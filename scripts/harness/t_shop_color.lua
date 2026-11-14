-- Title colour for rent (Shop.titleColor; contract temp/plan-group-play-1114/spec.md B2, plan points-play 1112 section
-- 4). server(T): the rent and its refusals, back to gold for free, renting again counting from now, the titles push
-- with the colour and its end, the notice a day before the end (once per rent), a spend request taken once.
-- client(T, kit): the colour by the server clock (gold after the end), the chat markup cached by title and colour,
-- the Points page section and its questions. kit: t_contracts.lua's client fixtures.
local DAY = 86400000
local M = {}

function M.server(T)
    local function section(name, fn)
        T.section("title colour: " .. name)
        local ok, err = pcall(fn)
        if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
    end
    local function boot()
        local Q = T.boot({ sandbox = { AdminRoles = "admin" } })
        T.tick(2)
        return Q
    end
    local function rent(p, c, pay) return T.cmd(p, "titleColor", { c = c, pay = pay }) end
    local function told(p)
        local n = 0
        for _, t in ipairs(T.sentTo(p, "toast")) do if t.kind == "colorSoon" then n = n + 1 end end
        return n
    end

    section("rent, the refusals, back to gold, again from now", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        T.cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 1000, "admin", "t")
        Q.Store.grantTitle(acc, "spend_1", "t")
        T.cmd(p, "title", { id = "spend_1" })
        local season, total = acc.points.season, acc.points.total
        T.check(rent(p, "pink", 300).code == "BAD_ARGS" and rent(p, "gold", 300).code == "BAD_ARGS", "not one of the five: BAD_ARGS")
        T.check(rent(p, "blue", 299).code == "PRICE_CHANGED" and acc.points.balance == 1000, "not the price: PRICE_CHANGED")
        T.check(rent(p, "", 300).code == "BAD_ARGS" and acc.points.balance == 1000, "back to gold names no price")
        T.clearOutbox()
        local r = rent(p, "blue", 300)
        local tc = acc.titleColor
        T.check(r and r.ok and acc.points.balance == 700 and tc.c == "blue" and tc.untilMs == T.now + 7 * DAY,
            "blue: 300 taken, 7 days from now")
        T.check(acc.points.season == season and acc.points.total == total, "season and total unchanged")
        local b = T.lastOf(p, "titles")
        T.check(b and b.u == "alice" and b.t == "spend_1" and b.c == "blue" and b.cu == tc.untilMs, "everyone gets the title, the colour and its end")
        T.check(acc.spent[1].what == "color" and acc.spent[1].n == -300 and acc.spent[1].ref == "blue"
            and Q.Report.row(T.now).spent.color == 300, "points history and report")
        T.check(T.lastOf(p, "state").titleColor.c == "blue", "the state carries it")
        T.advance(3 * DAY)
        r = rent(p, "green", 300)
        T.check(r.ok and acc.points.balance == 400 and acc.titleColor.c == "green" and acc.titleColor.untilMs == T.now + 7 * DAY,
            "another colour before the end: from now, 300 again")
        T.check(Q.Config.apply({ { op = "set", path = "shop.color.enabled", value = false } }, "t", "admin"), "off")
        T.check(rent(p, "red", 300).code == "SHOP_OFF" and acc.titleColor.c == "green", "off: SHOP_OFF")
        T.clearOutbox()
        r = rent(p, "", 0)
        b = T.lastOf(p, "titles")
        T.check(r.ok and acc.titleColor == nil and acc.points.balance == 400 and b and b.c == nil and b.t == "spend_1",
            "back to gold: free, also while off; the push has no colour")
        T.check(Q.Config.apply({ { op = "set", path = "shop.color.enabled", value = true } }, "t", "admin"), "on")
        acc.points.balance = 200
        T.check(rent(p, "red", 300).code == "NOT_ENOUGH_POINTS" and acc.titleColor == nil and acc.points.balance == 200,
            "200 points: NOT_ENOUGH_POINTS")
        T.check(not Q.Config.apply({ { op = "set", path = "shop.color.days", value = 91 } }, "t", "admin")
            and not Q.Config.apply({ { op = "set", path = "shop.color.pts", value = 0 } }, "t", "admin"), "out of range: refused")
    end)

    section("the titles push, the notice before the end", function()
        local Q = boot()
        local a, b = T.player{ name = "alice" }, T.player{ name = "bob" }
        T.cmd(a, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 1000, "admin", "t")
        Q.Store.grantTitle(acc, "spend_1", "t")
        T.cmd(a, "title", { id = "spend_1" })
        rent(a, "purple", 300)
        T.cmd(b, "hello")
        local function fullOf(pl)
            local out = nil
            for _, m in ipairs(T.sentTo(pl, "titles")) do if m.full then out = m end end
            return out
        end
        local full = fullOf(b)
        T.check(full.full and full.map.alice == "spend_1" and full.colors.alice.c == "purple" and full.colors.alice.cu == acc.titleColor.untilMs,
            "hello: the full map with the colours")
        T.check(told(a) == 0, "rented now: no notice")
        T.advance(6 * DAY + 60000)
        T.cmd(a, "hello")
        T.check(told(a) == 1, "a day or less left at hello: told once")
        T.cmd(a, "hello")
        T.check(told(a) == 1, "the next hello: not again")
        T.advance(DAY)
        T.cmd(b, "hello")
        full = fullOf(b)
        T.check(full.map.alice == "spend_1" and (full.colors == nil or full.colors.alice == nil), "ended: no colour sent")
        rent(a, "white", 300)
        T.advance(6 * DAY + 60000)
        T.cmd(a, "hello")
        T.check(told(a) == 2, "a new rent: its own notice")
    end)

    section("a spend request is run at most once", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        T.cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 1000, "admin", "t")
        local seq = acc.spendSeq or 0
        local r1 = T.cmd(p, "titleColor", { c = "blue", pay = 300, seq = seq })
        local r2 = T.cmd(p, "titleColor", { c = "blue", pay = 300, seq = seq })
        T.check(r1.ok and r2.code == "STALE" and acc.points.balance == 700, "the same screen twice: 300 taken once")
    end)
end

function M.client(T, kit)
    local check = T.check
    local MQ = MinidoracatQuest
    local C, D, Ti, E = MQ.Client, MQ.Draw, MQ.Titles, MQ.Entry
    local state, press, answer, btn, drew, lastSent = kit.state, kit.press, kit.answer, kit.btn, kit.drew, kit.lastSent

    T.section("title colour: chat and over the head")
    state({})
    local now = C.serverNow()
    kit.push("titles", { full = true, map = { bob = "hero" }, colors = { bob = { c = "blue", cu = now + 1000 } } })
    check(Ti.colorOf("bob") == D.TITLE_RGB.blue and Ti.colorOf("carol") == D.TITLE_RGB.gold, "the rented colour; gold for the rest")
    local line = Ti.decorateLine("[Local][bob]: hi", "bob")
    check(string.find(line, "<PUSHRGB:" .. D.TITLE_RGB.blue.rgb .. ">", 1, true) ~= nil, "chat: the title in its colour")
    T.advance(1500)
    check(Ti.colorOf("bob") == D.TITLE_RGB.gold, "past its end by the server clock: gold, the server sends nothing")
    line = Ti.decorateLine("[Local][bob]: hi", "bob")
    check(string.find(line, "<PUSHRGB:" .. D.TITLE_RGB.gold.rgb .. ">", 1, true) ~= nil and Ti.chatMark["hero|gold"] ~= nil
        and Ti.chatMark["hero|blue"] ~= nil, "chat: gold again, the markup cached per title and colour")
    kit.push("titles", { u = "bob", t = "hero", c = "red", cu = C.serverNow() + DAY })
    check(Ti.colorOf("bob") == D.TITLE_RGB.red, "a change: the new colour")
    kit.push("titles", { u = "bob", t = "hero" })
    check(Ti.colorOf("bob") == D.TITLE_RGB.gold and Ti.colorBy.bob == nil, "back to gold: the entry goes")

    T.section("title colour: the Points page")
    local pg = kit.newPage()
    local until5 = C.serverNow() + 5 * DAY
    state({ balance = 1000, title = "spend_1", titles = { "spend_1" }, titleColor = { c = "blue", untilMs = until5 } })
    MQ.PageExchange.layout(pg)
    check(drew(pg, "IGUI_MQ_UI_ColorHead") and drew(pg, "IGUI_MQ_UI_ColorLeft|IGUI_MQ_UI_Color_blue|IGUI_MQ_UI_Days|5")
        and drew(pg, "IGUI_MQ_UI_ChatTitle|IGUI_MQ_Title_spend_1"), "the section: the colour and days left, the preview")
    check(btn(pg, "col:blue") == nil and drew(pg, "IGUI_MQ_UI_TitleWorn") and btn(pg, "col:gold") and btn(pg, "col:green")
        and btn(pg, "col:white") and drew(pg, "IGUI_MQ_UI_Color_purple") and drew(pg, "IGUI_MQ_UI_ColorNote|300|IGUI_MQ_UI_Days|7"),
        "each row a name and a button; the one in use says so")
    press(btn(pg, "col:green"))
    local d = kit.dialogs[#kit.dialogs]
    check(d.title == "IGUI_MQ_UI_ColorAsk|IGUI_MQ_UI_Color_green" and d.confirmText == "IGUI_MQ_UI_ColorUse|IGUI_MQ_UI_Color_green"
        and string.find(d.text, "IGUI_MQ_UI_ColorAskNote|300|IGUI_MQ_UI_Days|7", 1, true)
        and string.find(d.text, "IGUI_MQ_UI_ColorAskRestart|IGUI_MQ_UI_Days|7", 1, true)
        and string.find(d.text, "IGUI_MQ_UI_BalanceAfter|1,000|700", 1, true), "a change asks: 300, 7 days, from now, the balance after")
    answer(true)
    check(lastSent().command == "titleColor" and lastSent().args.c == "green" and lastSent().args.pay == 300
        and lastSent().args.seq == C.spendSeq(), "Yes sends titleColor { c, pay, seq }")
    C.pending = {}
    pg.colorRid = nil
    press(btn(pg, "col:gold"))
    d = kit.dialogs[#kit.dialogs]
    check(d.title == "IGUI_MQ_UI_ColorBackAsk" and string.find(d.text, "IGUI_MQ_UI_ColorBackNote", 1, true), "back to gold asks too")
    answer(true)
    check(lastSent().args.c == "" and lastSent().args.pay == 0, "back to gold: titleColor { c = \"\", pay = 0 }")
    C.pending = {}
    pg.colorRid = nil
    state({ balance = 100, titleColor = { c = "blue", untilMs = C.serverNow() - 1 } })
    MQ.PageExchange.layout(pg)
    check(drew(pg, "IGUI_MQ_UI_ColorNoTitle") and btn(pg, "col:green") == nil and drew(pg, "IGUI_MQ_UI_PointsShort|200")
        and btn(pg, "col:gold") == nil and not drew(pg, "IGUI_MQ_UI_ColorLeft"),
        "no title: says so; an ended colour is gold; 100 points: how many short, no button")
    kit.push("catalog", { rev = 3, packs = {}, overrides = { shop = { color = { enabled = false } } } })
    MQ.PageExchange.layout(pg)
    check(not drew(pg, "IGUI_MQ_UI_ColorHead"), "off and none running: no section")
    state({ titleColor = { c = "blue", untilMs = until5 } })
    MQ.PageExchange.layout(pg)
    check(drew(pg, "IGUI_MQ_UI_ColorHead") and btn(pg, "col:gold") and btn(pg, "col:green") == nil,
        "off with one running: back to gold only")
    kit.push("catalog", { rev = 4, packs = {}, overrides = {} })
    local t, body = E.toastText({ kind = "colorSoon", c = "blue", untilMs = until5 })
    check(t == "IGUI_MQ_UI_ColorSoon" and string.find(body, "IGUI_MQ_UI_ColorSoonBody|IGUI_MQ_UI_Color_blue|", 1, true) == 1,
        "the notice names the colour and when it ends")
end

return M
