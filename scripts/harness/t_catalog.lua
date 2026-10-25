-- Catalog slice: data consistency (Catalog.lua + Translate/EN/IG_UI.json), Towns lookup, Trackers hooks.
return function(T)
    -- engine fakes this slice needs (only when another slice has not defined them)
    T.hour = 12
    T.raining = false
    getGameTime = getGameTime or function()
        return { getHour = function() return T.hour end, getWorldAgeHours = function() return 100 end }
    end
    RainManager = RainManager or { isRaining = function() return T.raining end }
    getNumActivePlayers = getNumActivePlayers or function() return #T.online end

    -- fake vanilla timed actions (installed before OnServerStarted so Trackers wraps them)
    local history = {}
    -- vanilla shape (ISHandcraftAction.lua:221-223): only logic:performCurrentRecipe() says whether it ran;
    -- the follow-up calls go through the same logic object (the wrapper's proxy must forward them)
    local function fakeClasses()
        ISHandcraftAction = {
            performRecipe = function(self)
                if self.logic and self.logic:performCurrentRecipe() then
                    self.logic:getRecipeData():luaCallOnCreate(self.character)
                end
                return "craft-result"
            end,
        }
        ISReadABook = { complete = function() return "read-result" end }
        ISMoveablesAction = { complete = function() return true end }
        ISBuildIsoEntity = {
            create = function(self) if self.ok then self:updateModData() end return nil end,
            updateModData = function() end,
        }
        ISPickupFishAction = { complete = function() return true end }
        ISHutchGrabEgg = { animEvent = function() return "egg-event" end,
            update = function(self) self.lastTimer = self.lastTimer + 2 end }
        -- milk()/shearAnimal take from the animal per tick; complete() returns true either way (ISMilkAnimal.lua:195-198)
        ISMilkAnimal = { milk = function(self) self.animal.milk = self.animal.milk - (self.take or 0) end,
            complete = function() return true end }
        ISShearAnimal = { animEvent = function(self) self.animal.wool = self.animal.wool - (self.take or 0) end,
            update = function() end, complete = function() return true end }
        -- false when another character holds the hook (ISCutAnimalOnHook.lua:61-64)
        ISCutAnimalOnHook = { complete = function(self) return self.ok end }
    end
    local function logic(ok, name)
        local data = { luaCallOnCreate = function(d, who) d.created = who end }
        return { data = data, getRecipeData = function(l) return l.data end,
            performCurrentRecipe = function()
                if ok then history[name] = (history[name] or 0) + 1 end
                return ok
            end }
    end

    local function recipe(name, cat, smith)
        return { name = name,
            getName = function(self) return self.name end,
            getCategory = function() return cat end,
            isSmithing = function() return smith == true end,
            involvesSkill = function() return false end }
    end
    local function human(p)
        p.isAnimal = function() return false end
        p.getVehicle = function(self) return self.veh end
        p.getPrimaryHandItem = function(self) return self.hand end
        p.isAsleep = function(self) return self.asleep == true end
        p.isOutside = function(self) return self.outside == true end
        p.getPerkLevel = function(self, perk) return self.levels[perk:getId()] or 0 end
        -- engine: CraftHistoryEntry is not exposed to Lua, so getCraftCount() fails (LuaManager.java:1832)
        p.getPlayerCraftHistory = function()
            return { getCraftHistoryFor = function() return {} end }
        end
        p.levels = {}
        return p
    end
    local function weapon(cat, ranged)
        return { __class = "HandWeapon",
            isRanged = function() return ranged == true end,
            getScriptItem = function() return { containsWeaponCategory = function(_, c) return c == cat end } end }
    end
    local function zombie(killer, sq)
        return { __class = "IsoZombie",
            getAttackedBy = function() return killer end,
            getCurrentSquare = function() return sq end }
    end

    -- ===================== data =====================
    T.section("catalog: data consistency")
    local Q = T.boot({ beforeStart = fakeClasses })
    local Cat = Q.Catalog
    local stats = Cat.stats

    local function isIn(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
    local function isInt(n) return type(n) == "number" and n == math.floor(n) end

    local nStats = 0
    for id, d in pairs(stats) do
        nStats = nStats + 1
        T.check(d.id == id and (d.kind == "count" or d.kind == "max"), "stat shape " .. id)
        if d.kind == "count" then T.check(isInt(d.ceil) and d.ceil > 0, "count stat has ceil " .. id) end
    end
    T.check(nStats == #Cat.statOrder, "statOrder lists every stat once")
    T.check(#Cat.perks == 35, "35 perks (42.21.0 PerkFactory.init)")
    for _, p in ipairs(Cat.perks) do T.check(stats["level." .. p] ~= nil and stats["xp." .. p] ~= nil, "perk stats " .. p) end

    local seen, perCat = {}, {}
    for _, a in ipairs(Cat.achievements) do
        T.check(not seen[a.id], "achievement id unique " .. a.id)
        seen[a.id] = true
        perCat[a.cat] = (perCat[a.cat] or 0) + 1
        T.check(isIn(Cat.achCats, a.cat), "achievement cat " .. a.id)
        T.check(stats[a.stat] ~= nil, "achievement stat exists " .. a.id)
        T.check(#a.tiers >= 1 and #a.tiers <= 10 and #a.pts == #a.tiers, "tiers/pts sizes " .. a.id)
        local inc = true
        for i, x in ipairs(a.tiers) do
            if not isInt(x) or x < 1 or (i > 1 and x <= a.tiers[i - 1]) then inc = false end
        end
        T.check(inc, "tiers strictly increasing " .. a.id)
        for k in pairs(a.titles) do T.check(isInt(k) and k >= 1 and k <= #a.tiers, "title tier in range " .. a.id) end
        if a.hidden then T.check(#a.tiers == 1 and a.cat == "hidden", "hidden has one tier " .. a.id) end
        T.check(a.icon == a.id, "icon = id " .. a.id)
        local d = Cat.DEFAULTS.achievements[a.id]
        T.check(d ~= nil and d.enabled == true and #d.tiers == #a.tiers and d.tiers ~= a.tiers, "DEFAULTS copy " .. a.id)
    end
    T.check(#Cat.achievements >= 105 and #Cat.achievements <= 115, "achievement count 105..115 (" .. #Cat.achievements .. ")")
    T.check(perCat.skill == 37 and perCat.hidden == 16, "skill 37, hidden 16")
    -- five default tiers: 10/20/30/50/80 points, title at IV only; tier V never over a stat's ceiling
    local nTiers, nTitles, nPts, five = 0, 0, 0, true
    for _, a in ipairs(Cat.achievements) do
        nTiers = nTiers + #a.tiers
        for _ in pairs(a.titles) do nTitles = nTitles + 1 end
        for _, p in ipairs(a.pts) do nPts = nPts + p end
        if not a.hidden then
            local p = a.pts
            five = five and #a.tiers == 5 and p[1] == 10 and p[2] == 20 and p[3] == 30 and p[4] == 50 and p[5] == 80
                and a.titles[4] == a.id .. "_4" and a.titles[5] == nil
            if string.sub(a.stat, 1, 6) == "level." then five = five and a.tiers[5] == 10 end
        end
    end
    T.check(five, "regular achievements: 5 tiers, 10/20/30/50/80, title at IV only, skill levels top at 10")
    T.check(nTiers == 471 and nTitles == 99 and nPts == 17770,
        "471 tiers, 99 titles, 17,770 points (" .. nTiers .. ", " .. nTitles .. ", " .. nPts .. ")")
    T.check(Cat.ach("skill_total").tiers[5] <= 10 * #Cat.perks and Cat.ach("towns").tiers[5] < Cat.ach("h_all_towns").tiers[1]
        and Cat.ach("achv_tiers").tiers[5] <= nTiers, "tier V within the ceiling: skill total, towns, achievement tiers")
    T.check(not Cat.scalable("level.Axe") and not Cat.scalable("skill.total") and not Cat.scalable("town.visited")
        and Cat.scalable("zombie.kills"), "difficulty skips ceiling stats")
    local filled = Cat.fillPts({ 1, 2, 3, 4 }, { 10, 20, 30, 50, 80 }, 5)
    T.check(#filled == 5 and filled[4] == 4 and filled[5] == 80 and #Cat.fillPts({ 1, 2 }, { 10, 20, 30 }, 2) == 2,
        "a 4-entry points override keeps the default tier V points")

    local tids, themeCount = {}, {}
    for _, list in ipairs({ Cat.daily, Cat.weekly }) do
        for _, t in ipairs(list) do
            T.check(not tids[t.tid], "template id unique " .. t.tid)
            tids[t.tid] = true
            T.check(isIn(Cat.themes, t.theme), "template theme " .. t.tid)
            T.check(stats[t.stat] ~= nil and stats[t.stat].kind == "count", "template stat is a count " .. t.tid)
            T.check(isInt(t.target[1]) and isInt(t.target[2]) and t.target[1] >= 1 and t.target[1] <= t.target[2],
                "template target " .. t.tid)
            T.check(isInt(t.step) and t.step >= 1, "template step " .. t.tid)
        end
    end
    for _, t in ipairs(Cat.daily) do
        themeCount[t.theme] = (themeCount[t.theme] or 0) + 1
        local d = Cat.DEFAULTS.daily.pool[t.tid]
        T.check(d ~= nil and d.pts == (t.rare and 20 or 15), "daily pool default " .. t.tid)
    end
    for _, th in ipairs(Cat.themes) do T.check((themeCount[th] or 0) >= 3, "theme has >= 3 daily templates " .. th) end
    local weekTheme = {}
    for _, t in ipairs(Cat.weekly) do
        weekTheme[t.theme] = true
        T.check(Cat.DEFAULTS.weekly.pool[t.tid] ~= nil, "weekly pool default " .. t.tid)
    end
    -- genWeek picks a theme first; a theme with no weekly template fell back to any template (sewing, animal care)
    for _, th in ipairs(Cat.themes) do T.check(weekTheme[th] == true, "theme has a weekly template " .. th) end
    -- xp.* counts XP after the profession multiplier: one shared target would favour one profession
    for _, t in ipairs(Cat.daily) do
        if string.sub(t.stat, 1, 3) == "xp." then T.check(t.shared == false, "xp daily stays out of the shared pick " .. t.tid) end
    end
    T.check(#Cat.newbie == 5, "5 newbie steps")
    for _, s in ipairs(Cat.newbie) do T.check(stats[s.stat] ~= nil, "newbie stat " .. s.stat) end
    for _, s in ipairs(Cat.DEFAULTS.goal.rotation) do
        T.check(stats[s] ~= nil and Cat.DEFAULTS.goal.limits[s] ~= nil, "goal rotation stat + limits " .. s)
    end

    T.check(#Cat.boards == 16, "16 boards")
    local bseen = {}
    for _, b in ipairs(Cat.boards) do
        T.check(not bseen[b.id], "board id unique " .. b.id)
        bseen[b.id] = true
        T.check(isIn(Cat.boardCats, b.cat), "board cat " .. b.id)
        T.check(b.stat == "@points" or stats[b.stat] ~= nil, "board stat " .. b.id)
    end
    T.check(#Cat.board("skill_total").periods == 1, "skill_total is total-only")

    T.check(#Cat.towns >= 12, "at least 12 towns")
    local townSeen = {}
    for _, t in ipairs(Cat.towns) do
        T.check(not townSeen[t.id], "town id unique " .. t.id)
        townSeen[t.id] = true
        for _, r in ipairs(t.rects) do
            T.check(isInt(r.x1) and isInt(r.y1) and isInt(r.x2) and isInt(r.y2) and r.x1 >= 0 and r.y1 >= 0
                and r.x2 <= 100000 and r.y2 <= 100000 and r.x1 <= r.x2 and r.y1 <= r.y2, "town rect legal " .. t.id)
        end
    end
    T.check(Cat.ach("h_all_towns").tiers[1] == #Cat.towns, "h_all_towns threshold = built-in town count")

    -- every derived translation key exists in Translate/EN/IG_UI.json (temp/i18n was merged into Translate/)
    local path = "MOD/MinidoracatQuestFor42/Contents/mods/MinidoracatQuestFor42/42/media/lua/shared/Translate/EN/IG_UI.json"
    local f = io.open(path, "r")
    T.check(f ~= nil, "Translate/EN/IG_UI.json exists")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    local missing = {}
    local function key(k) if not string.find(text, '"' .. k .. '": "', 1, true) then missing[#missing + 1] = k end end
    for _, x in ipairs(Cat.themes) do key("IGUI_MQ_Theme_" .. x) end
    for _, x in ipairs(Cat.achCats) do key("IGUI_MQ_AchCat_" .. x) end
    for _, x in ipairs(Cat.boardCats) do key("IGUI_MQ_BoardCat_" .. x) end
    for _, id in ipairs(Cat.statOrder) do key(Cat.statKey(id)) end
    for _, a in ipairs(Cat.achievements) do
        key("IGUI_MQ_Ach_" .. a.id)
        key("IGUI_MQ_AchDesc_" .. a.id)
        if a.hidden then key("IGUI_MQ_AchHint_" .. a.id) end
        for _, tid in pairs(a.titles) do key("IGUI_MQ_Title_" .. tid) end
    end
    for _, m in ipairs(Cat.DEFAULTS.streak.milestones) do if m.title then key("IGUI_MQ_Title_" .. m.title) end end
    key("IGUI_MQ_Title_" .. Cat.DEFAULTS.newbie.title)
    for _, k in ipairs({ "top1", "top3", "top10" }) do key("IGUI_MQ_Title_season_" .. k) end
    for _, list in ipairs({ Cat.daily, Cat.weekly }) do for _, t in ipairs(list) do key("IGUI_MQ_Q_" .. t.tid) end end
    for _, b in ipairs(Cat.boards) do
        key("IGUI_MQ_Board_" .. b.id)
        key("IGUI_MQ_Title_season_first_" .. b.id)
    end
    for _, t in ipairs(Cat.towns) do key("IGUI_MQ_Town_" .. t.id) end
    T.check(#missing == 0, "every catalog key translated (missing: " .. table.concat(missing, ", ") .. ")")

    -- ===================== towns =====================
    T.section("catalog: Towns.at")
    T.check(Q.Towns.at(10800, 9900) == "muldraugh", "muldraugh centre")
    T.check(Q.Towns.at(10540, 9240) == "muldraugh", "rect corner is inclusive")
    T.check(Q.Towns.at(10539, 9240) == nil, "one square outside")
    T.check(Q.Towns.at(13000, 2000) == "louisville", "louisville")
    local cfg = Q.Store.root().config
    cfg.overrides.towns = { custom = { { id = "raven", name = "Raven Creek", rects = { { x1 = 0, y1 = 0, x2 = 9, y2 = 9 } } } },
        disabled = { muldraugh = true } }
    cfg.rev = cfg.rev + 1
    T.check(Q.Towns.at(5, 5) == "raven", "custom town from config")
    T.check(Q.Towns.at(10800, 9900) == nil, "disabled built-in town")
    local names = {}
    for _, t in ipairs(Q.Towns.list()) do names[t.id] = true end
    T.check(names.raven and not names.muldraugh, "Towns.list follows config")
    cfg.overrides.towns = nil
    cfg.rev = cfg.rev + 1
    T.check(Q.Towns.at(10800, 9900) == "muldraugh", "re-enabled after config change")

    -- ===================== trackers =====================
    T.section("catalog: Trackers")
    local Tr = Q.Trackers
    T.check(Tr.installed == true, "installed on OnServerStarted")
    local p = human(T.player({ name = "alice", x = 10800, y = 9900, hours = 30 }))
    local function tot(stat) local a = Q.Store.account("alice", false) return a and a.total[stat] or 0 end
    T.cmd(p, "hello")   -- the poll waits for the hello's import (Trackers.pollPlayer)

    -- crafting: result passed through; counted only when logic:performCurrentRecipe() returned true
    local act = { character = p, craftRecipe = recipe("Soup", "Cooking"), logic = logic(true, "Soup") }
    local soupLogic = act.logic
    local r = ISHandcraftAction.performRecipe(act)
    T.check(r == "craft-result", "wrapped performRecipe returns the original result")
    T.check(tot("craft.count") == 1 and tot("cook.count") == 1, "craft + cook counted")
    T.check(act.logic == soupLogic and soupLogic.data.created == p, "proxy forwarded the follow-up calls, real logic restored")
    ISHandcraftAction.performRecipe({ character = p, craftRecipe = recipe("Nail", "Blacksmithing", true), logic = logic(false, "Nail") })
    T.check(tot("craft.count") == 1 and tot("smith.count") == 0, "failed craft not counted")
    ISHandcraftAction.performRecipe({ character = p, craftRecipe = recipe("Nail", "Blacksmithing", true), logic = logic(true, "Nail") })
    T.check(tot("smith.count") == 1, "smithing counted")
    local animal = { __class = "IsoPlayer", isAnimal = function() return true end }
    ISHandcraftAction.performRecipe({ character = animal, craftRecipe = recipe("X", "Misc"), logic = logic(true, "X") })
    T.check(tot("craft.count") == 2, "non-human character ignored (alice unchanged)")
    local boom = { character = p, craftRecipe = recipe("Boom", "Misc"),
        logic = { performCurrentRecipe = function() error("engine failure") end } }
    local real = boom.logic
    T.check(not pcall(ISHandcraftAction.performRecipe, boom) and boom.logic == real, "an error is re-raised and the real logic restored")

    T.check(ISReadABook.complete({ character = p, forceStopped = true }) == "read-result", "read result passed through")
    T.check(tot("book.read") == 0, "force-stopped read not counted")
    ISReadABook.complete({ character = p })
    T.check(tot("book.read") == 1, "finished book counted")

    ISMoveablesAction.complete({ character = p, mode = "place" })
    ISMoveablesAction.complete({ character = p, mode = "scrap" })
    ISMoveablesAction.complete({ character = p, mode = "pickup" })
    T.check(tot("furniture.placed") == 1 and tot("scrap.count") == 1, "moveables place/scrap")

    -- vanilla shape (ISBuildIsoEntity:new): craftRecipe is the entity's CraftRecipe, or false when it has none
    local function build(ok, cat)
        return setmetatable({ character = p, ok = ok, craftRecipe = cat and { getCategory = function() return cat end } or false },
            { __index = ISBuildIsoEntity })
    end
    T.check(ISBuildIsoEntity.create(build(false)) == nil, "build result passed through")
    T.check(tot("build.count") == 0, "build without consumed materials not counted")
    ISBuildIsoEntity.create(build(true))
    ISBuildIsoEntity.create(build(true, "Carpentry"))
    T.check(tot("build.count") == 2, "successful builds counted")
    -- 42.21 barricades are build entities (category Barricades); ISBarricadeAction is only used by TimedActionsTests
    ISBuildIsoEntity.create(build(true, "Barricades"))
    T.check(tot("barricade.count") == 1 and tot("build.count") == 2, "a barricade build entity counts as a barricade, not a build")

    T.hour = 23
    ISPickupFishAction.complete({ character = p, isFish = true })
    ISPickupFishAction.complete({ character = p, isFish = false })
    T.check(tot("fish.caught") == 1 and tot("fish.night") == 1, "fish (not junk), night fish")
    T.hour = 12

    T.check(ISHutchGrabEgg.animEvent({ character = p }, "update") == "egg-event", "egg animEvent passthrough")
    ISHutchGrabEgg.animEvent({ character = p }, "other")
    ISHutchGrabEgg.update({ character = p, lastTimer = 0 })
    T.check(tot("egg.count") == 3, "eggs: 1 from server animEvent + 2 from SP update")

    local function animalAction(take)
        local a = { milk = 1, wool = 2 }
        a.getData = function() return { getMilkQuantity = function() return a.milk end, getWoolQuantity = function() return a.wool end } end
        return { character = p, animal = a, take = take }
    end
    local idle, milking = animalAction(0), animalAction(0.1)
    ISMilkAnimal.milk(idle)
    ISMilkAnimal.complete(idle)
    ISMilkAnimal.milk(milking)
    ISMilkAnimal.milk(milking)
    ISMilkAnimal.complete(milking)
    T.check(tot("milk.count") == 1, "milking counts once per session, only when milk was taken")
    local fled, shearing = animalAction(0), animalAction(1)
    ISShearAnimal.animEvent(fled, "update")
    ISShearAnimal.complete(fled)
    ISShearAnimal.complete(animalAction(1))                   -- instant: complete before any tick
    ISShearAnimal.animEvent(shearing, "update")
    ISShearAnimal.complete(shearing)
    T.check(tot("shear.count") == 1, "shearing counts only when wool was taken")
    ISCutAnimalOnHook.complete({ character = p, ok = false })
    ISCutAnimalOnHook.complete({ character = p, ok = true })
    T.check(tot("butcher.count") == 1, "the first cut on a butchering hook counts as butchering (refused cut does not)")
    -- recorders run inside guard(): the error is swallowed but printed once per hook
    T.check(Tr.guard("T.hook", error, "boom") == false and Tr.guard("T.hook", error, "boom") == false, "guard swallows errors")
    local n = 0
    for _, line in ipairs(T.prints) do
        if string.find(line, "Trackers: T.hook failed: boom", 1, true) then n = n + 1 end
    end
    T.check(n == 1, "a recorder error is printed once per hook")

    -- kills
    local axe = weapon(WeaponCategory.AXE)
    local z = zombie(p, { getRoom = function() return {} end })
    T.fire("OnWeaponHitXp", p, axe, z, 1, 1)
    T.fire("OnZombieDead", z)
    T.fire("OnZombieDead", z)
    T.check(tot("zombie.kills") == 1, "kill de-duplicated")
    T.check(tot("zombie.kills.melee") == 1 and tot("zombie.kills.axe") == 1, "melee + axe from the last hit")
    T.check(tot("zombie.kills.indoor") == 1 and tot("zombie.kills.night") == 0, "indoor, not night")
    p.hand = weapon(nil, true)
    T.fire("OnZombieDead", zombie(p, nil))
    T.check(tot("zombie.kills.firearm") == 1, "firearm from held weapon")
    p.hand, p.veh = nil, { getDriver = function() return p end, getCurrentSpeedKmHour = function() return 88 end }
    T.fire("OnZombieDead", zombie(p, nil))
    T.check(tot("zombie.kills.vehicle") == 1, "vehicle kill")
    p.veh = nil
    T.fire("OnZombieDead", zombie(p, nil))
    T.check(tot("zombie.kills.unarmed") == 1, "bare-handed kill")
    T.fire("OnZombieDead", zombie(nil, nil))
    T.fire("OnZombieDead", zombie(animal, nil))
    T.check(tot("zombie.kills") == 4, "fire death and animal killer not counted")
    T.check(tot("kills.dayBest") == 4, "best kills in a day")

    -- xp and levels
    T.fire("AddXP", p, Perks.Cooking, 10)
    T.fire("AddXP", p, Perks.Cooking, -5)
    T.check(tot("xp.total") == 10 and tot("xp.Cooking") == 10, "xp total + per perk, negative ignored")
    p.levels.Woodwork, p.levels.Fitness = 3, 5
    T.fire("LevelPerk", p, Perks.Woodwork, 3, true)
    T.check(tot("level.Woodwork") == 3 and tot("skill.total") == 8 and tot("skill.max") == 5, "level-up -> level, total, max")

    -- hunting, deaths
    T.fire("OnCharacterDeath", { __class = "IsoPlayer", isAnimal = function() return true end,
        getAttackedBy = function() return p end })
    T.check(tot("hunt.kills") == 1, "animal killed by a player = hunt")

    -- poll: towns, travel, days, newbie
    T.tick(1)
    T.check(tot("town.visited") == 1 and Q.Store.account("alice", false).towns.muldraugh, "town visited once")
    T.check(tot("life.days") == 1, "life days from hours survived")
    local acc = Q.Store.account("alice", false)
    acc.newbie = acc.newbie or { steps = { false, false, false, false, false } }
    p.y = p.y + 300
    p.hours = 50
    T.advance(60000)
    T.tick(1)
    T.check(math.abs(tot("walk.km") - 0.3) < 1e-9, "walked 0.3 km in a minute")
    T.check(tot("survive.days") == 1, "one more day survived")
    T.check(tot("town.visited") == 1, "same town not counted twice")
    p.x, p.hand = 20000, axe
    T.advance(60000)
    T.tick(1)
    T.check(tot("newbie.leave") == 1, "left the start town with a weapon")
    T.check(math.abs(tot("walk.km") - 0.3) < 1e-9, "teleport-sized jump not counted as walking")
    p.y = p.y + 1000
    T.advance(60000)
    T.tick(1)
    T.check(math.abs(tot("walk.km") - 0.3) < 1e-9, "1 km in a minute on foot (> 0.5 km/min) is a teleport")
    p.y = p.y + 400
    T.advance(30000)
    Tr.nextPoll = 0   -- poll after 30 s instead of the usual minute
    T.tick(1)
    T.check(math.abs(tot("walk.km") - 0.3) < 1e-9, "the walk limit scales with the real interval (0.4 km in 30 s)")
    p.veh = { getDriver = function() return p end, getCurrentSpeedKmHour = function() return -121.7 end }
    p.x = 22000
    T.advance(60000)
    T.tick(1)
    T.check(math.abs(tot("drive.km") - 2) < 1e-9 and tot("speed.max") == 121, "120 km/h drive counted + top speed")
    p.x = 27000
    T.advance(60000)
    T.tick(1)
    T.check(math.abs(tot("drive.km") - 2) < 1e-9, "5 km in a minute in a car (> 4 km/min) is a teleport")
    p.veh = nil

    -- sleep
    p.asleep = true
    T.advance(5000)
    T.tick(1)
    T.advance(5000)
    T.tick(1)
    T.check(tot("sleep.indoor") == 1, "one indoor sleep per sleep")
    p.asleep = false
    T.advance(5000)
    T.tick(1)
    p.asleep, p.outside = true, true
    T.advance(5000)
    T.tick(1)
    T.check(tot("sleep.outdoor") == 1, "outdoor sleep")

    -- pacifist: a fresh life with no kills
    local b = human(T.player({ name = "bob", x = 500, y = 500, hours = 200 }))
    T.cmd(b, "hello")
    T.advance(60000)
    T.tick(1)
    local bacc = Q.Store.account("bob", false)
    T.check(bacc ~= nil and bacc.total["pacifist.days"] == 8, "pacifist days")
    T.check(b ~= nil, "bob online")

    -- mid-install veteran: nothing is polled before the hello, whose import unlocks old progress quietly; the
    -- character's kills count for this life too, so a character that already killed is no pacifist
    local v = human(T.player({ name = "vet", x = 600, y = 600, hours = 2400, kills = 500 }))
    v.levels.Woodwork = 8
    T.advance(60000)
    T.tick(1)
    T.check(Q.Store.account("vet", false) == nil, "no polling before hello")
    T.cmd(v, "hello")
    T.advance(60000)
    T.tick(1)
    local vacc = Q.Store.account("vet", false)
    T.check(vacc.life["zombie.kills"] == 500 and (vacc.total["pacifist.days"] or 0) == 0 and vacc.achv.h_pacifist == nil,
        "a character that already killed is no pacifist")
    T.check(vacc.points.season == 0 and vacc.points.balance == 0 and vacc.achv.skill_woodwork == 4
        and vacc.achv.life_days == 3, "old levels and days unlock quietly: lifetime points only")

    -- safety: no client command can add progress
    local before = tot("zombie.kills")
    T.fire("OnClientCommand", "MinidoracatQuest", "add", p, { stat = "zombie.kills", n = 100 })
    T.check(tot("zombie.kills") == before, "client command cannot add progress")
end
