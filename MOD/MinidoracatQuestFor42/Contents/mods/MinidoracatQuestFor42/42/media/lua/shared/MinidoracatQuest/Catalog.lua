-- MinidoracatQuest/Catalog.lua: built-in data (docs/ARCHITECTURE.md section 4).
-- Pure data plus small lookups; both sides load it. Display text comes from keys derived from ids.

require "MinidoracatQuest/Contract"

MinidoracatQuest = MinidoracatQuest or {}
local Q = MinidoracatQuest
local C = Q.Contract
local Cat = {}
Q.Catalog = Cat

Cat.themes = C.THEMES
Cat.achCats = C.ACH_CATS
Cat.boardCats = C.BOARD_CATS
Cat.DIFFICULTY = { easy = 0.6, normal = 1, hard = 1.6 }

-- 42.21.0 PerkFactory.init() leaf perks (PerkFactory.java:98-141); ids are perk:getId().
Cat.perks = {
    "Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance",
    "Aiming", "Reloading",
    "Woodwork", "Carving", "Cooking", "Electricity", "Glassmaking", "FlintKnapping", "Masonry",
    "Blacksmith", "Mechanics", "Pottery", "Tailoring", "MetalWelding",
    "Doctor", "Fishing", "PlantScavenging", "Tracking", "Trapping",
    "Fitness", "Strength", "Lightfoot", "Nimble", "Sprinting", "Sneak",
    "Farming", "Husbandry", "Butchering",
}

-- Stats. ceil = per real minute (count stats only); kind "max" ignores it.
-- account = true: kept per account only (no "this life" value; Stats writes no life scope, records show "-").
Cat.stats = {}
Cat.statOrder = {}
local function S(id, kind, ceil, unit, account)
    Cat.stats[id] = { id = id, kind = kind, ceil = ceil, unit = unit or "count", account = account }
    Cat.statOrder[#Cat.statOrder + 1] = id
end

S("zombie.kills", "count", 120)
S("zombie.kills.melee", "count", 120)
S("zombie.kills.firearm", "count", 120)
S("zombie.kills.vehicle", "count", 120)
S("zombie.kills.axe", "count", 120)
S("zombie.kills.blunt", "count", 120)
S("zombie.kills.smallblunt", "count", 120)
S("zombie.kills.longblade", "count", 120)
S("zombie.kills.smallblade", "count", 120)
S("zombie.kills.spear", "count", 120)
S("zombie.kills.improvised", "count", 120)
S("zombie.kills.unarmed", "count", 60)
S("zombie.kills.night", "count", 120)
S("zombie.kills.indoor", "count", 120)
S("zombie.kills.rain", "count", 120)
S("kills.dayBest", "max")
S("hunt.kills", "count", 20)
S("life.days", "max", nil, "days")
S("survive.days", "count", 5, "days")
S("pacifist.days", "max", nil, "days")
S("deaths", "count", 3)
S("skill.total", "max", nil, "level")
S("skill.max", "max", nil, "level")
S("xp.total", "count", 5000, "xp")
S("craft.count", "count", 60)
S("build.count", "count", 30)
S("cook.count", "count", 30)
S("sew.count", "count", 30)
S("smith.count", "count", 30)
S("knap.count", "count", 30)
S("carve.count", "count", 30)
S("mech.repair", "count", 20)
S("mech.install", "count", 20)
S("power.count", "count", 10)
S("scrap.count", "count", 60)
S("book.read", "count", 10)
S("bandage.count", "count", 30)
S("medic.count", "count", 30)
S("sleep.indoor", "count", 2)
S("sleep.outdoor", "count", 2)
S("barricade.count", "count", 30)
S("corpse.count", "count", 60)
S("wash.count", "count", 10)
S("plant.count", "count", 120)
S("farm.harvest", "count", 120)
S("fish.caught", "count", 6)
S("fish.night", "count", 6)
S("trap.caught", "count", 20)
S("forage.count", "count", 60)
S("butcher.count", "count", 10)
S("milk.count", "count", 20)
S("shear.count", "count", 10)
S("egg.count", "count", 30)
S("tree.chop", "count", 10)
S("walk.km", "count", 2, "km")
S("drive.km", "count", 4, "km")
S("speed.max", "max")
S("furniture.placed", "count", 60)
S("town.visited", "count", 5)
S("newbie.leave", "count", 1)
-- Fed by Systems; account-level (quests, achievements, seasons follow the account, not the character).
S("quest.daily", "count", 1000, nil, true)
S("quest.weekly", "count", 1000, nil, true)
S("streak.best", "max", nil, "days", true)
S("achv.tiers", "count", 1000, nil, true)
S("goal.done", "count", 1000, nil, true)
S("season.joined", "count", 1000, nil, true)
for _, p in ipairs(Cat.perks) do S("level." .. p, "max", nil, "level") end
for _, p in ipairs(Cat.perks) do S("xp." .. p, "count", 5000, "xp") end

function Cat.statKey(id)
    return "IGUI_MQ_Stat_" .. string.gsub(id, "%.", "_")
end

-- Achievements. Built-in: 4 tiers, title at tier 4; hidden: 1 tier.
Cat.achievements = {}
local PTS4 = { 10, 20, 30, 50 }
local HIDDEN_PTS = 30
local function A(id, cat, stat, tiers, scope)
    local titles = {}
    titles[4] = id .. "_4"
    Cat.achievements[#Cat.achievements + 1] = { id = id, cat = cat, stat = stat, tiers = tiers, pts = PTS4,
        titles = titles, icon = id, scope = scope }
end
local function H(id, stat, n, titled, scope)
    local titles = {}
    if titled then titles[1] = id end
    Cat.achievements[#Cat.achievements + 1] = { id = id, cat = "hidden", stat = stat, tiers = { n },
        pts = { HIDDEN_PTS }, titles = titles, icon = id, hidden = true, scope = scope }
end

for _, p in ipairs(Cat.perks) do
    local passive = p == "Fitness" or p == "Strength"
    A("skill_" .. string.lower(p), "skill", "level." .. p, passive and { 6, 7, 9, 10 } or { 3, 5, 8, 10 })
end
A("skill_total", "skill", "skill.total", { 30, 70, 140, 220 })
A("xp_total", "skill", "xp.total", { 1000, 10000, 50000, 200000 })

A("zombie_kills", "combat", "zombie.kills", { 100, 1000, 5000, 20000 })
A("kills_melee", "combat", "zombie.kills.melee", { 50, 500, 2500, 10000 })
A("kills_firearm", "combat", "zombie.kills.firearm", { 50, 500, 2500, 10000 })
A("kills_vehicle", "combat", "zombie.kills.vehicle", { 10, 100, 500, 2000 })
A("kills_axe", "combat", "zombie.kills.axe", { 25, 250, 1000, 5000 })
A("kills_blunt", "combat", "zombie.kills.blunt", { 25, 250, 1000, 5000 })
A("kills_smallblunt", "combat", "zombie.kills.smallblunt", { 25, 250, 1000, 5000 })
A("kills_longblade", "combat", "zombie.kills.longblade", { 25, 250, 1000, 5000 })
A("kills_smallblade", "combat", "zombie.kills.smallblade", { 25, 250, 1000, 5000 })
A("kills_spear", "combat", "zombie.kills.spear", { 25, 250, 1000, 5000 })
A("kills_improvised", "combat", "zombie.kills.improvised", { 25, 250, 1000, 5000 })
A("kills_night", "combat", "zombie.kills.night", { 50, 500, 2500, 10000 })
A("kills_indoor", "combat", "zombie.kills.indoor", { 25, 250, 1000, 5000 })
A("hunt", "combat", "hunt.kills", { 1, 10, 50, 200 })

A("life_days", "survival", "life.days", { 7, 30, 100, 365 }, "life")
A("survive_days", "survival", "survive.days", { 7, 30, 100, 365 })
A("bandage", "survival", "bandage.count", { 10, 50, 200, 1000 })
A("medic", "survival", "medic.count", { 5, 25, 100, 400 })
A("sleep_indoor", "survival", "sleep.indoor", { 5, 25, 100, 365 })
A("barricade", "survival", "barricade.count", { 10, 50, 200, 800 })
A("corpses", "survival", "corpse.count", { 10, 100, 500, 2000 })
A("wash", "survival", "wash.count", { 10, 50, 200, 600 })

A("craft", "production", "craft.count", { 25, 250, 1000, 5000 })
A("build", "production", "build.count", { 10, 100, 500, 2000 })
A("cook", "production", "cook.count", { 10, 100, 500, 2000 })
A("sew", "production", "sew.count", { 10, 50, 250, 1000 })
A("smith", "production", "smith.count", { 5, 50, 250, 1000 })
A("knap", "production", "knap.count", { 5, 50, 250, 1000 })
A("carve", "production", "carve.count", { 5, 50, 250, 1000 })
A("mech_repair", "production", "mech.repair", { 5, 25, 100, 400 })
A("mech_install", "production", "mech.install", { 5, 50, 200, 800 })
A("power", "production", "power.count", { 1, 10, 50, 200 })
A("scrap", "production", "scrap.count", { 10, 100, 500, 2000 })

A("plant", "nature", "plant.count", { 25, 250, 1000, 5000 })
A("harvest", "nature", "farm.harvest", { 25, 250, 1000, 5000 })
A("fish", "nature", "fish.caught", { 5, 25, 100, 400 })
A("forage", "nature", "forage.count", { 25, 250, 1000, 5000 })
A("trap", "nature", "trap.caught", { 5, 25, 100, 400 })
A("butcher", "nature", "butcher.count", { 3, 25, 100, 400 })
A("milk", "nature", "milk.count", { 5, 50, 200, 800 })
A("shear", "nature", "shear.count", { 3, 25, 100, 400 })
A("egg", "nature", "egg.count", { 10, 100, 500, 2000 })
A("chop", "nature", "tree.chop", { 10, 100, 500, 2000 })

A("towns", "explore", "town.visited", { 2, 5, 8, 11 })
A("walk", "explore", "walk.km", { 10, 100, 500, 2000 })
A("drive", "explore", "drive.km", { 50, 250, 1000, 5000 })
A("read", "explore", "book.read", { 5, 25, 100, 300 })
A("furniture", "explore", "furniture.placed", { 10, 100, 500, 2000 })

A("daily", "quest", "quest.daily", { 10, 50, 200, 500 })
A("weekly", "quest", "quest.weekly", { 3, 15, 50, 150 })
A("streak", "quest", "streak.best", { 3, 7, 30, 100 })
A("goal", "quest", "goal.done", { 1, 5, 15, 40 })
A("season", "quest", "season.joined", { 1, 3, 6, 12 })
A("achv_tiers", "quest", "achv.tiers", { 10, 50, 150, 300 })

H("h_first_blood", "zombie.kills", 1)
H("h_unarmed", "zombie.kills.unarmed", 1, true)
H("h_rain", "zombie.kills.rain", 50)
H("h_hundred", "kills.dayBest", 100, true)
H("h_extinction", "zombie.kills", 100000, true)
H("h_marathon", "walk.km", 42, true)
H("h_speed", "speed.max", 120)
H("h_outdoor_sleep", "sleep.outdoor", 1)
H("h_pacifist", "pacifist.days", 7, true, "life")
H("h_first_death", "deaths", 1)
H("h_nine_lives", "deaths", 9, true)
H("h_lights", "power.count", 1)
H("h_night_fish", "fish.night", 1)
H("h_peak", "skill.max", 10, true)
H("h_all_towns", "town.visited", 12, true)
H("h_first_hunt", "hunt.kills", 1)

-- Daily templates (section 4.4). rare = 20 pts by default; shared = false keeps it out of the shared pick.
Cat.daily = {}
local function D(tid, theme, stat, lo, hi, step, rare, solo)
    local t = { tid = tid, theme = theme, stat = stat, target = { lo, hi }, step = step, rare = rare }
    if solo then t.shared = false end
    Cat.daily[#Cat.daily + 1] = t
end
D("d_kill", "combat", "zombie.kills", 20, 40, 5)
D("d_kill_melee", "combat", "zombie.kills.melee", 15, 30, 5)
D("d_kill_firearm", "combat", "zombie.kills.firearm", 10, 20, 5, nil, true)
D("d_kill_night", "combat", "zombie.kills.night", 10, 20, 5)
D("d_build", "build", "build.count", 5, 10, 1)
D("d_barricade", "build", "barricade.count", 3, 6, 1)
D("d_furniture", "build", "furniture.placed", 3, 6, 1)
D("d_scrap", "build", "scrap.count", 5, 10, 1)
D("d_craft", "craft", "craft.count", 5, 10, 1)
D("d_carve", "craft", "carve.count", 2, 4, 1)
D("d_knap", "craft", "knap.count", 2, 4, 1)
D("d_smith", "craft", "smith.count", 1, 3, 1, nil, true)
D("d_cook", "cook", "cook.count", 3, 6, 1)
D("d_cook_more", "cook", "cook.count", 8, 12, 1, nil, true)
D("d_cook_xp", "cook", "xp.Cooking", 75, 150, 25)
D("d_sew", "tailor", "sew.count", 2, 4, 1, true)
D("d_tailor_xp", "tailor", "xp.Tailoring", 50, 100, 25, true)
D("d_wash", "tailor", "wash.count", 2, 4, 1, true)
D("d_plant", "farm", "plant.count", 10, 20, 5)
D("d_harvest", "farm", "farm.harvest", 10, 20, 5)
D("d_farm_xp", "farm", "xp.Farming", 50, 100, 25)
D("d_milk", "animal", "milk.count", 2, 4, 1, true, true)
D("d_egg", "animal", "egg.count", 3, 6, 1, true, true)
D("d_shear", "animal", "shear.count", 1, 2, 1, true, true)
D("d_butcher", "animal", "butcher.count", 1, 2, 1, true, true)
D("d_animal_xp", "animal", "xp.Husbandry", 50, 100, 25, true, true)
D("d_fish", "fishtrap", "fish.caught", 3, 5, 1, true)
D("d_trap", "fishtrap", "trap.caught", 1, 3, 1, true)
D("d_fish_xp", "fishtrap", "xp.Fishing", 50, 100, 25, true)
D("d_forage", "forage", "forage.count", 10, 20, 5, true)
D("d_chop", "forage", "tree.chop", 3, 6, 1, true)
D("d_forage_xp", "forage", "xp.PlantScavenging", 50, 100, 25, true)
D("d_mech_repair", "mech", "mech.repair", 1, 3, 1, nil, true)
D("d_mech_install", "mech", "mech.install", 2, 4, 1)
D("d_power", "mech", "power.count", 1, 2, 1, nil, true)
D("d_mech_xp", "mech", "xp.Mechanics", 50, 100, 25)
D("d_walk", "explore", "walk.km", 3, 6, 1)
D("d_drive", "explore", "drive.km", 10, 20, 5)
D("d_read", "explore", "book.read", 1, 2, 1)

Cat.weekly = {}
local function W(tid, theme, stat, lo, hi, step)
    Cat.weekly[#Cat.weekly + 1] = { tid = tid, theme = theme, stat = stat, target = { lo, hi }, step = step }
end
W("w_kill", "combat", "zombie.kills", 120, 180, 10)
W("w_kill_melee", "combat", "zombie.kills.melee", 80, 120, 10)
W("w_craft", "craft", "craft.count", 25, 40, 5)
W("w_build", "build", "build.count", 20, 30, 5)
W("w_cook", "cook", "cook.count", 15, 25, 5)
W("w_harvest", "farm", "farm.harvest", 40, 60, 5)
W("w_fish", "fishtrap", "fish.caught", 10, 15, 1)
W("w_forage", "forage", "forage.count", 40, 60, 5)
W("w_mech", "mech", "mech.install", 8, 12, 1)
W("w_drive", "explore", "drive.km", 30, 50, 5)
W("w_walk", "explore", "walk.km", 15, 25, 5)
W("w_read", "explore", "book.read", 3, 5, 1)

Cat.newbie = {
    { stat = "zombie.kills", target = 5 },
    { stat = "craft.count", target = 1 },
    { stat = "book.read", target = 1 },
    { stat = "newbie.leave", target = 1 },
    { stat = "sleep.indoor", target = 1 },
}

-- Boards (section 4.5). "@points" = points earned.
Cat.boards = {}
local BOTH = { "season", "total" }
local function B(id, cat, stat, periods)
    Cat.boards[#Cat.boards + 1] = { id = id, cat = cat, stat = stat, periods = periods or BOTH }
end
B("points", "overall", "@points")
B("kills", "combat", "zombie.kills")
B("kills_melee", "combat", "zombie.kills.melee")
B("kills_firearm", "combat", "zombie.kills.firearm")
B("life_days", "survival", "life.days")
B("skill_total", "skill", "skill.total", { "total" })
B("xp", "skill", "xp.total")
B("crafted", "life", "craft.count")
B("built", "life", "build.count")
B("harvested", "life", "farm.harvest")
B("fish", "life", "fish.caught")
B("drive_km", "life", "drive.km")
B("towns", "explore", "town.visited")
B("daily_done", "quest", "quest.daily")
B("streak_best", "quest", "streak.best")
B("achv_tiers", "quest", "achv.tiers")

-- Built-in towns (section 4.6). World square coords, inclusive.
-- Sources (42.21.0 vanilla): label centres media/maps/Muldraugh, KY/worldmap-annotations.lua, town points
-- in worldmap.xml, each map's spawnpoints.lua and POIData.lua building positions. Except muldraugh (design
-- draft, all spawns and POIs inside) and louisville (ISMapDefinitions.lua:472-490 treasure-map extent),
-- each rect is the POI/spawn bounding box padded by 100 squares.
-- Rect fields are named, same shape as config towns.custom (Config.lua townsCustom).
local function R(x1, y1, x2, y2) return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end
Cat.towns = {
    { id = "muldraugh", rects = { R(10540, 9240, 11160, 10760) } },
    { id = "west_point", rects = { R(10830, 6500, 12600, 7400) } },
    { id = "riverside", rects = { R(5631, 5104, 6917, 5662) } },
    { id = "rosewood", rects = { R(7722, 11037, 8595, 12494), R(7412, 11601, 7794, 11970) } },
    { id = "louisville", rects = { R(11700, 750, 14699, 3899) } },
    { id = "brandenburg", rects = { R(1897, 5637, 2342, 6534) } },
    { id = "ekron", rects = { R(240, 9585, 913, 10042) } },
    { id = "irvington", rects = { R(1744, 14024, 2649, 14591) } },
    { id = "echo_creek", rects = { R(3296, 10791, 3816, 11054) } },
    { id = "fallas_lake", rects = { R(7063, 8027, 7588, 8707) } },
    { id = "march_ridge", rects = { R(9780, 12500, 10291, 12923) } },
    { id = "valley_station", rects = { R(12425, 5109, 12740, 5432) } },
}

-- Lookups.
local achById, tplById, boardById = {}, {}, {}
for _, a in ipairs(Cat.achievements) do achById[a.id] = a end
for _, t in ipairs(Cat.daily) do tplById[t.tid] = t end
for _, t in ipairs(Cat.weekly) do tplById[t.tid] = t end
for _, b in ipairs(Cat.boards) do boardById[b.id] = b end
function Cat.ach(id) return achById[id] end
function Cat.tpl(tid) return tplById[tid] end
function Cat.board(id) return boardById[id] end

-- Defaults (section 3.4). Every built-in achievement and template gets a full entry.
local function copy(t)
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    return r
end

local D_PTS, RARE_PTS, W_PTS = 15, 20, 60
local dailyPool, weeklyPool, achDefaults = {}, {}, {}
for _, t in ipairs(Cat.daily) do
    dailyPool[t.tid] = { enabled = true, target = copy(t.target), pts = t.rare and RARE_PTS or D_PTS }
end
for _, t in ipairs(Cat.weekly) do
    weeklyPool[t.tid] = { enabled = true, target = copy(t.target), pts = W_PTS }
end
for _, a in ipairs(Cat.achievements) do
    achDefaults[a.id] = { enabled = true, tiers = copy(a.tiers), pts = copy(a.pts), titles = copy(a.titles) }
end

Cat.DEFAULTS = {
    daily = { swapsPerDay = 1, pts = D_PTS, rarePts = RARE_PTS, sharedPts = 20, pool = dailyPool },
    weekly = { count = 3, pts = W_PTS, pool = weeklyPool },
    goal = { enabled = true, pts = 50, growth = 1.1,
        rotation = { "zombie.kills", "craft.count", "drive.km", "fish.caught", "farm.harvest" },
        limits = {
            ["zombie.kills"] = { min = 2000, max = 100000, minContrib = 50 },
            ["craft.count"] = { min = 300, max = 20000, minContrib = 10 },
            ["drive.km"] = { min = 300, max = 20000, minContrib = 10 },
            ["fish.caught"] = { min = 30, max = 2000, minContrib = 2 },
            ["farm.harvest"] = { min = 300, max = 10000, minContrib = 10 },
        } },
    streak = { need = 3, gracePerWeek = 1, milestones = {
        { days = 3, pts = 15 }, { days = 7, pts = 40 }, { days = 14, pts = 80 },
        { days = 30, pts = 150, title = "streak_30" } } },
    newbie = { enabled = true, pts = 100, title = "newbie", days = 7 },
    achievements = achDefaults,
    custom = {},
    difficulty = { preset = "normal", mult = 1 },
    season = { lengthDays = 28 },
    rewards = { top1 = 600, top3 = 400, top10 = 200, participation = 100, participationMin = 250, firstTitles = true },
    exchange = { enabled = true, rate = 1, perDay = 100, min = 10 },
    broadcast = { enabled = true, minTier = 3, perMinute = 1 },
    titles = { head = true, chat = true },   -- the worn title over heads and after the name in chat
    boards = { inactiveDays = 180, rebuildSeasonMs = 300000, rebuildTotalMs = 1800000 },
    towns = { custom = {}, disabled = {} },
    ceilings = {},
}
