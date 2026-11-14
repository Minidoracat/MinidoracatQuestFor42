-- MinidoracatQuest/Donate.lua: the server-wide donation (docs/ARCHITECTURE.md section 5.10; plan points-play-1112
-- claim 3, owner 2026-11-13). Settings are Config donate.*; live state is root.donate in Global ModData (it goes back
-- with the accounts after a crash). Players give balance points (command donate, Points.pay "donate"); the round
-- that reaches the target keeps what is over it for the next round and schedules one horde on the next weekday `day`
-- at `time` (sandbox TimezoneOffset, like the horde windows) at least 24 h away. leadMin before it, once no horde is
-- on and no full fund waits, the horde is planned through Hordes.plan (actor "donate", every kind's health and points
-- x hp, cap = the preset's cap x hp), not counted in the day's automatic or sponsored hordes. No spot or no plan:
-- hordeAt stays and it tries again. A round not full stays as it is (no refund, no reset).

if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Sandbox"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"
require "MinidoracatQuest/Hordes"

local D = MQ.Donate or {}
MQ.Donate = D
local CODE = MQ.Contract.CODE
local MIN, HOUR, DAY = 60000, 3600000, 86400000
D.RETRY_MS = MIN   -- a horde that could not be planned (no spot, no id file) is tried again this much later
D.retryAt = D.retryAt or 0   -- memory only

-- root.donate = { total, n (donations this round), by = { [user] = pts this round }, round, hordeAt, last = { round, n,
-- at (when it filled) } }
function D.root()
    local r = MQ.Store.root()
    if type(r.donate) ~= "table" then r.donate = { total = 0, n = 0, by = {}, round = 1 } end
    return r.donate
end

local function dirty() MQ.Sync.dirty(nil, "donate") end

-- the first weekday `day` (1 = Monday) at `time` in tz (hours east of UTC) that is DAY or more after now
function D.nextAt(now, day, time, tz)
    local d0, m = math.floor((now + tz * HOUR) / DAY), MQ.Hordes.hm(time) or 0
    for d = d0, d0 + 8 do
        local at = d * DAY - tz * HOUR + m * MIN
        if MQ.Hordes.weekday(d) == day and at >= now + DAY then return at end
    end
end

-- a full round with no horde waiting: the target comes off (the rest counts toward the next round), the round is
-- closed and its horde scheduled; everyone is told
function D.fill(d, dc, now, tz)
    if d.hordeAt ~= nil or d.total < dc.target then return end
    d.total = d.total - dc.target
    d.last = { round = d.round, n = d.n, at = now }
    d.round, d.n, d.by = d.round + 1, 0, {}
    d.hordeAt = D.nextAt(now, dc.day, dc.time, tz)
    MQ.Net.broadcast("toast", { kind = "donateDone", at = d.hordeAt })
end

-- Command donate: n points (>= min) toward the target the client saw (total). Returns true, { n } | false, code.
function D.donate(acc, user, n, total, now)
    local cfg = MQ.Config.get()
    local dc = cfg.donate
    if not dc.enabled or #cfg.hordes.spots == 0 then return false, CODE.DONATE_OFF end
    if n < dc.min then return false, CODE.BAD_ARGS end
    if total ~= dc.target then return false, CODE.PRICE_CHANGED end
    if not MQ.Points.pay(acc, user, n, "donate", nil) then return false, CODE.NOT_ENOUGH_POINTS end
    local d = D.root()
    d.total, d.n = d.total + n, d.n + 1
    d.by[user] = (d.by[user] or 0) + n
    MQ.Stats.add(user, "donate.points", n)
    D.fill(d, dc, now, MQ.Sandbox.get("TimezoneOffset"))
    dirty()
    return true, { n = n }
end

-- Hordes.tick, after the fund: the scheduled horde, planned leadMin before hordeAt (a late tick starts it lead minutes
-- from now) once no horde is on and no full fund waits; then the next round may already be full.
function D.tick(now, cfg, tz)
    local d = D.root()
    local dc, h = cfg.donate, MQ.Store.root().hordes
    if d.hordeAt == nil or now < d.hordeAt - dc.leadMin * MIN or now < D.retryAt then return end
    if h.cur ~= nil or (h.fund ~= nil and h.fund.state == "ready") then return end
    local cur = #cfg.hordes.spots > 0 and MQ.Hordes.plan(cfg.hordes, math.max(d.hordeAt, now + dc.leadMin * MIN),
        "donate", { preset = dc.preset, leadMin = dc.leadMin, waitMin = dc.waitMin }) or nil
    if cur == nil then
        D.retryAt = now + D.RETRY_MS
        return
    end
    MQ.Hordes.toughen(cur, dc.hp)
    d.hordeAt = nil
    D.fill(d, dc, now, tz)
    dirty()
end

-- Sync provider "donate": { on, total, target, min, mine, n, hordeAt, hp, last }; on = enabled with a horde spot
function D.state(acc, user, now)
    local cfg = MQ.Config.get()
    local dc, d = cfg.donate, D.root()
    return { on = dc.enabled == true and #cfg.hordes.spots > 0, total = d.total, target = dc.target, min = dc.min,
        mine = d.by[user] or 0, n = d.n, hordeAt = d.hordeAt, hp = dc.hp, last = d.last }
end

-- a player's donation; total = the target the client showed
MQ.Server.define("donate", { kind = "mutation", spend = true, fields = { n = "int", total = "int" },
    run = function(ctx)
        return D.donate(MQ.Store.account(ctx.user, true), ctx.user, ctx.args.n, ctx.args.total, ctx.now)
    end })

MQ.Sync.provider("donate", D.state)

return D
