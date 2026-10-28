-- MinidoracatQuest/Entry.lua: ways into the window and notifications (ARCHITECTURE 7, spec 17).
--   Family Dock entry (id quest, order 70, badge = state.unseen, bind MinidoracatQuest_Toggle), the hotkey
--   (registered unbound: the family key table has no free single key), player MOD options (show the Dock entry,
--   server-wide unlock toasts, the tracker panel, other players' titles over heads and in chat) and the toast texts
--   for every server toast kind.
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
E.showHud = E.showHud ~= false
E.showHeadTitles = E.showHeadTitles ~= false
E.showChatTitles = E.showChatTitles ~= false

-- ===== MOD options (PZAPI.ModOptions; tick boxes read with explicit nil/type tests) =====
local function tick(o, id)
    local t = o:getOption(id)
    return t == nil or t:getValue() ~= false
end

function E.readOptions()
    local o = E.options
    if o == nil then return end
    E.showDock, E.showBroadcast = tick(o, "ShowDock"), tick(o, "ShowBroadcast")
    E.showHud, E.showHeadTitles, E.showChatTitles = tick(o, "ShowHud"), tick(o, "ShowHeadTitles"), tick(o, "ShowChatTitles")
end

function E.applyOptions()
    local hud = E.showHud
    E.readOptions()
    local UI = D.ui({ "dock" })
    if UI ~= nil and UI.Dock ~= nil then UI.Dock.refresh() end
    if Q.Hud ~= nil and hud ~= E.showHud then Q.Hud.setShown(E.showHud) end
end

if first and PZAPI and PZAPI.ModOptions then
    local o = PZAPI.ModOptions:create("MinidoracatQuestFor42", "UI_MinidoracatQuest_Options")
    o:addTickBox("ShowDock", "UI_MinidoracatQuest_ShowDock", true, "UI_MinidoracatQuest_ShowDock_tooltip")
    o:addTickBox("ShowBroadcast", "UI_MinidoracatQuest_ShowBroadcast", true, "UI_MinidoracatQuest_ShowBroadcast_tooltip")
    o:addTickBox("ShowHud", "UI_MinidoracatQuest_ShowHud", true, "UI_MinidoracatQuest_ShowHud_tooltip")
    o:addTickBox("ShowHeadTitles", "UI_MinidoracatQuest_ShowHeadTitles", true, "UI_MinidoracatQuest_ShowHeadTitles_tooltip")
    o:addTickBox("ShowChatTitles", "UI_MinidoracatQuest_ShowChatTitles", true, "UI_MinidoracatQuest_ShowChatTitles_tooltip")
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
    elseif k == "horde" then
        return E.hordeToast(t)
    elseif k == "hordePaid" then
        return getText("IGUI_MQ_Horde_Paid", D.num(t.pts or 0)),
            D.hordeCapped(getText("IGUI_MQ_Horde_PaidBody", D.num(t.kills or 0)), t.capped), D.EXTRA.success
    end
    return nil
end

-- whole minutes until ms, at least 1: the warnings say "starts in N min", not a clock time that players read as the
-- in-game time (design r12)
local function minsTo(ms)
    return math.max(1, math.floor(((tonumber(ms) or 0) - C.serverNow()) / 60000 + 0.5))
end

-- server-wide horde toasts (t.ev) and "remind", the personal one to players near the spot just before the start;
-- the warning names the kinds that may appear and the number of waves, never how many zombies. Every wave has its
-- spawn toast ("Wave W/N - " in front when N > 1) and every cleared one but the last its rest toast; win and fail
-- say what the horde paid (fail: the cleared waves) and when the cap scaled the shares down
function E.hordeToast(t)
    local place, ev = D.hordePlace(t), t.ev
    local waves = tostring(t.waves or 1)
    if ev == "soon" then
        return getText("IGUI_MQ_Horde_Title_soon", place),
            getText("IGUI_MQ_Horde_SoonBody", tostring(minsTo(t.startMs)), D.hordeKinds(t.kinds), waves), D.EXTRA.hordeSoon
    elseif ev == "remind" then
        return getText("IGUI_MQ_Horde_Title_remind", tostring(minsTo(t.startMs)), place), getText("IGUI_MQ_Horde_Remind"),
            D.EXTRA.hordeSoon
    elseif ev == "open" then
        return getText("IGUI_MQ_Horde_Title_wait", place), getText("IGUI_MQ_Horde_OpenBody", D.hordeKinds(t.kinds), waves),
            D.EXTRA.hordeSoon
    elseif ev == "spawn" then
        return getText("IGUI_MQ_Horde_Title_spawn", D.hordeName(t)),
            getText("IGUI_MQ_Horde_SpawnBody", tostring(t.limitMin or 0), D.num(t.size or 0)), D.EXTRA.horde
    elseif ev == "rest" then
        local w = tonumber(t.wave) or 1
        return getText("IGUI_MQ_Horde_Title_rest", tostring(w), waves, place),
            getText("IGUI_MQ_Horde_RestToast", tostring(w + 1), D.countdown((tonumber(t.nextAt) or 0) - C.serverNow())),
            D.EXTRA.hordeSoon
    elseif ev == "win" then
        return getText("IGUI_MQ_Horde_Title_win", place), D.hordeCapped(getText("IGUI_MQ_Horde_WinBody", waves,
            D.num(t.spawned or 0), D.num(t.n or 0), D.num(t.pool or 0)), t.capped), D.EXTRA.success
    elseif ev == "fail" then
        return getText("IGUI_MQ_Horde_Title_fail", place),
            D.hordeFailText(t.why, t.wave, t.waves, t.cleared, t.pool, t.capped), nil
    elseif ev == "cancel" then
        return getText("IGUI_MQ_Horde_Title_cancel", place), getText("IGUI_MQ_Horde_CancelBody"), nil
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
        if MinidoracatQuest.Hud ~= nil then MinidoracatQuest.Hud.show = MinidoracatQuest.Entry.showHud end
    end)
end

-- Update note (framework rev 24, WhatsNew): the first game after a player's update shows this
-- version's note at the top right. release_train.py ready reads this block by regex: literal
-- strings, one field per line; since moves to a version only when it ships a new note
-- (family conventions.md, in-game update notes).
do
    local ui = MinidoracatUI and MinidoracatUI.v1
    if ui ~= nil and ui.API_MAJOR == 1 and type(ui.API_REVISION) == "number" and ui.API_REVISION >= 24
            and ui.CAPABILITIES ~= nil and ui.CAPABILITIES.whatsNew == true and ui.WhatsNew ~= nil then
        ui.WhatsNew.register({
            modId = "MinidoracatQuestFor42",
            since = "0.3.0",
            name = "IGUI_MQ_Name",
            text = "IGUI_MQ_WhatsNew",
        })
    end
end
