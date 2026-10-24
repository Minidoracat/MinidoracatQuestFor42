-- MinidoracatQuest/Hud.lua: the tracker panel (design round 7: a floating panel, only what the player pinned).
--   Up to LIMIT.MAX_PINS pinned quests / achievements with their progress, top left beside the vanilla sidebar.
--   Drag to move; the arrow collapses it to the title row (both go to layout.ini); hovering a row shows an x that
--   unpins it. Hidden while nothing is pinned, the player is dead, the Esc menu is up or V hid the UI; it stays while
--   the main window is open, so a Track press shows up at once (user 2026-10-24), and windows draw over it (backMost).
--   It never shows itself while the UI is hidden: the vanilla V / Esc toggle restores what it hid.
--   Data: state.pins and state.trk, kept fresh by the server while the panel is on ("track"; Sync.lua).
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
-- one row per pin that still names something: { id, tag, name, prog, target, done, pts, color }
function H.rows(state, defs)
    local out = {}
    if type(state) ~= "table" then return out end
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

-- ===== layout: background, title row (star, name, count, arrow), one row per pin =====
function H.layout(p)
    H.dirty = false
    local rows = H.rows(C.state, C.defs())
    p.rows, p.hits = rows, {}
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
    b:text(pad + 28 + tw, pad - 3, getText("IGUI_MQ_UI_Count", tostring(#rows), tostring(Q.Contract.LIMIT.MAX_PINS)),
        "textMuted")
    b:arrow(w - pad - 8, pad + math.floor(lh / 2) - 4, not p.collapsed, "textMuted")
    if not p.collapsed then
        local y = th
        local xRight = w - pad - 16   -- room for the hover x
        for _, r in ipairs(rows) do
            local top = y
            local nameX = pad + b:chip(pad, y, r.tag, "textMuted") + 6
            if r.done then
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
            p.hits[#p.hits + 1] = { id = r.id, y0 = top - 2, y1 = y - 2, xx = w - pad - 12, ty = top + 3 }
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

function H.wanted()
    if not H.show or C.state == nil or #C.pins() == 0 or uiHidden() then return false end
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

function H.onTick()
    local now = getTimestampMs()
    if H.lastSync ~= nil and now - H.lastSync < H.SYNC_MS then return end
    H.lastSync = now
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
