-- MinidoracatQuest/Points.lua: the three point numbers (docs/ARCHITECTURE.md section 5.5).
-- season = earned this season (boards), total = earned ever, balance = spendable (exchange).
-- kind "import" adds to total only; kind "season" (season rewards) adds to balance only; the rest add to all three.
-- Event multipliers are applied by the caller.

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

-- balance only; true when it was enough
function P.spend(acc, amount)
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
