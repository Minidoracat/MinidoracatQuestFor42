-- MinidoracatQuest/Sandbox.lua: sandbox reads (docs/ARCHITECTURE.md section 9).
-- SandboxVars.MinidoracatQuest.<Key>; MP pushes sandbox values to clients, no sync needed.
-- Keep OPTIONS in step with media/sandbox-options.txt and the Sandbox_MinidoracatQuest_* keys.

MinidoracatQuest = MinidoracatQuest or {}
require "MinidoracatQuest/Contract"
local Q = MinidoracatQuest
local SB = Q.Sandbox or {}
Q.Sandbox = SB

SB.PAGE = "MinidoracatQuest"
SB.OPTIONS = {
    TimezoneOffset = { kind = "int", min = -12, max = 14, default = 8 },
    ResetHour = { kind = "int", min = 0, max = 23, default = 0 },
    -- string defaults in the txt cannot hold commas (ScriptParser); the list default lives here
    AdminRoles = { kind = "string", default = "admin" },
}

-- Value of a sandbox option, clamped; wrong type or missing falls back to the default.
function SB.get(key)
    local o = SB.OPTIONS[key]
    local page = SandboxVars and SandboxVars[SB.PAGE]
    local v = type(page) == "table" and page[key] or nil
    if o.kind == "int" then
        if not Q.Contract.isFinite(v) then return o.default end
        v = math.floor(v)
        if v < o.min then return o.min end
        if v > o.max then return o.max end
        return v
    end
    if type(v) ~= "string" then return o.default end
    return v
end

-- AdminRoles as a set; names separated by commas or semicolons, case-sensitive.
function SB.adminRoles()
    local set = {}
    for name in string.gmatch(SB.get("AdminRoles"), "[^,;]+") do
        local t = string.gsub(string.gsub(name, "^%s+", ""), "%s+$", "")
        if t ~= "" then set[t] = true end
    end
    return set
end
