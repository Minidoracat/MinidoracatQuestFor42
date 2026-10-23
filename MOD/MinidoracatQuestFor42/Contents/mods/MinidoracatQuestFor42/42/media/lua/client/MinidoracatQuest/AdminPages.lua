-- MinidoracatQuest/AdminPages.lua: admin tabs other than achievements and history (spec 9.4, 11.2-11.4, 13.5-13.8).
-- quests (daily/weekly pools, shared goal, streak, newbie, broadcast), season (length preview/apply, review,
-- rewards), exchange & events, players (anomalies, account view, revoke, hide), balance, towns.
-- Config edits go through the draft (AdminPanel); season/events/revoke/hide use their own ops (ARCHITECTURE.md 6.2).

require "MinidoracatQuest/AdminPanel"

local MQ = MinidoracatQuest
local A = MQ.Admin
local AM = MQ.AdminModel

local THEMES = { "combat", "build", "craft", "cook", "tailor", "farm", "animal", "fishtrap", "forage", "mech", "explore" }

local function fLabel(path) return getTextOrNull("IGUI_MQ_Admin_F_" .. string.gsub(path, "%.", "_")) or path end

local function summary(P, text)
    P.draftSummary = P.draftSummary and (P.draftSummary .. "; " .. text) or text
end

-- label column + controls; a label longer than the (capped) column wraps inside it
local function formRow(F, key, text, labelW, ctrls)
    local l = F:label("l:" .. key, text, nil, nil, labelW - A.GAP)
    l:setWidth(labelW)
    local row = { l }
    for _, c in ipairs(ctrls) do row[#row + 1] = c end
    F:row(row)
end

local function labelWidth(paths)
    local w = 0
    for _, p in ipairs(paths) do w = math.max(w, A.textW(fLabel(p))) end
    return math.min(w + A.GAP, 260)
end

-- simple form: { { path, range | "bool" } }
local function form(P, pg, F, rows)
    local paths = {}
    for i, r in ipairs(rows) do paths[i] = r[1] end
    local lw = labelWidth(paths)
    for _, r in ipairs(rows) do
        local ctrl
        if r[2] == "bool" then
            ctrl = A.boolField(P, pg, r[1], "", r[1])
        else
            ctrl = A.numField(P, pg, r[1], r[1], nil, r[2])
        end
        formRow(F, r[1], fLabel(r[1]), lw, { ctrl })
    end
end

local function textOf(t)
    t = string.gsub(tostring(t or ""), "^%s+", "")
    return (string.gsub(t, "%s+$", ""))
end

-- ===== quests =====

local function pool(P, pg, F, kind, list)
    local numW = math.max(60, A.textW("1,000,000") + 20)
    local ptsW = math.max(50, A.textW("10000") + 20)
    F:cells(kind .. ":hd", {
        { text = getText("IGUI_MQ_Admin_ColOn"), x = A.PAD, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColTarget"), x = A.PAD + 44 + A.GAP, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColPts"), x = A.PAD + 44 + 2 * numW + 4 * A.GAP + A.textW("-"), token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColQuest"), x = A.PAD + 44 + 2 * numW + ptsW + 5 * A.GAP + A.textW("-"), token = "textMuted" },
    })
    for _, tpl in ipairs(list or {}) do
        local base = kind .. ".pool." .. tpl.tid
        local on = A.boolField(P, pg, base .. ".enabled", "", base .. ".enabled")
        on:setWidth(44)
        local a = A.numField(P, pg, base .. ".target.1", base .. ".target", { 1 }, "target", numW)
        local dash = F:label("d:" .. base, "-", "textMuted")
        local b = A.numField(P, pg, base .. ".target.2", base .. ".target", { 2 }, "target", numW)
        local p = A.numField(P, pg, base .. ".pts", base .. ".pts", nil, "pts", ptsW)
        -- the name wraps inside what the row has left (a long DE name used to drop under the fields and read as
        -- the next row's, quest-ui-de-1023g)
        local nameW = math.max(80, F.width - 2 * A.PAD - 44 - 2 * numW - A.textW("-") - ptsW - 5 * A.GAP)
        local name = F:label("n:" .. base, A.questName(tpl.tid) .. (tpl.rare and (" " .. getText("IGUI_MQ_Admin_Rare")) or ""),
            nil, nil, nameW)
        F:row({ on, a, dash, b, p, name })
    end
end

local function layoutQuests(P, pg, F)
    local C = MQ.Catalog
    F:head("hd", getText("IGUI_MQ_Admin_DailyHead"))
    form(P, pg, F, { { "daily.pts", "pts" }, { "daily.rarePts", "pts" }, { "daily.sharedPts", "pts" },
        { "daily.swapsPerDay", "swaps" } })
    F:text("dpn", getText("IGUI_MQ_Admin_PoolHelp"), "textMuted")
    pool(P, pg, F, "daily", C.daily)
    F:gap()
    F:head("hw", getText("IGUI_MQ_Admin_WeeklyHead"))
    form(P, pg, F, { { "weekly.count", "weeklyCount" }, { "weekly.pts", "pts" } })
    pool(P, pg, F, "weekly", C.weekly)
    F:gap()

    F:head("hg", getText("IGUI_MQ_Admin_GoalHead"))
    form(P, pg, F, { { "goal.enabled", "bool" }, { "goal.pts", "pts" }, { "goal.growth", "growth" } })
    local numW = math.max(60, A.textW("1,000,000") + 20)
    local statW = 0
    local rotation = AM.get(P.S, "goal.rotation") or {}
    for _, stat in ipairs(rotation) do statW = math.max(statW, A.textW(A.statName(stat))) end
    F:cells("gl:hd", {
        { text = getText("IGUI_MQ_Admin_ColStat"), x = A.PAD, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColMin"), x = A.PAD + statW + A.GAP, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColMax"), x = A.PAD + statW + numW + 2 * A.GAP, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColContrib"), x = A.PAD + statW + 2 * numW + 3 * A.GAP, token = "textMuted" },
    })
    for _, stat in ipairs(rotation) do
        local l = F:label("gl:" .. stat, A.statName(stat))
        l:setWidth(statW)
        F:row({ l,
            A.numField(P, pg, "goal.limits." .. stat .. ".min", "goal.limits", { stat, "min" }, "target", numW),
            A.numField(P, pg, "goal.limits." .. stat .. ".max", "goal.limits", { stat, "max" }, "target", numW),
            A.numField(P, pg, "goal.limits." .. stat .. ".minContrib", "goal.limits", { stat, "minContrib" }, "target", numW) })
    end
    F:gap()

    F:head("hs", getText("IGUI_MQ_Admin_StreakHead"))
    form(P, pg, F, { { "streak.need", "need" }, { "streak.gracePerWeek", "grace" } })
    local ms = AM.get(P.S, "streak.milestones") or {}
    for i = 1, #ms do
        local l = F:label("ms:" .. i, getText("IGUI_MQ_Admin_Milestone", i))
        F:row({ l,
            A.numField(P, pg, "streak.milestones." .. i .. ".days", "streak.milestones", { i, "days" }, "msDays"),
            F:label("ms:d" .. i, getText("IGUI_MQ_Admin_Days"), "textMuted"),
            A.numField(P, pg, "streak.milestones." .. i .. ".pts", "streak.milestones", { i, "pts" }, "pts"),
            F:label("ms:p" .. i, getText("IGUI_MQ_Admin_PtsUnit"), "textMuted") })
    end
    F:gap()

    F:head("hn", getText("IGUI_MQ_Admin_NewbieHead"))
    form(P, pg, F, { { "newbie.enabled", "bool" }, { "newbie.pts", "pts" } })
    F:gap()
    F:head("hb", getText("IGUI_MQ_Admin_BroadcastHead"))
    form(P, pg, F, { { "broadcast.enabled", "bool" }, { "broadcast.minTier", "minTier" }, { "broadcast.perMinute", "perMinute" } })
end

-- milestone days strictly increasing
local function checkQuests(_, _, values)
    local days = {}
    for _, v in ipairs(values) do
        local part = v.field.part
        if v.field.path == "streak.milestones" and part[2] == "days" then days[part[1]] = v.value end
    end
    for i = 2, #days do
        if days[i] <= days[i - 1] then return getText("IGUI_MQ_Admin_ErrMilestones") end
    end
    return nil
end

A.pages.quests = { layout = layoutQuests, check = checkQuests }

-- ===== season =====

local function loadSeason(P, pg)
    A.send(P, "season.review", {}, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function onSeasonPreview(P)
    local pg = P.pages.season
    local tf = pg.flow.pool["len"]
    local days, key, lo, hi = AM.check(tf:getText(), "days")
    A.markError(P, tf, days == nil and getText(key, AM.num(lo), AM.num(hi)) or nil)
    if days == nil then return end
    A.send(P, "season.preview", { days = days }, function(res)
        if not res.ok then return A.fail(P, res) end
        pg.preview = { days = days, endMs = res.endMs, nextStartMs = res.nextStartMs }
        A.layout(P)
    end)
end

local function onSeasonApply(P)
    local pg = P.pages.season
    local pv = pg.preview
    if pv == nil then return end
    A.send(P, "season.apply", { days = pv.days }, function(res)
        if not res.ok then return A.fail(P, res) end
        pg.preview = nil
        A.say(P, getText("IGUI_MQ_Admin_SeasonApplied", pv.days, A.time((res.endMs or pv.endMs) - 60000)), "success")
        loadSeason(P, pg)
    end)
end

local function onSeasonCancel(P)
    P.pages.season.preview = nil
    A.layout(P)
end

local function onExclude(P, value, box)
    local pg = P.pages.season
    local r = box.entry
    box:setChecked(r.excluded == true, true)   -- the server decides; reload shows the result
    local function send(reason)
        A.send(P, "season.exclude", { user = r.user, on = value, reason = reason }, function(res)
            if not res.ok then return A.fail(P, res) end
            loadSeason(P, pg)
        end)
    end
    if not value then return send(nil) end
    A.ask(P, { title = getText("IGUI_MQ_Admin_Exclude"), danger = true, required = true,
        text = getText("IGUI_MQ_Admin_ExcludeAsk", r.user, A.num(r.pts or 0)),
        input = { placeholder = getText("IGUI_MQ_Admin_Reason") }, onOk = send })
end

local function onSeasonConfirm(P)
    local pg = P.pages.season
    local d = pg.data
    local n, ex = 0, 0
    for _, r in ipairs(d.rows or {}) do
        n = n + 1
        if r.excluded then ex = ex + 1 end
    end
    A.ask(P, { title = getText("IGUI_MQ_Admin_PayConfirm"), danger = true,
        text = getText("IGUI_MQ_Admin_PayAsk", tostring(d.frozenNo or d.no or "?"), n - ex, ex), confirm = getText("IGUI_MQ_Admin_PayNow"),
        onOk = function()
            A.send(P, "season.confirm", {}, function(res)
                if not res.ok then return A.fail(P, res) end
                A.say(P, getText("IGUI_MQ_Admin_Paid"), "success")
                loadSeason(P, pg)
            end)
        end })
end

local function layoutSeason(P, pg, F)
    local d = pg.data
    F:head("h", getText("IGUI_MQ_Admin_SeasonHead"))
    if d == nil then
        F:text("ld", pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
    else
        F:text("cur", getText("IGUI_MQ_Admin_SeasonNow", d.no or "?", A.time(d.startMs)), "text")
        F:text("end", getText("IGUI_MQ_Admin_SeasonEnd", A.time(type(d.endMs) == "number" and d.endMs - 60000 or nil)), "text")
        local len = F:field("len", math.max(60, A.textW("180") + 30))
        if pg.lenAt ~= d then
            pg.lenAt = d
            len:setText(tostring(d.lengthDays or ""))
        end
        len:setTooltip(getText("IGUI_MQ_Admin_RangeTip", "7", "180"))
        local prev = F:button("pv", getText("IGUI_MQ_Admin_PreviewLength"), onSeasonPreview)
        formRow(F, "len", getText("IGUI_MQ_Admin_SeasonLength"), A.textW(getText("IGUI_MQ_Admin_SeasonLength")) + A.GAP,
            { len, F:label("lu", getText("IGUI_MQ_Admin_Days"), "textMuted"), prev })
        local pv = pg.preview
        if pv then
            F:text("pvb", getText("IGUI_MQ_Admin_SeasonPreviewBody", A.time((pv.endMs or 0) - 60000), (d.no or 0) + 1,
                A.time(pv.nextStartMs)), "text", nil, "info", getText("IGUI_MQ_Admin_SeasonPreviewHead", pv.days))
            local apply = F:button("pva", getText("IGUI_MQ_Admin_Apply"), onSeasonApply, "primary")
            apply:setEnabled(not A.busy(P))
            F:row({ apply, F:button("pvc", getText("UI_Cancel"), onSeasonCancel, "ghost") })
        end
        F:text("lenn", getText("IGUI_MQ_Admin_SeasonLengthNote") .. " " .. A.tzNote(), "textMuted")
        F:gap()

        -- review list: the frozen season (frozenNo) while no/startMs/endMs already describe the new one (C30)
        F:head("rh", getText("IGUI_MQ_Admin_ReviewHead", tostring(d.frozenNo or d.no or "?")))
        if d.state ~= "review" then
            F:text("rn", getText("IGUI_MQ_Admin_ReviewNone"), "textMuted")
        else
            F:text("rf", getText("IGUI_MQ_Admin_FrozenAt", A.time(d.frozenAt)), "info")
            local rankW = A.textW("#000") + A.GAP
            local ptsW = A.textW("1,000,000") + A.GAP
            for i, r in ipairs(d.rows or {}) do
                local cells = {
                    { text = tostring(r.rank or i), x = A.PAD + 44 + rankW - A.GAP, right = true, token = "textMuted" },
                    { text = tostring(r.user), x = A.PAD + 44 + rankW, w = 160 },
                    { text = A.num(r.pts or 0), x = A.PAD + 44 + rankW + 160 + ptsW, right = true },
                }
                if (r.anomalies or 0) > 0 then
                    cells[#cells + 1] = { text = A.count("IGUI_MQ_Admin_Anomalies", r.anomalies), x = A.PAD + 44 + rankW + 160 + ptsW + A.GAP,
                        token = "warning" }
                end
                local row = F:cells("rr" .. i, cells, i % 2 == 0)
                local box = F:check("rx" .. i, "", onExclude, r.excluded == true)
                box.entry = r
                box:setWidth(40)
                box:setX(A.PAD)
                box:setY(row:getY() + math.floor((row.height - box.height) / 2))
                if r.excluded and r.reason then F:text("rw" .. i, getText("IGUI_MQ_Admin_ExcludedWhy", tostring(r.reason)), "textMuted") end
            end
            F:text("rc", getText("IGUI_MQ_Admin_ReviewNote"), "textMuted")
            F:row({ F:button("pay", getText("IGUI_MQ_Admin_PayConfirm"), onSeasonConfirm, "danger") })
        end
        F:gap()
    end

    F:head("wh", getText("IGUI_MQ_Admin_RewardsHead"))
    form(P, pg, F, { { "rewards.top1", "pts" }, { "rewards.top3", "pts" }, { "rewards.top10", "pts" },
        { "rewards.participation", "pts" }, { "rewards.participationMin", "pts" }, { "rewards.firstTitles", "bool" } })
    F:text("wn", getText("IGUI_MQ_Admin_RewardsNote"), "textMuted")
end

A.pages.season = { layout = layoutSeason, load = loadSeason }

-- ===== exchange & events =====

local function loadExchange(P, pg)
    A.send(P, "ex.status", {}, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function onEventRemove(P, b)
    local e = b.entry
    A.ask(P, { title = getText("IGUI_MQ_Admin_EventRemove"), danger = true,
        text = getText("IGUI_MQ_Admin_EventRemoveAsk", tostring(e.name)), onOk = function()
            A.send(P, "event.remove", { id = e.id }, function(res)
                if not res.ok then return A.fail(P, res) end
                loadExchange(P, P.pages.exchange)
            end)
        end })
end

local function themeLabel(id)
    return id == "all" and getText("IGUI_MQ_Admin_ThemeAll") or getText("IGUI_MQ_Theme_" .. tostring(id))
end

local function onEventAdd(P)
    local pg = P.pages.exchange
    local pool = pg.flow.pool
    local name = textOf(pool["ev:name"]:getText())
    local mult, key, lo, hi = AM.check(pool["ev:mult"]:getText(), "eventMult")
    local s = AM.dayStartMs(pool["ev:start"]:getText())
    local e = AM.dayStartMs(pool["ev:end"]:getText())
    A.markError(P, pool["ev:mult"], mult == nil and getText(key, AM.num(lo), AM.num(hi)) or nil)
    A.markError(P, pool["ev:start"], s == nil and getText("IGUI_MQ_Admin_ErrDate") or nil)
    A.markError(P, pool["ev:end"], (e == nil or (s and e < s)) and getText("IGUI_MQ_Admin_ErrDate") or nil)
    if name == "" then return A.say(P, getText("IGUI_MQ_Admin_ErrName"), "errorText") end
    if mult == nil or s == nil or e == nil or e < s then return A.say(P, getText("IGUI_MQ_Admin_FixErrors"), "errorText") end
    e = e + 86400000   -- end day inclusive
    if e <= getTimestampMs() then return A.say(P, getText("IGUI_MQ_Admin_ErrPast"), "errorText") end
    A.send(P, "event.add", { name = string.sub(name, 1, 64), theme = pool["ev:theme"]:getSelected() or "all", mult = mult,
        startMs = s, endMs = e }, function(res)
        if not res.ok then return A.fail(P, res) end
        pool["ev:name"]:setText("")
        A.say(P, getText("IGUI_MQ_Admin_EventAdded"), "success")
        loadExchange(P, pg)
    end)
end

local function dateField(P, F, key)
    local UI = P.UI
    if UI.CAPABILITIES.datePicker and UI.DateField then
        return F:get(key, function() return UI.DateField.new({ x = 0, y = 0, theme = P.theme, target = P }) end)
    end
    return F:field(key, A.textW("0000-00-00") + 30, "YYYY-MM-DD", 10)
end

local function layoutExchange(P, pg, F)
    local d = pg.data
    F:head("h", getText("IGUI_MQ_Admin_ExHead"))
    if d == nil then
        F:text("ld", pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
    else
        if d.ecAvailable == false then F:text("noec", getText("IGUI_MQ_Admin_NoEconomy"), "warning") end
        -- warn: unknown | disabled | cap_zero | over_cap (Systems ex.status, one at a time); nil = nothing to warn
        local warn = d.warn
        if warn == "unknown" or warn == "disabled" or warn == "cap_zero" or warn == "over_cap" then
            F:text("warn", getText("IGUI_MQ_Admin_Warn_" .. warn .. "_Body", A.num(d.ecCap or 0)), "text", nil, "warning",
                getText("IGUI_MQ_Admin_Warn_" .. warn .. "_Head"))
        end
        local over = warn == "over_cap"
        local rows = {
            { getText("IGUI_MQ_Admin_ExEnabled"), getText(d.enabled and "IGUI_MQ_Admin_On" or "IGUI_MQ_Admin_Off"),
                d.enabled and "success" or "textMuted" },
            { getText("IGUI_MQ_Admin_ExRate"), getText("IGUI_MQ_Admin_ExRateValue", A.num(d.rate or 0)) },
            { getText("IGUI_MQ_Admin_ExPerDay"), getText("IGUI_MQ_Admin_PtsN", A.num(d.perDay or 0)) },
            { getText("IGUI_MQ_Admin_ExToday"), getText("IGUI_MQ_Admin_CoinsN", A.num(d.todayCoins or 0)) },
            { getText("IGUI_MQ_Admin_ExEstimate"), getText("IGUI_MQ_Admin_CoinsN", A.num(d.estimate or 0)), over and "warning" or nil },
        }
        if type(d.ecCap) == "number" then
            rows[#rows + 1] = { getText("IGUI_MQ_Admin_ExCap"), getText("IGUI_MQ_Admin_CoinsN", A.num(d.ecCap)) }
        end
        if type(d.ecUsed) == "number" then
            rows[#rows + 1] = { getText("IGUI_MQ_Admin_ExEcUsed"), getText("IGUI_MQ_Admin_CoinsN", A.num(d.ecUsed)) }
        end
        local lw = 0
        for _, r in ipairs(rows) do lw = math.max(lw, A.textW(r[1])) end
        for i, r in ipairs(rows) do
            F:cells("s" .. i, { { text = r[1], x = A.PAD, token = "textMuted" }, { text = r[2], x = A.PAD + lw + 2 * A.GAP, token = r[3] } },
                i % 2 == 0)
        end
    end
    F:gap()
    F:head("hs", getText("IGUI_MQ_Admin_ExSettings"))
    form(P, pg, F, { { "exchange.enabled", "bool" }, { "exchange.rate", "rate" }, { "exchange.perDay", "perDay" },
        { "exchange.min", "exMin" } })
    F:gap()

    -- events
    F:head("he", getText("IGUI_MQ_Admin_EventsHead"))
    F:text("hen", getText("IGUI_MQ_Admin_EventsNote") .. " " .. A.tzNote(), "textMuted")
    local events = d and d.events or {}
    local live = 0
    for i, e in ipairs(events) do
        if (e.endMs or 0) > getTimestampMs() then live = live + 1 end
        F:text("e" .. i, getText("IGUI_MQ_Admin_EventRow", tostring(e.name), themeLabel(e.theme), AM.num(e.mult or 1),
            A.time(e.startMs) .. " - " .. A.time(e.endMs)), "text")
        local rm = F:button("er" .. i, getText("IGUI_MQ_Admin_EventRemove"), onEventRemove, "danger")
        rm.entry = e
        F:row({ rm })
    end
    if #events == 0 then F:text("en", getText("IGUI_MQ_Admin_EventsNone"), "textMuted") end
    local themes = { { id = "all", label = themeLabel("all") } }
    for _, t in ipairs(THEMES) do themes[#themes + 1] = { id = t, label = themeLabel(t) } end
    local lw = 0
    for _, k in ipairs({ "EvName", "EvTheme", "EvMult", "EvStart", "EvEnd" }) do lw = math.max(lw, A.textW(getText("IGUI_MQ_Admin_" .. k))) end
    lw = lw + A.GAP
    formRow(F, "ev:name", getText("IGUI_MQ_Admin_EvName"), lw, { F:field("ev:name", math.max(120, math.min(300, F.width - lw - 3 * A.PAD)), nil, 64) })
    formRow(F, "ev:theme", getText("IGUI_MQ_Admin_EvTheme"), lw,
        { F:dropdown("ev:theme", themes, pg.flow.pool["ev:theme"] and pg.flow.pool["ev:theme"]:getSelected() or "all", nil) })
    local mult = F:field("ev:mult", 60)
    if mult:getText() == "" then mult:setText("2") end
    mult:setTooltip(getText("IGUI_MQ_Admin_RangeTip", "1", "5"))
    formRow(F, "ev:mult", getText("IGUI_MQ_Admin_EvMult"), lw, { mult })
    formRow(F, "ev:start", getText("IGUI_MQ_Admin_EvStart"), lw, { dateField(P, F, "ev:start") })
    formRow(F, "ev:end", getText("IGUI_MQ_Admin_EvEnd"), lw, { dateField(P, F, "ev:end") })
    local add = F:button("ev:add", getText("IGUI_MQ_Admin_EventAdd"), onEventAdd, "primary")
    add:setEnabled(live < 3 and not A.busy(P))
    F:row({ add })
    if live >= 3 then F:text("ev:max", getText("IGUI_MQ_Admin_EventsMax"), "warning") end
end

A.pages.exchange = { layout = layoutExchange, load = loadExchange }

-- ===== players: anomalies, account view, revoke, hide =====

local function loadAnom(P, pg)
    pg.days = pg.days or 1
    A.send(P, "anom.list", { days = pg.days }, function(res)
        pg.rows, pg.err = res.ok and (res.rows or {}) or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function view(P, user)
    local pg = P.pages.players
    A.send(P, "acct.view", { user = user }, function(res)
        if not res.ok then
            pg.acct = nil
            A.fail(P, res)
            return A.layout(P)
        end
        res.user = res.user or user
        pg.acct, pg.revAch, pg.revTier = res, nil, nil
        A.layout(P)
    end)
end

local function onDays(P, b)
    local pg = P.pages.players
    pg.days = b.days
    loadAnom(P, pg)
end

local function onView(P, b) view(P, b.user) end

local function onLookup(P)
    local user = textOf(P.pages.players.flow.pool["lookup"]:getText())
    if user ~= "" then view(P, user) end
end

local function onRevAch(P, id)
    local pg = P.pages.players
    pg.revAch, pg.revTier = id, 0
    A.layout(P)
end

local function onRevTier(P, id) P.pages.players.revTier = id end

local function onRevoke(P)
    local pg = P.pages.players
    local acc, id = pg.acct, pg.revAch
    local cur = acc and acc.achv and tonumber(acc.achv[id]) or 0
    local to = pg.revTier or 0
    if id == nil or to >= cur then return end
    A.ask(P, { title = getText("IGUI_MQ_Admin_Revoke"), danger = true, required = true,
        text = getText("IGUI_MQ_Admin_RevokeAsk", acc.user, A.achName(P, id), cur - to, AM.roman(to)),
        input = { placeholder = getText("IGUI_MQ_Admin_Reason") }, onOk = function(reason)
            A.send(P, "achv.revoke", { user = acc.user, achId = id, tier = to, reason = reason }, function(res)
                if not res.ok then return A.fail(P, res) end
                A.say(P, getText("IGUI_MQ_Admin_Revoked"), "success")
                view(P, acc.user)
            end)
        end })
end

local function onHide(P)
    local acc = P.pages.players.acct
    local on = acc.hidden == nil
    A.ask(P, { title = getText(on and "IGUI_MQ_Admin_Hide" or "IGUI_MQ_Admin_Unhide"), danger = on, required = on,
        text = getText(on and "IGUI_MQ_Admin_HideAsk" or "IGUI_MQ_Admin_UnhideAsk", acc.user),
        input = { placeholder = getText("IGUI_MQ_Admin_Reason") }, onOk = function(reason)
            A.send(P, "board.hide", { user = acc.user, on = on, reason = reason ~= "" and reason or nil }, function(res)
                if not res.ok then return A.fail(P, res) end
                view(P, acc.user)
            end)
        end })
end

local function layoutAccount(P, pg, F)
    local acc = pg.acct
    F:head("a:h", getText("IGUI_MQ_Admin_AccountHead", acc.user))
    local pts = acc.points or {}
    F:text("a:p", getText("IGUI_MQ_Admin_AccountPts", A.num(pts.season or 0), A.num(pts.total or 0), A.num(pts.balance or 0)), "text")
    F:text("a:c", getText("IGUI_MQ_Admin_AccountAch", A.num(acc.achvCount or 0), A.num(acc.anomalies or 0)),
        (acc.anomalies or 0) > 0 and "warning" or "text")
    if acc.hidden then
        F:text("a:hid", getText("IGUI_MQ_Admin_AccountHidden", tostring(acc.hidden.reason or "-"), tostring(acc.hidden.actor or "-"),
            A.time(acc.hidden.at)), "warning")
    end
    -- revoke: achievement (unlocked ones) + tier to revoke down to
    local opts = {}
    for id, tier in pairs(acc.achv or {}) do
        if tonumber(tier) and tonumber(tier) > 0 then opts[#opts + 1] = { id = id, label = A.achName(P, id) .. " " .. AM.roman(tonumber(tier)) } end
    end
    MQ.Util.sort(opts, function(a, b) return a.label < b.label end)
    if #opts > 0 then
        if pg.revAch == nil or acc.achv[pg.revAch] == nil then pg.revAch, pg.revTier = opts[1].id, 0 end
        local cur = tonumber(acc.achv[pg.revAch]) or 0
        local tiers = {}
        for t = 0, cur - 1 do tiers[#tiers + 1] = { id = t, label = t == 0 and getText("IGUI_MQ_Admin_RevokeAll") or AM.roman(t) } end
        F:row({ F:label("a:rl", getText("IGUI_MQ_Admin_RevokeWhat")), F:dropdown("a:ra", opts, pg.revAch, onRevAch),
            F:label("a:rt", getText("IGUI_MQ_Admin_RevokeTo")), F:dropdown("a:rtier", tiers, pg.revTier or 0, onRevTier) })
    else
        F:text("a:none", getText("IGUI_MQ_Admin_AccountNoAch"), "textMuted")
    end
    local rv = F:button("a:revoke", getText("IGUI_MQ_Admin_Revoke"), onRevoke, "danger")
    rv:setEnabled(#opts > 0)
    F:row({ rv, F:button("a:hide", getText(acc.hidden and "IGUI_MQ_Admin_Unhide" or "IGUI_MQ_Admin_Hide"), onHide,
        acc.hidden and "normal" or "danger") })
    F:text("a:n", getText("IGUI_MQ_Admin_DangerNote"), "textMuted")
    F:gap(2 * A.GAP)
end

local function layoutPlayers(P, pg, F)
    F:row({ F:label("lk", getText("IGUI_MQ_Admin_Lookup")), F:field("lookup", 160, nil, 64),
        F:button("lkb", getText("IGUI_MQ_Admin_View"), onLookup) })
    if pg.acct then layoutAccount(P, pg, F) end

    F:head("h", getText("IGUI_MQ_Admin_AnomHead"))
    local chips = {}
    for i, days in ipairs({ 1, 7 }) do
        local b = F:button("d" .. i, getText(days == 1 and "IGUI_MQ_Admin_Today" or "IGUI_MQ_Admin_Days7"), onDays, "chip")
        b.days = days
        b:setActive((pg.days or 1) == days)
        chips[i] = b
    end
    F:row(chips)
    F:text("tz", A.tzNote(), "textMuted")
    if pg.rows == nil then
        F:text("ld", pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
        return
    end
    if #pg.rows == 0 then F:text("none", getText("IGUI_MQ_Admin_AnomNone"), "textMuted") end
    local timeW = A.timeW()
    local userW = 120
    for i, r in ipairs(pg.rows) do
        local b = F:button("v" .. i, getText("IGUI_MQ_Admin_View"), onView, "ghost")
        b.user = r.user
        -- the description goes on its own (wrapped) line under the row when it does not fit beside the name
        local desc = getText("IGUI_MQ_Admin_AnomRow", A.statName(r.stat), A.num(r.n or 0), A.num(r.ceil or 0))
        local descX = A.PAD + timeW + userW + A.GAP
        local fits = A.textW(desc) <= F.width - A.PAD - b.width - A.GAP - descX
        local cells = {
            { text = A.time(r.at), x = A.PAD, token = "textMuted" },
            { text = tostring(r.user), x = A.PAD + timeW, w = userW },
        }
        if fits then cells[3] = { text = desc, x = descX } end
        local row = F:cells("r" .. i, cells, i % 2 == 0)
        b:setX(F.width - A.PAD - b.width)
        b:setY(row:getY() + math.floor((row.height - b.height) / 2))
        if b.height > row.height then
            row:setHeight(b.height)
            F.y = row:getY() + row.height
            b:setY(row:getY())
        end
        if not fits then F:text("rd" .. i, desc, "text") end
    end
end

A.pages.players = { layout = layoutPlayers, load = loadAnom }

-- ===== balance =====

local function loadBalance(P, pg)
    A.send(P, "balance.report", {}, function(res)
        pg.rows, pg.err = res.ok and (res.rows or {}) or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function suggestText(s)
    if type(s) ~= "table" or type(s.value) ~= "table" then return "-" end
    return getText(s.kind == "hard" and "IGUI_MQ_Admin_TooHard" or "IGUI_MQ_Admin_TooEasy", A.num(s.value[1] or 0), A.num(s.value[2] or 0))
end

local function onApplySuggest(P)
    local changes = {}
    for _, r in ipairs(P.pages.balance.rows or {}) do
        local s = r.suggest
        if type(s) == "table" and type(s.path) == "string" and AM.targetOk(s.value) then
            changes[#changes + 1] = { op = "set", path = s.path, value = { s.value[1], s.value[2] } }
        end
    end
    if #changes == 0 then return A.say(P, getText("IGUI_MQ_Admin_NoSuggest"), "textMuted") end
    A.previewChanges(P, changes, getText("IGUI_MQ_Admin_SumSuggest", #changes))
end

local function layoutBalance(P, pg, F)
    F:head("h", getText("IGUI_MQ_Admin_BalanceHead"))
    F:text("n", getText("IGUI_MQ_Admin_BalanceNote"), "textMuted")
    if pg.rows == nil then
        F:text("ld", pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
        return
    end
    local rateW = math.max(A.textW(getText("IGUI_MQ_Admin_ColRate")), A.textW("100%")) + 2 * A.GAP
    local timeW = math.max(A.textW(getText("IGUI_MQ_Admin_ColMedian")), A.textW(getText("IGUI_MQ_Admin_Minutes", "000"))) + 2 * A.GAP
    -- quest names get the width; a suggestion goes on its own line under its row (EN names were cut to
    -- "Kill N zombies with f..." beside a suggestion column, quest-ui-en-1023c)
    local nameW = math.max(60, F.width - 2 * A.PAD - rateW - timeW)
    local x1 = A.PAD + nameW + rateW
    local x2 = x1 + timeW
    F:cells("hd", {
        { text = getText("IGUI_MQ_Admin_ColQuest"), x = A.PAD, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColRate"), x = x1, right = true, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColMedian"), x = x2, right = true, token = "textMuted" },
    })
    local any = false
    for i, r in ipairs(pg.rows) do
        any = any or r.suggest ~= nil
        F:cells("r" .. i, {
            { text = A.questName(tostring(r.tid)), x = A.PAD, w = nameW - A.GAP },
            { text = type(r.rate) == "number" and (math.floor(r.rate * 100 + 0.5) .. "%") or "-", x = x1, right = true },
            { text = type(r.medianMin) == "number" and getText("IGUI_MQ_Admin_Minutes", A.num(math.floor(r.medianMin + 0.5))) or "-",
                x = x2, right = true },
        }, i % 2 == 0)
        if r.suggest then F:text("sg" .. i, suggestText(r.suggest), "warning") end
    end
    if #pg.rows == 0 then F:text("none", getText("IGUI_MQ_Admin_BalanceNone"), "textMuted") end
    local b = F:button("apply", getText("IGUI_MQ_Admin_ApplySuggest"), onApplySuggest)
    b:setEnabled(any)
    F:row({ b })
end

A.pages.balance = { layout = layoutBalance, load = loadBalance }

-- ===== towns =====

local function onTownToggle(P, value, box)
    local dis = AM.copy(AM.get(P.S, "towns.disabled")) or {}
    dis[box.townId] = (not value) or nil
    AM.draftSet(P.S.draft, "towns.disabled", dis)
    summary(P, getText(value and "IGUI_MQ_Admin_SumTownOn" or "IGUI_MQ_Admin_SumTownOff", getText("IGUI_MQ_Town_" .. box.townId)))
    A.layout(P)
end

local function onTownRemove(P, b)
    local list = AM.copy(AM.get(P.S, "towns.custom")) or {}
    local out = {}
    for _, t in ipairs(list) do if t.id ~= b.townId then out[#out + 1] = t end end
    AM.draftSet(P.S.draft, "towns.custom", out)
    summary(P, getText("IGUI_MQ_Admin_SumTownDel", tostring(b.townName)))
    A.layout(P)
end

local function onHere(P, b)
    local pg = P.pages.towns
    A.send(P, "towns.here", {}, function(res)
        if not res.ok then return A.fail(P, res) end
        pg.here = res
        local pool = pg.flow.pool
        pool["t:x" .. b.corner]:setText(tostring(math.floor(res.x or 0)))
        pool["t:y" .. b.corner]:setText(tostring(math.floor(res.y or 0)))
        A.layout(P)
    end)
end

local function onTownAdd(P)
    local pg = P.pages.towns
    local pool = pg.flow.pool
    local name = textOf(pool["t:name"]:getText())
    local c, bad = {}, false
    for _, k in ipairs({ "x1", "y1", "x2", "y2" }) do
        local key = "t:" .. k
        local v, ek, lo, hi = AM.check(pool[key]:getText(), "coord")
        A.markError(P, pool[key], v == nil and getText(ek, AM.num(lo), AM.num(hi)) or nil)
        c[k], bad = v, bad or v == nil
    end
    if name == "" then return A.say(P, getText("IGUI_MQ_Admin_ErrName"), "errorText") end
    if bad then return A.say(P, getText("IGUI_MQ_Admin_FixErrors"), "errorText") end
    local list = AM.copy(AM.get(P.S, "towns.custom")) or {}
    list[#list + 1] = { id = AM.newId("t", getTimestampMs()), name = string.sub(name, 1, 64),
        rects = { AM.townRect(c.x1, c.y1, c.x2, c.y2) } }
    AM.draftSet(P.S.draft, "towns.custom", list)
    summary(P, getText("IGUI_MQ_Admin_SumTownAdd", name))
    for _, k in ipairs({ "t:name", "t:x1", "t:y1", "t:x2", "t:y2" }) do pool[k]:setText("") end
    A.say(P, getText("IGUI_MQ_Admin_InDraft"), "textMuted")
    A.layout(P)
end

local function rectText(r)
    if type(r) ~= "table" then return "-" end
    return "(" .. tostring(r.x1) .. ", " .. tostring(r.y1) .. ") - (" .. tostring(r.x2) .. ", " .. tostring(r.y2) .. ")"
end

local function layoutTowns(P, pg, F)
    local C = MQ.Catalog
    F:head("h", getText("IGUI_MQ_Admin_TownsHead"))
    F:text("n", getText("IGUI_MQ_Admin_TownsNote"), "textMuted")
    local dis = AM.get(P.S, "towns.disabled") or {}
    for i, t in ipairs(C.towns or {}) do
        local box = F:check("b" .. i, getText("IGUI_MQ_Town_" .. t.id), onTownToggle, dis[t.id] ~= true)
        box.townId = t.id
        F:row({ box, F:label("br" .. i, rectText(t.rects and t.rects[1]), "textMuted") })
    end
    F:gap()
    F:head("hc", getText("IGUI_MQ_Admin_CustomTowns"))
    local custom = AM.get(P.S, "towns.custom") or {}
    if #custom == 0 then F:text("cn", getText("IGUI_MQ_Admin_CustomTownsNone"), "textMuted") end
    for i, t in ipairs(custom) do
        local rm = F:button("cr" .. i, getText("IGUI_MQ_Admin_Remove"), onTownRemove, "ghost")
        rm.townId, rm.townName = t.id, t.name
        F:row({ F:label("cl" .. i, tostring(t.name)), F:label("cx" .. i, rectText(t.rects and t.rects[1]), "textMuted"), rm })
    end
    F:gap()
    F:head("ha", getText("IGUI_MQ_Admin_TownAdd"))
    local lw = A.textW(getText("IGUI_MQ_Admin_TownName"))
    for i = 1, 2 do lw = math.max(lw, A.textW(getText("IGUI_MQ_Admin_Corner", i))) end
    lw = lw + A.GAP
    formRow(F, "t:name", getText("IGUI_MQ_Admin_TownName"), lw, { F:field("t:name", 200, nil, 64) })
    local cw = A.textW("100000") + 24
    for i = 1, 2 do
        local here = F:button("t:here" .. i, getText("IGUI_MQ_Admin_UseHere"), onHere, "ghost")
        here.corner = i
        formRow(F, "t:c" .. i, getText("IGUI_MQ_Admin_Corner", i), lw,
            { F:field("t:x" .. i, cw, "x"), F:field("t:y" .. i, cw, "y"), here })
    end
    local h = pg.here
    if h then
        F:text("t:at", getText("IGUI_MQ_Admin_YouAre", tostring(h.x), tostring(h.y),
            h.town and getText("IGUI_MQ_Town_" .. h.town) or getText("IGUI_MQ_Admin_NoTown")), "textMuted")
    end
    F:row({ F:button("t:add", getText("IGUI_MQ_Admin_ToDraft"), onTownAdd, "primary") })
end

A.pages.towns = { layout = layoutTowns }
