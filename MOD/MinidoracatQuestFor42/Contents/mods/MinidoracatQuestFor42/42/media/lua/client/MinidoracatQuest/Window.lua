-- MinidoracatQuest/Window.lua: the main window (ARCHITECTURE 7): left NavList (daily, weekly, achievements,
--   boards, my records; separate group: settings, admin when state.admin), right content, opaque window.
--   Pages register a spec { id, label (translation key), icon, group = "main" | "tail", admin?, build(page),
--   layout(page), onShow(page)?, onHide(page)?, ticking? }. Layout runs only when data changed, the window was
--   resized, or (ticking pages) every 30 s for countdown text - never per frame.
--   Admin pages hook in with MinidoracatQuest.ClientUI.registerAdminPage(spec): spec.show(host), spec.hide(),
--   spec.resize(w, h), spec.onReply(payload); host = { UI, theme, parent, x, y, width, height, D }.
--   Opening sends watch {on=true}, closing {on=false}; showing daily or achievements sends seen.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.Window == nil
local W = Q.Window or {}
Q.Window = W
Q.ClientUI = Q.ClientUI or {}
local CUI = Q.ClientUI

W.CAPS = { "window", "controls", "scrollPanel", "navList" }
W.TICK_MS = 30000
W.specs = W.specs or {}
W.current = W.current or "daily"

-- ===== registry =====
function W.register(spec)
    for i, s in ipairs(W.specs) do
        if s.id == spec.id then
            W.specs[i] = spec
            return
        end
    end
    W.specs[#W.specs + 1] = spec
end

function W.spec(id)
    for _, s in ipairs(W.specs) do
        if s.id == id then return s end
    end
    return nil
end

-- admin pages (AdminUI slice); several may register, each becomes one nav row in the second group
function CUI.registerAdminPage(adm)
    if type(adm) ~= "table" then return false end
    local id = adm.id or "admin"
    W.register({
        id = id, admin = true, group = "tail", label = adm.label or "IGUI_MQ_UI_NavAdmin", icon = adm.icon or "shieldCheck",
        impl = adm,
        build = function() end,
        layout = function() end,
        onShow = function(page)
            if adm.show then adm.show({ UI = page.UI, theme = page.theme, parent = page.parent, x = 0, y = 0,
                width = page.width, height = page.height, D = D }) end
        end,
        onHide = function() if adm.hide then adm.hide() end end,
        onResize = function(page) if adm.resize then adm.resize(page.width, page.height) end end,
    })
    W.navDirty = true
    return true
end

local function adminReply(p)
    for _, s in ipairs(W.specs) do
        if s.admin and s.impl and s.impl.onReply then
            local ok, err = pcall(s.impl.onReply, p)
            if not ok then C.log("admin onReply: " .. tostring(err)) end
        end
    end
end

-- ===== nav =====
local function isAdmin() return C.state ~= nil and C.state.admin == true end

function W.navWidth()
    local w = 0
    for _, s in ipairs(W.specs) do w = math.max(w, D.textW(getText(s.label))) end
    return math.max(120, math.min(240, w + 8 + 16 + 6 + 16))
end

-- ===== window =====
function W.visible() return W.win ~= nil and W.win:isVisible() end

local function insertByOrder(list, item, order)
    local i = #list + 1
    while i > 1 and list[i - 1].order > order do
        list[i] = list[i - 1]
        i = i - 1
    end
    list[i] = item
end

-- load order is alphabetical (Admin*.lua first), so rows are placed by spec.order, not registration order
function W.navGroups()
    local main, tail = {}, {}
    for _, s in ipairs(W.specs) do
        if not s.admin or isAdmin() then
            local item = { id = s.id, label = getText(s.label), icon = s.icon, order = s.order or 100 }
            insertByOrder(s.group == "tail" and tail or main, item, item.order)
        end
    end
    return { { items = main }, { items = tail } }
end

-- default size: content half the screen width (640..1000 px) beside the nav and 82 % of the screen height
-- (460..1000 px). The content width does not depend on the nav labels (FR / DE nav is ~240 px: admin tables
-- and the points card were squeezed at a fixed 760 px window, quest-ui-fr-1023g). A size the player dragged
-- to is kept by ISLayoutManager until "Reset size".
function W.defaultSize()
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local content = math.max(640, math.min(1000, math.floor(sw * 0.5)))
    local h = math.max(460, math.min(1000, math.floor(sh * 0.82)))
    return math.min(content + W.navWidth(), sw - 40), math.min(h, sh - 40)
end

-- the "Reset size" chip sits left of the close button and shows only while the size is not the default
function W.placeReset()
    local b, win = W.resetBtn, W.win
    if b == nil or win == nil then return end
    local dw, dh = W.defaultSize()
    b:setVisible(win.width ~= dw or win.height ~= dh)
    local th = win:titleBarHeight()
    b:setX(win.width - th - 6 - b.width)
    b:setY(math.floor((th - b.height) / 2))
end

function W.resetSize()
    local win = W.win
    if win == nil then return end
    local w, h = W.defaultSize()
    local core = getCore()
    win:setWidth(w)
    win:setHeight(h)
    win:setX(math.floor((core:getScreenWidth() - w) / 2))
    win:setY(math.floor((core:getScreenHeight() - h) / 2))
    W.layout()
end

function W.build(UI)
    local theme = D.theme(UI)
    local core = getCore()
    local sw, sh = core:getScreenWidth(), core:getScreenHeight()
    local w, h = W.defaultSize()
    local win = UI.Window.new({ x = math.floor((sw - w) / 2), y = math.floor((sh - h) / 2), width = w, height = h,
        title = getText("IGUI_MQ_Name"), icon = "markerCrown", theme = theme, resizable = true,
        minWidth = math.min(640, w), minHeight = math.min(460, h), opaque = D.has(UI, "opaqueWindow") or nil,
        onResize = function() MinidoracatQuest.Window.layout() end,
        onClose = function() MinidoracatQuest.Window.onClosed() end })
    win.onEscape = function() win:close() end
    W.win, W.UI, W.theme, W.pages = win, UI, theme, {}
    W.navW = W.navWidth()
    local top = win:contentTop()
    W.nav = UI.NavList.new({ x = 0, y = top + 6, width = W.navW, groups = W.navGroups(), selected = W.current,
        theme = theme, target = W, onSelect = function(_, id) MinidoracatQuest.Window.select(id) end })
    win:addChild(W.nav)
    W.navAdmin = isAdmin()
    W.divider = ISPanel:new(W.navW, top, 1, h - top)
    W.divider:initialise()
    W.divider.backgroundColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    W.divider.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    win:addChild(W.divider)
    W.resetBtn = UI.Button.new({ x = 0, y = 0, height = win:titleBarHeight() - 8, title = getText("IGUI_MQ_UI_ResetSize"),
        style = "chip", theme = theme, target = W, onClick = function() MinidoracatQuest.Window.resetSize() end })
    win:addChild(W.resetBtn)
    win:addToUIManager()
    if ISLayoutManager and ISLayoutManager.RegisterWindow then
        pcall(ISLayoutManager.RegisterWindow, "MinidoracatQuestWindow", UI.Window, win)
    end
    W.placeReset()
end

local function contentRect()
    local win = W.win
    local top = win:contentTop()
    return W.navW + 1, top, win.width - W.navW - 1, win.height - top
end

local function newPage(spec)
    local x, y, w, h = contentRect()
    local panel = ISPanel:new(x, y, w, h)
    panel:initialise()
    panel.background = false
    panel.border = false
    W.win:addChild(panel)
    local page = { id = spec.id, spec = spec, UI = W.UI, theme = W.theme, win = W.win, parent = panel,
        width = w, height = h, dirty = true }
    local ok, err = pcall(spec.build, page)
    if not ok then C.log("page build " .. spec.id .. ": " .. tostring(err)) end
    W.pages[spec.id] = page
    return page
end

function W.page(id) return W.pages ~= nil and W.pages[id] or nil end

local function call(page, fname)
    local fn = page.spec[fname]
    if fn == nil then return end
    local ok, err = pcall(fn, page)
    if not ok then C.log("page " .. page.id .. "." .. fname .. ": " .. tostring(err)) end
end

function W.layoutPage(page)
    page.dirty, page.laidAt = false, getTimestampMs()
    call(page, "layout")
end

function W.select(id)
    local spec = W.spec(id) or W.specs[1]
    if spec == nil or W.win == nil then return end
    if spec.admin and not isAdmin() then spec = W.spec("daily") or W.specs[1] end
    local old = W.pages[W.current]
    if old ~= nil and old.id ~= spec.id then
        if W.UI.Dropdown and W.UI.Dropdown.close then pcall(W.UI.Dropdown.close, old.parent) end
        old.parent:setVisible(false)
        call(old, "onHide")
    end
    W.current = spec.id
    if W.nav:getSelected() ~= spec.id then W.nav:setSelected(spec.id, true) end
    local page = W.pages[spec.id] or newPage(spec)
    page.parent:setVisible(true)
    W.layoutPage(page)
    call(page, "onShow")
    W.maybeSeen()
end

W.go = W.select

function W.open(id)
    local UI = D.ui(W.CAPS)
    if UI == nil then
        D.toast(getText("IGUI_MQ_UI_NeedFramework"), "")
        return false
    end
    if W.win == nil or W.UI ~= UI then W.build(UI) end
    W.win:setVisible(true)
    W.win:bringToTop()
    C.send("watch", { on = true })
    if C.state == nil and not C.helloWaiting then C.hello() end
    W.syncNav()
    W.placeReset()   -- the default follows the screen size and the nav width (admin entry)
    W.select(id or W.current)
    return true
end

function W.close()
    if W.visible() then W.win:close() end
end

function W.toggle()
    if W.visible() then W.close() else W.open() end
end

function W.onClosed()
    C.send("watch", { on = false })
    local page = W.pages and W.pages[W.current]
    if page ~= nil then
        if W.UI.Dropdown and W.UI.Dropdown.close then pcall(W.UI.Dropdown.close, W.win) end
        call(page, "onHide")
    end
end

-- window resized: every built page gets the new size; the visible one relayouts on the next tick
function W.layout()
    if W.win == nil then return end
    local x, y, w, h = contentRect()
    W.divider:setHeight(h)
    for _, page in pairs(W.pages) do
        page.parent:setX(x)
        page.parent:setY(y)
        page.parent:setWidth(w)
        page.parent:setHeight(h)
        page.width, page.height, page.dirty = w, h, true
        D.resizePage(page)
        call(page, "onResize")
    end
    W.placeReset()
end

function W.syncNav()
    if W.nav == nil then return end
    if W.navDirty or W.navAdmin ~= isAdmin() then
        W.navDirty, W.navAdmin = false, isAdmin()
        W.navW = W.navWidth()
        W.nav:setWidth(W.navW)
        W.divider:setX(W.navW)
        W.nav:setGroups(W.navGroups())
        W.nav:setSelected(W.current, true)
        W.layout()
        local spec = W.spec(W.current)
        if spec ~= nil and spec.admin and not isAdmin() then W.select("daily") end
    end
end

-- seen: opening daily or achievements clears the dock badge (one request in flight)
function W.maybeSeen()
    if not W.visible() or (W.current ~= "daily" and W.current ~= "achievements") then return end
    local s = C.state
    if s == nil or (tonumber(s.unseen) or 0) <= 0 or C.isPending(W.seenRid) then return end
    W.seenRid = C.send("seen", {}, function() end)
end

function W.onData()
    if W.win == nil then return end
    W.syncNav()
    local page = W.pages[W.current]
    if page ~= nil then page.dirty = true end
    W.maybeSeen()
end

function W.onTick()
    if not W.visible() then return end
    local page = W.pages[W.current]
    if page == nil then return end
    if not page.dirty and page.spec.ticking and getTimestampMs() - (page.laidAt or 0) >= W.TICK_MS then page.dirty = true end
    if page.dirty then W.layoutPage(page) end
end

if first then
    for _, ev in ipairs({ "state", "delta", "catalog", "records", "board" }) do
        C.on(ev, "window", function() MinidoracatQuest.Window.onData() end)
    end
    C.on("admin", "window", function(p) adminReply(p) end)
    C.on("hello", "window", function()
        if MinidoracatQuest.Window.visible() then MinidoracatQuest.Client.send("watch", { on = true }) end
    end)
    Events.OnTick.Add(function() MinidoracatQuest.Window.onTick() end)
end
