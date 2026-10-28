-- MinidoracatQuest/Contract.lua: shared constants (docs/ARCHITECTURE.md sections 2, 3, 4.1, 6).
-- Both sides load this file; no client- or server-only globals here.

MinidoracatQuest = MinidoracatQuest or {}
local Q = MinidoracatQuest
local C = Q.Contract or {}
Q.Contract = C

C.MOD_ID = "MinidoracatQuestFor42"
C.MODULE = "MinidoracatQuest"        -- command module, sandbox page, ModData tag
C.PROTOCOL = 1
C.LOG_PREFIX = "[MinidoracatQuestFor42] "

C.ROOT_TAG = "MinidoracatQuest"           -- shared Global ModData table
C.ACCOUNT_TAG = "MinidoracatQuest_A"      -- + two digits 00..15
C.SHARDS = 16
C.SCHEMA = 1                              -- root and account tables
C.ACCOUNT_V = 1

C.LIMIT = {
    RATE_WINDOW_MS = 5000, RATE_MAX = 20,     -- per player
    COOLDOWN_MS = 300,                        -- default per command
    CACHE_TTL_MS = 60000, CACHE_PER_ACTOR = 64,
    REQUEST_ID_MIN = 8, REQUEST_ID_MAX = 64,
    STR = 64, TEXT = 256, JSON_BYTES = 32000, JSON_DEPTH = 16,
    USERNAME = 64,
    HISTORY = 20, AUDIT_RING = 500, SEASONS_KEPT = 12,
    DELTA_MS = 1000, TOAST_MERGE_MS = 2000, BROADCAST_MS = 60000,
    MAX_PREFS = 3, ANOMALY_ROWS = 200,
    MAX_PINS = 5,                             -- quests / achievements on the tracker panel
    MAX_LEAD = 120,                           -- horde warning minutes: a window's leadMin and the horde.now lead
    MAX_PRESETS = 8,                          -- hordes.presets (the "default" one included)
}

-- Result codes; the client shows IGUI_MQ_Code_<CODE>.
C.CODE = {}
for _, k in ipairs({ "OK", "PROTOCOL_MISMATCH", "BAD_ARGS", "IDENTITY_UNVERIFIED", "NOT_READY", "FORBIDDEN",
    "RATE_LIMITED", "NO_SWAPS", "BAD_SLOT", "BAD_THEME", "TOO_MANY_PREFS", "TITLE_LOCKED", "EXCHANGE_OFF",
    "EXCHANGE_MIN", "EXCHANGE_DAY_LIMIT", "NOT_ENOUGH_POINTS", "ECONOMY_MISSING", "BAD_BOARD", "BAD_CONFIG",
    "BAD_SEASON_LENGTH", "TOO_SOON", "NOT_FOUND", "FILE_ERROR", "INTERNAL", "TOO_MANY_PINS", "HORDE_BUSY", "NO_SPOTS",
    "CONFIG_CHANGED" }) do
    C.CODE[k] = k
end

-- Three independent vocabularies (section 4.1).
C.THEMES = { "combat", "build", "craft", "cook", "tailor", "farm", "animal", "fishtrap", "forage", "mech", "explore" }
C.THEME_GROUPS = {
    { "combat" },
    { "build", "craft", "cook", "tailor", "mech" },
    { "farm", "animal", "fishtrap", "forage", "explore" },
}
C.ACH_CATS = { "combat", "survival", "skill", "production", "nature", "explore", "quest", "horde", "hidden", "job" }
C.BOARD_CATS = { "overall", "combat", "survival", "skill", "life", "explore", "quest", "job" }

C.POINT_KINDS = { quest = true, shared = true, week = true, goal = true, streak = true, achv = true,
    newbie = true, season = true, import = true, admin = true, horde = true }

-- Built-in horde kinds (Hordes.lua spawns them); other mods add "<modId>:<id>" kinds through v1.registerHordeKind.
C.HORDE_KINDS = { "vanilla", "runner" }

function C.isFinite(n)
    return type(n) == "number" and n * 0 == 0
end

function C.isInt(n)
    return type(n) == "number" and n * 0 == 0 and n == math.floor(n)
end

function C.validRequestId(s)
    return type(s) == "string" and #s >= C.LIMIT.REQUEST_ID_MIN and #s <= C.LIMIT.REQUEST_ID_MAX
        and string.find(s, "^[%w_%-]+$") ~= nil
end

-- Player name: the engine's isValidUserName exists only on the server.
function C.validUsername(s)
    if type(s) ~= "string" or #s < 1 or #s > C.LIMIT.USERNAME or string.find(s, "%c") then return false end
    if isValidUserName ~= nil then return isValidUserName(s) == true end
    return true
end

function C.isTheme(id)
    for _, t in ipairs(C.THEMES) do if t == id then return true end end
    return false
end
