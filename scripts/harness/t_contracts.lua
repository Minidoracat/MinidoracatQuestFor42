-- Squad contracts (Contracts.lua; contract temp/plan-group-play-1114/spec.md B1, plan points-play 1112/1113): what a
-- met contract pays a member who pulled their weight and one who did not, nothing back when it is not met, a gathering
-- that ends short or loses its leader paying every stake back (offline too), the refusals in their order, perDay and
-- the day change, a settling that fails half way never settling again, the server's down time not counting, the
-- settings check (returnPct + bonusPct <= 95), the kill path of a player without a contract, the state part, records,
-- report and event log, a spend request taken once. Then the client: the page's five states, the questions, the
-- tracker row and the toasts. t_shop_color.lua (title colour) runs its server part before the client fakes and its
-- client part with the same fixtures (kit).
return function(T)
    local MIN = 60000
    local function section(name, fn)
        T.section("contracts: " .. name)
        local ok, err = pcall(fn)
        if not ok then T.check(false, name .. " raised: " .. tostring(err)) end
    end
    local function set(Q, values)
        local list = {}
        for path, v in pairs(values) do list[#list + 1] = { op = "set", path = path, value = v } end
        return Q.Config.apply(list, "t", "admin")
    end
    local function boot(keep)
        local Q = T.boot({ sandbox = { AdminRoles = "admin" }, keepGmd = keep, keepFiles = keep })
        T.tick(2)
        -- achievement points (first blood, contract_wins I) stay out of the balances these sections count
        local award = Q.Points.award
        Q.Points.award = function(acc, user, n, kind, ...)
            if kind == "achv" then return true end
            return award(acc, user, n, kind, ...)
        end
        return Q
    end
    -- players with hello and a balance (balance nil: as the account is)
    local function players(Q, names, balance)
        local out = {}
        for i, n in ipairs(names) do
            local p = T.player{ name = n }
            T.cmd(p, "hello")
            if balance then Q.Points.award(Q.Store.account(n, false), n, balance, "admin", "t") end
            out[i] = p
        end
        return table.unpack(out)
    end
    local function acct(Q, n) return Q.Store.account(n, false) end
    local function bal(Q, n) return acct(Q, n).points.balance end
    local function kill(Q, n, k, stat, opts) return Q.Stats.add(n, stat or "zombie.kills", k, opts) end
    local function list(Q) return Q.Store.root().contracts.list end
    local function count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    local function toasts(p, ev)
        local out = {}
        for _, t in ipairs(T.sentTo(p, "toast")) do
            if t.kind == "contract" and (ev == nil or t.ev == ev) then out[#out + 1] = t end
        end
        return out
    end
    local function start(p, tpl, pay) return T.cmd(p, "contractStart", { tpl = tpl or "hunt", pay = pay or 100 }) end
    local function join(p, id, pay) return T.cmd(p, "contractJoin", { id = id, pay = pay or 100 }) end
    -- the hunt contract at perMember 10 (target 10 x members), its stake 100; sharePct 30 -> 3 kills of your own
    local function small(Q) T.check(set(Q, { ["contracts.list.hunt.perMember"] = 10 }), "hunt perMember 10") end

    section("met: who pulled their weight gets the stake half back and 30 %, the other the half only", function()
        local Q = boot()
        small(Q)
        local a, b = players(Q, { "alice", "bob" }, 1000)
        local s0a, t0a, s0b, t0b = acct(Q, "alice").points.season, acct(Q, "alice").points.total,
            acct(Q, "bob").points.season, acct(Q, "bob").points.total
        local events = {}
        local write = Q.EventLog.write
        Q.EventLog.write = function(kind, user, f)
            if kind == "contract" then events[#events + 1] = f end
            return write(kind, user, f)
        end
        local r = start(a)
        local id = r and r.id
        T.check(r and r.ok and id ~= nil and bal(Q, "alice") == 900 and acct(Q, "alice").contract == id,
            "start: 100 staked, alice in the contract")
        T.check(acct(Q, "alice").points.season == s0a and acct(Q, "alice").points.total == t0a, "the stake takes the balance only")
        r = join(b, id)
        T.check(r and r.ok and bal(Q, "bob") == 900 and list(Q)[id].size == 2 and list(Q)[id].state == "open", "bob joins: 2 of 6")
        T.check(T.cmd(b, "contractGo", { id = id }).code == "FORBIDDEN", "only the leader starts it")
        r = T.cmd(a, "contractGo", { id = id })
        local c = list(Q)[id]
        T.check(r and r.ok and c.state == "active" and c.target == 20 and c.endsAt == c.startMs + 60 * MIN,
            "Start now: the target is 10 x 2, 60 minutes")
        T.check(Q.Contracts.today(acct(Q, "alice"), T.now) == 1 and Q.Contracts.today(acct(Q, "bob"), T.now) == 1,
            "each member's day count goes up at the start")
        T.check(T.cmd(b, "contractLeave", { id = id }).code == "FORBIDDEN" and list(Q)[id] ~= nil, "no leaving once it runs")
        kill(Q, "bob", 2)
        kill(Q, "alice", 10)
        T.check(c.prog == 12 and c.members.alice == 10 and c.members.bob == 2, "everyone's kills add up")
        kill(Q, "alice", 8)
        T.check(list(Q)[id] == nil and acct(Q, "alice").contract == nil and acct(Q, "bob").contract == nil,
            "20 of 20: settled, out of the list, nobody in it")
        T.check(bal(Q, "alice") == 1000 - 100 + 50 + 30, "alice (18 kills, 3 needed): 50 back + 30 bonus")
        T.check(bal(Q, "bob") == 1000 - 100 + 50, "bob (2 kills, under 3): 50 back, no bonus")
        T.check(acct(Q, "alice").points.season == s0a + 30 and acct(Q, "alice").points.total == t0a + 30,
            "the bonus is earned: season and total too; the 50 back is not")
        T.check(acct(Q, "bob").points.season == s0b and acct(Q, "bob").points.total == t0b, "bob's season and total unchanged")
        T.check(acct(Q, "alice").total["contract.wins"] == 1 and (acct(Q, "bob").total["contract.wins"] or 0) == 0
            and acct(Q, "alice").achv.contract_wins == 1, "contract.wins and its achievement for alice only")
        local sa = acct(Q, "alice").spent
        T.check(sa[1].what == "contractBonus" and sa[1].n == 30 and sa[2].what == "contractBack" and sa[2].n == 50
            and sa[3].what == "contract" and sa[3].n == -100 and sa[3].ref == "hunt", "points history: stake, back, bonus")
        local ta, tb = toasts(a, "won")[1], toasts(b, "won")[1]
        T.check(ta and ta.full and ta.back == 50 and ta.bonus == 30 and ta.size == 2 and ta.target == 20 and ta.mins == 1,
            "alice's toast: met, 50 back, +30")
        T.check(tb and not tb.full and tb.back == 50 and tb.bonus == 0 and tb.mine == 2 and tb.need == 3,
            "bob's toast: met, 2 of the 3 needed, only 50 back")
        local day = Q.Report.row(T.now)
        T.check(day.spent.contract == 100 and day.pts.contract == 30 and day.contracts["hunt:open"] == 1
            and day.contracts["hunt:won"] == 1, "report: 100 spent net, 30 earned, one started and met")
        T.check(#events == 2 and events[1].ev == "start" and events[1].target == 20 and events[2].ev == "won"
            and events[2].prog == 20, "event log: the start and the result")
        Q.EventLog.write = write
        T.cmd(a, "records")
        T.cmd(b, "records")
        local ra, rb = T.lastOf(a, "records").contracts[1], T.lastOf(b, "records").contracts[1]
        T.check(ra and ra.won and ra.back == 50 and ra.bonus == 30 and ra.mine == 18 and rb and rb.bonus == 0 and rb.back == 50,
            "records: the last contract with this player's share")
        kill(Q, "alice", 5)
        T.check(bal(Q, "alice") == 980, "kills after it do nothing")
    end)

    section("not met: time is up, nothing comes back", function()
        local Q = boot()
        small(Q)
        local a, b = players(Q, { "alice", "bob" }, 1000)
        local id = start(a).id
        join(b, id)
        T.cmd(a, "contractGo", { id = id })
        kill(Q, "alice", 15)
        T.advance(60 * MIN)
        kill(Q, "bob", 10)
        T.check(list(Q)[id].prog == 15, "a kill at the deadline, before the tick, does not count")
        T.tick(11)
        T.check(list(Q)[id] == nil and bal(Q, "alice") == 900 and bal(Q, "bob") == 900, "time up at 15 of 20: the stakes are gone")
        local t = toasts(a, "lost")[1]
        T.check(t and t.prog == 15 and t.target == 20 and t.stake == 100, "the toast: 15/20, 100 not returned")
        T.check(Q.Report.row(T.now).contracts["hunt:lost"] == 1 and (acct(Q, "alice").total["contract.wins"] or 0) == 0,
            "report: not met; no contract.wins")
    end)

    section("gathering ends short: every stake back, offline too", function()
        local Q = boot()
        T.check(set(Q, { ["contracts.minSize"] = 3 }), "minSize 3")
        local a, b = players(Q, { "alice", "bob" }, 1000)
        local id = start(a).id
        join(b, id)
        T.disconnect(b)
        T.advance(9 * MIN)
        T.tick(11)
        T.check(list(Q)[id] ~= nil and list(Q)[id].state == "open", "still gathering before joinMin")
        T.advance(MIN)
        T.tick(11)
        T.check(list(Q)[id] == nil and bal(Q, "alice") == 1000 and bal(Q, "bob") == 1000 and acct(Q, "bob").contract == nil,
            "10 minutes with 2 of 3: called off, both 100 back (bob offline)")
        local t = toasts(a, "refund")[1]
        T.check(t and t.why == "small" and t.pts == 100 and acct(Q, "alice").spent[1].what == "contractRefund",
            "the toast says why; the history has the refund")
        T.check(Q.Contracts.today(acct(Q, "alice"), T.now) == 0, "a contract that never ran does not count for the day")
        T.check(Q.Report.row(T.now).spent.contract == 0, "report: the refunds come off the contract column")
    end)

    section("the leader leaves: called off for everyone; a member leaving gets the stake back", function()
        local Q = boot()
        local a, b, c = players(Q, { "alice", "bob", "carol" }, 1000)
        local id = start(a).id
        join(b, id)
        join(c, id)
        local r = T.cmd(b, "contractLeave", { id = id })
        T.check(r and r.ok and bal(Q, "bob") == 1000 and list(Q)[id].size == 2 and list(Q)[id].members.bob == nil
            and acct(Q, "bob").contract == nil, "bob leaves: 100 back, 2 left")
        T.check(T.cmd(b, "contractLeave", { id = id }).code == "NOT_FOUND", "not in it any more")
        r = T.cmd(a, "contractLeave", { id = id })
        T.check(r and r.ok and list(Q)[id] == nil and bal(Q, "alice") == 1000 and bal(Q, "carol") == 1000,
            "the leader leaves: called off, everyone paid back")
        local tc = toasts(c, "refund")[1]
        T.check(tc and tc.why == "leader" and tc.pts == 100 and #toasts(b, "refund") == 0, "carol is told why; bob had left")
    end)

    section("the refusals, in order; nothing taken", function()
        local Q = boot()
        local a, b, c, d = players(Q, { "alice", "bob", "carol", "dave" }, 1000)
        T.check(set(Q, { ["contracts.enabled"] = false }), "off")
        T.check(start(a).code == "CONTRACT_OFF" and join(b, 1).code == "CONTRACT_OFF" and bal(Q, "alice") == 1000, "off: CONTRACT_OFF")
        T.check(set(Q, { ["contracts.enabled"] = true, ["contracts.list.melee.enabled"] = false }), "on, melee off")
        T.check(start(a, "nope").code == "NOT_FOUND" and start(a, "melee", 150).code == "NOT_FOUND"
            and join(b, 99).code == "NOT_FOUND", "no such template, one switched off, no such contract: NOT_FOUND")
        T.check(start(a, "hunt", 99).code == "PRICE_CHANGED" and bal(Q, "alice") == 1000, "not the stake: PRICE_CHANGED")
        acct(Q, "dave").points.balance = 60
        T.check(start(d).code == "NOT_ENOUGH_POINTS" and bal(Q, "dave") == 60 and list(Q)[1] == nil,
            "60 points: NOT_ENOUGH_POINTS, nothing opened")
        local id = start(a).id
        T.check(start(a).code == "CONTRACT_IN" and join(a, id).code == "CONTRACT_IN" and bal(Q, "alice") == 900,
            "already in one: CONTRACT_IN")
        T.check(join(b, id, 150).code == "PRICE_CHANGED" and bal(Q, "bob") == 1000, "join with another price: PRICE_CHANGED")
        T.check(set(Q, { ["contracts.maxActive"] = 1 }), "maxActive 1")
        T.check(start(b).code == "CONTRACT_MAX" and bal(Q, "bob") == 1000, "one live already: CONTRACT_MAX")
        T.check(T.cmd(a, "contractGo", { id = id }).code == "CONTRACT_SMALL" and list(Q)[id].state == "open",
            "alone: CONTRACT_SMALL")
        join(b, id)
        T.check(set(Q, { ["contracts.maxSize"] = 2 }), "maxSize 2")
        T.check(join(c, id).code == "CONTRACT_FULL" and bal(Q, "carol") == 1000, "2 of 2: CONTRACT_FULL")
        T.check(set(Q, { ["contracts.maxSize"] = 3, ["contracts.maxActive"] = 10 }), "maxSize 3")
        T.check(join(c, id).ok and list(Q)[id].state == "active" and list(Q)[id].target == 450,
            "the last place taken starts it at once (3 x 150)")
        T.check(join(d, id).code == "NOT_FOUND", "running: not gathering any more")
    end)

    section("three a day, then the next day", function()
        local Q = boot()
        T.check(set(Q, { ["contracts.list.hunt.perMember"] = 1 }), "hunt perMember 1")
        local a, b = players(Q, { "alice", "bob" }, 5000)
        T.now = Q.Clock.nextResetMs(T.now) + 60000
        for i = 1, 3 do
            local id = start(a).id
            join(b, id)
            T.cmd(a, "contractGo", { id = id })
            kill(Q, "alice", 2)
            T.check(list(Q)[id] == nil, "contract " .. i .. " met")
        end
        T.check(start(a).code == "CONTRACT_DAY" and start(b).code == "CONTRACT_DAY" and bal(Q, "alice") == 5000 - 3 * 100 + 3 * 80,
            "a fourth today: CONTRACT_DAY, nothing taken")
        T.now = Q.Clock.nextResetMs(T.now) + 1000
        T.check(start(a).ok, "the next day (the daily quests' reset): open again")
    end)

    section("a settling that fails half way is never settled again", function()
        local Q = boot()
        small(Q)
        local a, b = players(Q, { "alice", "bob" }, 1000)
        local id = start(a).id
        join(b, id)
        T.cmd(a, "contractGo", { id = id })
        local unpay, calls = Q.Points.unpay, 0
        Q.Points.unpay = function(acc, user, ...)
            calls = calls + 1
            if user == "bob" then error("disk full") end
            return unpay(acc, user, ...)
        end
        kill(Q, "bob", 5)
        kill(Q, "alice", 15)
        T.check(list(Q)[id] == nil and acct(Q, "alice").contract == nil and acct(Q, "bob").contract == nil and calls == 2,
            "the error came in the middle: the contract is already out of the list")
        Q.Points.unpay = unpay
        local a0, b0 = bal(Q, "alice"), bal(Q, "bob")
        T.advance(61 * MIN)
        T.tick(11)
        kill(Q, "alice", 5)
        T.check(bal(Q, "alice") == a0 and bal(Q, "bob") == b0 and #toasts(a, "won") == 1 and #toasts(a, "lost") == 0,
            "no second settling: not by the tick, not by more kills")
    end)

    section("the server's down time does not count", function()
        local Q = boot()
        small(Q)
        local a, b, c = players(Q, { "alice", "bob", "carol" }, 1000)
        local id = start(a).id
        join(b, id)
        T.cmd(a, "contractGo", { id = id })
        local gid = start(c).id
        T.advance(5 * MIN)
        T.tick(11)
        local left, gleft = list(Q)[id].endsAt - T.now, list(Q)[gid].openUntil - T.now
        T.now = T.now + 3 * 3600000   -- down for 3 hours
        Q = boot(true)
        local c2, g2 = list(Q)[id], list(Q)[gid]
        T.check(c2 ~= nil and c2.state == "active" and math.abs((c2.endsAt - T.now) - left) <= 2000,
            "running: the same time left after the restart")
        T.check(g2 ~= nil and g2.state == "open" and math.abs((g2.openUntil - T.now) - gleft) <= 2000,
            "gathering: the same time to join after the restart")
        a, b = players(Q, { "alice", "bob" })
        kill(Q, "alice", 20)
        T.check(list(Q)[id] == nil and bal(Q, "alice") == 980, "met after the restart, paid")
    end)

    section("the settings check: what goes back stays under the stake", function()
        local Q = boot()
        local ok, code, detail = set(Q, { ["contracts.returnPct"] = 70, ["contracts.bonusPct"] = 30 })
        T.check(not ok and code == "BAD_CONFIG" and detail.why == "contractPct", "70 + 30 = 100: refused (contractPct)")
        ok = set(Q, { ["contracts.returnPct"] = 66, ["contracts.bonusPct"] = 30 })
        T.check(not ok, "66 + 30 = 96: refused")
        T.check(set(Q, { ["contracts.returnPct"] = 65, ["contracts.bonusPct"] = 30 }), "65 + 30 = 95: taken")
        ok, code, detail = set(Q, { ["contracts.minSize"] = 5, ["contracts.maxSize"] = 4 })
        T.check(not ok and detail.why == "contractSize", "minSize over maxSize: refused")
        T.check(not set(Q, { ["contracts.perDay"] = 21 }) and not set(Q, { ["contracts.list.long.limitMin"] = 4 })
            and not set(Q, { ["contracts.list.long.stake"] = 0 }), "out of range: refused")
        T.check(Q.Config.get().contracts.returnPct == 65, "the refused ones changed nothing")
    end)

    section("the kill path of a player without a contract", function()
        local Q = boot()
        small(Q)
        local a, b, c = players(Q, { "alice", "bob", "carol" }, 1000)
        local id = start(a).id
        join(b, id)
        T.cmd(a, "contractGo", { id = id })
        local real = Q.Store.root().contracts
        local reads = 0
        Q.Store.root().contracts = setmetatable({}, { __index = function(_, k) reads = reads + 1; return real[k] end,
            __newindex = real })
        Q.Sync.dirtyMap = {}
        kill(Q, "carol", 5)
        T.check(reads == 0 and real.list[id].prog == 0, "carol has no contract: the contracts table is not even read")
        T.check(Q.Sync.dirtyMap.carol == nil or not Q.Sync.dirtyMap.carol.contracts, "and nothing is marked to send")
        Q.Store.root().contracts = real
        kill(Q, "alice", 3, "zombie.kills.melee")
        kill(Q, "alice", 3, nil, { quiet = true })
        T.check(real.list[id].prog == 0, "another stat or a quiet add (import) does not count")
    end)

    section("what players see: the state part, names, the pushes", function()
        local Q = boot()
        small(Q)
        local a, b, c = players(Q, { "alice", "bob", "carol" }, 1000)
        local adm = T.player{ name = "root", admin = true }
        T.cmd(adm, "hello")
        acct(Q, "alice").anon = true
        local id = start(a).id
        local st = Q.Contracts.state(acct(Q, "carol"), "carol", T.now)
        T.check(st.on and st.perDay == 3 and #st.tpls == 3 and st.tpls[1].id == "hunt" and st.tpls[2].id == "melee"
            and st.tpls[3].id == "long" and st.tpls[1].perMember == 10, "templates in their fixed order with today's numbers")
        T.check(#st.open == 1 and st.open[1].id == id and st.open[1].leader.anon and st.open[1].leader.n == nil
            and st.open[1].leader.a == nil and st.mine == nil, "an anonymous leader shows no name")
        st = Q.Contracts.state(acct(Q, "root"), "root", T.now)
        T.check(st.open[1].leader.a == "alice", "admins get the name")
        join(b, id)
        st = Q.Contracts.state(acct(Q, "bob"), "bob", T.now)
        T.check(#st.open == 0 and st.mine and st.mine.state == "open" and st.mine.members[2].me and st.mine.members[1].lead
            and st.mine.members[1].anon, "my contract: me, the leader, in order")
        T.cmd(b, "watch", { on = true })
        T.cmd(c, "watch", { on = true })
        T.cmd(a, "contractGo", { id = id })
        T.tick(11)
        T.clearOutbox()
        kill(Q, "bob", 3)
        T.tick(11)
        local function carried(p)
            -- a delta, or the full state when something else changed too (the first kill's achievement)
            for _, m in ipairs(T.outbox[p.name] or {}) do
                if (m.command == "delta" or m.command == "state") and m.args.contracts ~= nil then return m.args.contracts end
            end
            return nil
        end
        local db = carried(b)
        T.check(db and db.mine and db.mine.prog == 3, "progress goes to the members")
        T.check(carried(c) == nil, "not to others with the window open")
    end)

    section("a spend request is run at most once", function()
        local Q = boot()
        local a, b = players(Q, { "alice", "bob" }, 1000)
        local acc = acct(Q, "alice")
        local seq, rid = acc.spendSeq or 0, T.newRequestId()
        local r1 = T.cmd(a, "contractStart", { tpl = "hunt", pay = 100, seq = seq }, rid)
        local r2 = T.cmd(a, "contractStart", { tpl = "hunt", pay = 100, seq = seq }, rid)
        T.check(r1.ok and r2.ok and r2.replay and bal(Q, "alice") == 900 and count(list(Q)) == 1, "the same packet: one stake")
        local id = r1.id
        T.cmd(a, "contractLeave", { id = id })
        local r3 = T.cmd(a, "contractStart", { tpl = "hunt", pay = 100, seq = seq })
        T.check(r3.code == "STALE" and bal(Q, "alice") == 1000 and count(list(Q)) == 0, "a new request on the old screen: STALE")
        local s = acct(Q, "bob").spendSeq or 0
        start(a)
        local id2 = next(list(Q))
        local j1 = T.cmd(b, "contractJoin", { id = id2, pay = 100, seq = s })
        local j2 = T.cmd(b, "contractJoin", { id = id2, pay = 100, seq = s })
        T.check(j1.ok and j2.code == "STALE" and bal(Q, "bob") == 900, "join twice from one screen: one stake")
    end)

    section("Points.unpay: the report column follows what was paid back", function()
        local Q = boot()
        local _ = players(Q, { "alice" }, 1000)
        local acc = acct(Q, "alice")
        Q.Points.unpay(acc, "alice", 40, "hordeRefund", nil)
        Q.Points.unpay(acc, "alice", 10, "contractRefund", "hunt")
        Q.Points.unpay(acc, "alice", 5, "contractBack", "hunt")
        local sp = Q.Report.row(T.now).spent
        T.check(sp.horde == -40 and sp.contract == -15 and sp.contractRefund == nil, "hordeRefund -> horde, contract* -> contract")
    end)

    local color = dofile("scripts/harness/t_shop_color.lua")
    color.server(T)

    -- ===== client: fakes as t_client_shop.lua; the globals are put back at the end =====
    local check = T.check
    local saved = { ISUIElement = ISUIElement, ISPanel = ISPanel, getTextManager = getTextManager, UIFont = UIFont,
        getText = getText, getCore = getCore, MinidoracatUI = MinidoracatUI }
    local Base = {}
    Base.__index = Base
    for k, f in pairs({ initialise = function() end, setX = function(s, x) s.x = x end, setY = function(s, y) s.y = y end,
        getX = function(s) return s.x end, getY = function(s) return s.y end, setWidth = function(s, w) s.width = w end,
        setHeight = function(s, h) s.height = h end, setVisible = function(s, v) s.visible = v end,
        isVisible = function(s) return s.visible ~= false end, setTooltip = function(s, t) s.tooltip = t end,
        setEnabled = function(s, b) s.enabled = b end, addToUIManager = function() end, bringToTop = function() end,
        addChild = function(s, c) s.children = s.children or {}; s.children[#s.children + 1] = c; c.parent = s end }) do
        Base[k] = f
    end
    local function class(parent)
        local cls = setmetatable({}, { __index = parent })
        cls.__index = cls
        function cls:derive() return class(self) end
        function cls:new(x, y, w, h) return setmetatable({ x = x, y = y, width = w, height = h }, self) end
        return cls
    end
    ISUIElement, ISPanel = class(Base), class(Base)
    UIFont = { Small = "Small", Medium = "Medium" }
    getTextManager = function()
        return { MeasureStringX = function(_, _, s) return #tostring(s) * 7 end, getFontHeight = function() return 14 end }
    end
    getCore = function() return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end } end
    local function widget(extra)
        local Wd = setmetatable(extra or {}, { __index = Base })
        Wd.__index = Wd
        return function(opts)
            return setmetatable({ opts = opts, x = opts.x or 0, y = opts.y or 0, width = opts.width or 80, height = opts.height or 20 }, Wd)
        end
    end
    local button = widget({ setTitle = function(self, s) self.opts.title = s end,
        fitWidth = function(self) self.width = #tostring(self.opts.title) * 7 + 20 end, setActive = function(self, b) self.active = b end })
    local dialogs, shown = {}, {}
    local UI = {
        API_MAJOR = 1, API_REVISION = 22,
        CAPABILITIES = { window = true, controls = true, dialog = true, textWrap = true, toast = true },
        Text = { fit = function(s) return s end, wrap = function(s)
            local out = {}
            for line in string.gmatch(s .. "\n", "(.-)\n") do out[#out + 1] = line end
            return out
        end },
        Button = { new = function(opts) local b = button(opts); b.target, b.onclick, b.style = opts.target, opts.onClick, opts.style; return b end },
        ScrollPanel = { new = widget({ contentWidth = function(self) return self.width - 12 end, _scrollPanel = true }) },
        Dialog = { show = function(opts) dialogs[#dialogs + 1] = opts end },
        Toast = { show = function(o) shown[#shown + 1] = o end },
    }
    local colors = setmetatable({}, { __index = function(_, k) return { r = 1, g = 1, b = 1, a = 1, token = k } end })
    UI.Theme = { create = function() return { colors = colors } end }
    MinidoracatUI = { v1 = UI }
    getText = function(key, ...)
        local s = key
        for i = 1, select("#", ...) do s = s .. "|" .. tostring((select(i, ...))) end
        return s
    end
    local MQ = T.bootClient()
    local C, D, W = MQ.Client, MQ.Draw, MQ.Window
    local errors = {}
    C.log = function(m) errors[#errors + 1] = m end
    T.player({ name = "alice" })
    local K = MQ.Contract
    local kit = {}
    function kit.push(cmd, args) T.fire("OnServerCommand", K.MODULE, cmd, args) end
    function kit.lastSent() return T.clientSent[#T.clientSent] end
    function kit.answer(ok) local d = table.remove(dialogs); d.onResult(ok) end
    function kit.press(b) b.onclick(b.target, b) end
    function kit.newPage()
        local p = { UI = UI, theme = { colors = colors }, parent = ISPanel:new(0, 0, 640, 480), width = 640, height = 480 }
        D.scrollPage(p)
        return p
    end
    function kit.btn(p, key) local b = p.pool.items[key]; return (b ~= nil and b.visible ~= false) and b or nil end
    function kit.drew(p, frag)
        for i = 1, p.canvas.n do
            local s = p.canvas.ops[i].s
            if type(s) == "string" and string.find(s, frag, 1, true) then return true end
        end
        return false
    end
    -- a full state: o.balance, o.contracts, o.titleColor, o.title, o.pins, o.spent
    function kit.state(o)
        kit.push("state", { v = 1, user = "alice", now = T.now, points = { season = 0, total = 0, balance = o.balance or 1000 },
            spendSeq = math.max(5, C.spendSeq()), pins = o.pins or {}, trk = {}, achv = {}, titles = o.titles or {},
            title = o.title, titleColor = o.titleColor, contracts = o.contracts, spent = o.spent,
            exchange = { available = false } })
    end
    kit.dialogs, kit.shown, kit.UI, kit.errors = dialogs, shown, UI, errors
    local push, lastSent, answer, press, btn, drew, state = kit.push, kit.lastSent, kit.answer, kit.press, kit.btn, kit.drew, kit.state
    local PC, H, E = MQ.PageContracts, MQ.Hud, MQ.Entry
    local function navHas(id)
        for _, g in ipairs(W.navGroups()) do
            for _, it in ipairs(g.items) do if it.id == id then return true end end
        end
        return false
    end
    local TPLS = { { id = "hunt", stake = 100, perMember = 150, limitMin = 60 }, { id = "melee", stake = 150, perMember = 100, limitMin = 60 },
        { id = "long", stake = 250, perMember = 400, limitMin = 120 } }
    local function part(o)
        local ct = { on = true, perDay = 3, today = 1, returnPct = 50, bonusPct = 30, sharePct = 30, joinMin = 10, minSize = 2,
            maxSize = 6, tpls = TPLS, open = {} }
        for k, v in pairs(o or {}) do ct[k] = v end
        return ct
    end

    T.section("contracts: the page, no contract of mine")
    state({ balance = 210, contracts = part({ open = { { id = 7, tpl = "hunt", size = 2, leader = { n = "Kate" },
        openUntil = T.now + 440000, stake = 100, perMember = 150, limitMin = 60, returnPct = 50, bonusPct = 30, sharePct = 30 } } }) })
    check(PC.shown() and navHas("contracts"), "contracts on: the page is in the nav")
    local pg = kit.newPage()
    PC.layout(pg)
    check(btn(pg, "start:hunt") and btn(pg, "start:melee") and btn(pg, "start:long") == nil and drew(pg, "IGUI_MQ_UI_PointsShort|40"),
        "Start... where the balance covers the stake; Long haul: 40 points short, no button")
    check(drew(pg, "IGUI_MQ_Contract_Sub_melee|60|100") and drew(pg, "IGUI_MQ_Contract_Stake|250")
        and drew(pg, "IGUI_MQ_Contract_Rule_Kills") and drew(pg, "IGUI_MQ_Contract_TodayLeft|2"),
        "each template: what to do, the stake; the kill rule; contracts left today")
    check(btn(pg, "join:7") and drew(pg, "IGUI_MQ_Contract_Size|IGUI_MQ_Contract_hunt|2|6")
        and drew(pg, "IGUI_MQ_Contract_LeadIn|Kate|"), "a squad gathering: size, leader, when it starts, Join...")
    local sent0 = #T.clientSent
    press(btn(pg, "start:hunt"))
    local d = dialogs[#dialogs]
    check(#T.clientSent == sent0 and d.title == "IGUI_MQ_Contract_AskStart|IGUI_MQ_Contract_hunt"
        and d.confirmText == "IGUI_MQ_Contract_StartConfirm|100", "Start... asks first")
    for _, frag in ipairs({ "IGUI_MQ_Contract_AskStake|100|50|30", "IGUI_MQ_Contract_AskShare|30|45|50", "IGUI_MQ_Contract_AskLose",
        "IGUI_MQ_Contract_Rule_Kills", "IGUI_MQ_Contract_AskToday|2", "IGUI_MQ_UI_BalanceAfter|210|110" }) do
        check(string.find(d.text, frag, 1, true) ~= nil, "the question says " .. frag)
    end
    answer(false)
    check(#T.clientSent == sent0, "No sends nothing")
    press(btn(pg, "start:hunt"))
    answer(true)
    check(lastSent().command == "contractStart" and lastSent().args.tpl == "hunt" and lastSent().args.pay == 100
        and lastSent().args.seq == C.spendSeq(), "Yes sends contractStart { tpl, pay, seq }")
    C.pending = {}
    pg.spendRid = nil
    press(btn(pg, "join:7"))
    d = dialogs[#dialogs]
    check(d.title == "IGUI_MQ_Contract_AskJoin|IGUI_MQ_Contract_hunt" and d.confirmText == "IGUI_MQ_Contract_JoinConfirm|100",
        "Join... asks with the squad's stake")
    answer(true)
    check(lastSent().command == "contractJoin" and lastSent().args.id == 7 and lastSent().args.pay == 100, "Yes sends contractJoin")
    C.pending = {}
    pg.spendRid = nil
    state({ balance = 1000, contracts = part({ today = 3 }) })
    PC.layout(pg)
    check(btn(pg, "start:hunt") == nil and drew(pg, "IGUI_MQ_Contract_DayUsed|3") and drew(pg, "IGUI_MQ_Contract_OpenNone"),
        "three today: no Start, says so")
    state({ contracts = part({ on = false }) })
    check(not PC.shown(), "off and not in one: not in the nav")

    T.section("contracts: the page, my squad gathering and running")
    local members = { { me = true, k = 0, lead = true } }
    local mine = { id = 3, tpl = "hunt", state = "open", size = 1, lead = true, openUntil = T.now + 440000, stake = 100,
        perMember = 150, limitMin = 60, returnPct = 50, bonusPct = 30, sharePct = 30, members = members }
    state({ contracts = part({ mine = mine }) })
    PC.layout(pg)
    check(btn(pg, "go") == nil and drew(pg, "IGUI_MQ_Contract_NeedMore|2") and btn(pg, "leave")
        and drew(pg, "IGUI_MQ_Contract_Gathering") and btn(pg, "start:hunt") == nil, "alone: no Start now, how many it needs; Leave")
    members[2] = { n = "Bob", k = 0 }
    mine.size = 2
    state({ contracts = part({ mine = mine }) })
    PC.layout(pg)
    check(btn(pg, "go") and drew(pg, "IGUI_MQ_Contract_TargetNow|2|IGUI_MQ_Contract_Goal_hunt|60|300")
        and drew(pg, "IGUI_MQ_Contract_MembersStaked|IGUI_MQ_Contract_Leader|IGUI_MQ_Contract_You"), "two: Start now; the target at 2")
    press(btn(pg, "go"))
    check(lastSent().command == "contractGo" and lastSent().args.id == 3 and lastSent().args.seq == nil, "Start now sends contractGo")
    C.pending = {}
    pg.actRid = nil
    press(btn(pg, "leave"))
    check(lastSent().command == "contractLeave" and lastSent().args.id == 3, "Leave sends contractLeave")
    C.pending = {}
    pg.actRid = nil
    mine.lead = false
    state({ contracts = part({ mine = mine }) })
    PC.layout(pg)
    check(btn(pg, "go") == nil and btn(pg, "leave") and drew(pg, "IGUI_MQ_Contract_OpenNote"), "a member: no Start now")
    mine.state, mine.target, mine.prog, mine.endsAt = "active", 450, 212, T.now + 2468000
    members[1].k, members[2].k = 88, 79
    state({ contracts = part({ mine = mine }), pins = { "d1" } })
    PC.layout(pg)
    check(drew(pg, "IGUI_MQ_Contract_Running") and drew(pg, "IGUI_MQ_Contract_Kills|212|450")
        and drew(pg, "IGUI_MQ_Contract_Member|IGUI_MQ_Contract_You|88") and btn(pg, "leave") == nil, "running: kills, everyone's share")

    T.section("contracts: the tracker row")
    local rows = H.rows(C.state, C.defs())
    local cr = rows[1]
    check(cr and cr.contract and cr.tag == "IGUI_MQ_Contract_Tag" and cr.name == "IGUI_MQ_Contract_hunt" and cr.prog == 212
        and cr.target == 450 and cr.time == "IGUI_MQ_UI_Left|41:08", "running: a row with its countdown")
    check(H.wanted() and #H.rows({ contracts = part({ mine = mine }) }, C.defs()) == 1, "the panel shows for it with no pin")
    check(H.fitWidth({ cr }) >= math.min(H.width(),
        2 * H.PAD + D.chipW(cr.tag) + 6 + D.textW(cr.name) + 8 + D.textW("IGUI_MQ_UI_Left|00:00:00")),
        "the panel is wide enough for the name and the longest countdown (up to its cap)")
    mine.state = "open"
    check(H.contractRow({ contracts = part({ mine = mine }) }) == nil, "gathering: no row")
    mine.state = "active"

    T.section("contracts: toasts and recent contracts")
    local t1, b1 = E.toastText({ kind = "contract", ev = "won", tpl = "hunt", size = 3, mins = 52, target = 450, back = 50,
        bonus = 30, mine = 88, need = 45, full = true })
    local _, b2 = E.toastText({ kind = "contract", ev = "won", tpl = "hunt", back = 50, bonus = 0, mine = 12, need = 45, full = false })
    local t3, b3 = E.toastText({ kind = "contract", ev = "lost", tpl = "hunt", prog = 391, target = 450, stake = 100 })
    local t4, b4 = E.toastText({ kind = "contract", ev = "refund", tpl = "long", pts = 250, why = "leader" })
    check(t1 == "IGUI_MQ_Contract_ToastWon|IGUI_MQ_Contract_hunt" and b1 == "IGUI_MQ_Contract_ToastWonBody|3|52|450|50|30",
        "met with your share: 50 back, +30")
    check(b2 == "IGUI_MQ_Contract_ToastWonShort|12|45|50", "met without: only 50 back")
    check(t3 == "IGUI_MQ_Contract_ToastLost|IGUI_MQ_Contract_hunt" and b3 == "IGUI_MQ_Contract_ToastLostBody|391|450|100",
        "not met: the stake is lost")
    check(t4 == "IGUI_MQ_Contract_ToastRefund|IGUI_MQ_Contract_long" and b4 == "IGUI_MQ_Contract_ToastRefund_leader|250",
        "called off by the leader: paid back")
    C.records = { rows = {}, contracts = { { at = T.now, tpl = "hunt", size = 3, won = true, back = 50, bonus = 30 },
        { at = T.now, tpl = "long", size = 2, won = false, prog = 618, target = 800 } } }
    state({ contracts = part({}) })
    PC.layout(pg)
    check(drew(pg, "IGUI_MQ_Contract_ResWon") and drew(pg, "IGUI_MQ_Contract_ResBonus|50|30") and drew(pg, "IGUI_MQ_Contract_ResLost")
        and drew(pg, "IGUI_MQ_UI_Progress|618|800"), "recent contracts: met with what came back, not met with how far")
    local spentPage = kit.newPage()
    state({ spent = { { at = T.now, what = "contractBonus", n = 30, ref = "hunt" }, { at = T.now - 1, what = "contract", n = -100, ref = "hunt" } } })
    MQ.PageExchange.layout(spentPage)
    check(drew(spentPage, "IGUI_MQ_UI_LogContractBonus|IGUI_MQ_Contract_hunt") and drew(spentPage, "IGUI_MQ_UI_LogContract|IGUI_MQ_Contract_hunt"),
        "points history names the contract")

    color.client(T, kit)
    check(#errors == 0, "contracts client ran clean " .. tostring(errors[1]))
    for k, v in pairs(saved) do _G[k] = v end
end
