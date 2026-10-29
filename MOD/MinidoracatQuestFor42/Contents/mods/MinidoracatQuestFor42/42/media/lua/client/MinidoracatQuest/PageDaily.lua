-- MinidoracatQuest/PageDaily.lua: daily page (spec 1.3, 2, 3, 5, 6): event banners, the horde banner, header with
--   streak and reset chips, newbie card, three personal quest cards (theme tag, points, bar, swap), the server-wide
--   card, and the streak block (seven weekday dots, milestones). questCard is shared with the weekly page.

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
-- o = { key, frame, tag, tagToken, foot = { text, token }, swap = { enabled, page } | nil, noSwapText,
--       pin = tracker id ("d1".."d4", "w1".."w3") }
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
        -- normal style (framed like the Track chip next to it): swapping drops the progress, so it must read as a control
        btn = page.pool:button(o.key .. "swap", page.UI, page.theme, getText("IGUI_MQ_UI_Swap"), page, P.onSwap)
        btn.internal = o.swap.slot
        btn.quest, btn.progText = q, progText
        btn:setEnabled(o.swap.enabled)
    end
    -- pin chip: active quests, and a pinned one after it is done (so it can be taken off the panel)
    local pinBtn = nil
    if o.pin ~= nil and (not done or C.isPinned(o.pin)) then pinBtn = D.pinChip(page, o.key .. "pin", o.pin) end
    local footH = math.max(lh, btn and btn.height or 0, pinBtn and pinBtn.height or 0)
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
    local rightEdge = right
    if o.foot ~= nil then
        rightEdge = right - b:textRight(right, textY, o.foot[1], o.foot[2]) - 8
    elseif btn ~= nil then
        btn:setX(right - btn.width)
        btn:setY(cy)
        rightEdge = right - btn.width - 6
    elseif o.noSwapText ~= nil and not done then
        rightEdge = right - b:textRight(right, textY, o.noSwapText, "textFaint") - 8
    end
    if pinBtn ~= nil then
        pinBtn:setX(rightEdge - pinBtn.width)
        pinBtn:setY(cy + math.floor((footH - pinBtn.height) / 2))
    end
    return y + h + GAP
end

-- a quest with progress asks first (the swap cannot be undone); progress 0 swaps at once
function P.onSwap(page, btn)
    if C.isPending(page.swapRid) then return end
    local slot, q = btn.internal, btn.quest
    if (tonumber(q and q.prog) or 0) > 0 and D.has(page.UI, "dialog") then
        page.UI.Dialog.show({ title = getText("IGUI_MQ_UI_Swap"),
            text = getText("IGUI_MQ_UI_SwapAsk", D.questName(q), btn.progText or ""),
            confirmText = getText("IGUI_MQ_UI_Swap"), cancelText = getText("UI_Cancel"), danger = true,
            theme = page.theme, opaque = true,
            onResult = function(ok) if ok then MinidoracatQuest.PageDaily.swap(page, slot) end end })
        return
    end
    P.swap(page, slot)
end

function P.swap(page, slot)
    if C.isPending(page.swapRid) then return end
    page.swapRid = C.send("swap", { slot = slot }, function(r)
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

-- horde banner (plan r10 state screens, hordes v2): announced / waiting / active / rest from state.hordes.cur, else
-- the last result for LAST_MS after it ended (waves cleared, points, the cap note). Returns token, title, body,
-- rightText, spot | nil; spot (the cur) while the spot matters and the vanilla map is allowed: the caller adds the
-- Map button. The page ticks every 30 s, so the countdowns here are coarse (the tracker panel counts by the second).
-- Announced counts down to the start and says the 30-tile rule, so players who stay away know when and how far
-- (design r12; a clock read as the game time). The player Hordes page shows the same banner.
P.LAST_MS = 600000
function P.hordeBanner(s, now)
    local hs = type(s) == "table" and type(s.hordes) == "table" and s.hordes or {}
    local h = D.hordeLive(hs.cur)
    if h ~= nil then
        local st = h.state
        local spot = D.HORDE_MAP[st] and D.mapAllowed() and h or nil
        if st == "announced" then
            return D.EXTRA.hordeSoon, getText("IGUI_MQ_Horde_Title_soon", D.hordePlace(h)),
                getText("IGUI_MQ_Horde_SoonBanner", D.hordeKinds(h.kinds), tostring(h.x), tostring(h.y)),
                getText("IGUI_MQ_Horde_StartsIn", D.duration((tonumber(h.startMs) or now) - now)), spot
        end
        if st == "waiting" then
            return D.EXTRA.hordeSoon, getText("IGUI_MQ_Horde_Title_wait", D.hordeName(h)),
                getText("IGUI_MQ_Horde_WaitBody", tostring(h.x), tostring(h.y)),
                getText("IGUI_MQ_UI_Left", D.duration((tonumber(h.expireAt) or now) - now)), spot
        end
        if st == "rest" then
            local w = tonumber(h.wave) or 1
            return D.EXTRA.hordeSoon, getText("IGUI_MQ_Horde_Title_rest", tostring(w), tostring(h.waves or w), D.hordePlace(h)),
                getText("IGUI_MQ_Horde_RestBody", tostring(w + 1), tostring(h.x), tostring(h.y)),
                getText("IGUI_MQ_Horde_NextIn", D.duration((tonumber(h.nextAt) or now) - now)), spot
        end
        local n = tonumber(h.size) or 0
        return D.EXTRA.horde, getText("IGUI_MQ_Horde_Title_active", D.hordeName(h)),
            getText("IGUI_MQ_Horde_ActiveBody", D.num(math.max(0, n - (tonumber(h.left) or 0))), D.num(n),
                D.num(tonumber(h.mine) or 0)),
            getText("IGUI_MQ_UI_Left", D.duration((tonumber(h.endsAt) or now) - now))
    end
    local l = hs.last
    if type(l) ~= "table" or now - (tonumber(l.endedAt) or 0) >= P.LAST_MS then return nil end
    local place = D.hordePlace(l)
    local got, cleared, waves = tonumber(l.got) or 0, tonumber(l.cleared) or 0, tonumber(l.waves) or 1
    if l.state == "success" then
        if got <= 0 then
            return D.EXTRA.success, getText("IGUI_MQ_Horde_Title_win", place),
                getText("IGUI_MQ_Horde_WinOthers", tostring(cleared), tostring(waves), D.num(tonumber(l.killed) or 0)), nil
        end
        return D.EXTRA.success, getText("IGUI_MQ_Horde_Title_win", place),
            D.hordeCapped(getText("IGUI_MQ_Horde_WinMine", tostring(cleared), tostring(waves), D.num(tonumber(l.mine) or 0)),
                l.capped), getText("IGUI_MQ_UI_PlusPoints", D.num(got))
    end
    if l.state == "cancelled" then
        return "textMuted", getText("IGUI_MQ_Horde_Title_cancel", place), getText("IGUI_MQ_Horde_CancelBody"), nil
    end
    -- the sync has no failed wave: it is the one after the cleared ones
    return "errorText", getText("IGUI_MQ_Horde_Title_fail", place),
        D.hordeFailText(l.why, tonumber(l.wave) or cleared + 1, waves, cleared, l.pool, l.capped),
        got > 0 and getText("IGUI_MQ_UI_PlusPoints", D.num(got)) or getText("IGUI_MQ_Horde_NoReward")
end

function P.onHordeMap(page, btn) D.showOnMap(0, btn.spotX, btn.spotY) end

-- the banner, with the Map button at its bottom right while the spot matters (design 5.3). Returns the y below,
-- or nil without a horde to show. The Hordes page draws it too.
function P.hordeBlock(page, b, x, y, w, s)
    local token, title, body, right, spot = P.hordeBanner(s, C.serverNow())
    if token == nil then return nil end
    if spot == nil then return b:banner(x, y, w, token, title, body, right) end
    local btn = page.pool:button("hordeMap", page.UI, page.theme, getText("IGUI_MQ_UI_Map"), page, P.onHordeMap)
    btn:setTooltip(getText("IGUI_MQ_UI_ShowOnMap"))
    btn.spotX, btn.spotY = spot.x, spot.y
    local ny = b:banner(x, y, w, token, title, body, right, btn.height + 4)
    btn:setX(x + w - 10 - btn.width)
    btn:setY(ny - D.GAP - 6 - btn.height)
    return ny
end

local function newbie(b, x, y, w, s)
    local nb = s.newbie
    if type(nb) ~= "table" then return y end
    local steps = type(nb.steps) == "table" and nb.steps or {}
    local defs = Q.Catalog.newbie
    -- only the steps this server lets players do (no sleep step with SleepAllowed off, Catalog.statOn)
    local shown, done = {}, 0
    for i = 1, 5 do
        if Q.Catalog.statOn((defs[i] or {}).stat) then
            shown[#shown + 1] = i
            if steps[i] == true then done = done + 1 end
        end
    end
    local lh = D.fontH()
    local cfg = C.defs().cfg.newbie or {}
    local title = getText("IGUI_MQ_UI_Newbie")
    if tonumber(nb.startMs) then
        title = getText("IGUI_MQ_UI_NewbieDay", tostring(math.floor((C.serverNow() - nb.startMs) / 86400000) + 1))
    end
    local foot = getText("IGUI_MQ_UI_NewbieFoot", D.num(nb.pts or cfg.pts or 0),
        cfg.title and D.titleText(cfg.title) or "")
    local footLines = D.wrap(b.UI, foot, w - 2 * CARD_PAD, UIFont.Small)
    local h = CARD_PAD + D.chipH() + 6 + #shown * (lh + 6) + #footLines * (lh + 2) + CARD_PAD
    b:card(x, y, w, h, D.EXTRA.gold)
    local cy = y + CARD_PAD
    local tw = b:text(x + CARD_PAD, cy + 3, title, D.EXTRA.gold)
    b:chip(x + CARD_PAD + tw + 8, cy, getText("IGUI_MQ_UI_Count", tostring(done), tostring(#shown)), "textMuted")
    cy = cy + D.chipH() + 6
    for _, i in ipairs(shown) do
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
    local chips = { { D.days(days), "textMuted" } }
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
        elseif v == "grace" then   -- grace and miss differ by an icon too, not only by color
            b:dot(cx, y, size, "warning")
            b:dot(cx + 3, y + 3, size - 6, "surface")
            b:icon(cx + 5, y + 5, size - 10, "pause", "warning", "-")
        elseif v == "miss" then
            b:dot(cx, y, size, "errorText")
            b:dot(cx + 3, y + 3, size - 6, "surface")
            b:icon(cx + 5, y + 5, size - 10, "close", "errorText", "x")
        else
            b:dot(cx, y, size, "border")
            b:dot(cx + 2, y + 2, size - 4, "surface")
        end
        b:textCentre(x + (i - 1) * slot + slot / 2, y + size + 2, getText("IGUI_MQ_UI_Weekday_" .. i),
            isToday and D.EXTRA.gold or "textMuted")
    end
    y = y + size + lh + 13
    local cfg = C.defs().cfg.streak or {}
    local L = nil
    for _, m in ipairs(type(cfg.milestones) == "table" and cfg.milestones or {}) do
        if L == nil then L = b:list(x, y, w) else b:listSep(L, y) end
        local reached = days >= (tonumber(m.days) or 0)
        local line = getText("IGUI_MQ_UI_Milestone", tostring(m.days), D.num(m.pts or 0))
        if m.title then line = getText("IGUI_MQ_UI_WithTitle", line, D.titleText(m.title)) end
        if reached then
            b:icon(x + 8, y + 4, 16, "check", D.EXTRA.success, "v")
        else
            b:dot(x + 12, y + 8, 8, "textFaint")
        end
        b:fitText(x + 30, y + 4, line, w - 38, reached and D.EXTRA.success or "text")
        y = y + lh + 8
    end
    if L ~= nil then y = b:listEnd(L, y) + 2 end
    y = b:para(x, y + 4, getText("IGUI_MQ_UI_StreakRule", tostring(cfg.need or 3), tostring(cfg.gracePerWeek or 1)),
        w, "textMuted")
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
    y = P.hordeBlock(page, b, x, y, w, s) or y
    local st = type(s.streak) == "table" and s.streak or {}
    local chips = {}
    if (tonumber(st.days) or 0) > 0 then chips[#chips + 1] = { getText("IGUI_MQ_UI_StreakDays", tostring(st.days)), "textMuted" } end
    if tonumber(s.resetAt) then
        chips[#chips + 1] = { getText("IGUI_MQ_UI_ResetIn", D.duration(D.left(s.resetAt))), "textMuted" }
    end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Daily"), chips)
    y = newbie(b, x, y, w, s)
    local day = type(s.day) == "table" and s.day or {}
    local quests = type(day.quests) == "table" and day.quests or {}
    local swaps = math.floor(tonumber(day.swaps) or 0)
    local pending = C.isPending(page.swapRid)
    local shared, sharedSlot = nil, nil
    for i, q in ipairs(quests) do
        if type(q) == "table" and q.state ~= "swapped" and q.state ~= "expired" then
            if q.shared then
                shared, sharedSlot = q, i
            else
                y = P.questCard(b, page, x, y, w, q, { key = "q" .. i, pin = "d" .. i,
                    swap = swaps > 0 and q.state == "active" and { slot = i, enabled = not pending } or nil,
                    noSwapText = getText("IGUI_MQ_UI_NoSwaps") })
            end
        end
    end
    if shared ~= nil then
        y = P.questCard(b, page, x, y, w, shared, { key = "shared", pin = "d" .. sharedSlot, frame = D.EXTRA.info,
            tag = getText("IGUI_MQ_UI_Shared"), tagToken = D.EXTRA.info, barToken = D.EXTRA.info,
            foot = { getText("IGUI_MQ_UI_SharedDone", D.num(day.sharedDone or 0)), D.EXTRA.info } })
        y = b:para(x, y - 2, getText("IGUI_MQ_UI_SharedNote"), w, "textMuted") + GAP
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
