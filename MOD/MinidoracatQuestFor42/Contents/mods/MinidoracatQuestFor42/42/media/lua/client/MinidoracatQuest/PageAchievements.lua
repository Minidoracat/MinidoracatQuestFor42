-- MinidoracatQuest/PageAchievements.lua: achievements page (spec 8.2): unlocked-count chip, category filter chips
--   (categories without achievements are hidden), one card per achievement: icon with a tier-colored frame,
--   tier badge in text and color, next tier with threshold and points, progress bar from the records totals
--   (scope "life" reads the this-life column); hidden achievements show only their hint until unlocked.
--   Icons: media/ui/MinidoracatQuest/ach/<icon>.png, missing -> framework icon tinted with the tier color.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageAchievements or {}
Q.PageAchievements = P

local PAD, GAP = D.PAD, D.GAP
P.ICON_DIR = "media/ui/MinidoracatQuest/ach/"

-- ===== model (harness tests these) =====
-- a = effective achievement, tier = unlocked tier (0 = locked), row = records row or nil
function P.model(a, tier, row)
    tier = math.floor(tonumber(tier) or 0)
    local n = #a.tiers
    local m = { tier = tier, maxed = n > 0 and tier >= n, locked = tier <= 0, hiddenLocked = a.hidden and tier <= 0 }
    if not m.maxed and n > 0 then
        m.nextTier = tier + 1
        m.target = tonumber(a.tiers[tier + 1]) or 0
        m.pts = tonumber(a.pts[tier + 1]) or 0
    end
    if row ~= nil then m.value = tonumber(a.scope == "life" and row.life or row.total) or 0 end
    return m
end

-- categories that have at least one achievement, in catalog order (extras appended)
function P.categories(defs)
    local present, out = {}, {}
    for _, a in ipairs(defs.achievements) do present[a.cat or "other"] = true end
    local order = Q.Catalog and Q.Catalog.achCats or (Q.Contract and Q.Contract.ACH_CATS) or {}
    for _, cat in ipairs(order) do
        if present[cat] then
            out[#out + 1] = cat
            present[cat] = nil
        end
    end
    for _, a in ipairs(defs.achievements) do
        local cat = a.cat or "other"
        if present[cat] then
            out[#out + 1] = cat
            present[cat] = nil
        end
    end
    return out
end

function P.counts(defs, achv)
    local got = 0
    for _, a in ipairs(defs.achievements) do
        if (tonumber(achv and achv[a.id]) or 0) >= 1 then got = got + 1 end
    end
    return got, #defs.achievements
end

-- ===== card =====
local function iconTexture(a)
    if a.icon == nil then return nil end
    return D.tex(P.ICON_DIR .. tostring(a.icon) .. ".png")
end

local function card(b, page, x, y, w, a, m)
    local lh = D.fontH()
    local pad, box = 10, 40
    local tx = x + pad + box + 10
    local tw = x + w - pad - tx
    local tierCol = m.locked and b:col("textFaint") or D.tierColor(m.tier)
    local name = m.hiddenLocked and getText("IGUI_MQ_UI_HiddenAch") or D.achName(a)
    local badge = (not m.locked) and D.tierName(m.tier) or nil
    local badgeW = badge and D.chipW(badge) or 0
    local life = (a.scope == "life") and getText("IGUI_MQ_UI_LifeOnly") or nil
    local lifeW = life and (D.chipW(life) + 6) or 0
    -- pin chip: an achievement with a tier left (hidden ones stay secret); a pinned one always, to unpin it
    local pinId = "a:" .. a.id
    local pinBtn = nil
    if C.isPinned(pinId) or (not m.maxed and not a.hidden and #a.tiers > 0) then
        pinBtn = D.pinChip(page, "pin:" .. a.id, pinId)
    end
    local pinW = pinBtn and (pinBtn.width + 6) or 0
    local line
    if m.hiddenLocked then
        line = getText("IGUI_MQ_UI_Hint", D.achHint(a))
    elseif m.maxed then
        line = getText("IGUI_MQ_UI_AchMaxed")
    else
        line = getText("IGUI_MQ_UI_AchNext", D.tierName(m.nextTier), D.achDesc(a, m.nextTier), D.num(m.pts))
    end
    local lines = D.wrap(page.UI, line, tw, UIFont.Small)
    local showBar = not m.maxed and not m.hiddenLocked and m.value ~= nil and (m.target or 0) > 0
    local textH = D.chipH() + 4 + #lines * (lh + 2) + (showBar and (6 + 4 + lh) or 0)
    local h = math.max(box, textH) + 2 * pad
    b:card(x, y, w, h, (not m.locked) and tierCol or "border")
    -- icon box: tier frame drawn twice for a 2 px edge
    local bx, by = x + pad, y + pad
    b:fill(bx, by, box, box, "well")
    b:border(bx, by, box, box, tierCol)
    b:border(bx + 1, by + 1, box - 2, box - 2, tierCol)
    if m.hiddenLocked then
        b:textCentre(bx + box / 2, by + math.floor((box - D.fontH(UIFont.Medium)) / 2), "?", "textFaint", UIFont.Medium)
    else
        local tex = iconTexture(a)
        if tex ~= nil then
            b:tex(bx + 4, by + 4, box - 8, box - 8, tex)
        else
            b:icon(bx + 8, by + 8, box - 16, "markerStar", tierCol, "*")
        end
    end
    local cy = y + pad
    local nameW = b:fitText(tx, cy + 3, name, tw - badgeW - lifeW - pinW - 8, m.hiddenLocked and "textMuted" or "text")
    if life then b:chip(tx + nameW + 6, cy, life, "warning") end
    if badge then b:chip(x + w - pad - badgeW, cy, badge, tierCol, true) end
    if pinBtn then
        pinBtn:setX(x + w - pad - badgeW - (badge and 6 or 0) - pinBtn.width)
        pinBtn:setY(cy + math.floor((D.chipH() - pinBtn.height) / 2))
    end
    cy = cy + D.chipH() + 4
    for _, l in ipairs(lines) do
        b:text(tx, cy, l, m.maxed and D.EXTRA.success or "textMuted")
        cy = cy + lh + 2
    end
    if showBar then
        local v = math.min(m.value, m.target)
        b:bar(tx, cy + 2, tw, 6, v / m.target, D.tierColor(m.nextTier))
        cy = cy + 10
        b:textRight(x + w - pad, cy, getText("IGUI_MQ_UI_Progress", D.num(v), D.num(m.target)), "textMuted")
    end
    return y + h + 6
end

-- ===== page =====
function P.onCat(page, btn)
    page.cat = btn.internal
    page.sp:setYScroll(0)
    page.dirty = true
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    local defs = C.defs()
    local achv = s and type(s.achv) == "table" and s.achv or {}
    local got, total = P.counts(defs, achv)
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Achievements"),
        { { getText("IGUI_MQ_UI_Count", tostring(got), tostring(total)), D.EXTRA.gold } })
    if s == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    page.cat = page.cat or "all"
    local cats = P.categories(defs)
    local found = page.cat == "all"
    local btns = { page.pool:button("cat:all", page.UI, page.theme, getText("IGUI_MQ_UI_All"), page, P.onCat, "chip",
        page.cat == "all") }
    btns[1].internal = "all"
    for _, cat in ipairs(cats) do
        local btn = page.pool:button("cat:" .. cat, page.UI, page.theme, getText("IGUI_MQ_AchCat_" .. cat), page, P.onCat,
            "chip", page.cat == cat)
        btn.internal = cat
        btns[#btns + 1] = btn
        if cat == page.cat then found = true end
    end
    if not found then
        page.cat = "all"
        btns[1]:setActive(true)
    end
    y = D.placeRow(btns, x, y, x + w) + GAP + 2
    if C.recordsSentAt ~= nil and C.records == nil then
        b:chip(x, y, getText("IGUI_MQ_UI_Loading"), "textMuted")
        y = y + D.chipH() + GAP
    end
    local n = 0
    for _, a in ipairs(defs.achievements) do
        if page.cat == "all" or (a.cat or "other") == page.cat then
            n = n + 1
            y = card(b, page, x, y, w, a, P.model(a, achv[a.id], C.records ~= nil and (C.statRow(a.stat) or {}) or nil))
        end
    end
    if n == 0 then y = b:para(x, y, getText("IGUI_MQ_UI_NoAch"), w, "textMuted") end
    D.finish(page, y + GAP)
end

P.spec = {
    id = "achievements", label = "IGUI_MQ_UI_NavAchievements", icon = "markerStar", group = "main", order = 30,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageAchievements.layout(page) end,
    onShow = function() MinidoracatQuest.Client.requestRecords(false) end,
}
W.register(P.spec)
