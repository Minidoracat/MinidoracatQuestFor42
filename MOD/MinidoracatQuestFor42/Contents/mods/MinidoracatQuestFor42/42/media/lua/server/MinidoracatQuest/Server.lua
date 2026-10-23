-- MinidoracatQuest/Server.lua: command dispatch, start-up order, background tick, and the Core commands
-- (docs/ARCHITECTURE.md sections 5.7, 6.1, 6.2).
-- Dispatch is the MinidoracatSafehouse server/Server.lua S.define pipeline: module -> principal (unverified replies
-- rate-limited by claimed name) -> per-player rate limit (5 s / 20) -> command lookup -> per-command cooldown (drop,
-- no reply) -> field whitelist and types (protocol, requestId, unknown fields, NaN/Inf, lengths) -> admin gate ->
-- mutation result cache by requestId (60 s) -> run in pcall -> reply ok + code.
-- Additions: field type "json" (decoded server-side), Server.defineAdmin for ops under the "admin" command, admin by
-- sandbox AdminRoles (SP: always), and the SP direct call through Net.send.
-- Reply rules: player mutations get "result" then a fresh "state" on success; queries reply themselves through
-- Net.send and get a "result" only on failure; admin ops reply "admin" { op, ok, code, requestId, ... }.
-- Background work runs on OnTickEvenPaused (OnTick stops when the server is empty) with ms throttles.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Sandbox"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Identity"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Audit"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Sync"

local Q = MinidoracatQuest
local first = Q.Server == nil
local S = Q.Server or {}
Q.Server = S
local C, U = Q.Contract, Q.Util
local CODE, LIMIT = C.CODE, C.LIMIT

S.commands = S.commands or {}
S.adminOps = S.adminOps or {}
S.cache = S.cache or {}        -- user -> { map = { key -> { at, result } }, order = { key } }
S.rate = S.rate or {}          -- user -> { start, n }
S.cooldown = S.cooldown or {}  -- user -> { [command] = ms }
S.unverified = S.unverified or {}

-- spec = { kind = "query" | "mutation", fields = { f = "type" | "type?" }, admin = bool, cooldownMs, run(ctx) }
-- run returns true, data | false, code, data
function S.define(name, spec)
    spec.fields = spec.fields or {}
    S.commands[name] = spec
end

-- an op under the "admin" command; always needs admin; fields exclude "op"
function S.defineAdmin(op, spec)
    spec.fields = spec.fields or {}
    spec.admin = true
    S.adminOps[op] = spec
end

-- ===== field types =====

local function plainString(v, max)
    return type(v) == "string" and #v <= max and not string.find(v, "%c")
end

S.TYPES = {
    int = function(v) return C.isInt(v) and math.abs(v) <= 1e15 end,
    num = function(v) return C.isFinite(v) end,
    bool = function(v) return type(v) == "boolean" end,
    str = function(v) return plainString(v, LIMIT.STR) end,
    text = function(v) return plainString(v, LIMIT.TEXT) end,
    json = function(v) return type(v) == "string" and #v <= LIMIT.JSON_BYTES end,
}

-- returns nil, decodedArgs | code
local function validate(spec, args, extra)
    if type(args) ~= "table" then return CODE.BAD_ARGS end
    if args.protocol ~= C.PROTOCOL then return CODE.PROTOCOL_MISMATCH end
    if spec.kind == "mutation" or args.requestId ~= nil then
        if not C.validRequestId(args.requestId) then return CODE.BAD_ARGS end
    end
    local out = {}
    for k, v in pairs(args) do
        if k ~= "protocol" and k ~= "requestId" and not (extra and extra[k]) then
            local t = type(k) == "string" and spec.fields[k] or nil
            if t == nil then return CODE.BAD_ARGS end
            local name = string.gsub(t, "%?$", "")
            local check = S.TYPES[name]
            if check == nil or not check(v) then return CODE.BAD_ARGS end
            if name == "json" then
                local decoded = U.decode(v)
                if decoded == nil then return CODE.BAD_ARGS end
                v = decoded
            end
            out[k] = v
        end
    end
    for k, t in pairs(spec.fields) do
        if string.sub(t, -1) ~= "?" and args[k] == nil then return CODE.BAD_ARGS end
    end
    return nil, out
end

-- ===== rate limit, cooldown, result cache (Safehouse Server.lua) =====

local function rateLimited(who, now)
    local r = S.rate[who]
    if r == nil or now - r.start >= LIMIT.RATE_WINDOW_MS then
        r = { start = now, n = 0 }
        S.rate[who] = r
    end
    r.n = r.n + 1
    return r.n > LIMIT.RATE_MAX
end

local function coolingDown(who, key, ms, now)
    local per = S.cooldown[who]
    if per == nil then
        per = {}
        S.cooldown[who] = per
    end
    local last = per[key]
    if last ~= nil and now - last < ms then return true end
    per[key] = now
    return false
end

local function cachedResult(who, key, now)
    local c = S.cache[who]
    local hit = c and c.map[key]
    if hit == nil or now - hit.at > LIMIT.CACHE_TTL_MS then return nil end
    return hit.result
end

local function storeResult(who, key, result, now)
    local c = S.cache[who]
    if c == nil then
        c = { map = {}, order = {} }
        S.cache[who] = c
    end
    if c.map[key] == nil then c.order[#c.order + 1] = key end
    c.map[key] = { at = now, result = result }
    while #c.order > LIMIT.CACHE_PER_ACTOR do c.map[table.remove(c.order, 1)] = nil end
end

local function pruneCaches(now)
    for who, c in pairs(S.cache) do
        local keep = {}
        for _, key in ipairs(c.order) do
            local hit = c.map[key]
            if hit ~= nil and now - hit.at <= LIMIT.CACHE_TTL_MS then keep[#keep + 1] = key else c.map[key] = nil end
        end
        c.order = keep
        if #keep == 0 then S.cache[who] = nil end
    end
    S.rate, S.cooldown = {}, {}
    for name, at in pairs(S.unverified) do
        if now - at > 60000 then S.unverified[name] = nil end
    end
end

-- ===== admin =====

-- SP: always. MP: role name in sandbox AdminRoles; getRole() is nil in SP and may be nil on odd seats.
function S.isAdmin(player)
    if not isServer() then return true end
    if player == nil then return false end
    local ok, name = pcall(function()
        local role = player:getRole()
        if role == nil then return nil end
        return role:getName()
    end)
    if not ok or type(name) ~= "string" then return false end
    return Q.Sandbox.adminRoles()[name] == true
end

-- ===== replies =====

local function merged(base, data)
    if type(data) == "table" then
        for k, v in pairs(data) do
            if base[k] == nil then base[k] = v end
        end
    end
    return base
end

local function sendResult(player, command, requestId, res)
    res.command, res.requestId = command, requestId
    Q.Net.send(player, "result", res)
end

local function unverified(player, command, requestId, now)
    local name = Q.Identity.claimedName(player)
    if rateLimited("?" .. name, now) then return end
    local key = (type(command) == "string" and S.commands[command] ~= nil) and command or "UNKNOWN_COMMAND"
    Q.Audit.deny(name, key, CODE.IDENTITY_UNVERIFIED)
    local last = S.unverified[name]
    if last ~= nil and now - last < 60000 then return end
    S.unverified[name] = now
    sendResult(player, key, requestId, { ok = false, code = CODE.IDENTITY_UNVERIFIED })
end

-- spec, key, extraFields for a command (admin resolves its op)
local function lookup(command, args)
    if command == "admin" then
        local op = type(args) == "table" and args.op or nil
        local spec = type(op) == "string" and S.adminOps[op] or nil
        if spec == nil then return nil end
        return spec, "admin:" .. op, { op = true }, op
    end
    local spec = type(command) == "string" and S.commands[command] or nil
    return spec, command, nil, nil
end

local function runSpec(spec, ctx)
    local ok, a, b, c = pcall(spec.run, ctx)
    if not ok then
        U.log((ctx.op or ctx.command) .. " failed: " .. tostring(a))
        Q.Audit.throttled("RUN|" .. tostring(ctx.op or ctx.command), 60000, "INTERNAL",
            { actor = ctx.user, detail = tostring(a) }, ctx.now)
        return false, CODE.INTERNAL
    end
    return a, b, c
end

function S.onClientCommand(module, command, player, args)
    if module ~= C.MODULE then return end
    local now = getTimestampMs()
    local requestId = type(args) == "table" and C.validRequestId(args.requestId) and args.requestId or nil
    local user = Q.Identity.principal(player)
    if user == nil then return unverified(player, command, requestId, now) end
    local spec, key, extra, op = lookup(command, args)
    if rateLimited(user, now) then
        Q.Audit.deny(user, key or "?", CODE.RATE_LIMITED)
        if spec ~= nil and spec.kind == "mutation" then
            sendResult(player, command, requestId, { ok = false, code = CODE.RATE_LIMITED })
        end
        return
    end
    local function reply(res)
        if op ~= nil then
            res.op, res.requestId = op, requestId
            Q.Net.send(player, "admin", res)
        else
            sendResult(player, command, requestId, res)
        end
    end
    if spec == nil then
        Q.Audit.deny(user, "UNKNOWN_COMMAND", CODE.BAD_ARGS)
        return reply({ ok = false, code = CODE.BAD_ARGS })
    end
    if coolingDown(user, key, spec.cooldownMs or LIMIT.COOLDOWN_MS, now) then return end
    local bad, fields = validate(spec, args, extra)
    if bad then
        Q.Audit.deny(user, key, bad)
        local res = { ok = false, code = bad }
        if bad == CODE.PROTOCOL_MISMATCH then res.serverProtocol = C.PROTOCOL end
        return reply(res)
    end
    local admin = S.isAdmin(player)
    if spec.admin and not admin then
        Q.Audit.deny(user, key, CODE.FORBIDDEN)
        return reply({ ok = false, code = CODE.FORBIDDEN })
    end
    local mutation = spec.kind == "mutation"
    local cacheKey = mutation and (key .. "|" .. requestId) or nil
    if mutation then
        local cached = cachedResult(user, cacheKey, now)
        if cached ~= nil then
            cached.replay = true
            return reply(cached)
        end
    end
    local res
    if not S.ready or not Q.Store.ready() or (mutation and Q.Store.readOnly) then
        res = { ok = false, code = CODE.NOT_READY }
    else
        local ctx = { player = player, user = user, args = fields, now = now, admin = admin, command = command, op = op }
        local ok, a, b = runSpec(spec, ctx)
        if ok == true then
            if not mutation and op == nil then return end   -- queries reply on their own
            res = merged({ ok = true, code = CODE.OK }, a)
            if mutation and op ~= nil then
                Q.Audit.add("admin", user, nil, { op = op })
                Q.EventLog.write("admin", user, { op = op })
            end
        else
            res = merged({ ok = false, code = a or CODE.INTERNAL }, b)
        end
    end
    if not res.ok then Q.Audit.deny(user, key, res.code) end
    if mutation then storeResult(user, cacheKey, res, now) end
    reply(res)
    if res.ok and mutation and op == nil then
        local acc = Q.Store.account(user, false)
        if acc ~= nil then Q.Net.send(player, "state", Q.Sync.state(user, acc)) end
    end
end

-- ===== lifecycle and background tick =====

function S.onInitGlobalModData()
    Q.Store.init()
    Q.Identity.load()
    S.ready = true
    S.lastMinute = getTimestampMs()
end

function S.onServerStarted()
    Q.Net.up = true
end

-- watchers that went offline stop receiving deltas
local function pruneWatchers()
    for user in pairs(Q.Sync.watchers) do
        if Q.Net.playerOf(user) == nil then Q.Sync.forget(user) end
    end
end

function S.onTick()
    if not S.ready then return end
    local now = getTimestampMs()
    Q.Identity.tick(now)
    Q.Sync.tick(now)
    Q.EventLog.tick(now)
    if S.lastMinute == nil or now - S.lastMinute >= 60000 then
        S.lastMinute = now
        Q.Audit.flush()
        Q.Audit.prune(now)
        Q.Stats.prune(now)
        Q.Sync.prune(now)
        pruneCaches(now)
        pruneWatchers()
    end
end

-- ===== player commands (section 6.1) =====

local function safeCall(name, fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then
        Q.Audit.throttled("CALL|" .. name, 60000, "INTERNAL", { detail = name .. ": " .. tostring(err) }, getTimestampMs())
    end
end

S.define("hello", { kind = "query", run = function(ctx)
    local acc = Q.Store.account(ctx.user, true)
    if acc == nil then return false, CODE.NOT_READY end
    Q.Store.touch(ctx.user, acc)
    if Q.Quests then safeCall("Quests.ensure", Q.Quests.ensure, acc, ctx.user, ctx.now) end
    if Q.Import then safeCall("Import.baseline", Q.Import.baseline, acc, ctx.user, ctx.player) end
    Q.Net.send(ctx.player, "catalog", Q.Sync.catalog())
    Q.Net.send(ctx.player, "state", Q.Sync.state(ctx.user, acc))
    return true
end })

S.define("watch", { kind = "query", fields = { on = "bool" }, run = function(ctx)
    Q.Sync.watch(ctx.user, ctx.args.on)
    if ctx.args.on then
        local acc = Q.Store.account(ctx.user, false)
        if acc == nil then return false, CODE.NOT_FOUND end
        Q.Net.send(ctx.player, "state", Q.Sync.state(ctx.user, acc))
    end
    return true
end })

local function accountOf(ctx)
    return Q.Store.account(ctx.user, false)
end

S.define("seen", { kind = "mutation", run = function(ctx)
    local acc = accountOf(ctx)
    if acc == nil then return false, CODE.NOT_FOUND end
    acc.unseen = 0
    return true
end })

S.define("title", { kind = "mutation", fields = { id = "str?" }, run = function(ctx)
    local acc = accountOf(ctx)
    if acc == nil then return false, CODE.NOT_FOUND end
    local id = ctx.args.id
    if id == nil or id == "" then
        acc.title = nil
        return true
    end
    if not (acc.titles and acc.titles[id] == true) then return false, CODE.TITLE_LOCKED end
    acc.title = id
    if Q.Boards and Q.Boards.profileChanged then safeCall("Boards.profileChanged", Q.Boards.profileChanged, ctx.user) end
    return true
end })

S.define("anon", { kind = "mutation", fields = { on = "bool" }, run = function(ctx)
    local acc = accountOf(ctx)
    if acc == nil then return false, CODE.NOT_FOUND end
    acc.anon = ctx.args.on
    if Q.Boards and Q.Boards.profileChanged then safeCall("Boards.profileChanged", Q.Boards.profileChanged, ctx.user) end
    return true
end })

S.RECORD_ROWS = 400

S.define("records", { kind = "query", run = function(ctx)
    local acc = accountOf(ctx)
    if acc == nil then return false, CODE.NOT_FOUND end
    local seen, ids = {}, {}
    for _, scope in ipairs({ acc.total, acc.life, acc.season }) do
        for stat, v in pairs(scope) do
            if v ~= 0 and not seen[stat] then seen[stat] = true; ids[#ids + 1] = stat end
        end
    end
    U.sort(ids, function(a, b) return a < b end)
    local rows = {}
    for i = 1, math.min(#ids, S.RECORD_ROWS) do
        local s = ids[i]
        rows[i] = { stat = s, season = acc.season[s] or 0, life = acc.life[s] or 0, total = acc.total[s] or 0 }
    end
    local p = acc.points
    Q.Net.send(ctx.player, "records", { rows = rows, points = { season = p.season, total = p.total, balance = p.balance } })
    return true
end })

-- ===== admin ops (section 6.2) =====

S.defineAdmin("cfg.get", { kind = "query", run = function()
    local root = Q.Store.root()
    return true, { overrides = Q.Config.overrides(), rev = root.config.rev, history = Q.Config.historyRows() }
end })

S.defineAdmin("cfg.preview", { kind = "query", fields = { changes = "json" }, run = function(ctx)
    local ok, rows, detail = Q.Config.preview(ctx.args.changes)
    if not ok then return false, rows, { detail = detail } end
    return true, { rows = rows }
end })

S.defineAdmin("cfg.apply", { kind = "mutation", fields = { changes = "json", summary = "text" }, run = function(ctx)
    local ok, id, rev = Q.Config.apply(ctx.args.changes, ctx.args.summary, ctx.user)
    if not ok then return false, id, { detail = rev } end
    return true, { historyId = id, rev = rev }
end })

S.defineAdmin("cfg.undo", { kind = "mutation", fields = { historyId = "int" }, run = function(ctx)
    local ok, id, rev = Q.Config.undo(ctx.args.historyId, ctx.user)
    if not ok then return false, id end
    return true, { historyId = id, rev = rev }
end })

S.defineAdmin("cfg.export", { kind = "mutation", run = function()
    local ok, file = Q.Config.export()
    if not ok then return false, file end
    return true, { file = file }
end })

S.defineAdmin("cfg.import", { kind = "query", run = function()
    local ok, changes, rows = Q.Config.import()
    if not ok then return false, changes, { detail = rows } end
    return true, { changes = changes, rows = rows }
end })

S.defineAdmin("acct.view", { kind = "query", fields = { user = "str" }, run = function(ctx)
    local acc = Q.Store.account(ctx.args.user, false)
    if acc == nil then return false, CODE.NOT_FOUND end
    local n = 0
    for _ in pairs(acc.achv) do n = n + 1 end
    local p = acc.points
    return true, { user = ctx.args.user, points = { season = p.season, total = p.total, balance = p.balance },
        achvCount = n, anomalies = acc.anomalies or 0, hidden = acc.hidden, achv = acc.achv }
end })

S.defineAdmin("anom.list", { kind = "query", fields = { days = "int" }, run = function(ctx)
    local days = ctx.args.days
    if days < 1 or days > 30 then return false, CODE.BAD_ARGS end
    local since = ctx.now - days * 86400000
    local items = Q.Audit.recent(function(it) return it.kind == "over" and it.at >= since end, LIMIT.ANOMALY_ROWS)
    local rows = {}
    for i, it in ipairs(items) do
        local d = it.detail or {}
        rows[i] = { at = it.at, user = it.user, stat = d.stat, n = d.n, ceil = d.ceil }
    end
    return true, { rows = rows }
end })

S.defineAdmin("towns.here", { kind = "query", run = function(ctx)
    local p = ctx.player
    local x, y, z = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local town = nil
    if Q.Towns and Q.Towns.at then town = Q.Towns.at(x, y) end
    return true, { x = x, y = y, z = z, town = town }
end })

if first then
    Events.OnInitGlobalModData.Add(function(isNewGame) MinidoracatQuest.Server.onInitGlobalModData(isNewGame) end)
    Events.OnServerStarted.Add(function() MinidoracatQuest.Server.onServerStarted() end)
    Events.OnClientCommand.Add(function(module, command, player, args)
        MinidoracatQuest.Server.onClientCommand(module, command, player, args)
    end)
    Events.OnTickEvenPaused.Add(function() MinidoracatQuest.Server.onTick() end)
end
