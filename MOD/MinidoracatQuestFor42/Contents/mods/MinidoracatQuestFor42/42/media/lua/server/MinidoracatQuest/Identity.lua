-- MinidoracatQuest/Identity.lua: principal(player) and the private binding file
-- (docs/ARCHITECTURE.md sections 0, 3.5, 5.2; pz-family-docs conventions.md "player identity").
-- Ported from MinidoracatSafehouse server/Identity.lua (principal, observe, bindChecked, onNewGame, LOGIN binding
-- in tick) and the binding subset of server/Registry.lua (sidText, append-only private file, write-then-memory).
-- Dropped from the port: claim-time binding (no claims here) and hostile-name health mode.
-- On the server getUsername() is what the client sent; respawn and split-screen can claim a name
-- (ConnectCoopPacket.java:72-97), so every authorisation, ledger write and push goes through principal:
--   getPlayerNum() ~= 0 -> nil; non-Steam -> name; Steam: bound name with another SteamID -> nil, else name.
-- Bindings: Lua/MinidoracatQuest/<serverKey>/identity.txt, lines "1\tbind\t<name>\t<sid>\t<src>\t<ms>",
-- last line wins; the file is written before memory changes. Unreadable file -> principal fails closed.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Audit"

local Q = MinidoracatQuest
local first = Q.Identity == nil
local I = Q.Identity or {}
Q.Identity = I
local C, U = Q.Contract, Q.Util

I.SLOT_GAP_MS = 120000
I.NEWGAME_WINDOW_MS = 120000
I.SCAN_MS = 1000
I.REFUSE_LOG_MS = 3600000
I.WRITE_RETRY_MS = 60000

-- E2E overrides these on no-steam servers (conventions.md "player identity" point 6)
I.steamMode = I.steamMode or function() return getSteamModeActive() == true end
I.sidOf = I.sidOf or function(player) return player:getSteamID() end

I.slots = I.slots or {}
I.newGames = I.newGames or {}
I.writeRetryAt = I.writeRetryAt or {}
I.bindings = I.bindings or {}

local function validSid(v)
    return type(v) == "number" and v > 0 and v * 0 == 0 and v == math.floor(v)
end

local function playerNum(player)
    local ok, num = pcall(function() return player:getPlayerNum() end)
    if ok then return num end
    return nil
end

-- ===== private binding file (Safehouse Registry.lua subset) =====

function I.path() return Q.Store.path("identity.txt") end

-- SteamID arrives as a double; exact decimal text from two halves (no tostring/%d: 1e14+ turns scientific)
function I.sidText(v)
    local hi = math.floor(v / 1e9)
    local lo = v - hi * 1e9
    if lo < 0 then hi, lo = hi - 1, lo + 1e9 elseif lo >= 1e9 then hi, lo = hi + 1, lo - 1e9 end
    local low = tostring(math.floor(lo))
    if hi <= 0 then return low end
    return tostring(math.floor(hi)) .. string.rep("0", 9 - #low) .. low
end

local function sidFromText(text)
    if type(text) ~= "string" or #text > 19 or not string.find(text, "^%d+$") then return nil end
    local n = tonumber(text)
    if n == nil or n <= 0 then return nil end
    return n + 0.0
end

local function applyLine(line)
    local f = {}
    for part in string.gmatch(line, "[^\t]+") do f[#f + 1] = part end
    if f[1] ~= "1" or f[2] ~= "bind" or #f ~= 6 or not C.validUsername(f[3]) then return false end
    local sid, at = sidFromText(f[4]), tonumber(f[6])
    if sid == nil or at == nil then return false end
    I.bindings[f[3]] = { sid = sid, src = f[5], at = at }
    return true
end

-- once at start; an existing file that cannot be read fails closed
function I.load()
    I.bindings, I.privateUnreadable, I.privateBad = {}, false, 0
    local lines = Q.Store.readLines(I.path(), 200000)
    if lines == false then
        I.privateUnreadable = true
        U.log("identity file unreadable: " .. I.path())
        return
    end
    for _, line in ipairs(lines or {}) do
        if not applyLine(line) then I.privateBad = I.privateBad + 1 end
    end
end

function I.binding(name)
    return I.bindings[name]
end

-- write first, then memory
function I.setBinding(name, sid, src, now)
    if not C.validUsername(name) or not validSid(sid) then return false end
    local line = table.concat({ "1", "bind", name, I.sidText(sid), U.logSafe(src), string.format("%.0f", now) }, "\t")
    if not Q.Store.writeLines(I.path(), { line }, true) then return false end
    I.bindings[name] = { sid = sid, src = src, at = now }
    return true
end

-- ===== principal =====

function I.principal(player)
    if player == nil or playerNum(player) ~= 0 then return nil end
    local name = player:getUsername()
    if type(name) ~= "string" or name == "" then return nil end
    if not I.steamMode() then return name end
    if I.privateUnreadable then return nil end
    local b = I.bindings[name]
    if b == nil then return name end
    if b.sid ~= I.sidOf(player) then return nil end
    return name
end

-- log and rate-limit key only, not an identity
function I.claimedName(player)
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and type(name) == "string" then return name end
    return "?"
end

local function seatId(player)
    local ok, id = pcall(function() return player:getOnlineID() end)
    if ok and type(id) == "number" and id >= 0 then return id end
    return nil
end

local function deadNow(obj)
    local ok, dead = pcall(function() return obj:isDead() end)
    return ok and dead == true
end

-- Seat observation (Economy Id.observe): same seat, same SteamID, another name, previous occupant dead -- or the
-- same SteamID created another login within two minutes -> rename evidence for this occupancy.
function I.observe(player, now)
    local id = seatId(player)
    if id == nil then return nil end
    local name, sid = player:getUsername(), I.sidOf(player)
    local r = I.slots[id]
    if r ~= nil and r.name == name and r.sid == sid and now - r.seen <= I.SLOT_GAP_MS then
        r.seen, r.obj = now, player
        return r
    end
    local other = nil
    if validSid(sid) then
        local ng = I.newGames[sid]
        local prevDead = r ~= nil and r.obj ~= nil and deadNow(r.obj)
        if prevDead and r.sid == sid and r.name ~= name and now - r.seen <= I.SLOT_GAP_MS then
            other = r.name
        elseif ng ~= nil and ng.name ~= name and now - ng.at <= I.NEWGAME_WINDOW_MS then
            other = ng.name
        end
    end
    r = { name = name, sid = sid, seen = now, obj = player, suspect = other ~= nil, other = other }
    I.slots[id] = r
    return r
end

local function bindChecked(player, now, src)
    local name, sid = player:getUsername(), I.sidOf(player)
    if not C.validUsername(name) or not validSid(sid) then return false, "INVALID" end
    if deadNow(player) then return false, "DEAD" end
    local r = I.observe(player, now)
    if r == nil then return false, "NO_SEAT" end
    if r.suspect then return false, "RENAME_EVIDENCE", r.other end
    if not I.setBinding(name, sid, src, now) then return false, "WRITE_FAILED" end
    Q.Audit.write("BIND", { actor = name, code = src })
    return true
end

-- server OnNewGame: CreatePlayerPacket only (first join, respawn, split-screen join)
function I.onNewGame(player)
    if player == nil or not isServer() or not I.steamMode() or I.privateUnreadable then return end
    local name, sid = player:getUsername(), I.sidOf(player)
    if not C.validUsername(name) or not validSid(sid) then return end
    local now = getTimestampMs()
    I.newGames[sid] = { name = name, at = now }
    local b = I.bindings[name]
    if b == nil then
        if I.setBinding(name, sid, "NEWGAME", now) then Q.Audit.write("BIND", { actor = name, code = "NEWGAME" }) end
    elseif b.sid ~= sid then
        Q.Audit.write("BIND_CONFLICT", { actor = name, code = "SID_MISMATCH" })
    end
end

local function bindOnLogin(p, now)
    if I.privateUnreadable then return I.observe(p, now) end
    local name = p:getUsername()
    if I.bindings[name] ~= nil then return I.observe(p, now) end
    local retry = I.writeRetryAt[name]
    if retry ~= nil and now < retry then return I.observe(p, now) end
    I.writeRetryAt[name] = nil
    local ok, why, other = bindChecked(p, now, "LOGIN")
    if not ok then
        if why == "WRITE_FAILED" then I.writeRetryAt[name] = now + I.WRITE_RETRY_MS end
        Q.Audit.throttled("BIND_REFUSED|" .. U.logSafe(name), I.REFUSE_LOG_MS, "BIND_REFUSED",
            { actor = name, code = why, detail = "LOGIN " .. tostring(other or "-") }, now)
    end
end

-- every second on a Steam MP server: observe seats and bind online primary seats
function I.tick(now)
    if I.lastScan ~= nil and now - I.lastScan < I.SCAN_MS then return end
    I.lastScan = now
    if not isServer() or not I.steamMode() then return end
    local list = getOnlinePlayers()
    if list == nil then return end
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if playerNum(p) == 0 and type(p:getUsername()) == "string" then bindOnLogin(p, now) end
    end
end

if first then
    Events.OnNewGame.Add(function(player) MinidoracatQuest.Identity.onNewGame(player) end)
end
