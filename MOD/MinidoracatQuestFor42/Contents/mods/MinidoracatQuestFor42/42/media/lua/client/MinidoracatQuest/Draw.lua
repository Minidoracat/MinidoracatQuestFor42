-- MinidoracatQuest/Draw.lua: shared client UI kit (player pages and the admin pages).
--   UI framework probe (MIN_REV 22, per-capability), theme with this MOD's semantic tokens, text and number
--   formatting, and a display-list Canvas: pages build draw ops at layout time (strings and tables are made
--   there), render only walks the list and culls ops outside the scroll view. Buttons and other controls are
--   real framework widgets, pooled by key so a relayout reuses them.
--   UI classes are derived lazily (first window open), so the offline harness can load this file.

if isServer() then return end

require "MinidoracatQuest/Client"

local Q = MinidoracatQuest
local C = Q.Client
local D = Q.Draw or {}
Q.Draw = D

D.MIN_REV = 22
D.PAD, D.GAP = 12, 8

-- ===== framework probe (ARCHITECTURE 7; UI repo ARCHITECTURE 2) =====
function D.ui(caps)
    if not (MinidoracatUI and MinidoracatUI.v1) then pcall(require, "MinidoracatUI/V1") end
    local UI = MinidoracatUI and MinidoracatUI.v1
    if UI == nil or UI.API_MAJOR ~= 1 or (UI.API_REVISION or 0) < D.MIN_REV then return nil end
    local have = UI.CAPABILITIES or {}
    for _, cap in ipairs(caps or {}) do
        if have[cap] ~= true then return nil end
    end
    return UI
end

function D.has(UI, cap) return UI ~= nil and UI.CAPABILITIES ~= nil and UI.CAPABILITIES[cap] == true end

-- ===== colors: green done, gold emphasis, orange warning, red danger, blue server-wide, purple event =====
local function rgb(r, g, b) return { r = r, g = g, b = b, a = 1 } end
D.TIER = {
    rgb(0.85, 0.58, 0.42),   -- 1 bronze  #d9956a
    rgb(0.79, 0.82, 0.85),   -- 2 silver  #c9d1d9
    rgb(0.91, 0.76, 0.35),   -- 3 gold    #e8c25a
    rgb(0.56, 0.89, 0.87),   -- 4 platinum #8fe3df
    rgb(1.0, 0.56, 0.69),    -- 5+ legend #ff8fb1
}
D.EXTRA = {
    success = rgb(0.40, 0.82, 0.48),
    info = rgb(0.45, 0.68, 1.0),
    event = rgb(0.74, 0.55, 1.0),
    gold = rgb(0.91, 0.76, 0.35),
    legend = D.TIER[5],
    tier1 = D.TIER[1], tier2 = D.TIER[2], tier3 = D.TIER[3], tier4 = D.TIER[4], tier5 = D.TIER[5],
    -- admin report: players with activity / players who finished a daily quest (bars, legend, their big numbers);
    -- blue and orange stay apart for colour-blind readers (user's pick, 2026-10-25)
    reportActive = rgb(0.45, 0.68, 1.0),
    reportDone = rgb(1.0, 0.62, 0.30),
    -- hordes (plan r10): red while it runs, orange while it is announced or waits for players
    horde = rgb(1.0, 0.48, 0.35),
    hordeSoon = rgb(0.94, 0.63, 0.31),
}

function D.theme(UI)
    if D._theme ~= nil and D._themeUI == UI then return D._theme end
    D._theme, D._themeUI = UI.Theme.create({ variant = "dark", colors = D.EXTRA }), UI
    return D._theme
end

function D.tierColor(tier)
    tier = math.floor(tonumber(tier) or 1)
    if tier < 1 then tier = 1 end
    return D.TIER[math.min(tier, 5)]
end

-- ===== text =====
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- The spare "" argument: getTextOrNull formats the text, and a key with %1 but no argument prints a
-- missing-argument warning with a stack trace each call (Translator.java:513-522, 538-541).
function D.textOrNull(key)
    if getTextOrNull then return getTextOrNull(key, "") end
    local t = getText(key)
    if t == key then return nil end
    return t
end

function D.tierName(tier)
    tier = math.floor(tonumber(tier) or 1)
    if tier >= 1 and tier <= 4 then return getText("IGUI_MQ_Tier_" .. tier) end
    return getText("IGUI_MQ_Tier_Legend", ROMAN[tier] or tostring(tier))
end

-- season titles are s<no>_<kind> (catalog convention); admin titles may be free text
function D.titleText(id)
    if id == nil or id == "" then return "" end
    id = tostring(id)
    local no, kind = string.match(id, "^s(%d+)_(.+)$")
    if no ~= nil then
        local t = D.textOrNull("IGUI_MQ_Title_season_" .. kind)
        if t ~= nil then return getText("IGUI_MQ_Title_season_" .. kind, no) end
    end
    return D.textOrNull("IGUI_MQ_Title_" .. id) or id
end

function D.codeText(code)
    local t = D.textOrNull("IGUI_MQ_Code_" .. tostring(code))
    if t ~= nil then return t end
    return getText("IGUI_MQ_UI_CodeGeneric", tostring(code))
end

-- thousands separator: "," or a no-break space per language (IGUI_MQ_UI_ThousandSep); "," when the key has no
-- text (the offline harness). The decimal point stays ".".
function D.sep()
    local s = getText("IGUI_MQ_UI_ThousandSep")
    return s ~= "IGUI_MQ_UI_ThousandSep" and s or ","
end

-- 1234567 -> "1,234,567"; non-integers keep one decimal
function D.num(n)
    n = tonumber(n) or 0
    local neg = n < 0
    if neg then n = -n end
    local whole = math.floor(n)
    local frac = ""
    local tenth = math.floor((n - whole) * 10 + 0.5)
    if tenth >= 10 then
        whole, tenth = whole + 1, 0
    end
    if tenth > 0 then frac = "." .. tostring(tenth) end
    local s = tostring(whole)
    if string.find(s, "[eE%.]") then s = string.format("%.0f", whole) end
    local out, sep = "", #s > 3 and D.sep() or nil
    while #s > 3 do
        out = sep .. string.sub(s, -3) .. out
        s = string.sub(s, 1, -4)
    end
    return (neg and "-" or "") .. s .. out .. frac
end

function D.mult(m)
    m = tonumber(m) or 1
    if m == math.floor(m) then return tostring(math.floor(m)) end
    return string.format("%.1f", m)
end

function D.statName(stat)
    local s = C.defs().stats[stat]
    if type(s) == "table" and type(s.nameKey) == "string" then return getText(s.nameKey) end
    local Cat = Q.Catalog
    local key = (Cat and Cat.statKey) and Cat.statKey(stat) or ("IGUI_MQ_Stat_" .. string.gsub(tostring(stat), "[%.:]", "_"))
    return getText(key)
end

function D.statUnit(stat)
    local s = C.defs().stats[stat]
    return type(s) == "table" and s.unit or "count"
end

function D.themeName(theme)
    if theme == nil or theme == "all" then return getText("IGUI_MQ_UI_ThemeAll") end
    return getText("IGUI_MQ_Theme_" .. tostring(theme))
end

function D.achName(a)
    if a == nil then return "" end
    if a.kind == "custom" then return tostring(a.name or a.id) end
    if a.nameKey ~= nil then return getText(a.nameKey) end
    return getText("IGUI_MQ_Ach_" .. a.id)
end

-- description of reaching tier t (threshold as %1)
function D.achDesc(a, tier)
    if a == nil then return "" end
    local th = D.num(a.tiers[tier] or a.tiers[#a.tiers] or 0)
    if a.kind == "builtin" then return getText("IGUI_MQ_AchDesc_" .. a.id, th) end
    if a.descKey ~= nil then return getText(a.descKey, th) end
    return getText("IGUI_MQ_UI_AchDescStat", D.statName(a.stat), th)
end

function D.achHint(a)
    if a.kind == "builtin" then return getText("IGUI_MQ_AchHint_" .. a.id) end
    return getText("IGUI_MQ_UI_AchHintGeneric")
end

-- ===== titles (plan r13): every title and what earns it; the admin Titles tab and "My titles" on Records =====
local RANK_KEY = { top1 = "IGUI_MQ_UI_RewardTop1", top3 = "IGUI_MQ_UI_RewardTop3", top10 = "IGUI_MQ_UI_RewardTop10" }
local RANKS = { "top1", "top3", "top10" }

-- "s<no>_top1" / "s<no>_first_<board>" (Seasons.lua pay) -> a row; nil for any other id or a board no longer
-- defined (a removed pack's): the caller shows "source removed" instead of a raw key
function D.seasonTitle(id, cfg)
    local no, kind = string.match(id, "^s(%d+)_(.+)$")
    if no == nil then return nil end
    local board = string.match(kind, "^first_(.+)$")
    local cond
    if board ~= nil then
        local b = C.defs().boardById[board]
        if b == nil then return nil end
        cond = getText("IGUI_MQ_UI_TitleCondFirst", no, b.nameKey ~= nil and getText(b.nameKey) or getText("IGUI_MQ_Board_" .. board))
    elseif RANK_KEY[kind] ~= nil then
        cond = getText("IGUI_MQ_UI_TitleCondRank", no, getText(RANK_KEY[kind]))
    else
        return nil
    end
    local rw = type(cfg.rewards) == "table" and cfg.rewards or {}
    return { id = id, name = D.titleText(id), group = "season", cond = cond,
        off = board ~= nil and rw.firstTitles == false or nil }
end

local function seasonBoard(b)
    if b.stat == "@points" then return false end   -- its #1 is the season's top1 (Seasons.lua freeze)
    for _, p in ipairs(type(b.periods) == "table" and b.periods or {}) do
        if p == "season" then return true end
    end
    return false
end

-- what earns tier t of achievement a (an entry as C.defs builds it)
function D.achTitleCond(a, t)
    local desc = D.achDesc(a, t)
    if #a.tiers == 1 then return getText("IGUI_MQ_UI_TitleCondOne", D.achName(a), desc) end
    return getText("IGUI_MQ_UI_TitleCond", D.achName(a), D.tierName(t), desc)
end

-- the streak milestone condition (also for a recorded "streak:<days>" source)
function D.streakTitleCond(days, cfg)
    local sk = type(cfg.streak) == "table" and cfg.streak or {}
    return getText("IGUI_MQ_UI_TitleCondStreak", tostring(days), tostring(sk.need or 3))
end

function D.newbieTitleCond(cfg)
    local nb = type(cfg.newbie) == "table" and cfg.newbie or {}
    return getText("IGUI_MQ_UI_TitleCondNewbie", tostring(nb.days or 7))
end

-- achs: achievement entries as C.defs builds them (the admin passes its draft view): id, kind, cat, hidden, tiers,
-- titles, defTitles (the titles before admin edits), off; cfg: streak, newbie, rewards; no: the season number.
-- Rows in catalog order: { id, name, group, cond, ach?, tier?, hidden?, hint?, off?, custom?, alt? }. ach / tier:
-- the source achievement and tier; custom: the admin replaced the default text; alt: that default id, so a player
-- who got it before the edit still finds the condition.
function D.titleSources(achs, cfg, no)
    local out = {}
    for _, a in ipairs(achs) do
        for t = 1, #a.tiers do
            local id = a.titles[t]
            if id ~= nil then
                local def = a.defTitles and a.defTitles[t]
                out[#out + 1] = { id = id, name = D.titleText(id), group = a.kind == "custom" and "custom" or a.cat,
                    cond = D.achTitleCond(a, t),
                    ach = a.id, tier = t, hidden = a.hidden or nil, hint = a.hidden and D.achHint(a) or nil, off = a.off,
                    custom = a.defTitles ~= nil and def ~= id or nil, alt = def ~= id and def or nil }
            end
        end
    end
    local sk = type(cfg.streak) == "table" and cfg.streak or {}
    for _, m in ipairs(type(sk.milestones) == "table" and sk.milestones or {}) do
        if m.title ~= nil then
            out[#out + 1] = { id = m.title, name = D.titleText(m.title), group = "other",
                cond = D.streakTitleCond(m.days, cfg) }
        end
    end
    local nb = type(cfg.newbie) == "table" and cfg.newbie or {}
    if nb.title ~= nil then
        out[#out + 1] = { id = nb.title, name = D.titleText(nb.title), group = "other",
            cond = D.newbieTitleCond(cfg), off = nb.enabled == false or nil }
    end
    for _, k in ipairs(RANKS) do out[#out + 1] = D.seasonTitle("s" .. no .. "_" .. k, cfg) end
    for _, b in ipairs(C.defs().boards) do
        if seasonBoard(b) then out[#out + 1] = D.seasonTitle("s" .. no .. "_first_" .. b.id, cfg) end
    end
    return out
end

-- quest name with arg as %1 (a number, or a range on the Settings quest list)
function D.questText(tid, arg)
    local t = C.defs().daily[tid]
    if type(t) == "table" and type(t.nameKey) == "string" then return getText(t.nameKey, arg) end
    return getText("IGUI_MQ_Q_" .. tostring(tid), arg)
end

function D.questName(q)
    if q == nil then return "" end
    return D.questText(q.tid, D.num(q.target or 0))
end

-- ===== dates (sandbox TimezoneOffset; Kahlua os.date is fixed UTC, so compute the civil date ourselves) =====
function D.tzHours()
    local sv = SandboxVars and SandboxVars.MinidoracatQuest
    local tz = sv and tonumber(sv.TimezoneOffset) or 8
    return tz
end

-- ms -> year, month, day, hour, minute, weekday (1 = Monday); Hinnant days_from_civil inverse
function D.civil(ms)
    local t = math.floor(((tonumber(ms) or 0) + D.tzHours() * 3600000) / 1000)
    local days = math.floor(t / 86400)
    local secs = t - days * 86400
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    local wday = (days + 3) % 7 + 1
    return y, m, d, math.floor(secs / 3600), math.floor((secs % 3600) / 60), wday
end

function D.date(ms)
    local _, m, d, _, _, wd = D.civil(ms)
    return getText("IGUI_MQ_UI_Date", tostring(m), tostring(d), getText("IGUI_MQ_UI_Weekday_" .. wd))
end

-- full date with the year (a title list spans seasons)
function D.ymd(ms)
    local y, m, d = D.civil(ms)
    return getText("IGUI_MQ_UI_DateYMD", tostring(y), string.format("%02d", m), string.format("%02d", d))
end

function D.clock(ms)
    local _, _, _, hh, mm = D.civil(ms)
    return string.format("%02d:%02d", hh, mm)
end

function D.dateTime(ms)
    return getText("IGUI_MQ_UI_DateTime", D.date(ms), D.clock(ms))
end

-- "1 day" / "N days" (the singular keys exist for languages that inflect; the others repeat the plural)
function D.days(n) return getText(n == 1 and "IGUI_MQ_UI_Day1" or "IGUI_MQ_UI_Days", tostring(n)) end

-- remaining time, coarse: days, else hours, else minutes (at least 1)
function D.duration(ms)
    ms = tonumber(ms) or 0
    if ms >= 86400000 then return D.days(math.floor(ms / 86400000)) end
    if ms >= 3600000 then
        local h = math.floor(ms / 3600000)
        return getText(h == 1 and "IGUI_MQ_UI_Hour1" or "IGUI_MQ_UI_Hours", tostring(h))
    end
    return getText("IGUI_MQ_UI_Minutes", tostring(math.max(1, math.ceil(ms / 60000))))
end

function D.left(endsAt)
    return math.max(0, (tonumber(endsAt) or 0) - C.serverNow())
end

-- ===== measuring =====
function D.fontH(font) return getTextManager():getFontHeight(font or UIFont.Small) end
function D.textW(text, font) return getTextManager():MeasureStringX(font or UIFont.Small, text) end

function D.wrap(UI, text, maxW, font)
    if D.has(UI, "textWrap") and type(UI.Text.wrap) == "function" then return UI.Text.wrap(text, maxW, font) end
    return { UI.Text.fit(text, maxW, font) }
end

function D.fit(UI, text, maxW, font) return UI.Text.fit(text, maxW, font) end

-- ===== textures =====
D.texCache = D.texCache or {}
function D.tex(path)
    local t = D.texCache[path]
    if t == nil then
        local ok, tex = pcall(getTexture, path)
        t = ok and tex or false
        D.texCache[path] = t
    end
    return t or nil
end

-- ===== toast (framework Toast; without it a halo line over the player) =====
-- up to 6 message lines: the horde warning (waves, the edges rule, then the kinds) and the capped win / reward cut
-- their last words at 4 in EN and ES (quest-hui-*-1027b)
function D.toast(title, message, border)
    local UI = D.ui({ "toast" })
    if UI ~= nil and UI.Toast ~= nil then
        UI.Toast.show({ title = title, message = message ~= "" and message or title, maxLines = 6,
            colors = border and { border = border } or nil })
        return
    end
    local p = getSpecificPlayer(0)
    if p ~= nil and HaloTextHelper then
        local line = title
        if message ~= nil and message ~= "" and message ~= title then line = title .. " - " .. message end
        HaloTextHelper.addText(p, line)
    end
end

-- ===== Canvas: display list =====
local OP_FILL, OP_BORDER, OP_TEXT, OP_TEXTR, OP_TEXTC, OP_TEX, OP_ICON, OP_RECT, OP_DOT, OP_ARROW =
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10

local function drawOp(self, o, Skin, UI)
    local k, c = o.k, o.c
    if k == OP_TEXT then
        self:drawText(o.s, o.x, o.y, c.r, c.g, c.b, c.a or 1, o.f)
    elseif k == OP_FILL then
        Skin.fill(self, o.x, o.y, o.w, o.h, c, o.s)
    elseif k == OP_BORDER then
        Skin.border(self, o.x, o.y, o.w, o.h, c, o.s)
    elseif k == OP_RECT then
        self:drawRect(o.x, o.y, o.w, o.h, c.a or 1, c.r, c.g, c.b)
    elseif k == OP_TEXTR then
        self:drawTextRight(o.s, o.x, o.y, c.r, c.g, c.b, c.a or 1, o.f)
    elseif k == OP_TEXTC then
        self:drawTextCentre(o.s, o.x, o.y, c.r, c.g, c.b, c.a or 1, o.f)
    elseif k == OP_TEX then
        self:drawTextureScaledAspect(o.s, o.x, o.y, o.w, o.h, 1, 1, 1, 1)
    elseif k == OP_ICON then
        if not UI.Icons.draw(self, o.s, o.x, o.y, o.w, c) and o.f ~= nil then
            self:drawTextCentre(o.f, o.x + o.w / 2, o.y, c.r, c.g, c.b, c.a or 1, UIFont.Small)
        end
    elseif k == OP_DOT then
        Skin.dot(self, o.x, o.y, o.w, c, o.s)
    elseif k == OP_ARROW then
        Skin.arrow(self, o.x, o.y, o.s, c)
    end
end

local function canvasRender(self)
    local ops, n = self.ops, self.n or 0
    if n == 0 then return end
    local UI = self.UI
    local Skin = UI.Skin
    local top, bottom = -1, 1e9
    local p = self.parent
    if p ~= nil and p.getYScroll ~= nil then
        top = -p:getYScroll() - self:getY()
        bottom = top + p:getHeight()
    end
    for i = 1, n do
        local o = ops[i]
        if o.y + o.h >= top and o.y <= bottom then drawOp(self, o, Skin, UI) end
    end
    -- full text of truncated names under the mouse
    local tips = self.tips
    if tips ~= nil and #tips > 0 and self:isMouseOver() then
        local mx, my = self:getMouseX(), self:getMouseY()
        for i = 1, #tips do
            local t = tips[i]
            if mx >= t.x and mx < t.x + t.w and my >= t.y and my < t.y + t.h then
                local w = t.tw + 12
                local x = math.min(mx + 12, self.width - w)
                local y = t.y + t.h
                self:drawRect(x, y, w, t.th + 6, 0.95, 0.05, 0.05, 0.05)
                self:drawRectBorder(x, y, w, t.th + 6, 1, 0.4, 0.4, 0.4)
                self:drawText(t.text, x + 6, y + 3, 1, 1, 1, 1, UIFont.Small)
                break
            end
        end
    end
end
D.renderOps = canvasRender   -- any element with UI / theme / ops / n / tips (the tracker panel draws with it)

function D.newCanvas(UI, theme)
    if D.Canvas == nil then
        D.Canvas = ISUIElement:derive("MinidoracatQuestCanvas")
        D.Canvas.render = canvasRender
    end
    local c = D.Canvas:new(0, 0, 10, 10)
    c:initialise()
    c.UI, c.theme, c.ops, c.n, c.tips = UI, theme, {}, 0, {}
    return c
end

-- Builder: one per layout pass; every method appends an op and returns something useful for placement
local B = D.Builder or {}
D.Builder = B
B.__index = B

function D.begin(canvas)
    canvas.ops, canvas.n, canvas.tips = {}, 0, {}
    return setmetatable({ cv = canvas, UI = canvas.UI, theme = canvas.theme, colors = canvas.theme.colors }, B)
end

function B:op(k, x, y, w, h, c, s, f)
    local cv = self.cv
    cv.n = cv.n + 1
    cv.ops[cv.n] = { k = k, x = x, y = y, w = w, h = h, c = c, s = s, f = f }
end

function B:col(token)
    if type(token) == "table" then return token end
    return self.colors[token or "text"] or self.colors.text
end

function B:fill(x, y, w, h, token, shape) self:op(OP_FILL, x, y, w, h, self:col(token), shape) end
function B:border(x, y, w, h, token, shape) self:op(OP_BORDER, x, y, w, h, self:col(token), shape) end
function B:rect(x, y, w, h, token) self:op(OP_RECT, x, y, w, h, self:col(token)) end

-- returns text width
function B:text(x, y, s, token, font)
    font = font or UIFont.Small
    self:op(OP_TEXT, x, y, D.textW(s, font), D.fontH(font), self:col(token), s, font)
    return D.textW(s, font)
end

function B:textRight(xRight, y, s, token, font)
    font = font or UIFont.Small
    local w = D.textW(s, font)
    self:op(OP_TEXTR, xRight, y, w, D.fontH(font), self:col(token), s, font)
    return w
end

function B:textCentre(xMid, y, s, token, font)
    font = font or UIFont.Small
    self:op(OP_TEXTC, xMid, y, 1, D.fontH(font), self:col(token), s, font)
end

-- text fitted to maxW; a truncated one gets a hover tip with the full text. Returns drawn width
function B:fitText(x, y, s, maxW, token, font)
    font = font or UIFont.Small
    local shown = D.fit(self.UI, s, maxW, font)
    local w = self:text(x, y, shown, token, font)
    if shown ~= s then
        local tips = self.cv.tips
        tips[#tips + 1] = { x = x, y = y, w = math.max(w, 1), h = D.fontH(font), text = s, tw = D.textW(s, UIFont.Small),
            th = D.fontH(UIFont.Small) }
    end
    return w
end

-- wrapped paragraph; returns the y below it
function B:para(x, y, s, maxW, token, font)
    font = font or UIFont.Small
    local lh = D.fontH(font)
    for _, line in ipairs(D.wrap(self.UI, s, maxW, font)) do
        self:text(x, y, line, token, font)
        y = y + lh + 2
    end
    return y
end

function B:tex(x, y, w, h, texture) self:op(OP_TEX, x, y, w, h, self.colors.text, texture) end
function B:icon(x, y, size, key, token, fallbackText) self:op(OP_ICON, x, y, size, size, self:col(token), key, fallbackText) end
function B:dot(x, y, size, token, outline) self:op(OP_DOT, x, y, size, size, self:col(token), outline and self:col(outline) or nil) end
function B:arrow(x, y, up, token) self:op(OP_ARROW, x, y, 7, 4, self:col(token), up) end

D.CHIP_PADX = 8
function D.chipH() return D.fontH(UIFont.Small) + 6 end
function D.chipW(s) return D.textW(s, UIFont.Small) + 2 * D.CHIP_PADX end

-- static (non-clickable) chip: pill outline + text in the same color; returns width
function B:chip(x, y, s, token, filled)
    local w, h = D.chipW(s), D.chipH()
    local c = self:col(token)
    if filled then self:fill(x, y, w, h, { r = c.r, g = c.g, b = c.b, a = 0.18 }, "pill") end
    self:border(x, y, w, h, c, "pill")
    self:text(x + D.CHIP_PADX, y + 3, s, c)
    return w
end

-- card background with an optional colored frame
function B:card(x, y, w, h, frame)
    self:fill(x, y, w, h, self.colors.card or self.colors.well)
    self:border(x, y, w, h, frame or "border")
end

-- list box (design r11 B: the vanilla admin lists, ISSafehousesList.lua:23-31 and :67-82; the admin pages draw the
-- same with Flow:list): a square surface box, a header band, a line between entries and every second entry
-- shaded (hover), a border frame (square like vanilla, so the band's corners stay inside the frame).
--   local L = b:list(x, y, w); b:listHead(L, h) (the band is the first h px; texts after); b:listSep(L, y) at the
--   top of every entry after the first; return b:listEnd(L, y) at the bottom (returns y). Ops draw in order: the
--   background and an entry's shade are recorded first and get their heights later (the next listSep, listEnd),
--   so the texts recorded between stay on top.
function B:list(x, y, w)
    self:fill(x, y, w, 0, "surface", "rect")
    local cv = self.cv
    return { x = x, y = y, w = w, bg = cv.ops[cv.n], k = 1 }
end

function B:listHead(L, h)
    local c = self:col("border")
    self:rect(L.x, L.y, L.w, h, { r = c.r, g = c.g, b = c.b, a = 0.3 * (c.a or 1) })
    self:rect(L.x, L.y + h - 1, L.w, 1, c)
end

local function closeShade(L, y)
    local s = L.shade
    if s then
        s.h = y - s.y
        L.shade = nil
    end
end

function B:listSep(L, y)
    closeShade(L, y)
    L.k = L.k + 1
    if L.k % 2 == 0 then
        self:rect(L.x, y, L.w, 0, "hover")
        L.shade = self.cv.ops[self.cv.n]
    end
    local c = self:col("border")
    self:rect(L.x, y, L.w, 1, { r = c.r, g = c.g, b = c.b, a = 0.9 * (c.a or 1) })
end

function B:listEnd(L, y)
    closeShade(L, y)
    L.bg.h = y - L.y
    self:border(L.x, L.y, L.w, y - L.y, "border", "rect")
    return y
end

-- progress bar; ratio clamped 0..1
function B:bar(x, y, w, h, ratio, token)
    ratio = tonumber(ratio) or 0
    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
    self:rect(x, y, w, h, "well")
    self:rect(x, y, w, h, { r = 1, g = 1, b = 1, a = 0.08 })
    if ratio > 0 then self:rect(x, y, math.max(1, math.floor(w * ratio)), h, token or "accent") end
end

-- ===== control pool (Safehouse Flow pattern): get by key, hide the ones a layout did not touch =====
local Pool = D.Pool or {}
D.Pool = Pool
Pool.__index = Pool

function D.pool(parent)
    return setmetatable({ parent = parent, items = {}, seen = {}, gen = 0 }, Pool)
end

function Pool:begin() self.gen = self.gen + 1 end

function Pool:get(key, make)
    local el = self.items[key]
    if el == nil then
        el = make()
        self.parent:addChild(el)
        self.items[key] = el
    end
    self.seen[key] = self.gen
    el:setVisible(true)
    return el
end

function Pool:finish()
    for key, el in pairs(self.items) do
        if self.seen[key] ~= self.gen then el:setVisible(false) end
    end
end

-- button by key; style "chip"/"ghost"/"primary"/nil; returns the button sized to its title
function Pool:button(key, UI, theme, title, target, onClick, style, active)
    local b = self:get(key, function()
        return UI.Button.new({ x = 0, y = 0, title = title, style = style, theme = theme, target = target, onClick = onClick })
    end)
    b:setTitle(title)
    b:fitWidth()
    if style == "chip" then b:setActive(active == true) end
    return b
end

-- tracker pin chip on a quest or achievement card: "Track" / "Tracking" (active); a click toggles the pin.
-- With LIMIT.MAX_PINS pinned the others stay enabled (focusable by keyboard and gamepad): the hover hint says
-- why, and a click gets the server's TOO_MANY_PINS refusal as a toast (C.setPin).
function D.pinChip(page, key, id)
    local on = C.isPinned(id)
    local full = not on and #C.pins() >= Q.Contract.LIMIT.MAX_PINS
    local b = page.pool:button(key, page.UI, page.theme, getText(on and "IGUI_MQ_UI_Tracking" or "IGUI_MQ_UI_Track"),
        page, D.onPinChip, "chip", on)
    b.internal = id
    b:setTooltip(full and D.codeText("TOO_MANY_PINS") or nil)
    return b
end

function D.onPinChip(page, btn)
    if C.isPending(page.pinRid) then return end
    page.pinRid = C.setPin(btn.internal, not C.isPinned(btn.internal))
end

-- place a row of buttons from x, wrapping at maxX; returns the y below the last row
function D.placeRow(buttons, x0, y, maxX, gap)
    gap = gap or 6
    local x, rowH = x0, 0
    for _, b in ipairs(buttons) do
        if x > x0 and x + b.width > maxX then
            y = y + rowH + gap
            x, rowH = x0, 0
        end
        b:setX(x)
        b:setY(y)
        x = x + b.width + gap
        rowH = math.max(rowH, b.height)
    end
    return y + rowH
end

-- ===== page scaffold: a ScrollPanel with one Canvas as first child (controls added later render on top) =====
function D.scrollPage(page)
    local UI, theme = page.UI, page.theme
    local sp = UI.ScrollPanel.new({ x = 0, y = 0, width = page.width, height = page.height, theme = theme })
    page.parent:addChild(sp)
    page.sp = sp
    page.canvas = D.newCanvas(UI, theme)
    sp:addChild(page.canvas)
    page.pool = D.pool(sp)
    return sp
end

function D.resizePage(page)
    if page.sp ~= nil then
        page.sp:setWidth(page.width)
        page.sp:setHeight(page.height)
    end
end

-- content width inside the page's scroll panel
function D.contentW(page)
    return page.sp ~= nil and page.sp:contentWidth() or page.width
end

-- finish a layout pass: canvas height = content bottom
function D.finish(page, bottom)
    page.canvas:setWidth(D.contentW(page))
    page.canvas:setHeight(math.max(1, bottom))
    page.pool:finish()
end

-- page title row: title text and status chips after it (wrapping); returns the y below
function B:header(x, y, maxX, title, chips)
    local th = D.fontH(UIFont.Medium)
    local w = self:text(x, y, title, "text", UIFont.Medium)
    local cx, cy = x + w + 10, y + math.floor((th - D.chipH()) / 2)
    local bottom = y + th
    for _, ch in ipairs(chips or {}) do
        local cw = D.chipW(ch[1])
        if cx + cw > maxX then
            cx, cy = x, bottom + 4
            bottom = cy + D.chipH()
        end
        cx = cx + self:chip(cx, cy, ch[1], ch[2], ch[3]) + 6
    end
    return bottom + D.GAP
end

-- tinted banner box: title line + wrapped body; footH leaves room at the bottom for a button row the caller places
-- (its top at the returned y - D.GAP - 6 - its height). Returns y below
function B:banner(x, y, w, token, title, body, rightText, footH)
    local c = self:col(token)
    local lh = D.fontH(UIFont.Small)
    local lines = body ~= nil and D.wrap(self.UI, body, w - 20, UIFont.Small) or {}
    local h = 10 + lh + #lines * (lh + 2) + 8 + (footH or 0)
    self:fill(x, y, w, h, { r = c.r, g = c.g, b = c.b, a = 0.12 })
    self:border(x, y, w, h, c)
    local rw = rightText ~= nil and self:textRight(x + w - 10, y + 6, rightText, c) or 0
    self:fitText(x + 10, y + 6, title, w - 30 - rw, c)
    local ly = y + 8 + lh
    for _, line in ipairs(lines) do
        self:text(x + 10, ly, line, "text")
        ly = ly + lh + 2
    end
    return y + h + D.GAP
end

-- no state yet: "loading" line, or after the hello retries ran out an error line with a retry button.
-- Returns the y below
function D.waiting(page, b, x, y, w)
    if C.helloCode ~= nil then y = b:para(x, y, D.codeText(C.helloCode), w, "errorText") end
    if C.helloWaiting then
        b:chip(x, y, getText("IGUI_MQ_UI_Loading"), "textMuted")
        return y + D.chipH() + D.GAP
    end
    if C.helloCode == nil then y = b:para(x, y, getText("IGUI_MQ_UI_NoState"), w, "errorText") end
    local btn = page.pool:button("helloRetry", page.UI, page.theme, getText("IGUI_MQ_UI_Refresh"), page,
        function() MinidoracatQuest.Client.helloTries = 0; MinidoracatQuest.Client.hello() end)
    btn:setX(x)
    btn:setY(y)
    return y + btn.height + D.GAP
end

-- strongest running event multiplier for a quest theme (C9: only daily / weekly quest points)
function D.eventMult(theme)
    local s = C.state
    local best = nil
    local now = C.serverNow()
    for _, ev in ipairs(s and type(s.events) == "table" and s.events or {}) do
        if (ev.theme == "all" or ev.theme == theme) and (tonumber(ev.endsAt) or 0) > now then
            local m = tonumber(ev.mult) or 1
            if m > 1 and (best == nil or m > best) then best = m end
        end
    end
    return best
end

-- ===== hordes (state.hordes = { cur, last }; toasts kind "horde") =====
local LIVE = { announced = true, waiting = true, active = true, rest = true }
-- the states where the spot matters (players walk there or stay away): the Map button shows (design 5)
D.HORDE_MAP = { announced = true, waiting = true, rest = true }

-- the current horde while players see it (announced / waiting / active / rest between waves), else nil
function D.hordeLive(cur)
    if type(cur) == "table" and LIVE[cur.state] then return cur end
    return nil
end

-- the vanilla world map (ISWorldMap.lua:1491): false in Tutorial or when the sandbox turns the map off.
-- The admin spot rows call these too.
function D.mapAllowed()
    return ISWorldMap ~= nil and ISWorldMap.IsAllowed()
end

-- open the world map centred on x, y (ISWorldMap.lua:1500); MiniMap wraps ShowWorldMap, so its horde marker shows too.
-- false when the map is not allowed
function D.showOnMap(playerNum, x, y)
    if not D.mapAllowed() then return false end
    ISWorldMap.ShowWorldMap(playerNum, tonumber(x) or 0, tonumber(y) or 0, 16)
    return true
end

-- built-in towns by key, custom ones (config towns.custom, in every client's catalog push) by their name
function D.townName(id)
    if id == nil then return nil end
    local t = D.textOrNull("IGUI_MQ_Town_" .. tostring(id))
    if t ~= nil then return t end
    local towns = C.defs().cfg.towns
    for _, c in ipairs(type(towns) == "table" and type(towns.custom) == "table" and towns.custom or {}) do
        if type(c) == "table" and c.id == id then return tostring(c.name) end
    end
    return nil
end

-- "<spot> - <town>" (IGUI_MQ_Horde_Place), or the spot name alone outside any town
function D.hordePlace(h)
    local name, town = tostring(h.name or ""), D.townName(h.town)
    if town == nil then return name end
    return getText("IGUI_MQ_Horde_Place", name, town)
end

-- the place, prefixed "Wave W/N - " (or "Wave W/N cleared - " in the rest) when the horde has more than one wave;
-- an announced one shows the place alone (design 1). spotOnly: after the prefix the spot name without its town (the
-- tracker row, as in the design mock; with the town the prefix and countdown cut the spot off, quest-hui-en-1027a)
function D.hordeName(h, spotOnly)
    local place, n = D.hordePlace(h), tonumber(h.waves) or 1
    if n <= 1 or h.state == "announced" then return place end
    return getText(h.state == "rest" and "IGUI_MQ_Horde_WaveDone" or "IGUI_MQ_Horde_Wave", tostring(h.wave or 1),
        tostring(n), spotOnly and tostring(h.name or "") or place)
end

-- text, then the "every share was scaled down" note when the horde paid more than its cap
function D.hordeCapped(text, capped)
    if not capped then return text end
    return getText("IGUI_MQ_Horde_Join", text, getText("IGUI_MQ_Horde_Capped"))
end

-- the kinds that may appear ({ { id, nameKey } }), never a count
function D.hordeKinds(kinds)
    local names = {}
    for _, k in ipairs(type(kinds) == "table" and kinds or {}) do
        names[#names + 1] = type(k.nameKey) == "string" and D.textOrNull(k.nameKey) or tostring(k.id)
    end
    return table.concat(names, getText("IGUI_MQ_UI_ListSep"))
end

-- why a horde failed, "Wave W: " first when it has more than one wave
function D.hordeWhy(why, wave, waves)
    local s = D.textOrNull("IGUI_MQ_Horde_Why_" .. tostring(why)) or ""
    if (tonumber(waves) or 1) > 1 and wave ~= nil then return getText("IGUI_MQ_Horde_FailWave", tostring(wave), s) end
    return s
end

-- a failed horde still pays its cleared waves (design 4.3): why, then what was paid
function D.hordeFailText(why, wave, waves, cleared, pool, capped)
    local s = D.hordeWhy(why, wave, waves)
    cleared = tonumber(cleared) or 0
    if cleared <= 0 then return s end
    return D.hordeCapped(getText("IGUI_MQ_Horde_Join", s, getText("IGUI_MQ_Horde_FailPaid", tostring(cleared),
        D.num(tonumber(pool) or 0))), capped)
end

-- "12:34" / "1:02:03" (the tracker counts down by the second)
function D.countdown(ms)
    local s = math.max(0, math.ceil((tonumber(ms) or 0) / 1000))
    local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
    return string.format("%d:%02d", m, s % 60)
end
