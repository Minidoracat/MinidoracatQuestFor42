-- Systems slice: Quests, Achievements/Import, Exchange, Seasons, Boards, Balance.
return function(T)
    local DAY = 86400000
    local ADMIN = { AdminRoles = "admin" }
    local function boot(opts)
        opts = opts or {}
        opts.sandbox = opts.sandbox or ADMIN
        local Q = T.boot(opts)
        T.now = Q.Clock.weekResetMs(T.now) + 60000      -- Monday, just after the reset
        local s = Q.Store.root().season
        s.startMs, s.endMs = Q.Clock.dayStartMs(T.now), nil
        T.tick(2)                                       -- first ticks (startup retry round etc.)
        return Q
    end

    -- spaced so the 5 s / 20 command rate limit and the default cooldown never interfere
    local function cmd(p, c, args, gap)
        T.advance(gap or 300)
        return T.cmd(p, c, args)
    end
    local function admin(p, op, args)
        args = args or {}
        args.op = op
        return cmd(p, "admin", args)
    end

    -- push a stat until the quest is done (respects per-minute ceilings)
    local function finish(Q, user, q)
        local def = Q.Stats.def(q.stat)
        local guard = 0
        while q.state == "active" and guard < 400 do
            guard = guard + 1
            if def.kind == "max" then
                local acc = Q.Store.account(user, false)
                Q.Stats.max(user, q.stat, (acc.total[q.stat] or 0) + (q.target - q.prog))
            else
                Q.Stats.add(user, q.stat, math.min(q.target - q.prog, def.ceil or 1000))
            end
            T.advance(61000)
        end
        return q.state == "done"
    end
    local function push(Q, user, stat, n)
        local def = Q.Stats.def(stat)
        while n > 0 do
            local step = math.min(n, def.ceil or n)
            Q.Stats.add(user, stat, step)
            n = n - step
            T.advance(61000)
        end
    end
    local function nextDay(Q, acc, user)
        T.now = Q.Clock.nextResetMs(T.now) + 60000
        Q.Quests.ensure(acc, user, T.now)
    end
    local function completeDay(Q, acc, user, n)
        local ok = true
        for i = 1, n do ok = finish(Q, user, acc.day.quests[i]) and ok end
        return ok
    end
    local function has(list, v)
        for _, x in ipairs(list) do if x == v then return true end end
        return false
    end
    local function section(name, fn)
        T.section("systems: " .. name)
        local ok, err = pcall(fn)
        if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
    end

    -- ===================== Quests =====================
    section("daily quests, prefs, swap", function()
        local Q = boot()
        local p = T.player{ name = "alice", admin = true }
        local bob = T.player{ name = "bob" }
        cmd(p, "hello")
        cmd(bob, "hello")
        local acc = Q.Store.account("alice", false)
        local qs = acc.day.quests
        T.check(acc.day.key == Q.Clock.dayKey(T.now), "hello generates today's quests")
        T.check(qs[1] and qs[2] and qs[3] and qs[4] and qs[4].shared == true and not qs[1].shared, "3 personal + 1 shared")
        local seen, distinct = {}, true
        for i = 1, 4 do
            if seen[qs[i].stat] then distinct = false end
            seen[qs[i].stat] = true
        end
        T.check(distinct, "no stat repeats within a day")
        local G = Q.Contract.THEME_GROUPS
        T.check(has(G[1], qs[1].theme) and has(G[2], qs[2].theme) and has(G[3], qs[3].theme), "no prefs: one per group")
        T.check(Q.Store.account("bob", false).day.quests[4].tid == qs[4].tid, "shared quest is the same for everyone")
        local tids = { qs[1].tid, qs[2].tid, qs[3].tid }
        acc.day = nil
        Q.Quests.ensure(acc, "alice", T.now)
        T.check(acc.day.quests[1].tid == tids[1] and acc.day.quests[3].tid == tids[3], "same user and day -> same quests")

        local r = cmd(p, "prefs", { themes = "combat,farm,cook,mech" })
        T.check(r and r.code == "TOO_MANY_PREFS", "4 preferences refused")
        r = cmd(p, "prefs", { themes = "combat,bogus" })
        T.check(r and r.code == "BAD_THEME", "unknown theme refused")
        local before = acc.day.quests[1].tid
        r = cmd(p, "prefs", { themes = "farm, cook" })
        T.check(r and r.ok and #acc.prefs == 2 and acc.prefs[1] == "farm", "prefs saved")
        T.check(acc.day.quests[1].tid == before, "today's quests unchanged after prefs (C4)")
        T.check(T.lastOf(p, "state") ~= nil, "mutation pushes state")

        r = cmd(p, "swap", { slot = 4 })
        T.check(r and r.code == "BAD_SLOT", "shared quest cannot be swapped")
        local old = acc.day.quests[1]
        r = cmd(p, "swap", { slot = 1 })
        T.check(r and r.ok and old.state == "swapped" and acc.day.quests[1] ~= old and acc.day.quests[1].state == "active",
            "swap replaces slot 1")
        T.check(acc.day.quests[1].stat ~= old.stat and acc.day.quests[1].stat ~= acc.day.quests[2].stat, "swap keeps stats distinct")
        r = cmd(p, "swap", { slot = 2 })
        T.check(r and r.code == "NO_SWAPS", "second swap refused (swapsPerDay = 1)")

        nextDay(Q, acc, "alice")
        local t1, t2 = acc.day.quests[1].theme, acc.day.quests[2].theme
        T.check((t1 == "farm" or t1 == "cook") and (t2 == "farm" or t2 == "cook"), "next day: 2 slots from prefs "
            .. acc.day.quests[1].tid .. "," .. acc.day.quests[2].tid .. "," .. acc.day.quests[3].tid .. " shared " .. acc.day.quests[4].tid)
        T.check(acc.day.swaps == 1, "swaps reset each day")
        -- a delta only carries progress: across the reset an open window gets the new list as a full state
        local Qq = Q.Quests
        Qq.lastTick, Qq.tickDay, Qq.tickWeek = 0, Qq.keys(T.now)
        Q.Sync.watch("alice", true)
        Q.Sync.dirtyMap.alice = nil
        T.now = Q.Clock.nextResetMs(T.now) + 60000
        Qq.tick(T.now)
        T.check(Q.Sync.dirtyMap.alice and Q.Sync.dirtyMap.alice.all and acc.day.key == Qq.keys(T.now),
            "the daily reset moves an open window to the new quests with a full state")
        Q.Sync.watch("alice", false)

        -- slots 1 and 2 stay in the preferred themes when one runs dry: cooking has two stats and the shared quest
        -- takes one, so a second cooking slot must go to farming (it went to any theme before 2026-10-25)
        Q.Store.root().shared = { day = Q.Clock.dayKey(T.now), done = 0, tid = "d_cook", stat = "cook.count",
            theme = "cook", target = 5, pts = 20 }
        local off = 0
        for n = 1, 100 do
            local a = Q.Store.account("pref" .. n, true)
            a.prefs, a.day = { "cook", "farm" }, nil
            Q.Quests.ensure(a, "pref" .. n, T.now)
            for s = 1, 2 do
                local th = a.day.quests[s] and a.day.quests[s].theme
                if th ~= "cook" and th ~= "farm" then off = off + 1 end
            end
        end
        T.check(off == 0, "a preferred theme that runs dry hands its slot to the other preferred theme (" .. off .. " off)")
    end)

    -- owner 2026-10-27: an xp.<Perk> daily only for a skill with an XP boost below level 10; offline = not eligible
    section("xp dailies: boosted skills below level 10 only, in generation and swaps", function()
        local Q = boot()
        local Qq = Q.Quests
        local M = Perks.Mechanics
        local function pl(name, boost, level)
            return T.player{ name = name, boosts = { [M] = boost }, perks = { [M] = level } }
        end
        T.check(Qq.xpEligible(pl("e1", 1, 9), "Mechanics") == true, "boost 1, level 9: eligible")
        T.check(Qq.xpEligible(pl("e2", 0, 5), "Mechanics") == false, "no boost: not eligible")
        T.check(Qq.xpEligible(pl("e3", 3, 10), "Mechanics") == false, "level 10: not eligible")
        T.check(Qq.xpEligible(nil, "Mechanics") == false, "no player (offline): not eligible")
        local function isXp(q) return q ~= nil and string.sub(q.stat, 1, 3) == "xp." end
        -- n accounts preferring mech (two slots from it); mk(user) puts the player online, nil = offline
        local function run(prefix, mk)
            local gen, swapped = 0, 0
            for n = 1, 60 do
                local user = prefix .. n
                if mk then mk(user) end
                local a = Q.Store.account(user, true)
                a.prefs, a.day = { "mech" }, nil
                Qq.ensure(a, user, T.now)
                for i = 1, 3 do if isXp(a.day.quests[i]) then gen = gen + 1 end end
                if isXp(a.day.quests[1]) then a.day.quests[1].stat = "mech.none" end   -- so the swap may pick it again
                Qq.swap(a, user, 1)
                if isXp(a.day.quests[1]) then swapped = swapped + 1 end
            end
            return gen, swapped
        end
        local gen, swapped = run("off")
        T.check(gen == 0 and swapped == 0, "offline: no xp daily, generated or swapped in (" .. gen .. ", " .. swapped .. ")")
        gen, swapped = run("max", function(u) pl(u, 3, 10) end)
        T.check(gen == 0 and swapped == 0, "level 10 with a boost: no xp daily (" .. gen .. ", " .. swapped .. ")")
        gen, swapped = run("nob", function(u) pl(u, 0, 3) end)
        T.check(gen == 0 and swapped == 0, "no boost: no xp daily (" .. gen .. ", " .. swapped .. ")")
        gen, swapped = run("ok", function(u) pl(u, 2, 3) end)
        T.check(gen > 0 and swapped > 0, "boosted below 10: xp dailies still come, generated and swapped in ("
            .. gen .. ", " .. swapped .. ")")
        -- a day drawn while the player was away (a goal or season payout feeds offline accounts) is drawn again once
        -- the player is online, so xp dailies can come; a day with progress keeps its quests
        local again, flagged, kept = 0, 0, 0
        for n = 1, 60 do
            local user = "late" .. n
            local a = Q.Store.account(user, true)
            a.prefs, a.day = { "mech" }, nil
            Qq.ensure(a, user, T.now)
            if a.day.offline then flagged = flagged + 1 end
            pl(user, 2, 3)
            Qq.ensure(a, user, T.now)
            if a.day.offline then flagged = flagged + 100 end
            for i = 1, 3 do if isXp(a.day.quests[i]) then again = again + 1 end end
        end
        T.check(flagged == 60 and again > 0, "a day drawn offline is drawn again at login; xp dailies come ("
            .. flagged .. ", " .. again .. ")")
        local given, og = 0, Q.Balance.given
        Q.Balance.given = function(...) given = given + 1 return og(...) end
        local a = Q.Store.account("busy", true)
        a.day = nil
        Qq.ensure(a, "busy", T.now)
        local dayN, n0 = a.day.quests[4] and 4 or 3, given - #a.week.quests   -- the new week counts its quests too
        local q1 = a.day.quests[1]
        Qq.onStat(a, "busy", q1.stat, 0)   -- Stats.max reports delta 0 when the season value does not move
        T.check(a.day.offline == true and given - #a.week.quests == 0, "a zero delta leaves a day drawn offline uncounted")
        Q.Stats.add("busy", q1.stat, 1)
        local n1 = given - #a.week.quests
        T.check(n0 == 0 and q1.prog == 1 and not a.day.offline and n1 == dayN,
            "a day drawn offline counts as given at its first progress (" .. n0 .. ", " .. n1 .. ")")
        pl("busy", 2, 3)
        Qq.ensure(a, "busy", T.now)
        T.check(a.day.quests[1] == q1 and q1.prog == 1 and given - #a.week.quests == dayN,
            "a day drawn offline that already has progress keeps its quests at login, counted once")
        Q.Balance.given = og
        -- a pack's xp.<Perk> daily (no shared flag) never becomes the shared quest, which everyone gets
        T.check(Q.v1.registerPack({ modId = "XpPack", quests = { { id = "mechxp", stat = "xp.Mechanics", theme = "mech",
            target = { 50, 100 }, points = 15, nameKey = "IGUI_XpPack_MechXp" } } }) ~= nil, "pack with an xp daily")
        local cfg, xpShared = Q.Config.get(), 0
        for k = 1, 200 do
            Q.Store.root().shared = nil
            if isXp(Qq.sharedToday("d" .. k, cfg)) then xpShared = xpShared + 1 end
        end
        T.check(xpShared == 0, "a pack's xp daily is never the shared quest (" .. xpShared .. " of 200 days)")
    end)

    section("progress, streak, grace, weekly", function()
        local Q = boot()
        local p = T.player{ name = "alice" }
        cmd(p, "hello")
        local acc = Q.Store.account("alice", false)
        local q = acc.day.quests[1]
        local pts0 = acc.points.season
        Q.Stats.add("alice", q.stat == "zombie.kills" and "craft.count" or "zombie.kills", 1)
        T.check(q.prog == 0, "other stats do not move a quest")
        T.check(finish(Q, "alice", q), "quest completes from stat increments")
        T.check(acc.points.season >= pts0 + q.pts and acc.day.done >= 1, "completion awards points and counts")
        local prog = q.prog
        Q.Stats.add("alice", q.stat, 1)
        T.check(q.prog == prog and q.state == "done", "done quest stops counting")

        -- Monday: 3 of 4
        completeDay(Q, acc, "alice", 3)
        T.check(acc.streak.days == 1 and acc.streak.last == acc.day.key, "3 of 4 counts a streak day")
        T.check((acc.total["quest.daily"] or 0) >= 3, "quest.daily fed")
        T.check(acc.life["quest.daily"] == nil and (acc.season["quest.daily"] or 0) >= 3,
            "account-level stat: no life scope (records show -)")
        local ss = Q.Quests.stateStreak(acc, "alice", T.now)
        T.check(ss.today == Q.Clock.weekday(T.now) and ss.week[ss.today] == "done",
            "streak state marks today (Clock.weekday) and today's dot is done")
        nextDay(Q, acc, "alice")                      -- Tue
        completeDay(Q, acc, "alice", 3)
        nextDay(Q, acc, "alice")                      -- Wed
        local bal = acc.points.balance
        local before = acc.points.balance
        completeDay(Q, acc, "alice", 2)
        local twoQuests = acc.points.balance - before
        before = acc.points.balance
        local third = acc.day.quests[3].pts
        completeDay(Q, acc, "alice", 3)
        T.check(acc.streak.days == 3 and acc.streak.paid[3] == true, "3-day milestone")
        T.check(acc.points.balance - before >= third + 15, "milestone pays 15")
        nextDay(Q, acc, "alice")                      -- Thu: skipped
        nextDay(Q, acc, "alice")                      -- Fri
        T.check(acc.streak.days == 4 and acc.streak.graceUsed == true, "one missed day uses the weekly grace")
        local st = Q.Quests.stateStreak(acc, "alice", T.now)
        T.check(st.week[1] == "done" and st.week[4] == "grace" and st.week[5] == "", "streak dots")
        completeDay(Q, acc, "alice", 3)
        T.check(acc.streak.days == 5, "day after grace counts")
        nextDay(Q, acc, "alice")                      -- Sat: skipped
        nextDay(Q, acc, "alice")                      -- Sun
        T.check(acc.streak.days == 0 and acc.streak.paid[3] == nil, "second miss in a week resets (milestones reopen)")
        T.check((acc.total["streak.best"] or 0) == 5, "streak.best keeps the best run")
        nextDay(Q, acc, "alice")                      -- next Monday
        T.check(acc.streak.graceUsed == false, "grace resets on Monday")
        local w = acc.week.quests[1]
        T.check(#acc.week.quests == 3 and acc.week.key == Q.Clock.weekKey(T.now), "3 weekly quests")
        before = acc.points.season
        T.check(finish(Q, "alice", w) and acc.points.season - before >= w.pts, "weekly quest pays")
        T.check(bal ~= nil and twoQuests > 0, "points accrue")
        nextDay(Q, acc, "alice")
        acc.streak.days = 29
        completeDay(Q, acc, "alice", 3)
        T.check(acc.streak.days == 30 and acc.titles.streak_30 == true and acc.titleAt and acc.titleAt.streak_30 ~= nil
            and acc.titleAt.streak_30 <= T.now, "the 30-day milestone gives its title and records the time")
        T.check(acc.titleSrc and acc.titleSrc.streak_30 == "streak:30", "the streak title records its source")
    end)

    section("shared quest, community goal, newbie, events", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        local c = T.player{ name = "carol" }
        for _, p in ipairs({ a, b, c }) do cmd(p, "hello") end
        local accA, accB, accC = Q.Store.account("alice"), Q.Store.account("bob"), Q.Store.account("carol")
        local root = Q.Store.root()
        T.check(finish(Q, "bob", accB.day.quests[4]) and root.shared.done == 1, "shared done count")

        local g = root.goal
        T.check(g and g.week == accA.week.key and g.target >= 1, "goal of the week exists")
        g.target, g.minContrib = g.progress + 10, 5
        local pa, pc = accA.points.balance, accC.points.balance
        push(Q, "alice", g.stat, 10)
        T.check(g.reached and accA.week.goalPaid == true, "goal reached pays contributors")
        T.check(accC.week.goalPaid ~= true, "non-contributor not paid")
        T.check(accA.points.balance - pa >= 50, "goal pays 50")
        push(Q, "carol", g.stat, 5)
        T.check(accC.week.goalPaid == true and accC.points.balance - pc >= 50, "late contributor paid on reaching minContrib")

        local d = T.player{ name = "dave", hours = 1 }
        cmd(d, "hello")
        local accD = Q.Store.account("dave")
        T.check(accD.newbie ~= nil, "new account gets newbie steps")
        T.check(accA.newbie == nil, "veteran (24h+) skips newbie")
        for _, step in ipairs(Q.Catalog.newbie) do push(Q, "dave", step.stat, step.target) end
        T.check(accD.newbie == nil and accD.titles.newbie == true and accD.points.total >= 100, "newbie completes with title")
        T.check(type(accD.titleAt) == "table" and accD.titleAt.newbie ~= nil and accD.titleAt.newbie <= T.now,
            "the newbie title records when it came (titleAt, plan r13)")
        T.check(accD.titleSrc and accD.titleSrc.newbie == "newbie", "the newbie title records its source")

        local r = admin(b, "event.add", { name = "x", theme = "all", mult = 2, startMs = T.now - 1000, endMs = T.now + DAY })
        T.check(r and r.code == "FORBIDDEN", "non-admin event.add refused")
        r = admin(a, "event.add", { name = "Halloween", theme = "all", mult = 2, startMs = T.now - 1000, endMs = T.now + DAY })
        T.check(r and r.ok and r.id == 1, "event added")
        r = admin(a, "event.add", { name = "x", theme = "nope", mult = 2, startMs = T.now, endMs = T.now + DAY })
        T.check(r and r.code == "BAD_THEME", "event theme checked")
        admin(a, "event.add", { name = "e2", theme = "combat", mult = 1.5, startMs = T.now, endMs = T.now + DAY })
        admin(a, "event.add", { name = "e3", theme = "farm", mult = 3, startMs = T.now + DAY, endMs = T.now + 2 * DAY })
        r = admin(a, "event.add", { name = "e4", theme = "farm", mult = 3, startMs = T.now, endMs = T.now + DAY })
        T.check(r and r.code == "BAD_ARGS", "at most 3 events")
        local q = accA.day.quests[2]
        local shown = Q.Quests.stateDay(accA, "alice", T.now).quests[2].ptsNow
        T.check(shown == math.floor(q.pts * Q.Quests.eventMult(q.theme, T.now) + 0.5) and shown >= q.pts * 2,
            "state ptsNow = base x running event (" .. tostring(shown) .. ")")
        local before = accA.points.season
        finish(Q, "alice", q)
        T.check(accA.points.season - before >= q.pts * 2, "event doubles quest points")
        T.check(q.got == shown and Q.Quests.stateDay(accA, "alice", T.now).quests[2].ptsNow == shown,
            "shown ptsNow = the payout, and stays after completion")
        T.check(#Q.Quests.stateEvents(accA, "alice", T.now) == 2, "state lists running events")
        Q.Quests.watchEvents(T.now)   -- the server tick has seen events 1 and 2 running
        r = admin(a, "event.remove", { id = 99 })
        T.check(r and r.code == "NOT_FOUND", "remove unknown event")
        r = admin(a, "event.remove", { id = 1 })
        T.check(r and r.ok and #root.events == 2, "event removed")
        admin(a, "event.remove", { id = 2 })
        Q.Sync.watch("alice", true)
        Q.Sync.dirtyMap.alice = nil
        Q.Quests.watchEvents(T.now)
        T.check(Q.Sync.dirtyMap.alice and Q.Sync.dirtyMap.alice.events, "an event ending pushes a full state")
        local q3 = accA.day.quests[3]
        T.check(q3.state == "active" and Q.Quests.stateDay(accA, "alice", T.now).quests[3].ptsNow == q3.pts,
            "no event running: ptsNow back to the base points")
    end)

    -- ===================== Achievements / Import =====================
    section("achievements, broadcast, revoke, import", function()
        local Q = boot()
        local casts = {}
        local orig = Q.Sync.broadcastToast
        Q.Sync.broadcastToast = function(t, who) casts[#casts + 1] = t return orig(t, who) end
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        cmd(a, "hello")
        cmd(b, "hello")
        local acc = Q.Store.account("alice")
        local def = Q.Achievements.get("zombie_kills")
        T.check(def and #def.tiers >= 3, "zombie_kills in the effective list")
        local total0 = acc.points.total
        push(Q, "alice", "zombie.kills", def.tiers[3])
        T.check(acc.achv.zombie_kills == 3, "several tiers unlock at once")
        T.check(acc.points.total - total0 >= def.pts[1] + def.pts[2] + def.pts[3], "each tier pays")
        local n3 = 0
        for _, t in ipairs(casts) do if t.id == "zombie_kills" and t.tier == 3 and t.who == "alice" then n3 = n3 + 1 end end
        local low = 0
        for _, t in ipairs(casts) do if t.id == "zombie_kills" and t.tier < 3 then low = low + 1 end end
        T.check(n3 == 1 and low == 0, "only tier >= minTier is broadcast")
        T.check((acc.total["achv.tiers"] or 0) >= 3, "achv.tiers fed")

        local r = admin(b, "achv.revoke", { user = "alice", achId = "zombie_kills", tier = 1, reason = "x" })
        T.check(r and r.code == "FORBIDDEN", "non-admin revoke refused")
        r = admin(a, "achv.revoke", { user = "alice", achId = "zombie_kills", tier = 1, reason = "" })
        T.check(r and r.code == "BAD_ARGS", "revoke needs a reason")
        local before = acc.points.total
        r = admin(a, "achv.revoke", { user = "alice", achId = "zombie_kills", tier = 1, reason = "macro" })
        T.check(r and r.ok and acc.achv.zombie_kills == 1, "revoked to tier 1")
        T.check(before - acc.points.total == def.pts[2] + def.pts[3], "revoke takes the tier points back")
        push(Q, "alice", "zombie.kills", 1)
        T.check(acc.achv.zombie_kills == 1, "same stat value does not re-unlock")

        Q.Sync.broadcastToast = orig
        casts = {}
        Q.Sync.broadcastToast = function(t, who) casts[#casts + 1] = t return orig(t, who) end
        local e = T.player{ name = "eve", kills = 6000, hours = 100, perks = { [Perks.Woodwork] = 5 } }
        cmd(e, "hello")
        local ae = Q.Store.account("eve")
        T.check(ae.imported == true and (ae.achv.zombie_kills or 0) >= 3, "import unlocks from old progress")
        T.check(ae.points.season == 0 and ae.points.balance == 0 and ae.points.total > 0, "import: lifetime points only")
        T.check(ae.total["level.Woodwork"] == 5 and ae.newbie == nil, "import seeds skills, veteran skips newbie")
        T.check(#casts == 0, "import does not broadcast")
        local t0 = ae.points.total
        Q.Import.baseline(ae, "eve", e)
        T.check(ae.points.total == t0, "import runs once")
        Q.Sync.broadcastToast = orig
    end)

    section("five tiers: tier V, skill title at level 8, login catch-up", function()
        local Q = boot()
        local casts = {}
        local orig = Q.Sync.broadcastToast
        Q.Sync.broadcastToast = function(t, who) casts[#casts + 1] = t return orig(t, who) end
        local function count(t)
            local n = 0
            for _ in pairs(t or {}) do n = n + 1 end
            return n
        end
        local a = T.player{ name = "alice" }
        cmd(a, "hello")
        local acc = Q.Store.account("alice")
        local sk = Q.Achievements.get("skill_axe")
        T.check(#sk.tiers == 5 and sk.tiers[4] == 8 and sk.tiers[5] == 10 and sk.pts[5] == 80
            and sk.titles[4] == "skill_axe_4" and sk.titles[5] == nil, "skill_axe: 5 tiers, title at IV = level 8")
        Q.Stats.max("alice", "level.Axe", 7)
        T.check(acc.achv.skill_axe == 3 and not (acc.titles or {}).skill_axe_4, "level 7: tier III, no title yet")
        Q.Stats.max("alice", "level.Axe", 8)
        T.check(acc.achv.skill_axe == 4 and acc.titles.skill_axe_4 == true, "level 8: tier IV gives the title")
        local at4 = acc.titleAt and acc.titleAt.skill_axe_4
        T.check(at4 == T.now, "the tier IV title records the grant time")
        T.advance(5000)
        Q.Store.grantTitle(acc, "skill_axe_4")
        T.check(acc.titleAt.skill_axe_4 == at4, "granting an owned title again keeps the first time")
        local pts0, nTitles = acc.points.total, count(acc.titles)
        Q.Stats.max("alice", "level.Axe", 10)
        T.check(acc.achv.skill_axe == 5 and acc.points.total - pts0 == 80 and count(acc.titles) == nTitles,
            "level 10: tier V pays 80 and gives no new title")

        -- an account from the 4-tier days: Cooking 10 held old tier IV (title), 10 towns held old tier III
        local b = T.player{ name = "bob" }
        cmd(b, "hello")
        local accB = Q.Store.account("bob")
        accB.total["level.Cooking"], accB.achv.skill_cooking = 10, 4
        accB.titles = accB.titles or {}
        accB.titles.skill_cooking_4 = true
        accB.total["town.visited"], accB.achv.towns = 10, 3
        local p0, season0 = accB.points.total, accB.points.season
        casts = {}
        T.clearOutbox(b)
        cmd(b, "hello")
        T.check(accB.achv.skill_cooking == 5 and accB.achv.towns == 4 and accB.titles.towns_4 == true,
            "login catch-up: the tiers the new defaults give")
        T.check(accB.titleAt and accB.titleAt.towns_4 ~= nil and accB.titleAt.towns_4 <= T.now and accB.titleAt.skill_cooking_4 == nil,
            "a quiet catch-up title gets a time; a title owned before titleAt existed stays without one")
        T.check(accB.points.total - p0 == 80 + 50 and accB.points.season - season0 == 80 + 50,
            "catch-up pays only the new tiers, as normal achievement points")
        local bcast = 0
        for _, t in ipairs(casts) do if t.who == "bob" then bcast = bcast + 1 end end
        T.check(bcast == 0, "catch-up is not announced server-wide")
        T.advance(3000)
        T.tick(1)
        local toast = T.lastOf(b, "toast")
        T.check(toast ~= nil and (toast.kind == "achvMany" or toast.kind == "achv"), "catch-up toasts the player")
        local p1 = accB.points.total
        cmd(b, "hello")
        T.check(accB.points.total == p1 and accB.achv.skill_cooking == 5, "the next login pays nothing twice")
        Q.Sync.broadcastToast = orig
    end)

    -- owner 2026-10-27: titles record their source (titleSrc) and revoke goes by it; a cleared tier title grants
    -- nothing; a switched-off achievement can be revoked
    section("title sources, cleared tier titles, revoking a switched-off achievement", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        cmd(a, "hello")
        cmd(b, "hello")
        local acc = Q.Store.account("bob")
        local zk = Q.Achievements.get("zombie_kills")
        push(Q, "bob", "zombie.kills", zk.tiers[4])
        T.check(acc.achv.zombie_kills == 4 and acc.titles.zombie_kills_4 == true and type(acc.titleSrc) == "table"
            and acc.titleSrc.zombie_kills_4 == "a:zombie_kills:4", "the tier IV title records its source")
        local st = Q.Sync.state("bob", acc)
        T.check(type(st.titleSrc) == "table" and st.titleSrc.zombie_kills_4 == "a:zombie_kills:4", "state carries titleSrc")
        Q = boot({ keepGmd = true, keepFiles = true })
        acc = Q.Store.account("bob")
        local shape = type(acc.titleSrc) == "table"
        for k, v in pairs(acc.titleSrc or {}) do
            if type(k) ~= "string" or type(v) ~= "string" then shape = false end
        end
        T.check(shape and acc.titleSrc.zombie_kills_4 == "a:zombie_kills:4", "titleSrc survives a restart: title id -> source")
        a = T.player{ name = "alice", admin = true }
        b = T.player{ name = "bob" }
        cmd(a, "hello")
        cmd(b, "hello")
        local function setTitles(id, json)
            local r = admin(a, "cfg.apply", { summary = "t",
                changes = '[{"op":"set","path":"achievements.' .. id .. '.titles","value":' .. json .. '}]' })
            return r and r.ok
        end

        -- renamed twice after the grant: the revoke still takes the title the tier gave
        T.check(setTitles("zombie_kills", '{"4":"Slayer"}') and setTitles("zombie_kills", '{"4":"Reaper"}'), "renamed twice")
        local r = admin(a, "achv.revoke", { user = "bob", achId = "zombie_kills", tier = 3, reason = "macro" })
        T.check(r and r.ok and acc.titles.zombie_kills_4 == nil and acc.titleSrc.zombie_kills_4 == nil
            and acc.titleAt.zombie_kills_4 == nil, "revoke drops the title the tier granted, renamed since")

        -- no record (granted before titleSrc): the configured id and the built-in default go; a title another
        -- source granted stays
        local c = Q.Store.account("carol", true)
        c.achv.zombie_kills, c.titles = 4, { zombie_kills_4 = true, Reaper = true }
        r = admin(a, "achv.revoke", { user = "carol", achId = "zombie_kills", tier = 3, reason = "legacy" })
        T.check(r and r.ok and c.titles.zombie_kills_4 == nil and c.titles.Reaper == nil,
            "a legacy title without a record: the default id and the configured id both go")
        local dv = Q.Store.account("dave", true)
        dv.achv.zombie_kills, dv.titles, dv.titleSrc = 4, { Reaper = true }, { Reaper = "streak:30" }
        r = admin(a, "achv.revoke", { user = "dave", achId = "zombie_kills", tier = 3, reason = "other" })
        T.check(r and r.ok and dv.titles.Reaper == true, "the same text granted by another source stays")

        -- cleared in the editor: the whole titles map replaces the default, so tier IV grants no title
        T.check(setTitles("towns", "{}") and Q.Achievements.get("towns").titles[4] == nil, "a cleared tier title is gone")
        local tw = Q.Achievements.get("towns")
        local e = Q.Store.account("erin", true)
        e.total[tw.stat] = tw.base[4]
        Q.Achievements.evaluate(e, "erin", { noBroadcast = true })
        T.check(e.achv.towns == 4 and not (e.titles or {}).towns_4, "tier IV unlocks without the cleared title")

        -- switched off: still revocable (it answered NOT_FOUND)
        acc.achv.zombie_kills, acc.titles.zombie_kills_4, acc.titleSrc.zombie_kills_4 = 4, true, "a:zombie_kills:4"
        T.check(Q.Config.apply({ { op = "set", path = "achievements.zombie_kills.enabled", value = false } }, "off", "alice")
            and Q.Achievements.get("zombie_kills") == nil, "zombie_kills switched off")
        r = admin(a, "achv.revoke", { user = "bob", achId = "zombie_kills", tier = 0, reason = "off" })
        T.check(r and r.ok and acc.achv.zombie_kills == nil and acc.titles.zombie_kills_4 == nil,
            "a switched-off achievement can be revoked, with its title")
    end)

    -- ===================== Exchange =====================
    section("exchange", function()
        local credits, results = {}, {}
        local fake = { v1 = { API_MAJOR = 1, API_REVISION = 1, registerSource = function(spec)
            T.check(spec.modId == "MinidoracatQuestFor42" and spec.reasonCodes[1] == "mq_exchange", "registerSource spec")
            return { credit = function(u, cur, n, opts)
                credits[#credits + 1] = { u = u, cur = cur, n = n, rid = opts.requestId, reason = opts.reasonCode }
                return table.remove(results, 1) or { ok = true }
            end }
        end } }
        local Q = boot({ economy = fake })
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        cmd(a, "hello")
        cmd(b, "hello")
        local acc = Q.Store.account("alice")
        Q.Points.award(acc, "alice", 500, "admin")
        Q.Points.award(Q.Store.account("bob"), "bob", 15, "admin")
        T.check(Q.Exchange.available(), "economy detected")
        local r = cmd(a, "exchange", { amount = 5 }, 3100)
        T.check(r and r.code == "EXCHANGE_MIN", "below min refused")
        r = cmd(a, "exchange", { amount = 150 }, 3100)
        T.check(r and r.code == "EXCHANGE_DAY_LIMIT", "over daily limit refused")
        r = cmd(b, "exchange", { amount = 20 }, 3100)
        T.check(r and r.code == "NOT_ENOUGH_POINTS", "over balance refused")
        r = cmd(a, "exchange", { amount = 40 }, 3100)
        T.check(r and r.ok and r.state == "paid" and r.coins == 40 and acc.points.balance == 460, "paid exchange")
        T.check(credits[1] and credits[1].rid == "ex:alice:1" and credits[1].cur == "survivor" and credits[1].reason == "mq_exchange",
            "credit requestId and reason")
        r = cmd(a, "exchange", { amount = 10 }, 300)
        T.check(r == nil, "exchange cooldown drops the request")

        results[1] = { ok = false, error = "cap_exceeded" }
        r = cmd(a, "exchange", { amount = 30 }, 3100)
        T.check(r and r.ok and r.state == "queued" and acc.points.balance == 430 and #acc.ex.queue == 1, "cap -> queued, points held")
        local h = Q.Exchange.stateFor(acc, "alice", T.now).hist
        T.check(#h == 2 and h[1].state == "queued" and h[1].amount == 30 and h[2].state == "paid" and h[2].amount == 40,
            "history: the queued exchange first, then the paid one")
        local n = #credits
        T.tick(20)
        T.check(#credits == n, "no retry before the hour")
        T.advance(3600000)
        T.tick(2)
        T.check(#credits == n + 1 and credits[n + 1].rid == "ex:alice:2" and #acc.ex.queue == 0, "hourly retry keeps the requestId")
        T.check(acc.points.balance == 430, "retry does not charge again")

        results[1] = { ok = false, error = "account_frozen" }
        r = cmd(a, "exchange", { amount = 20 }, 3100)
        T.check(r and r.ok and r.state == "refunded" and acc.points.balance == 430, "refusal refunds points")
        T.check(acc.ex.used == 70, "refund returns the daily quota")
        local refused = false
        for _, it in ipairs(Q.Store.root().audit.items) do if it.kind == "exchange_refused" then refused = true end end
        T.check(refused, "refusal audited")
        h = Q.Exchange.stateFor(acc, "alice", T.now).hist
        T.check(#h == 3 and h[1].state == "refunded" and h[1].amount == 20 and h[2].state == "paid" and h[2].amount == 30
            and h[2].at > h[3].at, "history: newest first, the retried exchange counted as paid when it was paid")
        r = cmd(a, "exchange", { amount = 40 }, 3100)
        T.check(r and r.code == "EXCHANGE_DAY_LIMIT", "quota counts paid + queued")
        r = admin(a, "ex.status")
        T.check(r and r.ok and r.ecAvailable == true and r.todayCoins == 70 and r.min == 10, "ex.status")
        T.check(r.estimate == 70 and r.ecCap == nil and r.ecUsed == nil and r.ecEnabled == nil and r.warn == "unknown",
            "no sourceStatus: Economy limits unknown")
        local ss = nil
        fake.v1.sourceStatus = function(modId)
            T.check(modId == "MinidoracatQuestFor42", "sourceStatus asked for this mod")
            return ss
        end
        r = Q.Exchange.status(T.now)
        T.check(r.ecCap == nil and r.warn == "unknown", "sourceStatus nil -> unknown")
        ss = { enabled = true, dailyMintCap = 1000, mintToday = 70, day = "20261023" }
        r = admin(a, "ex.status")
        T.check(r and r.ecCap == 1000 and r.ecUsed == 70 and r.ecEnabled == true and r.warn == nil, "Economy cap read, no warning")
        ss = { enabled = true, dailyMintCap = 0, mintToday = 0 }
        T.check(Q.Exchange.status(T.now).warn == "cap_zero", "cap 0 warns")
        ss = { enabled = true, dailyMintCap = 50, mintToday = 0 }
        T.check(Q.Exchange.status(T.now).warn == "over_cap", "estimate over cap warns")
        ss = { enabled = false, dailyMintCap = 1000, mintToday = 0 }
        r = Q.Exchange.status(T.now)
        T.check(r.warn == "disabled" and r.ecEnabled == false, "disabled source warns")
        fake.v1.sourceStatus = function() error("boom") end
        T.check(Q.Exchange.status(T.now).warn == "unknown", "sourceStatus error -> unknown")
        fake.v1.sourceStatus = nil
        local st = Q.Exchange.stateFor(acc, "alice", T.now)
        T.check(st.available and st.used == 70, "state.exchange")
        for i = 1, 12 do acc.ex.log[i] = acc.ex.log[i] or { at = 0, amount = 10, coins = 10, state = "paid" } end
        acc.ex.day = nil   -- a new day: quota free again
        r = cmd(a, "exchange", { amount = 10 }, 3100)
        T.check(r and r.state == "paid" and #acc.ex.log == Q.Exchange.LOG and acc.ex.log[1].amount == 10
            and acc.ex.log[2].state == "refunded", "history keeps the newest " .. Q.Exchange.LOG)

        Q = boot()
        local c = T.player{ name = "carol" }
        cmd(c, "hello")
        Q.Points.award(Q.Store.account("carol"), "carol", 100, "admin")
        r = cmd(c, "exchange", { amount = 20 }, 3100)
        T.check(r and r.code == "ECONOMY_MISSING" and Q.Store.account("carol").points.balance == 100, "no economy: exchange off")
        r = Q.Exchange.status(T.now)
        T.check(r.ecCap == nil and r.warn == nil and r.ecAvailable == false, "no economy: no cap warning")
        Q = boot({ sp = true, economy = fake })
        T.check(not Q.Exchange.available(), "single player: exchange off")
    end)

    -- ===================== Seasons =====================
    section("seasons", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        local c = T.player{ name = "carol" }
        for _, p in ipairs({ a, b, c }) do cmd(p, "hello") end
        local r = admin(b, "season.preview", { days = 14 })
        T.check(r and r.code == "FORBIDDEN", "non-admin season op refused")
        r = admin(a, "season.preview", { days = 5 })
        T.check(r and r.code == "BAD_SEASON_LENGTH", "below 7 days refused")
        r = admin(a, "season.preview", { days = 181 })
        T.check(r and r.code == "BAD_SEASON_LENGTH", "above 180 days refused")
        r = admin(a, "season.preview", { days = 14 })
        local s = Q.Store.root().season
        T.check(r and r.ok and r.endMs == r.nextStartMs and r.endMs > T.now + DAY, "preview")
        T.check(s.lengthDays == 28, "preview changes nothing")
        r = admin(a, "season.apply", { days = 7 })
        T.check(r and r.ok and s.lengthDays == 7 and s.endMs == r.endMs, "apply length")
        T.check((r.endMs - Q.Clock.nextResetMs(r.endMs - 1)) == 0, "season ends at a daily reset")
        T.now = s.endMs - DAY / 2
        r = admin(a, "season.preview", { days = 7 })
        T.check(r and r.code == "TOO_SOON", "new end within 24 hours refused")

        local accA, accB, accC = Q.Store.account("alice"), Q.Store.account("bob"), Q.Store.account("carol")
        Q.Points.award(accA, "alice", 700, "admin")
        Q.Points.award(accB, "bob", 300, "admin")
        Q.Points.award(accC, "carol", 100, "admin")
        push(Q, "carol", "zombie.kills", 5)
        T.now = s.endMs + 1000
        T.tick(15)
        T.check(s.state == "review" and s.frozen and s.frozen.no == 1 and #s.frozen.rows == 3, "due -> review with frozen ranks")
        T.check(s.no == 2 and s.startMs == s.frozen.endMs and s.endMs > T.now, "freeze opens season 2 at once (C30)")
        local cur = Q.Seasons.current()
        T.check(cur.state == "review" and cur.reviewNo == 1 and cur.no == 2, "state.season shows review of season 1")
        accA = Q.Store.account("alice")
        T.check(accA.points.season == 0 and accA.sno == 2, "new season starts from zero")
        Q.Points.award(accA, "alice", 50, "admin")
        T.check(accA.points.season == 50, "points earned during review count for season 2")
        local balA, balB, balC = accA.points.balance, accB.points.balance, accC.points.balance
        r = admin(a, "season.review")
        T.check(r and r.ok and r.rows[1].user == "alice" and r.rows[1].rank == 1 and r.rows[1].pts == 700
            and r.frozenNo == 1 and r.no == 2, "review rows")
        r = admin(a, "season.exclude", { user = "bob", on = true, reason = "" })
        T.check(r and r.code == "BAD_ARGS", "exclusion needs a reason")
        r = admin(a, "season.exclude", { user = "nobody", on = true, reason = "x" })
        T.check(r and r.code == "NOT_FOUND", "exclusion of unknown user")
        r = admin(a, "season.exclude", { user = "bob", on = true, reason = "alt account" })
        T.check(r and r.ok and s.excluded.bob == "alt account", "excluded")
        r = admin(a, "season.confirm")
        T.check(r and r.ok and s.state == "running" and s.no == 2 and s.frozen == nil, "confirm pays season 1")
        -- season.joined may unlock its achievement too (a few achievement points on top)
        local dA, dC = accA.points.balance - balA, accC.points.balance - balC
        T.check(dA >= 700 and dA < 750 and accA.titles.s1_top1 == true, "rank 1: 600 + participation 100")
        T.check(accB.points.balance == balB, "excluded account gets nothing")
        T.check(dC >= 400 and dC < 450 and accC.titles.s1_top3 == true, "rank 2 (after exclusion): top3, no participation")
        T.check(accC.titles.s1_first_kills == true, "category #1 title")
        T.check(accA.titleAt.s1_top1 ~= nil and accC.titleAt.s1_top3 ~= nil and accC.titleAt.s1_first_kills ~= nil,
            "season rank and board-first titles record the grant time")
        T.check(accA.titleSrc.s1_top1 == "season:1:top1" and accC.titleSrc.s1_top3 == "season:1:top3"
            and accC.titleSrc.s1_first_kills == "first:kills", "season rank and board-first titles record their source")
        T.check(Q.Store.root().seasons[1].no == 1 and Q.Store.root().seasons[1].top[1].user == "alice", "history kept")
        T.check(Q.Store.account("alice").points.season >= 50, "review-period points survive the payout")
        T.check(accA.points.total >= 700, "season rewards do not touch lifetime")
        r = admin(a, "season.confirm")
        T.check(r and r.code == "NOT_READY", "nothing to confirm while running")

        Q.Points.award(accA, "alice", 300, "admin")
        T.now = s.endMs + 1000
        T.tick(15)
        T.check(s.state == "review" and s.frozen.no == 2 and s.no == 3, "season 2 due")
        T.advance(DAY + 1000)
        T.tick(15)
        T.check(s.state == "running" and s.no == 3 and Q.Store.root().seasons[1].no == 2,
            "24 hours without review pays automatically")

        Q.Points.award(Q.Store.account("alice"), "alice", 300, "admin")
        T.now = s.endMs + 1000
        T.tick(15)
        s.reviewDeadlineMs = T.now + 30 * DAY             -- planted: review still pending at the next due time
        T.now = s.endMs + 1000
        T.tick(15)
        T.check(Q.Store.root().seasons[1].no == 3 and s.frozen and s.frozen.no == 4 and s.no == 5,
            "pending payout runs before the next freeze")
    end)

    -- ===================== Boards =====================
    section("boards", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        local c = T.player{ name = "carol" }
        for _, p in ipairs({ a, b, c }) do cmd(p, "hello", nil, 2100) end
        Q.Points.award(Q.Store.account("alice"), "alice", 300, "admin")
        Q.Points.award(Q.Store.account("bob"), "bob", 500, "admin")
        Q.Points.award(Q.Store.account("carol"), "carol", 100, "admin")
        T.advance(300001)                             -- season boards rebuild every 5 minutes
        T.tick(40)
        cmd(a, "board", { board = "points", period = "season" }, 2100)
        local pg = T.lastOf(a, "board")
        T.check(pg and pg.rows[1].n == "bob" and pg.rows[1].v == 500 and pg.count == 3, "board from cache, sorted")
        T.check(pg and pg.me and pg.me.r == 2 and pg.season.no == 1, "own rank and season")
        local n = #T.sentTo(a, "board")
        cmd(a, "board", { board = "kills", period = "total" }, 0)    -- T.cmd itself waits 0.3 s
        T.check(#T.sentTo(a, "board") == n, "0.3 s later: inside the 0.5 s cooldown, dropped")
        local r = cmd(a, "board", { board = "nope", period = "season" }, 0)
        T.check(r and r.code == "BAD_BOARD", "0.6 s after the last served ask the next one is served (unknown board)")
        r = cmd(a, "board", { board = "skill_total", period = "season" }, 2100)
        T.check(r and r.code == "BAD_BOARD", "skill_total has no season board")

        Q.Store.account("bob").anon = true
        cmd(a, "board", { board = "points", period = "season" }, 2100)
        pg = T.lastOf(a, "board")
        T.check(pg.rows[1].n == nil and pg.rows[1].v == 500, "anonymous name hidden, rank kept")
        T.check(pg.rows[1].a == "bob" and pg.rows[2].a == nil, "admins also get who the anonymous row is, only on that row")
        cmd(c, "board", { board = "points", period = "season" }, 2100)
        local pc = T.lastOf(c, "board")
        T.check(pc.rows[1].n == nil and pc.rows[1].a == nil, "players never get the name of an anonymous row")
        r = admin(b, "board.hide", { user = "carol", on = true, reason = "x" })
        T.check(r and r.code == "FORBIDDEN", "non-admin hide refused")
        r = admin(a, "board.hide", { user = "carol", on = true, reason = "cheat" })
        T.check(r and r.ok and Q.Store.account("carol").hidden.reason == "cheat", "hidden")
        Q.Store.account("bob").seenMs = T.now - 181 * DAY
        Q.Boards.dirtyAll()
        T.tick(40)
        cmd(a, "board", { board = "points", period = "season" }, 2100)
        pg = T.lastOf(a, "board")
        T.check(pg.count == 1 and pg.rows[1].n == "alice", "hidden and 180-day inactive accounts are off the board")

        Q.Store.account("bob").seenMs = T.now
        admin(a, "board.hide", { user = "carol", on = false })
        Q.Boards.dirtyAll()
        T.tick(40)
        T.now = Q.Clock.nextResetMs(T.now) + 1000
        Q.Points.award(Q.Store.account("alice"), "alice", 1000, "admin")
        Q.Boards.dirtyAll()
        T.tick(40)
        cmd(a, "board", { board = "points", period = "season" }, 2100)
        pg = T.lastOf(a, "board")
        T.check(pg.me.r == 1 and pg.me.d == 1, "rank change vs the last day change")

        -- anon / title through the player commands show on the very next board reply (no rebuild in between)
        T.check(type(Q.Boards.profileChanged) == "function", "Boards.profileChanged is defined (Server calls it after anon/title)")
        local function carolRow()
            cmd(a, "board", { board = "points", period = "season" }, 2100)
            local p2 = T.lastOf(a, "board")
            return p2.rows[Q.Boards.cache["points:season"].rank.carol], p2
        end
        local at0 = Q.Boards.cache["points:season"].at
        Q.Store.account("carol").titles.e2e_title = true
        T.check(cmd(c, "title", { id = "e2e_title" }).ok == true, "title set")
        local told = T.lastOf(b, "titles")
        T.check(told and told.u == "carol" and told.t == "e2e_title", "wearing a title tells every online player")
        T.check(carolRow().t == "e2e_title", "new title on the next board reply")
        T.check(cmd(c, "anon", { on = true }).ok == true, "anon on")
        local row = carolRow()
        T.check(row.n == nil and row.t == "e2e_title", "anonymous on the next board reply (admins still see the title)")
        cmd(b, "board", { board = "points", period = "season" }, 2100)
        local brow = T.lastOf(b, "board").rows[Q.Boards.cache["points:season"].rank.carol]
        T.check(brow.n == nil and brow.a == nil and brow.t == nil,
            "an anonymous row shows players no title (the same title over the head would name them)")
        T.check(Q.Boards.cache["points:season"].at == at0, "no rebuild was needed for the profile change")
        cmd(c, "anon", { on = false })
        T.check(carolRow().n == "carol", "name back on the next board reply")
        admin(a, "board.hide", { user = "carol", on = true, reason = "cheat" })
        T.tick(40)
        local _, p3 = carolRow()
        local listed = false
        for _, r in ipairs(p3.rows) do if r.n == "carol" or r.t == "e2e_title" then listed = true end end
        T.check(not listed and Q.Boards.cache["points:season"].rank.carol == nil, "an admin-hidden account stays off the board")
        admin(a, "board.hide", { user = "carol", on = false })
        Q.Boards.dirtyAll()
        T.tick(40)

        -- a boards.* config change (apply and undo) reschedules: the new score shows without waiting for the
        -- rebuild already planned with the old 30-minute total interval
        Q.Points.award(Q.Store.account("carol"), "carol", 5000, "admin")
        T.tick(40)
        cmd(a, "board", { board = "points", period = "total" }, 2100)
        T.check(T.lastOf(a, "board").rows[1].n ~= "carol", "total board still waits for its 30-minute rebuild")
        local ok, hid = Q.Config.apply({ { op = "set", path = "boards.rebuildTotalMs", value = 60000 } }, "faster", "alice")
        T.check(ok == true, "rebuild interval change applies")
        T.tick(40)
        cmd(a, "board", { board = "points", period = "total" }, 2100)
        T.check(T.lastOf(a, "board").rows[1].n == "carol", "boards rebuilt right after the interval change")
        local s = Q.Boards.state["points:total"]
        T.check(s and s.nextMs > T.now and s.nextMs <= T.now + 60000, "next rebuild follows the new interval")
        T.check(Q.Config.undo(hid, "alice") == true and Q.Boards.state["points:total"].dirty == true
            and Q.Boards.state["points:total"].nextMs == 0, "undo of a boards change reschedules too")
    end)

    -- ===================== Tracker pins, worn titles =====================
    section("tracker pins and worn titles", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        cmd(a, "hello")
        cmd(b, "hello")
        local acc = Q.Store.account("bob")
        local zk = Q.Achievements.get("zombie_kills")
        local r = cmd(b, "pin", { id = "d1", on = true })
        T.check(r and r.ok and acc.pins[1] == "d1" and T.lastOf(b, "state").pins[1] == "d1",
            "an active daily slot pins; the reply state carries the pins")
        local r1, r2 = cmd(b, "pin", { id = "d9", on = true }), cmd(b, "pin", { id = "a:no_such", on = true })
        T.check(r1.code == "BAD_ARGS" and r2.code == "BAD_ARGS" and #acc.pins == 1, "a missing slot or achievement is refused")
        local hidden = nil
        for _, d in ipairs(Q.Achievements.list()) do if d.hidden and hidden == nil then hidden = d end end
        r = hidden and cmd(b, "pin", { id = "a:" .. hidden.id, on = true })
        T.check(r and r.code == "BAD_ARGS", "a hidden achievement cannot be pinned (the panel would show its goal)")
        for _, id in ipairs({ "d2", "d3", "w1", "a:zombie_kills" }) do cmd(b, "pin", { id = id, on = true }) end
        r = cmd(b, "pin", { id = "w2", on = true })
        T.check(#acc.pins == 5 and r.code == "TOO_MANY_PINS", "five pins at most")
        r = cmd(b, "pin", { id = "d1", on = true })
        T.check(r.ok and #acc.pins == 5, "pinning a pinned item again keeps one entry")
        r = cmd(b, "pin", { id = "d3", on = false })
        T.check(r.ok and #acc.pins == 4 and not has(acc.pins, "d3"), "unpinning frees a place")

        -- window closed, panel on: deltas carry what is pinned; panel off: only the badge
        cmd(b, "track", { on = true })
        T.advance(1000)
        T.tick(1)
        T.clearOutbox(b)
        T.check(finish(Q, "bob", acc.day.quests[1]), "pinned quest finished")
        push(Q, "bob", zk.stat, 3)
        T.tick(1)
        local d = T.lastOf(b, "delta")
        local val = ((zk.scope == "life" and acc.life or acc.total) or {})[zk.stat]
        T.check(d and d.day and d.day[1].state == "done" and d.trk and d.trk.zombie_kills.v == val and d.goal == nil
            and d.points == nil, "tracker on: pinned quest and achievement progress arrive, window-only parts do not")
        cmd(b, "track", { on = false })
        T.advance(1000)
        T.tick(1)
        T.clearOutbox(b)
        push(Q, "bob", zk.stat, 1)
        T.tick(1)
        d = T.lastOf(b, "delta")
        T.check(d == nil or (d.trk == nil and d.day == nil), "tracker off: no progress deltas")
        cmd(b, "track", { on = true })

        r = cmd(b, "swap", { slot = 2 })
        T.check(r and r.ok and not has(acc.pins, "d2"), "swapping a pinned quest drops its pin")
        push(Q, "bob", zk.stat, zk.tiers[#zk.tiers])
        T.check(acc.achv.zombie_kills == #zk.tiers and not has(acc.pins, "a:zombie_kills"),
            "an achievement pin goes when its last tier unlocks")
        T.now = Q.Clock.nextResetMs(T.now) + 60000
        Q.Quests.ensure(acc, "bob", T.now)
        T.check(#acc.pins == 1 and acc.pins[1] == "w1", "the daily reset drops the daily pins; weekly ones stay")
        T.now = Q.Clock.weekResetMs(T.now) + 60000
        Q.Quests.ensure(acc, "bob", T.now)
        T.check(#acc.pins == 0, "the weekly reset drops the weekly pins")

        -- worn titles: the map at login, every change to everyone
        local worn = nil
        for t = 1, #zk.tiers do worn = zk.titles[t] or worn end
        T.check(worn ~= nil and acc.titles[worn] == true and cmd(b, "title", { id = worn }).ok, "bob wears a zombie_kills title")
        local c = T.player{ name = "carol" }
        cmd(c, "hello")
        local first = T.sentTo(c, "titles")[1]
        T.check(first and first.full and first.map.bob == worn and T.lastOf(a, "titles").u == "carol",
            "logging in brings the worn titles of everyone online; the others get the newcomer's entry")
        local at = acc.titleAt and acc.titleAt[worn]
        local st = Q.Sync.state("bob", acc)
        T.check(at ~= nil and st.titleAt[worn] == at and type(st.titles[1]) == "string",
            "state carries titleAt next to the unchanged titles id list")
        r = admin(a, "achv.revoke", { user = "bob", achId = "zombie_kills", tier = 0, reason = "test" })
        T.check(acc.titles[worn] == nil and acc.titleAt[worn] == nil, "a revoke drops the title and its time")
        local told = T.lastOf(c, "titles")
        T.check(r and r.ok and acc.title == nil and told.u == "bob" and told.t == nil, "a revoked title comes off for everyone")
        T.clearOutbox()
        T.advance(60000)
        Q.Sync.broadcastToast({ kind = "broadcast", id = "zombie_kills", tier = 3, titleId = worn }, "bob")
        local plain, named = T.lastOf(c, "toast"), T.lastOf(a, "toast")
        T.check(plain and plain.titleId == nil and plain.a == nil and named and named.a == "bob" and named.titleId == worn,
            "an anonymous unlock notice names no title to players (the title would name them)")
    end)

    -- ===================== Balance =====================
    section("balance and difficulty", function()
        local Q = boot()
        local a = T.player{ name = "alice", admin = true }
        local b = T.player{ name = "bob" }
        cmd(a, "hello")
        Q.Store.root().balance = {}                   -- hello already handed out quests
        for i = 1, 20 do Q.Balance.given("d_fish", T.now) end
        for i = 1, 3 do Q.Balance.done("d_fish", T.now - 30 * 60000, T.now) end
        for i = 1, 10 do Q.Balance.given("d_craft", T.now) Q.Balance.done("d_craft", T.now - 6 * 60000, T.now) end
        Q.Balance.given("d_kill", T.now)
        local rows = {}
        for _, r in ipairs(Q.Balance.report(T.now)) do rows[r.tid] = r end
        local fish, craft = rows.d_fish, rows.d_craft
        T.check(fish and fish.rate == 0.15 and fish.medianMin == 30, "rate and median")
        T.check(fish.suggest and fish.suggest.kind == "hard" and fish.suggest.path == "daily.pool.d_fish.target"
            and fish.suggest.value[2] < Q.Catalog.tpl("d_fish").target[2], "too hard -> lower range")
        T.check(craft.suggest and craft.suggest.kind == "easy" and craft.suggest.value[1] > Q.Catalog.tpl("d_craft").target[1],
            "too easy -> higher range")
        T.check(rows.d_kill and rows.d_kill.suggest == nil, "few samples: no suggestion")
        local ok = Q.Config.preview({ { op = "set", path = fish.suggest.path, value = fish.suggest.value } })
        T.check(ok == true, "suggestion is a valid cfg change")
        T.advance(8 * DAY)
        Q.Balance.given("d_kill", T.now)
        T.check(#Q.Balance.report(T.now) == 1, "window is 7 days")
        local r = admin(b, "balance.report")
        T.check(r and r.code == "FORBIDDEN", "non-admin report refused")
        r = admin(a, "balance.report")
        T.check(r and r.ok and #r.rows == 1, "balance.report op")

        r = admin(a, "diff.preview", { preset = "weird" })
        T.check(r and r.code == "BAD_ARGS", "unknown preset")
        r = admin(a, "diff.preview", { preset = "custom" })
        T.check(r and r.code == "BAD_ARGS", "custom needs mult")
        r = admin(a, "diff.preview", { preset = "hard" })
        local rowOf = {}
        for _, row in ipairs(r and r.rows or {}) do rowOf[row.path] = row end
        local zr, sr = rowOf["achievements.zombie_kills.tiers"], rowOf["achievements.skill_axe.tiers"]
        T.check(r and r.ok and r.changes[2].value == 1.6 and zr and zr.after[1] > zr.before[1],
            "hard preview raises thresholds")
        T.check(sr and sr.after[5] == 10 and sr.after[1] == sr.before[1], "hard preview keeps skill levels (ceiling 10)")
        T.check(r.estimate[1] and r.estimate[1].hard > r.estimate[1].easy, "estimate table")
        local base = Q.Achievements.get("zombie_kills").tiers[3]
        T.check(Q.Config.apply(r.changes, "hard", "alice") == true, "preview changes apply")
        T.check(Q.Achievements.get("zombie_kills").tiers[3] == math.floor(base * 1.6 + 0.5), "difficulty scales thresholds")
        T.check(Q.Achievements.get("skill_axe").tiers[5] == 10 and Q.Achievements.get("towns").tiers[5] == 11
            and Q.Achievements.get("h_peak").tiers[1] == 10, "difficulty leaves ceiling stats (skill levels, towns) alone")
    end)
end
