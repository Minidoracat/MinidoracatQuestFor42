-- MinidoracatQuest/Stats.lua: the only way progress enters the mod (docs/ARCHITECTURE.md sections 3.3, 5.4, C36).
-- Three scopes per account: total (across characters), life (cleared on death), season (lazy reset in Store).
-- Per-minute ceiling: wall-clock minute windows per account per stat; the excess is dropped and audited once per
-- account per stat per minute (Audit.over), except opts.calm (facade built): its own window, dropped without an audit.
-- Listeners run in pcall in registration order.
-- Hot path: no tables or strings per call except the once-a-minute window table and the audit path.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Identity"
require "MinidoracatQuest/Audit"
require "MinidoracatQuest/Config"

local Q = MinidoracatQuest
local first = Q.Stats == nil
local S = Q.Stats or {}
Q.Stats = S
local C = Q.Contract

S.listeners = S.listeners or {}   -- { { name, fn } } in registration order
S.win = S.win or {}               -- user -> { minute, used = { [stat] = n } }

function S.listen(name, fn)
    for _, l in ipairs(S.listeners) do
        if l.name == name then l.fn = fn return end
    end
    S.listeners[#S.listeners + 1] = { name = name, fn = fn }
end

-- Catalog stat (Catalog.stats[id]) or a facade pack stat ("<modId>:<id>")
function S.def(stat)
    local cat = Q.Catalog and Q.Catalog.stats
    local d = cat and cat[stat]
    if d ~= nil then return d end
    local modId = string.match(stat, "^([^:]+):")
    local pack = modId and Q.Packs and Q.Packs[modId]
    return pack and pack.stats[stat] or nil
end

-- user name and whether it may create the account: a name (Seasons, Quests, fixtures) may; a player object only
-- counts once its hello made the account. The server's IsoPlayer for a joining client is named "Bob" (the default
-- survivor) while LevelPerk fires for its starting levels, which made one "Bob" account per server (E2E 1025g)
local function resolve(who)
    if type(who) == "string" then return who, true end
    return Q.Identity.principal(who), false
end

local function notify(acc, user, stat, delta, opts)
    for _, l in ipairs(S.listeners) do
        local ok, err = pcall(l.fn, acc, user, stat, delta, opts)
        if not ok then
            Q.Audit.throttled("LISTENER|" .. l.name, 60000, "INTERNAL", { detail = l.name .. ": " .. tostring(err) },
                getTimestampMs())
        end
    end
end

-- amount still allowed this minute (and records the use). calm: the excess is dropped without an anomaly or an audit
-- row (facade built: another mod's build flow can be faster than the vanilla pace the ceiling was set for)
local function allowance(acc, user, stat, n, ceil, calm)
    if not C.isFinite(ceil) or ceil <= 0 then return n end
    local minute = math.floor(getTimestampMs() / 60000)
    local w = S.win[user]
    if w == nil or w.minute ~= minute then
        w = { minute = minute, used = {} }
        S.win[user] = w
    end
    -- calm calls count in a window of their own: a minute of fast Build Anything tiles must not turn the next vanilla
    -- build of that minute into an anomaly (review 2026-11-15 round 2)
    local key = calm and (stat .. "|calm") or stat
    local used = w.used[key] or 0
    local allowed = ceil - used
    if allowed > n then allowed = n end
    if allowed < 0 then allowed = 0 end
    w.used[key] = used + allowed
    if allowed < n and not calm and Q.Audit.over(user, stat, n - allowed, ceil) then
        acc.anomalies = (acc.anomalies or 0) + 1
    end
    return allowed
end

-- true, added | false. n: finite and > 0. opts.quiet: no notifications (import). opts.calm: see allowance.
-- opts via ...: most callers omit it, and Kahlua does not nil-fill a missing fixed parameter (family pitfalls.md).
function S.add(who, stat, n, ...)
    local opts = ...
    if type(n) ~= "number" or n * 0 ~= 0 or n <= 0 or type(stat) ~= "string" then return false end
    local St = Q.Store
    if not St.ready() or St.readOnly then return false end
    local def = S.def(stat)
    if def == nil or def.kind == "max" then return false end
    local user, create = resolve(who)
    if user == nil then return false end
    local acc = St.account(user, create)
    if acc == nil then return false end
    local ceilings = Q.Config.get().ceilings
    local add = allowance(acc, user, stat, n, ceilings and ceilings[stat] or def.ceil, opts ~= nil and opts.calm)
    if add <= 0 then return false end
    acc.total[stat] = (acc.total[stat] or 0) + add
    if not def.account then acc.life[stat] = (acc.life[stat] or 0) + add end
    acc.season[stat] = (acc.season[stat] or 0) + add
    if Q.Report then Q.Report.seen(acc) end
    notify(acc, user, stat, add, opts)
    return true, add
end

-- Keeps the best value in each scope; listeners get delta = increase of total (0 when only life/season rose).
function S.max(who, stat, value, ...)
    local opts = ...
    if type(value) ~= "number" or value * 0 ~= 0 or value < 0 or type(stat) ~= "string" then return false end
    local St = Q.Store
    if not St.ready() or St.readOnly then return false end
    local def = S.def(stat)
    if def == nil then return false end
    local user, create = resolve(who)
    if user == nil then return false end
    local acc = St.account(user, create)
    if acc == nil then return false end
    local old = acc.total[stat] or 0
    local changed = false
    if value > old then acc.total[stat] = value; changed = true end
    if not def.account and value > (acc.life[stat] or 0) then acc.life[stat] = value; changed = true end
    if value > (acc.season[stat] or 0) then acc.season[stat] = value; changed = true end
    if not changed then return false end
    notify(acc, user, stat, value > old and value - old or 0, opts)
    return true
end

-- Import only: total = max(total, value); life = true raises the life scope the same way (a count the character
-- itself carries, e.g. its zombie kills). Runs just the "achievements" listener, quietly.
function S.seed(acc, user, stat, value, life)
    if acc == nil or type(stat) ~= "string" or not C.isFinite(value) then return false end
    if life and value > (acc.life[stat] or 0) then acc.life[stat] = value end
    if value <= (acc.total[stat] or 0) then return false end
    local old = acc.total[stat] or 0
    acc.total[stat] = value
    for _, l in ipairs(S.listeners) do
        if l.name == "achievements" then
            local ok, err = pcall(l.fn, acc, user, stat, value - old, { quiet = true, seed = true })
            if not ok then Q.Util.log("seed listener failed: " .. tostring(err)) end
        end
    end
    return true
end

-- Death: this life's stats go, and the character's starting levels (Trackers.ownBase). rules.deathWipe (owner
-- 2026-11-15, off by default) also empties the season scope and the season points: the season boards and the season
-- payout rank start over; balance, totals and achievements stay. Unlike a new season (Store lazySeason) anomalies
-- stay: a death must not clear the ceiling evidence Seasons.freeze copies into the review.
function S.resetLife(user)
    local acc = Q.Store.account(user, false)
    if acc == nil or Q.Store.readOnly then return end
    acc.life = {}
    acc.base = nil
    local rules = Q.Config.get().rules
    if not (rules and rules.deathWipe) then return end
    local lost = acc.points.season
    acc.season = {}
    acc.points.season = 0
    if Q.EventLog then Q.EventLog.write("deathWipe", user, { pts = lost }) end
    if Q.Boards then Q.Boards.dirtyPeriod("season") end
    if Q.Sync then
        Q.Sync.toast(user, { kind = "deathWipe", pts = lost })
        Q.Sync.dirty(user, "all")
    end
end

-- Players dying on the server (OnPlayerDeath never fires on a dedicated server; animals fire this too).
function S.onCharacterDeath(c)
    if not instanceof(c, "IsoPlayer") or c:isAnimal() then return end
    local user = Q.Identity.principal(c)
    if user ~= nil then S.resetLife(user) end
end

function S.prune(now)
    local minute = math.floor(now / 60000)
    for user, w in pairs(S.win) do
        if w.minute < minute then S.win[user] = nil end
    end
end

if first then
    Events.OnCharacterDeath.Add(function(c) MinidoracatQuest.Stats.onCharacterDeath(c) end)
end
