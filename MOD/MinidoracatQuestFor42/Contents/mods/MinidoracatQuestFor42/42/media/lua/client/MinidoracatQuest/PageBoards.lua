-- MinidoracatQuest/PageBoards.lua: leaderboards (spec 11.4, 12.2-12.4): season / all-time / season rewards chips,
--   8 board categories (empty ones hidden), the boards of the category, settle line, podium for the top three,
--   rank rows with titles and rank change, my row (always shown), rank gap and participation hint, and the
--   loading / ready / empty / error states of Client's board state machine (5 s timeout, retry).
--   The page asks only when opened or switched (no polling while closed).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageBoards or {}
Q.PageBoards = P

local PAD, GAP = D.PAD, D.GAP

-- ===== model (harness tests these) =====
function P.boardsIn(defs, cat)
    local out = {}
    for _, bd in ipairs(defs.boards) do
        if bd.cat == cat then out[#out + 1] = bd end
    end
    return out
end

function P.categories(defs)
    local order = Q.Catalog and Q.Catalog.boardCats or (Q.Contract and Q.Contract.BOARD_CATS) or {}
    local out = {}
    for _, cat in ipairs(order) do
        if #P.boardsIn(defs, cat) > 0 then out[#out + 1] = cat end
    end
    return out
end

-- the period actually shown: skill_total has only "total"
function P.periodFor(bd, period)
    local periods = type(bd.periods) == "table" and bd.periods or { "season", "total" }
    for _, p in ipairs(periods) do
        if p == period then return period end
    end
    return periods[1] or "total"
end

-- current selection -> board def and period; picks defaults when the selection no longer exists
function P.select(page, defs)
    local cats = P.categories(defs)
    local okCat = false
    for _, c in ipairs(cats) do if c == page.cat then okCat = true end end
    if not okCat then page.cat = cats[1] end
    if page.cat == nil then return nil, nil, cats end
    local list = P.boardsIn(defs, page.cat)
    page.boardOf = page.boardOf or {}
    local id = page.boardOf[page.cat]
    local bd = nil
    for _, x in ipairs(list) do if x.id == id then bd = x end end
    bd = bd or list[1]
    page.boardOf[page.cat] = bd.id
    return bd, P.periodFor(bd, page.period), cats
end

-- ===== actions =====
function P.ask(page)
    local bd, period = P.select(page, C.defs())
    if bd ~= nil then C.requestBoard(bd.id, period) end
end

function P.onPeriod(page, btn)
    if btn.internal == "rewards" then
        page.view = "rewards"
        local e = C.board("points", "season")
        if e == nil or e.status == "error" then C.requestBoard("points", "season") end
    else
        page.view, page.period = "board", btn.internal
        P.ask(page)
    end
    page.dirty = true
end

function P.onCat(page, btn)
    page.cat = btn.internal
    P.ask(page)
    page.dirty = true
end

function P.onBoard(page, btn)
    page.boardOf[page.cat] = btn.internal
    P.ask(page)
    page.dirty = true
end

function P.onRetry(page) P.ask(page) end
function P.onDaily() MinidoracatQuest.Window.select("daily") end

-- ===== drawing =====
-- row.a: the real name of an anonymous row, sent to admins only
local function nameOf(row)
    if row.n ~= nil then return row.n end
    if row.a ~= nil then return getText("IGUI_MQ_UI_AnonReal", row.a) end
    return getText("IGUI_MQ_UI_Anonymous")
end

local function delta(b, xRight, y, d)
    if d == nil then
        b:textRight(xRight, y, getText("IGUI_MQ_UI_RankNew"), D.EXTRA.info)
        return
    end
    d = tonumber(d) or 0
    if d == 0 then
        b:textRight(xRight, y, "-", "textFaint")
        return
    end
    local up = d > 0
    local col = up and D.EXTRA.success or "errorText"
    local w = b:textRight(xRight, y, tostring(math.abs(d)), col)
    b:arrow(xRight - w - 10, y + math.floor(D.fontH() / 2) - 2, up, col)
end

-- focus caption for one rank: "#rank  full name  [title]  value" (composed at layout, read per frame)
function P.stopLabel(rank, name, titleId, value)
    local s = "#" .. tostring(rank or "-") .. "  " .. tostring(name)
    if titleId ~= nil then s = s .. "  " .. getText("IGUI_MQ_UI_TitleBracket", D.titleText(titleId)) end
    return s .. "  " .. D.num(value or 0)
end

local function addStop(stops, x, y, w, h, rank, name, titleId, value)
    stops[#stops + 1] = { x = x, y = y, w = w, h = h, rank = rank, name = name,
        label = P.stopLabel(rank, name, titleId, value) }
end

local function podium(b, x, y, w, rows, stops)
    local top = {}
    for _, r in ipairs(rows) do
        local rk = tonumber(r.r)
        if rk and rk >= 1 and rk <= 3 and top[rk] == nil then top[rk] = r end
    end
    if top[1] == nil then return y end
    local lh = D.fontH()
    local colW = math.min(180, math.floor((w - 16) / 3))
    local x0 = x + math.floor((w - (colW * 3 + 16)) / 2)
    -- tallest content: rank (Medium), name, title, value, 6 px under the value; the steps stay 14 / 6 px
    local need = 18 + D.fontH(UIFont.Medium) + 3 * lh
    local heights = { need + 14, need + 6, need }
    local colors = { D.TIER[3], D.TIER[2], D.TIER[1] }
    local slots = { 2, 1, 3 }
    local baseY = y + heights[1] + 18
    for i, rank in ipairs(slots) do
        local r = top[rank]
        if r ~= nil then
            local cx = x0 + (i - 1) * (colW + 8)
            local h = heights[rank]
            local cy = baseY - h
            b:card(cx, cy, colW, h, colors[rank])
            if rank == 1 then b:icon(cx + math.floor(colW / 2) - 10, cy - 18, 20, "markerCrown", D.EXTRA.gold, "") end
            local mid = cx + colW / 2
            b:textCentre(mid, cy + 6, tostring(rank), colors[rank], UIFont.Medium)
            local nm = D.fit(b.UI, nameOf(r), colW - 12, UIFont.Small)
            b:textCentre(mid, cy + 8 + D.fontH(UIFont.Medium), nm, "text")
            if nm ~= nameOf(r) then
                local tips = b.cv.tips
                tips[#tips + 1] = { x = cx, y = cy, w = colW, h = h, text = nameOf(r), tw = D.textW(nameOf(r)), th = lh }
            end
            local ty = cy + 10 + D.fontH(UIFont.Medium) + lh
            if r.t ~= nil then
                b:textCentre(mid, ty, D.fit(b.UI, D.titleText(r.t), colW - 12, UIFont.Small), "textMuted")
                ty = ty + lh
            end
            b:textCentre(mid, ty + 2, D.num(r.v), colors[rank])
            top[rank] = { r = r, x = cx, y = cy, w = colW, h = h }
        end
    end
    -- focus order follows rank (1, 2, 3), not the 2-1-3 screen order
    for rank = 1, 3 do
        local c = top[rank]
        if c ~= nil and c.x ~= nil then addStop(stops, c.x, c.y, c.w, c.h, rank, nameOf(c.r), c.r.t, c.r.v) end
    end
    return baseY + GAP
end

local function row(b, x, y, w, r, frame, label, stops)
    local lh = D.fontH()
    local h = lh + 10
    if frame then
        b:card(x, y, w, h, frame)
    end
    local ty = y + 5
    b:textRight(x + 40, ty, label or tostring(r.r or "-"), frame or "textMuted")
    local valueW = D.textW("000,000,000") + 8
    -- the "new" label is translated (FR "NOUVEAU" ran into the value with a width taken from "NEW")
    local deltaW = math.max(D.textW(getText("IGUI_MQ_UI_RankNew")), D.textW("99") + 10) + 14
    local nameX, nameMax = x + 50, w - 50 - valueW - deltaW - 8
    local nw = b:fitText(nameX, ty, frame and (r.n or "") or nameOf(r), nameMax, "text")
    if r.t ~= nil and not frame then
        local t = getText("IGUI_MQ_UI_TitleBracket", D.titleText(r.t))
        local room = nameMax - nw - 6
        if room > 30 then b:fitText(nameX + nw + 6, ty, t, room, "textFaint") end
    end
    b:textRight(x + w - deltaW - 8, ty, D.num(r.v or 0), frame or "text")
    delta(b, x + w - 6, ty, r.d)
    if stops ~= nil then addStop(stops, x, y, w, h, r.r, r.full or nameOf(r), r.t, r.v) end
    return y + h + 2
end

-- ===== keyboard / gamepad focus over the drawn podium and rows (UI ARCHITECTURE 3.10) =====
-- One invisible control covers the ranks: _focusKind "button", an internal cursor over the stops in rank order
-- (1, 2, 3, 4 ... 50, then my row). Up/Left and Down/Right move one stop; at either end they return false so
-- the Focus engine moves to the previous / next target. focusRect frames the current stop, focusLabel gives
-- "#rank full name [title] value" (composed at layout). Mouse events pass through to the canvas and buttons.
local function reveal(el)
    local p = el.parent
    while p ~= nil do
        if p._scrollPanel and p.scrollTo then p:scrollTo(el) end
        p = p.parent
    end
end

function P.rankKey(el, key)
    local K = Keyboard
    local n = #el.stops
    if n == 0 then return false end
    local i = el.cursor or 1
    local j = nil
    if key == K.KEY_DOWN or key == K.KEY_RIGHT then
        j = i + 1
    elseif key == K.KEY_UP or key == K.KEY_LEFT then
        j = i - 1
    elseif key == K.KEY_HOME then
        j = 1
    elseif key == K.KEY_END then
        j = n
    elseif key == K.KEY_RETURN or key == K.KEY_NUMPADENTER or key == K.KEY_SPACE then
        return true
    else
        return false
    end
    if j < 1 or j > n then return false end
    el.cursor = j
    reveal(el)
    return true
end

local RankFocus = nil
local function rankClass()
    if RankFocus ~= nil then return RankFocus end
    RankFocus = ISUIElement:derive("MinidoracatQuestRankFocus")
    function RankFocus:forceClick() end
    function RankFocus:onFocusKey(key) return MinidoracatQuest.PageBoards.rankKey(self, key) end
    function RankFocus:focusRect()
        local s = self.stops[self.cursor or 0]
        if s == nil then return nil end
        return s.x, s.y - self.top, s.w, s.h
    end
    function RankFocus:focusLabel()
        local s = self.stops[self.cursor or 0]
        return s and s.label or nil
    end
    return RankFocus
end

-- stops are in scroll-content coordinates; the control starts at top and spans the content width
function P.placeRanks(page, top, stops)
    if #stops == 0 then return end
    local el = page.pool:get("ranks", function()
        local o = rankClass():new(0, 0, 1, 1)
        o:initialise()
        o.wantMouseEvents = false   -- before addChild: instantiate syncs it to consumeMouseEvents (ISUIElement.lua:1004)
        o._focusKind = "button"
        o.stops, o.top = {}, 0
        return o
    end)
    local bottom = top + 1
    for _, s in ipairs(stops) do bottom = math.max(bottom, s.y + s.h) end
    el.stops, el.top = stops, top
    if el.cursor == nil or el.cursor > #stops then el.cursor = 1 end
    el:setX(0)
    el:setY(top)
    el:setWidth(D.contentW(page))
    el:setHeight(bottom - top)
    page.ranks = el
end

local function skeleton(b, x, y, w)
    for _, f in ipairs({ 1, 0.85, 0.7 }) do
        b:rect(x, y, math.floor(w * f), 14, "well")
        y = y + 22
    end
    return y + GAP
end

local function seasonLine(b, x, y, w, season)
    if type(season) ~= "table" or not tonumber(season.endsAt) then return y end
    local line = getText("IGUI_MQ_UI_SeasonLine", tostring(season.no or "?"), D.dateTime(season.endsAt - 60000),
        D.duration(D.left(season.endsAt)))
    return b:para(x, y, line, w, "textMuted") + 4
end

local function seasonBanner(b, x, y, w, s)
    local st = s and type(s.season) == "table" and s.season or nil
    if st == nil then return y end
    -- review / paying: season reviewNo (the one before no) is being settled; no is already running
    local settling = tostring(st.reviewNo or ((tonumber(st.no) or 1) - 1))
    if st.state == "review" then
        return b:banner(x, y, w, D.EXTRA.info, getText("IGUI_MQ_UI_SeasonReview", settling),
            getText("IGUI_MQ_UI_SeasonReviewBody"))
    elseif st.state == "paying" then
        return b:banner(x, y, w, D.EXTRA.success, getText("IGUI_MQ_UI_SeasonPaying", settling),
            getText("IGUI_MQ_UI_SeasonPayingBody"))
    end
    return y
end

local function boardView(b, page, x, y, w, bd, period, e)
    local s = C.state
    local data = e and e.data or nil
    local status = e and e.status or "loading"
    if period == "season" then y = seasonLine(b, x, y, w, (data and data.season) or (s and s.season)) end
    if period ~= page.period then y = b:para(x, y, getText("IGUI_MQ_UI_BoardTotalOnly"), w, "textFaint") + 2 end
    if status == "error" then
        y = b:para(x, y + 4, getText("IGUI_MQ_UI_BoardError"), w, "errorText", UIFont.Medium)
        y = b:para(x, y, getText("IGUI_MQ_UI_BoardErrorBody"), w, "textMuted")
        local btn = page.pool:button("retry", page.UI, page.theme, getText("IGUI_MQ_UI_Refresh"), page, P.onRetry)
        btn:setX(x)
        btn:setY(y + 4)
        return y + btn.height + 2 * GAP
    end
    if status == "empty" or (status == "loading" and data ~= nil and #(data.rows or {}) == 0 and data.me == nil) then
        y = b:para(x, y + 4, getText(period == "season" and "IGUI_MQ_UI_BoardEmptySeason" or "IGUI_MQ_UI_BoardEmptyTotal"),
            w, "text", UIFont.Medium)
        y = b:para(x, y, getText("IGUI_MQ_UI_BoardEmptyBody"), w, "textMuted")
        local btn = page.pool:button("toDaily", page.UI, page.theme, getText("IGUI_MQ_UI_SeeDaily"), page, P.onDaily)
        btn:setX(x)
        btn:setY(y + 4)
        return y + btn.height + 2 * GAP
    end
    if data == nil then return skeleton(b, x, y + 4, w) end
    local rows = type(data.rows) == "table" and data.rows or {}
    local stops = {}
    local ranksTop = y + 4
    y = podium(b, x, y + 22, w, rows, stops)
    local me = data.me
    local myRank = type(me) == "table" and tonumber(me.r) or nil
    for _, r in ipairs(rows) do
        if (tonumber(r.r) or 0) > 3 then
            -- my own row inside the list gets the same gold frame as the pinned row below
            if myRank ~= nil and tonumber(r.r) == myRank then b:card(x, y, w, D.fontH() + 10, D.EXTRA.gold) end
            y = row(b, x, y, w, r, nil, nil, stops)
        end
    end
    y = y + 6
    if type(me) == "table" and me.r ~= nil then
        local meName = getText("IGUI_MQ_UI_BoardMe", tostring(s and s.user or ""))
        local my = { r = me.r, v = me.v, d = me.d, n = meName, full = meName, t = s and s.title or nil }
        y = row(b, x, y, w, my, D.EXTRA.gold, "#" .. tostring(me.r), stops)
        local hints = {}
        for _, r in ipairs(rows) do
            if tonumber(r.r) == tonumber(me.r) - 1 and tonumber(r.v) and tonumber(me.v) then
                hints[#hints + 1] = { getText("IGUI_MQ_UI_BoardGap", D.num(r.v - me.v), tostring(r.r)), "textMuted" }
            end
        end
        if bd.id == "points" and period == "season" then
            local min = tonumber(C.defs().cfg.rewards and C.defs().cfg.rewards.participationMin) or 0
            if (tonumber(me.v) or 0) >= min then
                hints[#hints + 1] = { getText("IGUI_MQ_UI_ParticipationDone"), D.EXTRA.success }
            else
                hints[#hints + 1] = { getText("IGUI_MQ_UI_ParticipationLeft", D.num(min - (tonumber(me.v) or 0))), "textMuted" }
            end
        end
        for _, hnt in ipairs(hints) do y = b:para(x, y, hnt[1], w, hnt[2]) end
    else
        y = b:para(x, y, getText("IGUI_MQ_UI_BoardNotRanked"), w, "textMuted")
    end
    P.placeRanks(page, ranksTop, stops)
    local bcfg = C.defs().cfg.boards or {}
    local every = period == "season" and (bcfg.rebuildSeasonMs or 300000) or (bcfg.rebuildTotalMs or 1800000)
    local mins = tostring(math.floor(every / 60000))
    local foot = tonumber(data.at) and getText("IGUI_MQ_UI_BoardUpdated", D.clock(data.at), mins)
        or getText("IGUI_MQ_UI_BoardEvery", mins)
    y = b:para(x, y + 6, foot, w, "textFaint")
    return y + GAP
end

local function rewardsView(b, page, x, y, w)
    local s = C.state
    local season = s and type(s.season) == "table" and s.season or {}
    local no = tostring(season.no or "?")
    local rw = C.defs().cfg.rewards or {}
    local lh = D.fontH()
    local chips = {}
    if tonumber(season.endsAt) then chips[1] = { getText("IGUI_MQ_UI_Left", D.duration(D.left(season.endsAt))), "textMuted" } end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_RewardsTitle", no), chips)
    local function points(n) return getText("IGUI_MQ_UI_PlusPoints", D.num(n or 0)) end
    local function withTitle(kind, n)
        return getText("IGUI_MQ_UI_RewardTitlePts", D.titleText("s" .. no .. "_" .. kind), points(n))
    end
    local rows = {
        { getText("IGUI_MQ_UI_RewardTop1"), withTitle("top1", rw.top1) },
        { getText("IGUI_MQ_UI_RewardTop3"), withTitle("top3", rw.top3) },
        { getText("IGUI_MQ_UI_RewardTop10"), withTitle("top10", rw.top10) },
        { getText("IGUI_MQ_UI_RewardPart", D.num(rw.participationMin or 0)), points(rw.participation) },
    }
    if rw.firstTitles ~= false then
        rows[#rows + 1] = { getText("IGUI_MQ_UI_RewardFirsts"), getText("IGUI_MQ_UI_RewardFirstsValue") }
    end
    -- label column fits the longest label up to 40 % of the width; both columns wrap (FR / DE cut the
    -- participation label and pushed "points" alone onto a second line, quest-ui-fr-1023g)
    local labelW = 0
    for _, r in ipairs(rows) do labelW = math.max(labelW, D.textW(r[1])) end
    labelW = math.min(labelW + 16, math.floor(w * 0.4))
    for i, r in ipairs(rows) do
        local labels = D.wrap(b.UI, r[1], labelW - 12, UIFont.Small)
        local lines = D.wrap(b.UI, r[2], w - labelW - 16, UIFont.Small)
        local h = math.max(1, #lines, #labels) * (lh + 2) + 8
        if i % 2 == 1 then b:rect(x, y, w, h, "hover") end
        local ly = y + 4
        for _, l in ipairs(labels) do
            b:text(x + 8, ly, l, "text")
            ly = ly + lh + 2
        end
        ly = y + 4
        for _, l in ipairs(lines) do
            b:text(x + labelW + 8, ly, l, D.EXTRA.gold)
            ly = ly + lh + 2
        end
        y = y + h
    end
    y = b:para(x, y + 6, getText("IGUI_MQ_UI_RewardNote"), w, "textFaint")
    local e = C.board("points", "season")
    local me = e and e.data and e.data.me
    if type(me) == "table" and me.r ~= nil then
        local min = tonumber(rw.participationMin) or 0
        y = b:para(x, y + 6, getText("IGUI_MQ_UI_RewardMine", D.num(me.v or 0), tostring(me.r)), w, "text")
        if (tonumber(me.v) or 0) >= min then y = b:para(x, y, getText("IGUI_MQ_UI_ParticipationDone"), w, D.EXTRA.success) end
    end
    return y + GAP
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local UI, theme = page.UI, page.theme
    page.view, page.period = page.view or "board", page.period or "season"
    local defs = C.defs()
    local bd, period, cats = P.select(page, defs)
    local e = bd and C.board(bd.id, period) or nil
    local chips = {}
    if page.view == "board" and e ~= nil and e.status == "loading" then chips[1] = { getText("IGUI_MQ_UI_Loading"), "textMuted" } end
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Boards"), chips)
    local tabs = {}
    for _, id in ipairs({ "season", "total", "rewards" }) do
        local active = (id == "rewards" and page.view == "rewards") or (page.view == "board" and page.period == id)
        local btn = page.pool:button("period:" .. id, UI, theme, getText("IGUI_MQ_UI_Period_" .. id), page, P.onPeriod,
            "chip", active)
        btn.internal = id
        tabs[#tabs + 1] = btn
    end
    y = D.placeRow(tabs, x, y, x + w) + GAP
    y = seasonBanner(b, x, y, w, C.state)
    if page.view == "rewards" then
        y = rewardsView(b, page, x, y, w)
        D.finish(page, y)
        return
    end
    if bd == nil then
        y = b:para(x, y, getText("IGUI_MQ_UI_NoBoards"), w, "textMuted")
        D.finish(page, y)
        return
    end
    local cb = {}
    for _, cat in ipairs(cats) do
        local btn = page.pool:button("cat:" .. cat, UI, theme, getText("IGUI_MQ_BoardCat_" .. cat), page, P.onCat, "chip",
            cat == page.cat)
        btn.internal = cat
        cb[#cb + 1] = btn
    end
    y = D.placeRow(cb, x, y, x + w) + GAP
    local list = P.boardsIn(defs, page.cat)
    if #list > 1 then
        local bb = {}
        for _, x2 in ipairs(list) do
            local label = x2.nameKey and getText(x2.nameKey) or getText("IGUI_MQ_Board_" .. x2.id)
            local btn = page.pool:button("board:" .. x2.id, UI, theme, label, page, P.onBoard, "chip", x2.id == bd.id)
            btn.internal = x2.id
            bb[#bb + 1] = btn
        end
        y = D.placeRow(bb, x, y, x + w) + GAP
    end
    y = boardView(b, page, x, y, w, bd, period, e)
    D.finish(page, y)
end

P.spec = {
    id = "boards", label = "IGUI_MQ_UI_NavBoards", icon = "chart", group = "main", order = 40, ticking = true,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageBoards.layout(page) end,
    onShow = function(page) MinidoracatQuest.PageBoards.ask(page) end,
}
W.register(P.spec)
