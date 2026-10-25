-- AdminUI scenarios: change assembly (batch multiplier, add tier, tier editor, custom achievement, forms, towns),
-- client-side input checks, time text, and a round trip of the assembled changes through the server's cfg.preview
-- (the client and Config.validate must agree on paths and shapes). The UI-driving half is t_admin_ui.lua.
return function(T)
    local function near(a, b) return math.abs(a - b) < 1e-9 end

    T.section("admin: client modules load and every tab has a page")
    local Q = T.bootClient({})
    local A, AM, C = Q.Admin, Q.AdminModel, Q.Catalog
    T.check(A ~= nil and AM ~= nil and C ~= nil, "Admin, AdminModel and Catalog loaded on the client")
    for _, id in ipairs(A.TABS) do
        T.check(A.pages[id] ~= nil and type(A.pages[id].layout) == "function", "admin tab has a layout: " .. id)
    end

    T.section("admin: input checks")
    T.check(AM.check("1,000", "tier") == 1000, "thousands separators accepted")
    T.check(AM.check(" 42 ", "pts") == 42, "spaces trimmed")
    local v, key = AM.check("abc", "pts")
    T.check(v == nil and key == "IGUI_MQ_Admin_ErrNumber", "non-number rejected")
    v, key = AM.check("10001", "pts")
    T.check(v == nil and key == "IGUI_MQ_Admin_ErrRange", "points over 10000 rejected")
    T.check(AM.check("-1", "pts") == nil, "negative points rejected")
    T.check(AM.check("0", "tier") == nil, "threshold 0 rejected")
    T.check(AM.check("1.5", "tier") == nil, "fractional threshold rejected")
    T.check(near(AM.check("1.25", "mult"), 1.25), "fractional multiplier accepted")
    T.check(AM.check("0.05", "mult") == nil and AM.check("11", "mult") == nil, "multiplier outside 0.1..10 rejected")
    T.check(AM.check("6", "days") == nil and AM.check("181", "days") == nil and AM.check("35", "days") == 35,
        "season length 7..180")
    T.check(AM.check("6", "eventMult") == nil and near(AM.check("1.5", "eventMult"), 1.5), "event multiplier 1..5")
    T.check(AM.check("nan", "pts") == nil and AM.check("inf", "tier") == nil, "nan/inf rejected")

    T.section("admin: new tier defaults (x2.5 to 2 significant digits, points x1.5 to 10)")
    local t, p = AM.nextTier({ 100, 1000, 5000, 20000, 50000, 100000 }, { 10, 20, 30, 50, 80, 120 })
    T.check(t == 250000 and p == 180, "after 100,000 / 120: 250,000 / 180 (spec 13.4)")
    t, p = AM.nextTier({ 100, 1000, 5000, 20000 }, { 10, 20, 30, 50 })
    T.check(t == 50000 and p == 80, "after 20,000 / 50: 50,000 / 80")
    t, p = AM.nextTier({ 3 }, { 10 })
    T.check(t == 8 and p == 20, "small thresholds still grow: 3 -> 8")
    t = AM.nextTier({ 1234 }, { 10 })
    T.check(t == 3100, "3085 rounds to 3100")

    T.section("admin: batch multiplier writes only changed paths")
    local S = { defaults = C.DEFAULTS, overrides = {}, draft = AM.newDraft() }
    local list = AM.achievements(S, C)
    local zk
    for _, a in ipairs(list) do if a.id == "zombie_kills" then zk = a end end
    T.check(zk ~= nil and #zk.tiers >= 4, "zombie_kills is in the merged list")
    local n, skipped = AM.batchScale(S, list, { zombie_kills = true }, "tiers", 1.25)
    T.check(n == 1 and #skipped == 0, "one achievement scaled")
    local changes = AM.draftChanges(S.draft)
    T.check(#changes == 1 and changes[1].op == "set" and changes[1].path == "achievements.zombie_kills.tiers",
        "one set change on achievements.zombie_kills.tiers")
    T.check(changes[1].value[1] == math.floor(zk.tiers[1] * 1.25 + 0.5) and changes[1].value[3] == math.floor(zk.tiers[3] * 1.25 + 0.5),
        "thresholds multiplied and rounded")
    T.check(AM.get(S, "achievements.zombie_kills.tiers")[1] == changes[1].value[1], "AM.get sees the draft")
    T.check(AM.get({ defaults = C.DEFAULTS, overrides = {} }, "achievements.zombie_kills.tiers")[1] == zk.tiers[1],
        "draft does not touch defaults")
    local scaled = AM.scaleTiers({ 1, 2, 3 }, 0.1)
    T.check(scaled[1] == 1 and scaled[2] == 2 and scaled[3] == 3, "x0.1 keeps thresholds >= 1 and strictly increasing")
    T.check(AM.scaleTiers({ 1, 900000000 }, 2) == nil, "overflow past 1e9 refused")
    local pts = AM.scalePts({ 10, 9000 }, 1.25)
    T.check(pts[1] == 13 and pts[2] == 10000, "points scaled and capped at 10000")

    T.section("admin: add tier to a selection; 10-tier cap")
    S.draft = AM.newDraft()
    list = AM.achievements(S, C)
    n = AM.batchAddTier(S, list, { zombie_kills = true })
    local tiers = AM.get(S, "achievements.zombie_kills.tiers")
    local apts = AM.get(S, "achievements.zombie_kills.pts")
    T.check(n == 1 and #tiers == #zk.tiers + 1 and #apts == #tiers, "one tier added to thresholds and points")
    local et, ep = AM.nextTier(zk.tiers, zk.pts)
    T.check(tiers[#tiers] == et and apts[#apts] == ep, "added tier uses the default")
    local ten = { id = "x", path = "achievements.x", tiers = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, pts = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, titles = {} }
    n, skipped = AM.batchAddTier(S, { ten }, { x = true })
    T.check(n == 0 and #skipped == 1, "an achievement at 10 tiers is skipped")

    T.section("admin: tier editor rows")
    local ti, tp, tt = AM.readTierRows({ { tier = "100", pts = "10", title = "" }, { tier = "1,000", pts = "20", title = "  Undying  " } })
    T.check(ti ~= nil and ti[2] == 1000 and tp[2] == 20 and tt[2] == "Undying" and tt[1] == nil, "rows read, titles trimmed")
    local _, errs = AM.readTierRows({ { tier = "100", pts = "10" }, { tier = "100", pts = "10" } })
    T.check(_ == nil and errs[2] and errs[2][2] == "IGUI_MQ_Admin_ErrIncreasing", "equal thresholds rejected")
    _, errs = AM.readTierRows({ { tier = "100", pts = "99999" } })
    T.check(_ == nil and errs[1][1] == "pts", "points out of range rejected")
    local eleven = {}
    for i = 1, 11 do eleven[i] = { tier = tostring(i * 10), pts = "1" } end
    _, errs = AM.readTierRows(eleven)
    T.check(_ == nil and errs[0] ~= nil, "11 tiers rejected")

    T.section("admin: custom achievement from an existing stat")
    local cid = AM.newId("c", 1730000000000)
    T.check(string.match(cid, "^[a-z0-9_]+$") ~= nil and #cid <= 32, "generated id matches ^[a-z0-9_]{1,32}$")
    local path, value = AM.customAch(cid, "  Pest control ", "combat", "zombie.kills", "10, 100 1000", "5,10,20")
    T.check(path == "custom." .. cid and value.name == "Pest control" and #value.tiers == 3 and value.pts[3] == 20
        and value.stat == "zombie.kills" and value.cat == "combat", "custom achievement value assembled")
    T.check(AM.customAch(cid, " ", "combat", "zombie.kills", "10", "5") == nil, "empty name rejected")
    T.check(AM.customAch(cid, "x", "combat", nil, "10", "5") == nil, "missing stat rejected")
    T.check(AM.customAch(cid, "x", "combat", "zombie.kills", "10,20", "5") == nil, "point count mismatch rejected")
    T.check(AM.customAch(cid, "x", "combat", "zombie.kills", "20,10", "5,5") == nil, "decreasing thresholds rejected")
    S.draft = AM.newDraft()
    AM.draftSet(S.draft, path, value)
    list = AM.achievements(S, C)
    local custom
    for _, a in ipairs(list) do if a.id == "c:" .. cid then custom = a end end
    T.check(custom ~= nil and custom.custom and list[#list] == custom, "draft custom achievement listed after built-ins")
    AM.batchScale(S, list, { ["c:" .. cid] = true }, "tiers", 2)
    local obj = AM.get(S, path)
    T.check(obj.tiers[1] == 20 and obj.name == "Pest control" and AM.draftCount(S.draft) == 1,
        "batch on a custom achievement rewrites the whole object in one change")
    AM.draftSet(S.draft, path, AM.DEL)
    list = AM.achievements(S, C)
    local still = false
    for _, a in ipairs(list) do if a.id == "c:" .. cid then still = true end end
    T.check(not still and AM.draftChanges(S.draft)[1].op == "del", "deleting a custom achievement is a del change")

    T.section("admin: forms fold into the draft")
    local tpl = C.daily[1]
    S.draft = AM.newDraft()
    local base = "daily.pool." .. tpl.tid
    local cur = AM.get(S, base .. ".target")
    T.check(type(cur) == "table" and type(cur[1]) == "number", "pool target default is an array {min, max}")
    local fa = { path = base .. ".target", part = { 1 }, key = "a" }
    local fb = { path = base .. ".target", part = { 2 }, key = "b" }
    n = AM.formToDraft(S, { { field = fa, value = cur[1] }, { field = fb, value = cur[2] } })
    T.check(n == 0 and AM.draftCount(S.draft) == 0, "unchanged form adds nothing")
    n = AM.formToDraft(S, { { field = fa, value = cur[1] + 1 }, { field = fb, value = cur[2] + 5 } })
    local ch = AM.draftChanges(S.draft)[1]
    T.check(n == 1 and ch.path == base .. ".target" and ch.value[1] == cur[1] + 1 and ch.value[2] == cur[2] + 5,
        "min and max fields become one set of the whole target")
    T.check(AM.targetOk({ 3, 5 }) and not AM.targetOk({ 5, 3 }), "min <= max check")
    local stat = C.DEFAULTS.goal.rotation[1]
    n = AM.formToDraft(S, { { field = { path = "goal.limits", part = { stat, "min" }, key = "g" }, value = 7 } })
    local gl = AM.get(S, "goal.limits")
    T.check(n == 1 and gl[stat].min == 7, "goal.limits edited through a stat-keyed part (whole map set)")
    -- a stat's per-minute limit: the default shows in the field, and typing it again leaves no key behind
    local fc = { path = "ceilings", part = { "zombie.kills" }, key = "c", default = C.stats["zombie.kills"].ceil }
    S.draft = AM.newDraft()
    n = AM.formToDraft(S, { { field = fc, value = fc.default } })
    T.check(n == 0 and AM.draftCount(S.draft) == 0, "a limit left at its default adds nothing")
    n = AM.formToDraft(S, { { field = fc, value = 200 } })
    T.check(n == 1 and AM.get(S, "ceilings")["zombie.kills"] == 200, "a changed limit is one key of the ceilings map")
    AM.formToDraft(S, { { field = fc, value = fc.default } })
    T.check(AM.get(S, "ceilings")["zombie.kills"] == nil, "back at the default the key is gone")
    local rect = AM.townRect(30, 40, 10, 20)
    T.check(rect.x1 == 10 and rect.y1 == 20 and rect.x2 == 30 and rect.y2 == 40, "town rectangle normalised")

    T.section("admin: whole-theme target multiplier on the template step")
    local st = AM.scaleTarget({ 2, 4 }, 1.25, 1)
    T.check(st and st[1] == 3 and st[2] == 5, "2-4 x1.25 -> 3-5")
    st = AM.scaleTarget({ 50, 100 }, 1.25, 25)
    T.check(st and st[1] == 75 and st[2] == 125, "50-100 on step 25 x1.25 -> 75-125")
    st = AM.scaleTarget({ 10, 20 }, 0.8, 5)
    T.check(st and st[1] == 10 and st[2] == 15, "10-20 on step 5 x0.8 -> 10-15 (8 rounds back to 10)")
    T.check(AM.scaleTarget({ 1, 1 }, 0.8, 1) == nil, "no change -> nil, nothing drafted")
    T.check(AM.scaleTarget({ 900000000, 1000000000 }, 2, 1) == nil, "past 1e9 refused")

    T.section("admin: time in the sandbox timezone")
    T.check(AM.time(0, 8) == "1970-01-01 08:00", "epoch at UTC+8")
    T.check(AM.time(0, -5) == "1969-12-31 19:00", "negative offset crosses the day")
    local ms = AM.dayStartMs("2026-11-10", 8)
    T.check(ms ~= nil and AM.time(ms, 8) == "2026-11-10 00:00" and AM.time(ms, 0) == "2026-11-09 16:00", "day start round trip")
    T.check(AM.dayStartMs("2026/2/29", 8) == nil and AM.dayStartMs("2028/2/29", 8) ~= nil, "leap days checked")
    T.check(AM.dayStartMs("2026-13-01", 8) == nil and AM.dayStartMs("nope", 8) == nil, "bad dates rejected")
    T.check(AM.tzText(8) == "+8" and AM.tzText(-3) == "-3", "timezone note text")

    T.section("admin: preview rows expand per tier")
    local P = { S = { defaults = C.DEFAULTS, overrides = {}, draft = AM.newDraft() } }
    local rows = A.diffRows(P, { { path = "achievements.zombie_kills.tiers", before = { 100, 1000, 5000 }, after = { 100, 1250, 6250 } },
        { path = "exchange.enabled", before = true, after = false } })
    T.check(#rows == 3 and rows[1].before == "1,000" and rows[1].after == "1,250", "only changed tiers listed, formatted")
    T.check(rows[3].before == "IGUI_MQ_Admin_On", "booleans as On/Off")
    rows = A.diffRows(P, { { path = "ceilings", before = {}, after = { ["zombie.kills"] = 200 } } })
    T.check(#rows == 1 and rows[1].before == A.num(C.stats["zombie.kills"].ceil) and rows[1].after == "200",
        "a ceilings change lists the stat with its default as the old value")

    T.section("admin: assembled changes pass the server's cfg.preview")
    local all = {}
    S = { defaults = C.DEFAULTS, overrides = {}, draft = AM.newDraft() }
    list = AM.achievements(S, C)
    AM.batchScale(S, list, { zombie_kills = true }, "tiers", 1.25)
    AM.batchAddTier(S, AM.achievements(S, C), { zombie_kills = true })
    AM.batchScale(S, AM.achievements(S, C), { zombie_kills = true }, "pts", 1.5)
    path, value = AM.customAch(AM.newId("c", 1730000000001), "Pest control", "combat", "zombie.kills", "10,100", "5,10")
    AM.draftSet(S.draft, path, value)
    AM.formToDraft(S, { { field = fa, value = cur[1] }, { field = fb, value = cur[2] + 1 } })
    AM.formToDraft(S, { { field = { path = "goal.limits", part = { stat, "minContrib" }, key = "g" }, value = 2 } })
    AM.draftSet(S.draft, "towns.custom", { { id = AM.newId("t", 1730000000002), name = "Camp", rects = { AM.townRect(5, 5, 1, 1) } } })
    AM.draftSet(S.draft, "towns.disabled", { [C.towns[1].id] = true })
    AM.draftSet(S.draft, "exchange.rate", 2)
    AM.draftSet(S.draft, "achievements.zombie_kills.enabled", false)
    AM.draftSet(S.draft, "daily.pool." .. tpl.tid .. ".enabled", false)
    AM.draftSet(S.draft, "weekly.pool." .. C.weekly[1].tid .. ".target", AM.scaleTarget(C.weekly[1].target, 1.25, C.weekly[1].step))
    AM.formToDraft(S, { { field = fc, value = 200 } })
    for _, c in ipairs(AM.draftChanges(S.draft)) do all[#all + 1] = c end
    local Qs = T.boot({})
    local admin = T.player({ name = "boss", admin = true })
    local json = Qs.Util.encode(all)
    local r = T.cmd(admin, "admin", { op = "cfg.preview", changes = json })
    T.check(r ~= nil and r.ok == true and type(r.rows) == "table" and #r.rows == #all,
        "cfg.preview accepts every assembled change (" .. tostring(r and (r.code or "") .. " " .. tostring(r.detail and r.detail.path) .. " "
            .. tostring(r.detail and r.detail.why)) .. ")")
    local bad = Qs.Util.encode({ { op = "set", path = "achievements.zombie_kills.tiers", value = { 10, 5 } } })
    r = T.cmd(admin, "admin", { op = "cfg.preview", changes = bad })
    T.check(r ~= nil and r.ok == false and r.code == "BAD_CONFIG", "server still rejects what the client would have blocked")
    local user = T.player({ name = "joe" })
    r = T.cmd(user, "admin", { op = "cfg.preview", changes = json })
    T.check(r == nil or r.ok == false, "non-admin cannot preview")

    T.section("admin: quests.playerList (players see the per-theme quest list)")
    T.check(Qs.Config.get().quests.playerList == false, "off by default")
    T.cmd(user, "hello", {})
    r = T.cmd(user, "admin", { op = "cfg.apply", changes = '[{"op":"set","path":"quests.playerList","value":true}]', summary = "x" })
    T.check(r ~= nil and r.ok == false and Qs.Config.get().quests.playerList == false, "a player cannot turn it on")
    r = T.cmd(admin, "admin", { op = "cfg.apply", changes = '[{"op":"set","path":"quests.playerList","value":1}]', summary = "x" })
    T.check(r ~= nil and r.code == "BAD_CONFIG", "only true / false")
    T.clearOutbox()
    r = T.cmd(admin, "admin", { op = "cfg.apply", changes = '[{"op":"set","path":"quests.playerList","value":true}]', summary = "on" })
    local cat = T.lastOf(user, "catalog")
    T.check(r ~= nil and r.ok and Qs.Config.get().quests.playerList == true and cat ~= nil
        and cat.overrides.quests.playerList == true, "an admin turns it on; the catalog push tells every player")
    local hist = T.cmd(admin, "admin", { op = "cfg.get" }).history
    T.check(hist[#hist].summary == "on", "the change is in the history")

    dofile("scripts/harness/t_admin_ui.lua")(T)
end
