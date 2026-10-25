-- MinidoracatQuestFor42 - points -> survivor coins through MinidoracatEconomy.v1 (optional, MP only).
-- Points are held before the credit; the same exchange always keeps the same requestId, so a retry
-- never pays twice (spec A.11, C2, C17, C33).
if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Audit"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"

local first = MQ.Exchange == nil
local X = MQ.Exchange or {}
MQ.Exchange = X

X.RETRY = { cap_exceeded = true, rate_limited = true, not_ready = true }
X.RETRY_MS = 3600000
X.PER_TICK = 10                       -- Economy allows 20 calls per source per tick
X.KEEP_DAYS = 7
X.LOG = 10                            -- finished exchanges kept per player for my records (acc.ex.log, newest first)
-- Economy's ledger shows a source's reason code through IGUI_MinidoracatEconomy_Reason_<code> when some mod ships
-- that key (ECWidgets U.reasonText); ours is in this mod's Translate files. The mq_ prefix keeps it apart from
-- other sources' codes, which share that key space.
X.REASON = "mq_exchange"

local function code(name) return MQ.Contract.CODE[name] end

function X.init()
    X.src = nil
    local E = MinidoracatEconomy and MinidoracatEconomy.v1
    if not isServer() or not (E and E.API_MAJOR == 1 and type(E.registerSource) == "function") then return end
    local ok, src = pcall(E.registerSource, { modId = MQ.Contract.MOD_ID, nameKey = "IGUI_MQ_Name",
        displayName = { EN = "Quests & Achievements" }, currencies = { "survivor" }, reasonCodes = { X.REASON } })
    if ok and type(src) == "table" and type(src.credit) == "function" then
        X.src = src
        MQ.Util.log("Economy exchange source registered")
    else
        MQ.Util.log("Economy exchange unavailable: " .. MQ.Util.logSafe(src))
    end
end

function X.available()
    return X.src ~= nil and isServer() == true
end

local function today(acc, day)
    local ex = acc.ex
    if ex.day ~= day then ex.day, ex.used = day, 0 end
    return ex
end

local function bookCoins(coins, now)
    local root = MQ.Store.root()
    local e = root.exchange
    local day = MQ.Clock.dayKey(now)
    if e.day ~= day then
        if e.day then
            table.insert(e.days, 1, { day = e.day, coins = e.coins or 0 })
            while #e.days > X.KEEP_DAYS do table.remove(e.days) end
        end
        e.day, e.coins = day, 0
    end
    e.coins = (e.coins or 0) + coins
    if MQ.Report then MQ.Report.add("coins", nil, coins) end
end

local function finish(acc, user, row, state, now)
    row.state = state
    MQ.EventLog.write("exchange", user, { seq = row.seq, amount = row.amount, coins = row.coins, state = state })
    if state == "paid" then bookCoins(row.coins, now) end
    local log = acc.ex.log or {}
    table.insert(log, 1, { at = now, amount = row.amount, coins = row.coins, state = state })
    while #log > X.LOG do table.remove(log) end
    acc.ex.log = log
end

-- Credit one held row: "paid" | "queued" | "refunded" (the caller removes it from the queue).
function X.send(acc, user, row, now)
    row.tries = (row.tries or 0) + 1
    local ok, res = pcall(X.src.credit, user, "survivor", row.coins,
        { requestId = "ex:" .. user .. ":" .. row.seq, reasonCode = X.REASON })
    if not ok then res = nil end
    if type(res) == "table" and res.ok then
        finish(acc, user, row, "paid", now)
        return "paid"
    end
    if type(res) ~= "table" or X.RETRY[res.error] then
        row.state = "queued"
        return "queued"
    end
    MQ.Points.refund(acc, row.amount)
    if acc.ex.day == row.day then acc.ex.used = math.max(0, acc.ex.used - row.amount) end
    MQ.Audit.add("exchange_refused", nil, user, { seq = row.seq, error = tostring(res.error) })
    finish(acc, user, row, "refunded", now)
    return "refunded"
end

-- -> ok, code, { state, coins }
function X.request(acc, user, amount)
    if not X.available() then return false, code("ECONOMY_MISSING") end
    local cfg = MQ.Config.get().exchange
    if not cfg.enabled then return false, code("EXCHANGE_OFF") end
    if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < cfg.min then
        return false, code("EXCHANGE_MIN")
    end
    local now = MQ.Clock.now()
    local day = MQ.Clock.dayKey(now)
    local ex = today(acc, day)
    if ex.used + amount > cfg.perDay then return false, code("EXCHANGE_DAY_LIMIT") end
    local coins = math.floor(amount * cfg.rate)
    if coins < 1 then return false, code("EXCHANGE_MIN") end
    if not MQ.Points.spend(acc, amount) then return false, code("NOT_ENOUGH_POINTS") end
    ex.used = ex.used + amount
    ex.seq = (ex.seq or 0) + 1
    local row = { seq = ex.seq, amount = amount, coins = coins, state = "held", at = now, tries = 0, day = day }
    local state = X.send(acc, user, row, now)
    if state == "queued" then
        ex.queue = ex.queue or {}
        ex.queue[#ex.queue + 1] = row
        MQ.Store.root().exchange.pending = MQ.Store.root().exchange.pending or {}
        MQ.Store.root().exchange.pending[user] = true
        MQ.EventLog.write("exchange", user, { seq = row.seq, amount = amount, coins = coins, state = "queued" })
    end
    MQ.Sync.dirty(user, "points")
    return true, code("OK"), { state = state, coins = coins }
end

-- ---------- retry: hourly and right after the (Economy) day changes ----------

X.nextMs = X.nextMs or 0
X.work = X.work or {}

-- Retries this user's queued rows not yet tried in this round; returns the budget left and
-- whether the user still has untried rows.
local function retryUser(user, budget, now)
    local acc = MQ.Store.account(user, false)
    local pending = MQ.Store.root().exchange.pending
    if not acc or not acc.ex.queue or #acc.ex.queue == 0 then
        pending[user] = nil
        return budget, false
    end
    local keep, more = {}, false
    for _, row in ipairs(acc.ex.queue) do
        if row.round ~= X.round and budget > 0 then
            budget = budget - 1
            row.round = X.round
            local state = X.send(acc, user, row, now)
            if state == "queued" then
                keep[#keep + 1] = row
            else
                MQ.Sync.toast(user, { kind = "exchange", state = state, coins = row.coins })
                MQ.Sync.dirty(user, "points")
                MQ.Sync.dirty(user, "exchange")   -- queued total and history (a full state for an open window)
            end
        else
            if row.round ~= X.round then more = true end
            keep[#keep + 1] = row
        end
    end
    acc.ex.queue = keep
    if #keep == 0 then pending[user] = nil end
    return budget, more
end

function X.tick(now)
    if not X.available() or not MQ.Store.ready() then return end
    local e = MQ.Store.root().exchange
    e.pending = e.pending or {}
    local day = MQ.Clock.dayKey(now)
    if #X.work == 0 and (now >= X.nextMs or (X.lastDay and X.lastDay ~= day)) then
        X.nextMs, X.lastDay, X.round = now + X.RETRY_MS, day, now
        for user in pairs(e.pending) do X.work[#X.work + 1] = user end
    end
    X.lastDay = X.lastDay or day
    local budget = X.PER_TICK
    while budget > 0 and #X.work > 0 do
        local more
        budget, more = retryUser(X.work[#X.work], budget, now)
        if not more then table.remove(X.work) end
    end
end

-- ---------- status ----------

function X.status(now)
    local cfg = MQ.Config.get().exchange
    local e = MQ.Store.root().exchange
    local todayCoins = e.day == MQ.Clock.dayKey(now) and e.coins or 0
    -- the 7 calendar days before today, a day without exchanges counting 0; the day still in e.day/e.coins (rolled
    -- into e.days only at the next exchange) counts too. No paid day in the window: today's coins.
    local byDay = {}
    for _, d in ipairs(e.days or {}) do byDay[d.day] = d.coins end
    if e.day then byDay[e.day] = e.coins or 0 end
    local sum, any = 0, false
    for k = 1, X.KEEP_DAYS do
        local c = byDay[MQ.Clock.dayKey(now - k * 86400000)]
        if c then sum, any = sum + c, true end
    end
    local estimate = any and sum / X.KEEP_DAYS or todayCoins
    local mult = 1
    local events = {}
    for _, ev in ipairs(MQ.Store.root().events or {}) do
        events[#events + 1] = { id = ev.id, name = ev.name, theme = ev.theme, mult = ev.mult, startMs = ev.startMs, endMs = ev.endMs }
        if ev.startMs <= now + 86400000 and now < ev.endMs and ev.mult > mult then mult = ev.mult end
    end
    estimate = math.floor(estimate * mult + 0.5)
    -- Economy's view of this source (EC.v1.sourceStatus, read-only; nil when absent or not registered)
    local E = MinidoracatEconomy and MinidoracatEconomy.v1
    local s = nil
    if type(E) == "table" and type(E.sourceStatus) == "function" then
        local ok, res = pcall(E.sourceStatus, MQ.Contract.MOD_ID)
        if ok and type(res) == "table" then s = res end
    end
    local ecCap = s and s.dailyMintCap or nil
    local ecEnabled = s and s.enabled
    local warn = nil
    if type(E) == "table" and ecCap == nil then warn = "unknown"
    elseif ecEnabled == false then warn = "disabled"
    elseif ecCap == 0 then warn = "cap_zero"
    elseif ecCap and estimate > ecCap then warn = "over_cap" end
    return { enabled = cfg.enabled, rate = cfg.rate, perDay = cfg.perDay, min = cfg.min, todayCoins = todayCoins,
        estimate = estimate, ecAvailable = X.available(), ecCap = ecCap, ecUsed = s and s.mintToday or nil,
        ecEnabled = ecEnabled, warn = warn, events = events }
end

function X.stateFor(acc, user, now)
    local cfg = MQ.Config.get().exchange
    local used = acc.ex.day == MQ.Clock.dayKey(now) and acc.ex.used or 0
    local queued, hist = 0, {}
    -- history: the rows still queued (newest first, at = when asked), then the finished ones (at = when they ended)
    local q = acc.ex.queue or {}
    for i = #q, 1, -1 do
        local row = q[i]
        queued = queued + row.amount
        if #hist < X.LOG then hist[#hist + 1] = { at = row.at, amount = row.amount, coins = row.coins, state = "queued" } end
    end
    for _, row in ipairs(acc.ex.log or {}) do
        if #hist >= X.LOG then break end
        hist[#hist + 1] = row
    end
    return { available = X.available(), enabled = cfg.enabled, rate = cfg.rate, perDay = cfg.perDay, used = used,
        min = cfg.min, queued = queued, hist = hist }
end

MQ.Server.define("exchange", { kind = "mutation", fields = { amount = "int" }, cooldownMs = 3000,
    run = function(ctx)
        local acc = MQ.Store.account(ctx.user, true)
        local ok, c, data = X.request(acc, ctx.user, ctx.args.amount)
        if not ok then return false, c end
        return true, data
    end })

MQ.Server.defineAdmin("ex.status", { kind = "query",
    run = function(ctx) return true, X.status(ctx.now) end })

MQ.Sync.provider("exchange", X.stateFor)

if first then
    Events.OnServerStarted.Add(function() MQ.Exchange.init() end)
    Events.OnTickEvenPaused.Add(function() MQ.Exchange.tick(getTimestampMs()) end)
end

return X
