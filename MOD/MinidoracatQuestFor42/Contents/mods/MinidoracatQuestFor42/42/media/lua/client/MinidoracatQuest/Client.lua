-- MinidoracatQuest/Client.lua: client-side state cache and transport (ARCHITECTURE.md sections 6 and 7).
--   receive(cmd, payload) is the single entry for server pushes: MP via OnServerCommand, SP via a direct call
--   from the server's Net.send (sendServerCommand is a no-op in SP).
--   Every command carries protocol + requestId; result/admin replies are matched by requestId, 10 s without a
--   reply delivers { ok = false, code = "NO_REPLY" } once.
--   defs(): effective definitions = shared Catalog defaults merged with the catalog push (overrides, custom
--   achievements, facade packs). Pure model helpers (board page state machine, exchange quote) live here so the
--   offline harness can test them without UI classes.

if isServer() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Catalog"

MinidoracatQuest = MinidoracatQuest or {}
local Q = MinidoracatQuest
local first = Q.Client == nil
local C = Q.Client or {}
Q.Client = C

C.TIMEOUT_MS = 10000        -- result / admin reply
C.BOARD_TIMEOUT_MS = 5000   -- board page error state (spec 12.4)
C.BOARD_GAP_MS = 600        -- server board cooldown is 0.5 s and drops silently
C.RECORDS_TIMEOUT_MS = 5000
C.RECORDS_TTL_MS = 30000    -- achievements page reuses records this fresh
C.HELLO_RETRY_MS = 10000
C.HELLO_TRIES = 6

C.pending = C.pending or {}
C.listeners = C.listeners or {}
C.boards = C.boards or {}
C.seq = C.seq or 0
C.skew = C.skew or 0

local function K() return Q.Contract or {} end

function C.log(msg)
    print("[MinidoracatQuestFor42] client: " .. tostring(msg))
end

-- ===== events (pages, dock, admin pages listen; same key replaces) =====
function C.on(event, key, fn)
    local l = C.listeners[event]
    if l == nil then
        l = {}
        C.listeners[event] = l
    end
    l[key] = fn
end

function C.off(event, key)
    if C.listeners[event] then C.listeners[event][key] = nil end
end

function C.emit(event, a, b)
    local l = C.listeners[event]
    if l == nil then return end
    for key, fn in pairs(l) do
        local ok, err = pcall(fn, a, b)
        if not ok then C.log("listener " .. tostring(event) .. "/" .. tostring(key) .. ": " .. tostring(err)) end
    end
end

-- ===== time =====
function C.now() return getTimestampMs() end
-- server wall clock estimate (state.now vs local clock at receipt)
function C.serverNow() return getTimestampMs() + C.skew end

-- ===== send =====
local function newRequestId()
    C.seq = C.seq + 1
    return string.format("mq-%08d-%d", math.floor(getTimestampMs() % 100000000), C.seq)
end

-- args.requestId already set = resend of the same request (server replays the cached result).
-- cb(reply) is called once: the matching result/admin push, or NO_REPLY after TIMEOUT_MS.
-- admin commands are always tracked so NO_REPLY also reaches the admin listeners.
function C.send(command, args, cb)
    local player = getSpecificPlayer(0)
    if player == nil then return nil end
    args = args or {}
    args.protocol = K().PROTOCOL
    local rid = args.requestId or newRequestId()
    args.requestId = rid
    if cb ~= nil or command == "admin" then
        C.pending[rid] = { command = command, args = args, sentAt = getTimestampMs(), cb = cb }
    end
    sendClientCommand(player, K().MODULE, command, args)
    return rid
end

function C.isPending(rid) return rid ~= nil and C.pending[rid] ~= nil end

local function deliver(p, reply)
    if p.cb == nil then return end
    local ok, err = pcall(p.cb, reply)
    if not ok then C.log("callback " .. tostring(p.command) .. ": " .. tostring(err)) end
end

function C.settle(reply)
    local rid = reply.requestId
    local p = rid ~= nil and C.pending[rid] or nil
    if p == nil then return end
    if reply.command ~= nil and reply.command ~= p.command then return end
    C.pending[rid] = nil
    deliver(p, reply)
end

function C.checkTimeouts(now)
    if C.lastCheck ~= nil and now - C.lastCheck < 500 then return end
    C.lastCheck = now
    local late = {}
    for rid, p in pairs(C.pending) do
        if now - p.sentAt >= C.TIMEOUT_MS then late[#late + 1] = rid end
    end
    for _, rid in ipairs(late) do
        local p = C.pending[rid]
        C.pending[rid] = nil
        local reply = { ok = false, code = "NO_REPLY", command = p.command, requestId = rid, op = p.args.op }
        deliver(p, reply)
        if p.command == "admin" then C.emit("admin", reply) end
    end
end

-- ===== hello =====
function C.hello()
    C.helloWaiting, C.helloAt, C.helloTries = true, getTimestampMs(), (C.helloTries or 0) + 1
    C.send("hello", {})
    C.emit("hello")
end

local function pumpHello(now)
    if not C.helloWaiting or now - (C.helloAt or 0) < C.HELLO_RETRY_MS then return end
    if (C.helloTries or 0) >= C.HELLO_TRIES then
        C.helloWaiting = false
        return
    end
    C.hello()
end

-- ===== effective definitions =====
local function isArray(t) return type(t) == "table" and t[1] ~= nil end

-- overrides win; arrays (tier lists, rotations) replace whole; maps merge per key
function C.merge(base, over)
    if type(over) ~= "table" or isArray(over) then
        if over == nil then return base end
        return over
    end
    if type(base) ~= "table" or isArray(base) then base = nil end
    local out = {}
    if base then for k, v in pairs(base) do out[k] = v end end
    for k, v in pairs(over) do out[k] = C.merge(base and base[k], v) end
    return out
end

-- insertion sort on strings (few custom ids; no table.sort in Kahlua)
local function sortedKeys(map)
    local keys = {}
    for k in pairs(map) do
        if type(k) == "string" then
            local i = #keys + 1
            while i > 1 and keys[i - 1] > k do
                keys[i] = keys[i - 1]
                i = i - 1
            end
            keys[i] = k
        end
    end
    return keys
end

-- difficulty multiplier on thresholds; same rule as server Achievements.lua A.scale (<100 round, else 2
-- significant digits, strictly increasing; stats with a ceiling keep their thresholds)
function C.scale(tiers, mult, stat)
    if stat ~= nil and not Q.Catalog.scalable(stat) then mult = 1 end
    local out, prev = {}, 0
    for i, v in ipairs(tiers) do
        local s = tonumber(v) or 0
        if mult ~= 1 then
            s = s * mult
            if s < 100 then
                s = math.floor(s + 0.5)
            else
                local mag = 1
                while s / mag >= 100 do mag = mag * 10 end
                s = math.floor(s / mag + 0.5) * mag
            end
        end
        if s <= prev then s = prev + 1 end
        out[i] = s
        prev = s
    end
    return out
end

local function achEntry(src, d, id, kind, mult)
    d = d or {}
    local base = d.tiers or src.tiers or {}
    local pts = Q.Catalog.fillPts(d.pts or src.pts or {}, src.pts, #base)
    return {
        id = id, kind = kind, cat = src.cat, stat = src.stat, base = base, tiers = C.scale(base, mult, src.stat),
        pts = pts, titles = d.titles or src.titles or {}, defTitles = src.titles,
        icon = src.icon, hidden = src.hidden == true, hint = src.hint, scope = src.scope,
        name = src.name, nameKey = src.nameKey, descKey = src.descKey,
    }
end

function C.invalidate() C._defs = nil end

function C.defs()
    if C._defs ~= nil then return C._defs end
    local Cat = Q.Catalog or {}
    local push = C.catalog or {}
    local cfg = C.merge(Cat.DEFAULTS or {}, type(push.overrides) == "table" and push.overrides or nil) or {}
    -- allAch: every achievement, the switched-off ones too (off = true): owned titles still name their source
    local d = { cfg = cfg, achievements = {}, achById = {}, allAch = {}, stats = {}, daily = {}, weekly = {}, boards = {},
        boardById = {}, packs = type(push.packs) == "table" and push.packs or {} }
    for id, s in pairs(Cat.stats or {}) do d.stats[id] = s end
    local function addAch(a, off)
        a.off = off or nil
        d.allAch[#d.allAch + 1] = a
        if not off and d.achById[a.id] == nil then
            d.achievements[#d.achievements + 1] = a
            d.achById[a.id] = a
        end
    end
    local mult = type(cfg.difficulty) == "table" and tonumber(cfg.difficulty.mult) or 1
    if mult == nil or mult <= 0 then mult = 1 end
    local cfgAch = type(cfg.achievements) == "table" and cfg.achievements or {}
    for _, a in ipairs(Cat.achievements or {}) do
        local o = cfgAch[a.id]
        addAch(achEntry(a, o, a.id, "builtin", mult), type(o) == "table" and o.enabled == false)
    end
    local custom = type(cfg.custom) == "table" and cfg.custom or {}
    for _, cid in ipairs(sortedKeys(custom)) do
        local c = custom[cid]
        if type(c) == "table" and type(c.tiers) == "table" and #c.tiers > 0 then
            local id = string.sub(cid, 1, 2) == "c:" and cid or ("c:" .. cid)
            addAch(achEntry(c, nil, id, "custom", mult), c.enabled == false)
        end
    end
    for _, pack in ipairs(d.packs) do
        if type(pack) == "table" then
            for sid, s in pairs(type(pack.stats) == "table" and pack.stats or {}) do d.stats[sid] = s end
            for _, a in ipairs(type(pack.achievements) == "table" and pack.achievements or {}) do
                if type(a) == "table" and type(a.id) == "string" then
                    local o = cfgAch[a.id]
                    addAch(achEntry(a, o, a.id, "pack", mult), type(o) == "table" and o.enabled == false)
                end
            end
            -- facade quests carry their own nameKey (API.lua stores it; Sync.catalog sends pack.quests)
            for _, q in ipairs(type(pack.quests) == "table" and pack.quests or {}) do
                if type(q) == "table" and type(q.tid) == "string" then d.daily[q.tid] = q end
            end
            for _, b in ipairs(type(pack.boards) == "table" and pack.boards or {}) do
                if type(b) == "table" and type(b.id) == "string" then d.boards[#d.boards + 1] = b end
            end
        end
    end
    for _, t in ipairs(Cat.daily or {}) do d.daily[t.tid] = t end
    for _, t in ipairs(Cat.weekly or {}) do d.weekly[t.tid] = t end
    local builtin = {}
    for _, b in ipairs(Cat.boards or {}) do builtin[#builtin + 1] = b end
    for _, b in ipairs(d.boards) do builtin[#builtin + 1] = b end
    d.boards = builtin
    for _, b in ipairs(d.boards) do d.boardById[b.id] = b end
    C._defs = d
    return d
end

-- ===== per-theme quest list (Settings) =====
-- Built from defs(): the shared Catalog ships to every client and the catalog push carries the whole overrides
-- tree to every player, so a server-side gate would hide nothing; config quests.playerList only decides who is
-- shown the list (admins always). A config apply re-sends catalog, which rebuilds it.
function C.questListShown()
    local s = C.state
    if s == nil then return false end
    local q = C.defs().cfg.quests
    return s.admin == true or (type(q) == "table" and q.playerList == true)
end

-- the lowest and highest target a template can roll: same rounding as server Quests.lua rollTarget
function C.targetRange(t, o, mult)
    local range = type(o) == "table" and type(o.target) == "table" and o.target or t.target
    local a = tonumber(range[1]) or 1
    local b = tonumber(range[2]) or a
    local step = t.step or 1
    local n = math.max(0, math.floor((b - a) / step))
    local function round(v)
        v = math.floor(v * mult / step + 0.5) * step
        return v < 1 and 1 or v
    end
    return round(a), round(a + step * n)
end

-- nil while hidden; else { { theme, daily = { { tid, lo, hi, pts, rare } }, weekly = { ... } } } in theme order,
-- enabled templates only (facade quests after the built-in ones), themes without any left out
function C.questList()
    if not C.questListShown() then return nil end
    local Cat, d = Q.Catalog or {}, C.defs()
    local cfg = d.cfg
    local mult = type(cfg.difficulty) == "table" and tonumber(cfg.difficulty.mult) or 1
    if mult == nil or mult <= 0 then mult = 1 end
    local byTheme = {}
    local function add(kind, t, pc)
        local o = type(pc.pool) == "table" and pc.pool[t.tid] or nil
        if type(t.theme) ~= "string" or (type(o) == "table" and o.enabled == false) then return end
        local pts = type(o) == "table" and tonumber(o.pts) or nil
        if pts == nil and kind == "daily" then pts = tonumber(t.pts) or (t.rare and pc.rarePts or pc.pts) end
        local lo, hi = C.targetRange(t, o, mult)
        local e = byTheme[t.theme] or { theme = t.theme, daily = {}, weekly = {} }
        byTheme[t.theme] = e
        e[kind][#e[kind] + 1] = { tid = t.tid, lo = lo, hi = hi, pts = pts or pc.pts or 0, rare = t.rare == true }
    end
    local dc = type(cfg.daily) == "table" and cfg.daily or {}
    local wc = type(cfg.weekly) == "table" and cfg.weekly or {}
    for _, t in ipairs(Cat.daily or {}) do add("daily", t, dc) end
    for _, pack in ipairs(d.packs) do
        for _, t in ipairs(type(pack) == "table" and type(pack.quests) == "table" and pack.quests or {}) do
            if type(t) == "table" and type(t.target) == "table" then add("daily", t, dc) end
        end
    end
    for _, t in ipairs(Cat.weekly or {}) do add("weekly", t, wc) end
    local out = {}
    for _, th in ipairs(Cat.themes or {}) do
        if byTheme[th] then out[#out + 1] = byTheme[th] end
    end
    return out
end

-- ===== delta merge =====
local function mergeInto(dst, src)
    for k, v in pairs(src) do dst[k] = v end
end

local function mergeQuests(list, delta)
    if type(list) ~= "table" or type(delta) ~= "table" then return end
    for i, q in pairs(delta) do
        local idx = tonumber(i)
        local target = idx and list[idx]
        if type(target) == "table" and type(q) == "table" then mergeInto(target, q) end
    end
end

function C.applyDelta(state, delta)
    for k, v in pairs(delta) do
        if k == "day" or k == "week" then
            local part = state[k]
            if type(part) == "table" and type(v) == "table" then
                -- delta.day = { [i] = { prog, state } } plus optional scalar fields (swaps, done, sharedDone)
                mergeQuests(part.quests, v)
                for f, fv in pairs(v) do
                    if type(f) == "string" then part[f] = fv end
                end
            end
        elseif (k == "goal" or k == "points") and type(v) == "table" and type(state[k]) == "table" then
            mergeInto(state[k], v)
        else
            state[k] = v
        end
    end
end

-- ===== board page state machine (spec 12.4): loading -> ready | empty | error; error/ready/empty -> loading =====
function C.boardKey(board, period) return tostring(board) .. "|" .. tostring(period) end

function C.board(board, period) return C.boards[C.boardKey(board, period)] end

function C.requestBoard(board, period)
    local key = C.boardKey(board, period)
    local e = C.boards[key]
    if e == nil then
        e = { board = board, period = period }
        C.boards[key] = e
    end
    e.status, e.sentAt, e.code = "loading", nil, nil
    C.boardQueue = e    -- latest ask wins; older queued asks are dropped
    C.pumpBoard(getTimestampMs())
    C.emit("board", key)
    return e
end

-- sentAt is set before sending: in SP the reply arrives inside sendClientCommand
function C.pumpBoard(now)
    local e = C.boardQueue
    if e == nil then return end
    if C.boardSentAt ~= nil and now - C.boardSentAt < C.BOARD_GAP_MS then return end
    C.boardQueue, C.boardSentAt, C.boardInFlight = nil, now, e
    if e.status == "loading" then e.sentAt = now end
    if C.send("board", { board = e.board, period = e.period }) == nil then
        C.boardQueue, C.boardSentAt, C.boardInFlight, e.sentAt = e, nil, nil, nil
    end
end

local function boardTimeouts(now)
    for key, e in pairs(C.boards) do
        if e.status == "loading" and e.sentAt ~= nil and now - e.sentAt >= C.BOARD_TIMEOUT_MS then
            e.status, e.code, e.sentAt = "error", "NO_REPLY", nil
            C.emit("board", key)
        end
    end
end

function C.onBoard(p)
    if p.board == nil or p.period == nil then return end
    local key = C.boardKey(p.board, p.period)
    local e = C.boards[key]
    if e == nil then
        e = { board = p.board, period = p.period }
        C.boards[key] = e
    end
    e.sentAt = nil
    if p.status ~= "ok" then
        e.status, e.code = "error", p.code or p.status
    else
        e.data = p
        local rows = type(p.rows) == "table" and p.rows or {}
        e.status = (#rows == 0 and p.me == nil) and "empty" or "ready"
    end
    C.emit("board", key)
end

-- ===== records (my records table, achievement progress) =====
function C.requestRecords(force)
    local now = getTimestampMs()
    if C.recordsSentAt ~= nil then return end
    if not force and C.records ~= nil and C.recordsAt ~= nil and now - C.recordsAt < C.RECORDS_TTL_MS then return end
    C.recordsSentAt, C.recordsError = now, nil
    if C.send("records", {}) == nil then
        C.recordsSentAt = nil
        return
    end
    C.emit("records")
end

-- queries answer with their own payload and send "result" only on failure
function C.onQueryFailed(p)
    if p.command == "board" then
        local e = C.boardInFlight
        if e ~= nil and e.status == "loading" then
            e.status, e.code, e.sentAt = "error", p.code, nil
            C.emit("board", C.boardKey(e.board, e.period))
        end
    elseif p.command == "records" then
        C.recordsSentAt, C.recordsError = nil, p.code or "INTERNAL"
        C.emit("records")
    elseif p.command == "hello" then
        C.helloCode = p.code
        C.emit("state")
    end
end

local function recordsTimeout(now)
    if C.recordsSentAt ~= nil and now - C.recordsSentAt >= C.RECORDS_TIMEOUT_MS then
        C.recordsSentAt, C.recordsError = nil, "NO_REPLY"
        C.emit("records")
    end
end

-- stat id -> { season, life, total }
function C.statRow(stat)
    return C.recordsBy ~= nil and C.recordsBy[stat] or nil
end

-- ===== exchange quote (spec 10.1, C33): all-in = min(balance, today's remaining) =====
-- returns { amount, coins, max, left, balance, after, min, rate, ok, reason }
function C.exchangeQuote(state, text)
    local ex = state and type(state.exchange) == "table" and state.exchange or {}
    local pts = state and type(state.points) == "table" and state.points or {}
    local balance = math.max(0, math.floor(tonumber(pts.balance) or 0))
    local left = math.max(0, math.floor((tonumber(ex.perDay) or 0) - (tonumber(ex.used) or 0)))
    local q = { balance = balance, left = left, max = math.min(balance, left), min = math.floor(tonumber(ex.min) or 0),
        rate = tonumber(ex.rate) or 1 }
    local amount = math.floor(tonumber(text) or 0)
    if amount < 0 then amount = 0 end
    q.amount, q.coins, q.after = amount, math.floor(amount * q.rate), balance - amount
    if not (ex.available == true and ex.enabled ~= false) then
        q.reason = "EXCHANGE_OFF"
    elseif amount <= 0 then
        q.reason = "EMPTY"
    elseif amount > balance then
        q.reason = "NOT_ENOUGH_POINTS"
    elseif amount > left then
        q.reason = "EXCHANGE_DAY_LIMIT"
    elseif amount < q.min then
        q.reason = "EXCHANGE_MIN"
    end
    q.ok = q.reason == nil
    return q
end

-- ===== tracker pins (state.pins: "d1".."d4" daily slots, "w1".."w3" weekly slots, "a:<achId>") =====
function C.pins() return C.state ~= nil and type(C.state.pins) == "table" and C.state.pins or {} end

function C.isPinned(id)
    for _, p in ipairs(C.pins()) do
        if p == id then return true end
    end
    return false
end

-- the mutation's fresh state redraws the pages and the panel; a refusal (TOO_MANY_PINS) shows why
function C.setPin(id, on)
    return C.send("pin", { id = id, on = on == true }, function(r)
        if not r.ok and Q.Draw ~= nil then Q.Draw.toast(Q.Draw.codeText(r.code), "", nil) end
    end)
end

-- ===== receive =====
local H = {}
C.handlers = H

function H.catalog(p)
    C.catalog = p
    C.invalidate()
    C.emit("catalog", p)
end

function H.state(p)
    C.state = p
    if type(p.now) == "number" then C.skew = p.now - getTimestampMs() end
    C.helloWaiting, C.helloTries, C.helloCode = false, 0, nil
    C.emit("state", p)
end

function H.delta(p)
    if C.state == nil then
        if not C.helloWaiting then C.hello() end
        return
    end
    C.applyDelta(C.state, p)
    C.emit("delta", p)
end

function H.result(p)
    if p.ok == false and (p.command == "board" or p.command == "records" or p.command == "hello") then
        C.onQueryFailed(p)
    end
    C.settle(p)
    C.emit("result", p)
end

function H.admin(p)
    p.command = p.command or "admin"
    C.settle(p)
    C.emit("admin", p)
end

function H.board(p) C.onBoard(p) end

function H.records(p)
    C.records, C.recordsAt, C.recordsSentAt, C.recordsError = p, getTimestampMs(), nil, nil
    local by = {}
    for _, r in ipairs(type(p.rows) == "table" and p.rows or {}) do
        if type(r) == "table" and r.stat ~= nil then by[r.stat] = r end
    end
    C.recordsBy = by
    if C.state ~= nil and type(p.points) == "table" then C.state.points = p.points end
    C.emit("records", p)
end

function H.toast(p) C.emit("toast", p) end

-- { full, map = { user -> titleId } } at hello, { u, t } on a change (Titles.lua keeps the table)
function H.titles(p) C.emit("titles", p) end

function C.receive(cmd, payload)
    if type(payload) ~= "table" then return end
    local h = H[cmd]
    if h == nil then return end
    local ok, err = pcall(h, payload)
    if not ok then C.log("receive " .. tostring(cmd) .. ": " .. tostring(err)) end
end

function C.onServerCommand(module, command, args)
    if module ~= K().MODULE then return end
    C.receive(command, args)
end

function C.onTick()
    local now = getTimestampMs()
    C.checkTimeouts(now)
    pumpHello(now)
    C.pumpBoard(now)
    boardTimeouts(now)
    recordsTimeout(now)
end

-- first hello waits for the first OnTick after OnGameStart (MP: sending inside OnGameStart takes the
-- SinglePlayerClient path; ARCHITECTURE 6.4)
local function firstTick()
    Events.OnTick.Remove(firstTick)
    C.started = true
    C.hello()
end

function C.onGameStart()
    C.state, C.catalog, C.records, C.recordsBy, C.recordsAt, C.recordsSentAt = nil, nil, nil, nil, nil, nil
    C.boards, C.boardQueue, C.boardSentAt, C.pending = {}, nil, nil, {}
    C.helloTries, C.started = 0, false
    C.invalidate()
    Events.OnTick.Add(firstTick)
end

-- respawn comes through OnCreatePlayer after the session has started
function C.onCreatePlayer(playerNum)
    if playerNum == 0 and C.started then
        C.helloTries = 0
        C.hello()
    end
end

if first then
    Events.OnServerCommand.Add(function(module, command, args) MinidoracatQuest.Client.onServerCommand(module, command, args) end)
    Events.OnTick.Add(function() MinidoracatQuest.Client.onTick() end)
    Events.OnGameStart.Add(function() MinidoracatQuest.Client.onGameStart() end)
    Events.OnCreatePlayer.Add(function(playerNum) MinidoracatQuest.Client.onCreatePlayer(playerNum) end)
end
