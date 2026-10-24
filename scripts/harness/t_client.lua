-- Client slice: state cache (state + delta merge), request matching and NO_REPLY, hello on the first tick and
-- after respawn, effective achievement definitions (overrides, difficulty, custom "c:", facade packs), the board
-- page state machine (0.6 s send gap, 5 s timeout, failure result), records timeout, the exchange quote limits,
-- toast texts, small formatters, and one SP round trip through the real server.
return function(T)
    local check = T.check
    local MQ = T.bootClient()
    local C, D, E = MQ.Client, MQ.Draw, MQ.Entry
    local K = MQ.Contract
    T.player({ name = "alice" })
    local function push(cmd, args) T.fire("OnServerCommand", K.MODULE, cmd, args) end
    local function lastSent() return T.clientSent[#T.clientSent] end
    local function sentCount(cmd)
        local n = 0
        for _, s in ipairs(T.clientSent) do if s.command == cmd then n = n + 1 end end
        return n
    end

    T.section("client: hello waits for the first tick, retries, respawn")
    T.fire("OnGameStart")
    check(sentCount("hello") == 0, "no hello inside OnGameStart")
    T.tick(1)
    check(sentCount("hello") == 1 and lastSent().args.protocol == K.PROTOCOL
        and K.validRequestId(lastSent().args.requestId), "first tick sends hello with protocol and requestId")
    T.advance(10000)
    T.tick(1)
    check(sentCount("hello") == 2, "no state 10 s after hello: asks again")
    push("state", { v = 1, user = "alice", now = T.now + 5000, unseen = 2, points = { season = 10, total = 20, balance = 30 },
        day = { quests = { { tid = "d_kill", prog = 1, target = 20, state = "active", pts = 15 },
            { tid = "d_craft", prog = 0, target = 5, state = "active", pts = 15 } }, swaps = 1, done = 0 },
        week = { quests = { { tid = "w_kill", prog = 3, target = 150, state = "active" } }, goalPart = 0 },
        goal = { stat = "zombie.kills", target = 100, progress = 10, reached = false },
        achv = {}, exchange = { available = true, enabled = true, rate = 2, perDay = 100, used = 30, min = 10 } })
    T.advance(20000)
    T.tick(1)
    check(sentCount("hello") == 2 and C.skew == 5000, "state stops the retries; server clock skew kept")
    T.fire("OnCreatePlayer", 0)
    check(sentCount("hello") == 3, "respawn (OnCreatePlayer 0 after start) sends hello again")

    T.section("client: delta merges into state")
    push("delta", { day = { [1] = { prog = 7 }, [2] = { prog = 5, state = "done" }, swaps = 0 },
        week = { [1] = { prog = 40 } }, goal = { progress = 60 }, points = { balance = 45 }, unseen = 0 })
    local s = C.state
    check(s.day.quests[1].prog == 7 and s.day.quests[1].target == 20 and s.day.quests[1].tid == "d_kill",
        "quest delta keeps other fields")
    check(s.day.quests[2].state == "done" and s.day.swaps == 0, "quest state and day scalar fields merged")
    check(s.week.quests[1].prog == 40 and s.goal.progress == 60 and s.goal.target == 100, "week and goal merged")
    check(s.points.balance == 45 and s.points.season == 10 and s.unseen == 0, "points merged per field, unseen replaced")
    E.onState()
    check(E.badge == 0 and E.status == nil, "dock badge follows unseen")
    push("delta", { unseen = 3 })
    check(E.badge == 3 and E.status ~= nil, "badge and status text are composed on change, not per frame")

    T.section("client: request matching and NO_REPLY")
    local got = {}
    local rid = C.send("swap", { slot = 1 }, function(r) got[#got + 1] = r end)
    check(lastSent().args.requestId == rid and C.isPending(rid), "mutation tracked by requestId")
    push("result", { ok = true, code = "OK", command = "title", requestId = rid })
    check(#got == 0, "reply for another command is not delivered")
    push("result", { ok = true, code = "OK", command = "swap", requestId = rid })
    check(#got == 1 and got[1].ok and not C.isPending(rid), "matching result delivered once")
    local late = {}
    C.send("prefs", { themes = "combat" }, function(r) late[#late + 1] = r end)
    T.advance(10000)
    T.tick(6)
    check(#late == 1 and late[1].code == "NO_REPLY", "10 s without a reply: NO_REPLY once")
    T.tick(20)
    check(#late == 1, "NO_REPLY only once")
    local adminSeen = {}
    C.on("admin", "test", function(p) adminSeen[#adminSeen + 1] = p end)
    C.send("admin", { op = "cfg.get" })
    T.advance(10000)
    T.tick(6)
    check(#adminSeen == 1 and adminSeen[1].code == "NO_REPLY" and adminSeen[1].op == "cfg.get",
        "admin without callback still reports NO_REPLY to admin listeners")
    C.off("admin", "test")

    T.section("client: effective achievement definitions")
    local cat = MQ.Catalog
    local a1, a2 = cat.achievements[1], cat.achievements[2]
    local base = C.defs()
    check(#base.achievements >= #cat.achievements - 0 and base.achById[a1.id] ~= nil, "built-ins present without a catalog push")
    push("catalog", { rev = 2, overrides = {
        achievements = { [a1.id] = { enabled = false }, [a2.id] = { tiers = { 10, 20, 30, 40, 50 }, pts = { 1, 2, 3, 4, 5 } } },
        custom = { mykills = { name = "Big hunt", cat = "combat", stat = "zombie.kills", tiers = { 5, 50 }, pts = { 5, 10 } },
            empty = { name = "x", cat = "combat", stat = "zombie.kills", tiers = {} } },
    }, packs = { { modId = "DoctorJob", stats = { ["DoctorJob:heal"] = { id = "DoctorJob:heal", nameKey = "IGUI_Doc_Heal" } },
        achievements = { { id = "DoctorJob:medic", cat = "job", stat = "DoctorJob:heal", tiers = { 1, 10 }, pts = { 5, 5 },
            nameKey = "IGUI_Doc_Medic" } }, boards = { { id = "DoctorJob:heal", cat = "job", stat = "DoctorJob:heal" } },
        quests = { { tid = "DoctorJob:triage", stat = "DoctorJob:heal", target = { 2, 4 }, pts = 10, nameKey = "IGUI_Doc_Triage" } } } } })
    local d = C.defs()
    check(d.achById[a1.id] == nil, "override enabled=false removes a built-in")
    check(#d.achById[a2.id].tiers == 5 and d.achById[a2.id].tiers[5] == 50 and d.achById[a2.id].pts[5] == 5,
        "override tiers and points replace the defaults")
    check(d.achById["c:mykills"] ~= nil and d.achById["c:mykills"].kind == "custom" and d.achById["c:empty"] == nil,
        "custom achievements get the c: prefix; ones without tiers are skipped")
    check(D.achName(d.achById["c:mykills"]) == "Big hunt", "custom names are plain text")
    check(d.achById["DoctorJob:medic"] ~= nil and d.stats["DoctorJob:heal"] ~= nil and d.boardById["DoctorJob:heal"] ~= nil,
        "facade pack achievements, stats and boards merged")
    check(D.questName({ tid = "DoctorJob:triage", target = 3 }) == "IGUI_Doc_Triage"
        and D.questName({ tid = "d_kill", target = 20 }) == "IGUI_MQ_Q_d_kill", "facade quest names use their nameKey")
    if MQ.Admin and MQ.Admin.questName then
        check(MQ.Admin.questName("DoctorJob:triage") == "IGUI_Doc_Triage", "admin panel quest names use the facade nameKey")
    end
    local defaultsKept = d.cfg.exchange ~= nil and d.cfg.exchange.perDay == cat.DEFAULTS.exchange.perDay
    check(defaultsKept, "sections without overrides keep the catalog defaults")
    push("catalog", { rev = 3, overrides = { difficulty = { preset = "hard", mult = 1.6 },
        custom = { mykills = { name = "Big hunt", cat = "combat", stat = "zombie.kills", tiers = { 5, 50, 120, 121 },
            pts = { 1, 1, 1, 1 } } } } })
    local t = C.defs().achById["c:mykills"].tiers
    check(t[1] == 8 and t[2] == 80 and t[3] == 190 and t[4] == 191, "difficulty scales thresholds like the server (" ..
        tostring(t[1]) .. "," .. tostring(t[2]) .. "," .. tostring(t[3]) .. "," .. tostring(t[4]) .. ")")
    local scaled = C.scale({ 100, 1000, 5000, 20000 }, 1.6)
    check(scaled[1] == 160 and scaled[2] == 1600 and scaled[3] == 8000 and scaled[4] == 32000, "C.scale 2 significant digits")
    check(C.scale({ 1, 1 }, 1)[2] == 2, "C.scale keeps tiers strictly increasing")

    T.section("client: achievement page model")
    local PA = MQ.PageAchievements
    local a = { id = "x", tiers = { 10, 100 }, pts = { 1, 2 }, scope = "life" }
    local m = PA.model(a, 1, { total = 500, life = 40 })
    check(m.nextTier == 2 and m.target == 100 and m.value == 40 and not m.maxed, "next tier from the life column for scope=life")
    check(PA.model(a, 2, nil).maxed and PA.model({ tiers = { 1 }, pts = { 1 }, hidden = true }, 0).hiddenLocked,
        "maxed and hidden-locked flags")

    T.section("client: board page state machine")
    local sent0 = sentCount("board")
    local e = C.requestBoard("kills", "season")
    check(e.status == "loading" and sentCount("board") == sent0 + 1 and lastSent().args.board == "kills"
        and lastSent().args.period == "season", "ask -> loading, sent at once")
    C.requestBoard("kills", "total")
    check(sentCount("board") == sent0 + 1, "second ask inside the 0.5 s server cooldown is queued, not dropped")
    T.tick(5)
    check(sentCount("board") == sent0 + 1, "still held at 0.5 s: the server would drop it")
    T.tick(1)
    check(sentCount("board") == sent0 + 2 and lastSent().args.period == "total", "queued ask goes out after the 0.6 s gap")
    push("board", { board = "kills", period = "season", status = "ok", rows = { { r = 1, n = "bob", v = 9 } }, me = nil })
    check(C.board("kills", "season").status == "ready" and C.board("kills", "season").data.rows[1].n == "bob", "rows -> ready")
    push("board", { board = "kills", period = "total", status = "ok", rows = {}, me = nil })
    check(C.board("kills", "total").status == "empty", "no rows and no me -> empty")
    e = C.requestBoard("kills", "season")
    check(e.status == "loading" and e.data ~= nil, "switching back: loading keeps the last data to draw")
    T.tick(25)
    T.advance(5000)
    T.tick(1)
    check(e.status == "error" and e.code == "NO_REPLY", "5 s without a reply -> error")
    C.requestBoard("kills", "season")
    T.tick(25)
    check(e.status == "loading", "retry -> loading")
    push("result", { ok = false, code = "BAD_BOARD", command = "board", requestId = lastSent().args.requestId })
    check(e.status == "error" and e.code == "BAD_BOARD", "failure result -> error with the code")
    local PB = MQ.PageBoards
    check(PB.periodFor({ periods = { "total" } }, "season") == "total" and PB.periodFor({ periods = { "season", "total" } },
        "season") == "season", "skill_total style boards fall back to all-time")

    T.section("client: records")
    C.requestRecords(true)
    check(lastSent().command == "records" and C.recordsSentAt ~= nil, "records asked")
    T.advance(5000)
    T.tick(1)
    check(C.recordsError == "NO_REPLY" and C.recordsSentAt == nil, "records timeout -> error state")
    C.requestRecords(true)
    push("records", { rows = { { stat = "zombie.kills", season = 3, life = 2, total = 9 } },
        points = { season = 1, total = 2, balance = 3 } })
    check(C.statRow("zombie.kills").total == 9 and C.recordsError == nil and C.state.points.balance == 3,
        "records indexed by stat; points refreshed")
    local before = sentCount("records")
    C.requestRecords(false)
    check(sentCount("records") == before, "fresh records are reused (no extra request)")

    T.section("client: exchange quote")
    local st = { points = { balance = 45 }, exchange = { available = true, enabled = true, rate = 2, perDay = 100, used = 30, min = 10 } }
    local q = C.exchangeQuote(st, "40")
    check(q.ok and q.coins == 80 and q.after == 5 and q.max == 45 and q.left == 70, "within limits: coins at the rate")
    check(C.exchangeQuote(st, "50").reason == "NOT_ENOUGH_POINTS", "above balance")
    st.points.balance = 500
    check(C.exchangeQuote(st, "0").max == 70 and C.exchangeQuote(st, "71").reason == "EXCHANGE_DAY_LIMIT",
        "all-in = min(balance, today's remaining)")
    check(C.exchangeQuote(st, "9").reason == "EXCHANGE_MIN" and C.exchangeQuote(st, "abc").reason == "EMPTY",
        "below minimum; non-number")
    st.exchange.available = false
    check(C.exchangeQuote(st, "20").reason == "EXCHANGE_OFF", "exchange unavailable")

    T.section("client: toasts and formatting")
    E.showBroadcast = false
    check(E.toastText({ kind = "broadcast", who = "bob", id = a2.id, tier = 3 }) == nil, "server-wide toasts can be turned off")
    E.showBroadcast = true
    check(E.toastText({ kind = "broadcast", who = nil, id = a2.id, tier = 3 }) ~= nil, "broadcast shown (anonymous ok)")
    local gt = getText
    getText = function(key, ...)
        local s = key
        for i = 1, select("#", ...) do s = s .. "|" .. tostring((select(i, ...))) end
        return s
    end
    local ok, head = pcall(E.toastText, { kind = "broadcast", a = "mei", id = a2.id, tier = 3 })
    local okQ, _, qbody = pcall(E.toastText, { kind = "quest", tid = "d_kill", target = 37, pts = 15 })
    getText = gt
    check(okQ and type(qbody) == "string" and string.find(qbody, "|37", 1, true) ~= nil,
        "a quest toast shows the target it carries (the cached list is stale while the window is closed)")
    check(ok and type(head) == "string" and string.find(head, "IGUI_MQ_UI_AnonReal|mei", 1, true) ~= nil,
        "the admins' copy names the anonymous achiever")
    check(E.toastText({ kind = "achvMany", ids = { a2.id, "c:mykills" }, n = 5 }) ~= nil
        and E.toastText({ kind = "exchange", state = "queued", coins = 10 }) ~= nil, "merged unlocks and exchange toasts")
    check(D.num(1234567) == "1,234,567" and D.num(0) == "0" and D.num(-1500) == "-1,500" and D.num(12.34) == "12.3",
        "number formatting")
    check(D.days(1) == "IGUI_MQ_UI_Day1" and D.days(5) == "IGUI_MQ_UI_Days" and D.duration(3600000) == "IGUI_MQ_UI_Hour1"
        and D.duration(2 * 86400000) == "IGUI_MQ_UI_Days", "1 day / 1 hour use the singular keys")
    local y, mo, dd, hh, mi, wd = D.civil(1790000000000)
    check(y == 2026 and mo == 9 and dd == 21 and hh == 22 and mi == 13 and wd == 1, "civil date at UTC+8")
    local PS = MQ.PageSettings
    local l = PS.toggle(PS.toggle(PS.toggle({}, "combat"), "farm"), "cook")
    check(#PS.toggle(l, "mech") == 3 and #PS.toggle(l, "farm") == 2, "preferences capped at 3, toggle removes")

    T.section("client: tracker rows, worn titles")
    local Hd, Ti = MQ.Hud, MQ.Titles
    local zk = C.defs().achById.zombie_kills
    local ts = { pins = { "d1", "w1", "a:zombie_kills", "d2", "d9" }, trk = { zombie_kills = { t = 1, v = 120 } },
        achv = { zombie_kills = 0 },
        day = { quests = { { tid = "d_kill", prog = 5, target = 20, state = "active", pts = 15 },
            { tid = "d_craft", prog = 5, target = 5, state = "done", pts = 15, ptsNow = 30 } } },
        week = { quests = { { tid = "w_kill", prog = 3, target = 150, state = "active" } } } }
    local rows = Hd.rows(ts, C.defs())
    check(#rows == 4 and rows[1].id == "d1" and rows[1].prog == 5 and rows[1].target == 20 and rows[2].id == "w1"
        and rows[4].id == "d2", "tracker: one row per pin in pin order; a pin naming nothing is skipped")
    check(rows[3].prog == 120 and rows[3].target == zk.tiers[2], "tracker: an achievement counts toward its next tier")
    check(rows[4].done and rows[4].pts == 30, "tracker: a done quest shows what it paid")
    ts.trk.zombie_kills.t = #zk.tiers
    check(#Hd.rows(ts, C.defs()) == 3, "tracker: a maxed achievement has no row")

    local gt2 = getText
    getText = function(key, a)
        if key == "IGUI_MQ_UI_ChatTitle" then return "(" .. tostring(a) .. ")" end
        return gt2(key, a)
    end
    local function mark(id)   -- D.titleText is the display name (the harness has no translations)
        local name = string.gsub(string.gsub(D.titleText(id), "<", "&lt;"), ">", "&gt;")
        return " <SPACE> <PUSHRGB:0.91,0.76,0.35> (" .. name .. ") <POPRGB> "
    end
    push("titles", { full = true, map = { bob = "<b>boss" } })
    local line = "<RGB:1,1,1>[12:00][Local][bob]: hi [bob]: x"
    local out = Ti.decorateLine(line, "bob")
    check(out == "<RGB:1,1,1>[12:00][Local][bob]" .. mark("<b>boss") .. ": hi [bob]: x" and not string.find(out, "<b>", 1, true),
        "chat: the title follows the author, escaped so it cannot open a rich-text command")
    check(Ti.decorateLine("[Local][carol]: hi", "carol") == "[Local][carol]: hi", "chat: an author without a title stays")
    push("titles", { u = "bob", t = "hero" })
    local msg = { text = "hi", getAuthor = function() return "bob" end, setText = function(self, t) self.text = t end,
        getTextWithPrefix = function(self) return "[Local][bob]: " .. self.text end }
    local px = Ti.wrap(msg)
    px:setText("* * *")
    check(px ~= msg and px:getAuthor() == "bob" and msg.text == "* * *"
        and px:getTextWithPrefix() == "[Local][bob]" .. mark("hero") .. ": * * *" and px.noSuch == nil,
        "chat: a titled author's message is wrapped; ISChat's other calls reach the real message")
    push("catalog", { rev = 90, overrides = { titles = { chat = false } } })
    check(Ti.wrap(msg) == msg and px:getTextWithPrefix() == "[Local][bob]: * * *",
        "chat: the server switch off: no wrapper, and kept lines drop the title on the next refresh")
    push("catalog", { rev = 91, overrides = {} })
    E.showChatTitles = false
    check(Ti.wrap(msg) == msg, "chat: the MOD option off: no wrapper")
    E.showChatTitles = true
    push("titles", { u = "bob" })
    check(Ti.byUser.bob == nil and Ti.wrap(msg) == msg, "chat: a title taken off is gone")
    getText = gt2

    -- over the head: the vanilla name rules decide whose title is drawn
    local keep = { "getCore", "getTextManager", "getServerOptions", "Core", "isoToScreenX", "isoToScreenY", "getMouseX",
        "getMouseY", "screenToIsoX", "screenToIsoY", "UIFont" }
    local kept = {}
    for _, n in ipairs(keep) do kept[n] = _G[n] end
    local opt, showSelf, drawn = { DisplayUserName = true }, true, {}
    getServerOptions = function() return { getBoolean = function(_, k) return opt[k] end } end
    getCore = function() return { isShowYourUsername = function() return showSelf end, getZoom = function() return 1 end } end
    getTextManager = function()
        return { getFontHeight = function() return 16 end,
            DrawStringCentre = function(_, _, _, _, s, r) if r ~= 0 then drawn[#drawn + 1] = s end end }
    end
    Core = { getTileScale = function() return 2 end }
    isoToScreenX = function(_, x) return x * 100 end
    isoToScreenY = function(_, _, y) return y * 100 end
    screenToIsoX = function(_, sx) return sx / 100 end
    screenToIsoY = function(_, _, sy) return sy / 100 end
    UIFont = UIFont or { Small = 1 }
    local mouseX, mouseY = 0, 0
    getMouseX, getMouseY = function() return mouseX end, function() return mouseY end
    local function seeable(p)
        p.speaking, p.invisible = false, false
        function p:canSeeAll() return false end
        function p:getVehicle() return nil end
        function p:IsSpeaking() return self.speaking end
        function p:hasTimedActions() return false end
        function p:getHaloTimerCount() return 0 end
        function p:isInvisible() return self.invisible end
        function p:isDisguised() return false end
        function p:getCurrentSquare() return { getCanSee = function() return true end } end
        function p:checkCanSeeClient() return true end
        function p:getUserNameHeight() return 16 end
        return p
    end
    seeable(T.online[1])
    local hb = seeable(T.player({ name = "bob" }))
    local hc = seeable(T.player({ name = "carol", x = 10010 }))
    push("titles", { full = true, map = { alice = "a_t", bob = "b_t", carol = "c_t" } })
    local function frame()
        drawn = {}
        Ti.scan()
        Ti.render()
        table.sort(drawn)
        return table.concat(drawn, ",")
    end
    local function want(...)
        local l = {}
        for i, id in ipairs({ ... }) do l[i] = D.titleText(id) end
        table.sort(l)
        return table.concat(l, ",")
    end
    check(frame() == want("a_t", "b_t", "c_t"), "head: every titled player in sight, yourself too (show your username)")
    showSelf, hb.speaking, hc.invisible = false, true, true
    check(frame() == "", "head: no own title without show-your-username; none while speaking or invisible")
    showSelf, hb.speaking, hc.invisible = true, false, false
    opt.DisplayUserName = false
    check(frame() == "", "head: the server shows no names, so no titles either")
    opt.DisplayUserName, opt.MouseOverToSeeDisplayName = true, true
    check(frame() == want("a_t"), "head: names on mouse-over only: others stay hidden until hovered")
    mouseX, mouseY = 10000 * 100, 10000 * 100 - 50
    check(frame() == want("a_t", "b_t"), "head: the hovered player's title shows")
    mouseX, mouseY = 10011 * 100 + 50, 10001 * 100 + 50
    check(frame() == want("a_t", "c_t"), "head: the mouse on the floor one square from a player shows the title (vanilla 3 x 3)")
    mouseX = 10012 * 100 + 50
    check(frame() == want("a_t"), "head: two squares off the player is not a mouse-over")
    E.showHeadTitles = false
    check(frame() == "", "head: the MOD option off")
    E.showHeadTitles = true
    for _, n in ipairs(keep) do _G[n] = kept[n] end
    T.disconnect(hb)
    T.disconnect(hc)

    T.section("client: SP round trip through the server")
    MQ = T.boot({ sp = true })
    C = MQ.Client
    T.player({ name = "solo" })
    T.fire("OnGameStart")
    T.tick(2)
    check(C.state ~= nil and C.catalog ~= nil and C.state.user == "solo", "SP hello: catalog and state via Client.receive")
    check(C.state ~= nil and C.state.admin == true, "SP player is admin")
    local res = nil
    C.send("anon", { on = true }, function(r) res = r end)
    check(res ~= nil and res.ok == true and C.state.anon == true, "SP mutation: result delivered, state refreshed")
    C.requestBoard("points", "season")
    local be = C.board("points", "season")
    check(be.status == "ready" or be.status == "empty", "SP board reply resolves the page state (" .. tostring(be.status) .. ")")
    T.advance(6000)
    T.tick(1)
    check(be.status ~= "error", "SP board answered synchronously does not time out later")
    C.requestRecords(true)
    T.advance(6000)
    T.tick(1)
    check(C.records ~= nil and C.recordsError == nil, "SP records answered synchronously do not time out later")

    -- UI layer against a fake framework; the fake globals are restored afterwards for the later scenarios
    local names = { "ISUIElement", "ISPanel", "UIFont", "Keyboard", "getTextManager", "getCore", "getTexture", "MinidoracatUI" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    local ok, err = pcall(dofile("scripts/harness/t_client_ui.lua"), T)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    if not ok then error(err, 0) end
end
