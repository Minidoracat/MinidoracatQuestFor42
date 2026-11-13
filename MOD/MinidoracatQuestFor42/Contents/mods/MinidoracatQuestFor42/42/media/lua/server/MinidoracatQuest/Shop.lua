-- MinidoracatQuest/Shop.lua: point sinks bought outright (plan points-sinks 2026-11-12): a streak shield and the point
-- titles. Paid swaps live in Quests.swap, sponsored hordes in Hordes.pledge. Every price, limit and switch comes from
-- Config shop.* on the server; pay is the price the player saw, a different one is PRICE_CHANGED.

if isClient() then return end

require "MinidoracatQuest/Contract"
require "MinidoracatQuest/Store"
require "MinidoracatQuest/Clock"
require "MinidoracatQuest/Config"
require "MinidoracatQuest/Points"
require "MinidoracatQuest/Server"
require "MinidoracatQuest/Quests"

local MQ = MinidoracatQuest
local Sh = MQ.Shop or {}
MQ.Shop = Sh
local CODE = MQ.Contract.CODE

Sh.TITLES = { spend_1 = true, spend_2 = true, spend_3 = true, spend_4 = true }   -- the fixed list (Config shop.titles.list)
Sh.SHIELD_HOLD = 1                                                               -- shield days held at most

-- true | false, code
function Sh.buyShield(acc, user, pay, now)
    local cfg = MQ.Config.get().shop.shield
    if not cfg.enabled then return false, CODE.SHOP_OFF end
    MQ.Quests.ensure(acc, user, now)   -- settle the day change first: a shield bought now must not cover days missed before
    local s = MQ.Quests.streakOf(acc)
    if (s.shield or 0) >= Sh.SHIELD_HOLD then return false, CODE.SHIELD_HELD end
    local week = MQ.Clock.weekKey(now)
    local n = s.shieldWeek == week and (s.shieldN or 0) or 0
    if n >= cfg.perWeek then return false, CODE.SHIELD_WEEK end
    if pay ~= cfg.pts then return false, CODE.PRICE_CHANGED end
    if not MQ.Points.pay(acc, user, cfg.pts, "shield", nil) then return false, CODE.NOT_ENOUGH_POINTS end
    s.shield, s.shieldWeek, s.shieldN = (s.shield or 0) + 1, week, n + 1
    return true
end

-- the price of a title id on sale now, or nil: a fixed one, or this season's patron title when season > 0
function Sh.titlePrice(id)
    local t = MQ.Config.get().shop.titles
    if Sh.TITLES[id] then return t.list[id] end
    if t.season > 0 and id == "s" .. MQ.Store.root().season.no .. "_patron" then return t.season end
    return nil
end

-- true | false, code. The title is not worn automatically.
function Sh.buyTitle(acc, user, id, pay)
    if not MQ.Config.get().shop.titles.enabled then return false, CODE.SHOP_OFF end
    local price = Sh.titlePrice(id)
    if price == nil then return false, CODE.NOT_FOUND end
    if acc.titles and acc.titles[id] then return false, CODE.TITLE_OWNED end
    if pay ~= price then return false, CODE.PRICE_CHANGED end
    if not MQ.Points.pay(acc, user, price, "title", id) then return false, CODE.NOT_ENOUGH_POINTS end
    MQ.Store.grantTitle(acc, id, "shop:" .. id)
    return true
end

MQ.Server.define("buyShield", { kind = "mutation", spend = true, fields = { pay = "int" },
    run = function(ctx) return Sh.buyShield(MQ.Store.account(ctx.user, true), ctx.user, ctx.args.pay, ctx.now) end })

MQ.Server.define("buyTitle", { kind = "mutation", spend = true, fields = { id = "str", pay = "int" },
    run = function(ctx) return Sh.buyTitle(MQ.Store.account(ctx.user, true), ctx.user, ctx.args.id, ctx.args.pay) end })

return Sh
