-- MinidoracatQuest/Titles.lua: worn titles of the online players (design round 7): a gold title after the author
--   in chat and one line over the head, above the vanilla name. MP only; each follows its server switch
--   (cfg.titles.chat / .head) and the player's MOD option. An anonymous player's title shows here too (decision
--   "board": only leaderboard rows hide it).
--   Data: T.byUser (user -> title id) from "titles": the full map at hello, then { u, t } per change.
--   Chat: ISChat.addLineInChat is wrapped at file load (vanilla adds it to OnAddMessage on OnGameStart,
--   ISChat.lua:1176). A message from a titled author goes in as a proxy: getTextWithPrefix() adds the title after
--   "[author]", every other method goes to the real message (ISChat calls getAuthor / setText, and
--   getTextWithPrefix again when the chat settings change).
--   Head: the vanilla name rules (IsoGameCharacter.renderlast / updateUserName): own title only with "show your
--   username", the server shows names (DisplayUserName or ShowFirstAndLastName) unless you can see all, not
--   invisible or disguised, square seen and checkCanSeeClient, MouseOverToSeeDisplayName -> only a player under the
--   mouse or within one square of the floor square under it. Skipped while speaking (the chat lines use that place),
--   in a vehicle (vanilla moves the name), and for yourself during a timed action or a halo note (the progress bar
--   and the note stack there).
--   Candidates are rebuilt every 500 ms; a frame only re-checks them and draws.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "Chat/ISChat"

local Q = MinidoracatQuest
local C, D = Q.Client, Q.Draw
local first = Q.Titles == nil
local T = Q.Titles or {}
Q.Titles = T

T.COLOR = { r = 0.91, g = 0.76, b = 0.35 }
T.CHAT_RGB = "0.91,0.76,0.35"
T.SCAN_MS = 500
T.RANGE2 = 40 * 40   -- tiles squared: farther players are off screen at any zoom
T.byUser = T.byUser or {}
T.text, T.chatMark = {}, {}   -- title id -> display text / chat markup (cleared with the catalog)
T.nearP, T.nearText, T.n = {}, {}, 0

function T.onTitles(p)
    if p.full then
        T.byUser = type(p.map) == "table" and p.map or {}
    elseif type(p.u) == "string" then
        T.byUser[p.u] = type(p.t) == "string" and p.t or nil
    end
    T.lastScan = nil
end

function T.textOf(id)
    local s = T.text[id]
    if s == nil then
        s = D.titleText(id)
        T.text[id] = s
    end
    return s
end

local function enabled(cfgKey, option)
    if not isClient() then return false end
    local E = Q.Entry
    if E ~= nil and E[option] == false then return false end
    local t = C.defs().cfg.titles
    return not (type(t) == "table" and t[cfgKey] == false)
end

-- ===== chat =====
-- "<RGB:..>[12:00][Local][Kate]: hi" -> "...[Kate] <SPACE> <PUSHRGB:..> (title) <POPRGB> : hi"
function T.decorateLine(line, user)
    local id = T.byUser[user]
    if id == nil or type(line) ~= "string" or not enabled("chat", "showChatTitles") then return line end
    local i = string.find(line, "[" .. user .. "]:", 1, true)
    if i == nil then return line end
    local mark = T.chatMark[id]
    if mark == nil then
        -- the rich text panel reads "<...>" as a command: a title cannot open one
        local name = string.gsub(string.gsub(T.textOf(id), "<", "&lt;"), ">", "&gt;")
        mark = " <SPACE> <PUSHRGB:" .. T.CHAT_RGB .. "> " .. getText("IGUI_MQ_UI_ChatTitle", name) .. " <POPRGB> "
        T.chatMark[id] = mark
    end
    local cut = i + #user + 1   -- the "]" after the name
    return string.sub(line, 1, cut) .. mark .. string.sub(line, cut + 1)
end

local own = {}
local fwd = {}
local function member(m, k) return m[k] end
local Proxy = {
    __index = function(self, k)
        local f = own[k]
        if f ~= nil then return f end
        local ok, v = pcall(member, rawget(self, "m"), k)
        if not ok or v == nil then return nil end
        f = fwd[k]
        if f == nil then
            f = function(px, ...)
                local m = rawget(px, "m")
                return m[k](m, ...)
            end
            fwd[k] = f
        end
        return f
    end,
}

function own.getTextWithPrefix(px)
    local m = rawget(px, "m")
    return T.decorateLine(m:getTextWithPrefix(), rawget(px, "u"))
end

local function authorOf(m) return m:getAuthor() end

-- the message ISChat stores and shows: a proxy only for a titled author while chat titles are on
function T.wrap(message)
    if not enabled("chat", "showChatTitles") then return message end
    local ok, author = pcall(authorOf, message)
    if not ok or type(author) ~= "string" or T.byUser[author] == nil then return message end
    return setmetatable({ m = message, u = author }, Proxy)
end

-- ===== over the head =====
local function anyTitle()
    for _ in pairs(T.byUser) do return true end
    return false
end

function T.scan()
    T.n = 0
    local me = getSpecificPlayer(0)
    if me == nil or not anyTitle() or not enabled("head", "showHeadTitles") then return end
    local so = getServerOptions()
    T.canSeeAll = me:canSeeAll() == true
    if not T.canSeeAll and so:getBoolean("DisplayUserName") ~= true and so:getBoolean("ShowFirstAndLastName") ~= true then
        return
    end
    T.mouseOnly = not T.canSeeAll and so:getBoolean("MouseOverToSeeDisplayName") == true
    T.lineH = getTextManager():getFontHeight(UIFont.Small)
    local mx, my = me:getX(), me:getY()
    local function add(p)
        local id = T.byUser[p:getUsername()]
        if id == nil or p:isDead() or p:getVehicle() ~= nil then return end
        local dx, dy = p:getX() - mx, p:getY() - my
        if dx * dx + dy * dy > T.RANGE2 then return end
        T.n = T.n + 1
        T.nearP[T.n], T.nearText[T.n] = p, T.textOf(id)
    end
    if getCore():isShowYourUsername() then add(me) end
    local list = getOnlinePlayers()
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p ~= me then add(p) end
    end
    for i = T.n + 1, #T.nearP do T.nearP[i], T.nearText[i] = nil, nil end
end

local function shown(me, p)
    if p:isDead() or p:getVehicle() ~= nil or p:IsSpeaking() then return false end
    if p == me then return not me:hasTimedActions() and me:getHaloTimerCount() <= 0 end
    if T.canSeeAll then return true end
    if p:isInvisible() or p:isDisguised() then return false end
    local sq = p:getCurrentSquare()
    return sq ~= nil and sq:getCanSee(0) and me:checkCanSeeClient(p)
end

function T.render()
    local n = T.n
    if n == 0 then return end
    local me = getSpecificPlayer(0)
    if me == nil then return end
    local tm = getTextManager()
    local zoom = getCore():getZoom(0)
    local lift = 64 * Core.getTileScale() / zoom   -- vanilla name anchor: 128 / (2 / tileScale), over the feet
    local half = 16 * Core.getTileScale() / zoom
    local lh = T.lineH or 16
    local c = T.COLOR
    local mx, my, tz, tx, ty
    for i = 1, n do
        local p = T.nearP[i]
        if shown(me, p) then
            local x, y, z = p:getX(), p:getY(), p:getZ()
            local sx = isoToScreenX(0, x, y, z)
            local foot = isoToScreenY(0, x, y, z)
            local top = foot - lift - p:getUserNameHeight() - lh - 1
            local hover = true
            if T.mouseOnly and p ~= me then
                mx = mx or getMouseX()
                my = my or getMouseY()
                hover = mx >= sx - half and mx <= sx + half and my >= top and my <= foot
                if not hover then
                    -- vanilla names the players on the 3 x 3 squares around the object under the mouse
                    -- (IsoGameCharacter.renderlast, IsoObjectPicker.ContextPick): the floor square stands in for it
                    local fz = math.floor(z)
                    if fz ~= tz then
                        tz = fz
                        tx, ty = math.floor(screenToIsoX(0, mx, my, fz)), math.floor(screenToIsoY(0, mx, my, fz))
                    end
                    hover = math.abs(tx - math.floor(x)) <= 1 and math.abs(ty - math.floor(y)) <= 1
                end
            end
            if hover then
                local text = T.nearText[i]
                tm:DrawStringCentre(UIFont.Small, sx + 1, top + 1, text, 0, 0, 0, 0.8)
                tm:DrawStringCentre(UIFont.Small, sx, top, text, c.r, c.g, c.b, 1)
            end
        end
    end
end

function T.onTick()
    local now = getTimestampMs()
    if T.lastScan ~= nil and now - T.lastScan < T.SCAN_MS then return end
    T.lastScan = now
    T.scan()
end

if first then
    C.on("titles", "titles", function(p) MinidoracatQuest.Titles.onTitles(p) end)
    C.on("catalog", "titles", function()
        local t = MinidoracatQuest.Titles
        t.text, t.chatMark = {}, {}
        t.lastScan = nil
    end)
    if ISChat ~= nil and type(ISChat.addLineInChat) == "function" then
        local orig = ISChat.addLineInChat
        ISChat.addLineInChat = function(message, tabID)
            return orig(MinidoracatQuest.Titles.wrap(message), tabID)
        end
    end
    Events.OnTick.Add(function() MinidoracatQuest.Titles.onTick() end)
    Events.OnPreUIDraw.Add(function() MinidoracatQuest.Titles.render() end)
end
