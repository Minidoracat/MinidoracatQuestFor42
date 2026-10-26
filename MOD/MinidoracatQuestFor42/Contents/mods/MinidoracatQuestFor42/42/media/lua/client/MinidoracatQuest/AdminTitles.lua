-- MinidoracatQuest/AdminTitles.lua: admin "Titles" tab (plan r13, the owner's pick 2026-10-27): every title and what
-- earns it, read-only. Rows come from D.titleSources over the admin's draft view (AM.achievements: switched-off,
-- custom and unapplied edits included) plus the pack achievements; titles are edited on the Achievements tab.

require "MinidoracatQuest/AdminPanel"
require "MinidoracatQuest/Draw"

local MQ = MinidoracatQuest
local A, AM, D = MQ.Admin, MQ.AdminModel, MQ.Draw

-- the config parts D.titleSources reads, through the draft
local function cfgView(S)
    return {
        streak = { need = AM.get(S, "streak.need"), milestones = AM.get(S, "streak.milestones") },
        newbie = { enabled = AM.get(S, "newbie.enabled"), title = AM.get(S, "newbie.title"), days = AM.get(S, "newbie.days") },
        rewards = { firstTitles = AM.get(S, "rewards.firstTitles") },
    }
end

-- thresholds as players meet them: the draft's difficulty multiplier on top (the Achievements tab shows the base);
-- pack entries come from Client.defs, already scaled by the applied multiplier
local function achievements(S)
    local mult = tonumber(AM.get(S, "difficulty.mult")) or 1
    if mult <= 0 then mult = 1 end
    local out = AM.achievements(S, MQ.Catalog)
    for _, a in ipairs(out) do
        a.kind, a.off = a.custom and "custom" or "builtin", not a.enabled
        a.tiers = MQ.Client.scale(a.tiers, mult, a.stat)
    end
    for _, a in ipairs(MQ.Client.defs().allAch) do
        if a.kind == "pack" then out[#out + 1] = a end
    end
    return out
end

local function groupLabel(g, no)
    if g == "custom" then return getText("IGUI_MQ_Admin_CatCustom") end
    if g == "other" then return getText("IGUI_MQ_Admin_TitleGroupOther") end
    if g == "season" then return getText("IGUI_MQ_Admin_TitleGroupSeason", tostring(no)) end
    return D.textOrNull("IGUI_MQ_AchCat_" .. tostring(g)) or tostring(g)
end

local function layout(P, pg, F)
    local season = MQ.Client.state ~= nil and type(MQ.Client.state.season) == "table" and MQ.Client.state.season or {}
    local no = tonumber(season.no) or 1
    -- during the review the season before (reviewNo) is not paid yet (Seasons.lua Se.current)
    local paid = (tonumber(season.reviewNo) or no) - 1
    local rows = D.titleSources(achievements(P.S), cfgView(P.S), no)
    F:head("head", getText("IGUI_MQ_Admin_TitleListHead"))
    F:text("note", getText("IGUI_MQ_Admin_TitlesNote"), "textMuted")
    -- grouped by first appearance: achievement categories in catalog order, then streak and newbie, then seasons
    local groups, seen = {}, {}
    for _, r in ipairs(rows) do
        if not seen[r.group] then
            seen[r.group] = true
            groups[#groups + 1] = r.group
        end
    end
    local L = F:list("t")
    local nameW = math.floor((F.width - 2 * A.PAD) * 0.3)
    local condX = A.PAD + nameW + A.GAP
    local condW = F.width - A.PAD - condX
    F:listHead({ { text = getText("IGUI_MQ_UI_TitleLabel"), x = A.PAD }, { text = getText("IGUI_MQ_UI_ColCond"), x = condX } }, "hd")
    local i = 0
    local function groupRow(text)
        i = i + 1
        F:item()
        F:cells("g" .. i, { { text = text, x = A.PAD, token = "info" } })
    end
    for _, g in ipairs(groups) do
        groupRow(groupLabel(g, no))
        for _, r in ipairs(rows) do
            if r.group == g then
                i = i + 1
                local name = r.custom and getText("IGUI_MQ_Admin_TitleCustom", r.name) or r.name
                if r.off then name = getText("IGUI_MQ_Admin_Disabled", name) end
                local tok = r.off and "textMuted" or "text"
                F:item()
                F:cells("r" .. i, { { text = name, x = A.PAD, w = nameW, wrap = true, token = tok },
                    { text = r.cond, x = condX, w = condW, wrap = true, token = tok } })
                -- hidden achievements: players only see the hint (the same line as the Achievements table's)
                if r.hint then F:text("h" .. i, getText("IGUI_MQ_Admin_TitleHint", r.hint), "textMuted") end
            end
        end
    end
    -- past seasons: the same titles with their own number; one line instead of 17 rows per season by default
    -- (3 ranks + one per season board but points)
    if paid >= 1 then
        groupRow(getText("IGUI_MQ_Admin_TitleGroupOld", tostring(paid)))
        F:text("old", getText("IGUI_MQ_Admin_TitleOldNote"), "textMuted")
    end
    F:listEnd(L, getText("IGUI_MQ_Admin_NoTitles"))
end

A.pages.titles = { layout = layout }
