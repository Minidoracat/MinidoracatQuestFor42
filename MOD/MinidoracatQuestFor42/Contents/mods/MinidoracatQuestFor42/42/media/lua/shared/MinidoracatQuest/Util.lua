-- MinidoracatQuest/Util.lua: pure helpers for both sides (docs/ARCHITECTURE.md section 2).
-- Kahlua: no next/xpcall/math.random/bit operators, table.sort is a recursive quicksort (use Util.sort).
-- The JSON decoder reports bad input by return value, never error(): pcall'd errors still reach the
-- engine's error list (pz-family-docs pitfalls.md:71).

MinidoracatQuest = MinidoracatQuest or {}
require "MinidoracatQuest/Contract"
local Q = MinidoracatQuest
local U = Q.Util or {}
Q.Util = U
local C = Q.Contract

function U.log(msg)
    print(C.LOG_PREFIX .. tostring(msg))
end

-- Log field: no newlines, tabs or square brackets (forged columns, pitfalls.md "Log").
function U.logSafe(v)
    return (string.gsub(tostring(v), "[%c%[%]]", "_"))
end

-- 32-bit string hash (h * 31 + byte); every step stays below 2^53, so doubles are exact.
function U.hash(s)
    s = tostring(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 4294967296 end
    return h
end

-- Seeded generator (Park-Miller, 48271 * state < 2^47 stays exact). r:int(a, b) is inclusive.
local Rng = {}
Rng.__index = Rng
function Rng:next()
    self.s = (self.s * 48271) % 2147483647
    return self.s
end
function Rng:int(a, b)
    if b <= a then return a end
    return a + self:next() % (b - a + 1)
end
function U.rng(seed)
    local n = type(seed) == "number" and seed or U.hash(seed)
    if n * 0 ~= 0 then n = 0 end
    return setmetatable({ s = math.floor(math.abs(n)) % 2147483646 + 1 }, Rng)
end

function U.pick(list, rng)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[rng:int(1, #list)]
end

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.round(v)
    return math.floor(v + 0.5)
end

function U.copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = U.copy(x) end
    return out
end

-- Stable bottom-up merge sort (Safehouse Contract.lua MSH.sortSafe). less(a, b) true only when a must precede b.
function U.sort(list, less)
    local n = #list
    if n < 2 then return list end
    local buf, width = {}, 1
    while width < n do
        local i = 1
        while i <= n do
            local midEnd = math.min(i + width - 1, n)
            local hiEnd = math.min(i + width * 2 - 1, n)
            local a, b, k = i, midEnd + 1, i
            while a <= midEnd and b <= hiEnd do
                if less(list[b], list[a]) then buf[k] = list[b]; b = b + 1
                else buf[k] = list[a]; a = a + 1 end
                k = k + 1
            end
            while a <= midEnd do buf[k] = list[a]; a = a + 1; k = k + 1 end
            while b <= hiEnd do buf[k] = list[b]; b = b + 1; k = k + 1 end
            i = i + width * 2
        end
        for j = 1, n do list[j] = buf[j] end
        width = width * 2
    end
    return list
end

function U.split(s, sep)
    local out = {}
    for part in string.gmatch(s, "[^" .. sep .. "]+") do
        local t = string.gsub(string.gsub(part, "^%s+", ""), "%s+$", "")
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end

-- ===== JSON =====
-- encode: tables whose keys are exactly 1..#t (and #t > 0) are arrays, everything else objects
-- (number keys become strings). decode turns object keys that are plain integers back into numbers,
-- so sparse maps such as titles = { [4] = "x" } survive a round trip.

local function numText(n)
    if n * 0 ~= 0 then return "null" end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%.0f", n) end
    local s = string.gsub(string.format("%.6f", n), "0+$", "")
    return (string.gsub(s, "%.$", ""))
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function strText(s)
    return '"' .. string.gsub(s, '[%c"\\]', function(c)
        return ESC[c] or string.format("\\u%04x", string.byte(c))
    end) .. '"'
end

local function arrayLen(t)
    local n = #t
    if n == 0 then return nil end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then return nil end
        count = count + 1
    end
    if count ~= n then return nil end
    return n
end

local function enc(v, out, depth)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t == "number" then out[#out + 1] = numText(v)
    elseif t == "string" then out[#out + 1] = strText(v)
    elseif t == "table" then
        if depth > C.LIMIT.JSON_DEPTH then return false end
        local n = arrayLen(v)
        if n then
            out[#out + 1] = "["
            for i = 1, n do
                if i > 1 then out[#out + 1] = "," end
                if not enc(v[i], out, depth + 1) then return false end
            end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for k, x in pairs(v) do
                local kt = type(k)
                if kt ~= "string" and kt ~= "number" then return false end
                if not first then out[#out + 1] = "," end
                first = false
                out[#out + 1] = strText(kt == "number" and numText(k) or k)
                out[#out + 1] = ":"
                if not enc(x, out, depth + 1) then return false end
            end
            out[#out + 1] = "}"
        end
    else
        return false
    end
    return true
end

-- Returns the JSON text, or nil when v holds functions/userdata or nests too deep.
function U.encode(v)
    local out = {}
    if not enc(v, out, 1) then return nil end
    return table.concat(out)
end

local function utf8char(cp)
    if cp < 128 then return string.char(cp) end
    if cp < 2048 then return string.char(192 + math.floor(cp / 64), 128 + cp % 64) end
    if cp < 65536 then
        return string.char(224 + math.floor(cp / 4096), 128 + math.floor(cp / 64) % 64, 128 + cp % 64)
    end
    return string.char(240 + math.floor(cp / 262144), 128 + math.floor(cp / 4096) % 64,
        128 + math.floor(cp / 64) % 64, 128 + cp % 64)
end

-- Decoder state: p = position; every reader returns value, ok.
local D = {}

local function skip(s, p)
    local _, e = string.find(s, "^[ \t\r\n]*", p)
    return e + 1
end

function D.str(s, p)
    -- s[p] == '"'
    local parts, i = {}, p + 1
    while true do
        local a, b = string.find(s, '^[^"\\%c]+', i)
        if a then parts[#parts + 1] = string.sub(s, a, b); i = b + 1 end
        local c = string.sub(s, i, i)
        if c == '"' then return table.concat(parts), i + 1 end
        if c ~= "\\" then return nil end
        local e = string.sub(s, i + 1, i + 1)
        local simple = ({ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[e]
        if simple then
            parts[#parts + 1] = simple
            i = i + 2
        elseif e == "u" then
            local hex = string.match(s, "^%x%x%x%x", i + 2)
            if not hex then return nil end
            local cp = tonumber(hex, 16)
            i = i + 6
            if cp >= 55296 and cp <= 56319 then
                local lo = string.match(s, "^\\u(%x%x%x%x)", i)
                local lv = lo and tonumber(lo, 16)
                if not lv or lv < 56320 or lv > 57343 then return nil end
                cp = 65536 + (cp - 55296) * 1024 + (lv - 56320)
                i = i + 6
            end
            parts[#parts + 1] = utf8char(cp)
        else
            return nil
        end
    end
end

function D.value(s, p, depth)
    if depth > C.LIMIT.JSON_DEPTH then return nil end
    p = skip(s, p)
    local c = string.sub(s, p, p)
    if c == "{" then
        local obj = {}
        p = skip(s, p + 1)
        if string.sub(s, p, p) == "}" then return obj, p + 1 end
        while true do
            if string.sub(s, p, p) ~= '"' then return nil end
            local k, np = D.str(s, p)
            if not k then return nil end
            p = skip(s, np)
            if string.sub(s, p, p) ~= ":" then return nil end
            local v, vp = D.value(s, p + 1, depth + 1)
            if vp == nil then return nil end
            if string.find(k, "^%-?%d+$") and #k <= 15 then k = tonumber(k) end
            obj[k] = v
            p = skip(s, vp)
            local d = string.sub(s, p, p)
            if d == "}" then return obj, p + 1 end
            if d ~= "," then return nil end
            p = skip(s, p + 1)
        end
    elseif c == "[" then
        local arr = {}
        p = skip(s, p + 1)
        if string.sub(s, p, p) == "]" then return arr, p + 1 end
        while true do
            local v, vp = D.value(s, p, depth + 1)
            if vp == nil then return nil end
            arr[#arr + 1] = v
            p = skip(s, vp)
            local d = string.sub(s, p, p)
            if d == "]" then return arr, p + 1 end
            if d ~= "," then return nil end
            p = p + 1
        end
    elseif c == '"' then
        return D.str(s, p)
    elseif string.sub(s, p, p + 3) == "true" then return true, p + 4
    elseif string.sub(s, p, p + 4) == "false" then return false, p + 5
    elseif string.sub(s, p, p + 3) == "null" then return nil, p + 4
    end
    local num = string.match(s, "^%-?%d+%.?%d*[eE]?[%+%-]?%d*", p)
    if num == nil or num == "" then return nil end
    local n = tonumber(num)
    if n == nil or n * 0 ~= 0 then return nil end
    return n, p + #num
end

-- Returns value or nil, "BAD_JSON" | "TOO_LARGE". maxBytes defaults to LIMIT.JSON_BYTES.
function U.decode(s, maxBytes)
    if type(s) ~= "string" then return nil, "BAD_JSON" end
    if #s > (maxBytes or C.LIMIT.JSON_BYTES) then return nil, "TOO_LARGE" end
    local v, p = D.value(s, 1, 1)
    if p == nil or skip(s, p) <= #s then return nil, "BAD_JSON" end
    return v
end
