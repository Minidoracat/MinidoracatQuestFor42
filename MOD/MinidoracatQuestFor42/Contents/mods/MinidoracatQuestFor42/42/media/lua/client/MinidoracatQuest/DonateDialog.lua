-- MinidoracatQuest/DonateDialog.lua: give points to the server-wide donation (plan points-play-1112 claim 3), opened
--   by the weekly page's "Donate...". Like PledgeDialog: an amount field, the least one may give, the balance before
--   and after, the no-refund rule; sends donate { n, total } where total is the target this client saw
--   (C.donateQuote; the server refuses PRICE_CHANGED when it is not the current one). A taken donation closes it with
--   a toast of what was given; a refusal toasts why and leaves it open.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.DonateDialog == nil
local X = Q.DonateDialog or {}
Q.DonateDialog = X

local PAD = 14

function X.visible() return X.win ~= nil and X.win:isVisible() end

function X.build(UI)
    local theme = D.theme(UI)
    local w = 400
    local core = getCore()
    local win = UI.Window.new({ x = math.floor((core:getScreenWidth() - w) / 2), y = math.floor(core:getScreenHeight() / 3),
        width = w, height = 220, title = getText("IGUI_MQ_UI_DonateTitle"), icon = "skull", theme = theme,
        opaque = D.has(UI, "opaqueWindow") or nil })
    win.onEscape = function() win:close() end
    X.win, X.UI, X.theme = win, UI, theme
    X.canvas = D.newCanvas(UI, theme)
    X.canvas:setY(win:contentTop())
    win:addChild(X.canvas)
    X.pool = D.pool(win)
    X.field = UI.TextField.new({ x = PAD, y = 0, width = 120, theme = theme, onlyNumbers = true, maxLength = 9,
        onChange = function(_, text) MinidoracatQuest.DonateDialog.onText(text) end })
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
    -- X.rid stays: a donation still waiting for its reply must not be sent a second time by opening the dialog again
    X.text = tostring(C.donateQuote(C.state, nil).dflt)
    X.field:setText(X.text)
    X.win:setVisible(true)
    X.win:bringToTop()
    X.layout()
    X.field:focus()
end

function X.close() if X.visible() then X.win:close() end end
function X.onCancel() X.close() end

function X.onText(text)
    X.text = text or ""
    X.layout()
end

function X.onSubmit()
    if C.isPending(X.rid) then return end
    -- the dialog redraws with every state, so what it shows and the spendSeq sendSpend takes now go together
    local q = C.donateQuote(C.state, X.text)
    if not q.ok then return end
    X.rid = C.sendSpend("donate", { n = q.amount, total = q.target },
        function(r) MinidoracatQuest.DonateDialog.onReply(r) end)
    if X.rid == nil then D.toast(D.codeText("RATE_LIMITED"), "", nil) end   -- another spend still waits for its reply
    X.layout()
end

function X.onReply(r)
    X.rid = nil
    if r.ok then
        D.toast(getText("IGUI_MQ_UI_Donated", D.num(tonumber(r.n) or 0)), "", D.EXTRA.success)
        X.close()
        return
    end
    D.toast(r.code == "NO_REPLY" and getText("IGUI_MQ_UI_ExNoReply") or D.codeText(r.code), "", nil)
    if X.visible() then X.layout() end
end

-- why the amount cannot go yet (warning line); nil while it can or the field is empty
local function reasonText(q)
    local r = q.reason
    if r == "DONATE_MIN" then return getText("IGUI_MQ_UI_DonateMin", D.num(q.min)) end
    if r == "NOT_ENOUGH_POINTS" then return getText("IGUI_MQ_UI_PointsShort", D.num(q.amount - q.balance)) end
    if r == "DONATE_OFF" then return D.codeText(r) end
    return nil
end

function X.layout()
    local UI, theme, win = X.UI, X.theme, X.win
    X.pool:begin()
    local b = D.begin(X.canvas)
    local w = win.width - 2 * PAD
    local x, y = PAD, PAD
    local top = win:contentTop()
    local q = C.donateQuote(C.state, X.text)
    local d = type((C.state or {}).donate) == "table" and C.state.donate or {}
    b:text(x, y, getText("IGUI_MQ_UI_Balance"), "textMuted")
    b:textRight(x + w, y, getText("IGUI_MQ_UI_PointsN", D.num(q.balance)), D.EXTRA.gold, UIFont.Medium)
    y = y + D.fontH(UIFont.Medium) + 4
    y = b:para(x, y, getText("IGUI_MQ_UI_DonateGot", D.num(tonumber(d.total) or 0), D.num(q.target)), w, "text") + 6
    X.field:setX(x)
    X.field:setY(top + y)
    X.field:setEnabled(not C.isPending(X.rid))
    y = y + X.field.height + 8
    local why = reasonText(q)
    if why ~= nil then y = b:para(x, y, why, w, "warning") end
    -- an amount that cannot go takes nothing: the balance stays
    y = b:para(x, y, getText("IGUI_MQ_UI_DonateHint", D.num(q.min), D.num(q.balance), D.num(q.ok and q.after or q.balance)),
        w, "textMuted") + 6
    local submit = X.pool:button("submit", UI, theme, getText("IGUI_MQ_UI_DonateGo", D.num(q.amount)), X, X.onSubmit,
        "primary")
    submit:setEnabled(q.ok and not C.isPending(X.rid))
    local cancel = X.pool:button("cancel", UI, theme, getText("IGUI_MQ_UI_Cancel"), X, X.onCancel, "ghost")
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
    -- the total or the balance moved while the dialog is open
    C.on("state", "donate", function() if MinidoracatQuest.DonateDialog.visible() then MinidoracatQuest.DonateDialog.layout() end end)
    C.on("delta", "donate", function() if MinidoracatQuest.DonateDialog.visible() then MinidoracatQuest.DonateDialog.layout() end end)
end
