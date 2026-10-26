-- Hordes (server/Hordes.lua): window and hourly rolls, kind mix, state machine, kills and payouts, admin ops,
-- Config hordes.* validation and config.json, the facade's registerHordeKind, the "hordes" state part and delta.
return function(T)
    local MIN, HOUR, DAY = 60000, 3600000, 86400000
    local TZ = 8
    -- Trackers' OnZombieDead path (a horde kill is an ordinary kill too); same fakes as t_catalog when it ran first
    getGameTime = getGameTime or function()
        return { getHour = function() return T.hour or 12 end, getWorldAgeHours = function() return 100 end }
    end
    RainManager = RainManager or { isRaining = function() return T.raining == true end }

    local SPOT = { name = "Gas Station", x = 10620, y = 9810, z = 0 }

    local function section(name, fn)
        T.section("hordes: " .. name)
        local ok, err = pcall(fn)
        if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
    end
    local function boot(opts)
        opts = opts or {}
        opts.sandbox = opts.sandbox or { AdminRoles = "admin", TimezoneOffset = TZ }
        local Q = T.boot(opts)
        Q.Hordes.tick(T.now)   -- first tick: H.boot
        return Q
    end
    -- one Hordes tick at T.now (the 1 s throttle reset)
    local function step(Q)
        Q.Hordes.lastTick = 0
        Q.Hordes.tick(T.now)
    end
    local function apply(Q, fields)
        local changes = {}
        for k, v in pairs(fields) do changes[#changes + 1] = { op = "set", path = "hordes." .. k, value = v } end
        local ok, code, detail = Q.Config.apply(changes, "test", "tester")
        if not ok then T.check(false, "apply hordes: " .. tostring(code) .. " " .. tostring(detail and detail.path)) end
    end
    local function cmd(p, c, args)
        T.advance(300)
        return T.cmd(p, c, args)
    end
    local function adm(p, op, args)
        args = args or {}
        args.op = op
        return cmd(p, "admin", args)
    end
    -- local time hh:mm of local day d (UTC+TZ)
    local function at(d, hh, mm) return d * DAY - TZ * HOUR + (hh * 60 + (mm or 0)) * MIN end
    local function today() return math.floor((T.now + TZ * HOUR) / DAY) end
    local function keyOf(Q, d)
        local y, m, dd = Q.Clock.civil(d)
        return string.format("%d-%02d-%02d", y, m, dd)
    end
    local function near(p, dx) p.x, p.y = SPOT.x + (dx or 30), SPOT.y end
    local function far(p) p.x, p.y = 10000, 10000 end
    local function toasts(p, ev)
        local out = {}
        for _, t in ipairs(T.sentTo(p, "toast")) do
            if (ev == "hordePaid" and t.kind == "hordePaid") or (t.kind == "horde" and t.ev == ev) then out[#out + 1] = t end
        end
        return out
    end
    local function hordeZombies()
        local out = {}
        for _, z in ipairs(T.zombies) do out[#out + 1] = z end
        return out
    end
    local function lastLog(Q)
        local log = Q.Store.root().hordes.log
        return log[#log]
    end
    -- records Points.award calls from now on: rec.horde[user], rec.all[user] (every kind), rec.ref (last horde ref)
    local function spyAwards(Q)
        local rec, orig = { horde = {}, all = {} }, Q.Points.award
        Q.Points.award = function(acc, user, amount, kind, ref, opts)
            local ok = orig(acc, user, amount, kind, ref, opts)
            if ok then
                local n = math.floor(amount + 0.5)
                rec.all[user] = (rec.all[user] or 0) + n
                if kind == "horde" then
                    rec.horde[user] = (rec.horde[user] or 0) + n
                    rec.ref = ref
                end
            end
            return ok
        end
        return rec
    end

    -- ===================== pure window math =====================
    section("window math", function()
        local Q = boot()
        local H = Q.Hordes
        local d = today() + 2
        local cfg = { from = "19:00", to = "23:00", leadMin = 15 }
        local ws, we = H.windowOf(cfg, d, TZ)
        T.check(ws == at(d, 19) and we == at(d, 23), "19:00-23:00 in the sandbox timezone")
        T.check(H.windowOf(cfg, d, 0) == d * DAY + 19 * HOUR, "timezone 0 is UTC")
        local wd, _, _, K = H.window(cfg, at(d, 18, 45), TZ)
        T.check(wd == d and K == 4, "rolls open leadMin before the window (4 hourly slots)")
        T.check(H.window(cfg, at(d, 18, 44), TZ) == nil, "a minute earlier: outside")
        T.check(H.window(cfg, at(d, 23) - 1, TZ) == d and H.window(cfg, at(d, 23), TZ) == nil, "the window ends at to")
        local s0, e0, r0 = H.slot(ws, we, 0, 15)
        T.check(s0 == at(d, 19) and e0 == at(d, 20) and r0 == at(d, 18, 45), "slot 0: 19:00-20:00, rolled at 18:45")
        local part = { from = "19:00", to = "21:30", leadMin = 0 }
        local pws, pwe = H.windowOf(part, d, TZ)
        local _, _, _, pK = H.window(part, at(d, 19), TZ)
        local s2, e2 = H.slot(pws, pwe, 2, 0)
        T.check(pK == 3 and s2 == at(d, 21) and e2 == at(d, 21, 30), "a part hour is the last slot, cut at to")
        local night = { from = "22:00", to = "02:00", leadMin = 15 }
        local nws, nwe = H.windowOf(night, d, TZ)
        T.check(nws == at(d, 22) and nwe == at(d + 1, 2), "to < from runs past midnight")
        T.check(H.window(night, at(d + 1, 1, 30), TZ) == d, "01:30 belongs to the window that opened the day before")
        T.check(H.window(night, at(d + 1, 2), TZ) == nil and H.window(night, at(d + 1, 21, 45), TZ) == d + 1,
            "closed at 02:00; the next one rolls from 21:45")
        local all = { from = "06:00", to = "06:00", leadMin = 15 }
        local aws, awe = H.windowOf(all, d, TZ)
        local _, _, _, aK = H.window(all, at(d, 12), TZ)
        T.check(awe - aws == DAY and aK == 24, "to == from: all day, 24 slots")
        T.check(H.window(all, at(d + 1, 5, 45), TZ) == d + 1 and H.window(all, at(d + 1, 5, 44), TZ) == d,
            "all day: the next day takes over lead minutes before it opens")
        T.check(H.hm("7:05") == 425 and H.hm("23:59") == 1439 and H.hm("19:0") == nil and H.hm("1900") == nil, "HH:MM parse")
    end)

    -- ===================== hourly rolls =====================
    section("hourly rolls: chance, maxPerDay, busy, downtime", function()
        local Q = boot()
        local H = Q.Hordes
        local h = Q.Store.root().hordes
        local alice = T.player{ name = "alice" }
        local d = today() + 2
        apply(Q, { enabled = true, chance = 100, maxPerDay = 2, spots = { SPOT }, count = { 4, 4 } })
        T.now = at(d, 18, 44)
        step(Q)
        T.check(h.cur == nil and h.roll.day ~= keyOf(Q, d), "before the first roll time: nothing")
        T.now = at(d, 18, 45)
        step(Q)
        T.check(h.roll.day == keyOf(Q, d) and h.roll.slot == 1 and h.roll.n == 1, "18:45: slot 0 rolled and hit")
        local cur = h.cur
        T.check(cur ~= nil and cur.auto == true and cur.actor == "auto" and cur.startMs == at(d, 19)
            and cur.announceAt == at(d, 18, 45) and cur.expireAt == at(d, 20), "start 19:00 (lead kept), expires after waitMin")
        T.check(cur and cur.state == "announced" and cur.town == "muldraugh" and cur.count == 4, "announced at once, town from the spot")
        local soon = toasts(alice, "soon")
        T.check(#soon == 1 and soon[1].startMs == at(d, 19) and #soon[1].kinds == 2 and soon[1].count == nil
            and soon[1].name == SPOT.name, "toast soon: kinds with weight > 0, never the count")
        T.now = at(d, 19, 45)
        step(Q)
        T.check(h.roll.slot == 2 and h.roll.n == 1 and h.cur == cur and cur.state == "waiting", "a busy cur skips slot 1")
        H.stop(cur.id, "tester", T.now)
        T.now = at(d, 20, 45)
        step(Q)
        T.check(h.roll.slot == 3 and h.roll.n == 2 and h.cur ~= nil and h.cur.startMs == at(d, 21), "slot 2 hits")
        H.stop(h.cur.id, "tester", T.now)
        T.now = at(d, 21, 45)
        step(Q)
        T.check(h.roll.slot == 4 and h.roll.n == 2 and h.cur == nil, "maxPerDay 2 reached: slot 3 skipped")

        apply(Q, { chance = 0 })
        T.now = at(d + 1, 18, 45)
        step(Q)
        T.check(h.roll.day == keyOf(Q, d + 1) and h.roll.slot == 1 and h.roll.n == 0 and h.cur == nil,
            "a new day resets the roll; chance 0 never hits")
        apply(Q, { chance = 30 })
        T.randQueue = { 30 }
        T.now = at(d + 1, 19, 45)
        step(Q)
        T.check(h.roll.slot == 2 and h.cur == nil, "chance 30: a roll of 30 misses")
        T.randQueue = { 29 }
        T.now = at(d + 1, 20, 45)
        step(Q)
        T.check(h.roll.slot == 3 and h.cur ~= nil and h.cur.startMs == at(d + 1, 21), "chance 30: a roll of 29 hits")
        H.stop(h.cur.id, "tester", T.now)

        apply(Q, { chance = 100 })
        T.now = at(d + 2, 21, 30)
        step(Q)
        T.check(h.roll.slot == 3 and h.roll.n == 1 and h.cur and h.cur.startMs == at(d + 2, 21, 45),
            "after downtime the ended slots are skipped; slot 2 starts at now + lead")
        H.stop(h.cur.id, "tester", T.now)
        T.now = at(d + 3, 21, 50)
        step(Q)
        T.check(h.roll.slot == 4 and h.roll.n == 1 and h.cur and h.cur.startMs == at(d + 3, 22, 5),
            "a slot with less than the lead left is skipped; the next one starts at now + lead")
        H.stop(h.cur.id, "tester", T.now)

        apply(Q, { enabled = false })
        T.now = at(d + 4, 18, 45)
        step(Q)
        T.check(h.roll.slot == 1 and h.cur == nil, "disabled: the slot passes without a horde")
        apply(Q, { enabled = true, spots = {} })
        T.now = at(d + 4, 19, 45)
        step(Q)
        T.check(h.roll.slot == 2 and h.cur == nil, "no spots: no horde")

        -- an admin moves the window start the same day: slot numbers restart from the new start, today's count stays
        apply(Q, { spots = { SPOT }, from = "21:00", maxPerDay = 2 })
        T.now = at(d + 4, 20, 45)
        step(Q)
        T.check(h.roll.slot == 1 and h.roll.n == 1 and h.cur ~= nil and h.cur.startMs == at(d + 4, 21),
            "a moved start rolls its first slot (the old slot count no longer applies)")
        H.stop(h.cur.id, "tester", T.now)
        apply(Q, { from = "21:30", maxPerDay = 1 })
        T.now = at(d + 4, 21, 15)
        step(Q)
        T.check(h.roll.slot == 1 and h.roll.n == 1 and h.cur == nil, "moved again: today's count stays, maxPerDay 1 holds")
    end)

    -- ===================== kind mix =====================
    section("kind mix by weight", function()
        local Q = boot()
        local H = Q.Hordes
        local function n(mix, kind)
            for _, m in ipairs(mix) do if m.kind == kind then return m.n end end
            return nil
        end
        local m = H.mix({ vanilla = 80, runner = 20 }, 30)
        T.check(#m == 2 and n(m, "vanilla") == 24 and n(m, "runner") == 6 and m[1].nameKey == "IGUI_MQ_Horde_Kind_vanilla",
            "80 / 20 of 30 = 24 + 6")
        m = H.mix({ vanilla = 1, runner = 1 }, 3)
        T.check(n(m, "vanilla") + n(m, "runner") == 3 and n(m, "runner") == 2, "the remainder goes to the largest weight (ties by id)")
        m = H.mix({ vanilla = 50, ["other:ghost"] = 50 }, 10)
        T.check(#m == 1 and n(m, "vanilla") == 10, "an unregistered kind is left out")
        m = H.mix({ vanilla = 0, runner = 0 }, 7)
        T.check(#m == 1 and n(m, "vanilla") == 7, "all weights 0: all vanilla")
        m = H.mix({ vanilla = 10, runner = 0 }, 5)
        T.check(#m == 1 and n(m, "runner") == nil, "weight 0 is not announced")
        H.registerKind({ modId = "m", id = "fast", nameKey = "IGUI_M_Fast", spawn = function() return {} end })
        m = H.mix({ vanilla = 50, ["m:fast"] = 50 }, 4)
        T.check(n(m, "m:fast") == 2 and n(m, "vanilla") == 2, "a registered kind joins the mix")
    end)

    -- ===================== manual horde, share payout =====================
    section("manual horde: open, spawn near a player, kills, share payout", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(admin, "hello")
        cmd(alice, "hello")
        cmd(bob, "hello")
        apply(Q, { spots = { SPOT }, count = { 6, 6 }, kinds = { vanilla = 50, runner = 50 }, perZombie = 5 })
        local accA, accB = Q.Store.account("alice", false), Q.Store.account("bob", false)
        local before = { s = accA.points.season, t = accA.points.total, b = accA.points.balance }
        local r = adm(admin, "horde.now")
        local cur = root.hordes.cur
        T.check(r and r.ok and r.id == 1 and cur and cur.id == 1 and cur.auto == false and cur.actor == "admin",
            "horde.now plans one at once")
        T.check(cur and cur.state == "waiting" and root.hordes.roll.n == 0, "manual: waiting now, not counted in roll.n")
        local open = toasts(alice, "open")
        T.check(#open == 1 and #open[1].kinds == 2 and open[1].count == nil and #toasts(alice, "soon") == 0, "toast open (no soon)")
        local hist = Q.Config.historyRows()
        T.check(hist[#hist].summary == "horde.now 1 Gas Station" and hist[#hist].undoable == false, "history row horde.now <id> <name>")
        r = adm(admin, "cfg.undo", { historyId = hist[#hist].id })
        T.check(r and r.code == "BAD_CONFIG", "the history row cannot be undone")
        r = adm(admin, "horde.now")
        T.check(r and r.code == "HORDE_BUSY", "a second horde.now: HORDE_BUSY")

        step(Q)
        T.check(cur.state == "waiting" and #T.spawnCalls == 0, "nobody within 50 tiles: no spawn")
        near(alice, 51)
        step(Q)
        T.check(cur.state == "waiting" and #T.spawnCalls == 0, "51 tiles away: no spawn")
        near(alice, 50)
        step(Q)
        T.check(cur.state == "active" and cur.spawned == 6 and cur.left == 6 and cur.spawnAt == T.now
            and cur.endsAt == T.now + 15 * MIN, "50 tiles: spawned, timer starts")
        local c1 = T.spawnCalls[1]
        T.check(#T.spawnCalls == 2 and c1.x1 == SPOT.x - 5 and c1.y2 == SPOT.y + 5 and c1.z == 0 and c1.n == 3
            and c1.outfit == nil and c1.female == 50, "addZombiesInOutfitArea over the 11 x 11 area, 3 per kind")
        local zs = hordeZombies()
        local sprinters = 0
        for _, z in ipairs(zs) do if z.sprinter then sprinters = sprinters + 1 end end
        T.check(sprinters == 3, "runner kind: doSprinter on its 3")
        local sp = toasts(bob, "spawn")
        T.check(#sp == 1 and sp[1].spawned == 6 and sp[1].pool == 30 and sp[1].split == "share" and sp[1].limitMin == 15,
            "toast spawn with pool and split")

        zs[1]:Kill(alice)
        zs[2]:Kill(alice)
        zs[3]:Kill(alice)
        zs[4]:Kill(bob)
        zs[5]:Kill(bob)
        T.fire("OnZombieDead", zs[1])
        T.check(cur.killed == 5 and cur.kills.alice == 3 and cur.kills.bob == 2 and cur.left == 1,
            "kills counted per player; a second OnZombieDead for the same zombie ignored")
        T.fire("OnZombieDead", T.zombie{ attacker = alice })
        T.check(cur.killed == 5 and cur.kills.alice == 3, "a zombie of no horde is ignored")
        T.check((accA.total["zombie.kills"] or 0) == 4, "horde kills (3) and the stray one still count as ordinary kills ("
            .. tostring(accA.total["zombie.kills"]) .. ")")
        -- spawned zombies report isExistInTheWorld() false (env.lua, quest-hz-1026e) and still count
        step(Q)
        T.check(root.hordes.cur == cur and cur.left == 1, "one alive: still active")
        zs[6]:Kill(nil)
        T.check(cur.killed == 6 and cur.kills.alice == 3, "a death without attacker clears it, no kill")
        local before = { s = accA.points.season, t = accA.points.total, b = accA.points.balance }
        local awards = spyAwards(Q)
        step(Q)
        T.check(root.hordes.cur == nil, "all gone with a player near: success")
        -- pool 30, attributed kills 5: alice 3/5 = 18, bob 2/5 = 12 (the fire death is not in the share)
        T.check(awards.horde.alice == 18 and awards.horde.bob == 12 and awards.ref == "horde:1", "points kind horde, by kill share")
        local all = awards.all.alice   -- + the hidden achievement's own points
        T.check(accA.points.season == before.s + all and accA.points.total == before.t + all
            and accA.points.balance == before.b + all and all > 18, "horde points reach season, total and balance")
        local pa, pb = toasts(alice, "hordePaid"), toasts(bob, "hordePaid")
        T.check(#pa == 1 and pa[1].pts == 18 and pa[1].kills == 3 and pa[1].pct == 60 and #pb == 1 and pb[1].pts == 12
            and pb[1].pct == 40, "personal toasts: points, kills, share %")
        local win = toasts(admin, "win")
        T.check(#win == 1 and win[1].n == 2 and win[1].spawned == 6 and win[1].killed == 6 and win[1].pool == 30, "toast win")
        T.check(accA.total["horde.wins"] == 1 and accB.total["horde.wins"] == 1 and accA.achv.h_horde == 1
            and accA.titles.h_horde == true, "horde.wins + 1 each; hidden h_horde and its title unlock")
        T.check((Q.Store.account("admin", false).total["horde.wins"] or 0) == 0, "no kill, no participation")
        local e = lastLog(Q)
        T.check(e.state == "success" and e.paid.alice == 18 and e.paid.bob == 12 and e.pool == 30 and e.spawned == 6
            and e.killed == 6 and e.auto == false and e.endedAt == T.now, "archived in root.hordes.log")
        local logged = false
        for _, b in ipairs(Q.EventLog.buffer) do
            if string.find(b.line, '"k":"horde"', 1, true) and string.find(b.line, '"state":"success"', 1, true) then logged = true end
        end
        T.check(logged, "event log kind horde")
        local live = 0
        for _ in pairs(H.live) do live = live + 1 end
        T.check(live == 0, "no zombie left in H.live")
    end)

    -- ===================== each, zero kills, pool 0 =====================
    section("payouts: each, no attributed kill, pool 0, share floor", function()
        local Q = boot()
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(alice, "hello")
        cmd(bob, "hello")
        apply(Q, { spots = { SPOT }, count = { 4, 4 }, kinds = { vanilla = 100 }, perZombie = 5, split = "each" })
        local accA, accB = Q.Store.account("alice", false), Q.Store.account("bob", false)
        local awards = spyAwards(Q)
        near(alice)
        adm(admin, "horde.now")
        local zs = hordeZombies()
        T.check(root.hordes.cur and root.hordes.cur.state == "active" and #zs == 4, "horde.now with a player near spawns at once")
        zs[1]:Kill(alice)
        zs[2]:Kill(alice)
        zs[3]:Kill(alice)
        zs[4]:Kill(bob)
        step(Q)
        T.check(awards.horde.alice == 20 and awards.horde.bob == 20, "each: every participant gets the whole pool")
        local pa = toasts(alice, "hordePaid")
        T.check(#pa == 1 and pa[1].pts == 20 and pa[1].pct == nil, "each: no share % in the toast")

        T.clearOutbox()
        adm(admin, "horde.now")
        for _, z in ipairs(hordeZombies()) do if not z.dead then z:Kill(nil) end end
        step(Q)
        local e = lastLog(Q)
        local paid = 0
        for _ in pairs(e.paid) do paid = paid + 1 end
        T.check(e.state == "success" and paid == 0 and #toasts(alice, "hordePaid") == 0 and toasts(alice, "win")[1].n == 0,
            "no attributed kill: success, nobody paid")

        apply(Q, { perZombie = 0, split = "share" })
        T.clearOutbox()
        awards = spyAwards(Q)
        local w1 = accA.total["horde.wins"]
        adm(admin, "horde.now")
        for _, z in ipairs(hordeZombies()) do if not z.dead then z:Kill(alice) end end
        step(Q)
        pa = toasts(alice, "hordePaid")
        T.check(awards.horde.alice == nil and accA.total["horde.wins"] == w1 + 1 and #pa == 0,
            "perZombie 0: no points, no personal toast, still a win")

        -- the share formula's floor: max(1, floor(pool * n / kills + 0.5)) with a tiny share
        apply(Q, { perZombie = 1 })
        T.clearOutbox()
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        cur.spawned, cur.kills = 10, { alice = 30, bob = 1 }
        Q.Hordes.finish("success", nil, T.now)
        T.check(lastLog(Q).paid.bob == 1 and lastLog(Q).paid.alice == 10, "share: at least 1 point per participant")
    end)

    -- ===================== design r12: stats, MVP, the records rows =====================
    section("r12: horde stats, MVP, achievements and the records rows", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(alice, "hello")
        cmd(bob, "hello")
        T.check(H.stateHordes(nil, "alice", T.now).on == false, "automatic hordes off and no result yet: the page stays out of the nav")
        apply(Q, { spots = { SPOT }, count = { 4, 4 }, kinds = { vanilla = 100 }, perZombie = 5, split = "share" })
        local accA, accB = Q.Store.account("alice", false), Q.Store.account("bob", false)
        near(alice)
        adm(admin, "horde.now")
        local zs = hordeZombies()
        zs[1]:Kill(alice)
        zs[2]:Kill(alice)
        zs[3]:Kill(alice)
        T.check(accA.total["horde.kills"] == 3 and (accA.total["horde.joined"] or 0) == 0, "each horde kill counts horde.kills at once")
        zs[4]:Kill(bob)
        step(Q)
        T.check(accA.total["horde.joined"] == 1 and accB.total["horde.joined"] == 1 and accB.total["horde.kills"] == 1,
            "a win: every participant joined")
        T.check(accA.total["horde.mvp"] == 1 and (accB.total["horde.mvp"] or 0) == 0 and accA.achv.horde_mvp == 1,
            "the top killer of a win with 2+ participants: MVP, tier I unlocks")
        T.check(accA.season["horde.kills"] == 3 and accA.life["horde.kills"] == nil, "account stats: season and total, no per-life value")

        local function finishWith(kills, result, why)
            adm(admin, "horde.now")
            local cur = root.hordes.cur
            cur.spawned, cur.kills = 10, kills
            H.finish(result or "success", why, T.now)
        end
        finishWith({ alice = 2, bob = 2 })
        T.check(accA.total["horde.mvp"] == 2 and accB.total["horde.mvp"] == 1, "a tie: both are MVP")
        finishWith({ alice = 5 })
        T.check(accA.total["horde.mvp"] == 2 and accA.total["horde.wins"] == 3 and accA.achv.horde_wins == 1,
            "one participant: no MVP; the third win unlocks Horde Sweeper tier I")
        finishWith({ alice = 1, bob = 3 }, "failed", "time")
        T.check(accB.total["horde.joined"] == 3 and accB.total["horde.mvp"] == 1 and accB.total["horde.wins"] == 2,
            "a fail: joined counts, no win, no MVP")
        local cur = H.plan(Q.Config.get().hordes, T.now + 2 * HOUR, nil)
        H.stop(cur.id, "admin", T.now)
        T.check(lastLog(Q).announced == false, "a cancel before the warning stays secret")

        T.clearOutbox()
        cmd(alice, "records")
        local rec = T.lastOf(alice, "records")
        local rows = rec and rec.hordes or {}
        T.check(#rows == 4 and rows[1].state == "failed" and rows[1].why == "time" and rows[1].mine == 1 and rows[1].got == 0
            and rows[4].state == "success" and rows[4].mine == 3 and rows[4].got > 0 and rows[4].spawned == 4,
            "records: the announced results, newest first, with my kills and points (the secret cancel left out)")
        T.check(rows[1].kills == nil and rows[1].paid == nil, "records rows carry only my share, not everyone's")
        cmd(bob, "records")
        local rb = T.lastOf(bob, "records").hordes
        T.check(rb[1].mine == 3 and rb[2].mine == 0 and rb[2].got == 0, "the same rows with bob's share")
        for _ = 1, H.RECENT + 2 do finishWith({ alice = 1 }) end
        cmd(alice, "records")
        T.check(#T.lastOf(alice, "records").hordes == H.RECENT, "at most H.RECENT rows")
        T.check(H.stateHordes(nil, "bob", T.now).on == true, "results to list: the page is in the nav")
    end)

    -- ===================== design r12: warning lead and the reminder =====================
    section("r12: manual warning lead and the reminder near the spot", function()
        local Q = boot()
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(alice, "hello")
        cmd(bob, "hello")
        apply(Q, { spots = { SPOT }, count = { 4, 4 }, kinds = { vanilla = 100 } })
        near(alice)
        far(bob)
        T.clearOutbox()
        local r = adm(admin, "horde.now", { lead = 5 })
        local cur = root.hordes.cur
        T.check(r and r.code == "OK" and cur.state == "announced" and cur.announceAt <= T.now and cur.startMs - cur.announceAt == 5 * MIN
            and cur.expireAt == cur.startMs + cur.waitMin * MIN, "lead 5: warned now, starts 5 minutes later")
        local soon = toasts(bob, "soon")
        T.check(#soon == 1 and soon[1].startMs == cur.startMs and #toasts(bob, "open") == 0, "everyone gets the warning with the start time")
        T.now = cur.startMs - 2 * MIN - 1
        step(Q)
        T.check(#toasts(alice, "remind") == 0 and #T.zombies == 0, "before the last 2 minutes: no reminder, nothing spawned")
        T.now = cur.startMs - 2 * MIN
        step(Q)
        local rem = toasts(alice, "remind")
        T.check(#rem == 1 and rem[1].startMs == cur.startMs and rem[1].name == SPOT.name and #toasts(bob, "remind") == 0,
            "2 minutes before: a personal reminder to the player within 50 tiles only")
        step(Q)
        T.check(#toasts(alice, "remind") == 1, "the reminder comes once")
        T.now = cur.startMs
        step(Q)
        T.check(cur.state == "active" and #T.zombies == 4, "at the start a player near spawns it")
        adm(admin, "horde.stop", { id = cur.id })

        T.clearOutbox()
        adm(admin, "horde.now", { lead = 2 })
        cur = root.hordes.cur
        T.check(cur.state == "announced" and cur.reminded == true, "a warning of 2 minutes or less is its own reminder")
        step(Q)
        T.check(#toasts(alice, "remind") == 0, "no second notice")
        adm(admin, "horde.stop", { id = cur.id })

        T.clearOutbox()
        adm(admin, "horde.now", { lead = 0 })
        T.check(root.hordes.cur.state == "active" and #toasts(alice, "open") == 1 and #toasts(alice, "soon") == 0,
            "lead 0: open at once, as before")
        adm(admin, "horde.stop", { id = root.hordes.cur.id })
        for _, bad in ipairs({ -1, 121 }) do
            r = adm(admin, "horde.now", { lead = bad })
            T.check(r and r.code == "BAD_ARGS" and root.hordes.cur == nil, "lead " .. bad .. ": refused")
        end
    end)

    -- ===================== failures =====================
    section("failures: time, nobody, spawn, virtualised zombies", function()
        local Q = boot()
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        cmd(alice, "hello")
        local accA = Q.Store.account("alice", false)
        apply(Q, { spots = { SPOT }, count = { 4, 4 }, kinds = { vanilla = 100 } })

        near(alice)
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        local zs = hordeZombies()
        zs[1]:Kill(alice)
        local p0 = accA.points.total
        T.now = cur.endsAt - 1
        step(Q)
        T.check(root.hordes.cur == cur, "before endsAt: still active")
        T.now = cur.endsAt
        step(Q)
        local e = lastLog(Q)
        T.check(root.hordes.cur == nil and e.state == "failed" and e.why == "time" and e.killed == 1, "endsAt: failed time")
        T.check(zs[2].oid == -1 and not zs[2].onSquare and zs[4].oid == -1 and zs[2].dead == false,
            "the rest removed through H.clearZombie (removeFromWorld + removeFromSquare)")
        T.check(accA.points.total == p0 and (accA.total["horde.wins"] or 0) == 0, "time out: no reward, no win")
        local fail = toasts(alice, "fail")
        T.check(#fail == 1 and fail[1].why == "time" and fail[1].left == 3, "toast fail with why and left")

        -- every zombie virtualised (walked away) and nobody near: not a success, nothing counted
        adm(admin, "horde.now")
        cur = root.hordes.cur
        zs = hordeZombies()
        far(alice)
        zs[7]:removeFromWorld()   -- virtualised by the engine: online id -1, off the square
        zs[8]:removeFromWorld()
        zs[6].oid = -1            -- online id -1 while the square still lists it
        zs[5].oid = 9999          -- object reused for another zombie: its death is not ours
        step(Q)
        T.check(root.hordes.cur == cur and cur.left == 0 and cur.killed == 0,
            "virtualised, removed (id -1) or reused zombies are gone; nobody near: still active")
        zs[5]:Kill(alice)
        T.check(cur.killed == 0, "a reused zombie object is not a horde kill")
        T.now = cur.endsAt
        step(Q)
        T.check(lastLog(Q).why == "time" and zs[6].onSquare == true, "time out; virtualised zombies stay normal zombies")

        T.clearOutbox()
        adm(admin, "horde.now")
        cur = root.hordes.cur
        T.now = cur.expireAt - 1
        step(Q)
        T.check(root.hordes.cur == cur and cur.state == "waiting", "before expireAt: waiting")
        T.now = cur.expireAt
        step(Q)
        T.check(lastLog(Q).state == "failed" and lastLog(Q).why == "nobody" and toasts(alice, "fail")[1].why == "nobody",
            "nobody within 50 tiles before expireAt: failed nobody")

        T.spawnCap = 0
        adm(admin, "horde.now")
        cur = root.hordes.cur
        near(alice)
        for _ = 1, 9 do step(Q) end
        T.check(root.hordes.cur == cur and cur.tries == 9 and cur.state == "waiting", "9 empty spawns: still waiting")
        step(Q)
        T.check(root.hordes.cur == nil and lastLog(Q).why == "spawn", "10 empty spawns: failed spawn")
        T.spawnCap, T.staleOwner = 2, alice
        adm(admin, "horde.now")
        T.check(root.hordes.cur.spawned == 2 and root.hordes.cur.left == 2, "unloaded squares: counts what really spawned")
        local owned = 0
        for z, t in pairs(Q.Hordes.live) do
            if t.horde == root.hordes.cur.id and (z.owner ~= nil or z.ownerPlayer ~= nil) then owned = owned + 1 end
        end
        T.check(owned == 0, "reused zombie objects: the network owner of their last life is cleared (quest-hz-1026j)")
    end)

    -- ===================== admin stop, restart =====================
    section("admin stop and restart", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(bob, "hello")
        apply(Q, { spots = { SPOT }, count = { 4, 4 }, kinds = { vanilla = 100 } })
        local cfg = Q.Config.get().hordes

        local cur = H.plan(cfg, T.now + 2 * HOUR, nil)
        step(Q)
        T.check(cur.state == "planned", "planned until announceAt")
        local r = adm(bob, "horde.stop", { id = cur.id })
        T.check(r and r.code == "FORBIDDEN" and root.hordes.cur == cur, "non-admin horde.stop refused")
        r = adm(bob, "horde.now")
        T.check(r and r.code == "FORBIDDEN", "non-admin horde.now refused")
        r = adm(bob, "horde.status")
        T.check(r and r.code == "FORBIDDEN", "non-admin horde.status refused")
        r = adm(admin, "horde.stop", { id = cur.id + 1 })
        T.check(r and r.code == "NOT_FOUND", "stop of another id: NOT_FOUND")
        T.clearOutbox()
        r = adm(admin, "horde.stop", { id = cur.id })
        T.check(r and r.ok and root.hordes.cur == nil and lastLog(Q).state == "cancelled" and lastLog(Q).announced == false
            and #toasts(alice, "cancel") == 0, "planned -> cancelled, players never hear of it")
        local hist = Q.Config.historyRows()
        T.check(hist[#hist].summary == "horde.stop " .. cur.id .. " Gas Station" and hist[#hist].undoable == false,
            "history row horde.stop <id> <name>")
        T.check(H.stateHordes(nil, "bob", T.now).last == nil, "a secret cancel is not shown as the last result")

        cur = H.plan(cfg, T.now + 10 * MIN, nil)
        step(Q)
        T.check(cur.state == "announced", "announced")
        adm(admin, "horde.stop", { id = cur.id })
        T.check(lastLog(Q).state == "cancelled" and #toasts(alice, "cancel") == 1, "announced -> cancelled, toast cancel")
        T.check(H.stateHordes(nil, "bob", T.now).last.state == "cancelled", "the cancel shows as the last result")

        adm(admin, "horde.now")
        cur = root.hordes.cur
        adm(admin, "horde.stop", { id = cur.id })
        T.check(lastLog(Q).state == "failed" and lastLog(Q).why == "admin", "waiting -> failed admin")

        near(alice)
        adm(admin, "horde.now")
        cur = root.hordes.cur
        local zs = hordeZombies()
        zs[1]:Kill(alice)
        adm(admin, "horde.stop", { id = cur.id })
        T.check(lastLog(Q).why == "admin" and lastLog(Q).killed == 1 and not zs[2].inWorld and not zs[4].inWorld,
            "active -> failed admin, the rest cleared")
        T.check(H.stateHordes(nil, "alice", T.now).last.got == nil, "no reward on a stop")

        adm(admin, "horde.now")
        cur = root.hordes.cur
        zs = hordeZombies()
        T.check(cur.state == "active", "active before the restart")
        local id = cur.id
        Q = boot({ keepGmd = true, keepFiles = true })
        root = Q.Store.root()
        local e = root.hordes.log[#root.hordes.log]
        T.check(root.hordes.cur == nil and e.id == id and e.state == "failed" and e.why == "restart",
            "a restart fails the active horde (restart)")
        T.check(zs[#zs].oid ~= -1 and zs[#zs].onSquare == true, "its zombies stay in the world as normal zombies (not cleared)")
        T.check(root.hordes.seq == id, "ids keep counting across the restart")
    end)

    -- ===================== status, provider, delta =====================
    section("horde.status, the hordes part and its delta", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(alice, "hello")
        cmd(bob, "hello")
        local r = adm(admin, "horde.now")
        T.check(r and r.code == "NO_SPOTS", "no spots: NO_SPOTS")
        apply(Q, { enabled = true, chance = 0, spots = { SPOT }, count = { 4, 4 }, kinds = { vanilla = 75, runner = 25 } })
        local cfg = Q.Config.get().hordes
        local d = today() + 2
        T.now = at(d, 12)
        step(Q)
        r = adm(admin, "horde.status")
        T.check(r and r.ok and r.cur == nil and r.roll.max == 1 and r.roll.enabled == true and r.roll.nextAt == at(d, 18, 45),
            "status: next roll at 18:45")
        T.check(#r.kinds == 2 and r.kinds[1].id == "vanilla" and r.kinds[1].builtin == true and r.kinds[2].id == "runner",
            "status: built-in kinds")

        local cur = H.plan(cfg, T.now + HOUR, nil)
        r = adm(admin, "horde.status")
        T.check(r.cur and r.cur.state == "planned" and r.cur.count == 4 and #r.cur.mix == 2 and r.cur.kills ~= nil,
            "status shows the planned horde in full")
        T.check(H.stateHordes(nil, "bob", T.now).cur == nil, "players do not see a planned horde")

        cmd(bob, "track", { on = true })
        cmd(alice, "watch", { on = true })
        T.now = cur.announceAt - 5000
        T.tick(12)               -- flush what the jump in time marked (the day change sends full states)
        T.clearOutbox()
        T.now = cur.announceAt
        T.tick(12)
        local dB, dA = T.lastOf(bob, "delta"), T.lastOf(alice, "delta")
        T.check(dB and dB.hordes and dB.hordes.cur and dB.hordes.cur.state == "announced" and T.lastOf(bob, "state") == nil,
            "a tracker-only player gets the hordes part in a delta")
        T.check(dA and dA.hordes and dA.hordes.cur and T.lastOf(alice, "state") == nil, "an open window gets it as a delta too")
        local v = dB.hordes.cur
        T.check(v.count == nil and v.mix == nil and v.pool == nil and v.mine == 0 and #v.kinds == 2 and v.x == SPOT.x
            and v.startMs == cur.startMs, "the view: spot and kinds, no count, no pool before the spawn")
        T.check(Q.Sync.state("bob", Q.Store.account("bob", false)).hordes.cur.id == cur.id, "full state carries it")

        near(alice)
        T.now = cur.startMs
        step(Q)
        for _, z in ipairs(hordeZombies()) do z:Kill(alice) end
        v = H.stateHordes(nil, "alice", T.now).cur
        T.check(v.pool == 20 and v.mine == 4 and v.left == 0 and v.killed == 4, "after the spawn: pool, my kills, left")
        step(Q)
        local ended = T.now
        local last = H.stateHordes(nil, "alice", T.now).last
        T.check(H.stateHordes(nil, "alice", T.now).cur == nil and last and last.state == "success" and last.got == 20
            and last.mine == 4, "the last result: state, my kills, my points")
        T.check(H.stateHordes(nil, "bob", T.now).last.got == nil, "someone who did not take part: no points in it")
        T.check(H.stateHordes(nil, "alice", ended + H.LAST_MS - 1).last ~= nil
            and H.stateHordes(nil, "alice", ended + H.LAST_MS).last == nil, "the last result shows for 10 minutes")

        H.startNow("admin", T.now)
        H.finish("success", nil, T.now)
        H.startNow("admin", T.now)
        H.stop(root.hordes.cur.id, "admin", T.now)
        r = adm(admin, "horde.status")
        T.check(#r.log == 3 and r.log[1].id > r.log[2].id and r.log[2].id > r.log[3].id, "status log: newest first")
        apply(Q, { enabled = false })
        r = adm(admin, "horde.status")
        T.check(r.roll.nextAt == nil and r.roll.enabled == false, "disabled: no next roll")
    end)

    -- ===================== config =====================
    section("Config hordes.* validation", function()
        local Q = boot()
        local Cf = Q.Config
        local function ok(path, value) return (Cf.validate({ op = "set", path = "hordes." .. path, value = value })) end
        local function spots(n, extra)
            local out = {}
            for i = 1, n do out[i] = { name = "S" .. i, x = 1, y = 2, z = 0 } end
            if extra then for k, x in pairs(extra) do out[1][k] = x end end
            return out
        end
        local good = {
            { "enabled", true }, { "from", "7:05" }, { "to", "23:59" }, { "to", "00:00" }, { "chance", 0 }, { "chance", 100 },
            { "maxPerDay", 1 }, { "maxPerDay", 24 }, { "leadMin", 0 }, { "leadMin", 120 }, { "waitMin", 1 }, { "waitMin", 240 },
            { "count", { 1, 100 } }, { "count", { 5, 5 } }, { "kinds.vanilla", 0 }, { "kinds.runner", 100 },
            { "kinds", { vanilla = 10, ["m:fast"] = 5 } }, { "kinds.m:fast", 7 }, { "limitMin", 1 }, { "limitMin", 120 },
            { "perZombie", 0 }, { "perZombie", 1000 }, { "split", "share" }, { "split", "each" }, { "spots", {} },
            { "spots", spots(32) }, { "spots", spots(1, { z = -32 }) }, { "spots", spots(1, { z = 31, x = 100000 }) },
        }
        for _, g in ipairs(good) do T.check(ok(g[1], g[2]), "valid hordes." .. g[1]) end
        local bad = {
            { "enabled", "yes" }, { "from", "24:00" }, { "from", "19:60" }, { "from", "1900" }, { "to", "19:0" }, { "to", 1900 },
            { "chance", 101 }, { "chance", -1 }, { "chance", 5.5 }, { "maxPerDay", 0 }, { "maxPerDay", 25 }, { "leadMin", 121 },
            { "waitMin", 0 }, { "waitMin", 241 }, { "count", { 6, 5 } }, { "count", { 0, 5 } }, { "count", { 1, 101 } },
            { "count", { 5 } }, { "count", 5 }, { "kinds.vanilla", 101 }, { "kinds", { ["a b"] = 1 } }, { "kinds", { vanilla = -1 } },
            { "limitMin", 0 }, { "limitMin", 121 }, { "perZombie", 1001 }, { "split", "all" }, { "spots", spots(33) },
            { "spots", spots(1, { z = 32 }) }, { "spots", spots(1, { z = -33 }) }, { "spots", spots(1, { x = 100001 }) },
            { "spots", spots(1, { name = "" }) }, { "spots", spots(1, { name = "a\nb" }) }, { "spots", spots(1, { town = "x" }) },
            { "spots", { 1 } }, { "foo", 1 },
        }
        for _, b in ipairs(bad) do T.check(not ok(b[1], b[2]), "invalid hordes." .. b[1] .. " = " .. tostring(b[2])) end
        T.check(not Cf.validate({ op = "set", path = "hordes", value = { enabled = true, foo = 1 } }), "unknown key inside hordes")
        T.check(Cf.validate({ op = "set", path = "hordes", value = { enabled = true, from = "06:00", to = "06:00" } }), "whole group")
    end)

    section("config.json round trip of hordes", function()
        local Q = boot()
        local DIR = "MinidoracatQuest/servertest/"
        local function fileTree(name)
            local f = T.files[DIR .. name]
            return f and Q.Util.decode(table.concat(f.lines, "\n"), 1000000) or nil
        end
        local defaults = fileTree("defaults.json")
        T.check(defaults and defaults.hordes and defaults.hordes.from == "19:00" and defaults.hordes.kinds.runner == 20
            and defaults.hordes.count[2] == 40, "defaults.json carries the hordes group")
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "enabled": true, "chance": 55, '
            .. '"spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ], "kinds": { "runner": 0 } } }' } }
        T.advance(Q.Config.POLL_MS)
        T.tick(1)
        local h = Q.Config.get().hordes
        T.check(h.enabled == true and h.chance == 55 and #h.spots == 1 and h.spots[1].name == "Lot" and h.kinds.runner == 0
            and h.kinds.vanilla == 80 and h.from == "19:00", "an edited config.json applies hordes (kinds merge, spots replace)")
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "spots": [ { "name": "Lot", "x": 1, "y": 1, "z": 40 } ] } }' } }
        T.advance(Q.Config.POLL_MS)
        T.tick(1)
        T.check(Q.Config.file.status.ok == false and Q.Config.file.status.path == "hordes.spots" and Q.Config.get().hordes.chance == 55,
            "a bad spot in config.json: nothing applied, the path reported")
        apply(Q, { split = "each" })
        local mirrored = fileTree("config.json")
        T.check(mirrored and mirrored.hordes.split == "each" and mirrored.hordes.chance == 55 and mirrored.hordes.spots[1].x == 10600,
            "a panel change to hordes is written back to config.json")
    end)

    -- ===================== facade =====================
    section("v1.registerHordeKind", function()
        local Q = boot()
        local H = Q.Hordes
        local v1 = Q.v1
        T.check(v1 and v1.API_MAJOR == 1 and v1.API_REVISION == 2 and v1.registerHordeKind == H.registerKind, "facade rev 2")
        local function spec(modId, id, extra)
            local s = { modId = modId, id = id, nameKey = "IGUI_X_" .. id, spawn = function() return {} end }
            for k, x in pairs(extra or {}) do s[k] = x end
            return s
        end
        T.check(v1.registerHordeKind(spec("ghostmod", "wraith")) == true and H.kinds["ghostmod:wraith"].modId == "ghostmod",
            "a valid kind registers as <modId>:<id>")
        local bads = {
            { spec("bad mod", "x"), "modId with a space" }, { spec("m", string.rep("a", 33)), "id over 32" },
            { spec("m", "x", { nameKey = "IGUI-X" }), "nameKey with a dash" }, { spec("m", "x", { spawn = "fn" }), "spawn not a function" },
            { spec(string.rep("m", 64), "x"), "key over 64 (the config weight key)" }, { "nope", "not a table" },
            { spec("m", "a:b"), "id with a colon" },
        }
        for _, b in ipairs(bads) do
            local okR, code = v1.registerHordeKind(b[1])
            T.check(okR == nil and code == "invalid_args", "rejected: " .. b[2])
        end
        for i = 1, 7 do v1.registerHordeKind(spec("ghostmod", "k" .. i)) end
        local okR, code = v1.registerHordeKind(spec("ghostmod", "k8"))
        T.check(okR == nil and code == "invalid_args", "9th kind of one mod refused (8 per mod)")
        T.check(v1.registerHordeKind(spec("ghostmod", "wraith", { nameKey = "IGUI_X_New" })) == true
            and H.kinds["ghostmod:wraith"].nameKey == "IGUI_X_New", "re-registering a key replaces it, even at the cap")
        for m = 1, 3 do for i = 1, 8 do v1.registerHordeKind(spec("mod" .. m, "k" .. i)) end end
        okR = v1.registerHordeKind(spec("mod4", "k1"))
        T.check(okR == nil, "33rd kind across mods refused (32 in all)")
        T.check(#H.kindList() == 34 and H.kindList()[3].id == "ghostmod:k1" and H.kindList()[3].builtin == false,
            "status kinds: built-ins first, then by id")
    end)

    section("a registered kind spawns through pcall", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local got = {}
        H.registerKind({ modId = "ghostmod", id = "wraith", nameKey = "IGUI_GM_Wraith", spawn = function(x, y, z, n)
            got[#got + 1] = { x = x, y = y, z = z, n = n }
            local list = { "not a zombie" }
            for i = 1, n + 2 do list[#list + 1] = T.zombie() end
            return list
        end })
        H.registerKind({ modId = "ghostmod", id = "broken", nameKey = "IGUI_GM_Broken", spawn = function() error("boom") end })
        apply(Q, { spots = { SPOT }, count = { 6, 6 }, kinds = { vanilla = 0, runner = 0, ["ghostmod:wraith"] = 50,
            ["ghostmod:broken"] = 50 } })
        near(alice)
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        T.check(#got == 1 and got[1].x == SPOT.x and got[1].n == 3, "the kind's spawn gets the spot and its share")
        T.check(cur.state == "active" and cur.spawned == 3, "only IsoZombie, at most n of them; a failing kind is skipped")
        T.check(T.logged("horde kind ghostmod:broken failed") or T.printed("horde kind ghostmod:broken failed"),
            "the failing kind is logged")
        local open = toasts(alice, "open")
        T.check(#open == 1 and #open[1].kinds == 2 and open[1].kinds[1].nameKey == "IGUI_GM_Broken"
            and open[1].kinds[2].nameKey == "IGUI_GM_Wraith", "the announcement names registered kinds by their nameKey")
    end)
end
