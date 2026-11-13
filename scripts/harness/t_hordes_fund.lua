-- Sponsored hordes (Hordes.lua: H.pledge, H.fundTick, the hordes part and horde.status; contract
-- temp/points-sinks/contract.md sections 2, 4, 6): pledges and their refusals, the last pledge taking what is missing,
-- expiry paying everyone back (offline too, over a restart), a full fund waiting for the horde on, the plan's cap,
-- paidDay apart from perDay, no spot / no id file paying back, the payout of a sponsored horde (rewardPct 0 too), the
-- sponsors in the notices (anonymous ones counted), and what a player sees of the fund.
-- F: t_hordes.lua's fixtures.
return function(T, F)
    local MIN = 60000
    local SPOT, section, boot, step, apply, cmd, adm = F.SPOT, F.section, F.boot, F.step, F.apply, F.cmd, F.adm
    local near, toasts, killAlive, lastLog, sum, spyAwards = F.near, F.toasts, F.killAlive, F.lastLog, F.sum, F.spyAwards
    local encoded, today, keyOf, wave = F.encoded, F.today, F.keyOf, F.wave

    -- hordes.paid.<key> through Config.apply
    local function paid(Q, fields)
        local changes = {}
        for k, v in pairs(fields) do changes[#changes + 1] = { op = "set", path = "hordes.paid." .. k, value = v } end
        local ok, code, detail = Q.Config.apply(changes, "test", "tester")
        if not ok then T.check(false, "apply hordes.paid: " .. tostring(code) .. " " .. tostring(detail and detail.path)) end
    end
    -- players with hello and a balance
    local function players(Q, list, balance)
        local out = {}
        for i, name in ipairs(list) do
            out[i] = T.player{ name = name, admin = name == "admin" }
            cmd(out[i], "hello")
            Q.Store.account(name, true).points.balance = balance or 1000
        end
        return table.unpack(out)
    end
    local function bal(Q, name) return Q.Store.account(name, false).points.balance end
    local function pledge(p, n, total) return cmd(p, "pledge", { n = n, total = total or 600 }) end
    local function refunds(p)
        local out = {}
        for _, t in ipairs(T.sentTo(p, "toast")) do if t.kind == "fundRefund" then out[#out + 1] = t end end
        return out
    end
    local function paidDay(Q) return (Q.Store.root().hordes.paidDay or {})[keyOf(Q, today())] end

    section("sponsored: pledges, the last one takes what is missing, the refusals", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local admin, alice, bob, carol, dave = players(Q, { "admin", "alice", "bob", "carol", "dave" })
        Q.Store.account("carol", false).points.balance = 100
        cmd(dave, "anon", { on = true })
        local r = pledge(alice, 150)
        T.check(r and r.code == "FUND_OFF" and h.fund == nil and bal(Q, "alice") == 1000, "hordes.paid off: FUND_OFF, nothing taken")
        paid(Q, { enabled = true })
        r = pledge(alice, 150)
        T.check(r and r.code == "FUND_OFF" and h.fund == nil, "on but no spot: FUND_OFF")
        T.check(H.stateHordes(nil, "alice", T.now).paid.on == false and H.stateHordes(nil, "alice", T.now).on == false,
            "no spot: the paid part is off, the page stays out of the nav")
        apply(Q, { spots = { SPOT }, cap = 500 })
        local st = H.stateHordes(nil, "alice", T.now)
        T.check(st.on == true and st.paid.on == true and st.paid.pts == 600 and st.paid.minPledge == 50 and st.paid.left == 1
            and st.paid.rewardPct == 50 and st.paid.leadMin == 15 and st.fund == nil, "paid on with a spot: the page is in the nav")
        T.check(st.paid.cap == 300, "the most it pays: 600 x 50%, under the preset's cap 500")
        apply(Q, { spots = { SPOT }, cap = 200 })
        T.check(H.stateHordes(nil, "alice", T.now).paid.cap == 200, "a preset cap under that share: the preset's")
        apply(Q, { spots = { SPOT }, cap = 500 })
        r = pledge(alice, 150, 500)
        T.check(r and r.code == "PRICE_CHANGED" and h.fund == nil and bal(Q, "alice") == 1000, "another goal than 600: PRICE_CHANGED")
        r = cmd(alice, "pledge", { n = 150 })
        T.check(r and r.code == "BAD_ARGS" and h.fund == nil, "no total: refused by the field types")
        r = pledge(alice, 49)
        T.check(r and r.code == "BAD_ARGS" and h.fund == nil and bal(Q, "alice") == 1000, "49 < minPledge 50: BAD_ARGS")
        r = pledge(alice, -100)
        T.check(r and r.code == "BAD_ARGS" and bal(Q, "alice") == 1000, "a negative pledge: BAD_ARGS, nothing given")
        r = pledge(alice, 150)
        local f = h.fund
        T.check(r and r.ok and r.n == 150 and f and f.total == 150 and f.pts == 600 and f.state == "open" and f.by.alice == 150
            and f.expireAt == T.now + 30 * MIN and bal(Q, "alice") == 850, "the first pledge opens the fund, 30 minutes")
        T.check(f.startMs == T.now, "startMs = the pledge time")
        local ft = toasts(bob, "fund")
        T.check(#ft == 1 and ft[1].total == 150 and ft[1].pts == 600 and ft[1].expireAt == f.expireAt, "toast fund to everyone")
        r = pledge(carol, 200)
        T.check(r and r.code == "NOT_ENOUGH_POINTS" and f.total == 150 and f.by.carol == nil and bal(Q, "carol") == 100,
            "carol has 100: NOT_ENOUGH_POINTS, not recorded")
        pledge(bob, 300)
        pledge(dave, 120)
        T.check(f.total == 570 and f.by.bob == 300 and f.by.dave == 120 and #toasts(bob, "fund") == 1, "more pledges: no new fund toast")
        local sc, sa = H.stateHordes(nil, "carol", T.now).fund, H.stateHordes(nil, "alice", T.now).fund
        T.check(sc and sc.total == 570 and sc.pts == 600 and sc.n == 3 and sc.mine == 0 and sc.state == "open"
            and sc.expireAt == f.expireAt and sc.by == nil, "a non-sponsor: total, n, mine 0")
        T.check(sa.mine == 150, "a sponsor: their own share")
        local s = encoded(Q, H.stateHordes(nil, "carol", T.now))
        T.check(not string.find(s, "alice", 1, true) and not string.find(s, "bob", 1, true),
            "nobody else's name or share goes to a player")
        r = pledge(carol, 20)
        T.check(r and r.code == "BAD_ARGS" and f.total == 570, "30 left: 20 is under it")
        r = pledge(carol, 100)
        T.check(r and r.ok and r.n == 30 and f.total == 600 and f.by.carol == 30 and bal(Q, "carol") == 70 and f.state == "ready",
            "the last pledge takes only the 30 missing (under minPledge is fine when that is all that is left)")
        r = pledge(alice, 50)
        T.check(r and r.code == "FUND_FULL" and f.by.alice == 150 and bal(Q, "alice") == 850, "full: FUND_FULL")
        r = adm(admin, "horde.status")
        T.check(r and r.fund and r.fund.by.bob == 300 and r.paid.n == 0 and r.paid.max == 1, "horde.status: the whole fund, paid 0 of 1")

        T.clearOutbox()
        step(Q)
        local cur = h.cur
        T.check(h.fund == nil and cur and cur.actor == "fund" and cur.auto == false and cur.cap == 300
            and cur.sponsors.alice == 150 and cur.sponsors.carol == 30, "the next tick plans it: actor fund, cap 600 x 50%")
        T.check(next(h.perDay) == nil and paidDay(Q) == 1, "not counted in perDay; paidDay + 1")
        for _, u in ipairs({ "alice", "bob", "carol", "dave" }) do
            T.check((Q.Store.account(u, false).total["horde.sponsored"] or 0) == 0, u .. ": horde.sponsored waits for the horde to play")
        end
        T.check((Q.Store.account("admin", false).total["horde.sponsored"] or 0) == 0, "not a sponsor: no stat")
        local soon = toasts(carol, "soon")
        T.check(cur.state == "announced" and #soon == 1 and soon[1].capPts == 300 and soon[1].sponsors.anon == 1
            and #soon[1].sponsors.names == 3 and soon[1].sponsors.names[1] == "alice" and soon[1].sponsors.names[3] == "carol",
            "toast soon in the same tick: sponsors by name, the anonymous one counted, capPts")
        T.check(not string.find(encoded(Q, soon[1]), "dave", 1, true) and soon[1].sponsors.by == nil,
            "the anonymous sponsor's name is nowhere in it, nor the shares")
        local v = H.stateHordes(nil, "carol", T.now).cur
        T.check(v.paid == true and v.sponsorN == 4 and v.capPts == 300 and v.sponsors == nil, "the horde view: paid, sponsorN, capPts")
        st = H.stateHordes(nil, "carol", T.now)
        T.check(st.fund == nil and st.paid.left == 0, "no fund now; none left today")
        r = pledge(alice, 600)
        T.check(r and r.code == "FUND_DAY" and h.fund == nil and bal(Q, "alice") == 850, "maxPerDay 1 reached: FUND_DAY")
        r = adm(admin, "horde.status")
        T.check(r.fund == nil and r.paid.n == 1 and r.paid.max == 1, "horde.status: paid 1 of 1")
        -- a plain horde has no paid view
        H.stop(cur.id, "admin", T.now)
        adm(admin, "horde.now")
        T.check(H.stateHordes(nil, "carol", T.now).cur.paid == nil, "an admin's horde: not paid")
    end)

    section("sponsored: one player fills it, it waits for the horde on, the cap", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local admin, alice = players(Q, { "admin", "alice" }, 2000)
        apply(Q, { spots = { SPOT }, cap = 500 })
        paid(Q, { enabled = true, pts = 333, maxPerDay = 2 })
        adm(admin, "horde.now")
        local busy = h.cur
        local r = pledge(alice, 333, 333)
        T.check(r and r.ok and r.n == 333 and h.fund.state == "ready" and bal(Q, "alice") == 1667, "one player fills it at once")
        T.check(#toasts(alice, "fund") == 1, "the fund toast still goes once")
        step(Q)
        T.check(h.cur == busy and h.fund ~= nil and h.fund.state == "ready" and paidDay(Q) == nil,
            "another horde on: the full fund waits")
        T.check(H.stateHordes(nil, "alice", T.now).fund.state == "ready", "the player sees it full")
        adm(admin, "horde.stop", { id = busy.id })
        step(Q)
        T.check(h.cur and h.cur.actor == "fund" and h.cur.cap == 166 and h.fund == nil and paidDay(Q) == 1,
            "that one over: planned, cap floor(333 x 50 / 100) = 166")
        adm(admin, "horde.stop", { id = h.cur.id })
        apply(Q, { cap = 100 })
        paid(Q, { enabled = false })
        r = pledge(alice, 333, 333)
        T.check(r and r.code == "FUND_OFF", "switched off: FUND_OFF")
        paid(Q, { enabled = true })
        pledge(alice, 333, 333)
        paid(Q, { enabled = false })   -- the points are in: a full fund still plays
        step(Q)
        T.check(h.cur and h.cur.actor == "fund" and h.cur.cap == 100 and paidDay(Q) == 2,
            "the preset's cap 100 is lower than 166: it stays; planned though paid was switched off")
        T.check(next(h.perDay) == nil, "perDay never counts a sponsored horde")
    end)

    section("sponsored: expiry pays everyone back, offline too, over a restart", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice, bob = players(Q, { "alice", "bob" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        pledge(alice, 100)
        pledge(bob, 200)
        local exp = h.fund.expireAt
        T.disconnect(bob)
        T.now = exp - 1
        step(Q)
        T.check(h.fund ~= nil and h.fund.total == 300, "open until expireAt")
        T.clearOutbox()
        T.now = exp
        step(Q)
        T.check(h.fund == nil and bal(Q, "alice") == 1000 and bal(Q, "bob") == 1000, "expired: each gets their points back, offline too")
        local rf = refunds(alice)
        T.check(#rf == 1 and rf[1].pts == 100 and rf[1].why == "expired", "toast fundRefund to the sponsor online")
        T.check(paidDay(Q) == nil and h.cur == nil, "no horde, paidDay not counted")

        -- a fund lives in the save; one that expired while the server was down goes back on the first tick
        pledge(alice, 100)
        local saved = h.fund
        Q = boot({ keepGmd = true, keepFiles = true })
        h = Q.Store.root().hordes
        T.check(h.fund ~= nil and h.fund.total == 100 and h.fund.by.alice == 100 and h.fund.expireAt == saved.expireAt,
            "a restart before expiry: the fund carries on")
        T.now = h.fund.expireAt + 3 * 60 * MIN
        Q = boot({ keepGmd = true, keepFiles = true })
        h = Q.Store.root().hordes
        T.check(h.fund == nil and bal(Q, "alice") == 1000, "expired while down: paid back on the first tick after the boot")
    end)

    section("sponsored: a pledge past the expiry and before the tick cannot fill the old fund", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice, bob = players(Q, { "alice", "bob" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        pledge(alice, 500)
        T.clearOutbox()
        local ok, res = Q.Hordes.pledge(Q.Store.account("bob", false), "bob", 100, 600, h.fund.expireAt)
        T.check(bal(Q, "alice") == 1000 and #refunds(alice) == 1, "the expired fund is paid back first")
        T.check(ok == true and res.n == 100 and h.fund ~= nil and h.fund.state == "open" and h.fund.total == 100
            and h.fund.by.alice == nil and bal(Q, "bob") == 900, "the late pledge opens a new fund instead")
    end)

    -- spendSeq (Server.onClientCommand): a pledge packet is run once, whatever came after it and however late it
    -- comes again. Not the result cache (CACHE_PER_ACTOR, CACHE_TTL_MS), not the 10 entries of acc.spent.
    section("sponsored: a pledge is taken once, however late its packet comes again", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice = players(Q, { "alice" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        local acc = Q.Store.account("alice", false)
        local seq, rid = acc.spendSeq or 0, T.newRequestId()
        local r1 = T.cmd(alice, "pledge", { n = 50, total = 600, seq = seq }, rid)
        T.advance(20000)
        local r2 = T.cmd(alice, "pledge", { n = 50, total = 600, seq = seq }, rid)
        T.check(r1 and r1.ok and r1.n == 50 and r2 and r2.ok and r2.replay == true and r2.n == 50 and h.fund.total == 50
            and bal(Q, "alice") == 950, "inside the cache: the first answer again, 50 taken once")
        -- ten more pledges (more than acc.spent keeps), then past the cache's lifetime: the first packet again
        for _ = 1, 10 do pledge(alice, 50) end
        T.check(h.fund.total == 550 and bal(Q, "alice") == 450 and #acc.spent == Q.Points.SPENT_KEEP, "11 pledges: 550 of 600")
        T.now = T.now + Q.Contract.LIMIT.CACHE_TTL_MS + 1000
        local r3 = T.cmd(alice, "pledge", { n = 50, total = 600, seq = seq }, rid)
        T.check(r3 and r3.code == "STALE" and h.fund.total == 550 and h.fund.state == "open" and bal(Q, "alice") == 450,
            "the first packet again after 10 newer payments and the cache's lifetime: STALE, nothing taken")
        -- spendSeq is saved with the account: a restart empties the cache, not this
        local now = acc.spendSeq
        Q = boot({ keepGmd = true, keepFiles = true })
        h = Q.Store.root().hordes
        local again = T.player{ name = "alice" }
        cmd(again, "hello")
        local r4 = T.cmd(again, "pledge", { n = 50, total = 600, seq = now - 1 })
        T.check(r4 and r4.code == "STALE" and h.fund ~= nil and h.fund.total == 550 and bal(Q, "alice") == 450
            and T.lastOf(again, "state").spendSeq == now, "after a restart: an older request is still STALE, the state says " .. now)
        local r5 = T.cmd(again, "pledge", { n = 50, total = 600 })
        T.check(r5 and r5.ok and r5.replay == nil and h.fund.total == 600 and bal(Q, "alice") == 400,
            "a request on the current state is a new pledge")
    end)

    section("sponsored: no spot or no id file when it is due pays back", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local admin, alice, bob = players(Q, { "admin", "alice", "bob" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        adm(admin, "horde.now")
        local busy = h.cur
        pledge(alice, 400)
        pledge(bob, 200)
        apply(Q, { spots = {} })
        adm(admin, "horde.stop", { id = busy.id })
        T.clearOutbox()
        step(Q)
        T.check(h.fund == nil and h.cur == nil and bal(Q, "alice") == 1000 and bal(Q, "bob") == 1000 and paidDay(Q) == nil,
            "full but the spots are gone: everyone paid back")
        local rf = refunds(bob)
        T.check(#rf == 1 and rf[1].pts == 200 and rf[1].why == "spots", "toast fundRefund why spots")

        apply(Q, { spots = { SPOT } })
        pledge(alice, 600)
        T.clearOutbox()
        T.silentWrites = true
        step(Q)
        T.silentWrites = false
        rf = refunds(alice)
        T.check(h.fund == nil and h.cur == nil and bal(Q, "alice") == 1000 and paidDay(Q) == nil
            and T.printed("horde id file not written") and #rf == 1 and rf[1].why == "file",
            "the horde id file not written: no horde, paid back in full")
    end)

    section("sponsored horde: the payout stays within its cap; rewardPct 0 pays nobody", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local alice, bob = players(Q, { "alice", "bob" })
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, points = { vanilla = 100 }, cap = 500 })
        paid(Q, { enabled = true, leadMin = 0, maxPerDay = 3 })
        pledge(alice, 300)
        pledge(bob, 300)
        T.clearOutbox()
        near(alice)
        near(bob, 10)
        step(Q)
        local cur = h.cur
        local open = toasts(alice, "open")
        T.check(cur and cur.cap == 300 and #open == 1 and open[1].capPts == 300 and #open[1].sponsors.names == 2
            and open[1].sponsors.anon == 0, "lead 0: toast open with the sponsors and capPts")
        step(Q)
        T.check(cur.state == "active", "the wave starts")
        killAlive(Q, cur.id, alice, 3)
        killAlive(Q, cur.id, bob)
        local awards = spyAwards(Q)
        step(Q)
        local e = lastLog(Q)
        T.check(h.cur == nil and e.state == "success" and e.pool == 300 and e.capped == true and sum(awards.horde) == 300
            and sum(e.paid) <= cur.cap, "value 400 over cap 300: 300 paid in all")
        local sp = Q.Store.account("alice", false).spent
        T.check(Q.Store.account("alice", false).total["horde.sponsored"] == 1 and #sp == 1 and sp[1].what == "horde" and sp[1].n == -300
            and #refunds(alice) == 0, "a sponsored horde that played: horde.sponsored + 1, no refund")

        paid(Q, { rewardPct = 0 })
        pledge(alice, 300)
        pledge(bob, 300)
        step(Q)
        cur = h.cur
        T.check(cur and cur.cap == 0, "rewardPct 0: cap 0")
        step(Q)
        killAlive(Q, cur.id, alice)
        awards = spyAwards(Q)
        T.clearOutbox()
        step(Q)
        e = lastLog(Q)
        T.check(h.cur == nil and e.state == "success" and e.pool == 0 and sum(awards.horde) == 0 and #toasts(alice, "hordePaid") == 0
            and e.paid.alice == 0 and #toasts(alice, "win") == 1, "cap 0: a win, the result kept, nobody paid, no error")
        T.check(Q.Store.account("alice", false).total["horde.wins"] == 2, "wins still count")
    end)

    section("sponsored horde: a restart carries it on as any horde, cap and sponsors kept", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice = players(Q, { "alice" }, 1000)
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, cap = 500 })
        paid(Q, { enabled = true, leadMin = 0 })
        pledge(alice, 600)
        near(alice)
        step(Q)
        step(Q)
        local id = h.cur.id
        T.check(h.cur.state == "active", "the sponsored horde runs")
        Q = boot({ keepGmd = true, keepFiles = true })
        h = Q.Store.root().hordes
        T.check(h.cur and h.cur.id == id and h.cur.state == "waiting" and h.cur.resume == true and h.cur.cap == 300
            and h.cur.sponsors.alice == 600 and h.cur.actor == "fund" and paidDay(Q) == 1,
            "after the boot: waits again, cap 300 and the sponsors kept, paidDay not counted again")
        T.check((Q.Store.account("alice", false).total["horde.sponsored"] or 0) == 0, "horde.sponsored waits for the end")
    end)

    section("sponsored horde: one that ends before a zombie came pays the sponsors back", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local admin, alice, bob = players(Q, { "admin", "alice", "bob" })
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, cap = 500 })
        paid(Q, { enabled = true, maxPerDay = 2 })
        pledge(alice, 400)
        pledge(bob, 200)
        step(Q)
        T.check(h.cur and h.cur.actor == "fund" and bal(Q, "alice") == 600 and paidDay(Q) == 1, "planned and announced")
        T.clearOutbox()
        local r = adm(admin, "horde.stop", { id = h.cur.id })
        T.check(r and r.ok and h.cur == nil and bal(Q, "alice") == 1000 and bal(Q, "bob") == 1000,
            "the admin cancels it before the start: everyone gets their points back")
        local rf = refunds(alice)
        T.check(#rf == 1 and rf[1].pts == 400 and rf[1].why == "ended", "toast fundRefund, why ended")
        T.check(paidDay(Q) == 1 and (Q.Store.account("alice", false).total["horde.sponsored"] or 0) == 0,
            "the day's count stays; no horde.sponsored for one that never played")
        -- nobody comes: the same
        pledge(alice, 600)
        step(Q)
        local cur = h.cur
        T.now = cur.expireAt
        step(Q)
        T.check(h.cur == nil and lastLog(Q).why == "nobody" and bal(Q, "alice") == 1000, "nobody came: paid back")
        r = pledge(alice, 100)
        T.check(r and r.code == "FUND_DAY" and bal(Q, "alice") == 1000, "both of today's are used: FUND_DAY")
        T.now = T.now + 24 * 60 * MIN
        r = pledge(alice, 100)
        T.check(r and r.ok and H.stateHordes(nil, "alice", T.now).paid.left == 2, "the next local day: open again")
    end)
end
