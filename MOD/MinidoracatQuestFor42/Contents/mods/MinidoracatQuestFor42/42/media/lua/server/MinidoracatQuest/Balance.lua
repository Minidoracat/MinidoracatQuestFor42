-- MinidoracatQuestFor42 - quest balance: completion rate and median minutes (daily: the last 7 days; weekly: the
-- last week that ended), target-range suggestions (<30% too hard, >90% too easy), and the quick difficulty preview.
-- The rate leaves out assignments swapped away: done / (given - swaps).
if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Server"

local Bal = MQ.Balance or {}
MQ.Balance = Bal

local DAY = 86400000
Bal.DAYS = 7
Bal.KEEP = 14                         -- days of rows kept: the last ended week starts up to 13 days ago
Bal.MINUTES_MAX = 64
Bal.MIN_GIVEN = 10                    -- fewer samples (given - swaps): no suggestion
Bal.LOW, Bal.HIGH = 0.3, 0.9
Bal.DOWN, Bal.UP = 0.7, 1.3           -- target range factor for "hard" / "easy"
Bal.PRESETS = { easy = 0.6, normal = 1, hard = 1.6 }

local function code(name) return MQ.Contract.CODE[name] end

local function prune(now)
    local oldest = MQ.Clock.dayKey(now - (Bal.KEEP - 1) * DAY)
    for _, days in pairs(MQ.Store.root().balance) do
        local stale = {}
        for k in pairs(days) do
            if k < oldest then stale[#stale + 1] = k end
        end
        for _, k in ipairs(stale) do days[k] = nil end
    end
end

local function row(tid, now)
    local root = MQ.Store.root()
    local day = MQ.Clock.dayKey(now)
    if Bal.prunedDay ~= day then
        Bal.prunedDay = day
        prune(now)
    end
    root.balance[tid] = root.balance[tid] or {}
    local r = root.balance[tid][day]
    if not r then
        r = { given = 0, done = 0, swaps = 0, minutes = {} }
        root.balance[tid][day] = r
    end
    return r
end

function Bal.given(tid, now)
    if not MQ.Store.ready() then return end
    local r = row(tid, now)
    r.given = r.given + 1
end

-- an assignment swapped away (Quests.swap): left out of the rate
function Bal.swapped(tid, now)
    if not MQ.Store.ready() then return end
    local r = row(tid, now)
    r.swaps = (r.swaps or 0) + 1
end

function Bal.done(tid, startMs, doneMs)
    if not MQ.Store.ready() then return end
    local r = row(tid, doneMs)
    r.done = r.done + 1
    if #r.minutes < Bal.MINUTES_MAX then r.minutes[#r.minutes + 1] = math.floor((doneMs - (startMs or doneMs)) / 60000) end
end

local function median(list)
    if #list == 0 then return nil end
    MQ.Util.sort(list, function(a, b) return a < b end)
    local m = math.floor((#list + 1) / 2)
    if #list % 2 == 0 then return math.floor((list[m] + list[m + 1]) / 2 + 0.5) end
    return list[m]
end

local function template(tid)
    local t = MQ.Catalog.tpl(tid)
    if t then return t end
    for _, pack in pairs(MQ.Packs or {}) do
        for _, q in ipairs(pack.quests or {}) do
            if q.tid == tid then return q end
        end
    end
    return nil
end

-- { kind, path, value = { min, max } } or nil
local function suggest(tid, rate, cfg)
    local kind, f
    if rate < Bal.LOW then kind, f = "hard", Bal.DOWN
    elseif rate > Bal.HIGH then kind, f = "easy", Bal.UP
    else return nil end
    local t = template(tid)
    if not t then return nil end
    local section = cfg.weekly.pool and cfg.weekly.pool[tid] and "weekly" or "daily"
    local o = cfg[section].pool and cfg[section].pool[tid]
    local range = o and o.target or t.target
    local step = t.step or 1
    local a = math.max(1, math.floor(range[1] * f / step + 0.5) * step)
    local b = math.max(a, math.floor((range[2] or range[1]) * f / step + 0.5) * step)
    if a == range[1] and b == (range[2] or range[1]) then return nil end
    return { kind = kind, path = section .. ".pool." .. tid .. ".target", value = { a, b } }
end

-- rows { tid, given, done, swaps, rate (nil when given - swaps is 0), medianMin, suggest }
function Bal.report(now)
    now = now or MQ.Clock.now()
    local oldest = MQ.Clock.dayKey(now - (Bal.DAYS - 1) * DAY)
    local weekStart = MQ.Clock.weekResetMs(now) - 7 * DAY
    local wFrom, wTo = MQ.Clock.dayKey(weekStart - 7 * DAY), MQ.Clock.dayKey(weekStart)
    local weekly = {}
    for _, t in ipairs(MQ.Catalog.weekly or {}) do weekly[t.tid] = true end
    local cfg = MQ.Config.get()
    local rows = {}
    for tid, days in pairs(MQ.Store.root().balance) do
        local given, done, swaps, mins = 0, 0, 0, {}
        local wk = weekly[tid]
        for day, r in pairs(days) do
            if (wk and day >= wFrom and day < wTo) or (not wk and day >= oldest) then
                given, done, swaps = given + r.given, done + r.done, swaps + (r.swaps or 0)
                for _, m in ipairs(r.minutes) do mins[#mins + 1] = m end
            end
        end
        if given > 0 then
            local n = given - swaps
            local rate = n > 0 and math.min(1, done / n) or nil
            rows[#rows + 1] = { tid = tid, given = given, done = done, swaps = swaps, rate = rate, medianMin = median(mins),
                suggest = rate and n >= Bal.MIN_GIVEN and suggest(tid, rate, cfg) or nil }
        end
    end
    MQ.Util.sort(rows, function(a, b) return a.tid < b.tid end)
    return rows
end

-- ---------- quick difficulty (C11): thresholds and quest targets only, never points ----------

function Bal.diffPreview(preset, mult)
    local m = Bal.PRESETS[preset]
    if preset == "custom" then
        if type(mult) ~= "number" or mult < 0.1 or mult > 10 then return nil, code("BAD_ARGS") end
        m = mult
    end
    if not m then return nil, code("BAD_ARGS") end
    local A = MQ.Achievements
    local list = A.list()
    local rows = {}
    for _, d in ipairs(list) do
        if #rows >= 40 then break end
        rows[#rows + 1] = { path = "achievements." .. d.id .. ".tiers", before = d.tiers, after = A.scale(d.base, m, d.stat) }
    end
    -- estimate: tier III of the first combat achievement with 3+ tiers, and who has reached it
    local ref = MQ.Catalog.ach("zombie_kills")
    ref = ref and A.get(ref.id)
    if not ref then
        for _, d in ipairs(list) do
            if not ref and #d.base >= 3 then ref = d end
        end
    end
    local estimate = {}
    if ref and #ref.base >= 3 then
        local mults = { easy = 0.6, normal = 1, hard = 1.6, custom = preset == "custom" and m or nil }
        local tier3 = { key = "IGUI_MQ_Est_Tier3" }
        local reached = { key = "IGUI_MQ_Est_Reached" }
        local values, n = {}, 0
        MQ.Store.each(function(_, acc)
            n = n + 1
            values[n] = acc.total[ref.stat] or 0
        end)
        for k, x in pairs(mults) do
            local t3 = A.scale(ref.base, x, ref.stat)[3]
            tier3[k] = t3
            local c = 0
            for i = 1, n do
                if values[i] >= t3 then c = c + 1 end
            end
            reached[k] = n > 0 and math.floor(c * 100 / n + 0.5) or 0
        end
        estimate[#estimate + 1] = tier3
        estimate[#estimate + 1] = reached
        -- daily completion of that stat's quests, scaled from today's difficulty
        local given, done = 0, 0
        local pool = MQ.Config.get().daily.pool or {}
        for _, r in ipairs(Bal.report()) do
            local t = template(r.tid)
            if t and t.stat == ref.stat and pool[r.tid] then
                given, done = given + r.given - r.swaps, done + r.done
            end
        end
        if given > 0 then
            local cur = MQ.Config.get().difficulty.mult or 1
            local rate = { key = "IGUI_MQ_Est_DailyRate" }
            for k, x in pairs(mults) do rate[k] = math.floor(math.min(1, done / given * cur / x) * 100 + 0.5) end
            estimate[#estimate + 1] = rate
        end
    end
    local changes = { { op = "set", path = "difficulty.preset", value = preset },
        { op = "set", path = "difficulty.mult", value = m } }
    return { changes = changes, rows = rows, estimate = estimate }
end

MQ.Server.defineAdmin("balance.report", { kind = "query",
    run = function(ctx) return true, { rows = Bal.report(ctx.now), minGiven = Bal.MIN_GIVEN } end })

MQ.Server.defineAdmin("diff.preview", { kind = "query", fields = { preset = "str", mult = "num?" },
    run = function(ctx)
        local res, c = Bal.diffPreview(ctx.args.preset, ctx.args.mult)
        if not res then return false, c end
        return true, res
    end })

return Bal
