-- MinidoracatQuest/Points.lua: the three point numbers (docs/ARCHITECTURE.md section 5.5).
-- season = earned this season (boards), total = earned ever, balance = spendable (exchange).
-- kind "import" adds to total only; kind "season" (season rewards) adds to balance only; the rest add to all three.
-- Event multipliers are applied by the caller. pay / unpay: point sinks (bottom of the file).

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/EventLog"

local Q = MinidoracatQuest
local P = Q.Points or {}
Q.Points = P
local C = Q.Contract

local function valid(amount)
    return C.isFinite(amount) and amount > 0
end

-- true | false
function P.award(acc, user, amount, kind, ref, opts)
    if acc == nil or not valid(amount) or not C.POINT_KINDS[kind] or Q.Store.readOnly then return false end
    amount = math.floor(amount + 0.5)
    if amount <= 0 then return false end
    local pts = acc.points
    if kind == "import" then
        pts.total = pts.total + amount
    elseif kind == "season" then
        pts.balance = pts.balance + amount
    else
        pts.season = pts.season + amount
        pts.total = pts.total + amount
        pts.balance = pts.balance + amount
    end
    Q.EventLog.write("points", user, { kind = kind, ref = ref, n = amount })
    if kind ~= "import" and Q.Report then Q.Report.add("pts", kind, amount) end
    if Q.Boards and Q.Boards.dirty then Q.Boards.dirty("@points") end
    if Q.Sync and Q.Sync.dirty then Q.Sync.dirty(user, "points") end
    return true
end

-- balance only; true when it was enough. Only inside a command defined with spend = true (Server.onClientCommand
-- sets P.open while one runs): a new command that takes points without the flag fails here, at its first use,
-- instead of being a request the server would run twice.
function P.spend(acc, amount)
    if not P.open then error("Points.spend outside a spend command", 2) end
    if acc == nil or not C.isInt(amount) or amount <= 0 or Q.Store.readOnly then return false end
    if acc.points.balance < amount then return false end
    acc.points.balance = acc.points.balance - amount
    return true
end

function P.refund(acc, amount)
    if acc == nil or not C.isInt(amount) or amount <= 0 or Q.Store.readOnly then return false end
    acc.points.balance = acc.points.balance + amount
    return true
end

-- ===== point sinks (plan points-sinks 2026-11-12) =====
-- Spending on a shop item: balance only, plus the account's last P.SPENT_KEEP entries (newest first), the event log,
-- the report's spent column and a full state (the shop changes more than the points). Exchanges use spend / refund.
-- Only commands defined with spend = true may pay: Server runs each such request at most once (acc.spendSeq).
P.SPENT_KEEP = 10

local function record(acc, what, n, ref)
    local list = type(acc.spent) == "table" and acc.spent or {}
    table.insert(list, 1, { at = getTimestampMs(), what = what, n = n, ref = ref })
    while #list > P.SPENT_KEEP do table.remove(list) end
    acc.spent = list
end

-- true when the balance was enough (what: swap | shield | title | horde; ref: the swapped tid, the title id)
function P.pay(acc, user, amount, what, ref)
    if not P.spend(acc, amount) then return false end
    record(acc, what, -amount, ref)
    Q.EventLog.write("spend", user, { what = what, ref = ref, n = amount })
    if Q.Report then Q.Report.add("spent", what, amount) end
    if Q.Sync and Q.Sync.dirty then Q.Sync.dirty(user, "all") end
    return true
end

-- gives a payment back (a fund that did not fill or could not play, a sponsored horde that ended before a zombie
-- came): the report takes it off the horde column
function P.unpay(acc, user, amount, what, ref)
    if not P.refund(acc, amount) then return false end
    record(acc, what, amount, ref)
    Q.EventLog.write("spend", user, { what = what, ref = ref, n = -amount })
    if Q.Report then Q.Report.add("spent", "horde", -amount) end
    if Q.Sync and Q.Sync.dirty then Q.Sync.dirty(user, "all") end
    return true
end
