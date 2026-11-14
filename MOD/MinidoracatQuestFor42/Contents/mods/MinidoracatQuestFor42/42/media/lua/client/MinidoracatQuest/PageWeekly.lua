-- MinidoracatQuest/PageWeekly.lua: weekly page (spec 4): the server-wide weekly goal card (gold frame, 8 px bar,
--   my contribution, payout rule) on top, the server-wide donation card under it (state.donate, plan points-play-1112
--   claim 3: progress, my share, "Donate..." opening DonateDialog; once full the extra horde's time), then the header
--   with the Monday reset countdown and the three weekly quest cards (same card as daily, no swap).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"
require "MinidoracatQuest/PageDaily"
require "MinidoracatQuest/DonateDialog"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageWeekly or {}
Q.PageWeekly = P

local PAD, GAP = D.PAD, D.GAP

local function goalLine(g)
    local key = "IGUI_MQ_UI_Goal_" .. string.gsub(tostring(g.stat), "[%.:]", "_")
    if D.textOrNull(key) ~= nil then return getText(key, D.num(g.target or 0)) end
    return getText("IGUI_MQ_UI_GoalGeneric", D.statName(g.stat), D.num(g.target or 0))
end

function P.goal(b, page, x, y, w, s)
    local g = s.goal
    if type(g) ~= "table" then return y end
    local lh, pad = D.fontH(), 10
    local inner = w - 2 * pad
    local target = tonumber(g.target) or 0
    local progress = tonumber(g.progress) or 0
    local week = type(s.week) == "table" and s.week or {}
    local rule = getText("IGUI_MQ_UI_GoalRule", D.num(g.minContrib or 0), D.num(g.pts or 0))
    local ruleLines = D.wrap(page.UI, rule, inner, UIFont.Small)
    local line = goalLine(g)
    local lineH = D.fontH(UIFont.Medium)
    local h = pad + D.chipH() + 6 + lineH + 6 + 8 + 8 + lh + 6 + #ruleLines * (lh + 2) + pad
    b:card(x, y, w, h, g.reached and D.EXTRA.success or D.EXTRA.info)
    local cy = y + pad
    local tw = b:text(x + pad, cy + 3, getText("IGUI_MQ_UI_GoalTitle"), D.EXTRA.info)
    if tonumber(g.endsAt) then
        b:chip(x + pad + tw + 8, cy, getText("IGUI_MQ_UI_SettlesAt", D.dateTime(g.endsAt - 60000)), "textMuted")
    end
    if g.reached then
        b:textRight(x + w - pad, cy + 3, getText("IGUI_MQ_UI_GoalReached"), D.EXTRA.success)
    end
    cy = cy + D.chipH() + 6
    b:fitText(x + pad, cy, line, inner, "text", UIFont.Medium)
    cy = cy + lineH + 6
    b:bar(x + pad, cy, inner, 8, target > 0 and progress / target or 0, g.reached and D.EXTRA.success or D.EXTRA.info)
    cy = cy + 16
    b:text(x + pad, cy, getText("IGUI_MQ_UI_Progress", D.num(progress), D.num(target)), "textMuted")
    -- reaching the minimum contribution shows a check too, not only the green color
    local met = (tonumber(week.goalPart) or 0) >= (tonumber(g.minContrib) or 0)
    local mw = b:textRight(x + w - pad, cy, getText("IGUI_MQ_UI_GoalMine", D.num(week.goalPart or 0)),
        met and D.EXTRA.success or "text")
    if met then b:icon(x + w - pad - mw - 20, cy, 16, "check", D.EXTRA.success, "v") end
    cy = cy + lh + 6
    for _, l in ipairs(ruleLines) do
        b:text(x + pad, cy, l, "textMuted")
        cy = cy + lh + 2
    end
    return y + h + GAP
end

function P.onDonate() Q.DonateDialog.open() end

-- The donation card (blue frame like the goal: "server-wide"). Not full: the target and when its horde comes, the bar,
-- the total and my share, "what is not full stays for next week" and Donate...; full (hordeAt): the extra horde's
-- time, how many donations filled it and what already counts toward the next round. "Toughness xN" when hp ~= 1.
-- No reset chip: a round not full stays. Less than the least donation: no button, how many points are missing.
function P.donate(b, page, x, y, w, s)
    local d = type(s.donate) == "table" and s.donate or nil
    if d == nil or (d.on ~= true and tonumber(d.hordeAt) == nil) then return y end
    local cfg = C.defs().cfg.donate or {}
    local lh, pad, mh = D.fontH(), 10, D.fontH(UIFont.Medium)
    local inner = w - 2 * pad
    local full = tonumber(d.hordeAt) ~= nil
    local target, total = tonumber(d.target) or 0, tonumber(d.total) or 0
    local line = full and getText("IGUI_MQ_UI_DonateAt", D.dateTime(d.hordeAt))
        or getText("IGUI_MQ_UI_DonateGoal", D.num(target), getText("IGUI_MQ_UI_Weekday_" .. tostring(cfg.day or 6)),
            tostring(cfg.time or ""))
    local notes = {}
    if (tonumber(d.hp) or 1) ~= 1 then notes[#notes + 1] = getText("IGUI_MQ_UI_DonateHp", D.mult(d.hp)) end
    if full then
        local last = type(d.last) == "table" and d.last or {}
        notes[#notes + 1] = getText("IGUI_MQ_UI_DonateDoneBody", D.num(last.n or 0), D.num(total))
    end
    local noteLines = {}
    for _, n in ipairs(notes) do
        for _, l in ipairs(D.wrap(page.UI, n, inner, UIFont.Small)) do noteLines[#noteLines + 1] = l end
    end
    local q = C.donateQuote(s, nil)
    local btn, foot = nil, full and "" or getText("IGUI_MQ_UI_DonateKeep")
    if d.on == true then
        if q.balance >= q.min then
            btn = page.pool:button("donate", page.UI, page.theme, getText("IGUI_MQ_UI_DonateOpen"), page, P.onDonate)
        else
            foot = getText("IGUI_MQ_UI_PointsShort", D.num(q.min - q.balance))
        end
    end
    local footH = math.max(lh, btn and btn.height or 0)
    local h = pad + D.chipH() + 6 + mh + 6 + #noteLines * (lh + 2) + (full and 0 or 8 + 8 + lh + 6) + footH + pad
    b:card(x, y, w, h, full and D.EXTRA.success or D.EXTRA.info)
    local cy = y + pad
    b:text(x + pad, cy + 3, getText("IGUI_MQ_UI_Donate"), D.EXTRA.info)
    if full then b:textRight(x + w - pad, cy + 3, getText("IGUI_MQ_UI_DonateFull"), D.EXTRA.success) end
    cy = cy + D.chipH() + 6
    b:fitText(x + pad, cy, line, inner, "text", UIFont.Medium)
    cy = cy + mh + 6
    if not full then
        b:bar(x + pad, cy, inner, 8, target > 0 and total / target or 0, D.EXTRA.info)
        cy = cy + 16
        b:text(x + pad, cy, getText("IGUI_MQ_UI_Progress", D.num(total), D.num(target)), "textMuted")
        b:textRight(x + w - pad, cy, getText("IGUI_MQ_UI_DonateMine", D.num(d.mine or 0)), "textMuted")
        cy = cy + lh + 6
    end
    for _, l in ipairs(noteLines) do
        b:text(x + pad, cy, l, "textMuted")
        cy = cy + lh + 2
    end
    local room = inner
    if btn ~= nil then
        btn:setX(x + w - pad - btn.width)
        btn:setY(cy + math.floor((footH - btn.height) / 2))
        room = inner - btn.width - 8
    end
    if foot ~= "" then b:fitText(x + pad, cy + math.floor((footH - lh) / 2), foot, room, "textMuted") end
    return y + h + GAP
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    if s == nil then
        y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Weekly"))
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    y = P.goal(b, page, x, y, w, s)
    y = P.donate(b, page, x, y, w, s)
    local chips = {}
    if tonumber(s.weekResetAt) then
        chips[1] = { getText("IGUI_MQ_UI_WeekReset", D.duration(D.left(s.weekResetAt))), "textMuted" }
    end
    y = b:header(x, y + 4, x + w, getText("IGUI_MQ_UI_Weekly"), chips)
    local week = type(s.week) == "table" and s.week or {}
    local n = 0
    for i, q in ipairs(type(week.quests) == "table" and week.quests or {}) do
        if type(q) == "table" and q.state ~= "expired" then
            n = n + 1
            y = Q.PageDaily.questCard(b, page, x, y, w, q, { key = "w" .. i, pin = "w" .. i })
        end
    end
    if n == 0 then y = b:para(x, y, getText("IGUI_MQ_UI_NoQuests"), w, "textMuted") + GAP end
    D.finish(page, y)
end

P.spec = {
    id = "weekly", label = "IGUI_MQ_UI_NavWeekly", icon = "clipboardCheck", group = "main", order = 20, ticking = true,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageWeekly.layout(page) end,
}
W.register(P.spec)
