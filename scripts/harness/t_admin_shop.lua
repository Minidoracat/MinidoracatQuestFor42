-- AdminUI, uses for points (plan points-sinks-1112 claim 5.2; contract temp/points-sinks/contract.md 1, 6, 8): the
-- exchange tab's uses section, the hordes tab's sponsored hordes and fund line, spent points on the report, point
-- titles on the Titles tab. Runs inside t_admin_ui.lua with its fakes and open panel (ctx).
return function(T, ctx)
    local Q, P, pool, press, answer, dialogs, replies = ctx.Q, ctx.P, ctx.pool, ctx.press, ctx.answer, ctx.dialogs, ctx.replies
    local A, AM, C = Q.Admin, Q.AdminModel, Q.Catalog
    local now = ctx.now
    local function shown(id, key) local el = pool(id)[key]; return el ~= nil and el:isVisible() end
    local function keyed(f)
        local gt = getText
        getText = function(key, ...)
            local s = key
            for i = 1, select("#", ...) do s = s .. "|" .. tostring((select(i, ...))) end
            return s
        end
        local ok, err = pcall(f)
        getText = gt
        if not ok then error(err, 0) end
    end
    local function default(path) return AM.get({ overrides = {}, defaults = C.DEFAULTS }, path) end

    -- every field: a new value reaches the draft on its own path (leaving the tab folds it in), typed back it leaves
    -- the draft; out of range (both ends) it is marked, the tab stays and nothing is drafted
    local function roundTrip(tab, away, rows)
        for _, r in ipairs(rows) do
            local path, range = r[1], r[2]
            A.select(P, tab)
            local function el() return pool(tab)["f:" .. path] end
            local function bounce() A.select(P, away); A.select(P, tab) end
            T.check(el() ~= nil and el():isVisible(), tab .. ": field shown for " .. path)
            if range == "bool" then
                local was = el():getChecked()
                T.check(was == (default(path) ~= false), path .. " starts at the default")
                el():setChecked(not was)
                bounce()
                local drafted = P.S.draft.by[path] == (not was) and el():getChecked() == (not was)
                el():setChecked(was)
                bounce()
                T.check(drafted and P.S.draft.by[path] == nil, path .. ": switched goes into the draft, switched back leaves it")
            elseif range ~= "pick" then
                local orig = el():getText()
                local lo, hi = AM.RANGE[range][1], AM.RANGE[range][2]
                T.check(orig == tostring(default(path)), path .. " shows the default " .. tostring(default(path)))
                local v = (tonumber(orig) or lo) < hi and (tonumber(orig) or lo) + 1 or hi - 1
                el():setText(tostring(v))
                bounce()
                local drafted = P.S.draft.by[path] == v and el():getText() == tostring(v)
                el():setText(orig)
                bounce()
                T.check(drafted and P.S.draft.by[path] == nil, path .. ": " .. v .. " goes into the draft, typed back leaves it")
                for _, bad in ipairs({ hi + 1, lo - 1 }) do
                    el():setText(tostring(bad))
                    A.select(P, away)
                    T.check(P.current == tab and el().invalid ~= nil and P.S.draft.by[path] == nil,
                        path .. ": " .. bad .. " is marked, the tab stays, nothing drafted")
                    el():setText(orig)
                end
                A.select(P, away)
                T.check(P.current == away and AM.draftCount(P.S.draft) == 0, path .. ": fixed, the tab can be left")
            end
        end
    end

    T.section("admin shop: uses for points on the exchange tab, one field per row (claim 5.2)")
    A.discard(P)
    A.select(P, "exchange")
    T.check(shown("exchange", "hu") and pool("exchange")["hu"].y > pool("exchange")["hs"].y and shown("exchange", "un"),
        "a Uses for points heading with its note under the exchange settings")
    local prevY, rowsOk = -1, true
    for _, r in ipairs(AM.USES) do
        local el = pool("exchange")["f:" .. r[1]]
        rowsOk = rowsOk and el ~= nil and el.y > prevY
        prevY = el and el.y or prevY
    end
    T.check(rowsOk, "every uses field on a row of its own, in the design's order")
    T.check(pool("exchange")["f:shop.swap.enabled"].opts.label == "IGUI_MQ_Admin_F_shop_swap_enabled"
        and pool("exchange")["l:shop.swap.enabled"] == nil, "a switch carries its label (says what On means)")
    T.check(pool("exchange")["l:shop.titles.list.spend_1"].lines[1] == "IGUI_MQ_Admin_ShopTitlePts",
        "a title price is labelled through the title name key")
    local wide = pool("exchange")["f:shop.titles.season"]
    T.check(wide.width >= A.textW(AM.num(AM.RANGE.titleSeason[2])) + A.FIELD_CHROME, "a price field fits 100,000 with the error mark")
    T.check(pool("basic")["f:shop.swap.pts"] == nil and pool("basic")["hu"] == nil, "Basic (five steps) gets nothing new")
    roundTrip("exchange", "season", AM.USES)

    T.section("admin shop: without the economy mod the uses section stays")
    local exReply = replies["ex.status"]
    replies["ex.status"] = function() return { enabled = false, rate = 1, perDay = 0, min = 1, ecAvailable = false, events = {} } end
    P.pages.exchange.loaded = false
    A.select(P, "exchange")
    T.check(shown("exchange", "noec") and shown("exchange", "hu") and shown("exchange", "f:shop.swap.pts")
        and shown("exchange", "f:shop.titles.season"), "no economy: the warning, and the uses section with its fields")
    local exData = P.pages.exchange.data
    P.pages.exchange.data = nil
    A.layout(P)
    T.check(shown("exchange", "ld") and shown("exchange", "hu") and shown("exchange", "f:shop.shield.pts"),
        "still loading the exchange status: the uses section is there too")
    P.pages.exchange.data = exData
    replies["ex.status"] = exReply
    P.pages.exchange.loaded = false
    A.select(P, "exchange")

    T.section("admin shop: the confirm view names a use's field with what it is for")
    pool("exchange")["f:shop.swap.pts"]:setText("60")
    pool("exchange")["f:shop.titles.list.spend_2"]:setText("2500")
    pool("exchange")["f:shop.titles.enabled"]:setChecked(false)
    A.onPreview(P)
    local changes = Q.Util.decode(ctx.last("cfg.preview").changes)
    local by = {}
    for _, ch in ipairs(changes) do by[ch.path] = ch end
    T.check(#changes == 3 and by["shop.swap.pts"].value == 60 and by["shop.titles.list.spend_2"].value == 2500
        and by["shop.titles.enabled"].value == false and by["shop.titles.list.spend_2"].op == "set",
        "Apply sends each use on its own path (a title price: shop.titles.list.<id>)")
    A.onConfirmCancel(P)
    A.discard(P)
    local labels = {}
    keyed(function()
        for _, p in ipairs({ "shop.swap.pts", "shop.titles.list.spend_2", "shop.titles.enabled", "hordes.paid.rewardPct",
            "hordes.paid.enabled", "hordes.maxPerDay" }) do labels[p] = A.pathLabel(P, p) end
    end)
    T.check(labels["shop.swap.pts"] == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_swap|IGUI_MQ_Admin_F_shop_swap_pts"
        and string.find(labels["shop.titles.list.spend_2"], "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_titles|IGUI_MQ_Admin_ShopTitlePts|", 1, true) == 1
        and labels["hordes.paid.rewardPct"] == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_horde|IGUI_MQ_Admin_F_hordes_paid_rewardPct",
        "a price or limit reads 'what it is for: field' in the confirm view")
    T.check(labels["shop.titles.enabled"] == "IGUI_MQ_Admin_F_shop_titles_enabled" and labels["hordes.paid.enabled"] == "IGUI_MQ_Admin_F_hordes_paid_enabled"
        and labels["hordes.maxPerDay"] == "IGUI_MQ_Admin_F_hordes_maxPerDay", "a switch and the other horde paths read as before")

    T.section("admin shop: sponsored hordes on the hordes tab (between windows and presets)")
    A.select(P, "hordes")
    local hp = pool("hordes")
    T.check(shown("hordes", "hpd") and shown("hordes", "pdn") and hp["hpd"].y > hp["hw"].y and hp["hpd"].y < hp["hpre"].y
        and hp["f:hordes.paid.enabled"].y > hp["hpd"].y and hp["f:hordes.paid.waitMin"].y < hp["hpre"].y,
        "the sponsored hordes section sits after the windows and before the presets")
    T.check(hp["f:hordes.paid.enabled"]:getChecked() == false and hp["f:hordes.paid.enabled"].opts.label == "IGUI_MQ_Admin_F_hordes_paid_enabled",
        "sponsoring starts off; the switch carries its label")
    local dd = hp["f:hordes.paid.preset"]
    local opts = {}
    for _, o in ipairs(dd.opts.options or {}) do opts[o.id] = true end
    T.check(dd.selected == "default" and opts.default, "the preset dropdown lists the presets, on the default one")
    roundTrip("hordes", "towns", AM.PAID)

    T.section("admin shop: deleting the sponsored horde's preset moves it back to the default")
    A.select(P, "hordes")
    press("hordes", "pre:copy")
    local pg = P.pages.hordes
    local copyId = pg.preset
    dd = pool("hordes")["f:hordes.paid.preset"]
    dd:setSelected(copyId)
    press("hordes", "pre:del")
    local d = dialogs[#dialogs]
    T.check(P.S.draft.by["hordes.paid.preset"] == copyId and string.find(d.text, "IGUI_MQ_Admin_HordePresetDelPaid", 1, true) == 1,
        "the picked preset went into the draft; the delete dialog says sponsored hordes move to the default")
    answer(true)
    T.check(AM.get(P.S, "hordes.paid.preset") == "default" and P.S.draft.by["hordes.paid.preset"] == nil
        and pool("hordes")["f:hordes.paid.preset"].selected == "default",
        "deleted: back on the default preset, nothing left in the draft (default is applied)")
    press("hordes", "pre:copy")
    copyId = pg.preset
    press("hordes", "pre:del")
    d = dialogs[#dialogs]
    T.check(string.find(d.text, "HordePresetDelPaid", 1, true) == nil, "a preset the sponsored horde does not use: the dialog does not mention it")
    answer(true)
    T.check(P.S.draft.by["hordes.paid.preset"] == nil, "and its setting is not touched")
    A.discard(P)
    -- applied on a preset: deleting it drafts a set back to "default"
    P.S.overrides.hordes = { presets = { hard = { name = "Hard", waves = { { base = 50, perPlayer = 50 } }, kinds = { runner = 100 },
        points = { runner = 9 }, hp = {}, limitMin = 10, restSec = 30, maxAlive = 200, cap = 900 } }, paid = { preset = "hard" } }
    A.resync(P)
    local pick = pool("hordes")["pre:pick"]
    pick.opts.onChange(pick.opts.target, "hard", pick)
    T.check(pool("hordes")["f:hordes.paid.preset"].selected == "hard", "the dropdown shows the applied preset")
    press("hordes", "pre:del")
    answer(true)
    T.check(P.S.draft.by["hordes.paid.preset"] == "default" and P.S.draft.by["hordes.presets.hard"] == AM.DEL,
        "an applied preset deleted: the sponsored horde's preset is set back to default in the same draft")
    A.discard(P)
    P.S.overrides.hordes = nil
    A.resync(P)

    T.section("admin shop: the fund line in the status")
    local status = {}
    local stReply = replies["horde.status"]
    replies["horde.status"] = function() return T.deepcopy(status) end
    local function reopen()
        A.select(P, "towns")
        keyed(function() A.select(P, "hordes") end)
    end
    reopen()
    T.check(not shown("hordes", "fund"), "no fund and sponsoring off: no fund line")
    status = { fund = { by = { alice = 100, bob = 50 }, total = 150, pts = 600, startMs = now, expireAt = now + 1800000, state = "open" },
        paid = { n = 0, max = 1 },
        cur = { id = 3, state = "planned", startMs = now + 900000, waves = 2, weights = {}, preset = "", actor = "fund", sponsors = { alice = 100 } } }
    reopen()
    local fl = pool("hordes")["fund"]
    T.check(fl and fl:isVisible() and string.find(fl.lines[1], "IGUI_MQ_Admin_HordeFundOpen|150|600|2|", 1, true) == 1
        and string.find(fl.lines[1], "|0|1", 1, true) ~= nil, "an open fund: points / goal, sponsors, end time, sponsored today n / max")
    T.check(string.find(pool("hordes")["cur"].lines[1], "IGUI_MQ_Admin_HordeCurPaid|", 1, true) == 1, "a sponsored horde says so on its status line")
    status.fund.state, status.cur = "ready", nil
    reopen()
    T.check(pool("hordes")["fund"].lines[1] == "IGUI_MQ_Admin_HordeFundReady|150|2|0|1", "a full fund: waits for the current horde")
    T.check(string.find(pool("hordes")["cur"].lines[1], "HordeCurPaid", 1, true) == nil, "an ordinary status line has no sponsored mark")
    status = { paid = { n = 1, max = 2 } }
    P.S.overrides.hordes = { paid = { enabled = true } }
    reopen()
    T.check(pool("hordes")["fund"]:isVisible() and pool("hordes")["fund"].lines[1] == "IGUI_MQ_Admin_HordeFundNone|1|2",
        "no fund but sponsoring on: the line says so with today's count")
    P.S.overrides.hordes = nil
    replies["horde.status"] = stReply
    A.resync(P)

    T.section("admin shop: spent points on the report")
    local rep = { days = 7, at = now, rows = {}, sum = { pts = 1000, ptsBy = { quest = 1000 }, spent = 300,
        spentBy = { swap = 100, shield = 0, horde = 200 } }, snap = {} }
    replies["report.get"] = function() return T.deepcopy(rep) end
    P.pages.report.loaded = false
    keyed(function() A.select(P, "report") end)
    T.check(shown("report", "ps") and pool("report")["ps"].lines[1] == "IGUI_MQ_Admin_ReportSpent|7|300"
        and pool("report")["ps"].y > pool("report")["pi"].y and pool("report")["ps"].y < pool("report")["pe"].y,
        "the points section says what was spent in the period, after what was given out")
    local psk = pool("report")["psk"].lines[1]
    T.check(string.find(psk, "IGUI_MQ_Admin_ReportShare|IGUI_MQ_Admin_ReportSpent_swap|100|33%", 1, true) ~= nil
        and string.find(psk, "IGUI_MQ_Admin_ReportSpent_horde|200|67%", 1, true) ~= nil and string.find(psk, "shield", 1, true) == nil,
        "spent by use like the issued line; a use with nothing spent is left out")
    -- a fund pledged before the period and paid back in it: horde is negative
    rep.sum.spent, rep.sum.spentBy = 500, { title = 1000, horde = -500 }
    A.select(P, "towns")
    P.pages.report.loaded = false
    keyed(function() A.select(P, "report") end)
    psk = pool("report")["psk"].lines[1]
    T.check(string.find(psk, "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_ReportSpent_title|1,000", 1, true) ~= nil
        and string.find(psk, "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_ReportSpent_horde|-500", 1, true) ~= nil
        and string.find(psk, "%", 1, true) == nil, "a net refund shows as a negative row, without shares")
    rep.sum.spent, rep.sum.spentBy = nil, nil
    A.select(P, "towns")
    P.pages.report.loaded = false
    A.select(P, "report")
    T.check(not shown("report", "ps") and not shown("report", "psk") and shown("report", "pe") and shown("report", "pi"),
        "an older server without spent: the report draws as before")
    replies["report.get"] = nil

    T.section("admin shop: point titles on the Titles tab")
    local D = Q.Draw
    local sources = D.titleSources
    D.titleSources = function(...)
        local out = sources(...)
        out[#out + 1] = { id = "mystery_1", name = "Mystery", group = "mystery", cond = "?" }
        return out
    end
    AM.draftSet(P.S.draft, "shop.titles.list.spend_1", 1234)
    local seenCfg
    local real = D.titleSources
    D.titleSources = function(achs, cfg, no) seenCfg = cfg; return real(achs, cfg, no) end
    keyed(function() A.select(P, "titles") end)
    D.titleSources = sources
    local groups = {}
    for k, el in pairs(pool("titles")) do
        local i = tonumber(string.match(k, "^g(%d+)$"))
        if i and el:isVisible() then groups[el.cells[1].text] = i end
    end
    T.check(seenCfg and seenCfg.shop and seenCfg.shop.titles.list.spend_1 == 1234 and seenCfg.shop.titles.enabled == true,
        "the Titles tab hands the draft's point title settings to titleSources")
    -- an unknown group reads by its id (groupLabel: the AchCat key, else the id); its row is listed under it
    local mysteryRow = false
    for k, el in pairs(pool("titles")) do
        if string.match(k, "^r%d+$") and el:isVisible() and el.cells[1].text == "Mystery" then mysteryRow = true end
    end
    local mysteryGroup = groups["mystery"] or groups["IGUI_MQ_AchCat_mystery"]
    T.check(mysteryGroup ~= nil and mysteryRow, "a group the tab has no label for still shows (by its id), with its row")
    local seasonAt = math.huge
    for text, i in pairs(groups) do
        if string.find(text, "IGUI_MQ_Admin_TitleGroupSeason|", 1, true) == 1 then seasonAt = math.min(seasonAt, i) end
    end
    local shopAt, otherAt = groups["IGUI_MQ_Admin_TitleGroupShop"], groups["IGUI_MQ_Admin_TitleGroupOther"]
    T.check(shopAt ~= nil and otherAt ~= nil and otherAt < shopAt and shopAt < seasonAt,
        "point titles (group shop) come after streak and newcomer, before the season titles")
    A.discard(P)
    A.select(P, "history")
    T.check(#ctx.unclosed == 0, "every list box opened on these tabs was closed: " .. table.concat(ctx.unclosed, ", "))
end
