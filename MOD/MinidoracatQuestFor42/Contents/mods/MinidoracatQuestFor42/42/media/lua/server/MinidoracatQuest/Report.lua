-- MinidoracatQuest/Report.lua: the admin "report" tab (docs/ARCHITECTURE.md section 6.5).
-- root.daily[dayKey] holds one row of totals per day, kept 30 days; the hooks (Stats.add, Points.award, Quests,
-- Exchange payout, Achievements unlock, Store account creation, hello) only add numbers. Only report.get and
-- report.export walk accounts: one shard per tick, the result kept 5 minutes. Totals only, never names or ids.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Server"
require "MinidoracatQuest/Achievements"
require "MinidoracatQuest/Balance"

local Q = MinidoracatQuest
local first = Q.Report == nil
local R = Q.Report or {}
Q.Report = R
local U, CODE = Q.Util, Q.Contract.CODE

local DAY = 86400000
R.KEEP = 30                       -- days of root.daily
R.TTL = 300000                    -- snapshot reuse
R.WINDOWS = { [7] = 1, [30] = 3 } -- report windows (days) -> ended weeks in the weekly rate
R.waiters = R.waiters or {}

local FIELDS = { "active", "fresh", "dGiven", "dDone", "dPlayers", "wGiven", "wDone", "coins", "tiers" }

-- ===== day rows =====

local function ready() return Q.Store.ready() and not Q.Store.readOnly end

local function prune(daily, now)
    local oldest = Q.Clock.dayKey(now - (R.KEEP - 1) * DAY)
    local stale = {}
    for k in pairs(daily) do
        if k < oldest then stale[#stale + 1] = k end
    end
    for _, k in ipairs(stale) do daily[k] = nil end
end

-- today's row; the day key is worked out (and old rows pruned) only when the day changes
function R.row(now)
    local root = Q.Store.root()
    if R.root ~= root or R.dayEnd == nil or now >= R.dayEnd or now < R.dayEnd - DAY then
        R.root, R.day, R.dayEnd = root, Q.Clock.dayKey(now), Q.Clock.nextResetMs(now)
        prune(root.daily, now)
    end
    local d = root.daily[R.day]
    if d == nil then
        d = { active = 0, fresh = 0, dGiven = 0, dDone = 0, dPlayers = 0, wGiven = 0, wDone = 0, swaps = {}, pts = {},
            coins = 0, tiers = 0 }
        root.daily[R.day] = d
    end
    return d
end

-- field += n (default 1); with key: field[key] += n (swaps by template id, pts by Points kind)
function R.add(field, key, n)
    if not ready() then return end
    local d = R.row(getTimestampMs())
    if key == nil then
        d[field] = (d[field] or 0) + (n or 1)
    else
        local m = d[field]
        m[key] = (m[key] or 0) + (n or 1)
    end
end

-- an account's activity: the first one of the day counts it as active
function R.seen(acc)
    if acc == nil or not ready() then return end
    local d = R.row(getTimestampMs())
    if acc.seenDay ~= R.day then
        acc.seenDay = R.day
        d.active = d.active + 1
    end
end

local function sumMap(m)
    local s = 0
    for _, n in pairs(m or {}) do s = s + n end
    return s
end

-- rows oldest first (a day without a row reads as zeros) and their sums; full keeps the swaps/pts maps (export)
local function rowsFor(days, now, full)
    local daily = Q.Store.root().daily or {}   -- absent on a read-only (newer schema) store
    local rows, sum = {}, { swapsBy = {}, ptsBy = {} }
    for _, f in ipairs(FIELDS) do sum[f] = 0 end
    for k = days - 1, 0, -1 do
        local key = Q.Clock.dayKey(now - k * DAY)
        local d = daily[key] or {}
        local r = { day = key }
        for _, f in ipairs(FIELDS) do
            r[f] = d[f] or 0
            sum[f] = sum[f] + r[f]
        end
        for tid, n in pairs(d.swaps or {}) do sum.swapsBy[tid] = (sum.swapsBy[tid] or 0) + n end
        for kind, n in pairs(d.pts or {}) do sum.ptsBy[kind] = (sum.ptsBy[kind] or 0) + n end
        if full then
            r.swaps, r.pts = U.copy(d.swaps or {}), U.copy(d.pts or {})
        else
            r.swaps, r.pts = sumMap(d.swaps), sumMap(d.pts)
        end
        rows[#rows + 1] = r
    end
    sum.active = nil   -- player-days; the window's players are the snapshot's count
    sum.swaps, sum.pts = sumMap(sum.swapsBy), sumMap(sum.ptsBy)
    local n = sum.dGiven - sum.swaps
    sum.dRate = n > 0 and math.min(1, sum.dDone / n) or nil
    -- weekly: only weeks that ended (R.WINDOWS[days] of them before this week's Monday reset)
    local weekStart = Q.Clock.weekResetMs(now) - 7 * DAY
    local wg, wd = 0, 0
    for k = 1, R.WINDOWS[days] * 7 do
        local d = daily[Q.Clock.dayKey(weekStart - k * DAY)]
        if d then wg, wd = wg + (d.wGiven or 0), wd + (d.wDone or 0) end
    end
    sum.wRate = wg > 0 and math.min(1, wd / wg) or nil
    return rows, sum
end

-- ===== account snapshot: one shard per tick =====

local function newWin(now, days)
    local since = Q.Clock.dayStartMs(now) - (days - 1) * DAY
    return { since = since, sinceKey = Q.Clock.dayKey(since), n = 0, none = 0, tierSum = 0, streak7 = 0,
        exPlayers = 0, achv = {} }
end

function R.start(now)
    local win = {}
    for days in pairs(R.WINDOWS) do win[days] = newWin(now, days) end
    R.job = { shard = 0, at = now, root = Q.Store.root(), win = win, bal = {}, unspent = 0 }
end

local function visit(job, acc)
    local b = acc.points and acc.points.balance or 0
    if b > 0 then
        job.unspent = job.unspent + b
        job.bal[#job.bal + 1] = b
    end
    for _, w in pairs(job.win) do
        if (acc.seenMs or 0) >= w.since or (acc.seenDay or "") >= w.sinceKey then
            w.n = w.n + 1
            local any = false
            for id, t in pairs(acc.achv or {}) do
                if type(t) == "number" and t > 0 then
                    any = true
                    local c = w.achv[id]
                    if c == nil then
                        c = {}
                        w.achv[id] = c
                    end
                    for k = 1, t do c[k] = (c[k] or 0) + 1 end   -- c[k] = players at tier k or above
                    w.tierSum = w.tierSum + t
                end
            end
            if not any then w.none = w.none + 1 end
            if acc.streak and (acc.streak.days or 0) >= 7 then w.streak7 = w.streak7 + 1 end
            for _, e in ipairs(acc.ex and acc.ex.log or {}) do
                if e.state == "paid" and (e.at or 0) >= w.since then
                    w.exPlayers = w.exPlayers + 1
                    break
                end
            end
        end
    end
end

local function answer(w, now)
    local ok, data, c = pcall(w.build, now)
    local res
    if ok and data then
        res = data
        res.ok, res.code = true, CODE.OK
    else
        if not ok then U.log(tostring(w.op) .. " failed: " .. tostring(data)) end
        res = { ok = false, code = ok and c or CODE.INTERNAL }
    end
    res.op, res.requestId = w.op, w.requestId
    pcall(Q.Net.send, w.player, "admin", res)   -- the admin may have left meanwhile
end

function R.tick(now)
    local job = R.job
    if job == nil or not Q.Store.ready() then return end
    if job.root ~= Q.Store.root() then
        R.job = nil
        return
    end
    Q.Store.eachIn(job.shard, function(_, acc) visit(job, acc) end)
    job.shard = job.shard + 1
    if job.shard < Q.Contract.SHARDS then return end
    U.sort(job.bal, function(a, b) return a > b end)
    local top = 0
    for i = 1, math.ceil(#job.bal / 10) do top = top + job.bal[i] end
    R.snap = { at = job.at, root = job.root, win = job.win, unspent = job.unspent, holders = #job.bal,
        top10 = job.unspent > 0 and top / job.unspent or nil }
    R.job = nil
    local waiters = R.waiters
    R.waiters = {}
    for _, w in ipairs(waiters) do answer(w, now) end
end

local function fresh(now)
    local s = R.snap
    return s ~= nil and s.root == Q.Store.root() and now - s.at < R.TTL
end

-- ===== replies =====

-- achievements in list order, sorted by players at the highest tier, then the next one down
local function achvRows(w)
    local rows = {}
    for _, d in ipairs((Q.Achievements.list())) do
        local c, counts = w.achv[d.id] or {}, {}
        for k = 1, #d.tiers do counts[k] = c[k] or 0 end
        rows[#rows + 1] = { id = d.id, hidden = d.hidden and true or nil, c = counts }
    end
    U.sort(rows, function(a, b)
        for k = 10, 1, -1 do
            local x, y = a.c[k] or 0, b.c[k] or 0
            if x ~= y then return x > y end
        end
        return false
    end)
    return rows
end

-- report.get reply (docs/ARCHITECTURE.md 6.5)
function R.data(days, now)
    local s = R.snap
    local w = s.win[days]
    local rows, sum = rowsFor(days, now)
    return { days = days, at = s.at, rows = rows, sum = sum, achv = achvRows(w),
        snap = { active = w.n, none = w.none, tierSum = w.tierSum, streak7 = w.streak7, exPlayers = w.exPlayers,
            unspent = s.unspent, holders = s.holders, top10 = s.top10 } }
end

-- report-YYYY-MM-DD.json beside config.json (one per day, overwritten); totals only
function R.export(now)
    local s = R.snap
    local w = s.win[30]
    local rows, sum = rowsFor(30, now, true)
    local achv = {}
    for _, r in ipairs(achvRows(w)) do achv[r.id] = r.c end
    local quests = {}
    for _, r in ipairs(Q.Balance.report(now)) do
        quests[r.tid] = { given = r.given, done = r.done, swaps = r.swaps, rate = r.rate }
    end
    local day = Q.Clock.dayKey(now)
    local out = { at = now, day = day, days = 30, daily = rows, sum = sum,
        players = { active7 = s.win[7].n, active30 = w.n, noAchv = w.none, tierSum = w.tierSum, streak7 = w.streak7,
            exchanged = w.exPlayers },
        achv = achv, points = { unspent = s.unspent, holders = s.holders, top10share = s.top10 }, quests = quests }
    local path = Q.Store.path("report-" .. day .. ".json")
    local text = U.encode(out, true)
    local back = Q.Store.writeLines(path, { text }, false) and Q.Store.readLines(path, 1)
    if type(back) ~= "table" or back[1] == nil then return nil, CODE.FILE_ERROR end
    return { path = path }
end

-- answer now from a fresh snapshot, or start the walk and answer when it ends
local function want(ctx, build)
    if fresh(ctx.now) then
        local data, c = build(ctx.now)
        if not data then return false, c end
        return true, data
    end
    if R.job == nil then R.start(ctx.now) end
    R.waiters[#R.waiters + 1] = { player = ctx.player, requestId = ctx.requestId, op = ctx.op, build = build }
    return true, Q.Server.LATER
end

Q.Server.defineAdmin("report.get", { kind = "query", fields = { days = "int" }, run = function(ctx)
    local days = ctx.args.days
    if R.WINDOWS[days] == nil then return false, CODE.BAD_ARGS end
    return want(ctx, function(now) return R.data(days, now) end)
end })

Q.Server.defineAdmin("report.export", { kind = "query", cooldownMs = 3000, run = function(ctx)
    return want(ctx, R.export)
end })

if first then
    Events.OnTickEvenPaused.Add(function() MinidoracatQuest.Report.tick(getTimestampMs()) end)
end

return R
