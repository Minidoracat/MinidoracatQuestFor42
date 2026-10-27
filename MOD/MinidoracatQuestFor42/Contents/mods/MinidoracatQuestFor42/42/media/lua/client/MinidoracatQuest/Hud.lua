-- MinidoracatQuest/Hud.lua: the tracker panel (design round 7: a floating panel, only what the player pinned).
--   Up to LIMIT.MAX_PINS pinned quests / achievements with their progress, top left beside the vanilla sidebar,
--   and above them one horde row while a horde is announced, waits for players, runs or rests between waves (not a
--   pin, not counted); a Map button on its second line while the spot matters.
--   Drag to move; the arrow collapses it to the title row (both go to layout.ini); hovering a pin row shows an x
--   that unpins it. Hidden while there is nothing to show, the player is dead, the Esc menu is up or V hid the UI;
--   it stays while the main window is open, so a Track press shows up at once (user 2026-10-24), and windows draw
--   over it (backMost). It never shows itself while the UI is hidden: the vanilla V / Esc toggle restores what it hid.
--   Data: state.pins, state.trk and state.hordes, kept fresh by the server while the panel is on ("track"; Sync.lua).
--   Texts and widths are laid out when the data changes; render only walks the op list (Draw canvas).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"
require "MinidoracatQuest/PageAchievements"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local first = Q.Hud == nil
local H = Q.Hud or {}
Q.Hud = H

H.LAYOUT_KEY = "MinidoracatQuestHud"
H.SYNC_MS = 500
H.PAD = 8
H.show = H.show ~= false     -- MOD option "ShowHud" (Entry.lua)

-- ===== model (harness tests these) =====
-- the horde row: { id = "horde", horde = true, tag, name, time, line, prog?, target?, mapX?, mapY? } or nil.
-- Every countdown says what it counts to (design 1): announced "4:29 to the start", waiting / active "52:10 left",
-- rest "0:24 to the next wave". When N > 1 the name is "Wave W/N - <spot>", the spot without its town (D.hordeName
-- spotOnly; the design mock), so the prefix and the countdown leave room for the spot. Line 2 starts with
-- the coordinates, so a long language cuts the rule, not the spot (design 5.2); active shows cleared / wave size.
-- mapX / mapY: the Map button (announced / waiting / rest, while the vanilla map is allowed)
function H.hordeRow(state, now)
    local hs = type(state) == "table" and type(state.hordes) == "table" and state.hordes or nil
    local h = hs and D.hordeLive(hs.cur)
    if h == nil then return nil end
    now = now or C.serverNow()
    local st = h.state
    local r = { id = "horde", horde = true, tag = getText("IGUI_MQ_Horde_Tag"), name = D.hordeName(h, true), state = st }
    if st == "active" then
        local n = tonumber(h.size) or 0
        r.prog, r.target = math.max(0, n - (tonumber(h.left) or 0)), n
        r.time = getText("IGUI_MQ_UI_Left", D.countdown((tonumber(h.endsAt) or now) - now))
        r.line = getText("IGUI_MQ_Horde_HudCleared", D.num(r.prog), D.num(n))
    elseif st == "waiting" then
        r.time = getText("IGUI_MQ_UI_Left", D.countdown((tonumber(h.expireAt) or now) - now))
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

-- the horde row first, then one row per pin that still names something: { id, tag, name, prog, target, done, pts, color }
function H.rows(state, defs, now)
    local out = {}
    if type(state) ~= "table" then return out end
    out[1] = H.hordeRow(state, now)
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
function H.width() return math.max(260, math.min(360, 20 * D.fontH())) end
function H.titleH() return D.fontH() + 10 end
-- an open row: tag + name, then bar + progress (long DE / FR / RU names keep the full width); a done row: one line
function H.rowH(r) return D.chipH() + (r.done and 6 or (2 + D.fontH() + 6)) end

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
-- the horde row has no x (not a pin) and draws in the horde red; p.hordeTime is what onTick compares.
-- The Map button sits at the right of line 2; its hit box is p.mapHit, not in p.hits (those are unpin targets),
-- and its hover text goes through the canvas tips. In the rest the countdown opens line 2 instead: "Next wave in
-- 0:38" beside "Wave 2/3 cleared" left no room for the spot even in English (quest-hui-en-1027a; ES kept "Oleada 2...")
local function hordeRowOps(b, r, y, w, pad, lh)
    local nameX = pad + b:chip(pad, y, r.tag, D.EXTRA.horde) + 6
    local rest = r.state == "rest"
    local tw = rest and 0 or b:textRight(w - pad, y + 3, r.time, D.EXTRA.horde) + 8
    b:fitText(nameX, y + 3, r.name, w - pad - tw - nameX, "text")
    local ly = y + D.chipH() + 2
    local lx = rest and pad + b:text(pad, ly, r.time, D.EXTRA.horde) + 6 or pad
    local lineW = w - pad - lx
    if r.mapX ~= nil then
        local label, tip = getText("IGUI_MQ_UI_Map"), getText("IGUI_MQ_UI_ShowOnMap")
        local bw, bh = D.textW(label) + 12, lh + 2
        local bx, by = w - pad - bw, ly - 1
        b:border(bx, by, bw, bh, "textMuted")
        b:text(bx + 6, ly, label, "text")
        local tips = b.cv.tips
        tips[#tips + 1] = { x = bx, y = by, w = bw, h = bh, text = tip, tw = D.textW(tip), th = lh }
        b.cv.mapHit = { x0 = bx, y0 = by, x1 = bx + bw, y1 = by + bh, x = r.mapX, y = r.mapY }
        lineW = lineW - bw - 6
    end
    if r.target == nil then return b:fitText(lx, ly, r.line, lineW, "textMuted") end
    local pw = b:textRight(w - pad, ly, r.line, "textMuted")
    b:bar(pad, ly + math.floor((lh - 4) / 2), w - 2 * pad - pw - 8, 4, r.target > 0 and r.prog / r.target or 0, D.EXTRA.horde)
end

function H.layout(p)
    H.dirty = false
    local rows = H.rows(C.state, C.defs())
    local pins = rows[1] ~= nil and rows[1].horde and #rows - 1 or #rows
    p.rows, p.hits, p.mapHit, p.hordeTime = rows, {}, nil, rows[1] ~= nil and rows[1].horde and rows[1].time or nil
    local b = D.begin(p)
    local pad, w, lh = H.PAD, p.width, D.fontH()
    local th = H.titleH()
    local h = th + pad
    if not p.collapsed then
        for _, r in ipairs(rows) do h = h + H.rowH(r) end
    end
    b:fill(0, 0, w, h, { r = 0, g = 0, b = 0, a = 0.78 })
    b:border(0, 0, w, h, "border")
    b:icon(pad, pad - 1, 14, "markerStar", D.EXTRA.gold, "*")
    local tw = b:text(pad + 20, pad - 3, getText("IGUI_MQ_UI_HudTitle"), "text")
    b:text(pad + 28 + tw, pad - 3, getText("IGUI_MQ_UI_Count", tostring(pins), tostring(Q.Contract.LIMIT.MAX_PINS)),
        "textMuted")
    b:arrow(w - pad - 8, pad + math.floor(lh / 2) - 4, not p.collapsed, "textMuted")
    if not p.collapsed then
        local y = th
        local xRight = w - pad - 16   -- room for the hover x
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
                local pw = b:textRight(w - pad, ly,
                    getText("IGUI_MQ_UI_Progress", D.num(math.min(r.prog, r.target)), D.num(r.target)), "textMuted")
                b:bar(pad, ly + math.floor((lh - 4) / 2), w - 2 * pad - pw - 8, 4, r.target > 0 and r.prog / r.target or 0,
                    r.color or "accent")
            end
            y = y + H.rowH(r)
            if not r.horde then p.hits[#p.hits + 1] = { id = r.id, y0 = top - 2, y1 = y - 2, xx = w - pad - 12, ty = top + 3 } end
        end
    end
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
    function Panel:onRightMouseDown() return false end
    function Panel:onRightMouseUp() return false end
    function Panel:SaveLayout(name, layout)
        layout.x, layout.y = self.x, self.y
        layout.moved = tostring(self.moved == true)
        layout.collapsed = tostring(self.collapsed == true)
    end
    function Panel:RestoreLayout(name, layout)
        self.collapsed = layout.collapsed == "true"
        local x, y = tonumber(layout.x), tonumber(layout.y)
        if layout.moved == "true" and x ~= nil and y ~= nil then
            self.moved = true
            self:setX(x)
            self:setY(y)
        end
        MinidoracatQuest.Hud.dirty = true
    end
    return Panel
end

function H.render(p)
    D.renderOps(p)
    if p.collapsed or not p:isMouseOver() then return end
    local mx, my = p:getMouseX(), p:getMouseY()
    for _, r in ipairs(p.hits or {}) do
        if my >= r.y0 and my < r.y1 then
            local c = mx >= r.xx - 4 and p.theme.colors.errorText or p.theme.colors.textMuted
            if not p.UI.Icons.draw(p, "close", r.xx, r.ty + 1, 12, c) then
                p:drawTextCentre("x", r.xx + 6, r.ty, c.r, c.g, c.b, 1, UIFont.Small)
            end
            return
        end
    end
end

function H.onMouseDown(p, x, y)
    if y < H.titleH() and x >= p.width - H.PAD - 20 then
        p.collapsed = not p.collapsed
        H.layout(p)
        H.persist()
        return true
    end
    local m = p.mapHit
    if m ~= nil and not p.collapsed and x >= m.x0 and x < m.x1 and y >= m.y0 and y < m.y1 then
        D.showOnMap(0, m.x, m.y)
        return true
    end
    if not p.collapsed then
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

function H.onMouseUp(p, x, y, outside)
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

-- something to show: a pin, or a horde players can see (same hide rules for both)
function H.wanted()
    if not H.show or C.state == nil or uiHidden() then return false end
    local hs = C.state.hordes
    if #C.pins() == 0 and D.hordeLive(type(hs) == "table" and hs.cur or nil) == nil then return false end
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
