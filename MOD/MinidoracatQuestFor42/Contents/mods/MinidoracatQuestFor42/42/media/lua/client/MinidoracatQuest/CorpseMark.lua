-- MinidoracatQuest/CorpseMark.lua: this player's own marked corpse (plan quest-corpse-highlight-1102; server side is
-- Hordes.lua "player corpse marks"). The server sends { mark } at each change and at hello (false: none). Once a second
-- the corpse within 1 square of the mark gets an outline and a light tint for player 0: matched by ObjectID, which
-- server and client share (RemoveCorpseFromMap relies on it), or by the modData key after the area reloaded. Each
-- second again: the loot window and the context menu clear corpse highlights (ISInventoryPage.updateContainerHighlight,
-- ISWorldObjectContextMenu), so it also claims the object through ISInventoryPage.OnObjectHighlighted. A walker mark
-- (the corpse reanimated) has no corpse to light; HordeMap.lua puts the mark on MiniMap.

if isServer() then return end

require "MinidoracatQuest/Client"

local Q = MinidoracatQuest
local C = Q.Client
local first = Q.CorpseMark == nil
local M = Q.CorpseMark or {}
Q.CorpseMark = M

M.mark, M.body, M.nextAt = nil, nil, 0

local function find(m)
    local cell = getCell()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(m.x + dx, m.y + dy, m.z)
            local list = sq ~= nil and sq:getStaticMovingObjects() or nil
            for i = 0, (list ~= nil and list:size() or 0) - 1 do
                local b = list:get(i)
                if instanceof(b, "IsoDeadBody") and ((m.oid ~= nil and b:getObjectIDAsLong() == m.oid)
                    or (b:hasModData() and b:getModData()[Q.Contract.MARK_KEY] == m.key)) then return b end
            end
        end
    end
end

local function light(b, on)
    b:setOutlineHighlight(0, on)
    b:setHighlighted(0, on, false)
    if on then
        b:setOutlineHighlightCol(0, 1, 0.85, 0.2, 1)
        b:setHighlightColor(0, 1, 0.75, 0.75, 1)
    end
    ISInventoryPage.OnObjectHighlighted(0, b, on)
end

function M.tick(now)
    if now < M.nextAt then return end
    M.nextAt = now + 1000
    local m = M.mark
    local b = m ~= nil and m.state ~= "walker" and find(m) or nil
    if M.body ~= nil and M.body ~= b then light(M.body, false) end
    M.body = b
    if b ~= nil then light(b, true) end
end

function M.receive(p)   -- Client.lua H.corpseMark
    local m, ok = p.mark, Q.Contract.isFinite
    M.mark = type(m) == "table" and ok(m.x) and ok(m.y) and ok(m.z) and m or nil
    M.nextAt = 0
    C.emit("corpseMark")
end

if first then
    Events.OnTick.Add(function() MinidoracatQuest.CorpseMark.tick(getTimestampMs()) end)
end
