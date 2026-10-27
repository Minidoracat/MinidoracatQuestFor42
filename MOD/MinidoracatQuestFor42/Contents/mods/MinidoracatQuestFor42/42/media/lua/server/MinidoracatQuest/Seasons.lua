-- MinidoracatQuestFor42 - seasons: running -> review (ranks frozen) -> paying -> running (spec 11).
-- The season ends at a daily reset (C16); 24 hours after the freeze the frozen list pays out by itself.
if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"

local first = MQ.Seasons == nil
local Se = MQ.Seasons or {}
MQ.Seasons = Se

local DAY = 86400000
Se.REVIEW_MS = DAY
Se.JOIN_STAT = "season.joined"

local function code(name) return MQ.Contract.CODE[name] end

-- First reset at or after start + (days - 1) days, i.e. start + days when start is a reset moment.
local function endFor(startMs, days)
    return MQ.Clock.nextResetMs(startMs + (days - 1) * DAY)
end

local function meta()
    local s = MQ.Store.root().season
    if not s.endMs then s.endMs = endFor(s.startMs, s.lengthDays or 28) end
    s.excluded = s.excluded or {}
    return s
end

-- state "review" = the previous season (reviewNo) waits for payout; season `no` is already running
function Se.current()
    local s = meta()
    return { no = s.no, startMs = s.startMs, endsAt = s.endMs, state = s.state, lengthDays = s.lengthDays,
        reviewNo = s.frozen and s.frozen.no or nil }
end

-- ---------- length ----------

function Se.previewLength(days)
    if type(days) ~= "number" or days ~= math.floor(days) or days < 7 or days > 180 then
        return nil, code("BAD_SEASON_LENGTH")
    end
    local s = meta()
    if s.state == "paying" then return nil, code("NOT_READY") end
    local endMs = endFor(s.startMs, days)
    if endMs < MQ.Clock.now() + DAY then return nil, code("TOO_SOON") end
    return { endMs = endMs, nextStartMs = endMs }
end

function Se.applyLength(days, actor)
    local p, c = Se.previewLength(days)
    if not p then return nil, c end
    local s = meta()
    local before = s.lengthDays
    s.lengthDays, s.endMs = days, p.endMs
    MQ.Config.addHistory(actor, "season.length " .. days,
        { { path = "season.lengthDays", before = before, after = days } }, false)
    MQ.EventLog.write("season", nil, { op = "length", days = days, endMs = p.endMs, actor = actor })
    MQ.Sync.dirty(nil, "all")
    return p
end

-- ---------- freeze / review ----------

local function less(a, b)
    if a.pts ~= b.pts then return a.pts > b.pts end
    return a.user < b.user
end

-- C30: at the due time freeze the ranks and open the next season in the same step; the frozen
-- season (frozen.no) is reviewed and paid while the new one already counts points.
-- Rows: top 10 plus everyone at or above the participation minimum.
local function freeze(s, now)
    local cfg = MQ.Config.get().rewards
    local rows = {}
    MQ.Store.each(function(user, acc)
        local pts = acc.sno == s.no and acc.points.season or 0
        if pts > 0 and not acc.hidden then rows[#rows + 1] = { user = user, pts = pts, anomalies = acc.anomalies or 0 } end
    end)
    MQ.Util.sort(rows, less)
    local keep = {}
    for i, r in ipairs(rows) do
        if i <= 10 or r.pts >= (cfg.participationMin or 0) then keep[#keep + 1] = r end
    end
    local firsts = {}
    if MQ.Boards then
        for _, b in ipairs(MQ.Boards.defs()) do
            if b.stat ~= "@points" and MQ.Boards.hasPeriod(b, "season") then
                firsts[b.id] = MQ.Boards.leader(b.id, "season")
            end
        end
    end
    s.frozen = { no = s.no, startMs = s.startMs, endMs = s.endMs, atMs = now, rows = keep, firsts = firsts }
    s.excluded = {}
    s.state = "review"
    s.reviewDeadlineMs = now + Se.REVIEW_MS
    MQ.EventLog.write("season", nil, { op = "freeze", no = s.no, rows = #keep })
    -- next season (accounts reset their season fields lazily on sno)
    local start = s.endMs
    if endFor(start, s.lengthDays) <= now then start = MQ.Clock.dayStartMs(now) end
    s.no = s.no + 1
    s.startMs, s.endMs = start, endFor(start, s.lengthDays)
    if MQ.Boards then MQ.Boards.dirtyAll() end
    MQ.Sync.dirty(nil, "all")
end

function Se.review()
    local s = meta()
    local f = s.frozen
    local out = { no = s.no, startMs = s.startMs, endMs = s.endMs, lengthDays = s.lengthDays, state = s.state,
        frozenNo = f and f.no or nil, frozenAt = f and f.atMs or nil, deadline = s.reviewDeadlineMs, rows = {} }
    if f then
        for i, r in ipairs(f.rows) do
            local why = s.excluded[r.user]
            out.rows[i] = { rank = i, user = r.user, pts = r.pts, anomalies = r.anomalies, excluded = why ~= nil, reason = why }
        end
    end
    return out
end

function Se.exclude(user, on, reason, actor)
    local s = meta()
    if s.state ~= "review" or not s.frozen then return false, code("NOT_READY") end
    local found = false
    for _, r in ipairs(s.frozen.rows) do
        if r.user == user then found = true end
    end
    if not found then return false, code("NOT_FOUND") end
    if on then
        if type(reason) ~= "string" or reason == "" then return false, code("BAD_ARGS") end
        s.excluded[user] = reason
    else
        s.excluded[user] = nil
    end
    MQ.EventLog.write("season", user, { op = "exclude", on = on, reason = reason, actor = actor })
    return true
end

-- ---------- payout ----------

-- Pays the frozen season (f.no); r.paid marks each row, so a payout cut short (crash before the
-- save) resumes without repeats.
local function pay(s, actor)
    s.state = "paying"
    local f = s.frozen
    local cfg = MQ.Config.get().rewards
    local rank, top = 0, {}
    for _, r in ipairs(f.rows) do
        local acc = not s.excluded[r.user] and MQ.Store.account(r.user, false) or nil
        if acc then
            rank = rank + 1
            local pts, tid = 0, nil
            if rank == 1 then pts, tid = cfg.top1, "top1"
            elseif rank <= 3 then pts, tid = cfg.top3, "top3"
            elseif rank <= 10 then pts, tid = cfg.top10, "top10" end
            if r.pts >= (cfg.participationMin or 0) then pts = pts + (cfg.participation or 0) end
            if tid then top[#top + 1] = { user = r.user, pts = r.pts } end
            if not r.paid then
                r.paid = true
                if tid then MQ.Store.grantTitle(acc, "s" .. f.no .. "_" .. tid, "season:" .. f.no .. ":" .. tid) end
                if pts > 0 then
                    MQ.Points.award(acc, r.user, pts, "season", "s" .. f.no)
                    if MQ.Stats.def(Se.JOIN_STAT) then MQ.Stats.add(r.user, Se.JOIN_STAT, 1) end
                end
                acc.unseen = (acc.unseen or 0) + 1
                MQ.Sync.toast(r.user, { kind = "season", no = f.no, rank = rank, pts = pts })
                MQ.EventLog.write("season", r.user, { op = "pay", no = f.no, rank = rank, pts = pts })
            end
        end
    end
    local firsts = {}
    for boardId, user in pairs(f.firsts or {}) do
        if not s.excluded[user] then
            firsts[boardId] = user
            local acc = cfg.firstTitles ~= false and MQ.Store.account(user, false) or nil
            if acc then MQ.Store.grantTitle(acc, "s" .. f.no .. "_first_" .. boardId, "first:" .. boardId) end
        end
    end
    table.insert(MQ.Store.root().seasons, 1, { no = f.no, startMs = f.startMs, endMs = f.endMs, top = top, firsts = firsts })
    local hist = MQ.Store.root().seasons
    while #hist > (MQ.Contract.LIMIT.SEASONS_KEPT or 12) do table.remove(hist) end
    MQ.EventLog.write("season", nil, { op = "close", no = f.no, actor = actor })
    s.state, s.frozen, s.excluded, s.reviewDeadlineMs = "running", nil, {}, nil
    MQ.Sync.dirty(nil, "all")
end

function Se.confirm(actor)
    local s = meta()
    if s.state ~= "review" or not s.frozen then return false, code("NOT_READY") end
    pay(s, actor)
    return true
end

Se.lastTick = Se.lastTick or 0

-- A pending payout always goes first, so a season can never freeze over an unpaid one.
function Se.tick(now)
    if now - Se.lastTick < 1000 or not MQ.Store.ready() then return end
    Se.lastTick = now
    local s = meta()
    if s.state == "paying" or (s.state == "review" and (now >= (s.reviewDeadlineMs or 0) or now >= s.endMs)) then
        pay(s, "auto")
    end
    if s.state == "running" and now >= s.endMs then freeze(s, now) end
end

-- ---------- registration ----------

MQ.Server.defineAdmin("season.preview", { kind = "query", fields = { days = "int" },
    run = function(ctx)
        local p, c = Se.previewLength(ctx.args.days)
        if not p then return false, c end
        return true, p
    end })

MQ.Server.defineAdmin("season.apply", { kind = "mutation", fields = { days = "int" },
    run = function(ctx)
        local p, c = Se.applyLength(ctx.args.days, ctx.user)
        if not p then return false, c end
        return true, { endMs = p.endMs }
    end })

MQ.Server.defineAdmin("season.review", { kind = "query",
    run = function() return true, Se.review() end })

MQ.Server.defineAdmin("season.exclude", { kind = "mutation", fields = { user = "str", on = "bool", reason = "text?" },
    run = function(ctx) return Se.exclude(ctx.args.user, ctx.args.on, ctx.args.reason, ctx.user) end })

MQ.Server.defineAdmin("season.confirm", { kind = "mutation",
    run = function(ctx) return Se.confirm(ctx.user) end })

MQ.Sync.provider("season", function() return Se.current() end)

if first then
    Events.OnTickEvenPaused.Add(function() MQ.Seasons.tick(getTimestampMs()) end)
end

return Se
