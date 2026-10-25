-- Report slice: day counters (seenDay, swaps, points, tiers, coins), 30-day prune, the balance contract (swaps left
-- out, weekly only for ended weeks, minGiven), the exchange estimate over 7 calendar days, report.get built one
-- shard per tick, report.export without names, and the report tab laid out from a real server reply.
return function(T)
    local DAY = 86400000
    local function boot(opts)
        opts = opts or {}
        opts.sandbox = opts.sandbox or { AdminRoles = "admin" }
        local Q = T.boot(opts)
        T.now = Q.Clock.weekResetMs(T.now) + 3 * DAY + 60000    -- Thursday: the last ended week is a full week back
        T.tick(2)
        return Q
    end
    local function cmd(p, c, args, gap)
        T.advance(gap or 400)
        return T.cmd(p, c, args)
    end
    local function admin(p, op, args)
        args = args or {}
        args.op = op
        return cmd(p, "admin", args)
    end
    local function section(name, fn)
        T.section("report: " .. name)
        local ok, err = pcall(fn)
        if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
    end
    local function count(list)
        local n = 0
        for i = 1, 4 do if list[i] then n = n + 1 end end
        return n
    end

    local reply   -- a real report.get reply for the UI section

    section("day counters", function()
        local credits = {}
        local fake = { v1 = { API_MAJOR = 1, API_REVISION = 1, registerSource = function()
            return { credit = function(_, _, n) credits[#credits + 1] = n return { ok = true } end }
        end } }
        local Q = boot({ economy = fake })
        local root = Q.Store.root()
        local a, b = T.player{ name = "alice", admin = true }, T.player{ name = "bob" }
        cmd(a, "hello")
        cmd(b, "hello")
        local day = Q.Clock.dayKey(T.now)
        local d = root.daily[day]
        local accA, accB = Q.Store.account("alice"), Q.Store.account("bob")
        T.check(d ~= nil and d.active == 2 and d.fresh == 2, "hello: two new accounts, both active today")
        T.check(d.dGiven == count(accA.day.quests) + count(accB.day.quests) and d.wGiven == #accA.week.quests + #accB.week.quests,
            "generated daily and weekly quests counted as given")
        Q.Stats.add("alice", "zombie.kills", 1)
        cmd(a, "hello", nil, 6000)
        T.check(d.active == 2 and accA.seenDay == day, "more activity the same day: still counted once")

        local old = accA.day.quests[1]
        local given = d.dGiven
        local r = cmd(a, "swap", { slot = 1 })
        T.check(r and r.ok and d.swaps[old.tid] == 1 and d.dGiven == given + 1, "swap: the template swapped away counted, the new one given")
        T.check(root.balance[old.tid][day].swaps == 1, "swap reaches the balance row")

        Q.Points.award(accA, "alice", 50, "admin")
        Q.Points.award(accA, "alice", 30, "import")
        T.check(d.pts.admin == 50 and d.pts.import == nil, "points by kind; import not counted")
        local zk = Q.Achievements.get("zombie_kills")
        accB.total["zombie.kills"] = zk.tiers[2]
        Q.Achievements.evaluate(accB, "bob", { stat = "zombie.kills" })
        -- the tier-count stat those two tiers add can unlock more (achievement-count achievements)
        T.check(accB.achv.zombie_kills == 2 and d.tiers >= 2, "unlocked tiers counted")
        local tiers = d.tiers
        local c = T.player{ name = "carol", kills = zk.tiers[1] + 1 }
        cmd(c, "hello")
        T.check((Q.Store.account("carol").achv.zombie_kills or 0) >= 1 and d.tiers == tiers, "import unlocks not counted")
        T.check(d.coins == 0, "no exchange yet: coins 0")
        r = cmd(a, "exchange", { amount = 40 }, 3100)
        T.check(r and r.ok and r.state == "paid" and d.coins == 40, "paid exchange books coins")

        T.now = Q.Clock.nextResetMs(T.now) + 60000
        Q.Stats.add("alice", "zombie.kills", 1)
        local d2 = root.daily[Q.Clock.dayKey(T.now)]
        T.check(d2 ~= nil and d2.active == 1 and d.active == 3, "the next day counts alice again, on the new row")

        T.section("report: rows older than 30 days pruned")
        local keep, drop = Q.Clock.dayKey(T.now + DAY - 29 * DAY), Q.Clock.dayKey(T.now + DAY - 30 * DAY)
        root.daily[keep], root.daily[drop], root.daily["2000-01-01"] = { active = 1 }, { active = 1 }, { active = 1 }
        T.now = Q.Clock.nextResetMs(T.now) + 60000
        Q.Report.add("fresh")
        T.check(root.daily[keep] ~= nil and root.daily[drop] == nil and root.daily["2000-01-01"] == nil,
            "day change keeps 30 days, drops older")

        T.section("report: report.get builds the snapshot one shard per tick")
        local nonAdmin = admin(b, "report.get", { days = 7 })
        T.check(nonAdmin and nonAdmin.code == "FORBIDDEN", "non-admin refused")
        r = admin(a, "report.get", { days = 10 })
        T.check(r and r.code == "BAD_ARGS", "only 7 or 30 days")
        local walked, eachIn = {}, Q.Store.eachIn
        Q.Store.eachIn = function(i, fn) walked[#walked + 1] = i return eachIn(i, fn) end
        r = admin(a, "report.get", { days = 7 })
        T.check(r == nil and Q.Report.job ~= nil and #walked == 0, "no reply and no walk in the command itself")
        local perTick, replies = true, #T.sentTo(a, "admin")
        for i = 1, 15 do
            T.tick(1)
            perTick = perTick and Q.Report.job ~= nil and Q.Report.job.shard == i
        end
        T.check(perTick and #T.sentTo(a, "admin") == replies, "15 ticks: one shard each, no reply yet")
        T.tick(1)
        Q.Store.eachIn = eachIn
        r = T.lastOf(a, "admin")
        T.check(r and r.op == "report.get" and r.ok == true and Q.Report.job == nil,
            "16th tick: the last shard, then the deferred reply")
        T.check(#r.rows == 7 and r.rows[7].day == Q.Clock.dayKey(T.now) and r.rows[1].day == Q.Clock.dayKey(T.now - 6 * DAY),
            "seven day rows, oldest first, today last")
        local zr, sorted = nil, true
        for i, x in ipairs(r.achv) do
            if x.id == "zombie_kills" then zr = x end
            local y = r.achv[i + 1]
            if y then
                for k = 10, 1, -1 do
                    local p, q = x.c[k] or 0, y.c[k] or 0
                    if p ~= q then sorted = sorted and p > q break end
                end
            end
        end
        T.check(sorted and zr and zr.c[1] == 2 and zr.c[2] == 1,
            "achievements sorted by the highest tier reached; c[k] = players at tier k or above")
        T.check(r.snap.active == 3 and r.snap.unspent == accA.points.balance + accB.points.balance + Q.Store.account("carol").points.balance,
            "snapshot: active players and unspent points")
        T.check(r.snap.holders >= 1 and r.snap.top10 > 0 and r.snap.top10 <= 1, "top 10% share in 0..1")
        T.check(r.sum.coins == 40 and r.sum.swaps == 1 and r.sum.ptsBy.admin == 50 and r.sum.tiers == d.tiers,
            "window sums: coins, swaps, points by kind, tiers (" .. tostring(r.sum.coins) .. "/" .. tostring(r.sum.swaps) .. "/"
                .. tostring(r.sum.ptsBy.admin) .. "/" .. tostring(r.sum.tiers) .. ")")
        reply = T.deepcopy(r)
        local rr = admin(a, "report.get", { days = 30 })
        T.check(rr and rr.ok and #rr.rows == 30, "within 5 minutes the snapshot answers at once")
        T.advance(300001)
        rr = admin(a, "report.get", { days = 7 })
        T.check(rr == nil and Q.Report.job ~= nil, "after 5 minutes the walk starts again")
        T.tick(16)

        T.section("report: export writes totals only")
        r = admin(a, "report.export")
        local path = Q.Store.path("report-" .. Q.Clock.dayKey(T.now) .. ".json")
        T.check(r and r.ok and r.path == path and T.files[path] ~= nil, "export writes report-<day>.json beside config.json")
        local text = table.concat(T.files[path].lines, "\n")
        T.check(not string.find(text, "alice", 1, true) and not string.find(text, "bob", 1, true)
            and not string.find(text, "carol", 1, true), "no player names in the file")
        local doc = Q.Util.decode(text)
        T.check(doc and doc.days == 30 and #doc.daily == 30 and doc.points.unspent == reply.snap.unspent
            and doc.achv.zombie_kills[1] == 2, "file holds the 30 day rows, points and achievement counts")
        T.silentWrites = true
        T.advance(3100)
        r = admin(a, "report.export")
        T.silentWrites = false
        T.check(r and r.ok == false and r.code == "FILE_ERROR", "a write that does not read back fails")
    end)

    section("balance: swaps left out, weekly only for ended weeks, minGiven", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        cmd(a, "hello")
        local B = Q.Balance
        Q.Store.root().balance = {}
        for _ = 1, 12 do B.given("d_fish", T.now) end
        for _ = 1, 2 do B.swapped("d_fish", T.now) end
        for _ = 1, 5 do B.done("d_fish", T.now, T.now) end
        for _ = 1, 11 do B.given("d_craft", T.now) end
        for _ = 1, 2 do B.swapped("d_craft", T.now) end
        local wtid = Q.Catalog.weekly[1].tid
        local lastWeek = Q.Clock.weekResetMs(T.now) - 13 * DAY   -- Tuesday of the week that ended
        for _ = 1, 10 do B.given(wtid, lastWeek) end
        for _ = 1, 2 do B.done(wtid, lastWeek, lastWeek + DAY) end
        for _ = 1, 10 do B.given(wtid, T.now) B.done(wtid, T.now, T.now) end   -- this week: still running
        local rows = {}
        for _, r in ipairs(B.report(T.now)) do rows[r.tid] = r end
        T.check(rows.d_fish and rows.d_fish.swaps == 2 and rows.d_fish.rate == 0.5, "rate = done / (given - swaps)")
        T.check(rows.d_craft and rows.d_craft.rate == 0 and rows.d_craft.suggest == nil,
            "given - swaps under minGiven: no suggestion even at 0%")
        T.check(rows[wtid] and rows[wtid].given == 10 and rows[wtid].done == 2 and rows[wtid].rate == 0.2,
            "weekly: only the week that ended")
        for _ = 1, 3 do B.swapped("d_kill", T.now) B.given("d_kill", T.now) end
        rows = {}
        for _, r in ipairs(B.report(T.now)) do rows[r.tid] = r end
        T.check(rows.d_kill and rows.d_kill.rate == nil, "everything swapped away: rate nil")
        local r = admin(a, "balance.report")
        T.check(r and r.ok and r.minGiven == 10 and type(r.rows) == "table", "reply carries minGiven")
    end)

    section("exchange estimate: last 7 calendar days, zero days included", function()
        local fake = { v1 = { API_MAJOR = 1, API_REVISION = 1, registerSource = function()
            return { credit = function() return { ok = true } end }
        end } }
        local Q = boot({ economy = fake })
        local e = Q.Store.root().exchange
        e.days = { { day = Q.Clock.dayKey(T.now - 3 * DAY), coins = 70 }, { day = Q.Clock.dayKey(T.now - 9 * DAY), coins = 700 } }
        e.day, e.coins = Q.Clock.dayKey(T.now - DAY), 70     -- yesterday, not yet rolled into days
        T.check(Q.Exchange.status(T.now).estimate == 20, "(70 + 70) / 7 days, the day 9 days back left out")
        e.days, e.day, e.coins = {}, Q.Clock.dayKey(T.now), 30
        T.check(Q.Exchange.status(T.now).estimate == 30, "no earlier exchange: today's coins")
    end)

    section("report tab lays out a real reply", function()
        if reply == nil then return T.check(false, "no server reply captured") end
        local saved = { ISUIElement = ISUIElement, ISPanel = ISPanel, getTextManager = getTextManager, UIFont = UIFont }
        local Base = {}
        Base.__index = Base
        function Base:getX() return self.x end
        function Base:setYScroll(y) self.yscroll = y end
        function Base:getYScroll() return self.yscroll or 0 end
        function Base:getHeight() return self.height end
        function Base:isEnabled() return self.enabled ~= false end
        for _, m in ipairs({ "initialise", "setWantMouseEvents", "setTooltip" }) do Base[m] = function() end end
        function Base:setX(x) self.x = x end
        function Base:setY(y) self.y = y end
        function Base:getY() return self.y end
        function Base:setWidth(w) self.width = w end
        function Base:setHeight(h) self.height = h end
        function Base:getWidth() return self.width end
        function Base:setVisible(v) self.visible = v end
        function Base:isVisible() return self.visible ~= false end
        function Base:setEnabled(b) self.enabled = b end
        function Base:addChild(c) c.parent = self end
        local draws, texts = 0, {}
        function Base:drawRect() draws = draws + 1 end
        function Base:drawText(s) draws = draws + 1; texts[#texts + 1] = s end
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
        local function widget(extra)
            local W = setmetatable(extra or {}, { __index = Base })
            W.__index = W
            return function(opts)
                return setmetatable({ opts = opts, x = 0, y = 0, width = opts.width or 80, height = 20 }, W)
            end
        end
        local UI = {
            CAPABILITIES = {},
            Text = { fit = function(s) return s end, wrap = function(s) return { s } end },
            Button = { new = widget({ setTitle = function(self, s) self.opts.title = s end, fitWidth = function() end,
                setActive = function(self, b) self.active = b end, setStyle = function(self, s) self.style = s end }) },
            Dropdown = { new = widget({ setOptions = function() end, setSelected = function() end }), close = function() end },
            Checkbox = { new = widget({ setLabel = function() end, setChecked = function(self, b) self.checked = b end,
                getChecked = function(self) return self.checked == true end }) },
            TextField = { new = widget({ getText = function(self) return self.text or "" end, setText = function(self, t) self.text = t end,
                setInvalid = function() end }) },
            Tabs = { new = widget({ setSelected = function() end }) },
            ScrollPanel = { new = widget({ contentWidth = function(self) return self.width - 12 end }) },
        }
        local Q = T.bootClient({})
        local A = Q.Admin
        local sent = {}
        Q.Client.send = function(_, args, cb)
            sent[#sent + 1] = args
            local res = args.op == "report.get" and T.deepcopy(reply)
                or args.op == "report.export" and { path = "MinidoracatQuest/servertest/report-x.json" }
                or args.op == "cfg.get" and { overrides = {}, history = {}, rev = 1 } or {}
            res.ok, res.op = true, args.op
            cb(res)
            return "req"
        end
        local colors = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, a = 1 } end })
        A.show({ UI = UI, theme = { colors = colors }, parent = ISPanel:new(0, 0, 640, 480), x = 0, y = 0, width = 640, height = 480 })
        local P = A.instance
        A.select(P, "report")
        local pool = P.pages.report.flow.pool
        T.check(sent[#sent].op == "report.get" and sent[#sent].days == 7, "the tab asks for 7 days")
        T.check(not T.printed("admin layout") and pool.bars and pool.bars:isVisible() and pool.kv1 and pool.ar1,
            "KPIs, bars and the achievement table laid out")
        pool.bars:render()
        T.check(draws > 0, "bars render with a text legend")
        -- 7 rows: a label under every day plus the 2 legend entries (the 30-day stride skipped days 2 and 6, E2E 1025g)
        T.check(#texts == #pool.bars.rows + 2, "7-day bars label every day (" .. #texts .. " texts)")
        pool.d2.handler(P, pool.d2)
        T.check(sent[#sent].op == "report.get" and sent[#sent].days == 30, "the 30-day chip asks again")
        pool.exp.handler(P, pool.exp)
        T.check(P.pages.report.saved == "MinidoracatQuest/servertest/report-x.json" and pool.saved and pool.saved:isVisible(),
            "export shows the written path")
        A.hide()
        for k, v in pairs(saved) do _G[k] = v end
    end)
end
