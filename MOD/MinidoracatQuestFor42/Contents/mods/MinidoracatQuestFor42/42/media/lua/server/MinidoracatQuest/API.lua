-- MinidoracatQuest/API.lua: server facade MinidoracatQuest.v1 for other mods (docs/ARCHITECTURE.md section 8).
-- Last module in the require chain: it requires every server module and assigns v1 only when all of them loaded,
-- so a consumer that sees v1 sees a working mod. Consumers probe v1.API_MAJOR == 1.
--   v1.registerPack(spec) -> pack | nil, code      pack.add(player, statId, n) -> true | false, code
-- Codes: invalid_args, rate_limited, not_ready. Stat/achievement/quest ids get the "<modId>:" prefix.
-- Registered packs live in MinidoracatQuest.Packs[modId] (shape below); Stats.def resolves pack stats from it.

if isClient() then return end

local MODULES = {
    "Contract", "Util", "Sandbox", "Store", "Identity", "Clock", "Audit", "EventLog", "Config", "Stats", "Points",
    "Net", "Sync", "Server",
    "Quests", "Achievements", "Exchange", "Seasons", "Boards", "Balance", "Report",
    "Trackers", "Towns",
}
for _, name in ipairs(MODULES) do require("MinidoracatQuest/" .. name) end

local Q = MinidoracatQuest
local first = Q.API == nil
local A = Q.API or {}
Q.API = A
local C = Q.Contract

A.CALLS_PER_TICK = 50
A.MAX_STATS, A.MAX_ACHV, A.MAX_QUESTS = 32, 64, 32
A.budget = A.budget or {}   -- modId -> calls this tick
Q.Packs = Q.Packs or {}

local PACK_CATS = { combat = true, survival = true, skill = true, life = true, explore = true, job = true }

local function idOk(s, max)
    return type(s) == "string" and #s >= 1 and #s <= max and string.find(s, "^[%w_%.%-]+$") ~= nil
end
local function keyOk(s)
    return s == nil or (type(s) == "string" and #s <= 128 and string.find(s, "^[%w_]+$") ~= nil)
end
local function list(t, max)
    if t == nil then return {} end
    if type(t) ~= "table" or #t > max then return nil end
    for k in pairs(t) do
        if not C.isInt(k) or k < 1 or k > #t then return nil end
    end
    return t
end

-- normalised pack or nil
local function normalise(spec)
    if type(spec) ~= "table" or type(spec.modId) ~= "string" or #spec.modId > 64
        or not string.find(spec.modId, "^[A-Za-z0-9_%-]+$") then
        return nil
    end
    local ns = spec.modId .. ":"
    local stats, achv, quests = list(spec.stats, A.MAX_STATS), list(spec.achievements, A.MAX_ACHV), list(spec.quests, A.MAX_QUESTS)
    if stats == nil or achv == nil or quests == nil then return nil end
    local pack = { modId = spec.modId, stats = {}, achievements = {}, quests = {}, boards = {} }
    for _, s in ipairs(stats) do
        if type(s) ~= "table" or not idOk(s.id, 64) or (s.kind ~= "count" and s.kind ~= "max") or not keyOk(s.nameKey) then return nil end
        if s.kind == "count" and (not C.isInt(s.ceil) or s.ceil < 1 or s.ceil > 1e6) then return nil end
        local id = ns .. s.id
        if pack.stats[id] then return nil end
        pack.stats[id] = { id = id, kind = s.kind, ceil = s.ceil, board = s.board == true, nameKey = s.nameKey }
        if s.board == true then
            pack.boards[#pack.boards + 1] = { id = id, cat = "job", stat = id, periods = { "season", "total" }, nameKey = s.nameKey }
        end
    end
    -- own stat ids get the prefix; built-in ids (Catalog.stats) stay as they are
    local function statRef(s)
        if not idOk(s, 96) then return nil end
        if pack.stats[ns .. s] then return ns .. s end
        if Q.Catalog and Q.Catalog.stats and Q.Catalog.stats[s] then return s end
        return nil
    end
    for _, a in ipairs(achv) do
        if type(a) ~= "table" or not idOk(a.id, 64) or not PACK_CATS[a.category] or not keyOk(a.nameKey) then return nil end
        local stat = statRef(a.stat)
        local tiers, pts = list(a.tiers, 10), list(a.points, 10)
        if stat == nil or tiers == nil or pts == nil or #tiers < 1 or #pts ~= #tiers then return nil end
        for i, t in ipairs(tiers) do
            if not C.isInt(t) or t < 1 or t > 1e9 or (i > 1 and t <= tiers[i - 1]) then return nil end
            if not C.isInt(pts[i]) or pts[i] < 0 or pts[i] > 10000 then return nil end
        end
        if a.title ~= nil and not keyOk(a.title) then return nil end
        if a.scope ~= nil and a.scope ~= "total" and a.scope ~= "life" then return nil end
        local titles = {}
        if a.title then titles[#tiers] = a.title end
        -- pack categories are a superset of the boards' words; anything not an achievement category files under job
        local cat = a.category
        if cat == "life" then cat = "job" end
        pack.achievements[#pack.achievements + 1] = { id = ns .. a.id, cat = cat, stat = stat,
            tiers = Q.Util.copy(tiers), pts = Q.Util.copy(pts), titles = titles, hidden = a.hidden == true,
            scope = a.scope or "total", nameKey = a.nameKey }
    end
    for _, q in ipairs(quests) do
        if type(q) ~= "table" or not idOk(q.id, 64) or not keyOk(q.nameKey) then return nil end
        local stat = statRef(q.stat)
        local target = list(q.target, 2)
        if stat == nil or target == nil or #target ~= 2 or not C.isInt(target[1]) or not C.isInt(target[2])
            or target[1] < 1 or target[1] > target[2] or target[2] > 1e9 then
            return nil
        end
        if q.points ~= nil and (not C.isInt(q.points) or q.points < 0 or q.points > 10000) then return nil end
        local theme = (C.isTheme(q.theme) and q.theme) or (C.isTheme(q.category) and q.category) or nil
        pack.quests[#pack.quests + 1] = { tid = ns .. q.id, theme = theme, stat = stat,
            target = { target[1], target[2] }, pts = q.points, nameKey = q.nameKey }
    end
    return pack
end

function A.registerPack(spec)
    local pack = normalise(spec)
    if pack == nil then return nil, "invalid_args" end
    Q.Packs[pack.modId] = pack
    if Q.Net.up or not isServer() then Q.Sync.catalogChanged() end
    local modId = pack.modId
    return {
        add = function(player, statId, n)
            local used = (A.budget[modId] or 0) + 1
            A.budget[modId] = used
            if used > A.CALLS_PER_TICK then return false, "rate_limited" end
            if type(n) ~= "number" or n * 0 ~= 0 or n <= 0 or n > 1000 or type(statId) ~= "string" then
                return false, "invalid_args"
            end
            if not Q.Store.ready() then return false, "not_ready" end
            local full = modId .. ":" .. statId
            local def = Q.Packs[modId] and Q.Packs[modId].stats[full]
            if def == nil then return false, "invalid_args" end
            local fn = def.kind == "max" and Q.Stats.max or Q.Stats.add
            local ok = pcall(fn, player, full, n)
            if not ok then return false, "invalid_args" end
            return true
        end,
    }
end

function A.onTick()
    A.budget = {}
end

if first then
    Events.OnTickEvenPaused.Add(function() MinidoracatQuest.API.onTick() end)
end

-- publish only when every module loaded (PZ require does not return reliably: check the globals)
local missing = {}
for _, name in ipairs(MODULES) do
    if type(Q[name]) ~= "table" then missing[#missing + 1] = name end
end
if #missing == 0 then
    Q.v1 = { API_MAJOR = 1, API_REVISION = 1, registerPack = A.registerPack }
else
    Q.v1 = nil
    Q.Util.log("facade not published, missing modules: " .. table.concat(missing, ","))
end
