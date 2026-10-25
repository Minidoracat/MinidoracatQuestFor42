-- MinidoracatQuest/AdminPages.lua: admin tabs other than achievements and history (spec 9.4, 11.2-11.4, 13.5-13.8).
-- basic (the guided first page: difficulty, season, rewards, exchange, newcomer quests and notices), quests (the
-- players-see-the-list switch, daily and weekly pools by theme with whole-theme buttons, shared goal, streak,
-- newbie, timed events), season (length preview/apply, review, rewards), exchange, players (account view, revoke,
-- hide, anomalies, per-minute limits), balance, towns. Config edits go through the draft (AdminPanel);
-- season/events/revoke/hide use their own ops (ARCHITECTURE.md 6.2), and the sections holding them say so
-- (IGUI_MQ_Admin_ImmediateNote).

require "MinidoracatQuest/AdminPanel"

local MQ = MinidoracatQuest
local A = MQ.Admin
local AM = MQ.AdminModel

local THEMES = { "combat", "build", "craft", "cook", "tailor", "farm", "animal", "fishtrap", "forage", "mech", "explore" }
local form, formRow = A.form, A.formRow

local function summary(P, text)
    P.draftSummary = P.draftSummary and (P.draftSummary .. "; " .. text) or text
end

local function textOf(t)
    t = string.gsub(tostring(t or ""), "^%s+", "")
    return (string.gsub(t, "%s+$", ""))
end

-- "all" reads "All quests" everywhere in the admin (theme filter, event theme); theme names come from Draw, like on the player pages
local function themeLabel(id)
    return id == "all" and getText("IGUI_MQ_Admin_ThemeAll") or MQ.Draw.themeName(id)
end

-- ===== shared loads: Basic shows both; Quests lists the events from ex.status =====

local function loadSeason(P)
    local pg = P.pages.season
    A.send(P, "season.review", {}, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function loadExchange(P)
    local pg = P.pages.exchange
    A.send(P, "ex.status", {}, function(res)
        pg.data, pg.err = res.ok and res or nil, (not res.ok) and res or nil
        A.layout(P)
    end)
end

local function loadingText(P, F, key, pg)
    F:text(key, pg.err and A.codeText(P, pg.err) or getText("IGUI_MQ_Admin_Loading"), pg.err and "errorText" or "textMuted")
end

-- warn: unknown | disabled | cap_zero | over_cap (Systems ex.status, one at a time); nil = nothing to warn
local function exWarn(d)
    local w = d and d.warn
    if w == "unknown" or w == "disabled" or w == "cap_zero" or w == "over_cap" then return w end
    return nil
end

-- ===== basic: steps 1-5 on one page; each step edits the same paths as its own tab =====

local function step(F, key, n, text) F:head(key, getText("IGUI_MQ_Admin_Step", n, text)) end

local function onToSeason(P) A.select(P, "season") end

-- number fields two per line: the first column keeps the tab's label width so it lines up with the other steps,
-- the second gets its own; Flow:row wraps the second pair onto the next line when the window is too narrow
local function formPairs(P, pg, F, rows, lw)
    local second = {}
    for i = 2, #rows, 2 do second[#second + 1] = rows[i][1] end
    local lw2 = A.labelWidth(second)
    for i = 1, #rows, 2 do
        local line = {}
        for j = i, math.min(i + 1, #rows) do
            local path, range = rows[j][1], rows[j][2]
            local w = j == i and lw or lw2
            if j > i then
                local s = F:label("sp:" .. path, "", nil, nil, 2 * A.GAP)
                s:setWidth(2 * A.GAP)
                line[#line + 1] = s
            end
            local l = F:label("l:" .. path, A.fLabel(path), nil, nil, w - A.GAP)
            l:setWidth(w)
            line[#line + 1] = l
            line[#line + 1] = A.numField(P, pg, path, path, nil, range)
        end
        F:row(line)
    end
end

local function layoutBasic(P, pg, F)
    local lw = A.labelWidth({ "rewards.top1", "rewards.top3", "rewards.top10", "rewards.participation", "exchange.enabled",
        "exchange.rate", "exchange.perDay", "newbie.enabled", "broadcast.enabled", "broadcast.minTier" })
    F:text("n", getText("IGUI_MQ_Admin_BasicNote"), "textMuted")

    -- 1. difficulty: its own preview with the estimate (the confirm view), like it was on the achievements tab
    step(F, "s1", 1, getText("IGUI_MQ_Admin_F_difficulty_preset"))
    A.AchvPage.difficultyRow(P, F)
    F:text("s1n", getText("IGUI_MQ_Admin_DiffNote"), "textMuted")

    -- 2. season: shown only; the length has the 24-hour rule and its preview on the season tab
    step(F, "s2", 2, getText("IGUI_MQ_Admin_Tab_season"))
    local sd = P.pages.season.data
    if sd then
        F:row({ F:label("s2l", getText("IGUI_MQ_Admin_BasicSeason", A.num(sd.lengthDays or 0),
            A.time(type(sd.endMs) == "number" and sd.endMs - 60000 or nil))),
            F:button("s2b", getText("IGUI_MQ_Admin_ToSeason"), onToSeason) })
    else
        loadingText(P, F, "s2l", P.pages.season)
    end

    step(F, "s3", 3, getText("IGUI_MQ_Admin_RewardsHead"))
    formPairs(P, pg, F, { { "rewards.top1", "pts" }, { "rewards.top3", "pts" }, { "rewards.top10", "pts" },
        { "rewards.participation", "pts" } }, lw)

    -- 4. exchange: without the economy mod this step only says so
    step(F, "s4", 4, getText("IGUI_MQ_Admin_ExHead"))
    local xd = P.pages.exchange.data
    if xd and xd.ecAvailable == false then
        F:text("s4x", getText("IGUI_MQ_Admin_NoEconomy"), "textMuted")
    else
        form(P, pg, F, { { "exchange.enabled", "bool" }, { "exchange.rate", "rate" }, { "exchange.perDay", "perDay" } }, lw)
        local warn = exWarn(xd)
        if warn then F:text("s4w", getText("IGUI_MQ_Admin_Warn_" .. warn .. "_Body", A.num(xd.ecCap or 0)), "warning") end
    end

    step(F, "s5", 5, getText("IGUI_MQ_Admin_StepNotice"))
    form(P, pg, F, { { "newbie.enabled", "bool" }, { "broadcast.enabled", "bool" }, { "broadcast.minTier", "minTier" } }, lw)
end

A.pages.basic = { layout = layoutBasic, load = function(P) loadSeason(P); loadExchange(P) end }

-- ===== quests =====

-- templates of one pool in theme order; theme = "all" or one theme id
local function templates(kind, theme)
    local out = {}
    for _, th in ipairs(THEMES) do
        if theme == "all" or th == theme then
            for _, tpl in ipairs(MQ.Catalog[kind] or {}) do if tpl.theme == th then out[#out + 1] = tpl end end
        end
    end
    return out
end

local function poolName(tpl) return A.questName(tpl.tid) .. (tpl.rare and (" " .. getText("IGUI_MQ_Admin_Rare")) or "") end

-- one pool: on, name, target min - max, points. Under "all" a theme line opens each group; the name column is as
-- wide as the longest name of the whole pool, so picking a theme does not move the fields
local function pool(P, pg, F, kind, theme)
    local numW = math.max(60, A.textW("1,000,000") + 20)
    local ptsW = math.max(50, A.textW("10000") + 20)
    local onW, dashW = 44, A.textW("-")
    local names = {}
    -- measured with the "(changed)" mark, so a row that gets a drafted value does not move the fields
    for i, tpl in ipairs(MQ.Catalog[kind] or {}) do names[i] = getText("IGUI_MQ_Admin_Changed", poolName(tpl)) end
    local nameW = A.colW(names, math.max(80, F.width - 2 * A.PAD - onW - 2 * numW - dashW - ptsW - 5 * A.GAP))
    local xName = A.PAD + onW + A.GAP
    local xTarget = xName + nameW + A.GAP
    F:cells(kind .. ":hd", {
        { text = getText("IGUI_MQ_Admin_ColOn"), x = A.PAD, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColQuest"), x = xName, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColTarget"), x = xTarget, token = "textMuted" },
        { text = getText("IGUI_MQ_Admin_ColPts"), x = xTarget + 2 * numW + dashW + 3 * A.GAP, token = "textMuted" },
    })
    local by = P.S.draft.by
    local last
    for _, tpl in ipairs(templates(kind, theme)) do
        if theme == "all" and tpl.theme ~= last then
            last = tpl.theme
            F:gap()
            F:text(kind .. ":th:" .. last, MQ.Draw.themeName(last), "text")
        end
        local base = kind .. ".pool." .. tpl.tid
        local on = A.boolField(P, pg, base .. ".enabled", "", base .. ".enabled")
        on:setWidth(onW)
        -- a long name wraps inside its column (a long DE name used to drop under the fields and read as the next
        -- row's, quest-ui-de-1023g); a row with a drafted value says so in its name, in a colour other than the
        -- gold of controls
        local pend = by[base .. ".enabled"] ~= nil or by[base .. ".target"] ~= nil or by[base .. ".pts"] ~= nil
        local name = F:label("n:" .. base, pend and getText("IGUI_MQ_Admin_Changed", poolName(tpl)) or poolName(tpl),
            pend and "info" or nil, nil, nameW - A.GAP)
        name:setWidth(nameW)
        local a = A.numField(P, pg, base .. ".target.1", base .. ".target", { 1 }, "target", numW)
        local dash = F:label("d:" .. base, "-", "textMuted")
        local b = A.numField(P, pg, base .. ".target.2", base .. ".target", { 2 }, "target", numW)
        local p = A.numField(P, pg, base .. ".pts", base .. ".pts", nil, "pts", ptsW)
        F:row({ on, name, a, dash, b, p })
    end
end

local function themeOptions()
    local C = MQ.Catalog
    local nd, nw = {}, {}
    for _, t in ipairs(C.daily or {}) do nd[t.theme] = (nd[t.theme] or 0) + 1 end
    for _, t in ipairs(C.weekly or {}) do nw[t.theme] = (nw[t.theme] or 0) + 1 end
    local opts = { { id = "all", label = getText("IGUI_MQ_Admin_ThemeCount", themeLabel("all"), #(C.daily or {}),
        #(C.weekly or {})) } }
    for _, th in ipairs(THEMES) do
        opts[#opts + 1] = { id = th, label = getText("IGUI_MQ_Admin_ThemeCount", MQ.Draw.themeName(th), nd[th] or 0, nw[th] or 0) }
    end
    return opts
end

-- the rows of other themes hide: their typed values go into the draft first (A.collect skips hidden fields)
local function onTheme(P, id, dd)
    local pg = P.pages.quests
    if not A.fold(P) then
        if dd then dd:setSelected(pg.theme, true) end
        return
    end
    pg.theme = id
    A.layout(P)
end

-- whole theme, daily and weekly: enabled on/off, or targets x mult on each template's step; into the draft.
-- The bar says what was done; a second x1.25 scales the drafted targets again, and the message gives the total
local function onThemeBatch(P, b)
    local pg = P.pages.quests
    if not A.fold(P) then return end
    local by = P.S.draft.by
    local n, drafted = 0, false
    for _, kind in ipairs({ "daily", "weekly" }) do
        for _, tpl in ipairs(templates(kind, pg.theme)) do
            local base = kind .. ".pool." .. tpl.tid
            if b.on ~= nil then
                if AM.get(P.S, base .. ".enabled") ~= b.on then
                    AM.draftSet(P.S.draft, base .. ".enabled", b.on)
                    n = n + 1
                end
            else
                drafted = drafted or by[base .. ".target"] ~= nil
                local t = AM.scaleTarget(AM.get(P.S, base .. ".target") or tpl.target, b.mult, tpl.step)
                if t then
                    AM.draftSet(P.S.draft, base .. ".target", t)
                    n = n + 1
                end
            end
        end
    end
    if n == 0 then return A.say(P, getText("IGUI_MQ_Admin_NoChanges"), "textMuted") end
    local th = MQ.Draw.themeName(pg.theme)
    local s
    if b.on == true then
        s = getText("IGUI_MQ_Admin_SumThemeOn", th, n)
    elseif b.on == false then
        s = getText("IGUI_MQ_Admin_SumThemeOff", th, n)
    else
        s = getText("IGUI_MQ_Admin_SumThemeMult", th, n, AM.num(b.mult))
    end
    summary(P, s)
    if b.mult then
        pg.mults = pg.mults or {}
        local total = (drafted and pg.mults[pg.theme] or 1) * b.mult
        pg.mults[pg.theme] = total
        if total ~= b.mult then s = getText("IGUI_MQ_Admin_MultTotal", s, AM.num(total)) end
    end
    pg.version = pg.version + 1   -- the fields show the draft now
    A.say(P, getText("IGUI_MQ_Admin_InDraftWhat", s), "textMuted")
    A.layout(P)
end

local function onEventRemove(P, b)
    local e = b.entry
    A.ask(P, { title = getText("IGUI_MQ_Admin_EventRemoveConfirm"), danger = true, confirm = getText("IGUI_MQ_Admin_EventRemoveConfirm"),
        text = getText("IGUI_MQ_Admin_EventRemoveAsk", tostring(e.name)), onOk = function()
            A.send(P, "event.remove", { id = e.id }, function(res)
                if not res.ok then return A.fail(P, res) end
                loadExchange(P)
            end)
        end })
end

local function onEventAdd(P)
    local pool = P.pages.quests.flow.pool
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
        loadExchange(P)
    end)
end

local function dateField(P, F, key)
    local UI = P.UI
    if UI.CAPABILITIES.datePicker and UI.DateField then
        return F:get(key, function() return UI.DateField.new({ x = 0, y = 0, theme = P.theme, target = P }) end)
    end
    return F:field(key, A.textW("0000-00-00") + 30, "YYYY-MM-DD", 10)
end

-- timed events multiply quest points, so they sit with the quests; event.add / event.remove take effect at once
local function layoutEvents(P, pg, F)
    local xp = P.pages.exchange
    F:head("he", getText("IGUI_MQ_Admin_EventsHead"))
    F:text("hen", getText("IGUI_MQ_Admin_EventsNote") .. " " .. getText("IGUI_MQ_Admin_ImmediateNote") .. " " .. A.tzNote(),
        "textMuted")
    if xp.data == nil then loadingText(P, F, "eld", xp) end
    local events = xp.data and xp.data.events or {}
    local live = 0
    for i, e in ipairs(events) do
        if (e.endMs or 0) > getTimestampMs() then live = live + 1 end
        local rm = F:button("er" .. i, getText("IGUI_MQ_Admin_EventRemove"), onEventRemove, "danger")
        rm.entry = e
        -- the remove button ends its own event's line (under it, it sat nearer the next event)
        F:row({ F:label("e" .. i, getText("IGUI_MQ_Admin_EventRow", tostring(e.name), themeLabel(e.theme), AM.num(e.mult or 1),
            A.time(e.startMs) .. " - " .. A.time(e.endMs)), "text", nil, F.width - 2 * A.PAD - rm.width - A.GAP), rm })
    end
    if xp.data and #events == 0 then F:text("en", getText("IGUI_MQ_Admin_EventsNone"), "textMuted") end
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
    -- apart from the form above and the draft buttons in the bar: this one sends at once
    F:gap()
    F:row({ add })
    if live >= 3 then F:text("ev:max", getText("IGUI_MQ_Admin_EventsMax"), "warning") end
end

-- jump buttons to the sections under the two long pools; each scrolls its heading to the top. ScrollPanel:scrollTo
-- only reveals (a heading below the view would land on the bottom edge); the native setYScroll clamps the range
local JUMPS = { { "hg", "IGUI_MQ_Admin_GoalHead" }, { "hs", "IGUI_MQ_Admin_StreakHead" }, { "hn", "IGUI_MQ_Admin_NewbieHead" },
    { "he", "IGUI_MQ_Admin_EventsHead" } }

-- b.jump, not b.target: ISButton sends a click to self.target (the panel), so a section key stored there made every
-- jump index a string (playtest 1025b, "attempted index: quests of non-table")
local function onJump(P, b)
    local pg = P.pages.quests
    local head = pg.flow.pool[b.jump]
    if head and head:isVisible() then pg.sp:setYScroll(-(head:getY() - A.PAD)) end
end

local function layoutQuests(P, pg, F)
    pg.theme = pg.theme or "all"
    local lw = A.labelWidth({ "daily.sharedPts", "daily.swapsPerDay", "weekly.count", "goal.enabled", "goal.pts", "goal.growth",
        "streak.need", "streak.gracePerWeek", "newbie.enabled", "newbie.pts" })
    -- whether players see this list (enabled templates, ranges, points) at the bottom of their Settings page
    form(P, pg, F, { { "quests.playerList", "bool" } })
    F:row({ F:label("thl", getText("IGUI_MQ_Admin_ThemeFilter")), F:dropdown("th", themeOptions(), pg.theme, onTheme) })
    F:text("dpn", getText("IGUI_MQ_Admin_PoolHelp"), "textMuted")
    -- the whole-theme buttons sit with the filter that picks the theme
    if pg.theme ~= "all" then
        local n = #templates("daily", pg.theme) + #templates("weekly", pg.theme)
        local row = { F:label("tbl", getText("IGUI_MQ_Admin_ThemeBatch", MQ.Draw.themeName(pg.theme), A.num(n))) }
        for k, on in ipairs({ true, false }) do
            local b = F:button("tb:o" .. k, getText(on and "IGUI_MQ_Admin_AllOn" or "IGUI_MQ_Admin_AllOff"), onThemeBatch)
            b.on, b.mult = on, nil
            row[#row + 1] = b
        end
        for k, m in ipairs({ 0.8, 1.25 }) do
            local b = F:button("tb:m" .. k, getText("IGUI_MQ_Admin_TargetMult", AM.num(m)), onThemeBatch)
            b.on, b.mult = nil, m
            row[#row + 1] = b
        end
        F:row(row)
    end
    local jumps = { F:label("jl", getText("IGUI_MQ_Admin_JumpTo"), "textMuted") }
    for _, j in ipairs(JUMPS) do
        local b = F:button("j:" .. j[1], getText(j[2]), onJump)
        b.jump = j[1]
        jumps[#jumps + 1] = b
    end
    F:row(jumps)
    F:head("hd", getText("IGUI_MQ_Admin_DailyHead"))
    -- daily.pts / rarePts / weekly.pts stay in config.json for pack quests: every built-in template has its own points
    form(P, pg, F, { { "daily.sharedPts", "pts" }, { "daily.swapsPerDay", "swaps" } }, lw)
    pool(P, pg, F, "daily", pg.theme)
    F:head("hw", getText("IGUI_MQ_Admin_WeeklyHead"))
    form(P, pg, F, { { "weekly.count", "weeklyCount" } }, lw)
    pool(P, pg, F, "weekly", pg.theme)

    F:head("hg", getText("IGUI_MQ_Admin_GoalHead"))
    form(P, pg, F, { { "goal.enabled", "bool" }, { "goal.pts", "pts" }, { "goal.growth", "growth" } }, lw)
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

    F:head("hs", getText("IGUI_MQ_Admin_StreakHead"))
    form(P, pg, F, { { "streak.need", "need" }, { "streak.gracePerWeek", "grace" } }, lw)
    local ms = AM.get(P.S, "streak.milestones") or {}
    for i = 1, #ms do
        local l = F:label("ms:" .. i, getText("IGUI_MQ_Admin_Milestone", i))
        F:row({ l,
            A.numField(P, pg, "streak.milestones." .. i .. ".days", "streak.milestones", { i, "days" }, "msDays"),
            F:label("ms:d" .. i, getText("IGUI_MQ_Admin_Days"), "textMuted"),
            A.numField(P, pg, "streak.milestones." .. i .. ".pts", "streak.milestones", { i, "pts" }, "pts"),
            F:label("ms:p" .. i, getText("IGUI_MQ_Admin_PtsUnit"), "textMuted") })
    end

    F:head("hn", getText("IGUI_MQ_Admin_NewbieHead"))
    form(P, pg, F, { { "newbie.enabled", "bool" }, { "newbie.pts", "pts" } }, lw)
    layoutEvents(P, pg, F)
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

A.pages.quests = { layout = layoutQuests, check = checkQuests, load = function(P) loadExchange(P) end }

-- ===== season =====

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
        loadSeason(P)
    end)
end

local function onSeasonCancel(P)
    P.pages.season.preview = nil
    A.layout(P)
end

-- a button, not a switch: excluding asks for a reason; "Include again" sends right away
local function onExclude(P, b)
    local r = b.entry
    local function send(reason)
        A.send(P, "season.exclude", { user = r.user, on = not r.excluded, reason = reason }, function(res)
            if not res.ok then return A.fail(P, res) end
            loadSeason(P)
        end)
    end
    if r.excluded then return send(nil) end
    A.ask(P, { title = getText("IGUI_MQ_Admin_Exclude"), danger = true, required = true, confirm = getText("IGUI_MQ_Admin_Exclude"),
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
                loadSeason(P)
            end)
        end })
end

-- review list: rank, name (as wide as the longest), points, anomalies; the button at the right end
local function layoutReview(P, F, d)
    local rows = d.rows or {}
    local rankW = A.textW("#000") + A.GAP
    local ptsW = A.textW("1,000,000") + A.GAP
    local names, anomW = {}, 0
    for i, r in ipairs(rows) do
        names[i] = r.excluded and getText("IGUI_MQ_Admin_ExcludedTag", tostring(r.user)) or tostring(r.user)
        if (r.anomalies or 0) > 0 then anomW = math.max(anomW, A.textW(A.count("IGUI_MQ_Admin_Anomalies", r.anomalies)) + A.GAP) end
    end
    local btnW = math.max(A.textW(getText("IGUI_MQ_Admin_Exclude")), A.textW(getText("IGUI_MQ_Admin_Unexclude"))) + 24
    local userW = A.colW(names, math.max(80, F.width - 2 * A.PAD - rankW - ptsW - anomW - btnW - 2 * A.GAP))
    for i, r in ipairs(rows) do
        local cells = {
            { text = tostring(r.rank or i), x = A.PAD + rankW - A.GAP, right = true, token = "textMuted" },
            { text = names[i], x = A.PAD + rankW, w = userW, token = r.excluded and "textMuted" or "text" },
            { text = A.num(r.pts or 0), x = A.PAD + rankW + userW + ptsW, right = true },
        }
        if (r.anomalies or 0) > 0 then
            cells[#cells + 1] = { text = A.count("IGUI_MQ_Admin_Anomalies", r.anomalies), x = A.PAD + rankW + userW + ptsW + A.GAP,
                token = "warning" }
        end
        local row = F:cells("rr" .. i, cells, i % 2 == 0)
        local b = F:button("rx" .. i, getText(r.excluded and "IGUI_MQ_Admin_Unexclude" or "IGUI_MQ_Admin_Exclude"), onExclude,
            (not r.excluded) and "danger" or nil)
        b.entry = r
        b:setX(F.width - A.PAD - b.width)
        b:setY(row:getY() + math.floor((row.height - b.height) / 2))
        if b.height > row.height then
            row:setHeight(b.height)
            F.y = row:getY() + row.height
            b:setY(row:getY())
        end
        if r.excluded and r.reason then F:text("rw" .. i, getText("IGUI_MQ_Admin_ExcludedWhy", tostring(r.reason)), "textMuted") end
    end
end

local function layoutSeason(P, pg, F)
    local d = pg.data
    F:head("h", getText("IGUI_MQ_Admin_SeasonHead"))
    if d == nil then
        loadingText(P, F, "ld", pg)
    else
        F:text("imm", getText("IGUI_MQ_Admin_ImmediateNote"), "textMuted")
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
            layoutReview(P, F, d)
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

A.pages.season = { layout = layoutSeason, load = function(P) loadSeason(P) end }

-- ===== exchange =====

local function layoutExchange(P, pg, F)
    local d = pg.data
    F:head("h", getText("IGUI_MQ_Admin_ExHead"))
    if d == nil then
        loadingText(P, F, "ld", pg)
    else
        if d.ecAvailable == false then F:text("noec", getText("IGUI_MQ_Admin_NoEconomy"), "warning") end
        local warn = exWarn(d)
        if warn then
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
end

A.pages.exchange = { layout = layoutExchange, load = function(P) loadExchange(P) end }

-- ===== players: account view, revoke, hide, anomalies, per-minute limits =====

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
        pg.sp:setYScroll(0)   -- the account is drawn at the top; "View" on a row far down would look like nothing happened
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
    A.ask(P, { title = getText("IGUI_MQ_Admin_Revoke"), danger = true, required = true, confirm = getText("IGUI_MQ_Admin_RevokeWhat"),
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
        confirm = getText(on and "IGUI_MQ_Admin_HideNow" or "IGUI_MQ_Admin_UnhideNow"),
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
    F:text("a:n", getText("IGUI_MQ_Admin_ImmediateNote") .. " " .. getText("IGUI_MQ_Admin_DangerNote"), "textMuted")
    F:gap(2 * A.GAP)
end

-- the stats with a per-minute limit that players drive (account-level ones are fed by the mod itself)
local function ceilStats()
    local C, out = MQ.Catalog, {}
    for _, id in ipairs(C.statOrder or {}) do
        local s = C.stats[id]
        if s and s.ceil and not s.account then out[#out + 1] = s end
    end
    return out
end

-- closing hides the fields: their typed values go into the draft first (A.collect skips hidden fields)
local function onCeilToggle(P)
    local pg = P.pages.players
    if pg.ceilOpen and not A.fold(P) then return end
    pg.ceilOpen = not pg.ceilOpen
    A.layout(P)
end

-- ceilings: one field per stat, the default being Catalog.stats[id].ceil; only changed stats get a key
local function layoutCeilings(P, pg, F)
    local stats = ceilStats()
    F:row({ F:button("ceil", pg.ceilOpen and getText("IGUI_MQ_Admin_Collapse") or getText("IGUI_MQ_Admin_CeilOpen", A.num(#stats)),
        onCeilToggle) })
    if not pg.ceilOpen then return end
    F:text("ceiln", getText("IGUI_MQ_Admin_CeilNote"), "textMuted")
    local labels = {}
    for i, s in ipairs(stats) do labels[i] = A.statName(s.id) end
    local lw = A.colW(labels, 260)
    local w = math.max(60, A.textW("1,000,000") + 20)
    for i, s in ipairs(stats) do
        formRow(F, "ceil:" .. s.id, labels[i], lw, { A.numField(P, pg, "ceil:" .. s.id, "ceilings", { s.id }, "ceil", w, s.ceil) })
    end
end

local function layoutPlayers(P, pg, F)
    F:row({ F:label("lk", getText("IGUI_MQ_Admin_Lookup")), F:field("lookup", 160, nil, 64),
        F:button("lkb", getText("IGUI_MQ_Admin_View"), onLookup) })
    if pg.acct then layoutAccount(P, pg, F) end

    F:head("h", getText("IGUI_MQ_Admin_AnomHead"))
    F:text("an", getText("IGUI_MQ_Admin_AnomNote"), "textMuted")
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
        loadingText(P, F, "ld", pg)
    else
        if #pg.rows == 0 then F:text("none", getText("IGUI_MQ_Admin_AnomNone"), "textMuted") end
        local timeW = A.timeW()
        local users = {}
        for i, r in ipairs(pg.rows) do users[i] = r.user end
        local userW = A.colW(users, math.floor(F.width / 3))
        for i, r in ipairs(pg.rows) do
            local b = F:button("v" .. i, getText("IGUI_MQ_Admin_View"), onView)
            b.user = r.user
            -- the description goes on its own (wrapped) line under the row when it does not fit beside the name
            -- the entry keeps only the dropped part (Audit.over); that minute's total is the limit plus it
            local desc = getText("IGUI_MQ_Admin_AnomRow", A.statName(r.stat), A.num((r.ceil or 0) + (r.n or 0)), A.num(r.ceil or 0))
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
    F:gap()
    layoutCeilings(P, pg, F)
end

A.pages.players = { layout = layoutPlayers, load = loadAnom }

-- ===== balance =====

-- reply: rows { tid, given, done, swaps?, rate?, medianMin?, suggest? } and minGiven (both from the server: rate =
-- done / (given - swaps), nil when nothing is left; a server before swaps sends neither swaps nor minGiven)
local function loadBalance(P, pg)
    A.send(P, "balance.report", {}, function(res)
        pg.rows, pg.err = res.ok and (res.rows or {}) or nil, (not res.ok) and res or nil
        pg.minGiven = res.minGiven
        A.layout(P)
    end)
end

local function suggestOk(s) return type(s) == "table" and type(s.path) == "string" and AM.targetOk(s.value) end

-- the range in effect now (draft, server or default) beside the suggested one
local function suggestText(P, s)
    if type(s) ~= "table" or type(s.value) ~= "table" then return "-" end
    local cur = type(s.path) == "string" and AM.get(P.S, s.path)
    if type(cur) ~= "table" then cur = {} end
    return getText(s.kind == "hard" and "IGUI_MQ_Admin_TooHard" or "IGUI_MQ_Admin_TooEasy", A.num(cur[1] or 0),
        A.num(cur[2] or cur[1] or 0), A.num(s.value[1] or 0), A.num(s.value[2] or 0))
end

local function onApplySuggest(P)
    local changes = {}
    for _, r in ipairs(P.pages.balance.rows or {}) do
        local s = r.suggest
        if suggestOk(s) then changes[#changes + 1] = { op = "set", path = s.path, value = { s.value[1], s.value[2] } } end
    end
    if #changes == 0 then return A.say(P, getText("IGUI_MQ_Admin_NoSuggest"), "textMuted") end
    A.previewChanges(P, changes, getText("IGUI_MQ_Admin_SumSuggest", #changes))
end

local function layoutBalance(P, pg, F)
    local minGiven = pg.minGiven or 10
    F:head("h", getText("IGUI_MQ_Admin_BalanceHead"))
    F:text("n", getText("IGUI_MQ_Admin_BalanceNote", A.num(minGiven)), "textMuted")
    if pg.rows == nil then return loadingText(P, F, "ld", pg) end
    -- daily and weekly rows share one list: the weekly ones say so ("Craft N items" is both)
    local weekly = {}
    for _, t in ipairs(MQ.Catalog.weekly or {}) do weekly[t.tid] = true end
    -- right-aligned number columns: given, completion, median time, swapped away; quest names get the rest and a
    -- suggestion goes on its own line under its row (EN names were cut to "Kill N zombies with f..." beside a
    -- suggestion column, quest-ui-en-1023c)
    local cols = { { "IGUI_MQ_Admin_ColGiven", "10,000" }, { "IGUI_MQ_Admin_ColRate", "100%" },
        { "IGUI_MQ_Admin_ColMedian", getText("IGUI_MQ_Admin_Minutes", "0,000") }, { "IGUI_MQ_Admin_ColSwaps", "10,000" } }
    local x = F.width - A.PAD
    for i = #cols, 1, -1 do
        cols[i].x = x
        x = x - math.max(A.textW(getText(cols[i][1])), A.textW(cols[i][2])) - 2 * A.GAP
    end
    local nameW = math.max(60, x - A.PAD)
    local head = { { text = getText("IGUI_MQ_Admin_ColQuest"), x = A.PAD, token = "textMuted" } }
    for _, c in ipairs(cols) do head[#head + 1] = { text = getText(c[1]), x = c.x, right = true, token = "textMuted" } end
    F:cells("hd", head)
    local n = 0
    for i, r in ipairs(pg.rows) do
        local tid = tostring(r.tid)
        local name = A.questName(tid)
        if weekly[tid] then name = getText("IGUI_MQ_Admin_WeeklyTag", name) end
        local given, swaps = tonumber(r.given) or 0, tonumber(r.swaps) or 0
        local rate = r.rate
        if type(rate) ~= "number" and swaps == 0 and given > 0 then rate = (tonumber(r.done) or 0) / given end
        local vals = { A.num(given), type(rate) == "number" and (math.floor(rate * 100 + 0.5) .. "%") or "-",
            type(r.medianMin) == "number" and getText("IGUI_MQ_Admin_Minutes", A.num(math.floor(r.medianMin + 0.5))) or "-",
            A.num(swaps) }
        local cells = { { text = name, x = A.PAD, w = nameW - A.GAP } }
        for k, c in ipairs(cols) do cells[#cells + 1] = { text = vals[k], x = c.x, right = true } end
        F:cells("r" .. i, cells, i % 2 == 0)
        if r.suggest then
            if suggestOk(r.suggest) then n = n + 1 end
            F:text("sg" .. i, suggestText(P, r.suggest), "warning")
        elseif given - swaps < minGiven then
            -- why a 0% row has no suggestion
            F:text("sg" .. i, getText("IGUI_MQ_Admin_FewSamples", A.num(minGiven)), "textMuted")
        end
    end
    if #pg.rows == 0 then F:text("none", getText("IGUI_MQ_Admin_BalanceNone"), "textMuted") end
    local b = F:button("apply", A.count("IGUI_MQ_Admin_ApplySuggest", n), onApplySuggest)
    b:setEnabled(n > 0)
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
        local rm = F:button("cr" .. i, getText("IGUI_MQ_Admin_Remove"), onTownRemove)
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
        local here = F:button("t:here" .. i, getText("IGUI_MQ_Admin_UseHere"), onHere)
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
