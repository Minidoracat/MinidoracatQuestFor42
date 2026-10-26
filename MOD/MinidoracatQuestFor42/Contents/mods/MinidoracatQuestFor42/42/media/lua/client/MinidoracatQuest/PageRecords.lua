-- MinidoracatQuest/PageRecords.lua: my records (spec 16): title picker (unlocked titles), points card (balance,
--   season, all-time) and the statistics table (season / this life / all-time) from the records query, with
--   loading and timeout states. Exchanging and its history have their own page (PageExchange, user 2026-10-24).

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
