-- MinidoracatQuest/HordeMap.lua: optional MinidoracatMiniMap integration for hordes (MiniMap docs/addon-api.md 3.3, 3.14).
--   While state.hordes.cur is announced / waiting / active / rest: one zone of +-ZONE_R squares around the spot and one
--   marker on it. MiniMap calls both providers every frame, so they only return cached tables; the tables are built
--   again when a state / delta push changes the horde view (id, state, spot, name, town). MiniMap is not a require
--   of this mod: the providers are registered when its API is there (file load, else OnGameStart); without it, nothing.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.HordeMap == nil
local M = Q.HordeMap or {}
Q.HordeMap = M

M.OWNER = "MinidoracatQuestFor42"
M.ZONE_R = 10
M.TEX = "media/ui/MinidoracatUI/mui_art_skull.png"
M.NONE = { hasFill = false, hasLine = false, hasIcon = false }   -- zones while no horde shows (never mutated)
M.zones, M.markers, M.key = M.NONE, nil, nil
M.revision = M.revision or 0

local function texture()
    if M.tex == nil and getTexture ~= nil then
        local ok, t = pcall(getTexture, M.TEX)
        M.tex = ok and t or false
    end
    return M.tex or nil
end

-- rebuild only when what the maps show changed
function M.refresh()
    local hs = C.state and C.state.hordes
    local h = D.hordeLive(type(hs) == "table" and hs.cur or nil)
    local x, y = h and tonumber(h.x), h and tonumber(h.y)
    local key = x and y and table.concat({ tostring(h.id), h.state, x, y, tostring(h.name), tostring(h.town) }, "|") or nil
    if key == M.key then return end
    M.key = key
    if key == nil then
        M.zones, M.markers = M.NONE, nil
        return
    end
    local c = h.state == "active" and D.EXTRA.horde or D.EXTRA.hordeSoon
    local col = { r = c.r, g = c.g, b = c.b }
    local label, r = D.hordePlace(h), M.ZONE_R
    M.zones = { { id = "mq_horde", name = label, rects = { { x1 = x - r, y1 = y - r, x2 = x + r, y2 = y + r } },
        fill = col, fillAlpha = 0.22, border = col, borderAlpha = 0.9 } }
    M.revision = M.revision + 1
    local tex = texture()
    M.markers = { revision = M.revision, markers = tex and { { id = "mq_horde", x = x, y = y, texture = tex,
        r = c.r, g = c.g, b = c.b, label = label, state = "live" } } or {} }
end

function M.zoneProvider() return M.zones end

-- the horde is the same for every local player; split screen draws it on the first player's maps only
function M.markerProvider(playerNum)
    if playerNum ~= 0 then return nil end
    return M.markers
end

-- true when MiniMap took at least one provider; zones need zoneApiVersion >= 1, markers markerApiVersion >= 1
function M.register()
    local api = MinidoracatMiniMapAPI
    if M.registered or type(api) ~= "table" then return M.registered == true end
    if type(api.zoneApiVersion) == "number" and api.zoneApiVersion >= 1 and type(api.registerZoneProvider) == "function" then
        api.registerZoneProvider(M.OWNER, M.zoneProvider)
        M.registered = true
    end
    if type(api.markerApiVersion) == "number" and api.markerApiVersion >= 1 and type(api.registerMarkerProvider) == "function" then
        api.registerMarkerProvider(M.OWNER, M.markerProvider)
        M.registered = true
    end
    if M.registered then C.log("MiniMap horde zone / marker registered") end
    return M.registered == true
end

if first then
    M.register()
    for _, ev in ipairs({ "state", "delta" }) do
        C.on(ev, "hordemap", function() MinidoracatQuest.HordeMap.refresh() end)
    end
    Events.OnGameStart.Add(function() MinidoracatQuest.HordeMap.register() end)
end
