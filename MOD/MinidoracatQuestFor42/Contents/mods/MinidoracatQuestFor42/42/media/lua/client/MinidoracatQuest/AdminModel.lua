-- MinidoracatQuest/AdminModel.lua: admin panel logic without UI (ARCHITECTURE.md 3.4, 6.2).
-- Config lookups over defaults + overrides + local draft, change assembly (batch multiplier, add tier,
-- tier editor, custom achievement), client-side range checks and time text in the sandbox timezone.
-- The server re-validates everything (Config.validate); these checks only save a round trip.

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
local AM = MQ.AdminModel or {}
MQ.AdminModel = AM

-- { min, max, integer } - same ranges as Config.validate (agreed with Core)
AM.RANGE = {
    pts = { 0, 10000, true }, tier = { 1, 1e9, true }, mult = { 0.1, 10 }, days = { 7, 180, true },
    target = { 1, 1e9, true }, rate = { 0.01, 1000 }, perDay = { 0, 1e6, true }, exMin = { 1, 1e6, true },
    need = { 1, 4, true }, grace = { 0, 7, true }, msDays = { 1, 365, true }, minTier = { 1, 10, true },
    perMinute = { 0, 60, true }, growth = { 0.1, 10 }, weeklyCount = { 1, 3, true }, swaps = { 0, 10, true },
    eventMult = { 1, 5 }, coord = { 0, 100000, true }, ceil = { 1, 1e6, true },
}
AM.MAX_TIERS = 10
AM.DEL = {}   -- draft marker: path removed (falls back to defaults)

-- ===== numbers =====

-- text -> value | nil, errKey, lo, hi
function AM.check(text, rangeKey)
    local r = AM.RANGE[rangeKey]
    local t = string.gsub(tostring(text or ""), "[,%s]", "")
    local v = tonumber(t)
    if v == nil or v ~= v then return nil, "IGUI_MQ_Admin_ErrNumber", r[1], r[2] end
    if (r[3] and v ~= math.floor(v)) or v < r[1] or v > r[2] then return nil, "IGUI_MQ_Admin_ErrRange", r[1], r[2] end
    return v
end

local function commas(i)
    local s = tostring(i)
    local out = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
    while out ~= s do
        s = out
        out = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
    end
    return out
end

-- 1234 -> "1,234"; 1.25 -> "1.25"
function AM.num(n)
    if type(n) ~= "number" then return "-" end
    if n == math.floor(n) and math.abs(n) < 1e15 then return commas(math.floor(n)) end
    local s = string.format("%.2f", n)
    s = string.gsub(s, "0+$", "")
    return (string.gsub(s, "%.$", ""))
end

-- 2 significant digits (new tier threshold, ARCHITECTURE.md 4.3)
function AM.round2(n)
    if n < 100 then return math.floor(n + 0.5) end
    local scale = 1
    while n / scale >= 100 do scale = scale * 10 end
    return math.floor(n / scale + 0.5) * scale
end

function AM.round10(n)
    return math.max(10, math.floor(n / 10 + 0.5) * 10)
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
function AM.roman(i) return ROMAN[i] or tostring(i) end

-- ===== tables =====

function AM.copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = AM.copy(x) end
    return out
end

function AM.same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, x in pairs(a) do if not AM.same(x, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function AM.split(path)
    local parts = {}
    for p in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = p end
    return parts
end

local function walk(t, parts, from)
    for i = from, #parts do
        if type(t) ~= "table" then return nil end
        local k = parts[i]
        local v = t[k]
        if v == nil then v = t[tonumber(k) or k] end
        t = v
    end
    return t
end

-- ===== state: defaults (Catalog.DEFAULTS), overrides (cfg.get), draft (unsent edits) =====

function AM.newDraft() return { order = {}, by = {} } end

function AM.draftSet(draft, path, value)
    if draft.by[path] == nil then draft.order[#draft.order + 1] = path end
    draft.by[path] = value
end

function AM.draftCount(draft) return #draft.order end

-- draft -> change list in edit order
function AM.draftChanges(draft)
    local out = {}
    for _, path in ipairs(draft.order) do
        local v = draft.by[path]
        if v == AM.DEL then
            out[#out + 1] = { op = "del", path = path }
        else
            out[#out + 1] = { op = "set", path = path, value = AM.copy(v) }
        end
    end
    return out
end

-- effective value at path; a draft entry on any prefix of the path wins
function AM.get(S, path)
    local parts = AM.split(path)
    local prefix
    local draft = S.draft and S.draft.by or {}
    for i = 1, #parts do
        prefix = i == 1 and parts[1] or (prefix .. "." .. parts[i])
        local d = draft[prefix]
        if d == AM.DEL then return walk(S.defaults, parts, 1) end
        if d ~= nil then return walk(d, parts, i + 1) end
    end
    local v = walk(S.overrides, parts, 1)
    if v ~= nil then return v end
    return walk(S.defaults, parts, 1)
end

-- ===== achievements =====

local function achSort(a, b)
    if a.custom ~= b.custom then return not a.custom end
    return a.order < b.order
end

-- merged list: built-in (Catalog order) then custom (by id). Each item:
-- { id, cid?, custom, cat, stat, name?, hidden, tiers, pts, titles, path }
function AM.achievements(S, catalog)
    local out = {}
    for i, a in ipairs(catalog and catalog.achievements or {}) do
        local base = "achievements." .. a.id
        out[#out + 1] = { id = a.id, cat = a.cat, stat = a.stat, hidden = a.hidden, order = i, path = base,
            tiers = AM.get(S, base .. ".tiers") or a.tiers or {},
            pts = AM.get(S, base .. ".pts") or a.pts or {},
            titles = AM.get(S, base .. ".titles") or a.titles or {},
            enabled = AM.get(S, base .. ".enabled") ~= false }
    end
    local ids = {}
    local seen = {}
    local function addIds(t)
        for cid in pairs(type(t) == "table" and t or {}) do
            if not seen[cid] then seen[cid] = true; ids[#ids + 1] = cid end
        end
    end
    addIds(S.overrides and S.overrides.custom)
    if S.draft then
        for _, path in ipairs(S.draft.order) do
            local cid = string.match(path, "^custom%.([^%.]+)$")
            if cid and not seen[cid] then seen[cid] = true; ids[#ids + 1] = cid end
        end
    end
    MQ.Util.sort(ids, AM.lt)
    for i, cid in ipairs(ids) do
        local c = AM.get(S, "custom." .. cid)
        if type(c) == "table" then
            out[#out + 1] = { id = "c:" .. cid, cid = cid, custom = true, cat = c.cat, stat = c.stat, name = c.name,
                order = i, path = "custom." .. cid, tiers = c.tiers or {}, pts = c.pts or {}, titles = c.titles or {},
                enabled = c.enabled ~= false }
        end
    end
    MQ.Util.sort(out, achSort)
    return out
end

function AM.lt(a, b) return a < b end

-- write tiers/pts/titles of one achievement into the draft (custom: the whole object); enabled = nil leaves it as it is
function AM.putAch(S, a, tiers, pts, titles, enabled)
    if a.custom then
        local obj = AM.copy(AM.get(S, a.path)) or {}
        obj.tiers, obj.pts, obj.titles = AM.copy(tiers), AM.copy(pts), AM.copy(titles or obj.titles or {})
        if enabled == false then obj.enabled = false elseif enabled then obj.enabled = nil end
        AM.draftSet(S.draft, a.path, obj)
        return
    end
    if not AM.same(tiers, a.tiers) then AM.draftSet(S.draft, a.path .. ".tiers", AM.copy(tiers)) end
    if not AM.same(pts, a.pts) then AM.draftSet(S.draft, a.path .. ".pts", AM.copy(pts)) end
    if titles ~= nil and not AM.same(titles, a.titles) then AM.draftSet(S.draft, a.path .. ".titles", AM.copy(titles)) end
    if enabled ~= nil and enabled ~= a.enabled then AM.draftSet(S.draft, a.path .. ".enabled", enabled) end
end

-- thresholds x f, kept strictly increasing and within 1..1e9; nil when the top tier overflows
function AM.scaleTiers(tiers, f)
    local out, prev = {}, 0
    for i, t in ipairs(tiers) do
        local v = math.floor(t * f + 0.5)
        if v <= prev then v = prev + 1 end
        if v > AM.RANGE.tier[2] then return nil end
        out[i], prev = v, v
    end
    return out
end

function AM.scalePts(pts, f)
    local out = {}
    for i, p in ipairs(pts) do out[i] = math.min(AM.RANGE.pts[2], math.max(0, math.floor(p * f + 0.5))) end
    return out
end

-- batch multiplier over the achievements in `selected` (a set of ids: the category shown); field "tiers" | "pts".
-- Returns number changed, list of ids skipped (overflow).
function AM.batchScale(S, list, selected, field, f)
    local n, skipped = 0, {}
    for _, a in ipairs(list) do
        if selected[a.id] then
            if field == "tiers" then
                local t = AM.scaleTiers(a.tiers, f)
                if t then AM.putAch(S, a, t, a.pts); n = n + 1 else skipped[#skipped + 1] = a.id end
            else
                AM.putAch(S, a, a.tiers, AM.scalePts(a.pts, f)); n = n + 1
            end
        end
    end
    return n, skipped
end

-- default for a new tier: threshold = last x2.5 (2 significant digits), points = last x1.5 (to 10)
function AM.nextTier(tiers, pts)
    local last = tiers[#tiers] or 0
    local t = math.max(last + 1, AM.round2(math.max(1, last) * 2.5))
    local p = math.min(AM.RANGE.pts[2], AM.round10((pts[#pts] or 0) * 1.5))
    return t, p
end

function AM.batchAddTier(S, list, selected)
    local n, skipped = 0, {}
    for _, a in ipairs(list) do
        if selected[a.id] then
            local t, p = AM.nextTier(a.tiers, a.pts)
            if #a.tiers >= AM.MAX_TIERS or t > AM.RANGE.tier[2] then
                skipped[#skipped + 1] = a.id
            else
                local tiers, pts = AM.copy(a.tiers), AM.copy(a.pts)
                local k = #tiers + 1
                tiers[k], pts[k] = t, p
                AM.putAch(S, a, tiers, pts)
                n = n + 1
            end
        end
    end
    return n, skipped
end

-- quest target {min, max} x f on the template's step (Balance.suggest rounds the same way); nil when unchanged
function AM.scaleTarget(t, f, step)
    step = step or 1
    local a = math.max(1, math.floor(t[1] * f / step + 0.5) * step)
    local b = math.max(a, math.floor((t[2] or t[1]) * f / step + 0.5) * step)
    if a > AM.RANGE.target[2] or b > AM.RANGE.target[2] then return nil end
    if a == t[1] and b == (t[2] or t[1]) then return nil end
    return { a, b }
end

-- tier editor rows { { tier = text, pts = text, title = text } } -> tiers, pts, titles | nil, errors
-- errors[i] = { field, key, lo, hi }
function AM.readTierRows(rows)
    local tiers, pts, titles, errors = {}, {}, {}, {}
    if #rows < 1 or #rows > AM.MAX_TIERS then errors[0] = { "tier", "IGUI_MQ_Admin_ErrTierCount", 1, AM.MAX_TIERS } end
    for i, r in ipairs(rows) do
        local t, key, lo, hi = AM.check(r.tier, "tier")
        if t == nil then
            errors[i] = { "tier", key, lo, hi }
        elseif i > 1 and tiers[i - 1] and t <= tiers[i - 1] then
            errors[i] = { "tier", "IGUI_MQ_Admin_ErrIncreasing" }
        end
        tiers[i] = t
        local p
        p, key, lo, hi = AM.check(r.pts, "pts")
        if p == nil and errors[i] == nil then errors[i] = { "pts", key, lo, hi } end
        pts[i] = p
        local title = string.gsub(tostring(r.title or ""), "^%s+", "")
        title = string.gsub(title, "%s+$", "")
        if title ~= "" then titles[i] = string.sub(title, 1, 64) end
    end
    for _ in pairs(errors) do return nil, errors end
    return tiers, pts, titles
end

-- new custom achievement -> path, value | nil, errKey
-- tiersText / ptsText: comma or space separated lists of the same length
function AM.customAch(id, name, cat, stat, tiersText, ptsText)
    name = string.gsub(tostring(name or ""), "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then return nil, "IGUI_MQ_Admin_ErrName" end
    if type(stat) ~= "string" or stat == "" then return nil, "IGUI_MQ_Admin_ErrStat" end
    local rows = {}
    for t in string.gmatch(tostring(tiersText or ""), "[^,;%s]+") do rows[#rows + 1] = { tier = t } end
    local i = 0
    for p in string.gmatch(tostring(ptsText or ""), "[^,;%s]+") do
        i = i + 1
        if rows[i] == nil then return nil, "IGUI_MQ_Admin_ErrPtsCount" end
        rows[i].pts = p
    end
    if i ~= #rows then return nil, "IGUI_MQ_Admin_ErrPtsCount" end
    local tiers, pts = AM.readTierRows(rows)
    if tiers == nil then
        for _, e in pairs(pts) do return nil, e[2], e[3], e[4] end
    end
    return "custom." .. id, { name = string.sub(name, 1, 64), cat = cat, stat = stat, tiers = tiers, pts = pts, titles = {} }
end

-- id for custom achievements / towns: prefix + base36(ms), matches ^[a-z0-9_]{1,32}$
function AM.newId(prefix, ms)
    local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    local n, s = math.floor(ms), ""
    repeat
        local d = n % 36
        s = string.sub(digits, d + 1, d + 1) .. s
        n = math.floor(n / 36)
    until n == 0
    return prefix .. s
end

-- ===== forms: field = { path, part = { key... }?, range, kind = "num"|"bool" } =====

local function setPart(t, part, v)
    for i = 1, #part - 1 do
        local k = part[i]
        if type(t[k]) ~= "table" then t[k] = {} end
        t = t[k]
    end
    t[part[#part]] = v
end

-- fields with values already read ({ field, value }) -> changed paths written into the draft, count.
-- A field with a default (a key inside a map, like one stat's per-minute limit) drops its key at the default value,
-- so only real changes reach the overrides.
function AM.formToDraft(S, values)
    local byPath, order = {}, {}
    for _, fv in ipairs(values) do
        local f = fv.field
        if byPath[f.path] == nil then
            order[#order + 1] = f.path
            byPath[f.path] = f.part and (AM.copy(AM.get(S, f.path)) or {}) or fv.value
        end
        local v = fv.value
        if f.part and f.default ~= nil and v == f.default then v = nil end
        if f.part then setPart(byPath[f.path], f.part, v) else byPath[f.path] = v end
    end
    local n = 0
    for _, path in ipairs(order) do
        if not AM.same(byPath[path], AM.get(S, path)) then
            AM.draftSet(S.draft, path, byPath[path])
            n = n + 1
        end
    end
    return n
end

-- target {min,max} sanity (both already range-checked)
function AM.targetOk(t) return type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and t[1] <= t[2] end

-- custom town rectangle (inclusive, corners in any order) -> { x1, y1, x2, y2 } with x1 <= x2, y1 <= y2
function AM.townRect(ax, ay, bx, by)
    return { x1 = math.min(ax, bx), y1 = math.min(ay, by), x2 = math.max(ax, bx), y2 = math.max(ay, by) }
end

-- ===== time (sandbox timezone; os.date is UTC in Kahlua, local time in standard Lua: never use it) =====

function AM.tz()
    local page = SandboxVars and SandboxVars.MinidoracatQuest
    local v = page and tonumber(page.TimezoneOffset) or 8
    return math.max(-12, math.min(14, math.floor(v)))
end

local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = m > 2 and m - 3 or m + 9
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function civilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400
    if m <= 2 then y = y + 1 end
    return y, m, d
end

local function two(n) return n < 10 and ("0" .. n) or tostring(n) end

-- ms -> "YYYY-MM-DD HH:MM" in UTC+tz
function AM.time(ms, tz)
    if type(ms) ~= "number" then return "-" end
    local mins = math.floor(ms / 60000) + (tz or AM.tz()) * 60
    local days = math.floor(mins / 1440)
    local rest = mins - days * 1440
    local y, m, d = civilFromDays(days)
    return y .. "-" .. two(m) .. "-" .. two(d) .. " " .. two(math.floor(rest / 60)) .. ":" .. two(rest % 60)
end

function AM.day(ms, tz)
    return string.sub(AM.time(ms, tz), 1, 10)
end

-- "YYYY-MM-DD" | "YYYY/M/D" -> ms of 00:00 that day in UTC+tz | nil
function AM.dayStartMs(text, tz)
    local y, m, d = string.match(tostring(text or ""), "^%s*(%d%d%d%d)[-/](%d%d?)[-/](%d%d?)%s*$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if y == nil or m < 1 or m > 12 or d < 1 then return nil end
    local nextY, nextM = y, m + 1
    if nextM > 12 then nextY, nextM = y + 1, 1 end
    if d > daysFromCivil(nextY, nextM, 1) - daysFromCivil(y, m, 1) then return nil end
    return (daysFromCivil(y, m, d) * 1440 - (tz or AM.tz()) * 60) * 60000
end

function AM.tzText(tz)
    tz = tz or AM.tz()
    return tz >= 0 and ("+" .. tz) or tostring(tz)
end

return AM
