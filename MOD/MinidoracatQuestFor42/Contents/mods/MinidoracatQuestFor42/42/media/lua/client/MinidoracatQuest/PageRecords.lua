-- MinidoracatQuest/PageRecords.lua: my records (spec 16): title picker (unlocked titles), my titles (each with what
--   earned it and when, plan r13), points card (balance, season, all-time) and the statistics table (season / this
--   life / all-time) from the records query, with loading and timeout states. Exchanging and its history have their
--   own page (PageExchange, user 2026-10-24).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageRecords or {}
Q.PageRecords = P

local PAD, GAP = D.PAD, D.GAP

-- ===== title =====
function P.setTitle(page, id)
    if id == "" then id = nil end
    page.titleRid = C.send("title", { id = id }, function(r)
        page.titleRid = nil
        if not r.ok then D.toast(D.codeText(r.code), "", nil) end
        page.dirty = true
    end)
end

function P.onTitleChange(page, id) P.setTitle(page, id) end
function P.onTitleChip(page, btn) P.setTitle(page, btn.internal) end

local function titleOptions(s)
    local opts, sig = { { id = "", label = getText("IGUI_MQ_UI_NoTitle") } }, ""
    for _, t in ipairs(type(s.titles) == "table" and s.titles or {}) do
        opts[#opts + 1] = { id = t, label = D.titleText(t) }
        sig = sig .. "|" .. tostring(t)
    end
    return opts, sig
end

-- returns the y below the title picker
local function titleRow(b, page, x, y, w, s)
    local UI, theme = page.UI, page.theme
    local label = getText("IGUI_MQ_UI_TitleLabel")
    local lw = b:text(x, y + 4, label, "textMuted")
    local opts, sig = titleOptions(s)
    local current = s.title or ""
    if D.has(UI, "dropdown") and UI.Dropdown ~= nil then
        local dd = page.pool:get("titleDD", function()
            return UI.Dropdown.new({ x = 0, y = 0, options = opts, selected = current, theme = theme, target = page,
                onChange = P.onTitleChange })
        end)
        if page.titleSig ~= sig then
            dd:setOptions(opts)
            page.titleSig = sig
        end
        dd:setSelected(current, true)
        dd:setEnabled(not C.isPending(page.titleRid))
        dd:setX(x + lw + 8)
        dd:setY(y)
        return y + dd.height + GAP
    end
    local btns = {}
    for i, o in ipairs(opts) do
        local btn = page.pool:button("title:" .. i, UI, theme, o.label, page, P.onTitleChip, "chip", o.id == current)
        btn.internal = o.id
        btns[#btns + 1] = btn
    end
    return D.placeRow(btns, x + lw + 8, y, x + w) + GAP
end

-- ===== my titles (plan r13; the owner chose owned titles only, 2026-10-27) =====
-- the condition from the recorded source (state.titleSrc, server Store.grantTitle): it still names the source after
-- the admin renamed the title (twice or more). Season ids carry their source, D.seasonTitle reads them.
local function recordedCond(src, defs)
    if type(src) ~= "string" then return nil end
    local ach, tier = string.match(src, "^a:(.+):(%d+)$")
    if ach ~= nil then
        tier = tonumber(tier)
        for _, a in ipairs(defs.allAch) do
            if a.id == ach and tier <= #a.tiers then return D.achTitleCond(a, tier) end
        end
        return nil
    end
    local days = string.match(src, "^streak:(%d+)$")
    if days ~= nil then return D.streakTitleCond(days, defs.cfg) end
    if src == "newbie" then return D.newbieTitleCond(defs.cfg) end
    return nil
end

-- newest first; titles from before titleAt existed have no time ("early") and follow in catalog order
local function myTitles(b, page, x, y, w, s)
    local owned = type(s.titles) == "table" and s.titles or {}
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_MyTitles", tostring(#owned)))
    local L = b:list(x, y, w)
    if #owned == 0 then
        return b:listEnd(L, b:para(x + 8, y + 6, getText("IGUI_MQ_UI_MyTitlesEmpty"), w - 16, "textMuted") + 4) + GAP
    end
    local defs = C.defs()
    local no = type(s.season) == "table" and tonumber(s.season.no) or 1
    -- a title id can come from several sources (admins may reuse a text): first the sources this player reached,
    -- then any other one except hidden achievements, which stay secret until unlocked (PageAchievements rule)
    local achv = type(s.achv) == "table" and s.achv or {}
    local sources = D.titleSources(defs.allAch, defs.cfg, no)
    local byId, order = {}, {}
    for pass = 1, 2 do
        for i, r in ipairs(sources) do
            local reached = r.ach == nil or (tonumber(achv[r.ach]) or 0) >= r.tier
            if (pass == 1 and reached) or (pass == 2 and not reached and not r.hidden) then
                for _, id in ipairs({ r.id, r.alt }) do
                    if byId[id] == nil then byId[id], order[id] = r, i end
                end
            end
        end
        -- after the reached rows: a default id whose tier title the admin cleared since (no row above), held from
        -- before titleSrc; the tier the player reached still names the condition
        if pass == 1 then
            for _, a in ipairs(defs.allAch) do
                for t, def in pairs(a.defTitles or {}) do
                    t = tonumber(t)
                    if t ~= nil and t <= #a.tiers and byId[def] == nil and (tonumber(achv[a.id]) or 0) >= t then
                        byId[def] = { cond = D.achTitleCond(a, t) }
                    end
                end
            end
        end
    end
    local at = type(s.titleAt) == "table" and s.titleAt or {}
    local srcOf = type(s.titleSrc) == "table" and s.titleSrc or {}
    local hName, hCond, hGot = getText("IGUI_MQ_UI_TitleLabel"), getText("IGUI_MQ_UI_ColCond"), getText("IGUI_MQ_UI_ColGot")
    local worn = getText("IGUI_MQ_UI_TitleWorn")
    local nameW, timeW = D.textW(hName), D.textW(hGot)
    local rows = {}
    for _, id in ipairs(owned) do
        local src = byId[id] or D.seasonTitle(id, defs.cfg)
        local r = { name = D.titleText(id), cond = recordedCond(srcOf[id], defs) or src and src.cond
            or getText("IGUI_MQ_UI_TitleNoSource"), at = tonumber(at[id]), order = order[id] or #owned + 1e6, worn = id == s.title }
        r.time = r.at and D.ymd(r.at) or getText("IGUI_MQ_UI_TitleEarly")
        nameW, timeW = math.max(nameW, D.textW(r.name), r.worn and D.textW(worn) or 0), math.max(timeW, D.textW(r.time))
        rows[#rows + 1] = r
    end
    Q.Util.sort(rows, function(p, q)
        if (p.at ~= nil) ~= (q.at ~= nil) then return p.at ~= nil end
        if p.at ~= q.at then return p.at > q.at end
        return p.order < q.order
    end)
    nameW = math.min(nameW, math.floor(w * 0.35))
    local lh = D.fontH()
    local condX = x + 8 + nameW + 12
    local condW = x + w - 8 - timeW - 12 - condX
    local rh = lh + 8
    b:listHead(L, rh)
    b:fitText(x + 8, y + 4, hName, nameW, "text")
    b:fitText(condX, y + 4, hCond, condW, "text")
    b:textRight(x + w - 8, y + 4, hGot, "text")
    y = y + rh
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        local names = D.wrap(b.UI, r.name, nameW, UIFont.Small)   -- admin-typed titles can be long
        local conds = D.wrap(b.UI, r.cond, condW, UIFont.Small)
        local ny = y + 4
        for _, l in ipairs(names) do
            b:text(x + 8, ny, l, "text")
            ny = ny + lh + 2
        end
        if r.worn then
            b:text(x + 8, ny, worn, "success")
            ny = ny + lh + 2
        end
        local cy = y + 4
        for _, l in ipairs(conds) do
            b:text(condX, cy, l, "text")
            cy = cy + lh + 2
        end
        b:textRight(x + w - 8, y + 4, r.time, r.at and "text" or "textFaint")
        y = math.max(ny, cy) + 2
    end
    return b:listEnd(L, y) + GAP
end

-- ===== points card =====
local function pointsCard(b, page, x, y, w, s)
    local pts = type(s.points) == "table" and s.points or {}
    local pad = 10
    local mh, lh = D.fontH(UIFont.Medium), D.fontH()
    local inner = w - 2 * pad
    local subLines = D.wrap(page.UI, getText("IGUI_MQ_UI_PointsSub", D.num(pts.season or 0), D.num(pts.total or 0)),
        inner, UIFont.Small)
    local noteLines = D.wrap(page.UI, getText("IGUI_MQ_UI_PointsNote"), inner, UIFont.Small)
    local h = pad + lh + 2 + mh + 4 + (#subLines + #noteLines) * (lh + 2) + pad
    b:card(x, y, w, h, D.EXTRA.gold)
    local cy = y + pad
    b:text(x + pad, cy, getText("IGUI_MQ_UI_Balance"), "textMuted")
    cy = cy + lh + 2
    b:text(x + pad, cy, D.num(pts.balance or 0), D.EXTRA.gold, UIFont.Medium)
    cy = cy + mh + 4
    for _, l in ipairs(subLines) do
        b:text(x + pad, cy, l, "text")
        cy = cy + lh + 2
    end
    for _, l in ipairs(noteLines) do
        b:text(x + pad, cy, l, "textMuted")
        cy = cy + lh + 2
    end
    return y + h + GAP
end

-- ===== table =====
function P.value(stat, v)
    if v == nil then return "-" end
    return D.num(v)
end

function P.onRetry() MinidoracatQuest.Client.requestRecords(true) end

local function statsTable(b, page, x, y, w, s)
    local rec = C.records
    if rec == nil then
        if C.recordsError ~= nil then
            y = b:para(x, y, getText("IGUI_MQ_UI_RecordsError"), w, "errorText")
            local btn = page.pool:button("retry", page.UI, page.theme, getText("IGUI_MQ_UI_Refresh"), page, P.onRetry)
            btn:setX(x)
            btn:setY(y)
            return y + btn.height + GAP
        end
        b:chip(x, y, getText("IGUI_MQ_UI_Loading"), "textMuted")
        return y + D.chipH() + GAP
    end
    local lh = D.fontH()
    local rows, used = {}, {}
    local stats = C.defs().stats
    local function add(r)
        if type(r) ~= "table" or r.stat == nil or used[r.stat] then return end
        used[r.stat] = true
        -- no definition (a removed pack's stat): not listed, its name would be a raw key
        local def = stats[r.stat]
        if type(def) ~= "table" then return end
        -- account-level stats (quests, achievement tiers) have no "this life" value
        rows[#rows + 1] = { D.statName(r.stat), P.value(r.stat, r.season), def.account and "-" or P.value(r.stat, r.life),
            P.value(r.stat, r.total) }
    end
    -- catalog display order first, then whatever else the server sent (facade stats)
    for _, id in ipairs(Q.Catalog and Q.Catalog.statOrder or {}) do add(C.statRow(id)) end
    for _, r in ipairs(type(rec.rows) == "table" and rec.rows or {}) do add(r) end
    local rp = type(rec.points) == "table" and rec.points or {}
    rows[#rows + 1] = { getText("IGUI_MQ_UI_PointsEarned"), D.num(rp.season or 0), "-", D.num(rp.total or 0), gold = true }
    local heads = { getText("IGUI_MQ_UI_ColStat"), getText("IGUI_MQ_UI_ColSeason"), getText("IGUI_MQ_UI_ColLife"),
        getText("IGUI_MQ_UI_ColTotal") }
    local colW = { 0, 0, 0, 0 }
    for c = 2, 4 do
        colW[c] = D.textW(heads[c])
        for _, r in ipairs(rows) do colW[c] = math.max(colW[c], D.textW(r[c])) end
        colW[c] = colW[c] + 16
    end
    local right = { x + w - 8 }
    right[3] = right[1] - colW[4]
    right[2] = right[3] - colW[3]
    local nameW = right[2] - colW[2] - x - 8
    local rh = lh + 8
    local L = b:list(x, y, w)
    b:listHead(L, rh)
    b:fitText(x + 8, y + 4, heads[1], nameW, "text")
    b:textRight(right[2], y + 4, heads[2], "text")
    b:textRight(right[3], y + 4, heads[3], "text")
    b:textRight(right[1], y + 4, heads[4], "text")
    y = y + rh
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        local tok = r.gold and D.EXTRA.gold or "text"
        b:fitText(x + 8, y + 4, r[1], nameW, tok)
        b:textRight(right[2], y + 4, r[2], tok)
        b:textRight(right[3], y + 4, r[3], tok)
        b:textRight(right[1], y + 4, r[4], tok)
        y = y + rh
    end
    y = b:listEnd(L, y)
    return b:para(x, y + 6, getText("IGUI_MQ_UI_RecordsNote"), w, "textMuted") + GAP
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Records"))
    if s == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    y = titleRow(b, page, x, y, w, s)
    y = myTitles(b, page, x, y, w, s)
    y = pointsCard(b, page, x, y, w, s)
    -- what the one-time import (Achievements Import.baseline) brought over from before the MOD was added
    y = b:para(x, y - 2, getText("IGUI_MQ_UI_ImportNote"), w, "textMuted") + GAP
    y = statsTable(b, page, x, y, w, s)
    D.finish(page, y)
end

P.spec = {
    id = "records", label = "IGUI_MQ_UI_NavRecords", icon = "transactions", group = "main", order = 50,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageRecords.layout(page) end,
    onShow = function() MinidoracatQuest.Client.requestRecords(true) end,
}
W.register(P.spec)
