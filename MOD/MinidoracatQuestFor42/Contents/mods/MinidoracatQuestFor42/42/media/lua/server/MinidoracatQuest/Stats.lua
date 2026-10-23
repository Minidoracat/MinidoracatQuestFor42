-- MinidoracatQuest/Stats.lua: the only way progress enters the mod (docs/ARCHITECTURE.md sections 3.3, 5.4, C36).
-- Three scopes per account: total (across characters), life (cleared on death), season (lazy reset in Store).
-- Per-minute ceiling: wall-clock minute windows per account per stat; the excess is dropped and audited once per
-- account per stat per minute (Audit.over). Listeners run in pcall in registration order.
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

local function resolve(who)
    if type(who) == "string" then return who end
    return Q.Identity.principal(who)
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

-- amount still allowed this minute (and records the use)
local function allowance(acc, user, stat, n, ceil)
    if not C.isFinite(ceil) or ceil <= 0 then return n end
    local minute = math.floor(getTimestampMs() / 60000)
    local w = S.win[user]
    if w == nil or w.minute ~= minute then
        w = { minute = minute, used = {} }
        S.win[user] = w
    end
    local used = w.used[stat] or 0
    local allowed = ceil - used
    if allowed > n then allowed = n end
    if allowed < 0 then allowed = 0 end
    w.used[stat] = used + allowed
    if allowed < n and Q.Audit.over(user, stat, n - allowed, ceil) then
        acc.anomalies = (acc.anomalies or 0) + 1
    end
    return allowed
end

-- true, added | false. n: finite and > 0. opts.quiet: no notifications (import).
function S.add(who, stat, n, opts)
    if type(n) ~= "number" or n * 0 ~= 0 or n <= 0 or type(stat) ~= "string" then return false end
    local St = Q.Store
    if not St.ready() or St.readOnly then return false end
    local def = S.def(stat)
    if def == nil or def.kind == "max" then return false end
    local user = resolve(who)
    if user == nil then return false end
    local acc = St.account(user, true)
    if acc == nil then return false end
    local ceilings = Q.Config.get().ceilings
    local add = allowance(acc, user, stat, n, ceilings and ceilings[stat] or def.ceil)
    if add <= 0 then return false end
    acc.total[stat] = (acc.total[stat] or 0) + add
    if not def.account then acc.life[stat] = (acc.life[stat] or 0) + add end
    acc.season[stat] = (acc.season[stat] or 0) + add
    notify(acc, user, stat, add, opts)
    return true, add
end

-- Keeps the best value in each scope; listeners get delta = increase of total (0 when only life/season rose).
function S.max(who, stat, value, opts)
    if type(value) ~= "number" or value * 0 ~= 0 or value < 0 or type(stat) ~= "string" then return false end
    local St = Q.Store
    if not St.ready() or St.readOnly then return false end
    local def = S.def(stat)
    if def == nil then return false end
    local user = resolve(who)
    if user == nil then return false end
    local acc = St.account(user, true)
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

-- Import only: total = max(total, value); runs just the "achievements" listener, quietly.
function S.seed(acc, user, stat, value)
    if acc == nil or type(stat) ~= "string" or not C.isFinite(value) or value <= (acc.total[stat] or 0) then return false end
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

function S.resetLife(user)
    local acc = Q.Store.account(user, false)
    if acc == nil or Q.Store.readOnly then return end
    acc.life = {}
end

-- Players dying on the server (OnPlayerDeath never fires on a dedicated server; animals fire this too).
function S.onCharacterDeath(c)
    if not instanceof(c, "IsoPlayer") then return end
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
