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
    -- like the framework: height omitted = content height (24 px rows, 6 px between untitled groups); setSelected
    -- ignores an id it does not list, nil clears
    fake.NavList = { new = function(o)
        local n = control(o, 160, 0)
        n.selected = nil
        function n:setGroups(g)
            self.groups = g
            local h = 0
            for i, gr in ipairs(g or {}) do h = h + (i > 1 and 6 or 0) + 24 * #gr.items end
            if o.height == nil then self.height = h end
            if self.selected ~= nil and not self:has(self.selected) then self.selected = nil end
        end
        function n:has(id)
            for _, gr in ipairs(self.groups or {}) do
                for _, it in ipairs(gr.items) do if it.id == id then return true end end
            end
            return false
        end
        function n:setSelected(id) if id == nil or self:has(id) then self.selected = id end end
        function n:getSelected() return self.selected end
        function n:getContentHeight() return self.height end
        -- cursor over the rows like the framework: Up / Down step and return false at the edge, Home / End jump
        function n:rowCount()
            local c = 0
            for _, gr in ipairs(self.groups or {}) do c = c + #gr.items end
            return c
        end
        function n:onFocusKey(key)
            local cnt, cur = self:rowCount(), self.cursor
            if key == Keyboard.KEY_DOWN or key == Keyboard.KEY_UP then
                local nxt = (cur or (key == Keyboard.KEY_DOWN and 0 or cnt + 1)) + (key == Keyboard.KEY_DOWN and 1 or -1)
                if nxt < 1 or nxt > cnt then return false end
                self.cursor = nxt
                return true
            elseif key == Keyboard.KEY_HOME or key == Keyboard.KEY_END then
                if cnt > 0 then self.cursor = key == Keyboard.KEY_HOME and 1 or cnt end
                return true
            end
            return false
        end
        n:setGroups(o.groups)
        if o.selected ~= nil and n:has(o.selected) then n.selected = o.selected end
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
    local ids = { "daily", "weekly", "achievements", "boards", "records", "exchange", "settings" }
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
    local nav, na = W.nav.groups, W.navAdmin
    local adminId = MQ.Admin and MQ.Admin.id or "admin"
    check(#nav == 2 and #nav[2].items == 1 and nav[2].items[1].id == "settings" and not W.nav:has(adminId),
        "W.nav: the main group, then Settings in its own group; no admin row in it")
    check(na ~= nil and na:isVisible() and #na.groups == 1 and na.groups[1].items[1].id == adminId,
        "the admin row is in its own list, W.navAdmin")
    local navBottom = W.nav.y + W.nav.height
    check(na.y > navBottom + 6 and na.y + na.height == W.win.height - 6,
        "W.navAdmin sits at the bottom of the nav column, well below Settings (more than the group gap)")
    W.win:setHeight(navBottom + 20)
    W.layout()
    check(na.y == navBottom + W.ADMIN_GAP, "in a short window it stays below Settings instead of covering it")
    W.win:setHeight(dh)
    W.layout()
    check(na.y + na.height == W.win.height - 6, "and goes back to the bottom when the window grows")
    -- the admin panel itself needs framework Tabs this fake lacks (t_admin_ui.lua drives it); only the nav here
    local admSpec = W.spec(adminId)
    local admShow, admHide = admSpec.onShow, admSpec.onHide
    admSpec.onShow, admSpec.onHide = function() end, function() end
    W.select(adminId)
    check(W.current == adminId and na:getSelected() == adminId and W.nav:getSelected() == nil,
        "selecting Admin marks only the admin list")
    W.select("settings")
    check(W.nav:getSelected() == "settings" and na:getSelected() == nil, "selecting Settings clears the admin list")
    na.onSelect(na.target, adminId, na)
    check(W.current == adminId and W.nav:getSelected() == nil, "a click in the admin list goes through Window.select")
    W.nav.onSelect(W.nav.target, "daily", W.nav)
    check(W.current == "daily" and na:getSelected() == nil and W.nav:getSelected() == "daily",
        "a click in the main list clears the admin one")
    admSpec.onShow, admSpec.onHide = admShow, admHide
    check(#errors == 0, "selection across the two lists ran clean " .. tostring(errors[1]))
    local focusedTo = nil
    fake.Focus = { focusControl = function(c) if c:isVisible() then focusedTo = c return true end return false end }
    W.nav:onFocusKey(Keyboard.KEY_END)
    check(W.nav:onFocusKey(Keyboard.KEY_DOWN) == true and focusedTo == na and na.cursor == 1,
        "keyboard / joypad Down on Settings (last row) moves focus to the admin list's first row")
    focusedTo = nil
    check(na:onFocusKey(Keyboard.KEY_UP) == true and focusedTo == W.nav and W.nav.cursor == W.nav:rowCount(),
        "Up on the admin row moves focus back to Settings")
    W.nav.cursor = 1
    focusedTo = nil
    check(W.nav:onFocusKey(Keyboard.KEY_DOWN) == true and W.nav.cursor == 2 and focusedTo == nil,
        "Down inside the main list stays the list's own step")
    check(na:onFocusKey(Keyboard.KEY_DOWN) == false and focusedTo == nil, "Down on the admin row: the old edge behaviour")
    C.state.admin = false
    W.onData()
    check(#W.nav.groups == 2 and W.nav.groups[2].items[1].id == "settings" and not na:isVisible(),
        "a player's nav ends with Settings; the admin list is hidden")
    W.nav:onFocusKey(Keyboard.KEY_END)
    focusedTo = nil
    check(W.nav:onFocusKey(Keyboard.KEY_DOWN) == false and focusedTo == nil,
        "a player: Down on Settings keeps the old behaviour (no hidden admin list to hop to)")
    fake.Focus = nil
    C.state.admin = true
    W.onData()
    local function navHas(id)
        for _, g in ipairs(W.nav.groups) do
            for _, it in ipairs(g.items) do if it.id == id then return true end end
        end
        return false
    end
    check(navHas("exchange"), "Exchange is in the nav while exchange is available")
    local ex0 = C.state.exchange
    C.state.exchange = { available = false, hist = ex0.hist }
    W.onData()
    check(navHas("exchange"), "Exchange stays in the nav while exchange is off but there is history")
    C.state.exchange = { available = false }
    W.select("exchange")
    W.onData()
    check(not navHas("exchange") and W.current == "daily",
        "with exchange off and no history the Exchange entry leaves the nav and the window leaves its page")
    C.state.exchange = ex0
    W.onData()
    check(navHas("exchange"), "Exchange comes back when exchange is available again")

    T.section("client UI: player pages - swap ask, thousands separator, pins, prefs cap, import note")
    local function drew(page, s)
        for i = 1, page.canvas.n do if page.canvas.ops[i].s == s then return true end end
        return false
    end
    W.select("daily")
    local dp = W.pages.daily
    MQ.PageDaily.layout(dp)
    local asked = {}
    fake.Dialog = { show = function(o) asked[#asked + 1] = o end }
    local swap1, swap3 = dp.pool.items.q1swap, dp.pool.items.q3swap
    check(swap1 ~= nil and swap1.style == nil and swap3 ~= nil, "swap is a normal (framed) button, not ghost")
    local sent0 = #T.clientSent
    swap1.onClick(swap1.target, swap1)
    check(#asked == 1 and asked[1].danger == true and asked[1].text == "IGUI_MQ_UI_SwapAsk" and #T.clientSent == sent0,
        "a quest with progress asks first (danger dialog) and sends nothing yet")
    asked[1].onResult(true)
    local last = T.clientSent[#T.clientSent]
    check(#T.clientSent == sent0 + 1 and last.command == "swap" and last.args.slot == 1, "confirming sends the swap")
    C.pending[dp.swapRid] = nil   -- no reply in this test: drop it so no NO_REPLY toast later
    dp.swapRid = nil
    swap3.onClick(swap3.target, swap3)
    last = T.clientSent[#T.clientSent]
    check(#asked == 1 and last.command == "swap" and last.args.slot == 3, "progress 0 swaps without asking")
    C.pending[dp.swapRid] = nil
    dp.swapRid = nil
    check(drew(dp, "pause"), "a grace day carries an icon, not only a color")
    local gtSep = getText
    getText = function(key, ...) if key == "IGUI_MQ_UI_ThousandSep" then return "\194\160" end return gtSep(key, ...) end
    local spaced = D.num(1234567)
    getText = gtSep
    check(spaced == "1\194\160234\194\160567" and D.num(1234567) == "1,234,567" and D.num(1234.5) == "1,234.5",
        "D.num uses IGUI_MQ_UI_ThousandSep (no-break space), comma without the key, decimal point stays")
    local AMs = MQ.AdminModel
    AMs.SEP = "\194\160"
    local amSpaced = AMs.num(1234567)
    AMs.SEP = ","
    check(amSpaced == "1\194\160234\194\160567" and AMs.num(1234567) == "1,234,567", "AM.num uses AM.SEP")
    W.select("settings")
    local sp = W.pages.settings
    sp.draft = { "combat", "farm" }
    MQ.PageSettings.layout(sp)
    check(not drew(sp, "IGUI_MQ_Code_TOO_MANY_PREFS"), "no prefs reason line below the cap")
    sp.draft = { "combat", "farm", "cook" }
    MQ.PageSettings.layout(sp)
    check(drew(sp, "IGUI_MQ_Code_TOO_MANY_PREFS"), "at 3/3 the reason line is drawn under the chips")
    sp.draft = nil

    T.section("client UI: per-theme quest list at the bottom of Settings")
    local function opIndex(page, s)
        for i = 1, page.canvas.n do if page.canvas.ops[i].s == s then return i end end
        return nil
    end
    sp.listOpen = nil
    MQ.PageSettings.layout(sp)
    local hi, ni = opIndex(sp, "IGUI_MQ_UI_QuestList"), opIndex(sp, "IGUI_MQ_UI_ModOptionsNote")
    local qb = sp.pool.items.questList
    check(hi ~= nil and ni ~= nil and hi > ni and qb ~= nil and qb.visible and qb.title == "IGUI_MQ_UI_ListShow"
        and not drew(sp, "IGUI_MQ_UI_QuestListRow"), "admin, setting off: the list is the last section, folded")
    check(drew(sp, "IGUI_MQ_UI_QuestListAdminOnly") and opIndex(sp, "IGUI_MQ_UI_QuestListAdminOnly") > hi,
        "while off the admin sees the only-admins note under the heading")
    qb.onClick(qb.target, qb)
    MQ.PageSettings.layout(sp)
    check(sp.listOpen and drew(sp, "IGUI_MQ_UI_QuestListRow") and drew(sp, "IGUI_MQ_UI_QuestListRare")
        and drew(sp, "IGUI_MQ_UI_QuestListCount") and sp.pool.items.questList.title == "IGUI_MQ_UI_ListHide",
        "opened: theme lines with counts, then the quests with points, rare ones marked")
    C.state.admin = false
    MQ.PageSettings.layout(sp)
    check(C.questList() == nil and not drew(sp, "IGUI_MQ_UI_QuestList") and not sp.pool.items.questList.visible,
        "a player sees no list while the setting is off")
    push("catalog", { rev = 2, packs = {}, overrides = { quests = { playerList = true }, difficulty = { mult = 1.6 },
        daily = { pool = { d_kill = { target = { 20, 40 } }, d_kill_melee = { enabled = false } } } } })
    MQ.PageSettings.layout(sp)
    local ql = C.questList()
    check(ql ~= nil and drew(sp, "IGUI_MQ_UI_QuestList") and not drew(sp, "IGUI_MQ_UI_QuestListAdminOnly"),
        "setting on: the player gets the list, without the admins-only note")
    local byTheme = {}
    for _, e in ipairs(ql) do byTheme[e.theme] = e end
    local combat, kill, melee = byTheme.combat, nil, false
    for _, t in ipairs(combat.daily) do
        if t.tid == "d_kill" then kill = t end
        if t.tid == "d_kill_melee" then melee = true end
    end
    check(ql[1].theme == "combat" and #combat.daily == 9 and #combat.weekly == 4 and not melee,
        "theme order; a disabled template leaves the list")
    check(kill and kill.lo == 30 and kill.hi == 65 and kill.pts == 15,
        "ranges come after the admin target override and the difficulty x1.6, on the template step (Quests rollTarget)")
    check(byTheme.tailor.daily[1].rare == true and byTheme.tailor.daily[1].pts == 20, "rare templates carry their higher points")
    push("catalog", { rev = 3, overrides = {}, packs = {} })
    C.state.admin = true
    sp.listOpen = nil
    W.select("records")
    MQ.PageRecords.layout(W.pages.records)
    check(drew(W.pages.records, "IGUI_MQ_UI_ImportNote"), "records page draws the import note")

    T.section("client UI: the player Hordes page (design r12)")
    check(not MQ.PageHordes.shown(), "no hordes part: the page is not in the nav")
    local PA = MQ.PageAchievements
    local function hordeCat(defs)
        for _, c in ipairs(PA.categories(defs)) do if c == "horde" then return true end end
        return false
    end
    local _, allN = PA.counts(C.defs(), {})
    local _, offN = PA.counts(PA.visible(C.defs()), {})
    check(hordeCat(C.defs()) and not hordeCat(PA.visible(C.defs())) and offN == allN - 3,
        "hordes off: the achievements page leaves out the horde category and its 3 from the count")
    C.state.hordes = { on = true }
    check(MQ.PageHordes.shown(), "on: the page is in the nav")
    check(hordeCat(PA.visible(C.defs())), "on: the horde achievements are listed")
    local gtH = getText
    getText = function(key, ...)
        local s = key
        for i = 1, select("#", ...) do s = s .. "|" .. tostring((select(i, ...))) end
        return s
    end
    push("records", { rows = { { stat = "horde.joined", season = 2, life = 0, total = 12 }, { stat = "horde.kills", season = 5, life = 0, total = 214 } },
        points = { season = 640, total = 1240, balance = 840 },
        hordes = { { id = 9, name = "Gas", state = "success", endedAt = now - 3600000, spawned = 30, killed = 30, mine = 18, got = 72 },
            { id = 8, name = "School", state = "failed", why = "time", endedAt = now - 86400000, spawned = 20, killed = 12, mine = 0, got = 0 },
            { id = 7, name = "Clinic", state = "cancelled", endedAt = now - 2 * 86400000, spawned = 0, killed = 0, mine = 0, got = 0 } } })
    W.select("hordes")
    local hp = W.pages.hordes
    MQ.PageHordes.layout(hp)
    check(drew(hp, "IGUI_MQ_UI_HordesNone") and drew(hp, "12") and drew(hp, "214") and drew(hp, "0"),
        "no horde now: the note; the tiles show the all-time totals, 0 for a stat never counted")
    check(drew(hp, "IGUI_MQ_UI_HordeRes_success|30|30") and drew(hp, "18") and drew(hp, "+72"), "a win: cleared n/n, my kills, +points")
    check(drew(hp, "IGUI_MQ_UI_HordeRes_failed|IGUI_MQ_Admin_HordeWhy_time") and drew(hp, "IGUI_MQ_UI_HordeAbsent"),
        "a fail without me: the reason and Absent")
    check(drew(hp, "IGUI_MQ_UI_HordeRes_cancelled") and drew(hp, "IGUI_MQ_UI_HordesNote"), "a cancel; the note under the list")
    C.state.hordes = { on = true, cur = { id = 10, name = "Gas", x = 10620, y = 9810, state = "announced", kinds = {}, startMs = now + 600000 },
        last = { id = 11, name = "Gas", state = "success", endedAt = now - 60000, spawned = 4, killed = 4, mine = 0 } }
    C.recordsSentAt = nil
    MQ.PageHordes.layout(hp)
    check(drew(hp, "IGUI_MQ_Horde_Title_soon|Gas") and not drew(hp, "IGUI_MQ_UI_HordesNone"), "a warned horde: the daily page banner on top")
    check(C.recordsSentAt ~= nil, "a result newer than the list: the records are asked again")
    C.recordsSentAt = nil
    MQ.PageHordes.layout(hp)
    check(C.recordsSentAt == nil, "asked once for that result")
    push("records", { rows = {}, points = { season = 640, total = 1240, balance = 840 }, hordes = {} })
    MQ.PageHordes.layout(hp)
    check(drew(hp, "IGUI_MQ_UI_HordesEmpty") and drew(hp, "0"), "no result yet: the empty line; the tiles read 0")
    getText = gtH
    C.state.hordes = nil
    W.select("daily")

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
    check(dchip and dchip.active and dchip.enabled ~= false and achChip and achChip.enabled ~= false
        and achChip.tooltip == "IGUI_MQ_Code_TOO_MANY_PINS",
        "five pinned: every Track chip stays enabled (focusable); the unpinned ones say why on hover")
    W.close()
    push("delta", { pins = {} })
    check(not hp:isVisible() and #errors == 0, "nothing pinned: no panel")
    MinidoracatUI = nil
end
