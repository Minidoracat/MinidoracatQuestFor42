-- MinidoracatQuest/Sync.lua: state / catalog / delta payloads and throttled pushes (docs/ARCHITECTURE.md 5.6, 6.3).
-- Systems-owned state parts (day, week, goal, streak, newbie, season, exchange, events, hordes) come from providers:
-- Sync.provider(part, fn) with fn(acc, user, now) -> value; parts without a provider are left out.
-- Pushes: players with the window open (watch) get at most one delta per second; parts other than
-- day/week/goal/points/unseen/trk/pins/hordes send a full state. Players with only the tracker panel on (track) get
-- the progress of what they pinned in the same deltas (day/week lists with a pinned slot, trk for pinned achievements,
-- pins) and the horde part; "all" / "events" still send them a full state. Players with neither only get unseen
-- changes (Dock badge).
-- Pins: "d1".."d4" today's daily slots, "w1".."w3" this week's slots, "a:<achId>"; at most LIMIT.MAX_PINS, saved on
-- the account; quest pins go at the reset (or a swap of that slot), an achievement pin when its last tier unlocks.
-- Titles: { full, map = { user -> titleId } } of the online players at hello, then { u, t } to everyone on a change
-- (client Titles.lua: after the name in chat and on a line over the head).
-- Achievement toasts to one player within 2 s merge into one (C28); server-wide notices are capped per achiever.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Stats"

local Q = MinidoracatQuest
local Y = Q.Sync or {}
Q.Sync = Y
local C, U = Q.Contract, Q.Util

Y.PARTS = { "day", "week", "goal", "streak", "newbie", "season", "exchange", "events", "hordes" }
Y.DELTA_PARTS = { day = true, week = true, goal = true, points = true, unseen = true, trk = true, pins = true, hordes = true }
Y.providers = Y.providers or {}
Y.dirtyMap = Y.dirtyMap or {}    -- user -> { [part] = true }
Y.watchers = Y.watchers or {}    -- user -> true
Y.trackers = Y.trackers or {}    -- user -> true (tracker panel on)
Y.pinStats = Y.pinStats or {}    -- user -> { [stat] = true } of the pinned achievements
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
        achv = acc.achv, titles = titles, titleAt = acc.titleAt, title = acc.title, prefs = acc.prefs, anon = acc.anon == true,
        unseen = acc.unseen or 0, pins = acc.pins or {}, trk = Y.trk(acc),
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

-- user = nil: every player with the window or the tracker on (others get a full state on their next watch/hello)
function Y.dirty(user, part)
    if user == nil then
        for u in pairs(Y.watchers) do Y.dirty(u, part) end
        for u in pairs(Y.trackers) do
            if not Y.watchers[u] then Y.dirty(u, part) end
        end
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

-- ---------- tracker panel: pins ----------

local function achDef(id)
    local A = Q.Achievements
    return A ~= nil and A.get ~= nil and A.get(id) or nil
end

-- the Stats listener below only marks "trk" for these stats
function Y.refreshPinStats(user, acc)
    local s = nil
    for _, id in ipairs(acc and acc.pins or {}) do
        local d = string.sub(id, 1, 2) == "a:" and achDef(string.sub(id, 3)) or nil
        if d ~= nil then
            s = s or {}
            s[d.stat] = true
        end
    end
    Y.pinStats[user] = s
end

function Y.track(user, on)
    Y.trackers[user] = on and true or nil
    Y.refreshPinStats(user, Q.Store.account(user, false))
end

-- today's / this week's active quest slot, or an achievement with a tier left (hidden ones stay secret)
function Y.pinValid(acc, id)
    local n = tonumber(string.match(id, "^d(%d)$"))
    if n ~= nil then
        local q = acc.day and acc.day.quests and acc.day.quests[n]
        return type(q) == "table" and q.state == "active"
    end
    n = tonumber(string.match(id, "^w(%d)$"))
    if n ~= nil then
        local q = acc.week and acc.week.quests and acc.week.quests[n]
        return type(q) == "table" and q.state == "active"
    end
    local aid = string.match(id, "^a:(.+)$")
    local d = aid and achDef(aid) or nil
    return d ~= nil and not d.hidden and (acc.achv[aid] or 0) < #d.tiers
end

-- true | false, code. Removing always works; adding checks the target and the limit.
function Y.pin(acc, user, id, on)
    local pins = acc.pins or {}
    local at = nil
    for i, p in ipairs(pins) do
        if p == id then at = i end
    end
    if not on then
        if at ~= nil then table.remove(pins, at) end
    elseif at == nil then
        if not Y.pinValid(acc, id) then return false, C.CODE.BAD_ARGS end
        if #pins >= C.LIMIT.MAX_PINS then return false, C.CODE.TOO_MANY_PINS end
        pins[#pins + 1] = id
    end
    acc.pins = pins
    Y.refreshPinStats(user, acc)
    return true
end

-- drops the pin id, or with prefix every pin starting with id ("d" at the daily reset)
function Y.unpin(acc, user, id, prefix)
    if type(acc.pins) ~= "table" then return end
    local kept, changed = {}, false
    for _, p in ipairs(acc.pins) do
        local hit
        if prefix then hit = string.sub(p, 1, #id) == id else hit = p == id end
        if hit then changed = true else kept[#kept + 1] = p end
    end
    if not changed then return end
    acc.pins = kept
    Y.refreshPinStats(user, acc)
    Y.dirty(user, "pins")
end

local function pinned(acc, prefix)
    for _, p in ipairs(acc.pins or {}) do
        if string.sub(p, 1, 1) == prefix then return true end
    end
    return false
end

-- { [achId] = { t = unlocked tier, v = value } } for the pinned achievements; the value is what the
-- achievements page shows (this life for scope "life", else the lifetime total)
function Y.trk(acc)
    local out = {}
    for _, id in ipairs(acc.pins or {}) do
        local aid = string.sub(id, 1, 2) == "a:" and string.sub(id, 3) or nil
        local d = aid and achDef(aid) or nil
        if d ~= nil then
            local scope = (d.scope == "life" and acc.life or acc.total) or {}
            out[aid] = { t = acc.achv[aid] or 0, v = scope[d.stat] or 0 }
        end
    end
    return out
end

local function questDelta(list)
    local out = {}
    -- ptsNow only changes on completion (the payout); event starts / ends send a full state (Quests.watchEvents)
    for i, q in ipairs(list or {}) do out[i] = { prog = q.prog, state = q.state, ptsNow = q.got } end
    return out
end

local function push(user, parts, player)
    local acc = Q.Store.account(user, false)
    if acc == nil or player == nil then return end
    local watching, tracking = Y.watchers[user], Y.trackers[user]
    local unseen = acc.unseen or 0
    if not watching and not tracking then
        if Y.sentUnseen[user] ~= unseen then
            Y.sentUnseen[user] = unseen
            Q.Net.send(player, "delta", { unseen = unseen })
        end
        return
    end
    -- full state: "all" / "events" for everyone; an open window also for any part a delta does not carry
    local full = parts.all or parts.events
    if not full and watching then
        for part in pairs(parts) do
            if not Y.DELTA_PARTS[part] then
                full = true
                break
            end
        end
    end
    if full then
        Y.sentUnseen[user] = unseen
        Q.Net.send(player, "state", Y.state(user, acc))
        return
    end
    local d = { unseen = unseen }
    local any = watching or Y.sentUnseen[user] ~= unseen
    Y.sentUnseen[user] = unseen
    if parts.day and (watching or pinned(acc, "d")) then
        d.day = questDelta(acc.day and acc.day.quests)
        any = true
    end
    if parts.week and (watching or pinned(acc, "w")) then
        d.week = questDelta(acc.week and acc.week.quests)
        any = true
    end
    if watching and parts.goal then
        local g = Q.Store.root().goal or {}
        d.goal = { progress = g.progress, reached = g.reached }
    end
    if watching and parts.points then d.points = { season = acc.points.season, total = acc.points.total, balance = acc.points.balance } end
    if parts.trk or parts.pins then
        d.trk = Y.trk(acc)
        any = true
    end
    if parts.pins then d.pins = acc.pins or {} end
    -- the horde row of the tracker and the daily banner: window and tracker alike
    if parts.hordes and Y.providers.hordes then
        local ok, v = pcall(Y.providers.hordes, acc, user, Q.Clock.now())
        if ok then
            d.hordes = v
            any = true
        end
    end
    if any then Q.Net.send(player, "delta", d) end
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
    -- one pass over the online list per flush (Net.toUser walks it for every send)
    local online = nil
    for user, parts in pairs(map) do
        if online == nil then
            online = {}
            Q.Net.eachOnline(function(p, u) online[u] = p end)
        end
        push(user, parts, online[user])
    end
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
-- (pass the real user when t.who is nil because the player is anonymous: admins get a copy naming them in `a`).
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
    if t.who == nil and achiever ~= nil then
        -- anonymous achiever: admins get the name; the others no title either, or the title worn over the head
        -- and in chat would tell who it is (round 7 decision: anonymity is not broken by titles)
        local named = U.copy(t)
        named.a = achiever
        local plain = U.copy(t)
        plain.titleId = nil
        Q.Net.eachOnline(function(p)
            Q.Net.send(p, "toast", (Q.Server ~= nil and Q.Server.isAdmin(p)) and named or plain)
        end)
    else
        Q.Net.broadcast("toast", t)
    end
    return true
end

function Y.catalogChanged()
    Q.Net.broadcast("catalog", Y.catalog())
end

function Y.forget(user)
    Y.watchers[user], Y.sentUnseen[user], Y.dirtyMap[user], Y.achvQueue[user] = nil, nil, nil, nil
    Y.trackers[user], Y.pinStats[user] = nil, nil
end

-- ---------- worn titles of the online players (chat suffix, line over the head) ----------

function Y.titles()
    local map = {}
    Q.Net.eachOnline(function(_, u)
        local acc = Q.Store.account(u, false)
        if acc ~= nil and acc.title ~= nil then map[u] = acc.title end
    end)
    return map
end

-- to everyone: a login (stale entries go too) or a title change; t = nil removes the entry
function Y.titleChanged(user, acc)
    Q.Net.broadcast("titles", { u = user, t = acc ~= nil and acc.title or nil })
end

function Y.prune(now)
    local minute = math.floor(now / 60000)
    for k, b in pairs(Y.bcast) do if b.minute < minute then Y.bcast[k] = nil end end
end

-- a stat of a pinned achievement moved: its trk entry goes out with the next flush (Stats hot path: lookups only)
Q.Stats.listen("track", function(acc, user, stat)
    local s = Y.pinStats[user]
    if s ~= nil and s[stat] then Y.dirty(user, "trk") end
end)
