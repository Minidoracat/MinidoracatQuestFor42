-- MinidoracatQuest/PageExchange.lua: points -> survivor coins on their own page (user 2026-10-24: split from My
--   records so one page does not carry too much): balance, today's allowance and the rate, the exchange button
--   (ExchangeDialog), points still queued, and the exchange history (state.exchange.hist: queued rows first, then
--   the finished ones, newest first; Exchange.stateFor). In the nav only while exchange works on this server or
--   there is history to show (spec.shown, Window.navGroups).

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
    local e = ex(C.state)
    return open(e) or (type(e.hist) == "table" and #e.hist > 0)
end

function P.onExchange() if Q.ExchangeDialog then Q.ExchangeDialog.open() end end

-- ===== balance card =====
local function card(b, page, x, y, w, s)
    local e = ex(s)
    local can = open(e)
    local pad = 10
    local mh, lh = D.fontH(UIFont.Medium), D.fontH()
    local btn = can and page.pool:button("exchange", page.UI, page.theme, getText("IGUI_MQ_UI_ExchangeOpen"), page,
        P.onExchange, "primary") or nil
    local q = C.exchangeQuote(s, "")
    local lines = {}
    if can then
        lines[#lines + 1] = { getText("IGUI_MQ_UI_ExLeft", D.num(q.left)), "text" }
        lines[#lines + 1] = { getText("IGUI_MQ_UI_ExRateNote", D.mult(q.rate)), "textFaint" }
        lines[#lines + 1] = { getText("IGUI_MQ_UI_PointsNoteEx"), "textFaint" }
    else
        lines[#lines + 1] = { getText("IGUI_MQ_UI_ExOff"), "textMuted" }
    end
    local queued = math.floor(tonumber(e.queued) or 0)
    if queued > 0 then lines[#lines + 1] = { getText("IGUI_MQ_UI_ExQueuedNote", D.num(queued)), "warning" } end
    -- a wide button (FR "Echanger contre des pieces de survivant...") goes under the text instead of beside it
    local below = btn ~= nil and btn.width > w * 0.35
    local inner = w - 2 * pad - ((btn and not below) and btn.width + 10 or 0)
    local wrapped, n = {}, 0
    for i, l in ipairs(lines) do
        wrapped[i] = D.wrap(page.UI, l[1], inner, UIFont.Small)
        n = n + #wrapped[i]
    end
    local h = pad + lh + 2 + mh + 4 + n * (lh + 2) + pad + (below and btn.height + 6 or 0)
    b:card(x, y, w, h, D.EXTRA.gold)
    local cy = y + pad
    b:text(x + pad, cy, getText("IGUI_MQ_UI_Balance"), "textMuted")
    cy = cy + lh + 2
    b:text(x + pad, cy, D.num(q.balance), D.EXTRA.gold, UIFont.Medium)
    cy = cy + mh + 4
    for i, l in ipairs(lines) do
        for _, t in ipairs(wrapped[i]) do
            b:text(x + pad, cy, t, l[2])
            cy = cy + lh + 2
        end
    end
    if btn and below then
        btn:setX(x + pad)
        btn:setY(cy + 4)
    elseif btn then
        btn:setX(x + w - pad - btn.width)
        btn:setY(y + math.floor((h - btn.height) / 2))
    end
    return y + h + GAP
end

-- ===== history =====
local EX_STATE = { paid = { "IGUI_MQ_UI_ExStatePaid", "success" }, queued = { "IGUI_MQ_UI_ExQueued", "warning" },
    refunded = { "IGUI_MQ_UI_ExStateRefunded", "errorText" } }

local function history(b, x, y, w, s)
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_ExHistory"))
    local hist = ex(s).hist
    if type(hist) ~= "table" or #hist == 0 then
        return b:para(x, y, getText("IGUI_MQ_UI_ExHistoryEmpty"), w, "textMuted") + GAP
    end
    local rows, timeW, stateW = {}, 0, 0
    for _, h in ipairs(hist) do
        local st = EX_STATE[h.state] or EX_STATE.paid
        local r = { D.dateTime(h.at or 0), getText("IGUI_MQ_UI_ExArrow", D.num(h.amount or 0), D.num(h.coins or 0)),
            getText(st[1]), st[2] }
        timeW, stateW = math.max(timeW, D.textW(r[1])), math.max(stateW, D.textW(r[3]))
        rows[#rows + 1] = r
    end
    local rh = D.fontH() + 8
    local midX = x + 8 + timeW + 16
    local midW = x + w - 8 - stateW - 16 - midX
    for i, r in ipairs(rows) do
        if i % 2 == 0 then b:rect(x, y, w, rh, "hover") end
        b:text(x + 8, y + 4, r[1], "textMuted")
        b:fitText(midX, y + 4, r[2], midW, "text")
        b:textRight(x + w - 8, y + 4, r[3], r[4])
        y = y + rh
    end
    return y + GAP
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_ExTitle"))
    if s == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    y = card(b, page, x, y, w, s)
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
