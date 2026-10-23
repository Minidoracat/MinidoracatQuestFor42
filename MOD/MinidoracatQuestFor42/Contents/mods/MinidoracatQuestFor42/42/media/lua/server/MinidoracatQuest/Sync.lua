-- MinidoracatQuest/Sync.lua: state / catalog / delta payloads and throttled pushes (docs/ARCHITECTURE.md 5.6, 6.3).
-- Systems-owned state parts (day, week, goal, streak, newbie, season, exchange, events) come from providers:
-- Sync.provider(part, fn) with fn(acc, user, now) -> value; parts without a provider are left out.
-- Pushes: players with the window open (watch) get at most one delta per second; parts other than
-- day/week/goal/points/unseen send a full state. Players without the window only get unseen changes (Dock badge).
-- Achievement toasts to one player within 2 s merge into one (C28); server-wide notices are capped per achiever.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Net"

local Q = MinidoracatQuest
local Y = Q.Sync or {}
Q.Sync = Y
local C, U = Q.Contract, Q.Util

Y.PARTS = { "day", "week", "goal", "streak", "newbie", "season", "exchange", "events" }
Y.DELTA_PARTS = { day = true, week = true, goal = true, points = true, unseen = true }
Y.providers = Y.providers or {}
Y.dirtyMap = Y.dirtyMap or {}    -- user -> { [part] = true }
Y.watchers = Y.watchers or {}    -- user -> true
Y.sentUnseen = Y.sentUnseen or {} -- user -> last unseen pushed to a closed window
Y.achvQueue = Y.achvQueue or {}  -- user -> { at, items = { { id, tier, pts } } }
Y.bcast = Y.bcast or {}          -- achiever -> { minute, n }

function Y.provider(part, fn)
    Y.providers[part] = fn
end

local function adminOf(user)
    local p = Q.Net.playerOf(user)
    return p ~= nil and Q.Server ~= nil and Q.Server.isAdmin(p)
end

function Y.state(user, acc)
    local K = Q.Clock
    local now = K.now()
    local titles = {}
    for id, on in pairs(acc.titles or {}) do if on then titles[#titles + 1] = id end end
    U.sort(titles, function(a, b) return a < b end)
    local st = {
        v = 1, user = user, admin = adminOf(user), now = now,
        dayKey = K.dayKey(now), resetAt = K.nextResetMs(now), weekKey = K.weekKey(now), weekResetAt = K.weekResetMs(now),
        points = { season = acc.points.season, total = acc.points.total, balance = acc.points.balance },
        achv = acc.achv, titles = titles, title = acc.title, prefs = acc.prefs, anon = acc.anon == true,
        unseen = acc.unseen or 0,
    }
    for _, part in ipairs(Y.PARTS) do
        local fn = Y.providers[part]
        if fn then
            local ok, v = pcall(fn, acc, user, now)
            if ok then st[part] = v
            else Q.Audit.throttled("PROVIDER|" .. part, 60000, "INTERNAL", { detail = part .. ": " .. tostring(v) }, now) end
        end
    end
    return st
end

function Y.catalog()
    local ov = Q.Config.overrides()
    local packs = {}
    for modId, p in pairs(Q.Packs or {}) do
        packs[#packs + 1] = { modId = modId, stats = p.stats, achievements = p.achievements, quests = p.quests, boards = p.boards }
    end
    U.sort(packs, function(a, b) return a.modId < b.modId end)
    local towns = nil
    if Q.Towns and Q.Towns.list then
        local ok, list = pcall(Q.Towns.list)
        if ok then towns = list end
    end
    local root = Q.Store.root()
    return { rev = root and root.config.rev or 0, overrides = ov, custom = ov.custom or {}, packs = packs, towns = towns }
end

-- user = nil: every player with the window open (others get a full state on their next watch/hello)
function Y.dirty(user, part)
    if user == nil then
        for u in pairs(Y.watchers) do Y.dirty(u, part) end
        return
    end
    local d = Y.dirtyMap[user]
    if d == nil then
        d = {}
        Y.dirtyMap[user] = d
    end
    d[part or "all"] = true
end

function Y.watch(user, on)
    Y.watchers[user] = on and true or nil
end

local function questDelta(list)
    local out = {}
    -- ptsNow only changes on completion (the payout); event starts / ends send a full state (Quests.watchEvents)
    for i, q in ipairs(list or {}) do out[i] = { prog = q.prog, state = q.state, ptsNow = q.got } end
    return out
end

local function push(user, parts)
    local acc = Q.Store.account(user, false)
    if acc == nil then return end
    if not Y.watchers[user] then
        local unseen = acc.unseen or 0
        if Y.sentUnseen[user] ~= unseen then
            Y.sentUnseen[user] = unseen
            Q.Net.toUser(user, "delta", { unseen = unseen })
        end
        return
    end
    for part in pairs(parts) do
        if not Y.DELTA_PARTS[part] then
            Q.Net.toUser(user, "state", Y.state(user, acc))
            return
        end
    end
    local d = { unseen = acc.unseen or 0 }
    Y.sentUnseen[user] = d.unseen
    if parts.day then d.day = questDelta(acc.day and acc.day.quests) end
    if parts.week then d.week = questDelta(acc.week and acc.week.quests) end
    if parts.goal then
        local g = Q.Store.root().goal or {}
        d.goal = { progress = g.progress, reached = g.reached }
    end
    if parts.points then d.points = { season = acc.points.season, total = acc.points.total, balance = acc.points.balance } end
    Q.Net.toUser(user, "delta", d)
end

local function flushAchv(now)
    for user, q in pairs(Y.achvQueue) do
        if now - q.at >= C.LIMIT.TOAST_MERGE_MS then
            Y.achvQueue[user] = nil
            local items = q.items
            if #items == 1 then
                Q.Net.toUser(user, "toast", { kind = "achv", id = items[1].id, tier = items[1].tier, pts = items[1].pts })
            else
                local ids = {}
                for i = 1, math.min(3, #items) do ids[i] = items[i].id end
                Q.Net.toUser(user, "toast", { kind = "achvMany", ids = ids, n = #items })
            end
        end
    end
end

function Y.tick(now)
    flushAchv(now)
    if Y.lastDelta ~= nil and now - Y.lastDelta < C.LIMIT.DELTA_MS then return end
    Y.lastDelta = now
    local map = Y.dirtyMap
    Y.dirtyMap = {}
    for user, parts in pairs(map) do push(user, parts) end
end

-- t = { kind, ... } (section 6.3). "achv" toasts merge per player for 2 s.
function Y.toast(user, t)
    if user == nil or type(t) ~= "table" then return end
    if t.kind == "achv" then
        local q = Y.achvQueue[user]
        if q == nil then
            q = { at = Q.Clock.now(), items = {} }
            Y.achvQueue[user] = q
        end
        q.items[#q.items + 1] = { id = t.id, tier = t.tier, pts = t.pts }
        return
    end
    Q.Net.toUser(user, "toast", t)
end

-- Server-wide notice; at most broadcast.perMinute per achiever per minute. achiever defaults to t.who
-- (pass the real user when t.who is nil because the player is anonymous).
function Y.broadcastToast(t, achiever)
    local cfg = Q.Config.get().broadcast or {}
    if cfg.enabled == false then return false end
    local cap = cfg.perMinute or 1
    local key = achiever or t.who
    if key ~= nil then
        local minute = math.floor(Q.Clock.now() / 60000)
        local b = Y.bcast[key]
        if b == nil or b.minute ~= minute then
            b = { minute = minute, n = 0 }
            Y.bcast[key] = b
        end
        if b.n >= cap then return false end
        b.n = b.n + 1
    end
    Q.Net.broadcast("toast", t)
    return true
end

function Y.catalogChanged()
    Q.Net.broadcast("catalog", Y.catalog())
end

function Y.forget(user)
    Y.watchers[user], Y.sentUnseen[user], Y.dirtyMap[user], Y.achvQueue[user] = nil, nil, nil, nil
end

function Y.prune(now)
    local minute = math.floor(now / 60000)
    for k, b in pairs(Y.bcast) do if b.minute < minute then Y.bcast[k] = nil end end
end
