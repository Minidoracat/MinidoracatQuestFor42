-- MinidoracatQuest/Hordes.lua: timed horde events (docs/ARCHITECTURE.md section 5.10).
-- Settings are Config hordes.* (config.json covers them); live state is root.hordes (section 3.1).
-- Schedule: every window (its weekdays, from-to in the sandbox TimezoneOffset, not the reward day) rolls once an hour
-- with its chance; hordes.maxPerDay counts the hordes of all windows of a local day; one horde at a time. A window
-- plays one of hordes.presets (a named set of waves, kinds, points, hp, cap, limitMin, restSec, maxAlive; H.presetOf)
-- and has its own leadMin and waitMin. A planned horde copies its preset, is announced leadMin before its start, then
-- runs its waves: each waits up to waitMin for a verified player within RANGE tiles, is sized by the players near
-- (Catalog.hordeWaveSize) and comes in batches from exits on a ring around the spot, at most maxAlive alive at once,
-- more as they die, each with its kind's health times hp (at most HP_MAX). The engine spawns only on loaded squares
-- (addZombiesInOutfit returns an empty list for a nil square, 42.21.0 LuaManager.java:10626-10630) and the server keeps
-- at least 48 tiles loaded around a player, so an exit stays within REACH of a player and GAP away from every player.
-- The server runs no zombie AI: a sound at the spot every LURE_MS goes to the clients that own the zombies (addSound,
-- WorldSoundManager) and draws them in. A wave all gone while a player is near = cleared (its kill value is kept),
-- restSec of rest, the next wave; the last one cleared = success. endsAt (limitMin per wave) reached = failed, the rest
-- cleared (H.clearZombie). Every end pays the kill value of the cleared waves (points per kind), at most cap a horde,
-- split by it.
-- IsoZombie objects are reused by the engine (VirtualZombieManager.java:728-742), so H.live is memory only and an
-- entry counts while the zombie keeps the online id it spawned with (single player: while the cell lists it, see
-- same): removeFromWorld (virtualised, walked away) sets it to -1 and a reuse hands out a new one; a reused object
-- also loses its entry at OnZombieCreate (H.onZombieCreate). Those stop counting and stay as normal zombies. A restart
-- fails an active horde ("restart"); planned / announced / waiting / rest ones carry on.
-- Kinds: built-in vanilla and runner (z:doSprinter() at spawn, IsoZombie.java:5563; never doZombieSpeed(1), which
-- rolls); other mods add "<modId>:<id>" kinds through v1.registerHordeKind. Quest owns timing, counting, clearing.
-- Manual starts (horde.now, design r12 and plan-presets-1028) play a preset (default "default"), announce lead minutes
-- ahead (0 = at once) and wait wait minutes for players (default 60). Players within RANGE get one
-- personal reminder REMIND_MS before the start. Participants' stats (horde.joined / kills / mvp) feed achievements and
-- the player Hordes page, which lists the recent results from root.hordes.log (H.recent, in the records reply).

if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Catalog"
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
H.RANGE = 30              -- tiles (2D) from the spot: players this close start a wave, size it and get the reminder
H.MAX_TRIES = 10          -- batches in a row that gave no zombie: none of the wave yet = failed "spawn", else the rest go
H.BATCH = 40              -- zombies spawned per tick at most
H.EXITS = 8               -- exit directions around the spot, from the wave's random angle
H.RING_MIN, H.RING_MAX = 30, 40   -- exit distance from the spot (tiles)
H.GAP = 25                -- an exit is at least this far (2D) from every living player
H.REACH = 43              -- and within this many tiles (Chebyshev) of one: 48 loaded (smallest client) minus the 5 of
                          -- the 11 x 11 spawn area
H.LURE_MS = 5000          -- the lure sound at the spot repeats this often while horde zombies are alive
H.LURE_REACH = 48         -- tiles the lure should carry after the hearing cuts: RING_MAX plus SPREAD
H.LURE_MAX = 49           -- radius cap: from 50 the sound also stirs the virtual (unloaded) population, wild zombies
                          -- past maxAlive (ZombiePopulationManager.java:489-505); loaded wild ones in range come anyway
H.SPREAD = 8              -- a spawn lands up to this far (2D) from its exit: the 11 x 11 area's corner (5 x sqrt 2)
H.CLEAR_RANGE = 50        -- a wave counts as cleared with a player this close (2D): the exits, the scatter and a chase
H.LAST_MS = 10 * MIN      -- players see the last result this long after it ended
H.LOG = 20                -- root.hordes.log entries kept
H.RECENT = 10             -- results in the records reply (the player Hordes page)
H.REMIND_MS = 2 * MIN     -- the personal reminder to players near the spot comes this long before the start
H.HP_MAX = 30             -- spawn health cap: the zombie packet sends health x 1000 as a short, so above 32.767 it
                          -- wraps negative on the clients (42.21.0 NetworkZombieAI.java:169, NetworkZombiePacker.java:243)
H.MAX_PER_MOD, H.MAX_PACK = 8, 32
H.kinds = H.kinds or {}   -- id -> { id, nameKey, spawn = fn(x, y, z, n) -> ArrayList | Lua array, modId? }
H.live = H.live or {}     -- IsoZombie -> { horde, onlineId, kind }; memory only
H.lastTick = H.lastTick or 0
H.lureAt = H.lureAt or 0  -- next lure sound (ms); memory only
H.spawnErr = H.spawnErr or {}   -- kind id -> the horde id its spawn error was logged for; memory only

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

-- LuaManager.java:10433: each zombie on a random square of the 11 x 11 area; unloaded squares give fewer. A reused
-- zombie object keeps useless from its last life (VirtualZombieManager.java:271-329 does not reset it; only setUseless
-- and the debug "Useless" outfits write it, IsoZombie.java:3220-3221, :4768) and a useless zombie ignores every sound
-- and drops its target (:1594, :2060), so it stands at its exit through the lure (quest-hz-1027h-l). The built-in
-- kinds want ordinary zombies; registered kinds set their own flags.
local function area(x, y, z, n)
    local list = addZombiesInOutfitArea(x - 5, y - 5, x + 5, y + 5, z, n, nil, 50)
    each(list, function(zed) if instanceof(zed, "IsoZombie") then zed:setUseless(false) end end)
    return list
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

-- { { kind, n, nameKey } } over the registered kinds with weight > 0 (Catalog.hordeMix: n sums to count, floors then
-- the remainder to the largest weights). No usable weight: all vanilla.
function H.mix(weights, count)
    local ids = {}
    for i, k in ipairs(H.kindList()) do ids[i] = k.id end
    local out = MQ.Catalog.hordeMix(ids, weights, count)
    for _, m in ipairs(out) do m.nameKey = H.kinds[m.kind].nameKey end
    return out
end

-- ---------- windows and hourly rolls (pure; tz = hours east of UTC) ----------

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

-- 1 = Monday .. 7 = Sunday of local day d (day 0, 1970-01-01, was a Thursday)
function H.weekday(d)
    return (d + 3) % 7 + 1
end

local function onDay(win, d)
    return string.find(win.days, tostring(H.weekday(d))) ~= nil
end

function H.winKey(win)
    return win.from .. "-" .. win.to .. "-" .. win.days
end

-- one roll key per window: winKey, with #2, #3 on a repeat, so identical windows keep their own slots and chances
function H.winKeys(windows)
    local keys, seen = {}, {}
    for i, win in ipairs(windows) do
        local key = H.winKey(win)
        seen[key] = (seen[key] or 0) + 1
        keys[i] = seen[key] > 1 and key .. "#" .. seen[key] or key
    end
    return keys
end

-- start and end ms of local day d's window; to < from runs past midnight, to == from is all day
function H.windowOf(win, d, tz)
    local from, to = H.hm(win.from) or 0, H.hm(win.to) or 0
    local len = to - from
    if len <= 0 then len = len + 1440 end
    local ws = d * DAY - tz * HOUR + from * MIN
    return ws, ws + len * MIN
end

-- the day of win that now belongs to (its rolls start win.leadMin before it opens; only its weekdays): d, ws, we, slot
-- count; nil outside. The later day wins, so an all-day window's next day starts rolling lead minutes before midnight
-- (no slot of the earlier day rolls that late).
function H.window(win, now, tz)
    local lead = win.leadMin * MIN
    local d0 = localDay(now, tz)
    for d = d0 + 1, d0 - 1, -1 do
        if onDay(win, d) then
            local ws, we = H.windowOf(win, d, tz)
            if ws - lead <= now and now < we then return d, ws, we, math.ceil((we - ws) / HOUR) end
        end
    end
    return nil
end

-- slot k (0-based): start, end (the window end caps the last one), roll time
function H.slot(ws, we, k, leadMin)
    local s = ws + k * HOUR
    return s, math.min(s + HOUR, we), s - leadMin * MIN
end

-- A window's roll state for local day `key` starting at ws (pure). Slot numbers count from the window start, so a
-- start moved by an admin (a new winKey too) restarts them at 0; the day's count lives apart in perDay.
local function rollFor(roll, key, ws)
    if roll ~= nil and roll.day == key and roll.ws == ws then return roll end
    return { day = key, ws = ws, slot = 0 }
end

-- one more horde on local day key; perDay keeps the last 3 days
local function countDay(h, key)
    h.perDay[key] = (h.perDay[key] or 0) + 1
    local keys = {}
    for k in pairs(h.perDay) do keys[#keys + 1] = k end
    if #keys <= 3 then return end
    U.sort(keys, function(a, b) return a > b end)
    for i = 4, #keys do h.perDay[keys[i]] = nil end
end

-- Takes every slot of every window whose roll time has passed. A slot that already ended (server down) is skipped,
-- not rolled late. Rolls of windows no longer in the settings are dropped.
function H.roll(now, cfg, tz)
    local h = hordes()
    local rolls, keep, keys = h.roll, {}, H.winKeys(cfg.windows)
    for i, win in ipairs(cfg.windows) do
        local key = keys[i]
        keep[key] = true
        local d, ws, we, K = H.window(win, now, tz)
        if d ~= nil then
            local dk = dayKey(d)
            local r = rollFor(rolls[key], dk, ws)
            rolls[key] = r
            while r.slot < K do
                local s, e, at = H.slot(ws, we, r.slot, win.leadMin)
                if now < at then break end
                r.slot = r.slot + 1
                if now < e and cfg.enabled and #cfg.spots > 0 and h.cur == nil and (h.perDay[dk] or 0) < cfg.maxPerDay
                    and ZombRand(100) < win.chance then
                    -- a whole minute in [max(slot start, now + lead), slot end): the announcement keeps its lead
                    local lo = math.ceil(math.max(s, now + win.leadMin * MIN) / MIN)
                    local hi = math.ceil(e / MIN) - 1
                    if hi >= lo then
                        countDay(h, dk)
                        H.plan(cfg, (lo + ZombRand(hi - lo + 1)) * MIN, nil, win)
                    end
                end
            end
        end
    end
    local old = {}
    for key in pairs(rolls) do
        if not keep[key] then old[#old + 1] = key end
    end
    for _, key in ipairs(old) do rolls[key] = nil end
end

-- the next roll time of one window, nil when none in the next week
local function nextOf(win, cfg, now, tz, roll, perDay)
    local from
    local d, ws, we, K = H.window(win, now, tz)
    if d ~= nil then
        local r = rollFor(roll, dayKey(d), ws)
        if r.slot < K and (perDay[dayKey(d)] or 0) < cfg.maxPerDay then
            local _, _, at = H.slot(ws, we, r.slot, win.leadMin)
            return at
        end
        from = d + 1
    else
        from = localDay(now, tz)
    end
    for dd = from, from + 7 do
        if onDay(win, dd) and (perDay[dayKey(dd)] or 0) < cfg.maxPerDay then
            local at = H.windowOf(win, dd, tz) - win.leadMin * MIN
            if at > now then return at end
        end
    end
    return nil
end

-- next roll ms over all windows for the admin page, nil when off or without spots
function H.nextRoll(cfg, now, tz, rolls, perDay)
    if not cfg.enabled or #cfg.spots == 0 then return nil end
    local best, keys = nil, H.winKeys(cfg.windows)
    for i, win in ipairs(cfg.windows) do
        local at = nextOf(win, cfg, now, tz, rolls[keys[i]], perDay)
        if at ~= nil and (best == nil or at < best) then best = at end
    end
    return best
end

-- ---------- one horde ----------

-- a preset of cfg (Config hordes), "default" when id names none. Every preset is whole: the default one merges
-- Catalog.DEFAULTS, the others are filled when config.json is read (Config.migrate) and refused without a knob
-- (Config validateAll); only hp may be left out (= x 1). The tables are cfg's: copy before keeping them.
function H.presetOf(cfg, id)
    return cfg.presets[id] or cfg.presets.default
end

-- win = { preset, leadMin, waitMin }: the window that rolled it, or horde.now's; actor nil = an automatic roll. The
-- preset's knobs are copied so later setting changes leave it alone; cur.preset is its name ("" = the default one).
function H.plan(cfg, startMs, actor, win)
    local h, p = hordes(), H.presetOf(cfg, win.preset)
    local spot = cfg.spots[ZombRand(#cfg.spots) + 1]
    h.seq = (h.seq or 0) + 1
    h.cur = { id = h.seq, auto = actor == nil, actor = actor or "auto", name = spot.name, x = spot.x, y = spot.y,
        z = spot.z, town = MQ.Towns.at(spot.x, spot.y), state = "planned", preset = p.name,
        announceAt = startMs - win.leadMin * MIN, startMs = startMs, expireAt = startMs + win.waitMin * MIN,
        waves = U.copy(p.waves), wave = 1, weights = U.copy(p.kinds), points = U.copy(p.points), hp = U.copy(p.hp or {}),
        cap = p.cap, limitMin = p.limitMin, waitMin = win.waitMin, restSec = p.restSec, maxAlive = p.maxAlive,
        size = 0, queued = 0, spawned = 0, left = 0, killed = 0, mix = {}, queue = {}, angle = 0, tries = 0,
        totalSpawned = 0, totalKilled = 0, cleared = 0, kills = {}, waveGot = {}, got = {}, waveKills = {}, gotKills = {} }
    dirty()
    return h.cur
end

-- A horde planned before the waves update (0.2.0, no cur.waves; it has its limitMin and waitMin) carries on as one
-- wave of its count; what it did not copy comes from today's default preset, at health x 1.
local function upgrade(cur)
    local p = H.presetOf(settings(), "default")
    local weights = {}
    for _, m in ipairs(cur.mix or {}) do weights[m.kind] = m.n end
    cur.waves = { { base = math.max(1, cur.count or 1), perPlayer = 0 } }
    cur.wave, cur.weights, cur.points, cur.cap, cur.hp, cur.preset = 1, weights, U.copy(p.points), p.cap, {}, p.name
    cur.restSec, cur.maxAlive, cur.size, cur.queued, cur.queue, cur.angle = p.restSec, p.maxAlive, 0, 0, {}, 0
    cur.totalSpawned, cur.totalKilled, cur.cleared = cur.spawned or 0, cur.killed or 0, 0
    cur.firstSpawnAt, cur.kills, cur.waveGot, cur.got = cur.spawnAt, cur.kills or {}, {}, {}
    cur.waveKills, cur.gotKills = {}, {}
    cur.count, cur.perZombie, cur.split, cur.spawnAt = nil, nil, nil, nil
end

-- the kinds a horde can bring ({ id, nameKey }, weight > 0): announcements list them without counts
local function kindsOf(cur)
    local out = {}
    for _, m in ipairs(H.mix(cur.weights, 0)) do out[#out + 1] = { id = m.kind, nameKey = m.nameKey } end
    return out
end

local function toast(cur, ev, fields)
    local t = { kind = "horde", ev = ev, id = cur.id, name = cur.name, town = cur.town }
    for k, v in pairs(fields) do t[k] = v end
    MQ.Net.broadcast("toast", t)
end

-- verified, living online players within range (default RANGE) tiles (2D)
function H.nearCount(cur, range)
    local r = range or H.RANGE
    local n, r2 = 0, r * r
    MQ.Net.eachOnline(function(p)
        if not p:isDead() then
            local dx, dy = p:getX() - cur.x, p:getY() - cur.y
            if dx * dx + dy * dy <= r2 then n = n + 1 end
        end
    end)
    return n
end

-- one personal reminder REMIND_MS before the start to the living players within RANGE (design r12): the start
-- spawns the horde if anyone is near, so the ones who stay away can still leave
local function remind(cur)
    cur.reminded = true
    local r2 = H.RANGE * H.RANGE
    local t = { kind = "horde", ev = "remind", id = cur.id, name = cur.name, town = cur.town, startMs = cur.startMs }
    MQ.Net.eachOnline(function(p)
        if not p:isDead() then
            local dx, dy = p:getX() - cur.x, p:getY() - cur.y
            if dx * dx + dy * dy <= r2 then MQ.Net.send(p, "toast", t) end
        end
    end)
end

-- still the zombie that was spawned: removeFromWorld sets the online id to -1 (IsoZombie.java:4335-4370) and a reused
-- object gets a new one (VirtualZombieManager.createRealZombieAlways). Not isExistInTheWorld(): on the dedicated server
-- a fresh horde zombie's square does not list it (quest-hz-1026e: false 0-1.5 s after the spawn), so with that check
-- every horde "won" on the next tick with 0 kills (quest-hz-1026c/d). Nor the persistent outfit id: spawned without an
-- outfit name a zombie is flagged to dress at random later (LuaManager.java:10661-10665), which would give it a new one.
-- Single player has no online ids (only the dedicated server hands them out, VirtualZombieManager.java:207-221: all
-- -1, quest-hsp-pre-1027a cleared every wave on the next tick with 0 kills) and isExistInTheWorld() is false there
-- too in the spawn frame; the cell's zombie list holds a zombie from its spawn (same frame) until removeFromWorld
-- (IsoZombie.java:4366), and still in OnZombieDead (onKilled fires it before DoDeath, IsoZombie.java:5409).
-- A reused object (unloaded, then handed out again within the 1 s tick) loses its entry at OnZombieCreate first.
local function same(z, t)
    if not isServer() then return getCell():getZombieList():contains(z) end
    local id = z:getOnlineID()
    return id ~= -1 and id == t.onlineId
end

-- The one way a horde zombie leaves the world (time out, admin stop). Callers drop its H.live entry first, so a
-- clear never counts as a kill.
-- E2E quest-hz-1026a (42.21.0 dedicated): after removeFromWorld + removeFromSquare on the server the owner client
-- turns the zombies remote at once, but no client drops them until their stale timeout (lastRemoteUpdate > 5000 in
-- 1000 / LockFPS steps per update, IsoZombie.java:3294-3295): 6 zombies went by 8 s, 200 in a crowd stayed 15-91 s
-- (quest-hclear-pre-1027a). So H.finish sends their ids once (hordeClear) and the clients near them remove them.
-- z:Kill(nil) on the server is not a substitute: those zombies stayed isDead() false / isExistInTheWorld() false on
-- the server and alive and owned on the owner client 30 s later.
function H.clearZombie(z)
    z:removeFromWorld()
    z:removeFromSquare()
end


-- A square a zombie can stand on: loaded (on the server getGridSquare is ServerMap's, nil outside the loaded cells,
-- IsoCell.java:3190-3192), a floor without solid / tree (IsoGridSquare.isFree, :3394) and not water (spawns refuse
-- water, VirtualZombieManager.java:254-255).
local function standable(x, y, z)
    local cell = getCell()
    local sq = cell ~= nil and cell:getGridSquare(x, y, z) or nil
    return sq ~= nil and sq:isFree(false) and not sq:isWaterSquare()
end

-- The exits of the current wave: EXITS directions from cur.angle, each RING_MIN..H.exitMax() tiles from the spot,
-- kept when they are GAP or more (2D) from every living online player, within REACH (Chebyshev) of at least one, and
-- standable. { { x, y } }, maybe empty; empty too when the lure cannot carry RING_MIN (heavy rain and fog, poor
-- hearing): the wave then comes at the spot (spawnBatch), as before the exits.
function H.exits(cur)
    local hi = H.exitMax()
    if hi < H.RING_MIN then return {} end
    local px, py = {}, {}
    MQ.Net.eachOnline(function(p)
        if not p:isDead() then px[#px + 1], py[#py + 1] = p:getX(), p:getY() end
    end)
    local out, gap2 = {}, H.GAP * H.GAP
    for i = 0, H.EXITS - 1 do
        local a = math.rad(cur.angle + i * 360 / H.EXITS)
        local r = H.RING_MIN + ZombRand(hi - H.RING_MIN + 1)
        local ex, ey = math.floor(cur.x + r * math.cos(a) + 0.5), math.floor(cur.y + r * math.sin(a) + 0.5)
        local ok, reach = true, false
        for j = 1, #px do
            local dx, dy = math.abs(px[j] - ex), math.abs(py[j] - ey)
            if dx * dx + dy * dy < gap2 then
                ok = false
                break
            end
            if math.max(dx, dy) <= H.REACH then reach = true end
        end
        if ok and reach and standable(ex, ey, cur.z) then out[#out + 1] = { x = ex, y = ey } end
    end
    return out
end

-- up to n zombies of one kind at (x, y); returns how many were real, new IsoZombies
local function spawnAt(cur, kind, x, y, n)
    local got = 0
    local ok, err = pcall(function()
        each(kind.spawn(x, y, cur.z, n), function(z)
            if got < n and instanceof(z, "IsoZombie") and H.live[z] == nil then
                -- the engine reuses zombie objects without clearing the network owner of their last life, and
                -- that owner's list no longer holds them: no client is sent the zombie until ownership moves
                -- (quest-hz-1026h / 1026j; NetworkZombieManager.java:172, :208, VirtualZombieManager.java:271-329).
                -- With no owner the next auth pass picks one (NetworkZombieManager.updateAuth).
                z:setOwner(nil)
                z:setOwnerPlayer(nil)
                H.live[z] = { horde = cur.id, onlineId = z:getOnlineID(), kind = kind.id }
                got = got + 1
                -- the preset's toughness: x the health the kind spawned with (sandbox ZombieLore.Toughness for the
                -- built-in ones); set at the spawn it reaches the clients (quest-hz-1027k)
                local mult = cur.hp and cur.hp[kind.id] or 1
                if mult ~= 1 then z:setHealth(math.min(z:getHealth() * mult, H.HP_MAX)) end
            end
        end)
    end)
    -- once per horde and kind: a broken spawn would otherwise log on every exit of every batch
    if not ok and H.spawnErr[kind.id] ~= cur.id then
        H.spawnErr[kind.id] = cur.id
        U.log("horde kind " .. U.logSafe(kind.id) .. " failed: " .. U.logSafe(err))
    end
    return got
end

-- n zombies from the queue (each kind's share of what is left, in mix order) over the exits in turn; no exit = at the
-- spot. Returns how many came.
local function spawnBatch(cur, n)
    local ok, exits = pcall(H.exits, cur)
    if not ok then
        U.log("horde exits failed: " .. U.logSafe(exits))
        exits = {}
    end
    if #exits == 0 then exits = { { x = cur.x, y = cur.y } } end
    local ids = {}
    for i, m in ipairs(cur.mix) do ids[i] = m.kind end
    local got, e = 0, 0
    for _, m in ipairs(MQ.Catalog.hordeMix(ids, cur.queue, n)) do
        local kind, per = H.kinds[m.kind], {}
        for _ = 1, m.n do
            e = e % #exits + 1
            per[e] = (per[e] or 0) + 1
        end
        for i = 1, #exits do
            if kind ~= nil and per[i] ~= nil then
                local g = spawnAt(cur, kind, exits[i].x, exits[i].y, per[i])
                cur.queue[m.kind] = cur.queue[m.kind] - g
                got = got + g
            end
        end
    end
    return got
end

-- the lure's hearing multiplier: sandbox lore hearing (WorldSoundManager.java:511-523: 1 = x3, 2 = x1, 3 = x0.45)
-- times the weather (IsoGameCharacter.java:15224-15227: 1 - rain x0.33 - fog x0.1). 4 and 5 roll each zombie's own
-- (IsoZombie.java:3904-3907: 4 = 1-3, 5 = 2-3), so some of them hear poorly: sized for poor like 3. Unknown = the
-- sandbox default, normal.
function H.lureMult()
    local lore = SandboxVars and SandboxVars.ZombieLore and SandboxVars.ZombieLore.Hearing
    local mult = lore == 1 and 3 or ((lore == 3 or lore == 4 or lore == 5) and 0.45 or 1)
    local ok, cm = pcall(getClimateManager)
    if ok and cm ~= nil then
        local okR, rain = pcall(cm.getRainIntensity, cm)
        local okF, fog = pcall(cm.getFogIntensity, cm)
        mult = mult * (1 - (okR and tonumber(rain) or 0) * 0.33 - (okF and tonumber(fog) or 0) * 0.1)
    end
    return math.max(mult, 0)
end

-- the radius that carries LURE_REACH after the hearing cuts, within LURE_REACH..LURE_MAX. Lure E2E quest-lure-1027b/c
-- (42.21.0, speed 2): 45/45 every 5 s brought 32/32 from 30-40 tiles within 60 s; 30/30 (heavy rain) only 7/32
function H.lureRadius()
    local mult = H.lureMult()
    if mult <= 0 then return H.LURE_MAX end
    return math.max(H.LURE_REACH, math.min(H.LURE_MAX, math.ceil(H.LURE_REACH / mult)))
end

-- the farthest exit (tiles from the spot) whose zombies, scattered SPREAD around it, still hear the lure
function H.exitMax()
    return math.min(H.RING_MAX, math.floor(H.lureRadius() * H.lureMult()) - H.SPREAD)
end

-- the lure: a sound at the spot the owner clients' zombies walk to (the server runs no zombie AI)
local function lure(cur, now)
    H.lureAt = now + H.LURE_MS
    local r = H.lureRadius()
    local ok, err = pcall(addSound, nil, cur.x, cur.y, cur.z, r, r)
    if not ok and H.lureErr ~= cur.id then
        H.lureErr = cur.id
        U.log("horde lure failed: " .. U.logSafe(err))
    end
end

-- waiting -> active: the wave's size by the players near now, its kind mix and a fresh exit angle
local function startWave(cur, now, players)
    local w = cur.waves[cur.wave]
    cur.size = MQ.Catalog.hordeWaveSize(w.base, w.perPlayer, players)
    cur.mix = H.mix(cur.weights, cur.size)
    cur.queue = {}
    for _, m in ipairs(cur.mix) do cur.queue[m.kind] = m.n end
    cur.queued, cur.spawned, cur.killed, cur.left, cur.tries = cur.size, 0, 0, cur.size, 0
    cur.angle = ZombRand(360)
    cur.state, cur.endsAt, cur.waveGot = "active", now + cur.limitMin * MIN, {}
    H.lureAt = 0
    toast(cur, "spawn", { wave = cur.wave, waves = #cur.waves, size = cur.size, endsAt = cur.endsAt,
        limitMin = cur.limitMin })
    dirty()
end

-- a wave all gone with a player near: its kill value (and kills, for the paid toast) become payable; rest before the
-- next, or success
local function cleared(cur, now)
    for user, pts in pairs(cur.waveGot) do cur.got[user] = (cur.got[user] or 0) + pts end
    for user, n in pairs(cur.waveKills) do cur.gotKills[user] = (cur.gotKills[user] or 0) + n end
    cur.waveGot, cur.waveKills, cur.cleared = {}, {}, cur.cleared + 1
    if cur.wave >= #cur.waves then return H.finish("success", nil, now) end
    cur.state, cur.nextAt = "rest", now + cur.restSec * 1000
    toast(cur, "rest", { wave = cur.wave, waves = #cur.waves, nextAt = cur.nextAt })
    dirty()
end

local function active(cur, now)
    local alive, gone = 0, {}
    for z, t in pairs(H.live) do
        if t.horde == cur.id then
            if same(z, t) and not z:isDead() then alive = alive + 1 else gone[#gone + 1] = z end
        end
    end
    for _, z in ipairs(gone) do H.live[z] = nil end
    local room = math.min(cur.maxAlive - alive, cur.queued, H.BATCH)
    if room > 0 then
        local got = spawnBatch(cur, room)
        if got > 0 then
            cur.firstSpawnAt = cur.firstSpawnAt or now
            cur.tries, cur.queued, alive = 0, cur.queued - got, alive + got
            cur.spawned, cur.totalSpawned = cur.spawned + got, cur.totalSpawned + got
            dirty()
        else
            cur.tries = cur.tries + 1
            if cur.tries >= H.MAX_TRIES then
                if cur.spawned == 0 then return H.finish("failed", "spawn", now) end
                cur.queued, cur.queue = 0, {}   -- the squares will not take more: the wave is the ones that came
            end
        end
    end
    if alive + cur.queued ~= cur.left then
        cur.left = alive + cur.queued
        dirty()
    end
    if alive > 0 and now >= H.lureAt then lure(cur, now) end
    if cur.queued == 0 and alive == 0 and H.nearCount(cur, H.CLEAR_RANGE) > 0 then return cleared(cur, now) end
    if now >= cur.endsAt then return H.finish("failed", "time", now) end
end

-- participants: >= 1 kill, by name
local function participants(cur)
    local users = {}
    for user, k in pairs(cur.kills) do
        if k >= 1 then users[#users + 1] = user end
    end
    U.sort(users, function(a, b) return a < b end)
    return users
end

-- Pays the kill value of the cleared waves (cur.got): pool = min(value, cap), split by it. Floors first, then the
-- remainder one point each to the largest fractions (ties by name), so the total is exactly pool. Points kind
-- "horde" and a personal toast for each payee. Returns paid, pool, capped.
local function pay(cur)
    local users, value, paid, frac = {}, 0, {}, {}
    for user, g in pairs(cur.got) do
        if g > 0 then
            users[#users + 1] = user
            value = value + g
        end
    end
    if value == 0 then return paid, 0, false end
    local pool, capped = math.min(value, cur.cap), value > cur.cap
    local left = pool
    for _, user in ipairs(users) do
        local num = pool * cur.got[user]
        paid[user] = math.floor(num / value)
        frac[user] = num - paid[user] * value
        left = left - paid[user]
    end
    U.sort(users, function(a, b)
        if frac[a] ~= frac[b] then return frac[a] > frac[b] end
        return a < b
    end)
    for i = 1, left do paid[users[i]] = paid[users[i]] + 1 end
    for _, user in ipairs(users) do
        local pts = paid[user]
        if pts > 0 then
            MQ.Points.award(MQ.Store.account(user, true), user, pts, "horde", "horde:" .. cur.id)
            -- kills of the cleared waves only: the ones these points are for (cur.kills also has the failed wave's)
            MQ.Sync.toast(user, { kind = "hordePaid", id = cur.id, name = cur.name, town = cur.town, pts = pts,
                kills = cur.gotKills[user] or 0, capped = capped })
        end
    end
    return paid, pool, capped
end

-- the top killers of a cleared horde with 2+ participants (all of them on a tie): horde.mvp + 1
local function mvp(cur, users)
    if #users < 2 then return end
    local top = 0
    for _, u in ipairs(users) do top = math.max(top, cur.kills[u]) end
    for _, u in ipairs(users) do
        if cur.kills[u] == top then MQ.Stats.add(u, "horde.mvp", 1) end
    end
end

-- result "success" | "failed" | "cancelled"; why for failed: time | nobody | admin | restart | spawn. Any result pays
-- the cleared waves (a failed wave's kills count for stats, not points).
function H.finish(result, why, now)
    local h = hordes()
    local cur = h.cur
    if cur == nil then return end
    h.cur = nil   -- first: an error further down must not finish (and pay) it again on the next tick
    local users = participants(cur)
    local paid, pool, capped = pay(cur)
    if result == "success" then
        for _, user in ipairs(users) do MQ.Stats.add(user, "horde.wins", 1) end
        mvp(cur, users)
    end
    -- every participant counts, whatever the result (a cancel comes before the spawn, so it has none)
    for _, user in ipairs(users) do MQ.Stats.add(user, "horde.joined", 1) end
    local mine = {}
    for z, t in pairs(H.live) do
        if t.horde == cur.id then mine[#mine + 1] = { z = z, t = t } end
    end
    local clear = result == "failed" and cur.state == "active"
    local ids, x1, y1, x2, y2 = {}, nil, nil, nil, nil
    for _, e in ipairs(mine) do
        H.live[e.z] = nil
        if clear and same(e.z, e.t) and not e.z:isDead() then
            local x, y = e.z:getX(), e.z:getY()
            local ok, err = pcall(H.clearZombie, e.z)
            if ok then
                ids[#ids + 1] = e.t.onlineId
                x1, y1 = math.min(x1 or x, x), math.min(y1 or y, y)
                x2, y2 = math.max(x2 or x, x), math.max(y2 or y, y)
            else
                U.log("horde clear failed: " .. U.logSafe(err))
            end
        end
    end
    -- once, after the clear: the clients that can hold them remove their copies (Client.lua handler hordeClear).
    -- Like ZombieDeleteOnClient (ZombieDeleteOnClientPacket.java:32-35) only to players they are relevant to: a
    -- client gets zombies within relevantRange * 8 <= 96 tiles (GameServer.java:2808-2809, UdpConnection.java:224-226),
    -- and online ids are a wrapping short counter (IsoObjectID.java:48-54), so a far client may hold another zombie
    -- with one of these ids. Dedicated server only: single player has one world (cleared above) and every id is -1,
    -- which the handler would match on every zombie of the cell.
    if isServer() and #ids > 0 then
        local msg, pad = { ids = ids }, 120
        MQ.Net.eachOnline(function(p)
            local px, py = p:getX(), p:getY()
            if px >= x1 - pad and px <= x2 + pad and py >= y1 - pad and py <= y2 + pad then
                MQ.Net.send(p, "hordeClear", msg)
            end
        end)
    end
    local waves = #cur.waves
    if result == "success" then
        toast(cur, "win", { waves = waves, spawned = cur.totalSpawned, killed = cur.totalKilled, pool = pool,
            capped = capped, n = #users })
    elseif result == "failed" then
        -- the wave it failed in is the one after the cleared ones (in the rest: the next wave), as the records show
        toast(cur, "fail", { why = why, wave = cur.cleared + 1, waves = waves, cleared = cur.cleared, pool = pool,
            capped = capped })
    elseif cur.state ~= "planned" then
        toast(cur, "cancel", {})
    end
    MQ.EventLog.write("horde", nil, { id = cur.id, state = result, why = why, spawned = cur.totalSpawned,
        killed = cur.totalKilled })
    local log = h.log
    log[#log + 1] = { id = cur.id, auto = cur.auto, name = cur.name, town = cur.town, state = result, why = why,
        startMs = cur.startMs, spawnAt = cur.firstSpawnAt, endedAt = now, waves = waves, cleared = cur.cleared,
        spawned = cur.totalSpawned, killed = cur.totalKilled, pool = pool, capped = capped, paid = paid,
        kills = cur.kills, announced = cur.state ~= "planned" }
    while #log > H.LOG do table.remove(log, 1) end
    dirty()
end

-- planned -> announced (or waiting) -> waiting -> active -> rest -> waiting ... -> finish
function H.step(now)
    local cur = hordes().cur
    if cur == nil then return end
    if cur.state == "planned" and now >= cur.announceAt then
        local open = now >= cur.startMs
        cur.state = open and "waiting" or "announced"
        -- a warning this short is its own reminder
        cur.reminded = cur.startMs - now <= H.REMIND_MS
        toast(cur, open and "open" or "soon", { startMs = cur.startMs, kinds = kindsOf(cur), waves = #cur.waves })
        dirty()
    end
    if cur.state == "announced" then
        if now >= cur.startMs then
            cur.state = "waiting"
            dirty()
        elseif not cur.reminded and now >= cur.startMs - H.REMIND_MS then
            remind(cur)
        end
    end
    if cur.state == "rest" and now >= cur.nextAt then
        cur.wave, cur.state, cur.expireAt = cur.wave + 1, "waiting", now + cur.waitMin * MIN
        dirty()
    end
    if cur.state == "waiting" then
        if now >= cur.expireAt then return H.finish("failed", "nobody", now) end
        local n = H.nearCount(cur)
        if n > 0 then startWave(cur, now, n) end
    end
    if cur.state == "active" then active(cur, now) end
end

-- first tick after the store is ready: the zombies of an active horde were not kept across the restart; a rest has
-- none, so it carries on
function H.boot(now)
    H.booted = true
    H.live = {}
    local cur = hordes().cur
    if cur == nil then return end
    if cur.waves == nil then
        upgrade(cur)
        dirty()
    end
    if cur.state == "active" then H.finish("failed", "restart", now) end
end

function H.tick(now)
    if now - H.lastTick < 1000 or not MQ.Store.ready() or MQ.Store.readOnly then return end
    H.lastTick = now
    if not H.booted then H.boot(now) end
    H.roll(now, settings(), MQ.Sandbox.get("TimezoneOffset"))
    H.step(now)
end

-- OnZombieCreate (VirtualZombieManager.java:203, its only trigger): the engine hands out a zombie, maybe an object that
-- left the world and is reused (:78-99, :272). It is no longer ours; spawnAt lists a new horde zombie after this event
-- (single player has no online id to tell the two apart, see same).
function H.onZombieCreate(z)
    if z ~= nil then H.live[z] = nil end
end

function H.onZombieDead(z)
    local t = z ~= nil and H.live[z] or nil
    if t == nil then return end   -- not ours, or the second event of a burning death
    H.live[z] = nil
    local cur = hordes().cur
    if cur == nil or cur.id ~= t.horde or cur.state ~= "active" or not same(z, t) then return end
    cur.killed, cur.totalKilled = cur.killed + 1, cur.totalKilled + 1
    if cur.left > 0 then cur.left = cur.left - 1 end
    -- Kill() sets the attacker before the event fires; fire deaths have none: cleared, no kill
    local killer = z:getAttackedBy()
    local user = killer ~= nil and instanceof(killer, "IsoPlayer") and MQ.Identity.principal(killer) or nil
    if user ~= nil then
        cur.kills[user] = (cur.kills[user] or 0) + 1
        cur.waveKills[user] = (cur.waveKills[user] or 0) + 1
        cur.waveGot[user] = (cur.waveGot[user] or 0) + (cur.points[t.kind] or cur.points.vanilla or 0)
        MQ.Stats.add(user, "horde.kills", 1)
    end
    dirty()
end

-- ---------- state part, admin ops ----------

-- Sync provider "hordes": { on, cur, last }; a planned horde is secret, the last result shows for LAST_MS. on: the
-- player Hordes page is in the nav (automatic hordes on, or there are results to list)
function H.stateHordes(acc, user, now)
    local h = hordes()
    local out, cur = {}, h.cur
    if cur ~= nil and cur.state ~= "planned" and cur.waves ~= nil then
        out.cur = { id = cur.id, name = cur.name, town = cur.town, x = cur.x, y = cur.y, z = cur.z, state = cur.state,
            kinds = kindsOf(cur), announceAt = cur.announceAt, startMs = cur.startMs, expireAt = cur.expireAt,
            endsAt = cur.endsAt, nextAt = cur.nextAt, wave = cur.wave, waves = #cur.waves, size = cur.size,
            left = cur.left, killed = cur.killed, limitMin = cur.limitMin, mine = cur.kills[user] or 0,
            got = cur.got[user] or 0 }
    end
    local e = h.log[#h.log]
    if e ~= nil and e.announced ~= false and now - e.endedAt < H.LAST_MS then
        out.last = { id = e.id, name = e.name, town = e.town, state = e.state, why = e.why, endedAt = e.endedAt,
            waves = e.waves, cleared = e.cleared, spawned = e.spawned, killed = e.killed, pool = e.pool,
            capped = e.capped, mine = e.kills and e.kills[user] or 0, got = e.paid and e.paid[user] }
    end
    out.on = settings().enabled == true or #h.log > 0 or out.cur ~= nil
    return out
end

-- the last n announced results, newest first, with this player's kills and points (the records reply, design r12)
function H.recent(user, n)
    local out, log = {}, hordes().log
    for i = #log, 1, -1 do
        local e = log[i]
        if e.announced ~= false then
            out[#out + 1] = { id = e.id, name = e.name, town = e.town, state = e.state, why = e.why,
                endedAt = e.endedAt, waves = e.waves, cleared = e.cleared, spawned = e.spawned, killed = e.killed,
                mine = e.kills and e.kills[user] or 0, got = e.paid and e.paid[user] or 0 }
            if #out >= n then break end
        end
    end
    return out
end

-- sandbox ZombieConfig.ZombiesCountBeforeDelete as the server has it (42.21.0 SandboxOptions.java:2044, 0..5000,
-- 0 = off; toLua puts it under SandboxVars.ZombieConfig): above it the engine deletes far zombies without a target
-- near a player. nil when it cannot be read.
function H.cull()
    local zc = type(SandboxVars) == "table" and SandboxVars.ZombieConfig or nil
    local v = type(zc) == "table" and zc.ZombiesCountBeforeDelete or nil
    if C.isFinite(v) then return math.floor(v) end
    return nil
end

function H.status(now)
    local h, cfg = hordes(), settings()
    local tz = MQ.Sandbox.get("TimezoneOffset")
    local log = {}
    for i = #h.log, math.max(1, #h.log - 9), -1 do log[#log + 1] = h.log[i] end
    return { cur = h.cur, log = log, kinds = H.kindList(), cull = H.cull(),
        roll = { n = h.perDay[dayKey(localDay(now, tz))] or 0, max = cfg.maxPerDay, enabled = cfg.enabled,
            nextAt = H.nextRoll(cfg, now, tz, h.roll, h.perDay) } }
end

-- manual start (design r12, plan-presets-1028): announced at once, starting lead minutes later (nil / 0 = now,
-- announced as "open"), playing presetId (nil = "default"), each wave waiting wait minutes (nil = 60); not counted in
-- perDay
function H.startNow(actor, now, lead, presetId, wait)
    local h, cfg = hordes(), settings()
    if h.cur ~= nil then return false, CODE.HORDE_BUSY end
    if #cfg.spots == 0 then return false, CODE.NO_SPOTS end
    lead = lead or 0
    local cur = H.plan(cfg, now + lead * MIN, actor, { preset = presetId or "default", leadMin = lead,
        waitMin = wait or 60 })
    MQ.Config.addHistory(actor, "horde.now " .. cur.id .. " " .. cur.name, {}, false)
    H.step(now)
    return true, cur.id
end

-- planned / announced -> cancelled; waiting / active / rest -> failed "admin" (active ones are cleared)
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

MQ.Server.defineAdmin("horde.now", { kind = "mutation", fields = { lead = "int?", wait = "int?", preset = "str?" },
    run = function(ctx)
    local a = ctx.args
    if a.lead ~= nil and (a.lead < 0 or a.lead > C.LIMIT.MAX_LEAD) then return false, CODE.BAD_ARGS end
    if a.wait ~= nil and (a.wait < 1 or a.wait > 240) then return false, CODE.BAD_ARGS end
    if a.preset ~= nil and settings().presets[a.preset] == nil then return false, CODE.BAD_ARGS end
    local ok, res = H.startNow(ctx.user, ctx.now, a.lead, a.preset, a.wait)
    if not ok then return false, res end
    return true, { id = res }
end })

MQ.Server.defineAdmin("horde.stop", { kind = "mutation", fields = { id = "int" },
    run = function(ctx) return H.stop(ctx.args.id, ctx.user, ctx.now) end })

MQ.Sync.provider("hordes", H.stateHordes)

if first then
    Events.OnTickEvenPaused.Add(function() MinidoracatQuest.Hordes.tick(getTimestampMs()) end)
    Events.OnZombieDead.Add(function(z) MinidoracatQuest.Hordes.onZombieDead(z) end)
    Events.OnZombieCreate.Add(function(z) MinidoracatQuest.Hordes.onZombieCreate(z) end)
end

return H
