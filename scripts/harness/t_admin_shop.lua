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
            elseif range ~= "pick" and range ~= "day" and range ~= "clock" then
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
    -- squad contracts below the uses: the shared knobs, then each template's four
    local ctRows = {}
    for _, r in ipairs(AM.CONTRACTS) do ctRows[#ctRows + 1] = r end
    for _, t in ipairs(C.contracts) do
        for _, k in ipairs(AM.CONTRACT_TPL) do ctRows[#ctRows + 1] = { "contracts.list." .. t.id .. "." .. k[1], k[2] } end
    end
    T.check(#ctRows == 9 + 3 * 4 and shown("exchange", "hct") and pool("exchange")["hct"].y > pool("exchange")["hu"].y,
        "a Squad contracts heading after the uses")
    roundTrip("exchange", "season", ctRows)
    keyed(function()
        T.check(A.pathLabel(P, "contracts.list.hunt.stake") == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Contract_hunt|IGUI_MQ_Admin_F_contracts_list_stake"
            and A.pathLabel(P, "contracts.bonusPct") == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_contract|IGUI_MQ_Admin_F_contracts_bonusPct"
            and A.pathLabel(P, "shop.color.pts") == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_color|IGUI_MQ_Admin_F_shop_color_pts"
            and A.pathLabel(P, "hordes.paid.pts") == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_horde|IGUI_MQ_Admin_F_hordes_paid_pts",
            "the confirm view names a contract or colour field with what it is for; the others as before")
    end)

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
    T.check(hp["f:hordes.paid.pts"] == nil and hp["f:hordes.paid.preset"] == nil and shown("hordes", "f:hordes.paid.backPct"),
        "price and preset left the form for the difficulty table; the share back on a clear is a field")
    local dd = hp["t:p1"]
    local opts = {}
    for _, o in ipairs(dd.opts.options or {}) do opts[o.id] = true end
    T.check(dd.selected == "default" and opts.default and hp["f:hordes.paid.tiers.1.name"]:getText() == "normal"
        and hp["f:hordes.paid.tiers.3.name"]:getText() == "nightmare" and hp["f:hordes.paid.tiers.2.pts"]:getText() == "1200"
        and hp["f:hordes.paid.tiers.3.hp"]:getText() == "3" and hp["f:hordes.paid.tiers.1.limitMin"]:getText() == "15"
        and hp["f:hordes.paid.tiers.4.pts"] == nil, "the three default tiers: name, preset, price, toughness, the preset's minutes")
    T.check(hp["t:r1"]:isEnabled() and hp["t:add"]:isEnabled() and hp["t:p1"].y > hp["f:hordes.paid.waitMin"].y
        and hp["t:p3"].y < hp["hdn"].y, "the table comes after the rules, before the donation; Add and Remove on")
    roundTrip("hordes", "towns", AM.PAID)

    T.section("admin shop: the difficulty table edits the whole tier list")
    A.select(P, "hordes")
    hp = pool("hordes")
    hp["f:hordes.paid.tiers.2.pts"]:setText("1300")
    hp["f:hordes.paid.tiers.3.limitMin"]:setText("30")
    hp["f:hordes.paid.tiers.1.name"]:setText("  Easy  ")
    A.select(P, "towns")
    A.select(P, "hordes")
    local dt = P.S.draft.by["hordes.paid.tiers"]
    T.check(type(dt) == "table" and #dt == 3 and dt[2].pts == 1300 and dt[3].limitMin == 30 and dt[1].limitMin == nil
        and dt[2].limitMin == 20 and dt[1].name == "Easy" and dt[3].hp == 3 and AM.draftCount(P.S.draft) == 1,
        "price, minutes and a trimmed name go into one whole-list entry; a minutes field left at the preset's stays unset, an own one stays")
    hp = pool("hordes")
    hp["f:hordes.paid.tiers.2.pts"]:setText("1200")
    hp["f:hordes.paid.tiers.3.limitMin"]:setText("25")
    hp["f:hordes.paid.tiers.1.name"]:setText("normal")
    A.select(P, "towns")
    A.select(P, "hordes")
    T.check(P.S.draft.by["hordes.paid.tiers"] == nil, "typed back: the list leaves the draft")
    press("hordes", "t:add")
    hp = pool("hordes")
    dt = P.S.draft.by["hordes.paid.tiers"]
    T.check(#dt == 4 and dt[4].name == "" and dt[4].pts == 2500 and dt[4].preset == "default" and dt[4].hp == 3
        and not hp["t:add"]:isEnabled() and hp["t:max"].color.token == "warning",
        "Add copies the last tier without its name; at 4 Add is off and the max note warns")
    press("hordes", "t:r2")
    dt = P.S.draft.by["hordes.paid.tiers"]
    T.check(#dt == 3 and dt[2].pts == 2500 and dt[3].name == "", "Remove takes that tier out")
    A.discard(P)
    P.S.overrides.hordes = { paid = { tiers = { { name = "normal", preset = "default", pts = 600, hp = 1 } } } }
    A.resync(P)
    A.select(P, "hordes")
    T.check(not pool("hordes")["t:r1"]:isEnabled() and pool("hordes")["f:hordes.paid.tiers.2.pts"]:isVisible() == false,
        "one tier: it cannot be removed")
    local rows
    keyed(function()
        rows = A.diffRows(P, { { path = "hordes.paid.tiers", before = C.DEFAULTS.hordes.paid.tiers,
            after = { { name = "", preset = "default", pts = 700, hp = 1.5 } } }, { path = "donate.day", before = 6, after = 2 },
            { path = "hordes.paid.tiers.2.pts", before = 1200, after = 1100 } })
    end)
    T.check(rows[1].after == "IGUI_MQ_Admin_HordeTierText|IGUI_MQ_UI_TierN|1|700|1.5|IGUI_MQ_Admin_HordePresetDefault"
        and string.find(rows[1].before, "IGUI_MQ_Tier_hard|1,200|2|", 1, true) ~= nil
        and rows[2].before == "IGUI_MQ_UI_Weekday_6" and rows[2].after == "IGUI_MQ_UI_Weekday_2"
        and rows[3].label == "IGUI_MQ_Admin_UseRow|IGUI_MQ_Admin_Use_horde|IGUI_MQ_UI_TierN|2 - IGUI_MQ_Admin_F_hordes_paid_tiers_pts",
        "the confirm view reads the tiers, the weekday and one tier's field")
    P.S.overrides.hordes = nil
    A.resync(P)

    T.section("admin shop: the server-wide donation on the hordes tab")
    A.select(P, "hordes")
    hp = pool("hordes")
    T.check(shown("hordes", "hdn") and hp["hdn"].y > hp["hpd"].y and hp["hdn"].y < hp["hpre"].y
        and hp["f:donate.enabled"]:getChecked() == false and hp["f:donate.day"].selected == 6
        and hp["f:donate.time"]:getText() == "21:00" and hp["f:donate.preset"].selected == "default",
        "after the sponsored hordes: off, Saturday 21:00 on the default preset")
    roundTrip("hordes", "towns", AM.DONATE)
    A.select(P, "hordes")
    pool("hordes")["f:donate.day"]:setSelected(2)
    pool("hordes")["f:donate.time"]:setText("20:30")
    A.select(P, "towns")
    T.check(P.S.draft.by["donate.day"] == 2 and P.S.draft.by["donate.time"] == "20:30", "the weekday and the time go into the draft")
    A.discard(P)
    A.select(P, "hordes")
    pool("hordes")["f:donate.time"]:setText("25:00")
    A.select(P, "towns")
    T.check(P.current == "hordes" and P.S.draft.by["donate.time"] == nil, "a bad time is marked and not drafted")
    A.discard(P)

    T.section("admin shop: deleting a preset a tier or the donation plays moves them back to the default")
    A.select(P, "hordes")
    press("hordes", "pre:copy")
    local pg = P.pages.hordes
    local copyId = pg.preset
    dd = pool("hordes")["t:p2"]
    dd.opts.onChange(dd.opts.target, copyId, dd)
    pool("hordes")["f:donate.preset"]:setSelected(copyId)
    press("hordes", "pre:del")
    local d = dialogs[#dialogs]
    T.check(P.S.draft.by["hordes.paid.tiers"][2].preset == copyId and P.S.draft.by["donate.preset"] == copyId
        and string.find(d.text, "IGUI_MQ_Admin_HordePresetDelPaid\nIGUI_MQ_Admin_HordePresetDelDonate", 1, true) == 1,
        "the picks went into the draft; the delete dialog says the tiers and the donation move to the default")
    answer(true)
    T.check(AM.get(P.S, "hordes.paid.tiers")[2].preset == "default" and P.S.draft.by["hordes.paid.tiers"] == nil
        and P.S.draft.by["donate.preset"] == nil and pool("hordes")["t:p2"].selected == "default",
        "deleted: back on the default preset, nothing left in the draft (default is applied)")
    press("hordes", "pre:copy")
    copyId = pg.preset
    press("hordes", "pre:del")
    d = dialogs[#dialogs]
    T.check(string.find(d.text, "HordePresetDelPaid", 1, true) == nil and string.find(d.text, "DelDonate", 1, true) == nil,
        "a preset nothing paid uses: the dialog does not mention them")
    answer(true)
    T.check(P.S.draft.by["hordes.paid.tiers"] == nil and P.S.draft.by["donate.preset"] == nil, "and their settings are not touched")
    A.discard(P)
    -- applied on a preset: deleting it drafts the tiers and the donation back to "default"
    P.S.overrides.hordes = { presets = { hard = { name = "Hard", waves = { { base = 50, perPlayer = 50 } }, kinds = { runner = 100 },
        points = { runner = 9 }, hp = {}, limitMin = 10, restSec = 30, maxAlive = 200, cap = 900 } },
        paid = { tiers = { { name = "normal", preset = "default", pts = 600, hp = 1 }, { name = "hard", preset = "hard", pts = 900, hp = 2 } } } }
    P.S.overrides.donate = { preset = "hard" }
    A.resync(P)
    local pick = pool("hordes")["pre:pick"]
    pick.opts.onChange(pick.opts.target, "hard", pick)
    T.check(pool("hordes")["t:p2"].selected == "hard" and pool("hordes")["f:hordes.paid.tiers.2.limitMin"]:getText() == "10",
        "the dropdown shows the applied preset; the minutes field that preset's")
    press("hordes", "pre:del")
    answer(true)
    local back = P.S.draft.by["hordes.paid.tiers"]
    T.check(back and back[2].preset == "default" and back[1].preset == "default" and P.S.draft.by["donate.preset"] == "default"
        and P.S.draft.by["hordes.presets.hard"] == AM.DEL,
        "an applied preset deleted: the tier and the donation are set back to default in the same draft")
    A.discard(P)
    P.S.overrides.donate = nil
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
    -- the donation where it stands (horde.status donate = root.donate) and its horde on the status line
    status = { paid = { n = 0, max = 1 }, donate = { total = 4200, n = 7, by = {}, round = 1 },
        cur = { id = 4, state = "planned", startMs = now + 900000, waves = 1, weights = {}, preset = "", actor = "donate" } }
    reopen()
    T.check(pool("hordes")["dns"]:isVisible() and pool("hordes")["dns"].lines[1] == "IGUI_MQ_Admin_DonateNow|4,200|10,000|7"
        and string.find(pool("hordes")["cur"].lines[1], "IGUI_MQ_Admin_HordeCurDonate|", 1, true) == 1,
        "the donation section: this round's points / target and donations; its horde says so on the status line")
    status.donate.hordeAt, status.cur = now + 86400000, nil
    reopen()
    T.check(string.find(pool("hordes")["dns"].lines[1], "IGUI_MQ_Admin_DonateFull|", 1, true) == 1
        and string.find(pool("hordes")["dns"].lines[1], "|4,200", 1, true) ~= nil, "full: the extra horde's time, what the next round has")
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
    -- squad contracts and title colours (plan points-play 2026-11-12): their spent columns and the contracts' success
    rep.sum.spent, rep.sum.spentBy = 400, { contract = 100, color = 300 }
    rep.sum.contractsBy = { ["hunt:open"] = 5, ["hunt:won"] = 3, ["hunt:lost"] = 1, ["long:open"] = 1 }
    A.select(P, "towns")
    P.pages.report.loaded = false
    keyed(function() A.select(P, "report") end)
    psk = pool("report")["psk"].lines[1]
    T.check(string.find(psk, "IGUI_MQ_Admin_ReportSpent_contract|100|25%", 1, true) ~= nil
        and string.find(psk, "IGUI_MQ_Admin_ReportSpent_color|300|75%", 1, true) ~= nil, "contracts and colours in the spent line")
    T.check(shown("report", "pc") and pool("report")["pc1"].lines[1] == "IGUI_MQ_Admin_ReportContract|IGUI_MQ_Contract_hunt|5|3|1|75%"
        and pool("report")["pc2"].lines[1] == "IGUI_MQ_Admin_ReportContract|IGUI_MQ_Contract_long|1|0|0|-"
        and pool("report")["pc3"] == nil, "contracts by template: started, met, not met, the share met (none ended: -)")
    rep.sum.contractsBy = nil
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
