-- MinidoracatQuest/AdminHordes.lua: admin tab "hordes" (design r10, lists r11, warning r12; ARCHITECTURE.md 6.2, 7).
-- Live status from horde.status (fetched each time the tab opens, after every action and by Refresh): the current
-- horde with Cancel / Stop, today's count and next roll, Start a horde (with its warning minutes), the last 5 results
-- (a list box). Below it the
-- settings: spots (a list box; add = towns.here, the admin's own position), window, chance, count, the kinds (a list
-- box of the kinds with a weight; the others are added from a dropdown), time limit, reward. Every setting goes
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

-- the server plans it from the applied settings: what waits in the draft is not used, and the dialog says so.
-- lead (design r12): minutes of warning before it starts, 0 = now
local LEAD_MAX = MQ.Contract.LIMIT.MAX_LEAD

-- spots added in the draft are not saved yet: the server would refuse with "add a spot first" while the list shows
-- them (2026-10-26 playtest: three presses before Apply), so say to apply first and send nothing
local function spotsOnlyInDraft(P)
    local applied = AM.get({ overrides = P.S.overrides, defaults = P.S.defaults }, "hordes.spots") or {}
    return #applied == 0 and #(AM.get(P.S, "hordes.spots") or {}) > 0
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
    local applied = tostring(AM.get({ overrides = P.S.overrides, defaults = P.S.defaults }, "hordes.leadMin") or 0)
    if pg.leadSeed == nil or tf:getText() == pg.leadSeed then tf:setText(applied) end
    pg.leadSeed = applied
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
    local L = F:list("p")
    local names = {}
    for i, s in ipairs(spots) do names[i] = tostring(s.name) end
    local nameW = A.colW(names, math.floor(F.width / 3))
    F:listHead({ { text = getText("IGUI_MQ_Admin_ColName"), x = A.PAD }, { text = getText("IGUI_MQ_Admin_ColPos"), x = A.PAD + nameW + A.GAP } })
    for i, s in ipairs(spots) do
        local rm = F:button("pr" .. i, getText("IGUI_MQ_Admin_Remove"), onSpotRemove)
        rm.spot, rm.spotName = i, s.name
        local nm = F:label("pl" .. i, names[i], nil, nil, nameW)
        nm:setWidth(nameW)
        F:item()
        F:row({ nm, F:label("px" .. i, tostring(s.x) .. ", " .. tostring(s.y) .. ", " .. tostring(s.z), "textMuted") }, nil, rm)
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_HordeSpotsNone"), "warning")
    local add = F:button("sp:add", getText("IGUI_MQ_Admin_HordeSpotHere"), onSpotAdd, "primary")
    add:setEnabled(#spots < AM.MAX_SPOTS)
    local label = getText("IGUI_MQ_Admin_HordeSpotName")
    formRow(F, "sp:name", label, A.textW(label) + A.GAP, { F:field("sp:name", 200, nil, 64), add })
    if #spots >= AM.MAX_SPOTS then F:text("pmax", getText("IGUI_MQ_Admin_HordeSpotsMax"), "warning") end
end

-- ===== settings =====

local PATHS = { "hordes.enabled", "hordes.from", "hordes.to", "hordes.chance", "hordes.maxPerDay", "hordes.leadMin",
    "hordes.waitMin", "hordes.count", "hordes.limitMin", "hordes.perZombie", "hordes.split" }

-- ===== kinds (design r11): a list box of the kinds with a weight above 0, the others in the dropdown under it =====

local KIND_START = 10   -- the weight a kind picked from the dropdown starts with; the admin edits it in its row

-- the built-in kinds have a default above 0 (Catalog.DEFAULTS.hordes.kinds); a kind another mod registers has none
local function kindDefaults(P)
    local h = P.S.defaults and P.S.defaults.hordes
    return h and h.kinds or {}
end

local function onKindAdd(P, id)
    if id == nil then return end
    local path = "hordes.kinds." .. id
    AM.draftSet(P.S.draft, path, KIND_START)
    -- a row removed and picked again shows the 10, not what was typed in it before the Remove
    local f = P.pages.hordes.fields[path]
    if f then f.at = nil end
    summary(P, getText("IGUI_MQ_Admin_HordeSumKindAdd", A.hordeKindName(P, id)))
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

-- Remove writes 0 on a built-in kind; on the others it drops the key (a "del" change), which also clears what a
-- removed mod left in config.json. A kind only the draft has (picked, then removed) just leaves the draft again.
local function onKindRemove(P, b)
    local path = "hordes.kinds." .. b.kind
    local ov = P.S.overrides and P.S.overrides.hordes and P.S.overrides.hordes.kinds
    if kindDefaults(P)[b.kind] ~= nil then
        AM.draftSet(P.S.draft, path, 0)
    elseif type(ov) == "table" and ov[b.kind] ~= nil then
        AM.draftSet(P.S.draft, path, AM.DEL)
    else
        AM.draftUnset(P.S.draft, path)
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

-- lw = the tab's label column: the name column is one PAD narrower, so the weights line up with the fields above
local function layoutKinds(P, pg, F, kinds, lw)
    local defaults = kindDefaults(P)
    local L = F:list("ks")
    local cw = lw - A.PAD
    F:listHead({ { text = getText("IGUI_MQ_Admin_ColKind"), x = A.PAD }, { text = getText("IGUI_MQ_Admin_ColWeight"), x = A.PAD + cw + A.GAP } })
    local add = {}
    for _, k in ipairs(kinds) do
        local path, name = "hordes.kinds." .. k.id, kindName(k)
        local w = tonumber(AM.get(P.S, path)) or 0
        if w > 0 then
            local nm = F:label("ks:n:" .. k.id, name, nil, nil, cw - A.GAP)
            nm:setWidth(cw)
            F:item()
            F:row({ nm, A.numField(P, pg, path, path, nil, "hordeWeight", nil, defaults[k.id] or 0) }, nil, removeBtn(F, k.id, name))
        else
            add[#add + 1] = { id = k.id, label = name }
        end
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
    layoutKinds(P, pg, F, kinds, lw)
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
