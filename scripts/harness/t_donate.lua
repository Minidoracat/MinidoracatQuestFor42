-- The server-wide donation (Donate.lua; plan points-play-1112 claim 3, contract temp/plan-group-play-1114/spec.md A3):
-- the donate command and its refusals, root.donate and the donate state part, a full round carrying what is over into
-- the next one, its horde scheduled on the next weekday / time at least 24 h away and planned leadMin before (toughened
-- by hp, its cap the preset's x hp, not counted in the day's hordes), waiting for a horde on or a full fund, kept when it
-- cannot be planned, the stat and achievement, one confirmation running once, the settings checks.
-- F: t_hordes.lua's fixtures.
return function(T, F)
    local MIN, HOUR, DAY = 60000, 3600000, 86400000
    local SPOT, section, boot, step, apply, cmd, adm = F.SPOT, F.section, F.boot, F.step, F.apply, F.cmd, F.adm
    local near, killAlive, lastLog, wave, at, encoded = F.near, F.killAlive, F.lastLog, F.wave, F.at, F.encoded

    local function set(Q, changes) return Q.Config.apply(changes, "test", "tester") end
    local function donateCfg(Q, fields)
        local changes = {}
        for k, v in pairs(fields) do changes[#changes + 1] = { op = "set", path = "donate." .. k, value = v } end
        local ok, code, detail = set(Q, changes)
        if not ok then T.check(false, "apply donate: " .. tostring(code) .. " " .. tostring(detail and detail.why)) end
    end
    local function players(Q, list, balance)
        local out = {}
        for i, name in ipairs(list) do
            out[i] = T.player{ name = name, admin = name == "admin" }
            cmd(out[i], "hello")
            Q.Store.account(name, true).points.balance = balance or 5000
        end
        return table.unpack(out)
    end
    local function bal(Q, name) return Q.Store.account(name, false).points.balance end
    local function donate(p, n, total) return cmd(p, "donate", { n = n, total = total or 2000 }) end
    local function dones(p)
        local out = {}
        for _, t in ipairs(T.sentTo(p, "toast")) do if t.kind == "donateDone" then out[#out + 1] = t end end
        return out
    end
    -- a local day (UTC+8, t_hordes' TZ) of weekday wd (1 = Monday) at or after today
    local function dayOf(wd)
        local d = math.floor((T.now + 8 * HOUR) / DAY)
        while (d + 3) % 7 + 1 ~= wd do d = d + 1 end
        return d
    end
    -- the usual setup: a spot, a one-wave preset of 4 regular zombies at 5 points (cap 500), the donation on with
    -- target 2,000 (cap 500 x hp 3 = 1,500 stays under it)
    local function setup(Q)
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, points = { vanilla = 5 }, cap = 500 })
        donateCfg(Q, { enabled = true, target = 2000 })
    end

    section("donate: refusals take nothing; a donation adds up", function()
        local Q = boot()
        local d = Q.Donate.root()
        local alice, bob, carol = players(Q, { "alice", "bob", "carol" })
        Q.Store.account("carol", false).points.balance = 50
        local r = donate(alice, 100, 10000)
        T.check(r and r.code == "DONATE_OFF" and bal(Q, "alice") == 5000 and d.total == 0, "off: DONATE_OFF")
        donateCfg(Q, { enabled = true, target = 2000 })
        r = donate(alice, 100)
        T.check(r and r.code == "DONATE_OFF" and bal(Q, "alice") == 5000, "on but no horde spot: DONATE_OFF")
        T.check(Q.Donate.state(nil, "alice", T.now).on == false, "no spot: the part says off")
        setup(Q)
        for _, c in ipairs({ { 9, 2000, "BAD_ARGS", "9 under the least 10" }, { -50, 2000, "BAD_ARGS", "a negative amount" },
            { 100, 10000, "PRICE_CHANGED", "another target than 2,000" } }) do
            r = donate(alice, c[1], c[2])
            T.check(r and r.code == c[3] and bal(Q, "alice") == 5000 and d.total == 0 and d.n == 0, c[4] .. ": " .. c[3])
        end
        r = donate(carol, 100)
        T.check(r and r.code == "NOT_ENOUGH_POINTS" and bal(Q, "carol") == 50 and d.total == 0 and d.by.carol == nil,
            "carol has 50: NOT_ENOUGH_POINTS, not recorded")
        r = cmd(alice, "donate", { n = 100 })
        T.check(r and r.code == "BAD_ARGS" and d.total == 0, "no total: refused by the field types")
        r = donate(alice, 300)
        local acc = Q.Store.account("alice", false)
        T.check(r and r.ok and r.n == 300 and bal(Q, "alice") == 4700 and d.total == 300 and d.n == 1 and d.by.alice == 300,
            "a donation: taken from the balance, into the round")
        T.check(acc.total["donate.points"] == 300 and acc.spent[1].what == "donate" and acc.spent[1].n == -300
            and acc.points.total == 0 and acc.points.season == 0, "the stat, the points history; earned points untouched")
        local today = Q.Store.root().daily[Q.Clock.dayKey(T.now)]
        T.check(today.spent.donate == 300, "the report's spent column: donate")
        donate(bob, 50)
        local sa, sb = Q.Donate.state(nil, "alice", T.now), Q.Donate.state(nil, "bob", T.now)
        T.check(sa.on == true and sa.total == 350 and sa.target == 2000 and sa.min == 10 and sa.mine == 300 and sa.n == 2
            and sa.hp == 3 and sa.hordeAt == nil and sb.mine == 50, "the donate part: on, total, target, least, mine, count, hp")
        T.check(not string.find(encoded(Q, sb), "alice", 1, true) and sb.by == nil, "nobody else's name or share goes to a player")
        donate(alice, 200)
        T.check(acc.total["donate.points"] == 500 and acc.achv.donate_points == 1, "500 donated: donate_points tier I")
        local a = Q.Catalog.ach("donate_points")
        T.check(a.cat == "horde" and a.tiers[2] == 2000 and a.tiers[5] == 40000 and a.titles[4] == "donate_points_4"
            and Q.Catalog.stats["donate.points"].ceil == nil, "donate_points: 500 / 2,000 / 5,000 / 15,000 / 40,000, no per-minute ceiling")
        donate(alice, 4000 - 500)
        T.check(acc.total["donate.points"] == 4000, "a big donation counts whole (no ceiling cuts it)")
        T.check(Q.Hordes.stateHordes(nil, "alice", T.now).on == true, "the donation on lists the Hordes page (its achievements)")
    end)

    section("donate: a full round carries the rest over; its horde at least 24 h later", function()
        local Q = boot()
        local d = Q.Donate.root()
        local alice, bob, carol = players(Q, { "alice", "bob", "carol" })
        setup(Q)
        local fri = dayOf(5)
        T.now = at(fri, 22, 0)   -- Saturday 21:00 is 23 h away: the next week's
        donate(alice, 1500)
        T.clearOutbox()
        local r = donate(bob, 700)
        T.check(r and r.ok and d.total == 200 and d.round == 2 and d.n == 0 and next(d.by) == nil
            and d.last.round == 1 and d.last.n == 2 and d.last.at == T.now, "2,200 of 2,000: 200 carry over, round 2 starts empty")
        T.check(d.hordeAt == at(fri + 8, 21, 0) and d.hordeAt - T.now >= DAY, "Friday 22:00: not tomorrow 21:00 (23 h), the Saturday after")
        local dt = dones(carol)
        T.check(#dt == 1 and dt[1].at == d.hordeAt, "everyone is told when (toast donateDone { at })")
        r = donate(carol, 1900)
        T.check(r and r.ok and d.total == 2100 and d.round == 2 and d.last.round == 1 and #dones(carol) == 1,
            "full again while its horde waits: it adds up, no second round yet")
        local st = Q.Donate.state(nil, "carol", T.now)
        T.check(st.hordeAt == d.hordeAt and st.last.n == 2 and st.mine == 1900, "the part: hordeAt and the last round")
        -- the weekday rule at the other edges
        local Q2 = boot()
        d = Q2.Donate.root()
        local a2 = players(Q2, { "alice" })
        setup(Q2)
        T.now = at(dayOf(5), 20, 0)
        donate(a2, 2000)
        T.check(d.hordeAt == at(dayOf(6), 21, 0) and d.hordeAt - at(dayOf(5), 20, 0) == 25 * HOUR, "Friday 20:00: tomorrow 21:00 (25 h)")
        Q2 = boot()
        d = Q2.Donate.root()
        a2 = players(Q2, { "alice" })
        setup(Q2)
        local sat = dayOf(6)
        T.now = at(sat, 20, 0)
        donate(a2, 2000)
        T.check(d.hordeAt == at(sat + 7, 21, 0), "Saturday 20:00: not in an hour, next Saturday")
        T.now = at(sat + 1, 9, 0)
    end)

    section("donate: its horde is planned leadMin before, toughened, not counted; then the next round", function()
        local Q = boot()
        local d, h = Q.Donate.root(), Q.Store.root().hordes
        local alice, bob = players(Q, { "alice", "bob" })
        setup(Q)
        donate(alice, 2000)
        donate(bob, 2100)
        local due = d.hordeAt
        T.check(d.total == 2100, "the next round is full already")
        T.now = due - 30 * MIN - 1000
        step(Q)
        T.check(h.cur == nil and d.hordeAt == due, "before leadMin (30) ahead: nothing yet")
        T.now = due - 30 * MIN
        step(Q)
        local cur = h.cur
        T.check(cur and cur.actor == "donate" and cur.auto == false and cur.startMs == due and cur.announceAt == due - 30 * MIN
            and cur.waitMin == 60, "planned: actor donate, starts at hordeAt, announced 30 minutes before")
        T.check(cur.hpMult == 3 and cur.points.vanilla == 15 and cur.cap == 1500 and cur.sponsors == nil,
            "x3: points 15, cap 500 x 3 = 1,500, nobody's fund")
        T.check(next(h.perDay) == nil and h.paidDay == nil, "not counted in the day's automatic or sponsored hordes")
        T.check(d.hordeAt ~= nil and d.hordeAt > due and d.total == 100 and d.round == 3,
            "planned, and the next round was full: the one after is scheduled")
        local v = Q.Hordes.stateHordes(nil, "alice", T.now)
        T.check(v.cur and v.cur.state == "announced" and v.cur.paid == nil, "the players see it announced; it is not a sponsored one")
        T.now = due
        near(alice)
        step(Q)
        step(Q)
        killAlive(Q, cur.id, alice)
        step(Q)
        local e = lastLog(Q)
        T.check(e.state == "success" and e.pool == 4 * 15 and e.paid.alice == 60, "it plays like any horde: 4 kills x 15")
    end)

    section("donate: waits for a horde on and a full fund; no spot or no id file keeps it", function()
        local Q = boot()
        local d, h = Q.Donate.root(), Q.Store.root().hordes
        local admin, alice, bob = players(Q, { "admin", "alice", "bob" })
        setup(Q)
        set(Q, { { op = "set", path = "hordes.paid.enabled", value = true } })
        donate(alice, 2000)
        local due = d.hordeAt
        T.now = due - 30 * MIN
        adm(admin, "horde.now", { lead = 5 })
        local busy = h.cur
        step(Q)
        T.check(h.cur == busy and d.hordeAt == due, "another horde on: it waits")
        cmd(bob, "pledge", { n = 600, total = 600, tier = 1 })
        adm(admin, "horde.stop", { id = busy.id })
        T.check(h.fund and h.fund.state == "ready", "a full fund waits too")
        step(Q)
        T.check(h.cur and h.cur.actor == "fund" and d.hordeAt == due, "the fund goes first")
        adm(admin, "horde.stop", { id = h.cur.id })
        apply(Q, { spots = {} })
        step(Q)
        T.check(h.cur == nil and d.hordeAt == due and d.total == 0, "no spot: kept, nothing refunded")
        apply(Q, { spots = { SPOT } })
        step(Q)
        T.check(h.cur == nil, "the spot is back: tried again after RETRY_MS, not every tick")
        T.advance(Q.Donate.RETRY_MS)
        T.silentWrites = true
        step(Q)
        T.silentWrites = false
        T.check(h.cur == nil and d.hordeAt == due and T.printed("horde id file not written"), "no id file: kept")
        T.advance(Q.Donate.RETRY_MS)
        donateCfg(Q, { enabled = false })
        local r = donate(alice, 100)
        T.check(r and r.code == "DONATE_OFF", "switched off: no more donations")
        step(Q)
        T.check(h.cur and h.cur.actor == "donate" and h.cur.startMs == T.now + 30 * MIN and d.hordeAt == nil,
            "switched off with the points in: it still plays; late, it starts lead minutes from now")
    end)

    section("donate: a restart keeps the round and the waiting horde", function()
        local Q = boot()
        local alice = players(Q, { "alice" })
        setup(Q)
        donate(alice, 2300)
        local due = Q.Donate.root().hordeAt
        Q = boot({ keepGmd = true, keepFiles = true })
        local d = Q.Donate.root()
        T.check(d.hordeAt == due and d.total == 300 and d.round == 2, "Global ModData: the round and hordeAt come back")
        T.now = due + 2 * HOUR   -- down past it
        Q = boot({ keepGmd = true, keepFiles = true })
        local cur = Q.Store.root().hordes.cur
        T.check(cur and cur.actor == "donate" and Q.Donate.root().hordeAt == nil, "planned on the first tick after the boot")
    end)

    -- spendSeq (Server.onClientCommand): one confirmation, one donation, whatever comes after
    section("donate: one confirmation runs once", function()
        local Q = boot()
        local d = Q.Donate.root()
        local alice = players(Q, { "alice" })
        setup(Q)
        local acc = Q.Store.account("alice", false)
        local seq, rid = acc.spendSeq or 0, T.newRequestId()
        local r1 = T.cmd(alice, "donate", { n = 100, total = 2000, seq = seq }, rid)
        T.advance(20000)
        local r2 = T.cmd(alice, "donate", { n = 100, total = 2000, seq = seq }, rid)
        T.check(r1 and r1.ok and r2 and r2.ok and r2.replay == true and d.total == 100 and bal(Q, "alice") == 4900,
            "the same packet again: the first answer, 100 taken once")
        local r3 = T.cmd(alice, "donate", { n = 100, total = 2000, seq = seq })
        T.check(r3 and r3.code == "STALE" and d.total == 100 and bal(Q, "alice") == 4900, "a new request on the old screen: STALE")
        local r4 = T.cmd(alice, "donate", { n = 100, total = 2000 })
        T.check(r4 and r4.ok and d.total == 200, "on the current state: a new donation")
    end)

    section("donate: settings validation", function()
        local Q = boot()
        local CODE = Q.Contract.CODE
        local function refused(changes, why, path, label)
            local ok, code, detail = set(Q, changes)
            if type(detail) ~= "table" then detail = {} end   -- applied (detail is the rev): report it as a failure, go on
            T.check(ok == false and code == CODE.BAD_CONFIG and detail and (why == nil or detail.why == why)
                and (path == nil or detail.path == path), label .. " (" .. tostring(detail and detail.why) .. ")")
        end
        for _, b in ipairs({ { "target", 99 }, { "target", 10000001 }, { "min", 0 }, { "min", 10001 }, { "day", 0 }, { "day", 8 },
            { "time", "24:00" }, { "time", "9" }, { "hp", 0 }, { "hp", 11 }, { "leadMin", Q.Contract.LIMIT.MAX_LEAD + 1 },
            { "waitMin", 0 }, { "preset", "1bad" }, { "enabled", 1 } }) do
            refused({ { op = "set", path = "donate." .. b[1], value = b[2] } }, nil, nil, "donate." .. b[1] .. " = " .. tostring(b[2]))
        end
        refused({ { op = "set", path = "donate.preset", value = "nosuch" } }, "preset", "donate.preset", "a preset that does not exist")
        local ok = set(Q, { { op = "set", path = "donate.target", value = 1000 } })
        T.check(ok == true, "off: a target under cap x hp is allowed")
        refused({ { op = "set", path = "donate.enabled", value = true } }, "donateCap", "donate.target",
            "on: its horde could pay 500 x 3 = 1,500 >= the target 1,000")
        ok = set(Q, { { op = "set", path = "donate.enabled", value = true }, { op = "set", path = "donate.hp", value = 1.5 } })
        T.check(ok == true, "x1.5: 750 < 1,000 is allowed")
        refused({ { op = "set", path = "hordes.presets.default.cap", value = 1000 } }, "donateCap", "donate.target",
            "a preset cap that makes it pay the target: refused while on")
        set(Q, { { op = "set", path = "hordes.presets.p2", value = { name = "Hard", waves = { wave(5) }, kinds = { vanilla = 1 },
            points = { vanilla = 1 }, cap = 9, limitMin = 5, restSec = 0, maxAlive = 10 } },
            { op = "set", path = "donate.preset", value = "p2" } })
        refused({ { op = "del", path = "hordes.presets.p2" } }, "preset", "donate.preset", "deleting the preset the donation plays")
        local admin = players(Q, { "admin" })
        local r = adm(admin, "horde.status")
        T.check(r and r.donate and r.donate.total == 0 and r.donate.round == 1, "horde.status carries root.donate")
    end)
end
