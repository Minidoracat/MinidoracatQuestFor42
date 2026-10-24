-- MinidoracatQuest/Entry.lua: ways into the window and notifications (ARCHITECTURE 7, spec 17).
--   Family Dock entry (id quest, order 70, badge = state.unseen, bind MinidoracatQuest_Toggle), the hotkey
--   (registered unbound: the family key table has no free single key), player MOD options (show the Dock entry,
--   show server-wide unlock toasts) and the toast texts for every server toast kind.
--   Dock callbacks run every frame inside pcall: they only read cached values (no tables, no strings).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.Entry == nil
local E = Q.Entry or {}
Q.Entry = E

E.BIND = "MinidoracatQuest_Toggle"
E.DOCK_ICON = "media/ui/MinidoracatQuest/dock_trophy.png"
E.badge = E.badge or 0
E.showDock = E.showDock ~= false
E.showBroadcast = E.showBroadcast ~= false

-- ===== MOD options (PZAPI.ModOptions; tick boxes read with explicit nil/type tests) =====
function E.readOptions()
    local o = E.options
    if o == nil then return end
    local d, b = o:getOption("ShowDock"), o:getOption("ShowBroadcast")
    E.showDock = d == nil or d:getValue() ~= false
    E.showBroadcast = b == nil or b:getValue() ~= false
end

function E.applyOptions()
    E.readOptions()
    local UI = D.ui({ "dock" })
    if UI ~= nil and UI.Dock ~= nil then UI.Dock.refresh() end
end

if first and PZAPI and PZAPI.ModOptions then
    local o = PZAPI.ModOptions:create("MinidoracatQuestFor42", "UI_MinidoracatQuest_Options")
    o:addTickBox("ShowDock", "UI_MinidoracatQuest_ShowDock", true, "UI_MinidoracatQuest_ShowDock_tooltip")
    o:addTickBox("ShowBroadcast", "UI_MinidoracatQuest_ShowBroadcast", true, "UI_MinidoracatQuest_ShowBroadcast_tooltip")
    o.apply = function() MinidoracatQuest.Entry.applyOptions() end
    E.options = o
    -- framework rev 23 backup (UI repo ARCHITECTURE 3.23): at file load, before the vanilla load in
    -- MainOptions:create; probed by flag, MIN_REV stays 22
    local UI = D.ui({ "modOptionsBackup" })
    local restored = UI ~= nil and UI.ModOptionsBackup ~= nil and UI.ModOptionsBackup.protect(o)
    if type(restored) == "number" and restored > 0 then
        C.log("restored " .. restored .. " settings from the backup (ModOptions.ini was wiped)")
    end
end

-- ===== Dock (UI repo ARCHITECTURE 3.16) =====
E.dockSpec = {
    id = "quest",
    order = 70,
    icon = E.DOCK_ICON,          -- colored trophy (Icons slice); unreadable -> iconKey (framework rev 21)
    iconKey = "markerCrown",
    bind = E.BIND,
    label = function() return getText("IGUI_MQ_Name") end,
    onClick = function() MinidoracatQuest.Window.toggle() end,
    getBadge = function() return MinidoracatQuest.Entry.badge end,
    getStatus = function() return MinidoracatQuest.Entry.status end,
    isAvailable = function() return MinidoracatQuest.Entry.showDock end,
}

function E.registerDock()
    local UI = D.ui({ "dock" })
    E.docked = UI ~= nil and UI.Dock ~= nil and UI.Dock.register(E.dockSpec) == true
    return E.docked
end

-- badge and status text are composed when state changes, not in the dock callbacks
function E.onState()
    local n = C.state and math.floor(tonumber(C.state.unseen) or 0) or 0
    if n == E.badge then return end
    E.badge = n
    E.status = n > 0 and getText("IGUI_MQ_UI_DockUnseen", tostring(n)) or nil
end

-- ===== hotkey =====
function E.initBinds()
    if keyBinding == nil then return end
    table.insert(keyBinding, { value = "[MinidoracatQuest]" })
    table.insert(keyBinding, { value = E.BIND, key = (Keyboard and Keyboard.KEY_NONE) or 0 })
end

function E.onKeyPressed(key)
    if key == nil or key == 0 then return end
    if key == getCore():getKey(E.BIND) then MinidoracatQuest.Window.toggle() end
end

-- ===== toasts (spec 17) =====
local function pts(n) return getText("IGUI_MQ_UI_PlusPoints", D.num(n)) end

-- returns title, message, border color; nil = do not show
function E.toastText(t)
    local k = t.kind
    local defs = C.defs()
    if k == "achv" then
        local a = defs.achById[t.id]
        return getText("IGUI_MQ_UI_ToastAchv", D.achName(a or { id = tostring(t.id), kind = "builtin" }), D.tierName(t.tier)),
            getText("IGUI_MQ_UI_ToastDescPts", a and D.achDesc(a, t.tier) or "", pts(t.pts or 0)), D.EXTRA.gold
    elseif k == "achvMany" then
        local names = {}
        for i, id in ipairs(type(t.ids) == "table" and t.ids or {}) do
            if i > 3 then break end
            names[#names + 1] = D.achName(defs.achById[id] or { id = tostring(id), kind = "builtin" })
        end
        return getText("IGUI_MQ_UI_ToastAchvMany", tostring(t.n or #names)),
            getText("IGUI_MQ_UI_ToastAchvManyBody", table.concat(names, getText("IGUI_MQ_UI_ListSep"))), D.EXTRA.gold
    elseif k == "quest" or k == "week" then
        -- the toast carries tid and target: with the window closed the cached list is the login snapshot
        return getText(k == "quest" and "IGUI_MQ_UI_ToastQuest" or "IGUI_MQ_UI_ToastWeek"),
            getText("IGUI_MQ_UI_ToastDescPts", D.questName({ tid = t.tid, target = t.target }), pts(t.pts or 0)),
            D.EXTRA.success
    elseif k == "goal" then
        return getText("IGUI_MQ_UI_ToastGoal"), getText("IGUI_MQ_UI_ToastDescPts", D.statName(t.stat), pts(t.pts or 0)),
            D.EXTRA.gold
    elseif k == "streak" then
        return getText("IGUI_MQ_UI_ToastStreak", tostring(t.days or 0)), pts(t.pts or 0), D.EXTRA.success
    elseif k == "newbie" then
        return getText("IGUI_MQ_UI_ToastNewbie"), pts(t.pts or 0), D.EXTRA.success
    elseif k == "exchange" then
        local coins = D.num(t.coins or 0)
        if t.state == "paid" then return getText("IGUI_MQ_UI_ExPaid", coins), "", D.EXTRA.success end
        if t.state == "queued" then return getText("IGUI_MQ_UI_ExQueued"), getText("IGUI_MQ_UI_ExQueuedBody"), nil end
        return getText("IGUI_MQ_UI_ExRefused"), getText("IGUI_MQ_UI_ExRefusedBody", D.num(t.amount or t.coins or 0)), nil
    elseif k == "season" then
        return getText("IGUI_MQ_UI_ToastSeason", tostring(t.no or 0)),
            getText("IGUI_MQ_UI_ToastSeasonBody", tostring(t.rank or "-"), pts(t.pts or 0)), D.EXTRA.gold
    elseif k == "broadcast" then
        if not E.showBroadcast then return nil end
        local a = defs.achById[t.id] or { id = tostring(t.id), kind = "builtin", tiers = {} }
        -- t.a: the real name of an anonymous achiever, in the copy sent to admins only
        local who = t.who or (t.a ~= nil and getText("IGUI_MQ_UI_AnonReal", t.a)) or getText("IGUI_MQ_UI_Anonymous")
        -- who + tier in the title, the achievement name opens the body: a long name plus a long achievement
        -- name overflowed the two title lines in FR / DE (quest-ui-fr-1023g)
        local title = getText("IGUI_MQ_UI_ToastBroadcastHead", who, D.tierName(t.tier))
        local body = getText("IGUI_MQ_UI_ToastDescPts", D.achName(a), a.tiers and D.achDesc(a, t.tier) or "")
        if t.titleId ~= nil then body = getText("IGUI_MQ_UI_ToastBroadcastTitle", body, D.titleText(t.titleId)) end
        return title, body, D.EXTRA.info
    end
    return nil
end

function E.onToast(t)
    local title, message, border = E.toastText(t)
    if title == nil then return end
    D.toast(title, message or "", border)
end

if first then
    C.on("state", "entry", function() MinidoracatQuest.Entry.onState() end)
    C.on("delta", "entry", function() MinidoracatQuest.Entry.onState() end)
    C.on("toast", "entry", function(t) MinidoracatQuest.Entry.onToast(t) end)
    Events.OnGameBoot.Add(function() MinidoracatQuest.Entry.initBinds() end)
    Events.OnKeyPressed.Add(function(key) MinidoracatQuest.Entry.onKeyPressed(key) end)
    Events.OnGameStart.Add(function()
        MinidoracatQuest.Entry.readOptions()
        MinidoracatQuest.Entry.registerDock()
    end)
end
