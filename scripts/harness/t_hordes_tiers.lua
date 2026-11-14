-- Sponsored horde tiers and the share back on a clear (plan points-play-1113 claims 1 and 3; contract
-- temp/plan-group-play-1114/spec.md A1, A2): hordes.paid.tiers in the state, a pledge naming its tier (PRICE_CHANGED
-- for a tier or price that is not the one on offer), the fund's copy of the tier, the planned horde made tougher
-- (health, points, cap, minutes per wave), horde.eliteWins and horde_elite, backPct paid back to every sponsor on a
-- success only and only once, the validation (rewardPct + backPct <= 90, prices in order, names, presets) and the
-- migration of the 0.7.0 single price (overrides and config.json).
-- F: t_hordes.lua's fixtures.
return function(T, F)
    local MIN, DAY = 60000, 86400000
    local SPOT, section, boot, step, apply, cmd, adm = F.SPOT, F.section, F.boot, F.step, F.apply, F.cmd, F.adm
    local near, toasts, killAlive, lastLog, wave, sig = F.near, F.toasts, F.killAlive, F.lastLog, F.wave, F.sig

    local function set(Q, changes)
        return Q.Config.apply(changes, "test", "tester")
    end
    local function paid(Q, fields)
        local changes = {}
        for k, v in pairs(fields) do changes[#changes + 1] = { op = "set", path = "hordes.paid." .. k, value = v } end
        local ok, code, detail = set(Q, changes)
        if not ok then T.check(false, "apply hordes.paid: " .. tostring(code) .. " " .. tostring(detail and detail.path)) end
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
    -- as PledgeDialog: the tier's sig of the state the player sees now
    local function pledge(p, n, total, tier) return cmd(p, "pledge", { n = n, total = total, tier = tier, sig = sig(tier) }) end
    local function backs(p)
        local out = {}
        for _, t in ipairs(T.sentTo(p, "toast")) do if t.kind == "fundBack" then out[#out + 1] = t end end
        return out
    end
    local function tier(name, preset, pts, hp, limitMin)
        return { name = name, preset = preset or "default", pts = pts, hp = hp, limitMin = limitMin }
    end

    section("tiers: the three defaults in the state, what each pays", function()
        local Q = boot()
        local H = Q.Hordes
        players(Q, { "alice" })
        apply(Q, { spots = { SPOT }, cap = 500, points = { vanilla = 5, runner = 8 } })
        paid(Q, { enabled = true })
        local p = H.stateHordes(nil, "alice", T.now).paid
        local t = p.tiers
        T.check(p.pts == nil and p.cap == nil and #t == 3 and p.backPct == 10, "paid.tiers replace pts / cap; backPct 10")
        T.check(t[1].name == "normal" and t[1].pts == 600 and t[1].hp == 1 and t[1].cap == 300
            and t[2].name == "hard" and t[2].pts == 1200 and t[2].hp == 2 and t[2].cap == 600
            and t[3].name == "nightmare" and t[3].pts == 2500 and t[3].hp == 3 and t[3].cap == 1250,
            "normal 600 x1 pays 300, hard 1,200 x2 pays 600, nightmare 2,500 x3 pays 1,250 (50% of the price)")
        T.check(t[1].waves == 1 and t[1].limitMin == 15 and #t[1].kinds == 2 and t[1].kinds[1].id == "vanilla"
            and t[1].kinds[2].nameKey == "IGUI_MQ_Horde_Kind_runner", "each tier: waves, the kinds and the minutes per wave it plays")
        apply(Q, { cap = 700 })
        t = H.stateHordes(nil, "alice", T.now).paid.tiers
        T.check(t[1].cap == 300 and t[2].cap == 600 and t[3].cap == 1250, "a preset cap above the share: the share")
        apply(Q, { cap = 250 })
        t = H.stateHordes(nil, "alice", T.now).paid.tiers
        T.check(t[1].cap == 250 and t[2].cap == 500 and t[3].cap == 750, "a lower preset cap: x hp (250 / 500 / 750)")
    end)

    section("tiers: a pledge names its tier; another tier or price is PRICE_CHANGED", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local alice, bob = players(Q, { "alice", "bob" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        for _, c in ipairs({ { 300, 1200, 4, "a tier past the list" }, { 300, 1200, 0, "tier 0" }, { 300, 600, 2, "tier 2 at tier 1's price" },
            { 300, 1200, nil, "no tier (1) at tier 2's price" } }) do
            local r = pledge(alice, c[1], c[2], c[3])
            T.check(r and r.code == "PRICE_CHANGED" and h.fund == nil and bal(Q, "alice") == 5000, c[4] .. ": PRICE_CHANGED, nothing taken")
        end
        local r = pledge(alice, 300, 1200, 2)
        local f = h.fund
        T.check(r and r.ok and f and f.tier == 2 and f.name == "hard" and f.preset == "default" and f.pts == 1200 and f.hp == 2
            and f.limitMin == nil and f.elite == false and bal(Q, "alice") == 4700, "tier 2 opens a fund at 1,200 with a copy of the tier")
        local ft = toasts(bob, "fund")
        T.check(#ft == 1 and ft[1].pts == 1200 and ft[1].name == "hard", "the fund toast names its tier")
        local st = H.stateHordes(nil, "bob", T.now).fund
        T.check(st.tier == 2 and st.name == "hard" and st.hp == 2 and st.pts == 1200, "the fund view: tier, name, hp")
        r = pledge(bob, 100, 1200, 3)
        T.check(r and r.code == "PRICE_CHANGED" and f.total == 300, "joining with another tier: PRICE_CHANGED")
        r = pledge(bob, 100, 2500)
        T.check(r and r.code == "PRICE_CHANGED" and f.total == 300, "joining at another price: PRICE_CHANGED")
        r = pledge(bob, 100, 1200)
        T.check(r and r.ok and f.total == 400 and bal(Q, "bob") == 4900, "joining without a tier: the fund's")
        r = pledge(bob, 100, 1200, 2)
        T.check(r and r.ok and f.total == 500, "joining with the fund's tier")
        -- an admin edits the tiers meanwhile: the open fund keeps its copy
        paid(Q, { tiers = { tier("normal", nil, 600, 1), tier("hard", nil, 1500, 4) } })
        r = pledge(bob, 700, 1200, 2)
        T.check(r and r.ok and f.state == "ready" and f.pts == 1200 and f.hp == 2, "the open fund keeps its price and toughness")
        h.fund = nil
        r = pledge(alice, 1500, 1500, 2)
        T.check(r and r.ok and h.fund.elite == true and h.fund.hp == 4, "the last of 2+ tiers is elite")
        h.fund = nil
        paid(Q, { tiers = { tier("normal", nil, 600, 1) } })
        r = pledge(alice, 600, 600, 1)
        T.check(r and r.ok and h.fund.elite == false, "one tier: never elite")
    end)

    section("tiers: the planned horde is tougher, pays more per kill, its own cap and minutes", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local alice = players(Q, { "alice" })
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 50, runner = 50 },
            points = { vanilla = 5, runner = 8, other = 0 }, hp = { runner = 2 }, cap = 500, limitMin = 15 })
        paid(Q, { enabled = true, leadMin = 0, maxPerDay = 5, tiers = { tier("normal", nil, 600, 1),
            tier("nightmare", nil, 2500, 3, 25) } })
        pledge(alice, 2500, 2500, 2)
        near(alice)
        T.spawnHealth = 2
        step(Q)
        local cur = h.cur
        T.check(cur and cur.actor == "fund" and cur.hpMult == 3 and cur.points.vanilla == 15 and cur.points.runner == 24
            and cur.points.other == 0 and cur.limitMin == 25 and cur.cap == 1250 and cur.elite == true
            and cur.tier == 2 and cur.tierName == "nightmare" and cur.backPct == 10,
            "x3: points 15 / 24 (0 stays 0), the tier's 25 minutes, cap min(500 x 3, 2,500 x 50%) = 1,250")
        step(Q)
        local out = { vanilla = {}, runner = {} }
        for z, t in pairs(H.live) do if t.horde == cur.id then table.insert(out[t.kind], z.health) end end
        local ok = #out.vanilla > 0 and #out.runner > 0
        for _, x in ipairs(out.vanilla) do ok = ok and math.abs(x - 6) < 1e-9 end
        for _, x in ipairs(out.runner) do ok = ok and math.abs(x - 12) < 1e-9 end
        T.check(cur.state == "active" and ok, "spawn health: vanilla 2 x 3 = 6, runner 2 x 2 (preset) x 3 = 12")
        T.check(cur.endsAt == T.now + 25 * MIN, "the wave's time limit is the tier's")
        local v = H.stateHordes(nil, "alice", T.now).cur
        T.check(v.paid and v.tier == 2 and v.tierName == "nightmare" and v.hp == 3 and v.capPts == 1250, "the horde view: tier and toughness")
        H.stop(cur.id, "admin", T.now)
        -- one tier at x1: the horde is the preset's, as before the tiers
        paid(Q, { tiers = { tier("normal", nil, 600, 1) } })
        pledge(alice, 600, 600)
        step(Q)
        cur = h.cur
        T.check(cur and cur.hpMult == nil and cur.points.vanilla == 5 and cur.points.runner == 8 and cur.limitMin == 15
            and cur.cap == 300 and cur.elite == false, "one tier x1: the preset's points and minutes, cap 300, not elite")
        T.spawnHealth = nil
    end)

    section("tiers: clearing the elite tier counts horde.eliteWins for the killers", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice, bob, carol = players(Q, { "alice", "bob", "carol" })
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 } })
        paid(Q, { enabled = true, leadMin = 0, maxPerDay = 5 })
        local function play(t, pts, killers)
            pledge(carol, pts, pts, t)
            near(alice)
            near(bob, 10)
            step(Q)
            step(Q)
            local id = h.cur.id
            for _, p in ipairs(killers) do killAlive(Q, id, p, 2) end
            killAlive(Q, id, killers[1])
            step(Q)
            return lastLog(Q)
        end
        local e = play(3, 2500, { alice })
        local acc = Q.Store.account("alice", false)
        T.check(e.state == "success" and acc.total["horde.eliteWins"] == 1 and acc.achv.horde_elite == 1
            and (Q.Store.account("bob", false).total["horde.eliteWins"] or 0) == 0
            and (Q.Store.account("carol", false).total["horde.eliteWins"] or 0) == 0,
            "nightmare cleared: the killer gets eliteWins and horde_elite tier I; no kill (or only paid) gets none")
        play(2, 1200, { alice, bob })
        T.check(acc.total["horde.eliteWins"] == 1 and (Q.Store.account("bob", false).total["horde.eliteWins"] or 0) == 0,
            "hard cleared: not elite")
        local a = Q.Catalog.ach("horde_elite")
        T.check(a.cat == "horde" and a.tiers[1] == 1 and a.tiers[5] == 50 and a.titles[4] == "horde_elite_4"
            and Q.Catalog.stats["horde.eliteWins"].account == true, "horde_elite: 1 / 3 / 10 / 25 / 50, a title at IV, account level")
    end)

    section("share back: a cleared sponsored horde gives every sponsor backPct, once", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local alice, bob, carol, dave = players(Q, { "alice", "bob", "carol", "dave" }, 3000)
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 } })
        paid(Q, { enabled = true, leadMin = 0, maxPerDay = 9 })
        pledge(alice, 2000, 2500, 3)
        pledge(bob, 485, 2500)
        pledge(dave, 15, 2500)
        near(carol)
        step(Q)
        step(Q)
        T.disconnect(bob)
        T.clearOutbox()
        killAlive(Q, h.cur.id, carol)
        step(Q)
        local e = lastLog(Q)
        T.check(e.state == "success" and bal(Q, "alice") == 1000 + 200 and bal(Q, "bob") == 3000 - 485 + 48
            and bal(Q, "dave") == 3000 - 15 + 1, "10% each, rounded down: 200, 48 (bob offline too), 1")
        local ab = backs(alice)
        T.check(#ab == 1 and ab[1].pts == 200 and ab[1].mine == 2000 and #backs(carol) == 0, "toast fundBack { pts, mine } to the sponsor")
        local sp = Q.Store.account("alice", false).spent[1]
        T.check(sp.what == "hordeBack" and sp.n == 200 and sp.ref == "horde:" .. e.id, "the points history: hordeBack, ref horde:<id>")
        local today = Q.Store.root().daily[Q.Clock.dayKey(T.now)]
        T.check(today.spent.horde == 2500 - 249, "the report takes it off the horde column")
        step(Q)
        T.check(bal(Q, "alice") == 1200, "never again on a later tick")
        -- failed and cancelled: nothing back (a cancel before the spawn is the full refund)
        pledge(alice, 600, 600, 1)
        step(Q)
        step(Q)
        T.now = h.cur.endsAt
        step(Q)
        T.check(lastLog(Q).state == "failed" and bal(Q, "alice") == 600 and #backs(alice) == 1, "failed: no share back")
        pledge(alice, 600, 600, 1)
        carol.x, carol.y = 10000, 10000   -- nobody at the spot: the horde waits, no zombie comes
        step(Q)
        T.check(h.cur and h.cur.firstSpawnAt == nil and bal(Q, "alice") == 0, "planned, waiting for a player")
        H.stop(h.cur.id, "admin", T.now)
        T.check(bal(Q, "alice") == 600 and #backs(alice) == 1, "cancelled before a zombie came: the full refund, no share back")
        near(carol)
        paid(Q, { backPct = 0 })
        pledge(alice, 600, 600, 1)
        step(Q)
        step(Q)
        killAlive(Q, h.cur.id, carol)
        step(Q)
        T.check(lastLog(Q).state == "success" and bal(Q, "alice") == 0 and #backs(alice) == 1, "backPct 0: nothing back")
    end)

    section("share back: an error halfway never pays it twice", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice, bob, carol = players(Q, { "alice", "bob", "carol" }, 3000)
        apply(Q, { spots = { SPOT }, waves = { wave(2) }, kinds = { vanilla = 100 } })
        paid(Q, { enabled = true, leadMin = 0 })
        pledge(alice, 300, 600)
        pledge(bob, 300, 600)
        near(carol)
        step(Q)
        step(Q)
        killAlive(Q, h.cur.id, carol)
        local unpay = Q.Points.unpay
        local calls = 0
        Q.Points.unpay = function(acc, user, n, what, ref)
            calls = calls + 1
            if calls == 2 then error("disk on fire") end
            return unpay(acc, user, n, what, ref)
        end
        local ok = pcall(step, Q)
        Q.Points.unpay = unpay
        local got = bal(Q, "alice") + bal(Q, "bob")
        step(Q)
        step(Q)
        T.check(not ok and h.cur == nil and got == 2700 + 2700 + 30, "the error stops the finish after one sponsor got 30")
        T.check(bal(Q, "alice") + bal(Q, "bob") == got and calls == 2, "the next ticks pay nobody again")
    end)

    section("tiers: settings validation", function()
        local Q = boot()
        local CODE = Q.Contract.CODE
        local function refused(changes, why, path, label)
            local ok, code, detail = set(Q, changes)
            if type(detail) ~= "table" then detail = {} end   -- applied (detail is the rev): report it as a failure, go on
            T.check(ok == false and code == CODE.BAD_CONFIG and detail and detail.why == why and (path == nil or detail.path == path),
                label .. " (" .. tostring(detail and detail.why) .. " " .. tostring(detail and detail.path) .. ")")
        end
        local P = "hordes.paid."
        refused({ { op = "set", path = P .. "backPct", value = 41 } }, "paidBack", P .. "backPct", "rewardPct 50 + backPct 41 > 90")
        refused({ { op = "set", path = P .. "rewardPct", value = 81 } }, "paidBack", P .. "backPct", "rewardPct 81 + backPct 10 > 90")
        local ok = set(Q, { { op = "set", path = P .. "rewardPct", value = 40 }, { op = "set", path = P .. "backPct", value = 50 } })
        T.check(ok == true, "40 + 50 = 90: allowed")
        refused({ { op = "set", path = P .. "backPct", value = 51 } }, "range", nil, "backPct over 50")
        refused({ { op = "set", path = P .. "tiers", value = { tier("a", nil, 900, 1), tier("b", nil, 800, 2) } } }, "tierOrder",
            P .. "tiers.2.pts", "a cheaper tier after a dearer one")
        ok = set(Q, { { op = "set", path = P .. "tiers", value = { tier("", nil, 800, 1), tier("", nil, 800, 2) } } })
        T.check(ok == true, "the same price twice and two blank names: allowed")
        refused({ { op = "set", path = P .. "tiers", value = { tier("x", nil, 800, 1), tier("x", nil, 900, 2) } } }, "tierSame",
            P .. "tiers.2.name", "two tiers of one name")
        refused({ { op = "set", path = P .. "tiers", value = { tier("x", "nosuch", 800, 1) } } }, "preset", P .. "tiers.1.preset",
            "a tier on a preset that does not exist")
        local five = {}
        for i = 1, 5 do five[i] = tier("t" .. i, nil, 100 * i, 1) end
        refused({ { op = "set", path = P .. "tiers", value = five } }, "tiers", nil, "5 tiers")
        refused({ { op = "set", path = P .. "tiers", value = {} } }, "tiers", nil, "no tier")
        for _, bad in ipairs({ tier("x", nil, 99, 1), tier("x", nil, 100001, 1), tier("x", nil, 600, 0), tier("x", nil, 600, 11),
            tier("x", nil, 600, 1, 0), tier("x", nil, 600, 1, 121), { name = "x", preset = "default", pts = 600, hp = 1, cap = 9 },
            { name = "x", preset = "default", pts = 600 } }) do
            refused({ { op = "set", path = P .. "tiers", value = { bad } } }, "tiers", nil, "a tier out of range or shape")
        end
        refused({ { op = "set", path = P .. "tiers.1.pts", value = 700 } }, "path", nil, "one tier's key: the list is whole-set only")
        -- deleting a preset a tier plays is refused, like a window's
        set(Q, { { op = "set", path = "hordes.presets.p2", value = { name = "Hard", waves = { wave(5) }, kinds = { vanilla = 1 },
            points = { vanilla = 1 }, cap = 9, limitMin = 5, restSec = 0, maxAlive = 10 } },
            { op = "set", path = P .. "tiers", value = { tier("x", "p2", 800, 1) } } })
        refused({ { op = "del", path = "hordes.presets.p2" } }, "preset", P .. "tiers.1.preset", "deleting the preset a tier plays")
    end)

    section("tiers: the 0.7.0 single price migrates (overrides and config.json)", function()
        local Q = boot()
        local Cf = Q.Config
        local DIR = "MinidoracatQuest/servertest/"
        local function fileTree()
            local f = T.files[DIR .. "config.json"]
            return f and Q.Util.decode(table.concat(f.lines, "\n"), 1000000) or nil
        end
        local t = { hordes = { paid = { enabled = true, pts = 800, preset = "p2", rewardPct = 40 } } }
        T.check(Cf.migrate(t) == true and t.hordes.paid.pts == nil and t.hordes.paid.preset == nil and #t.hordes.paid.tiers == 1
            and t.hordes.paid.tiers[1].name == "normal" and t.hordes.paid.tiers[1].preset == "p2" and t.hordes.paid.tiers[1].pts == 800
            and t.hordes.paid.tiers[1].hp == 1 and t.hordes.paid.rewardPct == 40, "pts + preset -> one tier { normal, p2, 800, x1 }")
        t = { hordes = { paid = { pts = 900 } } }
        Cf.migrate(t)
        T.check(t.hordes.paid.tiers[1].preset == "default" and t.hordes.paid.tiers[1].pts == 900, "only pts: on the default preset")
        t = { hordes = { paid = { preset = "p2" } } }
        Cf.migrate(t)
        T.check(t.hordes.paid.tiers[1].preset == "p2" and t.hordes.paid.tiers[1].pts == 600, "only preset: the old default price 600")
        t = { hordes = { paid = { enabled = true } } }
        T.check(Cf.migrate(t) == false and t.hordes.paid.tiers == nil, "neither (production): unchanged, the default tiers apply")
        t = { hordes = { paid = { pts = 99 } } }
        T.check(Cf.migrate(t) == false and t.hordes.paid.pts == 99, "an old value the old validation refused stays (fails on its path)")
        t = { hordes = { paid = { pts = 800, tiers = { tier("a", nil, 700, 1) } } } }
        T.check(Cf.migrate(t) == false and t.hordes.paid.pts == 800, "an old key next to the new one stays")
        -- (a) stored overrides at boot
        Q.Store.root().config.overrides.hordes = { paid = { enabled = true, pts = 750 } }
        T.files[DIR .. "config.json"] = nil
        Q = boot({ keepGmd = true })
        Cf = Q.Config
        local pt = Cf.get().hordes.paid
        T.check(pt.enabled == true and #pt.tiers == 1 and pt.tiers[1].pts == 750 and Q.Store.root().config.overrides.hordes.paid.pts == nil,
            "old overrides: migrated at boot")
        local mf = fileTree()
        T.check(mf and mf.hordes.paid.pts == nil and mf.hordes.paid.tiers[1].pts == 750, "and config.json written in the new shape")
        -- (b) an old config.json applies (not refused as a whole) and is rewritten
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "paid": { "enabled": true, "pts": 1000, "preset": "default", '
            .. '"minPledge": 20 }, "spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ] } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        pt = Cf.get().hordes.paid
        T.check(Cf.file.status.ok == true and #pt.tiers == 1 and pt.tiers[1].pts == 1000 and pt.minPledge == 20
            and #Cf.get().hordes.spots == 1, "a 0.7.0 config.json with pts / preset applies, migrated, with its other keys")
        mf = fileTree()
        T.check(mf and mf.hordes.paid.pts == nil and mf.hordes.paid.preset == nil and mf.hordes.paid.tiers[1].pts == 1000
            and mf.hordes.paid.minPledge == 20, "config.json rewritten in the new shape")
        local rev = Q.Store.root().config.rev
        T.advance(Cf.POLL_MS)
        T.tick(1)
        T.check(Q.Store.root().config.rev == rev, "the rewritten file is not applied again")
        -- (c) the production file (paid.enabled only) gets the three default tiers
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "paid": { "enabled": true } } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        pt = Cf.get().hordes.paid
        T.check(Cf.file.status.ok == true and #pt.tiers == 3 and pt.tiers[3].name == "nightmare", "paid.enabled alone: the three default tiers")
        -- (d) a bad old price: refused on its path, settings unchanged
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "paid": { "enabled": true, "pts": 50 } } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        T.check(Cf.file.status.ok == false and Cf.file.status.path == "hordes.paid.pts" and #Cf.get().hordes.paid.tiers == 3,
            "pts 50: config.json refused on hordes.paid.pts, the tiers unchanged")
    end)

    section("tiers: a fund from 0.7.0 (no tier copy) plays the first tier", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local alice = players(Q, { "alice" })
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, points = { vanilla = 5 } })
        paid(Q, { enabled = true })
        h.fund = { by = { alice = 100 }, total = 100, pts = 600, startMs = T.now, expireAt = T.now + 30 * MIN, state = "open" }
        local r = pledge(alice, 500, 600, 1)
        T.check(r and r.ok and h.fund.state == "ready", "pledging tier 1 to it works")
        step(Q)
        T.check(h.cur and h.cur.actor == "fund" and h.cur.hpMult == nil and h.cur.points.vanilla == 5 and h.cur.tier == 1
            and h.cur.elite == nil, "planned on the first tier's preset at x1")
    end)
    section("review r1 A-1: a refund or share back for an account that is not there makes it", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        players(Q, { "alice" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        T.check(Q.Store.account("ghost", false) == nil and Q.Store.account("ghost2", false) == nil, "no such accounts yet")
        h.fund = { by = { ghost = 120 }, total = 120, pts = 600, startMs = T.now, expireAt = T.now - 1, state = "open",
            tier = 1, name = "normal", preset = "default", hp = 1, elite = false }
        step(Q)
        local g = Q.Store.account("ghost", false)
        T.check(h.fund == nil and g ~= nil and g.points.balance == 120 and g.spent[1].what == "hordeRefund" and g.spent[1].n == 120,
            "an expired fund pays back a sponsor with no account: made, 120 on it")
        Q.Hordes.payBack({ id = 77, sponsors = { ghost2 = 500 }, backPct = 10 })
        local g2 = Q.Store.account("ghost2", false)
        T.check(g2 ~= nil and g2.points.balance == 50 and g2.spent[1].what == "hordeBack" and g2.spent[1].ref == "horde:77",
            "the share back too: made, 50 on it")
    end)

    section("review r1 A-2: a new fund opens only on the terms the dialog showed (sig)", function()
        local Q = boot()
        local H, h = Q.Hordes, Q.Store.root().hordes
        local alice, bob = players(Q, { "alice", "bob" })
        apply(Q, { spots = { SPOT } })
        paid(Q, { enabled = true })
        local v = H.stateHordes(nil, "alice", T.now).paid.tiers
        T.check(type(v[1].sig) == "string" and #v[1].sig <= Q.Contract.LIMIT.STR and v[1].sig ~= v[2].sig and v[2].sig ~= v[3].sig
            and H.stateHordes(nil, "bob", T.now).paid.tiers[2].sig == v[2].sig, "every tier has a short sig, its own, the same for everyone")
        local function changes(label, fn, i)
            local before = sig(i)
            fn()
            T.check(sig(i) ~= before, label .. ": tier " .. i .. "'s sig changes")
            return before
        end
        local old = changes("its toughness", function()
            paid(Q, { tiers = { tier("normal", nil, 600, 1), tier("hard", nil, 1200, 3), tier("nightmare", nil, 2500, 3) } })
        end, 2)
        local r = cmd(alice, "pledge", { n = 300, total = 1200, tier = 2, sig = old })
        T.check(r and r.code == "PRICE_CHANGED" and h.fund == nil and bal(Q, "alice") == 5000,
            "the dialog showed x2, the tier is x3 now: PRICE_CHANGED, nothing taken")
        r = cmd(alice, "pledge", { n = 300, total = 1200, tier = 2 })
        T.check(r and r.code == "PRICE_CHANGED" and h.fund == nil, "no sig for a new fund: PRICE_CHANGED")
        old = changes("the preset's waves", function() apply(Q, { waves = { wave(4), wave(4) } }) end, 1)
        r = cmd(alice, "pledge", { n = 300, total = 600, tier = 1, sig = old })
        T.check(r and r.code == "PRICE_CHANGED" and h.fund == nil, "the preset got a second wave: PRICE_CHANGED")
        changes("the preset's kinds", function() apply(Q, { kinds = { vanilla = 100, runner = 0 } }) end, 1)
        changes("the preset's minutes", function() apply(Q, { limitMin = 25 }) end, 1)
        changes("rewardPct (the most it pays)", function() paid(Q, { rewardPct = 40 }) end, 2)
        changes("the preset's cap", function() apply(Q, { cap = 100 }) end, 1)
        changes("its name", function()
            paid(Q, { tiers = { tier("normal", nil, 600, 1), tier("Hard!", nil, 1200, 3), tier("nightmare", nil, 2500, 3) } })
        end, 2)
        local same = sig(3)
        paid(Q, { minPledge = 60 })
        T.check(sig(3) == same, "a setting it does not show (minPledge): the same sig")
        r = cmd(alice, "pledge", { n = 300, total = 1200, tier = 2, sig = sig(2) })
        T.check(r and r.ok and h.fund and h.fund.tier == 2 and h.fund.hp == 3, "the current sig opens it")
        r = cmd(bob, "pledge", { n = 100, total = 1200, sig = "stale" })
        T.check(r and r.ok and h.fund.total == 400, "joining an open fund: the sig is not compared (it plays its copy)")
        r = cmd(bob, "pledge", { n = 100, total = 1200 })
        T.check(r and r.ok and h.fund.total == 500, "joining without one")
        h.fund = nil
        paid(Q, { tiers = { tier("normal", nil, 600, 1) } })
        r = cmd(alice, "pledge", { n = 100, total = 600 })
        T.check(r and r.code == "PRICE_CHANGED" and h.fund == nil, "one tier: a new fund needs the sig too")
        r = cmd(alice, "pledge", { n = 100, total = 600, sig = sig(1) })
        T.check(r and r.ok and h.fund ~= nil, "and opens with it")
    end)

    section("review r1 A-3: a 0.7.0 rewardPct over 80 gets the backPct that keeps the two within 90", function()
        local Q = boot()
        local Cf = Q.Config
        local DIR = "MinidoracatQuest/servertest/"
        local function fileTree()
            local f = T.files[DIR .. "config.json"]
            return f and Q.Util.decode(table.concat(f.lines, "\n"), 1000000) or nil
        end
        local function m(paidT)
            local t = { hordes = { paid = paidT } }
            return Cf.migrate(t), t.hordes.paid
        end
        local c, p = m({ rewardPct = 90 })
        T.check(c == true and p.backPct == 0 and p.rewardPct == 90, "rewardPct 90: backPct 0")
        c, p = m({ rewardPct = 85, pts = 800 })
        T.check(c == true and p.backPct == 5 and p.tiers[1].pts == 800, "rewardPct 85 (and the old price): backPct 5, one tier")
        c, p = m({ rewardPct = 80 })
        T.check(c == false and p.backPct == nil, "rewardPct 80: 80 + 10 fits, untouched")
        c, p = m({ rewardPct = 90, backPct = 5 })
        T.check(c == false and p.backPct == 5, "a backPct written next to it: untouched (fails on paidBack)")
        c, p = m({ rewardPct = 95 })
        T.check(c == false and p.backPct == nil, "a rewardPct the old validation refused: untouched (fails on its path)")
        -- (a) stored overrides at boot
        Q.Store.root().config.overrides.hordes = { paid = { enabled = true, rewardPct = 90 } }
        T.files[DIR .. "config.json"] = nil
        Q = boot({ keepGmd = true })
        Cf = Q.Config
        local pt = Cf.get().hordes.paid
        T.check(pt.rewardPct == 90 and pt.backPct == 0 and Q.Store.root().config.overrides.hordes.paid.backPct == 0,
            "old overrides with rewardPct 90: backPct 0 at boot")
        local ok = set(Q, { { op = "set", path = "hordes.paid.minPledge", value = 60 } })
        T.check(ok == true, "and the next change from the panel applies")
        local mf = fileTree()
        T.check(mf and mf.hordes.paid.backPct == 0, "config.json written with it")
        -- (b) a 0.7.0 config.json with rewardPct 90 applies and is rewritten
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "paid": { "enabled": true, "rewardPct": 90, "pts": 700 }, '
            .. '"spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ] } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        pt = Cf.get().hordes.paid
        T.check(Cf.file.status.ok == true and pt.rewardPct == 90 and pt.backPct == 0 and pt.tiers[1].pts == 700,
            "a 0.7.0 config.json with rewardPct 90: applies with backPct 0")
        mf = fileTree()
        T.check(mf and mf.hordes.paid.backPct == 0 and mf.hordes.paid.pts == nil, "config.json rewritten with backPct 0")
    end)
end
