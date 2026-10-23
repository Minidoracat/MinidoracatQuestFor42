-- MinidoracatQuest/Clock.lua: day and week boundaries (docs/ARCHITECTURE.md section 5.3, C34).
-- Same model as Economy ECRewards.lua resetShiftMs/dayKey/nextResetMs: a fixed shift (reset hour minus the
-- timezone) applied to epoch ms, never the host timezone (Kahlua os.date is fixed UTC).
-- With Economy installed and exposing v1.rewardDay(ms) -> "YYYYMMDD", nextResetMs (probed with type() ==
-- "function", not API_REVISION) its reward day wins, so quest days and Economy days flip together.
-- Weeks (ISO, Monday first) and season ends use the same shift: a week starts at Monday's reset.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Sandbox"

local Q = MinidoracatQuest
local K = Q.Clock or {}
Q.Clock = K

K.DAY_MS = 86400000
local DAY = K.DAY_MS

function K.now() return getTimestampMs() end

-- Economy's answer for ms, or nil when absent/invalid
local function economyDay(ms)
    local E = MinidoracatEconomy and MinidoracatEconomy.v1
    if type(E) ~= "table" or type(E.rewardDay) ~= "function" then return nil end
    local ok, key, nextMs = pcall(E.rewardDay, ms)
    if not ok or type(key) ~= "string" or not string.find(key, "^%d%d%d%d%d%d%d%d$") then return nil end
    if not Q.Contract.isFinite(nextMs) then return nil end
    return key, nextMs
end

function K.sandboxShiftMs()
    local hour = Q.Sandbox.get("ResetHour")
    local tz = Q.Sandbox.get("TimezoneOffset")
    return (hour * 60 - math.floor(tz * 60 + 0.5)) * 60000
end

-- Civil date from a day number (H. Hinnant; same as Economy EC.utcDate)
function K.civil(days)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = m > 2 and m - 3 or m + 9
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The shift that makes floor((ms - shift) / DAY) the local date. Economy's nextMs starts the day after its
-- key, so derive it from both: nextMs % DAY alone lands in [0, DAY) and, east of UTC, numbers every day one
-- too low (weeks then reset on Tuesday at UTC+8).
function K.shiftMs(ms)
    local key, nextMs = economyDay(ms or K.now())
    if not key then return K.sandboxShiftMs() end
    local y, m, d = tonumber(string.sub(key, 1, 4)), tonumber(string.sub(key, 5, 6)), tonumber(string.sub(key, 7, 8))
    return nextMs - (daysFromCivil(y, m, d) + 1) * DAY
end

local function pad2(n) return n < 10 and ("0" .. n) or tostring(n) end

-- local day number of ms (days since 1970-01-01 in the reset-shifted calendar)
local function localDay(ms)
    return math.floor((ms - K.shiftMs(ms)) / DAY)
end

function K.dayKey(ms)
    ms = ms or K.now()
    local key = economyDay(ms)
    if key then return string.sub(key, 1, 4) .. "-" .. string.sub(key, 5, 6) .. "-" .. string.sub(key, 7, 8) end
    local y, m, d = K.civil(math.floor((ms - K.sandboxShiftMs()) / DAY))
    return tostring(y) .. "-" .. pad2(m) .. "-" .. pad2(d)
end

function K.nextResetMs(ms)
    ms = ms or K.now()
    local _, nextMs = economyDay(ms)
    if nextMs then return nextMs end
    local shift = K.sandboxShiftMs()
    return math.floor((ms - shift) / DAY) * DAY + DAY + shift
end

function K.dayStartMs(ms)
    return K.nextResetMs(ms) - DAY
end

-- 1 = Monday .. 7 = Sunday (1970-01-01 was a Thursday)
function K.weekday(ms)
    return (localDay(ms or K.now()) + 3) % 7 + 1
end

function K.weekKey(ms)
    local days = localDay(ms or K.now())
    local wd = (days + 3) % 7 + 1
    local thu = days - (wd - 1) + 3
    local y = K.civil(thu)
    local week = math.floor((thu - daysFromCivil(y, 1, 1)) / 7) + 1
    return tostring(y) .. "-W" .. pad2(week)
end

-- the next Monday reset after ms
function K.weekResetMs(ms)
    ms = ms or K.now()
    local shift = K.shiftMs(ms)
    local days = math.floor((ms - shift) / DAY)
    local wd = (days + 3) % 7 + 1
    return (days + 8 - wd) * DAY + shift
end
