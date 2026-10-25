--[[
Smoke test: loads the REAL mod Lua with fake PZ globals, runs behaviour scenarios and asserts the results.

    lua scripts/smoke_harness.lua          (from the repo root; standard Lua 5.x)
    lua scripts/smoke_harness.lua core     (only scenario files whose name contains "core")

The fake environment is scripts/harness/env.lua, load order scripts/harness/modules.lua, scenarios
scripts/harness/t_*.lua (each returns function(T) ... end; a file may dofile its own t_<slice>_*.lua).

Why (two error classes luac -p cannot catch, both real family incidents):
- a changed signature with a missed call site is valid syntax and only fails when that path runs
- logic regressions in safety checks: "run it and assert" is the only defence

Limits: this is standard Lua, not Kahlua. next/xpcall misuse is caught by scripts/verify_mod.py's static scan;
Kahlua-only behaviour (table.sort recursion depth, hidden Java fields, LinkedHashMap memory) needs the
decompiled source and in-game tests.

Writing scenarios:
- run the paths that break: cleanup after delete, the second round across ticks, aggregated output
- safety boundaries need NEGATIVE assertions (out of range / blocked / protected must survive)
- a new guard is trusted only after planting a violation and seeing it caught
]]

local T = dofile("scripts/harness/env.lua")

-- fixed order; files that do not exist yet are skipped
local SCENARIOS = { "t_core", "t_catalog", "t_systems", "t_client", "t_admin", "t_report" }

local only = arg and arg[1]
local ran = 0
for _, name in ipairs(SCENARIOS) do
    if only == nil or string.find(name, only, 1, true) then
        local chunk = loadfile("scripts/harness/" .. name .. ".lua")
        if chunk then
            ran = ran + 1
            io.write("\n== " .. name .. " ==\n")
            local ok, err = pcall(function() chunk()(T) end)
            if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
        end
    end
end

io.write("\n")
if ran == 0 then
    io.write("no scenario to run\n")
    os.exit(1)
end
if T.failures > 0 then
    io.write(T.failures .. " failed (" .. T.passes .. " passed)\n")
    os.exit(1)
end
io.write("all passed (" .. T.passes .. ")\n")
