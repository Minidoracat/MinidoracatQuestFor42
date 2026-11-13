-- MinidoracatQuest/PageExchange.lua: the Points page (page id still "exchange"; user 2026-10-24 split it from My
--   records, plan points-sinks 2026-11-12 made it the page for every use of points): balance card, the uses on this
--   server (swap / shield / sponsored horde jump to their page, the exchange row opens ExchangeDialog, the page's only
--   primary button), the point titles (buy, wear) and the points history (state.exchange.hist and state.spent merged,
--   C.pointsLog). In the nav while any use is on, exchange works, or there is history (spec.shown, Window.navGroups).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageExchange or {}
Q.PageExchange = P

local PAD, GAP = D.PAD, D.GAP

local function ex(s) return type(s) == "table" and type(s.exchange) == "table" and s.exchange or {} end
local function open(e) return e.available == true and e.enabled ~= false end

function P.shown()
    local s = C.state
    for _ in pairs(C.uses(s)) do return true end
    local e = ex(s)
    return open(e) or (type(e.hist) == "table" and #e.hist > 0) or (s ~= nil and type(s.spent) == "table" and #s.spent > 0)
end

function P.onExchange() if Q.ExchangeDialog then Q.ExchangeDialog.open() end end
function P.onGo(page, btn) W.select(btn.go) end

-- ===== balance card =====
local function card(b, page, x, y, w, s)
    local pts = type(s.points) == "table" and s.points or {}
    local pad = 10
    local mh, lh = D.fontH(UIFont.Medium), D.fontH()
    local lines = {
        { D.wrap(page.UI, getText("IGUI_MQ_UI_PointsSub", D.num(pts.season or 0), D.num(pts.total or 0)), w - 2 * pad, UIFont.Small), "text" },
        { D.wrap(page.UI, getText("IGUI_MQ_UI_PointsSpendNote"), w - 2 * pad, UIFont.Small), "textMuted" },
    }
    local h = pad + lh + 2 + mh + 4 + (#lines[1][1] + #lines[2][1]) * (lh + 2) + pad
    b:card(x, y, w, h, D.EXTRA.gold)
    local cy = y + pad
    b:text(x + pad, cy, getText("IGUI_MQ_UI_Balance"), "textMuted")
    cy = cy + lh + 2
    b:text(x + pad, cy, D.num(C.balance(s)), D.EXTRA.gold, UIFont.Medium)
    cy = cy + mh + 4
    for _, l in ipairs(lines) do
        for _, t in ipairs(l[1]) do
            b:text(x + pad, cy, t, l[2])
            cy = cy + lh + 2
        end
    end
    return y + h + GAP
end

-- ===== uses: one row per use on, its button on the right (under the text when wider than 35 % of the list) =====
local function uses(b, page, x, y, w, s)
    local u, rows = C.uses(s), {}
    local function go(key, page_id, label)
        local btn = page.pool:button(key, page.UI, page.theme, getText(label), page, P.onGo)
        btn.go = page_id
        return btn
    end
    if u.swap then
        local free = (C.defs().cfg.daily or {}).swapsPerDay or 1
        rows[#rows + 1] = { getText("IGUI_MQ_UI_Swap"), { { getText("IGUI_MQ_UI_UseSwapSub", tostring(free),
            D.num(u.swap.pts or 0), tostring(u.swap.perDay or 0)), "textMuted" } }, go("useSwap", "daily", "IGUI_MQ_UI_GoDaily") }
    end
    if u.shield then
        rows[#rows + 1] = { getText("IGUI_MQ_UI_Shield"), { { getText("IGUI_MQ_UI_UseShieldSub", D.num(u.shield.pts or 0)),
            "textMuted" } }, go("useShield", "daily", "IGUI_MQ_UI_GoDaily") }
    end
    if u.horde then
        rows[#rows + 1] = { getText("IGUI_MQ_UI_Fund"), { { getText("IGUI_MQ_UI_UseFundSub", D.num(u.horde.pts or 0)),
            "textMuted" } }, go("useHorde", "hordes", "IGUI_MQ_UI_GoHordes") }
    end
    local e = ex(s)
    if open(e) then
        local q = C.exchangeQuote(s, "")
        local sub = { { getText("IGUI_MQ_UI_ExLeft", D.num(q.left)), "textMuted" },
            { getText("IGUI_MQ_UI_ExRateNote", D.mult(q.rate)), "textMuted" } }
        local queued = math.floor(tonumber(e.queued) or 0)
        if queued > 0 then sub[#sub + 1] = { getText("IGUI_MQ_UI_ExQueuedNote", D.num(queued)), "warning" } end
        rows[#rows + 1] = { getText("IGUI_MQ_UI_ExTitle"), sub,
            page.pool:button("exchange", page.UI, page.theme, getText("IGUI_MQ_UI_ExchangeOpen"), page, P.onExchange, "primary") }
    end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Uses"))
    local L = b:list(x, y, w)
    if #rows == 0 then
        return b:listEnd(L, b:para(x + 8, y + 6, getText("IGUI_MQ_UI_UsesEmpty"), w - 16, "textMuted") + 4) + GAP
    end
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        local btn = r[3]
        local below = btn.width > w * 0.35
        local tw = w - 16 - (below and 0 or btn.width + 12)
        local ty = b:para(x + 8, y + 6, r[1], tw, "text")
        for _, l in ipairs(r[2]) do ty = b:para(x + 8, ty, l[1], tw, l[2]) end
        if below then
            btn:setX(x + 8)
            btn:setY(ty + 2)
            ty = ty + 2 + btn.height + 4
        else
            btn:setX(x + w - 8 - btn.width)
            btn:setY(y + 4)
            ty = math.max(ty, y + 4 + btn.height + 2)
        end
        y = ty + 4
    end
    return b:listEnd(L, y) + GAP
end

-- ===== point titles (plan points-sinks 3): wear the owned ones, buy the ones the balance covers, else how many short
function P.onBuyTitle(page, btn)
    local pay, id = btn.pay, btn.internal
    D.askSpend(page, "titleRid", { title = getText("IGUI_MQ_UI_TitleBuyAsk", D.num(pay), D.titleText(id)),
        text = getText("IGUI_MQ_UI_TitleBuyNote") .. "\n" .. D.balanceAfter(pay), confirm = getText("IGUI_MQ_UI_TitleBuy") },
        "buyTitle", { id = id, pay = pay })
end

-- wearing costs nothing: a plain request like My records' (PageRecords.setTitle), not a spend
function P.onWear(page, btn)
    if C.isPending(page.titleRid) then return end
    page.titleRid = C.send("title", { id = btn.internal }, function(r)
        page.titleRid = nil
        if not r.ok then D.toast(D.codeText(r.code), "", nil) end
        page.dirty = true
    end)
    page.dirty = true
end

local function titles(b, page, x, y, w, s)
    local list = C.shopTitles(s)
    if #list == 0 then return y end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_ShopTitles"))
    local owned = {}
    for _, id in ipairs(type(s.titles) == "table" and s.titles or {}) do owned[id] = true end
    local bal, pending = C.balance(s), C.isPending(page.titleRid)
    local lh = D.fontH()
    local hName, hPts = getText("IGUI_MQ_UI_TitleLabel"), getText("IGUI_MQ_UI_ColPoints")
    local worn = getText("IGUI_MQ_UI_TitleWorn")
    local ptsW, actW, rows = D.textW(hPts), 0, {}
    for _, t in ipairs(list) do
        local r = { t = t, price = D.num(t.pts) }
        if owned[t.id] and s.title == t.id then
            r.worn, r.actW = true, 20 + D.textW(worn)
        elseif owned[t.id] then
            r.btn = page.pool:button("tw:" .. t.id, page.UI, page.theme, getText("IGUI_MQ_UI_TitleUse"), page, P.onWear)
        elseif bal >= t.pts then
            r.btn = page.pool:button("tb:" .. t.id, page.UI, page.theme, getText("IGUI_MQ_UI_TitleBuy"), page, P.onBuyTitle)
            r.btn.pay = t.pts
        else
            r.short = getText("IGUI_MQ_UI_PointsShort", D.num(t.pts - bal))
            r.actW = D.textW(r.short)
        end
        if r.btn then
            r.btn.internal = t.id
            r.btn:setEnabled(not pending)
            r.actW = r.btn.width
        end
        ptsW, actW = math.max(ptsW, D.textW(r.price)), math.max(actW, r.actW)
        rows[#rows + 1] = r
    end
    -- a wide action column (a long translation) goes under the name, so names keep room to wrap
    local below = actW > w * 0.35
    local ptsR = x + w - 8 - (below and 0 or actW + 12)
    local nameW = ptsR - ptsW - 12 - (x + 8)
    local rh = lh + 8
    local L = b:list(x, y, w)
    b:listHead(L, rh)
    b:fitText(x + 8, y + 4, hName, nameW, "text")
    b:textRight(ptsR, y + 4, hPts, "text")
    y = y + rh
    local endsAt = type(s.season) == "table" and tonumber(s.season.endsAt) or nil
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        local ny = b:para(x + 8, y + 4, D.titleText(r.t.id), nameW, D.EXTRA.gold)   -- wraps, never cut
        if r.t.season and endsAt ~= nil then
            ny = b:para(x + 8, ny, getText("IGUI_MQ_UI_TitleSeasonOnly", D.duration(D.left(endsAt))), nameW, "textMuted")
        end
        b:textRight(ptsR, y + 4, r.price, "text")
        local ay, ax = y + 4, x + w - 8 - r.actW
        if below then ay, ax = ny + 2, x + 8 end
        local bottom = ay + lh
        if r.btn then
            r.btn:setX(ax)
            r.btn:setY(ay - 2)
            bottom = ay - 2 + r.btn.height
        elseif r.worn then
            b:icon(ax, ay, 16, "check", D.EXTRA.success, "v")
            b:text(ax + 20, ay, worn, D.EXTRA.success)
        else
            b:text(ax, ay, r.short, "textMuted")
        end
        y = math.max(ny, bottom) + 4
    end
    return b:listEnd(L, y) + GAP
end

-- ===== points history: exchanges (their state in words and color) and spends / refunds, newest first =====
local EX_STATE = { paid = { "IGUI_MQ_UI_ExStatePaid", "success" }, queued = { "IGUI_MQ_UI_ExQueued", "warning" },
    refunded = { "IGUI_MQ_UI_ExStateRefunded", "errorText" } }
local SPENT = { swap = "IGUI_MQ_UI_LogSwap", shield = "IGUI_MQ_UI_LogShield", title = "IGUI_MQ_UI_LogTitle",
    horde = "IGUI_MQ_UI_LogHorde", hordeRefund = "IGUI_MQ_UI_LogHordeRefund" }

local function logRow(e)
    local r = { time = D.dateTime(e.at) }
    if e.ex ~= nil then
        local h = e.ex
        local st = EX_STATE[h.state] or EX_STATE.paid
        r.detail, r.state, r.stateTok = getText("IGUI_MQ_UI_LogExchange", D.num(h.coins or 0)), getText(st[1]), st[2]
        if h.state == "refunded" then
            r.pts, r.ptsTok = "0", "textMuted"   -- the points came back
        else
            r.pts, r.ptsTok = D.num(-(tonumber(h.amount) or 0)), "text"
        end
        return r
    end
    local sp = e.spent
    local key = SPENT[sp.what]
    r.detail = key == nil and tostring(sp.what) or (sp.what == "title" and getText(key, D.titleText(sp.ref)) or getText(key))
    local n = tonumber(sp.n) or 0
    if n > 0 then r.pts, r.ptsTok = "+" .. D.num(n), D.EXTRA.success else r.pts, r.ptsTok = D.num(n), "text" end
    return r
end

local function history(b, x, y, w, s)
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_PointsLog"))
    local log = C.pointsLog(s)
    local L = b:list(x, y, w)
    if #log == 0 then
        return b:listEnd(L, b:para(x + 8, y + 6, getText("IGUI_MQ_UI_PointsLogEmpty"), w - 16, "textMuted") + 4) + GAP
    end
    local hTime, hDetail, hPts = getText("IGUI_MQ_UI_ColTime"), getText("IGUI_MQ_UI_ColDetail"), getText("IGUI_MQ_UI_ColPoints")
    local rows, timeW, ptsW = {}, D.textW(hTime), D.textW(hPts)
    for _, e in ipairs(log) do
        local r = logRow(e)
        timeW, ptsW = math.max(timeW, D.textW(r.time)), math.max(ptsW, D.textW(r.pts))
        rows[#rows + 1] = r
    end
    local lh = D.fontH()
    local rh = lh + 8
    local midX = x + 8 + timeW + 16
    local midW = x + w - 8 - ptsW - 16 - midX
    b:listHead(L, rh)
    b:text(x + 8, y + 4, hTime, "text")
    b:fitText(midX, y + 4, hDetail, midW, "text")
    b:textRight(x + w - 8, y + 4, hPts, "text")
    y = y + rh
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        b:text(x + 8, y + 4, r.time, "textMuted")
        b:textRight(x + w - 8, y + 4, r.pts, r.ptsTok)
        local lines = D.wrap(b.UI, r.detail, midW, UIFont.Small)
        local ly = y + 4
        for _, l in ipairs(lines) do
            b:text(midX, ly, l, "text")
            ly = ly + lh + 2
        end
        if r.state ~= nil then
            -- the state word stays whole: after the detail when it fits, else on the next line
            local lastW = D.textW(lines[#lines] or "")
            if #lines > 0 and lastW + 8 + D.textW(r.state) <= midW then
                b:text(midX + lastW + 8, ly - lh - 2, r.state, r.stateTok)
            else
                b:text(midX, ly, r.state, r.stateTok)
                ly = ly + lh + 2
            end
        end
        y = math.max(y + rh, ly + 2)
    end
    return b:listEnd(L, y) + GAP
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_NavExchange"))
    if s == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    y = card(b, page, x, y, w, s)
    y = uses(b, page, x, y, w, s)
    y = titles(b, page, x, y, w, s)
    y = history(b, x, y, w, s)
    D.finish(page, y)
end

P.spec = {
    id = "exchange", label = "IGUI_MQ_UI_NavExchange", icon = "coins", group = "main", order = 60,
    shown = function() return MinidoracatQuest.PageExchange.shown() end,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageExchange.layout(page) end,
}
W.register(P.spec)
