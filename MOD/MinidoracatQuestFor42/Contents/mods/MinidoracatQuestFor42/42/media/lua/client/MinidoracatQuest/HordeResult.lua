-- MinidoracatQuest/HordeResult.lua: a horde's results window (plan-horde-result 1029, item 2; data ARCHITECTURE 7).
--   receive(s): the server pushes the results at the end to the players at the spot (s.push); they wait (pending)
--   until the player is safe: no live zombie within SAFE_R tiles at SAFE_S checks in a row, one a second. A player
--   who dies or waits KEEP_MS drops them (the Hordes page still has them). Meanwhile the tracker panel says so and has
--   a Results button (Hud.resultRow; it opens at once). The Hordes page's View results asks for one (no push): it
--   opens at once.
--   Shown, a framework Window takes the focus (Focus.onFocus) and a gamepad (Focus.takeJoypad): a pushed one that is
--   safe therefore waits while the Quest window or another framework window holds the keys (review 1029 r1, C1), and
--   a gamepad player gets one toast instead (the character would stop answering the stick). One opened by the player
--   (Results, View results) is the framework's: it takes the gamepad, B closes it.
--   The window is a framework Window like ExchangeDialog (not a Dialog: that one blocks the whole screen), one at a
--   time. Esc (once the window has the keys), B and Close close it; a held Esc is eaten with its release, so the
--   release does not reach the game's pause menu (C2). Result and place, end time / waves / minutes, joined / kills /
--   points paid, the cap note, the MVP (a tag, not only a color), the deaths (DEATHS names, then +N), then every
--   player by kills in a scrolling list (rank, player, kills, points; my row framed and named "(you)", the dead
--   marked in words). The
--   window stays on screen: on a short screen the list shows fewer rows (MIN_ROWS at least). Without the framework
--   (or its window, controls, scroll panel): one toast.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.HordeResult == nil
local R = Q.HordeResult or {}
Q.HordeResult = R

R.SAFE_R, R.SAFE_S, R.KEEP_MS = 20, 3, 600000
R.ROWS, R.MIN_ROWS = 10, 3   -- the list shows ROWS rows, then scrolls (fewer on a short screen, MIN_ROWS at least)
R.DEATHS = 10                -- death names listed; the rest is "+N"
R.calm = R.calm or 0
local PAD = 14

local function changed() if Q.Hud ~= nil then Q.Hud.onData() end end

function R.receive(s)
    if not s.push then return R.open(s) end
    local now = getTimestampMs()
    R.pending, R.at, R.lastTick, R.calm = s, now, now, 0
    changed()
end

function R.drop()
    R.pending, R.calm = nil, 0
    changed()
end

-- no live zombie within SAFE_R tiles of the player (the client holds the zombies near it; corpses do not count)
function R.safe(p)
    local list = getCell():getZombieList()
    local px, py, r2 = p:getX(), p:getY(), R.SAFE_R * R.SAFE_R
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        local dx, dy = z:getX() - px, z:getY() - py
        if not z:isDead() and dx * dx + dy * dy <= r2 then return false end
    end
    return true
end

-- once a second while results wait: SAFE_S safe checks in a row open them; dead or KEEP_MS later they are dropped
function R.tick(now)
    if R.pending == nil or now - (R.lastTick or 0) < 1000 then return end
    R.lastTick = now
    local p = getSpecificPlayer(0)
    if p == nil or p:isDead() or now - R.at >= R.KEEP_MS then return R.drop() end
    R.calm = R.safe(p) and R.calm + 1 or 0
    if R.calm >= R.SAFE_S then R.autoOpen(R.pending) end
end

-- a row or death entry: the account, or "anonymous" (admins also get the account, as on the boards)
local function who(e)
    if e.anon then return e.a ~= nil and getText("IGUI_MQ_UI_AnonReal", e.a) or getText("IGUI_MQ_UI_Anonymous") end
    return tostring(e.n or "")
end

-- "Cleared: <place>" in green, "Failed: <place>" in red
function R.head(s)
    local ok = s.state == "success"
    return getText(ok and "IGUI_MQ_Horde_ResultHead_success" or "IGUI_MQ_Horde_ResultHead_failed", D.hordePlace(s)),
        ok and D.EXTRA.success or "errorText"
end

-- the Quest window or another framework window holds the keys (it is the focus root and on screen): opening now would
-- take them (Window onShown -> Focus.onFocus)
function R.busy(UI)
    if Q.Window ~= nil and Q.Window.visible() then return true end
    local F = UI ~= nil and UI.Focus or nil
    local r = F ~= nil and F.activeRoot or nil
    return r ~= nil and r ~= R.win and r.isReallyVisible ~= nil and r:isReallyVisible() == true
end

-- a pushed result once the player is safe: a gamepad player gets the toast (dropped), a busy screen waits
function R.autoOpen(s)
    if getJoypadData ~= nil and getJoypadData(0) ~= nil then
        D.toast(getText("IGUI_MQ_Horde_ResultTitle"), (R.head(s)), nil)
        return R.drop()
    end
    if R.busy(D.ui({ "window", "controls", "scrollPanel" })) then return end
    R.open(s)
end

function R.visible() return R.win ~= nil and R.win:isVisible() end

-- wider with the font (400 at a 16 px Small font, 500 at CatLang's 20): a tile's label gets (width - 2 PAD - 2 GAP) / 3
-- - 16; DE "Gezahlte Punkte" needs 125 px in CatLang, 400 left about 102 (integrator, 2026-10-29)
function R.width() return math.min(math.max(400, 25 * D.fontH()), getCore():getScreenWidth() - 40) end
function R.close() if R.visible() then R.win:close() end end

function R.build(UI)
    local theme = D.theme(UI)
    local core = getCore()
    local w = R.width()
    local win = UI.Window.new({ x = math.floor((core:getScreenWidth() - w) / 2), y = math.floor(core:getScreenHeight() / 4),
        width = w, height = 300, title = getText("IGUI_MQ_Horde_ResultTitle"), icon = "skull", theme = theme,
        opaque = D.has(UI, "opaqueWindow") or nil })
    -- Esc (and gamepad B, which asks onEscape first and stops there when it answers true, Focus.lua:1101-1108):
    -- close now. While Esc is physically down, GameKeyboard.eatKeyPress takes its release too (GameKeyboard.java:37-41,
    -- 71-77), so the release cannot reach the game's pause menu; waiting for the release instead lost it to a Dock
    -- above us, which answers isKeyConsumed from the shared ledger (UIManager.java:1468-1476, Dock.lua:1017-1018).
    -- Not when Esc is up (B): a mark never cleared by a release would eat the player's next Esc (Focus.lua:349-357).
    win.onEscape = function()
        win:close()
        local K = Keyboard
        if K ~= nil and K.isKeyDown ~= nil and K.isKeyDown(K.KEY_ESCAPE) and GameKeyboard ~= nil
            and GameKeyboard.eatKeyPress ~= nil then
            GameKeyboard.eatKeyPress(K.KEY_ESCAPE)
        end
        return true
    end
    R.win, R.UI, R.theme = win, UI, theme
    R.canvas = D.newCanvas(UI, theme)
    R.canvas:setY(win:contentTop())
    win:addChild(R.canvas)
    R.sp = UI.ScrollPanel.new({ x = PAD, y = 0, width = w - 2 * PAD, height = 100, theme = theme })
    win:addChild(R.sp)
    R.list = D.newCanvas(UI, theme)
    R.sp:addChild(R.list)
    R.pool = D.pool(win)
    win:addToUIManager()
end

-- a pushed one comes through autoOpen; the Results and View results buttons call this directly
function R.open(s)
    if R.pending ~= nil and R.pending.id == s.id then R.drop() end
    local UI = D.ui({ "window", "controls", "scrollPanel" })
    if UI == nil then return D.toast(getText("IGUI_MQ_Horde_ResultTitle"), (R.head(s)), nil) end
    if R.win == nil or R.UI ~= UI then R.build(UI) end
    R.s = s
    R.win:setVisible(true)
    R.win:bringToTop()
    R.sp:setYScroll(0)
    R.layout()
end

-- the rows in the scroll panel's canvas: rank, player (+ MVP tag, + "Died"), kills, points; my row framed
local function listRows(s, rows, lw, lh)
    local rb = D.begin(R.list)
    local rh = lh + 8
    local rankR, ptsR = 8 + math.max(D.textW(getText("IGUI_MQ_Admin_ColRank")), D.textW("000")), lw - 8
    local killR = ptsR - math.max(D.textW(getText("IGUI_MQ_UI_ColPoints")), D.textW("00,000")) - 12
    local nameX = rankR + 12
    local nameR = killR - math.max(D.textW(getText("IGUI_MQ_Horde_ResultKills")), D.textW("0,000")) - 12
    local mvp, died = getText("IGUI_MQ_Horde_MvpTag"), getText("IGUI_MQ_Horde_Died")
    local L = rb:list(0, 0, lw)
    local y = 0
    for i, r in ipairs(rows) do
        if i > 1 then rb:listSep(L, y) end
        local name = who(r)
        if i == tonumber(s.me) then
            name = getText("IGUI_MQ_Horde_You", name)
            rb:border(1, y + 1, lw - 2, rh - 2, "accent")
        end
        local tagsW = (r.mvp and D.chipW(mvp) + 6 or 0) + (r.dead and D.textW(died) + 6 or 0)
        rb:textRight(rankR, y + 4, tostring(r.r or i), "textMuted")
        local tx = nameX + rb:fitText(nameX, y + 4, name, nameR - nameX - tagsW, r.anon and "textMuted" or "text") + 6
        if r.mvp then tx = tx + rb:chip(tx, y + 1, mvp, D.EXTRA.gold, true) + 6 end
        if r.dead then rb:text(tx, y + 4, died, "textMuted") end
        rb:textRight(killR, y + 4, D.num(r.k or 0), "text")
        rb:textRight(ptsR, y + 4, D.num(r.p or 0), D.EXTRA.gold)
        y = y + rh
    end
    rb:listEnd(L, y)
    R.list:setWidth(lw)
    R.list:setHeight(math.max(1, y))
    return rankR, nameX, killR, ptsR, rh
end

-- everything but the list rows, with `shown` list rows visible; returns the window height
local function place(shown)
    local s, win, UI, theme = R.s, R.win, R.UI, R.theme
    R.pool:begin()
    local b = D.begin(R.canvas)
    local w = win.width - 2 * PAD
    local x, y = PAD, PAD
    local top = win:contentTop()
    local lh = D.fontH()
    local sep = getText("IGUI_MQ_UI_ListSep")
    local head, tok = R.head(s)
    y = b:para(x, y, head, w, tok, UIFont.Medium) + 2
    local ended = tonumber(s.endedAt) or 0
    local mins = math.max(0, math.floor((ended - (tonumber(s.spawnAt) or ended)) / 60000 + 0.5))
    y = b:para(x, y, getText("IGUI_MQ_Horde_ResultMeta", D.dateTime(ended), tostring(tonumber(s.cleared) or 0),
        tostring(tonumber(s.waves) or 1), tostring(mins)), w, "textMuted")
    local why = s.state ~= "success" and D.hordeWhy(s.why, (tonumber(s.cleared) or 0) + 1, s.waves) or ""
    if why ~= "" then y = b:para(x, y, why, w, "textMuted") end
    -- joined / kills / points paid
    y = y + 6
    local tw, mh = math.floor((w - 2 * D.GAP) / 3), D.fontH(UIFont.Medium)
    local th = 8 + mh + 2 + lh + 8
    for i, t in ipairs({ { s.joined, "IGUI_MQ_Horde_ResultJoined" }, { s.killed, "IGUI_MQ_Horde_ResultKills" },
        { s.pool, "IGUI_MQ_Horde_ResultPaid" } }) do
        local tx = x + (i - 1) * (tw + D.GAP)
        b:card(tx, y, tw, th)
        b:text(tx + 8, y + 8, D.num(tonumber(t[1]) or 0), D.EXTRA.gold, UIFont.Medium)
        b:fitText(tx + 8, y + 8 + mh + 2, getText(t[2]), tw - 16, "textMuted")
    end
    y = y + th + 6
    if s.capped then y = b:para(x, y, getText("IGUI_MQ_Horde_ResultCapped"), w, "warning") end
    local rows = type(s.rows) == "table" and s.rows or {}
    local mvps, topK = {}, nil
    for _, r in ipairs(rows) do
        if r.mvp then
            mvps[#mvps + 1] = who(r)
            topK = topK or r.k
        end
    end
    if #mvps > 0 then
        local cw = b:chip(x, y, getText("IGUI_MQ_Horde_MvpTag"), D.EXTRA.gold, true)
        local kw = b:textRight(x + w, y + 3, getText("IGUI_MQ_Horde_MvpKills", D.num(topK or 0)), "textMuted")
        b:fitText(x + cw + 6, y + 3, table.concat(mvps, sep), w - cw - kw - 14, "text")
        y = y + D.chipH() + 4
    end
    local deaths, dead = {}, type(s.deaths) == "table" and s.deaths or {}
    for i = 1, math.min(#dead, R.DEATHS) do
        deaths[i] = getText("IGUI_MQ_Horde_DiedWave", who(dead[i]), tostring(dead[i].wave or 1))
    end
    if #dead > R.DEATHS then deaths[#deaths + 1] = "+" .. D.num(#dead - R.DEATHS) end
    if #deaths > 0 then
        local dw = b:text(x, y, getText("IGUI_MQ_Horde_Died"), "textMuted") + 8
        y = b:para(x + dw, y, table.concat(deaths, sep), w - dw, "text")
    end
    -- the list: its head here, the rows in the scroll panel under it
    y = y + 6
    local lw = R.sp:contentWidth()
    local rankR, nameX, killR, ptsR, rh = listRows(s, rows, lw, lh)
    local L = b:list(x, y, lw)
    b:listHead(L, rh)
    b:textRight(x + rankR, y + 4, getText("IGUI_MQ_Admin_ColRank"), "text")
    b:text(x + nameX, y + 4, getText("IGUI_MQ_UI_ColPlayer"), "text")
    b:textRight(x + killR, y + 4, getText("IGUI_MQ_Horde_ResultKills"), "text")
    b:textRight(x + ptsR, y + 4, getText("IGUI_MQ_UI_ColPoints"), "text")
    y = b:listEnd(L, y + rh)
    local listH = shown * rh
    R.sp:setVisible(listH > 0)
    R.sp:setY(top + y)
    R.sp:setHeight(math.max(1, listH))
    y = y + listH + 4
    if #rows > shown then y = b:para(x, y, getText("IGUI_MQ_Horde_ResultMore", tostring(#rows - shown)), w, "textMuted") end
    if s.me == nil then y = b:para(x, y, getText("IGUI_MQ_Horde_NoKillsYou"), w, "textMuted") end
    y = y + 4
    local close = R.pool:button("close", UI, theme, getText("IGUI_MQ_UI_Close"), R, R.close, "primary")
    close:setX(x + w - close.width)
    close:setY(top + y)
    y = y + close.height + PAD
    R.canvas:setWidth(win.width)
    R.canvas:setHeight(y)
    R.pool:finish()
    if win.height ~= top + y then win:setHeight(top + y) end
    return top + y
end

-- every open and every resolution / font change lays it out again at R.width(), inside the screen: on a short screen
-- (768 high, 50 deaths) the list shows fewer rows so the ranking and Close stay on it
function R.layout()
    local win = R.win
    if win.width ~= R.width() then
        win:setWidth(R.width())
        R.sp:setWidth(win.width - 2 * PAD)
    end
    local rows = type(R.s.rows) == "table" and #R.s.rows or 0
    local shown = math.min(rows, R.ROWS)
    local h = place(shown)
    local sh = getCore():getScreenHeight()
    local maxH = sh - 40
    if h > maxH and shown > R.MIN_ROWS then
        shown = math.max(R.MIN_ROWS, shown - math.ceil((h - maxH) / (D.fontH() + 8)))
        h = place(shown)
    end
    local y = math.max(0, math.min(win:getY(), sh - h - 20))
    if y ~= win:getY() then win:setY(y) end
end

if first then
    Events.OnTick.Add(function() MinidoracatQuest.HordeResult.tick(getTimestampMs()) end)
    Events.OnResolutionChange.Add(function()
        if MinidoracatQuest.HordeResult.visible() then MinidoracatQuest.HordeResult.layout() end
    end)
end
