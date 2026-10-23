-- MinidoracatQuestFor42 - leaderboards: dirty + due scheduling, at most one rebuild per tick,
-- answers from the cache only (spec 12.3, A.12; contract 4.5, C1).
if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Audit"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"

local first = MQ.Boards == nil
local B = MQ.Boards or {}
MQ.Boards = B

B.TOP = 50
local DAY = 86400000

-- In memory only: key = boardId .. ":" .. period
B.cache = B.cache or {}       -- key -> { rows = { { u, v } }, rank = { [user] = r }, at, base = { [user] = r } }
B.state = B.state or {}       -- key -> { dirty, nextMs }
B.due = B.due or {}

local function code(name) return MQ.Contract.CODE[name] end

function B.defs()
    local out = {}
    for _, b in ipairs(MQ.Catalog.boards) do out[#out + 1] = b end
    local mods = {}
    for m in pairs(MQ.Packs or {}) do mods[#mods + 1] = m end
    MQ.Util.sort(mods, function(a, b) return a < b end)
    for _, m in ipairs(mods) do
        for _, b in ipairs(MQ.Packs[m].boards or {}) do out[#out + 1] = b end
    end
    return out
end

function B.def(id)
    for _, b in ipairs(B.defs()) do
        if b.id == id then return b end
    end
    return nil
end

function B.hasPeriod(def, period)
    for _, p in ipairs(def.periods or {}) do
        if p == period then return true end
    end
    return false
end

local function st(key)
    local s = B.state[key]
    if not s then
        s = { dirty = true, nextMs = 0 }
        B.state[key] = s
    end
    return s
end

-- stat -> { key... }; rebuilt when packs change (hot path: Stats listener)
local function index()
    local n = 0
    for _, pack in pairs(MQ.Packs or {}) do n = n + #(pack.boards or {}) end
    if B.idx and B.idxPacks == n then return B.idx end
    local idx = {}
    for _, b in ipairs(B.defs()) do
        idx[b.stat] = idx[b.stat] or {}
        for _, p in ipairs(b.periods) do
            local keys = idx[b.stat]
            keys[#keys + 1] = b.id .. ":" .. p
        end
    end
    B.idx, B.idxPacks = idx, n
    return idx
end

-- stat id or "@points"
function B.dirty(stat)
    local keys = index()[stat]
    if not keys then return end
    for i = 1, #keys do st(keys[i]).dirty = true end
end

function B.dirtyAll()
    for _, b in ipairs(B.defs()) do
        for _, p in ipairs(b.periods) do
            local s = st(b.id .. ":" .. p)
            s.dirty, s.nextMs = true, 0
        end
    end
end

local function value(acc, def, period, sno)
    if period == "season" and acc.sno ~= sno then return 0 end
    if def.stat == "@points" then return acc.points[period] or 0 end
    local t = acc[period]
    return t and t[def.stat] or 0
end

local function less(a, b)
    if a.v ~= b.v then return a.v > b.v end
    return a.u < b.u
end

function B.rebuild(id, period, now)
    local def = B.def(id)
    if not def then return nil end
    local key = id .. ":" .. period
    local cfg = MQ.Config.get().boards or {}
    local cutoff = now - (cfg.inactiveDays or 180) * DAY
    local sno = MQ.Store.root().season.no
    local rows = {}
    MQ.Store.each(function(user, acc)
        if not acc.hidden and (acc.seenMs or 0) >= cutoff then
            local v = value(acc, def, period, sno)
            if v > 0 then rows[#rows + 1] = { u = user, v = v } end
        end
    end)
    MQ.Util.sort(rows, less)
    local rank = {}
    for i, r in ipairs(rows) do rank[r.u] = i end
    local old = B.cache[key]
    local day = MQ.Clock.dayKey(now)
    local base, baseDay = old and old.base or {}, old and old.baseDay
    if old and baseDay ~= day then base, baseDay = old.rank, day end   -- ranks at the last day change
    local c = { rows = rows, rank = rank, at = now, base = base, baseDay = baseDay or day }
    B.cache[key] = c
    return c
end

-- Top user of a board right now (season freeze); rebuilt synchronously.
function B.leader(id, period)
    local c = B.rebuild(id, period, MQ.Clock.now())
    return c and c.rows[1] and c.rows[1].u or nil
end

B.lastSchedule = B.lastSchedule or 0

function B.tick(now)
    if not MQ.Store.ready() then return end
    if now - B.lastSchedule >= 1000 then
        B.lastSchedule = now
        local cfg = MQ.Config.get().boards or {}
        for _, b in ipairs(B.defs()) do
            for _, p in ipairs(b.periods) do
                local key = b.id .. ":" .. p
                local s = st(key)
                if s.dirty and now >= s.nextMs and not s.queued then
                    s.dirty, s.queued = false, true
                    s.nextMs = now + (p == "season" and (cfg.rebuildSeasonMs or 300000) or (cfg.rebuildTotalMs or 1800000))
                    B.due[#B.due + 1] = { id = b.id, period = p, key = key }
                end
            end
        end
    end
    local job = table.remove(B.due, 1)
    if job then
        st(job.key).queued = false
        B.rebuild(job.id, job.period, now)
    end
end

-- -> payload | nil, code
function B.page(boardId, period, user)
    local def = type(boardId) == "string" and B.def(boardId) or nil
    if not def or not B.hasPeriod(def, period) then return nil, code("BAD_BOARD") end
    local key = boardId .. ":" .. period
    local now = MQ.Clock.now()
    local c = B.cache[key] or B.rebuild(boardId, period, now)
    local season = MQ.Store.root().season
    local out = { board = boardId, period = period, status = "ok", season = { no = season.no, endsAt = season.endMs },
        rows = {}, count = #c.rows, at = c.at }
    for i = 1, math.min(B.TOP, #c.rows) do
        local r = c.rows[i]
        local acc = MQ.Store.account(r.u, false)
        local b = c.base[r.u]
        out.rows[i] = { r = i, n = not (acc and acc.anon) and r.u or nil, v = r.v, t = acc and acc.title or nil,
            d = b and b - i or nil }
    end
    local mine = user and c.rank[user]
    if mine then
        local b = c.base[user]
        out.me = { r = mine, v = c.rows[mine].v, d = b and b - mine or nil }
    end
    return out
end

-- Server calls this after `anon` / `title` succeed. Nothing to do: the cache keeps only users, values and ranks,
-- and page() reads each sent row's anon / title from the account, so the next board reply already shows the change.
function B.profileChanged(user) end

function B.setHidden(user, on, reason, actor)
    local acc = MQ.Store.account(user, false)
    if not acc then return false, code("NOT_FOUND") end
    if on then
        if type(reason) ~= "string" or reason == "" then return false, code("BAD_ARGS") end
        acc.hidden = { reason = reason, actor = actor, at = MQ.Clock.now() }
    else
        acc.hidden = nil
    end
    B.dirtyAll()
    MQ.EventLog.write("hide", user, { on = on, reason = reason, actor = actor })
    return true
end

-- ---------- registration ----------

MQ.Server.define("board", { kind = "query", fields = { board = "str", period = "str" }, cooldownMs = 2000,
    run = function(ctx)
        local page, c = B.page(ctx.args.board, ctx.args.period, ctx.user)
        if not page then return false, c end
        MQ.Net.send(ctx.player, "board", page)
        return true
    end })

MQ.Server.defineAdmin("board.hide", { kind = "mutation", fields = { user = "str", on = "bool", reason = "text?" },
    run = function(ctx) return B.setHidden(ctx.args.user, ctx.args.on, ctx.args.reason, ctx.user) end })

MQ.Stats.listen("boards", function(acc, user, stat) B.dirty(stat) end)

if first then
    Events.OnTickEvenPaused.Add(function() MQ.Boards.tick(getTimestampMs()) end)
end

return B
