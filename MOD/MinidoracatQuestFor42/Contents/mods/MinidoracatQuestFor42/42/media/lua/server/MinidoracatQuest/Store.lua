-- MinidoracatQuest/Store.lua: Global ModData (shared root + 16 account shards) and the private-file helpers
-- (docs/ARCHITECTURE.md sections 3.1, 3.2, 3.5, 5.1).
-- Any logged-in client can ModData.request a whole table (GlobalModData.java:153-200), so nothing private
-- lives here: identity bindings and exports go to Lua/MinidoracatQuest/<serverKey>/ files.
-- A table whose schema is newer than this code makes the whole store read-only (no rewrites, no creates).

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"

local Q = MinidoracatQuest
local St = Q.Store or {}
Q.Store = St
local C = Q.Contract

local function now() return getTimestampMs() end

local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

local function ensure(t, k, v)
    if t[k] == nil then t[k] = v end
    return t[k]
end

-- schema check; returns true when the table is usable for writes
local function prepare(t)
    if t.schema == nil then
        t.schema = C.SCHEMA
        return true
    end
    if type(t.schema) ~= "number" or t.schema > C.SCHEMA then return false end
    -- schema 1 is the first version: nothing to upgrade yet
    return true
end

local function fillRoot(r, t)
    ensure(r, "config", { overrides = {}, rev = 0 })
    ensure(r.config, "overrides", {})
    ensure(r.config, "rev", 0)
    ensure(r, "history", {})
    ensure(r, "season", { no = 1, startMs = t, lengthDays = 28, state = "running", excluded = {} })
    ensure(r.season, "excluded", {})
    ensure(r, "seasons", {})
    ensure(r, "shared", {})
    ensure(r, "goal", {})
    ensure(r, "weekTotals", { totals = {} })
    ensure(r, "audit", { head = 0, items = {} })
    ensure(r, "balance", {})
    ensure(r, "exchange", { coins = 0, days = {} })
    ensure(r, "events", {})
    ensure(r, "daily", {})
    ensure(r, "hordes", {})                  -- timed hordes (Hordes.lua): cur = the one horde, log = last 20 results
    local h = r.hordes
    ensure(h, "seq", 0)
    -- one roll per window (roll[winKey]) and the day count apart (perDay) since 2026-10-27; the old single roll
    -- { day, ws, slot, n } keeps its count
    if type(h.roll) == "table" and (h.roll.day ~= nil or h.roll.slot ~= nil) then
        h.perDay = h.roll.day ~= nil and { [h.roll.day] = h.roll.n or 0 } or {}
        h.roll = {}
    end
    ensure(h, "roll", {})
    ensure(h, "perDay", {})
    ensure(h, "log", {})
    -- results from before 2026-10-27 had one wave, a pool of perZombie x spawned whatever the result, pay only on a
    -- win and "each" paying that pool to everyone: one wave, cleared on a win, pool = what was actually paid
    for _, e in ipairs(h.log) do
        if type(e) == "table" and e.waves == nil then
            local paid = 0
            for _, v in pairs(type(e.paid) == "table" and e.paid or {}) do paid = paid + (tonumber(v) or 0) end
            e.waves, e.cleared, e.pool, e.split = 1, e.state == "success" and 1 or 0, paid, nil
        end
    end
end

function St.shardTag(user)
    return string.format("%s%02d", C.ACCOUNT_TAG, Q.Util.hash(user) % C.SHARDS)
end

-- Called from OnInitGlobalModData (Server). Safe to call again (hot reload / harness reboot).
function St.init()
    local t = now()
    St.readOnly = false
    local root = ModData.getOrCreate(C.ROOT_TAG)
    if not prepare(root) then St.readOnly = true end
    St.shards = {}
    for i = 0, C.SHARDS - 1 do
        local s = ModData.getOrCreate(string.format("%s%02d", C.ACCOUNT_TAG, i))
        if not prepare(s) then St.readOnly = true end
        St.shards[i] = s
    end
    if St.readOnly then
        Q.Util.log("Global ModData schema is newer than this version: store is read-only")
    else
        fillRoot(root, t)
        for i = 0, C.SHARDS - 1 do ensure(St.shards[i], "accounts", {}) end
    end
    St.rootT = root
end

function St.ready()
    return St.rootT ~= nil and St.rootT.season ~= nil
end

function St.root()
    return St.rootT
end

local function newAccount(t, sno)
    local acc = {
        v = C.ACCOUNT_V, firstMs = t, seenMs = t,
        total = {}, life = {}, season = {}, sno = sno,
        points = { season = 0, total = 0, balance = 0 },
        day = { quests = {}, swaps = 0, done = 0 },
        week = { quests = {}, goalPart = 0 },
        streak = { days = 0, best = 0, graceUsed = false, paid = {} },
        towns = {}, achv = {}, titles = {}, prefs = {}, anon = false,
        ex = { used = 0, seq = 0, queue = {} },
        unseen = 0, imported = false, anomalies = 0,
    }
    local cfg = Q.Config and Q.Config.get and Q.Config.get() or nil
    local nb = cfg and cfg.newbie or nil
    if nb == nil or nb.enabled ~= false then
        acc.newbie = { startMs = t, steps = { false, false, false, false, false } }
    end
    return acc
end

-- Every title grant goes through here: titleAt keeps the first grant time, titleSrc what granted it ("a:<achId>:<tier>",
-- "streak:<days>", "newbie", "season:<no>:<rank>", "first:<boardId>"); revoke goes by titleSrc (owner 2026-10-27).
-- Titles granted before titleAt / titleSrc existed have neither and stay without them.
function St.grantTitle(acc, id, src)
    acc.titles = acc.titles or {}
    if acc.titles[id] then return end
    acc.titles[id] = true
    acc.titleAt = acc.titleAt or {}
    acc.titleAt[id] = now()
    acc.titleSrc = acc.titleSrc or {}
    acc.titleSrc[id] = src
end

-- C30: season fields reset lazily when the account belongs to an older season
local function lazySeason(acc)
    local no = St.rootT.season.no
    if acc.sno ~= no and not St.readOnly then
        acc.sno = no
        acc.season = {}
        acc.points.season = 0
        acc.anomalies = 0
    end
end

function St.account(user, create)
    if not St.ready() or type(user) ~= "string" then return nil end
    local accounts = St.shards[Q.Util.hash(user) % C.SHARDS].accounts
    if accounts == nil then return nil end
    local acc = accounts[user]
    if acc == nil then
        if not create or St.readOnly then return nil end
        acc = newAccount(now(), St.rootT.season.no)
        accounts[user] = acc
        if Q.Report then Q.Report.add("fresh") end
        return acc
    end
    lazySeason(acc)
    return acc
end

function St.touch(user, acc)
    if St.readOnly or acc == nil then return end
    acc.seenMs = now()
    lazySeason(acc)
end

-- fn(user, acc) for every account of shard i (0..SHARDS-1): the report snapshot walks one shard per tick
function St.eachIn(i, fn)
    local accounts = St.shards[i].accounts
    if accounts then
        for user, acc in pairs(accounts) do
            lazySeason(acc)
            fn(user, acc)
        end
    end
end

-- fn(user, acc) for every account in all 16 shards (board rebuild, settlement, admin queries only)
function St.each(fn)
    if not St.ready() then return end
    for i = 0, C.SHARDS - 1 do St.eachIn(i, fn) end
end

St.isEmpty = isEmpty

-- ===== private files (<cachedir>/Lua/MinidoracatQuest/<serverKey>/...) =====
-- Ported from Safehouse Registry.lua (serverKey, writeLines, readLines). getFileWriter swallows write errors
-- (PrintWriter), so callers that must be sure read the file back. Lua cannot delete or rename files.

-- the server name on a dedicated server; sp_<save name> in single player, where getServerName() is ""
-- (LuaManager.java:4099-4105) and Zomboid/Lua is shared by every save on the machine (pitfalls.md; the same folder
-- rule as VehicleManager Export.lua and MiniMapWatch Config.lua)
function St.serverKey()
    local name
    if isServer() then name = getServerName and getServerName() or nil
    elseif getWorld and getWorld() then name = "sp_" .. tostring(getWorld():getWorld()) end
    if type(name) ~= "string" or name == "" or name == "sp_" then name = "default" end
    return (string.gsub(name, "[^%w_%-]", "_"))
end

function St.path(file)
    return "MinidoracatQuest/" .. St.serverKey() .. "/" .. file
end

function St.writeLines(path, lines, append)
    local writer
    local opened = pcall(function() writer = getFileWriter(path, true, append) end)
    if not opened or writer == nil then return false end
    local written = pcall(function()
        for _, line in ipairs(lines) do writer:writeln(line) end
    end)
    local closed = pcall(function() writer:close() end)
    return written and closed
end

-- lines (at most max); nil when the file does not exist; false when it exists but cannot be read
function St.readLines(path, max)
    local reader
    local opened = pcall(function() reader = getFileReader(path, false) end)
    if not opened or reader == nil then
        local ok, exists = pcall(cacheFileExists, path)
        if ok and not exists then return nil end
        return false
    end
    local lines = {}
    local read = pcall(function()
        while #lines < max do
            local line = reader:readLine()
            if line == nil then break end
            lines[#lines + 1] = line
        end
    end)
    pcall(function() reader:close() end)
    if not read then return false end
    return lines
end
