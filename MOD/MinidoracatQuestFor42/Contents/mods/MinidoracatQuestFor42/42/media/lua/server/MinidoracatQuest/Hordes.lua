-- MinidoracatQuest/Hordes.lua: timed horde events (docs/ARCHITECTURE.md section 5.10).
-- Settings are Config hordes.* (config.json covers them); live state is root.hordes (section 3.1).
-- Inside the daily window (sandbox TimezoneOffset, not the reward day) one roll per hour with hordes.chance, at most
-- hordes.maxPerDay a day, one horde at a time. A planned horde is announced leadMin before its start, then waits up
-- to waitMin for a verified player within RANGE tiles (the engine spawns only on loaded squares, LuaManager.java:10589)
-- and spawns its kind mix. All tracked zombies gone while a player is near = success (points by kill share or the
-- whole pool each); endsAt reached = the rest are cleared (H.clearZombie) and nobody is paid.
-- IsoZombie objects are reused by the engine (VirtualZombieManager.java:728-742), so H.live is memory only and an
-- entry counts while the zombie keeps the online id it spawned with: removeFromWorld (virtualised, walked away) sets
-- it to -1 and a reuse hands out a new one. Those stop counting and stay as normal zombies. A restart fails an active
-- horde ("restart"); planned / announced / waiting ones carry on.
-- Kinds: built-in vanilla and runner (z:doSprinter() at spawn, IsoZombie.java:5563; never doZombieSpeed(1), which
-- rolls); other mods add "<modId>:<id>" kinds through v1.registerHordeKind. Quest owns timing, counting, clearing.

if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Sandbox"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Identity"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"
require "MinidoracatQuest/Towns"

local first = MQ.Hordes == nil
local H = MQ.Hordes or {}
MQ.Hordes = H
local C, U = MQ.Contract, MQ.Util
local CODE = C.CODE

local MIN, HOUR, DAY = 60000, 3600000, 86400000
H.RANGE = 50              -- tiles (2D) from the spot: a player this close spawns the horde and confirms success
H.MAX_TRIES = 10          -- spawn attempts that gave no zombie before the horde fails ("spawn")
H.LAST_MS = 10 * MIN      -- players see the last result this long after it ended
H.LOG = 20                -- root.hordes.log entries kept
H.MAX_PER_MOD, H.MAX_PACK = 8, 32
H.kinds = H.kinds or {}   -- id -> { id, nameKey, spawn = fn(x, y, z, n) -> ArrayList | Lua array, modId? }
H.live = H.live or {}     -- IsoZombie -> { horde, onlineId }; memory only
H.lastTick = H.lastTick or 0

local function hordes() return MQ.Store.root().hordes end
local function settings() return MQ.Config.get().hordes end
local function dirty() MQ.Sync.dirty(nil, "hordes") end

-- fn(item) over a Java list (size/get) or a Lua array
local function each(list, fn)
    if type(list) == "table" and list.size == nil then
        for i = 1, #list do fn(list[i]) end
    elseif list ~= nil then
        for i = 0, list:size() - 1 do fn(list:get(i)) end
    end
end

-- ---------- kinds ----------

-- LuaManager.java:10433: each zombie on a random square of the 11 x 11 area; unloaded squares give fewer
local function area(x, y, z, n)
    return addZombiesInOutfitArea(x - 5, y - 5, x + 5, y + 5, z, n, nil, 50)
end

H.kinds.vanilla = { id = "vanilla", nameKey = "IGUI_MQ_Horde_Kind_vanilla", spawn = area }
H.kinds.runner = { id = "runner", nameKey = "IGUI_MQ_Horde_Kind_runner", spawn = function(x, y, z, n)
    local list = area(x, y, z, n)
    -- fixed sprinter (speedType 1, lunger); the walk type reaches every client in the zombie packet
    each(list, function(zed) if instanceof(zed, "IsoZombie") then zed:doSprinter() end end)
    return list
end }

local function idOk(s, max, pattern)
    return type(s) == "string" and #s >= 1 and #s <= max and string.find(s, pattern) ~= nil
end

-- v1.registerHordeKind: spec = { modId, id, nameKey, spawn }; key "<modId>:<id>" (<= 64 chars: the config weight
-- key limit); <= MAX_PER_MOD per modId, <= MAX_PACK in all; registering a key again replaces it.
function H.registerKind(spec)
    if type(spec) ~= "table" or not idOk(spec.modId, 64, "^[%w_%-]+$") or not idOk(spec.id, 32, "^[%w_%-]+$")
        or not idOk(spec.nameKey, 128, "^[%w_]+$") or type(spec.spawn) ~= "function" then
        return nil, "invalid_args"
    end
    local key = spec.modId .. ":" .. spec.id
    if #key > 64 then return nil, "invalid_args" end
    if H.kinds[key] == nil then
        local mine, all = 0, 0
        for _, k in pairs(H.kinds) do
            if k.modId ~= nil then
                all = all + 1
                if k.modId == spec.modId then mine = mine + 1 end
            end
        end
        if mine >= H.MAX_PER_MOD or all >= H.MAX_PACK then return nil, "invalid_args" end
    end
    H.kinds[key] = { id = key, nameKey = spec.nameKey, spawn = spec.spawn, modId = spec.modId }
    return true
end

-- { { id, nameKey, builtin } }: built-in kinds in Contract order, then registered kinds by id
function H.kindList()
    local out, packs = {}, {}
    for _, id in ipairs(C.HORDE_KINDS) do
        out[#out + 1] = { id = id, nameKey = H.kinds[id].nameKey, builtin = true }
    end
    for id, k in pairs(H.kinds) do
        if k.modId ~= nil then packs[#packs + 1] = { id = id, nameKey = k.nameKey, builtin = false } end
    end
    U.sort(packs, function(a, b) return a.id < b.id end)
    for _, k in ipairs(packs) do out[#out + 1] = k end
    return out
end

-- { { kind, n, nameKey } } over the registered kinds with weight > 0; n sums to count (floors, then the remainder one
-- each to the largest weights). No usable weight: all vanilla.
function H.mix(weights, count)
    local list, sum = {}, 0
    for _, k in ipairs(H.kindList()) do
        local w = type(weights) == "table" and weights[k.id] or 0
        if type(w) == "number" and w > 0 then
            list[#list + 1] = { kind = k.id, n = 0, nameKey = k.nameKey, w = w }
            sum = sum + w
        end
    end
    if sum == 0 then return { { kind = "vanilla", n = count, nameKey = H.kinds.vanilla.nameKey } } end
    local left, order = count, {}
    for i, m in ipairs(list) do
        m.n = math.floor(count * m.w / sum)
        left = left - m.n
        order[i] = m
    end
    U.sort(order, function(a, b)
        if a.w ~= b.w then return a.w > b.w end
        return a.kind < b.kind
    end)
    local i = 1
    while left > 0 do
        order[i].n = order[i].n + 1
        left = left - 1
        i = i % #order + 1
    end
    for _, m in ipairs(list) do m.w = nil end
    return list
end

-- ---------- window and hourly rolls (pure; tz = hours east of UTC) ----------

function H.hm(s)
    local h, m = string.match(tostring(s), "^(%d%d?):(%d%d)$")
    if h == nil then return nil end
    return tonumber(h) * 60 + tonumber(m)
end

local function localDay(now, tz)
    return math.floor((now + tz * HOUR) / DAY)
end

local function dayKey(d)
    local y, m, dd = MQ.Clock.civil(d)
    return string.format("%d-%02d-%02d", y, m, dd)
end

-- start and end ms of local day d's window; to < from runs past midnight, to == from is all day
function H.windowOf(cfg, d, tz)
    local from, to = H.hm(cfg.from) or 0, H.hm(cfg.to) or 0
    local len = to - from
    if len <= 0 then len = len + 1440 end
    local ws = d * DAY - tz * HOUR + from * MIN
    return ws, ws + len * MIN
end

-- the window now belongs to (its rolls start leadMin before it opens): d, ws, we, slot count; nil outside. The later
-- day wins, so an all-day window's next day starts rolling lead minutes before midnight (no slot of the earlier day
-- rolls that late).
function H.window(cfg, now, tz)
    local lead = cfg.leadMin * MIN
    local d0 = localDay(now, tz)
    for d = d0 + 1, d0 - 1, -1 do
        local ws, we = H.windowOf(cfg, d, tz)
        if ws - lead <= now and now < we then return d, ws, we, math.ceil((we - ws) / HOUR) end
    end
    return nil
end

-- slot k (0-based): start, end (the window end caps the last one), roll time
function H.slot(ws, we, k, leadMin)
    local s = ws + k * HOUR
    return s, math.min(s + HOUR, we), s - leadMin * MIN
end

-- The roll state for local day `key` whose window starts at ws (pure). Slot numbers count from the window start, so a
-- start moved by an admin restarts them at 0; hordes already planned that day (n) still count against maxPerDay.
local function rollFor(roll, key, ws)
    if roll.day == key and roll.ws == ws then return roll end
    return { day = key, ws = ws, slot = 0, n = roll.day == key and roll.n or 0 }
end

-- Takes every slot whose roll time has passed. A slot that already ended (server down) is skipped, not rolled late.
function H.roll(now, cfg, tz)
    local d, ws, we, K = H.window(cfg, now, tz)
    if d == nil then return end
    local h = hordes()
    h.roll = rollFor(h.roll, dayKey(d), ws)
    local r = h.roll
    while r.slot < K do
        local s, e, at = H.slot(ws, we, r.slot, cfg.leadMin)
        if now < at then return end
        r.slot = r.slot + 1
        if now < e and cfg.enabled and #cfg.spots > 0 and h.cur == nil and r.n < cfg.maxPerDay
            and ZombRand(100) < cfg.chance then
            -- a whole minute in [max(slot start, now + lead), slot end): the announcement keeps its lead
            local lo = math.ceil(math.max(s, now + cfg.leadMin * MIN) / MIN)
            local hi = math.ceil(e / MIN) - 1
            if hi >= lo then
                r.n = r.n + 1
                H.plan(cfg, (lo + ZombRand(hi - lo + 1)) * MIN, nil)
            end
        end
    end
end

-- next roll ms for the admin page, nil when off or without spots
function H.nextRoll(cfg, now, tz, roll)
    if not cfg.enabled or #cfg.spots == 0 then return nil end
    local d, ws, we, K = H.window(cfg, now, tz)
    local from
    if d ~= nil then
        local r = rollFor(roll, dayKey(d), ws)
        local slot, n = r.slot, r.n
        if slot < K and n < cfg.maxPerDay then
            local _, _, at = H.slot(ws, we, slot, cfg.leadMin)
            return at
        end
        from = d + 1
    else
        from = localDay(now, tz)
    end
    for dd = from, from + 2 do
        local at = H.windowOf(cfg, dd, tz) - cfg.leadMin * MIN
        if at > now then return at end
    end
    return nil
end

-- ---------- one horde ----------

-- actor nil = an automatic roll; the knobs are copied so later setting changes leave it alone
function H.plan(cfg, startMs, actor)
    local h = hordes()
    local spot = cfg.spots[ZombRand(#cfg.spots) + 1]
    local lo, hi = cfg.count[1], cfg.count[2]
    local count = lo + ZombRand(hi - lo + 1)
    h.seq = (h.seq or 0) + 1
    h.cur = { id = h.seq, auto = actor == nil, actor = actor or "auto", name = spot.name, x = spot.x, y = spot.y,
        z = spot.z, town = MQ.Towns.at(spot.x, spot.y), mix = H.mix(cfg.kinds, count), count = count,
        perZombie = cfg.perZombie, split = cfg.split, limitMin = cfg.limitMin, waitMin = cfg.waitMin,
        state = "planned", announceAt = startMs - cfg.leadMin * MIN, startMs = startMs,
        expireAt = startMs + cfg.waitMin * MIN, spawned = 0, left = 0, killed = 0, kills = {}, tries = 0 }
    dirty()
    return h.cur
end

local function kindsOf(cur)
    local out = {}
    for _, m in ipairs(cur.mix) do out[#out + 1] = { id = m.kind, nameKey = m.nameKey } end
    return out
end

local function toast(cur, ev, fields)
    local t = { kind = "horde", ev = ev, id = cur.id, name = cur.name, town = cur.town }
    for k, v in pairs(fields) do t[k] = v end
    MQ.Net.broadcast("toast", t)
end

-- a verified, living online player within RANGE tiles (2D)
function H.near(cur)
    local found, r2 = false, H.RANGE * H.RANGE
    MQ.Net.eachOnline(function(p)
        if not found and not p:isDead() then
            local dx, dy = p:getX() - cur.x, p:getY() - cur.y
            found = dx * dx + dy * dy <= r2
        end
    end)
    return found
end

-- still the zombie that was spawned: removeFromWorld sets the online id to -1 (IsoZombie.java:4335-4370) and a reused
-- object gets a new one (VirtualZombieManager.createRealZombieAlways). Not isExistInTheWorld(): on the dedicated server
-- a fresh horde zombie's square does not list it (quest-hz-1026e: false 0-1.5 s after the spawn), so with that check
-- every horde "won" on the next tick with 0 kills (quest-hz-1026c/d). Nor the persistent outfit id: spawned without an
-- outfit name a zombie is flagged to dress at random later (LuaManager.java:10661-10665), which would give it a new one.
local function same(z, t)
    local id = z:getOnlineID()
    return id ~= -1 and id == t.onlineId
end

-- The one way a horde zombie leaves the world (time out, admin stop). Callers drop its H.live entry first, so a
-- clear never counts as a kill.
-- E2E quest-hz-1026a (42.21.0 dedicated): after removeFromWorld + removeFromSquare on the server the owner client
-- turned the zombies remote within 3 s and dropped them by 8 s. z:Kill(nil) on the server is not a substitute: those
-- zombies stayed isDead() false / isExistInTheWorld() false on the server and alive and owned on the owner client
-- 30 s later.
function H.clearZombie(z)
    z:removeFromWorld()
    z:removeFromSquare()
end

local function spawn(cur, now)
    for _, m in ipairs(cur.mix) do
        local kind = H.kinds[m.kind]
        if kind ~= nil and m.n > 0 then
            local got = 0
            local ok, err = pcall(function()
                each(kind.spawn(cur.x, cur.y, cur.z, m.n), function(z)
                    if got < m.n and instanceof(z, "IsoZombie") and H.live[z] == nil then
                        H.live[z] = { horde = cur.id, onlineId = z:getOnlineID() }
                        got = got + 1
                    end
                end)
            end)
            if not ok then U.log("horde kind " .. U.logSafe(m.kind) .. " failed: " .. U.logSafe(err)) end
            cur.spawned = cur.spawned + got
        end
    end
    if cur.spawned == 0 then
        cur.tries = cur.tries + 1
        if cur.tries >= H.MAX_TRIES then H.finish("failed", "spawn", now) end
        return
    end
    cur.state, cur.left, cur.spawnAt, cur.endsAt = "active", cur.spawned, now, now + cur.limitMin * MIN
    toast(cur, "spawn", { endsAt = cur.endsAt, limitMin = cur.limitMin, spawned = cur.spawned,
        pool = cur.perZombie * cur.spawned, split = cur.split })
    dirty()
end

local function check(cur, now)
    local alive, gone = 0, {}
    for z, t in pairs(H.live) do
        if t.horde == cur.id then
            if same(z, t) and not z:isDead() then alive = alive + 1 else gone[#gone + 1] = z end
        end
    end
    for _, z in ipairs(gone) do H.live[z] = nil end
    if alive ~= cur.left then
        cur.left = alive
        dirty()
    end
    if alive == 0 and H.near(cur) then return H.finish("success", nil, now) end
    if now >= cur.endsAt then return H.finish("failed", "time", now) end
end

-- participants (>= 1 kill) get points kind "horde", horde.wins + 1 and a personal toast (none when pool 0 pays
-- nothing: the server-wide "win" already says it); returns paid, count
local function pay(cur, pool)
    local total, users = 0, {}
    for user, k in pairs(cur.kills) do
        total = total + k
        if k >= 1 then users[#users + 1] = user end
    end
    U.sort(users, function(a, b) return a < b end)
    local paid = {}
    for _, user in ipairs(users) do
        local k = cur.kills[user]
        local pts = 0
        if pool > 0 then pts = cur.split == "each" and pool or math.max(1, math.floor(pool * k / total + 0.5)) end
        if pts > 0 then MQ.Points.award(MQ.Store.account(user, true), user, pts, "horde", "horde:" .. cur.id) end
        MQ.Stats.add(user, "horde.wins", 1)
        paid[user] = pts
        if pts > 0 then
            local t = { kind = "hordePaid", id = cur.id, name = cur.name, town = cur.town, pts = pts, kills = k }
            if cur.split ~= "each" then t.pct = math.floor(100 * k / total + 0.5) end
            MQ.Sync.toast(user, t)
        end
    end
    return paid, #users
end

-- result "success" | "failed" | "cancelled"; why for failed: time | nobody | admin | restart | spawn
function H.finish(result, why, now)
    local h = hordes()
    local cur = h.cur
    if cur == nil then return end
    local pool = cur.perZombie * cur.spawned
    local paid, n = {}, 0
    if result == "success" then paid, n = pay(cur, pool) end
    local mine = {}
    for z, t in pairs(H.live) do
        if t.horde == cur.id then mine[#mine + 1] = { z = z, t = t } end
    end
    local clear = result == "failed" and cur.state == "active"
    for _, e in ipairs(mine) do
        H.live[e.z] = nil
        if clear and same(e.z, e.t) and not e.z:isDead() then
            local ok, err = pcall(H.clearZombie, e.z)
            if not ok then U.log("horde clear failed: " .. U.logSafe(err)) end
        end
    end
    if result == "success" then
        toast(cur, "win", { spawned = cur.spawned, killed = cur.killed, pool = pool, split = cur.split, n = n })
    elseif result == "failed" then
        toast(cur, "fail", { why = why, left = cur.left })
    elseif cur.state ~= "planned" then
        toast(cur, "cancel", {})
    end
    MQ.EventLog.write("horde", nil, { id = cur.id, state = result, why = why, spawned = cur.spawned, killed = cur.killed })
    local log = h.log
    log[#log + 1] = { id = cur.id, auto = cur.auto, name = cur.name, town = cur.town, state = result, why = why,
        startMs = cur.startMs, spawnAt = cur.spawnAt, endedAt = now, spawned = cur.spawned, killed = cur.killed,
        pool = pool, split = cur.split, paid = paid, kills = cur.kills, announced = cur.state ~= "planned" }
    while #log > H.LOG do table.remove(log, 1) end
    h.cur = nil
    dirty()
end

-- planned -> announced (or waiting) -> waiting -> active -> finish
function H.step(now)
    local cur = hordes().cur
    if cur == nil then return end
    if cur.state == "planned" and now >= cur.announceAt then
        local open = now >= cur.startMs
        cur.state = open and "waiting" or "announced"
        toast(cur, open and "open" or "soon", { startMs = cur.startMs, kinds = kindsOf(cur) })
        dirty()
    end
    if cur.state == "announced" and now >= cur.startMs then
        cur.state = "waiting"
        dirty()
    end
    if cur.state == "waiting" then
        if now >= cur.expireAt then return H.finish("failed", "nobody", now) end
        if H.near(cur) then spawn(cur, now) end
    elseif cur.state == "active" then
        check(cur, now)
    end
end

-- first tick after the store is ready: the zombies of an active horde were not kept across the restart
function H.boot(now)
    H.booted = true
    H.live = {}
    local cur = hordes().cur
    if cur ~= nil and cur.state == "active" then H.finish("failed", "restart", now) end
end

function H.tick(now)
    if now - H.lastTick < 1000 or not MQ.Store.ready() or MQ.Store.readOnly then return end
    H.lastTick = now
    if not H.booted then H.boot(now) end
    H.roll(now, settings(), MQ.Sandbox.get("TimezoneOffset"))
    H.step(now)
end

function H.onZombieDead(z)
    local t = z ~= nil and H.live[z] or nil
    if t == nil then return end   -- not ours, or the second event of a burning death
    H.live[z] = nil
    local cur = hordes().cur
    if cur == nil or cur.id ~= t.horde or cur.state ~= "active" or not same(z, t) then return end
    cur.killed = cur.killed + 1
    if cur.left > 0 then cur.left = cur.left - 1 end
    -- Kill() sets the attacker before the event fires; fire deaths have none: cleared, no kill
    local killer = z:getAttackedBy()
    local user = killer ~= nil and instanceof(killer, "IsoPlayer") and MQ.Identity.principal(killer) or nil
    if user ~= nil then cur.kills[user] = (cur.kills[user] or 0) + 1 end
    dirty()
end

-- ---------- state part, admin ops ----------

-- Sync provider "hordes": { cur, last }; a planned horde is secret, the last result shows for LAST_MS
function H.stateHordes(acc, user, now)
    local h = hordes()
    local out, cur = {}, h.cur
    if cur ~= nil and cur.state ~= "planned" then
        out.cur = { id = cur.id, name = cur.name, town = cur.town, x = cur.x, y = cur.y, z = cur.z, state = cur.state,
            kinds = kindsOf(cur), announceAt = cur.announceAt, startMs = cur.startMs, expireAt = cur.expireAt,
            endsAt = cur.endsAt, spawned = cur.spawned, left = cur.left, killed = cur.killed,
            pool = cur.spawned > 0 and cur.perZombie * cur.spawned or nil, perZombie = cur.perZombie, split = cur.split,
            limitMin = cur.limitMin, mine = cur.kills[user] or 0 }
    end
    local e = h.log[#h.log]
    if e ~= nil and e.announced ~= false and now - e.endedAt < H.LAST_MS then
        out.last = { id = e.id, name = e.name, town = e.town, state = e.state, why = e.why, endedAt = e.endedAt,
            spawned = e.spawned, killed = e.killed, pool = e.pool, split = e.split,
            mine = e.kills and e.kills[user] or 0, got = e.paid and e.paid[user] }
    end
    return out
end

function H.status(now)
    local h, cfg = hordes(), settings()
    local tz = MQ.Sandbox.get("TimezoneOffset")
    local roll = h.roll
    local d, ws = H.window(cfg, now, tz)
    if d ~= nil then roll = rollFor(roll, dayKey(d), ws) end
    local log = {}
    for i = #h.log, math.max(1, #h.log - 9), -1 do log[#log + 1] = h.log[i] end
    return { cur = h.cur, log = log, kinds = H.kindList(),
        roll = { day = roll.day, slot = roll.slot, n = roll.n, max = cfg.maxPerDay, enabled = cfg.enabled,
            nextAt = H.nextRoll(cfg, now, tz, roll) } }
end

-- manual start: now, announced as "open" at once; not counted in roll.n
function H.startNow(actor, now)
    local h, cfg = hordes(), settings()
    if h.cur ~= nil then return false, CODE.HORDE_BUSY end
    if #cfg.spots == 0 then return false, CODE.NO_SPOTS end
    local cur = H.plan(cfg, now, actor)
    MQ.Config.addHistory(actor, "horde.now " .. cur.id .. " " .. cur.name, {}, false)
    H.step(now)
    return true, cur.id
end

-- planned / announced -> cancelled; waiting / active -> failed "admin" (active ones are cleared)
function H.stop(id, actor, now)
    local cur = hordes().cur
    if cur == nil or cur.id ~= id then return false, CODE.NOT_FOUND end
    local name = cur.name
    if cur.state == "planned" or cur.state == "announced" then
        H.finish("cancelled", "admin", now)
    else
        H.finish("failed", "admin", now)
    end
    MQ.Config.addHistory(actor, "horde.stop " .. id .. " " .. name, {}, false)
    return true
end

MQ.Server.defineAdmin("horde.status", { kind = "query", run = function(ctx) return true, H.status(ctx.now) end })

MQ.Server.defineAdmin("horde.now", { kind = "mutation", run = function(ctx)
    local ok, res = H.startNow(ctx.user, ctx.now)
    if not ok then return false, res end
    return true, { id = res }
end })

MQ.Server.defineAdmin("horde.stop", { kind = "mutation", fields = { id = "int" },
    run = function(ctx) return H.stop(ctx.args.id, ctx.user, ctx.now) end })

MQ.Sync.provider("hordes", H.stateHordes)

if first then
    Events.OnTickEvenPaused.Add(function() MinidoracatQuest.Hordes.tick(getTimestampMs()) end)
    Events.OnZombieDead.Add(function(z) MinidoracatQuest.Hordes.onZombieDead(z) end)
end

return H
