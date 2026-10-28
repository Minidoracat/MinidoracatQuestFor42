-- Core scenarios: dispatch guards, identity, store, stats, points, config, sync, clock, facade, SP path.
return function(T)
    local function boot(opts)
        local Q = T.boot(opts)
        -- private test stats (do not depend on Catalog numbers)
        Q.Catalog = Q.Catalog or {}
        Q.Catalog.stats = Q.Catalog.stats or {}
        Q.Catalog.stats["t.count"] = { id = "t.count", kind = "count", ceil = 10 }
        Q.Catalog.stats["t.max"] = { id = "t.max", kind = "max" }
        return Q
    end
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local CODE

    T.section("boot, schema, facade")
    local Q = boot({ sandbox = { AdminRoles = "admin;owner" } })
    CODE = Q.Contract.CODE
    T.check(Q.Store.ready() and T.gmd.MinidoracatQuest.schema == 1, "root table created with schema 1")
    local shards = 0
    for i = 0, 15 do if T.gmd[string.format("MinidoracatQuest_A%02d", i)].schema == 1 then shards = shards + 1 end end
    T.check(shards == 16, "16 account shards with schema")
    T.check(#T.netEarly == 0, "no network use before OnServerStarted")
    T.check(type(Q.v1) == "table" and Q.v1.API_MAJOR == 1, "facade v1 published after all modules")

    T.section("field whitelist and types")
    local alice = T.player({ name = "alice" })
    local admin = T.player({ name = "boss", admin = true })
    local owner = T.player({ name = "own", role = "owner" })
    T.cmd(alice, "hello", {})
    T.check(T.lastOf(alice, "state") ~= nil and T.lastOf(alice, "catalog") ~= nil, "hello sends catalog and state")
    T.check(Q.Store.account("alice", false) ~= nil, "hello creates the account")
    local r = T.cmd(alice, "watch", { on = true, extra = 1 })
    T.check(r and r.code == CODE.BAD_ARGS, "unknown field rejected")
    r = T.cmd(alice, "watch", { on = "yes" })
    T.check(r and r.code == CODE.BAD_ARGS, "wrong type rejected")
    r = T.cmd(alice, "watch", {})
    T.check(r and r.code == CODE.BAD_ARGS, "missing required field rejected")
    r = T.cmd(admin, "admin", { op = "anom.list", days = 0 / 0 })
    T.check(r and r.code == CODE.BAD_ARGS, "NaN rejected")
    r = T.cmd(admin, "admin", { op = "anom.list", days = math.huge })
    T.check(r and r.code == CODE.BAD_ARGS, "Inf rejected")
    r = T.cmd(alice, "title", { id = string.rep("x", 65) })
    T.check(r and r.code == CODE.BAD_ARGS, "str over 64 rejected")
    r = T.cmd(alice, "title", { id = "a\nb" })
    T.check(r and r.code == CODE.BAD_ARGS, "control characters rejected")
    r = T.cmd(alice, "watch", { on = true, protocol = 99 })
    T.check(r and r.code == CODE.PROTOCOL_MISMATCH and r.serverProtocol == 1, "protocol mismatch")
    r = T.cmd(alice, "seen", {}, false)
    T.check(r and r.code == CODE.BAD_ARGS, "mutation without requestId rejected")
    r = T.cmd(alice, "nope", {})
    T.check(r and r.code == CODE.BAD_ARGS, "unknown command rejected")
    r = T.cmd(admin, "admin", { op = "cfg.preview", changes = "{not json" })
    T.check(r and r.code == CODE.BAD_ARGS, "malformed json rejected")
    r = T.cmd(admin, "admin", { op = "cfg.preview", changes = "[" .. string.rep("1,", 17000) .. "1]" })
    T.check(r and r.code == CODE.BAD_ARGS, "json over 32000 bytes rejected")
    T.advance(60000)
    T.tick(1)
    T.check(T.logged("DENY\talice"), "denials aggregated into the audit log")

    T.section("admin gate")
    r = T.cmd(alice, "admin", { op = "cfg.get" })
    T.check(r and r.ok == false and r.code == CODE.FORBIDDEN and r.overrides == nil, "non-admin blocked, no data")
    local norole = T.player({ name = "ghost", noRole = true })
    r = T.cmd(norole, "admin", { op = "cfg.get" })
    T.check(r and r.code == CODE.FORBIDDEN, "nil role is not admin")
    r = T.cmd(admin, "admin", { op = "cfg.get" })
    T.check(r and r.ok and r.op == "cfg.get" and type(r.overrides) == "table", "admin role passes")
    r = T.cmd(owner, "admin", { op = "cfg.get" })
    T.check(r and r.ok, "second AdminRoles entry passes")
    r = T.cmd(alice, "admin", { op = "cfg.apply", changes = '[{"op":"set","path":"exchange.perDay","value":5}]', summary = "x" })
    T.check(r and r.code == CODE.FORBIDDEN and Q.Config.get().exchange.perDay ~= 5, "non-admin cannot apply config")

    T.section("requestId idempotency")
    local before = Q.Store.root().config.rev
    local json = '[{"op":"set","path":"exchange.perDay","value":42}]'
    local r1 = T.cmd(admin, "admin", { op = "cfg.apply", changes = json, summary = "s" }, "req-same-0001")
    local r2 = T.cmd(admin, "admin", { op = "cfg.apply", changes = json, summary = "s" }, "req-same-0001")
    T.check(r1 and r1.ok and r2 and r2.replay == true and r2.historyId == r1.historyId, "same requestId replays the first result")
    T.check(Q.Store.root().config.rev == before + 1, "replayed mutation applied once")
    T.check(Q.Store.root().audit.items[Q.Store.root().audit.head].kind == "admin", "admin mutation audited in ring")

    T.section("config preview / apply / undo")
    local def = Q.Config.get().exchange.min
    r = T.cmd(admin, "admin", { op = "cfg.preview", changes = '[{"op":"set","path":"exchange.min","value":25}]' })
    T.check(r and r.ok and r.rows[1].before == def and r.rows[1].after == 25, "preview shows before/after")
    T.check(Q.Config.get().exchange.min == def, "preview changes nothing")
    T.clearOutbox()
    r = T.cmd(admin, "admin", { op = "cfg.apply", changes = '[{"op":"set","path":"exchange.min","value":25}]', summary = "min" })
    T.check(r and r.ok and Q.Config.get().exchange.min == 25, "apply changes the effective value")
    T.check(T.lastOf(alice, "catalog") ~= nil, "apply broadcasts catalog to online players")
    local hid = r.historyId
    r = T.cmd(admin, "admin", { op = "cfg.undo", historyId = hid })
    T.check(r and r.ok and Q.Config.get().exchange.min == def, "undo restores the default")
    T.check(Q.Config.overrides().exchange.min == nil, "undo removes the override")
    r = T.cmd(admin, "admin", { op = "cfg.undo", historyId = 99999 })
    T.check(r and r.code == CODE.NOT_FOUND, "undo of unknown history id")
    local hist = T.cmd(admin, "admin", { op = "cfg.get" }).history
    T.check(#hist == 3 and hist[3].summary == "undo #" .. hid and hist[2].n == 1, "history rows carry summary and count")
    local bad = {
        { '[{"op":"set","path":"exchange.perDay","value":-1}]', "out of range" },
        { '[{"op":"set","path":"nope.x","value":1}]', "unknown path" },
        { '[{"op":"set","path":"season.lengthDays","value":14}]', "season length not a config path" },
        { '[{"op":"set","path":"achievements.zombie_kills.tiers","value":[10,5]}]', "tiers must increase" },
        { '[{"op":"set","path":"goal.limits.zombie","value":1}]', "stat-keyed family is whole-set only" },
        { '[{"op":"del","path":"exchange.min","value":1}]', "del with value" },
        { '[{"op":"set","path":"exchange..min","value":1}]', "empty path segment" },
    }
    for _, b in ipairs(bad) do
        r = T.cmd(admin, "admin", { op = "cfg.apply", changes = b[1], summary = "bad" })
        T.check(r and r.code == CODE.BAD_CONFIG and r.detail ~= nil, "rejected: " .. b[2])
    end
    r = T.cmd(admin, "admin", { op = "cfg.apply", summary = "rot",
        changes = '[{"op":"set","path":"goal.rotation","value":["zombie.kills"]},'
            .. '{"op":"set","path":"custom.c1","value":{"name":"Doc","cat":"job","stat":"t.count","tiers":[1,5],"pts":[10,20],"titles":{"2":"Legend"}}}]' })
    T.check(r and r.ok and #Q.Config.get().goal.rotation == 1, "list values replace the default list")
    T.check(Q.Config.get().custom.c1.titles[2] == "Legend", "json integer keys come back as numbers")

    T.section("config.json: mirror, edit, errors, undo, restart")
    local DIR = "MinidoracatQuest/servertest/"
    local function fileTree(name)
        local f = T.files[DIR .. name]
        return f and Q.Util.decode(table.concat(f.lines, "\n"), 1000000) or nil
    end
    local function edit(lines)
        T.files[DIR .. "config.json"] = lines and { lines = lines } or nil
        T.advance(Q.Config.POLL_MS)
        T.tick(1)
    end
    local mirrored = fileTree("config.json")
    T.check(mirrored and mirrored.exchange.perDay == 42 and mirrored.custom.c1.name == "Doc" and #mirrored.goal.rotation == 1,
        "every panel apply rewrites config.json with the settings in effect")
    local defaults = fileTree("defaults.json")
    T.check(defaults and defaults.daily.pool.d_kill.target ~= nil and defaults.achievements.zombie_kills.tiers[1] == 100
        and defaults.season == nil, "defaults.json lists every default value, config paths only")
    edit({ "{", '  "exchange": { "perDay": 7 }', "}" })
    local hist7 = Q.Config.historyRows()
    local fileHid = hist7[#hist7].id
    T.check(Q.Config.get().exchange.perDay == 7 and Q.Config.get().custom.c1 == nil and #Q.Config.get().goal.rotation > 1,
        "an edited config.json applies on the next poll; families it leaves out go back to the defaults")
    T.check(hist7[#hist7].actor == "config.json" and hist7[#hist7].summary == "config.json" and hist7[#hist7].undoable ~= false,
        "a file apply is a history entry that can be undone")
    T.check(Q.Config.file.status.ok == true and fileTree("status.json").ok == true, "status.json says it applied")
    edit({ "{", '  "exchange": {', '    "perDay": 9,', "  }", "}" })
    local fst = Q.Config.file.status
    T.check(fst.ok == false and fst.why == "json" and fst.line == 3 and Q.Config.get().exchange.perDay == 7
        and fileTree("status.json").line == 3, "broken JSON (trailing comma): nothing applied, the comma's line goes to status.json")
    edit({ "{", '  "exchange": {', '    "perDay": 9', '    "min": 5', "  }", "}" })
    T.check(Q.Config.file.status.line == 4, "missing comma: the line where parsing stopped")
    edit({ '{ "daily": { "pool": { "d_kill": { "target": [5, 1] } } } }' })
    fst = Q.Config.file.status
    T.check(fst.ok == false and fst.path == "daily.pool.d_kill.target" and fst.why == "target"
        and Q.Config.get().exchange.perDay == 7, "invalid value: the key path is reported and no family is applied")
    r = T.cmd(admin, "admin", { op = "cfg.undo", historyId = fileHid })
    T.check(r and r.ok and Q.Config.get().exchange.perDay == 42 and fileTree("config.json").exchange.perDay == 42
        and Q.Config.file.status.ok == true, "undoing a file apply restores the settings and rewrites config.json")
    edit(nil)
    T.check(fileTree("config.json") and fileTree("config.json").custom.c1.name == "Doc", "a deleted config.json is written again")
    T.section("cfg.preview / cfg.apply / cfg.undo: changes built on an older rev are refused")
    do
        -- the panel loaded the settings, then config.json changed them (2026-10-28: an open panel still listed the old
        -- horde spots, and a spot edit there would have sent the old list back)
        local seen = T.cmd(admin, "admin", { op = "cfg.get" }).rev
        edit({ '{ "exchange": { "perDay": 6 } }' })
        local cur = Q.Store.root().config.rev
        local ch = '[{"op":"set","path":"exchange.min","value":12}]'
        r = T.cmd(admin, "admin", { op = "cfg.preview", changes = ch, rev = seen })
        T.check(cur == seen + 1 and r and r.code == CODE.CONFIG_CHANGED and r.rev == cur,
            "a preview on the rev loaded before the file change is refused with the rev in effect")
        r = T.cmd(admin, "admin", { op = "cfg.apply", changes = ch, summary = "old", rev = seen })
        T.check(r and r.code == CODE.CONFIG_CHANGED and r.rev == cur and Q.Store.root().config.rev == cur
            and Q.Config.get().exchange.min ~= 12 and Q.Config.get().exchange.perDay == 6,
            "an apply on it too: nothing written, the file's settings stay")
        r = T.cmd(admin, "admin", { op = "cfg.preview", changes = ch, rev = cur + 1 })
        T.check(r and r.code == CODE.CONFIG_CHANGED, "any rev but the one in effect is refused")
        r = T.cmd(admin, "admin", { op = "cfg.preview", changes = ch, rev = "x" })
        T.check(r and r.code == CODE.BAD_ARGS, "rev is an integer")
        r = T.cmd(admin, "admin", { op = "cfg.apply", changes = ch, summary = "new", rev = cur })
        T.check(r and r.ok and r.rev == cur + 1 and Q.Config.get().exchange.min == 12, "the rev in effect applies")
        -- an undo from a history list loaded before another write to the same path (a push moves the panel's
        -- settings on, not its list): undoing would set the newer value back (review r1, 2026-10-28)
        local hid, listRev = r.historyId, r.rev
        edit({ '{ "exchange": { "perDay": 6, "min": 13 } }' })
        r = T.cmd(admin, "admin", { op = "cfg.undo", historyId = hid, rev = listRev })
        T.check(r and r.code == CODE.CONFIG_CHANGED and r.rev == listRev + 1 and Q.Config.get().exchange.min == 13
            and Q.Store.root().config.rev == listRev + 1, "an undo from a list loaded before another write is refused: the newer value stays")
        r = T.cmd(admin, "admin", { op = "cfg.undo", historyId = hid, rev = listRev + 1 })
        T.check(r and r.ok and r.rev == listRev + 2, "on the rev in effect the undo goes through")
    end
    T.failWrites = true
    r = T.cmd(admin, "admin", { op = "cfg.apply", changes = '[{"op":"set","path":"exchange.min","value":11}]', summary = "w" })
    T.failWrites = false
    T.check(r and r.ok and Q.Config.get().exchange.min == 11 and Q.Config.file.status.why == "write",
        "a panel change still applies when config.json cannot be written; the status says so")
    T.files[DIR .. "config.json"] = { lines = { '\239\187\191{ "exchange": { "perDay": 3 } }' } }
    local revBefore = Q.Store.root().config.rev
    Q = boot({ keepGmd = true, keepFiles = true, sandbox = { AdminRoles = "admin;owner" } })
    T.check(Q.Config.get().exchange.perDay == 3 and Q.Store.root().config.rev == revBefore + 1,
        "at start a config.json edited while the server was down applies (a leading BOM is fine)")
    Q = boot({ keepGmd = true, keepFiles = true, sandbox = { AdminRoles = "admin;owner" } })
    T.check(Q.Store.root().config.rev == revBefore + 1, "a start with an unchanged config.json changes nothing")
    local mode = T.mode
    T.mode = "sp"
    local spA = Q.Store.path("config.json")
    T.world = "Other save"
    local spB = Q.Store.path("config.json")
    T.world, T.mode = "Riverside test", mode
    T.check(spA == "MinidoracatQuest/sp_Riverside_test/config.json" and spB ~= spA,
        "single player keeps config.json per save (Zomboid/Lua is shared by every save on the machine)")

    T.section("identity")
    local Q2 = boot({ steam = true })
    local a1 = T.player({ name = "carol", sid = 76561198000000032 })
    T.tick(11)
    T.check(Q2.Identity.binding("carol") ~= nil, "login binding written")
    local file = T.files["MinidoracatQuest/servertest/identity.txt"]
    T.check(file and string.find(file.lines[1], "76561198000000032", 1, true) ~= nil, "binding stored as exact SteamID text")
    T.disconnect(a1)
    local fake = T.player({ name = "carol", sid = 76561198000000099 })
    T.check(Q2.Identity.principal(fake) == nil, "SteamID mismatch has no principal")
    r = T.cmd(fake, "hello", {})
    T.check(r and r.code == CODE.IDENTITY_UNVERIFIED, "mismatched identity blocked")
    local split = T.player({ name = "dave", num = 1 })
    T.check(Q2.Identity.principal(split) == nil, "split-screen seat has no principal")
    T.check(not Q2.Stats.add(fake, "t.count", 1), "stats refuse an unverified player")
    local boundFile = T.deepcopy(T.files)
    boot({ steam = true, keepFiles = true, beforeStart = function() end })
    T.check(MinidoracatQuest.Identity.binding("carol") ~= nil, "binding survives restart")
    T.files = boundFile
    T.unreadable["MinidoracatQuest/servertest/identity.txt"] = true
    MinidoracatQuest.Identity.load()
    T.check(MinidoracatQuest.Identity.principal(T.player({ name = "erin", sid = 76561198000000005 })) == nil,
        "unreadable identity file fails closed in Steam mode")

    T.section("stats: scopes, ceiling, lazy season")
    Q = boot({})
    local bob = T.player({ name = "bob" })
    -- a player object counts only once hello made its account (the server's joining IsoPlayer is "Bob", E2E 1025g)
    T.check(not Q.Stats.add(bob, "t.count", 4) and not Q.Stats.max(bob, "t.max", 4) and Q.Store.account("bob", false) == nil,
        "a player object without an account counts nothing and makes no account")
    Q.Store.account("bob", true)   -- what hello does
    T.check(Q.Stats.add(bob, "t.count", 4), "add counts")
    T.check(not Q.Stats.add(bob, "t.count", 0) and not Q.Stats.add(bob, "t.count", -1) and not Q.Stats.add(bob, "t.count", 0 / 0),
        "zero, negative, NaN refused")
    T.check(not Q.Stats.add(bob, "no.such", 1), "unknown stat refused")
    local acc = Q.Store.account("bob", false)
    T.check(acc.total["t.count"] == 4 and acc.life["t.count"] == 4 and acc.season["t.count"] == 4, "three scopes updated")
    local ok, added = Q.Stats.add(bob, "t.count", 20)
    T.check(ok and added == 6 and acc.total["t.count"] == 10, "excess over the per-minute ceiling dropped")
    T.check(not Q.Stats.add(bob, "t.count", 3), "ceiling reached: further adds dropped")
    local overs = Q.Audit.recent(function(it) return it.kind == "over" end, 10)
    T.check(#overs == 1 and overs[1].detail.n == 17 and acc.anomalies == 1, "one audit entry per account per stat per minute")
    T.check(T.logged("OVER"), "overflow written to the audit log")
    r = T.cmd(T.player({ name = "boss", admin = true }), "admin", { op = "anom.list", days = 1 })
    T.check(r and r.ok and r.rows[1] and r.rows[1].user == "bob" and r.rows[1].ceil == 10, "anom.list returns the overflow")
    T.advance(60000)
    T.check(Q.Stats.add(bob, "t.count", 3) and acc.total["t.count"] == 13, "next minute allowed again")
    T.check(Q.Stats.max(bob, "t.max", 7) and not Q.Stats.max(bob, "t.max", 5) and acc.total["t.max"] == 7, "max keeps the best")
    T.check(not Q.Stats.add(bob, "t.max", 1), "add refuses a max stat")
    T.fire("OnCharacterDeath", bob)
    acc = Q.Store.account("bob", false)
    T.check(acc.life["t.count"] == nil and acc.total["t.count"] == 13, "death clears life only")
    -- relative: the death above may unlock achievements that already paid points
    local p0 = { season = acc.points.season, total = acc.points.total, balance = acc.points.balance }
    Q.Points.award(acc, "bob", 30, "quest", "q1")
    T.check(acc.points.season == p0.season + 30 and acc.points.total == p0.total + 30 and acc.points.balance == p0.balance + 30,
        "normal award adds all three")
    Q.Points.award(acc, "bob", 5, "import", "imp")
    T.check(acc.points.total == p0.total + 35 and acc.points.season == p0.season + 30 and acc.points.balance == p0.balance + 30,
        "import adds total only")
    Q.Points.award(acc, "bob", 7, "season", "s1")
    T.check(acc.points.balance == p0.balance + 37 and acc.points.total == p0.total + 35, "season reward adds balance only")
    T.check(not Q.Points.award(acc, "bob", 5, "bogus", "x"), "unknown kind refused")
    local bal = acc.points.balance
    T.check(not Q.Points.spend(acc, bal + 1) and Q.Points.spend(acc, 10) and acc.points.balance == bal - 10, "spend needs balance")
    T.check(Q.Points.refund(acc, 10) and acc.points.balance == bal, "refund returns balance")
    local keepTotal = acc.points.total
    Q.Store.root().season.no = 2
    acc = Q.Store.account("bob", false)
    T.check(acc.sno == 2 and count(acc.season) == 0 and acc.points.season == 0 and acc.anomalies == 0, "new season resets season fields lazily")
    T.check(acc.total["t.count"] == 13 and acc.points.total == keepTotal and acc.points.balance == bal, "lazy reset keeps total and balance")

    T.section("shard routing")
    local tag = string.format("MinidoracatQuest_A%02d", Q.Util.hash("bob") % 16)
    T.check(Q.Store.shardTag("bob") == tag and T.gmd[tag].accounts.bob ~= nil, "account stored in hash % 16 shard")
    local other
    for i = 1, 50 do
        local name = "user" .. i
        if Q.Store.shardTag(name) ~= tag then other = name break end
    end
    Q.Store.account(other, true)
    T.check(T.gmd[Q.Store.shardTag(other)].accounts[other] ~= nil and T.gmd[tag].accounts[other] == nil, "other user lands in its own shard")
    T.check(T.gmd.MinidoracatQuest.accounts == nil, "shared table holds no accounts")
    local seen = {}
    Q.Store.each(function(user) seen[user] = true end)
    T.check(seen.bob and seen[other], "Store.each walks every shard")

    T.section("player commands")
    T.cmd(bob, "hello", {})
    r = T.cmd(bob, "title", { id = "legend" })
    T.check(r and r.code == CODE.TITLE_LOCKED, "locked title refused")
    acc.titles.legend = true
    T.clearOutbox(bob)
    r = T.cmd(bob, "title", { id = "legend" })
    T.check(r and r.ok and acc.title == "legend" and T.lastOf(bob, "state").title == "legend", "owned title set, state follows")
    r = T.cmd(bob, "anon", { on = true })
    T.check(r and r.ok and acc.anon == true, "anon set")
    acc.unseen = 4
    r = T.cmd(bob, "seen", {})
    T.check(r and r.ok and acc.unseen == 0, "seen clears unseen")
    T.check(T.cmd(bob, "records", {}) == nil, "successful query sends no result")
    local rec = T.lastOf(bob, "records")
    local found = false
    for _, row in ipairs(rec.rows) do if row.stat == "t.count" and row.total == 13 then found = true end end
    T.check(found and rec.points.balance == acc.points.balance, "records lists stats and points")
    r = T.cmd(T.player({ name = "boss", admin = true, x = 123.7, y = 456.2 }), "admin", { op = "towns.here" })
    T.check(r and r.ok and r.x == 123 and r.y == 456, "towns.here returns integer square")
    r = T.cmd(T.player({ name = "boss", admin = true }), "admin", { op = "acct.view", user = "bob" })
    T.check(r and r.ok and r.points.balance == acc.points.balance and r.anomalies == 0, "acct.view summary")
    r = T.cmd(T.player({ name = "boss", admin = true }), "admin", { op = "acct.view", user = "nobody" })
    T.check(r and r.code == CODE.NOT_FOUND, "acct.view unknown user")

    T.section("rate limit and cooldown")
    local spam = T.player({ name = "spam" })
    T.cmd(spam, "hello", {})
    local before2 = #T.sentTo(spam, "state")
    T.fire("OnClientCommand", "MinidoracatQuest", "hello", spam, { protocol = 1 })
    T.check(#T.sentTo(spam, "state") == before2, "per-command cooldown drops without reply")
    T.advance(6000)
    local limited = 0
    for i = 1, 25 do
        T.advance(1)
        T.fire("OnClientCommand", "MinidoracatQuest", "seen", spam, { protocol = 1, requestId = string.format("spam-%05d", i) })
    end
    for _, res in ipairs(T.sentTo(spam, "result")) do if res.code == CODE.RATE_LIMITED then limited = limited + 1 end end
    T.check(limited >= 1, "over 20 commands in 5 s are rate limited")

    T.section("sync: delta, toasts, broadcast cap")
    local wat = T.player({ name = "wat" })
    T.cmd(wat, "hello", {})
    T.cmd(wat, "watch", { on = true })
    local wacc = Q.Store.account("wat", false)
    T.advance(1000)
    T.tick(1)   -- flush what hello/watch dirtied
    T.clearOutbox(wat)
    Q.Points.award(wacc, "wat", 10, "admin", "t")
    T.advance(1000)
    T.tick(1)
    local d = T.lastOf(wat, "delta")
    T.check(d and d.points and d.points.balance == wacc.points.balance, "watcher gets a points delta")
    Q.Sync.toast("wat", { kind = "achv", id = "a1", tier = 1, pts = 10 })
    Q.Sync.toast("wat", { kind = "achv", id = "a2", tier = 2, pts = 20 })
    T.tick(1)
    T.check(#T.sentTo(wat, "toast") == 0, "achievement toasts wait for the merge window")
    T.advance(2000)
    T.tick(1)
    local toast = T.lastOf(wat, "toast")
    T.check(toast and toast.kind == "achvMany" and toast.n == 2, "two unlocks within 2 s merge")
    T.clearOutbox()
    T.check(Q.Sync.broadcastToast({ kind = "broadcast", who = "wat", id = "a1", tier = 3 }), "first broadcast sent")
    T.check(not Q.Sync.broadcastToast({ kind = "broadcast", who = "wat", id = "a2", tier = 3 }), "second broadcast in the minute capped")
    T.check(T.lastOf(bob, "toast") ~= nil, "broadcast reaches other players")
    T.advance(60000)
    local boss = T.player({ name = "boss", admin = true })
    T.clearOutbox()
    T.check(Q.Sync.broadcastToast({ kind = "broadcast", id = "a3", tier = 3 }, "wat"), "anonymous broadcast sent")
    local seen, named = T.lastOf(bob, "toast"), T.lastOf(boss, "toast")
    T.check(seen and seen.who == nil and seen.a == nil and named and named.a == "wat",
        "an anonymous achiever is named to admins only")

    T.section("event log")
    Q.EventLog.write("quest_done", "bob", { tid = "d_kill" })
    T.advance(10000)
    T.tick(1)
    local evFile
    for path, f in pairs(T.files) do if string.find(path, "/events%-%d+%.json$") then evFile = f end end
    T.check(evFile ~= nil and string.find(evFile.lines[#evFile.lines], '"k":"quest_done"', 1, true) ~= nil, "events flushed as NDJSON")

    T.section("clock")
    local K = Q.Clock
    T.check(K.dayKey(T.now) == "2026-09-21" and K.weekday(T.now) == 1 and K.weekKey(T.now) == "2026-W39", "day/week keys at UTC+8")
    T.check(K.nextResetMs(T.now) - T.now < 86400000 and (K.nextResetMs(T.now) - K.sandboxShiftMs()) % 86400000 == 0, "next reset on the shift")
    MinidoracatEconomy = { v1 = { rewardDay = function() return "20300102", 1893542400000 + 3600000 end } }
    T.check(K.dayKey(T.now) == "2030-01-02" and K.nextResetMs(T.now) == 1893546000000, "Economy rewardDay wins, key reformatted")
    -- Economy answering like ECRewards for a fixed shift (reset hour minus timezone)
    local function econAt(shift)
        return { v1 = { rewardDay = function(ms)
            local day = math.floor((ms - shift) / 86400000)
            local y, m, d = K.civil(day)
            return string.format("%04d%02d%02d", y, m, d), (day + 1) * 86400000 + shift
        end } }
    end
    MinidoracatEconomy = nil
    local wd, wk, wr = K.weekday(T.now), K.weekKey(T.now), K.weekResetMs(T.now)
    MinidoracatEconomy = econAt(K.sandboxShiftMs())
    T.check(K.weekday(T.now) == wd and K.weekKey(T.now) == wk and K.weekResetMs(T.now) == wr,
        "Economy at the same UTC+8 reset keeps Monday weeks")
    MinidoracatEconomy = econAt(15 * 3600000)   -- reset 15:00 UTC: still Sunday's reward day
    T.check(K.dayKey(T.now) == "2026-09-20" and K.weekday(T.now) == 7 and K.weekResetMs(T.now) == K.nextResetMs(T.now),
        "week boundary follows Economy's reset")
    MinidoracatEconomy = { v1 = { rewardDay = function() return nil end } }
    T.check(K.dayKey(T.now) == "2026-09-21", "bad rewardDay falls back to sandbox")
    MinidoracatEconomy = nil

    T.section("facade")
    Q.Catalog.stats["zombie.kills"] = Q.Catalog.stats["zombie.kills"] or { id = "zombie.kills", kind = "count", ceil = 120 }
    local pack = Q.v1.registerPack({ modId = "DoctorJob",
        stats = { { id = "heals", kind = "count", board = true, ceil = 30, nameKey = "IGUI_DoctorJob_Heals" } },
        achievements = { { id = "medic", stat = "heals", category = "job", tiers = { 10, 100 }, points = { 10, 20 }, title = "medic" } },
        quests = { { id = "heal3", stat = "heals", category = "life", target = { 3, 5 }, points = 15, nameKey = "IGUI_DoctorJob_Heal3" } } })
    T.check(pack ~= nil and Q.Packs.DoctorJob.stats["DoctorJob:heals"] ~= nil, "pack registered with prefixed ids")
    T.check(Q.Packs.DoctorJob.achievements[1].titles[2] == "medic" and #Q.Packs.DoctorJob.boards == 1, "pack achievement and job board")
    local catPack = nil
    for _, p in ipairs(Q.Sync.catalog().packs) do if p.modId == "DoctorJob" then catPack = p end end
    T.check(catPack ~= nil and catPack.quests[1].tid == "DoctorJob:heal3" and catPack.quests[1].nameKey == "IGUI_DoctorJob_Heal3",
        "catalog push carries the pack quest nameKey to clients")
    T.check(pack.add(bob, "heals", 2) and Q.Store.account("bob", false).total["DoctorJob:heals"] == 2, "pack.add records progress")
    local okA, codeA = pack.add(bob, "heals", 0 / 0)
    T.check(not okA and codeA == "invalid_args", "pack.add refuses NaN")
    okA, codeA = pack.add(bob, "heals", 1001)
    T.check(not okA and codeA == "invalid_args", "pack.add refuses n over 1000")
    for _ = 1, 50 do pack.add(bob, "heals", 0.1) end
    okA, codeA = pack.add(bob, "heals", 1)
    T.check(not okA and codeA == "rate_limited", "51st call in one tick rate limited")
    T.tick(1)
    T.check(pack.add(bob, "heals", 1), "budget resets next tick")
    local nilPack, why = Q.v1.registerPack({ modId = "bad id!", stats = {} })
    T.check(nilPack == nil and why == "invalid_args", "invalid modId refused")

    T.section("single player direct path")
    Q = boot({ sp = true })
    local solo = T.player({ name = "solo" })
    sendClientCommand(solo, "MinidoracatQuest", "hello", { protocol = 1, requestId = "sp-hello-01" })
    local st = T.lastOf(solo, "state")
    T.check(st ~= nil and st.user == "solo" and st.admin == true, "SP hello answered through Client.receive, admin true")
    T.advance(400)
    r = T.cmd(solo, "admin", { op = "cfg.get" })
    T.check(r and r.ok, "SP admin op works with nil role")
    local real = Q.Store.account("solo", false).points.balance
    st.points.balance = real + 999
    T.check(Q.Store.account("solo", false).points.balance == real, "SP payload is a copy")
end
