-- MinidoracatQuest/PageSettings.lua: settings (spec 1.2, 12.2): quest theme preferences (11 themes, pick up to 3,
--   applied with one button; C4: takes effect today if today's quests are not made yet, otherwise next day) and
--   the anonymous-on-leaderboards switch. The Dock / broadcast switches live in the game's MOD options. Last, the
--   folded per-theme quest list: admins always, players while config quests.playerList is on (C.questList).

if isServer() then return end

require "MinidoracatQuest/Client"
require "MinidoracatQuest/Draw"
require "MinidoracatQuest/Window"

local Q = MinidoracatQuest
local C, D, W = Q.Client, Q.Draw, Q.Window
local P = Q.PageSettings or {}
Q.PageSettings = P

local PAD, GAP = D.PAD, D.GAP
P.MAX = 3

function P.themes()
    return (Q.Catalog and Q.Catalog.themes) or (Q.Contract and Q.Contract.THEMES) or {}
end

-- draft list (in click order) or the server's
function P.current(page)
    if page.draft ~= nil then return page.draft end
    local s = C.state
    return s and type(s.prefs) == "table" and s.prefs or {}
end

local function contains(list, id)
    for i, v in ipairs(list) do if v == id then return i end end
    return nil
end

-- toggle a theme in a list capped at P.MAX; returns a new list (harness tests this)
function P.toggle(list, id)
    local out = {}
    for _, v in ipairs(list) do out[#out + 1] = v end
    local i = contains(out, id)
    if i then
        table.remove(out, i)
    elseif #out < P.MAX then
        out[#out + 1] = id
    end
    return out
end

function P.same(a, b)
    if #a ~= #b then return false end
    for _, v in ipairs(a) do if not contains(b, v) then return false end end
    return true
end

function P.onTheme(page, btn)
    page.draft = P.toggle(P.current(page), btn.internal)
    page.msg = nil
    page.dirty = true
end

function P.onApply(page)
    local list = P.current(page)
    page.prefsRid = C.send("prefs", { themes = table.concat(list, ",") }, function(r)
        page.prefsRid = nil
        if r.ok then
            page.draft, page.msg = nil, { getText("IGUI_MQ_UI_PrefsSaved"), D.EXTRA.success }
        else
            page.msg = { D.codeText(r.code), "errorText" }
        end
        page.dirty = true
    end)
    page.dirty = true
end

function P.onAnon(page, checked)
    page.anonRid = C.send("anon", { on = checked == true }, function(r)
        page.anonRid = nil
        if not r.ok then page.msg = { D.codeText(r.code), "errorText" } end
        page.dirty = true
    end)
end

function P.layout(page)
    page.pool:begin()
    local b = D.begin(page.canvas)
    local w = D.contentW(page) - 2 * PAD
    local x, y = PAD, PAD
    local UI, theme = page.UI, page.theme
    local s = C.state
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Settings"))
    if s == nil then
        y = D.waiting(page, b, x, y, w)
        D.finish(page, y)
        return
    end
    local list = P.current(page)
    y = b:header(x, y, x + w, getText("IGUI_MQ_UI_Prefs"),
        { { getText("IGUI_MQ_UI_PrefsCount", tostring(#list), tostring(P.MAX)), "textMuted" } })
    y = b:para(x, y, getText("IGUI_MQ_UI_PrefsRule"), w, "textMuted") + 4
    local btns = {}
    for _, id in ipairs(P.themes()) do
        local btn = page.pool:button("theme:" .. id, UI, theme, D.themeName(id), page, P.onTheme, "chip",
            contains(list, id) ~= nil)
        btn.internal = id
        btn:setEnabled(contains(list, id) ~= nil or #list < P.MAX)
        btns[#btns + 1] = btn
    end
    y = D.placeRow(btns, x, y, x + w) + GAP
    -- at the cap the other chips are disabled: say why under them (focus skips disabled chips, so no tooltip)
    if #list >= P.MAX then y = b:para(x, y - 4, D.codeText("TOO_MANY_PREFS"), w, "textMuted") + 4 end
    local apply = page.pool:button("apply", UI, theme, getText("IGUI_MQ_UI_PrefsApply"), page, P.onApply, "primary")
    local serverPrefs = type(s.prefs) == "table" and s.prefs or {}
    apply:setEnabled(not C.isPending(page.prefsRid) and not P.same(list, serverPrefs))
    apply:setX(x)
    apply:setY(y)
    if page.msg ~= nil then
        b:fitText(x + apply.width + 10, y + math.floor((apply.height - D.fontH()) / 2), page.msg[1],
            w - apply.width - 10, page.msg[2])
    end
    y = y + apply.height + 4
    y = b:para(x, y, getText("IGUI_MQ_UI_PrefsWhen"), w, "textMuted") + GAP
    y = b:header(x, y + 6, x + w, getText("IGUI_MQ_UI_Privacy"))
    local label = getText("IGUI_MQ_UI_Anon")
    local cbw = math.min(w, 48 + D.textW(label))
    local cb = page.pool:get("anon", function()
        return UI.Checkbox.new({ x = 0, y = 0, width = cbw, label = label, checked = s.anon == true, theme = theme,
            target = page, onChange = P.onAnon })
    end)
    cb:setLabel(label)
    cb:setWidth(cbw)
    cb:setChecked(s.anon == true, true)
    cb:setEnabled(not C.isPending(page.anonRid))
    cb:setX(x)
    cb:setY(y)
    y = y + cb.height + 4
    y = b:para(x, y, getText("IGUI_MQ_UI_AnonNote"), w, "textMuted") + GAP
    y = b:para(x, y + 6, getText("IGUI_MQ_UI_ModOptionsNote"), w, "textMuted") + GAP
    y = P.questList(page, b, x, y, w)
    D.finish(page, y)
end

function P.onQuestList(page)
    page.listOpen = not page.listOpen
    page.dirty = true
end

local function range(lo, hi)
    if lo == hi then return D.num(lo) end
    return getText("IGUI_MQ_UI_Range", D.num(lo), D.num(hi))
end

-- last section: the quests each theme can give (C.questList: admins always, players while quests.playerList is
-- on); folded until opened. Returns the y below
function P.questList(page, b, x, y, w)
    local list = C.questList()
    if list == nil then return y end
    y = y + 6
    local title = getText("IGUI_MQ_UI_QuestList")
    local tw = b:text(x, y, title, "text", UIFont.Medium)
    local btn = page.pool:button("questList", page.UI, page.theme,
        getText(page.listOpen and "IGUI_MQ_UI_ListHide" or "IGUI_MQ_UI_ListShow"), page, P.onQuestList, "chip",
        page.listOpen == true)
    local th = D.fontH(UIFont.Medium)
    local bx, by = x + tw + 10, y + math.floor((th - btn.height) / 2)
    if bx + btn.width > x + w then bx, by = x, y + th + 4 end
    btn:setX(bx)
    btn:setY(by)
    y = math.max(y + th, by + btn.height) + GAP
    local q = C.defs().cfg.quests
    if not (type(q) == "table" and q.playerList == true) then
        y = b:para(x, y, getText("IGUI_MQ_UI_QuestListAdminOnly"), w, "textMuted") + 4
    end
    if not page.listOpen or #list == 0 then return y + GAP end
    -- one list box (design r11 B), one entry per theme
    local ind = 12
    local L = b:list(x, y, w)
    x, w = x + 8, w - 16
    for i, e in ipairs(list) do
        if i > 1 then b:listSep(L, y) end
        y = y + 4
        local name = D.themeName(e.theme)
        local counts = getText("IGUI_MQ_UI_QuestListCount", tostring(#e.daily), tostring(#e.weekly))
        local nw = D.textW(name)
        if nw + GAP + D.textW(counts) <= w then
            b:text(x, y, name, "text")
            b:text(x + nw + GAP, y, counts, "textMuted")
            y = y + D.fontH() + 2
        else
            y = b:para(x, y, name, w, "text")
            y = b:para(x, y, counts, w, "textMuted")
        end
        for _, kind in ipairs({ "daily", "weekly" }) do
            if #e[kind] > 0 then
                y = b:para(x + ind, y, getText(kind == "daily" and "IGUI_MQ_UI_Daily" or "IGUI_MQ_UI_Weekly"), w - ind,
                    "textMuted")
                for _, t in ipairs(e[kind]) do
                    y = b:para(x + 2 * ind, y, getText(t.rare and "IGUI_MQ_UI_QuestListRare" or "IGUI_MQ_UI_QuestListRow",
                        D.questText(t.tid, range(t.lo, t.hi)), D.num(t.pts)), w - 2 * ind, "text")
                end
            end
        end
        y = y + 2
    end
    return b:listEnd(L, y) + GAP
end

P.spec = {
    id = "settings", label = "IGUI_MQ_UI_NavSettings", icon = "settings", group = "tail", order = 90,
    build = function(page) D.scrollPage(page) end,
    layout = function(page) MinidoracatQuest.PageSettings.layout(page) end,
    onHide = function(page) page.draft, page.msg = nil, nil end,
}
W.register(P.spec)
