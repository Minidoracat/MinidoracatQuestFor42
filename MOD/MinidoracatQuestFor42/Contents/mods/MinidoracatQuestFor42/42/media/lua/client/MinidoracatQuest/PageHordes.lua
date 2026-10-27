-- MinidoracatQuest/PageHordes.lua: the player Hordes page (design r12): the current horde (the daily page banner),
--   my horde totals (stats horde.joined / wins / kills / mvp from the records query) and the recent results
--   (records.hordes: the last announced ones on the server, newest first, each with my kills and points;
--   Hordes.recent). In the nav while automatic hordes are on or there are results (state.hordes.on).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageHordes or {}
Q.PageHordes = P

local PAD, GAP = D.PAD, D.GAP

P.TILES = { "horde.joined", "horde.wins", "horde.kills", "horde.mvp" }

function P.shown()
    local hs = C.state and C.state.hordes
    return type(hs) == "table" and hs.on == true
end

function P.onRetry() Q.Client.requestRecords(true) end

-- ===== the current horde (the daily page banner and its Map button) =====
local function now(page, b, x, y, w, s)
    return Q.PageDaily.hordeBlock(page, b, x, y, w, s)
        or b:para(x, y, getText("IGUI_MQ_UI_HordesNone"), w, "textMuted") + GAP
end

-- ===== my totals: one tile per stat, the all-time value =====
local function tiles(b, page, x, y, w)
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_HordesMine"))
    if C.records == nil then
        if C.recordsError ~= nil then
            y = b:para(x, y, getText("IGUI_MQ_UI_RecordsError"), w, "errorText")
            local btn = page.pool:button("retry", page.UI, page.theme, getText("IGUI_MQ_UI_Refresh"), page, P.onRetry)
            btn:setX(x)
            btn:setY(y)
            return y + btn.height + GAP
        end
        b:chip(x, y, getText("IGUI_MQ_UI_Loading"), "textMuted")
        return y + D.chipH() + GAP
    end
    local n = #P.TILES
    local tw = math.floor((w - (n - 1) * GAP) / n)
    local mh, lh, pad = D.fontH(UIFont.Medium), D.fontH(), 8
    local h = pad + mh + 2 + lh + pad
    for i, stat in ipairs(P.TILES) do
        local tx = x + (i - 1) * (tw + GAP)
        local r = C.statRow(stat)
        b:card(tx, y, tw, h)
        b:text(tx + pad, y + pad, D.num(r and r.total or 0), D.EXTRA.gold, UIFont.Medium)
        b:fitText(tx + pad, y + pad + mh + 2, D.statName(stat), tw - 2 * pad, "textMuted")
    end
    return y + h + GAP
end

-- ===== recent results: waves cleared; a failed one of several waves names the wave it failed in =====
local function result(e)
    local waves, cleared = tonumber(e.waves) or 1, tonumber(e.cleared) or 0
    if e.state == "success" then
        return getText("IGUI_MQ_UI_HordeRes_success", tostring(cleared), tostring(waves)), "success"
    end
    if e.state == "cancelled" then return getText("IGUI_MQ_UI_HordeRes_cancelled"), "textMuted" end
    local why = getText("IGUI_MQ_Admin_HordeWhy_" .. tostring(e.why))
    if waves > 1 then
        return getText("IGUI_MQ_UI_HordeRes_failedWave", tostring(cleared + 1), why, tostring(cleared)), "errorText"
    end
    return getText("IGUI_MQ_UI_HordeRes_failed", why), "errorText"
end

-- a cancel came before any spawn, so nobody took part in it
local function mine(e)
    local k = tonumber(e.mine) or 0
    if e.state == "cancelled" then return "-", "textFaint" end
    if k >= 1 then return D.num(k), "text" end
    return getText("IGUI_MQ_UI_HordeAbsent"), "textFaint"
end

local function points(e)
    local got = tonumber(e.got) or 0
    if got > 0 then return "+" .. D.num(got), D.EXTRA.gold end
    return "-", "textFaint"
end

local function recent(b, x, y, w)
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_HordesRecent"))
    local list = C.records and C.records.hordes
    local L = b:list(x, y, w)
    if type(list) ~= "table" or #list == 0 then
        return b:listEnd(L, b:para(x + 8, y + 6, getText("IGUI_MQ_UI_HordesEmpty"), w - 16, "textMuted") + 4) + GAP
    end
    local hTime, hPlace, hRes = getText("IGUI_MQ_UI_ColTime"), getText("IGUI_MQ_UI_ColPlace"), getText("IGUI_MQ_UI_ColResult")
    local hMine, hPts = getText("IGUI_MQ_UI_ColMyKills"), getText("IGUI_MQ_UI_ColPoints")
    local rows, timeW, placeW, mineW, ptsW = {}, D.textW(hTime), D.textW(hPlace), D.textW(hMine), D.textW(hPts)
    for _, e in ipairs(list) do
        if type(e) == "table" then
            local r = { D.dateTime(tonumber(e.endedAt) or 0), D.hordePlace(e) }
            r[3], r[4] = result(e)
            r[5], r[6] = mine(e)
            r[7], r[8] = points(e)
            timeW, placeW = math.max(timeW, D.textW(r[1])), math.max(placeW, D.textW(r[2]))
            mineW, ptsW = math.max(mineW, D.textW(r[5])), math.max(ptsW, D.textW(r[7]))
            rows[#rows + 1] = r
        end
    end
    placeW = math.min(placeW, math.floor(w / 4))
    local rh = D.fontH() + 8
    local placeX = x + 8 + timeW + 12
    local resX = placeX + placeW + 12
    local ptsR = x + w - 8
    local mineR = ptsR - ptsW - 12
    local resW = mineR - mineW - 12 - resX
    b:listHead(L, rh)
    b:text(x + 8, y + 4, hTime, "text")
    b:fitText(placeX, y + 4, hPlace, placeW, "text")
    b:fitText(resX, y + 4, hRes, resW, "text")
    b:textRight(mineR, y + 4, hMine, "text")
    b:textRight(ptsR, y + 4, hPts, "text")
    y = y + rh
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        b:text(x + 8, y + 4, r[1], "textMuted")
        b:fitText(placeX, y + 4, r[2], placeW, "text")
        b:textRight(mineR, y + 4, r[5], r[6])
        b:textRight(ptsR, y + 4, r[7], r[8])
        -- the result wraps: ES "Falló en la oleada 2: se acabó el tiempo (1 despejadas)" lost the cleared waves
        -- to the cut (quest-hui-es-1027b); one line keeps the row at rh
        y = math.max(y + rh, b:para(resX, y + 4, r[3], resW, r[4]) + 2)
    end
    y = b:listEnd(L, y)
    return b:para(x, y + 6, getText("IGUI_MQ_UI_HordesNote"), w, "textMuted") + GAP
end

-- a horde that ended while the page is open: ask once for the records that list it
local function refresh(s)
    local last = type(s.hordes) == "table" and s.hordes.last or nil
    local id = type(last) == "table" and last.id or nil
    if id == nil or id == P.askedFor then return end
    local list = C.records and C.records.hordes
    local top = type(list) == "table" and list[1] or nil
    if type(top) == "table" and top.id == id then return end
    P.askedFor = id
    C.requestRecords(true)
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_NavHordes"))
    if s == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    refresh(s)
    y = now(page, b, x, y, w, s)
    y = tiles(b, page, x, y, w)
    y = recent(b, x, y, w)
    D.finish(page, y)
end

P.spec = {
    id = "hordes", label = "IGUI_MQ_UI_NavHordes", icon = "skull", group = "main", order = 25, ticking = true,
    shown = function() return MinidoracatQuest.PageHordes.shown() end,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageHordes.layout(page) end,
    onShow = function() MinidoracatQuest.Client.requestRecords(true) end,
}
W.register(P.spec)
