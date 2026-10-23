-- MinidoracatQuest/Audit.lua: audit trail (docs/ARCHITECTURE.md section 2, C36).
-- Shape from Safehouse Audit.lua: writeLog(logger, line) lands in <cachedir>/Logs/<start>_MinidoracatQuest.txt
-- with a timestamp per line; logs over 10MB are truncated, not rotated (ZLogger.java:95-101), so denials are
-- aggregated and flushed once a minute. Plus a 500-entry ring in the shared ModData table for the admin panel
-- (no SteamIDs there: clients can request the table).

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"

local Q = MinidoracatQuest
local A = Q.Audit or {}
Q.Audit = A
local U = Q.Util

A.LOGGER = "MinidoracatQuest"
A.denyAgg = A.denyAgg or {}   -- "actor|command|code" -> count
A.limited = A.limited or {}   -- key -> { at, suppressed }
A.overSeen = A.overSeen or {} -- "user|stat" -> { minute, item }

-- event: upper-case name; f = { actor, user, code, detail }
function A.write(event, f)
    f = f or {}
    writeLog(A.LOGGER, table.concat({ U.logSafe(event), U.logSafe(f.actor or "-"), U.logSafe(f.user or "-"),
        U.logSafe(f.code or "-"), U.logSafe(f.detail or "-") }, "\t"))
end

function A.deny(actor, command, code)
    local key = U.logSafe(actor or "?") .. "|" .. U.logSafe(command or "?") .. "|" .. U.logSafe(code or "?")
    A.denyAgg[key] = (A.denyAgg[key] or 0) + 1
end

function A.flush()
    local agg = A.denyAgg
    A.denyAgg = {}
    for key, count in pairs(agg) do
        local actor, command, code = string.match(key, "^(.-)|(.-)|(.*)$")
        A.write("DENY", { actor = actor, code = code, detail = command .. " x" .. tostring(count) })
    end
end

-- at most one line per key per window; the rest are counted
function A.throttled(key, windowMs, event, f, now)
    local s = A.limited[key]
    if s ~= nil and now - s.at < windowMs then
        s.suppressed = s.suppressed + 1
        return false
    end
    if s ~= nil and s.suppressed > 0 then
        f = f or {}
        f.detail = tostring(f.detail or "-") .. " suppressed=" .. tostring(s.suppressed)
    end
    A.limited[key] = { at = now, suppressed = 0 }
    A.write(event, f)
    return true
end

-- Ring entry in root.audit (500): { at, kind, actor, user, detail }. Returns the stored item.
function A.add(kind, actor, user, detail)
    local St = Q.Store
    local item = { at = getTimestampMs(), kind = kind, actor = actor, user = user, detail = detail }
    A.write(string.upper(tostring(kind)), { actor = actor, user = user,
        detail = type(detail) == "table" and U.encode(detail) or detail })
    if not St.ready() or St.readOnly then return item end
    local ring = St.root().audit
    ring.head = ring.head % Q.Contract.LIMIT.AUDIT_RING + 1
    ring.items[ring.head] = item
    return item
end

-- Newest first, optional filter(item) -> bool, at most max rows.
function A.recent(filter, max)
    local St = Q.Store
    local out = {}
    if not St.ready() then return out end
    local ring, size = St.root().audit, Q.Contract.LIMIT.AUDIT_RING
    for i = 0, size - 1 do
        local item = ring.items[(ring.head - 1 - i + size * 2) % size + 1]
        if item == nil then break end
        if filter == nil or filter(item) then
            out[#out + 1] = item
            if #out >= max then break end
        end
    end
    return out
end

-- Per-minute ceiling overflow (C36): one ring entry per account per stat per wall-clock minute; further drops in
-- the same minute add to that entry. Returns true when this call created the entry (new anomaly).
function A.over(user, stat, n, ceil)
    local now = getTimestampMs()
    local minute = math.floor(now / 60000)
    local key = user .. "|" .. stat
    local seen = A.overSeen[key]
    if seen ~= nil and seen.minute == minute then
        local d = seen.item.detail
        d.n = d.n + n
        return false
    end
    local item = A.add("over", nil, user, { stat = stat, n = n, ceil = ceil })
    A.overSeen[key] = { minute = minute, item = item }
    if Q.EventLog then Q.EventLog.write("over", user, { stat = stat, n = n, ceil = ceil }) end
    return true
end

function A.prune(now)
    local minute = math.floor(now / 60000)
    for k, s in pairs(A.overSeen) do
        if s.minute < minute then A.overSeen[k] = nil end
    end
end
