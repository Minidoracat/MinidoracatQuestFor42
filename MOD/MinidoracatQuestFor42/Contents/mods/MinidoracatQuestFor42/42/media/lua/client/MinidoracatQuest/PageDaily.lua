-- MinidoracatQuest/PageDaily.lua: daily page (spec 1.3, 2, 3, 5, 6): event banners, header with streak and reset
--   chips, newbie card, three personal quest cards (theme tag, points, bar, swap), the server-wide card, and the
--   streak block (seven weekday dots, milestones). questCard is shared with the weekly page.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageDaily or {}
Q.PageDaily = P

local PAD, GAP = D.PAD, D.GAP
local CARD_PAD = 10

-- ===== quest card =====
-- o = { key, frame, tag, tagToken, foot = { text, token }, swap = { enabled, page } | nil, noSwapText }
-- returns the y below the card
function P.questCard(b, page, x, y, w, q, o)
    local lh = D.fontH()
    local inner = w - 2 * CARD_PAD
    local done = q.state == "done"
    -- ptsNow: what the server pays now (event multiplier applied, or the payout once done); older servers: pts
    local pts = getText("IGUI_MQ_UI_PlusPoints", D.num(tonumber(q.ptsNow) or q.pts or 0))
    local ptsW = D.textW(pts) + (done and 20 or 0)
    local mult = (not done) and D.eventMult(q.theme) or nil
    local multText = mult and getText("IGUI_MQ_UI_Mult", D.mult(mult)) or nil
    local multW = multText and (D.chipW(multText) + 6) or 0
    local tag = o.tag or D.themeName(q.theme)
    local nameLines = D.wrap(page.UI, D.questName(q), inner, UIFont.Small)
    local target = tonumber(q.target) or 0
    local prog = math.min(tonumber(q.prog) or 0, target > 0 and target or (tonumber(q.prog) or 0))
    local progText = getText("IGUI_MQ_UI_Progress", D.num(prog), D.num(target))
    local btn = nil
    if o.swap ~= nil and not done then
        btn = page.pool:button(o.key .. "swap", page.UI, page.theme, getText("IGUI_MQ_UI_Swap"), page, P.onSwap, "ghost")
        btn.internal = o.swap.slot
        btn:setEnabled(o.swap.enabled)
    end
    local footH = math.max(lh, btn and btn.height or 0)
    local h = CARD_PAD + D.chipH() + 6 + #nameLines * (lh + 2) + 4 + 6 + 6 + footH + CARD_PAD
    b:card(x, y, w, h, o.frame or (done and D.EXTRA.success) or "border")
    local cy = y + CARD_PAD
    b:chip(x + CARD_PAD, cy, tag, o.tagToken or "textMuted")
    local right = x + w - CARD_PAD
    if multText then b:chip(right - ptsW - multW, cy, multText, D.EXTRA.event, true) end
    if done then
        b:icon(right - ptsW, cy + 3, 16, "check", D.EXTRA.success, "v")
        b:textRight(right, cy + 3, pts, D.EXTRA.success)
    else
        b:textRight(right, cy + 3, pts, D.EXTRA.gold)
    end
    cy = cy + D.chipH() + 6
    for _, line in ipairs(nameLines) do
        b:text(x + CARD_PAD, cy, line, "text")
        cy = cy + lh + 2
    end
    cy = cy + 4
    b:bar(x + CARD_PAD, cy, inner, 6, target > 0 and prog / target or (done and 1 or 0),
        done and D.EXTRA.success or (o.barToken or "accent"))
    cy = cy + 12
    local textY = cy + math.floor((footH - lh) / 2)
    if done then
        b:text(x + CARD_PAD, textY, getText("IGUI_MQ_UI_QuestDone"), D.EXTRA.success)
    else
        b:text(x + CARD_PAD, textY, progText, "textMuted")
    end
    if o.foot ~= nil then
        b:textRight(right, textY, o.foot[1], o.foot[2])
    elseif btn ~= nil then
        btn:setX(right - btn.width)
        btn:setY(cy)
    elseif o.noSwapText ~= nil and not done then
        b:textRight(right, textY, o.noSwapText, "textFaint")
    end
    return y + h + GAP
end

function P.onSwap(page, btn)
    if C.isPending(page.swapRid) then return end
    page.swapRid = C.send("swap", { slot = btn.internal }, function(r)
        page.swapRid = nil
        if not r.ok then D.toast(D.codeText(r.code), "", nil) end
        page.dirty = true
    end)
    page.dirty = true
end

-- ===== blocks =====
local function events(b, x, y, w, s)
    local now = C.serverNow()
    for _, ev in ipairs(type(s.events) == "table" and s.events or {}) do
        if (tonumber(ev.endsAt) or 0) > now then
            y = b:banner(x, y, w, D.EXTRA.event, tostring(ev.name or ""),
                getText("IGUI_MQ_UI_EventLine", D.themeName(ev.theme), D.mult(ev.mult)),
                getText("IGUI_MQ_UI_Left", D.duration(ev.endsAt - now)))
        end
    end
    return y
end

local function newbie(b, x, y, w, s)
    local nb = s.newbie
    if type(nb) ~= "table" then return y end
    local steps = type(nb.steps) == "table" and nb.steps or {}
    local defs = Q.Catalog and Q.Catalog.newbie or {}
    local done = 0
    for i = 1, 5 do if steps[i] == true then done = done + 1 end end
    local lh = D.fontH()
    local cfg = C.defs().cfg.newbie or {}
    local title = getText("IGUI_MQ_UI_Newbie")
    if tonumber(nb.startMs) then
        title = getText("IGUI_MQ_UI_NewbieDay", tostring(math.floor((C.serverNow() - nb.startMs) / 86400000) + 1))
    end
    local foot = getText("IGUI_MQ_UI_NewbieFoot", D.num(nb.pts or cfg.pts or 0),
        cfg.title and D.titleText(cfg.title) or "")
    local footLines = D.wrap(b.UI, foot, w - 2 * CARD_PAD, UIFont.Small)
    local h = CARD_PAD + D.chipH() + 6 + 5 * (lh + 6) + #footLines * (lh + 2) + CARD_PAD
    b:card(x, y, w, h, D.EXTRA.gold)
    local cy = y + CARD_PAD
    local tw = b:text(x + CARD_PAD, cy + 3, title, D.EXTRA.gold)
    b:chip(x + CARD_PAD + tw + 8, cy, getText("IGUI_MQ_UI_Count", tostring(done), "5"), D.EXTRA.gold)
    cy = cy + D.chipH() + 6
    for i = 1, 5 do
        local ok = steps[i] == true
        local def = defs[i] or {}
        if ok then
            b:icon(x + CARD_PAD, cy, 16, "check", D.EXTRA.success, "v")
        else
            b:dot(x + CARD_PAD + 3, cy + 3, 10, "textFaint")
            b:dot(x + CARD_PAD + 5, cy + 5, 6, "surface")
        end
        b:text(x + CARD_PAD + 24, cy, getText("IGUI_MQ_UI_NewbieStep_" .. i, D.num(def.target or 1)),
            ok and "textMuted" or "text")
        cy = cy + lh + 6
    end
    for _, line in ipairs(footLines) do
        b:text(x + CARD_PAD, cy, line, "textMuted")
        cy = cy + lh + 2
    end
    return y + h + GAP
end

-- streak block: chip days, grace chip, seven weekday dots, milestones, rule caption
function P.streak(b, x, y, w, s)
    local st = type(s.streak) == "table" and s.streak or {}
    local days = math.floor(tonumber(st.days) or 0)
    local chips = { { D.days(days), D.EXTRA.gold } }
    if st.graceUsed then chips[2] = { getText("IGUI_MQ_UI_GraceUsed"), "warning" } end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Streak"), chips) + 3   -- room for today's ring
    local lh = D.fontH()
    local slot = math.min(56, math.floor(w / 7))
    local size = 22
    local week = type(st.week) == "table" and st.week or {}
    local today = tonumber(st.today)   -- 1 = Monday; marked with a gold ring and label
    for i = 1, 7 do
        local cx = x + (i - 1) * slot + math.floor((slot - size) / 2)
        local v = week[i]
        local isToday = i == today
        if isToday then
            b:dot(cx - 3, y - 3, size + 6, D.EXTRA.gold)
            b:dot(cx - 1, y - 1, size + 2, "surface")
        end
        if v == "done" then
            b:dot(cx, y, size, D.EXTRA.success)
        elseif v == "grace" then
            b:dot(cx, y, size, "warning")
            b:dot(cx + 3, y + 3, size - 6, "surface")
        elseif v == "miss" then
            b:dot(cx, y, size, "errorText")
            b:dot(cx + 3, y + 3, size - 6, "surface")
        else
            b:dot(cx, y, size, "border")
            b:dot(cx + 2, y + 2, size - 4, "surface")
        end
        b:textCentre(x + (i - 1) * slot + slot / 2, y + size + 2, getText("IGUI_MQ_UI_Weekday_" .. i),
            isToday and D.EXTRA.gold or "textMuted")
    end
    y = y + size + lh + 13
    local cfg = C.defs().cfg.streak or {}
    for _, m in ipairs(type(cfg.milestones) == "table" and cfg.milestones or {}) do
        local reached = days >= (tonumber(m.days) or 0)
        local line = getText("IGUI_MQ_UI_Milestone", tostring(m.days), D.num(m.pts or 0))
        if m.title then line = getText("IGUI_MQ_UI_WithTitle", line, D.titleText(m.title)) end
        if reached then
            b:icon(x, y, 16, "check", D.EXTRA.success, "v")
        else
            b:dot(x + 4, y + 4, 8, "textFaint")
        end
        b:fitText(x + 22, y, line, w - 22, reached and D.EXTRA.success or "text")
        y = y + lh + 4
    end
    y = b:para(x, y + 4, getText("IGUI_MQ_UI_StreakRule", tostring(cfg.need or 3), tostring(cfg.gracePerWeek or 1)),
        w, "textFaint")
    return y + GAP
end

-- ===== page =====
function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    if s == nil then
        y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Daily"))
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    y = events(b, x, y, w, s)
    local st = type(s.streak) == "table" and s.streak or {}
    local chips = {}
    if (tonumber(st.days) or 0) > 0 then chips[#chips + 1] = { getText("IGUI_MQ_UI_StreakDays", tostring(st.days)), D.EXTRA.gold } end
    if tonumber(s.resetAt) then
        chips[#chips + 1] = { getText("IGUI_MQ_UI_ResetIn", D.duration(D.left(s.resetAt))), "textMuted" }
    end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Daily"), chips)
    y = newbie(b, x, y, w, s)
    local day = type(s.day) == "table" and s.day or {}
    local quests = type(day.quests) == "table" and day.quests or {}
    local swaps = math.floor(tonumber(day.swaps) or 0)
    local pending = C.isPending(page.swapRid)
    local shared = nil
    for i, q in ipairs(quests) do
        if type(q) == "table" and q.state ~= "swapped" and q.state ~= "expired" then
            if q.shared then
                shared = q
            else
                y = P.questCard(b, page, x, y, w, q, { key = "q" .. i,
                    swap = swaps > 0 and q.state == "active" and { slot = i, enabled = not pending } or nil,
                    noSwapText = getText("IGUI_MQ_UI_NoSwaps") })
            end
        end
    end
    if shared ~= nil then
        y = P.questCard(b, page, x, y, w, shared, { key = "shared", frame = D.EXTRA.info,
            tag = getText("IGUI_MQ_UI_Shared"), tagToken = D.EXTRA.info, barToken = D.EXTRA.info,
            foot = { getText("IGUI_MQ_UI_SharedDone", D.num(day.sharedDone or 0)), D.EXTRA.info } })
        y = b:para(x, y - 2, getText("IGUI_MQ_UI_SharedNote"), w, "textFaint") + GAP
    end
    if #quests == 0 then y = b:para(x, y, getText("IGUI_MQ_UI_NoQuests"), w, "textMuted") + GAP end
    y = P.streak(b, x, y + 4, w, s)
    D.finish(page, y)
end

P.spec = {
    id = "daily", label = "IGUI_MQ_UI_NavDaily", icon = "check", group = "main", order = 10, ticking = true,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageDaily.layout(page) end,
}
W.register(P.spec)
