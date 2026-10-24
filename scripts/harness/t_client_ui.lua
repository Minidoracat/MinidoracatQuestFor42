-- Client slice, UI layer: runs every player page layout and the canvas render against a minimal fake of the
-- MinidoracatUI framework (rev 22) and the vanilla ISUIElement / ISPanel surface the pages use. Catches nil
-- fields and wrong call shapes in layout code; it does not check pixels (E2E screenshots do that).
return function(T)
    local check = T.check
    local draws = 0

    -- ===== fake vanilla UI =====
    local El = {}
    El.__index = El
    local function make(cls, x, y, w, h)
        return setmetatable({ x = x or 0, y = y or 0, width = w or 0, height = h or 0, children = {}, visible = true }, cls)
    end
    function El:initialise() end
    function El:addChild(c) c.parent = self; self.children[#self.children + 1] = c end
    function El:setX(v) self.x = v end
    function El:setY(v) self.y = v end
    function El:getX() return self.x end
    function El:getY() return self.y end
    function El:setWidth(v) self.width = v end
    function El:setHeight(v) self.height = v end
    function El:getWidth() return self.width end
    function El:getHeight() return self.height end
    function El:setVisible(v) self.visible = v == true end
    function El:isVisible() return self.visible end
    function El:getIsVisible() return self.visible end
    function El:addToUIManager() end
    function El:removeFromUIManager() end
    function El:bringToTop() end
    function El:backMost() end
    function El:getYScroll() return 0 end
    function El:setYScroll() end
    function El:isMouseOver() return true end
    function El:getMouseX() return 60 end
    function El:getMouseY() return 60 end
    for _, f in ipairs({ "drawText", "drawTextRight", "drawTextCentre", "drawRect", "drawRectBorder",
        "drawTextureScaledAspect", "drawTextureScaled" }) do
        El[f] = function() draws = draws + 1 end
    end
    local function derive(base)
        local c = setmetatable({}, { __index = base })
        c.__index = c
        c.derive = function(self) return derive(self) end
        c.new = function(cls, x, y, w, h) return make(cls, x, y, w, h) end
        return c
    end
    ISUIElement = derive(El)
    ISPanel = derive(El)
    UIFont = { Small = 1, Medium = 2 }
    Keyboard = { KEY_NONE = 0, KEY_UP = 200, KEY_DOWN = 208, KEY_LEFT = 203, KEY_RIGHT = 205, KEY_HOME = 199,
        KEY_END = 207, KEY_RETURN = 28, KEY_NUMPADENTER = 156, KEY_SPACE = 57 }
    function getTextManager()
        return { MeasureStringX = function(_, _, s) return #tostring(s) * 7 end, getFontHeight = function(_, f) return f == 2 and 20 or 15 end }
    end
    function getCore()
        return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end,
            getKey = function() return 0 end }
    end
    function getTexture() return nil end

    -- ===== fake framework =====
    local function control(opts, w, h)
        local o = make(El, opts.x, opts.y, opts.width or w, opts.height or h)
        for k, v in pairs(opts) do if o[k] == nil then o[k] = v end end
        return o
    end
    local toasts = {}
    local fake = { API_MAJOR = 1, API_REVISION = 22, CAPABILITIES = {} }
    for _, cap in ipairs({ "window", "controls", "scrollPanel", "navList", "dropdown", "textWrap", "toast", "dock",
        "dialog", "opaqueWindow", "table", "virtualList", "tileGrid" }) do fake.CAPABILITIES[cap] = true end
    local tokens = { "surface", "well", "border", "text", "textMuted", "textFaint", "textDisabled", "accent", "hover",
        "selected", "errorText", "warning", "card" }
    fake.Theme = { create = function(o)
        local colors = {}
        for _, t in ipairs(tokens) do colors[t] = { r = 1, g = 1, b = 1, a = 1 } end
        for k, v in pairs(o and o.colors or {}) do colors[k] = v end
        return { colors = colors }
    end }
    local function paint() draws = draws + 1 end
    fake.Skin = { fill = paint, border = paint, dot = paint, arrow = paint }
    fake.Icons = { draw = function() draws = draws + 1 return false end }
    fake.Text = { fit = function(s) return s end, wrap = function(s) return { s } end }
    fake.Button = { new = function(o)
        local b = control(o, #tostring(o.title) * 7 + 20, 25)
        function b:setTitle(t) self.title = t end
        function b:fitWidth() self.width = #tostring(self.title) * 7 + 20 end
        function b:setActive(v) self.active = v end
        function b:setEnabled(v) self.enabled = v end
        function b:setTooltip(t) self.tooltip = t end
        return b
    end }
    fake.ScrollPanel = { new = function(o)
        local p = control(o, 200, 200)
        function p:contentWidth() return self.width - 12 end
        p._scrollPanel = true
        function p:scrollTo(el) self.scrolledTo = el end
        return p
    end }
    fake.NavList = { new = function(o)
        local n = control(o, 160, 200)
        function n:setGroups(g) self.groups = g end
        function n:setSelected(id) self.selected = id end
        function n:getSelected() return self.selected end
        return n
    end }
    fake.Window = { new = function(o)
        local w = control(o, 400, 400)
        function w:contentTop() return 24 end
        function w:titleBarHeight() return 24 end
        function w:close() self.visible = false if self.onClose then self.onClose(self) end end
        return w
    end }
    fake.Checkbox = { new = function(o)
        local c = control(o, 100, 20)
        function c:setLabel(l) self.label = l end
        function c:setChecked(v) self.checked = v end
        function c:setEnabled(v) self.enabled = v end
        return c
    end }
    fake.Dropdown = { new = function(o)
        local d = control(o, 120, 25)
        function d:setOptions(x) self.options = x end
        function d:setSelected(id) self.selected = id end
        function d:setEnabled(v) self.enabled = v end
        return d
    end, close = function() end }
    fake.TextField = { new = function(o)
        local f = control(o, 120, 25)
        f.text = ""
        function f:setText(s) self.text = s end
        function f:getText() return self.text end
        function f:focus() end
        function f:setEnabled(v) self.enabled = v end
        return f
    end }
    fake.Toast = { show = function(o) toasts[#toasts + 1] = o end }
    fake.Dock = { register = function(spec) fake.dockSpec = spec return true end, refresh = function() end }
    MinidoracatUI = { v1 = fake }

    T.section("client UI: MOD options backup (framework rev 23, flag-probed)")
    local trace = {}
    PZAPI = { ModOptions = {
        create = function(_, modId)
            trace[#trace + 1] = "create"
            local o = { modId = modId }
            function o:addTickBox() trace[#trace + 1] = "tick" end
            return o
        end,
        load = function() trace[#trace + 1] = "load" end,
    } }
    fake.ModOptionsBackup = { protect = function(o)
        trace[#trace + 1] = "protect:" .. tostring(o and o.modId)
        return 0
    end }
    fake.CAPABILITIES.modOptionsBackup = true
    T.bootClient()
    PZAPI.ModOptions:load() -- the vanilla load in MainOptions:create comes after every MOD file loaded
    check(table.concat(trace, ",") == "create,tick,tick,tick,tick,tick,protect:MinidoracatQuestFor42,load",
        "flag on: protect once, after every tick box, before the vanilla load (" .. table.concat(trace, ",") .. ")")
    trace = {}
    fake.CAPABILITIES.modOptionsBackup = nil
    T.bootClient()
    check(table.concat(trace, ",") == "create,tick,tick,tick,tick,tick", "flag off: protect not called (" .. table.concat(trace, ",") .. ")")
    PZAPI, fake.ModOptionsBackup = nil, nil

    local MQ = T.bootClient()
    local C, D, W, E = MQ.Client, MQ.Draw, MQ.Window, MQ.Entry
    local errors = {}
    C.log = function(m) errors[#errors + 1] = m end
    T.player({ name = "alice" })
    local K = MQ.Contract
    local function push(cmd, args) T.fire("OnServerCommand", K.MODULE, cmd, args) end

    T.section("client UI: framework missing -> no window, notice instead")
    MinidoracatUI = nil
    check(W.open() == false and W.win == nil, "no framework: window does not open")
    MinidoracatUI = { v1 = fake }

    T.section("client UI: dock entry")
    T.fire("OnGameStart")
    check(E.docked == true and fake.dockSpec.id == "quest" and fake.dockSpec.order == 70
        and fake.dockSpec.bind == "MinidoracatQuest_Toggle" and fake.dockSpec.isAvailable() == true, "dock spec registered")

    T.section("client UI: every page lays out without state, then with a full state")
    check(W.open("daily") == true and W.visible(), "window opens")
    local watch = T.clientSent[#T.clientSent - 0]
    local sawWatch = false
    for _, s in ipairs(T.clientSent) do if s.command == "watch" and s.args.on == true then sawWatch = true end end
    check(sawWatch, "opening sends watch on")
    local dw, dh = W.defaultSize()
    check(dw > 640 + W.navWidth() and dh > 640 and W.win.width == dw and W.win.height == dh and not W.resetBtn:isVisible(),
        "opens larger than before at the default size, Reset size hidden")
    W.win:setWidth(dw - 100)
    W.win:setHeight(dh - 80)
    W.layout()
    check(W.resetBtn:isVisible(), "a resized window shows Reset size")
    W.resetBtn.onClick(W.resetBtn.target, W.resetBtn)
    check(W.win.width == dw and W.win.height == dh and not W.resetBtn:isVisible(), "Reset size restores the default and hides itself")
    local ids = { "daily", "weekly", "achievements", "boards", "records", "settings" }
    for _, id in ipairs(ids) do W.select(id) end
    check(#errors == 0, "no-state layouts ran clean " .. tostring(errors[1]))
    local cat = MQ.Catalog
    local a2 = cat.achievements[2]
    local now = T.now
    push("catalog", { rev = 1, overrides = {}, packs = {} })
    push("state", { v = 1, user = "alice", admin = true, now = now, dayKey = "2026-09-21", resetAt = now + 5 * 3600000,
        weekKey = "2026-W39", weekResetAt = now + 4 * 86400000, unseen = 2,
        points = { season = 640, total = 1240, balance = 840 },
        day = { quests = {
            { tid = cat.daily[1].tid, theme = cat.daily[1].theme, stat = cat.daily[1].stat, target = 20, prog = 12, pts = 15, state = "active" },
            { tid = cat.daily[2].tid, theme = cat.daily[2].theme, stat = cat.daily[2].stat, target = 5, prog = 5, pts = 15, state = "done" },
            { tid = cat.daily[3].tid, theme = cat.daily[3].theme, stat = cat.daily[3].stat, target = 3, prog = 0, pts = 20, state = "active" },
            { tid = cat.daily[4].tid, theme = cat.daily[4].theme, stat = cat.daily[4].stat, target = 10, prog = 3, pts = 20, state = "active", shared = true },
        }, swaps = 1, done = 1, sharedDone = 12 },
        week = { quests = { { tid = cat.weekly[1].tid, theme = cat.weekly[1].theme, target = 150, prog = 72, pts = 60, state = "active" } }, goalPart = 812 },
        goal = { stat = "zombie.kills", target = 30000, progress = 18640, minContrib = 50, pts = 50, endsAt = now + 3 * 86400000, reached = false },
        streak = { days = 5, graceUsed = true, week = { "done", "done", "grace", "done", "done", "", "" }, next = { days = 7, pts = 40 } },
        newbie = { steps = { true, true, false, false, false }, pts = 100, startMs = now - 3600000 },
        achv = { [a2.id] = 2 }, titles = { "newbie", "s3_top1" }, title = "newbie", prefs = { "combat", "farm" }, anon = false,
        season = { no = 3, startMs = now - 86400000, endsAt = now + 12 * 86400000, state = "review", reviewNo = 2 },
        exchange = { available = true, enabled = true, rate = 1, perDay = 100, used = 0, min = 10, queued = 20,
            hist = { { at = now - 60000, amount = 20, coins = 20, state = "queued" },
                { at = now - 3600000, amount = 40, coins = 40, state = "paid" },
                { at = now - 7200000, amount = 30, coins = 30, state = "refunded" } } },
        events = { { id = 1, name = "Halloween", theme = "combat", mult = 2, endsAt = now + 2 * 86400000 } } })
    push("records", { rows = { { stat = a2.stat, season = 3, life = 2, total = 9 }, { stat = "zombie.kills", season = 1, life = 1, total = 2 } },
        points = { season = 640, total = 1240, balance = 840 } })
    push("board", { board = "points", period = "season", status = "ok", season = { no = 3, endsAt = now + 86400000 }, at = now,
        rows = { { r = 1, n = "OldJoe", v = 1530, d = 0 }, { r = 2, n = "Marcus", v = 1204, d = 1 }, { r = 3, n = nil, v = 980, d = -1 },
            { r = 4, n = "Lena_Wanderer_of_Muldraugh", v = 876, d = 2, t = "s3_top1" }, { r = 5, n = "Ricky", v = 850 } },
        me = { r = 12, v = 640, d = 3 }, count = 40 })
    local seenSent = false
    for _, id in ipairs(ids) do
        W.select(id)
        W.onTick()
        D.Canvas.render(W.pages[id].canvas)
    end
    for _, s in ipairs(T.clientSent) do if s.command == "seen" then seenSent = true end end
    check(#errors == 0, "full-state layouts and canvas render ran clean " .. tostring(errors[1]))
    check(seenSent, "opening daily / achievements with unseen > 0 sends seen")
    check(draws > 100, "canvas issued draw calls (" .. draws .. ")")
    local nav = W.nav.groups
    check(nav ~= nil and #nav[2].items >= 2, "admin row shown in the second nav group for admins")

    T.section("client UI: leaderboard focus walks rank 1 -> 50 -> my row")
    local long = "Lena_Wanderer_of_Muldraugh_and_the_Whole_County"
    local rows50 = {}
    for r = 1, 50 do
        rows50[r] = { r = r, n = (r == 4) and long or (r ~= 5 and r ~= 6 and ("p" .. r) or nil), v = 2000 - r, d = 0,
            t = (r == 4) and "s3_top1" or nil, a = (r == 5) and "Mei" or nil }
    end
    push("board", { board = "points", period = "season", status = "ok", season = { no = 3, endsAt = now + 86400000 },
        at = now, rows = rows50, me = { r = 57, v = 640, d = 3 }, count = 80 })
    W.select("boards")
    W.onTick()
    local rk = W.pages.boards.ranks
    check(rk ~= nil and rk.visible and rk._focusKind == "button" and rk.wantMouseEvents == false,
        "ranks are one focus target that lets the mouse through")
    check(#rk.stops == 51 and rk.cursor == 1 and rk.stops[1].rank == 1 and rk.stops[2].rank == 2 and rk.stops[3].rank == 3,
        "stops in rank order: podium 1, 2, 3 first")
    local fx, fy, fw, fh = rk:focusRect()
    check(fx ~= nil and fw > 0 and fh > 0, "focus ring framed on the current stop")
    check(rk:onFocusKey(Keyboard.KEY_UP) == false, "Up on rank 1 hands focus to the previous target")
    for _ = 1, 3 do rk:onFocusKey(Keyboard.KEY_DOWN) end
    check(rk.stops[rk.cursor].rank == 4 and string.find(rk:focusLabel(), long, 1, true) ~= nil
        and string.find(rk:focusLabel(), "IGUI_MQ_UI_TitleBracket", 1, true) ~= nil,
        "the truncated long name gets its full name and title in the focus caption")
    rk:onFocusKey(Keyboard.KEY_DOWN)
    local l5 = rk:focusLabel()
    rk:onFocusKey(Keyboard.KEY_DOWN)
    check(string.find(l5, "IGUI_MQ_UI_AnonReal", 1, true) ~= nil
        and string.find(rk:focusLabel(), "IGUI_MQ_UI_Anonymous", 1, true) ~= nil,
        "an anonymous row shows the real name only when the reply carries it (admins)")
    local steps = 0
    while rk.stops[rk.cursor].rank ~= 50 and steps < 100 do
        rk:onFocusKey(Keyboard.KEY_DOWN)
        steps = steps + 1
    end
    check(rk.stops[rk.cursor].rank == 50 and W.pages.boards.sp.scrolledTo == rk, "Down walks to rank 50 and scrolls to it")
    check(rk:onFocusKey(Keyboard.KEY_DOWN) and rk.stops[rk.cursor].rank == 57, "next stop after rank 50 is my row")
    check(rk:onFocusKey(Keyboard.KEY_DOWN) == false, "Down on my row hands focus to the next target")
    check(rk:onFocusKey(Keyboard.KEY_HOME) and rk.cursor == 1 and rk:onFocusKey(Keyboard.KEY_END) and rk.cursor == 51,
        "Home / End jump to the first / last stop")
    check(#errors == 0, "leaderboard with 50 rows ran clean " .. tostring(errors[1]))

    T.section("client UI: board states")
    local BP = W.pages.boards
    for _, st in ipairs({ "error", "empty", "loading" }) do
        local e = C.board("points", "season")
        e.status = st
        if st == "loading" then e.data = nil end
        W.select("boards")
        BP.dirty = true
        W.onTick()
    end
    local PB = MQ.PageBoards
    PB.onPeriod(BP, { internal = "rewards" })
    W.onTick()
    PB.onCat(BP, { internal = "combat" })
    W.onTick()
    check(#errors == 0, "board error / empty / loading / rewards / category layouts ran clean " .. tostring(errors[1]))

    T.section("client UI: exchange dialog")
    local X = MQ.ExchangeDialog
    X.open()
    check(X.visible() and X.text == "100", "opens with the default amount (min(100, max))")
    X.onText("30")
    X.onSubmit()
    local ex = T.clientSent[#T.clientSent]
    check(ex.command == "exchange" and ex.args.amount == 30 and X.phase == "held", "submit sends exchange and shows held")
    push("result", { ok = true, code = "OK", command = "exchange", requestId = ex.args.requestId, state = "queued", coins = 30 })
    check(X.phase == "queued", "queued result shown")
    X.open()
    X.onText("20")
    X.onSubmit()
    local ex2 = T.clientSent[#T.clientSent]
    T.advance(10000)
    T.tick(6)
    check(X.phase == "noreply", "no reply -> ask again state")
    X.onSubmit()
    check(T.clientSent[#T.clientSent].args.requestId == ex2.args.requestId, "ask again reuses the requestId")
    D.Canvas.render(X.canvas)
    check(#errors == 0, "exchange layouts ran clean " .. tostring(errors[1]))

    T.section("client UI: toasts and close")
    push("toast", { kind = "achv", id = a2.id, tier = 3, pts = 30 })
    push("toast", { kind = "broadcast", who = "OldJoe", id = a2.id, tier = 4, titleId = "s3_top1" })
    check(#toasts == 2 and toasts[1].title ~= nil, "toasts go to the framework Toast")
    W.close()
    local off = false
    for _, s in ipairs(T.clientSent) do if s.command == "watch" and s.args.on == false then off = true end end
    check(off and not W.visible(), "closing sends watch off")

    T.section("client UI: tracker panel")
    local Hd = MQ.Hud
    getPlayerScreenLeft, getPlayerScreenTop, getPlayerData = function() return 0 end, function() return 0 end, function() end
    local inv = { shown = true, x = 200 }
    function inv:isVisible() return self.shown end
    function inv:getX() return self.x end
    function inv:getRight() return self.x + 640 end
    function inv:getY() return 0 end
    function inv:titleBarHeight() return 17 end
    getPlayerData = function() return { playerInventory = inv } end
    local _, yUnder = Hd.defaultXY()
    inv.shown = false
    local _, yFree = Hd.defaultXY()
    inv.shown, inv.x = true, 900
    local _, yAside = Hd.defaultXY()
    check(yUnder == 23 and yFree == 10 and yAside == 10,
        "the panel starts below the vanilla inventory's title bar only when it would run under it")
    getPlayerData = function() end
    push("delta", { pins = { "d1", "w1" } })
    local hp = Hd.panel
    check(hp ~= nil and hp:isVisible() and #hp.rows == 2 and #errors == 0,
        "pins with the window closed: the panel shows a row for each")
    hp:render()
    local h1 = hp.hits[1]
    Hd.onMouseDown(hp, h1.xx + 2, h1.y0 + 2)
    local unpin = T.clientSent[#T.clientSent]
    check(unpin.command == "pin" and unpin.args.id == "d1" and unpin.args.on == false, "a row's x unpins it")
    local fullH = hp.height
    Hd.onMouseDown(hp, hp.width - 10, 4)
    check(hp.collapsed and hp.height < fullH and hp.height <= Hd.titleH() + Hd.PAD, "the arrow folds the panel to its title row")
    Hd.onMouseDown(hp, hp.width - 10, 4)
    check(not hp.collapsed and hp.height == fullH, "and opens it again")
    W.open("daily")
    check(hp:isVisible(), "the panel stays while the main window is open")
    W.close()
    ISUIHandler = { allUIVisible = false }
    Hd.sync()
    check(not hp:isVisible(), "hidden while V hides the UI")
    ISUIHandler = nil
    W.open("daily")
    push("delta", { pins = { "d1", "d2", "d3", "d4", "w1" } })
    W.onTick()
    check(hp:isVisible() and #hp.rows == 5, "a pin made with the window open shows in the panel at once")
    local dchip = W.pages.daily.pool.items.q1pin
    W.select("achievements")
    W.onTick()
    local achChip = nil
    for key, el in pairs(W.pages.achievements.pool.items) do
        if string.sub(key, 1, 4) == "pin:" and el.visible then achChip = el end
    end
    check(dchip and dchip.active and dchip.enabled and achChip and achChip.enabled == false and achChip.tooltip ~= nil,
        "five pinned: their chips stay clickable, the others turn gray with the reason on hover")
    W.close()
    push("delta", { pins = {} })
    check(not hp:isVisible() and #errors == 0, "nothing pinned: no panel")
    MinidoracatUI = nil
end
