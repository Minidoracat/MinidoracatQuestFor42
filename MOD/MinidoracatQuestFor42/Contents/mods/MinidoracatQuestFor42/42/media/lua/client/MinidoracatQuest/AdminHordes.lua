-- MinidoracatQuest/AdminHordes.lua: admin tab "hordes" (design plan-hordes-1027 claims 1.1, 3, 4, 5.3; lists r11,
-- warning r12; ARCHITECTURE.md 6.2, 7).
-- Live status from horde.status (fetched each time the tab opens, after every action and by Refresh): the current
-- horde (wave W / N, rest countdown) with Cancel / Stop, today's count and next roll, Start a horde (with its warning
-- minutes), the last 5 results (a list box). Below it the settings, in the design's order: spots (a list box with a
-- Map button; add = towns.here, the admin's own position), windows (days, clock, chance per window), waves (base and
-- % per extra player, previews for 1 and 4 players), kinds (weight, computed share, points per kill), reward (the cap
-- and an estimate for 1 / 4 / 8 players). Every setting goes through the draft and the bottom Apply
-- (cfg.preview / cfg.apply), so History and config.json carry it; horde.now / horde.stop act at once
-- (IGUI_MQ_Admin_ImmediateNote). The server re-checks everything.

require "MinidoracatQuest/AdminPanel"

local MQ = MinidoracatQuest
local A = MQ.Admin
local AM = MQ.AdminModel
local formRow = A.formRow

local function summary(P, text)
    P.draftSummary = P.draftSummary and (P.draftSummary .. "; " .. text) or text
end

local function place(h) return MQ.Draw.hordePlace(h) end

-- the applied settings (no draft): what horde.now uses
local function applied(P, path) return AM.get({ overrides = P.S.overrides, defaults = P.S.defaults }, path) end

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

-- what a field shows now: its typed text when valid, else the draft value (previews, share and estimate follow typing).
-- A field the last layout left out is hidden and stale (a removed kind row): the draft value counts then.
local function live(pg, key, fallback)
    local f = pg.fields[key]
    if f and f.el and f.at == pg.version and f.el:isVisible() then
        local v = AM.check(f.el:getText(), f.range)
        if v ~= nil then return v end
    end
    return fallback
end

-- a field whose typed value feeds a preview: lay the tab out again on every change (TextField onChange, framework rev 7)
local function relayout() A.layout(A.instance) end
local function feeds(el)
    el.onChange = relayout
    return el
end

-- ===== status =====

local function soon(c) return c.state == "planned" or c.state == "announced" end

local function waveCount(c) return type(c.waves) == "table" and #c.waves or (tonumber(c.waves) or 0) end

-- the kinds with a weight in the horde's copy (no counts: they depend on who comes)
local function kindsText(P, weights)
    local parts = {}
    for _, k in ipairs(kindList(P)) do
        if type(weights) == "table" and (tonumber(weights[k.id]) or 0) > 0 then parts[#parts + 1] = kindName(k) end
    end
    return table.concat(parts, getText("IGUI_MQ_UI_ListSep"))
end

local function curText(P, c)
    local st = getText("IGUI_MQ_Admin_HordeState_" .. tostring(c.state))
    local w, n = A.num(tonumber(c.wave) or 1), A.num(waveCount(c))
    if c.state == "active" then
        return getText("IGUI_MQ_Admin_HordeCurActive", st, place(c), w, n, A.num(tonumber(c.killed) or 0),
            A.num(tonumber(c.size) or 0), A.time(c.endsAt))
    elseif c.state == "rest" then
        -- wave = the one just cleared; the countdown is as of this layout (Refresh updates it), on the server clock
        return getText("IGUI_MQ_Admin_HordeCurRest", st, place(c), w, n,
            MQ.Draw.countdown((tonumber(c.nextAt) or 0) - MQ.Client.serverNow()))
    elseif c.state == "waiting" then
        return getText("IGUI_MQ_Admin_HordeCurWaiting", st, place(c), w, n, A.time(c.expireAt))
    end
    return getText("IGUI_MQ_Admin_HordeCurPlan", st, place(c), A.time(c.startMs), n, kindsText(P, c.weights))
end

local function rollText(roll)
    if roll.enabled ~= true then return getText("IGUI_MQ_Admin_HordeAutoOff") end
    local n, max = A.num(tonumber(roll.n) or 0), A.num(tonumber(roll.max) or 0)
    if tonumber(roll.nextAt) then return getText("IGUI_MQ_Admin_HordeToday", n, max, A.time(roll.nextAt)) end
    return getText("IGUI_MQ_Admin_HordeTodayDone", n, max)
end

local function resultText(e)
    if e.state == "cancelled" then return getText("IGUI_MQ_Admin_HordeRes_cancelled") end
    local cleared, waves, pool = A.num(tonumber(e.cleared) or 0), A.num(tonumber(e.waves) or 0), A.num(tonumber(e.pool) or 0)
    local s
    if e.state == "success" then
        s = getText("IGUI_MQ_Admin_HordeResWin", cleared, waves, A.num(tonumber(e.killed) or 0), pool)
    else
        s = getText("IGUI_MQ_Admin_HordeResFail", getText("IGUI_MQ_Admin_HordeWhy_" .. tostring(e.why)), cleared, waves, pool)
    end
    if e.capped then s = s .. getText("IGUI_MQ_Admin_HordeCapped") end
    return s
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

-- the server plans it from the applied settings: what waits in the draft is not used, and the dialog says so.
-- lead (design r12): minutes of warning before it starts, 0 = now
local LEAD_MAX = MQ.Contract.LIMIT.MAX_LEAD

-- spots added in the draft are not saved yet: the server would refuse with "add a spot first" while the list shows
-- them (2026-10-26 playtest: three presses before Apply), so say to apply first and send nothing
local function spotsOnlyInDraft(P)
    return #(applied(P, "hordes.spots") or {}) == 0 and #(AM.get(P.S, "hordes.spots") or {}) > 0
end

local function onNow(P)
    local el = P.pages.hordes.flow.pool["now:lead"]
    local lead = tonumber(el and el:getText() or "")
    local bad = lead == nil or lead ~= math.floor(lead) or lead < 0 or lead > LEAD_MAX
    local msg = bad and getText("IGUI_MQ_Admin_ErrRange", "0", tostring(LEAD_MAX)) or nil
    A.markError(P, el, msg)
    if bad then return A.say(P, msg, "errorText") end
    if spotsOnlyInDraft(P) then return A.say(P, getText("IGUI_MQ_Admin_HordeSpotsUnapplied"), "errorText") end
    local label = getText("IGUI_MQ_Admin_HordeNow")
    local text = lead == 0 and getText("IGUI_MQ_Admin_HordeNowAskNow") or getText("IGUI_MQ_Admin_HordeNowAsk", tostring(lead))
    A.ask(P, { title = label, confirm = label, text = text, onOk = function()
        A.send(P, "horde.now", { lead = lead }, function(res) afterOp(P, res, "IGUI_MQ_Admin_HordeStarted") end)
    end })
end

-- the warning field: the applied hordes.leadMin until the admin types another value
local function leadField(P, pg, F)
    local tf = F:field("now:lead", 44, nil, 3)
    local lead = tostring(applied(P, "hordes.leadMin") or 0)
    if pg.leadSeed == nil or tf:getText() == pg.leadSeed then tf:setText(lead) end
    pg.leadSeed = lead
    return tf
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
    F:row({ F:label("now:l", getText("IGUI_MQ_Admin_HordeLead"), "text"), leadField(P, pg, F),
        F:label("now:u", getText("IGUI_MQ_Admin_HordeLeadUnit"), "text"), now, F:button("refresh", getText("IGUI_MQ_Admin_HordeRefresh"), load) })
    F:head("hl", getText("IGUI_MQ_Admin_HordeLogHead"))
    if d == nil then return end   -- the status line above says loading / the error
    local log = type(d.log) == "table" and d.log or {}
    local n = math.min(5, #log)
    local L = F:list("l")
    local places = {}
    for i = 1, n do places[i] = place(log[i]) end
    local timeW, placeW = A.timeW(), A.colW(places, math.floor(F.width / 3))
    local resX = A.PAD + timeW + placeW
    F:listHead({ { text = getText("IGUI_MQ_Admin_ColTime"), x = A.PAD }, { text = getText("IGUI_MQ_Admin_ColPlace"), x = A.PAD + timeW },
        { text = getText("IGUI_MQ_Admin_ColResult"), x = resX } })
    for i = 1, n do
        local e = log[i]
        F:item()
        F:cells("l" .. i, { { text = A.time(e.endedAt or e.startMs), x = A.PAD, token = "textMuted" },
            { text = places[i], x = A.PAD + timeW, w = placeW - A.GAP },
            { text = resultText(e), x = resX, w = F.width - A.PAD - resX, wrap = true,
                token = e.state == "success" and "success" or (e.state == "cancelled" and "textMuted" or "errorText") } })
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_HordeLogNone"))
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

-- design 5.3: the vanilla world map centred on the spot, so the admin checks it without walking there
local function onSpotMap(P, b)
    local pl = getPlayer()
    MQ.Draw.showOnMap(pl and pl:getPlayerNum() or 0, b.spotX, b.spotY)
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
    local map = MQ.Draw.mapAllowed()
    local L = F:list("p")
    local names, pos = {}, {}
    for i, s in ipairs(spots) do
        names[i], pos[i] = tostring(s.name), tostring(s.x) .. ", " .. tostring(s.y) .. ", " .. tostring(s.z)
    end
    -- the position column as wide as its widest value: the Map buttons line up (quest-hui-en-1027a)
    local nameW, posW = A.colW(names, math.floor(F.width / 3)), A.colW(pos, math.floor(F.width / 3))
    F:listHead({ { text = getText("IGUI_MQ_Admin_ColName"), x = A.PAD }, { text = getText("IGUI_MQ_Admin_ColPos"), x = A.PAD + nameW + A.GAP } })
    for i, s in ipairs(spots) do
        local rm = F:button("pr" .. i, getText("IGUI_MQ_Admin_Remove"), onSpotRemove)
        rm.spot, rm.spotName = i, s.name
        local nm = F:label("pl" .. i, names[i], nil, nil, nameW)
        nm:setWidth(nameW)
        local px = F:label("px" .. i, pos[i], "textMuted")
        px:setWidth(posW)
        local ctrls = { nm, px }
        if map then
            local mb = F:button("pm" .. i, getText("IGUI_MQ_UI_Map"), onSpotMap)
            mb:setTooltip(getText("IGUI_MQ_UI_ShowOnMap"))
            mb.spotX, mb.spotY = s.x, s.y
            ctrls[3] = mb
        end
        F:item()
        F:row(ctrls, nil, rm)
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_HordeSpotsNone"), "warning")
    local add = F:button("sp:add", getText("IGUI_MQ_Admin_HordeSpotHere"), onSpotAdd, "primary")
    add:setEnabled(#spots < AM.MAX_SPOTS)
    local label = getText("IGUI_MQ_Admin_HordeSpotName")
    formRow(F, "sp:name", label, A.textW(label) + A.GAP, { F:field("sp:name", 200, nil, 64), add })
    if #spots >= AM.MAX_SPOTS then F:text("pmax", getText("IGUI_MQ_Admin_HordeSpotsMax"), "warning") end
end

-- ===== whole-set lists (hordes.windows, hordes.waves) =====

-- add / remove / a day toggle: what is typed goes into the draft first (a field invalid: the bar says so, nothing
-- changes), then the list is edited and the fields read it again. A list back at its applied value leaves the draft.
local function editList(P, path, fn)
    if not A.fold(P) then return end
    local list = AM.copy(AM.get(P.S, path)) or {}
    fn(list)
    if AM.same(list, applied(P, path)) then AM.draftUnset(P.S.draft, path) else AM.draftSet(P.S.draft, path, list) end
    local pg = P.pages.hordes
    pg.version = pg.version + 1
    A.layout(P)
end

local function hasDay(w) return type(w.days) == "string" and w.days ~= "" end
local function dayOn(w, d) return type(w.days) == "string" and string.find(w.days, tostring(d), 1, true) ~= nil end

-- "1234567" -> the weekday names (1 = Monday, Draw.civil)
local function daysText(days)
    if days == "1234567" then return getText("IGUI_MQ_Admin_HordeEveryDay") end
    local parts = {}
    for d = 1, 7 do
        if string.find(tostring(days or ""), tostring(d), 1, true) then parts[#parts + 1] = getText("IGUI_MQ_UI_Weekday_" .. d) end
    end
    return table.concat(parts, getText("IGUI_MQ_UI_ListSep"))
end

-- preview rows (A.diffRows): a whole windows / waves value as one readable line
function A.hordeValue(path, v)
    if type(v) ~= "table" or (path ~= "hordes.windows" and path ~= "hordes.waves") then return v end
    local parts = {}
    for i, w in ipairs(v) do
        if path == "hordes.windows" then
            parts[i] = getText("IGUI_MQ_Admin_HordeWindowText", tostring(w.from), tostring(w.to), A.num(tonumber(w.chance) or 0),
                daysText(w.days))
        else
            parts[i] = getText("IGUI_MQ_Admin_HordeWaveText", A.num(tonumber(w.base) or 0), A.num(tonumber(w.perPlayer) or 0))
        end
    end
    return table.concat(parts, "; ")
end

-- ===== windows (claim 3) =====

local function onDay(P, b)
    editList(P, "hordes.windows", function(list)
        local w = list[b.win]
        if w == nil then return end
        local days = ""
        for d = 1, 7 do
            local on = dayOn(w, d)
            if d == b.day then on = not on end
            if on then days = days .. d end
        end
        w.days = days
    end)
end

local function onWindowAdd(P)
    editList(P, "hordes.windows", function(list)
        if #list < AM.MAX_WINDOWS then list[#list + 1] = AM.copy(MQ.Catalog.DEFAULTS.hordes.windows[1]) end
    end)
end

local function onWindowRemove(P, b)
    editList(P, "hordes.windows", function(list)
        if #list > 1 then table.remove(list, b.win) end
    end)
end

local function layoutWindows(P, pg, F, lw)
    F:head("hw", getText("IGUI_MQ_Admin_HordeWindowsHead"))
    F:text("wn", getText("IGUI_MQ_Admin_HordeWindowsNote") .. " " .. A.tzNote(), "textMuted")
    formRow(F, "hordes.enabled", A.fLabel("hordes.enabled"), lw, { A.boolField(P, pg, "hordes.enabled", "", "hordes.enabled") })
    local list = AM.get(P.S, "hordes.windows") or {}
    local L = F:list("w")
    for i, w in ipairs(list) do
        local key = "hordes.windows." .. i
        F:item()
        F:row({ A.clockField(P, pg, key .. ".from", "hordes.windows", { i, "from" }),
            F:label("w:t" .. i, getText("IGUI_MQ_Admin_HordeTo"), "textMuted"),
            A.clockField(P, pg, key .. ".to", "hordes.windows", { i, "to" }),
            F:label("w:c" .. i, getText("IGUI_MQ_Admin_HordeChance"), "textMuted"),
            A.numField(P, pg, key .. ".chance", "hordes.windows", { i, "chance" }, "hordeChance"),
            F:label("w:p" .. i, "%", "textMuted") })
        local chips = {}
        for d = 1, 7 do
            local b = F:button("w:d" .. i .. ":" .. d, getText("IGUI_MQ_UI_Weekday_" .. d), onDay, "chip")
            b.win, b.day = i, d
            b:setActive(dayOn(w, d))
            chips[d] = b
        end
        local rm = F:button("w:r" .. i, getText("IGUI_MQ_Admin_Remove"), onWindowRemove)
        rm.win = i
        rm:setEnabled(#list > 1)
        F:row(chips, nil, rm)
        -- no day: the server refuses the set; the page check stops Apply with the same text
        if not hasDay(w) then F:text("w:e" .. i, getText("IGUI_MQ_Admin_HordeErrDays"), "errorText") end
    end
    F:listEnd(L)
    local add = F:button("w:add", getText("IGUI_MQ_Admin_HordeWindowAdd"), onWindowAdd)
    add:setEnabled(#list < AM.MAX_WINDOWS)
    F:row({ add, F:label("w:max", getText("IGUI_MQ_Admin_HordeWindowsMax", AM.MAX_WINDOWS), "textMuted") })
    A.form(P, pg, F, { { "hordes.maxPerDay", "hordePerDay" }, { "hordes.leadMin", "hordeLead" }, { "hordes.waitMin", "hordeWait" } }, lw)
end

-- ===== waves (claims 1.1, 1.3, 1.4) =====

local function waveSize(pg, i, w, players)
    local key = "hordes.waves." .. i
    return MQ.Catalog.hordeWaveSize(tonumber(live(pg, key .. ".base", w.base)) or 1,
        tonumber(live(pg, key .. ".perPlayer", w.perPlayer)) or 0, players)
end

local function onWaveAdd(P)
    editList(P, "hordes.waves", function(list)
        if #list < AM.MAX_WAVES then list[#list + 1] = AM.copy(list[#list] or MQ.Catalog.DEFAULTS.hordes.waves[1]) end
    end)
end

local function onWaveRemove(P, b)
    editList(P, "hordes.waves", function(list)
        if #list > 1 then table.remove(list, b.wave) end
    end)
end

local function layoutWaves(P, pg, F, lw)
    F:head("hv", getText("IGUI_MQ_Admin_HordeWavesHead"))
    local list = AM.get(P.S, "hordes.waves") or {}
    local hIdx, hBase, hPer = getText("IGUI_MQ_Admin_HordeColWave"), getText("IGUI_MQ_Admin_HordeColBase"),
        getText("IGUI_MQ_Admin_HordeColPerPlayer")
    local h1, h4 = A.count("IGUI_MQ_Admin_HordeColPlayers", 1), A.count("IGUI_MQ_Admin_HordeColPlayers", 4)
    local wIdx = math.max(A.textW(hIdx), A.textW("10"))
    local wBase, wPer = math.max(60, A.textW(hBase)), 60
    -- one more gap after "%": the 1-player preview read as "%15" (CH) and its header touched "Per extra player"
    -- (EN, quest-hui-*-1027b)
    local wPct = math.max(A.textW("%"), A.textW(hPer) - wPer - A.GAP) + A.GAP
    local wP = math.max(A.textW(h1), A.textW(h4), A.textW(A.num(99999)))
    local L = F:list("v")
    local xB = A.PAD + wIdx + A.GAP
    local x1 = xB + wBase + A.GAP + wPer + A.GAP + wPct + A.GAP
    F:listHead({ { text = hIdx, x = A.PAD }, { text = hBase, x = xB }, { text = hPer, x = xB + wBase + A.GAP },
        { text = h1, x = x1 }, { text = h4, x = x1 + wP + A.GAP } })
    for i, w in ipairs(list) do
        local key = "hordes.waves." .. i
        local base = feeds(A.numField(P, pg, key .. ".base", "hordes.waves", { i, "base" }, "hordeBase", wBase))
        local per = feeds(A.numField(P, pg, key .. ".perPlayer", "hordes.waves", { i, "perPlayer" }, "hordePerPlayer", wPer))
        local idx = F:label("v:i" .. i, tostring(i))
        idx:setWidth(wIdx)
        local pct = F:label("v:pc" .. i, "%", "textMuted")
        pct:setWidth(wPct)
        local p1 = F:label("v:1:" .. i, A.num(waveSize(pg, i, w, 1)), "textMuted")
        p1:setWidth(wP)
        local p4 = F:label("v:4:" .. i, A.num(waveSize(pg, i, w, 4)), "textMuted")
        p4:setWidth(wP)
        local rm = F:button("v:r" .. i, getText("IGUI_MQ_Admin_Remove"), onWaveRemove)
        rm.wave = i
        rm:setEnabled(#list > 1)
        F:item()
        F:row({ idx, base, per, pct, p1, p4 }, nil, rm)
    end
    F:listEnd(L)
    F:text("vn", getText("IGUI_MQ_Admin_HordeWavesNote"), "textMuted")
    local add = F:button("v:add", getText("IGUI_MQ_Admin_HordeWaveAdd"), onWaveAdd)
    add:setEnabled(#list < AM.MAX_WAVES)
    F:row({ add, F:label("v:max", getText("IGUI_MQ_Admin_HordeWavesMax", AM.MAX_WAVES), "textMuted") })
    A.form(P, pg, F, { { "hordes.restSec", "hordeRest" }, { "hordes.limitMin", "hordeLimit" }, { "hordes.maxAlive", "hordeAlive" } }, lw)
    -- the sandbox ZombiesCountBeforeDelete the server read (nil: it could not)
    local cull = pg.data and tonumber(pg.data.cull)
    if cull then F:text("cull", getText("IGUI_MQ_Admin_HordeCull", A.num(cull)), "textMuted") end
end

-- ===== kinds (design r11 list box; claim 4): weight, share, points per kill =====

local KIND_START = 10   -- the weight a kind picked from the dropdown starts with; the admin edits it in its row

-- the built-in kinds have defaults (Catalog.DEFAULTS.hordes.kinds / points); a kind another mod registers has none
local function defaultsOf(P, group)
    local h = P.S.defaults and P.S.defaults.hordes
    return h and h[group] or {}
end

local function overridden(P, group, id)
    local h = P.S.overrides and P.S.overrides.hordes
    return h ~= nil and type(h[group]) == "table" and h[group][id] ~= nil
end

-- a key of a non-built-in kind: a "del" change when the applied config has it, else the draft forgets it
local function dropKey(P, group, id)
    local path = "hordes." .. group .. "." .. id
    if overridden(P, group, id) then AM.draftSet(P.S.draft, path, AM.DEL) else AM.draftUnset(P.S.draft, path) end
end

local function onKindAdd(P, id)
    if id == nil then return end
    AM.draftSet(P.S.draft, "hordes.kinds." .. id, KIND_START)
    -- no points of its own yet: it starts at what a regular zombie pays as shown (typed, else the draft's); the other
    -- typed fields stay unfolded, so a weight typed 0 keeps its row until Apply
    if AM.get(P.S, "hordes.points." .. id) == nil then
        local vanilla = AM.get(P.S, "hordes.points.vanilla")
        AM.draftSet(P.S.draft, "hordes.points." .. id, tonumber(live(P.pages.hordes, "hordes.points.vanilla", vanilla)) or 0)
    end
    -- a row removed and picked again shows the new values, not what was typed in it before the Remove
    for _, g in ipairs({ "kinds", "points" }) do
        local f = P.pages.hordes.fields["hordes." .. g .. "." .. id]
        if f then f.at = nil end
    end
    summary(P, getText("IGUI_MQ_Admin_HordeSumKindAdd", A.hordeKindName(P, id)))
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

-- Remove writes 0 on a built-in kind (its points stay); on the others it drops the weight and the points keys (a
-- "del" change), which also clears what a removed mod left in config.json. A kind only the draft has (picked, then
-- removed) just leaves the draft again.
local function onKindRemove(P, b)
    if defaultsOf(P, "kinds")[b.kind] ~= nil then
        AM.draftSet(P.S.draft, "hordes.kinds." .. b.kind, 0)
    else
        dropKey(P, "kinds", b.kind)
        dropKey(P, "points", b.kind)
    end
    -- picked and removed with nothing else pending: no summary or "in the draft" note for edits that cancel out
    if AM.draftCount(P.S.draft) == 0 then
        P.draftSummary = nil
        A.say(P, nil)
    else
        summary(P, getText("IGUI_MQ_Admin_HordeSumKindDel", b.kindName))
        A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    end
    A.layout(P)
end

-- keys the applied config still has for kinds no mod registers (the mod was removed): the server skips them
-- (Hordes.lua H.mix); known only once horde.status listed the registered kinds
local function orphans(P, kinds)
    local ov = P.S.overrides and P.S.overrides.hordes and P.S.overrides.hordes.kinds
    if type(ov) ~= "table" or P.pages.hordes.data == nil then return {} end
    local known, out = {}, {}
    for _, k in ipairs(kinds) do known[k.id] = true end
    for id in pairs(ov) do
        if not known[id] and AM.get(P.S, "hordes.kinds." .. id) ~= nil then out[#out + 1] = id end
    end
    MQ.Util.sort(out, function(a, b) return a < b end)
    return out
end

local function removeBtn(F, id, name)
    local rm = F:button("ks:r:" .. id, getText("IGUI_MQ_Admin_Remove"), onKindRemove)
    rm.kind, rm.kindName = id, name
    return rm
end

-- the installed kinds with a weight above 0 in the draft (the rows), with the weights as typed
local function weighted(P, pg, kinds)
    local rows, weights, total = {}, {}, 0
    for _, k in ipairs(kinds) do
        local path = "hordes.kinds." .. k.id
        local w = tonumber(AM.get(P.S, path)) or 0
        if w > 0 then
            rows[#rows + 1] = k
            weights[k.id] = tonumber(live(pg, path, w)) or 0
            total = total + weights[k.id]
        end
    end
    return rows, weights, total
end

-- points per kill as shown: the typed value, the draft's, else (no entry) what a regular zombie pays. A kind with no
-- points of its own whose field still shows the inherited value follows the vanilla field as typed, as the server
-- pays it (Hordes.lua: points[kind] or points.vanilla)
local function pointsOf(P, pg, id)
    local path = "hordes.points." .. id
    local seed = tonumber(AM.get(P.S, "hordes.points.vanilla")) or 0
    local vanilla = tonumber(live(pg, "hordes.points.vanilla", seed)) or 0
    local own = AM.get(P.S, path)
    local v = tonumber(live(pg, path, own))
    if own == nil and (v == nil or v == seed) then return vanilla end
    return v or vanilla
end

-- lw = the tab's label column: the name column is one PAD narrower, so the weights line up with the fields above
local function layoutKinds(P, pg, F, kinds, lw)
    F:head("hk", getText("IGUI_MQ_Admin_HordeKindsHead"))
    local wDef, pDef = defaultsOf(P, "kinds"), defaultsOf(P, "points")
    local rows, weights, total = weighted(P, pg, kinds)
    local hW, hS, hP = getText("IGUI_MQ_Admin_ColWeight"), getText("IGUI_MQ_Admin_HordeColShare"), getText("IGUI_MQ_Admin_HordeColPoints")
    local cw = lw - A.PAD
    local wW = 60
    local wS = math.max(A.textW(hS), A.textW(getText("IGUI_MQ_Admin_HordePct", 100)))
    local wP = math.max(60, A.textW(hP))
    local vanillaPts = tonumber(AM.get(P.S, "hordes.points.vanilla")) or 0
    local L = F:list("ks")
    local xW = A.PAD + cw + A.GAP
    F:listHead({ { text = getText("IGUI_MQ_Admin_ColKind"), x = A.PAD }, { text = hW, x = xW }, { text = hS, x = xW + wW + A.GAP },
        { text = hP, x = xW + wW + A.GAP + wS + A.GAP } })
    local inRows = {}
    for _, k in ipairs(rows) do
        inRows[k.id] = true
        local name = kindName(k)
        local wPath, pPath = "hordes.kinds." .. k.id, "hordes.points." .. k.id
        local nm = F:label("ks:n:" .. k.id, name, nil, nil, cw - A.GAP)
        nm:setWidth(cw)
        local wf = feeds(A.numField(P, pg, wPath, wPath, nil, "hordeWeight", wW, wDef[k.id] or 0))
        local share = total > 0 and math.floor(weights[k.id] * 100 / total + 0.5) or 0
        local sl = F:label("ks:s:" .. k.id, getText("IGUI_MQ_Admin_HordePct", share), "textMuted")
        sl:setWidth(wS)
        local pf = feeds(A.numField(P, pg, pPath, pPath, nil, "hordePoints", wP, pDef[k.id] or vanillaPts))
        F:item()
        F:row({ nm, wf, sl, pf }, nil, removeBtn(F, k.id, name))
    end
    local add = {}
    for _, k in ipairs(kinds) do
        if not inRows[k.id] then add[#add + 1] = { id = k.id, label = kindName(k) } end
    end
    for _, id in ipairs(orphans(P, kinds)) do
        local nm = F:label("ks:o:" .. id, id, "textFaint", nil, cw - A.GAP)
        nm:setWidth(cw)
        F:item()
        F:row({ nm, F:label("ks:w:" .. id, A.num(tonumber(AM.get(P.S, "hordes.kinds." .. id)) or 0), "textFaint"),
            F:label("ks:g:" .. id, getText("IGUI_MQ_Admin_HordeKindGone"), "warning") }, nil, removeBtn(F, id, id))
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_HordeKindsNone"))
    -- no width: as wide as the placeholder or the longest kind name (Dropdown.lua naturalWidth)
    if #add > 0 then
        F:row({ F:dropdown("ks:add", add, nil, onKindAdd, getText("IGUI_MQ_Admin_HordeKindAdd")) })
    else
        F:text("ks:all", getText("IGUI_MQ_Admin_HordeKindsAll"), "textMuted")
    end
    F:text("kn", getText("IGUI_MQ_Admin_HordeKindsNote"), "textMuted")
end

-- ===== reward (claim 4): the cap and what the settings pay =====

local EST_PLAYERS = { 1, 4, 8 }

-- points one horde pays with every wave cleared by `players` players, before the cap (the server's sizes and mix:
-- Catalog.hordeWaveSize / hordeMix; points per kill, no entry = points.vanilla)
function A.hordeEstimate(P, pg, kinds, players)
    local C = MQ.Catalog
    local rows, weights = weighted(P, pg, kinds)
    local ids = {}
    for i, k in ipairs(rows) do ids[i] = k.id end
    local value = 0
    for i, w in ipairs(AM.get(P.S, "hordes.waves") or {}) do
        for _, m in ipairs(C.hordeMix(ids, weights, waveSize(pg, i, w, players))) do
            value = value + m.n * pointsOf(P, pg, m.kind)
        end
    end
    return value
end

local function layoutReward(P, pg, F, kinds, lw)
    F:head("hr", getText("IGUI_MQ_Admin_HordeRewardHead"))
    formRow(F, "hordes.cap", A.fLabel("hordes.cap"), lw, { feeds(A.numField(P, pg, "hordes.cap", "hordes.cap", nil, "hordeCap")) })
    F:text("rn", getText("IGUI_MQ_Admin_HordeRewardNote"), "textMuted")
    local cap = tonumber(live(pg, "hordes.cap", AM.get(P.S, "hordes.cap"))) or 0
    local parts = {}
    for i, n in ipairs(EST_PLAYERS) do
        local v = A.hordeEstimate(P, pg, kinds, n)
        -- key .. "1" = the singular (A.count)
        local key = v > cap and "IGUI_MQ_Admin_HordeEstCap" or "IGUI_MQ_Admin_HordeEst"
        parts[i] = getText(n == 1 and key .. "1" or key, n, A.num(math.min(v, cap)))
    end
    F:text("est", table.concat(parts, "   "), "text", nil, "success", getText("IGUI_MQ_Admin_HordeEstHead"))
end

-- ===== the tab =====

local PATHS = { "hordes.enabled", "hordes.maxPerDay", "hordes.leadMin", "hordes.waitMin", "hordes.restSec",
    "hordes.limitMin", "hordes.maxAlive", "hordes.cap" }

local function layout(P, pg, F)
    F:head("h", getText("IGUI_MQ_Admin_HordeHead"))
    F:text("n", getText("IGUI_MQ_Admin_HordeNote"), "textMuted")
    layoutStatus(P, pg, F)
    layoutSpots(P, pg, F)
    local kinds = kindList(P)
    local lw = A.labelWidth(PATHS)
    for _, k in ipairs(kinds) do lw = math.max(lw, math.min(A.textW(kindName(k)) + A.GAP, 260)) end
    layoutWindows(P, pg, F, lw)
    layoutWaves(P, pg, F, lw)
    layoutKinds(P, pg, F, kinds, lw)
    layoutReward(P, pg, F, kinds, lw)
end

-- Apply: every window needs a day (the server refuses an empty days string)
local function check(P)
    for _, w in ipairs(AM.get(P.S, "hordes.windows") or {}) do
        if not hasDay(w) then return getText("IGUI_MQ_Admin_HordeErrDays") end
    end
    return nil
end

A.pages.hordes = { layout = layout, load = load, check = check }
