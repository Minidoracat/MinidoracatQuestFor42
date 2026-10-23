-- MinidoracatQuestFor42 - daily quests (preferences), shared quest, swaps, streak, weekly quests,
-- community goal, newbie steps and timed events (server authority, contract 5.8).
if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"
require "MinidoracatQuest/Balance"

local first = MQ.Quests == nil
local Q = MQ.Quests or {}
MQ.Quests = Q

local DAY = 86400000
local INACTIVE_MS = 30 * DAY        -- C32: drop day/week scratch after 30 days offline
-- contract 4.1: without preferences the three slots draw from these groups in order
Q.GROUPS = MQ.Contract.THEME_GROUPS
-- quest-type stats fed here (ids owned by Catalog; skipped when Catalog has no such stat)
Q.STAT = { daily = "quest.daily", weekly = "quest.weekly", streak = "streak.best", goal = "goal.done" }

local function code(name) return MQ.Contract.CODE[name] end

-- Feed a quest-type stat if the catalog defines it (Stats.add re-enters the listeners; these
-- stats are never daily/weekly targets, so the recursion stops after one level).
function Q.feed(user, id, n, isMax)
    if not MQ.Stats.def(id) then return end
    if isMax then MQ.Stats.max(user, id, n) else MQ.Stats.add(user, id, n) end
end

-- ---------- keys (hot path: no strings built while the day lasts) ----------

local cur = { dayStart = 0, dayEnd = 0, weekEnd = 0 }

function Q.keys(now)
    if now >= cur.dayEnd or now < cur.dayStart then
        cur.day = MQ.Clock.dayKey(now)
        cur.dayEnd = MQ.Clock.nextResetMs(now)
        cur.dayStart = cur.dayEnd - DAY
        cur.week = MQ.Clock.weekKey(now)
        cur.weekEnd = MQ.Clock.weekResetMs(now)
    end
    return cur.day, cur.week
end

-- ---------- pools ----------

local function packList(field)
    local ids, out = {}, {}
    for modId in pairs(MQ.Packs or {}) do ids[#ids + 1] = modId end
    MQ.Util.sort(ids, function(a, b) return a < b end)
    for _, modId in ipairs(ids) do
        for _, t in ipairs(MQ.Packs[modId][field] or {}) do out[#out + 1] = t end
    end
    return out
end

-- Enabled templates in a stable order: Catalog first, then packs by modId.
local function pool(list, overrides, packs)
    local out = {}
    overrides = overrides or {}
    for _, t in ipairs(list or {}) do
        local o = overrides[t.tid]
        if not (o and o.enabled == false) then out[#out + 1] = t end
    end
    for _, t in ipairs(packs or {}) do
        local o = overrides[t.tid]
        if not (o and o.enabled == false) then out[#out + 1] = t end
    end
    return out
end

function Q.dailyPool(cfg) return pool(MQ.Catalog.daily, cfg.daily.pool, packList("quests")) end
function Q.weeklyPool(cfg) return pool(MQ.Catalog.weekly, cfg.weekly.pool) end

local function diffMult(cfg)
    local m = cfg.difficulty and cfg.difficulty.mult
    return type(m) == "number" and m > 0 and m or 1
end
Q.diffMult = diffMult

-- rng nil = middle of the range (shared quest)
local function rollTarget(t, o, rng, mult)
    local range = (o and o.target) or t.target
    local a = range[1]
    local b = range[2] or a
    local step = t.step or 1
    local n = math.floor((b - a) / step)
    if n < 0 then n = 0 end
    local v = a + step * (rng and rng:int(0, n) or math.floor(n / 2))
    v = math.floor(v * mult / step + 0.5) * step
    if v < 1 then v = 1 end
    return v
end

local function pickT(list, theme, rng, used)
    local c = {}
    for _, t in ipairs(list) do
        if t.theme == theme and not used[t.stat] then c[#c + 1] = t end
    end
    if #c == 0 then
        for _, t in ipairs(list) do
            if not used[t.stat] then c[#c + 1] = t end
        end
    end
    if #c == 0 then return nil end
    return c[rng:int(1, #c)]
end

local function newQuest(t, target, pts, now)
    return { tid = t.tid, stat = t.stat, theme = t.theme, target = target, prog = 0, pts = pts,
        state = "active", startMs = now }
end

local function dailyPts(cfg, t)
    local o = cfg.daily.pool and cfg.daily.pool[t.tid]
    if o and type(o.pts) == "number" then return o.pts end
    if type(t.pts) == "number" then return t.pts end      -- pack quests carry their own points
    return t.rare and cfg.daily.rarePts or cfg.daily.pts
end

-- Two slots from the player's themes and one from all themes; else one per group (contract 4.1).
function Q.slots(prefs, rng)
    local U = MQ.Util
    if prefs and #prefs > 0 then
        return { U.pick(prefs, rng), U.pick(prefs, rng), U.pick(MQ.Contract.THEMES, rng) }
    end
    return { U.pick(Q.GROUPS[1], rng), U.pick(Q.GROUPS[2], rng), U.pick(Q.GROUPS[3], rng) }
end

-- ---------- shared quest (seeded by the day only) ----------

function Q.sharedToday(day, cfg)
    local root = MQ.Store.root()
    local s = root.shared
    if s and s.day == day then return s end
    s = { day = day, done = 0 }
    local list = {}
    for _, t in ipairs(Q.dailyPool(cfg)) do
        if t.shared ~= false then list[#list + 1] = t end
    end
    if #list > 0 then
        local rng = MQ.Util.rng(MQ.Util.hash(day))
        local t = list[rng:int(1, #list)]
        local o = cfg.daily.pool and cfg.daily.pool[t.tid]
        s.tid, s.stat, s.theme = t.tid, t.stat, t.theme
        s.target = rollTarget(t, o, nil, diffMult(cfg))
        s.pts = cfg.daily.sharedPts
    end
    root.shared = s
    return s
end

-- ---------- generation ----------

local function genDay(acc, user, day, now, cfg)
    local list = Q.dailyPool(cfg)
    local mult = diffMult(cfg)
    local rng = MQ.Util.rng(MQ.Util.hash(user .. "|" .. day))
    local used, quests = {}, {}
    local sh = Q.sharedToday(day, cfg)
    if sh.stat then used[sh.stat] = true end
    for i, theme in ipairs(Q.slots(acc.prefs, rng)) do
        local t = pickT(list, theme, rng, used)
        if t then
            used[t.stat] = true
            quests[i] = newQuest(t, rollTarget(t, cfg.daily.pool and cfg.daily.pool[t.tid], rng, mult), dailyPts(cfg, t), now)
            MQ.Balance.given(t.tid, now)
        end
    end
    if sh.stat then
        local q = { tid = sh.tid, stat = sh.stat, theme = sh.theme, target = sh.target, prog = 0, pts = sh.pts,
            state = "active", shared = true, startMs = now }
        quests[4] = q
        MQ.Balance.given(sh.tid, now)
    end
    acc.day = { key = day, quests = quests, swaps = cfg.daily.swapsPerDay, done = 0 }
end

local function genWeek(acc, user, week, now, cfg)
    local list = Q.weeklyPool(cfg)
    local mult = diffMult(cfg)
    local rng = MQ.Util.rng(MQ.Util.hash(user .. "|" .. week))
    local used, quests = {}, {}
    for i = 1, cfg.weekly.count or 3 do
        local t = pickT(list, MQ.Util.pick(Q.GROUPS[(i - 1) % 3 + 1], rng), rng, used)
        if not t then break end
        used[t.stat] = true
        local o = cfg.weekly.pool and cfg.weekly.pool[t.tid]
        quests[#quests + 1] = newQuest(t, rollTarget(t, o, rng, mult), o and o.pts or cfg.weekly.pts, now)
        MQ.Balance.given(t.tid, now)
    end
    acc.week = { key = week, quests = quests, goalPart = 0 }
end

-- ---------- streak (C23) ----------

local function streakOf(acc)
    local s = acc.streak
    if not s then
        s = { days = 0, best = 0, graceUsed = false, paid = {} }
        acc.streak = s
    end
    s.paid = s.paid or {}
    s.marks = s.marks or {}
    return s
end

local function mark(s, day, what, now)
    s.marks[day] = what
    local oldest = MQ.Clock.dayKey(now - 8 * DAY)
    local stale = {}
    for k in pairs(s.marks) do
        if k < oldest then stale[#stale + 1] = k end
    end
    for _, k in ipairs(stale) do s.marks[k] = nil end
end

local function countDay(acc, user, s, day, now, cfg, what)
    s.days = (s.days or 0) + 1
    s.last = day
    if s.days > (s.best or 0) then s.best = s.days end
    mark(s, day, what, now)
    Q.feed(user, Q.STAT.streak, s.best, true)
    for _, m in ipairs(cfg.streak.milestones or {}) do
        if s.days >= m.days and not s.paid[m.days] then
            s.paid[m.days] = true
            MQ.Points.award(acc, user, m.pts, "streak", m.days)
            if m.title then acc.titles = acc.titles or {}; acc.titles[m.title] = true end
            acc.unseen = (acc.unseen or 0) + 1
            MQ.EventLog.write("streak", user, { days = m.days, pts = m.pts })
            MQ.Sync.toast(user, { kind = "streak", days = m.days, pts = m.pts })
        end
    end
    MQ.Sync.dirty(user, "streak")
end

-- Day change: yesterday missed -> grace once per week (counts as a day), otherwise reset.
function Q.rollStreak(acc, user, now, cfg)
    local s = streakOf(acc)
    if (s.days or 0) == 0 or not s.last then return end
    local missed = {}
    for k = 1, 3 do
        local ms = now - k * DAY
        if MQ.Clock.dayKey(ms) <= s.last then break end
        missed[#missed + 1] = ms
    end
    if #missed == 0 then return end
    if #missed == 1 and (cfg.streak.gracePerWeek or 0) > 0 then
        local wk = MQ.Clock.weekKey(missed[1])
        if s.graceWeek ~= wk then
            s.graceWeek, s.graceUsed = wk, true
            countDay(acc, user, s, MQ.Clock.dayKey(missed[1]), now, cfg, "grace")
            return
        end
    end
    s.days, s.paid = 0, {}
    MQ.Sync.dirty(user, "streak")
end

-- ---------- ensure ----------

function Q.ensure(acc, user, now)
    local day, week = Q.keys(now)
    local cfg = MQ.Config.get()
    local changed = false
    if not acc.day or acc.day.key ~= day then
        if acc.day then
            for i = 1, 4 do
                local q = acc.day.quests and acc.day.quests[i]
                if q and q.state == "active" then q.state = "expired" end
            end
        end
        Q.rollStreak(acc, user, now, cfg)
        genDay(acc, user, day, now, cfg)
        changed = true
        MQ.Sync.dirty(user, "day")
    end
    if not acc.week or acc.week.key ~= week then
        Q.goalFor(week, now, cfg)
        genWeek(acc, user, week, now, cfg)
        changed = true
        MQ.Sync.dirty(user, "week")
    end
    local s = streakOf(acc)
    if s.graceWeek ~= week and s.graceUsed then s.graceUsed = false end
    local nb = acc.newbie
    if nb and (cfg.newbie.enabled == false or now - (nb.startMs or now) >= (cfg.newbie.days or 7) * DAY) then
        acc.newbie = nil
        changed = true
        MQ.Sync.dirty(user, "newbie")
    end
    return changed
end

-- ---------- timed events (C9) ----------

function Q.eventMult(theme, now)
    local m = 1
    for _, e in ipairs(MQ.Store.root().events or {}) do
        if e.startMs <= now and now < e.endMs and (e.theme == "all" or e.theme == theme) and e.mult > m then
            m = e.mult
        end
    end
    return m
end

-- points a quest pays: the stored payout once done, otherwise base x the event multiplier now (same rounding)
function Q.questPts(q, now)
    if q.state == "done" then return q.got end
    return math.floor(q.pts * Q.eventMult(q.theme, now) + 0.5)
end

-- ---------- completion ----------

local function complete(acc, user, q, kind, now, cfg)
    local pts = Q.questPts(q, now)   -- before state = "done" (questPts returns the stored payout then)
    q.state, q.doneMs, q.prog, q.got = "done", now, q.target, pts
    MQ.Points.award(acc, user, pts, kind, q.tid)
    acc.unseen = (acc.unseen or 0) + 1
    MQ.Balance.done(q.tid, q.startMs, now)
    local week = kind == "week"
    MQ.EventLog.write(week and "week_done" or "quest_done", user, { tid = q.tid, pts = pts })
    MQ.Sync.toast(user, { kind = week and "week" or "quest", tid = q.tid, pts = pts })
    if week then
        Q.feed(user, Q.STAT.weekly, 1)
        return
    end
    local d = acc.day
    d.done = (d.done or 0) + 1
    if q.shared then
        local sh = MQ.Store.root().shared
        if sh and sh.day == d.key then sh.done = (sh.done or 0) + 1 end
    end
    Q.feed(user, Q.STAT.daily, 1)
    if d.done >= (cfg.streak.need or 3) then
        local s = streakOf(acc)
        if s.last ~= d.key then countDay(acc, user, s, d.key, now, cfg, "done") end
    end
end

local function advance(acc, user, list, stat, delta, kind, now, cfg, part)
    for i = 1, #list do
        local q = list[i]
        if q and q.state == "active" and q.stat == stat then
            q.prog = q.prog + delta
            MQ.Sync.dirty(user, part)
            if q.prog >= q.target then complete(acc, user, q, kind, now, cfg) end
        end
    end
end

function Q.onStat(acc, user, stat, delta, opts)
    if opts and opts.quiet then return end
    local now = MQ.Clock.now()
    Q.ensure(acc, user, now)
    local cfg = MQ.Config.get()
    local qs = acc.day.quests
    for i = 1, 4 do
        local q = qs[i]
        if q and q.state == "active" and q.stat == stat then
            q.prog = q.prog + delta
            MQ.Sync.dirty(user, "day")
            if q.prog >= q.target then complete(acc, user, q, q.shared and "shared" or "quest", now, cfg) end
        end
    end
    advance(acc, user, acc.week.quests, stat, delta, "week", now, cfg, "week")
end

-- ---------- community goal ----------

function Q.goalFor(week, now, cfg)
    local root = MQ.Store.root()
    local g = root.goal
    if g and g.week == week then return g end
    if g and g.reached and not g.paid then Q.payAll(g) end
    if not (cfg.goal and cfg.goal.enabled ~= false and cfg.goal.rotation and #cfg.goal.rotation > 0) then
        root.goal = nil
        root.weekTotals = { week = week, totals = {} }
        return nil
    end
    local rot = cfg.goal.rotation
    local wn = tonumber(string.match(week, "W(%d+)")) or 1
    local stat = rot[wn % #rot + 1]
    local lim = (cfg.goal.limits or {})[stat] or {}
    local lo, hi = lim.min or 1, lim.max or 1000000000
    local wt = root.weekTotals
    local last = nil
    if wt and wt.week == MQ.Clock.weekKey(now - 7 * DAY) and wt.totals then last = wt.totals[stat] end
    local target = lo
    if last then target = MQ.Util.clamp(math.floor(last * (cfg.goal.growth or 1)), lo, hi) end
    g = { week = week, stat = stat, target = target, progress = 0, pts = cfg.goal.pts, reached = false, paid = false,
        minContrib = math.max(lim.minContrib or 1, math.floor((last or 0) * 0.001)) }
    root.goal = g
    root.weekTotals = { week = week, totals = {} }
    return g
end

local function payOne(user, acc, g)
    acc.week.goalPaid = true
    MQ.Points.award(acc, user, g.pts, "goal", g.stat)
    acc.unseen = (acc.unseen or 0) + 1
    MQ.EventLog.write("goal_paid", user, { stat = g.stat, pts = g.pts })
    MQ.Sync.toast(user, { kind = "goal", stat = g.stat, pts = g.pts })
    MQ.Sync.dirty(user, "goal")
    Q.feed(user, Q.STAT.goal, 1)
end

function Q.payAll(g)
    g.paid = true
    MQ.Store.each(function(user, acc)
        local w = acc.week
        if w and w.key == g.week and not w.goalPaid and (w.goalPart or 0) >= g.minContrib then payOne(user, acc, g) end
    end)
end

function Q.onGoalStat(acc, user, stat, delta, opts)
    if opts and opts.quiet then return end
    local root = MQ.Store.root()
    Q.ensure(acc, user, MQ.Clock.now())
    local cfg = MQ.Config.get()
    local wt = root.weekTotals
    if wt and cfg.goal and cfg.goal.rotation then
        for _, s in ipairs(cfg.goal.rotation) do
            if s == stat then wt.totals[stat] = (wt.totals[stat] or 0) + delta break end
        end
    end
    local g = root.goal
    if not (g and g.stat == stat and acc.week.key == g.week) then return end
    g.progress = g.progress + delta
    acc.week.goalPart = (acc.week.goalPart or 0) + delta
    MQ.Sync.dirty(user, "goal")
    if g.reached then
        if not acc.week.goalPaid and acc.week.goalPart >= g.minContrib then payOne(user, acc, g) end
    elseif g.progress >= g.target then
        g.reached = true
        Q.payAll(g)
    end
end

-- ---------- newbie (C18, C35) ----------

function Q.onNewbieStat(acc, user, stat, delta, opts)
    local nb = acc.newbie
    if not nb or (opts and opts.quiet) then return end
    local cfg = MQ.Config.get()
    if cfg.newbie.enabled == false then return end
    local changed, all = false, true
    for i, step in ipairs(MQ.Catalog.newbie or {}) do
        if not nb.steps[i] and step.stat == stat and (acc.total[stat] or 0) >= step.target then
            nb.steps[i] = true
            changed = true
        end
        if not nb.steps[i] then all = false end
    end
    if not changed then return end
    MQ.Sync.dirty(user, "newbie")
    if not all then return end
    acc.newbie = nil
    MQ.Points.award(acc, user, cfg.newbie.pts, "newbie", "newbie")
    if cfg.newbie.title then acc.titles = acc.titles or {}; acc.titles[cfg.newbie.title] = true end
    acc.unseen = (acc.unseen or 0) + 1
    MQ.Sync.toast(user, { kind = "newbie", pts = cfg.newbie.pts })
end

-- ---------- swap and preferences ----------

function Q.swap(acc, user, slot)
    if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > 3 then return false, code("BAD_SLOT") end
    local now = MQ.Clock.now()
    Q.ensure(acc, user, now)
    local d = acc.day
    local q = d.quests[slot]
    if not q or q.state ~= "active" then return false, code("BAD_SLOT") end
    if (d.swaps or 0) <= 0 then return false, code("NO_SWAPS") end
    local cfg = MQ.Config.get()
    local used = {}
    for i = 1, 4 do
        if d.quests[i] then used[d.quests[i].stat] = true end
    end
    local rng = MQ.Util.rng(MQ.Util.hash(user .. "|" .. d.key .. "|swap|" .. tostring(d.swaps)))
    local t = pickT(Q.dailyPool(cfg), q.theme, rng, used)
    if not t then return false, code("NOT_FOUND") end
    q.state = "swapped"
    d.quests[slot] = newQuest(t, rollTarget(t, cfg.daily.pool and cfg.daily.pool[t.tid], rng, diffMult(cfg)), dailyPts(cfg, t), now)
    d.swaps = d.swaps - 1
    MQ.Balance.given(t.tid, now)
    MQ.Sync.dirty(user, "day")
    return true
end

-- C4: unlimited changes; today's quests stay, the next day uses the new list.
function Q.setPrefs(acc, list)
    if type(list) ~= "table" then return false, code("BAD_ARGS") end
    local out, seen = {}, {}
    for _, id in ipairs(list) do
        if not MQ.Contract.isTheme(id) then return false, code("BAD_THEME") end
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    if #out > 3 then return false, code("TOO_MANY_PREFS") end
    acc.prefs = out
    return true
end


-- ---------- tick ----------

Q.lastTick = Q.lastTick or 0

function Q.tick(now)
    if now - Q.lastTick < 1000 or not MQ.Store.ready() then return end
    Q.lastTick = now
    local day, week = Q.keys(now)
    if Q.tickDay == day and Q.tickWeek == week then return Q.watchEvents(now) end
    local cfg = MQ.Config.get()
    Q.sharedToday(day, cfg)
    Q.goalFor(week, now, cfg)
    local root = MQ.Store.root()
    local live = {}
    for _, e in ipairs(root.events or {}) do
        if e.endMs > now then live[#live + 1] = e end
    end
    root.events = live
    if Q.tickDay ~= nil and Q.tickDay ~= day then
        MQ.Store.each(function(_, acc)
            if (acc.seenMs or now) < now - INACTIVE_MS then acc.day, acc.week = nil, nil end
        end)
    end
    Q.tickDay, Q.tickWeek = day, week
    Q.watchEvents(now)
end

-- an event starting or ending changes ptsNow and the banner: full state to every open window
function Q.watchEvents(now)
    local sig = ""
    for _, e in ipairs(MQ.Store.root().events or {}) do
        if e.startMs <= now and now < e.endMs then sig = sig .. e.id .. "," end
    end
    if sig ~= (Q.eventSig or "") then
        Q.eventSig = sig
        MQ.Sync.dirty(nil, "events")
    end
end

-- ---------- state parts ----------

local function copyQuest(q, now)
    return { tid = q.tid, stat = q.stat, theme = q.theme, target = q.target, prog = q.prog, pts = q.pts,
        ptsNow = Q.questPts(q, now), state = q.state, shared = q.shared, startMs = q.startMs, doneMs = q.doneMs }
end

local function copyQuests(list, now)
    local out = {}
    for i = 1, #(list or {}) + 1 do
        local q = list and list[i]
        if q then out[i] = copyQuest(q, now) end
    end
    return out
end

function Q.stateDay(acc, user, now)
    Q.ensure(acc, user, now)
    local sh = MQ.Store.root().shared
    local d = acc.day
    local out = { quests = {}, swaps = d.swaps, done = d.done, sharedDone = sh and sh.day == d.key and sh.done or 0 }
    for i = 1, 4 do
        local q = d.quests[i]
        if q then out.quests[i] = copyQuest(q, now) end
    end
    return out
end

function Q.stateWeek(acc, user, now)
    Q.ensure(acc, user, now)
    return { quests = copyQuests(acc.week.quests, now), goalPart = acc.week.goalPart or 0 }
end

function Q.stateGoal(acc, user, now)
    local g = MQ.Store.root().goal
    if not g then return nil end
    return { stat = g.stat, target = g.target, progress = g.progress, minContrib = g.minContrib, pts = g.pts,
        endsAt = MQ.Clock.weekResetMs(now), reached = g.reached }
end

function Q.stateStreak(acc, user, now)
    local s = streakOf(acc)
    local cfg = MQ.Config.get()
    local wd = MQ.Clock.weekday(now)
    local week = {}
    for i = 1, 7 do
        local m = s.marks[MQ.Clock.dayKey(now + (i - wd) * DAY)]
        week[i] = m or (i < wd and "miss" or "")
    end
    local nextM = nil
    for _, m in ipairs(cfg.streak.milestones or {}) do
        if not s.paid[m.days] then
            nextM = { days = m.days, pts = m.pts }
            break
        end
    end
    return { days = s.days or 0, graceUsed = s.graceUsed == true, week = week, today = wd, next = nextM }
end

function Q.stateNewbie(acc, user, now)
    local nb = acc.newbie
    if not nb then return nil end
    local steps = {}
    for i = 1, #(MQ.Catalog.newbie or {}) do steps[i] = nb.steps[i] == true end
    return { steps = steps, pts = MQ.Config.get().newbie.pts }
end

function Q.stateEvents(acc, user, now)
    local out = {}
    for _, e in ipairs(MQ.Store.root().events or {}) do
        if e.startMs <= now and now < e.endMs then
            out[#out + 1] = { id = e.id, name = e.name, theme = e.theme, mult = e.mult, endsAt = e.endMs }
        end
    end
    return out
end

-- ---------- admin: timed events ----------

function Q.addEvent(name, theme, mult, startMs, endMs, now, actor)
    local okTheme = theme == "all" or MQ.Contract.isTheme(theme)
    if not okTheme then return false, code("BAD_THEME") end
    if type(name) ~= "string" or name == "" or mult < 1 or mult > 5 or endMs <= startMs or endMs <= now then
        return false, code("BAD_ARGS")
    end
    local root = MQ.Store.root()
    root.events = root.events or {}
    local live, id = 0, 0
    for _, e in ipairs(root.events) do
        if e.endMs > now then live = live + 1 end
        if e.id > id then id = e.id end
    end
    if live >= 3 then return false, code("BAD_ARGS") end
    id = id + 1
    root.events[#root.events + 1] = { id = id, name = name, theme = theme, mult = mult, startMs = startMs, endMs = endMs }
    -- summary "event.add <id> <name>": the client formats it (AdminPanel.summaryText); older rows have no name
    MQ.Config.addHistory(actor, "event.add " .. id .. " " .. name, { { path = "events." .. id, after = mult } }, false)
    return true, id
end

function Q.removeEvent(id, actor)
    local root = MQ.Store.root()
    for i, e in ipairs(root.events or {}) do
        if e.id == id then
            table.remove(root.events, i)
            MQ.Config.addHistory(actor, "event.remove " .. id .. " " .. tostring(e.name or ""),
                { { path = "events." .. id, before = e.mult } }, false)
            return true
        end
    end
    return false, code("NOT_FOUND")
end

-- ---------- registration ----------

local function accOf(ctx) return MQ.Store.account(ctx.user, true) end

MQ.Server.define("swap", { kind = "mutation", fields = { slot = "int" },
    run = function(ctx) return Q.swap(accOf(ctx), ctx.user, ctx.args.slot) end })

MQ.Server.define("prefs", { kind = "mutation", fields = { themes = "str?" },
    run = function(ctx) return Q.setPrefs(accOf(ctx), MQ.Util.split(ctx.args.themes or "", ",")) end })

MQ.Server.defineAdmin("event.add", { kind = "mutation",
    fields = { name = "text", theme = "str", mult = "num", startMs = "num", endMs = "num" },
    run = function(ctx)
        local a = ctx.args
        local ok, res = Q.addEvent(a.name, a.theme, a.mult, a.startMs, a.endMs, ctx.now, ctx.user)
        if not ok then return false, res end
        return true, { id = res }
    end })

MQ.Server.defineAdmin("event.remove", { kind = "mutation", fields = { id = "int" },
    run = function(ctx) return Q.removeEvent(ctx.args.id, ctx.user) end })

MQ.Stats.listen("quests", Q.onStat)
MQ.Stats.listen("goal", Q.onGoalStat)
MQ.Stats.listen("newbie", Q.onNewbieStat)
MQ.Sync.provider("day", Q.stateDay)
MQ.Sync.provider("week", Q.stateWeek)
MQ.Sync.provider("goal", Q.stateGoal)
MQ.Sync.provider("streak", Q.stateStreak)
MQ.Sync.provider("newbie", Q.stateNewbie)
MQ.Sync.provider("events", Q.stateEvents)

if first then
    Events.OnTickEvenPaused.Add(function() MQ.Quests.tick(getTimestampMs()) end)
end

return Q
