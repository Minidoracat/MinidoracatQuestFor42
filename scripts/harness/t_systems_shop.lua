-- Point sinks bought on the server (contract temp/points-sinks 3-5): paid swaps (Quests.swap), the streak shield
-- (Shop.buyShield, Quests.rollStreak) and the point titles (Shop.buyTitle). Spending takes the balance only.
return function(T)
    local DAY = 86400000
    local function boot()
        local Q = T.boot({ sandbox = { AdminRoles = "admin" } })
        T.now = Q.Clock.weekResetMs(T.now) + 3 * DAY + 60000   -- Thursday: yesterday and the day before are this week
        T.tick(2)
        return Q
    end
    local function cmd(p, c, args, gap)
        T.advance(gap or 300)
        return T.cmd(p, c, args)
    end
    local function section(name, fn)
        T.section("shop: " .. name)
        local ok, err = pcall(fn)
        if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
    end
    local function set(Q, path, value)
        return Q.Config.apply({ { op = value == nil and "del" or "set", path = path, value = value } }, "t", "alice")
    end

    section("paid swaps", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 1000, "admin", "t")
        local season, total = acc.points.season, acc.points.total
        local d = acc.day
        local bal0 = acc.points.balance
        local r = cmd(p, "swap", { slot = 1, pay = 999 })
        T.check(r and r.ok and d.swaps == 0 and d.paid == 0 and acc.points.balance == bal0 and acc.spent == nil,
            "the free swap stays free (pay ignored)")
        local bal = acc.points.balance
        local before = d.quests[1]
        r = cmd(p, "swap", { slot = 1 })
        T.check(r and r.code == "PRICE_CHANGED" and d.quests[1] == before and acc.points.balance == bal,
            "free swaps used: no pay -> PRICE_CHANGED, nothing taken")
        r = cmd(p, "swap", { slot = 1, pay = 49 })
        T.check(r and r.code == "PRICE_CHANGED" and d.quests[1] == before and acc.points.balance == bal,
            "pay not the price -> PRICE_CHANGED, nothing taken")

        local seeds, hash = {}, Q.Util.hash
        Q.Util.hash = function(s)
            if string.find(s, "|swap|", 1, true) then seeds[#seeds + 1] = s end
            return hash(s)
        end
        r = cmd(p, "swap", { slot = 1, pay = 50 })
        T.check(r and r.ok and before.state == "swapped" and d.quests[1] ~= before and d.paid == 1 and d.swaps == 0,
            "paid swap replaces the quest and counts paid")
        T.check(acc.points.balance == bal - 50 and acc.points.season == season and acc.points.total == total,
            "paid swap takes 50 from the balance; season and total stay")
        T.check(acc.spent[1].what == "swap" and acc.spent[1].n == -50 and acc.spent[1].ref == before.tid,
            "the spend is recorded with the swapped-out quest")
        local st = T.lastOf(p, "state")
        T.check(st and st.day.paid == 1 and st.day.swaps == 0 and st.spent[1].what == "swap" and st.points.balance == bal - 50,
            "the reply state carries day.paid, spent and the balance")
        r = cmd(p, "swap", { slot = 2, pay = 50 })
        T.check(r and r.ok and d.paid == 2, "second paid swap")
        Q.Util.hash = hash
        T.check(#seeds == 2 and seeds[1] ~= seeds[2], "two paid swaps draw from different seeds")
        r = cmd(p, "swap", { slot = 3, pay = 50 })
        T.check(r and r.ok and d.paid == 3 and acc.points.balance == bal - 150, "third paid swap (perDay 3)")
        local q3 = d.quests[3]
        r = cmd(p, "swap", { slot = 3, pay = 50 })
        T.check(r and r.code == "NO_SWAPS" and d.quests[3] == q3 and acc.points.balance == bal - 150, "past perDay -> NO_SWAPS")

        T.now = Q.Clock.nextResetMs(T.now) + 60000
        cmd(p, "hello")
        d = acc.day
        T.check(d.paid == 0 and d.swaps == 1, "the next day: paid back to 0, the free swap back")
        cmd(p, "swap", { slot = 1 })
        acc.points.balance = 30
        local q1 = d.quests[1]
        r = cmd(p, "swap", { slot = 1, pay = 50 })
        T.check(r and r.code == "NOT_ENOUGH_POINTS" and d.quests[1] == q1 and q1.state == "active" and d.paid == 0
            and acc.points.balance == 30, "not enough points: quest, count and balance unchanged")
        acc.points.balance = 500
        local pool = Q.Quests.dailyPool
        Q.Quests.dailyPool = function() return {} end
        r = cmd(p, "swap", { slot = 1, pay = 50 })
        Q.Quests.dailyPool = pool
        T.check(r and r.code == "NOT_FOUND" and d.quests[1] == q1 and acc.points.balance == 500 and d.paid == 0,
            "nothing to draw -> NOT_FOUND, nothing taken")
        T.check(set(Q, "shop.swap.enabled", false) == true, "paid swaps switched off")
        r = cmd(p, "swap", { slot = 1, pay = 50 })
        T.check(r and r.code == "NO_SWAPS" and d.quests[1] == q1 and acc.points.balance == 500, "switched off -> NO_SWAPS")
        set(Q, "shop.swap", nil)
        set(Q, "shop.swap.pts", 80)
        r = cmd(p, "swap", { slot = 1, pay = 50 })
        T.check(r and r.code == "PRICE_CHANGED" and acc.points.balance == 500, "a price changed after the player looked")
        r = cmd(p, "swap", { slot = 1, pay = 80 })
        T.check(r and r.ok and acc.points.balance == 420, "the new price")
        Q.Store.readOnly = true
        q1 = d.quests[1]
        r = cmd(p, "swap", { slot = 1, pay = 80 })
        Q.Store.readOnly = false
        T.check(r and r.code == "NOT_READY" and d.quests[1] == q1 and acc.points.balance == 420, "read-only store: no swap")
    end)

    section("streak shield: buying", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 1000, "admin", "t")
        local season, total = acc.points.season, acc.points.total
        local bal = acc.points.balance
        local st = Q.Quests.stateStreak(acc, "alice", T.now)
        T.check(st.shield == 0 and st.shieldLeft == 1, "no shield yet, one purchase left this week")
        local r = cmd(p, "buyShield", { pay = 199 })
        T.check(r and r.code == "PRICE_CHANGED" and (acc.streak.shield or 0) == 0 and acc.points.balance == bal,
            "wrong price refused")
        r = cmd(p, "buyShield", {})
        T.check(r and r.code == "BAD_ARGS", "pay is required")
        acc.points.balance = 150
        r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.code == "NOT_ENOUGH_POINTS" and (acc.streak.shield or 0) == 0 and acc.points.balance == 150,
            "not enough points")
        acc.points.balance = bal
        set(Q, "shop.shield.enabled", false)
        r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.code == "SHOP_OFF" and (acc.streak.shield or 0) == 0, "switched off -> SHOP_OFF")
        set(Q, "shop.shield", nil)
        r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.ok and acc.streak.shield == 1 and acc.streak.shieldN == 1
            and acc.streak.shieldWeek == Q.Clock.weekKey(T.now), "bought: one shield day")
        T.check(acc.points.balance == bal - 200 and acc.points.season == season and acc.points.total == total
            and acc.spent[1].what == "shield" and acc.spent[1].n == -200, "200 from the balance only, recorded")
        st = T.lastOf(p, "state")
        T.check(st and st.streak.shield == 1 and st.streak.shieldLeft == 0, "the reply state shows the shield")
        r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.code == "SHIELD_HELD" and acc.points.balance == bal - 200, "a second one while holding one")
        acc.streak.shield = 0   -- used up
        r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.code == "SHIELD_WEEK" and acc.points.balance == bal - 200, "perWeek reached -> SHIELD_WEEK")
        Q.Store.readOnly = true
        r = cmd(p, "buyShield", { pay = 200 })
        Q.Store.readOnly = false
        T.check(r and r.code == "NOT_READY" and acc.streak.shield == 0, "read-only store: nothing bought")
        T.now = Q.Clock.weekResetMs(T.now) + 60000
        st = Q.Quests.stateStreak(acc, "alice", T.now)
        T.check(st.shieldLeft == 1, "a new week: one purchase left again")
        r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.ok and acc.streak.shield == 1 and acc.streak.shieldN == 1, "bought again the next week")
    end)

    section("streak shield: the day change", function()
        local Q = boot()
        local cfg = Q.Config.get()
        local acc = Q.Store.account("sam", true)
        local now = T.now
        local yest, before = Q.Clock.dayKey(now - DAY), Q.Clock.dayKey(now - 2 * DAY)
        -- days missed = days between s.last and today; graceUsed: yesterday's week already had its grace
        local function roll(missed, shield, graceUsed)
            acc.streak = { days = 5, best = 5, last = Q.Clock.dayKey(now - (missed + 1) * DAY), paid = { [3] = true },
                marks = {}, shield = shield, graceUsed = graceUsed,
                graceWeek = graceUsed and Q.Clock.weekKey(now - DAY) or nil }
            Q.Quests.rollStreak(acc, "sam", now, cfg)
            return acc.streak
        end
        local s = roll(1, 1, false)
        T.check(s.days == 6 and s.shield == 1 and s.marks[yest] == "grace" and s.graceUsed == true,
            "1 missed, grace free: the grace covers it, the shield stays")
        s = roll(1, 1, true)
        T.check(s.days == 6 and s.shield == 0 and s.marks[yest] == "shield" and s.last == yest,
            "1 missed, grace used: the shield covers it")
        local st = Q.Quests.stateStreak(acc, "sam", now)
        T.check(st.week[st.today - 1] == "shield" and st.shield == 0, "the streak state shows the shield day")
        s = roll(2, 1, false)
        T.check(s.days == 7 and s.shield == 0 and s.marks[before] == "shield" and s.marks[yest] == "grace" and s.last == yest,
            "2 missed: the shield takes the older day, the grace yesterday")
        s = roll(2, 1, true)
        T.check(s.days == 0 and s.shield == 1 and next(s.paid) == nil, "2 missed without the grace: reset, the shield kept")
        s = roll(3, 1, false)
        T.check(s.days == 0 and s.shield == 1, "3 missed: reset, the shield kept")
        s = roll(0, 1, false)
        T.check(s.days == 5 and s.shield == 1, "nothing missed: nothing changes")
        -- without a shield: the rule from before the shop
        s = roll(1, nil, false)
        T.check(s.days == 6 and s.marks[yest] == "grace" and s.shield == nil, "no shield, 1 missed with the grace: grace day")
        s = roll(1, nil, true)
        T.check(s.days == 0 and s.shield == nil, "no shield, 1 missed after the grace: reset")
        s = roll(2, nil, false)
        T.check(s.days == 0 and s.marks[yest] == nil, "no shield, 2 missed: reset")
        -- through Q.ensure with a best streak that grows: countDay feeds the stat, whose listener runs Q.ensure again
        -- before the day key moves, and that inner roll counts yesterday; the outer loop must not count it again
        local z = Q.Store.account("zoe", true)
        z.streak = { days = 4, best = 4, last = Q.Clock.dayKey(now - 3 * DAY), paid = { [3] = true }, marks = {}, shield = 1 }
        Q.Quests.ensure(z, "zoe", now)
        T.check(z.streak.days == 6 and z.streak.best == 6 and z.streak.shield == 0 and z.streak.last == yest
            and z.streak.marks[before] == "shield" and z.streak.marks[yest] == "grace",
            "2 missed with a growing best streak: 2 days counted, not 3")
        set(Q, "streak.gracePerWeek", 0)
        cfg = Q.Config.get()
        s = roll(1, 1, false)
        T.check(s.days == 6 and s.shield == 0 and s.marks[yest] == "shield", "grace switched off: the shield covers the day")
        s = roll(1, nil, false)
        T.check(s.days == 0, "grace switched off, no shield: reset")
        set(Q, "streak", nil)

        -- a shield bought after a missed day does not cover it: the purchase settles the day change first
        cfg = Q.Config.get()
        local p = T.player{ name = "ann" }
        cmd(p, "hello")
        local a = Q.Store.account("ann", false)
        Q.Points.award(a, "ann", 1000, "admin", "t")
        a.streak.days, a.streak.last, a.streak.graceWeek = 4, Q.Clock.dayKey(T.now - 2 * DAY), Q.Clock.weekKey(T.now - DAY)
        a.day.key = Q.Clock.dayKey(T.now - DAY)   -- the day change has not run for her yet
        local r = cmd(p, "buyShield", { pay = 200 })
        T.check(r and r.ok and a.streak.days == 0 and a.streak.shield == 1, "the purchase rolls the streak first")
    end)

    section("point titles", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 20000, "admin", "t")
        local season, total = acc.points.season, acc.points.total
        local bal = acc.points.balance
        local r = cmd(p, "buyTitle", { id = "spend_1", pay = 1000 })
        T.check(r and r.ok and acc.titles.spend_1 == true and acc.titleAt.spend_1 == T.now
            and acc.titleSrc.spend_1 == "shop:spend_1", "spend_1 bought: title, time and source")
        T.check(acc.title ~= "spend_1" and acc.points.balance == bal - 1000 and acc.points.season == season
            and acc.points.total == total, "not worn automatically; balance only")
        T.check(acc.spent[1].what == "title" and acc.spent[1].ref == "spend_1" and acc.spent[1].n == -1000, "recorded")
        local st = T.lastOf(p, "state")
        local listed = false
        for _, id in ipairs(st and st.titles or {}) do if id == "spend_1" then listed = true end end
        T.check(listed and st.titleSrc.spend_1 == "shop:spend_1", "the reply state lists the title")
        bal = acc.points.balance
        r = cmd(p, "buyTitle", { id = "spend_1", pay = 1000 })
        T.check(r and r.code == "TITLE_OWNED" and acc.points.balance == bal, "bought twice -> TITLE_OWNED")
        local no = Q.Store.root().season.no
        local patron = "s" .. no .. "_patron"
        for _, id in ipairs({ "s" .. (no - 1) .. "_patron", "s" .. (no + 1) .. "_patron", "spend_5", "bogus", "streak_30" }) do
            r = cmd(p, "buyTitle", { id = id, pay = 1500 })
            T.check(r and r.code == "NOT_FOUND" and acc.titles[id] == nil and acc.points.balance == bal, "not on sale: " .. id)
        end
        set(Q, "shop.titles.season", 0)
        r = cmd(p, "buyTitle", { id = patron, pay = 1500 })
        T.check(r and r.code == "NOT_FOUND" and acc.titles[patron] == nil, "season 0: no season title on sale")
        set(Q, "shop.titles.season", nil)
        r = cmd(p, "buyTitle", { id = patron, pay = 1499 })
        T.check(r and r.code == "PRICE_CHANGED" and acc.titles[patron] == nil and acc.points.balance == bal, "wrong price")
        r = cmd(p, "buyTitle", { id = patron, pay = 1500 })
        T.check(r and r.ok and acc.titleSrc[patron] == "shop:" .. patron and acc.points.balance == bal - 1500,
            "this season's patron title")
        set(Q, "shop.titles.list.spend_2", 2400)
        r = cmd(p, "buyTitle", { id = "spend_2", pay = 2000 })
        T.check(r and r.code == "PRICE_CHANGED" and acc.titles.spend_2 == nil, "the list price is the server's")
        acc.points.balance = 100
        r = cmd(p, "buyTitle", { id = "spend_2", pay = 2400 })
        T.check(r and r.code == "NOT_ENOUGH_POINTS" and acc.titles.spend_2 == nil and acc.points.balance == 100,
            "not enough points: no title")
        acc.points.balance = 5000
        set(Q, "shop.titles.enabled", false)
        r = cmd(p, "buyTitle", { id = "spend_2", pay = 2400 })
        T.check(r and r.code == "SHOP_OFF" and acc.titles.spend_2 == nil, "switched off -> SHOP_OFF")
        set(Q, "shop", nil)
        Q.Store.readOnly = true
        r = cmd(p, "buyTitle", { id = "spend_2", pay = 2000 })
        Q.Store.readOnly = false
        T.check(r and r.code == "NOT_READY" and acc.titles.spend_2 == nil and acc.points.balance == 5000,
            "read-only store: no title")
        r = cmd(p, "buyTitle", { id = "spend_2", pay = 2000 })
        T.check(r and r.ok and acc.titles.spend_2 == true and acc.points.balance == 3000, "back to the default price")
    end)

    -- A spend request names the account's spendSeq its screen had; the server runs it only while that still is the
    -- account's and moves it on first. Nothing here rests on the result cache, on time or on the order of packets.
    section("a spend request is run at most once", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        Q.Points.award(acc, "alice", 5000, "admin", "t")
        local function flood()
            for i = 1, Q.Contract.LIMIT.CACHE_PER_ACTOR do
                T.advance(20)
                T.cmd(p, "anon", { on = i % 2 == 0 })
            end
        end
        local function states() return #T.sentTo(p, "state") end
        T.check(T.lastOf(p, "state").spendSeq == (acc.spendSeq or 0), "the full state carries the account's spendSeq")
        cmd(p, "swap", { slot = 1 })   -- the free one
        -- the same packet again: the cached answer while the cache holds it, STALE once it does not; never run twice
        local seq, rid = acc.spendSeq, T.newRequestId()
        local r1 = T.cmd(p, "swap", { slot = 1, pay = 50, seq = seq }, rid)
        local q1, bal = acc.day.quests[1], acc.points.balance
        local r2 = T.cmd(p, "swap", { slot = 1, pay = 50, seq = seq }, rid)
        T.check(r1 and r1.ok and acc.spendSeq == seq + 1 and r2 and r2.ok and r2.replay == true and acc.day.quests[1] == q1
            and acc.points.balance == bal, "the same packet inside the cache: the first answer, one swap, 50 taken once")
        flood()
        local n0 = states()
        local r3 = T.cmd(p, "swap", { slot = 1, pay = 50, seq = seq }, rid)
        T.check(r3 and r3.code == "STALE" and acc.day.quests[1] == q1 and acc.day.paid == 1 and acc.points.balance == bal
            and acc.spendSeq == seq + 1, "the same packet after the cache let go: STALE, nothing run, spendSeq not moved")
        T.check(states() == n0 + 1 and T.lastOf(p, "state").spendSeq == seq + 1, "STALE sends the state with the spendSeq to use")
        -- two requests made on one screen (the player confirmed again before the first answer showed): one runs
        seq = acc.spendSeq
        local ra = T.cmd(p, "swap", { slot = 2, pay = 50, seq = seq })
        local rb = T.cmd(p, "swap", { slot = 2, pay = 50, seq = seq })
        T.check(ra and ra.ok and rb and rb.code == "STALE" and acc.day.paid == 2 and acc.points.balance == bal - 50,
            "two requests of one screen, each with its own requestId: the second is STALE, 50 taken once")
        -- a refusal uses the request up too: it cannot run later when things have changed
        seq, bal = acc.spendSeq, acc.points.balance
        n0 = states()
        r1 = T.cmd(p, "buyTitle", { id = "spend_2", pay = 1, seq = seq })
        T.check(r1 and r1.code == "PRICE_CHANGED" and acc.spendSeq == seq + 1 and states() == n0 + 1,
            "a refusal moves spendSeq on and sends the state")
        r2 = T.cmd(p, "buyTitle", { id = "spend_2", pay = 2000, seq = seq })
        T.check(r2 and r2.code == "STALE" and acc.titles.spend_2 == nil and acc.points.balance == bal, "the old screen's request: STALE")
        r2 = T.cmd(p, "buyTitle", { id = "spend_2", pay = 2000 })
        T.check(r2 and r2.ok and acc.titles.spend_2 == true and acc.points.balance == bal - 2000, "asked again on the new state: bought")
        -- a command that fails after it paid cannot be run again by pressing again on the same screen
        Q.Server.define("tBoom", { kind = "mutation", spend = true, run = function(ctx)
            Q.Points.pay(Q.Store.account(ctx.user, true), ctx.user, 10, "swap", "boom")
            error("boom")
        end })
        seq, bal = acc.spendSeq, acc.points.balance
        r1 = T.cmd(p, "tBoom", { seq = seq })
        r2 = T.cmd(p, "tBoom", { seq = seq })
        T.check(r1 and r1.code == "INTERNAL" and r2 and r2.code == "STALE" and acc.points.balance == bal - 10
            and acc.spendSeq == seq + 1, "an error inside the command still used the request up: taken once, not twice")
        Q.Server.commands.tBoom = nil
        -- a command that takes points without spend = true fails at once (it would not be run-once)
        Q.Server.define("tSneak", { kind = "mutation", run = function(ctx)
            return Q.Points.pay(Q.Store.account(ctx.user, true), ctx.user, 10, "swap", "sneak")
        end })
        bal = acc.points.balance
        r1 = T.cmd(p, "tSneak", {})
        T.check(r1 and r1.code == "INTERNAL" and acc.points.balance == bal, "taking points outside a spend command: an error, nothing taken")
        Q.Server.commands.tSneak = nil
        -- what the server did not look at leaves spendSeq alone: bad arguments, a store that is not ready
        seq, bal = acc.spendSeq, acc.points.balance
        r1 = T.cmd(p, "buyShield", { pay = "x", seq = seq })
        Q.Store.readOnly = true
        rid = T.newRequestId()
        r2 = T.cmd(p, "buyShield", { pay = 200, seq = seq }, rid)
        Q.Store.readOnly = false
        T.check(r1 and r1.code == "BAD_ARGS" and r2 and r2.code == "NOT_READY" and acc.spendSeq == seq and acc.points.balance == bal,
            "BAD_ARGS and NOT_READY do not move spendSeq")
        r3 = T.cmd(p, "buyShield", { pay = 200, seq = seq }, rid)
        T.check(r3 and r3.ok and r3.replay == nil and acc.streak.shield == 1 and acc.points.balance == bal - 200,
            "NOT_READY is not kept as the answer: the same packet runs once the server is ready")
        -- a request without seq (an older client) is refused before anything is looked at
        seq = acc.spendSeq
        T.fire("OnClientCommand", Q.Contract.MODULE, "buyTitle", p,
            { protocol = Q.Contract.PROTOCOL, requestId = T.newRequestId(), id = "spend_1", pay = 1000 })
        T.check(T.lastOf(p, "result").code == "BAD_ARGS" and acc.titles.spend_1 == nil and acc.spendSeq == seq, "no seq: BAD_ARGS")
    end)

    section("a swap is for the quest the player saw", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        local q1 = acc.day.quests[1]
        local r = T.cmd(p, "swap", { slot = 1, at = q1.startMs + 1 })
        T.check(r and r.code == "STALE" and acc.day.quests[1] == q1 and acc.day.swaps == 1,
            "another quest in the slot than the one named: STALE, the quest and the free swap stay")
        r = T.cmd(p, "swap", { slot = 1, at = q1.startMs })
        T.check(r and r.ok and acc.day.quests[1] ~= q1, "the quest named is the one there: swapped")
    end)

    section("a settings change reaches an open window's state", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        cmd(p, "watch", { on = true })
        T.tick(12)   -- past Contract.LIMIT.DELTA_MS: the pending pushes are out
        T.clearOutbox()
        set(Q, "shop.shield.perWeek", 2)
        T.tick(12)
        local st = T.lastOf(p, "state")
        T.check(st ~= nil and st.streak.shieldLeft == 2, "the state worked out from the settings is pushed again")
    end)
end
