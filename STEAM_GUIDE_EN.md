<!-- Steam guide source (English): the full reference for this mod; the Workshop description only summarizes. Format and sync: pz-family-docs/release.md「完整說明：Steam 指南」 -->
<!-- Placeholders until first release: GUIDE_ZH (Chinese guide id), WORKSHOP_ID (item id); fill them in per release-first.md「首發」steps 4 and 5 -->
<!-- 標題：📖 Quests & Achievements Mod Guide: Quests, Achievements, Leaderboards & Admin Panel -->
<!-- 摘要：Illustrated guide to Minidoracat Quests & Achievements: daily and weekly quests, the server-wide quest and weekly server goal, streaks, newcomer quests, timed events, achievements and titles, leaderboards and seasons, My records, exchanging points for Survivor Coins and player settings, plus installation, sandbox options, the admin panel, season payouts, Economy integration, data and backups for hosts, and the API for other mod authors. -->
=== 🚀 Quick start
[b]繁體中文版：[/b][url=https://steamcommunity.com/sharedfiles/filedetails/?id=GUIDE_ZH]Minidoracat Quests & Achievements 完整說明[/url]

The mod on Steam Workshop:
https://steamcommunity.com/sharedfiles/filedetails/?id=WORKSHOP_ID
Daily and weekly quests, achievements, season leaderboards and titles; pair it with the Economy mod to exchange points for Survivor Coins.
[olist]
[*] [b]Open the window[/b]: click the trophy icon (Quests & Achievements) on the family toolbar.
[*] [b]Check today's quests[/b]: the Daily quests page lists today's 4 quests; they advance as you play.
[*] [b]Earn points[/b]: completing quests, unlocking achievements and keeping a streak all give points.
[*] [b]See your rank[/b]: the Leaderboards page shows Season and All-time ranks.
[*] [b]Exchange[/b]: on servers with the Economy mod, turn points into Survivor Coins on the My records page.
[/olist]
[h3]Requirements[/h3]
[list]
[*] [b]Required[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library[/url]
[*] [b]Optional[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3801482125]Minidoracat Economy[/url], to exchange points for Survivor Coins on multiplayer servers.
[/list]
[h3]Where it works[/h3]
[list]
[*] [b]Single player and multiplayer[/b]: all progress is counted by the server (the game itself in single player).
[*] [b]Exchange is multiplayer only[/b]: the Economy mod supports dedicated servers only.
[*] [b]Split screen[/b]: players 2-4 do not earn progress.
[*] [b]Adding it mid-save[/b]: zombie kills, days survived and skill levels are imported; see the FAQ.
[/list]
[h3]Other ways to open the window[/h3]
[list]
[*] [b]Hotkey[/b]: unbound by default. Set "Open / close Quests & Achievements" under "Minidoracat Quests & Achievements" in Options > Key Bindings.
[*] [b]Number on the toolbar icon[/b]: completions and unlocks you have not seen yet; it clears when you open the Daily quests or Achievements page.
[/list]
=== 🧰 Daily quests
{{img:01-daily-en.jpg}}
[h3]Today's 4 quests[/h3]
[list]
[*] [b]3 personal quests[/b]: drawn from 11 themes, never two on the same stat in one day.
[*] [b]1 server-wide quest[/b]: one a day with the same target for everyone; the page shows how many players finished it today.
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
[*] [b]Themes do not change points[/b]: every preferred theme pays the same; only rare quests pay a little more.
[/list]
[h3]Swaps and preferences[/h3]
[list]
[*] [b]Swap quest[/b]: swap 1 personal quest per day; the server-wide quest cannot be swapped.
[*] [b]Preferred themes[/b]: pick up to 3 themes under Settings; each day 2 quests come from your themes and 1 from all themes.
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
[*] [b]Themes[/b]: one slot each from Combat, Production and Outdoors; preferences are not used.
[/list]
[h3]This week's server goal[/h3]
[list]
[*] [b]What it is[/b]: the whole server works toward one total, rotating weekly: kills, crafting, distance driven, fishing, harvesting.
[*] [b]Target[/b]: 1.1 times last week's server total, kept between a minimum and maximum per stat; the first week uses the minimum.
[*] [b]Reward[/b]: when the goal is reached, everyone whose contribution this week meets the minimum gets 50 points.
[*] [b]Late is fine[/b]: if you reach the minimum contribution after the goal is reached, you are paid when you do.
[*] [b]Your contribution[/b]: the page shows what you contributed this week and the minimum.
[/list]
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
[tr][td]Hidden[/td][td]16 achievements, only a hint until unlocked[/td][/tr]
[tr][td]Professions[/td][td]None built in; other mods add them through the API[/td][/tr]
[/table]
[h3]Tiers and points[/h3]
[table]
[tr][th]Tier[/th][th]Default points[/th][/tr]
[tr][td]Bronze I[/td][td]10[/td][/tr]
[tr][td]Silver II[/td][td]20[/td][/tr]
[tr][td]Gold III[/td][td]30[/td][/tr]
[tr][td]Platinum IV[/td][td]50 + title[/td][/tr]
[tr][td]Hidden achievement (1 tier)[/td][td]30, some give a title[/td][/tr]
[/table]
[list]
[*] [b]About 110 in total[/b]: 107 built in; a server may add custom achievements or achievements from other mods.
[*] [b]Next tier[/b]: every achievement shows the next tier's threshold and points.
[*] [b]More tiers[/b]: admins can add up to 10 tiers; tier 5 and up are called "Legend".
[*] [b]One-life achievements[/b]: those marked "One life" use this life's stats and start over after death; the rest use your all-time totals across characters.
[*] [b]Raised thresholds[/b]: unlocked achievements are never taken back.
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
[*] [b]Use one[/b]: pick one on the My records page to show next to your name on leaderboards (one at a time, or none). A server-wide notice names the title that unlock earned.
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
[*] [b]Anonymous[/b]: turn it on under Settings; you are still ranked, others see "Anonymous survivor", admins see "Name (anonymous)".
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
[tr][td]Quests, achievements, streaks, server goal, newcomer quests[/td][td]+[/td][td]+[/td][td]+[/td][/tr]
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
[*] [b]Pick a title[/b]: the title menu on the points card; choose "No title" to remove it.
[/list]
=== 🧰 Exchanging for Survivor Coins
{{img:06-exchange-en.jpg}}
The server needs Minidoracat Economy (multiplayer only). On the My records page, press "Exchange for survivor coins...".
[list]
[*] [b]Rate[/b]: 1 point = 1 Survivor Coin by default, set by the host.
[*] [b]Limits[/b]: by default up to 100 points per player per day, at least 10 per exchange; "All available" fills in the smaller of your balance and today's remaining limit.
[*] [b]Balance only[/b]: ranks use points earned, so exchanging never lowers your rank.
[*] [b]Queued[/b]: when the Economy mod's daily allowance for this mod is used up, your points are held and paid automatically later (retried every hour and right after the Economy mod's daily reset).
[*] [b]Refunded[/b]: if your economy account cannot receive coins, the points come back and you are asked to contact an admin.
[*] [b]No reply[/b]: press "Ask again" to check the result; asking again never exchanges twice.
[*] [b]Imported achievements[/b]: points from achievements imported mid-save never reach your balance and cannot be exchanged.
[/list]
=== 🧰 Settings
{{img:07-settings-en.jpg}}
[h3]Settings in the window[/h3]
[list]
[*] [b]Quest preferences[/b]: pick up to 3 themes and press Apply; rules under "Daily quests".
[*] [b]Appear anonymous on leaderboards[/b]: you are still ranked, others see "Anonymous survivor", and server-wide notices do not name you; admins can still see who you are. Only applies to this mod's leaderboards.
[/list]
[h3]Mod options (Options > MODS > Quests & Achievements)[/h3]
[list]
[*] [b]Show the toolbar entry[/b]: when hidden, the hotkey still opens the window.
[*] [b]Show server-wide unlock notices[/b]: when off, other players' unlocks are not shown.
[/list]
=== ⚙️ Installation and load order
[list]
[*] [b]Multiplayer server[/b]: in Mods= put MinidoracatQuestFor42 after MinidoracatUIFor42, and add both Workshop IDs to WorkshopItems=; add the Economy mod for exchanges (its position does not matter to this mod).
[*] [b]Same version[/b]: the server and every player need the same version.
[*] [b]Single player[/b]: subscribe and enable it in the mod list; in single player you are always an admin and see the Admin page.
[*] [b]Mid-save[/b]: fine; on an existing save each account's old progress is imported the first time it appears, see the FAQ.
[/list]
=== ⚙️ Sandbox options and defaults
The sandbox page "Minidoracat Quests & Achievements" has three options; everything else is set in the in-game admin panel.
[table]
[tr][th]Option[/th][th]Default[/th][th]Notes[/th][/tr]
[tr][td]Time zone (UTC offset, hours)[/td][td]8[/td][td]-12 to 14; time zone for the daily reset and times on screen[/td][/tr]
[tr][td]Daily reset hour[/td][td]0[/td][td]0-23; local hour when daily quests reset; weekly quests reset at this hour on Monday[/td][/tr]
[tr][td]Admin roles[/td][td]admin[/td][td]Role names that can open the admin panel, separated by commas or semicolons, case-sensitive; use English names, as non-English characters are corrupted on every server restart[/td][/tr]
[/table]
[list]
[*] [b]With the Economy mod[/b]: when the Economy mod provides its day-change API, the daily and weekly reset follow the Economy mod's daily reward reset and the first two options no longer decide it.
[/list]
[h3]Main admin panel defaults[/h3]
[table]
[tr][th]Setting[/th][th]Default[/th][/tr]
[tr][td]Daily quest points / rare / server-wide[/td][td]15 / 20 / 20[/td][/tr]
[tr][td]Swaps per day[/td][td]1[/td][/tr]
[tr][td]Weekly quests[/td][td]3, 60 points each[/td][/tr]
[tr][td]Server goal[/td][td]On, 50 points when reached, target ×1.1 of last week[/td][/tr]
[tr][td]Streaks[/td][td]3 quests count as a day, 1 grace day per week[/td][/tr]
[tr][td]Newcomer quests[/td][td]On, 100 points + title[/td][/tr]
[tr][td]Achievement points[/td][td]10 / 20 / 30 / 50 per tier, hidden 30[/td][/tr]
[tr][td]Difficulty[/td][td]Normal (Easy ×0.6, Hard ×1.6; only thresholds and quest targets)[/td][/tr]
[tr][td]Season length[/td][td]28 days (7-180)[/td][/tr]
[tr][td]Exchange[/td][td]On, 1 point = 1 Survivor Coin, 100 points per player per day, at least 10[/td][/tr]
[tr][td]Server-wide notices[/td][td]On, from tier 3, 1 per player per minute[/td][/tr]
[tr][td]Not ranked[/td][td]Offline for 180 days[/td][/tr]
[/table]
=== ⚙️ Admin panel
{{img:08-admin-thresholds-en.jpg}}
Open "Admin" on the left of the window; only roles listed in the "Admin roles" sandbox option see it, and the server checks every action again.
[h3]How changes work[/h3]
[list]
[*] [b]Draft first[/b]: edits go into pending changes; press "Preview changes" to see old and new values, then apply.
[*] [b]Unlocks are kept[/b]: higher thresholds only affect what comes next.
[*] [b]Times[/b]: shown in the sandbox time zone.
[/list]
[h3]Achievements[/h3]
[list]
[*] [b]Quick difficulty[/b]: Easy, Normal, Hard or a custom multiplier; changes thresholds and quest targets only, not points, with an estimate before you apply.
[*] [b]Batch edits[/b]: tick several achievements to multiply thresholds or points, or add a tier.
[*] [b]Single edit[/b]: threshold, points and title for each tier, up to 10 tiers.
[*] [b]Custom achievements[/b]: add one from an existing stat (name, category, thresholds, points), or delete it.
[/list]
[h3]Quests[/h3]
[list]
[*] [b]Daily and weekly pools[/b]: on/off, target range and points per template.
[*] [b]Daily settings[/b]: points for daily, rare and server-wide quests, swaps per day.
[*] [b]Server goal[/b]: on/off, reward, growth over last week, rotation, minimum, maximum and minimum contribution per stat.
[*] [b]Streak rewards[/b]: quests needed per day, grace days per week, milestones.
[*] [b]Newcomer quests and server-wide notices[/b]: on/off, reward, starting tier, notices per player per minute.
[/list]
[h3]Exchange & events[/h3]
{{img:11-admin-exchange-en.jpg}}
[list]
[*] [b]Exchange settings[/b]: on/off, rate, per-player daily limit, minimum per exchange.
[*] [b]Today[/b]: server total exchanged today, estimated daily exchange, and the Economy mod's daily limit for this mod with today's usage.
[*] [b]Warnings[/b]: shown at the top when the Economy limit is 0, cannot be read, this mod is disabled in the Economy mod, or the estimate exceeds the limit; see "Economy integration".
[*] [b]Timed events[/b]: name, quest theme (or all quests), multiplier (1-5), start and end date (inclusive); up to 3 at a time, removable.
[/list]
[h3]Players[/h3]
[list]
[*] [b]Anomalies[/b]: today or the last 7 days, records of a stat going over its per-minute limit.
[*] [b]Look up an account[/b]: three point numbers, achievements, anomalies this season, whether it is removed from the leaderboards.
[*] [b]Revoke achievements[/b]: down to a chosen tier, or all of it.
[*] [b]Remove from or return to the leaderboards[/b]: data is kept. Revoking and removing require a reason and record who did it.
[/list]
[h3]Balance[/h3]
[list]
[*] [b]Completion rate[/b]: for each quest template over the last 7 days, with median completion time.
[*] [b]Suggestions[/b]: below 30% is marked "Too hard", above 90% "Too easy", with a suggested target range you can add to the pending changes in one click.
[/list]
[h3]Towns[/h3]
[list]
[*] [b]12 built in[/b]: Muldraugh, West Point, Riverside, Rosewood, Louisville, Brandenburg, Ekron, Irvington, Echo Creek, Fallas Lake, March Ridge, Valley Station; each can be disabled.
[*] [b]Custom towns[/b]: a name and two corners; "Use my position" fills in coordinates.
[*] [b]Used for[/b]: town achievements, the Towns visited board and the newcomer step "leave your starting town".
[/list]
[h3]History[/h3]
[list]
[*] [b]Undo[/b]: the last 20 changes; undo writes the old values back and counts as a change itself.
[*] [b]Export[/b]: writes the current overrides to a JSON file on the server.
[*] [b]Import[/b]: rename the file to import.json, put it in the same folder and press "Import..."; you see a preview before applying.
[/list]
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
[*] [b]Exclude[/b]: write a reason to exclude someone from rewards.
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
[*] [b]The limit you must set[/b]: the Economy mod gives every integration source a daily mint limit of 0 by default. Open the Economy admin's "Integration sources" page and set a daily limit for Quests & Achievements; until you do, every exchange is queued and nothing is paid.
[*] [b]Choosing the limit[/b]: roughly players who exchange per day × per-player daily limit × rate; the estimate on this mod's "Exchange & events" admin page helps.
[*] [b]Queue and retries[/b]: when the allowance is used up, rate-limited, the Economy mod is not ready or does not answer, the exchange is queued and retried every hour, plus right after the Economy mod's daily reset.
[*] [b]Refunds[/b]: any other refusal (for example a player's economy account cannot receive coins) refunds the points. One exchange is never paid twice.
[*] [b]Day change[/b]: when the Economy mod provides its day-change API (versions after 42.21.0-0.20.1), the daily and weekly reset happen at the same moment as the Economy mod's daily reward; reading the limit and today's usage needs the same versions. Older Economy versions still exchange, but the admin page cannot show the limit.
[/list]
=== ⚙️ Data and backups
[table]
[tr][th]Contents[/th][th]Location[/th][/tr]
[tr][td]Setting overrides, seasons, server-wide quest and server goal, timed events, audit (last 500)[/td][td]Global ModData shared table MinidoracatQuest in the world save[/td][/tr]
[tr][td]Each account's stats, quests, points, achievements, titles, preferences, exchange queue[/td][td]Global ModData account tables MinidoracatQuest_A00-A15 (16 tables)[/td][/tr]
[tr][td]Account to Steam account bindings[/td][td]Zomboid/Lua/MinidoracatQuest/<server name>/identity.txt[/td][/tr]
[tr][td]Daily event log (one line per event)[/td][td]Same folder, events-YYYYMMDD.json, one per day[/td][/tr]
[tr][td]Exported / imported settings[/td][td]Same folder, export-<date-time>.json / import.json[/td][/tr]
[tr][td]Audit log[/td][td]*_MinidoracatQuest.txt in Zomboid/Logs[/td][/tr]
[/table]
[list]
[*] [b]17 Global ModData tables[/b]: backed up and rolled back with the world save; they hold no Steam accounts or private data.
[*] [b]Event logs[/b]: a new uncompressed file every day; this mod only writes them, never reads them. Lua cannot delete files, so archive or delete old ones yourself.
[*] [b]Backups[/b]: back up the world save together with Lua/MinidoracatQuest/<server name>/. Without identity.txt, names on a Steam server are bound again only when each player comes back online.
[/list]
=== ⚙️ For mod authors
Other mods can add stats, achievements, daily quests and Professions leaderboards on the server through MinidoracatQuest.v1. For a full example and field limits, see "給其他 MOD 的 API" (API for other mods) in the GitHub README:
https://github.com/Minidoracat/MinidoracatQuestFor42#給其他-mod-的-api
[list]
[*] [b]Detect[/b]: use it only when MinidoracatQuest.v1 exists and API_MAJOR == 1; skip it when the mod is not installed.
[*] [b]Register[/b]: call registerPack in OnServerStarted (multiplayer) or OnGameStart (single player); register again on every server start.
[*] [b]Report progress[/b]: on the server with pack.add(player, statId, n); clients have no way to report progress.
[*] [b]Limits[/b]: per mod 32 stats, 64 achievements and 32 quests; 50 pack.add calls per tick; n up to 1000.
[*] [b]Translations[/b]: names use translation keys your mod ships, so clients need your mod too.
[*] [b]Admins[/b]: can tune or disable your achievements and quests in the admin panel like any other.
[/list]
=== ⚠️ Known limitations
[list]
[*] [b]Anonymity only applies on this mod's leaderboard screens[/b]: the game lets clients read the save's shared data, so a modified client can see who is anonymous and every account's points.
[*] [b]The character who finishes an action comes from the client[/b]: which character crafting, building, repairs or fishing are credited to follows the character the client sent in the vanilla action; the server still verifies identity and applies per-minute limits.
[*] [b]Distance is a straight line per minute[/b]: detours and back-and-forth count less; only the driver earns driving distance, not passengers; a jump too large for one minute (teleport) is ignored.
[*] [b]Per-minute limits[/b]: each stat has a per-minute limit; anything above it does not count and is logged as an anomaly for admins.
[*] [b]Exchange is multiplayer only[/b]: the Economy mod supports dedicated servers only.
[*] [b]Split screen[/b]: players 2-4 do not earn progress.
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
[*] Each account's zombie kills, days survived and skill levels are imported the first time it appears, and matching achievements unlock quietly.
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
[*] Other players do not see your name on this mod's leaderboards or in server-wide notices; admins do. A modified client can also read the save data; see "Known limitations".
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
