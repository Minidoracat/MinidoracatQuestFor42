-- MinidoracatQuest/Towns.lua: town areas (built-in Catalog.towns + config towns.custom) and point lookup.
-- Rects are { x1, y1, x2, y2 } named fields, inclusive. The flat index is rebuilt when the effective config changes.

if isClient() then return end

require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Config"

local Q = MinidoracatQuest
local T = Q.Towns or {}
Q.Towns = T

local cfgSeen, list
local rid, rx1, ry1, rx2, ry2, count = {}, {}, {}, {}, {}, 0

local function rebuild(cfg)
    cfgSeen = cfg
    list, rid, rx1, ry1, rx2, ry2, count = {}, {}, {}, {}, {}, {}, 0
    local towns = cfg.towns or {}
    local disabled = towns.disabled or {}
    local function addTown(t)
        if disabled[t.id] then return end
        list[#list + 1] = t
        for _, r in ipairs(t.rects) do
            count = count + 1
            rid[count], rx1[count], ry1[count], rx2[count], ry2[count] = t.id, r.x1, r.y1, r.x2, r.y2
        end
    end
    for _, t in ipairs(Q.Catalog.towns) do addTown(t) end
    for _, t in ipairs(towns.custom or {}) do addTown(t) end
end

local function current()
    local cfg = Q.Config.get()
    if cfg ~= cfgSeen then rebuild(cfg) end
end

-- Enabled towns: built-in { id, rects } then custom { id, name, rects }.
function T.list()
    current()
    return list
end

-- townId or nil. First match wins (built-in before custom).
function T.at(x, y)
    current()
    for i = 1, count do
        if x >= rx1[i] and x <= rx2[i] and y >= ry1[i] and y <= ry2[i] then return rid[i] end
    end
    return nil
end
