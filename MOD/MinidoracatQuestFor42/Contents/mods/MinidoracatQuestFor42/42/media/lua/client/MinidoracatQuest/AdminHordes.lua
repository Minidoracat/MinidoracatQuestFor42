-- MinidoracatQuest/AdminHordes.lua: admin tab "hordes" (design r10; ARCHITECTURE.md 6.2, 7).
-- Live status from horde.status (fetched each time the tab opens, after every action and by Refresh): the current
-- horde with Cancel / Stop, today's count and next roll, Start one now, the last 5 results. Below it the settings:
-- spots (add = towns.here, the admin's own position), window, chance, count, kind weights, time limit, reward. Every
-- setting goes through the draft and the bottom Apply (cfg.preview / cfg.apply), so History and config.json carry it;
-- horde.now / horde.stop act at once (IGUI_MQ_Admin_ImmediateNote). The server re-checks everything.

require "MinidoracatQuest/AdminPanel"

local MQ = MinidoracatQuest
local A = MQ.Admin
local AM = MQ.AdminModel
local formRow = A.formRow

local function summary(P, text)
    P.draftSummary = P.draftSummary and (P.draftSummary .. "; " .. text) or text
end

local function place(h) return MQ.Draw.hordePlace(h) end

-- the status is live: pg.loaded goes back to false, so the next visit to the tab asks again
local function load(P)
    local pg = P.pages.hordes
    pg.loaded = false
    A.send(P, "horde.status", {}, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

-- built-in kinds first (Contract.HORDE_KINDS), then what horde.status lists (kinds other mods registered)
local function kindList(P)
    local data = P.pages and P.pages.hordes and P.pages.hordes.data
    local out, seen = {}, {}
    local function add(id, nameKey)
        if seen[id] then return end
        seen[id] = true
        out[#out + 1] = { id = id, nameKey = nameKey }
    end
    for _, id in ipairs(MQ.Contract.HORDE_KINDS or {}) do add(id, "IGUI_MQ_Horde_Kind_" .. id) end
    for _, k in ipairs(data and type(data.kinds) == "table" and data.kinds or {}) do
        if type(k) == "table" and type(k.id) == "string" then add(k.id, k.nameKey) end
    end
    return out
end

local function kindName(k) return type(k.nameKey) == "string" and getTextOrNull(k.nameKey) or k.id end

-- also names the per-kind rows of a preview (A.pathLabel)
function A.hordeKindName(P, id)
    for _, k in ipairs(kindList(P)) do
        if k.id == id then return kindName(k) end
    end
    return id
end

-- ===== status =====

local function mixText(P, mix)
    local parts = {}
    for _, m in ipairs(type(mix) == "table" and mix or {}) do
        parts[#parts + 1] = (type(m.nameKey) == "string" and getTextOrNull(m.nameKey) or A.hordeKindName(P, tostring(m.kind)))
            .. " " .. A.num(tonumber(m.n) or 0)
    end
    return table.concat(parts, getText("IGUI_MQ_UI_ListSep"))
end

local function soon(c) return c.state == "planned" or c.state == "announced" end

local function curText(P, c)
    local st = getText("IGUI_MQ_Admin_HordeState_" .. tostring(c.state))
    if c.state == "active" then
        local n = tonumber(c.spawned) or 0
        return getText("IGUI_MQ_Admin_HordeCurLive", st, place(c), A.num(math.max(0, n - (tonumber(c.left) or 0))), A.num(n),
            A.time(c.endsAt))
    end
    local waiting = c.state == "waiting"
    return getText(waiting and "IGUI_MQ_Admin_HordeCurWait" or "IGUI_MQ_Admin_HordeCurSoon", st, place(c),
        A.time(waiting and c.expireAt or c.startMs), A.num(tonumber(c.count) or 0), mixText(P, c.mix))
end

local function rollText(roll)
    if roll.enabled ~= true then return getText("IGUI_MQ_Admin_HordeAutoOff") end
    local n, max = A.num(tonumber(roll.n) or 0), A.num(tonumber(roll.max) or 0)
    if tonumber(roll.nextAt) then return getText("IGUI_MQ_Admin_HordeToday", n, max, A.time(roll.nextAt)) end
    return getText("IGUI_MQ_Admin_HordeTodayDone", n, max)
end

local function resultText(e)
    local killed, spawned = A.num(tonumber(e.killed) or 0), A.num(tonumber(e.spawned) or 0)
    if e.state == "success" then return getText("IGUI_MQ_Admin_HordeRes_success", killed, spawned, A.num(tonumber(e.pool) or 0)) end
    if e.state == "cancelled" then return getText("IGUI_MQ_Admin_HordeRes_cancelled") end
    return getText("IGUI_MQ_Admin_HordeRes_failed", getText("IGUI_MQ_Admin_HordeWhy_" .. tostring(e.why)), killed, spawned)
end

local function afterOp(P, res, okKey)
    if res.ok then A.say(P, getText(okKey), "success") else A.fail(P, res) end
    load(P)
end

local function onStop(P, b)
    local c = b.cur
    local label = getText(soon(c) and "IGUI_MQ_Admin_HordeCancel" or "IGUI_MQ_Admin_HordeStop")
    A.ask(P, { title = label, confirm = label, danger = true,
        text = getText(soon(c) and "IGUI_MQ_Admin_HordeCancelAsk" or "IGUI_MQ_Admin_HordeStopAsk", place(c)),
        onOk = function()
            A.send(P, "horde.stop", { id = c.id }, function(res) afterOp(P, res, "IGUI_MQ_Admin_HordeStopped") end)
        end })
end

-- the server plans it from the applied settings: what waits in the draft is not used, and the dialog says so
local function onNow(P)
    local label = getText("IGUI_MQ_Admin_HordeNow")
    A.ask(P, { title = label, confirm = label, text = getText("IGUI_MQ_Admin_HordeNowAsk"), onOk = function()
        A.send(P, "horde.now", {}, function(res) afterOp(P, res, "IGUI_MQ_Admin_HordeStarted") end)
    end })
end

local function layoutStatus(P, pg, F)
    local d = pg.data
    F:head("hs", getText("IGUI_MQ_Admin_HordeStatusHead"))
    F:text("sn", getText("IGUI_MQ_Admin_HordeNowNote") .. " " .. getText("IGUI_MQ_Admin_ImmediateNote"), "textMuted")
    local cur = d and type(d.cur) == "table" and d.cur or nil
    if d == nil then
        F:text("sl", pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
    elseif cur then
        local stop = F:button("stop", getText(soon(cur) and "IGUI_MQ_Admin_HordeCancel" or "IGUI_MQ_Admin_HordeStop"), onStop, "danger")
        stop.cur = cur
        F:row({ F:label("cur", curText(P, cur), "text", nil, F.width - 2 * A.PAD - stop.width - A.GAP), stop })
    else
        F:text("cur", getText("IGUI_MQ_Admin_HordeNone"), "textMuted")
    end
    if d and type(d.roll) == "table" then F:text("roll", rollText(d.roll), "textMuted") end
    local now = F:button("now", getText("IGUI_MQ_Admin_HordeNow"), onNow, "primary")
    now:setEnabled(d ~= nil and cur == nil)
    F:row({ now, F:button("refresh", getText("IGUI_MQ_Admin_HordeRefresh"), load) })
    F:head("hl", getText("IGUI_MQ_Admin_HordeLogHead"))
    local log = d and type(d.log) == "table" and d.log or {}
    if d and #log == 0 then F:text("l0", getText("IGUI_MQ_Admin_HordeLogNone"), "textMuted") end
    for i = 1, math.min(5, #log) do
        local e = log[i]
        F:text("l" .. i, getText("IGUI_MQ_Admin_HordeLogRow", A.time(e.endedAt or e.startMs), place(e), resultText(e)))
    end
end

-- ===== spots (hordes.spots, a whole-set list in the draft) =====

local function onSpotRemove(P, b)
    local out = {}
    for i, s in ipairs(AM.get(P.S, "hordes.spots") or {}) do
        if i ~= b.spot then out[#out + 1] = AM.copy(s) end
    end
    AM.draftSet(P.S.draft, "hordes.spots", out)
    summary(P, getText("IGUI_MQ_Admin_HordeSumSpotDel", tostring(b.spotName)))
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

local function onSpotAdd(P)
    local el = P.pages.hordes.flow.pool["sp:name"]
    local name = string.match((string.gsub(el:getText() or "", "%c", "")), "^%s*(.-)%s*$")
    A.markError(P, el, name == "" and getText("IGUI_MQ_Admin_ErrName") or nil)
    if name == "" then return A.say(P, getText("IGUI_MQ_Admin_ErrName"), "errorText") end
    name = string.sub(name, 1, 64)
    A.send(P, "towns.here", {}, function(res)
        if not res.ok then return A.fail(P, res) end
        local list = AM.copy(AM.get(P.S, "hordes.spots")) or {}
        if #list >= AM.MAX_SPOTS then return A.say(P, getText("IGUI_MQ_Admin_HordeSpotsMax"), "errorText") end
        list[#list + 1] = { name = name, x = math.floor(tonumber(res.x) or 0), y = math.floor(tonumber(res.y) or 0),
            z = math.floor(tonumber(res.z) or 0) }
        AM.draftSet(P.S.draft, "hordes.spots", list)
        summary(P, getText("IGUI_MQ_Admin_HordeSumSpotAdd", name))
        el:setText("")
        A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
        A.layout(P)
    end)
end

local function layoutSpots(P, pg, F)
    F:head("hp", getText("IGUI_MQ_Admin_HordeSpotsHead"))
    F:text("pn", getText("IGUI_MQ_Admin_HordeSpotsNote"), "textMuted")
    local spots = AM.get(P.S, "hordes.spots") or {}
    if #spots == 0 then F:text("p0", getText("IGUI_MQ_Admin_HordeSpotsNone"), "warning") end
    for i, s in ipairs(spots) do
        local rm = F:button("pr" .. i, getText("IGUI_MQ_Admin_Remove"), onSpotRemove)
        rm.spot, rm.spotName = i, s.name
        F:row({ F:label("pl" .. i, tostring(s.name)),
            F:label("px" .. i, "(" .. tostring(s.x) .. ", " .. tostring(s.y) .. ", " .. tostring(s.z) .. ")", "textMuted"), rm })
    end
    local add = F:button("sp:add", getText("IGUI_MQ_Admin_HordeSpotHere"), onSpotAdd, "primary")
    add:setEnabled(#spots < AM.MAX_SPOTS)
    local label = getText("IGUI_MQ_Admin_HordeSpotName")
    formRow(F, "sp:name", label, A.textW(label) + A.GAP, { F:field("sp:name", 200, nil, 64), add })
    if #spots >= AM.MAX_SPOTS then F:text("pmax", getText("IGUI_MQ_Admin_HordeSpotsMax"), "warning") end
end

-- ===== settings =====

local PATHS = { "hordes.enabled", "hordes.from", "hordes.to", "hordes.chance", "hordes.maxPerDay", "hordes.leadMin",
    "hordes.waitMin", "hordes.count", "hordes.limitMin", "hordes.perZombie", "hordes.split" }

local function layoutSettings(P, pg, F)
    local kinds = kindList(P)
    local lw = A.labelWidth(PATHS)
    for _, k in ipairs(kinds) do lw = math.max(lw, math.min(A.textW(kindName(k)) + A.GAP, 260)) end
    local function row(path, ctrls) formRow(F, path, A.fLabel(path), lw, ctrls) end
    F:head("hc", getText("IGUI_MQ_Admin_HordeScheduleHead"))
    row("hordes.enabled", { A.boolField(P, pg, "hordes.enabled", "", "hordes.enabled") })
    row("hordes.from", { A.clockField(P, pg, "hordes.from", "hordes.from") })
    row("hordes.to", { A.clockField(P, pg, "hordes.to", "hordes.to") })
    A.form(P, pg, F, { { "hordes.chance", "hordeChance" }, { "hordes.maxPerDay", "hordePerDay" }, { "hordes.leadMin", "hordeLead" },
        { "hordes.waitMin", "hordeWait" } }, lw)
    F:head("hk", getText("IGUI_MQ_Admin_HordePackHead"))
    row("hordes.count", { A.numField(P, pg, "hordes.count.1", "hordes.count", { 1 }, "hordeCount"), F:label("cnt:d", "-", "textMuted"),
        A.numField(P, pg, "hordes.count.2", "hordes.count", { 2 }, "hordeCount") })
    F:text("kn", getText("IGUI_MQ_Admin_HordeKindsNote"), "textMuted")
    -- one weight per kind, each its own key under the hordes.kinds branch; an unset key means its default
    local defaults = MQ.Catalog.DEFAULTS.hordes.kinds or {}
    for _, k in ipairs(kinds) do
        local path = "hordes.kinds." .. k.id
        formRow(F, path, kindName(k), lw, { A.numField(P, pg, path, path, nil, "hordeWeight", nil, defaults[k.id] or 0) })
    end
    A.form(P, pg, F, { { "hordes.limitMin", "hordeLimit" }, { "hordes.perZombie", "hordePerZombie" } }, lw)
    F:text("pool", getText("IGUI_MQ_Admin_HordePoolNote"), "textMuted")
    row("hordes.split", { A.pickField(P, pg, "hordes.split", "hordes.split", {
        { id = "share", label = getText("IGUI_MQ_Admin_HordeSplit_share") },
        { id = "each", label = getText("IGUI_MQ_Admin_HordeSplit_each") } }) })
end

local function layout(P, pg, F)
    F:head("h", getText("IGUI_MQ_Admin_HordeHead"))
    F:text("n", getText("IGUI_MQ_Admin_HordeNote") .. " " .. A.tzNote(), "textMuted")
    layoutStatus(P, pg, F)
    layoutSpots(P, pg, F)
    layoutSettings(P, pg, F)
end

A.pages.hordes = { layout = layout, load = load }
