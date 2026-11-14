-- MinidoracatQuest/Donate.lua: the server-wide donation (docs/ARCHITECTURE.md section 5.10; plan points-play-1112
-- claim 3, owner 2026-11-13). Settings are Config donate.*; live state is root.donate in Global ModData (it goes back
-- with the accounts after a crash). Players give balance points (command donate, Points.pay "donate"); the round
-- that reaches the target keeps what is over it for the next round and schedules one horde on the next weekday `day`
-- at `time` (sandbox TimezoneOffset, like the horde windows) at least 24 h away, with a copy of the round's terms
-- (preset, hp, target, leadMin, waitMin: settings changed later do not touch it). leadMin before it, once no horde is
-- on and no full fund waits, the horde is planned through Hordes.plan (actor "donate", every kind's health and points
-- x hp, cap = the preset's cap x hp but under the round's target), not counted in the day's automatic or sponsored
-- hordes. No spot or no plan: hordeAt stays and it tries again. A planned one that ends before its first zombie goes
-- back on the calendar (D.unplayed). A round not full stays as it is (no refund, no reset).

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

-- root.donate = { total, n (donations this round), by = { [user] = pts this round }, round, hordeAt, next (the terms
-- of the round hordeAt plays, D.terms), later = { { at, terms } } | nil (rounds waiting behind hordeAt: a horde that
-- did not play while the next round was scheduled already), last = { round, n, at (when it filled) } }
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

-- the terms a full round plays on: a copy, so later settings cannot make it pay more than it took in
function D.terms(dc)
    return { preset = dc.preset, hp = dc.hp, target = dc.target, leadMin = dc.leadMin, waitMin = dc.waitMin }
end

-- a full round with no horde waiting: the target comes off (the rest counts toward the next round), the round is
-- closed and its horde scheduled with a copy of its terms; everyone is told
function D.fill(d, dc, now, tz)
    if d.hordeAt ~= nil or d.total < dc.target then return end
    d.total = d.total - dc.target
    d.last = { round = d.round, n = d.n, at = now }
    d.round, d.n, d.by = d.round + 1, 0, {}
    d.hordeAt, d.next = D.nextAt(now, dc.day, dc.time, tz), D.terms(dc)
    MQ.Net.broadcast("toast", { kind = "donateDone", at = d.hordeAt })
end

-- Hordes.finish: the donation's horde ended before its first zombie came (cancelled, nobody came, nothing could
-- spawn, a restart). Its round was paid for, so it goes back on the calendar with its terms (cur.donate; a horde
-- planned before the copies: today's): the next weekday `day` at `time` at least 24 h away, or, with the next round
-- scheduled already, the first one 24 h or more after the last one waiting. Everyone is told (donateMoved { at }).
function D.unplayed(cur, now)
    local d, dc, tz = D.root(), MQ.Config.get().donate, MQ.Sandbox.get("TimezoneOffset")
    local terms, at = cur.donate or D.terms(dc), nil
    if d.hordeAt == nil then
        at = D.nextAt(now, dc.day, dc.time, tz)
        d.hordeAt, d.next = at, terms
    else
        d.later = d.later or {}
        local after = #d.later > 0 and d.later[#d.later].at or d.hordeAt
        at = D.nextAt(math.max(now, after), dc.day, dc.time, tz)
        d.later[#d.later + 1] = { at = at, terms = terms }
    end
    MQ.Net.broadcast("toast", { kind = "donateMoved", at = at })
    dirty()
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

-- Hordes.tick, after the fund: the scheduled horde, planned on its terms (d.next; one scheduled before the copies:
-- today's) leadMin before hordeAt (a late tick starts it lead minutes from now) once no horde is on and no full fund
-- waits; its cap stays under the round's target. Then a round waiting behind it takes the slot, or the next round
-- may already be full.
function D.tick(now, cfg, tz)
    local d = D.root()
    local h = MQ.Store.root().hordes
    if d.hordeAt == nil or now < D.retryAt then return end
    local c = d.next or D.terms(cfg.donate)
    if now < d.hordeAt - c.leadMin * MIN then return end
    if h.cur ~= nil or (h.fund ~= nil and h.fund.state == "ready") then return end
    local cur = #cfg.hordes.spots > 0 and MQ.Hordes.plan(cfg.hordes, math.max(d.hordeAt, now + c.leadMin * MIN),
        "donate", { preset = c.preset, leadMin = c.leadMin, waitMin = c.waitMin }) or nil
    if cur == nil then
        D.retryAt = now + D.RETRY_MS
        return
    end
    MQ.Hordes.toughen(cur, c.hp)
    cur.cap = math.min(cur.cap, c.target - 1)
    cur.donate = c
    d.hordeAt, d.next = nil, nil
    if d.later ~= nil and #d.later > 0 then
        local w = table.remove(d.later, 1)
        d.hordeAt, d.next = w.at, w.terms
        if #d.later == 0 then d.later = nil end
    else
        d.later = nil
        D.fill(d, cfg.donate, now, tz)
    end
    dirty()
end

-- Sync provider "donate": { on, total, target, min, mine, n, hordeAt, hp, last }; on = enabled with a horde spot; hp =
-- the scheduled horde's (its copied terms) while one is, else today's
function D.state(acc, user, now)
    local cfg = MQ.Config.get()
    local dc, d = cfg.donate, D.root()
    local hp = d.hordeAt ~= nil and d.next ~= nil and d.next.hp or dc.hp
    return { on = dc.enabled == true and #cfg.hordes.spots > 0, total = d.total, target = dc.target, min = dc.min,
        mine = d.by[user] or 0, n = d.n, hordeAt = d.hordeAt, hp = hp, last = d.last }
end

-- a player's donation; total = the target the client showed
MQ.Server.define("donate", { kind = "mutation", spend = true, fields = { n = "int", total = "int" },
    run = function(ctx)
        return D.donate(MQ.Store.account(ctx.user, true), ctx.user, ctx.args.n, ctx.args.total, ctx.now)
    end })

MQ.Sync.provider("donate", D.state)

return D
