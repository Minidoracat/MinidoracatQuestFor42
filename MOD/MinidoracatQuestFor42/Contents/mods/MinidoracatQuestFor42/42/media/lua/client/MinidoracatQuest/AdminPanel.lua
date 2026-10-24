-- MinidoracatQuest/AdminPanel.lua: admin page shell inside the quest window (ARCHITECTURE.md 6.2, 7; spec 13).
-- Sub-tabs + one ScrollPanel per tab + bottom bar (pending draft, preview, reload, status). Pages register
-- in A.pages (AdminAchv.lua, AdminPages.lua). Every config edit goes into a local draft first and is only
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

A.TABS = { "achv", "quests", "season", "exchange", "players", "balance", "towns", "history" }
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
    if self.zebra then
        local z = colors.hover
        self:drawRect(0, 0, self.width, self.height, 0.5 * (z.a or 1), z.r, z.g, z.b)
    end
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

local Flow = {}
Flow.__index = Flow

function A.flow(parent, P)
    return setmetatable({ parent = parent, P = P, pool = {}, seen = {}, gen = 0, y = 0, width = 0 }, Flow)
end

function Flow:begin(width)
    self.gen, self.y, self.width = self.gen + 1, A.PAD, width
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
function Flow:text(key, text, token, font, box, title)
    font = font or UIFont.Small
    local P = self.P
    local colors = P.theme.colors
    local l = self:get(key, newLabel)
    local pad = box and 8 or 0
    local maxW = self.width - 2 * A.PAD - 2 * pad
    local lines = {}
    if title then lines[1] = title end
    for _, line in ipairs(wrapLines(P.UI, text, maxW, font)) do lines[#lines + 1] = line end
    l.color, l.strike = colors[token or "text"] or colors.text, false
    l.box = box and (colors[box] or colors.accent) or nil
    local w, h = setLines(l, lines, font, title and UIFont.Medium or nil, pad, pad)
    l:setWidth(box and (self.width - 2 * A.PAD) or w)
    l:setHeight(h)
    l:setX(A.PAD)
    l:setY(self.y)
    self.y = self.y + h + A.GAP
    return l
end

function Flow:head(key, text) return self:text(key, text, "text", UIFont.Medium) end

-- controls left to right, wrapping; vertically centred per line
function Flow:row(ctrls, x0)
    x0 = x0 or A.PAD
    local x, rowY, rowH, line = x0, self.y, 0, {}
    local right = self.width - A.PAD
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
    self.y = rowY + rowH + A.GAP
end

-- table row of texts; returns the row element (placed, y advanced)
function Flow:cells(key, cells, zebra)
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
    r.cells, r.zebra = cells, zebra
    r:setX(0)
    r:setY(self.y)
    r:setWidth(self.width)
    r:setHeight(lines * fontH() + 8)
    self.y = self.y + r.height
    return r
end

-- callbacks go through trampolines so a reused element always calls the latest handler
local function click(P, b) if b.handler then b.handler(P, b) end end
local function checked(P, value, box) if box.handler then box.handler(P, value, box) end end
local function picked(P, id, dd) if dd.handler then dd.handler(P, id, dd) end end

function Flow:button(key, title, handler, style)
    local P = self.P
    local b = self:get(key, function()
        return P.UI.Button.new({ x = 0, y = 0, title = title, style = style, theme = P.theme, target = P, onClick = click })
    end)
    b:setTitle(title)
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

-- options = { { id, label } }; selected kept when still present
function Flow:dropdown(key, options, selected, handler)
    local P = self.P
    local dd = self:get(key, function()
        return P.UI.Dropdown.new({ x = 0, y = 0, options = options, selected = selected, theme = P.theme,
            target = P, onChange = picked, maxRows = 12 })
    end)
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

-- "1 item" / "N items": key .. "1" holds the singular (same text where the language does not inflect)
function A.count(key, n) return getText(n == 1 and key .. "1" or key, n) end

function A.tzNote() return getText("IGUI_MQ_Admin_TzNote", AM.tzText()) end

function A.codeText(P, res)
    if res.code == "BAD_CONFIG" and type(res.detail) == "table" then
        return getText("IGUI_MQ_Admin_BadConfig", A.pathLabel(P, tostring(res.detail.path or "?")), tostring(res.detail.why or "?"))
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
    if type(t) == "table" and type(t.nameKey) == "string" then return getText(t.nameKey, "N") end
    return getTextOrNull("IGUI_MQ_Q_" .. tid, "N") or tid   -- with the argument, %1 does not warn (Draw.textOrNull)
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
        else
            out[#out + 1] = { label = label, before = A.valueText(r.before), after = A.valueText(r.after) }
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

function A.layoutBar(P)
    local F = P.barFlow
    if F == nil then return end
    F:begin(P.bar.width)
    F.y = 4
    local n = AM.draftCount(P.S.draft)
    local ctrls = {}
    local prev = F:button("preview", n > 0 and getText("IGUI_MQ_Admin_PreviewN", n) or getText("IGUI_MQ_Admin_Preview"),
        A.onPreview, "primary")
    prev:setEnabled(P.confirm == nil and P.S.overrides ~= nil)
    ctrls[1] = prev
    if n > 0 then ctrls[#ctrls + 1] = F:button("discard", getText("IGUI_MQ_Admin_Discard"), A.onDiscard, "ghost") end
    ctrls[#ctrls + 1] = F:button("reload", getText("IGUI_MQ_Admin_Reload"), A.onReload, "ghost")
    F:row(ctrls)
    if A.busy(P) then
        F:text("msg", getText("IGUI_MQ_Admin_Waiting"), "textMuted")
    elseif P.msg then
        F:text("msg", P.msg, P.msgToken)
    end
    F:finish()
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

-- number field bound to a config path (part = key list inside the value); range = AM.RANGE key
function A.numField(P, pg, key, path, part, range, width)
    local f = field(pg, key)
    f.path, f.part, f.range, f.kind = path, part, range, "num"
    local r = AM.RANGE[range]
    f.el = pg.flow:field("f:" .. key, width or math.max(60, textW(AM.num(r[2])) + 20))
    if f.at ~= pg.version then
        f.at = pg.version
        local v = valueAt(P, f)
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

-- read this page's bound fields; nil when any is invalid (marked on the field)
function A.collect(P, pg)
    local values, bad, pairsOf = {}, false, {}
    for _, f in pairs(pg.fields) do
        if f.gen == pg.flow.gen and f.path then
            if f.kind == "bool" then
                values[#values + 1] = { field = f, value = f.el:getChecked() }
            else
                local v, key, lo, hi = AM.check(f.el:getText(), f.range)
                markError(P, f.el, v == nil and getText(key, AM.num(lo), AM.num(hi)) or nil)
                if v == nil then
                    bad = true
                else
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
            markError(P, t[1][2].el, getText("IGUI_MQ_Admin_ErrMinMax"))
            markError(P, t[2][2].el, getText("IGUI_MQ_Admin_ErrMinMax"))
            bad = true
        end
    end
    -- stable order: by field key
    MQ.Util.sort(values, function(a, b) return a.field.key < b.field.key end)
    if bad then return nil end
    return values
end

-- bar "Preview changes": fold the page's form into the draft, then cfg.preview the whole draft
function A.onPreview(P)
    local pg = P.pages[P.current]
    local values = A.collect(P, pg)
    if values == nil then return A.say(P, getText("IGUI_MQ_Admin_FixErrors"), "errorText") end
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

function A.onDiscard(P)
    P.S.draft, P.draftSummary = AM.newDraft(), nil
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

-- "Apply changes?" view: summary, rows with the old value struck through, note, estimate table
function A.layoutConfirm(P, pg, F)
    local c = P.confirm
    F:head("cf:h", getText("IGUI_MQ_Admin_ConfirmHead"))
    F:text("cf:s", c.summary or "", "textMuted")
    local w = F.width - 2 * A.PAD
    local arrowW = textW("->")
    -- value columns as wide as the longest old/new value (capped at 160 and a quarter), the label gets the rest
    local valW = textW("0000")
    for _, r in ipairs(c.rows) do valW = math.max(valW, textW(r.before), textW(r.after)) end
    valW = math.floor(math.min(160, w / 4, valW + A.GAP))
    local labelW = w - 2 * valW - arrowW - 3 * A.GAP
    for i, r in ipairs(c.rows) do
        local x = A.PAD
        F:cells("cf:r" .. i, {
            { text = r.label, x = x, w = labelW, wrap = true },
            { text = r.before, x = x + labelW + A.GAP, w = valW, token = "textFaint", strike = true },
            { text = "->", x = x + labelW + valW + 2 * A.GAP, token = "textMuted" },
            { text = r.after, x = x + labelW + valW + arrowW + 3 * A.GAP, w = valW, token = "accent" },
        }, i % 2 == 0)
    end
    if #c.rows == 0 then F:text("cf:none", getText("IGUI_MQ_Admin_NoDiff"), "textMuted") end
    F:gap()
    if c.estimate then A.layoutEstimate(P, F, c.estimate) end
    F:text("cf:n", c.note or getText("IGUI_MQ_Admin_KeepUnlocked"), "textMuted")
    local apply = F:button("cf:apply", getText("IGUI_MQ_Admin_ApplyChanges"), A.onConfirmApply, "primary")
    apply:setEnabled(not A.busy(P))
    F:row({ apply, F:button("cf:cancel", getText("UI_Cancel"), A.onConfirmCancel, "ghost") })
end

-- difficulty estimate { { key, easy, normal, hard, custom? } } (Systems diff.preview)
function A.layoutEstimate(P, F, est)
    if type(est) ~= "table" or #est == 0 then return end
    local cols = { "easy", "normal", "hard" }
    for _, r in ipairs(est) do if r.custom ~= nil then cols[4] = "custom" end end
    local colW = 0
    for _, k in ipairs(cols) do colW = math.max(colW, textW(getText("IGUI_MQ_Admin_Diff_" .. k)) + 2 * A.GAP) end
    local right = F.width - A.PAD
    local function line(key, cells)
        for i, k in ipairs(cols) do
            cells[#cells + 1] = { text = cells.vals[k], x = right - (#cols - i) * colW, right = true, token = cells.token }
        end
        cells.vals, cells.token = nil, nil
        F:cells(key, cells)
    end
    local head = { { text = getText("IGUI_MQ_Admin_EstHead"), x = A.PAD, token = "textMuted" }, vals = {}, token = "textMuted" }
    for _, k in ipairs(cols) do head.vals[k] = getText("IGUI_MQ_Admin_Diff_" .. k) end
    line("cf:eh", head)
    for i, r in ipairs(est) do
        local pct = r.key ~= "IGUI_MQ_Est_Tier3"
        local cells = { { text = getTextOrNull(tostring(r.key)) or tostring(r.key), x = A.PAD, w = right - #cols * colW - A.PAD },
            vals = {} }
        for _, k in ipairs(cols) do
            local v = r[k]
            cells.vals[k] = type(v) == "number" and (pct and (A.num(v) .. "%") or A.num(v)) or "-"
        end
        line("cf:e" .. i, cells)
    end
    F:gap()
end

-- ===== dialogs =====

-- opts = { title, text, confirm, danger, input = { placeholder }?, required, onOk = fn(text) }
function A.ask(P, opts)
    local UI = P.UI
    UI.Dialog.show({ title = opts.title, text = opts.text, confirmText = opts.confirm or getText("UI_Ok"),
        cancelText = getText("UI_Cancel"), danger = opts.danger, theme = P.theme, opaque = true,
        input = opts.input,
        onResult = function(ok, text)
            if not ok then return end
            text = string.gsub(tostring(text or ""), "^%s+", "")
            text = string.gsub(text, "%s+$", "")
            if opts.required and text == "" then
                local again = {}
                for k, v in pairs(opts) do again[k] = v end
                again.text = opts.text .. "\n\n" .. getText("IGUI_MQ_Admin_ReasonRequired")
                return A.ask(P, again)
            end
            opts.onOk(text)
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
        P.history, P.rev, P.file = res.history or {}, res.rev, res.file
        A.resync(P)
    end)
end

-- fields show server values again (after apply, discard, reload)
function A.resync(P)
    for _, pg in pairs(P.pages) do pg.version = pg.version + 1 end
    A.layout(P)
end

function A.onReload(P)
    P.msg = nil
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
    F:finish()
    A.layoutBar(P)
end

function A.select(P, id)
    if P.pages[id] == nil then id = A.TABS[1] end
    if P.confirm and id ~= P.current then P.confirm = nil end
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
    local items = {}
    for i, id in ipairs(A.TABS) do items[i] = { id = id, label = getText("IGUI_MQ_Admin_Tab_" .. id) } end
    P.tabs = UI.Tabs.new({ items = items, selected = P.current, theme = theme, target = P,
        onSelect = function(target, id) A.select(target, id) end })
    P.root:addChild(P.tabs)
    -- long translations: a dropdown replaces the tab strip when it does not fit
    P.pick = UI.Dropdown.new({ x = A.PAD, y = 4, options = items, selected = P.current, theme = theme, target = P,
        onChange = function(target, id) A.select(target, id) end })
    P.root:addChild(P.pick)
    for _, id in ipairs(A.TABS) do
        local sp = UI.ScrollPanel.new({ x = 0, y = 0, width = host.width, height = 100, theme = theme })
        P.root:addChild(sp)
        P.pages[id] = { id = id, sp = sp, flow = A.flow(sp, P), fields = {}, version = 0 }
    end
    P.bar = ISPanel:new(0, 0, host.width, 10)
    P.bar:initialise()
    P.bar.background = false
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
    local barH = 2 * fontH() + 26
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
    local why = tostring(fs.why or "?")
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
        if #rows == 0 then F:text("none", getText("IGUI_MQ_Admin_HistoryEmpty"), "textMuted") end
        local timeW = A.timeW()
        for i, h in ipairs(rows) do
            F:cells("r" .. i, {
                { text = A.time(h.at), x = A.PAD, token = "textMuted" },
                { text = tostring(h.actor or "-"), x = A.PAD + timeW, w = 120 },
                { text = A.count("IGUI_MQ_Admin_Items", h.n or 0), x = F.width - A.PAD, right = true, token = "textMuted" },
            }, i % 2 == 0)
            F:text("s" .. i, A.summaryText(h.summary), "text")
            if h.undoable ~= false then
                local undo = F:button("u" .. i, getText("IGUI_MQ_Admin_Undo"), A.onUndo, "ghost")
                undo.entry = h
                F:row({ undo })
            end
        end
        F:gap()
        F:head("io", getText("IGUI_MQ_Admin_FileHead"))
        F:text("ion", getText("IGUI_MQ_Admin_FileNote"), "textMuted")
        if type(P.file) == "table" then F:text("ios", A.fileText(P.file), P.file.ok and "textMuted" or "errorText") end
    end,
}

function A.onUndo(P, b)
    local h = b.entry
    A.ask(P, { title = getText("IGUI_MQ_Admin_Undo"), text = getText("IGUI_MQ_Admin_UndoAsk", A.summaryText(h.summary), A.time(h.at)),
        onOk = function()
            A.send(P, "cfg.undo", { historyId = h.id }, function(res)
                if not res.ok then return A.fail(P, res) end
                P.msg, P.msgToken = getText("IGUI_MQ_Admin_Undone"), "success"
                A.loadConfig(P)
            end)
        end })
end

if MQ.ClientUI and MQ.ClientUI.registerAdminPage then MQ.ClientUI.registerAdminPage(A) end
