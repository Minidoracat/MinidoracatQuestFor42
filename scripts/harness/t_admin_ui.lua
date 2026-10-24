-- AdminUI: drive every admin tab through a fake UI framework and check the ops and fields that are sent
-- (ARCHITECTURE.md 6.2). Layout and handler errors surface here instead of in game. The fakes below only model
-- what the admin files call; they are installed for this file and removed at the end.
return function(T)
    local saved = { ISUIElement = ISUIElement, ISPanel = ISPanel, getTextManager = getTextManager, UIFont = UIFont }

    -- ===== fake engine elements =====
    local Base = {}
    Base.__index = Base
    function Base:initialise() end
    function Base:setX(x) self.x = x end
    function Base:setY(y) self.y = y end
    function Base:getX() return self.x end
    function Base:getY() return self.y end
    function Base:setWidth(w) self.width = w end
    function Base:setHeight(h) self.height = h end
    function Base:getWidth() return self.width end
    function Base:getHeight() return self.height end
    function Base:setVisible(v) self.visible = v end
    function Base:isVisible() return self.visible ~= false end
    function Base:addChild(c) self.children = self.children or {}; self.children[#self.children + 1] = c; c.parent = self end
    function Base:setYScroll(y) self.yscroll = y end
    function Base:getYScroll() return self.yscroll or 0 end
    function Base:setTooltip(s) self.tooltip = s end
    function Base:setEnabled(b) self.enabled = b end
    function Base:isEnabled() return self.enabled ~= false end
    function Base:setWantMouseEvents(b) self.wantMouse = b end
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

    -- ===== fake framework =====
    local function widget(extra)
        local W = setmetatable(extra or {}, { __index = Base })
        W.__index = W
        return function(opts)
            return setmetatable({ opts = opts, x = opts.x or 0, y = opts.y or 0, width = opts.width or 80, height = opts.height or 20 }, W)
        end
    end
    local dialogs = {}
    local UI = {
        CAPABILITIES = { textFieldInvalid = true, datePicker = false },
        Text = { fit = function(s) return s end, wrap = function(s) return { s } end },
        Button = { new = widget({ setTitle = function(self, s) self.opts.title = s end,
            fitWidth = function(self) self.width = #tostring(self.opts.title) * 7 + 20 end,
            setActive = function(self, b) self.active = b end }) },
        Checkbox = { new = widget({ setLabel = function() end, setChecked = function(self, b) self.opts.checked = b end,
            getChecked = function(self) return self.opts.checked == true end }) },
        TextField = { new = widget({ getText = function(self) return self.text or "" end, setText = function(self, s) self.text = s end,
            setInvalid = function(self, b, m) self.invalid = b and (m or true) or nil end }) },
        Dropdown = { new = widget({ setOptions = function(self, o) self.opts.options = o end,
            setSelected = function(self, id) self.selected = id end, getSelected = function(self) return self.selected end }),
            close = function() end },
        Tabs = { new = widget({ getWidth = function() return 400 end, setSelected = function() end }) },
        ScrollPanel = { new = widget({ contentWidth = function(self) return self.width - 12 end }) },
        Dialog = { show = function(opts) dialogs[#dialogs + 1] = opts end },
    }
    local colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })

    local Q = T.bootClient({})
    local A, AM, C = Q.Admin, Q.AdminModel, Q.Catalog
    local now = getTimestampMs()
    local tid = C.daily[1].tid
    local sent = {}
    local function last(op)
        for i = #sent, 1, -1 do if sent[i].op == op then return sent[i] end end
        return nil
    end
    local exWarn = "over_cap"
    local replies = {
        ["cfg.get"] = function() return { overrides = {}, history = { { id = 3, at = now, actor = "boss", summary = "x", n = 2 } }, rev = 3,
            file = { ok = false, at = now, source = "file", why = "target", path = "daily.pool.d_kill.target" } } end,
        ["cfg.preview"] = function(args)
            local rows = {}
            for i, c in ipairs(Q.Util.decode(args.changes)) do rows[i] = { path = c.path, before = 1, after = c.value } end
            return { rows = rows }
        end,
        ["cfg.apply"] = function() return { historyId = 4, rev = 4 } end,
        ["diff.preview"] = function(args) return { changes = { { op = "set", path = "difficulty.preset", value = args.preset } },
            rows = { { path = "achievements.zombie_kills.tiers", before = { 100, 1000 }, after = { 160, 1600 } } },
            estimate = { { key = "IGUI_MQ_Est_Tier3", easy = 3000, normal = 5000, hard = 8000 },
                { key = "IGUI_MQ_Est_Reached", easy = 9, normal = 5, hard = 3 } } } end,
        ["season.review"] = function() return { state = "review", no = 3, frozenNo = 2, startMs = now, endMs = now + 86400000 * 28, lengthDays = 28,
            frozenAt = now, rows = { { rank = 1, user = "OldJoe", pts = 1530, anomalies = 0, excluded = false },
                { rank = 3, user = "Ricky", pts = 1120, anomalies = 2, excluded = true, reason = "dupe" } } } end,
        ["season.preview"] = function(args) return { endMs = now + args.days * 86400000, nextStartMs = now + args.days * 86400000 } end,
        ["season.apply"] = function(args) return { endMs = now + args.days * 86400000 } end,
        ["ex.status"] = function() return { enabled = true, rate = 1, perDay = 100, min = 10, todayCoins = 2140, estimate = 4800,
            ecAvailable = true, ecCap = 3000, ecUsed = 2140, ecEnabled = true, warn = exWarn,
            events = { { id = 1, name = "Halloween", theme = "combat", mult = 2, startMs = now, endMs = now + 86400000 } } } end,
        ["anom.list"] = function() return { rows = { { at = now, user = "Ricky", stat = "zombie.kills", n = 340, ceil = 120 } } } end,
        ["acct.view"] = function(args) return { user = args.user, points = { season = 1, total = 2, balance = 3 }, achvCount = 5,
            anomalies = 2, achv = { zombie_kills = 3 } } end,
        ["balance.report"] = function() return { rows = { { tid = tid, given = 10, done = 2, rate = 0.2, medianMin = 55,
            suggest = { kind = "hard", path = "daily.pool." .. tid .. ".target", value = { 2, 3 } } } } } end,
        ["towns.here"] = function() return { x = 10500, y = 9800, z = 0 } end,
    }
    Q.Client.send = function(cmd, args, cb)
        T.check(cmd == "admin", "admin page only sends the admin command")
        sent[#sent + 1] = args
        local res = replies[args.op] and replies[args.op](args) or {}
        res.ok, res.op = res.ok ~= false, args.op
        cb(res)
        return "req"
    end

    local parent = ISPanel:new(0, 0, 640, 480)
    A.show({ UI = UI, theme = { colors = colors }, parent = parent, x = 0, y = 0, width = 640, height = 480 })
    local P = A.instance
    T.check(P ~= nil and last("cfg.get") ~= nil and P.S.overrides ~= nil, "showing the admin page loads cfg.get")
    local function pool(id) return P.pages[id].flow.pool end
    local function press(id, key) local b = pool(id)[key]; T.check(b ~= nil and b:isVisible(), "button shown: " .. id .. "/" .. key); b.handler(P, b) end
    local function answer(ok, text) local d = dialogs[#dialogs]; dialogs[#dialogs] = nil; d.onResult(ok, text) end

    T.section("admin ui: every tab lays out and loads its data")
    local loads = { season = "season.review", exchange = "ex.status", players = "anom.list", balance = "balance.report" }
    for _, id in ipairs(A.TABS) do
        A.select(P, id)
        if loads[id] then T.check(last(loads[id]) ~= nil, "tab " .. id .. " sends " .. loads[id]) end
    end
    T.check(not T.printed("admin layout"), "no tab raised during layout")

    T.section("admin ui: batch x1.25 -> preview -> apply")
    A.select(P, "achv")
    local box
    local cat = pool("achv")["cat"]
    cat.handler(P, "combat", cat)
    for _, el in pairs(pool("achv")) do if el.achId == "zombie_kills" and el.opts.onChange then box = el end end
    T.check(box ~= nil, "zombie_kills row has a select box")
    box.handler(P, true, box)
    T.check(pool("achv")["b:m2"]:isEnabled(), "batch buttons enabled with a selection")
    press("achv", "b:m2")
    A.onPreview(P)
    local pv = last("cfg.preview")
    local changes = pv and Q.Util.decode(pv.changes)
    T.check(changes and changes[1].path == "achievements.zombie_kills.tiers" and P.confirm ~= nil, "preview sent, confirm view shown")
    T.check(pool("achv")["cf:r1"] ~= nil and pool("achv")["cf:r1"].cells[2].strike == true, "old value struck through")
    press("achv", "cf:apply")
    local ap = last("cfg.apply")
    T.check(ap ~= nil and ap.changes == pv.changes and ap.summary == "IGUI_MQ_Admin_SumScale", "cfg.apply sends the previewed changes and a summary")
    T.check(P.confirm == nil and AM.draftCount(P.S.draft) == 0, "draft cleared after apply")

    T.section("admin ui: tier editor and new achievement")
    A.AchvPage.onEdit(P, { achId = "zombie_kills" })
    local apg = P.pages.achv
    T.check(#apg.rows == 4 and pool("achv")["e:t1"]:getText() == tostring(apg.rows[1].tier), "editor filled from the achievement")
    press("achv", "e:add")
    T.check(#apg.rows == 5 and pool("achv")["e:t5"]:getText() ~= "", "add tier fills the default")
    pool("achv")["e:n5"]:setText("Undying")
    press("achv", "e:save")
    local tiers = AM.get(P.S, "achievements.zombie_kills.tiers")
    local titles = AM.get(P.S, "achievements.zombie_kills.titles")
    T.check(#tiers == 5 and titles[5] == "Undying" and apg.edit == nil, "editor result is in the draft")
    A.onDiscard(P)
    press("achv", "n:open")
    pool("achv")["n:name"]:setText("Pest control")
    pool("achv")["n:tiers"]:setText("10, 100")
    pool("achv")["n:pts"]:setText("5, 10")
    press("achv", "n:add")
    local customPath = P.S.draft.order[1]
    T.check(customPath ~= nil and string.match(customPath, "^custom%.c[a-z0-9]+$") ~= nil, "new achievement drafted under custom.<id>")
    A.onDiscard(P)

    T.section("admin ui: quick difficulty")
    local hard
    for _, el in pairs(pool("achv")) do if el.preset == "hard" then hard = el end end
    hard.handler(P, hard)
    T.check(last("diff.preview").preset == "hard" and P.confirm and P.confirm.estimate ~= nil, "diff.preview -> confirm with estimate")
    press("achv", "cf:apply")
    T.check(Q.Util.decode(last("cfg.apply").changes)[1].path == "difficulty.preset", "difficulty applied through cfg.apply")

    T.section("admin ui: quest form checks before sending")
    A.select(P, "quests")
    local before = #sent
    local fa = pool("quests")["f:daily.pool." .. tid .. ".target.1"]
    local fb = pool("quests")["f:daily.pool." .. tid .. ".target.2"]
    fa:setText("0")
    A.onPreview(P)
    T.check(#sent == before and fa.invalid ~= nil, "target 0 blocked on the client")
    fa:setText("50")
    fb:setText("40")
    A.onPreview(P)
    T.check(#sent == before and fb.invalid ~= nil, "min > max blocked on the client")
    fa:setText("3")
    fb:setText("4")
    A.onPreview(P)
    changes = Q.Util.decode(last("cfg.preview").changes)
    T.check(#sent == before + 1 and changes[1].path == "daily.pool." .. tid .. ".target" and changes[1].value[1] == 3, "valid edit previewed")
    A.onConfirmCancel(P)
    A.onDiscard(P)

    T.section("admin ui: season length, exclusion, payout")
    A.select(P, "season")
    pool("season")["len"]:setText("6")
    before = #sent
    press("season", "pv")
    T.check(#sent == before and pool("season")["len"].invalid ~= nil, "length 6 blocked on the client")
    pool("season")["len"]:setText("35")
    press("season", "pv")
    T.check(last("season.preview").days == 35 and pool("season")["pvb"]:isVisible(), "season.preview -> info banner")
    press("season", "pva")
    T.check(last("season.apply").days == 35, "season.apply with the previewed length")
    local rx = pool("season")["rx1"]
    rx.handler(P, true, rx)
    answer(true, "  ")
    T.check(#dialogs == 1 and dialogs[1].danger, "empty reason asks again")
    answer(true, "alt account")
    local ex = last("season.exclude")
    T.check(ex.user == "OldJoe" and ex.on == true and ex.reason == "alt account", "season.exclude with user and reason")
    press("season", "pay")
    T.check(dialogs[1].danger == true, "payout asks once more with a danger dialog")
    answer(true, "")
    T.check(last("season.confirm") ~= nil, "season.confirm sent after the second confirmation")

    T.section("admin ui: exchange status and events")
    A.select(P, "exchange")
    local warnEl = pool("exchange")["warn"]
    T.check(warnEl ~= nil and warnEl:isVisible() and warnEl.lines[1] == "IGUI_MQ_Admin_Warn_over_cap_Head",
        "warn=over_cap shows the over-cap banner")
    T.check(pool("exchange")["s7"] ~= nil and pool("exchange")["s7"]:isVisible(), "economy limit and paid-today rows shown")
    for _, w in ipairs({ "cap_zero", "disabled", "unknown" }) do
        exWarn = w
        P.pages.exchange.loaded = false
        A.select(P, "exchange")
        T.check(pool("exchange")["warn"]:isVisible() and pool("exchange")["warn"].lines[1] == "IGUI_MQ_Admin_Warn_" .. w .. "_Head",
            "warn=" .. w .. " shows its banner")
    end
    exWarn = nil
    P.pages.exchange.loaded = false
    A.select(P, "exchange")
    T.check(not pool("exchange")["warn"]:isVisible(), "no warn -> no banner")
    pool("exchange")["ev:name"]:setText("Fest")
    pool("exchange")["ev:start"]:setText("2099-01-01")
    pool("exchange")["ev:end"]:setText("2099-01-03")
    press("exchange", "ev:add")
    local ev = last("event.add")
    T.check(ev and ev.name == "Fest" and ev.theme == "all" and ev.mult == 2 and ev.startMs == AM.dayStartMs("2099-01-01")
        and ev.endMs == AM.dayStartMs("2099-01-03") + 86400000, "event.add with day range in the sandbox timezone")
    press("exchange", "er1")
    answer(true, "")
    T.check(last("event.remove").id == 1, "event.remove by id")

    T.section("admin ui: anomalies, account, revoke, hide")
    A.select(P, "players")
    press("players", "d2")
    T.check(last("anom.list").days == 7, "7-day chip")
    press("players", "v1")
    T.check(last("acct.view").user == "Ricky" and P.pages.players.acct ~= nil, "view account from an anomaly row")
    before = #sent
    press("players", "a:revoke")
    T.check(#dialogs == 1 and dialogs[1].danger == true and dialogs[1].input ~= nil, "revoke: danger dialog asking for a reason")
    answer(true, "")
    T.check(#sent == before, "no revoke without a reason")
    answer(true, "duped kills")
    local rv = last("achv.revoke")
    T.check(rv and rv.user == "Ricky" and rv.achId == "zombie_kills" and rv.tier == 0 and rv.reason == "duped kills", "achv.revoke fields")
    press("players", "a:hide")
    answer(true, "cheating")
    local hd = last("board.hide")
    T.check(hd and hd.user == "Ricky" and hd.on == true and hd.reason == "cheating", "board.hide fields")

    T.section("admin ui: balance suggestions, towns, history")
    A.select(P, "balance")
    press("balance", "apply")
    changes = Q.Util.decode(last("cfg.preview").changes)
    T.check(changes[1].path == "daily.pool." .. tid .. ".target" and changes[1].value[2] == 3 and P.confirm ~= nil, "suggestions previewed")
    A.onConfirmCancel(P)
    A.select(P, "towns")
    press("towns", "t:here1")
    T.check(pool("towns")["t:x1"]:getText() == "10500", "towns.here fills the corner")
    pool("towns")["t:name"]:setText("Camp")
    pool("towns")["t:x2"]:setText("10400")
    pool("towns")["t:y2"]:setText("9900")
    press("towns", "t:add")
    local ct = AM.get(P.S, "towns.custom")
    T.check(#ct == 1 and ct[1].rects[1].x1 == 10400 and ct[1].rects[1].y2 == 9900, "custom town drafted with a normalised rectangle")
    local tb = pool("towns")["b1"]
    tb.handler(P, false, tb)
    T.check(AM.get(P.S, "towns.disabled")[C.towns[1].id] == true, "built-in town disabled in the draft")
    A.onDiscard(P)
    A.select(P, "history")
    press("history", "u1")
    answer(true, "")
    T.check(last("cfg.undo").historyId == 3, "cfg.undo with the history id")
    T.check(pool("history")["ios"] ~= nil and pool("history")["export"] == nil, "history tab shows the config.json state, no export/import")
    T.check(A.summaryText("event.add 3") == "IGUI_MQ_Admin_HistEventAdd" and A.summaryText("season.length 35") == "IGUI_MQ_Admin_HistSeasonLength"
        and A.summaryText("undo #2") == "IGUI_MQ_Admin_HistUndo" and A.summaryText("config.json") == "IGUI_MQ_Admin_HistFile"
        and A.summaryText("Tiers of X") == "Tiers of X",
        "server-written history summaries get translated, admin-typed ones stay")
    local gt = getText
    getText = function(key, a, b) return key .. "|" .. tostring(a) .. "|" .. tostring(b) end
    T.check(A.summaryText("event.add 3 Weekend Rush") == "IGUI_MQ_Admin_HistEventAdd|Weekend Rush|nil"
        and A.summaryText("event.remove 3") == "IGUI_MQ_Admin_HistEventRemove|#3|nil",
        "event summaries show the event name, older rows the id")
    local json = A.fileText({ ok = false, at = now, why = "json", line = 4 })
    local bad = A.fileText({ ok = false, at = now, why = "target", path = "daily.pool.d_kill.target" })
    T.check(string.find(json, "^IGUI_MQ_Admin_FileBad|") and string.find(json, "IGUI_MQ_Admin_FileJson|4", 1, true)
        and string.find(bad, "IGUI_MQ_Admin_BadConfig|daily.pool.d_kill.target|target", 1, true),
        "a rejected config.json names the line, or the key path as written in the file")
    getText = gt
    T.check(not T.printed("admin layout"), "no layout error during the flows")
    A.hide()

    A.instance = nil
    for k, v in pairs(saved) do _G[k] = v end
end
