-- MinidoracatQuest/Trackers.lua: game events, finished timed actions and a per-minute poll -> Stats
-- (docs/ARCHITECTURE.md section 5.9). Runs on the dedicated server and in single player.
-- Hooks are installed once, after every mod's top-level code (OnServerStarted / SP OnGameStart), so our
-- wrappers are outermost. Wrappers run the vanilla method first, pass its result through unchanged and
-- record inside guard() (pcall; the first error of each hook is printed once). Timed-action character comes
-- from the client's action args (pitfalls.md:182-195); Stats.add still requires a verified principal for that player.

if isClient() then return end

require "MinidoracatQuest/Catalog"
require "MinidoracatQuest/Stats"
require "MinidoracatQuest/Identity"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Towns"

local Q = MinidoracatQuest
local first = Q.Trackers == nil
local T = Q.Trackers or {}
Q.Trackers = T
local Cat = Q.Catalog

T.POLL_MS = 60000
T.SLEEP_MS = 5000
T.PER_TICK = 8
T.WALK_KM_MIN = 0.5   -- km per minute (~30 km/h); faster on foot is a teleport (PZ sprinting is far slower)
T.DRIVE_KM_MIN = 4    -- km per minute (240 km/h); faster in a car is a teleport
T.STALE_MS = 90000    -- older position samples are dropped (relog, server pause)

T.seen = T.seen or {}             -- zombie -> true, cleared every minute
T.hitBy = T.hitBy or {}           -- zombie -> owner of the last weapon hit
T.hitWith = T.hitWith or {}       -- zombie -> that weapon (false = none)
T.px, T.py, T.pt = T.px or {}, T.py or {}, T.pt or {}
T.days = T.days or {}             -- user -> floor(hours survived / 24) at the last poll
T.start, T.left = T.start or {}, T.left or {}   -- newbie: start town this session, step reported
T.asleep = T.asleep or {}
T.dayKey, T.dayKills = T.dayKey or {}, T.dayKills or {}
T.missing = T.missing or {}       -- hook names that did not exist (logged once)
T.failed = T.failed or {}         -- hook name -> true once its recorder errored (logged once)
T.queue, T.cursor = T.queue, T.cursor or 1
T.nextPoll, T.nextSleep = T.nextPoll or 0, T.nextSleep or 0

local function add(who, stat, n) Q.Stats.add(who, stat, n or 1) end

-- pcall that prints the first error of each hook: a recorder that cannot read the engine (unexposed class,
-- renamed field) must show up in the server log once instead of silently counting nothing.
local function guard(name, f, ...)
    local ok, v = pcall(f, ...)
    if not ok and not T.failed[name] then
        T.failed[name] = true
        print("[MinidoracatQuestFor42] Trackers: " .. name .. " failed: " .. tostring(v))
    end
    return ok, v
end
T.guard = guard

local function isHuman(c)
    return c ~= nil and instanceof(c, "IsoPlayer") and not c:isAnimal()
end
T.isHuman = isHuman

-- perk id -> stat ids; perk objects built at install (Perks exists by then)
local xpStat, levelStat = {}, {}
for _, id in ipairs(Cat.perks) do
    xpStat[id] = "xp." .. id
    levelStat[id] = "level." .. id
end
local perkObjs, perkLevelStat = {}, {}
local weaponCats = {}   -- { { WeaponCategory, stat } }

local function isNight()
    local h = getGameTime():getHour()
    return h >= 21 or h < 6
end

------------------------------------------------------------------------------------------------------------------
-- Kills

function T.onWeaponHit(owner, weapon, hitObject)
    if hitObject ~= nil and instanceof(hitObject, "IsoZombie") and isHuman(owner) then
        T.hitBy[hitObject] = owner
        T.hitWith[hitObject] = weapon or false
    end
end

local function weaponKill(killer, w)
    if w and instanceof(w, "HandWeapon") and w:isRanged() then
        add(killer, "zombie.kills.firearm")
        return
    end
    add(killer, "zombie.kills.melee")
    local script = w and instanceof(w, "HandWeapon") and w:getScriptItem() or nil
    if script == nil or script:containsWeaponCategory(WeaponCategory.UNARMED) then
        add(killer, "zombie.kills.unarmed")
        return
    end
    for _, wc in ipairs(weaponCats) do
        if script:containsWeaponCategory(wc[1]) then add(killer, wc[2]) end
    end
end

function T.onZombieDead(z)
    if z == nil or T.seen[z] then return end   -- the burning path can fire twice
    T.seen[z] = true
    local killer = z:getAttackedBy()            -- nil for fire deaths
    if not isHuman(killer) then return end
    add(killer, "zombie.kills")
    local w = nil
    if T.hitBy[z] == killer then w = T.hitWith[z] or nil end
    if w == nil and killer:getVehicle() ~= nil then
        add(killer, "zombie.kills.vehicle")
    else
        weaponKill(killer, w or killer:getPrimaryHandItem())
    end
    if isNight() then add(killer, "zombie.kills.night") end
    local sq = z:getCurrentSquare()
    if sq ~= nil and sq:getRoom() ~= nil then add(killer, "zombie.kills.indoor") end
    if RainManager.isRaining() then add(killer, "zombie.kills.rain") end
    -- best kills in one game day (memory only; a restart starts the day over)
    local name = killer:getUsername()
    local day = math.floor(getGameTime():getWorldAgeHours() / 24)
    if T.dayKey[name] ~= day then T.dayKey[name], T.dayKills[name] = day, 0 end
    T.dayKills[name] = T.dayKills[name] + 1
    Q.Stats.max(killer, "kills.dayBest", T.dayKills[name])
end

function T.onCharacterDeath(c)
    if c == nil or not instanceof(c, "IsoPlayer") then return end
    if c:isAnimal() then
        local k = c:getAttackedBy()
        if isHuman(k) then add(k, "hunt.kills") end
        return
    end
    add(c, "deaths")
    -- life scope itself is cleared by Stats.onCharacterDeath
end

------------------------------------------------------------------------------------------------------------------
-- XP and levels

function T.skillTotals(p, who)
    local sum, best = 0, 0
    for i, perk in ipairs(perkObjs) do
        local l = p:getPerkLevel(perk)
        if l > 0 then
            sum = sum + l
            if l > best then best = l end
            Q.Stats.max(who, perkLevelStat[i], l)
        end
    end
    if sum > 0 then Q.Stats.max(who, "skill.total", sum) end
    if best > 0 then Q.Stats.max(who, "skill.max", best) end
end

function T.onAddXP(owner, perk, amount)
    if type(amount) ~= "number" or amount <= 0 or not isHuman(owner) then return end
    add(owner, "xp.total", amount)
    local s = perk ~= nil and xpStat[perk:getId()]
    if s then add(owner, s, amount) end
end

function T.onLevelPerk(owner, perk, level, increased)
    if not increased or not isHuman(owner) or perk == nil then return end
    local s = levelStat[perk:getId()]
    if s == nil then return end
    Q.Stats.max(owner, s, level)
    T.skillTotals(owner, owner)
end

------------------------------------------------------------------------------------------------------------------
-- Timed actions

-- Replaces cls[method]; before(self) runs first (its value is passed on), after(self, result, pre) records.
function T.wrap(name, cls, method, after, before)
    local orig = cls and cls[method]
    if type(orig) ~= "function" then
        T.missing[#T.missing + 1] = name .. "." .. method
        return false
    end
    cls[method] = function(self, ...)
        local pre
        if before ~= nil then
            local ok, v = guard(name .. "." .. method, before, self)
            if ok then pre = v end
        end
        local result = orig(self, ...)
        if isHuman(self.character) then guard(name .. "." .. method, after, self, result, pre) end
        return result
    end
    return true
end

local function counter(stat)
    return function(self, result)
        if result ~= false then add(self.character, stat) end
    end
end

local function doIt(stat)
    return function(self, result)
        if result ~= false and self.doIt then add(self.character, stat) end
    end
end

-- Success = the boolean vanilla performRecipe itself tests, self.logic:performCurrentRecipe()
-- (ISHandcraftAction.lua:221-223). The craft history cannot tell: getCraftHistoryFor returns a
-- PlayerCraftHistory.CraftHistoryEntry, which LuaManager never exposes (only PlayerCraftHistory, :1832),
-- so getCraftCount() errors in Lua (E2E quest-mp 2026-10-23: no craft was ever counted).
-- For the duration of the call self.logic is a proxy that forwards every method and records that result.
local function afterCraft(self)
    local who, r = self.character, self.craftRecipe
    add(who, "craft.count")
    if r:getCategory() == "Cooking" then add(who, "cook.count") end
    if r:isSmithing() then add(who, "smith.count") end
    if r:involvesSkill(Perks.FlintKnapping) then add(who, "knap.count") end
    if r:involvesSkill(Perks.Carving) then add(who, "carve.count") end
end

local function wrapCraft()
    local cls = ISHandcraftAction
    local orig = cls and cls.performRecipe
    if type(orig) ~= "function" then
        T.missing[#T.missing + 1] = "ISHandcraftAction.performRecipe"
        return
    end
    cls.performRecipe = function(self, ...)
        local real = self.logic
        if real == nil or not isHuman(self.character) then return orig(self, ...) end
        local done = false
        self.logic = setmetatable({ performCurrentRecipe = function()
            done = real:performCurrentRecipe() == true
            return done
        end }, { __index = function(_, k) return function(_, ...) return real[k](real, ...) end end })
        local ok, result = pcall(orig, self, ...)
        self.logic = real
        if not ok then error(result) end
        if done then guard("ISHandcraftAction.performRecipe", afterCraft, self) end
        return result
    end
end

local function plantAt(self)
    local p = self.plant
    return SFarmingSystem.instance:getLuaObjectAt(p.x, p.y, p.z)
end

-- Milking / shearing: complete() returns true even when nothing was taken (milk(): stressed animal or full bucket
-- force-completes first, ISMilkAnimal.lua:57-75; E2E quest-t2-1023c: shear counted while the ewe kept her 2 wool).
-- The per-tick method that takes milk / wool marks the action; the end of the session counts once if marked.
local function sessionEnd(self, stat)
    if self.mqTook and not self.mqCounted then
        self.mqCounted = true
        add(self.character, stat)
    end
end
-- stat: the session can end inside this tick (single player forceStop, see below); count after the tick has taken
local function marksTaken(amount, stat)
    return function(self, _, before)
        if before ~= nil and amount(self) < before then self.mqTook = true end
        if stat ~= nil and self.mqStopped then sessionEnd(self, stat) end
    end, amount
end
local function sessionTaken(stat)
    return function(self, result)
        if result ~= false then sessionEnd(self, stat) end
    end
end
local function stopped(self) self.mqStopped = true end
local function milkQty(self) return self.animal:getData():getMilkQuantity() end
local function woolQty(self) return self.animal:getData():getWoolQuantity() end

function T.installActions()
    local W = T.wrap
    -- crafting: performRecipe is the single place the recipe runs (SP perform / MP server complete)
    wrapCraft()
    -- building: create() returns nil for success and failure; updateModData runs only after materials were consumed.
    -- 42.21 barricading is a build entity too (scripts/generated/entities/barricades, CraftRecipe category Barricades,
    -- built from the build menu through ISBuildIsoEntity); ISBarricadeAction is only queued by client/Tests/TimedActionsTests.lua.
    if W("ISBuildIsoEntity", ISBuildIsoEntity, "create", function(self)
            if not self.mqBuilt then return end
            local r = self.craftRecipe
            add(self.character, r and r:getCategory() == "Barricades" and "barricade.count" or "build.count")
        end, function(self) self.mqBuilt = false end) then
        local orig = ISBuildIsoEntity.updateModData
        ISBuildIsoEntity.updateModData = function(self, ...)
            local r = orig(self, ...)
            if self.mqBuilt == false then self.mqBuilt = true end
            return r
        end
    end
    W("ISAddItemInRecipe", ISAddItemInRecipe, "complete", counter("cook.count"))
    W("ISRepairClothing", ISRepairClothing, "complete", counter("sew.count"))
    W("ISHarvestPlantAction", ISHarvestPlantAction, "complete", function(self, _, had)
        if had then add(self.character, "farm.harvest") end
    end, function(self) return plantAt(self) ~= nil end)
    W("ISSeedActionNew", ISSeedActionNew, "complete", function(self, _, plowed)
        if plowed then add(self.character, "plant.count") end
    end, function(self) local p = plantAt(self) return p ~= nil and p.state == "plow" end)
    W("ISPickupFishAction", ISPickupFishAction, "complete", function(self, result)
        if result == false or not self.isFish then return end
        add(self.character, "fish.caught")
        if isNight() then add(self.character, "fish.night") end
    end)
    W("ISCheckTrapAction", ISCheckTrapAction, "complete", function(self, _, caught)
        if caught then add(self.character, "trap.caught") end
    end, function(self)
        local t = STrapSystem.instance:getLuaObjectAt(self.trap.x, self.trap.y, self.trap.z)
        return t ~= nil and t.animal ~= nil and t.animal.type ~= nil
    end)
    W("ISForageAction", ISForageAction, "complete", function(self, result)
        if result == true then add(self.character, "forage.count") end
    end)
    W("ISButcherAnimal", ISButcherAnimal, "complete", counter("butcher.count"))         -- carcass on the ground
    W("ISCutAnimalOnHook", ISCutAnimalOnHook, "complete", counter("butcher.count"))     -- first cut on a butchering hook
    -- one per milking / shearing session that took something: milk() runs per tick in SP update and MP server
    -- animEvent (ISMilkAnimal.lua:131,203); shearAnimal runs in SP update / MP server animEvent (ISShearAnimal.lua:54,121).
    -- The MP server ends a session with forceComplete -> complete(). Single player ends it with the Lua forceStop inside
    -- the tick instead: the animal dry, the bucket full or the animal stressed (ISMilkAnimal.lua:60-113; getDuration -1,
    -- so SP milking never reaches complete()), stress or no wool left (ISShearAnimal.lua:24-28,49-57: stress() can stop
    -- the first tick before that same tick shears). forceStop only marks; the tick's wrapper counts once it has seen
    -- what was taken. A player's cancel stops the action in Java (StopAllActionQueue -> stop(), IsoGameCharacter.java:5432-5446;
    -- a hit reaction's BaseAction.forceStop -> stop(), :9020-9033), never through the Lua forceStop
    W("ISMilkAnimal", ISMilkAnimal, "milk", marksTaken(milkQty, "milk.count"))
    W("ISMilkAnimal", ISMilkAnimal, "complete", sessionTaken("milk.count"))
    W("ISMilkAnimal", ISMilkAnimal, "forceStop", stopped)
    W("ISShearAnimal", ISShearAnimal, "update", marksTaken(woolQty, "shear.count"))
    W("ISShearAnimal", ISShearAnimal, "animEvent", marksTaken(woolQty))
    W("ISShearAnimal", ISShearAnimal, "complete", sessionTaken("shear.count"))
    W("ISShearAnimal", ISShearAnimal, "forceStop", stopped)
    -- eggs: one per egg; MP server takes them in animEvent("update") (ISHutchGrabEgg.lua:52-61), SP in update()
    local eggEvent = ISHutchGrabEgg and ISHutchGrabEgg.animEvent
    if type(eggEvent) == "function" then
        ISHutchGrabEgg.animEvent = function(self, event, parameter)
            local result = eggEvent(self, event, parameter)
            if isServer() and event == "update" and isHuman(self.character) then guard("ISHutchGrabEgg.animEvent", add, self.character, "egg.count") end
            return result
        end
    else
        T.missing[#T.missing + 1] = "ISHutchGrabEgg.animEvent"
    end
    W("ISHutchGrabEgg", ISHutchGrabEgg, "update", function(self, _, before)
        local n = (self.lastTimer or 0) - (before or 0)
        if n > 0 then add(self.character, "egg.count", n) end
    end, function(self) return self.lastTimer or 0 end)
    W("ISRepairEngine", ISRepairEngine, "complete", function(self, _, cond)
        if cond ~= nil and self.part:getCondition() > cond then add(self.character, "mech.repair") end
    end, function(self) return self.part:getCondition() end)
    W("ISFixVehiclePartAction", ISFixVehiclePartAction, "complete", function(self, _, cond)
        if cond ~= nil and self.item:getCondition() > cond then add(self.character, "mech.repair") end
    end, function(self) return self.item:getCondition() end)
    W("ISInstallVehiclePart", ISInstallVehiclePart, "complete", function(self)
        if self.item ~= nil and self.part:getInventoryItem() == self.item then add(self.character, "mech.install") end
    end)
    W("ISPlugGenerator", ISPlugGenerator, "complete", function(self, result)
        if result ~= false and self.plug then add(self.character, "power.count") end
    end)
    W("ISActivateGenerator", ISActivateGenerator, "complete", function(self, result)
        if result ~= false and self.activate and self.generator:isActivated() then add(self.character, "power.count") end
    end)
    W("ISReadABook", ISReadABook, "complete", function(self, result, stopped)
        if result ~= false and not stopped then add(self.character, "book.read") end
    end, function(self) return self.forceStopped == true end)
    W("ISApplyBandage", ISApplyBandage, "complete", doIt("bandage.count"))
    W("ISStitch", ISStitch, "complete", doIt("medic.count"))
    W("ISSplint", ISSplint, "complete", doIt("medic.count"))
    W("ISDisinfect", ISDisinfect, "complete", counter("medic.count"))
    W("ISRemoveBullet", ISRemoveBullet, "complete", counter("medic.count"))
    W("ISRemoveGlass", ISRemoveGlass, "complete", counter("medic.count"))
    W("ISMoveablesAction", ISMoveablesAction, "complete", function(self, result)
        if result == false then return end
        if self.mode == "place" then add(self.character, "furniture.placed")
        elseif self.mode == "scrap" then add(self.character, "scrap.count") end
    end)
    W("ISBarricadeAction", ISBarricadeAction, "complete", counter("barricade.count"))   -- vanilla UI no longer queues it; mods may
    W("ISBuryCorpse", ISBuryCorpse, "complete", counter("corpse.count"))
    -- a burn counts only when it set the corpse on fire (owner 2026-10-29): complete() returns true and uses the petrol
    -- and the lighter either way (ISBurnCorpseAction.lua:61-68), while IsoFire.CanAddFire starts nothing under MP
    -- NoFire, in a safehouse without fire, on water or on a square already burning (IsoFire.java:265-283).
    -- StartFire adds the fire to the square at once (IsoFireManager.java:196-217), so complete() can look
    W("ISBurnCorpseAction", ISBurnCorpseAction, "complete", function(self, result, sq)
        if result ~= false and sq ~= nil and sq:getFire() ~= nil then add(self.character, "corpse.count") end
    end, function(self)
        local sq = self.corpse:getSquare()
        if sq ~= nil and sq:getFire() == nil then return sq end
    end)
    W("ISWashYourself", ISWashYourself, "complete", counter("wash.count"))
    W("ISWashClothing", ISWashClothing, "complete", counter("wash.count"))
    -- the action force-completes when the tree falls (ISChopTreeAction.lua:82-86)
    W("ISChopTreeAction", ISChopTreeAction, "complete", function(self, result)
        if result ~= false and self.tree ~= nil and self.tree:getObjectIndex() == -1 then
            add(self.character, "tree.chop")
        end
    end)
end

------------------------------------------------------------------------------------------------------------------
-- Poll

function T.online()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers()
        if list ~= nil then
            for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p ~= nil then out[#out + 1] = p end
        end
    end
    return out
end

local function holdsWeapon(p)
    local item = p:getPrimaryHandItem()
    return item ~= nil and instanceof(item, "HandWeapon")
end

-- A segment faster than the walk/drive limit is a teleport (admin, safehouse, other mods) and is dropped whole;
-- a ride that ends on foot inside one poll is checked against the walk limit, so a fast one is not credited as walking.
local function travel(p, user, now, x, y, veh, driver)
    local ox, oy, ot = T.px[user], T.py[user], T.pt[user]
    T.px[user], T.py[user], T.pt[user] = x, y, now
    if ox == nil or now <= ot or now - ot > T.STALE_MS then return end
    local dx, dy = x - ox, y - oy
    local km = math.sqrt(dx * dx + dy * dy) / 1000
    local limit = (veh == nil and T.WALK_KM_MIN or T.DRIVE_KM_MIN) * (now - ot) / 60000
    if km < 0.01 or km > limit then return end
    if veh == nil then add(user, "walk.km", km)
    elseif driver then add(user, "drive.km", km) end
end

function T.pollPlayer(p, now)
    if not isHuman(p) or p:isDead() then return end
    local user = Q.Identity.principal(p)
    if user == nil then return end
    local St = Q.Store
    local acc = St.ready() and not St.readOnly and St.account(user, false) or nil
    -- not before hello: its import seeds old levels and days quietly; polled first, they would unlock out loud
    if acc == nil or not acc.imported then return end

    local x, y = p:getX(), p:getY()
    local veh = p:getVehicle()
    local driver = veh ~= nil and veh:getDriver() == p
    travel(p, user, now, x, y, veh, driver)
    if driver then
        local kmh = math.floor(math.abs(veh:getCurrentSpeedKmHour()))
        if kmh > 0 then Q.Stats.max(user, "speed.max", kmh) end
    end

    local days = math.floor(p:getHoursSurvived() / 24)
    local last = T.days[user]
    if last ~= nil and days > last then add(user, "survive.days", days - last) end
    T.days[user] = days
    if days > 0 then
        Q.Stats.max(user, "life.days", days)
        if (acc.life["zombie.kills"] or 0) == 0 then Q.Stats.max(user, "pacifist.days", days) end
    end

    local town = Q.Towns.at(x, y)
    if town ~= nil and acc.towns ~= nil and not acc.towns[town] then
        acc.towns[town] = true
        add(user, "town.visited")
    end
    if not T.start[user] then T.start[user] = town end
    if acc.newbie ~= nil and not T.left[user] and T.start[user] ~= nil
        and town ~= T.start[user] and holdsWeapon(p) then
        T.left[user] = true
        add(user, "newbie.leave")
    end

    T.skillTotals(p, user)
end

function T.sleepCheck(p)
    if not isHuman(p) or p:isDead() then return end
    local user = Q.Identity.principal(p)
    if user == nil then return end
    local asleep = p:isAsleep() == true
    if asleep and not T.asleep[user] then
        add(user, p:isOutside() and "sleep.outdoor" or "sleep.indoor")
    end
    T.asleep[user] = asleep
end

function T.tick()
    local now = getTimestampMs()
    if now >= T.nextPoll then
        T.nextPoll = now + T.POLL_MS
        T.seen, T.hitBy, T.hitWith = {}, {}, {}
        T.queue, T.cursor = T.online(), 1
    end
    local q = T.queue
    if q ~= nil then
        local stop = math.min(#q, T.cursor + T.PER_TICK - 1)
        for i = T.cursor, stop do guard("poll", T.pollPlayer, q[i], now) end
        T.cursor = stop + 1
        if T.cursor > #q then T.queue = nil end
    end
    if now >= T.nextSleep then
        T.nextSleep = now + T.SLEEP_MS
        for _, p in ipairs(T.online()) do guard("sleep", T.sleepCheck, p) end
    end
end

------------------------------------------------------------------------------------------------------------------

function T.install()
    if T.installed then return end
    T.installed = true
    for _, id in ipairs(Cat.perks) do
        local perk = Perks.FromString(id)
        if perk ~= nil and perk ~= Perks.None and perk ~= Perks.MAX then
            perkObjs[#perkObjs + 1] = perk
            perkLevelStat[#perkObjs] = levelStat[id]
        end
    end
    weaponCats = {
        { WeaponCategory.AXE, "zombie.kills.axe" }, { WeaponCategory.BLUNT, "zombie.kills.blunt" },
        { WeaponCategory.SMALL_BLUNT, "zombie.kills.smallblunt" }, { WeaponCategory.LONG_BLADE, "zombie.kills.longblade" },
        { WeaponCategory.SMALL_BLADE, "zombie.kills.smallblade" }, { WeaponCategory.SPEAR, "zombie.kills.spear" },
        { WeaponCategory.IMPROVISED, "zombie.kills.improvised" },
    }
    Events.OnZombieDead.Add(function(z) Q.Trackers.onZombieDead(z) end)
    Events.OnWeaponHitXp.Add(function(o, w, h) Q.Trackers.onWeaponHit(o, w, h) end)
    Events.AddXP.Add(function(o, perk, n) Q.Trackers.onAddXP(o, perk, n) end)
    Events.LevelPerk.Add(function(o, perk, l, up) Q.Trackers.onLevelPerk(o, perk, l, up) end)
    Events.OnCharacterDeath.Add(function(c) Q.Trackers.onCharacterDeath(c) end)
    Events.OnTickEvenPaused.Add(function() Q.Trackers.tick() end)
    T.installActions()
    if #T.missing > 0 then
        print("[MinidoracatQuestFor42] Trackers: missing hooks " .. table.concat(T.missing, ", "))
    end
end

if first then
    Events.OnServerStarted.Add(function() MinidoracatQuest.Trackers.install() end)
    if not isServer() then Events.OnGameStart.Add(function() MinidoracatQuest.Trackers.install() end) end
end
