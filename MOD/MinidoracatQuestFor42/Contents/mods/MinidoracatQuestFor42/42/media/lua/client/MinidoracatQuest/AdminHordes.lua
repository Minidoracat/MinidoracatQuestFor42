-- MinidoracatQuest/AdminHordes.lua: admin tab "hordes" (design plan-hordes-1027 claims 1.1, 3, 4, 5.3; plan-presets-1028;
-- lists r11, warning r12; ARCHITECTURE.md 6.2, 7).
-- Live status from horde.status (fetched each time the tab opens, after every action and by Refresh): the current
-- horde (wave W / N, next wave time, its preset) with Cancel / Stop, today's count and next roll, Start a horde (an
-- applied preset, its warning and wait minutes), the last 5 results (a list box). Below it the settings: spots (a
-- list box with a Map button; add = towns.here, the admin's own position), windows (days, clock, chance, preset,
-- warning and wait minutes per window), presets (the one the page edits, copy, delete, its name, the windows using
-- it), then that preset's waves (base and % per extra player, previews for 1 and 4 players), kinds (weight, computed
-- share, points per kill, toughness) and reward (the cap and an estimate for 1 / 4 / 8 players). Every setting goes
-- through the draft and the bottom Apply (cfg.preview / cfg.apply), so History and config.json carry it;
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

local function inDraft(P)
    if AM.draftCount(P.S.draft) == 0 then A.say(P, nil) else A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted") end
end

-- the applied settings (no draft): what horde.now uses
local function appliedS(P) return { overrides = P.S.overrides, defaults = P.S.defaults } end
local function applied(P, path) return AM.get(appliedS(P), path) end
-- in the applied overrides themselves (not a default): a key there is removed with a "del" change
local function overridden(P, path) return AM.get({ overrides = P.S.overrides, defaults = {} }, path) ~= nil end

-- the status is live: pg.loaded goes back to false, so the next visit to the tab asks again
local function load(P)
    local pg = P.pages.hordes
    pg.loaded = false
    A.send(P, "horde.status", {}, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

-- ===== presets (hordes.presets; the page edits one: P.pages.hordes.preset, page state, not a setting) =====

local MAPS = { kinds = true, points = true, hp = true }

local function maxPresets() return MQ.Contract.LIMIT.MAX_PRESETS end

-- the built-in default preset (Catalog): what an unset field of the default preset means, and what a new or copied
-- preset starts from; another preset is complete (Config.migrate fills what config.json leaves out)
local function base() return MQ.Catalog.DEFAULTS.hordes.presets.default end

-- the presets S shows ("default" first, then by id); a preset deleted in the draft is gone
local function presetIds(S)
    local seen, ids = {}, {}
    local function add(id)
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, tree in ipairs({ S.defaults, S.overrides }) do
        local t = tree and tree.hordes and tree.hordes.presets
        for id in pairs(type(t) == "table" and t or {}) do add(id) end
    end
    for _, path in ipairs(S.draft and S.draft.order or {}) do
        local id = string.match(path, "^hordes%.presets%.([^%.]+)")
        if id then add(id) end
    end
    local out = {}
    for _, id in ipairs(ids) do
        if AM.get(S, "hordes.presets." .. id) ~= nil then out[#out + 1] = id end
    end
    MQ.Util.sort(out, function(a, b)
        if a == "default" or b == "default" then return a == "default" and b ~= "default" end
        return a < b
    end)
    return out
end

-- "" (and no name at all) reads as the translated "Default" for the default preset, else as its id. A preset deleted
-- in the draft keeps its applied name, so the "before" side of a preview names it
local function nameOf(S, id)
    local path = "hordes.presets." .. id .. ".name"
    local n = AM.get(S, path)
    if n == nil and S.draft then n = AM.get({ overrides = S.overrides, defaults = S.defaults }, path) end
    if type(n) == "string" and n ~= "" then return n end
    return id == "default" and getText("IGUI_MQ_Admin_HordePresetDefault") or id
end

-- also names the preset rows of a preview and of a refusal (A.pathLabel)
function A.hordePresetName(P, id) return nameOf(P.S, id) end

-- the preset the page edits; back to "default" when it is gone (discarded, deleted)
local function current(P, ids)
    local pg = P.pages.hordes
    local found = false
    for _, id in ipairs(ids or presetIds(P.S)) do found = found or id == pg.preset end
    if not found then pg.preset = "default" end
    return pg.preset
end

local function pre(P) return "hordes.presets." .. current(P) end

-- what an unset key of the edited preset's map means: the default preset reads the Catalog defaults key by key
-- (Config merges it); every other preset is complete (the server fills and checks it, presetPart), so an unset key
-- there is just unset (hp: 1x)
local function defaultsOf(P, group)
    if current(P) == "default" then return base()[group] or {} end
    return {}
end

-- a key of the edited preset's map as the server plays it
local function mapGet(P, group, k)
    local v = AM.get(P.S, pre(P) .. "." .. group .. "." .. k)
    if v == nil then v = defaultsOf(P, group)[k] end
    return v
end

-- the windows (draft) whose preset is id
local function windowsOf(P, id)
    local out = {}
    for i, w in ipairs(AM.get(P.S, "hordes.windows") or {}) do
        if w.preset == id then out[#out + 1] = { i = i, w = w } end
    end
    return out
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

-- a number field as wide as its largest value with the error mark shown (interface review M3): at least minW (60)
local function numW(range, minW)
    return math.max(minW or 60, A.textW(AM.num(AM.RANGE[range][2])) + A.FIELD_CHROME)
end

-- "max N" beside an Add button: the warning colour once it is reached (interface review)
local function maxLabel(F, key, text, full) return F:label(key, text, full and "warning" or "textMuted") end

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

-- the horde's copy names its preset ("" = the default one)
local function curPreset(c)
    return type(c.preset) == "string" and c.preset ~= "" and c.preset or getText("IGUI_MQ_Admin_HordePresetDefault")
end

local function curText(P, c)
    local st = getText("IGUI_MQ_Admin_HordeState_" .. tostring(c.state))
    local w, n = A.num(tonumber(c.wave) or 1), A.num(waveCount(c))
    if c.state == "active" then
        return getText("IGUI_MQ_Admin_HordeCurActive", st, place(c), w, n, A.num(tonumber(c.killed) or 0),
            A.num(tonumber(c.size) or 0), A.time(c.endsAt))
    elseif c.state == "rest" then
        -- wave = the one just cleared; a clock time, not a countdown: the line is laid out once and stays on screen
        return getText("IGUI_MQ_Admin_HordeCurRest", st, place(c), w, n, A.time(c.nextAt))
    elseif c.state == "waiting" then
        return getText("IGUI_MQ_Admin_HordeCurWaiting", st, place(c), w, n, A.time(c.expireAt))
    end
    return getText("IGUI_MQ_Admin_HordeCurPlan", st, place(c), A.time(c.startMs), n, kindsText(P, c.weights), curPreset(c))
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
    -- before it starts the action is "Cancel this horde": the way out must not be called Cancel too
    A.ask(P, { title = label, confirm = label, danger = true, cancel = soon(c) and getText("IGUI_MQ_Admin_HordeKeep") or nil,
        text = getText(soon(c) and "IGUI_MQ_Admin_HordeCancelAsk" or "IGUI_MQ_Admin_HordeStopAsk", place(c)),
        onOk = function()
            A.send(P, "horde.stop", { id = c.id }, function(res) afterOp(P, res, "IGUI_MQ_Admin_HordeStopped") end)
        end })
end

-- spots added in the draft are not saved yet: the server would refuse with "add a spot first" while the list shows
-- them (2026-10-26 playtest: three presses before Apply), so say to apply first and send nothing
local function spotsOnlyInDraft(P)
    return #(applied(P, "hordes.spots") or {}) == 0 and #(AM.get(P.S, "hordes.spots") or {}) > 0
end

-- the preset Start a horde plays: an applied one (the server plans from the applied settings, like the spots above)
local function nowPreset(P, ids)
    local pg = P.pages.hordes
    for _, id in ipairs(ids or presetIds(appliedS(P))) do
        if id == pg.nowPre then return id end
    end
    return "default"
end

-- the server plans it from the applied settings: what waits in the draft is not used, and the dialog says so.
-- lead (design r12): minutes of warning before it starts, 0 = now; wait: minutes each wave waits for a player
local function onNow(P)
    local pool = P.pages.hordes.flow.pool
    local leadEl, waitEl = pool["now:lead"], pool["now:wait"]
    -- the same ranges and messages as a window's leadMin / waitMin (Config)
    local lead, lk, llo, lhi = AM.check(leadEl:getText(), "hordeLead")
    local wait, wk, wlo, whi = AM.check(waitEl:getText(), "hordeWait")
    if A.markAll(P, { { leadEl, lead == nil and getText(lk, AM.num(llo), AM.num(lhi)) or nil },
        { waitEl, wait == nil and getText(wk, AM.num(wlo), AM.num(whi)) or nil } }) then return end
    if spotsOnlyInDraft(P) then return A.say(P, getText("IGUI_MQ_Admin_HordeSpotsUnapplied"), "errorText") end
    A.say(P, nil)
    local id = nowPreset(P)
    local name = nameOf(appliedS(P), id)
    local label = getText("IGUI_MQ_Admin_HordeNow")
    local text = lead == 0 and getText("IGUI_MQ_Admin_HordeNowAskNow", name) or getText("IGUI_MQ_Admin_HordeNowAsk", name, tostring(lead))
    A.ask(P, { title = label, confirm = label, text = text, onOk = function()
        A.send(P, "horde.now", { lead = lead, wait = wait, preset = id }, function(res) afterOp(P, res, "IGUI_MQ_Admin_HordeStarted") end)
    end })
end

local function onNowPreset(P, id) P.pages.hordes.nowPre = id end

-- the Start a horde row: preset, warning and wait minutes. The fields start at a new window's values
-- (Catalog.DEFAULTS.hordes.windows[1]) and keep what the admin typed
local function nowRow(P, pg, F)
    local ids = presetIds(appliedS(P))
    local opts = {}
    for i, id in ipairs(ids) do opts[i] = { id = id, label = nameOf(appliedS(P), id) } end
    local lead = F:field("now:lead", numW("hordeLead", 44), nil, 3)
    local wait = F:field("now:wait", numW("hordeWait", 44), nil, 3)
    if not pg.nowSeeded then
        local w = MQ.Catalog.DEFAULTS.hordes.windows[1]
        lead:setText(tostring(w.leadMin))
        wait:setText(tostring(w.waitMin))
        pg.nowSeeded = true
    end
    local now = F:button("now", getText("IGUI_MQ_Admin_HordeNow"), onNow, "primary")
    now:setEnabled(pg.data ~= nil and type(pg.data.cur) ~= "table")
    local unit = getText("IGUI_MQ_Admin_HordeLeadUnit")
    F:row({ F:label("now:pl", getText("IGUI_MQ_Admin_HordePreset"), "text"), F:dropdown("now:pre", opts, nowPreset(P, ids), onNowPreset),
        F:label("now:l", getText("IGUI_MQ_Admin_HordeLead"), "text"), lead, F:label("now:u", unit, "text"),
        F:label("now:wl", getText("IGUI_MQ_Admin_HordeWait"), "text"), wait, F:label("now:wu", unit, "text"),
        now, F:button("refresh", getText("IGUI_MQ_Admin_HordeRefresh"), load) })
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
        -- the button keeps the row's end whatever the language and the state (review)
        F:row({ F:label("cur", curText(P, cur), "text", nil, F.width - 2 * A.PAD - stop.width - A.GAP) }, nil, stop)
    else
        F:text("cur", getText("IGUI_MQ_Admin_HordeNone"), "textMuted")
    end
    if d and type(d.roll) == "table" then F:text("roll", rollText(d.roll), "textMuted") end
    nowRow(P, pg, F)
    F:head("hl", getText("IGUI_MQ_Admin_HordeLogHead"))
    local log = d and type(d.log) == "table" and d.log or {}
    local n = math.min(5, #log)
    local L = F:list("l")
    -- the column header once the results are in; until then the box says loading (or why it could not)
    if d then
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
                { text = places[i], x = A.PAD + timeW, w = placeW - A.GAP, wrap = true },
                { text = resultText(e), x = resX, w = F.width - A.PAD - resX, wrap = true,
                    token = e.state == "success" and "success" or (e.state == "cancelled" and "textMuted" or "errorText") } })
        end
        F:listEnd(L, getText("IGUI_MQ_Admin_HordeLogNone"))
    else
        F:listEnd(L, pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or nil)
    end
end

-- ===== spots (hordes.spots, a whole-set list in the draft) =====

-- asks first: a removed spot comes back only by walking there again (review). It goes by the spot as shown when asked,
-- not by its row: a push while the dialog is open relays the list and this button's index with it (review r2)
local function onSpotRemove(P, b)
    local spot, name = AM.copy((AM.get(P.S, "hordes.spots") or {})[b.spot]), b.spotName
    A.ask(P, { title = getText("IGUI_MQ_Admin_HordeSpotDelTitle", tostring(name)), danger = true,
        text = getText("IGUI_MQ_Admin_HordeSpotDelAsk") .. "\n\n" .. getText("IGUI_MQ_Admin_AfterApply"),
        confirm = getText("IGUI_MQ_Admin_HordeSpotDel"), cancel = getText("IGUI_MQ_Admin_Keep"), onOk = function()
            local out, gone = {}, false
            for _, s in ipairs(AM.get(P.S, "hordes.spots") or {}) do
                if not gone and AM.same(s, spot) then gone = true else out[#out + 1] = AM.copy(s) end
            end
            -- removed elsewhere meanwhile: nothing left to remove
            if not gone then return A.layout(P) end
            AM.draftSet(P.S.draft, "hordes.spots", out)
            summary(P, getText("IGUI_MQ_Admin_HordeSumSpotDel", tostring(name)))
            A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
            A.layout(P)
        end })
end

-- design 5.3: the vanilla world map centred on the spot, so the admin checks it without walking there
local function onSpotMap(P, b)
    local pl = getPlayer()
    MQ.Draw.showOnMap(pl and pl:getPlayerNum() or 0, b.spotX, b.spotY)
end

local function onSpotAdd(P)
    local el = P.pages.hordes.flow.pool["sp:name"]
    local name = A.cleanText(el:getText())
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

local function layoutSpots(P, pg, F, lw)
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
    -- gold stays for Start a horde and Apply (review)
    local add = F:button("sp:add", getText("IGUI_MQ_Admin_HordeSpotHere"), onSpotAdd)
    add:setEnabled(#spots < AM.MAX_SPOTS)
    formRow(F, "sp:name", getText("IGUI_MQ_Admin_HordeSpotName"), lw, { F:field("sp:name", 200, nil, 64), add })
    if #spots >= AM.MAX_SPOTS then F:text("pmax", getText("IGUI_MQ_Admin_HordeSpotsMax"), "warning") end
end

-- ===== whole-set lists (hordes.windows, a preset's waves) =====

-- add / remove / a day toggle: what is typed goes into the draft first (a field invalid: the bar says so, nothing
-- changes), then the list is edited and the fields read it again. A list back at its applied value leaves the draft,
-- unless its preset is a whole value in the draft (copied in): then the list stays in that value.
local function editList(P, path, fn)
    if not A.fold(P) then return A.layout(P) end
    local list = AM.copy(AM.get(P.S, path)) or {}
    fn(list)
    local whole = string.match(path, "^(hordes%.presets%.[^%.]+)%.")
    if AM.same(list, applied(P, path)) and not (whole and P.S.draft.by[whole]) then
        AM.draftUnset(P.S.draft, path)
    else
        AM.draftSet(P.S.draft, path, list)
    end
    -- the bar no longer says a field is wrong (interface review M1)
    inDraft(P)
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

-- "Mon, Tue 20:00-23:00": a window in the presets section and the delete dialog
local function windowShort(w) return getText("IGUI_MQ_Admin_HordeWindowShort", daysText(w.days), tostring(w.from), tostring(w.to)) end

-- preview rows: a whole windows / waves value as one readable line (presets named as the draft names them)
function A.hordeValue(P, path, v)
    if type(v) ~= "table" then return v end
    local parts = {}
    if path == "hordes.windows" then
        for i, w in ipairs(v) do
            parts[i] = getText("IGUI_MQ_Admin_HordeWindowText", tostring(w.from), tostring(w.to), A.num(tonumber(w.chance) or 0),
                daysText(w.days), nameOf(P.S, tostring(w.preset)), A.num(tonumber(w.leadMin) or 0), A.num(tonumber(w.waitMin) or 0))
        end
    elseif string.match(path, "^hordes%.presets%.[^%.]+%.waves$") then
        for i, w in ipairs(v) do
            parts[i] = getText("IGUI_MQ_Admin_HordeWaveText", A.num(tonumber(w.base) or 0), A.num(tonumber(w.perPlayer) or 0))
        end
    else
        return v
    end
    return table.concat(parts, "; ")
end

-- a preview row (A.diffRows) of a horde path that needs more than the value: whole windows / waves, a whole preset
-- added or deleted ("Add preset "Hard""). nil = an ordinary row
local function presetText(id, v)
    if type(v) ~= "table" then return nil end
    if type(v.name) == "string" and v.name ~= "" then return v.name end
    return id == "default" and getText("IGUI_MQ_Admin_HordePresetDefault") or id
end

function A.hordeRow(P, r, label)
    local path = tostring(r.path)
    local id = string.match(path, "^hordes%.presets%.([^%.]+)$")
    if id then
        local b, a = presetText(id, r.before), presetText(id, r.after)
        if a == nil then
            label = getText("IGUI_MQ_Admin_HordePresetDelRow", b or id)
        elseif b == nil then
            label = getText("IGUI_MQ_Admin_HordePresetAddRow", a)
        end
        return { label = label, before = A.valueText(b), after = A.valueText(a) }
    end
    if path == "hordes.windows" or string.match(path, "^hordes%.presets%.[^%.]+%.waves$") then
        return { label = label, before = A.valueText(A.hordeValue(P, path, r.before)), after = A.valueText(A.hordeValue(P, path, r.after)) }
    end
    return nil
end

-- ===== windows (claim 3; plan-presets-1028: a preset, warning and wait minutes per window) =====

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

local function onWindowPreset(P, id, dd)
    editList(P, "hordes.windows", function(list)
        if list[dd.win] then list[dd.win].preset = id end
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

local function presetOptions(P, ids)
    local opts = {}
    for i, id in ipairs(ids) do opts[i] = { id = id, label = nameOf(P.S, id) } end
    return opts
end

local function layoutWindows(P, pg, F, lw, ids)
    F:head("hw", getText("IGUI_MQ_Admin_HordeWindowsHead"))
    F:text("wn", getText("IGUI_MQ_Admin_HordeWindowsNote") .. " " .. A.tzNote(), "textMuted")
    -- the label is the box's own: a click on the words toggles it too (review)
    F:row({ A.boolField(P, pg, "hordes.enabled", A.fLabel("hordes.enabled"), "hordes.enabled") })
    local list = AM.get(P.S, "hordes.windows") or {}
    local opts = presetOptions(P, ids)
    local unit = getText("IGUI_MQ_Admin_HordeLeadUnit")
    local L = F:list("w")
    for i, w in ipairs(list) do
        local key = "hordes.windows." .. i
        F:item()
        F:row({ A.clockField(P, pg, key .. ".from", "hordes.windows", { i, "from" }),
            F:label("w:t" .. i, getText("IGUI_MQ_Admin_HordeTo"), "textMuted"),
            A.clockField(P, pg, key .. ".to", "hordes.windows", { i, "to" }),
            F:label("w:c" .. i, getText("IGUI_MQ_Admin_HordeChance"), "textMuted"),
            A.numField(P, pg, key .. ".chance", "hordes.windows", { i, "chance" }, "hordeChance", numW("hordeChance")),
            F:label("w:pc" .. i, "%", "textMuted") })
        local dd = F:dropdown("w:p" .. i, opts, w.preset, onWindowPreset)
        dd.win = i
        F:row({ F:label("w:pl" .. i, getText("IGUI_MQ_Admin_HordePreset"), "textMuted"), dd,
            F:label("w:ll" .. i, getText("IGUI_MQ_Admin_HordeLead"), "textMuted"),
            A.numField(P, pg, key .. ".leadMin", "hordes.windows", { i, "leadMin" }, "hordeLead", numW("hordeLead")),
            F:label("w:lu" .. i, unit, "textMuted"),
            F:label("w:wl" .. i, getText("IGUI_MQ_Admin_HordeWait"), "textMuted"),
            A.numField(P, pg, key .. ".waitMin", "hordes.windows", { i, "waitMin" }, "hordeWait", numW("hordeWait")),
            F:label("w:wu" .. i, unit, "textMuted") })
        local chips = {}
        for d = 1, 7 do
            local b = F:button("w:d" .. i .. ":" .. d, getText("IGUI_MQ_UI_Weekday_" .. d), onDay, "chip")
            b.win, b.day = i, d
            -- one Tab stop per window, arrows inside (framework Focus _focusGroup, rev 10): 8 windows were 56 stops
            b._focusGroup = "w:d" .. i
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
    F:row({ add, maxLabel(F, "w:max", getText("IGUI_MQ_Admin_HordeWindowsMax", AM.MAX_WINDOWS), #list >= AM.MAX_WINDOWS) })
    formRow(F, "hordes.maxPerDay", A.fLabel("hordes.maxPerDay"), lw,
        { A.numField(P, pg, "hordes.maxPerDay", "hordes.maxPerDay", nil, "hordePerDay", numW("hordePerDay")) })
end

-- ===== presets section (plan-presets-1028 claim 1) =====

-- switching folds what is typed first (a field invalid: the bar says so and the page stays)
local function onPresetPick(P, id)
    local pg = P.pages.hordes
    if id == pg.preset then return end
    if not A.fold(P) then return A.layout(P) end
    pg.preset = id
    pg.version = pg.version + 1
    A.layout(P)
end

-- every field of preset id as the server plays it: maps key by key, a field it lacks from the default preset
local function fullPreset(P, id)
    local path = "hordes.presets." .. id
    local out = {}
    for k, v in pairs(base()) do
        local kp = path .. "." .. k
        if MAPS[k] then
            local keys, seen = {}, {}
            local function add(t)
                for key in pairs(type(t) == "table" and t or {}) do
                    if not seen[key] then seen[key] = true; keys[#keys + 1] = key end
                end
            end
            local whole = AM.get(P.S, kp)
            add(whole)
            if id == "default" or whole == nil then add(v) end
            add(AM.get({ overrides = P.S.overrides, defaults = {} }, kp))
            for _, dp in ipairs(P.S.draft.order) do
                local key = string.sub(dp, 1, #kp + 1) == kp .. "." and string.sub(dp, #kp + 2) or nil
                if key and not string.find(key, ".", 1, true) then add({ [key] = true }) end
            end
            local m = {}
            for _, key in ipairs(keys) do
                local x = AM.get(P.S, kp .. "." .. key)
                if x == nil and whole == nil then x = v[key] end
                m[key] = AM.copy(x)
            end
            out[k] = m
        else
            local x = AM.get(P.S, kp)
            if x == nil then x = v end
            out[k] = AM.copy(x)
        end
    end
    return out
end

local function onPresetCopy(P)
    if not A.fold(P) then return A.layout(P) end
    local pg = P.pages.hordes
    local ids = presetIds(P.S)
    local new
    for n = 2, maxPresets() do
        if new == nil and AM.get(P.S, "hordes.presets.p" .. n) == nil then new = "p" .. n end
    end
    if #ids >= maxPresets() or new == nil then
        return A.say(P, getText("IGUI_MQ_Admin_HordePresetsMax", maxPresets()), "errorText")
    end
    -- "<name> 2", counting up past the names already taken
    local from = nameOf(P.S, pg.preset)
    local taken = {}
    for _, id in ipairs(ids) do taken[nameOf(P.S, id)] = true end
    local name
    local n = 1
    repeat
        n = n + 1
        local tail = " " .. n
        name = string.sub(from, 1, AM.MAX_NAME - #tail) .. tail
    until not taken[name]
    local copy = fullPreset(P, pg.preset)
    copy.name = name
    AM.draftSet(P.S.draft, "hordes.presets." .. new, copy)
    summary(P, getText("IGUI_MQ_Admin_HordeSumPresetAdd", name))
    pg.preset = new
    pg.version = pg.version + 1
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

-- after the dialog: the windows on it go back to "default" (the windows list as a whole into the draft), the preset
-- leaves the draft (only there) or gets a "del" (applied), and so do the edits made under it
local function deletePreset(P, id, name)
    local path = "hordes.presets." .. id
    local wins = AM.copy(AM.get(P.S, "hordes.windows")) or {}
    local moved = false
    for _, w in ipairs(wins) do
        if w.preset == id then w.preset, moved = "default", true end
    end
    if moved then
        if AM.same(wins, applied(P, "hordes.windows")) then AM.draftUnset(P.S.draft, "hordes.windows")
        else AM.draftSet(P.S.draft, "hordes.windows", wins) end
    end
    local under = {}
    for _, dp in ipairs(P.S.draft.order) do
        if string.sub(dp, 1, #path + 1) == path .. "." then under[#under + 1] = dp end
    end
    for _, dp in ipairs(under) do AM.draftUnset(P.S.draft, dp) end
    if overridden(P, path) then AM.draftSet(P.S.draft, path, AM.DEL) else AM.draftUnset(P.S.draft, path) end
    summary(P, getText("IGUI_MQ_Admin_HordeSumPresetDel", name))
    local pg = P.pages.hordes
    pg.preset = "default"
    pg.version = pg.version + 1
    inDraft(P)
    A.layout(P)
end

local function onPresetDel(P)
    local pg = P.pages.hordes
    local id = pg.preset
    if id == "default" then return end
    if not A.fold(P) then return A.layout(P) end
    local name = nameOf(P.S, id)
    local used = windowsOf(P, id)
    local text
    if #used == 0 then
        text = getText("IGUI_MQ_Admin_HordePresetUnused")
    else
        local lines = {}
        for i, u in ipairs(used) do lines[i] = windowShort(u.w) end
        text = A.count("IGUI_MQ_Admin_HordePresetDelAsk", #used) .. "\n" .. table.concat(lines, "\n")
    end
    A.ask(P, { title = getText("IGUI_MQ_Admin_HordePresetDelTitle", name), danger = true,
        text = text .. "\n\n" .. getText("IGUI_MQ_Admin_AfterApply"), confirm = getText("IGUI_MQ_Admin_HordePresetDel"),
        cancel = getText("IGUI_MQ_Admin_Keep"), onOk = function() deletePreset(P, id, name) end })
end

local function layoutPresets(P, pg, F, lw, ids)
    local id, path = pg.preset, pre(P)
    F:head("hpre", getText("IGUI_MQ_Admin_HordePresetsHead"))
    F:text("pren", getText("IGUI_MQ_Admin_HordePresetsNote"), "textMuted")
    local full = #ids >= maxPresets()
    local copy = F:button("pre:copy", getText("IGUI_MQ_Admin_HordePresetCopy"), onPresetCopy)
    copy:setEnabled(not full)
    local del = F:button("pre:del", getText("IGUI_MQ_Admin_HordePresetDel"), onPresetDel)
    del:setEnabled(id ~= "default")
    F:row({ F:label("pre:l", getText("IGUI_MQ_Admin_HordePresetPick"), "text"), F:dropdown("pre:pick", presetOptions(P, ids), id, onPresetPick),
        copy, del, maxLabel(F, "pre:max", getText("IGUI_MQ_Admin_HordePresetsMax", maxPresets()), full) })
    formRow(F, path .. ".name", A.fLabel(path .. ".name"), lw, { A.textField(P, pg, path .. ".name", path .. ".name", 200, AM.MAX_NAME) })
    local used = windowsOf(P, id)
    if #used == 0 then
        F:text("pre:u", getText("IGUI_MQ_Admin_HordePresetUnused"), "textMuted")
    else
        local parts = {}
        for i, u in ipairs(used) do parts[i] = windowShort(u.w) end
        F:text("pre:u", getText("IGUI_MQ_Admin_HordePresetUsed", table.concat(parts, getText("IGUI_MQ_UI_ListSep"))), "textMuted")
    end
end

-- the edited preset's own number fields, labelled like the settings they hold (A.fLabel); unset = the default preset's
local function presetForm(P, pg, F, lw, rows)
    for _, r in ipairs(rows) do
        local path = pre(P) .. "." .. r[1]
        formRow(F, path, A.fLabel(path), lw, { A.numField(P, pg, path, path, nil, r[2], numW(r[2]), base()[r[1]]) })
    end
end

-- ===== waves (claims 1.1, 1.3, 1.4) =====

local function waveSize(pg, wp, i, w, players)
    local key = wp .. "." .. i
    return MQ.Catalog.hordeWaveSize(tonumber(live(pg, key .. ".base", w.base)) or 1,
        tonumber(live(pg, key .. ".perPlayer", w.perPlayer)) or 0, players)
end

local function wavesOf(P) return AM.get(P.S, pre(P) .. ".waves") or base().waves end

local function onWaveAdd(P)
    editList(P, pre(P) .. ".waves", function(list)
        if #list < AM.MAX_WAVES then list[#list + 1] = AM.copy(list[#list] or base().waves[1]) end
    end)
end

local function onWaveRemove(P, b)
    editList(P, pre(P) .. ".waves", function(list)
        if #list > 1 then table.remove(list, b.wave) end
    end)
end

local function layoutWaves(P, pg, F, lw)
    local wp = pre(P) .. ".waves"
    F:head("hv", getText("IGUI_MQ_Admin_HordeWavesHead", nameOf(P.S, pg.preset)))
    local list = wavesOf(P)
    local hIdx, hBase, hPer = getText("IGUI_MQ_Admin_HordeColWave"), getText("IGUI_MQ_Admin_HordeColBase"),
        getText("IGUI_MQ_Admin_HordeColPerPlayer")
    local h1, h4 = A.count("IGUI_MQ_Admin_HordeColPlayers", 1), A.count("IGUI_MQ_Admin_HordeColPlayers", 4)
    local wIdx = math.max(A.textW(hIdx), A.textW("10"))
    -- the per-player header spans its field and the "%" column (wPct)
    local wBase, wPer = numW("hordeBase", math.max(60, A.textW(hBase))), numW("hordePerPlayer")
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
        local key = wp .. "." .. i
        local base_ = feeds(A.numField(P, pg, key .. ".base", wp, { i, "base" }, "hordeBase", wBase))
        local per = feeds(A.numField(P, pg, key .. ".perPlayer", wp, { i, "perPlayer" }, "hordePerPlayer", wPer))
        local idx = F:label("v:i" .. i, tostring(i))
        idx:setWidth(wIdx)
        local pct = F:label("v:pc" .. i, "%", "textMuted")
        pct:setWidth(wPct)
        local p1 = F:label("v:1:" .. i, A.num(waveSize(pg, wp, i, w, 1)), "textMuted")
        p1:setWidth(wP)
        local p4 = F:label("v:4:" .. i, A.num(waveSize(pg, wp, i, w, 4)), "textMuted")
        p4:setWidth(wP)
        local rm = F:button("v:r" .. i, getText("IGUI_MQ_Admin_Remove"), onWaveRemove)
        rm.wave = i
        rm:setEnabled(#list > 1)
        F:item()
        F:row({ idx, base_, per, pct, p1, p4 }, nil, rm)
    end
    F:listEnd(L)
    local add = F:button("v:add", getText("IGUI_MQ_Admin_HordeWaveAdd"), onWaveAdd)
    add:setEnabled(#list < AM.MAX_WAVES)
    F:row({ add, maxLabel(F, "v:max", getText("IGUI_MQ_Admin_HordeWavesMax", AM.MAX_WAVES), #list >= AM.MAX_WAVES) })
    -- under the row it explains (review)
    F:text("vn", getText("IGUI_MQ_Admin_HordeWavesNote"), "textMuted")
    presetForm(P, pg, F, lw, { { "restSec", "hordeRest" }, { "limitMin", "hordeLimit" }, { "maxAlive", "hordeAlive" } })
    -- the sandbox ZombiesCountBeforeDelete the server read (nil: it could not)
    local cull = pg.data and tonumber(pg.data.cull)
    if cull then F:text("cull", getText("IGUI_MQ_Admin_HordeCull", A.num(cull)), "textMuted") end
end

-- ===== kinds (design r11 list box; claim 4): weight, share, points per kill, toughness =====

local KIND_START = 10   -- the weight a kind picked from the dropdown starts with; the admin edits it in its row

-- a key of a non-built-in kind: a "del" change when the applied config has it, else the draft forgets it
local function dropKey(P, group, id)
    local path = pre(P) .. "." .. group .. "." .. id
    if overridden(P, path) then AM.draftSet(P.S.draft, path, AM.DEL) else AM.draftUnset(P.S.draft, path) end
end

local function onKindAdd(P, id)
    if id == nil then return end
    local kp = pre(P)
    AM.draftSet(P.S.draft, kp .. ".kinds." .. id, KIND_START)
    -- no points of its own yet: it starts at what a regular zombie pays as shown (typed, else the draft's); the other
    -- typed fields stay unfolded, so a weight typed 0 keeps its row until Apply
    if mapGet(P, "points", id) == nil then
        local vanilla = mapGet(P, "points", "vanilla")
        AM.draftSet(P.S.draft, kp .. ".points." .. id, tonumber(live(P.pages.hordes, kp .. ".points.vanilla", vanilla)) or 0)
    end
    -- a row removed and picked again shows the new values, not what was typed in it before the Remove
    for _, g in ipairs({ "kinds", "points", "hp" }) do
        local f = P.pages.hordes.fields[kp .. "." .. g .. "." .. id]
        if f then f.at = nil end
    end
    summary(P, getText("IGUI_MQ_Admin_HordeSumKindAdd", A.hordeKindName(P, id)))
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

-- Remove writes 0 on a built-in kind (Catalog: Contract.HORDE_KINDS have default weights) in any preset, and keeps
-- its points; on the others it drops the weight, points and toughness keys (a "del" change when applied), which also
-- clears what a removed mod left in config.json. A kind only the draft has (picked, then removed) just leaves the
-- draft again.
local function onKindRemove(P, b)
    if base().kinds[b.kind] ~= nil then
        AM.draftSet(P.S.draft, pre(P) .. ".kinds." .. b.kind, 0)
    else
        for _, g in ipairs({ "kinds", "points", "hp" }) do dropKey(P, g, b.kind) end
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
    local ov = AM.get({ overrides = P.S.overrides, defaults = {} }, pre(P) .. ".kinds")
    if type(ov) ~= "table" or P.pages.hordes.data == nil then return {} end
    local known, out = {}, {}
    for _, k in ipairs(kinds) do known[k.id] = true end
    for id in pairs(ov) do
        if not known[id] and AM.get(P.S, pre(P) .. ".kinds." .. id) ~= nil then out[#out + 1] = id end
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
        local w = tonumber(mapGet(P, "kinds", k.id)) or 0
        if w > 0 then
            rows[#rows + 1] = k
            weights[k.id] = tonumber(live(pg, pre(P) .. ".kinds." .. k.id, w)) or 0
            total = total + weights[k.id]
        end
    end
    return rows, weights, total
end

-- points per kill as shown: the typed value, the draft's, else (no entry) what a regular zombie pays. A kind with no
-- points of its own whose field still shows the inherited value follows the vanilla field as typed, as the server
-- pays it (Hordes.lua: points[kind] or points.vanilla)
local function pointsOf(P, pg, id)
    local path = pre(P) .. ".points." .. id
    local seed = tonumber(mapGet(P, "points", "vanilla")) or 0
    local vanilla = tonumber(live(pg, pre(P) .. ".points.vanilla", seed)) or 0
    local own = mapGet(P, "points", id)
    local v = tonumber(live(pg, path, own))
    if own == nil and (v == nil or v == seed) then return vanilla end
    return v or vanilla
end

-- lw = the tab's label column: the name column is one PAD narrower, so the weights line up with the fields above
local function layoutKinds(P, pg, F, kinds, lw)
    local kp = pre(P)
    F:head("hk", getText("IGUI_MQ_Admin_HordeKindsHead", nameOf(P.S, pg.preset)))
    local wDef, pDef = defaultsOf(P, "kinds"), defaultsOf(P, "points")
    local rows, weights, total = weighted(P, pg, kinds)
    local hW, hS, hP, hH = getText("IGUI_MQ_Admin_ColWeight"), getText("IGUI_MQ_Admin_HordeColShare"),
        getText("IGUI_MQ_Admin_HordeColPoints"), getText("IGUI_MQ_Admin_HordeColHp")
    local cw = lw - A.PAD
    -- as wide as the header too: DE "Gewichtung" ran into "Anteil" (quest-ui-de-1028a)
    local wW = numW("hordeWeight", math.max(60, A.textW(hW)))
    local wS = math.max(A.textW(hS), A.textW(getText("IGUI_MQ_Admin_HordePct", 100)))
    local wP = numW("hordePoints", math.max(60, A.textW(hP)))
    local wH = numW("hordeHp", math.max(60, A.textW(hH)))
    local vanillaPts = tonumber(mapGet(P, "points", "vanilla")) or 0
    local L = F:list("ks")
    local xW = A.PAD + cw + A.GAP
    local xP = xW + wW + A.GAP + wS + A.GAP
    F:listHead({ { text = getText("IGUI_MQ_Admin_ColKind"), x = A.PAD }, { text = hW, x = xW }, { text = hS, x = xW + wW + A.GAP },
        { text = hP, x = xP }, { text = hH, x = xP + wP + A.GAP } })
    local inRows = {}
    for _, k in ipairs(rows) do
        inRows[k.id] = true
        local name = kindName(k)
        local wPath, pPath, hPath = kp .. ".kinds." .. k.id, kp .. ".points." .. k.id, kp .. ".hp." .. k.id
        local nm = F:label("ks:n:" .. k.id, name, nil, nil, cw - A.GAP)
        nm:setWidth(cw)
        local wf = feeds(A.numField(P, pg, wPath, wPath, nil, "hordeWeight", wW, wDef[k.id] or 0))
        local share = total > 0 and math.floor(weights[k.id] * 100 / total + 0.5) or 0
        local sl = F:label("ks:s:" .. k.id, getText("IGUI_MQ_Admin_HordePct", share), "textMuted")
        sl:setWidth(wS)
        local pf = feeds(A.numField(P, pg, pPath, pPath, nil, "hordePoints", wP, pDef[k.id] or vanillaPts))
        -- unset = 1x (the sandbox toughness)
        local hf = A.numField(P, pg, hPath, hPath, nil, "hordeHp", wH, 1)
        F:item()
        F:row({ nm, wf, sl, pf, hf }, nil, removeBtn(F, k.id, name))
    end
    local add = {}
    for _, k in ipairs(kinds) do
        if not inRows[k.id] then add[#add + 1] = { id = k.id, label = kindName(k) } end
    end
    for _, id in ipairs(orphans(P, kinds)) do
        local nm = F:label("ks:o:" .. id, id, "textFaint", nil, cw - A.GAP)
        nm:setWidth(cw)
        F:item()
        F:row({ nm, F:label("ks:w:" .. id, A.num(tonumber(AM.get(P.S, kp .. ".kinds." .. id)) or 0), "textFaint"),
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

-- points one horde of the edited preset pays with every wave cleared by `players` players, before the cap (the
-- server's sizes and mix: Catalog.hordeWaveSize / hordeMix; points per kill, no entry = points.vanilla)
function A.hordeEstimate(P, pg, kinds, players)
    local C = MQ.Catalog
    local rows, weights = weighted(P, pg, kinds)
    local ids = {}
    for i, k in ipairs(rows) do ids[i] = k.id end
    local wp = pre(P) .. ".waves"
    local value = 0
    for i, w in ipairs(wavesOf(P)) do
        for _, m in ipairs(C.hordeMix(ids, weights, waveSize(pg, wp, i, w, players))) do
            value = value + m.n * pointsOf(P, pg, m.kind)
        end
    end
    return value
end

local function layoutReward(P, pg, F, kinds, lw)
    local name = nameOf(P.S, pg.preset)
    F:head("hr", getText("IGUI_MQ_Admin_HordeRewardHead", name))
    local cp = pre(P) .. ".cap"
    formRow(F, cp, A.fLabel(cp), lw, { feeds(A.numField(P, pg, cp, cp, nil, "hordeCap", numW("hordeCap"), base().cap)) })
    F:text("rn", getText("IGUI_MQ_Admin_HordeRewardNote"), "textMuted")
    local cap = tonumber(live(pg, cp, AM.get(P.S, cp) or base().cap)) or 0
    local parts = {}
    for i, n in ipairs(EST_PLAYERS) do
        local v = A.hordeEstimate(P, pg, kinds, n)
        -- key .. "1" = the singular (A.count)
        local key = v > cap and "IGUI_MQ_Admin_HordeEstCap" or "IGUI_MQ_Admin_HordeEst"
        parts[i] = getText(n == 1 and key .. "1" or key, n, A.num(math.min(v, cap)))
    end
    -- the box's first line says what it is (review: no heading font inside a box)
    F:text("est", getText("IGUI_MQ_Admin_HordeEstHead", name) .. "\n" .. table.concat(parts, "   "), "text", nil, "success")
end

-- ===== the tab =====

-- every form label of the tab, one column (A.labelWidth; preset fields read as hordes.<field>, A.fLabel)
local PATHS = { "hordes.maxPerDay", "hordes.name", "hordes.restSec", "hordes.limitMin", "hordes.maxAlive", "hordes.cap" }

local function layout(P, pg, F)
    -- no page heading: the tab already says Hordes (review). Its notes wrap narrower (Flow:text)
    F.narrowNotes = true
    F:text("n", getText("IGUI_MQ_Admin_HordeNote"), "textMuted")
    local ids = presetIds(P.S)
    current(P, ids)
    local kinds = kindList(P)
    local lw = math.max(A.labelWidth(PATHS), math.min(A.textW(getText("IGUI_MQ_Admin_HordeSpotName")) + A.GAP, 260))
    for _, k in ipairs(kinds) do lw = math.max(lw, math.min(A.textW(kindName(k)) + A.GAP, 260)) end
    layoutStatus(P, pg, F)
    layoutSpots(P, pg, F, lw)
    layoutWindows(P, pg, F, lw, ids)
    layoutPresets(P, pg, F, lw, ids)
    layoutWaves(P, pg, F, lw)
    layoutKinds(P, pg, F, kinds, lw)
    layoutReward(P, pg, F, kinds, lw)
end

-- shows the preset a check is about and marks its name field, then says why (the page check's message)
local function badName(P, pg, values, id, msg)
    AM.formToDraft(P.S, values)
    pg.preset = id
    pg.version = pg.version + 1
    A.layout(P)
    local el = pg.flow.pool["f:hordes.presets." .. id .. ".name"]
    if el then
        A.markError(P, el, msg)
        MQ.Draw.reveal(el)
    end
    return msg
end

-- Apply: every window needs a day (the server refuses an empty days string); every preset but the default needs a
-- name, and no two presets may read the same (the names as typed count)
local function check(P, pg, values)
    for _, w in ipairs(AM.get(P.S, "hordes.windows") or {}) do
        if not hasDay(w) then return getText("IGUI_MQ_Admin_HordeErrDays") end
    end
    local typed = {}
    for _, fv in ipairs(values or {}) do
        local id = string.match(tostring(fv.field.path), "^hordes%.presets%.([^%.]+)%.name$")
        if id then typed[id] = fv.value end
    end
    local seen = {}
    for _, id in ipairs(presetIds(P.S)) do
        local n = typed[id]
        if n == nil then n = AM.get(P.S, "hordes.presets." .. id .. ".name") end
        n = type(n) == "string" and n or ""
        if n == "" and id ~= "default" then return badName(P, pg, values, id, getText("IGUI_MQ_Admin_HordeErrPresetName")) end
        local shown = n ~= "" and n or getText("IGUI_MQ_Admin_HordePresetDefault")
        if seen[shown] then return badName(P, pg, values, id, getText("IGUI_MQ_Admin_HordeErrPresetSame", shown)) end
        seen[shown] = true
    end
    return nil
end

A.pages.hordes = { layout = layout, load = load, check = check }
