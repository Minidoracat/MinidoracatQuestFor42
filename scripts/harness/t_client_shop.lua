-- Client slice, points uses (plan points-sinks 2026-11-12, contract temp/points-sinks): the paid swap and the streak
-- shield on the daily page, the Points page (uses, point titles, merged history, nav rule), Sponsor a horde on the
-- Hordes page with the pledge dialog, the sponsored banner, the new toasts and title sources. Every button is pressed
-- the way the engine does it, b.onclick(b.target, b); texts read "key|arg1|arg2" so a check sees key and values.
-- The fakes follow t_hordes_ui.lua; the globals are put back at the end.
return function(T)
    local check = T.check
    local saved = { ISUIElement = ISUIElement, ISPanel = ISPanel, getTextManager = getTextManager, UIFont = UIFont,
        getText = getText, getCore = getCore, MinidoracatUI = MinidoracatUI }

    -- ===== fakes =====
    local Base = {}
    Base.__index = Base
    function Base:initialise() end
    function Base:setX(x) self.x = x end
    function Base:setY(y) self.y = y end
    function Base:getX() return self.x end
    function Base:getY() return self.y end
    function Base:setWidth(w) self.width = w end
    function Base:setHeight(h) self.height = h end
    function Base:setVisible(v) self.visible = v end
    function Base:isVisible() return self.visible ~= false end
    function Base:addChild(c) self.children = self.children or {}; self.children[#self.children + 1] = c; c.parent = self end
    function Base:setTooltip(s) self.tooltip = s end
    function Base:setEnabled(b) self.enabled = b end
    function Base:addToUIManager() end
    function Base:bringToTop() end
    local function class(parent)
        local cls = setmetatable({}, { __index = parent })
        cls.__index = cls
        function cls:derive() return class(self) end
        function cls:new(x, y, w, h) return setmetatable({ x = x, y = y, width = w, height = h }, self) end
        return cls
    end
    ISUIElement, ISPanel = class(Base), class(Base)
    UIFont = { Small = "Small", Medium = "Medium" }
    getTextManager = function()
        return { MeasureStringX = function(_, _, s) return #tostring(s) * 7 end, getFontHeight = function() return 14 end }
    end
    getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
    local function widget(extra)
        local Wd = setmetatable(extra or {}, { __index = Base })
        Wd.__index = Wd
        return function(opts)
            return setmetatable({ opts = opts, x = opts.x or 0, y = opts.y or 0, width = opts.width or 80, height = opts.height or 20 }, Wd)
        end
    end
    local button = widget({ setTitle = function(self, s) self.opts.title = s end,
        fitWidth = function(self) self.width = #tostring(self.opts.title) * 7 + 20 end, setActive = function(self, b) self.active = b end })
    local dialogs, toasts = {}, {}
    local UI = {
        API_MAJOR = 1, API_REVISION = 22,
        CAPABILITIES = { window = true, controls = true, dialog = true, textWrap = true, toast = true },
        Text = { fit = function(s) return s end, wrap = function(s)
            local out = {}
            for line in string.gmatch(s .. "\n", "(.-)\n") do out[#out + 1] = line end
            return out
        end },
        -- ISButton keeps target and onclick on the button and a click calls self.onclick(self.target, self)
        Button = { new = function(opts) local b = button(opts); b.target, b.onclick, b.style = opts.target, opts.onClick, opts.style; return b end },
        TextField = { new = widget({ getText = function(self) return self.text or "" end, setText = function(self, s) self.text = s end,
            focus = function() end }) },
        ScrollPanel = { new = widget({ contentWidth = function(self) return self.width - 12 end, _scrollPanel = true }) },
        Window = { new = widget({ contentTop = function() return 24 end, setTitle = function(self, t) self.title = t end,
            close = function(self) self.visible = false end }) },
        Dialog = { show = function(opts) dialogs[#dialogs + 1] = opts end },
        Toast = { show = function(o) toasts[#toasts + 1] = o end },
    }
    local colors = setmetatable({}, { __index = function(_, k) return { r = 1, g = 1, b = 1, a = 1, token = k } end })
    UI.Theme = { create = function() return { colors = colors } end }
    MinidoracatUI = { v1 = UI }
    getText = function(key, ...)
        local s = key
        for i = 1, select("#", ...) do s = s .. "|" .. tostring((select(i, ...))) end
        return s
    end

    local MQ = T.bootClient()
    local C, D, W = MQ.Client, MQ.Draw, MQ.Window
    local errors = {}
    C.log = function(m) errors[#errors + 1] = m end
    T.player({ name = "alice" })
    local K, cat = MQ.Contract, MQ.Catalog
    local function push(cmd, args) T.fire("OnServerCommand", K.MODULE, cmd, args) end
    local function lastSent() return T.clientSent[#T.clientSent] end
    local function answer(ok) local d = table.remove(dialogs); d.onResult(ok) end
    local function press(b) b.onclick(b.target, b) end
    local function newPage(width)
        local p = { UI = UI, theme = { colors = colors }, parent = ISPanel:new(0, 0, width or 640, 480), width = width or 640, height = 480 }
        D.scrollPage(p)
        return p
    end
    local function btn(p, key) local b = p.pool.items[key]; return (b ~= nil and b.visible ~= false) and b or nil end
    local function drew(p, frag)
        for i = 1, p.canvas.n do
            local s = p.canvas.ops[i].s
            if type(s) == "string" and string.find(s, frag, 1, true) then return true end
        end
        return false
    end
    -- every list box a layout opened was closed: its background got a height and its frame was drawn
    local function boxesClosed(p)
        local fills, frames = 0, 0
        for i = 1, p.canvas.n do
            local o = p.canvas.ops[i]
            if o.k == 1 and o.s == "rect" then
                fills = fills + 1
                if o.h <= 0 then return false end
            elseif o.k == 2 and o.s == "rect" then
                frames = frames + 1
            end
        end
        return fills > 0 and fills == frames
    end
    local function settle(p)
        C.pending = {}   -- the requests of the step before are over
        p.swapRid, p.shieldRid, p.titleRid = nil, nil, nil
    end

    local now = T.now
    local SHOP = { swap = { enabled = true, pts = 50, perDay = 3 }, shield = { enabled = true, pts = 200, perWeek = 1 },
        titles = { enabled = true, season = 1500, list = { spend_1 = 1000, spend_2 = 2000, spend_3 = 3500, spend_4 = 5000 } } }
    local function catalog(shop) push("catalog", { rev = 1, packs = {}, overrides = { shop = shop } }) end
    local OFF = { swap = { enabled = false }, shield = { enabled = false }, titles = { enabled = false } }
    local d1, d2 = cat.daily[1], cat.daily[2]
    local function state(o)
        push("state", { v = 1, user = "alice", now = now, points = { season = 2310, total = 8450, balance = o.balance or 1240 },
            spendSeq = o.spendSeq or math.max(5, C.spendSeq()),   -- never older than the one shown (Client drops that)
            day = { quests = { { tid = d1.tid, theme = d1.theme, target = 30, prog = 12, pts = 15, state = "active", startMs = now - 1000 },
                { tid = d2.tid, theme = d2.theme, target = 5, prog = 0, pts = 15, state = "active", startMs = now - 2000 } },
                swaps = o.swaps or 0, paid = o.paid },
            streak = { days = 12, graceUsed = o.graceUsed, week = o.week or { "done", "grace", "done", "", "", "", "" },
                shield = o.shield, shieldLeft = o.shieldLeft },
            season = { no = 2, endsAt = now + 12 * 86400000 }, titles = o.titles or {}, title = o.title, titleSrc = o.titleSrc,
            exchange = o.exchange or { available = false }, spent = o.spent, hordes = o.hordes })
    end
    catalog(SHOP)

    T.section("points uses: the daily page's swap button")
    local PD = MQ.PageDaily
    local dp = newPage()
    state({ swaps = 1, paid = 0 })
    PD.layout(dp)
    local s1 = btn(dp, "q1swap")
    check(s1 ~= nil and s1.opts.title == "IGUI_MQ_UI_Swap" and s1.pay == nil, "a free swap left: Swap quest, no price")
    press(s1)
    C.state.spendSeq = 6   -- a state comes while the question is open
    answer(true)
    check(lastSent().command == "swap" and lastSent().args.slot == 1 and lastSent().args.pay == nil,
        "free swap: asks (progress) and sends swap without pay")
    check(lastSent().args.seq == 5 and lastSent().args.at == now - 1000, "it is the request for the screen pressed on (seq, at)")
    settle(dp)
    -- a swap that needs no question (free, no progress): it names the quest shown (at) and the state's spendSeq
    local fn = #T.clientSent
    press(btn(dp, "q2swap"))
    check(#T.clientSent == fn + 1 and lastSent().command == "swap" and lastSent().args.slot == 2
        and lastSent().args.at == now - 2000 and lastSent().args.seq == 6, "a free swap without a question: swap { slot, at, seq }")
    settle(dp)
    state({ swaps = 0, paid = 1 })
    PD.layout(dp)
    s1 = btn(dp, "q1swap")
    local s2 = btn(dp, "q2swap")
    check(s1 ~= nil and s1.opts.title == "IGUI_MQ_UI_SwapPay|50" and s2 ~= nil, "free ones used: Swap quest (50 points)")
    local sent0 = #T.clientSent
    press(s1)
    local d = dialogs[#dialogs]
    check(#T.clientSent == sent0 and d ~= nil and d.title == "IGUI_MQ_UI_SwapPayTitle|50" and d.danger == true
        and string.find(d.text, "IGUI_MQ_UI_SwapPayAsk|", 1, true) ~= nil
        and string.find(d.text, "IGUI_MQ_UI_SwapPayLeft|1,240|1,190|1", 1, true) ~= nil and d.confirmText == "IGUI_MQ_UI_SwapPayGo|50",
        "a paid swap asks first: the price in the title, the progress lost, balance before / after, swaps left; danger with progress")
    answer(false)
    check(#T.clientSent == sent0, "No sends nothing")
    press(s1)
    answer(true)
    check(lastSent().command == "swap" and lastSent().args.slot == 1 and lastSent().args.pay == 50, "Yes sends swap { slot, pay = 50 }")
    push("result", { ok = false, code = "PRICE_CHANGED", command = "swap", requestId = lastSent().args.requestId })
    check(toasts[#toasts].title == nil, "a one-sentence toast has no title line (the framework would show the sentence twice)")
    check(toasts[#toasts].message == "IGUI_MQ_Code_PRICE_CHANGED" and dp.swapRid == nil and dp.dirty,
        "PRICE_CHANGED: the toast says so and the page lays out again")
    settle(dp)
    -- no answer: nothing is sent again. The player asks again, and what goes out on yes is the request for the
    -- screen the question was asked on, also when the state of the first request comes while the question is open
    press(s1)
    answer(true)
    local firstRid = lastSent().args.requestId
    check(lastSent().args.at == now - 1000 and lastSent().args.seq == C.spendSeq(), "a paid swap names the quest shown and the state's spendSeq")
    T.advance(10000)
    T.tick(6)
    check(toasts[#toasts].message == "IGUI_MQ_UI_ExNoReply" and dp.swapRid == nil, "no reply: says so")
    local dn, sn = #dialogs, #T.clientSent
    press(s1)
    check(#dialogs == dn + 1 and #T.clientSent == sn, "pressed again: the question again, nothing sent by itself")
    local asked = C.spendSeq()
    C.state.spendSeq = asked + 1   -- the first request did run: its state comes while the question is open
    answer(true)
    check(#T.clientSent == sn + 1 and lastSent().args.requestId ~= firstRid and lastSent().args.seq == asked,
        "yes on a question asked before that state: a new request with the old spendSeq (the server answers STALE)")
    push("result", { ok = false, code = "STALE", command = "swap", requestId = lastSent().args.requestId })
    check(toasts[#toasts].message == "IGUI_MQ_Code_STALE" and dp.swapRid == nil and dp.dirty, "STALE: the toast says the screen was old")
    settle(dp)
    state({ swaps = 0, paid = 1 })
    PD.layout(dp)
    s1, s2 = btn(dp, "q1swap"), btn(dp, "q2swap")
    -- a spend from another page still waits for its reply: yes sends nothing, and says so
    local waiting = C.sendSpend("buyShield", { pay = 200 }, function() end)
    local hn, htn = #T.clientSent, #toasts
    press(s2)
    answer(true)
    check(waiting ~= nil and #T.clientSent == hn and #toasts == htn + 1 and toasts[#toasts].message == "IGUI_MQ_Code_RATE_LIMITED"
        and dp.swapRid == nil, "yes while another spend waits: nothing is sent, a toast says to wait")
    settle(dp)
    press(s2)
    d = dialogs[#dialogs]
    check(d ~= nil and d.danger == false and string.find(d.text, "IGUI_MQ_UI_SwapPayAskNew|", 1, true) ~= nil,
        "no progress: a paid swap still asks, in the normal style")
    answer(false)
    state({ swaps = 0, paid = 0, balance = 30 })
    PD.layout(dp)
    check(btn(dp, "q1swap") == nil and drew(dp, "IGUI_MQ_UI_SwapShort|50|20"), "not enough points: no button, 'costs 50, 20 short'")
    state({ swaps = 0, paid = 3 })
    PD.layout(dp)
    check(btn(dp, "q1swap") == nil and drew(dp, "IGUI_MQ_UI_NoSwaps"), "paid swaps used up: 'no more swaps today'")
    state({ swaps = 0 })
    PD.layout(dp)
    check(btn(dp, "q1swap") == nil and drew(dp, "IGUI_MQ_UI_NoSwaps") and not drew(dp, "IGUI_MQ_UI_Shield"),
        "a state without day.paid / shieldLeft (no point sinks): the page as before")
    catalog(OFF)
    state({ swaps = 0, paid = 0 })
    PD.layout(dp)
    check(btn(dp, "q1swap") == nil and drew(dp, "IGUI_MQ_UI_NoSwaps"), "paid swaps off: 'no more swaps today'")
    catalog(SHOP)
    local narrow = newPage(300)
    state({ swaps = 0, paid = 0 })
    PD.layout(narrow)
    local nb, pin = btn(narrow, "q1swap"), btn(narrow, "q1pin")
    check(nb ~= nil and pin ~= nil and nb.x == D.PAD + 10 and nb.y >= pin.y + pin.height,
        "a swap button wider than 35 % of the card moves under the progress and Track")
    check(boxesClosed(dp), "daily page: every list box closed")

    T.section("points uses: the streak shield")
    state({ shield = 0, shieldLeft = 1 })
    PD.layout(dp)
    local sb = btn(dp, "shieldBuy")
    check(sb ~= nil and sb.opts.title == "IGUI_MQ_UI_ShieldBuy|200" and drew(dp, "IGUI_MQ_UI_ShieldNote|1")
        and drew(dp, "IGUI_MQ_UI_StreakRuleShield"), "for sale: the buy button, the rule, the streak rule mentions it")
    press(sb)
    d = dialogs[#dialogs]
    check(d.title == "IGUI_MQ_UI_ShieldAskTitle|200" and string.find(d.text, "IGUI_MQ_UI_BalanceAfter|1,240|1,040", 1, true) ~= nil,
        "buying asks first with the price and the balance after")
    answer(true)
    check(lastSent().command == "buyShield" and lastSent().args.pay == 200, "Yes sends buyShield { pay = 200 }")
    settle(dp)
    state({ shield = 0, shieldLeft = 1, balance = 120 })
    PD.layout(dp)
    check(btn(dp, "shieldBuy") == nil and drew(dp, "IGUI_MQ_UI_PointsShort|80"), "not enough points: no button, 80 points short")
    state({ shield = 0, shieldLeft = 0 })
    PD.layout(dp)
    check(btn(dp, "shieldBuy") == nil and drew(dp, "IGUI_MQ_UI_ShieldWeekUsed"), "this week's bought: next week, no button")
    state({ shield = 1, shieldLeft = 0, week = { "done", "shield", "done", "", "", "", "" } })
    PD.layout(dp)
    check(btn(dp, "shieldBuy") == nil and drew(dp, "IGUI_MQ_UI_ShieldChip") and drew(dp, "IGUI_MQ_UI_ShieldHeld")
        and drew(dp, "IGUI_MQ_UI_ShieldHeldNote"), "held: the chip, '1 day held', buy again once used")
    check(drew(dp, "lock"), "a shield day carries the lock icon, not only a color")
    catalog(OFF)
    PD.layout(dp)
    check(drew(dp, "IGUI_MQ_UI_ShieldHeld") and drew(dp, "IGUI_MQ_UI_StreakRule|"), "off but held: the card stays, the old rule")
    state({ shield = 0, shieldLeft = 1 })
    PD.layout(dp)
    check(not drew(dp, "IGUI_MQ_UI_Shield") and btn(dp, "shieldBuy") == nil, "off and none held: no card")
    catalog(SHOP)

    T.section("points uses: the Points page")
    local PE = MQ.PageExchange
    local function navHas(id)
        for _, g in ipairs(W.navGroups()) do
            for _, it in ipairs(g.items) do if it.id == id then return true end end
        end
        return false
    end
    catalog(OFF)
    state({})
    check(not PE.shown() and not navHas("exchange"), "every use off, no exchange, no history: no Points page in the nav")
    state({ spent = { { at = now, what = "swap", n = -50, ref = d1.tid } } })
    check(PE.shown() and navHas("exchange"), "a spend in the history keeps the page")
    state({ hordes = { on = true, paid = { on = true, pts = 600 } } })
    check(PE.shown(), "sponsored hordes on: the page shows")
    catalog({ swap = { enabled = false }, shield = { enabled = false }, titles = SHOP.titles })
    state({})
    check(PE.shown(), "point titles on: the page shows")
    catalog(SHOP)
    local ep = newPage()
    local selected = nil
    local realSelect = W.select
    W.select = function(id) selected = id end
    state({ balance = 2760, titles = { "spend_1" }, title = "spend_1", hordes = { on = true, paid = { on = true, pts = 600 } },
        exchange = { available = true, enabled = true, rate = 1, perDay = 100, used = 0, min = 10, queued = 20, hist = {} } })
    PE.layout(ep)
    local primary = 0
    for _, b in pairs(ep.pool.items) do if b.visible ~= false and b.style == "primary" then primary = primary + 1 end end
    check(btn(ep, "useSwap") and btn(ep, "useShield") and btn(ep, "useHorde") and btn(ep, "exchange")
        and btn(ep, "exchange").style == "primary" and primary == 1, "uses: one row each, Exchange... the page's only primary button")
    check(drew(ep, "IGUI_MQ_UI_PointsSpendNote") and drew(ep, "IGUI_MQ_UI_ExQueuedNote|20"), "balance note; the queued points note")
    press(btn(ep, "useHorde"))
    local toHordes = selected
    press(btn(ep, "useSwap"))
    check(toHordes == "hordes" and selected == "daily", "the go buttons open their page through Window.select")
    check(btn(ep, "tb:spend_1") == nil and btn(ep, "tw:spend_1") == nil and drew(ep, "IGUI_MQ_UI_TitleWorn"), "owned and worn: In use")
    check(btn(ep, "tb:spend_2") ~= nil and btn(ep, "tb:s2_patron") ~= nil and drew(ep, "IGUI_MQ_UI_TitleSeasonOnly|"),
        "affordable: Get this title; this season's patron says season only")
    check(btn(ep, "tb:spend_3") == nil and drew(ep, "IGUI_MQ_UI_PointsShort|740") and drew(ep, "IGUI_MQ_UI_PointsShort|2,240"),
        "too dear: no button, how many points short")
    press(btn(ep, "tb:spend_2"))
    d = dialogs[#dialogs]
    check(d.title == "IGUI_MQ_UI_TitleBuyAsk|2,000|IGUI_MQ_Title_spend_2" and d.confirmText == "IGUI_MQ_UI_TitleBuy"
        and string.find(d.text, "IGUI_MQ_UI_TitleBuyNote", 1, true) and string.find(d.text, "IGUI_MQ_UI_BalanceAfter|2,760|760", 1, true),
        "buying a title asks with the price, the no-refund note and the balance after")
    answer(true)
    check(lastSent().command == "buyTitle" and lastSent().args.id == "spend_2" and lastSent().args.pay == 2000,
        "Yes sends buyTitle { id, pay }")
    settle(ep)
    state({ balance = 2760, titles = { "spend_1" } })
    PE.layout(ep)
    local wear = btn(ep, "tw:spend_1")
    check(wear ~= nil and btn(ep, "exchange") == nil, "owned, not worn: Wear; no exchange row when exchange is off")
    press(wear)
    check(lastSent().command == "title" and lastSent().args.id == "spend_1" and lastSent().args.seq == nil,
        "Wear sends title { id }: wearing is not a spend (no seq)")
    settle(ep)
    check(drew(ep, "IGUI_MQ_UI_PointsLogEmpty") and boxesClosed(ep), "no history: the empty line; every list box closed")
    W.select = realSelect

    T.section("points uses: the merged history")
    local hist, spent = {}, {}
    for i = 1, 6 do hist[i] = { at = now - i * 2000, amount = 10 * i, coins = 10 * i, state = i == 1 and "queued" or "paid" } end
    for i = 1, 7 do spent[i] = { at = now - i * 2000 + 1000, what = i % 2 == 0 and "swap" or "hordeRefund", n = i % 2 == 0 and -50 or 150 } end
    local log = C.pointsLog({ exchange = { hist = hist }, spent = spent })
    local sorted = #log == 10
    for i = 2, #log do if log[i].at > log[i - 1].at then sorted = false end end
    check(sorted and log[1].spent == spent[1] and log[2].ex == hist[1] and log[10].ex == hist[5],
        "exchanges and spends merged newest first, 10 at most (the 3 oldest dropped)")
    state({ exchange = { available = false, hist = hist }, spent = spent, titles = {} })
    PE.layout(ep)
    check(drew(ep, "IGUI_MQ_UI_LogSwap") and drew(ep, "+150") and drew(ep, "-50") and drew(ep, "IGUI_MQ_UI_ExQueued")
        and drew(ep, "IGUI_MQ_UI_LogExchange|10"), "rows: spends and refunds with their sign, exchanges with their state")
    catalog(OFF)
    PE.layout(ep)
    check(drew(ep, "IGUI_MQ_UI_UsesEmpty") and not drew(ep, "IGUI_MQ_UI_ShopTitles") and boxesClosed(ep),
        "every use off, history only: the uses box says none, no title list; boxes closed")
    catalog(SHOP)

    T.section("points uses: title sources and My titles")
    local rows = D.titleSources(C.defs().allAch, C.defs().cfg, 2)
    local shop = {}
    for _, r in ipairs(rows) do if r.group == "shop" then shop[#shop + 1] = r end end
    check(#shop == 5 and shop[1].id == "spend_1" and shop[1].cond == "IGUI_MQ_UI_TitleCondShop|1,000" and shop[5].id == "s2_patron"
        and not shop[1].off, "the admin title list: a Point titles group, the four in order then the season's, 'get it for N points'")
    catalog({ swap = SHOP.swap, shield = SHOP.shield, titles = { enabled = false, season = 0, list = SHOP.titles.list } })
    rows = D.titleSources(C.defs().allAch, C.defs().cfg, 2)
    local off, patron = true, false
    for _, r in ipairs(rows) do
        if r.group == "shop" then off = off and r.off == true end
        if r.id == "s2_patron" then patron = true end
    end
    check(off and not patron, "titles not sold: the rows say off; season price 0: no season title")
    catalog(SHOP)
    local sp = D.seasonTitle("s1_patron", C.defs().cfg)
    check(sp ~= nil and sp.group == "shop" and D.titleText("s1_patron") == "IGUI_MQ_Title_season_patron|1",
        "an older season's patron title still has a source and its name")
    local rp = newPage()
    state({ titles = { "spend_2" }, titleSrc = { spend_2 = "shop:spend_2" } })
    MQ.PageRecords.layout(rp)
    check(drew(rp, "IGUI_MQ_UI_TitleCondShopOwned") and not drew(rp, "IGUI_MQ_UI_TitleNoSource"),
        "My titles: a bought title says it was bought with points")

    T.section("points uses: Sponsor a horde on the Hordes page")
    local PH, X = MQ.PageHordes, MQ.PledgeDialog
    local hp = newPage()
    local paid = { on = true, pts = 600, minPledge = 50, rewardPct = 50, leadMin = 15, left = 1 }
    state({ hordes = { on = true, paid = paid } })
    PH.layout(hp)
    local pb = btn(hp, "pledge")
    check(pb ~= nil and pb.opts.title == "IGUI_MQ_UI_FundStart" and drew(hp, "IGUI_MQ_UI_FundLeftToday|1")
        and drew(hp, "IGUI_MQ_UI_FundIdle|600|15|300"), "no fund: hordes left today, the rule with the most it pays, Start a fund...")
    paid.cap = 200
    state({ hordes = { on = true, paid = paid } })
    PH.layout(hp)
    check(drew(hp, "IGUI_MQ_UI_FundIdle|600|15|200"), "the server's cap (a lower preset cap) is what the rule promises")
    paid.cap = nil
    state({ hordes = { on = true, paid = paid } })
    PH.layout(hp)
    pb = btn(hp, "pledge")
    press(pb)
    check(X.visible() and X.text == "100" and X.win.title == "IGUI_MQ_UI_FundStartTitle", "the dialog opens with min(left, 100, balance)")
    -- the dialog redraws with every state: Submit names the spendSeq of the state shown as it is pressed
    C.state.spendSeq = 9
    X.onText("150")
    press(X.pool.items.submit)
    check(lastSent().command == "pledge" and lastSent().args.n == 150 and lastSent().args.total == 600 and lastSent().args.seq == 9,
        "submit sends pledge { n, total, seq }")
    push("result", { ok = true, command = "pledge", requestId = lastSent().args.requestId, n = 150 })
    check(not X.visible() and toasts[#toasts].message == "IGUI_MQ_UI_FundPledged|150", "the reply closes it: what was taken")
    state({ hordes = { on = true, paid = { on = true, pts = 600, minPledge = 50, left = 0 } } })
    PH.layout(hp)
    check(btn(hp, "pledge") == nil and drew(hp, "IGUI_MQ_UI_FundDayUsed"), "today's used up: says so, no button")
    state({ balance = 20, hordes = { on = true, paid = paid } })
    PH.layout(hp)
    check(btn(hp, "pledge") == nil and drew(hp, "IGUI_MQ_UI_PointsShort|30"), "less than the least pledge: no button, 30 short")
    local fund = { total = 450, pts = 600, n = 3, mine = 150, expireAt = now + 12 * 60000, state = "open" }
    state({ hordes = { on = true, paid = { on = true, pts = 700, minPledge = 50, left = 1 }, fund = fund } })
    PH.layout(hp)
    pb = btn(hp, "pledge")
    check(pb ~= nil and pb.opts.title == "IGUI_MQ_UI_FundPledge" and drew(hp, "IGUI_MQ_UI_FundOpen")
        and drew(hp, "IGUI_MQ_UI_FundProgress|450|600") and drew(hp, "IGUI_MQ_UI_FundOpenBody|3|150") and drew(hp, "IGUI_MQ_UI_FundExpires|"),
        "fund open: progress of the fund's own target, sponsors and mine, when it ends, Sponsor...")
    press(pb)
    local fill = X.pool.items.fill
    check(X.win.title == "IGUI_MQ_UI_FundPledgeTitle" and fill ~= nil and fill.visible ~= false and fill.opts.title == "IGUI_MQ_UI_FundFill|150",
        "Fill the remaining 150")
    X.onText("10")
    check(X.pool.items.submit.enabled == false and drew({ canvas = X.canvas }, "IGUI_MQ_UI_FundMin|50"), "below the least: says so, cannot send")
    local bal, num = C.state.points.balance, MQ.Draw.num
    check(drew({ canvas = X.canvas }, "IGUI_MQ_UI_FundHint|50|" .. num(bal) .. "|" .. num(bal)),
        "an amount that cannot go: the balance line does not say points leave")
    X.onText("200")
    check(X.pool.items.submit.enabled == false and drew({ canvas = X.canvas }, "IGUI_MQ_UI_FundMax|150"), "more than it needs: says so")
    press(fill)
    check(drew({ canvas = X.canvas }, "IGUI_MQ_UI_FundHint|50|" .. num(bal) .. "|" .. num(bal - 150)), "one that can go: balance before and after")
    press(X.pool.items.submit)
    check(lastSent().command == "pledge" and lastSent().args.n == 150 and lastSent().args.total == 600,
        "the fund's target goes as total, not the changed setting")
    -- closing and opening the dialog again while that pledge waits for its reply does not let a second one out
    local pn = #T.clientSent
    X.close()
    press(pb)
    press(X.pool.items.submit)
    check(#T.clientSent == pn and X.pool.items.submit.enabled == false, "opened again while one is out: nothing more is sent")
    push("result", { ok = false, code = "FUND_FULL", command = "pledge", requestId = lastSent().args.requestId })
    check(X.visible() and toasts[#toasts].message == "IGUI_MQ_Code_FUND_FULL" and X.pool.items.submit.enabled == true,
        "a refusal says why and keeps the dialog open to try again")
    X.close()
    fund.state, fund.n, fund.total = "ready", 4, 600
    state({ hordes = { on = true, paid = paid, fund = fund } })
    PH.layout(hp)
    check(btn(hp, "pledge") == nil and drew(hp, "IGUI_MQ_UI_FundFull") and drew(hp, "IGUI_MQ_UI_FundFullBody|4|600")
        and drew(hp, "IGUI_MQ_UI_FundFullSoon"), "fund full: who filled it and that it is announced next, no button")
    state({ hordes = { on = true, paid = paid, cur = { id = 3, state = "announced", name = "Gas", x = 1, y = 2, kinds = {},
        startMs = now + 600000, paid = true, sponsorN = 4, capPts = 300 } } })
    PH.layout(hp)
    check(drew(hp, "IGUI_MQ_Horde_PaidChip") and drew(hp, "IGUI_MQ_Horde_PaidLine|4|300"), "the sponsored horde: the chip and the line in the banner")
    PD.layout(dp)
    check(drew(dp, "IGUI_MQ_Horde_PaidChip") and drew(dp, "IGUI_MQ_Horde_PaidLine|4|300"), "the daily page banner shows the same")
    local q = C.pledgeQuote({ hordes = { paid = { on = false, pts = 600 } } }, "100")
    local qd = C.pledgeQuote({ points = { balance = 500 }, hordes = { paid = { on = true, pts = 600, left = 0 } } }, "100")
    local qf = C.pledgeQuote({ points = { balance = 500 }, hordes = { paid = { on = true, pts = 600, left = 1 },
        fund = { pts = 600, total = 600, state = "ready" } } }, "100")
    check(q.reason == "FUND_OFF" and qd.reason == "FUND_DAY" and qf.reason == "FUND_FULL", "pledge quote: off, today's used, full")

    T.section("points uses: toasts")
    local E = MQ.Entry
    local t1, b1 = E.toastText({ kind = "horde", ev = "fund", total = 150, pts = 600, expireAt = now + 30 * 60000 })
    check(t1 == "IGUI_MQ_Horde_Title_fund" and b1 == "IGUI_MQ_Horde_FundBody|150|600|30", "a fund started: where it stands, minutes left")
    local _, b2 = E.toastText({ kind = "horde", ev = "soon", name = "Gas", startMs = now + 900000, kinds = {}, waves = 1,
        sponsors = { names = { "bob", "carol" }, anon = 2 }, capPts = 300 })
    check(string.find(b2, "IGUI_MQ_Horde_SponsorsN|bob" .. "IGUI_MQ_UI_ListSep" .. "carol|4", 1, true) == 1 + #"IGUI_MQ_Horde_Join|",
        "a sponsored warning names the shown sponsors and counts the anonymous ones")
    local _, b3 = E.toastText({ kind = "horde", ev = "open", name = "Gas", kinds = {}, sponsors = { names = {}, anon = 3 } })
    local _, b4 = E.toastText({ kind = "horde", ev = "soon", name = "Gas", startMs = now + 900000, kinds = {} })
    check(string.find(b3, "IGUI_MQ_Horde_SponsorsAnon|3", 1, true) ~= nil and string.find(b4, "Sponsors", 1, true) == nil,
        "all anonymous: only the count; a horde nobody paid for: as before")
    local r1 = E.toastText({ kind = "fundRefund", pts = 150, why = "expired" })
    local r2 = E.toastText({ kind = "fundRefund", pts = 150, why = "spots" })
    local r3 = E.toastText({ kind = "fundRefund", pts = 150, why = "file" })
    local r4 = E.toastText({ kind = "fundRefund", pts = 150, why = "ended" })
    check(r1 == "IGUI_MQ_UI_FundRefund|150" and r2 == "IGUI_MQ_UI_FundRefundFail|150" and r3 == r2 and r4 == r2,
        "refund toasts: not filled, or the horde could not start or ended before a zombie came")
    check(D.codeText("PRICE_CHANGED") == "IGUI_MQ_Code_PRICE_CHANGED", "new codes read their own text")
    check(#errors == 0, "points uses ran clean " .. tostring(errors[1]))

    for k, v in pairs(saved) do _G[k] = v end
end
