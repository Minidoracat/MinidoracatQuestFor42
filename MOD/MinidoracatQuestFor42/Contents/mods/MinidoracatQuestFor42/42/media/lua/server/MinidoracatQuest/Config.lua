-- MinidoracatQuest/Config.lua: effective settings = Catalog.DEFAULTS deep-merged with root.config.overrides
-- (docs/ARCHITECTURE.md section 3.4). A change is { op = "set" | "del", path = "a.b.c", value }.
-- "set" stores value as the override at path (replacing that override subtree); "del" removes the override so the
-- default shows again. Paths use dots, so families keyed by stat id (stat ids contain dots: goal.limits, ceilings)
-- and list values (milestones, rotation, tiers, towns.custom) are whole-set only: SCHEMA marks them as leaves and
-- the merge replaces leaves instead of merging into the default.
-- Every apply records { path, before, after } of the overrides in root.history (last 20); undo writes "before"
-- back and is itself a history entry.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Audit"
require "MinidoracatQuest/Clock"

local Q = MinidoracatQuest
local Cf = Q.Config or {}
Q.Config = Cf
local C, U = Q.Contract, Q.Util
local CODE = C.CODE

Cf.MAX_CHANGES = 200
Cf.MAX_CUSTOM = 200
Cf.IMPORT_BYTES = 1000000

-- ===== validators: function(v) -> true | false, why =====

local function isArray(t, max)
    if type(t) ~= "table" then return false end
    local n = 0
    for k in pairs(t) do
        if not C.isInt(k) or k < 1 then return false end
        n = n + 1
    end
    return n == #t and n <= max
end

local function int(lo, hi)
    return function(v)
        if not C.isInt(v) or v < lo or v > hi then return false, "range" end
        return true
    end
end
local function num(lo, hi)
    return function(v)
        if not C.isFinite(v) or v < lo or v > hi then return false, "range" end
        return true
    end
end
local function bool(v)
    if type(v) ~= "boolean" then return false, "type" end
    return true
end
local function str(max)
    return function(v)
        if type(v) ~= "string" or #v < 1 or #v > max or string.find(v, "%c") then return false, "type" end
        return true
    end
end
local function oneOf(list)
    return function(v)
        for _, x in ipairs(list) do if x == v then return true end end
        return false, "value"
    end
end

local statId = str(96)
local titleId = str(64)
local ptsV = int(0, 10000)

local function tiers(v)
    if not isArray(v, 10) or #v < 1 then return false, "tiers" end
    for i, x in ipairs(v) do
        if not C.isInt(x) or x < 1 or x > 1e9 or (i > 1 and x <= v[i - 1]) then return false, "tiers" end
    end
    return true
end
local function ptsList(v)
    if not isArray(v, 10) or #v < 1 then return false, "pts" end
    for _, x in ipairs(v) do if not ptsV(x) then return false, "pts" end end
    return true
end
local function titlesMap(v)
    if type(v) ~= "table" then return false, "titles" end
    for k, x in pairs(v) do
        if not C.isInt(k) or k < 1 or k > 10 or not titleId(x) then return false, "titles" end
    end
    return true
end
local function target(v)
    if not isArray(v, 2) or #v ~= 2 then return false, "target" end
    if not C.isInt(v[1]) or not C.isInt(v[2]) or v[1] < 1 or v[2] > 1e9 or v[1] > v[2] then return false, "target" end
    return true
end
local function statList(v)
    if not isArray(v, 16) or #v < 1 then return false, "rotation" end
    for _, s in ipairs(v) do if not statId(s) then return false, "rotation" end end
    return true
end
local function limitsMap(v)
    if type(v) ~= "table" then return false, "limits" end
    for k, x in pairs(v) do
        if not statId(k) or type(x) ~= "table" then return false, "limits" end
        if not C.isInt(x.min) or not C.isInt(x.max) or x.min < 1 or x.max > 1e9 or x.min > x.max then return false, "limits" end
        if x.minContrib ~= nil and (not C.isInt(x.minContrib) or x.minContrib < 0 or x.minContrib > 1e9) then
            return false, "limits"
        end
    end
    return true
end
local function ceilingsMap(v)
    if type(v) ~= "table" then return false, "ceilings" end
    for k, x in pairs(v) do
        if not statId(k) or not C.isInt(x) or x < 1 or x > 1e6 then return false, "ceilings" end
    end
    return true
end
local function milestones(v)
    if not isArray(v, 10) then return false, "milestones" end
    for i, m in ipairs(v) do
        if type(m) ~= "table" or not C.isInt(m.days) or m.days < 1 or m.days > 365 then return false, "milestones" end
        if i > 1 and m.days <= v[i - 1].days then return false, "milestones" end
        if not ptsV(m.pts) or (m.title ~= nil and not titleId(m.title)) then return false, "milestones" end
    end
    return true
end
local LOWER_ID = "^[a-z0-9_]+$"
local function lowerId(s) return type(s) == "string" and #s >= 1 and #s <= 32 and string.find(s, LOWER_ID) ~= nil end
local function customDef(v)
    if type(v) ~= "table" then return false, "custom" end
    for k in pairs(v) do
        if k ~= "name" and k ~= "cat" and k ~= "stat" and k ~= "tiers" and k ~= "pts" and k ~= "titles" and k ~= "enabled" then
            return false, "custom"
        end
    end
    if not str(64)(v.name) or not oneOf(C.ACH_CATS)(v.cat) or not statId(v.stat) then return false, "custom" end
    if not tiers(v.tiers) or not ptsList(v.pts) or #v.pts ~= #v.tiers then return false, "custom" end
    if v.titles ~= nil and not titlesMap(v.titles) then return false, "custom" end
    if v.enabled ~= nil and type(v.enabled) ~= "boolean" then return false, "custom" end
    return true
end
local function townsCustom(v)
    if not isArray(v, 64) then return false, "towns" end
    local seen = {}
    for _, t in ipairs(v) do
        if type(t) ~= "table" or not lowerId(t.id) or seen[t.id] or not str(64)(t.name) then return false, "towns" end
        seen[t.id] = true
        if not isArray(t.rects, 16) or #t.rects < 1 then return false, "towns" end
        for _, r in ipairs(t.rects) do
            if type(r) ~= "table" then return false, "towns" end
            for _, k in ipairs({ "x1", "y1", "x2", "y2" }) do
                if not C.isInt(r[k]) or r[k] < 0 or r[k] > 100000 then return false, "towns" end
            end
            if r.x1 > r.x2 or r.y1 > r.y2 then return false, "towns" end
        end
    end
    return true
end
local function townsDisabled(v)
    if type(v) ~= "table" then return false, "towns" end
    for k, x in pairs(v) do
        if type(k) ~= "string" or #k > 64 or x ~= true then return false, "towns" end
    end
    return true
end

-- Branch tables: named children, "*" = any id key ([%w_:-], <= 64), "#" = tier key 1..10. Functions are leaves.
local POOL = { ["*"] = { enabled = bool, target = target, pts = ptsV } }
Cf.SCHEMA = {
    daily = { swapsPerDay = int(0, 10), pts = ptsV, rarePts = ptsV, sharedPts = ptsV, pool = POOL },
    weekly = { count = int(1, 3), pts = ptsV, pool = POOL },
    goal = { enabled = bool, pts = ptsV, growth = num(0.1, 10), rotation = statList, limits = limitsMap },
    streak = { need = int(1, 4), gracePerWeek = int(0, 7), milestones = milestones },
    newbie = { enabled = bool, pts = ptsV, title = titleId, days = int(1, 60) },
    achievements = { ["*"] = { enabled = bool, tiers = tiers, pts = ptsList, titles = { ["#"] = titleId } } },
    custom = { ["*lower"] = customDef },
    difficulty = { preset = oneOf({ "easy", "normal", "hard", "custom" }), mult = num(0.1, 10) },
    rewards = { top1 = ptsV, top3 = ptsV, top10 = ptsV, participation = ptsV, participationMin = ptsV, firstTitles = bool },
    exchange = { enabled = bool, rate = num(0.01, 1000), perDay = int(0, 1e6), min = int(1, 1e6) },
    broadcast = { enabled = bool, minTier = int(1, 10), perMinute = int(0, 60) },
    boards = { inactiveDays = int(7, 365), rebuildSeasonMs = int(60000, 86400000), rebuildTotalMs = int(60000, 86400000) },
    towns = { custom = townsCustom, disabled = townsDisabled },
    ceilings = ceilingsMap,
    -- season.lengthDays only changes through the season ops (section 3.4); not a config path
}

local function child(node, key)
    if type(node) ~= "table" then return nil end
    if node[key] ~= nil then return node[key] end
    if node["*"] ~= nil and type(key) == "string" and #key <= 64 and string.find(key, "^[%w_:%-]+$") then return node["*"] end
    if node["*lower"] ~= nil and lowerId(key) then return node["*lower"] end
    if node["#"] ~= nil and C.isInt(key) and key >= 1 and key <= 10 then return node["#"] end
    return nil
end

local function checkNode(node, v)
    if type(node) == "function" then return node(v) end
    if type(v) ~= "table" then return false, "type" end
    for k, x in pairs(v) do
        local c = child(node, k)
        if c == nil then return false, "unknown " .. tostring(k) end
        local ok, why = checkNode(c, x)
        if not ok then return false, why end
    end
    return true
end

-- "a.b.4" -> { "a", "b", 4 }; nil when malformed
function Cf.parsePath(path)
    if type(path) ~= "string" or #path < 1 or #path > 200 or string.find(path, "%.%.") or string.find(path, "^%.")
        or string.find(path, "%.$") then
        return nil
    end
    local segs = {}
    for seg in string.gmatch(path, "[^%.]+") do
        if not string.find(seg, "^[%w_:%-]+$") then return nil end
        segs[#segs + 1] = string.find(seg, "^%d+$") and tonumber(seg) or seg
    end
    if #segs == 0 or #segs > 6 then return nil end
    return segs
end

-- true | false, why
function Cf.validate(change)
    if type(change) ~= "table" then return false, "change" end
    for k in pairs(change) do
        if k ~= "op" and k ~= "path" and k ~= "value" then return false, "change" end
    end
    local segs = Cf.parsePath(change.path)
    if segs == nil then return false, "path" end
    local node = Cf.SCHEMA
    for _, seg in ipairs(segs) do
        node = child(node, seg)
        if node == nil then return false, "path" end
    end
    if change.op == "del" then
        if change.value ~= nil then return false, "change" end
        return true
    end
    if change.op ~= "set" or change.value == nil then return false, "change" end
    return checkNode(node, change.value)
end

-- ===== overrides tree =====

local function getAt(tree, segs)
    local t = tree
    for _, s in ipairs(segs) do
        if type(t) ~= "table" then return nil end
        t = t[s]
    end
    return t
end

local function setAt(tree, segs, value)
    local t = tree
    for i = 1, #segs - 1 do
        if type(t[segs[i]]) ~= "table" then t[segs[i]] = {} end
        t = t[segs[i]]
    end
    t[segs[#segs]] = value
end

local function delAt(tree, segs)
    local chain, t = {}, tree
    for i = 1, #segs - 1 do
        t = t[segs[i]]
        if type(t) ~= "table" then return end
        chain[i] = t
    end
    t[segs[#segs]] = nil
    for i = #segs - 1, 1, -1 do
        if not Q.Store.isEmpty(chain[i]) then break end
        local parent = i == 1 and tree or chain[i - 1]
        parent[segs[i]] = nil
    end
end

local function merge(dst, src, node)
    for k, v in pairs(src) do
        local c = child(node, k)
        if type(v) == "table" and type(dst[k]) == "table" and type(c) == "table" then
            merge(dst[k], v, c)
        else
            dst[k] = U.copy(v)
        end
    end
    return dst
end

function Cf.defaults()
    return Q.Catalog and Q.Catalog.DEFAULTS or {}
end

function Cf.overrides()
    local St = Q.Store
    if not St.ready() then return {} end
    return St.root().config.overrides
end

local function effective(overrides)
    return merge(U.copy(Cf.defaults()), overrides, Cf.SCHEMA)
end

-- Effective settings; cached until the next apply. Callers must not modify the result.
function Cf.get()
    local St = Q.Store
    local rev = St.ready() and St.root().config.rev or -1
    local defaults = Cf.defaults()
    if Cf.cache == nil or Cf.cacheRev ~= rev or Cf.cacheDefaults ~= defaults then
        Cf.cache = effective(Cf.overrides())
        Cf.cacheRev, Cf.cacheDefaults = rev, defaults
    end
    return Cf.cache
end

function Cf.invalidate()
    Cf.cache = nil
end

local function validateAll(changes)
    if not isArray(changes, Cf.MAX_CHANGES) or #changes < 1 then return false, { why = "changes" } end
    for i, ch in ipairs(changes) do
        local ok, why = Cf.validate(ch)
        if not ok then return false, { index = i, path = type(ch) == "table" and ch.path or nil, why = why } end
    end
    -- custom achievement count limit on the resulting overrides
    local after = U.copy(Cf.overrides())
    for _, ch in ipairs(changes) do
        local segs = Cf.parsePath(ch.path)
        if ch.op == "set" then setAt(after, segs, U.copy(ch.value)) else delAt(after, segs) end
    end
    local n = 0
    for _ in pairs(after.custom or {}) do n = n + 1 end
    if n > Cf.MAX_CUSTOM then return false, { why = "custom count" } end
    return true, after
end

-- true, rows | false, BAD_CONFIG, detail. rows = { { path, before, after } } on effective values.
function Cf.preview(changes)
    local ok, after = validateAll(changes)
    if not ok then return false, CODE.BAD_CONFIG, after end
    local nowEff, nextEff = Cf.get(), effective(after)
    local rows = {}
    for _, ch in ipairs(changes) do
        local segs = Cf.parsePath(ch.path)
        rows[#rows + 1] = { path = ch.path, before = U.copy(getAt(nowEff, segs)), after = U.copy(getAt(nextEff, segs)) }
    end
    return true, rows
end

local function pushHistory(actor, summary, changes, undoable)
    local root = Q.Store.root()
    local cfg = root.config
    cfg.histSeq = (cfg.histSeq or 0) + 1
    local h = root.history
    h[#h + 1] = { id = cfg.histSeq, at = getTimestampMs(), actor = actor, summary = summary, changes = changes,
        undoable = undoable ~= false }
    while #h > C.LIMIT.HISTORY do table.remove(h, 1) end
    return cfg.histSeq
end

function Cf.addHistory(actor, summary, changes, undoable)
    if not Q.Store.ready() or Q.Store.readOnly then return nil end
    return pushHistory(actor, summary, changes or {}, undoable)
end

-- writes changes (already validated); returns history id, rev
local function write(changes, summary, actor)
    local root = Q.Store.root()
    local ov = root.config.overrides
    local rec, boards = {}, false
    for _, ch in ipairs(changes) do
        local segs = Cf.parsePath(ch.path)
        local before = U.copy(getAt(ov, segs))
        if ch.op == "set" then setAt(ov, segs, U.copy(ch.value)) else delAt(ov, segs) end
        rec[#rec + 1] = { path = ch.path, before = before, after = U.copy(getAt(ov, segs)) }
        if segs[1] == "boards" then boards = true end
    end
    root.config.rev = root.config.rev + 1
    Cf.invalidate()
    local id = pushHistory(actor, summary, rec, true)
    if Q.Sync and Q.Sync.catalogChanged then Q.Sync.catalogChanged() end
    -- rebuild every board on the next ticks, so a new interval / inactiveDays applies now instead of after the
    -- rebuild already scheduled with the old interval (up to 24 h)
    if boards and Q.Boards then Q.Boards.dirtyAll() end
    return id, root.config.rev
end

-- true, historyId, rev | false, code, detail
function Cf.apply(changes, summary, actor)
    if not Q.Store.ready() or Q.Store.readOnly then return false, CODE.NOT_READY end
    local ok, detail = validateAll(changes)
    if not ok then return false, CODE.BAD_CONFIG, detail end
    local id, rev = write(changes, type(summary) == "string" and summary or "", actor)
    return true, id, rev
end

function Cf.undo(historyId, actor)
    if not Q.Store.ready() or Q.Store.readOnly then return false, CODE.NOT_READY end
    local entry
    for _, h in ipairs(Q.Store.root().history) do if h.id == historyId then entry = h end end
    if entry == nil then return false, CODE.NOT_FOUND end
    if entry.undoable == false then return false, CODE.BAD_CONFIG end
    local changes = {}
    for i = #entry.changes, 1, -1 do
        local r = entry.changes[i]
        if r.before == nil then changes[#changes + 1] = { op = "del", path = r.path }
        else changes[#changes + 1] = { op = "set", path = r.path, value = r.before } end
    end
    if #changes == 0 then return false, CODE.BAD_CONFIG end
    local id, rev = write(changes, "undo #" .. tostring(historyId), actor)
    return true, id, rev
end

function Cf.historyRows()
    local rows = {}
    if not Q.Store.ready() then return rows end
    for _, h in ipairs(Q.Store.root().history) do
        rows[#rows + 1] = { id = h.id, at = h.at, actor = h.actor, summary = h.summary, n = #(h.changes or {}),
            undoable = h.undoable }
    end
    return rows
end

-- ===== export / import (private files, section 3.5) =====

local function pad2(n) return n < 10 and ("0" .. n) or tostring(n) end

-- true, fileName | false, code
function Cf.export()
    local t = getTimestampMs()
    local y, m, d = Q.Clock.civil(math.floor(t / 86400000))
    local s = math.floor(t / 1000) % 86400
    local name = string.format("export-%d%s%s-%s%s%s.json", y, pad2(m), pad2(d),
        pad2(math.floor(s / 3600)), pad2(math.floor(s / 60) % 60), pad2(s % 60))
    local text = U.encode(Cf.overrides())
    if text == nil or not Q.Store.writeLines(Q.Store.path(name), { text }, false) then return false, CODE.FILE_ERROR end
    local back = Q.Store.readLines(Q.Store.path(name), 100000)
    if type(back) ~= "table" or table.concat(back, "\n") ~= text then return false, CODE.FILE_ERROR end
    return true, name
end

-- Reads import.json (an overrides tree as written by export) and turns it into top-level changes:
-- set every family in the file, del every current family missing from it. true, changes, rows | false, code, detail
function Cf.import()
    local lines = Q.Store.readLines(Q.Store.path("import.json"), 100000)
    if lines == nil then return false, CODE.NOT_FOUND end
    if lines == false then return false, CODE.FILE_ERROR end
    local tree, err = U.decode(table.concat(lines, "\n"), Cf.IMPORT_BYTES)
    if type(tree) ~= "table" then return false, CODE.BAD_CONFIG, { why = err or "json" } end
    local changes = {}
    for k, v in pairs(tree) do
        changes[#changes + 1] = { op = "set", path = tostring(k), value = v }
    end
    for k in pairs(Cf.overrides()) do
        if tree[k] == nil then changes[#changes + 1] = { op = "del", path = tostring(k) } end
    end
    U.sort(changes, function(a, b) return a.path < b.path end)
    if #changes == 0 then return false, CODE.BAD_CONFIG, { why = "empty" } end
    local ok, rows, detail = Cf.preview(changes)
    if not ok then return false, rows, detail end
    return true, changes, rows
end
