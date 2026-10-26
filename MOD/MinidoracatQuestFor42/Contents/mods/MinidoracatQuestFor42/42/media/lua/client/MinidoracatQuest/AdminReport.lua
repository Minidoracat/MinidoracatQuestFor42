-- MinidoracatQuest/AdminReport.lua: the admin "report" tab (report.get / report.export, ARCHITECTURE.md 6.5).
-- Usage (players, new accounts, daily completion, per-day bars), points (issued by kind, coins, unspent, top 10%
-- share) and achievements (players at each tier). Totals only; per-template quest rows stay on the balance tab.

require "MinidoracatQuest/AdminPanel"

local MQ = MinidoracatQuest
local A = MQ.Admin

local ROMAN = { "I", "II", "III", "IV", "V" }
-- Points kinds grouped the way the legend reads (Contract.POINT_KINDS; anything else is "other")
local KIND_GROUP = { quest = "daily", shared = "daily", week = "weekly", achv = "achv", goal = "goal" }
local GROUPS = { "daily", "weekly", "achv", "goal", "other" }

local function pct(rate)
    if type(rate) ~= "number" then return "-" end
    return math.floor(rate * 100 + 0.5) .. "%"
end

local function load(P, pg)
    pg.days = pg.days or 7
    A.send(P, "report.get", { days = pg.days }, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function onDays(P, b)
    local pg = P.pages.report
    if pg.days == b.days then return end
    pg.days, pg.data, pg.err = b.days, nil, nil
    load(P, pg)
    A.layout(P)
end

local function onExport(P)
    local pg = P.pages.report
    A.send(P, "report.export", {}, function(res)
        if res.ok then pg.saved = tostring(res.path) else A.fail(P, res) end
        A.layout(P)
    end)
end

-- ===== per-day bars: players with activity (reportActive) beside players who finished a daily quest (reportDone) =====

local Bars

local function dayLabel(day, first, last)
    if last then return getText("IGUI_MQ_Admin_Today") end
    local m, d = tonumber(string.sub(day, 6, 7)), tonumber(string.sub(day, 9, 10))
    if first then return tostring(m) .. "/" .. tostring(d) end
    return tostring(d)
end

local function barsClass()
    if Bars then return Bars end
    Bars = ISUIElement:derive("MinidoracatQuestReportBars")
    function Bars:render()
        local rows, colors, fh = self.rows, self.theme.colors, self.fh
        local n = #rows
        if n == 0 then return end
        local on, done, muted = colors.reportActive, colors.reportDone, colors.textMuted
        local chartH = self.height - 2 * fh - 6
        local max = 1
        for i = 1, n do max = math.max(max, rows[i].active or 0, rows[i].dPlayers or 0) end
        local slot = self.width / n
        local bw = math.max(1, math.floor(slot / 2) - 2)
        local stride = n > 10 and 5 or 1
        for i = 1, n do
            local r = rows[i]
            local x = math.floor((i - 1) * slot + (slot - 2 * bw - 1) / 2)
            local ha = math.floor(chartH * (r.active or 0) / max)
            local hd = math.floor(chartH * (r.dPlayers or 0) / max)
            self:drawRect(x, chartH - ha, bw, ha, on.a or 1, on.r, on.g, on.b)
            self:drawRect(x + bw + 1, chartH - hd, bw, hd, done.a or 1, done.r, done.g, done.b)
            -- 7 days: every day; 30 days: every 5th from today, not next to the first or last label
            if i == 1 or i == n or ((n - i) % stride == 0 and (stride == 1 or (i > 2 and i < n - 1))) then
                self:drawText(dayLabel(r.day, i == 1, i == n), math.floor((i - 1) * slot), chartH + 2,
                    muted.r, muted.g, muted.b, muted.a or 1, UIFont.Small)
            end
        end
        -- legend: the colours carry no meaning alone
        local ly, x = chartH + fh + 4, 0
        for _, it in ipairs(self.legend) do
            self:drawRect(x, ly + math.floor((fh - 8) / 2), 8, 8, it.c.a or 1, it.c.r, it.c.g, it.c.b)
            self:drawText(it.text, x + 12, ly, colors.text.r, colors.text.g, colors.text.b, colors.text.a or 1, UIFont.Small)
            x = x + 12 + A.textW(it.text) + 3 * A.GAP
        end
    end
    return Bars
end

local function bars(P, F, rows)
    local cls = barsClass()
    local colors = P.theme.colors
    local e = F:get("bars", function()
        local b = cls:new(0, 0, 1, 1)
        b:initialise()
        b:setWantMouseEvents(false)
        b.theme, b.fh = P.theme, A.fontH()
        return b
    end)
    e.rows = rows
    e.legend = { { c = colors.reportActive, text = getText("IGUI_MQ_Admin_ReportLegendActive") },
        { c = colors.reportDone, text = getText("IGUI_MQ_Admin_ReportLegendDone") } }
    e:setX(A.PAD)
    e:setY(F.y)
    e:setWidth(F.width - 2 * A.PAD)
    e:setHeight(80 + 2 * e.fh + 6)
    F.y = F.y + e.height + A.GAP
end

-- big numbers in equal columns, the caption under each; it[3] = the colour token of the bars a number belongs to
local function kpis(F, items)
    local colW = math.floor((F.width - 2 * A.PAD) / #items)
    local h = 0
    for i, it in ipairs(items) do
        local x = A.PAD + (i - 1) * colW
        local v = F:label("kv" .. i, it[1], it[3] or "text", UIFont.Medium)
        local c = F:label("kc" .. i, it[2], "textMuted", nil, colW - A.GAP)
        v:setX(x)
        v:setY(F.y)
        c:setX(x)
        c:setY(F.y + v.height)
        h = math.max(h, v.height + c.height)
    end
    F.y = F.y + h + A.GAP
end

local function layoutAchv(P, F, data)
    local s = data.snap or {}
    local active = s.active or 0
    F:head("ha", getText("IGUI_MQ_Admin_ReportAchvHead"))
    F:text("an", getText("IGUI_MQ_Admin_ReportAchvNote", data.days, A.num(active),
        A.num(active > 0 and math.floor((s.tierSum or 0) / active + 0.5) or 0), A.num(s.tierSum or 0)), "textMuted")
    local L = F:list("al")
    local colW = math.max(A.textW("0,000"), A.textW("III")) + 2 * A.GAP
    local nameW = math.max(60, F.width - 2 * A.PAD - #ROMAN * colW)
    local head = { { text = getText("IGUI_MQ_Admin_ColAch"), x = A.PAD } }
    for k, t in ipairs(ROMAN) do head[#head + 1] = { text = t, x = A.PAD + nameW + k * colW, right = true, token = "tier" .. k } end
    F:listHead(head, "ah")
    local none, hidden, i = {}, 0, 0
    for _, r in ipairs(data.achv or {}) do
        local c = type(r.c) == "table" and r.c or {}
        if (c[1] or 0) == 0 then
            if r.hidden then hidden = hidden + 1 else none[#none + 1] = A.achName(P, tostring(r.id)) end
        else
            i = i + 1
            local cells = { { text = A.achName(P, tostring(r.id)), x = A.PAD, w = nameW - A.GAP } }
            for k = 1, #ROMAN do
                cells[#cells + 1] = { text = c[k] and A.num(c[k]) or "-", x = A.PAD + nameW + k * colW, right = true }
            end
            F:item()
            F:cells("ar" .. i, cells)
        end
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_ReportAchvEmpty"))
    local n = #none + hidden
    if n > 0 then
        -- hidden achievements count toward N but are never named
        local names = table.concat(none, getText("IGUI_MQ_UI_ListSep"))
        local text
        if hidden == 0 then text = getText("IGUI_MQ_Admin_ReportNone", A.num(n), names)
        elseif #none == 0 then text = getText("IGUI_MQ_Admin_ReportNoneAllHidden", A.num(n))
        else text = getText("IGUI_MQ_Admin_ReportNoneHidden", A.num(n), names, A.num(hidden)) end
        F:text("anone", text, "textMuted")
    end
end

local function layoutReport(P, pg, F)
    local days = pg.days or 7
    local chips = {}
    for i, d in ipairs({ 7, 30 }) do
        local b = F:button("d" .. i, getText("IGUI_MQ_Admin_ReportDays", d), onDays, "chip")
        b.days = d
        b:setActive(days == d)
        chips[i] = b
    end
    chips[#chips + 1] = F:button("exp", getText("IGUI_MQ_Admin_ReportExport"), onExport)
    F:row(chips)
    local data = pg.data
    if data == nil then
        F:text("ld", pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
        return
    end
    local D = MQ.Draw
    F:text("note", getText("IGUI_MQ_Admin_ReportNote", D and D.clock and D.clock(data.at or 0) or A.time(data.at)), "textMuted")
    if pg.saved then F:text("saved", getText("IGUI_MQ_Admin_ReportSaved", "Zomboid/Lua/" .. pg.saved), "textMuted") end
    local rows, sum, s = data.rows or {}, data.sum or {}, data.snap or {}
    local today = rows[#rows] or {}

    F:head("hu", getText("IGUI_MQ_Admin_ReportUsageHead"))
    kpis(F, {
        { A.num(today.active or 0), getText("IGUI_MQ_Admin_ReportToday"), "reportActive" },
        { A.num(s.active or 0), getText("IGUI_MQ_Admin_ReportActive", data.days), "reportActive" },
        { A.num(sum.fresh or 0), getText("IGUI_MQ_Admin_ReportFresh") },
        { pct(sum.dRate), getText("IGUI_MQ_Admin_ReportDailyRate"), "reportDone" },
    })
    bars(P, F, rows)
    F:text("wk", getText("IGUI_MQ_Admin_ReportWeekLine", pct(sum.wRate), A.num(sum.swaps or 0), A.num(s.streak7 or 0)), "text")

    F:head("hp", getText("IGUI_MQ_Admin_ReportPtsHead"))
    local total = sum.pts or 0
    F:text("pi", getText("IGUI_MQ_Admin_ReportIssued", data.days, A.num(total)), "text")
    local by = {}
    for kind, n in pairs(type(sum.ptsBy) == "table" and sum.ptsBy or {}) do
        local g = KIND_GROUP[kind] or "other"
        by[g] = (by[g] or 0) + n
    end
    local parts = {}
    for _, g in ipairs(GROUPS) do
        if (by[g] or 0) > 0 then
            parts[#parts + 1] = getText("IGUI_MQ_Admin_ReportShare", getText("IGUI_MQ_Admin_ReportKind_" .. g), A.num(by[g]),
                pct(by[g] / total))
        end
    end
    if #parts > 0 then F:text("pk", table.concat(parts, getText("IGUI_MQ_UI_ListSep")), "textMuted") end
    F:text("pe", getText("IGUI_MQ_Admin_ReportEcon", A.num(sum.coins or 0), A.num(s.exPlayers or 0), A.num(s.unspent or 0),
        pct(s.top10)), "text")
    F:gap()
    layoutAchv(P, F, data)
end

A.pages.report = { layout = layoutReport, load = load }
