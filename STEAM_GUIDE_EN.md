<!-- 指南網址：https://steamcommunity.com/sharedfiles/filedetails/?id=3827763966 -->
<!-- Steam guide source (English): the full reference for this mod; the Workshop description only summarizes. Format and sync: pz-family-docs/release.md「完整說明：Steam 指南」 -->
<!-- 標題：📖 Quests & Achievements Mod Guide: Quests, Achievements, Leaderboards & Admin Panel -->
<!-- 摘要：Illustrated guide to Minidoracat Quests & Achievements: daily and weekly quests, the server-wide quest and weekly server goal, streaks, newcomer quests, timed events, hordes, achievements and titles, leaderboards and seasons, My records, exchanging points for Survivor Coins and player settings, plus installation, sandbox options, the admin panel, season payouts, Economy integration, data and backups for hosts, and the API for other mod authors. -->
=== 🚀 Quick start
[b]繁體中文版：[/b][url=https://steamcommunity.com/sharedfiles/filedetails/?id=3827763929]Minidoracat Quests & Achievements 完整說明[/url]

The mod on Steam Workshop:
https://steamcommunity.com/sharedfiles/filedetails/?id=3827762894
Daily and weekly quests, achievements, season leaderboards and titles; pair it with the Economy mod to exchange points for Survivor Coins.
[olist]
[*] [b]Open the window[/b]: click the trophy icon (Quests & Achievements) on the family toolbar.
[*] [b]Check today's quests[/b]: the Daily quests page lists today's 4 quests; they advance as you play.
[*] [b]Earn points[/b]: completing quests, unlocking achievements and keeping a streak all give points.
[*] [b]See your rank[/b]: the Leaderboards page shows Season and All-time ranks.
[*] [b]Exchange[/b]: on servers with the Economy mod, turn points into Survivor Coins on the Exchange page.
[/olist]
[h3]Requirements[/h3]
[list]
[*] [b]Required[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library[/url]
[*] [b]Optional[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3801482125]Minidoracat Economy[/url], to exchange points for Survivor Coins on multiplayer servers.
[*] [b]Optional[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359]Minidoracat MiniMap[/url], to show the horde area on the minimap.
[/list]
[h3]Where it works[/h3]
[list]
[*] [b]Single player and multiplayer[/b]: all progress is counted by the server (the game itself in single player).
[*] [b]Exchange is multiplayer only[/b]: the Economy mod supports dedicated servers only.
[*] [b]Split screen[/b]: players 2-4 do not earn progress.
[*] [b]Adding it mid-save[/b]: zombie kills, days survived and skill levels are imported; see the FAQ.
[/list]
[h3]Opening and sizing the window[/h3]
[list]
[*] [b]Hotkey[/b]: unbound by default. Set "Open / close Quests & Achievements" under "Minidoracat Quests & Achievements" in Options > Key Bindings.
[*] [b]Number on the toolbar icon[/b]: completions and unlocks you have not seen yet; it clears when you open the Daily quests or Achievements page.
[*] [b]Window size[/b]: drag the bottom-right corner and the game remembers it; when the size differs from the default, "Reset size" in the title bar brings it back.
[/list]
=== 🧰 Daily quests
{{img:01-daily-en.jpg}}
[h3]Today's 4 quests[/h3]
[list]
[*] [b]3 personal quests[/b]: drawn from 11 themes, never two on the same stat in one day.
[*] [b]1 server-wide quest[/b]: one a day with the same target for everyone; the page shows how many players finished it today. Experience quests are never the server-wide quest (XP is multiplied by profession bonuses, so matching professions are much faster), and neither are quests not everyone can do: a set weapon type, driving, hunting or night fishing.
[*] [b]Progress[/b]: counts from the moment the quest appears; earlier play does not count.
[*] [b]Reset[/b]: at the daily reset; unfinished quests expire. The top of the page shows the time left.
[/list]
[h3]Points[/h3]
[table]
[tr][th]Quest[/th][th]Default points[/th][/tr]
[tr][td]Regular daily quest[/td][td]15[/td][/tr]
[tr][td]Rare quest (fishing, trapping, animal care, tailoring, foraging)[/td][td]20[/td][/tr]
[tr][td]Server-wide quest[/td][td]20[/td][/tr]
[/table]
[list]
[*] [b]Rare themes pay more[/b]: Tailoring, Animal Care, Fishing & Trapping and Foraging dailies take more setup and pay 5 more by default; each card shows its points.
[/list]
[h3]Swaps and preferences[/h3]
[list]
[*] [b]Swap quest[/b]: swap 1 personal quest per day; a quest with progress asks first (the progress cannot be restored); the server-wide quest cannot be swapped.
[*] [b]XP quests[/b]: "Earn N XP" quests only go to a skill with a profession or trait XP bonus that is below level 10 (the game gives no XP at 10, and a quarter without a bonus); otherwise another quest of the same theme comes, also when you swap.
[*] [b]Preferred themes[/b]: pick up to 3 themes under Settings; each day 2 quests come from your themes and 1 from all themes. When a preferred theme has no quest left for the day, that slot draws from your other preferred themes.
[*] [b]No preferences[/b]: the three slots draw one each from Combat, Production (Building, Crafting, Cooking, Tailoring, Mechanics & Electrical) and Outdoors (Farming, Animal Care, Fishing & Trapping, Foraging, Exploration).
[*] [b]When it applies[/b]: change preferences as often as you like; if today's quests already exist, the change applies from the next reset.
[/list]
[h3]Streaks[/h3]
[list]
[*] [b]A day counts[/b]: when you finish 3 of the 4 quests (the server-wide quest counts).
[*] [b]Grace day[/b]: you may miss 1 day per week and it still counts toward the streak; grace resets on Monday.
[*] [b]Break[/b]: a missed day after the grace is used resets the streak at the next reset.
[*] [b]Milestones[/b]: each paid once per streak; after a reset you can earn them again.
[/list]
[table]
[tr][th]Streak[/th][th]Reward[/th][/tr]
[tr][td]3 days[/td][td]15 points[/td][/tr]
[tr][td]7 days[/td][td]40 points[/td][/tr]
[tr][td]14 days[/td][td]80 points[/td][/tr]
[tr][td]30 days[/td][td]150 points + title[/td][/tr]
[/table]
[h3]Newcomer quests[/h3]
[list]
[*] [b]Who gets them[/b]: new accounts, from their first appearance; accounts that had already survived more than 24 hours when the mod was added skip them.
[*] [b]5 steps, any order[/b]: kill 5 zombies, craft 1 item, finish reading 1 book, leave your starting town with a weapon in hand, sleep indoors once.
[*] [b]How long[/b]: shown at the top of the Daily quests page until all are done or 7 days pass.
[*] [b]Reward[/b]: 100 points and the title "Rookie Survivor".
[*] [b]Death[/b]: does not restart them; progress is kept.
[/list]
[h3]Timed events[/h3]
[list]
[*] [b]During an event[/b]: in a period the admin schedules, daily and weekly quest points for one theme (or all quests) are multiplied.
[*] [b]Not affected[/b]: achievement and server goal points.
[*] [b]Shown[/b]: running events are listed on the Daily quests page.
[/list]
=== 🧰 Weekly quests and server goal
{{img:02-weekly-en.jpg}}
[h3]Weekly quests[/h3]
[list]
[*] [b]How many[/b]: 3 a week, 60 points each.
[*] [b]Reset[/b]: at the daily reset time on Monday.
[*] [b]Themes[/b]: one slot each from Combat, Production and Outdoors; preferences are not used. All 11 themes have weekly quests.
[/list]
[h3]This week's server goal[/h3]
[list]
[*] [b]What it is[/b]: the whole server works toward one total, rotating weekly: kills, crafting, distance driven, fishing, harvesting.
[*] [b]Target[/b]: 1.1 times last week's server total, kept between a minimum and maximum per stat; the first week uses the minimum.
[*] [b]Reward[/b]: when the goal is reached, everyone whose contribution this week meets the minimum gets 50 points.
[*] [b]Late is fine[/b]: if you reach the minimum contribution after the goal is reached, you are paid when you do.
[*] [b]Your contribution[/b]: the page shows what you contributed this week and the minimum.
[/list]
=== 🧰 Hordes
{{img:13-horde-en.jpg}}
Once an admin sets up spots, the server can start a horde during its time windows: zombies come at a spot in waves, and every wave cleared in time pays points for its kills.
[h3]How to take part[/h3]
[olist]
[*] [b]The warning[/b]: before it starts, everyone gets a "Horde warning" with the place, how many minutes until the start, the number of waves and the kinds that may appear (for example Regular zombies and Sprinters), never the count. When an admin starts one with a warning of 0, the message says it starts now.
[*] [b]Reminder[/b]: when the warning is longer than 2 minutes, players within 30 tiles of the spot get one more notice 2 minutes before the start. If you do not want to take part, leave then: the first wave comes when someone is within 30 tiles.
[*] [b]Get there[/b]: once it has started, a wave comes as soon as someone is within 30 tiles of the spot, and the wave's timer starts. Each wave waits only so long for players; if nobody comes, the horde fails.
[*] [b]How big a wave is[/b]: it depends on how many living players are within 30 tiles when it starts: the admin sets a base count and how many % of it each extra player adds.
[*] [b]Where it comes from[/b]: the zombies appear 30 to 40 tiles from the spot, from up to 8 directions and at least 25 tiles from every player, and a sound at the spot draws them in. In very heavy rain (or rain with thick fog), or when zombie hearing is set to Poor, Random or Random between Normal and Poor in the sandbox (with Random some zombies hear poorly), the sound does not carry that far and the wave appears right at the spot.
[*] [b]Not all at once[/b]: only so many horde zombies are on the field at a time; more come in as they die.
[*] [b]Clear it[/b]: kill every zombie of the wave within its time limit while a player is within 50 tiles of the spot, so chasing the last ones out to the edges is fine. Zombies killed by others or burnt count as cleared too. After a short rest the next wave comes, again once someone is within 30 tiles; clearing the last wave clears the horde.
[*] [b]Get points[/b]: only players with a kill get points; see "Reward" below.
[/olist]
[h3]Where to see it[/h3]
[list]
[*] [b]Tracker panel[/b]: a horde row on top shows the place, "Wave W/N" when there is more than one, the countdown ("Starts in", "left" or "Next wave in") and "Cleared N/M". It does not use one of the 5 slots, has no ×, and shows even when you track nothing. "Show the tracker panel" in the mod options must be on.
[*] [b]Daily quests page[/b]: a horde banner under the timed events shows the current state; for 10 minutes after the end it shows the result, the waves cleared, your kills and the points you got.
[*] [b]Map button[/b]: before the start, while waiting for players and during a rest, the tracker row and the banner have a "Map" button that opens the world map on the spot. It is hidden when the server turns the world map off.
[*] [b]Minimap[/b]: with Minidoracat MiniMap installed, the minimap marks the area around the spot.
[*] [b]Notices[/b]: the warning, each wave appearing, the rest between waves, cleared, failed and cancelled go to everyone; the reminder 2 minutes before the start goes only to players near the spot; points you get come with a "Horde reward" notice and your kills in the cleared waves.
[/list]
[h3]Hordes page[/h3]
{{img:15-hordes-en.jpg}}
Once the server has automatic hordes on or has had a horde, a "Hordes" page appears on the left of the window.
[list]
[*] [b]Now[/b]: the same banner as on the daily quests page; with no horde it says so.
[*] [b]My hordes[/b]: your totals for hordes joined, hordes cleared, horde kills and hordes where you were the top killer. One kill counts as joining.
[*] [b]Recent hordes[/b]: the last 10 hordes on the server with time, place, result (waves cleared, or the wave it failed in), your kills and your points; older ones only count in your totals.
[/list]
[h3]Reward[/h3]
[list]
[*] [b]Points per kill[/b]: each kill earns that kind's points (by default Regular zombies 5, Sprinters 8; a kind without its own points pays like a regular zombie).
[*] [b]Only cleared waves pay[/b]: kills in a wave that fails earn nothing; the waves cleared before it still pay, whatever the result.
[*] [b]Cap[/b]: one horde pays at most a set total (500 by default). When the kills add up to more, everyone's share shrinks in proportion.
[*] [b]Where it counts[/b]: season, all-time and balance, so it can be exchanged.
[*] [b]Horde achievements[/b]: once the server has automatic hordes on or has had a horde, the achievements page gets a "Hordes" category: hordes cleared, horde kills and top killer (cleared hordes with 2 or more players, ties count for all), five tiers each. The first horde you help clear also unlocks a hidden achievement and the title "Horde Hunter".
[*] [b]Kills still count[/b]: horde kills count for kill stats, quests and achievements as usual.
[/list]
[h3]Failing[/h3]
[list]
[*] [b]Time runs out[/b]: the zombies left in that wave are removed; the waves already cleared still pay.
[*] [b]Other reasons[/b]: nobody came within 30 tiles in time, an admin stopped it, the server restarted during a wave, or the wave could not appear at the spot. Zombies already out when the server restarts stay as normal zombies; a horde that is not in the middle of a wave (planned, announced, waiting for players or resting) carries on.
[*] [b]Zombies that wander off[/b]: horde zombies that follow someone far away and get stored by the game become normal zombies; they no longer count for the horde, so there is no need to chase them.
[/list]
[b]Admins[/b]: spots, time windows, waves, kinds and the reward are set up as described in "Horde settings".
=== 🧰 Achievements and titles
{{img:03-achievements-en.jpg}}
[h3]Categories[/h3]
[table]
[tr][th]Category[/th][th]Covers[/th][/tr]
[tr][td]Combat[/td][td]Total kills, melee, firearms, vehicles, each weapon type, at night, indoors, hunting[/td][/tr]
[tr][td]Survival[/td][td]Days survived in one life, total days survived, bandaging, medical care, sleeping indoors, barricading, clearing corpses, washing[/td][/tr]
[tr][td]Skills[/td][td]All 35 skills that can level up, total skill level, total XP[/td][/tr]
[tr][td]Production & Building[/td][td]Crafting, building, cooking, tailoring, smithing, knapping, carving, vehicle repair, installing parts, connecting power, scrapping[/td][/tr]
[tr][td]Farming & Wilds[/td][td]Planting, harvesting, fishing, foraging, trapping, butchering, milking, shearing, collecting eggs, chopping trees[/td][/tr]
[tr][td]Exploration[/td][td]Towns visited, walking, driving, reading, placing furniture[/td][/tr]
[tr][td]Quests[/td][td]Daily, weekly, longest streak, server goals, seasons joined, achievement tiers[/td][/tr]
[tr][td]Hordes[/td][td]Hordes cleared, horde kills, top killer (listed only on servers that run hordes)[/td][/tr]
[tr][td]Hidden[/td][td]17 achievements, only a hint until unlocked[/td][/tr]
[tr][td]Professions[/td][td]None built in; other mods add them through the API[/td][/tr]
[/table]
[h3]Tiers and points[/h3]
[table]
[tr][th]Tier[/th][th]Default points[/th][/tr]
[tr][td]Bronze I[/td][td]10[/td][/tr]
[tr][td]Silver II[/td][td]20[/td][/tr]
[tr][td]Gold III[/td][td]30[/td][/tr]
[tr][td]Platinum IV[/td][td]50 + title[/td][/tr]
[tr][td]Legend V[/td][td]80[/td][/tr]
[tr][td]Hidden achievement (1 tier)[/td][td]30, some give a title[/td][/tr]
[/table]
[list]
[*] [b]About 110 in total[/b]: 111 built in; a server may add custom achievements or achievements from other mods. Each category button shows unlocked/total.
[*] [b]Next tier[/b]: every achievement shows the next tier's threshold and points.
[*] [b]How the five tiers work[/b]: for counts, Legend V is 2.5 times Platinum IV; skill achievements are skill levels 2 / 4 / 6 / 8 / 10 (Fitness and Strength 6 to 10), so a skill title comes at level 8. Admins can add up to 10 tiers.
[*] [b]One-life achievements[/b]: those marked "One life" use this life's stats and start over after death; the rest use your all-time totals across characters.
[*] [b]Raised thresholds[/b]: unlocked achievements are never taken back. When thresholds are lowered or an update adds tiers, the tiers you already reached are added at your next login (points paid as usual, only you get the notice).
[/list]
[h3]Notifications[/h3]
{{img:10-toast-en.jpg}}
[list]
[*] [b]Your own[/b]: quest completions, achievement unlocks, streak milestones, the server goal, exchange results and season payouts.
[*] [b]Merged[/b]: several unlocks within 2 seconds become one "N achievements unlocked" notice.
[*] [b]Server-wide notices[/b]: when someone unlocks Gold III or higher (or a hidden achievement), every online player sees it, at most 1 per player per minute; anonymous players are not named, admins see "Name (anonymous)".
[*] [b]Turn server-wide notices off[/b]: untick "Show server-wide unlock notices" in Options > MODS > Quests & Achievements.
[/list]
[h3]Titles[/h3]
[list]
[*] [b]Earned from[/b]: top achievement tiers, hidden achievements, a 30-day streak, newcomer quests and season rewards.
[*] [b]Use one[/b]: pick one on the My records page (one at a time, or none). A server-wide notice names the title that unlock earned.
[*] [b]My titles[/b]: My records lists every title you have, how you got it and when, newest first; the one you use says "In use". Times are recorded from the version that added this list; titles you got before show "Early".
[*] [b]All titles for admins[/b]: the admin panel's read-only Titles tab lists every title and what earns it; titles of switched-off achievements show "(off)", changed text "(custom)", and hidden achievements add the hint players see. To change a title's text, press Edit on the Achievements tab.
[*] [b]Revoked or cleared[/b]: when an admin revokes achievement tiers, the titles those tiers gave go too (also after the text was changed, or the achievement switched off); a tier whose title is left empty in the achievement editor gives no title.
[*] [b]Where it shows[/b]: next to your name on leaderboards, one line above your name over your head, and after your name in chat (gold, multiplayer only).
[*] [b]When the head title is hidden[/b]: it follows the vanilla name rules: hidden when the server does not show names, when the player is invisible or disguised, or out of sight; when the server shows names only on mouse-over, the title also shows only when you point at that player. It steps aside while the player speaks or sits in a vehicle. Your own title follows the vanilla option Options > Multiplayer > Show your username.
[*] [b]Turn them off[/b]: Options > MODS > Quests & Achievements has separate ticks for head and chat titles; the host can also turn each off for everyone in the admin panel.
[/list]
=== 🧰 Tracker panel
{{img:12-tracker-en.jpg}}
[list]
[*] [b]Add[/b]: press "Track" on a daily or weekly quest card or an achievement card (press again to stop), up to 5; with 5 tracked, pressing "Track" on another card tells you to untrack one first.
[*] [b]What it shows[/b]: at the top left, next to the vanilla sidebar: quests show progress/target, achievements the next tier's target, a done quest gets a check mark and the points it paid.
[*] [b]Hordes[/b]: during a horde an extra row sits on top; it does not use one of the 5 slots (see "Hordes").
[*] [b]Move and fold[/b]: drag the panel to move it and the game remembers where; the arrow in its title row folds it to one line.
[*] [b]Untrack[/b]: point at a row and press the × that appears on its right.
[*] [b]Removed on its own[/b]: daily quests at the daily reset, weekly quests at the weekly reset, a swapped quest, and an achievement that reached its top tier.
[*] [b]When it steps aside[/b]: while the UI is hidden with V, the Esc menu is up, or your character is dead. It stays while the quest window is open, so a Track press shows up at once; the quest window and every other window draw over it.
[*] [b]Turn it off[/b]: untick "Show the tracker panel" in Options > MODS > Quests & Achievements.
[/list]
=== 🧰 Leaderboards and seasons
{{img:04-leaderboard-en.jpg}}
[h3]Boards[/h3]
[table]
[tr][th]Category[/th][th]Boards[/th][/tr]
[tr][td]Overall[/td][td]Points earned[/td][/tr]
[tr][td]Combat[/td][td]Kills, melee kills, firearm kills[/td][/tr]
[tr][td]Survival[/td][td]Days survived in one life[/td][/tr]
[tr][td]Skills[/td][td]Total skill level (All-time only), XP earned[/td][/tr]
[tr][td]Life[/td][td]Items crafted, structures built, crops harvested, fish caught, distance driven[/td][/tr]
[tr][td]Exploration[/td][td]Towns visited[/td][/tr]
[tr][td]Quests[/td][td]Daily quests completed, longest streak, achievement tiers[/td][/tr]
[tr][td]Professions[/td][td]Boards added by other mods[/td][/tr]
[/table]
[list]
[*] [b]Season and All-time[/b]: Season boards use this season's amounts, All-time boards your totals.
[*] [b]Each page[/b]: the top 50, plus your rank, how it changed and how much more you need for the next rank.
[*] [b]Updates[/b]: Season boards every 5 minutes, All-time boards every 30 minutes; the page shows the last update.
[*] [b]Not ranked[/b]: accounts offline for 180 days (data is kept) and accounts an admin removed from the leaderboards.
[*] [b]Anonymous[/b]: turn it on under Settings; you are still ranked, others see "Anonymous survivor" and no title, admins see "Name (anonymous)".
[/list]
[h3]Seasons[/h3]
[list]
[*] [b]Length[/b]: 28 days by default (real time), ending at a daily reset. The top of the page shows the season number, when it ends and the time left.
[*] [b]What ranks you[/b]: points earned this season on the Overall board. Exchanging does not lower your rank.
[*] [b]Season end[/b]: ranks freeze and a new season starts at once, so points earned during the payout count for the new season.
[*] [b]Payout[/b]: after the admin confirms, and automatically within 24 hours at the latest; you do not need to do anything.
[/list]
[h3]Season rewards (the Season rewards tab on Leaderboards)[/h3]
[table]
[tr][th]Rank[/th][th]Default reward[/th][/tr]
[tr][td]1st[/td][td]600 points + title[/td][/tr]
[tr][td]2nd-3rd[/td][td]400 points + title[/td][/tr]
[tr][td]4th-10th[/td][td]200 points + title[/td][/tr]
[tr][td]Earned 250+ this season (participation, stacks with rank rewards)[/td][td]100 points[/td][/tr]
[tr][td]1st on any other board[/td][td]Title only[/td][/tr]
[/table]
[list]
[*] [b]Reward points go to your balance only[/b]: you can exchange them, but they do not count toward any ranking.
[*] [b]Your standing[/b]: the tab shows your points and rank this season, and how much more you need for the participation reward.
[/list]
=== 🧰 My records and points
{{img:05-records-en.jpg}}
[h3]Three point numbers[/h3]
[table]
[tr][th]Number[/th][th]Used for[/th][/tr]
[tr][td]Earned this season[/td][td]Overall Season rank and the participation reward[/td][/tr]
[tr][td]Earned all-time[/td][td]All-time ranks[/td][/tr]
[tr][td]Balance[/td][td]Exchanging for Survivor Coins[/td][/tr]
[/table]
[table]
[tr][th]Source[/th][th]Season[/th][th]All-time[/th][th]Balance[/th][/tr]
[tr][td]Quests, achievements, streaks, server goal, newcomer quests, hordes[/td][td]+[/td][td]+[/td][td]+[/td][/tr]
[tr][td]Achievements imported when the mod was added mid-save[/td][td]-[/td][td]+[/td][td]-[/td][/tr]
[tr][td]Season rewards[/td][td]-[/td][td]-[/td][td]+[/td][/tr]
[tr][td]Exchanging for Survivor Coins[/td][td]-[/td][td]-[/td][td]minus[/td][/tr]
[/table]
[h3]Stats table[/h3]
[list]
[*] [b]This life[/b]: resets when your character dies.
[*] [b]Season[/b]: this season's amount.
[*] [b]All-time[/b]: kept across characters; achievements use this column.
[/list]
[h3]Titles[/h3]
[list]
[*] [b]Pick a title[/b]: the title menu at the top of the page; choose "No title" to remove it.
[*] [b]My titles[/b]: the list under the title menu: every title you have, how you got it and when.
[/list]
=== 🧰 Exchanging for Survivor Coins
{{img:06-exchange-en.jpg}}
The server needs Minidoracat Economy (multiplayer only). The Exchange page on the left of the window (listed while the server can exchange or you have exchange history) shows your balance, how much you can still exchange today and the rate; press "Exchange for survivor coins...".
[list]
[*] [b]Rate[/b]: 1 point = 1 Survivor Coin by default, set by the host.
[*] [b]Limits[/b]: by default up to 100 points per player per day, at least 10 per exchange; "All available" fills in the smaller of your balance and today's remaining limit.
[*] [b]Balance only[/b]: ranks use points earned, so exchanging never lowers your rank.
[*] [b]Queued[/b]: when the Economy mod's daily allowance for this mod is used up, your points are held and paid automatically later (retried every hour and right after the Economy mod's daily reset).
[*] [b]Refunded[/b]: if your economy account cannot receive coins, the points come back and you are asked to contact an admin.
[*] [b]No reply[/b]: press "Ask again" to check the result; asking again never exchanges twice.
[*] [b]Imported achievements[/b]: points from achievements imported mid-save never reach your balance and cannot be exchanged.
[*] [b]Exchange history[/b]: once you have exchanged, the Exchange page lists the last 10 below the balance card (time, points to coins, Queued / Credited / Points returned). In the Economy admin ledger the reason reads "Quest points exchange"; from Economy 42.21.0-0.23.0 on, your wallet statement and the receipts on the Economy admin's Player page read it too.
[/list]
=== 🧰 Settings
{{img:07-settings-en.jpg}}
[h3]Settings in the window[/h3]
[list]
[*] [b]Quest preferences[/b]: pick up to 3 themes and press Apply; rules under "Daily quests".
[*] [b]Appear anonymous on leaderboards[/b]: you are still ranked, others see "Anonymous survivor", and server-wide notices do not name you; admins can still see who you are. Only applies to this mod's leaderboards and notices: your title over your head and in chat still shows.
[*] [b]Quests by theme[/b]: at the bottom of the page, "Show" lists each theme's daily and weekly quests with their target ranges at the current difficulty and their points; rare quests are marked. By default only admins see it; once the server owner turns it on under Admin > Quests, players see it too.
[/list]
[h3]Mod options (Options > MODS > Quests & Achievements)[/h3]
[list]
[*] [b]Show the toolbar entry[/b]: when hidden, the hotkey still opens the window.
[*] [b]Show server-wide unlock notices[/b]: when off, other players' unlocks are not shown.
[*] [b]Show the tracker panel[/b]: the tracker panel at the top left.
[*] [b]Show titles above heads[/b]: other players' (and your own) head titles; turning it off also saves this computer the drawing.
[*] [b]Show titles in chat[/b]: the title after the name in chat lines.
[/list]
=== ⚙️ Installation and load order
[list]
[*] [b]Multiplayer server[/b]: in Mods= put MinidoracatQuestFor42 after MinidoracatUIFor42, and add both Workshop IDs to WorkshopItems=; add the Economy mod for exchanges (its position does not matter to this mod).
[*] [b]Same version[/b]: the server and every player need the same version.
[*] [b]Single player[/b]: subscribe and enable it in the mod list; in single player you are always an admin and see the Admin page.
[*] [b]Mid-save[/b]: fine; on an existing save each account's old progress is imported the first time it appears, see the FAQ.
[/list]
=== ⚙️ Sandbox options and defaults
The sandbox page "Minidoracat Quests & Achievements" has three options; everything else is set in the in-game admin panel or directly in config.json on the server (see "Settings file config.json").
[table]
[tr][th]Option[/th][th]Default[/th][th]Notes[/th][/tr]
[tr][td]Time zone (UTC offset, hours)[/td][td]8[/td][td]-12 to 14; time zone for the daily reset, times on screen and the horde time windows[/td][/tr]
[tr][td]Daily reset hour[/td][td]0[/td][td]0-23; local hour when daily quests reset; weekly quests reset at this hour on Monday[/td][/tr]
[tr][td]Admin roles[/td][td]admin[/td][td]Role names that can open the admin panel, separated by commas or semicolons, case-sensitive; use English names, as non-English characters are corrupted on every server restart[/td][/tr]
[/table]
[list]
[*] [b]With the Economy mod[/b]: when the Economy mod provides its day-change API, the daily and weekly reset follow the Economy mod's daily reward reset and the first two options no longer decide it; the horde time windows still use this time zone.
[/list]
[h3]Main admin panel defaults[/h3]
[table]
[tr][th]Setting[/th][th]Default[/th][/tr]
[tr][td]Daily quest points / rare / server-wide[/td][td]15 / 20 / 20[/td][/tr]
[tr][td]Swaps per day[/td][td]1[/td][/tr]
[tr][td]Weekly quests[/td][td]3, 60 points each[/td][/tr]
[tr][td]Server goal[/td][td]On, 50 points when reached, target ×1.1 of last week[/td][/tr]
[tr][td]Streaks[/td][td]3 quests count as a day, 1 grace day per week[/td][/tr]
[tr][td]Players see the quests by theme[/td][td]Off (admins only)[/td][/tr]
[tr][td]Newcomer quests[/td][td]On, 100 points + title[/td][/tr]
[tr][td]Achievement points[/td][td]10 / 20 / 30 / 50 / 80 per tier, hidden 30[/td][/tr]
[tr][td]Difficulty[/td][td]Normal (Easy ×0.6, Hard ×1.6; only thresholds and quest targets; skill levels and towns visited have a ceiling and stay as they are)[/td][/tr]
[tr][td]Season length[/td][td]28 days (7-180)[/td][/tr]
[tr][td]Exchange[/td][td]On, 1 point = 1 Survivor Coin, 100 points per player per day, at least 10[/td][/tr]
[tr][td]Server-wide notices[/td][td]On, from tier 3, 1 per player per minute[/td][/tr]
[tr][td]Hordes[/td][td]Automatic hordes off (settings in "Horde settings")[/td][/tr]
[tr][td]Not ranked[/td][td]Offline for 180 days[/td][/tr]
[/table]
=== ⚙️ Admin panel
{{img:08-admin-basic-en.jpg}}
Open "Admin" on the left of the window (its own group at the bottom of the list); only roles listed in the "Admin roles" sandbox option see it, and the server checks every action again.
[h3]How changes work[/h3]
[list]
[*] [b]Tabs[/b]: settings come first (General, Achievements, Titles, Quests, Season, Exchange, Towns, Hordes); after the divider come operations (Players, Report, Balance, History). For Hordes see "Horde settings".
[*] [b]Draft first[/b]: edits go into pending changes; press "Apply" at the bottom to see old and new values, then confirm. "Discard changes" asks before it discards.
[*] [b]Instant buttons[/b]: timed events, horde start/cancel/stop, the payout review and account actions skip that confirmation; those sections say so.
[*] [b]Unlocks are kept[/b]: higher thresholds only affect what comes next.
[*] [b]Times[/b]: shown in the sandbox time zone.
[/list]
[h3]General[/h3]
Steps 1-5 cover the common settings; the other tabs hold the rest.
[olist]
[*] [b]Difficulty[/b]: Easy, Normal, Hard or a custom multiplier; changes thresholds and quest targets only, not points. A button first lists the estimated effect, then you confirm.
[*] [b]Season[/b]: days per season and the next settlement; a button takes you to the Season tab to change it.
[*] [b]Rewards[/b]: 1st, 2nd-3rd, 4th-10th and participation.
[*] [b]Exchange[/b]: on/off, rate, per-player daily limit; without the Economy mod the step says why.
[*] [b]Newcomer quests and announcements[/b]: newcomer quests on/off, announcements on/off and the tier they start from.
[/olist]
[h3]Achievements[/h3]
[list]
[*] [b]Batch edits[/b]: act on every achievement in the category shown; multiply thresholds or points, or add a tier.
[*] [b]Single edit[/b]: threshold, points and title for each tier, up to 10 tiers; you can also turn the achievement off, so players no longer see it on the achievements page and cannot unlock it.
[*] [b]Marks[/b]: changed achievements show "(changed)", disabled ones "(off)".
[*] [b]Custom achievements[/b]: add one from an existing stat (name, category, thresholds, points), or delete it.
[*] [b]Hidden achievements[/b]: pick the Hidden category; each row lists what unlocks it and the hint players see. Edit changes their thresholds, points and titles. A custom achievement cannot be made hidden, and the hint text cannot be changed.
[*] [b]Announcements and title display[/b]: announcements on/off, starting tier, announcements per player per minute; one server-wide switch each for head and chat titles, off means nobody sees them.
[/list]
[h3]Quests[/h3]
[list]
[*] [b]Players see each theme's quests[/b]: the switch at the top of the tab, off by default. Off, only admins see the quests-by-theme list at the bottom of Settings, marked as hidden from players; on, players see it too. It goes through Apply and History like any setting.
[*] [b]Theme filter[/b]: the list shows how many daily and weekly quests each theme has; with a theme picked, buttons beside the filter turn the whole group on or off, or multiply its targets by 0.8 or 1.25. The result goes into pending changes, the bar says what was done, and templates with pending changes show "(changed)". Buttons under the filter jump to the community goal, streak rewards, newcomer quests and timed events.
[*] [b]Daily and weekly pools[/b]: on/off, target range and points per template; of two templates with the same name, the bigger one shows "(bulk)".
[*] [b]Daily and weekly settings[/b]: points for the server-wide quest, swaps per day, weekly quests.
[*] [b]Community goal[/b]: on/off, reward, growth over last week, and the minimum, maximum and minimum contribution of each stat in the rotation.
[*] [b]Streak rewards[/b]: quests needed per day, grace days per week, milestones.
[*] [b]Newcomer quests[/b]: on/off and reward.
[*] [b]Timed events[/b]: name, quest theme (or all quests), multiplier (1-5), start and end date (inclusive); up to 3 at a time, removable. Adding and removing take effect at once and cannot be undone from History.
[/list]
[h3]Exchange[/h3]
{{img:11-admin-exchange-en.jpg}}
[list]
[*] [b]Exchange settings[/b]: on/off, rate, per-player daily limit, minimum per exchange.
[*] [b]Today[/b]: exchanged today, estimated daily exchange, and the Economy mod's daily limit for this mod with today's usage, all server-wide totals.
[*] [b]Warnings[/b]: shown at the top when the Economy limit is 0, cannot be read, this mod is disabled in the Economy mod, or the estimate exceeds the limit; see "Economy integration".
[*] [b]Change the limit[/b]: the button opens the Economy mod's "Integration sources" page.
[/list]
[h3]Towns[/h3]
[list]
[*] [b]12 built in[/b]: Muldraugh, West Point, Riverside, Rosewood, Louisville, Brandenburg, Ekron, Irvington, Echo Creek, Fallas Lake, March Ridge, Valley Station; each can be disabled.
[*] [b]Custom towns[/b]: a name and two corners; "Use my position" fills in coordinates.
[*] [b]Used for[/b]: town achievements, the Towns visited board and the newcomer step "leave your starting town".
[/list]
[h3]Players[/h3]
[list]
[*] [b]Anomalies[/b]: today or the last 7 days, records of a stat going over its per-minute limit. Every stat has one (120 zombie kills by default, for example); each row shows that minute's total and the limit. The excess is not counted, so it does not advance quests or achievements.
[*] [b]Per-minute limits[/b]: "Per-minute limits..." at the bottom of the page opens the limit of every stat (1-1,000,000); changes go into pending changes like any other.
[*] [b]Look up an account[/b]: View on a row, or type the account, lists at the top of the page its three point numbers, achievements, anomalies this season and whether it is removed from the leaderboards.
[*] [b]Revoke achievements[/b]: down to a chosen tier, or all of it.
[*] [b]Remove from or return to the leaderboards[/b]: data is kept. Revoking and removing require a reason and record who did it.
[/list]
[h3]Report[/h3]
[list]
[*] [b]Scope[/b]: totals for the last 7 or 30 days, counts only, no individual players; recounted when the page opens and kept for 5 minutes.
[*] [b]Usage[/b]: players with activity today and in the period, new accounts, daily and weekly completion, swaps, 7+ day streaks, and a pair of bars per day: players with activity and players who finished a daily quest.
[*] [b]Points[/b]: paid out in the period and the share from each source, coins exchanged, unspent points and the share the top 10% hold.
[*] [b]Achievements[/b]: players per tier of each achievement; those nobody unlocked come last (hidden ones counted, not named).
[*] [b]Export JSON[/b]: report-YYYY-MM-DD.json beside config.json, one per day, with no player names or accounts.
[/list]
[h3]Balance[/h3]
[list]
[*] [b]Completion rate[/b]: for each quest template, times given, completion, median time to finish and times swapped away; daily quests over the last 7 days, weekly quests over the last week that ended; weekly quests show "(weekly)". Completion leaves out swapped quests.
[*] [b]Suggestions[/b]: quests given 10+ times with completion under 30% or over 90% show their current and suggested target range; those given fewer times say "Too few samples". "Apply N suggestions..." lists every change before you confirm.
[/list]
[h3]History[/h3]
[list]
[*] [b]Undo[/b]: the last 20 changes; undo writes the old values back and counts as a change itself.
[*] [b]Settings file state[/b]: below the list you see the folder of config.json and when it was last in sync; when the file has an error and was not applied, you see the line or the field.
[*] [b]File-only settings[/b]: leaderboards (boards), community goal rotation (goal.rotation), newcomer title and days (newbie.title, newbie.days); see "Settings file config.json".
[/list]
=== ⚙️ Horde settings
{{img:14-admin-hordes-en.jpg}}
The "Admin > Hordes" tab runs from top to bottom in this order:
[list]
[*] [b]Now[/b]: the current horde's place, state, "wave W/N", how many are cleared and its times; while it waits for players, the time it waits until (nobody by then: it fails); during a rest "next wave in M:SS". "Cancel this horde" before it starts, "Stop this horde" after (it fails, the cleared waves still pay, its zombies on the field are removed); both ask first. Below: "Today N / M hordes, next roll HH:MM" and "Refresh".
[*] [b]Start a horde[/b]: skips the roll and starts a horde at a random spot with the applied settings, even with automatic hordes off; it does not count toward the daily limit. Fill in the "Warning" minutes to the left of the button (the applied "Warning before start (min)" by default, 0 to 120; 0 starts it now). With a horde already planned or running, cancel or stop it first. Starting and stopping are listed in History but cannot be undone.
[*] [b]Recent results[/b]: the last 5 hordes with the waves cleared and the points paid ("(capped)" when the cap was hit), the kills for cleared hordes and the reason for failures.
[*] [b]Spots[/b]: stand where a horde should appear, fill in "Spot name" and press "Add my current position"; up to 32 spots, one picked at random for each horde. Each row has a "Map" button that opens the world map on the spot. Automatic hordes and "Start a horde" need at least one spot. The zombies walk in from 30-40 tiles around the spot, so keep spots more than 60 tiles from player bases.
[*] [b]Time windows[/b]: "Automatic hordes" (off by default), then one row per window: the start and end time with "to" between them (HH:MM in the sandbox time zone; an end earlier than the start runs past midnight and belongs to the day it starts, equal means all day), "chance per hour" and the seven weekday buttons (pick at least one), and "Remove"; "Add a window" up to 8. Each window rolls once an hour during its time and, on a hit, schedules a horde within that hour; identical windows each roll on their own, and only one horde runs at a time. Below: "Hordes per day at most" (all windows together), "Warning before start (min)" and "Fail if nobody comes (min)" (how long each wave waits for someone within 30 tiles before the horde fails).
[*] [b]Waves[/b]: one row per wave with "Base" and "Per extra player" (%), and the wave's size for 1 and 4 players; "Add a wave" up to 10 (it copies the last row), at least one stays. Below: "Rest between waves (s)", "Time limit per wave (min)" and "Most alive at once", with the server's sandbox delete threshold next to it: keep "Most alive at once" below it, or the game may delete far zombies, which do not count as kills.
[*] [b]Kinds[/b]: one row per kind above 0 with "Weight", "Share" and "Points each", and "Remove". Weights are relative and need not add up to 100; only kinds above 0 appear, and the warning lists only those. Add others from the "Add a kind..." dropdown: they start at weight 10 and, without points of their own, at the regular zombies' points. A kind whose mod was removed shows "Not installed" and can be removed.
[*] [b]Reward[/b]: "Most one horde pays (pts)" and "Estimate with these settings (every wave cleared)" for 1, 4 and 8 players, marked "(cap)" where the cap cuts it. The wave sizes, shares and estimate follow what you type.
[*] [b]Like other settings[/b]: spots, windows, waves, kinds and fields go into pending changes and take effect with "Apply" at the bottom; they are kept in History and written to config.json (see "Settings file config.json"). A horde already scheduled keeps the settings it was planned with.
[/list]
[table]
[tr][th]Setting[/th][th]Default[/th][/tr]
[tr][td]Time windows[/td][td]Every day 19:00 to 23:00, 30% per hour, 1 horde per day at most[/td][/tr]
[tr][td]Warning / wait for players[/td][td]15 min / 60 min per wave[/td][/tr]
[tr][td]Waves[/td][td]1 wave of 30 zombies, +50% per extra player; 30 s rest between waves; 200 alive at once at most[/td][/tr]
[tr][td]Kinds (weight / points each)[/td][td]Regular zombies 80 / 5, Sprinters 20 / 8[/td][/tr]
[tr][td]Time limit / cap[/td][td]15 min per wave / 500 points per horde[/td][/tr]
[/table]
=== ⚙️ Settings file config.json
The admin panel settings (except timed events and the season length) are also kept in a file on the server, so you can change them without joining the game. Location: Lua/MinidoracatQuest/<server name>/ in the server's user folder (a dedicated server uses ~/Zomboid by default, %USERPROFILE%\Zomboid on Windows); in single player it is Zomboid/Lua/MinidoracatQuest/sp_<save name>/ on your own computer, one per save. The console prints this folder at start (settings files: …).
[table]
[tr][th]File[/th][th]Use[/th][/tr]
[tr][td]config.json[/td][td]The settings that differ from the defaults; edit this one[/td][/tr]
[tr][td]defaults.json[/td][td]Read-only: every default value, written the same way as config.json, so you can copy a block over and change it; rewritten at each start[/td][/tr]
[tr][td]status.json[/td][td]Read-only: the result of the last read or write (time, success, the line or field with the error)[/td][/tr]
[/table]
[list]
[*] [b]Applies within about a minute[/b]: the server reads the file every 60 seconds; when the text changed it checks and applies it and records a change "Applied from config.json", which you can undo in the panel. Edits made while the server is down apply at the next start.
[*] [b]Write only what you change[/b]: anything not written uses the default; removing a whole group (for example "exchange") puts that group back to the defaults. Lists such as tiers or the goal rotation are always written whole; so are achievement titles: a tier left out has no title.
[*] [b]An error stops the whole file[/b]: with broken JSON, a value out of range or a misspelt name, the current settings stay; status.json, the server console and the panel's History tab show the line where the JSON stopped or the field with the error (for example daily.pool.d_kill.target).
[*] [b]Panel changes rewrite the file[/b]: after an apply or undo in the panel the server writes the settings in effect back to config.json, so manual edits it has not read yet are overwritten. A deleted file is written again.
[*] [b]Not in the panel[/b]: leaderboards (boards), community goal rotation (goal.rotation), newcomer title and days (newbie.title, newbie.days) change only in this file.
[*] [b]Hordes (hordes)[/b]: every setting of the Hordes tab: enabled, windows (up to 8 {days, from, to, chance}: days such as "12345", 1 = Monday; from and to "HH:MM"; chance per hour; always written whole), maxPerDay, leadMin, waitMin, waves (up to 10 {base, perPlayer}, perPlayer = % of base per extra player; always written whole), restSec, maxAlive, kinds (kind id to weight; built in: vanilla, runner), points (kind id to points per kill; a kind left out pays like vanilla), limitMin, cap, spots (up to 32 {name, x, y, z}, always written whole). Ranges are in the GitHub README.
[*] [b]Older horde settings[/b]: from, to, chance, count, perZombie and split are gone. A file that still has them is converted at start or on the next read and written back: from/to/chance become one window on every day, count becomes one wave of its middle value that does not grow with players, perZombie becomes every kind's points, and split is dropped. An old key is kept instead when its new key is already in the file or its value was not valid before either; then the file is not applied and status.json names that key, so fix it by hand.
[*] [b]Restoring a world save[/b]: the server applies config.json at start, so the settings follow the file, not the older save.
[*] [b]Settings from the 4-tier days still work[/b]: an achievement whose tiers list has 4 numbers keeps 4 tiers; a pts list of 4 numbers (points changed, tiers not) pays the default 80 for tier 5.
[/list]
Example: the daily quest "Kill N zombies" (d_kill) gets a target of 30 to 60 and 20 points, the "Zombie Slayer" achievement (zombie_kills) gets doubled thresholds, and the exchange rate becomes 1 point for 2 Survivor Coins:
[code]{
  "achievements": {
    "zombie_kills": { "tiers": [200, 2000, 10000, 40000, 100000] }
  },
  "daily": {
    "pool": {
      "d_kill": { "target": [30, 60], "pts": 20 }
    }
  },
  "exchange": { "rate": 2 }
}[/code]
=== ⚙️ Season settings and payout
{{img:09-admin-season-en.jpg}}
[h3]Changing the season length[/h3]
[list]
[*] [b]Range[/b]: 7-180 days, real time.
[*] [b]Preview first[/b]: shows the new end of this season and the start of the next; the new end must be at least 24 hours away.
[*] [b]Applies now[/b]: to the current season.
[/list]
[h3]Season end and payout[/h3]
[olist]
[*] [b]Freeze[/b]: ranks freeze at the season end and a new season starts at once.
[*] [b]Review[/b]: the admin page lists the frozen ranks; accounts with anomalies are only flagged, never excluded automatically.
[*] [b]Exclude[/b]: press "Exclude from rewards" on a row and write a reason; "Include again" puts them back. These buttons act at once.
[*] [b]Pay[/b]: press "Confirm and pay..." and confirm again; payouts cannot be undone.
[*] [b]Automatic payout[/b]: if nobody acts within 24 hours, the frozen list minus excluded accounts is paid automatically.
[/olist]
[list]
[*] [b]Reward settings[/b]: 1st, 2nd-3rd, 4th-10th, participation reward and its minimum, and whether first place on other boards gets a title.
[*] [b]History[/b]: the last 12 seasons with dates, top 10 and first place on each board.
[/list]
=== ⚙️ Economy integration
[list]
[*] [b]Registers itself[/b]: once the server is up, this mod registers with the Economy mod as the integration source "Quests & Achievements" and pays in Survivor Coins.
[*] [b]The limit you must set[/b]: the Economy mod gives every integration source a daily mint limit of 0 by default, shared by all players on the server. Open the Economy admin's "Integration sources" page and set the "Daily issue cap" for Quests & Achievements; until you do, every exchange is queued and nothing is paid.
[*] [b]Choosing the limit[/b]: roughly players who exchange per day × per-player daily limit × rate; the estimate on this mod's "Exchange" admin tab helps.
[*] [b]Queue and retries[/b]: when the allowance is used up, rate-limited, the Economy mod is not ready or does not answer, the exchange is queued and retried every hour, plus right after the Economy mod's daily reset.
[*] [b]Refunds[/b]: any other refusal (for example a player's economy account cannot receive coins) refunds the points. One exchange is never paid twice.
[*] [b]Day change[/b]: when the Economy mod provides its day-change API (versions after 42.21.0-0.20.1), the daily and weekly reset happen at the same moment as the Economy mod's daily reward; reading the limit and today's usage needs the same versions. Older Economy versions still exchange, but the admin page cannot show the limit.
[/list]
=== ⚙️ Data and backups
[table]
[tr][th]Contents[/th][th]Location[/th][/tr]
[tr][td]Setting overrides, seasons, server-wide quest and server goal, timed events, hordes (the current one and the last 20 results), audit (last 500)[/td][td]Global ModData shared table MinidoracatQuest in the world save[/td][/tr]
[tr][td]Each account's stats, quests, points, achievements, titles, preferences, tracked items, exchange queue and last 10 exchanges[/td][td]Global ModData account tables MinidoracatQuest_A00-A15 (16 tables)[/td][/tr]
[tr][td]Account to Steam account bindings[/td][td]Zomboid/Lua/MinidoracatQuest/<server name>/identity.txt[/td][/tr]
[tr][td]Daily event log (one line per event)[/td][td]Same folder, events-YYYYMMDD.json, one per day[/td][/tr]
[tr][td]The admin panel settings file, every default value, the result of the last read[/td][td]Same folder, config.json, defaults.json, status.json[/td][/tr]
[tr][td]Audit log[/td][td]*_MinidoracatQuest.txt in Zomboid/Logs[/td][/tr]
[/table]
[list]
[*] [b]17 Global ModData tables[/b]: backed up and rolled back with the world save; they hold no Steam accounts or private data.
[*] [b]Event logs[/b]: a new uncompressed file every day; this mod only writes them, never reads them. Lua cannot delete files, so archive or delete old ones yourself.
[*] [b]Backups[/b]: back up the world save together with Lua/MinidoracatQuest/<server name>/. Without identity.txt, names on a Steam server are bound again only when each player comes back online. When you restore only the world save, the settings still follow config.json in that folder.
[/list]
=== ⚙️ For mod authors
Other mods can add stats, achievements, daily quests, Professions leaderboards and horde kinds on the server through MinidoracatQuest.v1. For a full example and field limits, see "給其他 MOD 的 API" (API for other mods) in the GitHub README:
https://github.com/Minidoracat/MinidoracatQuestFor42#給其他-mod-的-api
[list]
[*] [b]Detect[/b]: use it only when MinidoracatQuest.v1 exists and API_MAJOR == 1; skip it when the mod is not installed.
[*] [b]Register[/b]: call registerPack in OnServerStarted (multiplayer) or OnGameStart (single player); register again on every server start.
[*] [b]Report progress[/b]: on the server with pack.add(player, statId, n); clients have no way to report progress.
[*] [b]Limits[/b]: per mod 32 stats, 64 achievements and 32 quests; 50 pack.add calls per tick; n up to 1000.
[*] [b]Translations[/b]: names use translation keys your mod ships, so clients need your mod too.
[*] [b]Admins[/b]: can tune or disable your achievements and quests in the admin panel like any other.
[*] [b]Horde kinds[/b]: registerHordeKind (from API_REVISION 2; check with type that it is a function) registers a kind of zombie; your mod only spawns them, this mod handles timing, counting and clearing. 8 kinds per mod, 32 in all; a new kind's weight starts at 0 until an admin adds it from the Hordes tab's dropdown, and until it has points of its own a kill pays what a regular zombie pays.
[*] [b]Spawned zombies[/b]: only appearance, health, walk type and speed and some state flags of a server-spawned zombie reach clients, so set them when you spawn it; strength, sight and hearing are worked out on each computer, and modData does not sync. The engine reuses zombie objects without clearing useless from their last life (such a zombie ignores sounds and players), so call setUseless(false) at spawn if your kind should be drawn in.
[/list]
=== ⚠️ Known limitations
[list]
[*] [b]Anonymity only applies on this mod's leaderboard screens[/b]: the game lets clients read the save's shared data, so a modified client can see who is anonymous and every account's points.
[*] [b]The character who finishes an action comes from the client[/b]: which character crafting, building, repairs or fishing are credited to follows the character the client sent in the vanilla action; the server still verifies identity and applies per-minute limits.
[*] [b]Distance is a straight line per minute[/b]: detours and back-and-forth count less; only the driver earns driving distance, not passengers; a jump too large for one minute (teleport) is ignored.
[*] [b]Per-minute limits[/b]: each stat has a per-minute limit; anything above it does not count and is logged as an anomaly for admins.
[*] [b]Exchange is multiplayer only[/b]: the Economy mod supports dedicated servers only.
[*] [b]Split screen[/b]: players 2-4 do not earn progress; the tracker panel and head titles are for player 1 only.
[*] [b]Head titles approximate the vanilla rules[/b]: players in a vehicle get none. When the server shows names only on mouse-over (the vanilla default), the mod checks the floor square under the mouse and the squares around it, plus the player's body; vanilla uses the object under the mouse, so pointing at a wall or a tall object can differ by one square.
[*] [b]Chat titles[/b]: only lines that arrive while the author wears a title get one; a title changed or taken off later does not always update lines already shown. A mod that rewrites the whole vanilla chat window may keep them from appearing.
[*] [b]Horde zombies that wander off become normal[/b]: a zombie away from every player is stored by the game and the mod cannot recognise it when it comes back, so it stops counting for the horde and is not removed when time runs out.
[*] [b]A server restart fails the wave in progress[/b]: zombies already out stay as normal zombies and that wave pays nothing; the waves cleared before it still pay. A horde that is not in the middle of a wave (planned, announced, waiting for players or resting) carries on.
[*] [b]Wild zombies near the spot come too[/b]: horde zombies follow a sound from the spot every 5 seconds, and wild zombies nearby hear it as well; they do not count for the horde. The sound reaches at most 49 tiles, so it does not stir zombies farther away that are not loaded.
[*] [b]Removed zombies can linger for a few seconds[/b]: when time runs out or an admin stops a horde, the player in charge of those zombies (usually the closest one) may still see them for up to about 8 seconds.
[*] [b]Mid-save import is partial[/b]: only kills, days survived and skill levels; crafting, distance, fishing and the rest count from when the mod is added.
[*] [b]Player identity[/b]: on Steam servers a name is bound to its Steam account the first time it comes online; switching Steam accounts makes you a different player, and there is no way to unbind yet. No-Steam servers cannot stop someone respawning under another player's name; a modified client may take a name that has not come online to be bound yet.
[*] [b]Event logs keep growing[/b]: see "Data and backups".
[/list]
=== ❓ FAQ
[h3]My quest is not advancing?[/h3]
[list]
[*] Progress counts from the moment the quest appears; earlier play does not count.
[*] Split screen players 2-4 do not earn progress.
[*] On a multiplayer server, if you see "Your identity could not be verified", rejoin the server; if it continues, contact an admin.
[/list]
[h3]I added the mod to an old save. Does my earlier progress count?[/h3]
[list]
[*] Your current character's zombie kills, days survived in this life and skill levels are imported the first time each account appears, and matching achievements unlock quietly; everything else counts from the day the mod is added.
[*] Points from imported achievements only go to "earned all-time"; they do not count for the season and cannot be exchanged.
[*] Accounts that had survived more than 24 hours skip the newcomer quests.
[/list]
[h3]What happens if I remove the mod?[/h3]
[list]
[*] The mod adds no items, buildings or recipes, so removing it does not break the save.
[*] Progress stays in the save and the server folder and comes back when you reinstall; play while it is removed does not count.
[/list]
[h3]My exchange keeps saying "Queued"?[/h3]
[list]
[*] The Economy mod's daily limit for this mod is 0 by default; the host must set it on the Economy admin's "Integration sources" page.
[*] When the limit is used up, the coins are paid automatically later; you do not need to exchange again.
[/list]
[h3]Why did my rank not drop after exchanging?[/h3]
[list]
[*] Ranks use points earned; exchanging only spends your balance.
[/list]
[h3]When is the daily reset?[/h3]
[list]
[*] The top of the Daily quests page shows the time left. Without the Economy mod it follows the sandbox time zone and daily reset hour; with it, the Economy mod's daily reward reset. Weekly quests reset at the daily reset on Monday.
[/list]
[h3]I am anonymous. Can others still see me?[/h3]
[list]
[*] Other players do not see your name or title on this mod's leaderboards or in server-wide notices; admins do. A modified client can also read the save data; see "Known limitations".
[*] Your title over your head and in chat still shows; an anonymous leaderboard row has no title, so nobody can match your title to your rank.
[/list]
[h3]The horde never appears?[/h3]
[list]
[*] The warning already shows the spot's coordinates and a "Map" button. After the start time, a wave only comes once someone is within 30 tiles of the spot, and the same goes for every later wave; the zombies then walk in from 30 to 40 tiles away (in very heavy rain they appear right at the spot).
[*] Admins: automatic hordes are off by default and need at least one spot; "Admin > Hordes" shows today's count and the next roll.
[/list]
[h3]How do I become an admin?[/h3]
[list]
[*] Multiplayer: your server role name must be in the "Admin roles" sandbox option (admin by default). In single player you are always an admin.
[/list]
=== 💬 Feedback
[list]
[*] [b][url=https://github.com/Minidoracat/MinidoracatQuestFor42/issues]GitHub Issues[/url][/b]
[*] [b][url=https://discord.gg/Gur2V67]Discord community[/url][/b]: when reporting, please include
[list]
[*] Game mode (single player / multiplayer)
[*] What happened and the steps to reproduce it
[*] Error messages (if any)
[/list]
[/list]
