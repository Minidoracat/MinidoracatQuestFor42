-- MinidoracatQuest/Hud.lua: the tracker panel (design round 7: a floating panel, only what the player pinned).
--   Up to LIMIT.MAX_PINS pinned quests / achievements with their progress, top left beside the vanilla sidebar,
--   and above them one horde row while a horde is announced, waits for players, runs or rests between waves (not a
--   pin, not counted); a Map button on its second line, an x on its first that takes this horde off the panel
--   (C.hordeHidden; the next horde shows again). After a horde, while its pushed results wait for the player to be
--   safe (HordeResult.pending), that row says so and has a Results button.
--   Drag to move; the arrow or the MinidoracatQuest_Hud key (Entry.lua) collapses it to the title row (both go to
--   layout.ini); hovering a pin row shows an x that unpins it. Hidden while there is nothing to show, the player is
--   dead, the Esc menu is up or V hid the UI; it stays while the main window is open, so a Track press shows up at
--   once (user 2026-10-24), and windows draw over it (backMost). It never shows itself while the UI is hidden: the
--   vanilla V / Esc toggle restores what it hid.
--   Width (plan hud-width, user 2026-10-29): as wide as the widest row needs, between H.minWidth() and H.width(); a
--   horde or results row takes all of H.width(). Dragging the right edge sets a smaller cap (layout.ini maxW), a
--   double click or a drag past H.width() clears it; a panel in the right half keeps its right edge when the width
--   changes. The background alpha is the HudOpacity MOD option; under 80 % the text gets a shadow (Draw.renderOps).
--   Data: state.pins, state.trk and state.hordes, kept fresh by the server while the panel is on ("track"; Sync.lua).
--   Texts and widths are laid out when the data changes; render only walks the op list (Draw canvas).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"
require "MinidoracatQuest/PageAchievements"
require "MinidoracatQuest/HordeResult"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local first = Q.Hud == nil
local H = Q.Hud or {}
Q.Hud = H

H.LAYOUT_KEY = "MinidoracatQuestHud"
H.SYNC_MS = 500
H.PAD = 8
H.show = H.show ~= false     -- MOD option "ShowHud" (Entry.lua)
H.opacity = H.opacity or 0.8 -- MOD option "HudOpacity" / 100 (Entry.lua); 0.8 is the framework's surface alpha
H.SHADOW_BELOW = 0.8         -- a lighter background than this gives the text a shadow
H.GRIP = 8                   -- the right edge that resizes
H.DOUBLE_MS = 500            -- two presses on that edge this close: back to the automatic width

-- ===== model (harness tests these) =====
-- the live horde the panel shows: not the one the player took off it
local function shownHorde(state)
    local hs = type(state) == "table" and type(state.hordes) == "table" and state.hordes or nil
    local h = hs and D.hordeLive(hs.cur)
    if h == nil or (C.hordeHidden ~= nil and h.id == C.hordeHidden) then return nil end
    return h
end

-- the horde row: { id = "horde", horde = true, hordeId, tag, name, time, line, prog?, target?, mapX?, mapY? } or nil.
-- Every countdown says what it counts to (design 1): announced "4:29 to the start", waiting "Waiting 52:10", active
-- "52:10 left", rest "0:24 to the next wave". When N > 1 the name is "Wave W/N - <spot>", the spot without its town
-- (D.hordeName spotOnly; the design mock), so the prefix and the countdown leave room for the spot. Line 2 starts with
-- the coordinates, so a long language cuts the rule, not the spot (design 5.2); active shows who joined (1+ kill) and
-- cleared / wave size. mapX / mapY: the Map button (every live state, while the vanilla map is allowed)
function H.hordeRow(state, now)
    local h = shownHorde(state)
    if h == nil then return nil end
    now = now or C.serverNow()
    local st = h.state
    local r = { id = "horde", horde = true, hordeId = h.id, tag = getText("IGUI_MQ_Horde_Tag"), name = D.hordeName(h, true),
        state = st }
    if st == "active" then
        local n = tonumber(h.size) or 0
        r.prog, r.target = math.max(0, n - (tonumber(h.left) or 0)), n
        r.time = getText("IGUI_MQ_UI_Left", D.countdown((tonumber(h.endsAt) or now) - now))
        r.line = getText("IGUI_MQ_Horde_HudActive", D.num(tonumber(h.joined) or 0), D.num(r.prog), D.num(n))
    elseif st == "waiting" then
        r.time = getText("IGUI_MQ_Horde_WaitLeft", D.countdown((tonumber(h.expireAt) or now) - now))
        r.line = getText("IGUI_MQ_Horde_HudWait", tostring(h.x), tostring(h.y))
    elseif st == "rest" then
        r.time = getText("IGUI_MQ_Horde_NextIn", D.countdown((tonumber(h.nextAt) or now) - now))
        r.line = getText("IGUI_MQ_Horde_HudRest", tostring((tonumber(h.wave) or 1) + 1))
    else
        r.time = getText("IGUI_MQ_Horde_StartsIn", D.countdown((tonumber(h.startMs) or now) - now))
        r.line = getText("IGUI_MQ_Horde_HudSoon", tostring(h.x), tostring(h.y))
    end
    if D.HORDE_MAP[st] and D.mapAllowed() then r.mapX, r.mapY = tonumber(h.x), tonumber(h.y) end
    return r
end

-- pushed results waiting for the player to be safe (no live horde row): { id = "result", horde = true, result, tag,
-- name, line, state } or nil; the chip is green for a cleared horde
function H.resultRow()
    local s = Q.HordeResult.pending
    if s == nil then return nil end
    local key = s.state == "success" and "IGUI_MQ_Horde_HudDone_success" or "IGUI_MQ_Horde_HudDone_failed"
    return { id = "result", horde = true, result = s, tag = getText("IGUI_MQ_Horde_Tag"), name = getText(key, D.hordePlace(s)),
        line = getText("IGUI_MQ_Horde_HudResultWait"), state = s.state }
end

-- the horde row first, then one row per pin that still names something: { id, tag, name, prog, target, done, pts, color }
function H.rows(state, defs, now)
    local out = {}
    if type(state) ~= "table" then return out end
    out[1] = H.hordeRow(state, now) or H.resultRow()
    local trk = type(state.trk) == "table" and state.trk or {}
    local achv = type(state.achv) == "table" and state.achv or {}
    for _, id in ipairs(type(state.pins) == "table" and state.pins or {}) do
        local kind, n = string.match(tostring(id), "^([dw])(%d)$")
        if kind ~= nil then
            local list = state[kind == "d" and "day" or "week"]
            local q = type(list) == "table" and type(list.quests) == "table" and list.quests[tonumber(n)] or nil
            if type(q) == "table" and (q.state == "active" or q.state == "done") then
                local tag = q.shared and "IGUI_MQ_UI_Shared" or (kind == "d" and "IGUI_MQ_UI_HudDaily" or "IGUI_MQ_UI_HudWeekly")
                out[#out + 1] = { id = id, tag = getText(tag), name = D.questName(q), prog = tonumber(q.prog) or 0,
                    target = tonumber(q.target) or 0, done = q.state == "done",
                    pts = tonumber(q.ptsNow) or tonumber(q.pts) or 0 }
            end
        else
            local aid = string.match(tostring(id), "^a:(.+)$")
            local a = aid ~= nil and defs.achById[aid] or nil
            if a ~= nil then
                local t = type(trk[aid]) == "table" and trk[aid] or {}
                local m = Q.PageAchievements.model(a, tonumber(t.t) or achv[aid] or 0, { life = t.v, total = t.v })
                if not m.maxed and m.nextTier ~= nil then
                    out[#out + 1] = { id = id, tag = getText("IGUI_MQ_UI_HudAch"),
                        name = D.achName(a) .. " " .. D.tierName(m.nextTier), prog = m.value or 0, target = m.target or 0,
                        color = D.tierColor(m.nextTier) }
                end
            end
        end
    end
    return out
end

-- ===== geometry =====
-- the cap: wider with the font and the screen (the spot name and line 2's count and Map button need the room), never
-- narrower than 0.3.1's min(360, 20 x font) (1024 wide at 16 px: 320, not 260; review 1029 r1, C3)
function H.width()
    local fh = D.fontH()
    return math.max(260, math.min(360, 20 * fh), math.min(24 * fh, math.floor(getCore():getScreenWidth() / 4)))
end
-- the narrowest the panel gets, also the narrowest cap a drag sets (192 px at 16 px)
function H.minWidth() return 12 * D.fontH() end
function H.countText(r) return getText("IGUI_MQ_UI_Progress", D.num(math.min(r.prog, r.target)), D.num(r.target)) end
-- the widest count of the open pin rows: the counts share one right-aligned column and every bar ends left of it
function H.countW(rows)
    local w = 0
    for _, r in ipairs(rows) do
        if not r.horde and not r.done then w = math.max(w, D.textW(H.countText(r))) end
    end
    return w
end
-- what the widest row needs, between H.minWidth() and the cap (H.width(), or maxW when the player dragged a smaller
-- one; a maxW under the floor, saved with a smaller font or edited in layout.ini, is held to it). A horde or results
-- row takes the whole cap: its layout was checked at H.width() in 12 languages (review 1029: long spot names). The
-- sums follow H.layout: the title row (star 20, gap 8, arrow 16), line 1 of a row (chip, 6, name, 16 for the hover
-- x), line 2 (a bar of 4 x font, 8, the count column), a done row (name, 24, points, 16)
function H.fitWidth(rows, maxW)
    local cap, fh, pad = H.width(), D.fontH(), H.PAD
    local least = math.min(H.minWidth(), cap)
    if maxW ~= nil then cap = math.max(least, math.min(cap, maxW)) end
    if rows[1] ~= nil and rows[1].horde then return cap end
    local need = 2 * pad + 44 + D.textW(getText("IGUI_MQ_UI_HudTitle"))
        + D.textW(getText("IGUI_MQ_UI_Count", tostring(#rows), tostring(Q.Contract.LIMIT.MAX_PINS)))
    local countW = H.countW(rows)
    for _, r in ipairs(rows) do
        local name = D.chipW(r.tag) + 6 + D.textW(r.name)
        if r.done then
            need = math.max(need, 2 * pad + name + 40 + D.textW(getText("IGUI_MQ_UI_PlusPoints", D.num(r.pts))))
        else
            need = math.max(need, 2 * pad + name + 16, 2 * pad + countW + 8 + 4 * fh)
        end
    end
    return math.min(cap, math.max(least, need))
end
-- a new width: a panel in the right half keeps its right edge, except while the player drags that edge. A panel
-- that was never moved sits at H.defaultXY(), in the left half
function H.fit(p, w)
    if w == p.width then return end
    if p.sizing == nil and p.x + p.width / 2 > getCore():getScreenWidth() / 2 then p:setX(p.x + p.width - w) end
    p:setWidth(w)
end
function H.titleH() return D.fontH() + 10 end
-- an open row: tag + name, then bar + progress (long DE / FR / RU names keep the full width); a done row: one line.
-- The horde row is 4 px taller: its Map hit box spans line 2 (24 px and more) without reaching the next row's unpin
function H.rowH(r) return D.chipH() + (r.done and 6 or (2 + D.fontH() + (r.horde and 10 or 6))) end

function H.defaultXY()
    local data = getPlayerData and getPlayerData(0) or nil
    local eq = data and data.equipped or nil
    local x = eq ~= nil and eq.getRight ~= nil and (eq:getRight() + 12) or (getPlayerScreenLeft(0) + 70)
    local y = getPlayerScreenTop(0) + 10
    -- the vanilla inventory starts as a title bar across the top (ISPlayerDataObject: x = w / 2 - w / 3, y = 0):
    -- when the panel would run under that bar, it starts below it
    local inv = data and data.playerInventory or nil
    if inv ~= nil and inv:isVisible() and inv:getX() < x + H.width() and inv:getRight() > x
        and inv:getY() < y + H.titleH() then
        y = math.max(y, inv:getY() + inv:titleBarHeight() + 6)
    end
    return x, y
end

function H.clamp(p)
    local core = getCore()
    local x = math.max(0, math.min(p.x, core:getScreenWidth() - p.width))
    local y = math.max(0, math.min(p.y, core:getScreenHeight() - p.height))
    if x ~= p.x then p:setX(x) end
    if y ~= p.y then p:setY(y) end
end

-- layout.ini now (the path the game runs on every save; the Dock does the same)
function H.persist()
    local LM = ISLayoutManager
    if LM ~= nil and type(LM.windows) == "table" and LM.windows[H.LAYOUT_KEY] ~= nil and LM.OnPostSave then
        pcall(LM.OnPostSave)
    end
end

-- ===== layout: background, title row (star, name, pin count, arrow), the horde row, one row per pin =====
-- the horde row is not a pin (no unpin x) and only an active horde draws in the horde red, the others in its orange;
-- p.hordeTime is what onTick compares. Its x sits at the right of line 1, always shown (red under the mouse, render):
-- hit box p.hideHit, at least 20 px wide and the line's height, the countdown left of it. The Map button sits at the
-- right of line 2: hit box p.mapHit, the whole line 2 (24 px and more) up to the next row; while it runs line 2
-- puts the count text and the button first and the bar takes what is left (none under 24 px). Neither hit box is
-- in p.hits (those are unpin targets); their hover texts go through the canvas tips. In the rest the countdown
-- opens line 2 instead: "Next wave in 0:38" beside "Wave 2/3 cleared" left no room for the spot even in English
-- (quest-hui-en-1027a; ES kept "Oleada 2..."). The results row: a Results button at the right of line 1
-- (p.resultHit), the wait note on line 2.
local function tip(b, x, y, w, h, text)
    local tips = b.cv.tips
    tips[#tips + 1] = { x = x, y = y, w = w, h = h, text = text, tw = D.textW(text), th = D.fontH() }
end

local function resultRowOps(b, r, y, w, pad, lh)
    local nameX = pad + b:chip(pad, y, r.tag, r.state == "success" and D.EXTRA.success or "textMuted") + 6
    local label = getText("IGUI_MQ_Horde_ResultBtn")
    local bw = D.textW(label) + 12
    local bx = w - pad - bw
    b:border(bx, y + 1, bw, lh + 2, "textMuted")
    b:text(bx + 6, y + 3, label, "text")
    b.cv.resultHit = { x0 = bx, y0 = y, x1 = bx + bw, y1 = y + D.chipH() }
    b:fitText(nameX, y + 3, r.name, bx - 6 - nameX, "text")
    b:fitText(pad, y + D.chipH() + 2, r.line, w - 2 * pad, "textMuted")
end

local function hordeRowOps(b, r, y, w, pad, lh)
    if r.result then return resultRowOps(b, r, y, w, pad, lh) end
    local tok = r.state == "active" and D.EXTRA.horde or D.EXTRA.hordeSoon
    local nameX = pad + b:chip(pad, y, r.tag, tok) + 6
    local ch = D.chipH()
    local xr = w - pad - 18
    b.cv.hideHit = { x0 = xr, y0 = y, x1 = w, y1 = y + ch, xx = w - pad - 12, ty = y + 3, id = r.hordeId }
    tip(b, xr, y, w - xr, ch, getText("IGUI_MQ_Horde_Hide"))
    local rest = r.state == "rest"
    local tw = rest and 0 or b:textRight(xr - 4, y + 3, r.time, tok) + 8
    b:fitText(nameX, y + 3, r.name, xr - 4 - tw - nameX, "text")
    local ly = y + ch + 2
    local lx = rest and pad + b:text(pad, ly, r.time, tok) + 6 or pad
    local right = w - pad
    if r.mapX ~= nil then
        local label = getText("IGUI_MQ_UI_Map")
        local bw, bh = D.textW(label) + 12, lh + 2
        local bx, by = w - pad - bw, ly - 1
        b:border(bx, by, bw, bh, "textMuted")
        b:text(bx + 6, ly, label, "text")
        tip(b, bx, by, bw, bh, getText("IGUI_MQ_UI_ShowOnMap"))
        b.cv.mapHit = { x0 = bx, y0 = y + ch, x1 = bx + bw, y1 = y + H.rowH(r) - 2, x = r.mapX, y = r.mapY }
        right = bx - 6
    end
    if r.target == nil then return b:fitText(lx, ly, r.line, right - lx, "textMuted") end
    -- the count does not fit: cut it (it would draw past the panel's left edge right-aligned), no bar (C5)
    if D.textW(r.line) > right - lx then return b:fitText(lx, ly, r.line, right - lx, "textMuted") end
    local pw = b:textRight(right, ly, r.line, "textMuted")
    local barW = right - lx - pw - 8
    if barW >= 24 then
        b:bar(lx, ly + math.floor((lh - 4) / 2), barW, 4, r.target > 0 and r.prog / r.target or 0, D.EXTRA.horde)
    end
end

function H.layout(p)
    H.dirty = false
    local rows = H.rows(C.state, C.defs())
    local pins = rows[1] ~= nil and rows[1].horde and #rows - 1 or #rows
    p.rows, p.hits, p.mapHit, p.hideHit, p.resultHit = rows, {}, nil, nil, nil
    p.hordeTime = rows[1] ~= nil and rows[1].horde and rows[1].time or nil
    H.fit(p, H.fitWidth(rows, p.maxW))
    p.textShadow = H.opacity < H.SHADOW_BELOW
    local b = D.begin(p)
    local pad, w, lh = H.PAD, p.width, D.fontH()
    local th = H.titleH()
    local h = th + pad
    if not p.collapsed then
        for _, r in ipairs(rows) do h = h + H.rowH(r) end
    end
    local s = b.colors.surface
    b:fill(0, 0, w, h, { r = s.r, g = s.g, b = s.b, a = H.opacity })
    b:border(0, 0, w, h, "border")
    b:icon(pad, pad - 1, 14, "markerStar", D.EXTRA.gold, "*")
    local tw = b:text(pad + 20, pad - 3, getText("IGUI_MQ_UI_HudTitle"), "text")
    b:text(pad + 28 + tw, pad - 3, getText("IGUI_MQ_UI_Count", tostring(pins), tostring(Q.Contract.LIMIT.MAX_PINS)),
        "textMuted")
    b:arrow(w - pad - 8, pad + math.floor(lh / 2) - 4, not p.collapsed, "textMuted")
    if not p.collapsed then
        local y = th
        local xRight = w - pad - 16   -- room for the hover x
        local countW = H.countW(rows)
        for _, r in ipairs(rows) do
            local top = y
            local nameX = not r.horde and pad + b:chip(pad, y, r.tag, "textMuted") + 6
            if r.horde then
                hordeRowOps(b, r, y, w, pad, lh)
            elseif r.done then
                local pw = b:textRight(xRight, y + 3, getText("IGUI_MQ_UI_PlusPoints", D.num(r.pts)), D.EXTRA.success)
                b:icon(xRight - pw - 16, y + 3, 14, "check", D.EXTRA.success, "v")
                b:fitText(nameX, y + 3, r.name, xRight - pw - 24 - nameX, "textMuted")
            else
                b:fitText(nameX, y + 3, r.name, xRight - nameX, "text")
                local ly = y + D.chipH() + 2
                b:textRight(w - pad, ly, H.countText(r), "textMuted")
                b:bar(pad, ly + math.floor((lh - 4) / 2), w - 2 * pad - countW - 8, 4, r.target > 0 and r.prog / r.target or 0,
                    r.color or "accent")
            end
            y = y + H.rowH(r)
            if not r.horde then p.hits[#p.hits + 1] = { id = r.id, y0 = top - 2, y1 = y - 2, xx = w - pad - 12, ty = top + 3 } end
        end
    end
    p.gripTip = getText("IGUI_MQ_UI_HudResize")
    p.gripTipW = D.textW(p.gripTip) + 12
    p:setHeight(h)
    H.clamp(p)
end

-- ===== panel (derived on first use so the offline harness can load this file) =====
local Panel = nil

local function panelClass()
    if Panel ~= nil then return Panel end
    Panel = ISPanel:derive("MinidoracatQuestHud")
    function Panel:prerender() end
    function Panel:render() MinidoracatQuest.Hud.render(self) end
    function Panel:onMouseDown(x, y) return MinidoracatQuest.Hud.onMouseDown(self, x, y) end
    function Panel:onMouseUp(x, y) return MinidoracatQuest.Hud.onMouseUp(self, x, y, false) end
    function Panel:onMouseUpOutside(x, y) return MinidoracatQuest.Hud.onMouseUp(self, x, y, true) end
    -- while the right edge is dragged the moves resize it; otherwise ISPanel moves the panel
    function Panel:onMouseMove(dx, dy)
        if self.sizing ~= nil then return MinidoracatQuest.Hud.onSizing(self) end
        return ISPanel.onMouseMove(self, dx, dy)
    end
    function Panel:onMouseMoveOutside(dx, dy)
        if self.sizing ~= nil then return MinidoracatQuest.Hud.onSizing(self) end
        return ISPanel.onMouseMoveOutside(self, dx, dy)
    end
    function Panel:onRightMouseDown() return false end
    function Panel:onRightMouseUp() return false end
    function Panel:SaveLayout(name, layout)
        layout.x, layout.y, layout.width = self.x, self.y, self.width
        layout.moved = tostring(self.moved == true)
        layout.collapsed = tostring(self.collapsed == true)
        layout.maxW = self.maxW   -- the dragged cap; nil (automatic) drops the key
    end
    function Panel:RestoreLayout(name, layout)
        self.collapsed = layout.collapsed == "true"
        self.maxW = tonumber(layout.maxW)
        local x, y, w = tonumber(layout.x), tonumber(layout.y), tonumber(layout.width)
        if layout.moved == "true" and x ~= nil and y ~= nil then
            self.moved = true
            self:setX(x)
            self:setY(y)
            -- the width x was saved with (0.4.0 saved none: it was H.width(), what H.build made the panel), so
            -- H.fit keeps a right-half panel's right edge
            if w ~= nil then self:setWidth(w) end
        end
        MinidoracatQuest.Hud.dirty = true
    end
    return Panel
end

local function drawX(p, xx, ty, c)
    if not p.UI.Icons.draw(p, "close", xx, ty + 1, 12, c) then
        p:drawTextCentre("x", xx + 6, ty, c.r, c.g, c.b, 1, UIFont.Small)
    end
end

local function inside(m, x, y) return m ~= nil and x >= m.x0 and x < m.x1 and y >= m.y0 and y < m.y1 end

-- the right edge below the title row, outside the horde row's buttons: a drag sets the cap, a double click clears it
function H.onGrip(p, x, y)
    return not p.collapsed and x >= p.width - H.GRIP and y >= H.titleH()
        and not inside(p.hideHit, x, y) and not inside(p.resultHit, x, y) and not inside(p.mapHit, x, y)
end

-- the handle, only while the mouse is on the edge or drags it (plan hud-width). On the edge a hover text beside the
-- panel, on the side with room: the canvas tips draw inside the panel, which may be narrower than the text
local function drawGrip(p)
    local top = H.titleH()
    local gh = math.min(2 * D.fontH(), p.height - top - H.PAD)
    local c = p.theme.colors.text
    if gh > 0 then p:drawRect(p.width - 5, top + math.floor((p.height - top - gh) / 2), 3, gh, 1, c.r, c.g, c.b) end
    if p.sizing ~= nil or p.gripTip == nil then return end
    local w, th = p.gripTipW, D.fontH()
    local x = p.width + 6
    if p.x + x + w > getCore():getScreenWidth() then x = -w - 6 end
    local y = math.max(0, p:getMouseY() - math.floor(th / 2) - 3)
    p:drawRect(x, y, w, th + 6, 0.95, 0.05, 0.05, 0.05)
    p:drawRectBorder(x, y, w, th + 6, 1, 0.4, 0.4, 0.4)
    p:drawText(p.gripTip, x + 6, y + 3, 1, 1, 1, 1, UIFont.Small)
end

function H.render(p)
    D.renderOps(p)
    if p.collapsed then return end
    local over = p:isMouseOver()
    local mx, my = p:getMouseX(), p:getMouseY()
    local colors = p.theme.colors
    local hx = p.hideHit
    if hx ~= nil then drawX(p, hx.xx, hx.ty, over and inside(hx, mx, my) and colors.errorText or colors.textMuted) end
    if p.sizing ~= nil or over and H.onGrip(p, mx, my) then
        drawGrip(p)   -- a press here resizes: no red x that says it unpins
        return
    end
    if not over then return end
    for _, r in ipairs(p.hits or {}) do
        if my >= r.y0 and my < r.y1 then
            drawX(p, r.xx, r.ty, mx >= r.xx - 4 and colors.errorText or colors.textMuted)
            return
        end
    end
end

function H.onMouseDown(p, x, y)
    if y < H.titleH() and x >= p.width - H.PAD - 20 then
        H.toggleCollapsed(p)
        return true
    end
    if not p.collapsed then
        if inside(p.hideHit, x, y) then
            C.setHordeHidden(p.hideHit.id)
            return true
        end
        if inside(p.resultHit, x, y) then
            Q.HordeResult.open(Q.HordeResult.pending)
            return true
        end
        local m = p.mapHit
        if inside(m, x, y) then
            D.showOnMap(0, m.x, m.y)
            return true
        end
        if H.onGrip(p, x, y) then
            local now = getTimestampMs()
            if p.gripAt ~= nil and now - p.gripAt < H.DOUBLE_MS then
                p.gripAt, p.maxW = nil, nil   -- a double click: the automatic width again
                H.layout(p)
                H.persist()
            else
                p.gripAt, p.sizing = now, { dx = p.width - x }
            end
            return true
        end
        for _, r in ipairs(p.hits or {}) do
            if y >= r.y0 and y < r.y1 and x >= r.xx - 4 then
                C.setPin(r.id, false)
                return true
            end
        end
    end
    p.dragX, p.dragY = p.x, p.y
    ISPanel.onMouseDown(p, x, y)
    return true
end

-- while the right edge is dragged: the cap follows the mouse, a drag past H.width() makes it automatic again; a
-- release the panel missed (the button is up) ends it
function H.onSizing(p)
    if not isMouseButtonDown(0) then return H.endSizing(p) end
    local cap, w = H.width(), math.floor(p:getMouseX() + p.sizing.dx)
    if w >= cap then p.maxW = nil else p.maxW = math.max(math.min(H.minWidth(), cap), w) end
    H.layout(p)
end

function H.endSizing(p)
    p.sizing = nil
    H.persist()
end

function H.onMouseUp(p, x, y, outside)
    if p.sizing ~= nil then
        H.endSizing(p)
        return true
    end
    local moving = p.moving
    if outside then ISPanel.onMouseUpOutside(p, x, y) else ISPanel.onMouseUp(p, x, y) end
    if moving and (p.x ~= p.dragX or p.y ~= p.dragY) then
        p.moved = true
        H.clamp(p)
        H.persist()
    end
    return true
end

function H.build()
    local UI = D.ui(W.CAPS)
    if UI == nil then return nil end
    local cls = panelClass()
    local x, y = H.defaultXY()
    local p = cls:new(x, y, H.width(), 40)
    p:initialise()
    p.UI, p.theme, p.ops, p.n, p.tips, p.hits = UI, D.theme(UI), {}, 0, {}, {}
    p.moveWithMouse = true
    p.background = false
    p:addToUIManager()
    -- a passive overlay under every window, also the ones built before it (inventory, a character window left open):
    -- the engine moves back-most elements to the bottom on every update, after a drag's bringToTop too
    -- (UIManager.java:562-568)
    p:backMost()
    p:setVisible(false)
    H.panel = p
    if ISLayoutManager and ISLayoutManager.RegisterWindow then
        pcall(ISLayoutManager.RegisterWindow, H.LAYOUT_KEY, cls, p)
    end
    H.dirty = true
    return p
end

-- ===== visibility =====
local function uiHidden()
    if ISUIHandler ~= nil and ISUIHandler.allUIVisible == false then return true end
    local ms = MainScreen and MainScreen.instance
    return ms ~= nil and ms.inGame == true and ms:isReallyVisible() == true
end

-- something to show: a pin, a horde players can see (not the one taken off the panel) or results waiting for the
-- player to be safe (same hide rules for all)
function H.wanted()
    if not H.show or C.state == nil or uiHidden() then return false end
    if #C.pins() == 0 and shownHorde(C.state) == nil and Q.HordeResult.pending == nil then return false end
    local p = getSpecificPlayer(0)
    return p ~= nil and not p:isDead()
end

function H.sync()
    local want = H.wanted()
    local p = H.panel
    if want and p == nil then p = H.build() end
    if p == nil then return end
    if want and H.dirty then H.layout(p) end
    want = want and #(p.rows or {}) > 0
    if want ~= (p:isVisible() == true) then p:setVisible(want) end
end

function H.onData()
    H.dirty = true
    H.sync()
end

-- the option changed: the server stops or starts the deltas for the panel
function H.setShown(on)
    H.show = on ~= false
    if C.state ~= nil then C.send("track", { on = H.show }) end
    H.sync()
end

-- the arrow and the MinidoracatQuest_Hud key (Entry.lua): fold to the title row and back (layout.ini right away);
-- the key does nothing while the panel is not shown
function H.toggleCollapsed(p)
    p = p or H.panel
    if p == nil or not p:isVisible() then return false end
    p.collapsed = not p.collapsed
    H.layout(p)
    H.persist()
    return true
end

-- the HudOpacity MOD option (Entry.lua) as an alpha: the next layout repaints the background and turns the shadow on
function H.setOpacity(a)
    if a == H.opacity then return end
    H.opacity = a
    H.dirty = true
    H.sync()
end

-- every 500 ms; a shown horde countdown lays the panel out again only when its text changed (once a second while it runs)
function H.onTick()
    local now = getTimestampMs()
    if H.lastSync ~= nil and now - H.lastSync < H.SYNC_MS then return end
    H.lastSync = now
    local p = H.panel
    if p ~= nil and p.hordeTime ~= nil then
        local r = H.hordeRow(C.state)
        if r == nil or r.time ~= p.hordeTime then H.dirty = true end
    end
    H.sync()
end

function H.onResolutionChange()
    local p = H.panel
    if p == nil then return end
    H.dirty = true   -- the next layout takes the new H.width() (H.fitWidth)
    if not p.moved then
        local x, y = H.defaultXY()
        p:setX(x)
        p:setY(y)
    end
    H.clamp(p)
end

if first then
    for _, ev in ipairs({ "state", "delta", "catalog" }) do
        C.on(ev, "hud", function() MinidoracatQuest.Hud.onData() end)
    end
    C.on("hello", "hud", function()
        if MinidoracatQuest.Hud.show then MinidoracatQuest.Client.send("track", { on = true }) end
    end)
    Events.OnTick.Add(function() MinidoracatQuest.Hud.onTick() end)
    Events.OnResolutionChange.Add(function() MinidoracatQuest.Hud.onResolutionChange() end)
end
