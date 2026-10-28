-- Hordes (server/Hordes.lua): windows with weekdays and hourly rolls, presets (a window's or horde.now's set of waves,
-- kinds, points, hp, cap, limitMin, restSec, maxAlive) and each window's lead / wait, kind mix, waves (size by players
-- near, exits, maxAlive batches, lure, rest, the hp multiplier), kills and the capped kill-value payout, admin ops,
-- boot, Config hordes.* validation, the 0.2.0 and presets migrations and config.json, the facade's
-- registerHordeKind, the "hordes" state part and delta; joined, deaths and their toasts, the MVP toast, the result
-- (H.result, its push to the players there at the end, the hordeResult query).
return function(T)
    local MIN, HOUR, DAY = 60000, 3600000, 86400000
    local TZ = 8
    -- Trackers' OnZombieDead path (a horde kill is an ordinary kill too); same fakes as t_catalog when it ran first
    getGameTime = getGameTime or function()
        return { getHour = function() return T.hour or 12 end, getWorldAgeHours = function() return 100 end }
    end
    RainManager = RainManager or { isRaining = function() return T.raining == true end }

    local SPOT = { name = "Gas Station", x = 10620, y = 9810, z = 0 }
    local ALL = "1234567"

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
    -- fields: hordes.<key>; the preset knobs (waves, kinds, ...) go to the default preset
    local PRESET = { waves = true, kinds = true, points = true, hp = true, cap = true, limitMin = true, restSec = true,
        maxAlive = true }
    local function apply(Q, fields)
        local changes = {}
        for k, v in pairs(fields) do
            changes[#changes + 1] = { op = "set", path = (PRESET[k] and "hordes.presets.default." or "hordes.") .. k, value = v }
        end
        local ok, code, detail = Q.Config.apply(changes, "test", "tester")
        if not ok then T.check(false, "apply hordes: " .. tostring(code) .. " " .. tostring(detail and detail.path)) end
    end
    -- a window; o = { preset, leadMin, waitMin } (default "default", 15, 60)
    local function win(from, to, chance, days, o)
        o = o or {}
        return { days = days or ALL, from = from, to = to, chance = chance, preset = o.preset or "default",
            leadMin = o.leadMin or 15, waitMin = o.waitMin or 60 }
    end
    local function wave(base, perPlayer) return { base = base, perPlayer = perPlayer or 0 } end
    -- the default preset in effect
    local function def(Q) return Q.Config.get().hordes.presets.default end
    -- a whole preset (every knob but hp, like the defaults) named name, with o's knobs over it
    local function full(name, o)
        local p = { name = name, waves = { wave(30, 50) }, kinds = { vanilla = 80, runner = 20 },
            points = { vanilla = 5, runner = 8 }, cap = 500, limitMin = 15, restSec = 30, maxAlive = 200 }
        for k, v in pairs(o or {}) do p[k] = v end
        return p
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
    local function sortedIds(ids)
        local t = {}
        for i, v in ipairs(type(ids) == "table" and ids or {}) do t[i] = v end
        table.sort(t)
        return table.concat(t, ",")
    end
    local function aliveOf(Q, id)
        local n = 0
        for z, t in pairs(Q.Hordes.live) do
            if t.horde == id and not z.dead and z.oid ~= -1 then n = n + 1 end
        end
        return n
    end
    local function killAlive(Q, id, who, max)
        local n = 0
        local list = {}
        for z, t in pairs(Q.Hordes.live) do if t.horde == id then list[#list + 1] = z end end
        table.sort(list, function(a, b) return a.oid < b.oid end)
        for _, z in ipairs(list) do
            if (max == nil or n < max) and not z.dead then
                z:Kill(who)
                n = n + 1
            end
        end
        return n
    end
    local function lastLog(Q)
        local log = Q.Store.root().hordes.log
        return log[#log]
    end
    local function sum(map)
        local s = 0
        for _, v in pairs(map) do s = s + v end
        return s
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
    section("window math and weekdays", function()
        local Q = boot()
        local H = Q.Hordes
        local d = today() + 2
        local w = win("19:00", "23:00", 30)
        local ws, we = H.windowOf(w, d, TZ)
        T.check(ws == at(d, 19) and we == at(d, 23), "19:00-23:00 in the sandbox timezone")
        T.check(H.windowOf(w, d, 0) == d * DAY + 19 * HOUR, "timezone 0 is UTC")
        local wd, _, _, K = H.window(w, at(d, 18, 45), TZ)
        T.check(wd == d and K == 4, "rolls open leadMin before the window (4 hourly slots)")
        T.check(H.window(w, at(d, 18, 44), TZ) == nil, "a minute earlier: outside")
        T.check(H.window(w, at(d, 23) - 1, TZ) == d and H.window(w, at(d, 23), TZ) == nil, "the window ends at to")
        local s0, e0, r0 = H.slot(ws, we, 0, 15)
        T.check(s0 == at(d, 19) and e0 == at(d, 20) and r0 == at(d, 18, 45), "slot 0: 19:00-20:00, rolled at 18:45")
        local part = win("19:00", "21:30", 30)
        local pws, pwe = H.windowOf(part, d, TZ)
        local _, _, _, pK = H.window(part, at(d, 19), TZ)
        local s2, e2 = H.slot(pws, pwe, 2, 0)
        T.check(pK == 3 and s2 == at(d, 21) and e2 == at(d, 21, 30), "a part hour is the last slot, cut at to")
        local night = win("22:00", "02:00", 30)
        local nws, nwe = H.windowOf(night, d, TZ)
        T.check(nws == at(d, 22) and nwe == at(d + 1, 2), "to < from runs past midnight")
        T.check(H.window(night, at(d + 1, 1, 30), TZ) == d, "01:30 belongs to the window that opened the day before")
        T.check(H.window(night, at(d + 1, 2), TZ) == nil and H.window(night, at(d + 1, 21, 45), TZ) == d + 1,
            "closed at 02:00; the next one rolls from 21:45")
        local all = win("06:00", "06:00", 30)
        local aws, awe = H.windowOf(all, d, TZ)
        local _, _, _, aK = H.window(all, at(d, 12), TZ)
        T.check(awe - aws == DAY and aK == 24, "to == from: all day, 24 slots")
        T.check(H.window(all, at(d + 1, 5, 45), TZ) == d + 1 and H.window(all, at(d + 1, 5, 44), TZ) == d,
            "all day: the next day takes over lead minutes before it opens")
        T.check(H.hm("7:05") == 425 and H.hm("23:59") == 1439 and H.hm("19:0") == nil and H.hm("1900") == nil, "HH:MM parse")
        T.check(H.weekday(0) == 4 and H.weekday(4) == 1 and H.weekday(10) == 7, "1970-01-01 Thursday = 4, Monday = 1, Sunday = 7")
        local wday = H.weekday(d)
        local only = win("19:00", "23:00", 30, tostring(wday))
        T.check(H.window(only, at(d, 20), TZ) == d and H.window(only, at(d + 1, 20), TZ) == nil,
            "a window opens on its weekdays only")
        local nightOnly = win("22:00", "02:00", 30, tostring(wday))
        T.check(H.window(nightOnly, at(d + 1, 1), TZ) == d, "past midnight it still belongs to its start day")
        T.check(H.winKey(win("19:00", "23:00", 30, "135")) == "19:00-23:00-135", "winKey = from-to-days")
        -- (b) the window's own leadMin: rolls open that long before it
        local early = win("19:00", "23:00", 30, nil, { leadMin = 40 })
        T.check(H.window(early, at(d, 18, 20), TZ) == d and H.window(early, at(d, 18, 19), TZ) == nil
            and H.window(w, at(d, 18, 20), TZ) == nil, "win.leadMin 40: rolls from 18:20 (the 15 one not yet)")
    end)

    -- ===================== hourly rolls =====================
    section("hourly rolls: chance, maxPerDay, busy, downtime", function()
        local Q = boot()
        local H = Q.Hordes
        local h = Q.Store.root().hordes
        local alice = T.player{ name = "alice" }
        local d = today() + 2
        local KEY = "19:00-23:00-" .. ALL
        apply(Q, { enabled = true, windows = { win("19:00", "23:00", 100) }, maxPerDay = 2, spots = { SPOT },
            waves = { wave(4) } })
        T.now = at(d, 18, 44)
        step(Q)
        T.check(h.cur == nil and (h.roll[KEY] == nil or h.roll[KEY].day ~= keyOf(Q, d)), "before the first roll time: nothing")
        T.now = at(d, 18, 45)
        step(Q)
        local r = h.roll[KEY]
        T.check(r and r.day == keyOf(Q, d) and r.slot == 1 and h.perDay[keyOf(Q, d)] == 1, "18:45: slot 0 rolled and hit")
        local cur = h.cur
        T.check(cur ~= nil and cur.auto == true and cur.actor == "auto" and cur.startMs == at(d, 19)
            and cur.announceAt == at(d, 18, 45) and cur.expireAt == at(d, 20), "start 19:00 (lead kept), expires after waitMin")
        T.check(cur and cur.state == "announced" and cur.town == "muldraugh" and #cur.waves == 1 and cur.wave == 1,
            "announced at once, town from the spot, the waves copied")
        local soon = toasts(alice, "soon")
        T.check(#soon == 1 and soon[1].startMs == at(d, 19) and #soon[1].kinds == 2 and soon[1].size == nil
            and soon[1].waves == 1 and soon[1].name == SPOT.name, "toast soon: kinds with weight > 0 and waves, never a count")
        T.now = at(d, 19, 45)
        step(Q)
        T.check(r.slot == 2 and h.perDay[keyOf(Q, d)] == 1 and h.cur == cur and cur.state == "waiting", "a busy cur skips slot 1")
        H.stop(cur.id, "tester", T.now)
        T.now = at(d, 20, 45)
        step(Q)
        T.check(r.slot == 3 and h.perDay[keyOf(Q, d)] == 2 and h.cur ~= nil and h.cur.startMs == at(d, 21), "slot 2 hits")
        H.stop(h.cur.id, "tester", T.now)
        T.now = at(d, 21, 45)
        step(Q)
        T.check(r.slot == 4 and h.perDay[keyOf(Q, d)] == 2 and h.cur == nil, "maxPerDay 2 reached: slot 3 skipped")

        apply(Q, { windows = { win("19:00", "23:00", 0) } })
        T.now = at(d + 1, 18, 45)
        step(Q)
        r = h.roll[KEY]
        T.check(r.day == keyOf(Q, d + 1) and r.slot == 1 and (h.perDay[keyOf(Q, d + 1)] or 0) == 0 and h.cur == nil,
            "a new day resets the roll; chance 0 never hits")
        apply(Q, { windows = { win("19:00", "23:00", 30) } })
        T.randQueue = { 30 }
        T.now = at(d + 1, 19, 45)
        step(Q)
        T.check(h.roll[KEY].slot == 2 and h.cur == nil, "chance 30: a roll of 30 misses")
        T.randQueue = { 29 }
        T.now = at(d + 1, 20, 45)
        step(Q)
        T.check(h.roll[KEY].slot == 3 and h.cur ~= nil and h.cur.startMs == at(d + 1, 21), "chance 30: a roll of 29 hits")
        H.stop(h.cur.id, "tester", T.now)

        apply(Q, { windows = { win("19:00", "23:00", 100) } })
        T.now = at(d + 2, 21, 30)
        step(Q)
        T.check(h.roll[KEY].slot == 3 and h.perDay[keyOf(Q, d + 2)] == 1 and h.cur and h.cur.startMs == at(d + 2, 21, 45),
            "after downtime the ended slots are skipped; slot 2 starts at now + lead")
        H.stop(h.cur.id, "tester", T.now)
        T.now = at(d + 3, 21, 50)
        step(Q)
        T.check(h.roll[KEY].slot == 4 and h.cur and h.cur.startMs == at(d + 3, 22, 5),
            "a slot with less than the lead left is skipped; the next one starts at now + lead")
        H.stop(h.cur.id, "tester", T.now)
        local days = 0
        for _ in pairs(h.perDay) do days = days + 1 end
        T.check(days == 3 and h.perDay[keyOf(Q, d)] == nil, "perDay keeps the last 3 days")

        apply(Q, { enabled = false })
        T.now = at(d + 4, 18, 45)
        step(Q)
        T.check(h.roll[KEY].slot == 1 and h.cur == nil, "disabled: the slot passes without a horde")
        apply(Q, { enabled = true, spots = {} })
        T.now = at(d + 4, 19, 45)
        step(Q)
        T.check(h.roll[KEY].slot == 2 and h.cur == nil, "no spots: no horde")

        -- an admin moves the window start the same day: a new window key rolls from its first slot, today's count stays
        apply(Q, { spots = { SPOT }, windows = { win("21:00", "23:00", 100) }, maxPerDay = 2 })
        T.now = at(d + 4, 20, 45)
        step(Q)
        local K2 = "21:00-23:00-" .. ALL
        T.check(h.roll[KEY] == nil and h.roll[K2].slot == 1 and h.perDay[keyOf(Q, d + 4)] == 1 and h.cur ~= nil
            and h.cur.startMs == at(d + 4, 21), "a moved start rolls its first slot; the old window's roll is dropped")
        H.stop(h.cur.id, "tester", T.now)
        apply(Q, { windows = { win("21:30", "23:00", 100) }, maxPerDay = 1 })
        T.now = at(d + 4, 21, 15)
        step(Q)
        T.check(h.roll["21:30-23:00-" .. ALL].slot == 1 and h.perDay[keyOf(Q, d + 4)] == 1 and h.cur == nil,
            "moved again: today's count stays, maxPerDay 1 holds")

        -- two identical windows keep their own slots: chance 0 first no longer eats the slot of the 100 one
        apply(Q, { windows = { win("19:00", "23:00", 0), win("19:00", "23:00", 100) }, maxPerDay = 2 })
        T.now = at(d + 5, 18, 45)
        step(Q)
        T.check(h.roll[KEY].slot == 1 and h.roll[KEY .. "#2"] and h.roll[KEY .. "#2"].slot == 1 and h.cur ~= nil
            and h.cur.startMs == at(d + 5, 19), "identical windows roll apart: the second one (100%) hits")
    end)

    section("windows: chosen weekdays only, maxPerDay shared by every window", function()
        local Q = boot()
        local H = Q.Hordes
        local h = Q.Store.root().hordes
        local d = today() + 3
        local wd = H.weekday(d)
        apply(Q, { enabled = true, spots = { SPOT }, maxPerDay = 2,
            windows = { win("10:00", "12:00", 100, tostring(wd), { leadMin = 0 }),
                win("19:00", "21:00", 100, tostring(wd), { leadMin = 0 }) } })
        T.now = at(d, 10)
        step(Q)
        T.check(h.cur ~= nil and h.perDay[keyOf(Q, d)] == 1, "window A on its weekday: hit")
        H.stop(h.cur.id, "tester", T.now)
        T.now = at(d, 11)
        step(Q)
        T.check(h.cur ~= nil and h.perDay[keyOf(Q, d)] == 2, "window A again: the second of the day")
        H.stop(h.cur.id, "tester", T.now)
        T.now = at(d, 19)
        step(Q)
        T.check(h.cur == nil and h.roll["19:00-21:00-" .. wd].slot == 1, "window B: maxPerDay counts window A's hordes too")
        T.now = at(d + 1, 10)
        step(Q)
        T.now = at(d + 1, 19)
        step(Q)
        T.check(h.cur == nil and h.perDay[keyOf(Q, d + 1)] == nil, "the next day is not a chosen weekday: no roll at all")
        T.now = at(d + 1, 12)
        local r = adm(T.player{ name = "admin", admin = true }, "horde.status")
        T.check(r and r.roll.n == 0 and r.roll.max == 2 and r.roll.nextAt == at(d + 7, 10), "status: next roll a week later")
        apply(Q, { windows = { win("10:00", "12:00", 100, tostring(wd), { leadMin = 0 }),
            win("15:00", "16:00", 100, ALL, { leadMin = 0 }) } })
        r = adm(T.player{ name = "admin2", admin = true }, "horde.status")
        T.check(r.roll.nextAt == at(d + 1, 15), "status: the earliest roll over every window")
    end)

    -- ===================== presets (plan-presets-1028) =====================
    -- (a) a window playing another preset: its horde copies that preset's knobs
    section("presets: a window's horde copies its preset", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local d = today() + 2
        local hard = { name = "Hard", waves = { wave(7, 10), wave(3) }, kinds = { vanilla = 10, runner = 90 },
            points = { vanilla = 4, runner = 9 }, hp = { runner = 2.5 }, cap = 77, limitMin = 9, restSec = 11, maxAlive = 120 }
        apply(Q, { enabled = true, spots = { SPOT }, maxPerDay = 3, presets = { p2 = hard, p3 = full("Thin", { cap = 5 }) },
            windows = { win("19:00", "23:00", 100, nil, { preset = "p2" }) } })
        T.now = at(d, 18, 45)
        step(Q)
        local cur = h.cur
        T.check(cur ~= nil and cur.preset == "Hard" and #cur.waves == 2 and cur.waves[1].base == 7 and cur.waves[1].perPlayer == 10
            and cur.waves[2].base == 3 and cur.weights.vanilla == 10 and cur.weights.runner == 90 and cur.points.vanilla == 4
            and cur.points.runner == 9 and cur.hp.runner == 2.5 and cur.cap == 77 and cur.limitMin == 9 and cur.restSec == 11
            and cur.maxAlive == 120, "the window's preset p2: waves, kinds, points, hp, cap, limitMin, restSec, maxAlive copied")
        local p2 = Q.Config.get().hordes.presets.p2
        T.check(cur.waves ~= p2.waves and cur.weights ~= p2.kinds and cur.points ~= p2.points and cur.hp ~= p2.hp,
            "copies: a later settings change leaves the horde alone")
        Q.Hordes.stop(cur.id, "tester", T.now)
        apply(Q, { windows = { win("19:00", "23:00", 100, nil, { preset = "p3" }) } })
        T.now = at(d, 19, 45)
        step(Q)
        cur = h.cur
        T.check(cur ~= nil and cur.preset == "Thin" and cur.cap == 5 and cur.limitMin == 15 and cur.waves[1].base == 30
            and cur.weights.runner == 20 and next(cur.hp) == nil, "a preset without hp: health x 1 (cur.hp empty)")
        local p = Q.Hordes.presetOf(Q.Config.get().hordes, "gone")
        T.check(p.name == "" and p.cap == 500, "presetOf an id that does not exist: the default preset")
    end)

    -- (b) each window's own leadMin and waitMin: roll time, announceAt, expireAt
    section("presets: each window's warning and waiting minutes", function()
        local Q = boot()
        local h = Q.Store.root().hordes
        local admin = T.player{ name = "admin", admin = true }
        local d = today() + 2
        apply(Q, { enabled = true, spots = { SPOT }, maxPerDay = 2, windows = {
            win("10:00", "12:00", 100, nil, { leadMin = 40, waitMin = 7 }),
            win("19:00", "21:00", 100, nil, { leadMin = 5, waitMin = 90 }) } })
        T.now = at(d, 9, 19)
        step(Q)
        T.check(h.cur == nil, "window A (lead 40): nothing at 09:19")
        T.now = at(d, 9, 20)
        step(Q)
        local cur = h.cur
        T.check(cur ~= nil and cur.startMs == at(d, 10) and cur.announceAt == at(d, 9, 20) and cur.expireAt == at(d, 10, 7)
            and cur.waitMin == 7, "window A: rolled at 09:20, warned 40 minutes ahead, waits 7 minutes")
        T.now = at(d, 10, 7) - 1
        step(Q)
        T.check(cur.state == "waiting", "still waiting a minute before its expireAt")
        T.now = at(d, 10, 7)
        step(Q)
        T.check(h.cur == nil and lastLog(Q).why == "nobody", "nobody came within A's waitMin: failed nobody")
        T.now = at(d, 12, 30)
        step(Q)
        local r = adm(admin, "horde.status")
        T.check(r and r.roll.nextAt == at(d, 18, 55), "status: B's next roll is 5 minutes (its lead) before it opens")
        T.now = at(d, 18, 54)
        step(Q)
        T.check(h.cur == nil, "window B (lead 5): nothing at 18:54")
        T.now = at(d, 18, 55)
        step(Q)
        cur = h.cur
        T.check(cur ~= nil and cur.startMs == at(d, 19) and cur.announceAt == at(d, 18, 55) and cur.expireAt == at(d, 20, 30)
            and cur.waitMin == 90, "window B: rolled at 18:55, starts 19:00, waits 90 minutes")
    end)

    -- (c) horde.now { lead, wait, preset }
    section("presets: horde.now picks a preset and the waiting minutes", function()
        local Q = boot()
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        apply(Q, { spots = { SPOT }, presets = { p2 = full("Hard", { waves = { wave(2), wave(2) }, cap = 33, hp = { vanilla = 2 } }) } })
        local r = adm(admin, "horde.now", { lead = 3, wait = 5, preset = "p2" })
        local cur = root.hordes.cur
        T.check(r and r.ok and cur.preset == "Hard" and #cur.waves == 2 and cur.cap == 33 and cur.hp.vanilla == 2
            and cur.waitMin == 5 and cur.announceAt == T.now and cur.startMs == T.now + 3 * MIN
            and cur.expireAt == cur.startMs + 5 * MIN, "preset p2, lead 3, wait 5")
        adm(admin, "horde.stop", { id = cur.id })
        r = adm(admin, "horde.now", { lead = 3 })
        cur = root.hordes.cur
        T.check(r and r.ok and cur.preset == "" and cur.cap == 500 and cur.waitMin == 60 and next(cur.hp) == nil
            and cur.expireAt == cur.startMs + 60 * MIN, "without preset / wait: the default preset, 60 minutes")
        adm(admin, "horde.stop", { id = cur.id })
        r = adm(admin, "horde.now", { wait = 240 })
        T.check(r and r.ok and root.hordes.cur.waitMin == 240, "wait 240 is the top")
        adm(admin, "horde.stop", { id = root.hordes.cur.id })
        for _, args in ipairs({ { preset = "nope" }, { preset = "p3" }, { wait = 0 }, { wait = 241 }, { lead = 121, preset = "p2" } }) do
            r = adm(admin, "horde.now", args)
            T.check(r and r.code == "BAD_ARGS" and root.hordes.cur == nil,
                "horde.now refused: preset " .. tostring(args.preset) .. " wait " .. tostring(args.wait))
        end
    end)

    -- (d) the preset's hp multiplies the spawn health, capped at H.HP_MAX
    section("presets: toughness multiplies the spawn health", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        near(alice)
        T.spawnHealth = 2
        local function healths()
            local out = { vanilla = {}, runner = {} }
            for z, t in pairs(H.live) do
                if t.horde == root.hordes.cur.id then table.insert(out[t.kind], z.health) end
            end
            return out
        end
        local function all(list, v)
            for _, x in ipairs(list) do if math.abs(x - v) > 1e-9 then return false end end
            return #list > 0
        end
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 50, runner = 50 }, hp = { vanilla = 3 } })
        adm(admin, "horde.now")
        local hs = healths()
        T.check(all(hs.vanilla, 6) and all(hs.runner, 2), "vanilla x 3: 2 -> 6; runner without hp (x 1): left at 2")
        adm(admin, "horde.stop", { id = root.hordes.cur.id })
        apply(Q, { hp = { vanilla = 10, runner = 0.5 } })
        T.spawnHealth = 4
        adm(admin, "horde.now")
        hs = healths()
        T.check(all(hs.vanilla, H.HP_MAX) and H.HP_MAX == 30 and all(hs.runner, 2),
            "x 10 of 4 = 40: capped at 30 (the packet's short); x 0.5: 2")
        adm(admin, "horde.stop", { id = root.hordes.cur.id })
        apply(Q, { hp = { vanilla = 1, runner = 1 } })
        T.spawnHealth = 31.5
        adm(admin, "horde.now")
        hs = healths()
        T.check(all(hs.vanilla, 31.5) and all(hs.runner, 31.5), "x 1: the health is not touched (not even capped)")
    end)

    -- ===================== kind mix and wave size =====================
    section("kind mix by weight", function()
        local Q = boot()
        local H = Q.Hordes
        local Cat = Q.Catalog
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
        m = Cat.hordeMix({ "a", "b", "c" }, { a = 70, b = 50, c = 0 }, 12)
        T.check(#m == 2 and m[1].kind == "a" and m[1].n == 7 and m[2].n == 5, "Catalog.hordeMix: kindIds order, weights relative")
        m = Cat.hordeMix({ "a", "b", "c" }, { a = 1, b = 1, c = 1 }, 5)
        T.check(m[1].n == 2 and m[2].n == 2 and m[3].n == 1, "Catalog.hordeMix: ties by id")
    end)

    section("wave size by the players near the spot", function()
        local Q = boot()
        local Cat = Q.Catalog
        T.check(Cat.hordeWaveSize(30, 50, 1) == 30 and Cat.hordeWaveSize(30, 50, 4) == 75 and Cat.hordeWaveSize(30, 50, 0) == 30
            and Cat.hordeWaveSize(1, 0, 10) == 1 and Cat.hordeWaveSize(3, 50, 2) == 5 and Cat.hordeWaveSize(9999, 1000, 9) > 9999,
            "base + perPlayer % per extra player, rounded; no 100 cap")
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local ps = {}
        for i = 1, 5 do ps[i] = T.player{ name = "p" .. i } end
        apply(Q, { spots = { SPOT }, waves = { wave(10, 50) }, kinds = { vanilla = 100 }, maxAlive = 2000 })
        near(ps[1])
        adm(admin, "horde.now")
        T.check(root.hordes.cur.size == 10 and root.hordes.cur.left == 10, "1 player near: base 10")
        adm(admin, "horde.stop", { id = root.hordes.cur.id })
        near(ps[2], 10)
        near(ps[3], -20)
        ps[4].x, ps[4].y = SPOT.x, SPOT.y + 30
        ps[5].x, ps[5].y = SPOT.x + 5, SPOT.y
        ps[5].dead = true
        adm(admin, "horde.now")
        local sp = toasts(ps[1], "spawn")
        T.check(root.hordes.cur.size == 25 and sp[#sp].size == 25 and sp[#sp].wave == 1 and sp[#sp].waves == 1,
            "4 living players near (a dead one does not count): 10 x (1 + 0.5 x 3) = 25")
    end)

    -- ===================== exits =====================
    section("exits: ring, gap, reach, fallback", function()
        local Q = boot()
        local H = Q.Hordes
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        local cur = { x = SPOT.x, y = SPOT.y, z = 0, angle = 0 }
        near(alice)
        far(bob)
        local ex = H.exits(cur)
        T.check(#ex == 2 and ex[1].x == SPOT.x and ex[1].y == SPOT.y + 30 and ex[2].x == SPOT.x and ex[2].y == SPOT.y - 30,
            "player 30 east: north and south exits (east too close, west and diagonals out of reach)")
        -- property: random players and angles, every kept exit keeps the rules
        local seed, bad, kept, empty = 12345, 0, 0, 0
        local function rnd(n)
            seed = (seed * 1103515245 + 12345) % 2147483648
            return seed % n
        end
        for _ = 1, 200 do
            alice.x, alice.y = SPOT.x + rnd(61) - 30, SPOT.y + rnd(61) - 30
            bob.x, bob.y = SPOT.x + rnd(121) - 60, SPOT.y + rnd(121) - 60
            cur.angle = rnd(360)
            T.randQueue = {}
            for i = 1, 8 do T.randQueue[i] = rnd(11) end
            ex = H.exits(cur)
            if #ex == 0 then empty = empty + 1 end
            for _, e in ipairs(ex) do
                kept = kept + 1
                local reach = false
                for _, p in ipairs({ alice, bob }) do
                    local dx, dy = math.abs(p.x - e.x), math.abs(p.y - e.y)
                    if dx * dx + dy * dy < 25 * 25 then bad = bad + 1 end
                    if math.max(dx, dy) <= 43 then reach = true end
                end
                local r = math.sqrt((e.x - SPOT.x) ^ 2 + (e.y - SPOT.y) ^ 2)
                if not reach or r < 29 or r > 41 then bad = bad + 1 end
            end
        end
        T.check(bad == 0 and kept > 200, "200 random layouts: no exit within 25 of a player, none beyond 43 Chebyshev of all ("
            .. kept .. " kept, " .. empty .. " empty)")
        near(alice)
        far(bob)
        T.randQueue = {}
        T.square = function(x, y) if y > SPOT.y then return "water" end return nil end
        T.check(#H.exits(cur) == 0, "water and unloaded squares are no exits")
        T.square = function(x, y) if y > SPOT.y then return "solid" end return "free" end
        ex = H.exits(cur)
        T.check(#ex == 1 and ex[1].y == SPOT.y - 30, "a solid square is no exit")

        -- no exit at all: the wave spawns at the spot
        T.square = function() return nil end
        local admin = T.player{ name = "admin", admin = true }
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 } })
        adm(admin, "horde.now")
        local c = T.spawnCalls[1]
        T.check(Q.Store.root().hordes.cur.spawned == 4 and #T.spawnCalls == 1 and c.x1 == SPOT.x - 5 and c.y1 == SPOT.y - 5
            and c.n == 4, "no usable exit: spawned at the spot (11 x 11)")
        adm(admin, "horde.stop", { id = Q.Store.root().hordes.cur.id })
        T.square = nil
        T.spawnCalls = {}
        adm(admin, "horde.now")
        local ok = #T.spawnCalls == 2
        for _, call in ipairs(T.spawnCalls) do
            if call.x1 ~= SPOT.x - 5 or (call.y1 ~= SPOT.y + 25 and call.y1 ~= SPOT.y - 35) or call.n ~= 2 then ok = false end
        end
        T.check(ok, "exits in turn: 2 at each of the 2 exits")
    end)

    -- ===================== one wave, payout =====================
    section("manual horde: open, spawn at exits, kill value, capped split", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        cmd(admin, "hello")
        cmd(alice, "hello")
        cmd(bob, "hello")
        apply(Q, { spots = { SPOT }, waves = { wave(6) }, kinds = { vanilla = 50, runner = 50 },
            points = { vanilla = 1, runner = 3 }, cap = 9 })
        local accA, accB = Q.Store.account("alice", false), Q.Store.account("bob", false)
        local r = adm(admin, "horde.now")
        local cur = root.hordes.cur
        T.check(r and r.ok and r.id == 1 and cur and cur.id == 1 and cur.auto == false and cur.actor == "admin",
            "horde.now plans one at once")
        T.check(cur and cur.state == "waiting" and next(root.hordes.perDay) == nil, "manual: waiting now, not counted in perDay")
        local open = toasts(alice, "open")
        T.check(#open == 1 and #open[1].kinds == 2 and open[1].waves == 1 and #toasts(alice, "soon") == 0, "toast open (no soon)")
        local hist = Q.Config.historyRows()
        T.check(hist[#hist].summary == "horde.now 1 Gas Station" and hist[#hist].undoable == false, "history row horde.now <id> <name>")
        r = adm(admin, "cfg.undo", { historyId = hist[#hist].id })
        T.check(r and r.code == "BAD_CONFIG", "the history row cannot be undone")
        r = adm(admin, "horde.now")
        T.check(r and r.code == "HORDE_BUSY", "a second horde.now: HORDE_BUSY")

        step(Q)
        T.check(cur.state == "waiting" and #T.spawnCalls == 0, "nobody within 30 tiles: no spawn")
        near(alice, 31)
        step(Q)
        T.check(cur.state == "waiting" and #T.spawnCalls == 0, "31 tiles away: no spawn")
        near(alice, 30)
        step(Q)
        T.check(cur.state == "active" and cur.size == 6 and cur.spawned == 6 and cur.left == 6 and cur.firstSpawnAt == T.now
            and cur.endsAt == T.now + 15 * MIN, "30 tiles: the wave starts, timer runs")
        local zs = hordeZombies()
        local runners, vanillas = {}, {}
        for _, z in ipairs(zs) do
            if z.sprinter then runners[#runners + 1] = z else vanillas[#vanillas + 1] = z end
        end
        T.check(#runners == 3 and #vanillas == 3 and T.spawnCalls[1].outfit == nil and T.spawnCalls[1].female == 50,
            "runner kind: doSprinter on its 3")
        local sp = toasts(bob, "spawn")
        T.check(#sp == 1 and sp[1].size == 6 and sp[1].wave == 1 and sp[1].waves == 1 and sp[1].limitMin == 15
            and sp[1].pool == nil and sp[1].split == nil, "toast spawn: wave, waves, size, endsAt, limitMin")
        -- the harness sandbox has no ZombieLore: the sandbox default, normal hearing -> LURE_REACH (48)
        T.check(#T.sounds == 1 and T.sounds[1].x == SPOT.x and T.sounds[1].y == SPOT.y and T.sounds[1].radius == H.LURE_REACH
            and T.sounds[1].volume == H.LURE_REACH, "the lure sounds at the spot (unknown hearing: the sandbox default)")
        local climate = { rain = 0, fog = 0 }
        getClimateManager = function()
            return { getRainIntensity = function() return climate.rain end, getFogIntensity = function() return climate.fog end }
        end
        SandboxVars.ZombieLore = { Hearing = 2 }
        T.check(H.lureRadius() == H.LURE_REACH and H.lureRadius() == 48 and H.exitMax() == H.RING_MAX,
            "normal hearing, clear weather: 48, exits out to 40 (a scatter corner 7.07 past the exit still hears)")
        climate.rain = 0.25
        T.check(H.lureRadius() == H.LURE_MAX and H.exitMax() == 36, "light rain (x0.9175): capped at 49, exits pulled in to 36")
        climate.rain, climate.fog = 1, 1
        local wave = { x = SPOT.x, y = SPOT.y, z = 0, angle = 0 }
        T.check(H.lureRadius() == H.LURE_MAX and H.exitMax() == 19 and #H.exits(wave) == 0,
            "heavy rain and fog (x0.57): 49 carries 27, under RING_MIN + spread: no exits, the wave comes at the spot")
        SandboxVars.ZombieLore.Hearing = 1
        T.check(H.lureRadius() == H.LURE_REACH and H.exitMax() == H.RING_MAX, "pinpoint hearing: never under LURE_REACH")
        climate.rain, climate.fog = 0, 0
        -- 4 rolls 1-3 and 5 rolls 2-3 per zombie (IsoZombie.java:3904-3907): sized for the poor ones (r2)
        for _, lore in ipairs({ 3, 4, 5 }) do
            SandboxVars.ZombieLore.Hearing = lore
            T.check(H.lureRadius() == H.LURE_MAX and H.exitMax() == 14 and #H.exits(wave) == 0,
                "hearing " .. lore .. " (poor, or random with poor ones): 49 carries 22, the wave comes at the spot")
        end
        getClimateManager, SandboxVars.ZombieLore = nil, nil

        runners[1]:Kill(alice)
        runners[2]:Kill(alice)
        runners[3]:Kill(alice)
        vanillas[1]:Kill(bob)
        vanillas[2]:Kill(bob)
        T.fire("OnZombieDead", runners[1])
        T.check(cur.killed == 5 and cur.totalKilled == 5 and cur.kills.alice == 3 and cur.kills.bob == 2 and cur.left == 1,
            "kills counted per player; a second OnZombieDead for the same zombie ignored")
        T.check(cur.waveGot.alice == 9 and cur.waveGot.bob == 2 and next(cur.got) == nil, "kill value per kind (runner 3, vanilla 1)")
        T.fire("OnZombieDead", T.zombie{ attacker = alice })
        T.check(cur.killed == 5 and cur.kills.alice == 3, "a zombie of no horde is ignored")
        T.check((accA.total["zombie.kills"] or 0) == 4, "horde kills (3) and the stray one still count as ordinary kills")
        step(Q)
        T.check(root.hordes.cur == cur and cur.left == 1, "one alive: still active")
        T.advance(H.LURE_MS)
        step(Q)
        T.check(#T.sounds == 2, "the lure repeats every LURE_MS while zombies are alive")
        vanillas[3]:Kill(nil)
        T.check(cur.killed == 6 and cur.kills.alice == 3, "a death without attacker clears it, no kill")
        local awards = spyAwards(Q)
        step(Q)
        T.check(root.hordes.cur == nil, "all gone with a player near: success")
        -- value 11 > cap 9: alice 9 x 9 / 11 = 7.36, bob 9 x 2 / 11 = 1.64 -> 7 + 1, remainder 1 to bob (.64 > .36)
        T.check(awards.horde.alice == 7 and awards.horde.bob == 2 and awards.ref == "horde:1", "cap 9 split by kill value: 7 + 2")
        local pa, pb = toasts(alice, "hordePaid"), toasts(bob, "hordePaid")
        T.check(#pa == 1 and pa[1].pts == 7 and pa[1].kills == 3 and pa[1].capped == true and pa[1].pct == nil and #pb == 1
            and pb[1].pts == 2, "personal toasts: points, kills, capped")
        local win1 = toasts(admin, "win")
        T.check(#win1 == 1 and win1[1].n == 2 and win1[1].spawned == 6 and win1[1].killed == 6 and win1[1].pool == 9
            and win1[1].capped == true and win1[1].waves == 1, "toast win")
        T.check(accA.total["horde.wins"] == 1 and accB.total["horde.wins"] == 1 and accA.achv.h_horde == 1
            and accA.titles.h_horde == true, "horde.wins + 1 each; hidden h_horde and its title unlock")
        T.check((Q.Store.account("admin", false).total["horde.wins"] or 0) == 0, "no kill, no participation")
        local e = lastLog(Q)
        T.check(e.state == "success" and e.paid.alice == 7 and e.paid.bob == 2 and e.pool == 9 and e.capped == true
            and e.spawned == 6 and e.killed == 6 and e.waves == 1 and e.cleared == 1 and e.auto == false and e.endedAt == T.now,
            "archived in root.hordes.log")
        local logged = false
        for _, b in ipairs(Q.EventLog.buffer) do
            if string.find(b.line, '"k":"horde"', 1, true) and string.find(b.line, '"state":"success"', 1, true) then logged = true end
        end
        T.check(logged, "event log kind horde")
        T.check(next(H.live) == nil, "no zombie left in H.live")
    end)

    section("payout: exact largest remainder, no value, zero points", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, cap = 10 })
        local function finishWith(got, kills, cap)
            adm(admin, "horde.now")
            local cur = root.hordes.cur
            cur.got, cur.kills, cur.cap = got, kills, cap or cur.cap
            H.finish("success", nil, T.now)
            return lastLog(Q)
        end
        local e = finishWith({ alice = 7, bob = 5, carol = 3 }, { alice = 7, bob = 5, carol = 3 })
        T.check(e.paid.alice == 5 and e.paid.bob == 3 and e.paid.carol == 2 and sum(e.paid) == 10 and e.pool == 10 and e.capped,
            "15 over cap 10: floors 4 + 3 + 2, the 1 left to the largest fraction")
        e = finishWith({ a = 1, b = 1, c = 1 }, { a = 1, b = 1, c = 1 }, 2)
        T.check(sum(e.paid) == 2 and e.paid.a == 1 and e.paid.b == 1 and e.paid.c == 0, "equal fractions: ties by name")
        e = finishWith({ alice = 3, bob = 1 }, { alice = 3, bob = 1 }, 500)
        T.check(e.paid.alice == 3 and e.paid.bob == 1 and e.pool == 4 and e.capped == false, "under the cap: the value as it is")
        local all = 0
        local got, kills = {}, {}
        for i = 1, 7 do
            got["u" .. i] = i * 13
            kills["u" .. i] = i
        end
        e = finishWith(got, kills, 97)
        for _, v in pairs(e.paid) do all = all + v end
        T.check(all == 97, "7 players over cap 97: the total is exactly the cap")
        T.clearOutbox()
        local w0 = Q.Store.account("alice", true).total["horde.wins"] or 0
        e = finishWith({}, { alice = 2 })
        T.check(next(e.paid) == nil and e.pool == 0 and #toasts(alice, "hordePaid") == 0
            and Q.Store.account("alice", true).total["horde.wins"] == w0 + 1, "no kill value (0-point kinds): a win, nobody paid")
    end)

    -- ===================== multi-wave =====================
    section("waves: rest, the next wave, per-wave waiting, failure pays the cleared waves", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        cmd(alice, "hello")
        apply(Q, { spots = { SPOT }, waves = { wave(4), wave(2), wave(3) }, kinds = { vanilla = 100 },
            points = { vanilla = 5 }, restSec = 30, cap = 500 })
        near(alice)
        adm(admin, "horde.now", { wait = 10 })
        local cur = root.hordes.cur
        T.check(cur.state == "active" and cur.wave == 1 and cur.size == 4, "wave 1 of 3")
        killAlive(Q, cur.id, alice)
        step(Q)
        local rest = toasts(alice, "rest")
        T.check(cur.state == "rest" and cur.cleared == 1 and cur.got.alice == 20 and cur.nextAt == T.now + 30000 and #rest == 1
            and rest[1].wave == 1 and rest[1].waves == 3 and rest[1].nextAt == cur.nextAt, "wave 1 cleared: rest 30 s, toast rest")
        local v = H.stateHordes(nil, "alice", T.now).cur
        T.check(v.state == "rest" and v.nextAt == cur.nextAt and v.wave == 1 and v.waves == 3 and v.got == 20 and v.mine == 4,
            "the view in rest: nextAt, wave, my kills and payable points")
        T.now = cur.nextAt - 1
        step(Q)
        T.check(cur.state == "rest", "rest until nextAt")
        far(alice)
        T.now = cur.nextAt
        step(Q)
        T.check(cur.state == "waiting" and cur.wave == 2 and cur.expireAt == T.now + 10 * MIN, "nextAt: wave 2 waits waitMin")
        near(alice)
        T.advance(MIN)
        step(Q)
        T.check(cur.state == "active" and cur.wave == 2 and cur.size == 2 and cur.spawned == 2 and #toasts(alice, "spawn") == 2,
            "a player near: wave 2 starts")
        killAlive(Q, cur.id, alice)
        step(Q)
        T.check(cur.state == "rest" and cur.cleared == 2 and cur.got.alice == 30, "wave 2 cleared")
        T.now = cur.nextAt
        step(Q)
        T.check(cur.state == "active" and cur.wave == 3, "a player already near: wave 3 starts at nextAt")
        killAlive(Q, cur.id, alice, 1)
        local awards = spyAwards(Q)
        T.now = cur.endsAt
        step(Q)
        local e = lastLog(Q)
        local fail = toasts(alice, "fail")
        T.check(root.hordes.cur == nil and e.state == "failed" and e.why == "time" and e.cleared == 2 and e.waves == 3
            and e.pool == 30 and e.spawned == 9 and e.killed == 9 - 2, "wave 3 timed out: failed, 2 cleared waves")
        T.check(awards.horde.alice == 30, "only the cleared waves pay (wave 3's kill is not paid)")
        local paidT = toasts(alice, "hordePaid")
        T.check(#paidT == 1 and paidT[1].pts == 30 and e.kills.alice >= 2 and paidT[1].kills == e.kills.alice - 1,
            "the paid toast counts the cleared waves' kills, not wave 3's (the record keeps them all)")
        T.check(#fail == 1 and fail[1].why == "time" and fail[1].wave == 3 and fail[1].waves == 3 and fail[1].cleared == 2
            and fail[1].pool == 30 and fail[1].capped == false, "toast fail: why, wave, waves, cleared, pool")
        T.check(Q.Store.account("alice", false).total["horde.wins"] == nil, "a fail is no win")

        -- nobody comes for wave 2 by its waiting deadline
        T.clearOutbox()
        adm(admin, "horde.now")
        cur = root.hordes.cur
        killAlive(Q, cur.id, alice)
        step(Q)
        far(alice)
        T.now = cur.nextAt
        step(Q)
        T.now = cur.expireAt - 1
        step(Q)
        T.check(cur.state == "waiting" and cur.wave == 2, "wave 2 waiting until its deadline")
        T.now = cur.expireAt
        step(Q)
        e = lastLog(Q)
        T.check(e.why == "nobody" and e.cleared == 1 and e.pool == 20 and e.paid.alice == 20, "nobody by the deadline: failed, wave 1 paid")

        -- the last wave cleared: success with every wave paid
        apply(Q, { waves = { wave(2), wave(2) }, restSec = 0 })
        T.clearOutbox()
        near(alice)
        adm(admin, "horde.now")
        cur = root.hordes.cur
        killAlive(Q, cur.id, alice)
        step(Q)
        T.check(cur.state == "rest", "restSec 0: still one tick of rest")
        step(Q)
        killAlive(Q, cur.id, alice)
        step(Q)
        e = lastLog(Q)
        local w = toasts(alice, "win")
        T.check(e.state == "success" and e.cleared == 2 and e.pool == 20 and #w == 1 and w[1].waves == 2 and w[1].spawned == 4,
            "the last wave cleared: success, every wave paid")
    end)

    -- ===================== maxAlive, refill, tries =====================
    section("maxAlive batches, refill as they die, the tries rule", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        apply(Q, { spots = { SPOT }, waves = { wave(25) }, kinds = { vanilla = 100 }, maxAlive = 10 })
        near(alice)
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        local over = aliveOf(Q, cur.id) > 10
        T.check(aliveOf(Q, cur.id) == 10 and cur.queued == 15 and cur.left == 25 and cur.spawned == 10, "10 alive, 15 queued")
        killAlive(Q, cur.id, alice, 3)
        T.check(cur.left == 22, "a kill: left - 1")
        step(Q)
        over = over or aliveOf(Q, cur.id) > 10
        T.check(aliveOf(Q, cur.id) == 10 and cur.queued == 12 and cur.left == 22, "3 died: 3 more from the exits")
        local steps = 0
        while root.hordes.cur == cur and steps < 20 do
            killAlive(Q, cur.id, alice, 4)
            step(Q)
            over = over or aliveOf(Q, cur.id) > 10
            steps = steps + 1
        end
        T.check(not over and lastLog(Q).state == "success" and lastLog(Q).spawned == 25 and lastLog(Q).killed == 25,
            "maxAlive never exceeded; all 25 came and the wave cleared")

        apply(Q, { waves = { wave(60) }, maxAlive = 100 })
        adm(admin, "horde.now")
        cur = root.hordes.cur
        T.check(cur.spawned == H.BATCH and cur.queued == 20, "at most BATCH (40) a tick")
        step(Q)
        T.check(cur.spawned == 60 and cur.queued == 0, "the rest the next tick")
        adm(admin, "horde.stop", { id = cur.id })

        -- tries: nothing spawns at all
        apply(Q, { waves = { wave(4) } })
        T.spawnCap = 0
        adm(admin, "horde.now")
        cur = root.hordes.cur
        for _ = 1, 8 do step(Q) end
        T.check(root.hordes.cur == cur and cur.tries == 9 and cur.state == "active" and cur.spawned == 0, "9 empty batches: still on")
        step(Q)
        T.check(root.hordes.cur == nil and lastLog(Q).why == "spawn", "10 empty batches with nothing spawned: failed spawn")

        -- tries: part of the wave came, then the squares give nothing: the rest is dropped
        T.spawnCap = nil
        apply(Q, { waves = { wave(15) }, maxAlive = 10 })
        adm(admin, "horde.now")
        cur = root.hordes.cur
        T.spawnCap = 0
        killAlive(Q, cur.id, alice, 5)
        for _ = 1, 9 do step(Q) end
        T.check(cur.queued == 5 and cur.tries == 9, "9 empty refills: the queue waits")
        step(Q)
        T.check(root.hordes.cur == cur and cur.queued == 0 and cur.left == 5 and cur.size == 15, "the 10th: the rest is dropped")
        killAlive(Q, cur.id, alice)
        step(Q)
        T.check(lastLog(Q).state == "success" and lastLog(Q).spawned == 10, "the ones that came cleared: success")

        T.spawnCap, T.staleOwner, T.staleUseless = 2, alice, true
        apply(Q, { waves = { wave(4) } })
        adm(admin, "horde.now")
        T.check(root.hordes.cur.spawned == 4, "unloaded squares: 2 per exit call")
        local owned, useless = 0, 0
        for z, t in pairs(H.live) do
            if t.horde == root.hordes.cur.id and (z.owner ~= nil or z.ownerPlayer ~= nil) then owned = owned + 1 end
            if t.horde == root.hordes.cur.id and z.useless then useless = useless + 1 end
        end
        T.check(owned == 0, "reused zombie objects: the network owner of their last life is cleared (quest-hz-1026j)")
        T.check(useless == 0, "and useless from their last life too (built-in kinds; a useless zombie ignores the lure)")
        T.sounds = {}
        killAlive(Q, root.hordes.cur.id, alice)
        far(alice)
        T.advance(H.LURE_MS)
        step(Q)
        T.check(#T.sounds == 0 and root.hordes.cur ~= nil, "no zombie alive: no lure; nobody near: not cleared yet")
        near(alice, 45)
        step(Q)
        T.check(root.hordes.cur == nil and lastLog(Q).state == "success",
            "a player 45 tiles out (chasing at the exits, inside CLEAR_RANGE 50, outside RANGE 30): cleared")
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
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 }, points = { vanilla = 5 } })
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
            cur.totalSpawned, cur.kills = 10, kills
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
        local cur = H.plan(Q.Config.get().hordes, T.now + 2 * HOUR, nil, win("19:00", "23:00", 0))
        H.stop(cur.id, "admin", T.now)
        T.check(lastLog(Q).announced == false, "a cancel before the warning stays secret")

        T.clearOutbox()
        cmd(alice, "records")
        local rec = T.lastOf(alice, "records")
        local rows = rec and rec.hordes or {}
        T.check(#rows == 4 and rows[1].state == "failed" and rows[1].why == "time" and rows[1].mine == 1 and rows[1].got == 0
            and rows[4].state == "success" and rows[4].mine == 3 and rows[4].got == 15 and rows[4].spawned == 4
            and rows[4].waves == 1 and rows[4].cleared == 1, "records: the announced results, newest first, with my kills and points")
        T.check(rows[1].kills == nil and rows[1].paid == nil, "records rows carry only my share, not everyone's")
        cmd(bob, "records")
        local rb = T.lastOf(bob, "records").hordes
        T.check(rb[1].mine == 3 and rb[2].mine == 0 and rb[2].got == 0, "the same rows with bob's share")
        for _ = 1, H.RECENT + 2 do finishWith({ alice = 1 }) end
        cmd(alice, "records")
        T.check(#T.lastOf(alice, "records").hordes == H.RECENT, "at most H.RECENT rows")
        T.check(H.stateHordes(nil, "bob", T.now).on == true, "results to list: the page is in the nav")
    end)

    -- ===================== 2026-10-29: joined, deaths, death toasts =====================
    -- position in p's outbox of the first horde toast ev (nil when none)
    local function toastAt(p, ev)
        for i, t in ipairs(T.sentTo(p, "toast")) do
            if t.kind == "horde" and t.ev == ev then return i end
        end
        return nil
    end
    local function encoded(Q, v) return Q.Util.encode(v) or "" end
    local function die(p, dx)
        near(p, dx)
        p.dead = true
        T.fire("OnCharacterDeath", p)
    end
    local function revive(p)
        p.dead = false
        far(p)
    end

    section("deaths: near a spawned horde, once per account, at most DEATHS_MAX, toasts merged over 2 s", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        local carol = T.player{ name = "carol" }
        local dave = T.player{ name = "dave" }
        local cow = T.player{ name = "cow" }
        function cow:isAnimal() return true end
        function cow:getAttackedBy() return nil end   -- Trackers.onCharacterDeath asks an animal for its hunter
        for _, p in ipairs({ admin, alice, bob, carol, dave, cow }) do cmd(p, "hello") end
        cmd(carol, "anon", { on = true })
        apply(Q, { spots = { SPOT }, waves = { wave(2), wave(2) }, kinds = { vanilla = 100 } })
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        die(bob, 10)
        T.check(cur.state == "waiting" and #cur.deaths == 0, "a death before the first spawn is not listed")
        revive(bob)
        near(alice)
        step(Q)
        T.check(cur.state == "active" and H.stateHordes(nil, "bob", T.now).cur.joined == 0, "spawned, no kill yet: 0 joined")
        local zs = hordeZombies()
        zs[1]:Kill(alice)
        T.check(H.stateHordes(nil, "bob", T.now).cur.joined == 1, "a kill: 1 joined (players with 1+ kill)")

        T.clearOutbox()
        die(dave, 51)
        die(cow, 0)
        T.check(#cur.deaths == 0, "a death 51 tiles away, or of an animal, is not listed")
        local t0 = T.now
        die(bob, 50)
        die(bob, 50)
        T.advance(1000)
        die(carol, 0)
        T.check(#cur.deaths == 2 and cur.deaths[1].u == "bob" and cur.deaths[1].wave == 1 and cur.deaths[1].at == t0
            and cur.deaths[2].u == "carol", "50 tiles away: listed once per account, with wave and time")
        T.now = t0 + H.DEATH_MS - 1
        step(Q)
        T.check(#toasts(alice, "death") == 0, "no death toast before DEATH_MS")
        T.now = t0 + H.DEATH_MS
        step(Q)
        local dt = toasts(alice, "death")
        T.check(#dt == 1 and #dt[1].names == 1 and dt[1].names[1] == "bob" and dt[1].anon == 1 and dt[1].wave == 1
            and dt[1].waves == 2 and dt[1].id == cur.id and dt[1].name == SPOT.name, "one toast for both: bob by name, carol anonymous")
        T.check(not string.find(encoded(Q, dt[1]), "carol", 1, true), "the anonymous player's name is nowhere in the toast")
        step(Q)
        T.check(#toasts(alice, "death") == 1, "sent once")

        zs[2]:Kill(alice)
        step(Q)
        T.check(cur.state == "rest", "wave 1 cleared: rest")
        revive(dave)
        die(dave, 0)
        T.check(#cur.deaths == 3 and cur.deaths[3].u == "dave", "a death in the rest counts")
        for i = #cur.deaths + 1, H.DEATHS_MAX do cur.deaths[i] = { u = "x" .. i, wave = 1, at = T.now } end
        die(admin, 0)
        T.check(#cur.deaths == H.DEATHS_MAX, "at most DEATHS_MAX listed")

        H.stop(cur.id, "admin", T.now)   -- dave's toast still waiting: it goes out before the fail toast
        local dI, fI = toastAt(alice, "death"), toastAt(alice, "fail")
        dt = toasts(alice, "death")
        T.check(#dt == 2 and dt[2].names[1] == "dave" and dI ~= nil and fI ~= nil and toastAt(alice, "death") < fI
            and T.sentTo(alice, "toast")[fI - 1].ev == "death", "the waiting deaths go out at the end, before the result")
        T.check(#lastLog(Q).deaths == H.DEATHS_MAX and lastLog(Q).deaths[1].u == "bob", "the log keeps the deaths")
        revive(bob)
        die(bob, 0)
        T.advance(H.DEATH_MS)
        step(Q)
        T.check(root.hordes.cur == nil and #toasts(alice, "death") == 2, "after the end: no death toast")
    end)

    section("result: MVP toast, log fields, rows and anonymity, who gets it, hordeResult", function()
        local Q = boot()
        local H = Q.Hordes
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        local bob = T.player{ name = "bob" }
        local carol = T.player{ name = "carol" }
        local dave = T.player{ name = "dave" }
        local erin = T.player{ name = "erin", offline = true, x = SPOT.x, y = SPOT.y }
        for _, p in ipairs({ admin, alice, bob, carol, dave }) do cmd(p, "hello") end
        cmd(carol, "anon", { on = true })
        apply(Q, { spots = { SPOT }, waves = { wave(6) }, kinds = { vanilla = 100 }, points = { vanilla = 5 } })
        near(alice)
        adm(admin, "horde.now")
        local zs = hordeZombies()
        zs[1]:Kill(alice)
        zs[2]:Kill(alice)
        zs[3]:Kill(carol)
        zs[4]:Kill(carol)
        zs[5]:Kill(bob)
        die(bob, 20)
        zs[6]:Kill(nil)
        near(admin, 50)
        near(dave, -50)
        far(carol)
        T.clearOutbox()
        step(Q)
        local e = lastLog(Q)
        T.check(root.hordes.cur == nil and e.state == "success" and e.joined == 3 and #e.mvp == 2 and e.mvp[1] == "alice"
            and e.mvp[2] == "carol" and #e.deaths == 1 and e.deaths[1].u == "bob", "log: joined, MVP (a tie) and deaths")
        local mv = toasts(dave, "mvp")
        T.check(#mv == 1 and #mv[1].names == 1 and mv[1].names[1] == "alice" and mv[1].anon == 1 and mv[1].kills == 2
            and mv[1].id == e.id and toastAt(dave, "win") < toastAt(dave, "mvp"), "toast mvp after win: alice, 1 anonymous, 2 kills")
        T.check(not string.find(encoded(Q, mv[1]), "carol", 1, true), "the anonymous MVP's name is nowhere in the toast")

        local pa = T.sentTo(alice, "hordeResult")
        local s = pa[1] or { rows = {}, deaths = {} }
        local r1, r2, r3 = s.rows[1] or {}, s.rows[2] or {}, s.rows[3] or {}
        T.check(#pa == 1 and s.push == true and s.id == e.id and s.state == "success" and s.joined == 3 and s.spawnAt == e.spawnAt
            and s.endedAt == e.endedAt and s.pool == e.pool and s.capped == false and s.waves == 1 and s.cleared == 1
            and s.killed == 6 and s.spawned == 6 and s.name == SPOT.name, "pushed result: the horde's numbers, push = true")
        T.check(#s.rows == 3 and r1.r == 1 and r1.n == "alice" and r1.k == 2 and r1.p == e.paid.alice and r1.mvp == true
            and r2.r == 2 and r2.anon == true and r2.n == nil and r2.a == nil and r2.k == 2 and r2.mvp == true
            and r3.r == 3 and r3.n == "bob" and r3.k == 1 and r3.dead == true and r3.mvp == nil and r1.dead == nil,
            "rows by kills, a tie by name; MVP and died marks; the anonymous one has no name")
        T.check(s.me == 1 and #s.deaths == 1 and s.deaths[1].n == "bob" and s.deaths[1].wave == 1, "me and the deaths")
        T.check(not string.find(encoded(Q, s), "carol", 1, true), "a player's result never names the anonymous one")
        local sa = T.sentTo(admin, "hordeResult")[1] or { rows = {} }
        T.check(sa.push == true and sa.rows[2] and sa.rows[2].a == "carol" and sa.rows[2].n == nil and sa.me == nil,
            "an admin 50 tiles away gets it with the anonymous name in a")
        local sd = T.sentTo(dave, "hordeResult")
        T.check(#sd == 1 and sd[1].me == nil and #sd[1].rows == 3, "50 tiles away without a kill: pushed, me nil")
        T.check(#T.sentTo(bob, "hordeResult") == 0 and #T.sentTo(carol, "hordeResult") == 0
            and #T.sentTo(erin, "hordeResult") == 0, "not pushed to the dead, the far or the offline")

        local rb = H.recent("bob", 1)[1] or {}
        e.joined = nil
        local old = H.recent("bob", 1)[1] or {}
        e.joined = 3
        T.check(rb.joined == 3 and old.joined == 3, "records rows carry joined (older logs: the accounts in kills)")

        T.clearOutbox()
        T.check(cmd(carol, "hordeResult", { id = e.id }) == nil, "hordeResult found: no result reply")
        local q = T.lastOf(carol, "hordeResult") or { rows = {} }
        T.check(q.push == nil and q.me == 2 and q.rows[2].anon == true and q.rows[2].n == nil and q.rows[2].a == nil,
            "asked: no push flag, my own anonymous row")
        local r = cmd(alice, "hordeResult", { id = 999 })
        T.check(r and r.ok == false and r.code == "NOT_FOUND" and T.lastOf(alice, "hordeResult") == nil, "unknown id: NOT_FOUND")

        local cfg = Q.Config.get().hordes
        local cur = H.plan(cfg, T.now + 2 * HOUR, nil, win("19:00", "23:00", 0))
        H.stop(cur.id, "admin", T.now)
        r = cmd(alice, "hordeResult", { id = cur.id })
        T.check(r and r.code == "NOT_FOUND", "a secret cancel: NOT_FOUND")
        adm(admin, "horde.now", { lead = 5 })
        H.stop(root.hordes.cur.id, "admin", T.now)
        T.check(lastLog(Q).state == "cancelled" and #T.sentTo(alice, "hordeResult") == 0, "a cancel is not pushed")

        -- RESULT_ROWS: the top 100, my row appended with its rank
        local kills = { tb = 500, ta = 500, zero = 0 }
        for i = 1, 105 do kills[string.format("u%03d", i)] = 200 - i end
        local big = { id = 50, kills = kills, paid = {}, deaths = {}, mvp = {} }
        local b1 = H.result(big, "u105", false)
        T.check(b1.joined == 107 and #b1.rows == 101 and b1.rows[1].n == "ta" and b1.rows[2].n == "tb"
            and b1.rows[100].r == 100 and b1.rows[101].r == 107 and b1.rows[101].n == "u105" and b1.me == 101,
            "at most RESULT_ROWS; my row past them appended with its rank")
        local b2 = H.result(big, "u010", false)
        local b3 = H.result(big, "zero", false)
        T.check(#b2.rows == 100 and b2.me == 12 and #b3.rows == 100 and b3.me == nil, "within them: me = my row; no kill: me nil")
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
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 } })
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
            "2 minutes before: a personal reminder to the player within 30 tiles only")
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
    section("failures: time, nobody, virtualised zombies", function()
        local Q = boot()
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        cmd(alice, "hello")
        local accA = Q.Store.account("alice", false)
        apply(Q, { spots = { SPOT }, waves = { wave(4) }, kinds = { vanilla = 100 } })

        near(alice)
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        local zs = hordeZombies()
        local cleared = { zs[2].oid, zs[3].oid, zs[4].oid }
        zs[1]:Kill(alice)
        local p0 = accA.points.total
        T.now = cur.endsAt - 1
        step(Q)
        T.check(root.hordes.cur == cur, "before endsAt: still active")
        T.now = cur.endsAt
        step(Q)
        local e = lastLog(Q)
        T.check(root.hordes.cur == nil and e.state == "failed" and e.why == "time" and e.killed == 1 and e.pool == 0, "endsAt: failed time")
        T.check(zs[2].oid == -1 and not zs[2].onSquare and zs[4].oid == -1 and zs[2].dead == false,
            "the rest removed through H.clearZombie (removeFromWorld + removeFromSquare)")
        T.check(accA.points.total == p0 and (accA.total["horde.wins"] or 0) == 0, "time out in wave 1: no reward, no win")
        local fail = toasts(alice, "fail")
        T.check(#fail == 1 and fail[1].why == "time" and fail[1].wave == 1 and fail[1].cleared == 0, "toast fail with why and wave")
        local hc, hcA = T.sentTo(alice, "hordeClear"), T.sentTo(admin, "hordeClear")
        T.check(#hc == 1 and sortedIds(hc[1].ids) == sortedIds(cleared),
            "hordeClear once to a player near them with the cleared online ids (not the killed one)")
        T.check(#hcA == 0, "hordeClear not sent to a player 600 tiles away (a far client may reuse those online ids)")

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
        T.check(#T.sentTo(alice, "hordeClear") == 1, "nothing cleared (virtualised, reused, id -1): no hordeClear")

        T.clearOutbox()
        adm(admin, "horde.now")
        cur = root.hordes.cur
        T.now = cur.expireAt - 1
        step(Q)
        T.check(root.hordes.cur == cur and cur.state == "waiting", "before expireAt: waiting")
        T.now = cur.expireAt
        step(Q)
        T.check(lastLog(Q).state == "failed" and lastLog(Q).why == "nobody" and toasts(alice, "fail")[1].why == "nobody",
            "nobody within 30 tiles before expireAt: failed nobody")
    end)

    -- quest-hsp-pre-1027a (single player, before the fix): every zombie had online id -1, so each wave "cleared" on
    -- the next tick with 0 kills and the horde won paying nothing
    section("single player: no online ids; the cell's zombie list tracks them", function()
        local Q = boot({ sp = true })
        local H, root = Q.Hordes, Q.Store.root()
        local solo = T.player{ name = "solo" }
        cmd(solo, "hello")
        apply(Q, { spots = { SPOT }, waves = { wave(3), wave(2) }, kinds = { vanilla = 100 }, points = { vanilla = 2 },
            restSec = 5 })
        near(solo)
        local stray = T.zombie{ cell = true }   -- a wild zombie of the same cell: online id -1 too
        local function mine(id)
            local out = {}
            for z, t in pairs(H.live) do if t.horde == id then out[#out + 1] = z end end
            return out
        end
        local r = adm(solo, "horde.now")
        local cur = root.hordes.cur
        local zs = mine(cur and cur.id)
        T.check(r and r.ok and cur.state == "active" and #zs == 3 and zs[1].oid == -1 and zs[1].inWorld == false,
            "SP spawn: 3 tracked, online id -1, not on their squares yet")
        T.advance(1000)
        step(Q)
        T.check(root.hordes.cur == cur and cur.state == "active" and cur.left == 3 and #mine(cur.id) == 3,
            "next tick: all 3 still count (no online id is not gone)")
        zs[1]:Kill(solo)
        zs[2]:Kill(solo)
        step(Q)
        T.check(cur.state == "active" and cur.killed == 2 and cur.left == 1 and cur.kills.solo == 2 and cur.waveGot.solo == 4,
            "kills count; one standing keeps the wave active")
        zs[3]:Kill(solo)
        step(Q)
        T.check(cur.state == "rest" and cur.cleared == 1 and cur.got.solo == 6, "the last kill clears wave 1")
        T.advance(5000)
        step(Q)
        zs = mine(cur.id)
        T.check(cur.state == "active" and cur.wave == 2 and #zs == 2, "wave 2 after the rest")
        local awards = spyAwards(Q)
        zs[1]:Kill(solo)
        step(Q)
        T.check(root.hordes.cur == cur and cur.left == 1, "wave 2: one left")
        zs[2]:Kill(solo)
        step(Q)
        local e = lastLog(Q)
        T.check(root.hordes.cur == nil and e.state == "success" and e.killed == 5 and awards.horde.solo == 10,
            "success after the last kill pays 5 x 2")

        adm(solo, "horde.now")
        cur = root.hordes.cur
        zs = mine(cur.id)
        zs[1]:removeFromWorld()   -- unloaded: out of the cell's list
        step(Q)
        T.check(cur.left == 2 and #mine(cur.id) == 2, "removed from the world: gone, not alive")
        -- unloaded and handed out again as a wild zombie before the next tick (r2): OnZombieCreate drops it
        T.reuseZombie(zs[2])
        step(Q)
        T.check(cur.left == 1 and #mine(cur.id) == 1 and H.live[zs[2]] == nil, "reused within a tick: no longer the horde's")
        zs[2]:Kill(solo)
        step(Q)
        T.check(cur.state == "active" and cur.killed == 0 and cur.kills.solo == nil, "killing the reused zombie is no horde kill")
        T.now = cur.endsAt
        step(Q)
        T.check(lastLog(Q).why == "time" and zs[3].onSquare == false and zs[2].onSquare == true,
            "time out clears the rest, not the reused zombie")
        T.check(#T.sentTo(solo, "hordeClear") == 0 and getCell():getZombieList():contains(stray),
            "no hordeClear in SP (every id is -1: the handler would remove every zombie of the cell)")
    end)

    -- r2: finish drops cur first, so an error after the payout does not finish (and pay) it again on the next tick
    section("finish: an error after the payout does not pay twice", function()
        local Q = boot()
        local root = Q.Store.root()
        local admin = T.player{ name = "admin", admin = true }
        local alice = T.player{ name = "alice" }
        cmd(alice, "hello")
        apply(Q, { spots = { SPOT }, waves = { wave(2) }, kinds = { vanilla = 100 }, points = { vanilla = 3 } })
        near(alice)
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        local awards = spyAwards(Q)
        killAlive(Q, cur.id, alice)
        local write, calls = Q.EventLog.write, 0
        Q.EventLog.write = function(kind, ...)
            if kind == "horde" then
                calls = calls + 1
                if calls == 1 then error("disk full") end
            end
            return write(kind, ...)
        end
        local ok1 = pcall(step, Q)
        local ok2 = pcall(step, Q)
        Q.EventLog.write = write
        T.check(not ok1 and ok2 and root.hordes.cur == nil and calls == 1 and awards.horde.alice == 6,
            "the error stops finish after the payout; the next tick has nothing to finish (6 paid once)")
    end)

    section("client: hordeClear removes this client's copies of the cleared zombies", function()
        local Q = T.bootClient()
        local a = T.zombie{ oid = 501, cell = true }
        local b = T.zombie{ oid = 502, cell = true }
        local other = T.zombie{ oid = 503, cell = true }
        Q.Client.receive("hordeClear", { ids = { 502, 501, 777 } })
        T.check(#T.cellZombies == 1 and T.cellZombies[1] == other and other.unregistered == nil and other.onSquare,
            "only the listed ids leave the cell's zombie list; an unknown id is ignored")
        T.check(a.unregistered and not a.onSquare and not a.inWorld and b.unregistered and not b.onSquare,
            "removed like ZombieDeleteOnClient: emitter unregistered, removeFromWorld, removeFromSquare")
        Q.Client.receive("hordeClear", { ids = "bad" })
        Q.Client.receive("hordeClear", {})
        T.check(#T.cellZombies == 1 and not T.printed("receive hordeClear"), "a payload without an id list does nothing")
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
        cmd(alice, "hello")
        apply(Q, { spots = { SPOT }, waves = { wave(4), wave(4) }, kinds = { vanilla = 100 }, points = { vanilla = 2 } })
        local cfg = Q.Config.get().hordes

        local cur = H.plan(cfg, T.now + 2 * HOUR, nil, win("19:00", "23:00", 0))
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

        cur = H.plan(cfg, T.now + 10 * MIN, nil, win("19:00", "23:00", 0))
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
        local stopIds = { zs[2].oid, zs[3].oid, zs[4].oid }
        adm(admin, "horde.stop", { id = cur.id })
        T.check(lastLog(Q).why == "admin" and lastLog(Q).killed == 1 and not zs[2].inWorld and not zs[4].inWorld,
            "active -> failed admin, the rest cleared")
        local hc = T.sentTo(alice, "hordeClear")
        T.check(#hc == 1 and sortedIds(hc[1].ids) == sortedIds(stopIds), "admin stop while active: hordeClear with the cleared ids")
        T.check(H.stateHordes(nil, "alice", T.now).last.got == nil, "no cleared wave: no reward on a stop")

        -- stop in rest: failed admin, wave 1 paid
        adm(admin, "horde.now")
        cur = root.hordes.cur
        killAlive(Q, cur.id, alice)
        step(Q)
        T.check(cur.state == "rest", "in rest")
        adm(admin, "horde.stop", { id = cur.id })
        T.check(lastLog(Q).state == "failed" and lastLog(Q).why == "admin" and lastLog(Q).paid.alice == 8,
            "rest -> failed admin, the cleared wave paid")

        -- a restart in rest carries on
        adm(admin, "horde.now")
        cur = root.hordes.cur
        killAlive(Q, cur.id, alice)
        step(Q)
        local id, nextAt = cur.id, cur.nextAt
        Q = boot({ keepGmd = true, keepFiles = true })
        H, root = Q.Hordes, Q.Store.root()
        cur = root.hordes.cur
        T.check(cur ~= nil and cur.id == id and cur.state == "rest", "a restart in rest: the horde carries on")
        alice = T.player{ name = "alice" }
        cmd(alice, "hello")
        near(alice)
        T.now = nextAt
        step(Q)
        T.check(cur.state == "active" and cur.wave == 2, "after the rest wave 2 starts")

        -- a restart while active: failed restart, the cleared waves paid
        zs = hordeZombies()
        Q = boot({ keepGmd = true, keepFiles = true })
        root = Q.Store.root()
        local e = root.hordes.log[#root.hordes.log]
        T.check(root.hordes.cur == nil and e.id == id and e.state == "failed" and e.why == "restart" and e.cleared == 1
            and e.paid.alice == 8, "a restart fails the active horde (restart); wave 1 is paid")
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
        apply(Q, { enabled = true, windows = { win("19:00", "23:00", 0) }, spots = { SPOT }, waves = { wave(4) },
            kinds = { vanilla = 75, runner = 25 }, points = { vanilla = 5, runner = 5 } })
        local cfg = Q.Config.get().hordes
        local d = today() + 2
        T.now = at(d, 12)
        step(Q)
        r = adm(admin, "horde.status")
        T.check(r and r.ok and r.cur == nil and r.roll.max == 1 and r.roll.n == 0 and r.roll.enabled == true
            and r.roll.nextAt == at(d, 18, 45) and r.roll.day == nil and r.roll.slot == nil, "status: next roll at 18:45")
        T.check(#r.kinds == 2 and r.kinds[1].id == "vanilla" and r.kinds[1].builtin == true and r.kinds[2].id == "runner",
            "status: built-in kinds")
        T.check(r.cull == nil, "status.cull: nil when the sandbox value cannot be read")
        SandboxVars.ZombieConfig = { ZombiesCountBeforeDelete = 500 }
        r = adm(admin, "horde.status")
        T.check(r.cull == 500, "status.cull: SandboxVars.ZombieConfig.ZombiesCountBeforeDelete")
        SandboxVars.ZombieConfig = { ZombiesCountBeforeDelete = "x" }
        T.check(H.cull() == nil, "a non-number: nil")

        local cur = H.plan(cfg, T.now + HOUR, nil, win("19:00", "23:00", 0))
        r = adm(admin, "horde.status")
        T.check(r.cur and r.cur.state == "planned" and #r.cur.waves == 1 and r.cur.weights.vanilla == 75 and r.cur.kills ~= nil,
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
        T.check(v.size == 0 and v.mix == nil and v.pool == nil and v.perZombie == nil and v.split == nil and v.mine == 0
            and v.got == 0 and v.wave == 1 and v.waves == 1 and #v.kinds == 2 and v.x == SPOT.x and v.startMs == cur.startMs,
            "the view: spot, kinds and waves, no count before the spawn")
        T.check(Q.Sync.state("bob", Q.Store.account("bob", false)).hordes.cur.id == cur.id, "full state carries it")

        near(alice)
        T.now = cur.startMs
        step(Q)
        killAlive(Q, cur.id, alice)
        v = H.stateHordes(nil, "alice", T.now).cur
        T.check(v.size == 4 and v.mine == 4 and v.left == 0 and v.killed == 4 and v.got == 0, "after the spawn: size, my kills, left")
        step(Q)
        local ended = T.now
        local last = H.stateHordes(nil, "alice", T.now).last
        T.check(H.stateHordes(nil, "alice", T.now).cur == nil and last and last.state == "success" and last.got == 20
            and last.mine == 4 and last.pool == 20 and last.capped == false and last.waves == 1 and last.cleared == 1,
            "the last result: state, waves, my kills, my points")
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
        local function wins(n, extra)
            local out = {}
            for i = 1, n do out[i] = win("19:00", "23:00", 30) end
            if extra then for k, x in pairs(extra) do out[1][k] = x end end
            return out
        end
        local function waves(n, extra)
            local out = {}
            for i = 1, n do out[i] = wave(10, 50) end
            if extra then for k, x in pairs(extra) do out[1][k] = x end end
            return out
        end
        local P = "presets.default."
        local good = {
            { "enabled", true }, { "windows", wins(1) }, { "windows", wins(8) }, { "windows", wins(1, { days = "7" }) },
            { "windows", wins(1, { days = "7654321", from = "7:05", to = "00:00", chance = 0 }) },
            { "windows", wins(1, { chance = 100 }) }, { "windows", wins(1, { leadMin = 0, waitMin = 1 }) },
            { "windows", wins(1, { leadMin = 120, waitMin = 240, preset = "p2" }) }, { "windows", wins(1, { preset = "night_1" }) },
            { "presets.night_1.cap", 5 }, { "presets.Night-2", full("N") }, { "presets", { night_1 = full("N") } },
            { "maxPerDay", 1 }, { "maxPerDay", 24 }, { P .. "waves", waves(1) }, { P .. "waves", waves(10) },
            { P .. "waves", waves(1, { base = 1, perPlayer = 0 }) }, { P .. "waves", waves(1, { base = 9999, perPlayer = 1000 }) },
            { P .. "restSec", 0 }, { P .. "restSec", 600 }, { P .. "maxAlive", 10 }, { P .. "maxAlive", 2000 },
            { P .. "kinds.vanilla", 0 }, { P .. "kinds.runner", 100 }, { P .. "kinds", { vanilla = 10, ["m:fast"] = 5 } },
            { P .. "kinds.m:fast", 7 }, { P .. "points.vanilla", 0 }, { P .. "points.runner", 1000 }, { P .. "points.m:fast", 3 },
            { P .. "points", { vanilla = 1 } }, { P .. "limitMin", 1 }, { P .. "limitMin", 120 }, { P .. "cap", 1 },
            { P .. "cap", 1000000 }, { P .. "hp.runner", 0.1 }, { P .. "hp.m:fast", 10 }, { P .. "hp", { vanilla = 2.5 } },
            { P .. "hp", {} }, { P .. "name", "" }, { P .. "name", string.rep("x", 32) }, { "presets.p2.name", "Hard" },
            { "presets.p2.hp.runner", 3 }, { "presets.p2", Q.Catalog.DEFAULTS.hordes.presets.default },
            { "presets.p2", { limitMin = 5 } }, { "spots", {} },
            { "spots", spots(32) }, { "spots", spots(1, { z = -32 }) }, { "spots", spots(1, { z = 31, x = 100000 }) },
        }
        for _, g in ipairs(good) do T.check(ok(g[1], g[2]), "valid hordes." .. g[1]) end
        local bad = {
            { "enabled", "yes" }, { "windows", {} }, { "windows", wins(9) }, { "windows", wins(1, { days = "" }) },
            { "windows", wins(1, { days = "8" }) }, { "windows", wins(1, { days = "0" }) }, { "windows", wins(1, { days = "11" }) },
            { "windows", wins(1, { days = "12345671" }) }, { "windows", wins(1, { days = 1 }) },
            { "windows", wins(1, { from = "24:00" }) }, { "windows", wins(1, { to = "19:60" }) }, { "windows", wins(1, { to = "1900" }) },
            { "windows", wins(1, { chance = 101 }) }, { "windows", wins(1, { chance = -1 }) }, { "windows", wins(1, { chance = 5.5 }) },
            { "windows", wins(1, { extra = 1 }) }, { "windows", { { from = "19:00", to = "23:00", chance = 30 } } },
            { "windows", { { days = ALL, from = "19:00", to = "23:00", chance = 30 } } },
            { "windows", wins(1, { leadMin = 121 }) }, { "windows", wins(1, { leadMin = -1 }) }, { "windows", wins(1, { waitMin = 0 }) },
            { "windows", wins(1, { waitMin = 241 }) }, { "windows", wins(1, { waitMin = 1.5 }) }, { "windows", wins(1, { preset = "" }) },
            { "windows", wins(1, { preset = "a b" }) }, { "windows", wins(1, { preset = 2 }) },
            { "windows", wins(1, { preset = string.rep("p", 65) }) }, { "windows", wins(1, { preset = "m:x-1" }) },
            { "windows", wins(1, { preset = "2" }) }, { "windows", wins(1, { preset = "1234567890123456" }) },
            { "windows", wins(1, { preset = "_a" }) },
            { "windows", { 1 } }, { "windows", { a = win("19:00", "23:00", 30) } }, { "windows.1.from", "20:00" },
            { "maxPerDay", 0 }, { "maxPerDay", 25 },
            { P .. "waves", {} }, { P .. "waves", waves(11) }, { P .. "waves", waves(1, { base = 0 }) },
            { P .. "waves", waves(1, { base = 10000 }) }, { P .. "waves", waves(1, { perPlayer = -1 }) },
            { P .. "waves", waves(1, { perPlayer = 1001 }) }, { P .. "waves", waves(1, { base = 2.5 }) },
            { P .. "waves", waves(1, { extra = 1 }) }, { P .. "waves", { { base = 5 } } }, { P .. "waves.1.base", 5 },
            { P .. "restSec", -1 }, { P .. "restSec", 601 }, { P .. "maxAlive", 9 }, { P .. "maxAlive", 2001 },
            { P .. "kinds.vanilla", 101 }, { P .. "kinds", { ["a b"] = 1 } }, { P .. "kinds", { vanilla = -1 } },
            { P .. "points.vanilla", 1001 }, { P .. "points.vanilla", -1 }, { P .. "points", { ["a b"] = 1 } },
            { P .. "points.runner", 1.5 }, { P .. "limitMin", 0 }, { P .. "limitMin", 121 }, { P .. "cap", 0 },
            { P .. "cap", 1000001 }, { P .. "hp.runner", 0.09 }, { P .. "hp.runner", 10.1 }, { P .. "hp.runner", "2" },
            { P .. "hp", { ["a b"] = 1 } }, { P .. "name", string.rep("x", 33) }, { P .. "name", "a\nb" }, { P .. "name", 1 },
            { P .. "foo", 1 }, { "presets.a b.cap", 1 }, { "presets.p2", { foo = 1 } }, { "presets.p2", 5 },
            -- preset ids: a letter first (JSON decodes "2" to the number 2), no ":"
            { "presets.2.cap", 5 }, { "presets.1234567890123456.cap", 5 }, { "presets.1a.cap", 5 }, { "presets.a:b.cap", 5 },
            { "presets", { [2] = full("N") } }, { "presets", { ["2"] = full("N") } }, { "presets", { [1234567890123456] = full("N") } },
            { "spots", spots(33) }, { "spots", spots(1, { z = 32 }) }, { "spots", spots(1, { z = -33 }) },
            { "spots", spots(1, { x = 100001 }) }, { "spots", spots(1, { name = "" }) }, { "spots", spots(1, { name = "a\nb" }) },
            { "spots", spots(1, { town = "x" }) }, { "spots", { 1 } }, { "foo", 1 },
            -- removed 2026-10-27
            { "from", "19:00" }, { "to", "23:00" }, { "chance", 30 }, { "count", { 20, 40 } }, { "perZombie", 5 },
            { "split", "share" },
            -- moved into presets / windows 2026-10-28
            { "leadMin", 15 }, { "waitMin", 60 }, { "waves", waves(1) }, { "kinds.vanilla", 1 }, { "points.vanilla", 1 },
            { "cap", 500 }, { "limitMin", 15 }, { "restSec", 30 }, { "maxAlive", 200 }, { "hp.runner", 2 },
        }
        for _, b in ipairs(bad) do T.check(not ok(b[1], b[2]), "invalid hordes." .. b[1] .. " = " .. tostring(b[2])) end
        T.check(not Cf.validate({ op = "set", path = "hordes", value = { enabled = true, foo = 1 } }), "unknown key inside hordes")
        T.check(not Cf.validate({ op = "set", path = "hordes", value = { enabled = true, count = { 1, 2 } } }),
            "a removed key inside hordes")
        T.check(Cf.validate({ op = "set", path = "hordes", value = Q.Catalog.DEFAULTS.hordes }), "the defaults validate as a whole group")
    end)

    -- (e) after the changes: every window's preset exists, at most MAX_PRESETS presets
    section("Config hordes: window presets exist, at most 8 presets", function()
        local Q = boot()
        local Cf = Q.Config
        local function set(path, value) return { op = "set", path = "hordes." .. path, value = value } end
        local ok, code, detail = Cf.apply({ set("windows", { win("19:00", "23:00", 30), win("8:00", "9:00", 30, nil,
            { preset = "p3" }) }) }, "test", "tester")
        T.check(not ok and code == "BAD_CONFIG" and detail.why == "preset" and detail.path == "hordes.windows.2.preset"
            and Cf.get().hordes.windows[1].preset == "default" and #Cf.get().hordes.windows == 1,
            "a window playing a preset that does not exist: refused on its path, nothing applied")
        ok = Cf.apply({ set("presets.p3", full("Hard")), set("windows", { win("8:00", "9:00", 30, nil, { preset = "p3" }) }) },
            "test", "tester")
        T.check(ok and Cf.get().hordes.windows[1].preset == "p3", "with the preset in the same apply: fine")
        ok, code, detail = Cf.apply({ { op = "del", path = "hordes.presets.p3" } }, "test", "tester")
        T.check(not ok and detail.why == "preset" and detail.path == "hordes.windows.1.preset" and Cf.get().hordes.presets.p3 ~= nil,
            "deleting a preset a window still plays: refused")
        ok = Cf.apply({ set("windows", { win("8:00", "9:00", 30) }), { op = "del", path = "hordes.presets.p3" } }, "test", "tester")
        T.check(ok and Cf.get().hordes.presets.p3 == nil, "moved to default first: the preset goes")
        Cf.apply({ set("presets.default.cap", 9) }, "test", "tester")
        ok = Cf.apply({ { op = "del", path = "hordes.presets.default" } }, "test", "tester")
        T.check(ok and Cf.get().hordes.presets.default.cap == 500 and Cf.get().hordes.windows[1].preset == "default",
            "a del of default only brings its defaults back")
        local changes = {}
        for i = 2, 8 do changes[#changes + 1] = set("presets.p" .. i, full("P" .. i)) end
        T.check((Cf.apply(changes, "test", "tester")), "8 presets with the default one: fine")
        ok, code, detail = Cf.apply({ set("presets.p9", full("P9")) }, "test", "tester")
        T.check(not ok and code == "BAD_CONFIG" and detail.why == "presets" and Cf.get().hordes.presets.p9 == nil,
            "a 9th preset: refused")
        local okP, codeP, detailP = Cf.preview({ set("presets.p9", full("P9")) })
        T.check(not okP and codeP == "BAD_CONFIG" and detailP.why == "presets", "the preview says so too")
    end)

    -- review r1: every preset but default is whole and has a name of its own; the server refuses the rest
    section("Config hordes: whole presets, a name, no two alike", function()
        local Q = boot()
        local Cf = Q.Config
        local function set(path, value) return { op = "set", path = "hordes." .. path, value = value } end
        local function refused(changes, why, path, what)
            local ok, code, detail = Cf.apply(changes, "test", "tester")
            local d = type(detail) == "table" and detail or {}
            T.check(not ok and code == "BAD_CONFIG" and d.why == why and d.path == path, what .. ": " .. why .. " on " .. path
                .. " (got " .. tostring(ok) .. " " .. tostring(d.why) .. " " .. tostring(d.path) .. ")")
        end
        T.check((Cf.apply({ set("presets.p2", full("Hard")) }, "test", "tester")), "a whole preset applies")
        refused({ { op = "del", path = "hordes.presets.p2.kinds" } }, "presetPart", "hordes.presets.p2.kinds",
            "the panel deletes p2's kinds")
        T.check(Cf.get().hordes.presets.p2.kinds ~= nil, "and p2 keeps them")
        refused({ set("presets.p3.cap", 5) }, "presetPart", "hordes.presets.p3.waves", "a new preset with one knob (first missing)")
        local noName = full("x")
        noName.name = nil
        refused({ set("presets.p3", noName) }, "presetName", "hordes.presets.p3.name", "a preset without a name")
        refused({ set("presets.p3", full("  ")) }, "presetName", "hordes.presets.p3.name", "a blank name")
        refused({ set("presets.p3", full("Hard")) }, "presetSame", "hordes.presets.p3.name", "a second Hard")
        refused({ set("presets.p1", full("Hard")) }, "presetSame", "hordes.presets.p2.name", "by id order: the later id is named")
        refused({ set("presets.default.name", "Hard") }, "presetSame", "hordes.presets.p2.name", "the default one's name counts too")
        T.check((Cf.apply({ set("presets.p3", full("hard")), set("presets.default.name", "Std") }, "test", "tester")),
            "names that differ (case too) are fine; default may have one")
        T.check((Cf.apply({ set("presets.p2.hp", {}) }, "test", "tester")) and Cf.apply({ { op = "del", path = "hordes.presets.p2.hp" } },
            "test", "tester"), "hp may be left out")
        -- the last key of a map leaves it empty, not gone (review r2): a preset of pack kinds only can drop its kind
        local packOnly = full("Pack")
        packOnly.kinds, packOnly.points = { ["m:brute"] = 10 }, { ["m:brute"] = 5 }
        T.check((Cf.apply({ set("presets.p4", packOnly) }, "test", "tester")), "a preset of pack kinds only applies")
        local okDel = Cf.apply({ { op = "del", path = "hordes.presets.p4.kinds.m:brute" },
            { op = "del", path = "hordes.presets.p4.points.m:brute" } }, "test", "tester")
        local p4 = Cf.get().hordes.presets.p4
        T.check(okDel and type(p4.kinds) == "table" and Q.Store.isEmpty(p4.kinds) and type(p4.points) == "table"
            and Q.Store.isEmpty(p4.points), "removing its only kind leaves kinds and points empty, not gone")
    end)

    -- ===================== migration =====================
    section("migration: old overrides, old config.json, undo of removed paths", function()
        local Q = boot()
        local Cf = Q.Config
        local DIR = "MinidoracatQuest/servertest/"
        local function fileTree(name)
            local f = T.files[DIR .. name]
            return f and Q.Util.decode(table.concat(f.lines, "\n"), 1000000) or nil
        end
        local function prodTree()
            return { hordes = { count = { 100, 100 }, perZombie = 1, kinds = { vanilla = 70, runner = 30, ["m:x"] = 10 },
                leadMin = 25, maxPerDay = 2, enabled = true, spots = { { name = "A", x = 1, y = 2, z = 0 } } } }
        end
        local t = prodTree()
        T.check(Cf.migrate(t) == true, "the production tree changes")
        local h = t.hordes
        local dp = h.presets and h.presets.default or {}
        T.check(dp.waves and #dp.waves == 1 and dp.waves[1].base == 100 and dp.waves[1].perPlayer == 0 and h.count == nil
            and h.waves == nil, "count { 100, 100 } -> one wave of 100, perPlayer 0, in the default preset")
        T.check(dp.points and dp.points.vanilla == 1 and dp.points.runner == 1 and dp.points["m:x"] == 1 and h.perZombie == nil
            and h.points == nil, "perZombie 1 -> points 1 for vanilla, runner and every kind")
        T.check(dp.kinds and dp.kinds.vanilla == 70 and h.kinds == nil and h.maxPerDay == 2 and h.enabled == true,
            "kinds move to the default preset; the rest unchanged")
        T.check(h.windows and #h.windows == 1 and h.windows[1].from == "19:00" and h.windows[1].preset == "default"
            and h.windows[1].leadMin == 25 and h.windows[1].waitMin == 60 and h.leadMin == nil,
            "leadMin without window keys: the default window, with the old lead")
        T.check(Cf.validate({ op = "set", path = "hordes", value = h }), "the migrated group validates")
        T.check(Cf.migrate(t) == false, "a second run changes nothing")
        t = { hordes = { from = "20:00", chance = 50, count = { 20, 41 }, split = "each", waves = { wave(7) },
            perZombie = 3, points = { vanilla = 9 } } }
        Cf.migrate(t)
        h = t.hordes
        T.check(#h.windows == 1 and h.windows[1].days == ALL and h.windows[1].from == "20:00" and h.windows[1].to == "23:00"
            and h.windows[1].chance == 50 and h.from == nil and h.chance == nil, "from / chance -> the first window (to default)")
        T.check(h.presets.default.waves[1].base == 7 and h.count[2] == 41 and h.presets.default.points.vanilla == 9
            and h.presets.default.points.runner == nil and h.perZombie == 3 and h.split == nil,
            "waves / points already there stay (moved to the preset); the old keys next to them stay too")
        T.check(not Cf.validate({ op = "set", path = "hordes", value = h }),
            "so an edit in the old shape fails validation on its path instead of being dropped")
        t = { hordes = { cap = 100, presets = { default = { cap = 200 } } } }
        T.check(Cf.migrate(t) == false and t.hordes.cap == 100 and t.hordes.presets.default.cap == 200
            and not Cf.validate({ op = "set", path = "hordes", value = t.hordes }),
            "a top-level knob next to the preset's own: stays, validation names it")
        t = { hordes = { count = { 1, 2 } } }
        Cf.migrate(t)
        T.check(t.hordes.presets.default.waves[1].base == 2, "the average rounds half up")

        -- (f) the two old shapes in full: 0.2.0 (production) and the 0.3.0 in development (top-level knobs)
        t = { hordes = { enabled = true, from = "20:00", to = "23:30", chance = 40, count = { 20, 40 }, perZombie = 2,
            split = "share", kinds = { vanilla = 60, runner = 40 }, leadMin = 25, waitMin = 45, limitMin = 20, maxPerDay = 2,
            spots = { { name = "A", x = 1, y = 2, z = 0 } } } }
        T.check(Cf.migrate(t) == true, "0.2.0: changed")
        h = t.hordes
        local w = h.windows and h.windows[1] or {}
        dp = h.presets and h.presets.default or {}
        T.check(#h.windows == 1 and w.days == ALL and w.from == "20:00" and w.to == "23:30" and w.chance == 40
            and w.preset == "default" and w.leadMin == 25 and w.waitMin == 45, "0.2.0: one window with the old lead and wait")
        T.check(dp.waves[1].base == 30 and dp.points.vanilla == 2 and dp.points.runner == 2 and dp.kinds.runner == 40
            and dp.limitMin == 20, "0.2.0: waves, points, kinds and limitMin in the default preset")
        T.check(h.from == nil and h.count == nil and h.perZombie == nil and h.split == nil and h.kinds == nil and h.leadMin == nil
            and h.waitMin == nil and h.limitMin == nil and h.maxPerDay == 2, "0.2.0: no old key left")
        T.check(Cf.validate({ op = "set", path = "hordes", value = h }), "0.2.0: the result validates")
        local function oldWin(from, to, chance, days) return { days = days or ALL, from = from, to = to, chance = chance } end
        t = { hordes = { enabled = true, windows = { oldWin("19:00", "21:00", 50), oldWin("6:00", "8:00", 20, "67") },
            maxPerDay = 3, waves = { wave(10, 20), wave(5) }, kinds = { runner = 50 }, points = { vanilla = 3 }, cap = 300,
            limitMin = 10, restSec = 10, maxAlive = 150, leadMin = 5, waitMin = 30, spots = { { name = "A", x = 1, y = 2, z = 0 } } } }
        T.check(Cf.migrate(t) == true, "0.3.0 in development: changed")
        h = t.hordes
        dp = h.presets and h.presets.default or {}
        T.check(h.windows[1].preset == "default" and h.windows[1].leadMin == 5 and h.windows[1].waitMin == 30
            and h.windows[2].preset == "default" and h.windows[2].leadMin == 5 and h.windows[2].waitMin == 30
            and h.windows[2].days == "67" and h.leadMin == nil and h.waitMin == nil, "0.3.0: every window gets the lead and wait")
        T.check(#dp.waves == 2 and dp.waves[1].perPlayer == 20 and dp.kinds.runner == 50 and dp.points.vanilla == 3 and dp.cap == 300
            and dp.limitMin == 10 and dp.restSec == 10 and dp.maxAlive == 150 and h.waves == nil and h.cap == nil
            and h.restSec == nil and h.maxAlive == nil, "0.3.0: every knob in the default preset")
        T.check(Cf.validate({ op = "set", path = "hordes", value = h }), "0.3.0: the result validates")
        T.check(Cf.migrate(t) == false, "0.3.0: a second run changes nothing")
        t = { hordes = { windows = { oldWin("19:00", "21:00", 50) } } }
        T.check(Cf.migrate(t) == true and t.hordes.windows[1].leadMin == 15 and t.hordes.windows[1].waitMin == 60
            and t.hordes.windows[1].preset == "default", "windows without a top-level lead / wait: the old defaults 15 / 60")
        T.check(Cf.migrate({ daily = {} }) == false and Cf.migrate({ hordes = { enabled = true } }) == false and Cf.migrate(nil) == false,
            "nothing old: false")
        t = { hordes = { perZombie = "0", count = { 40, 20 }, from = "25:00" } }
        T.check(Cf.migrate(t) == false and t.hordes.perZombie == "0" and t.hordes.points == nil and t.hordes.count[1] == 40
            and t.hordes.waves == nil and t.hordes.from == "25:00" and t.hordes.windows == nil,
            "old values the old validation refused stay (no silent new default)")
        T.check(not Cf.validate({ op = "set", path = "hordes", value = t.hordes }), "so the group fails validation")
        -- r2: false is a value (not a missing key), and count must be the old two-item array
        t = { hordes = { from = false, chance = false } }
        T.check(Cf.migrate(t) == false and t.hordes.from == false and t.hordes.chance == false and t.hordes.windows == nil,
            "from / chance = false stay: no default for a key that is there")
        t = { hordes = { count = { 30, 50, extra = 1 } } }
        T.check(Cf.migrate(t) == false and t.hordes.count.extra == 1 and t.hordes.waves == nil,
            "a count with a key besides 1 and 2 stays (the old isArray check refused it)")

        -- (a) the stored overrides at boot
        Q.Store.root().config.overrides.hordes = prodTree().hordes
        T.files[DIR .. "config.json"] = nil
        Q = boot({ keepGmd = true })
        Cf = Q.Config
        local hh = Cf.get().hordes
        T.check(hh.presets.default.waves[1].base == 100 and hh.presets.default.points.vanilla == 1 and hh.count == nil
            and hh.perZombie == nil and hh.leadMin == nil and hh.windows[1].from == "19:00" and hh.windows[1].leadMin == 25
            and Q.Store.root().config.overrides.hordes.count == nil and Q.Store.root().config.overrides.hordes.leadMin == nil,
            "stored old overrides: migrated at boot")
        local mf = fileTree("config.json")
        T.check(mf and mf.hordes.presets.default.waves[1].base == 100 and mf.hordes.count == nil and mf.hordes.leadMin == nil
            and mf.hordes.windows[1].leadMin == 25, "and written to config.json in the new shape")

        -- (b) an old config.json tree
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "count": [ 30, 50 ], "perZombie": 2, "split": "each", '
            .. '"from": "18:00", "to": "22:00", "chance": 40, "spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ] } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        hh = Cf.get().hordes
        T.check(Cf.file.status.ok == true and def(Q).waves[1].base == 40 and def(Q).points.runner == 2
            and hh.windows[1].from == "18:00" and hh.windows[1].chance == 40 and hh.windows[1].leadMin == 15
            and hh.spots[1].name == "Lot" and hh.split == nil, "an old config.json applies, migrated")
        mf = fileTree("config.json")
        T.check(mf and mf.hordes.count == nil and mf.hordes.from == nil and mf.hordes.windows[1].to == "22:00"
            and mf.hordes.presets.default.waves[1].base == 40 and mf.hordes.waves == nil, "config.json rewritten in the new shape")
        local before = Q.Store.root().config.rev
        T.advance(Cf.POLL_MS)
        T.tick(1)
        T.check(Q.Store.root().config.rev == before, "the rewritten file is not applied again")

        -- (c) a bad old value in config.json: the file is refused and kept, the settings stay
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "perZombie": "5", "count": [ 30, 50 ] } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        mf = fileTree("config.json")
        T.check(Cf.file.status.ok == false and mf.hordes.perZombie == "5" and mf.hordes.count ~= nil
            and def(Q).points.runner == 2 and def(Q).waves[1].base == 40,
            "a bad old perZombie: config.json refused and not rewritten, the applied settings unchanged")

        -- (d) an explicit false in an old config.json: refused, not filled with the default
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "chance": false } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        mf = fileTree("config.json")
        T.check(Cf.file.status.ok == false and string.find(tostring(Cf.file.status.path), "chance", 1, true) ~= nil
            and mf.hordes.chance == false and mf.hordes.windows == nil and Cf.get().hordes.windows[1].chance == 40,
            "chance = false: config.json refused on hordes.chance and not rewritten, the settings unchanged")

        -- undo of a history entry with removed paths
        local admin = T.player{ name = "admin", admin = true }
        local id1 = Cf.addHistory("old", "old count", { { path = "hordes.count", before = { 20, 40 }, after = { 5, 5 } } }, true)
        local id2 = Cf.addHistory("old", "old group", { { path = "hordes", before = { enabled = true, count = { 1, 2 } },
            after = { enabled = false } } }, true)
        local r1 = adm(admin, "cfg.undo", { historyId = id1 })
        local r2 = adm(admin, "cfg.undo", { historyId = id2 })
        T.check(r1 and r1.code == "BAD_CONFIG" and r2 and r2.code == "BAD_CONFIG" and Cf.get().hordes.count == nil
            and def(Q).waves[1].base == 40, "undo refuses removed paths and old values; nothing written")
        apply(Q, { cap = 77 })
        local hist = Cf.historyRows()
        local r3 = adm(admin, "cfg.undo", { historyId = hist[#hist].id })
        T.check(r3 and r3.ok and def(Q).cap == 500, "a valid undo still works")

        -- (f) a config.json of the 0.3.0 in development: applies, migrated and rewritten
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "windows": [ { "days": "1234567", "from": "18:00", '
            .. '"to": "22:00", "chance": 40 } ], "waves": [ { "base": 12, "perPlayer": 0 } ], "cap": 90, "leadMin": 7, '
            .. '"waitMin": 20, "spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ] } }' } }
        T.advance(Cf.POLL_MS)
        T.tick(1)
        hh = Cf.get().hordes
        mf = fileTree("config.json")
        T.check(Cf.file.status.ok == true and def(Q).waves[1].base == 12 and def(Q).cap == 90 and hh.windows[1].leadMin == 7
            and hh.windows[1].waitMin == 20 and hh.windows[1].preset == "default", "a 0.3.0 config.json applies, migrated")
        T.check(mf and mf.hordes.cap == nil and mf.hordes.leadMin == nil and mf.hordes.presets.default.cap == 90
            and mf.hordes.windows[1].waitMin == 20, "and is rewritten in the new shape")

        -- review r1: a partial preset in config.json is filled from the default preset and written back whole
        local function put(json)
            T.files[DIR .. "config.json"] = { lines = { json } }
            T.advance(Cf.POLL_MS)
            T.tick(1)
            return table.concat(T.files[DIR .. "config.json"].lines, "\n")
        end
        local SPOTS = '"spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ]'
        put('{ "hordes": { ' .. SPOTS .. ', "presets": { "p2": { "name": "Hard", "cap": 70 } }, "windows": [ { "days": "1234567", '
            .. '"from": "18:00", "to": "22:00", "chance": 40, "preset": "p2", "leadMin": 5, "waitMin": 9 } ] } }')
        local p2 = Cf.get().hordes.presets.p2
        mf = fileTree("config.json")
        T.check(Cf.file.status.ok == true and p2 and p2.cap == 70 and p2.limitMin == 15 and p2.waves[1].base == 30
            and p2.kinds.runner == 20 and p2.hp == nil, "a partial p2 in config.json: the missing knobs from the defaults (not hp)")
        T.check(mf and mf.hordes.presets.p2.limitMin == 15 and mf.hordes.presets.p2.maxAlive == 200 and mf.hordes.presets.p2.cap == 70,
            "and config.json is written back with the whole p2")
        -- a top-level leadMin the old validation refused stays: the file fails on it, nothing is rewritten
        local text = '{ "hordes": { ' .. SPOTS .. ', "leadMin": false } }'
        T.check(put(text) == text and Cf.file.status.ok == false and Cf.file.status.path == "hordes.leadMin"
            and Cf.get().hordes.windows[1].leadMin == 5, "leadMin false: refused on hordes.leadMin, the file left as it is")
        text = '{ "hordes": { ' .. SPOTS .. ', "waitMin": 999, "windows": [ { "days": "1234567", "from": "18:00", "to": "22:00", '
            .. '"chance": 40 } ] } }'
        T.check(put(text) == text and Cf.file.status.ok == false and Cf.file.status.path == "hordes.waitMin"
            and Cf.get().hordes.windows[1].waitMin == 9, "waitMin out of range: refused on hordes.waitMin, not replaced by 60")
        -- every window has its own leadMin and a top-level one is there too: the old key next to the new one stays
        text = '{ "hordes": { ' .. SPOTS .. ', "leadMin": 30, "windows": [ { "days": "1234567", "from": "18:00", "to": "22:00", '
            .. '"chance": 40, "preset": "default", "leadMin": 5, "waitMin": 9 } ] } }'
        T.check(put(text) == text and Cf.file.status.ok == false and Cf.file.status.path == "hordes.leadMin"
            and Cf.get().hordes.windows[1].leadMin == 5, "a top-level leadMin next to the windows' own: refused, not dropped")
        local t2 = { hordes = { leadMin = 30, windows = { win("18:00", "22:00", 40, nil, { leadMin = 5 }) } } }
        T.check(Cf.migrate(t2) == false and t2.hordes.leadMin == 30 and t2.hordes.windows[1].leadMin == 5,
            "migrate leaves both as they are")
    end)

    section("Store: the old single roll keeps its day count; an old live horde carries on", function()
        local Q = boot()
        -- (g) the default preset as the server has it now (an old horde takes what it did not copy from here)
        apply(Q, { cap = 321, restSec = 12, maxAlive = 150, points = { vanilla = 7 }, hp = { vanilla = 3 }, limitMin = 40 })
        Q.Config.apply({ { op = "set", path = "hordes.presets.default.name", value = "Std" } }, "test", "tester")
        local root = Q.Store.root()
        root.hordes.roll = { day = "2026-10-27", ws = 123, slot = 2, n = 1 }
        root.hordes.perDay = nil
        root.hordes.seq = 5
        root.hordes.log = { { id = 3, state = "success", pool = 50, split = "each", paid = { alice = 50, bob = 50 },
            kills = { alice = 6, bob = 4 } }, { id = 4, state = "failed", why = "time", pool = 40, split = "share", paid = {},
            kills = { alice = 2 } } }
        root.hordes.cur = { id = 5, auto = true, actor = "auto", name = "Old", x = SPOT.x, y = SPOT.y, z = 0, town = "muldraugh",
            mix = { { kind = "vanilla", n = 3, nameKey = "IGUI_MQ_Horde_Kind_vanilla" } }, count = 3, perZombie = 5,
            split = "share", limitMin = 15, waitMin = 60, state = "announced", announceAt = T.now - MIN, startMs = T.now + MIN,
            expireAt = T.now + 61 * MIN, spawned = 0, left = 0, killed = 0, kills = {}, tries = 0 }
        Q = boot({ keepGmd = true })
        root = Q.Store.root()
        T.check(root.hordes.perDay["2026-10-27"] == 1 and next(root.hordes.roll) == nil, "roll { day, n } -> perDay[day] = n")
        local l1, l2 = root.hordes.log[1], root.hordes.log[2]
        T.check(l1.waves == 1 and l1.cleared == 1 and l1.pool == 100 and l1.split == nil and l2.waves == 1 and l2.cleared == 0
            and l2.pool == 0, "old results: one wave, cleared on a win, pool = what was actually paid")
        local cur = root.hordes.cur
        T.check(cur and cur.waves[1].base == 3 and cur.weights.vanilla == 3 and cur.count == nil and cur.split == nil
            and cur.got ~= nil, "an old planned horde: one wave of its count")
        T.check(cur.points.vanilla == 7 and cur.cap == 321 and cur.restSec == 12 and cur.maxAlive == 150 and cur.preset == "Std"
            and type(cur.hp) == "table" and next(cur.hp) == nil and cur.limitMin == 15 and cur.waitMin == 60,
            "(g) the rest from today's default preset, health x 1; its own limitMin and waitMin stay")
        local alice = T.player{ name = "alice" }
        near(alice)
        T.now = cur.startMs
        step(Q)
        T.check(cur.state == "active" and cur.spawned == 3, "and it runs")
    end)

    section("config.json round trip of hordes", function()
        local Q = boot()
        local DIR = "MinidoracatQuest/servertest/"
        local function fileTree(name)
            local f = T.files[DIR .. name]
            return f and Q.Util.decode(table.concat(f.lines, "\n"), 1000000) or nil
        end
        local defaults = fileTree("defaults.json")
        T.check(defaults and defaults.hordes and defaults.hordes.windows[1].from == "19:00"
            and defaults.hordes.windows[1].leadMin == 15 and defaults.hordes.presets.default.kinds.runner == 20
            and defaults.hordes.presets.default.waves[1].base == 30 and defaults.hordes.presets.default.cap == 500,
            "defaults.json carries the hordes group")
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "enabled": true, "maxPerDay": 3, '
            .. '"spots": [ { "name": "Lot", "x": 10600, "y": 9800, "z": 0 } ], '
            .. '"presets": { "default": { "kinds": { "runner": 0 } } } } }' } }
        T.advance(Q.Config.POLL_MS)
        T.tick(1)
        local h = Q.Config.get().hordes
        T.check(h.enabled == true and h.maxPerDay == 3 and #h.spots == 1 and h.spots[1].name == "Lot" and def(Q).kinds.runner == 0
            and def(Q).kinds.vanilla == 80 and def(Q).cap == 500 and h.windows[1].from == "19:00",
            "an edited config.json applies hordes (preset knobs merge, spots replace)")
        T.files[DIR .. "config.json"] = { lines = { '{ "hordes": { "spots": [ { "name": "Lot", "x": 1, "y": 1, "z": 40 } ] } }' } }
        T.advance(Q.Config.POLL_MS)
        T.tick(1)
        T.check(Q.Config.file.status.ok == false and Q.Config.file.status.path == "hordes.spots" and Q.Config.get().hordes.maxPerDay == 3,
            "a bad spot in config.json: nothing applied, the path reported")
        apply(Q, { cap = 123 })
        local mirrored = fileTree("config.json")
        T.check(mirrored and mirrored.hordes.presets.default.cap == 123 and mirrored.hordes.maxPerDay == 3
            and mirrored.hordes.spots[1].x == 10600,
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
            for i = 1, n + 2 do list[#list + 1] = T.zombie{ useless = true } end   -- a kind may want them standing
            return list
        end })
        H.registerKind({ modId = "ghostmod", id = "broken", nameKey = "IGUI_GM_Broken", spawn = function() error("boom") end })
        apply(Q, { spots = { SPOT }, waves = { wave(6) }, kinds = { vanilla = 0, runner = 0, ["ghostmod:wraith"] = 50,
            ["ghostmod:broken"] = 50 }, points = { vanilla = 1, ["ghostmod:wraith"] = 4 } })
        near(alice)
        adm(admin, "horde.now")
        local cur = root.hordes.cur
        T.check(#got == 2 and got[1].x == SPOT.x and (got[1].y == SPOT.y + 30 or got[1].y == SPOT.y - 30)
            and got[1].n + got[2].n == 3, "the kind's spawn gets the exits and its share")
        T.check(cur.state == "active" and cur.spawned == 3 and cur.queue["ghostmod:broken"] == 3,
            "only IsoZombie, at most n of them; a failing kind is skipped and stays queued")
        local function fails()
            local n = 0
            for _, l in ipairs(T.prints) do
                if string.find(l, "horde kind ghostmod:broken failed", 1, true) then n = n + 1 end
            end
            return n
        end
        T.check(fails() == 1, "the failing kind is logged once, though both exits hit it")
        step(Q)
        T.check(fails() == 1 and cur.queue["ghostmod:broken"] == 3, "its next batch fails again: still one line a horde")
        local open = toasts(alice, "open")
        T.check(#open == 1 and #open[1].kinds == 2 and open[1].kinds[1].nameKey == "IGUI_GM_Broken"
            and open[1].kinds[2].nameKey == "IGUI_GM_Wraith", "the announcement names registered kinds by their nameKey")
        local z
        for zz, t in pairs(H.live) do if t.kind == "ghostmod:wraith" then z = zz end end
        T.check(z.useless == true, "a registered kind's own flags stay (only the built-in kinds clear useless)")
        z:Kill(alice)
        T.check(cur.waveGot.alice == 4, "a registered kind's own points")
    end)
end
