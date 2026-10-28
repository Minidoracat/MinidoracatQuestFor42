-- MinidoracatQuest/AdminPanel.lua: admin page shell inside the quest window (ARCHITECTURE.md 6.2, 7; spec 13).
-- Sub-tabs + one ScrollPanel per tab + bottom bar (pending draft, preview, reload, status). Pages register
-- in A.pages (AdminAchv.lua, AdminTitles.lua, AdminPages.lua, AdminHordes.lua). Every config edit goes into a local draft first and is only
-- applied through cfg.preview -> "Apply changes?" view -> cfg.apply. The server re-checks everything.
-- Host contract (QuestClientUI): ClientUI.registerAdminPage(spec); spec.show(host)/hide()/resize(w, h)/onReply(p);
-- host = { UI, theme, parent, x, y, width, height, D = MinidoracatQuest.Draw }; Client.send("admin", args, cb).
-- Vanilla: ISUIElement (drawText/drawRect/drawRectBorder), getTextManager():MeasureStringX/getFontHeight.

require "MinidoracatQuest/AdminModel"
require "MinidoracatQuest/Window"

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
local A = MQ.Admin or {}
MQ.Admin = A
local AM = MQ.AdminModel

-- settings first (Basic is the guided first page), then the operations tabs from A.TAB_BREAK on
A.TABS = { "basic", "achv", "titles", "quests", "season", "exchange", "towns", "hordes", "players", "report", "balance", "history" }
A.TAB_BREAK = "players"
A.pages = A.pages or {}   -- id -> { layout = fn(P, pg, F), load = fn(P, pg)? }
A.PAD, A.GAP = 10, 6

local function fontH(font) return getTextManager():getFontHeight(font or UIFont.Small) end
local function textW(s, font) return getTextManager():MeasureStringX(font or UIFont.Small, s) end
A.fontH, A.textW = fontH, textW

-- ===== elements =====

-- classes are derived on first build, so this file loads without the UI (offline harness)
local Label, Row

function A.defineClasses()
if Label then return end

-- text block: lines, optional strike-through and box (banner); render allocates nothing
Label = ISUIElement:derive("MinidoracatQuestAdminLabel")

function Label:prerender()
    local b = self.box
    if b then
        self:drawRect(0, 0, self.width, self.height, 0.15, b.r, b.g, b.b)
        self:drawRectBorder(0, 0, self.width, self.height, 0.9, b.r, b.g, b.b)
    end
end

function Label:render()
    local c, fh, lines = self.color, self.fh, self.lines
    for i = 1, #lines do
        local f = (i == 1 and self.firstFont) or self.font
        self:drawText(lines[i], self.padX, self.lineY[i], c.r, c.g, c.b, c.a or 1, f)
    end
    if self.strike then
        self:drawRect(self.padX, self.padY + math.floor(fh / 2), self.width - 2 * self.padX, 1, c.a or 1, c.r, c.g, c.b)
    end
end


-- one table row of texts at fixed columns: cells = { { text, x, right?, w?, wrap?, token?, strike? } }
-- wrap = up to three lines inside w (the row grows); other cells stay centered
Row = ISUIElement:derive("MinidoracatQuestAdminRow")

function Row:render()
    local colors, cells, fh = self.theme.colors, self.cells, self.fh
    local ty = math.floor((self.height - fh) / 2)
    for i = 1, #cells do
        local c = cells[i]
        local col = colors[c.token or "text"] or colors.text
        local x = c.right and (c.x - c.tw) or c.x
        if c.lines then
            for k, l in ipairs(c.lines) do self:drawText(l, x, 4 + (k - 1) * fh, col.r, col.g, col.b, col.a or 1, UIFont.Small) end
        else
            self:drawText(c.shown, x, ty, col.r, col.g, col.b, col.a or 1, UIFont.Small)
        end
        if c.strike then self:drawRect(x, ty + math.floor(fh / 2), c.tw, 1, col.a or 1, col.r, col.g, col.b) end
    end
end
end

local function newLabel()
    local l = Label:new(0, 0, 1, 1)
    l:initialise()
    l.lines, l.lineY, l.padX, l.padY, l.fh = {}, {}, 0, 0, fontH()
    l.font, l.color = UIFont.Small, { r = 1, g = 1, b = 1, a = 1 }
    return l
end

-- ===== flow: elements reused by key; each layout places from the top, unused ones are hidden =====
-- ox / width: where the helpers place (a list box narrows them, Flow:list)

local Flow = {}
Flow.__index = Flow

function A.flow(parent, P)
    return setmetatable({ parent = parent, P = P, pool = {}, seen = {}, gen = 0, y = 0, width = 0, ox = 0, lists = {} }, Flow)
end

-- narrowNotes goes back to off: a page turns it on in its own layout (the hordes tab), so the confirm view shown on
-- the same flow keeps the full width
function Flow:begin(width)
    self.gen, self.y, self.width, self.ox, self.L, self.lists = self.gen + 1, A.PAD, width, 0, nil, {}
    self.narrowNotes = nil
end

function Flow:get(key, make)
    local el = self.pool[key]
    if el == nil then
        el = make()
        self.parent:addChild(el)
        self.pool[key] = el
    end
    self.seen[key] = self.gen
    el:setVisible(true)
    return el
end

function Flow:finish()
    for key, el in pairs(self.pool) do
        if self.seen[key] ~= self.gen then el:setVisible(false) end
    end
end

function Flow:gap(n) self.y = self.y + (n or A.GAP) end

local function wrapLines(UI, text, maxW, font)
    if UI.Text and type(UI.Text.wrap) == "function" then return UI.Text.wrap(text, maxW, font) end
    return { text }
end

local function setLines(l, lines, font, firstFont, padX, padY)
    l.font, l.firstFont, l.padX, l.padY = font, firstFont, padX, padY
    l.fh = fontH(font)
    local y, w = padY, 0
    local out, ys = {}, {}
    for i, line in ipairs(lines) do
        local f = (i == 1 and firstFont) or font
        out[i], ys[i] = line, y
        y = y + fontH(f) + 2
        w = math.max(w, textW(line, f))
    end
    l.lines, l.lineY = out, ys
    return w, y - 2 + padY
end

-- label (not placed): one line, or wrapped to maxW when given (form label columns are capped)
function Flow:label(key, text, token, font, maxW)
    font = font or UIFont.Small
    local l = self:get(key, newLabel)
    local colors = self.P.theme.colors
    l.color, l.box, l.strike = colors[token or "text"] or colors.text, nil, false
    local lines = { text }
    if maxW and textW(text, font) > maxW then lines = wrapLines(self.P.UI, text, maxW, font) end
    local w, h = setLines(l, lines, font, nil, 0, 0)
    l:setWidth(w)
    l:setHeight(h)
    return l
end

-- wrapped paragraph at the left margin; box = theme token for a banner frame
local LIST_PAD = 4   -- above and below a text or a control row inside a list box (cells rows pad themselves)

function Flow:text(key, text, token, font, box, title)
    font = font or UIFont.Small
    local P = self.P
    local colors = P.theme.colors
    local l = self:get(key, newLabel)
    local pad = box and 8 or 0
    local maxW = self.width - 2 * A.PAD - 2 * pad
    -- a plain note (no box, UIFont.Small) of a page that asks for it (F.narrowNotes: the hordes tab) wraps at 30 font
    -- heights (about 600 px): a 1920 px wide panel made Latin lines of about 120 characters (horde presets design,
    -- review 2026-10-28). Not every page: with it the Basic tab's one-line notes needed a scroll at 1080p in DE, FR and
    -- ES (quest-ui-*-1028d). Headings (Medium) and the bottom bar's message keep the full width
    if not box and font == UIFont.Small and self.narrowNotes then maxW = math.min(maxW, 30 * fontH(font)) end
    local lines = {}
    if title then lines[1] = title end
    for _, line in ipairs(wrapLines(P.UI, text, maxW, font)) do lines[#lines + 1] = line end
    l.color, l.strike = colors[token or "text"] or colors.text, false
    l.box = box and (colors[box] or colors.accent) or nil
    local w, h = setLines(l, lines, font, title and UIFont.Medium or nil, pad, pad)
    l:setWidth(box and (self.width - 2 * A.PAD) or w)
    l:setHeight(h)
    if self.L then self.y = self.y + LIST_PAD end
    l:setX(self.ox + A.PAD)
    l:setY(self.y)
    self.y = self.y + h + (self.L and LIST_PAD or A.GAP)
    return l
end

-- a heading opens a group: twice the gap above it (not at the top), so it sits closer to what it heads
function Flow:head(key, text)
    if self.y > A.PAD then self:gap(2 * A.GAP) end
    return self:text(key, text, "text", UIFont.Medium)
end

-- controls left to right, wrapping; vertically centred per line. tail = one control kept at the right end of the
-- first line (a row's Remove)
function Flow:row(ctrls, x0, tail)
    x0 = self.ox + (x0 or A.PAD)
    local x, rowY, rowH, line = x0, self.y + (self.L and LIST_PAD or 0), 0, {}
    local right = self.ox + self.width - A.PAD
    if tail then
        tail:setX(right - tail.width)
        right = right - tail.width - A.GAP
        line[1], rowH = tail, tail.height
    end
    for _, c in ipairs(ctrls) do
        if x > x0 and x + c.width > right then
            for _, d in ipairs(line) do d:setY(rowY + math.floor((rowH - d.height) / 2)) end
            rowY, x, rowH, line = rowY + rowH + A.GAP, x0, 0, {}
        end
        c:setX(x)
        line[#line + 1] = c
        x = x + c.width + A.GAP
        rowH = math.max(rowH, c.height)
    end
    for _, d in ipairs(line) do d:setY(rowY + math.floor((rowH - d.height) / 2)) end
    self.y = rowY + rowH + (self.L and LIST_PAD or A.GAP)
end

-- table row of texts; returns the row element (placed, y advanced)
function Flow:cells(key, cells)
    local P = self.P
    local r = self:get(key, function()
        local e = Row:new(0, 0, 1, 1)
        e:initialise()
        -- display only: ISUIElement:new wants mouse events and its onMouseUp returns nil, so a row added after a
        -- button over it took the mouse-up and the button never fired (anomaly "View", UIElement.java:1331-1342)
        e:setWantMouseEvents(false)
        e.theme, e.fh = P.theme, fontH()
        return e
    end)
    local lines = 1
    for _, c in ipairs(cells) do
        c.text = tostring(c.text or "")
        local fit = c.w and P.UI.Text and P.UI.Text.fit
        c.shown = fit and fit(c.text, c.w, UIFont.Small) or c.text
        c.lines = nil
        if c.wrap and fit and c.shown ~= c.text then
            -- up to three lines, the last one cut (FR "Entrainement : / Armes contondantes / longues")
            local ws = wrapLines(P.UI, c.text, c.w, UIFont.Small)
            if #ws > 1 then
                c.lines = { ws[1] }
                if #ws > 2 then c.lines[2] = ws[2] end
                c.lines[#c.lines + 1] = (fit(table.concat(ws, " ", #c.lines + 1), c.w, UIFont.Small))
                lines = math.max(lines, #c.lines)
            end
        end
        c.tw = textW(c.shown)
    end
    r.cells = cells
    r:setX(self.ox)
    r:setY(self.y)
    r:setWidth(self.width)
    r:setHeight(lines * fontH() + 8)
    self.y = self.y + r.height
    return r
end

-- ===== list boxes (design r11 B: the vanilla admin lists, ISSafehousesList.lua:23-31 and :67-82) =====
-- F:list(key) opens a box at the current y; inside it F.ox / F.width are the box's, so the A.PAD / F.width column
-- math of the caller stays (open the box first, then measure). F:listHead(cells, hkey?) puts the header band on top
-- (hkey = its pool key, default key .. ":th"), F:item() starts each entry (an entry can be several rows: cells, a
-- wrapped text, a row of controls); a line separates the entries and every second one is shaded (the user asked
-- for alternating colours on top of B, 2026-10-26), the whole entry, so a wrapped line stays in its entry's band.
-- F:listEnd(L, empty, token) closes the box, with the empty text inside when no entry came. A.paintLists draws the
-- boxes in the page ScrollPanel's prerender, under every child: no frame covers a row, a field or a button, and the
-- ui-mp layout detector sees no extra element. Boxes do not nest.
function Flow:list(key)
    local L = { key = key, x = self.ox + A.PAD, y = self.y, w = self.width - 2 * A.PAD, hh = 0, starts = {},
        ox = self.ox, width = self.width }
    self.lists[#self.lists + 1] = L
    self.ox, self.width, self.L = L.x, L.w, L
    return L
end

function Flow:listHead(cells, hkey)
    self.L.hh = self:cells(hkey or (self.L.key .. ":th"), cells).height
end

function Flow:item()
    local starts = self.L.starts
    starts[#starts + 1] = self.y
end

function Flow:listEnd(L, empty, token)
    if #L.starts == 0 and empty then
        self:item()
        self:text(L.key .. ":0", empty, token or "textMuted")
    end
    L.h = self.y - L.y
    self.ox, self.width, self.L = L.ox, L.width, nil
    self.y = self.y + A.GAP
end

-- the boxes of the current layout, in content coordinates: the panel's own drawing scrolls with its children
-- (UIElement.java:469-483). Background surface, header band border x 0.3, every second entry hover (the player
-- pages' old stripe), lines border (vanilla 0.4 grey a0.9)
function A.paintLists(sp, F)
    local lists = F.lists
    local n = #lists
    if n == 0 then return end
    local colors = F.P.theme.colors
    local bg, ln, hv = colors.surface, colors.border, colors.hover
    local a = ln.a or 1
    for i = 1, n do
        local L = lists[i]
        local h = L.h
        if h then
            sp:drawRect(L.x, L.y, L.w, h, bg.a or 1, bg.r, bg.g, bg.b)
            if L.hh > 0 then
                sp:drawRect(L.x, L.y, L.w, L.hh, 0.3 * a, ln.r, ln.g, ln.b)
                sp:drawRect(L.x, L.y + L.hh - 1, L.w, 1, a, ln.r, ln.g, ln.b)
            end
            local starts = L.starts
            for k = 2, #starts do
                local y0 = starts[k]
                if k % 2 == 0 then sp:drawRect(L.x, y0, L.w, (starts[k + 1] or (L.y + h)) - y0, hv.a or 1, hv.r, hv.g, hv.b) end
                sp:drawRect(L.x, y0, L.w, 1, 0.9 * a, ln.r, ln.g, ln.b)
            end
            sp:drawRectBorder(L.x, L.y, L.w, h, a, ln.r, ln.g, ln.b)
        end
    end
end

-- callbacks go through trampolines so a reused element always calls the latest handler
local function click(P, b) if b.handler then b.handler(P, b) end end
local function checked(P, value, box) if box.handler then box.handler(P, value, box) end end
local function picked(P, id, dd) if dd.handler then dd.handler(P, id, dd) end end

-- style is applied on every layout: a reused button can switch (season "Exclude" danger <-> "Include again" normal)
function Flow:button(key, title, handler, style)
    local P = self.P
    local b = self:get(key, function()
        return P.UI.Button.new({ x = 0, y = 0, title = title, style = style, theme = P.theme, target = P, onClick = click })
    end)
    b:setTitle(title)
    if b.setStyle then b:setStyle(style or "normal") end
    b:fitWidth()
    b:setEnabled(true)
    b.handler = handler
    return b
end

function Flow:check(key, label, handler, value)
    local P = self.P
    local width = 48 + textW(label)
    local c = self:get(key, function()
        return P.UI.Checkbox.new({ x = 0, y = 0, width = width, label = label, theme = P.theme, target = P, onChange = checked })
    end)
    c:setLabel(label)
    c:setWidth(width)
    c:setEnabled(true)
    c.handler = handler
    if value ~= nil then c:setChecked(value == true, true) end
    return c
end

function Flow:field(key, width, placeholder, maxLength)
    local P = self.P
    local tf = self:get(key, function()
        return P.UI.TextField.new({ x = 0, y = 0, width = width, theme = P.theme, placeholder = placeholder,
            maxLength = maxLength })
    end)
    if tf.width ~= width then tf:setWidth(width) end
    return tf
end

-- options = { { id, label } }; selected kept when still present; placeholder = the text while nothing is picked
function Flow:dropdown(key, options, selected, handler, placeholder, width)
    local P = self.P
    local dd = self:get(key, function()
        return P.UI.Dropdown.new({ x = 0, y = 0, width = width, options = options, selected = selected, theme = P.theme,
            target = P, onChange = picked, maxRows = 12, placeholder = placeholder })
    end)
    if width and dd.width ~= width then dd:setWidth(width) end
    dd:setOptions(options)
    dd:setSelected(selected, true)
    dd.handler = handler
    return dd
end

-- ===== text helpers =====

function A.D() return MQ.Draw end

function A.num(n)
    local D = MQ.Draw
    if D and D.num and type(n) == "number" and n == math.floor(n) then return D.num(n) end
    return AM.num(n)
end

function A.time(ms)
    if type(ms) ~= "number" then return "-" end
    local D = MQ.Draw
    if D and D.dateTime then return D.dateTime(ms) end
    return AM.time(ms)
end

-- width of a time column: two-digit month/day at 23:59 on each weekday of one week, the widest one
-- (weekday names differ in width: EN "Wed" beside an actor name left no gap with a Sunday sample)
function A.timeW()
    local w, d0 = 0, AM.dayStartMs("2026-12-21")
    for k = 0, 6 do w = math.max(w, textW(A.time(d0 + k * 86400000 + 86340000))) end
    return w + A.GAP
end

-- a name column as wide as its widest entry, cut only past cap (a fixed 160 cut "Lena_Wanderer_of_Mul...")
function A.colW(texts, cap)
    local w = 0
    for _, s in ipairs(texts) do w = math.max(w, textW(tostring(s))) end
    return math.max(20, math.min(w + A.GAP, cap))
end

-- "1 item" / "N items": key .. "1" holds the singular (same text where the language does not inflect)
function A.count(key, n) return getText(n == 1 and key .. "1" or key, n) end

function A.tzNote() return getText("IGUI_MQ_Admin_TzNote", AM.tzText()) end

-- a reason the server gives for a refused setting (Config.validate / validateAll): translated where it says how to fix
-- it (IGUI_MQ_Admin_Why_<why>), else the server's own word
function A.whyText(why)
    why = tostring(why or "?")
    return getTextOrNull("IGUI_MQ_Admin_Why_" .. why) or why
end

function A.codeText(P, res)
    if res.code == "BAD_CONFIG" and type(res.detail) == "table" then
        local why = A.whyText(res.detail.why)
        -- a check of the whole result (8 presets at most) names no path
        if res.detail.path == nil and why ~= tostring(res.detail.why) then return why end
        return getText("IGUI_MQ_Admin_BadConfig", A.pathLabel(P, tostring(res.detail.path or "?")), why)
    end
    if res.code == "NO_REPLY" then return getText("IGUI_MQ_Admin_NoReply") end
    local D = MQ.Draw
    if D and D.codeText then return D.codeText(res.code) end
    return getTextOrNull("IGUI_MQ_Code_" .. tostring(res.code)) or tostring(res.code)
end

function A.statName(stat)
    return getTextOrNull("IGUI_MQ_Stat_" .. string.gsub(tostring(stat), "%.", "_")) or tostring(stat)
end

function A.achName(P, id)
    local cid = string.match(id, "^c:(.+)$")
    if cid then
        local c = AM.get(P.S, "custom." .. cid)
        return type(c) == "table" and c.name or id
    end
    return getTextOrNull("IGUI_MQ_Ach_" .. id) or id
end

function A.questName(tid)
    local t = MQ.Client and MQ.Client.defs().daily[tid]
    local name
    if type(t) == "table" and type(t.nameKey) == "string" then
        name = getText(t.nameKey, "N")
    else
        name = getTextOrNull("IGUI_MQ_Q_" .. tid, "N") or tid   -- with the argument, %1 does not warn (Draw.textOrNull)
    end
    -- "_more" templates read like their base one to players (only the number differs); admin lists tell them apart
    if string.match(tostring(tid), "_more$") then name = getText("IGUI_MQ_Admin_Bulk", name) end
    return name
end

function A.titleText(id)
    local D = MQ.Draw
    if D and D.titleText then return D.titleText(id) end
    return getTextOrNull("IGUI_MQ_Title_" .. tostring(id)) or tostring(id)
end

function A.fieldName(f) return getTextOrNull("IGUI_MQ_Admin_Field_" .. f) or f end

-- config path -> readable name
function A.pathLabel(P, path)
    local id, f = string.match(path, "^achievements%.(.+)%.(%a+)$")
    if id then return A.achName(P, id) .. " - " .. A.fieldName(f) end
    local cid = string.match(path, "^custom%.([^%.]+)")
    if cid then return A.achName(P, "c:" .. cid) end
    local kind, tid
    kind, tid, f = string.match(path, "^(%a+)%.pool%.([^%.]+)%.(%a+)$")
    if kind then return A.questName(tid) .. " - " .. A.fieldName(f) end
    -- horde presets (AdminHordes.lua names them and the kinds, pack kinds by the nameKey horde.status gave):
    -- "Preset "Hard": Each kill - Runner"
    local pid, rest = string.match(path, "^hordes%.presets%.([^%.]+)%.(.+)$")
    if pid and A.hordePresetName then
        local group, kid = string.match(rest, "^(%a+)%.(.+)$")
        local what
        if (group == "kinds" or group == "points" or group == "hp") and A.hordeKindName then
            what = A.fLabel("hordes." .. group) .. " - " .. A.hordeKindName(P, kid)
        else
            what = A.fLabel("hordes." .. (group or rest))
        end
        return getText("IGUI_MQ_Admin_HordePresetRow", A.hordePresetName(P, pid), what)
    end
    pid = string.match(path, "^hordes%.presets%.([^%.]+)$")
    if pid and A.hordePresetName then return getText("IGUI_MQ_Admin_HordePresetIs", A.hordePresetName(P, pid)) end
    -- one window of the whole-set list (the server names hordes.windows.<i>.preset): "Windows 2"
    local wi = string.match(path, "^hordes%.windows%.(%d+)")
    if wi then return A.fLabel("hordes.windows") .. " " .. wi end
    return getTextOrNull("IGUI_MQ_Admin_F_" .. string.gsub(path, "%.", "_")) or path
end

local function isNumList(v)
    if type(v) ~= "table" or #v == 0 then return false end
    for _, x in ipairs(v) do if type(x) ~= "number" then return false end end
    return true
end

function A.valueText(v)
    if v == nil then return getText("IGUI_MQ_Admin_None") end
    if type(v) == "boolean" then return getText(v and "IGUI_MQ_Admin_On" or "IGUI_MQ_Admin_Off") end
    if type(v) == "number" then return A.num(v) end
    if type(v) ~= "table" then return tostring(v) end
    if isNumList(v) then
        local parts = {}
        for i, x in ipairs(v) do parts[i] = A.num(x) end
        return table.concat(parts, " / ")
    end
    if type(v.name) == "string" then return v.name end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return A.count("IGUI_MQ_Admin_Items", n)
end

-- per-stat limit rows of a "ceilings" change (effective maps; a stat without a key uses Catalog.stats[id].ceil)
local function ceilRows(out, label, before, after)
    local C = MQ.Catalog or {}
    local stats, keys, seen = C.stats or {}, {}, {}
    local function add(k) if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    for _, k in ipairs(C.statOrder or {}) do if before[k] ~= nil or after[k] ~= nil then add(k) end end
    for k in pairs(after) do add(k) end
    for k in pairs(before) do add(k) end
    for _, k in ipairs(keys) do
        local def = stats[k] and stats[k].ceil
        local b, a = before[k] or def, after[k] or def
        if b ~= a then out[#out + 1] = { label = label .. " - " .. A.statName(k), before = A.valueText(b), after = A.valueText(a) } end
    end
end

-- server preview rows -> display rows { label, before, after }; number lists expand per tier
function A.diffRows(P, rows)
    local out = {}
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        local label = A.pathLabel(P, tostring(r.path))
        if isNumList(r.before) and isNumList(r.after) then
            local n = math.max(#r.before, #r.after)
            for i = 1, n do
                if r.before[i] ~= r.after[i] then
                    out[#out + 1] = { label = label .. " " .. AM.roman(i), before = A.valueText(r.before[i]),
                        after = A.valueText(r.after[i]) }
                end
            end
        elseif r.path == "ceilings" and type(r.before) == "table" and type(r.after) == "table" then
            ceilRows(out, label, r.before, r.after)
        else
            -- whole horde windows / waves / presets: one readable line each (AdminHordes.lua A.hordeRow, nil = not one)
            out[#out + 1] = A.hordeRow and A.hordeRow(P, r, label)
                or { label = label, before = A.valueText(r.before), after = A.valueText(r.after) }
        end
    end
    return out
end

-- ===== network =====

-- one outstanding request per op; done(reply) once (ClientUI turns timeouts into code NO_REPLY)
function A.send(P, op, fields, done)
    if P.waits[op] then return false end
    local args = { op = op }
    for k, v in pairs(fields or {}) do args[k] = v end
    P.waits[op] = true
    A.layoutBar(P)
    MQ.Client.send("admin", args, function(res)
        P.waits[op] = nil
        if type(res) ~= "table" then res = { ok = false, code = "INTERNAL" } end
        if done then done(res) end
        A.layoutBar(P)
    end)
    return true
end

function A.busy(P)
    for _ in pairs(P.waits) do return true end
    return false
end

-- replies come through the send callback
function A.onReply(_) end

function A.encode(changes)
    local ok, s = pcall(MQ.Util.encode, changes)
    if not ok or type(s) ~= "string" or #s > 32000 then return nil end
    return s
end

-- ===== status bar =====

function A.say(P, text, token)
    P.msg, P.msgToken = text, token or "text"
    A.layoutBar(P)
end

function A.fail(P, res) A.say(P, A.codeText(P, res), "errorText") end

-- one row of buttons and one line of message; taller when the message wraps (long translations, narrow windows:
-- quest-ui-de-1026w), the pages above give up the room
local function barHeight(P) return math.max(2 * fontH() + 26, P.barFlow and P.barFlow.y or 0) end

function A.layoutBar(P)
    local F = P.barFlow
    if F == nil then return end
    F:begin(P.bar.width)
    F.y = 4
    local ctrls = {}
    if P.confirm then
        -- the confirm view's own actions: its rows can run past a hundred, so Apply never waits at their end
        local apply = F:button("apply", getText("IGUI_MQ_Admin_ApplyChanges"), A.onConfirmApply, "primary")
        apply:setEnabled(not A.busy(P))
        ctrls[1] = apply
        ctrls[2] = F:button("cancel", getText("UI_Cancel"), A.onConfirmCancel)
    else
        local n = AM.draftCount(P.S.draft)
        -- the solid gold button only when there is something to preview
        local prev = F:button("preview", n > 0 and getText("IGUI_MQ_Admin_PreviewN", n) or getText("IGUI_MQ_Admin_Preview"),
            A.onPreview, n > 0 and "primary" or nil)
        prev:setEnabled(P.S.overrides ~= nil)
        ctrls[1] = prev
        if n > 0 then ctrls[#ctrls + 1] = F:button("discard", getText("IGUI_MQ_Admin_Discard"), A.onDiscard) end
        ctrls[#ctrls + 1] = F:button("reload", getText("IGUI_MQ_Admin_Reload"), A.onReload)
    end
    F:row(ctrls)
    if A.busy(P) then
        F:text("msg", getText("IGUI_MQ_Admin_Waiting"), "textMuted")
    elseif P.msg then
        F:text("msg", P.msg, P.msgToken)
    end
    F:finish()
    if barHeight(P) ~= P.bar:getHeight() then A.place(P, P.root:getWidth(), P.root:getHeight()) end
end

-- ===== draft, preview, apply =====

local function field(pg, key)
    local f = pg.fields[key]
    if f == nil then
        f = { key = key }
        pg.fields[key] = f
    end
    f.gen = pg.flow.gen
    return f
end

local function markError(P, el, message)
    if el.setInvalid and P.UI.CAPABILITIES.textFieldInvalid then
        el:setInvalid(message ~= nil, message)
    elseif message ~= nil and el.setTooltip then
        el:setTooltip(message)
    end
end
A.markError = markError

local function valueAt(P, f)
    local v = AM.get(P.S, f.path)
    if f.part then
        for _, k in ipairs(f.part) do v = type(v) == "table" and v[k] or nil end
    end
    return v
end

-- what a framework TextField keeps around its text with the error mark shown: padding 2 x 6, the 16 px mark and its
-- 4 px gap, the entry inset 2 x 2 (MinidoracatUI Widgets/Controls.lua FIELD_PAD, ICON_SIZE, INVALID_GAP,
-- TEXTBOX_INSET). A field narrower than its text + this cuts the text when marked (interface review M3)
A.FIELD_CHROME = 36

-- number field bound to a config path (part = key list inside the value); range = AM.RANGE key;
-- default = what an unset key means (shown, and dropped again by AM.formToDraft). Without a width it is as wide as
-- its largest value with the error mark shown (at least 60)
function A.numField(P, pg, key, path, part, range, width, default)
    local f = field(pg, key)
    f.path, f.part, f.range, f.kind, f.default = path, part, range, "num", default
    local r = AM.RANGE[range]
    f.el = pg.flow:field("f:" .. key, width or math.max(60, textW(AM.num(r[2])) + A.FIELD_CHROME))
    if f.at ~= pg.version then
        f.at = pg.version
        local v = valueAt(P, f)
        if v == nil then v = default end
        f.el:setText(type(v) == "number" and (v == math.floor(v) and tostring(math.floor(v)) or AM.num(v)) or "")
        markError(P, f.el, nil)
    end
    f.el:setTooltip(getText("IGUI_MQ_Admin_RangeTip", AM.num(r[1]), AM.num(r[2])))
    return f.el
end

function A.boolField(P, pg, key, label, path, part)
    local f = field(pg, key)
    f.path, f.part, f.kind = path, part, "bool"
    f.el = pg.flow:check("f:" .. key, label, nil)
    if f.at ~= pg.version then
        f.at = pg.version
        f.el:setChecked(valueAt(P, f) ~= false, true)
    end
    return f.el
end

-- free text bound to a config path (a horde preset's name): control characters dropped, spaces trimmed, cut to max
-- characters (Kahlua strings count UTF-16 units: 32 Chinese characters too); the page's own check says what a name
-- may not be, and a refill clears its mark
function A.textField(P, pg, key, path, width, max)
    local f = field(pg, key)
    f.path, f.kind, f.max = path, "text", max
    f.el = pg.flow:field("f:" .. key, width, nil, max)
    if f.at ~= pg.version then
        f.at = pg.version
        local v = AM.get(P.S, path)
        f.el:setText(type(v) == "string" and v or "")
        markError(P, f.el, nil)
    end
    return f.el
end

function A.cleanText(s, max)
    s = string.match((string.gsub(tostring(s or ""), "%c", "")), "^%s*(.-)%s*$")
    return max and string.sub(s, 1, max) or s
end

-- "HH:MM" text bound to a config path (part = key list inside the value); AM.clock checks it like the server
function A.clockField(P, pg, key, path, part)
    local f = field(pg, key)
    f.path, f.part, f.kind = path, part, "clock"
    f.el = pg.flow:field("f:" .. key, textW("00:00") + A.FIELD_CHROME, "HH:MM", 5)
    if f.at ~= pg.version then
        f.at = pg.version
        local v = valueAt(P, f)
        f.el:setText(type(v) == "string" and v or "")
        markError(P, f.el, nil)
    end
    return f.el
end

-- dropdown bound to a config path; options = { { id, label } }. Flow:dropdown re-selects on every layout, so the
-- pick made since the last resync is kept
function A.pickField(P, pg, key, path, options)
    local f = field(pg, key)
    f.path, f.kind = path, "pick"
    local sel = AM.get(P.S, path)
    if f.el ~= nil and f.at == pg.version then sel = f.el:getSelected() or sel end
    f.at = pg.version
    f.el = pg.flow:dropdown("f:" .. key, options, sel, nil)
    return f.el
end

-- ===== forms: a label column + controls, shared by every tab =====

-- a horde preset's field reads like the setting it holds: hordes.presets.<id>.limitMin -> F_hordes_limitMin
function A.fLabel(path)
    path = string.gsub(path, "^hordes%.presets%.[^%.]+%.", "hordes.")
    return getTextOrNull("IGUI_MQ_Admin_F_" .. string.gsub(path, "%.", "_")) or path
end

-- label column + controls; a label longer than the (capped) column wraps inside it
function A.formRow(F, key, text, labelW, ctrls)
    local l = F:label("l:" .. key, text, nil, nil, labelW - A.GAP)
    l:setWidth(labelW)
    local row = { l }
    for _, c in ipairs(ctrls) do row[#row + 1] = c end
    F:row(row)
end

-- one label width for every form of a tab, so the fields line up (each form measured itself before)
function A.labelWidth(paths)
    local w = 0
    for _, p in ipairs(paths) do w = math.max(w, textW(A.fLabel(p))) end
    return math.min(w + A.GAP, 260)
end

-- simple form: { { path, range | "bool", width? } }; lw = the tab's label width (A.labelWidth), else this form's own
function A.form(P, pg, F, rows, lw)
    if lw == nil then
        local paths = {}
        for i, r in ipairs(rows) do paths[i] = r[1] end
        lw = A.labelWidth(paths)
    end
    for _, r in ipairs(rows) do
        local ctrl
        if r[2] == "bool" then
            ctrl = A.boolField(P, pg, r[1], "", r[1])
        else
            ctrl = A.numField(P, pg, r[1], r[1], nil, r[2], r[3])
        end
        A.formRow(F, r[1], A.fLabel(r[1]), lw, { ctrl })
    end
end

-- read this page's bound fields; when any is invalid (each marked on its field): nil, the topmost one and its message
function A.collect(P, pg)
    local values, pairsOf = {}, {}
    local top, why
    local function mark(el, msg)
        markError(P, el, msg)
        if msg and (top == nil or el:getY() < top:getY() or (el:getY() == top:getY() and el:getX() < top:getX())) then
            top, why = el, msg
        end
    end
    for _, f in pairs(pg.fields) do
        if f.gen == pg.flow.gen and f.path then
            if f.kind == "bool" then
                values[#values + 1] = { field = f, value = f.el:getChecked() }
            elseif f.kind == "pick" then
                values[#values + 1] = { field = f, value = f.el:getSelected() }
            elseif f.kind == "text" then
                -- the page check marks a bad name again; a fixed one loses its mark here
                mark(f.el, nil)
                values[#values + 1] = { field = f, value = A.cleanText(f.el:getText(), f.max) }
            elseif f.kind == "clock" then
                local v = AM.clock(f.el:getText())
                mark(f.el, v == nil and getText("IGUI_MQ_Admin_HordeErrClock") or nil)
                if v ~= nil then values[#values + 1] = { field = f, value = v } end
            else
                local v, key, lo, hi = AM.check(f.el:getText(), f.range)
                mark(f.el, v == nil and getText(key, AM.num(lo), AM.num(hi)) or nil)
                if v ~= nil then
                    values[#values + 1] = { field = f, value = v }
                    -- target {min, max}: min <= max
                    if f.part and (f.part[1] == 1 or f.part[1] == 2) and string.match(f.path, "%.target$") then
                        local t = pairsOf[f.path] or {}
                        pairsOf[f.path] = t
                        t[f.part[1]] = { v, f }
                    end
                end
            end
        end
    end
    for _, t in pairs(pairsOf) do
        if t[1] and t[2] and t[1][1] > t[2][1] then
            mark(t[1][2].el, getText("IGUI_MQ_Admin_ErrMinMax"))
            mark(t[2][2].el, getText("IGUI_MQ_Admin_ErrMinMax"))
        end
    end
    if top then return nil, top, why end
    -- stable order: by field key
    MQ.Util.sort(values, function(a, b) return a.field.key < b.field.key end)
    return values
end

-- the bar says what is wrong with the topmost marked field (the range was only in its hover text) and the page
-- scrolls to it (interface review H2, 2026-10-28)
function A.fixFirst(P, el, why)
    A.say(P, getText("IGUI_MQ_Admin_FixErrorsWhy", why), "errorText")
    MQ.Draw.reveal(el)
end
local fixFirst = A.fixFirst

-- fields a button reads itself (events, towns): marks = { { el, message | nil } } in any order. Marks each; when
-- any is wrong, fixFirst on the topmost. true = something was wrong
function A.markAll(P, marks)
    local top, why
    for _, m in ipairs(marks) do
        local el, msg = m[1], m[2]
        markError(P, el, msg)
        if msg and (top == nil or el:getY() < top:getY() or (el:getY() == top:getY() and el:getX() < top:getX())) then
            top, why = el, msg
        end
    end
    if top then fixFirst(P, top, why) end
    return top ~= nil
end

-- typed values reach the draft only through Preview or this: leaving a tab, or a button that edits the draft itself
-- (theme batch, difficulty). false = a field is invalid (marked, and the bar says so)
function A.fold(P)
    local values, el, why = A.collect(P, P.pages[P.current])
    if values == nil then
        fixFirst(P, el, why)
        return false
    end
    AM.formToDraft(P.S, values)
    return true
end

-- bar "Apply" (key IGUI_MQ_Admin_Preview): fold the page's form into the draft, then cfg.preview the whole draft; the
-- confirm view it opens is where the change is applied (renamed from "Preview changes" after the 2026-10-25 playtest)
function A.onPreview(P)
    local pg = P.pages[P.current]
    local values, el, why = A.collect(P, pg)
    if values == nil then return fixFirst(P, el, why) end
    local check = A.pages[P.current].check
    if check then
        local err = check(P, pg, values)
        if err then return A.say(P, err, "errorText") end
    end
    AM.formToDraft(P.S, values)
    local changes = AM.draftChanges(P.S.draft)
    if #changes == 0 then return A.say(P, getText("IGUI_MQ_Admin_NoChanges"), "textMuted") end
    A.previewChanges(P, changes, P.draftSummary or A.count("IGUI_MQ_Admin_SummaryN", #changes), { fromDraft = true })
end

-- asks first: the draft can hold edits from every tab, and nothing brings them back
function A.onDiscard(P)
    local n = AM.draftCount(P.S.draft)
    if n == 0 then return A.discard(P) end
    A.ask(P, { title = getText("IGUI_MQ_Admin_Discard"), danger = true, text = A.count("IGUI_MQ_Admin_DiscardAsk", n),
        confirm = getText("IGUI_MQ_Admin_Discard"), onOk = function() A.discard(P) end })
end

-- also closes the confirm view: its Apply sends the changes it was opened with, the discarded ones too
function A.discard(P)
    P.S.draft, P.draftSummary, P.confirm = AM.newDraft(), nil, nil
    A.resync(P)
    A.say(P, nil)
end

-- changes -> cfg.preview -> confirm view. opts = { fromDraft, note, estimate }
function A.previewChanges(P, changes, summary, opts)
    local json = A.encode(changes)
    if json == nil then return A.say(P, getText("IGUI_MQ_Admin_TooBig"), "errorText") end
    A.send(P, "cfg.preview", { changes = json }, function(res)
        if not res.ok then return A.fail(P, res) end
        A.confirm(P, changes, res.rows, summary, opts)
    end)
end

function A.confirm(P, changes, rows, summary, opts)
    opts = opts or {}
    P.confirm = { changes = changes, rows = A.diffRows(P, rows), summary = summary, fromDraft = opts.fromDraft,
        note = opts.note, estimate = opts.estimate }
    P.msg = nil
    A.layout(P)
    P.pages[P.current].sp:setYScroll(0)
end

function A.onConfirmApply(P)
    local c = P.confirm
    local json = c and A.encode(c.changes)
    if json == nil then return end
    A.send(P, "cfg.apply", { changes = json, summary = string.sub(c.summary or "", 1, 256) }, function(res)
        if not res.ok then return A.fail(P, res) end
        P.confirm = nil
        if c.fromDraft then P.S.draft, P.draftSummary = AM.newDraft(), nil end
        P.msg, P.msgToken = getText("IGUI_MQ_Admin_Applied", tostring(res.historyId or "")), "success"
        A.loadConfig(P)
    end)
end

function A.onConfirmCancel(P)
    P.confirm = nil
    A.layout(P)
end

-- "Apply changes?" view: summary, estimate table and note first, then the rows with the old value struck through;
-- Apply / Cancel are in the bar (A.layoutBar)
function A.layoutConfirm(P, pg, F)
    local c = P.confirm
    F:head("cf:h", getText("IGUI_MQ_Admin_ConfirmHead"))
    F:text("cf:s", c.summary or "", "textMuted")
    if c.estimate then A.layoutEstimate(P, F, c.estimate) end
    F:text("cf:n", c.note or getText("IGUI_MQ_Admin_KeepUnlocked"), "textMuted")
    F:gap()
    local L = F:list("cf:l")
    local w = F.width - 2 * A.PAD
    local arrowW = textW("->")
    -- value columns as wide as the longest old/new value (capped at 160 and a quarter), the label gets the rest
    local valW = textW("0000")
    for _, r in ipairs(c.rows) do valW = math.max(valW, textW(r.before), textW(r.after)) end
    valW = math.floor(math.min(160, w / 4, valW + A.GAP))
    local labelW = w - 2 * valW - arrowW - 3 * A.GAP
    for i, r in ipairs(c.rows) do
        local x = A.PAD
        F:item()
        F:cells("cf:r" .. i, {
            { text = r.label, x = x, w = labelW, wrap = true },
            { text = r.before, x = x + labelW + A.GAP, w = valW, token = "textFaint", strike = true },
            { text = "->", x = x + labelW + valW + 2 * A.GAP, token = "textMuted" },
            { text = r.after, x = x + labelW + valW + arrowW + 3 * A.GAP, w = valW, token = "text" },
        })
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_NoDiff"))
end

-- difficulty estimate { { key, easy, normal, hard, custom? } } (Systems diff.preview)
function A.layoutEstimate(P, F, est)
    if type(est) ~= "table" or #est == 0 then return end
    local cols = { "easy", "normal", "hard" }
    for _, r in ipairs(est) do if r.custom ~= nil then cols[4] = "custom" end end
    local colW = 0
    for _, k in ipairs(cols) do colW = math.max(colW, textW(getText("IGUI_MQ_Admin_Diff_" .. k)) + 2 * A.GAP) end
    local L = F:list("cf:el")
    local right = F.width - A.PAD
    local function cellsOf(cells)
        for i, k in ipairs(cols) do
            cells[#cells + 1] = { text = cells.vals[k], x = right - (#cols - i) * colW, right = true }
        end
        cells.vals = nil
        return cells
    end
    local head = { { text = getText("IGUI_MQ_Admin_EstHead"), x = A.PAD }, vals = {} }
    for _, k in ipairs(cols) do head.vals[k] = getText("IGUI_MQ_Admin_Diff_" .. k) end
    F:listHead(cellsOf(head), "cf:eh")
    for i, r in ipairs(est) do
        local pct = r.key ~= "IGUI_MQ_Est_Tier3"
        local cells = { { text = getTextOrNull(tostring(r.key)) or tostring(r.key), x = A.PAD, w = right - #cols * colW - A.PAD },
            vals = {} }
        for _, k in ipairs(cols) do
            local v = r[k]
            cells.vals[k] = type(v) == "number" and (pct and (A.num(v) .. "%") or A.num(v)) or "-"
        end
        F:item()
        F:cells("cf:e" .. i, cellsOf(cells))
    end
    F:listEnd(L)
end

-- ===== dialogs =====

-- opts = { title, text, confirm, cancel?, danger, input = { placeholder }?, required, onOk = fn(text) }
-- confirm names the action ("Exclude from rewards", "Undo"); cancel names the way out when "Cancel" would read as
-- the action ("Cancel this horde"); a required reason is said in the text, because the
-- input has the focus when the dialog opens and a placeholder does not draw then (framework TextField)
function A.ask(P, opts)
    local UI = P.UI
    local text = opts.text
    if opts.required then text = text .. "\n\n" .. getText("IGUI_MQ_Admin_Reason") end
    UI.Dialog.show({ title = opts.title, text = text, confirmText = opts.confirm or getText("UI_Ok"),
        cancelText = opts.cancel or getText("UI_Cancel"), danger = opts.danger, theme = P.theme, opaque = true,
        input = opts.input,
        onResult = function(ok, typed)
            if not ok then return end
            typed = string.gsub(tostring(typed or ""), "^%s+", "")
            typed = string.gsub(typed, "%s+$", "")
            if opts.required and typed == "" then
                local again = {}
                for k, v in pairs(opts) do again[k] = v end
                again.text = opts.text .. "\n\n" .. getText("IGUI_MQ_Admin_ReasonRequired")
                return A.ask(P, again)
            end
            opts.onOk(typed)
        end })
end

-- ===== shell =====

function A.loadConfig(P)
    A.send(P, "cfg.get", {}, function(res)
        if not res.ok then
            P.loadError = res
            A.layout(P)
            return
        end
        P.loadError = nil
        P.S.overrides = type(res.overrides) == "table" and res.overrides or {}
        P.history, P.rev, P.file, P.dir = res.history or {}, res.rev, res.file, res.dir
        A.resync(P)
    end)
end

-- fields show server values again (after apply, discard, reload)
function A.resync(P)
    for _, pg in pairs(P.pages) do pg.version = pg.version + 1 end
    A.layout(P)
end

-- server values again; the draft stays, and so do valid values typed on this tab (folded in like on a tab switch)
function A.onReload(P)
    local values = A.collect(P, P.pages[P.current])
    if values then AM.formToDraft(P.S, values) end
    P.msg, P.confirm = nil, nil
    A.loadConfig(P)
    for id, pg in pairs(P.pages) do
        pg.loaded = false
        if id == P.current then A.loadPage(P, pg) end
    end
end

function A.loadPage(P, pg)
    local def = A.pages[pg.id]
    if not pg.loaded and def and def.load then
        pg.loaded = true
        def.load(P, pg)
    end
end

function A.layout(P)
    if P == nil or not P.root:isVisible() then return end
    local pg = P.pages[P.current]
    local F = pg.flow
    F:begin(pg.sp:contentWidth())
    if P.confirm then
        A.layoutConfirm(P, pg, F)
    elseif P.S.overrides == nil or MQ.Catalog == nil then
        F:text("load", P.loadError and A.codeText(P, P.loadError) or getText("IGUI_MQ_Admin_Loading"),
            P.loadError and "errorText" or "textMuted")
    else
        local ok, err = pcall(A.pages[P.current].layout, P, pg, F)
        if not ok then
            print("[MinidoracatQuestFor42] admin layout " .. tostring(P.current) .. ": " .. tostring(err))
            F:text("err", getText("IGUI_MQ_Admin_LayoutError"), "errorText")
        end
    end
    -- ScrollPanel sizes its content by the lowest visible child: an empty label leaves a margin under the last row
    local pad = F:get("~pad", newLabel)
    pad:setY(F.y + A.PAD)
    F:finish()
    A.layoutBar(P)
end

function A.select(P, id)
    if P.pages[id] == nil then id = A.TABS[1] end
    local cur = P.pages[P.current]
    if cur and id ~= P.current then
        -- typed values reach the draft only through Preview: fold them in before leaving the tab, or a Preview on
        -- another tab misses them and the next resync puts the server values back
        if not A.fold(P) then
            if P.tabs then P.tabs:setSelected(P.current, true) end
            if P.pick then P.pick:setSelected(P.current, true) end
            return
        end
        -- the same path can sit on two tabs (Basic and its own tab): the tab shown reads the draft again
        P.pages[id].version = P.pages[id].version + 1
        if P.confirm then
            P.confirm = nil
            P.msg, P.msgToken = getText("IGUI_MQ_Admin_ConfirmClosed"), "textMuted"
        end
    end
    if P.UI.Dropdown and P.UI.Dropdown.close then P.UI.Dropdown.close(P.root) end
    P.current = id
    if P.tabs then P.tabs:setSelected(id, true) end
    if P.pick then P.pick:setSelected(id, true) end
    for pid, pg in pairs(P.pages) do pg.sp:setVisible(pid == id) end
    A.loadPage(P, P.pages[id])
    A.layout(P)
end

function A.build(host)
    A.defineClasses()
    local UI, theme = host.UI, host.theme
    local P = { UI = UI, theme = theme, host = host, pages = {}, waits = {}, current = A.TABS[1],
        S = { defaults = MQ.Catalog and MQ.Catalog.DEFAULTS or {}, overrides = nil, draft = AM.newDraft() } }
    P.root = ISPanel:new(host.x or 0, host.y or 0, host.width, host.height)
    P.root:initialise()
    P.root.background = false
    host.parent:addChild(P.root)
    local items, strip = {}, {}
    for i, id in ipairs(A.TABS) do
        items[i] = { id = id, label = getText("IGUI_MQ_Admin_Tab_" .. id) }
        -- the framework strip draws no separator: a disabled "|" item stands between settings and operations
        if id == A.TAB_BREAK then strip[#strip + 1] = { id = "sep", label = "|" } end
        strip[#strip + 1] = items[i]
    end
    P.tabs = UI.Tabs.new({ items = strip, selected = P.current, theme = theme, target = P,
        onSelect = function(target, id) if id ~= "sep" then A.select(target, id) end end })
    if P.tabs.setItemEnabled then P.tabs:setItemEnabled("sep", false) end
    P.root:addChild(P.tabs)
    -- long translations: a dropdown replaces the tab strip when it does not fit
    P.pick = UI.Dropdown.new({ x = A.PAD, y = 4, options = items, selected = P.current, theme = theme, target = P,
        onChange = function(target, id) A.select(target, id) end })
    P.root:addChild(P.pick)
    for _, id in ipairs(A.TABS) do
        local sp = UI.ScrollPanel.new({ x = 0, y = 0, width = host.width, height = 100, theme = theme })
        P.root:addChild(sp)
        local pg = { id = id, sp = sp, flow = A.flow(sp, P), fields = {}, version = 0 }
        P.pages[id] = pg
        -- list boxes go under the children: the panel's prerender runs before them and sets the view stencil
        local base = sp.prerender
        function sp:prerender()
            base(self)
            if not self.isCollapsed then A.paintLists(self, pg.flow) end
        end
    end
    P.bar = ISPanel:new(0, 0, host.width, 10)
    P.bar:initialise()
    P.bar.background = false
    -- 1 px top line: the bar is fixed over the scrolled content, not the form's next row
    function P.bar:prerender()
        local c = theme.colors.border
        self:drawRect(0, 0, self.width, 1, c.a or 1, c.r, c.g, c.b)
    end
    P.root:addChild(P.bar)
    P.barFlow = A.flow(P.bar, P)
    return P
end

function A.place(P, width, height)
    P.root:setWidth(width)
    P.root:setHeight(height)
    local wide = P.tabs:getWidth() <= width - 2 * A.PAD
    P.tabs:setVisible(wide)
    P.pick:setVisible(not wide)
    P.tabs:setX(A.PAD)
    P.tabs:setY(4)
    local top = (wide and P.tabs:getHeight() or P.pick:getHeight()) + 8
    local barH = barHeight(P)
    for _, pg in pairs(P.pages) do
        pg.sp:setY(top)
        pg.sp:setWidth(width)
        pg.sp:setHeight(math.max(40, height - top - barH))
    end
    P.bar:setY(height - barH)
    P.bar:setWidth(width)
    P.bar:setHeight(barH)
end

function A.show(host)
    if MQ.Draw and MQ.Draw.sep then AM.SEP = MQ.Draw.sep() end
    local P = A.instance
    if P == nil or P.host.parent ~= host.parent or P.UI ~= host.UI then
        if P then P.root:setVisible(false) end
        P = A.build(host)
        A.instance = P
    end
    P.root:setVisible(true)
    A.place(P, host.width, host.height)
    if P.S.overrides == nil then A.loadConfig(P) end
    A.select(P, P.current)
end

function A.hide()
    local P = A.instance
    if P == nil then return end
    if P.UI.Dropdown and P.UI.Dropdown.close then P.UI.Dropdown.close(P.root) end
    P.root:setVisible(false)
end

function A.resize(width, height)
    local P = A.instance
    if P == nil then return end
    A.place(P, width, height)
    A.layout(P)
end

-- ===== history page: last 20 changes, undo, config.json state =====

-- summaries the server writes itself (Quests events, Seasons length, Config undo and file applies) are fixed English
-- codes; event rows carry the event name after the id ("event.add 3 Fest"), older rows only the id -> "#3"
local SERVER_SUMMARY = { { "^event%.add (%d+)(.*)$", "IGUI_MQ_Admin_HistEventAdd", true },
    { "^event%.remove (%d+)(.*)$", "IGUI_MQ_Admin_HistEventRemove", true },
    { "^horde%.now (%d+)(.*)$", "IGUI_MQ_Admin_HordeHistNow", true }, { "^horde%.stop (%d+)(.*)$", "IGUI_MQ_Admin_HordeHistStop", true },
    { "^season%.length (%d+)$", "IGUI_MQ_Admin_HistSeasonLength" }, { "^undo #(%d+)$", "IGUI_MQ_Admin_HistUndo" },
    { "^(config%.json)$", "IGUI_MQ_Admin_HistFile" } }
function A.summaryText(s)
    s = tostring(s or "")
    for _, m in ipairs(SERVER_SUMMARY) do
        local n, rest = string.match(s, m[1])
        if n and m[3] then
            local name = string.match(rest or "", "^ (.+)$")
            return getText(m[2], name or ("#" .. n))
        end
        if n then return getText(m[2], n) end
    end
    return s
end

-- config.json state from cfg.get (Config.file.status): when it was last in sync, or why the file was not applied
function A.fileText(fs)
    if fs.why == "read" or fs.why == "write" then return getText("IGUI_MQ_Admin_FileIo", A.time(fs.at), fs.why) end
    if fs.ok then return getText("IGUI_MQ_Admin_FileOk", A.time(fs.at)) end
    local why = A.whyText(fs.why)
    if fs.line then
        why = getText("IGUI_MQ_Admin_FileJson", fs.line)
    elseif fs.path then
        why = getText("IGUI_MQ_Admin_BadConfig", fs.path, why)
    end
    return getText("IGUI_MQ_Admin_FileBad", A.time(fs.at), why)
end

A.pages.history = {
    layout = function(P, pg, F)
        F:head("h", getText("IGUI_MQ_Admin_HistoryHead"))
        F:text("hn", getText("IGUI_MQ_Admin_HistoryNote") .. " " .. A.tzNote(), "textMuted")
        local rows = P.history or {}
        local L = F:list("hl")
        local timeW = A.timeW()
        local actors = {}
        for i, h in ipairs(rows) do actors[i] = h.actor or "-" end
        local actorW = A.colW(actors, math.floor(F.width / 3))
        F:listHead({ { text = getText("IGUI_MQ_Admin_ColTime"), x = A.PAD }, { text = getText("IGUI_MQ_Admin_ColActor"), x = A.PAD + timeW },
            { text = getText("IGUI_MQ_Admin_ColChanges"), x = F.width - A.PAD, right = true } })
        for i, h in ipairs(rows) do
            F:item()
            F:cells("r" .. i, {
                { text = A.time(h.at), x = A.PAD, token = "textMuted" },
                { text = tostring(h.actor or "-"), x = A.PAD + timeW, w = actorW },
                { text = A.count("IGUI_MQ_Admin_Items", h.n or 0), x = F.width - A.PAD, right = true, token = "textMuted" },
            })
            F:text("s" .. i, A.summaryText(h.summary), "text")
            if h.undoable ~= false then
                local undo = F:button("u" .. i, getText("IGUI_MQ_Admin_Undo"), A.onUndo)
                undo.entry = h
                F:row({ undo })
            end
        end
        F:listEnd(L, getText("IGUI_MQ_Admin_HistoryEmpty"))
        F:head("io", getText("IGUI_MQ_Admin_FileHead"))
        -- the folder this server really uses (cfg.get dir; single player: sp_<save>)
        F:text("ion", getText("IGUI_MQ_Admin_FileNote", "Zomboid/Lua/" .. tostring(P.dir or "MinidoracatQuest/")), "textMuted")
        F:text("ioo", getText("IGUI_MQ_Admin_FileOnly"), "textMuted")
        if type(P.file) == "table" then F:text("ios", A.fileText(P.file), P.file.ok and "textMuted" or "errorText") end
    end,
}

function A.onUndo(P, b)
    local h = b.entry
    A.ask(P, { title = getText("IGUI_MQ_Admin_Undo"), text = getText("IGUI_MQ_Admin_UndoAsk", A.summaryText(h.summary), A.time(h.at)),
        confirm = getText("IGUI_MQ_Admin_Undo"), onOk = function()
            A.send(P, "cfg.undo", { historyId = h.id }, function(res)
                if not res.ok then return A.fail(P, res) end
                P.msg, P.msgToken = getText("IGUI_MQ_Admin_Undone"), "success"
                A.loadConfig(P)
            end)
        end })
end

if MQ.ClientUI and MQ.ClientUI.registerAdminPage then MQ.ClientUI.registerAdminPage(A) end
