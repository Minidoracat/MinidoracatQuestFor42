-- MinidoracatQuestFor42 - achievements: effective list (built-in + overrides + custom "c:" + packs),
-- tier unlocks with points and titles, broadcasts (C27), revoke, and Import.baseline (spec A.6).
if isClient() then return end

MinidoracatQuest = MinidoracatQuest or {}
local MQ = MinidoracatQuest
require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Util"
require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Audit"
require "MinidoracatQuest/EventLog"
require "MinidoracatQuest/Sync"
require "MinidoracatQuest/Server"

local A = MQ.Achievements or {}
MQ.Achievements = A
local Imp = MQ.Import or {}
MQ.Import = Imp

A.TIER_STAT = "achv.tiers"

local function code(name) return MQ.Contract.CODE[name] end

-- Difficulty scales thresholds (C11): below 100 round to an integer, above to 2 significant digits;
-- the result stays strictly ascending.
function A.scale(tiers, mult)
    local out, prev = {}, 0
    for i, v in ipairs(tiers) do
        local s = v
        if mult ~= 1 then
            s = v * mult
            if s < 100 then
                s = math.floor(s + 0.5)
            else
                local mag = 1
                while s / mag >= 100 do mag = mag * 10 end
                s = math.floor(s / mag + 0.5) * mag
            end
        end
        if s <= prev then s = prev + 1 end
        out[i] = s
        prev = s
    end
    return out
end

-- tiers = effective thresholds (difficulty applied); base = thresholds before difficulty
local function merge(base, o, mult)
    o = o or {}
    local tiers = o.tiers or base.tiers
    return { id = base.id, cat = base.cat, stat = base.stat, icon = base.icon, hidden = base.hidden,
        scope = base.scope, name = base.name, nameKey = base.nameKey, custom = base.custom, base = tiers,
        tiers = A.scale(tiers, mult), pts = o.pts or base.pts or {}, titles = o.titles or base.titles or {} }
end

-- ---------- effective list (cached per effective config table and pack count) ----------

A.cache = A.cache or {}

local function packCount()
    local n = 0
    for _, p in pairs(MQ.Packs or {}) do n = n + #(p.achievements or {}) end
    return n
end

function A.list()
    local cfg, packs = MQ.Config.get(), packCount()
    local c = A.cache
    if c.list and c.cfg == cfg and c.packs == packs then return c.list, c.byStat end
    local mult = cfg.difficulty and cfg.difficulty.mult
    if type(mult) ~= "number" or mult <= 0 then mult = 1 end
    local ov = cfg.achievements or {}
    local list = {}
    for _, d in ipairs(MQ.Catalog.achievements) do
        local o = ov[d.id]
        if not (o and o.enabled == false) then list[#list + 1] = merge(d, o, mult) end
    end
    local keys = {}
    for k in pairs(cfg.custom or {}) do keys[#keys + 1] = k end
    MQ.Util.sort(keys, function(a, b) return a < b end)
    for _, k in ipairs(keys) do
        local d = cfg.custom[k]
        if type(d) == "table" and d.enabled ~= false and type(d.tiers) == "table" and #d.tiers > 0 then
            list[#list + 1] = merge({ id = "c:" .. k, cat = d.cat, stat = d.stat, name = d.name, custom = true,
                tiers = d.tiers, pts = d.pts, titles = d.titles }, nil, mult)
        end
    end
    local mods = {}
    for m in pairs(MQ.Packs or {}) do mods[#mods + 1] = m end
    MQ.Util.sort(mods, function(a, b) return a < b end)
    for _, m in ipairs(mods) do
        for _, d in ipairs(MQ.Packs[m].achievements or {}) do
            local o = ov[d.id]
            if not (o and o.enabled == false) then list[#list + 1] = merge(d, o, mult) end
        end
    end
    local byStat = {}
    for _, d in ipairs(list) do
        byStat[d.stat] = byStat[d.stat] or {}
        local b = byStat[d.stat]
        b[#b + 1] = d
    end
    A.cache = { list = list, byStat = byStat, cfg = cfg, packs = packs }
    return list, byStat
end

function A.get(id)
    for _, d in ipairs((A.list())) do
        if d.id == id then return d end
    end
    return nil
end

-- ---------- evaluation ----------

local function broadcastable(cfg, d, tier)
    local b = cfg.broadcast or {}
    if b.enabled == false then return false end
    local min = b.minTier or 3
    return tier >= min or (#d.tiers < min and tier == #d.tiers)
end

local function unlock(acc, user, d, from, to, quiet, cfg, now)
    acc.titles = acc.titles or {}
    for t = from + 1, to do
        local pts = d.pts[t] or 0
        if pts > 0 then MQ.Points.award(acc, user, pts, quiet and "import" or "achv", d.id .. ":" .. t) end
        local title = d.titles[t]
        if title then acc.titles[title] = true end
        if not quiet then
            acc.unseen = (acc.unseen or 0) + 1
            MQ.EventLog.write("achv", user, { id = d.id, tier = t, pts = pts })
            MQ.Sync.toast(user, { kind = "achv", id = d.id, tier = t, pts = pts })
            if broadcastable(cfg, d, t) then
                MQ.Sync.broadcastToast({ kind = "broadcast", who = not acc.anon and user or nil, id = d.id, tier = t,
                    titleId = title }, user)
            end
        end
    end
    acc.achv[d.id] = to
    if to >= #d.tiers then MQ.Sync.unpin(acc, user, "a:" .. d.id) end   -- nothing left to track
    MQ.Sync.dirty(user, "achv")
    if quiet then
        local total = 0
        for _, n in pairs(acc.achv) do total = total + n end
        MQ.Stats.seed(acc, user, A.TIER_STAT, total)
    elseif MQ.Stats.def(A.TIER_STAT) then
        MQ.Stats.add(user, A.TIER_STAT, to - from)
    end
end

-- opts = { stat = id (only that stat's achievements), quiet = true (import: lifetime points only) }
function A.evaluate(acc, user, opts)
    opts = opts or {}
    local list, byStat = A.list()
    if opts.stat then list = byStat[opts.stat] end
    if not list then return 0 end
    local cfg = MQ.Config.get()
    local now = getTimestampMs()
    local off = acc.achvOff or {}
    local n = 0
    for _, d in ipairs(list) do
        local cur = acc.achv[d.id] or 0
        local nextT = d.tiers[cur + 1]
        if nextT then
            local v = (acc.total[d.stat] or 0) - (off[d.id] or 0)
            if v >= nextT then
                local to = cur
                while d.tiers[to + 1] and v >= d.tiers[to + 1] do to = to + 1 end
                unlock(acc, user, d, cur, to, opts.quiet, cfg, now)
                n = n + to - cur
            end
        end
    end
    return n
end

function A.onStat(acc, user, stat, delta, opts)
    A.evaluate(acc, user, { stat = stat, quiet = opts and opts.quiet })
end

-- Revoke down to toTier (0 = all). Titles of the removed tiers and their points (season and lifetime;
-- the balance may be spent already) go away; progress restarts from the toTier threshold so the
-- same stat value does not unlock it again.
function A.revoke(user, achId, toTier, reason, actor)
    local acc = MQ.Store.account(user, false)
    if not acc then return false, code("NOT_FOUND") end
    local d = A.get(achId)
    local cur = acc.achv[achId] or 0
    if not d or cur == 0 then return false, code("NOT_FOUND") end
    if type(toTier) ~= "number" or toTier < 0 or toTier >= cur then return false, code("BAD_ARGS") end
    local lost = 0
    local worn = acc.title
    for t = toTier + 1, cur do
        lost = lost + (d.pts[t] or 0)
        local title = d.titles[t]
        if title and acc.titles then
            acc.titles[title] = nil
            if acc.title == title then acc.title = nil end
        end
    end
    if acc.title ~= worn then MQ.Sync.titleChanged(user, acc) end
    local p = acc.points
    p.season = math.max(0, p.season - lost)
    p.total = math.max(0, p.total - lost)
    acc.achv[achId] = toTier > 0 and toTier or nil
    acc.achvOff = acc.achvOff or {}
    acc.achvOff[achId] = math.max(0, (acc.total[d.stat] or 0) - (toTier > 0 and d.tiers[toTier] or 0))
    if MQ.Boards then MQ.Boards.dirty("@points") MQ.Boards.dirty(A.TIER_STAT) end
    MQ.Audit.add("revoke", actor, user, { id = achId, from = cur, to = toTier, reason = reason, pts = lost })
    MQ.EventLog.write("revoke", user, { id = achId, from = cur, to = toTier, pts = lost, actor = actor })
    MQ.Sync.dirty(user, "all")
    return true
end

-- ---------- import (spec A.6): once per account, lifetime only, silent ----------

function Imp.baseline(acc, user, player)
    if acc.imported then return end
    acc.imported = true
    local S = MQ.Stats
    local hours = player:getHoursSurvived() or 0
    -- the vanilla count is this character's, so it is this life's too: pacifist.days must not see a killer as clean
    S.seed(acc, user, "zombie.kills", player:getZombieKills() or 0, true)
    S.seed(acc, user, "life.days", math.floor(hours / 24))
    local sum, best = 0, 0
    for _, id in ipairs(MQ.Catalog.perks or {}) do
        local perk = Perks.FromString(id)
        local lv = perk and player:getPerkLevel(perk) or 0
        if lv > 0 then S.seed(acc, user, "level." .. id, lv) end
        sum = sum + lv
        if lv > best then best = lv end
    end
    S.seed(acc, user, "skill.total", sum)
    S.seed(acc, user, "skill.max", best)
    A.evaluate(acc, user, { quiet = true })
    local veteran = hours >= 24
    for _, step in ipairs(MQ.Catalog.newbie or {}) do
        if (acc.total[step.stat] or 0) >= step.target then veteran = true end
    end
    if veteran then acc.newbie = nil end
    MQ.Sync.dirty(user, "all")
end

MQ.Server.defineAdmin("achv.revoke", { kind = "mutation",
    fields = { user = "str", achId = "str", tier = "int", reason = "text" },
    run = function(ctx)
        local a = ctx.args
        if a.reason == "" then return false, code("BAD_ARGS") end
        return A.revoke(a.user, a.achId, a.tier, a.reason, ctx.user)
    end })

MQ.Stats.listen("achievements", A.onStat)

return A
