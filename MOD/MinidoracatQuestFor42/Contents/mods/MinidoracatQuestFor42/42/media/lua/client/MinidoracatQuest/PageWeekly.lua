-- MinidoracatQuest/PageWeekly.lua: weekly page (spec 4): the server-wide weekly goal card (gold frame, 8 px bar,
--   my contribution, payout rule) on top, then the header with the Monday reset countdown and the three weekly
--   quest cards (same card as daily, no swap).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"
require "MinidoracatQuest/PageDaily"

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
