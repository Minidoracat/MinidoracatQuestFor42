-- MinidoracatQuest/Net.lua: server -> client sends (docs/ARCHITECTURE.md sections 5.6, 6.4).
-- MP: sendServerCommand(player, MODULE, cmd, payload), only after OnServerStarted (the network layer does not exist
-- before it; pz-family-docs pitfalls.md:151-159). SP: sendServerCommand is a no-op (LuaManager.java:8952-8970), so
-- the payload goes straight to MinidoracatQuest.Client.receive (KnoxPass Server.lua pattern).
-- Online players come from getOnlinePlayers() (getPlayerFromUsername returns nil on a dedicated server).

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"

local Q = MinidoracatQuest
local N = Q.Net or {}
Q.Net = N
local C = Q.Contract

function N.send(player, cmd, payload)
    if isServer() then
        if not N.up or player == nil then return false end
        sendServerCommand(player, C.MODULE, cmd, payload)
        return true
    end
    local client = Q.Client
    if client and client.receive then
        -- same process in SP: hand over a copy so client code cannot write into server tables
        client.receive(cmd, Q.Util.copy(payload))
        return true
    end
    return false
end

-- fn(player, user) for every online primary player whose identity checks out
function N.eachOnline(fn)
    if isServer() then
        if not N.up then return end
        local list = getOnlinePlayers()
        if list == nil then return end
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            local user = Q.Identity.principal(p)
            if user ~= nil then fn(p, user) end
        end
        return
    end
    local p = getPlayer and getPlayer() or nil
    local user = p and Q.Identity.principal(p) or nil
    if user ~= nil then fn(p, user) end
end

-- the online player for user, or nil
function N.playerOf(user)
    local found
    N.eachOnline(function(p, u) if u == user and found == nil then found = p end end)
    return found
end

function N.toUser(user, cmd, payload)
    local p = N.playerOf(user)
    if p == nil then return false end
    return N.send(p, cmd, payload)
end

function N.broadcast(cmd, payload)
    N.eachOnline(function(p) N.send(p, cmd, payload) end)
end
