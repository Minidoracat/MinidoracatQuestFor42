-- MinidoracatQuest/AdminAchv.lua: admin "Achievements" tab (spec 13.1-13.4).
-- Table: name / I-IV / more; batch multiplier and add-tier over the category shown, into the draft; tier editor
-- (on/off, thresholds, points, titles, up to 10 tiers); new achievement from an existing stat (custom.<id>);
-- broadcast and title display forms. The quick difficulty chips sit on the Basic tab (P_.difficultyRow).
-- Everything ends in cfg.preview / cfg.apply (AdminPanel).

require "MinidoracatQuest/AdminPanel"

local MQ = MinidoracatQuest
local A = MQ.Admin
local AM = MQ.AdminModel

local P_ = {}   -- page helpers
local MULTS = { 0.8, 1.25 }
local PRESETS = { "easy", "normal", "hard", "custom" }

local function summary(P, text)
    P.draftSummary = P.draftSummary and (P.draftSummary .. "; " .. text) or text
end

-- the achievements of the category shown: the table rows, and what the batch buttons change
function P_.shown(pg, a) return (a.custom and pg.cat == "custom") or (not a.custom and a.cat == pg.cat) end

function P_.inCat(pg)
    local set = {}
    for _, a in ipairs(pg.list) do if P_.shown(pg, a) then set[a.id] = true end end
    return set
end

-- ===== difficulty =====

function P_.onPreset(P, b)
    -- typed values on this tab reach the draft first: applying the difficulty reloads every field
    if not A.fold(P) then return end
    local preset = b.preset
    local function run(mult)
        A.send(P, "diff.preview", { preset = preset, mult = mult }, function(res)
            if not res.ok then return A.fail(P, res) end
            A.confirm(P, res.changes or {}, res.rows,
                getText("IGUI_MQ_Admin_SumDiff", getText("IGUI_MQ_Admin_Diff_" .. preset)),
                { estimate = res.estimate, note = getText("IGUI_MQ_Admin_DiffNote") })
        end)
    end
    if preset ~= "custom" then return run(nil) end
    A.ask(P, { title = getText("IGUI_MQ_Admin_Diff_custom"), text = getText("IGUI_MQ_Admin_MultAsk", "0.1", "10"),
        input = { text = "1" }, onOk = function(text)
            local m, key, lo, hi = AM.check(text, "mult")
            if m == nil then return A.say(P, getText(key, AM.num(lo), AM.num(hi)), "errorText") end
            run(m)
        end })
end

-- quick difficulty chips (Basic tab): a chip runs diff.preview and opens the confirm view with the estimate
function P_.difficultyRow(P, F)
    local preset = AM.get(P.S, "difficulty.preset") or "normal"
    local ctrls = {}
    for _, id in ipairs(PRESETS) do
        local title = getText("IGUI_MQ_Admin_Diff_" .. id)
        if id == "custom" and preset == "custom" then
            title = title .. " x" .. AM.num(AM.get(P.S, "difficulty.mult") or 1)
        end
        local b = F:button("d:" .. id, title, P_.onPreset, "chip")
        b.preset = id
        b:setActive(id == preset)
        ctrls[#ctrls + 1] = b
    end
    F:row(ctrls)
end

-- ===== batch =====

function P_.scale(P, pg, field, f)
    local n, skipped = AM.batchScale(P.S, pg.list, P_.inCat(pg), field, f)
    if n > 0 then
        summary(P, getText(field == "tiers" and "IGUI_MQ_Admin_SumScale" or "IGUI_MQ_Admin_SumPts", n, AM.num(f)))
    end
    P.msg, P.msgToken = nil, nil
    if #skipped > 0 then P.msg, P.msgToken = getText("IGUI_MQ_Admin_Skipped", #skipped), "warning" end
    A.layout(P)
end

function P_.onMult(P, b) P_.scale(P, P.pages.achv, "tiers", b.mult) end

function P_.onCustomMult(P, b)
    local fieldName = b.field
    A.ask(P, { title = b.title, text = getText("IGUI_MQ_Admin_MultAsk", "0.1", "10"), input = { text = "1" },
        onOk = function(text)
            local m, key, lo, hi = AM.check(text, "mult")
            if m == nil then return A.say(P, getText(key, AM.num(lo), AM.num(hi)), "errorText") end
            P_.scale(P, P.pages.achv, fieldName, m)
        end })
end

function P_.onAddTier(P)
    local pg = P.pages.achv
    local n, skipped = AM.batchAddTier(P.S, pg.list, P_.inCat(pg))
    if n > 0 then summary(P, getText("IGUI_MQ_Admin_SumAddTier", n)) end
    P.msg, P.msgToken = nil, nil
    if #skipped > 0 then P.msg, P.msgToken = getText("IGUI_MQ_Admin_Skipped", #skipped), "warning" end
    A.layout(P)
end

function P_.onEditOn(P, value) P.pages.achv.editOn = value end

function P_.onCat(P, id)
    local pg = P.pages.achv
    pg.cat = id
    A.layout(P)
end

-- ===== tier editor =====

function P_.byId(pg, id)
    for _, a in ipairs(pg.list) do if a.id == id then return a end end
    return nil
end

function P_.onEdit(P, b)
    local pg = P.pages.achv
    local a = P_.byId(pg, b.achId)
    if a == nil then return end
    pg.edit, pg.rows, pg.editErr, pg.rowsAt, pg.editOn = a.id, {}, nil, nil, a.enabled ~= false
    for i, t in ipairs(a.tiers) do
        local title = a.titles[i] or a.titles[tostring(i)]
        pg.rows[i] = { tier = tostring(t), pts = tostring(a.pts[i] or 0), title = title and tostring(title) or "" }
    end
    pg.sp:setYScroll(0)
    A.layout(P)
end

-- copy the editor's text fields back into pg.rows
function P_.readRows(pg)
    local pool = pg.flow.pool
    for i, r in ipairs(pg.rows) do
        if pool["e:t" .. i] then r.tier = pool["e:t" .. i]:getText() end
        if pool["e:p" .. i] then r.pts = pool["e:p" .. i]:getText() end
        if pool["e:n" .. i] then r.title = pool["e:n" .. i]:getText() end
    end
end

function P_.syncRows(pg)
    local pool = pg.flow.pool
    for i, r in ipairs(pg.rows) do
        if pool["e:t" .. i] then pool["e:t" .. i]:setText(r.tier) end
        if pool["e:p" .. i] then pool["e:p" .. i]:setText(r.pts) end
        if pool["e:n" .. i] then pool["e:n" .. i]:setText(r.title) end
    end
end

-- threshold/points the "add tier" button would use, from the editor's current texts
function P_.nextFromRows(rows)
    local tiers, pts = {}, {}
    for i, r in ipairs(rows) do
        tiers[i] = tonumber((string.gsub(r.tier, "[,%s]", ""))) or 0
        pts[i] = tonumber((string.gsub(r.pts, "[,%s]", ""))) or 0
    end
    return AM.nextTier(tiers, pts)
end

function P_.onRowAdd(P)
    local pg = P.pages.achv
    P_.readRows(pg)
    if #pg.rows >= AM.MAX_TIERS then return end
    local t, p = P_.nextFromRows(pg.rows)
    pg.rows[#pg.rows + 1] = { tier = tostring(t), pts = tostring(p), title = "" }
    A.layout(P)
    P_.syncRows(pg)
end

function P_.onRowDel(P)
    local pg = P.pages.achv
    P_.readRows(pg)
    if #pg.rows <= 1 then return end
    pg.rows[#pg.rows] = nil
    A.layout(P)
    P_.syncRows(pg)
end

function P_.onEditClose(P)
    P.pages.achv.edit = nil
    A.layout(P)
end

function P_.onEditSave(P)
    local pg = P.pages.achv
    local a = P_.byId(pg, pg.edit)
    if a == nil then return end
    P_.readRows(pg)
    local tiers, pts, titles = AM.readTierRows(pg.rows)
    if tiers == nil then
        pg.editErr = pts
        A.layout(P)
        return A.say(P, getText("IGUI_MQ_Admin_FixErrors"), "errorText")
    end
    AM.putAch(P.S, a, tiers, pts, titles, pg.editOn ~= false)
    summary(P, getText("IGUI_MQ_Admin_SumEdit", A.achName(P, a.id)))
    pg.edit, pg.editErr = nil, nil
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

function P_.onCustomDelete(P)
    local pg = P.pages.achv
    local a = P_.byId(pg, pg.edit)
    if a == nil or not a.custom then return end
    A.ask(P, { title = getText("IGUI_MQ_Admin_DeleteCustom"), danger = true, confirm = getText("IGUI_MQ_Admin_DeleteNow"),
        text = getText("IGUI_MQ_Admin_DeleteCustomAsk", A.achName(P, a.id)), onOk = function()
            AM.draftSet(P.S.draft, a.path, AM.DEL)
            summary(P, getText("IGUI_MQ_Admin_SumDelete", A.achName(P, a.id)))
            pg.edit = nil
            A.layout(P)
        end })
end

function P_.layoutEditor(P, pg, F, a)
    local D = MQ.Draw
    F:head("e:h", getText("IGUI_MQ_Admin_TierHead", A.achName(P, a.id)))
    F:text("e:c", getText("IGUI_MQ_Admin_TierCount", #pg.rows, AM.MAX_TIERS), "textMuted")
    -- achievements.<id>.enabled (custom: enabled in the object); off = players no longer see it or unlock it
    F:row({ F:check("e:on", getText("IGUI_MQ_Admin_AchEnabled"), P_.onEditOn, pg.editOn ~= false) })
    F:text("e:onn", getText("IGUI_MQ_Admin_AchEnabledNote"), "textMuted")
    local nameW = 0
    for i = 1, #pg.rows do
        nameW = math.max(nameW, A.textW(D and D.tierName and D.tierName(i) or AM.roman(i)))
    end
    local numW = A.textW("1,000,000,000") + 16
    local ptsW = A.textW("10000") + 24
    local titleW = math.max(80, F.width - 2 * A.PAD - nameW - numW - ptsW - 4 * A.GAP)
    F:cells("e:hd", {
        { text = getText("IGUI_MQ_Admin_ColTier"), x = A.PAD, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColThreshold"), x = A.PAD + nameW + A.GAP, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColPts"), x = A.PAD + nameW + numW + 2 * A.GAP, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColTitle"), x = A.PAD + nameW + numW + ptsW + 3 * A.GAP, token = "textMuted" },
    })
    local errs = pg.editErr or {}
    for i, r in ipairs(pg.rows) do
        local l = F:label("e:l" .. i, D and D.tierName and D.tierName(i) or AM.roman(i),
            i > 4 and "legend" or "text")
        l:setWidth(nameW)
        local t = F:field("e:t" .. i, numW)
        local p = F:field("e:p" .. i, ptsW)
        local n = F:field("e:n" .. i, titleW, getText("IGUI_MQ_Admin_TitlePlaceholder"), 64)
        local e = errs[i]
        A.markError(P, t, e and e[1] == "tier" and getText(e[2], AM.num(e[3] or 0), AM.num(e[4] or 0)) or nil)
        A.markError(P, p, e and e[1] == "pts" and getText(e[2], AM.num(e[3] or 0), AM.num(e[4] or 0)) or nil)
        F:row({ l, t, p, n })
    end
    if pg.rowsAt ~= pg.edit .. "#" .. #pg.rows then
        pg.rowsAt = pg.edit .. "#" .. #pg.rows
        P_.syncRows(pg)
    end
    local add = F:button("e:add", getText("IGUI_MQ_Admin_AddTier"), P_.onRowAdd)
    add:setEnabled(#pg.rows < AM.MAX_TIERS)
    local del = F:button("e:del", getText("IGUI_MQ_Admin_DelTier"), P_.onRowDel)
    del:setEnabled(#pg.rows > 1)
    F:row({ add, del })
    local nt, np = P_.nextFromRows(pg.rows)
    F:text("e:next", getText("IGUI_MQ_Admin_NextTier", A.num(nt), A.num(np)), "textMuted")
    F:text("e:keep", getText("IGUI_MQ_Admin_KeepUnlocked"), "textMuted")
    local ctrls = { F:button("e:save", getText("IGUI_MQ_Admin_ToDraft"), P_.onEditSave, "primary"),
        F:button("e:close", getText("UI_Cancel"), P_.onEditClose, "ghost") }
    if a.custom then ctrls[3] = F:button("e:rm", getText("IGUI_MQ_Admin_DeleteCustom"), P_.onCustomDelete, "danger") end
    F:row(ctrls)
    F:gap(2 * A.GAP)
end

-- ===== new achievement from an existing stat =====

function P_.statOptions()
    local C = MQ.Catalog
    local ids = C.statOrder
    if ids == nil then
        ids = {}
        for id in pairs(C.stats or {}) do ids[#ids + 1] = id end
        MQ.Util.sort(ids, AM.lt)
    end
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = { id = id, label = A.statName(id) } end
    return out
end

function P_.onNewToggle(P)
    local pg = P.pages.achv
    pg.newOpen = not pg.newOpen
    A.layout(P)
end

function P_.onNewAdd(P)
    local pg = P.pages.achv
    local pool = pg.flow.pool
    local id = AM.newId("c", getTimestampMs())
    local path, value, lo, hi = AM.customAch(id, pool["n:name"]:getText(), pool["n:cat"]:getSelected(),
        pool["n:stat"]:getSelected(), pool["n:tiers"]:getText(), pool["n:pts"]:getText())
    if path == nil then return A.say(P, getText(value, AM.num(lo or 0), AM.num(hi or 0)), "errorText") end
    AM.draftSet(P.S.draft, path, value)
    summary(P, getText("IGUI_MQ_Admin_SumCustom", value.name))
    pool["n:name"]:setText("")
    pool["n:tiers"]:setText("")
    pool["n:pts"]:setText("")
    pg.newOpen, pg.cat = false, "custom"
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
end

function P_.layoutNew(P, pg, F, cats)
    F:head("n:h", getText("IGUI_MQ_Admin_NewAchHead"))
    F:text("n:help", getText("IGUI_MQ_Admin_NewAchHelp"), "textMuted")
    local lw = 0
    for _, k in ipairs({ "Name", "Stat", "Cat", "Tiers", "Pts" }) do lw = math.max(lw, A.textW(getText("IGUI_MQ_Admin_New" .. k))) end
    local fw = math.max(120, math.min(320, F.width - 2 * A.PAD - lw - A.GAP))
    local function line(key, ctrl)
        local l = F:label("n:l" .. key, getText("IGUI_MQ_Admin_New" .. key))
        l:setWidth(lw)
        F:row({ l, ctrl })
    end
    line("Name", F:field("n:name", fw, nil, 64))
    local stats = P_.statOptions()
    line("Stat", F:dropdown("n:stat", stats, pg.flow.pool["n:stat"] and pg.flow.pool["n:stat"]:getSelected()
        or (stats[1] and stats[1].id), nil))
    local catOpts = {}
    for _, c in ipairs(cats) do
        if c ~= "custom" and c ~= "hidden" then catOpts[#catOpts + 1] = { id = c, label = getText("IGUI_MQ_AchCat_" .. c) } end
    end
    line("Cat", F:dropdown("n:cat", catOpts, pg.flow.pool["n:cat"] and pg.flow.pool["n:cat"]:getSelected()
        or (catOpts[1] and catOpts[1].id), nil))
    line("Tiers", F:field("n:tiers", fw, "100, 1000, 5000"))
    line("Pts", F:field("n:pts", fw, "10, 20, 30"))
    F:row({ F:button("n:add", getText("IGUI_MQ_Admin_ToDraft"), P_.onNewAdd, "primary"),
        F:button("n:close", getText("UI_Cancel"), P_.onNewToggle, "ghost") })
    F:gap(2 * A.GAP)
end

-- ===== page =====

function P_.cats(list)
    local out, seen = {}, {}
    for _, a in ipairs(list) do
        local c = a.custom and "custom" or a.cat
        if c and not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
    if not seen.custom then out[#out + 1] = "custom" end
    return out
end

-- name as the table shows it: "(changed)" for an edit still in the draft and "(off)" beside the colour,
-- so neither depends on gold or grey alone
function P_.rowName(P, a, b0)
    local name = a.custom and a.name or A.achName(P, a.id)
    local changed = b0 == nil or not (AM.same(b0.tiers, a.tiers) and AM.same(b0.pts, a.pts)
        and AM.same(b0.titles, a.titles) and b0.enabled == a.enabled)
    if changed then name = getText("IGUI_MQ_Admin_Changed", name) end
    if not a.enabled then name = getText("IGUI_MQ_Admin_Disabled", name) end
    return name
end

function P_.catLabel(c) return c == "custom" and getText("IGUI_MQ_Admin_CatCustom") or getText("IGUI_MQ_AchCat_" .. c) end

function P_.layout(P, pg, F)
    local C = MQ.Catalog
    pg.list = AM.achievements(P.S, C)
    local base = {}
    for _, a in ipairs(AM.achievements({ defaults = P.S.defaults, overrides = P.S.overrides }, C)) do base[a.id] = a end
    local cats = P_.cats(pg.list)
    pg.cat = pg.cat or cats[1]

    if pg.edit then
        local a = P_.byId(pg, pg.edit)
        if a then P_.layoutEditor(P, pg, F, a) else pg.edit = nil end
    end

    F:head("h", getText("IGUI_MQ_Admin_AchHead"))
    -- category filter, each with how many achievements it holds
    local perCat = {}
    for _, a in ipairs(pg.list) do
        local c = a.custom and "custom" or a.cat
        perCat[c] = (perCat[c] or 0) + 1
    end
    local opts = {}
    for _, c in ipairs(cats) do
        opts[#opts + 1] = { id = c, label = getText("IGUI_MQ_Admin_CatCount", P_.catLabel(c), A.num(perCat[c] or 0)) }
    end
    F:row({ F:label("cl", getText("IGUI_MQ_Admin_Category")), F:dropdown("cat", opts, pg.cat, P_.onCat) })

    -- table
    -- number columns as wide as the widest threshold shown, so names keep their room (FR / DE skill names
    -- were cut to "Training: Kurze ..." with a fixed "100,000" floor, quest-ui-de-1023h)
    local numW = A.textW("000")
    for _, a in ipairs(pg.list) do
        if P_.shown(pg, a) then
            for t = 1, 4 do if a.tiers[t] then numW = math.max(numW, A.textW(A.num(a.tiers[t]))) end end
        end
    end
    numW = numW + 2 * A.GAP
    local moreW = math.max(A.textW(getText("IGUI_MQ_Admin_Edit")), A.textW("+10")) + 24
    local right = F.width - A.PAD - moreW - 3 * A.GAP   -- one gap made FR "IV Plus" read as one header
    local nameX = A.PAD
    local nameW = math.max(60, right - 4 * numW - nameX - A.GAP)
    local head = { { text = getText("IGUI_MQ_Admin_ColAch"), x = nameX, token = "textMuted" } }
    for t = 1, 4 do head[#head + 1] = { text = AM.roman(t), x = right - (4 - t) * numW, right = true, token = "textMuted" } end
    head[#head + 1] = { text = getText("IGUI_MQ_Admin_ColMore"), x = right + 3 * A.GAP, token = "textMuted" }
    F:cells("hd", head)
    local i = 0
    for _, a in ipairs(pg.list) do
        if P_.shown(pg, a) then
            i = i + 1
            local b0 = base[a.id]
            local cells = { { text = P_.rowName(P, a, b0), x = nameX, w = nameW, wrap = true,
                token = a.enabled and "text" or "textMuted" } }
            for t = 1, 4 do
                local v = a.tiers[t]
                local changed = b0 == nil or (b0.tiers[t] ~= v) or (b0.pts[t] ~= a.pts[t])
                cells[#cells + 1] = { text = v and A.num(v) or "-", x = right - (4 - t) * numW, right = true,
                    token = changed and "accent" or "text" }
            end
            local row = F:cells("r" .. i, cells, i % 2 == 0)
            local extra = #a.tiers - 4
            local more = F:button("m" .. i, extra > 0 and ("+" .. extra) or getText("IGUI_MQ_Admin_Edit"), P_.onEdit,
                extra > 0 and "chip" or nil)
            more.achId = a.id
            more:setX(right + 3 * A.GAP)
            more:setY(row:getY() + math.floor((row.height - more.height) / 2))
            if more.height > row.height then
                row:setHeight(more.height)
                F.y = row:getY() + row.height
                more:setY(row:getY())
            end
            -- hidden achievements: players only see the hint, so the admin table spells out what unlocks them
            if a.hidden and not a.custom then
                F:text("hw" .. i, getText("IGUI_MQ_Admin_HiddenWhat",
                    getText("IGUI_MQ_AchDesc_" .. a.id, A.num(a.tiers[1] or 0)), getText("IGUI_MQ_AchHint_" .. a.id)),
                    "textMuted")
            end
        end
    end
    if i == 0 then F:text("empty", getText("IGUI_MQ_Admin_NoAch"), "textMuted") end
    F:gap()

    -- batch row: every achievement of the category shown (one or two: Edit on their rows)
    local batch = { F:label("bn", getText("IGUI_MQ_Admin_CatBatch", P_.catLabel(pg.cat), A.num(i))) }
    for k, m in ipairs(MULTS) do
        local b = F:button("b:m" .. k, getText("IGUI_MQ_Admin_TierMult", AM.num(m)), P_.onMult)
        b.mult = m
        batch[#batch + 1] = b
    end
    batch[#batch + 1] = F:button("b:add", getText("IGUI_MQ_Admin_AddTier"), P_.onAddTier)
    local ct = F:button("b:ct", getText("IGUI_MQ_Admin_TierCustom"), P_.onCustomMult)
    ct.field, ct.title = "tiers", getText("IGUI_MQ_Admin_TierCustom")
    batch[#batch + 1] = ct
    local cp = F:button("b:cp", getText("IGUI_MQ_Admin_PtsCustom"), P_.onCustomMult)
    cp.field, cp.title = "pts", getText("IGUI_MQ_Admin_PtsCustom")
    batch[#batch + 1] = cp
    for k = 2, #batch do batch[k]:setEnabled(i > 0) end
    F:row(batch)
    F:text("bh", getText("IGUI_MQ_Admin_BatchHelp"), "textMuted")
    F:gap()

    if pg.newOpen then
        P_.layoutNew(P, pg, F, cats)
    else
        F:row({ F:button("n:open", getText("IGUI_MQ_Admin_NewAch"), P_.onNewToggle) })
    end
    F:gap()

    -- unlock notices and title display belong with achievements ("from which tier" is an achievement tier)
    local lw = A.labelWidth({ "broadcast.enabled", "broadcast.minTier", "broadcast.perMinute", "titles.head", "titles.chat" })
    F:head("hb", getText("IGUI_MQ_Admin_BroadcastHead"))
    A.form(P, pg, F, { { "broadcast.enabled", "bool" }, { "broadcast.minTier", "minTier" }, { "broadcast.perMinute", "perMinute" } }, lw)
    F:gap()
    F:head("ht", getText("IGUI_MQ_Admin_TitlesHead"))
    A.form(P, pg, F, { { "titles.head", "bool" }, { "titles.chat", "bool" } }, lw)
end

A.pages.achv = { layout = P_.layout }
A.AchvPage = P_
