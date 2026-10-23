-- MinidoracatQuest/EventLog.lua: daily event file Lua/MinidoracatQuest/<serverKey>/events-YYYYMMDD.json
-- (docs/ARCHITECTURE.md C14, section 3.5): one JSON object per line {"t":ms,"k":kind,"u":user,...}.
-- Lines are buffered and appended every FLUSH_MS from the server tick, never written inside game event handlers.
-- A failed append keeps the buffer (bounded by MAX_BUFFER, oldest dropped and counted).

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"

local Q = MinidoracatQuest
local L = Q.EventLog or {}
Q.EventLog = L
local U = Q.Util

-- A dedicated server has no Lua event on shutdown (OnSave/OnPostSave fire only in GameWindow, i.e. client/SP), so
-- whatever is still buffered at RCON quit is lost: keep the window short. Empty buffers cost nothing (flush returns).
-- (E2E persist-mp 2026-10-23: with 10 s an event written a few seconds before quit was missing after the restart.)
L.FLUSH_MS = 1000
L.MAX_BUFFER = 2000
L.buffer = L.buffer or {}   -- { day = "YYYYMMDD", line }
L.dropped = L.dropped or 0

function L.write(kind, user, fields)
    local t = getTimestampMs()
    local parts = { '{"t":', string.format("%.0f", t), ',"k":', U.encode(tostring(kind)) }
    if user ~= nil then
        parts[#parts + 1] = ',"u":'
        parts[#parts + 1] = U.encode(tostring(user))
    end
    for k, v in pairs(fields or {}) do
        local text = U.encode(v)
        if type(k) == "string" and text ~= nil then
            parts[#parts + 1] = "," .. U.encode(k) .. ":" .. text
        end
    end
    parts[#parts + 1] = "}"
    local buf = L.buffer
    if #buf >= L.MAX_BUFFER then
        table.remove(buf, 1)
        L.dropped = L.dropped + 1
    end
    buf[#buf + 1] = { day = string.gsub(Q.Clock.dayKey(t), "%-", ""), line = table.concat(parts) }
end

function L.flush()
    local buf = L.buffer
    if #buf == 0 then return true end
    local byDay, order = {}, {}
    for _, e in ipairs(buf) do
        if byDay[e.day] == nil then byDay[e.day] = {}; order[#order + 1] = e.day end
        local lines = byDay[e.day]
        lines[#lines + 1] = e.line
    end
    local keep = {}
    for _, day in ipairs(order) do
        if not Q.Store.writeLines(Q.Store.path("events-" .. day .. ".json"), byDay[day], true) then
            for _, line in ipairs(byDay[day]) do keep[#keep + 1] = { day = day, line = line } end
        end
    end
    L.buffer = keep
    if #keep > 0 then
        Q.Audit.throttled("EVENTLOG_WRITE", 600000, "FILE_ERROR", { detail = "events buffered=" .. #keep }, getTimestampMs())
    end
    return #keep == 0
end

function L.tick(now)
    if L.lastFlush ~= nil and now - L.lastFlush < L.FLUSH_MS then return end
    L.lastFlush = now
    L.flush()
end
