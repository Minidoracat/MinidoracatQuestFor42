-- MinidoracatQuest/PageContracts.lua: the Squad contracts page (plan points-play 2026-11-12 section 2, its five states;
--   texts of revision 1113). No contract of mine: the templates (Start..., or how many points are missing) and the
--   squads gathering (Join...). Gathering: the members, the target at the size now, Start now (the leader) and Leave.
--   Running: time left, the kills against the target, every member's kills. The result comes as a toast
--   (P.toastText), and stays in Recent contracts (records.contracts, Contracts.recent). Start and Join ask first
--   (Draw.askSpend): the stake, what comes back when met, the share rule, nothing back otherwise, no leaving once it
--   runs, the contracts left today. In the nav while contracts are on or the player is in one (state.contracts).
--   The tracker row of a running contract is Hud.contractRow.

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageContracts or {}
Q.PageContracts = P

local PAD, GAP = D.PAD, D.GAP

local function part(s) return type(s) == "table" and type(s.contracts) == "table" and s.contracts or nil end

function P.shown()
    local ct = part(C.state)
    return ct ~= nil and (ct.on == true or ct.mine ~= nil)
end

function P.name(tpl) return getText("IGUI_MQ_Contract_" .. tostring(tpl)) end

-- a member as the server named them (Contracts.state: me / anonymous, the real name only to admins / n)
function P.who(m)
    if type(m) ~= "table" then return "" end
    if m.me then return getText("IGUI_MQ_Contract_You") end
    if m.anon then return m.a ~= nil and getText("IGUI_MQ_UI_AnonReal", m.a) or getText("IGUI_MQ_UI_Anonymous") end
    return tostring(m.n)
end

-- what a met contract gives back to a member: { back, bonus, need } (same rounding as the server's Contracts.finish)
function P.payout(c)
    local stake = tonumber(c.stake) or 0
    return { back = math.floor(stake * (tonumber(c.returnPct) or 0) / 100),
        bonus = math.floor(stake * (tonumber(c.bonusPct) or 0) / 100),
        need = math.ceil((tonumber(c.perMember) or 0) * (tonumber(c.sharePct) or 0) / 100) }
end

-- ===== start / join: asked first (review 1112: no stake without a question) =====
function P.ask(page, join, c, args, cmd)
    local ct = part(C.state) or {}
    local stake, pay = tonumber(c.stake) or 0, P.payout(c)
    local text = table.concat({
        getText("IGUI_MQ_Contract_AskStake", D.num(stake), D.num(pay.back), D.num(pay.bonus)),
        getText("IGUI_MQ_Contract_AskShare", tostring(c.sharePct or 0), D.num(pay.need), D.num(pay.back)),
        getText("IGUI_MQ_Contract_AskLose"),
        getText("IGUI_MQ_Contract_Rule_Kills"),
        getText("IGUI_MQ_Contract_AskToday", tostring(math.max(0, (tonumber(ct.perDay) or 0) - (tonumber(ct.today) or 0)))),
        D.balanceAfter(stake),
    }, "\n")
    D.askSpend(page, "spendRid", { title = getText(join and "IGUI_MQ_Contract_AskJoin" or "IGUI_MQ_Contract_AskStart", P.name(c.tpl or c.id)),
        text = text, confirm = getText(join and "IGUI_MQ_Contract_JoinConfirm" or "IGUI_MQ_Contract_StartConfirm", D.num(stake)) },
        cmd, args)
end

function P.onStart(page, btn)
    local t, ct = btn.tpl, part(C.state) or {}
    -- a new contract copies today's percentages (Contracts.start)
    local c = { tpl = t.id, stake = t.stake, perMember = t.perMember, returnPct = ct.returnPct, bonusPct = ct.bonusPct,
        sharePct = ct.sharePct }
    P.ask(page, false, c, { tpl = t.id, pay = t.stake }, "contractStart")
end

function P.onJoin(page, btn)
    local o = btn.open
    P.ask(page, true, o, { id = o.id, pay = o.stake }, "contractJoin")
end

-- leaving and starting take no points: plain requests, the reply's state redraws the page
local function act(page, cmd, args)
    if C.isPending(page.actRid) then return end
    page.actRid = C.send(cmd, args, function(r)
        page.actRid = nil
        if not r.ok then D.toast(D.codeText(r.code), "", nil) end
        page.dirty = true
    end)
    page.dirty = true
end
function P.onLeave(page, btn) act(page, "contractLeave", { id = btn.internal }) end
function P.onGo(page, btn) act(page, "contractGo", { id = btn.internal }) end

-- ===== a list of { name, sub, price, btn | short }: the price right-aligned, the action at the right (under the text
-- when it is wider than 35 % of the list, as the Points page's title list) =====
local function listRows(b, x, y, w, rows)
    local lh = D.fontH()
    local ptsW, actW = 0, 0
    for _, r in ipairs(rows) do
        r.actW = r.btn ~= nil and r.btn.width or (r.short ~= nil and D.textW(r.short) or 0)
        ptsW, actW = math.max(ptsW, D.textW(r.price)), math.max(actW, r.actW)
    end
    local below = actW > w * 0.35
    local ptsR = x + w - 8 - (below and 0 or actW + 12)
    local nameW = ptsR - ptsW - 12 - (x + 8)
    local L = b:list(x, y, w)
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        local ny = b:para(x + 8, y + 4, r.name, nameW, "text")
        ny = b:para(x + 8, ny, r.sub, nameW, "textMuted")
        b:textRight(ptsR, y + 4, r.price, D.EXTRA.gold)
        local ay, ax = y + 4, x + w - 8 - r.actW
        if below then ay, ax = ny + 2, x + 8 end
        local bottom = ay + lh
        if r.btn ~= nil then
            r.btn:setX(ax)
            r.btn:setY(ay - 2)
            bottom = ay - 2 + r.btn.height
        elseif r.short ~= nil then
            b:text(ax, ay, r.short, "textMuted")
        end
        y = math.max(ny, bottom) + 4
    end
    return b:listEnd(L, y)
end

-- the action of a row: a button while the balance covers the stake, else how many points are missing (no button)
local function action(page, key, label, onClick, stake, bal, pending)
    if bal < stake then return nil, getText("IGUI_MQ_UI_PointsShort", D.num(stake - bal)) end
    local btn = page.pool:button(key, page.UI, page.theme, getText(label), page, onClick)
    btn:setEnabled(not pending)
    return btn, nil
end

-- ===== no contract of mine: the templates and the squads gathering =====
local function none(b, page, x, y, w, s, ct)
    if ct.on ~= true then return b:para(x, y, D.codeText("CONTRACT_OFF"), w, "textMuted") + GAP end
    y = b:para(x, y, getText("IGUI_MQ_Contract_Intro", tostring(ct.minSize or 2), tostring(ct.maxSize or 6),
        tostring(ct.returnPct or 0), tostring(ct.bonusPct or 0)), w, "textMuted")
    y = b:para(x, y, getText("IGUI_MQ_Contract_Rule_Kills"), w, "textMuted") + 6
    local bal, pending = C.balance(s), C.isPending(page.spendRid)
    local can = (tonumber(ct.today) or 0) < (tonumber(ct.perDay) or 0)
    if not can then y = b:para(x, y, getText("IGUI_MQ_Contract_DayUsed", tostring(ct.perDay or 0)), w, "warning") + 4 end
    local rows = {}
    for _, t in ipairs(type(ct.tpls) == "table" and ct.tpls or {}) do
        local r = { name = P.name(t.id), sub = getText("IGUI_MQ_Contract_Sub_" .. t.id, tostring(t.limitMin), D.num(t.perMember)),
            price = getText("IGUI_MQ_Contract_Stake", D.num(t.stake)) }
        if can then
            r.btn, r.short = action(page, "start:" .. t.id, "IGUI_MQ_Contract_Start", P.onStart, t.stake, bal, pending)
            if r.btn ~= nil then r.btn.tpl = t end
        end
        rows[#rows + 1] = r
    end
    if #rows > 0 then y = listRows(b, x, y, w, rows) + GAP end
    y = b:header(x, y, x + w, getText("IGUI_MQ_Contract_OpenHead"))
    local open = type(ct.open) == "table" and ct.open or {}
    if #open == 0 then return b:para(x, y, getText("IGUI_MQ_Contract_OpenNone"), w, "textMuted") + GAP end
    rows = {}
    for _, o in ipairs(open) do
        local r = { name = getText("IGUI_MQ_Contract_Size", P.name(o.tpl), tostring(o.size), tostring(ct.maxSize or 0)),
            sub = getText("IGUI_MQ_Contract_LeadIn", P.who(o.leader), D.duration(D.left(o.openUntil))),
            price = getText("IGUI_MQ_Contract_Stake", D.num(o.stake)) }
        if can and (tonumber(o.size) or 0) < (tonumber(ct.maxSize) or 0) then
            r.btn, r.short = action(page, "join:" .. o.id, "IGUI_MQ_Contract_Join", P.onJoin, o.stake, bal, pending)
            if r.btn ~= nil then r.btn.open = o end
        end
        rows[#rows + 1] = r
    end
    return listRows(b, x, y, w, rows) + GAP
end

-- "You 88 · Kate 79 · Bob 45" (running) or "Kate (leader), You, Bob" (gathering)
local function memberText(c, running)
    local parts = {}
    for _, m in ipairs(type(c.members) == "table" and c.members or {}) do
        local n = P.who(m)
        if running then
            parts[#parts + 1] = getText("IGUI_MQ_Contract_Member", n, D.num(m.k or 0))
        else
            parts[#parts + 1] = m.lead and getText("IGUI_MQ_Contract_Leader", n) or n
        end
    end
    return table.concat(parts, getText(running and "IGUI_MQ_Contract_Dot" or "IGUI_MQ_UI_ListSep"))
end

-- ===== my gathering contract =====
local function gathering(b, page, x, y, w, ct, c)
    local L = b:list(x, y, w)
    local iw = w - 16
    local top = y + 6
    local right = b:textRight(x + w - 8, top, getText("IGUI_MQ_Contract_StartsIn", D.duration(D.left(c.openUntil))), "textMuted")
    b:fitText(x + 8, top, getText("IGUI_MQ_Contract_Size", P.name(c.tpl), tostring(c.size), tostring(ct.maxSize or 0)),
        iw - right - 8, "text")
    y = top + D.fontH() + 4
    y = b:para(x + 8, y, getText("IGUI_MQ_Contract_MembersStaked", memberText(c, false), D.num(c.stake)), iw, "textMuted")
    y = b:para(x + 8, y, getText("IGUI_MQ_Contract_TargetNow", tostring(c.size),
        getText("IGUI_MQ_Contract_Goal_" .. c.tpl, tostring(c.limitMin), D.num((tonumber(c.perMember) or 0) * (tonumber(c.size) or 0)))),
        iw, "textMuted")
    local btns = {}
    if c.lead then
        if (tonumber(c.size) or 0) >= (tonumber(ct.minSize) or 2) then
            local go = page.pool:button("go", page.UI, page.theme, getText("IGUI_MQ_Contract_GoNow"), page, P.onGo)
            go.internal = c.id
            btns[#btns + 1] = go
        else
            y = b:para(x + 8, y, getText("IGUI_MQ_Contract_NeedMore", tostring(ct.minSize or 2)), iw, "warning")
        end
    end
    local leave = page.pool:button("leave", page.UI, page.theme, getText("IGUI_MQ_Contract_Leave", D.num(c.stake)), page, P.onLeave)
    leave.internal = c.id
    btns[#btns + 1] = leave
    for _, bt in ipairs(btns) do bt:setEnabled(not C.isPending(page.actRid)) end
    y = D.placeRow(btns, x + 8, y + 6, x + w - 8) + 8
    y = b:listEnd(L, y)
    y = b:para(x, y + 6, getText("IGUI_MQ_Contract_OpenNote"), w, "textMuted")
    return b:para(x, y, getText("IGUI_MQ_Contract_Rule_Kills"), w, "textMuted") + GAP
end

-- ===== my running contract =====
local function running(b, x, y, w, c)
    local y0 = y
    local L = b:list(x, y, w)
    local iw, lh = w - 16, D.fontH()
    local top = y + 6
    local right = b:textRight(x + w - 8, top, getText("IGUI_MQ_UI_Left", D.duration(D.left(c.endsAt))), D.EXTRA.gold)
    b:fitText(x + 8, top, getText("IGUI_MQ_Contract_SizeRun", P.name(c.tpl), tostring(c.size)), iw - right - 8, "text")
    y = top + lh + 6
    local target = tonumber(c.target) or 0
    b:bar(x + 8, y, iw, 6, target > 0 and (tonumber(c.prog) or 0) / target or 0, D.EXTRA.gold)
    y = y + 12
    local kills = getText("IGUI_MQ_Contract_Kills", D.num(c.prog or 0), D.num(target))
    local who = memberText(c, true)
    b:text(x + 8, y, kills, "textMuted")
    local kw = D.textW(kills)
    if kw + 16 + D.textW(who) <= iw then
        b:textRight(x + w - 8, y, who, "textMuted")
        y = y + lh + 8
    else
        y = b:para(x + 8, y + lh + 2, who, iw, "textMuted") + 6
    end
    y = b:listEnd(L, y)
    b:border(x, y0, w, y - y0, D.EXTRA.gold, "rect")
    return b:para(x, y + 6, getText("IGUI_MQ_Contract_Rule_Kills"), w, "textMuted") + GAP
end

-- ===== recent contracts (records.contracts): time, contract and size, the result on one line and its number below =====
local function recent(b, x, y, w)
    if C.records == nil then return y end
    y = b:header(x, y, x + w, getText("IGUI_MQ_Contract_Recent"))
    local list = type(C.records.contracts) == "table" and C.records.contracts or {}
    local L = b:list(x, y, w)
    if #list == 0 then
        return b:listEnd(L, b:para(x + 8, y + 6, getText("IGUI_MQ_Contract_RecentNone"), w - 16, "textMuted") + 4) + GAP
    end
    local hTime, hName, hRes = getText("IGUI_MQ_UI_ColTime"), getText("IGUI_MQ_Contract_Col"), getText("IGUI_MQ_UI_ColResult")
    local rows, timeW, resW = {}, D.textW(hTime), D.textW(hRes)
    for _, e in ipairs(list) do
        if type(e) == "table" then
            local r = { time = D.dateTime(tonumber(e.at) or 0), name = getText("IGUI_MQ_Contract_SizeRun", P.name(e.tpl), tostring(e.size)) }
            if e.won then
                r.res, r.tok = getText("IGUI_MQ_Contract_ResWon"), D.EXTRA.success
                r.sub = (tonumber(e.bonus) or 0) > 0 and getText("IGUI_MQ_Contract_ResBonus", D.num(e.back or 0), D.num(e.bonus))
                    or getText("IGUI_MQ_Contract_ResBack", D.num(e.back or 0))
            else
                r.res, r.tok = getText("IGUI_MQ_Contract_ResLost"), "errorText"
                r.sub = getText("IGUI_MQ_UI_Progress", D.num(e.prog or 0), D.num(e.target or 0))
            end
            timeW = math.max(timeW, D.textW(r.time))
            resW = math.max(resW, 20 + D.textW(r.res), D.textW(r.sub))
            rows[#rows + 1] = r
        end
    end
    local lh = D.fontH()
    local nameX = x + 8 + timeW + 12
    local resX = x + w - 8 - resW
    local nameW = resX - 12 - nameX
    b:listHead(L, lh + 8)
    b:text(x + 8, y + 4, hTime, "text")
    b:fitText(nameX, y + 4, hName, nameW, "text")
    b:text(resX, y + 4, hRes, "text")
    y = y + lh + 8
    for i, r in ipairs(rows) do
        if i > 1 then b:listSep(L, y) end
        b:text(x + 8, y + 4, r.time, "textMuted")
        local ny = b:para(nameX, y + 4, r.name, nameW, "text")
        b:icon(resX, y + 4, 14, r.tok == "errorText" and "close" or "check", r.tok, r.tok == "errorText" and "x" or "v")
        b:text(resX + 20, y + 4, r.res, r.tok)
        b:text(resX, y + 4 + lh + 2, r.sub, "textMuted")
        y = math.max(ny, y + 4 + 2 * lh + 2) + 4
    end
    return b:listEnd(L, y) + GAP
end

-- a contract of mine that ended while the page is open: ask once for the records that list it
local function refresh(ct)
    local id = ct ~= nil and type(ct.mine) == "table" and ct.mine.id or nil
    if P.mineId ~= nil and id == nil then C.requestRecords(true) end
    P.mineId = id
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local s = C.state
    local ct = part(s)
    local mine = ct ~= nil and type(ct.mine) == "table" and ct.mine or nil
    local chips = nil
    if mine ~= nil and mine.state == "active" then
        chips = { { getText("IGUI_MQ_Contract_Running"), D.EXTRA.gold, true } }
    elseif mine ~= nil then
        chips = { { getText("IGUI_MQ_Contract_Gathering"), "warning", true } }
    elseif ct ~= nil and ct.on == true then
        chips = { { getText("IGUI_MQ_Contract_TodayLeft", tostring(math.max(0, (tonumber(ct.perDay) or 0) - (tonumber(ct.today) or 0)))),
            "textMuted" } }
    end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_NavContracts"), chips)
    if s == nil or ct == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    refresh(ct)
    if mine == nil then
        y = none(b, page, x, y, w, s, ct)
    elseif mine.state == "active" then
        y = running(b, x, y, w, mine)
    else
        y = gathering(b, page, x, y, w, ct, mine)
    end
    y = recent(b, x, y, w)
    D.finish(page, y)
end

-- ===== the result and refund toasts (Entry.toastText) =====
-- returns title, message, border
function P.toastText(t)
    local name = P.name(t.tpl)
    if t.ev == "won" then
        local body = t.full and getText("IGUI_MQ_Contract_ToastWonBody", tostring(t.size or 0), tostring(t.mins or 0),
            D.num(t.target or 0), D.num(t.back or 0), D.num(t.bonus or 0))
            or getText("IGUI_MQ_Contract_ToastWonShort", D.num(t.mine or 0), D.num(t.need or 0), D.num(t.back or 0))
        return getText("IGUI_MQ_Contract_ToastWon", name), body, D.EXTRA.success
    elseif t.ev == "lost" then
        return getText("IGUI_MQ_Contract_ToastLost", name),
            getText("IGUI_MQ_Contract_ToastLostBody", D.num(t.prog or 0), D.num(t.target or 0), D.num(t.stake or 0)), D.EXTRA.horde
    elseif t.ev == "refund" then
        local why = t.why == "leader" and "IGUI_MQ_Contract_ToastRefund_leader" or "IGUI_MQ_Contract_ToastRefund_small"
        return getText("IGUI_MQ_Contract_ToastRefund", name), getText(why, D.num(t.pts or 0)), D.EXTRA.gold
    end
    return nil
end

P.spec = {
    id = "contracts", label = "IGUI_MQ_UI_NavContracts", icon = "users", group = "main", order = 27, ticking = true,
    shown = function() return MinidoracatQuest.PageContracts.shown() end,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageContracts.layout(page) end,
    onShow = function() MinidoracatQuest.Client.requestRecords(true) end,
}
W.register(P.spec)
