-- MinidoracatQuest/Contracts.lua: squad contracts (plan points-play 2026-11-12, revision 1113; docs/ARCHITECTURE.md
-- section 5.11). A player starts one of the fixed templates (Catalog.contracts) staking its price; others stake the
-- same to join within joinMin minutes; minSize .. maxSize members; maxSize starts it at once, the leader may start it
-- earlier. Running: perMember x members kills of the template's stat within limitMin minutes, everyone's kills added
-- up (horde kills too; the same stats as the daily quests). Met: each member gets returnPct % of the stake back
-- (Points.unpay), and one with sharePct % of perMember kills of their own also bonusPct % as earned points
-- (Points.award kind "contract") and a contract.wins. Not met: nothing back. A gathering contract that ends short of
-- minSize, or whose leader leaves, gives every stake back.
-- State in Global ModData (root.contracts = { seq, beat, list = { [id] = c }, log }), so a crash takes the stakes and
-- the contracts back together. The time the server was down does not count: every tick keeps beat, the first tick
-- after a start moves openUntil / endsAt on by the gap.
-- Prices and percentages are copied into the contract when it starts; later settings do not change it.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Net"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"

local MQ = MinidoracatQuest
local first = MQ.Contracts == nil
local Ct = MQ.Contracts or {}
MQ.Contracts = Ct
local CODE, U = MQ.Contract.CODE, MQ.Util

local MIN = 60000
Ct.LOG = 20        -- root.contracts.log: the last results, newest last
Ct.RECENT = 10     -- the records reply: this player's last ones
Ct.lastTick = 0

local function settings() return MQ.Config.get().contracts end

-- root.contracts; a read-only store gets an empty one that is not kept
local function data()
    local root = MQ.Store.root()
    local d = root.contracts
    if d == nil then
        d = { seq = 0, list = {}, log = {} }
        if not MQ.Store.readOnly then root.contracts = d end
    end
    return d
end

function Ct.statOf(tpl)
    for _, t in ipairs(MQ.Catalog.contracts) do
        if t.id == tpl then return t.stat end
    end
    return nil
end

-- contracts started today (the daily quests' day)
function Ct.today(acc, now)
    local d = acc.contractDay
    if type(d) == "table" and d.key == MQ.Clock.dayKey(now) then return d.n end
    return 0
end

local function countDay(acc, now)
    local key = MQ.Clock.dayKey(now)
    local d = acc.contractDay
    if type(d) ~= "table" or d.key ~= key then
        d = { key = key, n = 0 }
        acc.contractDay = d
    end
    d.n = d.n + 1
end

-- the contract the player is in, or nil (an id left over from a contract that is gone is dropped; a read-only store,
-- a newer schema, is left as it is)
local function mineOf(acc)
    local id = acc.contract
    if id == nil then return nil end
    local c = data().list[id]
    if c == nil then
        if not MQ.Store.readOnly then acc.contract = nil end
        return nil
    end
    return c
end

-- the gathering list goes to every open window, progress to the members only
local function dirtyAll() MQ.Sync.dirty(nil, "contracts") end
local function dirtyMembers(c)
    for _, u in ipairs(c.order) do MQ.Sync.dirty(u, "contracts") end
end

local function live()
    local n = 0
    for _ in pairs(data().list) do n = n + 1 end
    return n
end

-- drops c and every member's acc.contract: first, so an error further down cannot settle it again
local function detach(c)
    data().list[c.id] = nil
    for _, u in ipairs(c.order) do
        local acc = MQ.Store.account(u, false)
        if acc ~= nil and acc.contract == c.id then acc.contract = nil end
    end
end

-- every stake back (online or not); why: "small" (joinMin ended short of minSize) | "leader" (the leader left)
function Ct.disband(c, why)
    detach(c)
    for _, u in ipairs(c.order) do
        local acc = MQ.Store.account(u, false)
        if acc == nil or not MQ.Points.unpay(acc, u, c.stake, "contractRefund", c.tpl) then
            U.log("contract " .. c.id .. ": " .. c.stake .. " points not paid back to " .. U.logSafe(u))
        else
            MQ.Sync.toast(u, { kind = "contract", ev = "refund", tpl = c.tpl, pts = c.stake, why = why })
        end
    end
    dirtyAll()
end

-- gathering -> running: the target is set by the members now; each member's day count goes up
function Ct.begin(c, now)
    c.state, c.startMs, c.endsAt = "active", now, now + c.limitMin * MIN
    c.target, c.prog = c.perMember * c.size, 0
    for _, u in ipairs(c.order) do
        local acc = MQ.Store.account(u, false)
        if acc ~= nil then countDay(acc, now) end
    end
    MQ.EventLog.write("contract", c.leader, { ev = "start", id = c.id, tpl = c.tpl, size = c.size, target = c.target })
    dirtyAll()
end

-- met (won) or out of time. Each member: back = returnPct % of the stake when met, bonus = bonusPct % for one with
-- need = ceil(perMember x sharePct %) kills of their own. Offline members see it in their records.
function Ct.finish(c, won, now)
    detach(c)
    local need = math.ceil(c.perMember * c.sharePct / 100)
    local back = won and math.floor(c.stake * c.returnPct / 100) or 0
    local bonus = won and math.floor(c.stake * c.bonusPct / 100) or 0
    local d = data()
    d.log[#d.log + 1] = { id = c.id, tpl = c.tpl, size = c.size, target = c.target, prog = c.prog, won = won, at = now,
        startMs = c.startMs, stake = c.stake, need = need, back = back, bonus = bonus, members = c.members }
    while #d.log > Ct.LOG do table.remove(d.log, 1) end
    if MQ.Report then MQ.Report.add("contracts", c.tpl .. (won and ":won" or ":lost")) end
    MQ.EventLog.write("contract", c.leader, { ev = won and "won" or "lost", id = c.id, tpl = c.tpl, size = c.size,
        target = c.target, prog = c.prog })
    local mins = math.max(1, math.ceil((now - c.startMs) / MIN))
    for _, u in ipairs(c.order) do
        local acc = MQ.Store.account(u, false)
        local k = c.members[u] or 0
        if acc ~= nil and won then
            local full = k >= need
            if back > 0 then MQ.Points.unpay(acc, u, back, "contractBack", c.tpl) end
            if full and bonus > 0 and MQ.Points.award(acc, u, bonus, "contract", "contract:" .. c.id) then
                MQ.Points.note(acc, u, "contractBonus", bonus, c.tpl)
            end
            if full then MQ.Stats.add(u, "contract.wins", 1) end
            MQ.Sync.toast(u, { kind = "contract", ev = "won", tpl = c.tpl, size = c.size, target = c.target, mins = mins,
                back = back, bonus = full and bonus or 0, mine = k, need = need, full = full })
        elseif acc ~= nil then
            MQ.Sync.toast(u, { kind = "contract", ev = "lost", tpl = c.tpl, prog = c.prog, target = c.target,
                stake = c.stake })
        end
    end
    dirtyAll()
end

-- ===== commands =====

-- the checks contractStart and contractJoin share, in the contract's order (after "not found")
local function canJoin(acc, cfg, now)
    if mineOf(acc) ~= nil then return CODE.CONTRACT_IN end
    if Ct.today(acc, now) >= cfg.perDay then return CODE.CONTRACT_DAY end
    return nil
end

-- true, { id } | false, code
function Ct.start(acc, user, tpl, pay, now)
    local cfg = settings()
    if not cfg.enabled then return false, CODE.CONTRACT_OFF end
    local t, stat = cfg.list[tpl], Ct.statOf(tpl)
    if t == nil or stat == nil or not t.enabled then return false, CODE.NOT_FOUND end
    local bad = canJoin(acc, cfg, now)
    if bad then return false, bad end
    if live() >= cfg.maxActive then return false, CODE.CONTRACT_MAX end
    if pay ~= t.stake then return false, CODE.PRICE_CHANGED end
    if not MQ.Points.pay(acc, user, t.stake, "contract", tpl) then return false, CODE.NOT_ENOUGH_POINTS end
    local d = data()
    d.seq = d.seq + 1
    local c = { id = d.seq, tpl = tpl, stat = stat, stake = t.stake, perMember = t.perMember, limitMin = t.limitMin,
        returnPct = cfg.returnPct, bonusPct = cfg.bonusPct, sharePct = cfg.sharePct, leader = user, order = { user },
        members = { [user] = 0 }, size = 1, state = "open", openUntil = now + cfg.joinMin * MIN, prog = 0 }
    d.list[c.id] = c
    acc.contract = c.id
    if MQ.Report then MQ.Report.add("contracts", tpl .. ":open") end
    dirtyAll()
    return true, { id = c.id }
end

function Ct.join(acc, user, id, pay, now)
    local cfg = settings()
    if not cfg.enabled then return false, CODE.CONTRACT_OFF end
    local c = data().list[id]
    if c == nil or c.state ~= "open" or now >= c.openUntil then return false, CODE.NOT_FOUND end
    local bad = canJoin(acc, cfg, now)
    if bad then return false, bad end
    if c.size >= cfg.maxSize then return false, CODE.CONTRACT_FULL end
    if pay ~= c.stake then return false, CODE.PRICE_CHANGED end
    if not MQ.Points.pay(acc, user, c.stake, "contract", c.tpl) then return false, CODE.NOT_ENOUGH_POINTS end
    c.order[#c.order + 1] = user
    c.members[user] = 0
    c.size = c.size + 1
    acc.contract = c.id
    if c.size >= cfg.maxSize then Ct.begin(c, now) else dirtyAll() end
    return true
end

-- gathering only; the leader leaving ends it for everyone
function Ct.leave(acc, user, id)
    local c = data().list[id]
    if c == nil or c.members[user] == nil then return false, CODE.NOT_FOUND end
    if c.state ~= "open" then return false, CODE.FORBIDDEN end
    if c.leader == user then
        Ct.disband(c, "leader")
        return true
    end
    for i, u in ipairs(c.order) do
        if u == user then
            table.remove(c.order, i)
            break
        end
    end
    c.members[user] = nil
    c.size = c.size - 1
    acc.contract = nil
    MQ.Points.unpay(acc, user, c.stake, "contractRefund", c.tpl)
    dirtyAll()
    return true
end

function Ct.go(user, id, now)
    local c = data().list[id]
    if c == nil or c.state ~= "open" then return false, CODE.NOT_FOUND end
    if c.leader ~= user then return false, CODE.FORBIDDEN end
    if c.size < settings().minSize then return false, CODE.CONTRACT_SMALL end
    Ct.begin(c, now)
    return true
end

-- ===== progress (Stats hot path: a player without a contract costs one field read) =====

function Ct.onStat(acc, user, stat, delta, opts)
    local id = acc.contract
    if id == nil or (opts and opts.quiet) then return end
    local c = data().list[id]
    if c == nil or c.state ~= "active" or c.stat ~= stat or delta <= 0 or c.members[user] == nil then return end
    local now = getTimestampMs()
    if now >= c.endsAt then return end   -- out of time: the next tick settles it
    c.prog = c.prog + delta
    c.members[user] = c.members[user] + delta
    if c.prog >= c.target then Ct.finish(c, true, now) else dirtyMembers(c) end
end

-- ===== tick =====

function Ct.tick(now)
    if now - Ct.lastTick < 1000 or not MQ.Store.ready() or MQ.Store.readOnly then return end
    Ct.lastTick = now
    local d = data()
    if not Ct.booted then
        Ct.booted = true
        -- the server was down from the last beat (a save) to now: that time does not count
        local down = d.beat ~= nil and now - d.beat or 0
        if down > 0 then
            for _, c in pairs(d.list) do
                c.openUntil = c.openUntil + down
                if c.endsAt ~= nil then c.endsAt = c.endsAt + down end
            end
            dirtyAll()
        end
    end
    d.beat = now
    local due = {}
    for _, c in pairs(d.list) do
        if (c.state == "open" and now >= c.openUntil) or (c.state == "active" and now >= c.endsAt) then due[#due + 1] = c end
    end
    U.sort(due, function(a, b) return a.id < b.id end)
    local minSize = settings().minSize
    for _, c in ipairs(due) do
        if c.state == "active" then
            Ct.finish(c, c.prog >= c.target, now)
        elseif c.size >= minSize then
            Ct.begin(c, now)
        else
            Ct.disband(c, "small")
        end
    end
end

-- ===== what players see =====

-- a member as the horde results name them (Hordes.result): an anonymous account shows no name, admins get it in `a`
local function who(u, viewer, admin)
    local acc = MQ.Store.account(u, false)
    if u == viewer then return { me = true } end
    if acc ~= nil and acc.anon then return { anon = true, a = admin and u or nil } end
    return { n = u }
end

local function isAdmin(user)
    local p = MQ.Net.playerOf(user)
    return p ~= nil and MQ.Server.isAdmin(p)
end

-- Sync provider "contracts": { on, perDay, today, returnPct, bonusPct, sharePct, joinMin, minSize, maxSize,
-- tpls = { { id, stake, perMember, limitMin } } (the enabled ones, Catalog order), open = { gathering ones the player
-- is not in }, mine = the player's own with every member's kills }
function Ct.state(acc, user, now)
    local cfg, d = settings(), data()
    local admin = isAdmin(user)
    local out = { on = cfg.enabled, perDay = cfg.perDay, today = Ct.today(acc, now), returnPct = cfg.returnPct,
        bonusPct = cfg.bonusPct, sharePct = cfg.sharePct, joinMin = cfg.joinMin, minSize = cfg.minSize,
        maxSize = cfg.maxSize, tpls = {}, open = {} }
    for _, t in ipairs(MQ.Catalog.contracts) do
        local s = cfg.list[t.id]
        if s.enabled then
            out.tpls[#out.tpls + 1] = { id = t.id, stake = s.stake, perMember = s.perMember, limitMin = s.limitMin }
        end
    end
    for _, c in pairs(d.list) do
        if c.state == "open" and c.members[user] == nil then
            out.open[#out.open + 1] = { id = c.id, tpl = c.tpl, size = c.size, leader = who(c.leader, user, admin),
                openUntil = c.openUntil, stake = c.stake, perMember = c.perMember, limitMin = c.limitMin,
                returnPct = c.returnPct, bonusPct = c.bonusPct, sharePct = c.sharePct }
        end
    end
    U.sort(out.open, function(a, b) return a.id < b.id end)
    local c = mineOf(acc)
    if c ~= nil then
        local members = {}
        for _, u in ipairs(c.order) do
            local m = who(u, user, admin)
            m.k, m.lead = c.members[u] or 0, u == c.leader or nil
            members[#members + 1] = m
        end
        out.mine = { id = c.id, tpl = c.tpl, state = c.state, size = c.size, lead = c.leader == user,
            openUntil = c.openUntil, startMs = c.startMs, endsAt = c.endsAt, target = c.target, prog = c.prog,
            stake = c.stake, perMember = c.perMember, limitMin = c.limitMin, returnPct = c.returnPct,
            bonusPct = c.bonusPct, sharePct = c.sharePct, members = members }
    end
    return out
end

-- the records reply: the player's last results, newest first { at, tpl, size, won, prog, target, back, bonus, mine }
function Ct.recent(user)
    local out, log = {}, data().log
    for i = #log, 1, -1 do
        local e = log[i]
        local k = e.members[user]
        if k ~= nil then
            local full = e.won and k >= e.need
            out[#out + 1] = { at = e.at, tpl = e.tpl, size = e.size, won = e.won, prog = e.prog, target = e.target,
                back = e.back, bonus = full and e.bonus or 0, mine = k }
            if #out >= Ct.RECENT then break end
        end
    end
    return out
end

MQ.Server.define("contractStart", { kind = "mutation", spend = true, fields = { tpl = "str", pay = "int" },
    run = function(ctx)
        return Ct.start(MQ.Store.account(ctx.user, true), ctx.user, ctx.args.tpl, ctx.args.pay, ctx.now)
    end })

MQ.Server.define("contractJoin", { kind = "mutation", spend = true, fields = { id = "int", pay = "int" },
    run = function(ctx)
        return Ct.join(MQ.Store.account(ctx.user, true), ctx.user, ctx.args.id, ctx.args.pay, ctx.now)
    end })

MQ.Server.define("contractLeave", { kind = "mutation", fields = { id = "int" },
    run = function(ctx)
        local acc = MQ.Store.account(ctx.user, false)
        if acc == nil then return false, CODE.NOT_FOUND end
        return Ct.leave(acc, ctx.user, ctx.args.id)
    end })

MQ.Server.define("contractGo", { kind = "mutation", fields = { id = "int" },
    run = function(ctx) return Ct.go(ctx.user, ctx.args.id, ctx.now) end })

MQ.Stats.listen("contracts", Ct.onStat)
MQ.Sync.provider("contracts", Ct.state)

if first then
    Events.OnTickEvenPaused.Add(function() MinidoracatQuest.Contracts.tick(getTimestampMs()) end)
end

return Ct
