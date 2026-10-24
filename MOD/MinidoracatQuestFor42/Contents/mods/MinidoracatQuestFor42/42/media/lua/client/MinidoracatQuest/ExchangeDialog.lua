-- MinidoracatQuest/ExchangeDialog.lua: points -> survivor coins (spec 10.1, 10.3; C33).
--   Balance, today's remaining allowance, amount field with 50 / 100 / all-in quick picks, live coins at the
--   server's rate, balance after, then the result: paid (green), queued (orange, paid after the next reset),
--   refunded (red). No reply in 10 s: the same request (same requestId) can be asked again; the server replays
--   the original result instead of exchanging twice. Opened only from the Exchange page when state.exchange.available.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.ExchangeDialog == nil
local X = Q.ExchangeDialog or {}
Q.ExchangeDialog = X

local PAD = 14

X.REASON = {
    EXCHANGE_MIN = "IGUI_MQ_UI_ExMin", EXCHANGE_DAY_LIMIT = "IGUI_MQ_UI_ExDayLimit",
    NOT_ENOUGH_POINTS = "IGUI_MQ_UI_ExNoPoints", EXCHANGE_OFF = "IGUI_MQ_UI_ExOff",
}

function X.visible() return X.win ~= nil and X.win:isVisible() end

function X.build(UI)
    local theme = D.theme(UI)
    local w = 380
    for _, k in ipairs({ "IGUI_MQ_UI_PointsNoteEx", "IGUI_MQ_UI_ExQueuedBody", "IGUI_MQ_UI_ExTitle" }) do
        w = math.max(w, math.min(480, D.textW(getText(k)) * 0.6 + 2 * PAD))
    end
    -- the amount row never wraps: field 120 + "points = N coins" (ES / PTBR / TR ran past 380, quest-ui-es-1023h)
    w = math.max(w, math.min(480, 120 + 8 + D.textW(getText("IGUI_MQ_UI_ExArrowCoins", "00,000")) + 2 * PAD + 8))
    local core = getCore()
    local win = UI.Window.new({ x = math.floor((core:getScreenWidth() - w) / 2), y = math.floor(core:getScreenHeight() / 3),
        width = w, height = 260, title = getText("IGUI_MQ_UI_ExTitle"), icon = "coins", theme = theme,
        opaque = D.has(UI, "opaqueWindow") or nil, onClose = function() MinidoracatQuest.ExchangeDialog.onClose() end })
    win.onEscape = function() win:close() end
    X.win, X.UI, X.theme = win, UI, theme
    X.canvas = D.newCanvas(UI, theme)
    X.canvas:setY(win:contentTop())
    win:addChild(X.canvas)
    X.pool = D.pool(win)
    X.field = UI.TextField.new({ x = PAD, y = 0, width = 120, theme = theme, onlyNumbers = true, maxLength = 9,
        onChange = function(_, text) MinidoracatQuest.ExchangeDialog.onText(text) end })
    win:addChild(X.field)
    win:addToUIManager()
end

function X.open()
    local UI = D.ui({ "window", "controls" })
    if UI == nil then
        D.toast(getText("IGUI_MQ_UI_NeedFramework"), "")
        return
    end
    if X.win == nil or X.UI ~= UI then X.build(UI) end
    local q = C.exchangeQuote(C.state, "0")
    X.phase, X.code, X.result, X.args = "input", nil, nil, nil
    X.text = tostring(math.max(0, math.min(100, q.max)))
    X.field:setText(X.text)
    X.field:setEnabled(true)
    X.win:setVisible(true)
    X.win:bringToTop()
    X.layout()
    X.field:focus()
end

function X.close() if X.visible() then X.win:close() end end
function X.onClose() X.phase = "input" end

function X.onText(text)
    if X.phase ~= "input" then return end
    X.text = text or ""
    X.layout()
end

function X.onQuick(_, btn)
    if X.phase ~= "input" then return end
    X.text = tostring(btn.internal)
    X.field:setText(X.text)
    X.layout()
end

function X.onReply(r)
    if r.code == "NO_REPLY" then
        X.phase = "noreply"
    elseif r.ok then
        X.phase, X.result = r.state or "paid", r
    else
        X.phase, X.code = "error", r.code
    end
    if X.visible() then X.layout() end
end

function X.send()
    X.phase = "held"
    X.layout()
    C.send("exchange", X.args, function(r) MinidoracatQuest.ExchangeDialog.onReply(r) end)
end

function X.onSubmit()
    if X.phase == "noreply" then
        X.send()          -- same args table, same requestId
        return
    end
    if X.phase ~= "input" then
        X.close()
        return
    end
    local q = C.exchangeQuote(C.state, X.text)
    if not q.ok then return end
    X.held = q
    X.args = { amount = q.amount }
    X.field:setEnabled(false)
    X.send()
end

function X.onCancel() X.close() end

-- result box per phase: title, body, token
local function resultLines(q)
    local h = X.held or q
    if X.phase == "held" then
        return getText("IGUI_MQ_UI_ExHeld"), getText("IGUI_MQ_UI_ExArrow", D.num(h.amount), D.num(h.coins)), "textMuted"
    elseif X.phase == "paid" then
        local bal = C.state and C.state.points and C.state.points.balance or h.after
        return getText("IGUI_MQ_UI_ExPaid", D.num(X.result.coins or h.coins)), getText("IGUI_MQ_UI_ExPaidBody", D.num(bal)),
            D.EXTRA.success
    elseif X.phase == "queued" then
        return getText("IGUI_MQ_UI_ExQueued"), getText("IGUI_MQ_UI_ExQueuedBodyN", D.num(h.amount)), "warning"
    elseif X.phase == "refunded" then
        return getText("IGUI_MQ_UI_ExRefused"), getText("IGUI_MQ_UI_ExRefusedBody", D.num(h.amount)), "errorText"
    elseif X.phase == "noreply" then
        return getText("IGUI_MQ_UI_ExNoReply"), getText("IGUI_MQ_UI_ExNoReplyBody"), "warning"
    elseif X.phase == "error" then
        return getText("IGUI_MQ_UI_ExFailed"), D.codeText(X.code), "errorText"
    end
    return nil
end

function X.layout()
    local UI, theme, win = X.UI, X.theme, X.win
    X.pool:begin()
    local b = D.begin(X.canvas)
    local w = win.width - 2 * PAD
    local x, y = PAD, PAD
    local top = win:contentTop()
    local lh = D.fontH()
    local q = C.exchangeQuote(C.state, X.text)
    b:text(x, y, getText("IGUI_MQ_UI_Balance"), "textMuted")
    b:textRight(x + w, y, getText("IGUI_MQ_UI_PointsN", D.num(q.balance)), D.EXTRA.gold, UIFont.Medium)
    y = y + D.fontH(UIFont.Medium) + 4
    y = b:para(x, y, getText("IGUI_MQ_UI_ExLeft", D.num(q.left)), w, "text") + 8   -- wraps (FR ran to the frame)
    -- amount field + "points -> N coins"
    X.field:setX(x)
    X.field:setY(top + y)
    local fh = X.field.height
    b:text(x + X.field.width + 8, y + math.floor((fh - lh) / 2),
        getText("IGUI_MQ_UI_ExArrowCoins", D.num(q.coins)), "text")
    y = y + fh + 8
    if X.phase == "input" then
        local picks = {}
        for _, n in ipairs({ 50, 100 }) do
            local btn = X.pool:button("q" .. n, UI, theme, D.num(n), X, X.onQuick, "chip", q.amount == n)
            btn.internal = n
            btn:setEnabled(n <= q.max and n >= q.min)
            picks[#picks + 1] = btn
        end
        local all = X.pool:button("qall", UI, theme, getText("IGUI_MQ_UI_ExAll", D.num(q.max)), X, X.onQuick, "chip",
            q.amount == q.max and q.max > 0)
        all.internal = q.max
        all:setEnabled(q.max >= q.min and q.max > 0)
        picks[#picks + 1] = all
        y = D.placeRow(picks, x, top + y, x + w) - top + 8
        if q.reason ~= nil and X.REASON[q.reason] then
            y = b:para(x, y, getText(X.REASON[q.reason], D.num(q.reason == "EXCHANGE_MIN" and q.min or q.left)), w, "warning")
        end
        y = b:para(x, y, getText("IGUI_MQ_UI_ExAfter", D.num(math.max(0, q.after))), w, "textMuted")
        y = b:para(x, y, getText("IGUI_MQ_UI_ExRateNote", D.mult(q.rate)), w, "textFaint") + 6
    else
        local title, body, tok = resultLines(q)
        if title ~= nil then
            local lines = D.wrap(UI, body, w - 20, UIFont.Small)
            local h = 10 + lh + 4 + #lines * (lh + 2) + 8
            local c = b:col(tok)
            b:fill(x, y, w, h, { r = c.r, g = c.g, b = c.b, a = 0.12 })
            b:border(x, y, w, h, c)
            b:text(x + 10, y + 8, title, c)
            local ly = y + 8 + lh + 4
            for _, l in ipairs(lines) do
                b:text(x + 10, ly, l, "text")
                ly = ly + lh + 2
            end
            y = y + h + 10
        end
    end
    -- buttons, right aligned
    local submitTitle
    if X.phase == "input" then
        submitTitle = getText("IGUI_MQ_UI_ExSubmit", D.num(q.amount))
    elseif X.phase == "noreply" then
        submitTitle = getText("IGUI_MQ_UI_ExAskAgain")
    else
        submitTitle = getText("IGUI_MQ_UI_Close")
    end
    local submit = X.pool:button("submit", UI, theme, submitTitle, X, X.onSubmit, "primary")
    submit:setEnabled((X.phase == "input" and q.ok) or X.phase ~= "held" and X.phase ~= "input")
    local cancel = X.pool:button("cancel", UI, theme, getText("IGUI_MQ_UI_Cancel"), X, X.onCancel, "ghost")
    cancel:setVisible(X.phase == "input" or X.phase == "noreply")
    submit:setX(x + w - submit.width)
    submit:setY(top + y)
    cancel:setX(submit:getX() - 8 - cancel.width)
    cancel:setY(top + y)
    y = y + submit.height + PAD
    X.canvas:setWidth(win.width)
    X.canvas:setHeight(y)
    X.pool:finish()
    if win.height ~= top + y then win:setHeight(top + y) end
end

if first then
    -- balance or allowance changed while the dialog is open
    C.on("state", "exchange", function() if MinidoracatQuest.ExchangeDialog.visible() then MinidoracatQuest.ExchangeDialog.layout() end end)
    C.on("delta", "exchange", function() if MinidoracatQuest.ExchangeDialog.visible() then MinidoracatQuest.ExchangeDialog.layout() end end)
end
