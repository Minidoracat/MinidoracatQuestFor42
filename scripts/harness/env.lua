--[[
Fake PZ environment: loads the REAL mod Lua so scenario files can assert behaviour
(scripts/smoke_harness.lua runs t_*.lua in order). Shape follows MinidoracatSafehouseFor42 scripts/harness/env.lua.
This is standard Lua, not Kahlua: next/xpcall/table.sort misuse is verify_mod.py's job; Lua 5.4 prints 5.0 as
"5.0" while Kahlua prints "5" -- never assert on strings built from floats.
Fake objects implement only what the mod calls; add missing engine pieces here, not in scenario files.

Quick reference
  T.boot{ sandbox = { Key = v }, sp = bool, steam = bool, keepGmd = bool, keepFiles = bool, beforeStart = fn, noStart = bool }
      server boot (MP dedicated by default): loads shared+server, then OnInitGlobalModData -> OnLoadedMapZones ->
      OnServerStarted. sp = true: single player, loads shared+server+client in one process (isServer/isClient both
      false); replies reach MinidoracatQuest.Client.receive and are also recorded in T.outbox.
  T.bootClient{}           MP client: loads shared+client (T.mode = "client").
  T.player{ name, admin, role, sid, x, y, z, num, oid, dead, noRole, offline }  online IsoPlayer (p.veh, p.hand)
  T.zombie{ oid, outfit, attacker, inWorld }  IsoZombie; addZombiesInOutfitArea makes these (T.spawnCap limits how many
      it returns, like unloaded squares; T.spawnCalls records the calls; they report isExistInTheWorld() false like
      fresh zombies on a dedicated server, quest-hz-1026e); z:Kill(killer) fires OnZombieDead
  T.cmd(p, cmd, args, requestId)   fills protocol (+ requestId for mutations / admin mutation ops), advances 300 ms,
      fires OnClientCommand and returns the "result" or "admin" reply sent for it (nil when none).
  T.lastOf(p, cmd), T.sentTo(p, cmd), T.broadcastsOf(cmd), T.clientSent (sendClientCommand records)
  T.advance(ms), T.tick(n) (100 ms + OnTick + OnTickEvenPaused per step), T.fire(event, ...)
  T.files[path] = { lines }, T.failWrites, T.silentWrites, T.unreadable[path], T.logs, T.logged(fragment)
  T.gmd (Global ModData), T.missing (requires that found no file)
]]

local T = {}
T.MEDIA = "MOD/MinidoracatQuestFor42/Contents/mods/MinidoracatQuestFor42/42/media/lua"

-- ===== results =====
T.failures, T.passes = 0, 0
function T.check(ok, label)
    if ok then
        T.passes = T.passes + 1
        io.write("  PASS  " .. label .. "\n")
    else
        T.failures = T.failures + 1
        io.write("  FAIL  " .. label .. "\n")
    end
    return ok
end
function T.section(title) io.write(title .. "\n") end

-- ===== time, mode, log =====
T.now = 1790000000000
function getTimestampMs() return T.now end
function T.advance(ms) T.now = T.now + ms end

T.mode = "server"   -- "server" (MP dedicated) | "client" (MP client) | "sp"
function isServer() return T.mode == "server" end
function isClient() return T.mode == "client" end

T.logs, T.prints = {}, {}
function writeLog(_, text) T.logs[#T.logs + 1] = text end
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    T.prints[#T.prints + 1] = table.concat(parts, " ")
    if T.verbose then io.write("    | " .. T.prints[#T.prints] .. "\n") end
end
function getText(key, ...) return key end
function getTextOrNull(key) return key end
function T.logged(fragment)
    for _, line in ipairs(T.logs) do
        if string.find(line, fragment, 1, true) then return true end
    end
    return false
end
function T.printed(fragment)
    for _, line in ipairs(T.prints) do
        if string.find(line, fragment, 1, true) then return true end
    end
    return false
end

-- ===== java-style list (size()/get(i), 0-based) =====
function T.javaList(items)
    items = items or {}
    local l = { _raw = items }
    function l:size() return #items end
    function l:get(i) return items[i + 1] end
    function l:add(v) items[#items + 1] = v return true end
    function l:isEmpty() return #items == 0 end
    return l
end
ArrayList = { new = function() return T.javaList({}) end }

-- instanceof is Java isInstance (LuaManager.java:2948-2952): fake objects carry __class
function instanceof(obj, cls)
    return type(obj) == "table" and rawget(obj, "__class") == cls
end

Capability = setmetatable({}, { __index = function(_, k) return k end })

-- ===== events =====
T.handlers = {}
Events = setmetatable({}, {
    __index = function(_, name)
        return {
            Add = function(fn)
                local l = T.handlers[name] or {}
                l[#l + 1] = fn
                T.handlers[name] = l
            end,
            Remove = function(fn)
                local l = T.handlers[name] or {}
                for i, f in ipairs(l) do if f == fn then table.remove(l, i) break end end
            end,
        }
    end,
})
-- the network layer exists only from OnServerStarted (GameServer.java:1509 / :1533)
function T.fire(name, ...)
    if name == "OnServerStarted" then T.netUp = true end
    local l = T.handlers[name] or {}
    local copy = {}
    for i, f in ipairs(l) do copy[i] = f end
    for _, fn in ipairs(copy) do fn(...) end
end

-- ===== Global ModData (GlobalModData.java) =====
T.gmd = {}
ModData = {
    getOrCreate = function(tag)
        if T.gmd[tag] == nil then T.gmd[tag] = {} end
        return T.gmd[tag]
    end,
    get = function(tag) return T.gmd[tag] end,
    exists = function(tag) return T.gmd[tag] ~= nil end,
    remove = function(tag) T.gmd[tag] = nil end,
    request = function() end,
}

function T.deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[T.deepcopy(k)] = T.deepcopy(x) end
    return out
end

-- ===== files under <cachedir>/Lua/ =====
T.files = {}
T.failWrites = false
T.silentWrites = false   -- opens and closes fine but writes nothing (PrintWriter swallows IOException)
T.unreadable = {}
function getFileWriter(path, createIfNull, append)
    if T.failWrites then return nil end
    local f = T.files[path]
    if f == nil or not append then
        f = { lines = {} }
        T.files[path] = f
    end
    if T.silentWrites then
        return { writeln = function() end, write = function() end, close = function() end }
    end
    return {
        writeln = function(_, line) f.lines[#f.lines + 1] = line end,
        write = function(_, text) f.lines[#f.lines + 1] = text end,
        close = function() end,
    }
end
function getFileReader(path, createIfNull)
    local f = T.files[path]
    if f == nil or T.unreadable[path] then return nil end
    local i = 0
    return {
        readLine = function()
            i = i + 1
            return f.lines[i]
        end,
        close = function() end,
    }
end
function cacheFileExists(path) return T.files[path] ~= nil end

function getServerName() return T.mode == "server" and "servertest" or "" end   -- LuaManager.java:4099-4105
T.world = "Riverside test"
function getWorld() return { getWorld = function() return T.world end } end    -- Core.gameSaveWorld
T.steam = false
function getSteamModeActive() return T.steam end

-- ServerWorldDatabase.java:766-788 (no profanity filter)
function isValidUserName(user)
    if type(user) ~= "string" then return false end
    local trimmed = string.gsub(string.gsub(user, "^%s+", ""), "%s+$", "")
    if trimmed == "" or string.find(user, "[;@%$,\\/%.'%?\"]") or #trimmed < 2 or #user > 32 then return false end
    return true
end

-- ===== sandbox =====
function T.resetSandbox()
    SandboxVars = { MinidoracatQuest = {} }
    local SB = MinidoracatQuest and MinidoracatQuest.Sandbox
    if SB then
        for k, o in pairs(SB.OPTIONS) do SandboxVars.MinidoracatQuest[k] = o.default end
    end
end
function T.sandbox(key, value) SandboxVars.MinidoracatQuest[key] = value end

-- ===== random =====
T.randQueue = {}
function ZombRand(a, b)
    local v = table.remove(T.randQueue, 1) or 0
    if b ~= nil then return a + v % (b - a) end
    return v % a
end

-- ===== players (IsoPlayer) =====
T.online, T.outbox, T.broadcasts = {}, {}, {}
T.nextOnlineId = 0

-- ===== engine enums (Perks, WeaponCategory): any member exists; Perks.FromString(id) =====
function T.enum(cls)
    return setmetatable({}, { __index = function(t, k)
        local v = { __class = cls, id = k }
        function v:getId() return self.id end
        function v:name() return self.id end
        rawset(t, k, v)
        return v
    end })
end
Perks = T.enum("Perk")
rawset(Perks, "FromString", function(id) return Perks[id] end)
WeaponCategory = T.enum("WeaponCategory")
function T.player(o)
    o = o or {}
    local p = {
        __class = "IsoPlayer",
        name = o.name or "alice", x = o.x or 10000, y = o.y or 10000, z = o.z or 0,
        sid = o.sid or 76561198000000000, admin = o.admin or false, role = o.role, dead = o.dead or false,
        num = o.num or 0, hours = o.hours or 100, kills = o.kills or 0, noRole = o.noRole, perks = o.perks or {},
    }
    if o.oid ~= nil then p.oid = o.oid else p.oid = T.nextOnlineId; T.nextOnlineId = T.nextOnlineId + 4 end
    function p:getUsername() return self.name end
    function p:getPlayerNum() return self.num end
    function p:getSteamID() return self.sid end
    function p:getOnlineID() return self.oid end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isDead() return self.dead end
    function p:isAnimal() return false end
    function p:getHoursSurvived() return self.hours end
    function p:getZombieKills() return self.kills end
    function p:getVehicle() return self.veh end
    function p:getPrimaryHandItem() return self.hand end
    function p:getPerkLevel(perk) return self.perks[perk] or 0 end
    -- Role.getName (IsoPlayer.java:7562 getRole, Role.java:41); SP getRole() is nil (pitfalls.md:124)
    function p:getRole()
        if self.noRole or T.mode == "sp" then return nil end
        local name = self.role or (self.admin and "admin" or "user")
        return { getName = function() return name end, hasCapability = function() return self.admin end }
    end
    if not o.offline then T.online[#T.online + 1] = p end
    T.outbox[p.name] = T.outbox[p.name] or {}
    return p
end
function T.disconnect(p)
    for i, x in ipairs(T.online) do if x == p then table.remove(T.online, i) break end end
end

-- ===== zombies (IsoZombie) =====
T.zombies, T.spawnCalls, T.spawnCap = {}, {}, nil
T.nextZombieId = 1000
function T.zombie(o)
    o = o or {}
    local z = { __class = "IsoZombie", oid = o.oid or T.nextZombieId, outfit = o.outfit or 655360, attacker = o.attacker,
        dead = false, inWorld = o.inWorld ~= false, onSquare = true, sprinter = false }
    T.nextZombieId = T.nextZombieId + 1
    function z:getOnlineID() return self.oid end
    function z:getPersistentOutfitID() return self.outfit end
    function z:isDead() return self.dead end
    function z:isExistInTheWorld() return self.inWorld end
    function z:getAttackedBy() return self.attacker end
    function z:getCurrentSquare() return nil end
    function z:doSprinter() self.sprinter = true end
    -- the server zombie's online id goes to -1 (IsoZombie.java:4335-4370)
    function z:removeFromWorld() self.inWorld, self.oid = false, -1 end
    function z:removeFromSquare() self.onSquare = false end
    -- IsoGameCharacter.Kill: attacker set, then OnZombieDead (IsoZombie.onKilled)
    function z:Kill(killer)
        self.attacker, self.dead = killer, true
        T.fire("OnZombieDead", self)
    end
    T.zombies[#T.zombies + 1] = z
    return z
end
-- LuaManager.java:10433; returns an ArrayList, fewer when squares are not loaded (T.spawnCap). On the dedicated server
-- these report isExistInTheWorld() false (their square's moving objects do not list them) for at least 1.5 s after the
-- spawn: quest-hz-1026e HZDBG, online id and outfit id unchanged
function addZombiesInOutfitArea(x1, y1, x2, y2, z, n, outfit, femaleChance)
    T.spawnCalls[#T.spawnCalls + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, z = z, n = n, outfit = outfit, female = femaleChance }
    local list = {}
    for i = 1, T.spawnCap and math.min(n, T.spawnCap) or n do list[i] = T.zombie{ inWorld = false } end
    return T.javaList(list)
end
T.netEarly = {}
local function early(what)
    if T.mode ~= "server" or T.netUp then return false end
    T.netEarly[#T.netEarly + 1] = what
    return true
end
function getOnlinePlayers()
    if early("getOnlinePlayers") then return nil end
    return T.javaList(T.online)
end
function getSpecificPlayer(i) return T.online[i + 1] end
function getPlayer() return T.online[1] end

local function record(name, cmd, payload)
    local box = T.outbox[name] or {}
    T.outbox[name] = box
    box[#box + 1] = { command = cmd, args = payload }
end

-- LuaManager.java:3881-3886 returns IsoPlayer.numPlayers (local split-screen seats); harness: local players = online list
function getNumActivePlayers() return #T.online end
function sendServerCommand(a, b, c, d)
    if early("sendServerCommand") then return end
    if T.mode == "sp" then return end   -- SP: no-op (LuaManager.java:8952-8970)
    if type(a) == "string" then
        T.broadcasts[#T.broadcasts + 1] = { module = a, command = b, args = c }
    else
        record(a.name, c, d)
    end
end
T.clientSent = {}
-- SP routes sendClientCommand(player, ...) into the same process's OnClientCommand (LuaManager.java:8924-8939)
function sendClientCommand(player, module, command, args)
    T.clientSent[#T.clientSent + 1] = { player = player, module = module, command = command, args = args }
    if T.mode == "sp" then T.fire("OnClientCommand", module, command, player, args) end
end

-- ===== loading the mod =====
local loaded = {}
T.missing = {}
-- PZ's require of a missing file does not raise; record it instead
function require(name)
    if loaded[name] then return true end
    for _, dir in ipairs({ "shared", "server", "client" }) do
        local chunk = loadfile(T.MEDIA .. "/" .. dir .. "/" .. name .. ".lua")
        if chunk then
            loaded[name] = true
            chunk()
            return true
        end
    end
    T.missing[name] = true
    return false
end

T.MODULES = dofile("scripts/harness/modules.lua")

local function loadModules(dirs)
    for _, entry in ipairs(T.MODULES) do
        if dirs[entry.dir] then
            local f = io.open(T.MEDIA .. "/" .. entry.dir .. "/" .. entry.name .. ".lua", "r")
            if f then
                f:close()
                require(entry.name)
            end
        end
    end
end

local function resetWorld(opts)
    T.handlers = {}
    T.online, T.outbox, T.broadcasts, T.clientSent = {}, {}, {}, {}
    T.netUp, T.netEarly = false, {}
    T.logs, T.prints = {}, {}
    if not opts.keepGmd then T.gmd = {} end
    if not opts.keepFiles then T.files = {} end
    T.unreadable = {}
    T.failWrites, T.silentWrites = false, false
    T.randQueue = {}
    T.zombies, T.spawnCalls, T.spawnCap = {}, {}, nil
    T.steam = opts.steam or false
    T.nextOnlineId = 0
    T.missing = {}
    MinidoracatQuest = nil
    MinidoracatEconomy = opts.economy
    for k in pairs(loaded) do loaded[k] = nil end
end

-- SP: replies go through Client.receive; record them under the local player's name
local function spCapture()
    local Q = MinidoracatQuest
    Q.Client = Q.Client or {}
    local orig = Q.Client.receive
    Q.Client.receive = function(cmd, payload)
        local p = getPlayer()
        record(p and p.name or "_sp", cmd, payload)
        if orig then return orig(cmd, payload) end
    end
end

function T.boot(opts)
    opts = opts or {}
    resetWorld(opts)
    T.mode = opts.sp and "sp" or "server"
    loadModules(opts.sp and { shared = true, server = true, client = true } or { shared = true, server = true })
    T.resetSandbox()
    for k, v in pairs(opts.sandbox or {}) do SandboxVars.MinidoracatQuest[k] = v end
    if opts.sp then spCapture() end
    if opts.beforeStart then opts.beforeStart(T) end
    if not opts.noStart then
        T.fire("OnInitGlobalModData", false)
        T.fire("OnLoadedMapZones")
        if not opts.sp then T.fire("OnServerStarted") end
    end
    return MinidoracatQuest
end

function T.bootClient(opts)
    opts = opts or {}
    resetWorld(opts)
    T.mode = "client"
    loadModules({ shared = true, client = true })
    T.resetSandbox()
    return MinidoracatQuest
end

function T.tick(n)
    for _ = 1, n or 1 do
        T.advance(100)
        T.fire("OnTick")
        T.fire("OnTickEvenPaused")
    end
end

-- ===== commands =====
T.reqSeq = 0
function T.newRequestId()
    T.reqSeq = T.reqSeq + 1
    return string.format("req-%08d", T.reqSeq)
end

local function specOf(command, args)
    local S = MinidoracatQuest.Server
    if command == "admin" then return S.adminOps[args.op] end
    return S.commands[command]
end

-- Sends one command; returns the "result" (or "admin") reply produced for it, nil when none.
-- requestId: nil = auto (mutations only), false = omit, string = use it.
function T.cmd(player, command, args, requestId)
    args = args or {}
    if args.protocol == nil then args.protocol = MinidoracatQuest.Contract.PROTOCOL end
    if requestId == nil then
        local spec = specOf(command, args)
        if spec == nil or spec.kind == "mutation" then args.requestId = T.newRequestId() end
    elseif requestId ~= false then
        args.requestId = requestId
    end
    T.advance(300)
    local box = T.outbox[player.name] or {}
    T.outbox[player.name] = box
    local before = #box
    T.fire("OnClientCommand", MinidoracatQuest.Contract.MODULE, command, player, args)
    local want = command == "admin" and "admin" or "result"
    for i = #box, before + 1, -1 do
        if box[i].command == want then return box[i].args end
    end
    return nil
end

function T.lastOf(player, command)
    local box = T.outbox[player.name] or {}
    for i = #box, 1, -1 do
        if box[i].command == command then return box[i].args end
    end
    return nil
end

function T.sentTo(player, command)
    local out = {}
    for _, e in ipairs(T.outbox[player.name] or {}) do
        if command == nil or e.command == command then out[#out + 1] = e.args end
    end
    return out
end

function T.clearOutbox(player)
    if player then T.outbox[player.name] = {} else
        for k in pairs(T.outbox) do T.outbox[k] = {} end
        T.broadcasts = {}
    end
end

function T.broadcastsOf(command)
    local out = {}
    for _, b in ipairs(T.broadcasts) do if b.command == command then out[#out + 1] = b.args end end
    return out
end

return T
