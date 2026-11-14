<!-- 指南網址：https://steamcommunity.com/sharedfiles/filedetails/?id=3827763966 -->
<!-- Steam guide source (English): the full reference for this mod; the Workshop description only summarizes. Format and sync: pz-family-docs/release.md「完整說明：Steam 指南」 -->
<!-- 標題：📖 Quests & Achievements Mod Guide: Quests, Achievements, Leaderboards & Admin Panel -->
<!-- 摘要：Illustrated guide to Minidoracat Quests & Achievements: daily and weekly quests, the server-wide quest and weekly server goal, streaks, newcomer quests, timed events, hordes, sponsored hordes and the server-wide donation, squad contracts, achievements and titles, leaderboards and seasons, My records, uses for points (quest swaps, streak shields, point titles, title colours, sponsored hordes, the server-wide donation, squad contracts, Survivor Coins) and player settings, plus installation, sandbox options, the admin panel, season payouts, Economy integration, data and backups for hosts, and the API for other mod authors. -->
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
[*] [b]Spend points[/b]: the Points page shows what points can do: extra quest swaps, a streak shield, point titles, title colours, sponsored hordes, the server-wide donation, squad contracts; on servers with the Economy mod, Survivor Coins too.
[/olist]
[h3]Requirements[/h3]
[list]
[*] [b]Required[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701]Minidoracat UI Library[/url]
[*] [b]Optional[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3801482125]Minidoracat Economy[/url], to exchange points for Survivor Coins on multiplayer servers.
[*] [b]Optional[/b]: [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359]Minidoracat MiniMap[/url], to show the horde area and your own corpse from a horde on the minimap.
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
[*] [b]Hotkey[/b]: unbound by default. Set "Open / close Quests & Achievements" under "Minidoracat Quests & Achievements" in Options > Key Bindings; "Collapse / expand the tracker panel" in the same group folds the tracker panel.
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
[*] [b]Swap quest[/b]: swap 1 personal quest per day for free; a quest with progress asks first (the progress cannot be restored); the server-wide quest cannot be swapped.
[*] [b]Swap again for points[/b]: once the free swap is used, you can swap again for points (50 points each by default, up to 3 more a day). The button shows the price and asks before it spends; when you are short, the button's place says how many points you still need.
[*] [b]XP quests[/b]: "Earn N XP" quests only go to a skill with a profession or trait XP bonus that is below level 10 (the game gives no XP at 10, and a quarter without a bonus); otherwise another quest of the same theme comes, also when you swap.
[*] [b]Preferred themes[/b]: pick up to 3 themes under Settings; each day 2 quests come from your themes and 1 from all themes. When a preferred theme has no quest left for the day, that slot draws from your other preferred themes.
[*] [b]No preferences[/b]: the three slots draw one each from Combat, Production (Building, Crafting, Cooking, Tailoring, Mechanics & Electrical) and Outdoors (Farming, Animal Care, Fishing & Trapping, Foraging, Exploration).
[*] [b]When it applies[/b]: change preferences as often as you like; if today's quests already exist, the change applies from the next reset.
[/list]
[h3]Streaks[/h3]
[list]
[*] [b]A day counts[/b]: when you finish 3 of the 4 quests (the server-wide quest counts).
[*] [b]Grace day[/b]: you may miss 1 day per week and it still counts toward the streak; grace resets on Monday.
[*] [b]Break[/b]: a missed day after the grace is used, with no streak shield held, resets the streak at the next reset.
[*] [b]Milestones[/b]: each paid once per streak; after a reset you can earn them again.
[*] [b]Streak shield[/b]: in the streak area, buy 1 shield day for points (200 by default) in advance. When you miss a day and this week's grace day is already used, the shield is used up at the reset and the day still counts toward your streak (a lock on that day's dot).
[*] [b]Shield limits[/b]: you can hold 1 day at most and buy another once it is used; at most 1 a week. At most 2 days are covered in a row (1 grace day plus 1 shield day), so missing 3 days still resets the streak, and an unused shield is kept. A day already missed cannot be covered afterwards.
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
[*] [b]5 steps, any order[/b]: kill 5 zombies, craft 1 item, finish reading 1 book, leave your starting town with a weapon in hand, sleep indoors once. On a multiplayer server that does not allow sleeping (the vanilla multiplayer default) there is no sleep step, so 4 steps finish them.
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
[h3]Server-wide donation[/h3]
[list]
[*] [b]Donate here[/b]: when the server has the donation on, a "Server-wide donation" block sits under the server goal, where everyone pools points for an extra server-wide horde; see "Sponsored hordes and server-wide donation".
[/list]
=== 🧰 Hordes
{{img:13-horde-en.jpg}}
Once an admin sets up spots, the server can start a horde during its time windows: zombies come at a spot in waves, and every wave cleared in time pays points for its kills.
[h3]How to take part[/h3]
[olist]
[*] [b]The warning[/b]: before it starts, everyone gets a "Horde warning" with the place, how many minutes until the start, the number of waves and the kinds that may appear (for example Regular zombies and Sprinters), never the count. When an admin starts one with a warning of 0, the message says it starts now.
[*] [b]Reminder[/b]: when the warning is longer than 2 minutes, players within 30 tiles of the spot get one more notice 2 minutes before the start. If you do not want to take part, leave then: the first wave comes when someone is within 30 tiles.
[*] [b]Get there[/b]: once it has started, a wave comes as soon as someone is within 30 tiles of the spot, and the wave's timer starts. Each wave waits only so long for players (set per time window); if nobody comes, the horde fails.
[*] [b]How big a wave is[/b]: it depends on how many living players are within 30 tiles when it starts: the admin sets a base count and how many % of it each extra player adds.
[*] [b]Where it comes from[/b]: the zombies appear 30 to 40 tiles from the spot, from up to 8 directions and at least 25 tiles from every player, and a sound at the spot draws them in. In very heavy rain (or rain with thick fog), or with sandbox zombie hearing set to Poor or either Random option, the sound does not carry that far and the wave appears right at the spot.
[*] [b]Not all at once[/b]: only so many horde zombies are on the field at a time; more come in as they die.
[*] [b]Clear it[/b]: kill every zombie of the wave within its time limit while a player is within 50 tiles of the spot, so chasing the last ones out to the edges is fine. Zombies killed by others or burnt count as cleared too. After a short rest the next wave comes, again once someone is within 30 tiles; clearing the last wave clears the horde.
[*] [b]Get points[/b]: only players with a kill get points; see "Reward" below.
[/olist]
[h3]Where to see it[/h3]
[list]
[*] [b]Tracker panel[/b]: a horde row on top shows the place, "Wave W/N" when there is more than one, the countdown ("Starts in", "Waiting", "left" or "Next wave in") and "Cleared N/M"; while the horde is in progress it reads "N joined · N/M cleared", and one kill counts as joining. Only a horde in progress is red; before the start, while waiting for players and during a rest it is orange. It does not use one of the 5 slots and shows even when you track nothing. "Show the tracker panel" in the mod options must be on.
[*] [b]Hide this horde[/b]: the ✕ at the right end of the horde row's first line hides this horde: the row goes away and this horde's server-wide notices (warning, waves, cleared, failed, cancelled, deaths, MVP) stop; the reminder 2 minutes before the start, your "Horde reward" and the results still come. The next horde shows again, and so does this one after you log in again.
[*] [b]Daily quests page[/b]: a horde banner under the timed events shows the current state; for 10 minutes after the end it shows the result, the waves cleared, your kills and the points you got. "Hide from tracker" / "Show in tracker" on the banner hides this horde or brings it back, also with a keyboard or controller.
[*] [b]Map button[/b]: before the start, while waiting for players, in progress and during a rest, the tracker row and the banner have a "Map" button that opens the world map on the spot. It is hidden when the server turns the world map off.
[*] [b]Minimap[/b]: with Minidoracat MiniMap installed, the minimap marks the area around the spot and names the state (such as "Horde in progress: …").
[*] [b]Notices[/b]: the warning, each wave appearing, the rest between waves, cleared, failed and cancelled go to everyone; points you get come with a "Horde reward" notice and your kills in the cleared waves. Deaths in the horde and the horde MVP go to everyone too; see "Horde results and notices".
[/list]
[h3]Hordes page[/h3]
{{img:15-hordes-en.jpg}}
Once the server has automatic or sponsored hordes on or has had a horde, a "Hordes" page appears on the left of the window; sponsoring a horde happens here too.
[list]
[*] [b]Now[/b]: the same banner as on the daily quests page; with no horde it says so.
[*] [b]My hordes[/b]: your totals for hordes joined, hordes cleared, horde kills and hordes where you were the top killer.
[*] [b]Recent hordes[/b]: the last 10 hordes on the server with time, place, result (waves cleared, or the wave it failed in), your kills and your points; older ones only count in your totals. Hordes where someone got a kill have a "View results" button that anyone can press (see "Horde results and notices").
[/list]
[h3]Reward[/h3]
[list]
[*] [b]Points per kill[/b]: each kill earns that kind's points (by default Regular zombies 5, Sprinters 8; a kind without its own points pays like a regular zombie).
[*] [b]Only cleared waves pay[/b]: kills in a wave that fails earn nothing; the waves cleared before it still pay, whatever the result.
[*] [b]Cap[/b]: one horde pays at most a set total (500 by default; each preset can differ). When the kills add up to more, everyone's share shrinks in proportion.
[*] [b]Where it counts[/b]: season, all-time and balance, so it can be exchanged.
[*] [b]Horde achievements[/b]: the achievements page gets a "Hordes" category on the same servers as the Hordes page: hordes cleared, horde kills and top killer (cleared hordes with 2 or more players, ties count for all), five tiers each. The first horde you help clear also unlocks a hidden achievement and the title "Horde Hunter".
[*] [b]Kills still count[/b]: horde kills count for kill stats, quests and achievements as usual.
[/list]
[h3]Failing[/h3]
[list]
[*] [b]Time runs out[/b]: the zombies left in that wave are removed; the waves already cleared still pay.
[*] [b]Other reasons[/b]: nobody came within 30 tiles in time, an admin stopped it, or the wave could not appear at the spot.
[*] [b]Zombies that wander off[/b]: horde zombies that follow someone far away and get stored by the game become normal zombies; they no longer count for the horde, so there is no need to chase them.
[*] [b]A server restart is not a failure[/b]: the horde carries on from the last world save: in the wave that was cut off, the zombies that were left come back and kills from before the restart still count. No wave starts for 10 minutes after the start (admins can change this) so everyone can get back; the tracker shows "Resumes in 4:12". The zombies that were out become normal zombies and do not count.
[/list]
[h3]Horde corpses[/h3]
[list]
[*] [b]Removed on their own[/b]: at most 500 horde corpses are kept, the oldest go first; 10 minutes after a horde ends, the rest around the spot are removed with everything on them. Loot them before that.
[*] [b]Player corpses stay[/b]: only the corpses of zombies this mod spawned for a horde are removed; player corpses and other zombies' corpses are never removed.
[*] [b]Find your own corpse[/b]: die within 50 tiles of the spot between the first wave and the end of the horde, and your corpse gets a gold outline (seen through walls) and a light red tint. With Minidoracat MiniMap installed, the maps also show a "My corpse" marker. Only you see them. If the corpse reanimates, the marker stays at its last place, faded; once that zombie is killed, the marker moves to where it fell. The mark goes 24 hours (real time) after the death or once the corpse is gone, and cannot be turned off. Anyone can loot the corpse.
[/list]
[b]Admins[/b]: spots, time windows and presets (waves, kinds and the reward) are set up as described in "Horde settings".
=== 🧰 Horde results and notices
When a horde ends, the players at the spot get its results; deaths during a horde and the MVP of a cleared horde are announced to everyone.
[h3]Results[/h3]
[list]
[*] [b]Who gets them[/b]: players online, alive and within 50 tiles of the spot the moment the horde is cleared or fails. Everyone else presses "View results" on the Hordes page; the server keeps only the last 20 hordes, and an older one says "This horde is no longer kept (only the last 20)."
[*] [b]When they open[/b]: never in the middle of a fight. They open once no living zombie has been within 20 tiles of you for 3 seconds in a row; if the quest window or another Minidoracat window is open then, they wait until you close it. Until then the tracker panel shows a "Cleared · …" or "Failed · …" row with "Opens once no zombie is within 20 tiles", and its "Results" button opens them at once. If they cannot open for 10 minutes (zombies stay around or the window stays open), or you die meanwhile, they no longer open on their own.
[*] [b]Playing with a controller[/b]: no window opens on its own; a "Horde results" notice shows the result and place instead. For the details, press "View results" on the Hordes page.
[*] [b]What they show[/b]: the result and place, when it ended, the waves cleared and the minutes it took; three numbers, Joined, Kills and Points paid (with a note when the points cap was reached and the points were shared by kills); the MVP; who died and in which wave (up to 10 names, then "+N").
[*] [b]Ranking[/b]: rank, player, kills and points; your row is framed and marked "(you)", players who died are marked "Died", and with no kills you see "You had no kills in this horde." Up to 100 rows; if you rank lower, your row is added at the end. Scroll down for the rest of a long list; on a short screen fewer rows show, so the window stays on screen. Anonymous players show as "Anonymous survivor"; admins see "name (anonymous)".
[*] [b]Close[/b]: Esc or "Close"; if you opened it with a controller ("View results"), press B. Only one is open at a time.
[/list]
[h3]Death and MVP notices[/h3]
[list]
[*] [b]Death notices[/b]: from the first wave until the horde ends, when anyone dies within 50 tiles of the spot, everyone gets a "… died in the horde" notice with the place and the wave; deaths within 2 seconds share one notice, "N players died in the horde". Only a player's first death in a horde counts.
[*] [b]MVP notice[/b]: when a horde with 2 or more players is cleared, everyone gets "Horde MVP: …" with the kills; ties count for all.
[*] [b]Anonymous players[/b]: show as "Anonymous survivor" in death and MVP notices, for admins too.
[*] [b]A hidden horde[/b]: if you hid the horde from the tracker, its death and MVP notices stay quiet too; the results still come.
[/list]
=== 🧰 Sponsored hordes and server-wide donation
Players can spend points on extra hordes: a few of them pool points for a "sponsored horde", or the whole server donates toward a "server-wide donation" horde. Both need an admin to turn them on and a horde spot on the server; they play, notify and report results like any horde (see "Hordes").
[h3]Sponsor a horde[/h3]
{{img:19-pledge-tiers-en.jpg}}
When an admin turns on "Players can sponsor a horde" under "Admin > Hordes", the Hordes page gets a "Sponsor a horde" block.
[olist]
[*] [b]Pick a difficulty and start[/b]: anyone presses "Start a fund...", picks a difficulty and puts in some points (at least 50 by default; when less than that is left, you can give just what is left).
[*] [b]Chip in[/b]: others press "Sponsor..." to add theirs; the fund keeps the difficulty it was started with.
[*] [b]Full means a horde[/b]: once that difficulty's price is pooled, an extra horde starts at a random spot 15 minutes later, and anyone can fight it; the warning names the sponsors (anonymous ones are only counted). If another horde is on, it waits for that one to end.
[/olist]
[table]
[tr][th]Difficulty[/th][th]Price[/th][th]Zombies as tough[/th][th]Points each (Regular / Sprinter)[/th][th]Per wave[/th][th]Pays at most[/th][/tr]
[tr][td]Normal[/td][td]600 points[/td][td]1×[/td][td]5 / 8[/td][td]15 min[/td][td]300 points[/td][/tr]
[tr][td]Hard[/td][td]1,200 points[/td][td]2×[/td][td]10 / 16[/td][td]20 min[/td][td]600 points[/td][/tr]
[tr][td]Nightmare[/td][td]2,500 points[/td][td]3×[/td][td]15 / 24[/td][td]25 min[/td][td]1,250 points[/td][/tr]
[/table]
[list]
[*] [b]These are the defaults[/b]: all difficulties have the same waves and zombie counts; a harder one has tougher zombies, more points per kill and a higher total it can pay. The host can set 1 to 4 tiers and the page shows this server's; with one tier there is no difficulty to pick.
[*] [b]The terms are fixed when the fund opens[/b]: the horde plays the terms the screen showed when the fund opened; an admin changing the settings later does not affect it.
[*] [b]10% back on a clear[/b]: when every wave is cleared, each sponsor gets 10% of their share back, even without being there; Points history says "Sponsored horde cleared: part of your share back". Nothing comes back if it is not cleared.
[*] [b]Nightmare's own achievement[/b]: the top difficulty is marked "Own achievement"; clearing it with a kill of your own counts for the "Nightmare Conqueror" achievement.
[*] [b]Not filled: full refund[/b]: a fund has a time limit (30 minutes by default); if it is not full by then, everyone gets all their points back, offline players too.
[*] [b]Could not start: refund too[/b]: if the horde cannot happen after the fund is full (no spot, cancelled by an admin, nobody came), all points come back as well; once the zombies appear there is no refund.
[*] [b]Points always go down[/b]: the horde pays at most half of the pooled points, shared by kills; with the 10% back on a clear, still less comes back than went in. Kills, joining and clearing still count for horde stats and achievements, plus a "Hordes sponsored" stat.
[*] [b]How many[/b]: 1 a day at most, not counted with automatic hordes.
[*] [b]Server restart[/b]: an open fund is kept; one that ran out while the server was down is refunded at start.
[/list]
[h3]Server-wide donation[/h3]
{{img:20-donate-en.jpg}}
Once an admin turns the donation on (off by default), the Weekly quests page gets a "Server-wide donation" block: everyone donates points, and a full round brings an extra server-wide horde.
[list]
[*] [b]Donate[/b]: press "Donate...", at least 10 points each time; the block shows the round's total and what you gave.
[*] [b]Full means a horde[/b]: at 10,000 points an extra horde is set for Saturday 21:00 (sandbox time zone), at least 24 hours after the round fills, otherwise the Saturday after; everyone is told when it fills.
[*] [b]That horde[/b]: a random spot, a warning 30 minutes before, anyone can fight it. Zombies are 3× as tough and pay 3× the points (Regular 15, Sprinter 24); it pays 1,500 points at most, always less than the target.
[*] [b]No refunds[/b]: a round not full stays and keeps filling; anything over the target counts toward the next round.
[*] [b]Moved if it does not happen[/b]: if that horde ends before any zombie comes (cancelled, nobody came), it moves to the next Saturday and everyone is told. Once zombies came, it is not moved.
[*] [b]Achievement[/b]: the points you donate count for the "Open Handed" achievement.
[*] [b]These are the defaults[/b]: the host can change the target, weekday, time and toughness; the page shows this server's settings.
[/list]
=== 🧰 Squad contracts
{{img:16-contracts-en.jpg}}
A few players each stake points as a squad and meet a kill target together within a time limit. The "Squad contracts" page on the left of the window lists the contracts you can start, the squads gathering and your recent contracts. Multiplayer only: single player has no such page.
[h3]Three contracts[/h3]
[table]
[tr][th]Contract[/th][th]Target[/th][th]Time limit[/th][th]Stake[/th][/tr]
[tr][td]Hunt[/td][td]Kill 150 × players[/td][td]60 min[/td][td]100 points[/td][/tr]
[tr][td]Melee hunt[/td][td]Melee-kill 100 × players[/td][td]60 min[/td][td]150 points[/td][/tr]
[tr][td]Long haul[/td][td]Kill 400 × players[/td][td]120 min[/td][td]250 points[/td][/tr]
[/table]
[list]
[*] [b]These are the defaults[/b]: the host can change targets, time limits and stakes or turn a contract off; the page shows this server's settings.
[*] [b]The target grows with the squad[/b]: it is one player's share times the players at the start, so more players do not make it easier.
[/list]
[h3]Starting and joining[/h3]
[olist]
[*] [b]Start[/b]: press "Start..." on a contract; the confirmation shows the stake, what comes back and the rules, and "Start and stake N points" takes the stake and makes you the leader.
[*] [b]Gather[/b]: the squad shows under "Squads gathering" for others for 10 minutes, 2 to 6 players a squad. Others press "Join..." and stake the same points.
[*] [b]Go[/b]: the clock starts when 6 players are in, or when the leader presses "Start now" (2 players at least). When the 10 minutes run out with 2 or more players it starts too; with fewer the squad breaks up and everyone gets the stake back in full.
[*] [b]Play together[/b]: the target is met when the squad's kills add up to it in time.
[/olist]
[list]
[*] [b]No leaving once it starts[/b]: you can only leave while the squad is gathering.
[*] [b]Leave while gathering[/b]: a member presses "Leave and get N points back" for the whole stake.
[*] [b]Disband[/b]: the leader presses "Disband squad" (a leader leaving also disbands it); every member gets their stake back in full.
[*] [b]Uses one for the day[/b]: leaving, or disbanding as the leader, uses one of your contracts for the day, and the game asks first; members of a disbanded squad and squads that break up for lack of players do not.
[*] [b]How many[/b]: 3 contracts per player per day, counted when one starts, with the same day change as daily quests; one contract at a time. At most 10 contracts gather or run on the server at once.
[/list]
[h3]Results[/h3]
[table]
[tr][th]Result[/th][th]What comes back[/th][/tr]
[tr][td]Met, you pulled your weight[/td][td]Half the stake back, plus 30% of the stake as a points bonus[/td][/tr]
[tr][td]Met, you did not[/td][td]Half the stake back only[/td][/tr]
[tr][td]Not met[/td][td]The stake is lost[/td][/tr]
[/table]
[list]
[*] [b]Pulling your weight[/b]: kills of your own of at least 30% of one player's share: 45 for Hunt, 30 for Melee hunt, 120 for Long haul.
[*] [b]Example[/b]: a met Hunt with a 100 stake gives 50 back plus a 30 bonus, 80 in all, to those who pulled their weight, and 50 to the rest.
[*] [b]The bonus counts as earned points[/b]: season, all-time and balance, so it counts for ranks; the stake that comes back only returns to your balance. A met contract where you pulled your weight also counts for the "Contractor" achievement.
[*] [b]Notices and history[/b]: when it ends every member gets a notice with the result and what came back; "Recent contracts" lists your last 10.
[/list]
[h3]Which kills count[/h3]
[list]
[*] [b]The same as daily quests[/b]: kills in a horde count too; Melee hunt counts melee kills only.
[*] [b]Running zombies over[/b]: they count for the driver, not for passengers.
[*] [b]Fire does not count[/b]: a zombie that burns to death has no attacker, so it counts for nobody.
[*] [b]Time up means stop[/b]: kills after the time limit do not count.
[/list]
[h3]Where to see it[/h3]
{{img:17-contract-active-en.jpg}}
[list]
[*] [b]Squad contracts page[/b]: while running it shows the time left, the squad's kills against the target and each member's kills.
[*] [b]Tracker panel[/b]: a running contract adds a row under the horde row with the contract, the time left and the squad's progress; it does not use one of the 5 slots.
[*] [b]Server restart[/b]: time while the server is down does not count, so no time is lost; the clock goes on as soon as the server is up.
[/list]
{{img:18-contract-tracker-en.jpg}}
=== 🧰 Achievements and titles
{{img:03-achievements-en.jpg}}
[h3]Categories[/h3]
[table]
[tr][th]Category[/th][th]Covers[/th][/tr]
[tr][td]Combat[/td][td]Total kills, melee, firearms, vehicles, each weapon type, at night, indoors, hunting[/td][/tr]
[tr][td]Survival[/td][td]Days survived in one life, total days survived, bandaging, medical care, sleeping indoors (listed where the server allows sleeping, or once unlocked), barricading, clearing corpses, washing[/td][/tr]
[tr][td]Skills[/td][td]All 35 skills that can level up, total skill level, total XP[/td][/tr]
[tr][td]Production & Building[/td][td]Crafting, building, cooking, tailoring, smithing, knapping, carving, vehicle repair, installing parts, connecting power, scrapping[/td][/tr]
[tr][td]Farming & Wilds[/td][td]Planting, harvesting, fishing, foraging, trapping, butchering, milking, shearing, collecting eggs from henhouses, chopping trees[/td][/tr]
[tr][td]Exploration[/td][td]Towns visited, walking, driving, reading, placing furniture[/td][/tr]
[tr][td]Quests[/td][td]Daily, weekly, longest streak, server goals, seasons joined, achievement tiers, squad contracts (multiplayer only)[/td][/tr]
[tr][td]Hordes[/td][td]Hordes cleared, horde kills, top killer, top-tier sponsored hordes cleared, points donated (listed only on servers that run hordes)[/td][/tr]
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
[*] [b]About 115 in total[/b]: 114 built in; a server may add custom achievements or achievements from other mods. Each category button shows unlocked/total.
[*] [b]Next tier[/b]: every achievement shows the next tier's threshold and points.
[*] [b]How the five tiers work[/b]: for counts, Legend V is 2.5 times Platinum IV; skill achievements are skill levels 2 / 4 / 6 / 8 / 10 (Fitness and Strength 6 to 10), so a skill title comes at level 8. Admins can add up to 10 tiers.
[*] [b]One-life achievements[/b]: those marked "One life" use this life's stats and start over after death; the rest use your all-time totals across characters.
[*] [b]Raised thresholds[/b]: unlocked achievements are never taken back. When thresholds are lowered or an update adds tiers, the tiers you already reached are added at your next login (points paid as usual, only you get the notice).
[/list]
[h3]Group play achievements[/h3]
[table]
[tr][th]Achievement[/th][th]For[/th][th]Five tiers[/th][th]Tier IV title[/th][/tr]
[tr][td]Contractor[/td][td]Squad contracts met with your share of the kills (multiplayer only)[/td][td]1 / 5 / 15 / 40 / 100[/td][td]Contract Veteran[/td][/tr]
[tr][td]Nightmare Conqueror[/td][td]Top-tier sponsored hordes cleared with a kill of your own[/td][td]1 / 3 / 10 / 25 / 50[/td][td]Nightmare Slayer[/td][/tr]
[tr][td]Open Handed[/td][td]Points given to the server-wide donation[/td][td]500 / 2,000 / 5,000 / 15,000 / 40,000[/td][td]Server Benefactor[/td][/tr]
[/table]
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
[*] [b]Earned from[/b]: top achievement tiers, hidden achievements, a 30-day streak, newcomer quests and season rewards, or bought with points (see "Points").
[*] [b]Use one[/b]: pick one on the My records page (titles bought with points can also be worn with "Wear" on the Points page); one at a time, or none. A server-wide notice names the title that unlock earned.
[*] [b]My titles[/b]: My records lists every title you have, how you got it and when, newest first; the one you use says "In use". Times are recorded from the version that added this list; titles you got before show "Early".
[*] [b]All titles for admins[/b]: the admin panel's read-only Titles tab lists every title and what earns it; titles of switched-off achievements show "(off)", changed text "(custom)", and hidden achievements add the hint players see. To change a title's text, press Edit on the Achievements tab.
[*] [b]Revoked or cleared[/b]: when an admin revokes achievement tiers, the titles those tiers gave go too (also after the text was changed, or the achievement switched off); a tier whose title is left empty in the achievement editor gives no title.
[*] [b]Where it shows[/b]: next to your name on leaderboards, one line above your name over your head, and after your name in chat (multiplayer only). Head and chat titles are gold, and you can spend points on another colour (see "Points").
[*] [b]When the head title is hidden[/b]: it follows the vanilla name rules: hidden when the server does not show names, when the player is invisible or disguised, or out of sight; when the server shows names only on mouse-over, the title also shows only when you point at that player. It steps aside while the player speaks or sits in a vehicle. Your own title follows the vanilla option Options > Multiplayer > Show your username.
[*] [b]Turn them off[/b]: Options > MODS > Quests & Achievements has separate ticks for head and chat titles; the host can also turn each off for everyone in the admin panel.
[/list]
=== 🧰 Tracker panel
{{img:12-tracker-en.jpg}}
[list]
[*] [b]Add[/b]: press "Track" on a daily or weekly quest card or an achievement card (press again to stop), up to 5; with 5 tracked, pressing "Track" on another card tells you to untrack one first.
[*] [b]What it shows[/b]: at the top left, next to the vanilla sidebar: quests show progress/target, achievements the next tier's target, a done quest gets a check mark and the points it paid.
[*] [b]Hordes[/b]: during a horde an extra row sits on top; it does not use one of the 5 slots, and the ✕ on its right hides this horde. After a horde ends, a "Results" row waits there until the results open (see "Hordes" and "Horde results and notices").
[*] [b]Squad contracts[/b]: a running contract adds a row under the horde row; it does not use one of the 5 slots (see "Squad contracts").
[*] [b]Move and fold[/b]: drag the panel to move it and the game remembers where; the arrow in its title row folds it to one line, and so can a hotkey (see "Opening and sizing the window").
[*] [b]Width[/b]: the panel is only as wide as its rows, and every progress bar ends at the same place; with a horde or results row it gets wider so place names are not cut. Point at its right edge for a handle: drag it left to set the widest the panel gets (the game remembers it), and the panel still shrinks when its rows are narrower; double-click the edge for the automatic width again. A panel in the right half of the screen keeps its right edge when its width changes.
[*] [b]Background[/b]: "Tracker panel background opacity (%)" in Options > MODS > Quests & Achievements goes from 50 to 100, 80 by default; under 80 the text gets a black shadow.
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
[tr][td]Balance[/td][td]Spending on uses for points: quest swaps, streak shields, point titles, title colours, sponsored hordes, the server-wide donation, squad contracts, Survivor Coins (see "Points")[/td][/tr]
[/table]
[table]
[tr][th]Source or use[/th][th]Season[/th][th]All-time[/th][th]Balance[/th][/tr]
[tr][td]Quests, achievements, streaks, server goal, newcomer quests, hordes, squad contract bonuses[/td][td]+[/td][td]+[/td][td]+[/td][/tr]
[tr][td]Achievements imported when the mod was added mid-save[/td][td]-[/td][td]+[/td][td]-[/td][/tr]
[tr][td]Season rewards[/td][td]-[/td][td]-[/td][td]+[/td][/tr]
[tr][td]Exchanging for Survivor Coins[/td][td]-[/td][td]-[/td][td]minus[/td][/tr]
[tr][td]Paid quest swaps, streak shields, point titles, title colours, sponsored hordes, the server-wide donation, squad contract stakes[/td][td]-[/td][td]-[/td][td]minus[/td][/tr]
[tr][td]Refunds of a horde fund not filled or a sponsored horde that could not start, the 10% back on a cleared sponsored horde, squad contract stakes coming back[/td][td]-[/td][td]-[/td][td]+[/td][/tr]
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
=== 🧰 Points
{{img:06-exchange-en.jpg}}
The Points page on the left of the window shows what your points can do. Servers without the Economy mod and single player have it too: it is listed while any use for points is on, the server can exchange, or you have points history.
[list]
[*] [b]Points balance[/b]: the points you can spend, with your points earned this season and all-time below.
[*] [b]Uses for points[/b]: the uses this server has on and their prices; the buttons take you to the Daily quests, Weekly quests, Hordes or Squad contracts page, or open the exchange window.
[*] [b]Point titles[/b]: titles you can only get with points; see below.
[*] [b]Title colour[/b]: spend points on another colour for your title; see below.
[*] [b]Points history[/b]: your last 10 spends, refunds and exchanges for Survivor Coins.
[/list]
[h3]Uses for points[/h3]
[table]
[tr][th]Use[/th][th]Default price[/th][th]How often[/th][th]Where[/th][/tr]
[tr][td]Swap quest[/td][td]50 points[/td][td]Up to 3 more a day after the free one[/td][td]The quest cards on Daily quests[/td][/tr]
[tr][td]Streak shield[/td][td]200 points[/td][td]Hold 1 day at most, buy 1 a week at most[/td][td]The streak area on Daily quests[/td][/tr]
[tr][td]Point titles[/td][td]1,000 / 2,000 / 3,500 / 5,000 points; this season's title 1,500 points[/td][td]Once per title[/td][td]The Points page[/td][/tr]
[tr][td]Title colour[/td][td]300 points[/td][td]Lasts 7 days[/td][td]The Points page[/td][/tr]
[tr][td]Sponsor a horde[/td][td]600 / 1,200 / 2,500 points (three difficulties) pooled by several players[/td][td]1 a day at most[/td][td]The Hordes page (once an admin turns it on)[/td][/tr]
[tr][td]Server-wide donation[/td][td]At least 10 points each; 10,000 from the server brings a horde[/td][td]No limit[/td][td]The Weekly quests page (once an admin turns it on)[/td][/tr]
[tr][td]Squad contracts[/td][td]A 100 / 150 / 250 point stake[/td][td]3 per player per day[/td][td]The Squad contracts page (multiplayer only)[/td][/tr]
[tr][td]Survivor Coins[/td][td]1 point = 1 Survivor Coin[/td][td]Up to 100 points per player per day[/td][td]The Points page (Economy mod, multiplayer only)[/td][/tr]
[/table]
[list]
[*] [b]Ranks stay[/b]: spent points only come off your points balance; points earned this season and all-time stay the same, so your leaderboard ranks do not change.
[*] [b]Asks first[/b]: before every spend the game shows your balance before and after, and spends only once you confirm.
[*] [b]The host decides[/b]: these are the defaults; the host can turn any use off and change prices and counts, and the page shows this server's settings.
[*] [b]Swaps and shields[/b]: see "Swaps and preferences" and "Streaks" under "Daily quests".
[*] [b]Sponsored hordes, the donation and squad contracts[/b]: see "Sponsored hordes and server-wide donation" and "Squad contracts".
[/list]
[h3]Point titles[/h3]
[list]
[*] [b]Which ones[/b]: four fixed titles (1,000 / 2,000 / 3,500 / 5,000 points by default), plus one title each season (1,500 points by default) that can only be bought during that season.
[*] [b]No refunds[/b]: buying asks first; the points are not refunded once you have the title.
[*] [b]Wearing it[/b]: a bought title is not put on for you; press "Wear" on the same page or pick it on My records. In My titles its condition reads "A title bought with points".
[/list]
[h3]Title colour[/h3]
{{img:21-title-color-en.jpg}}
[list]
[*] [b]Change the colour[/b]: for 300 points your title over your head and in chat turns from gold to Blue, Green, Purple, Coral or White for 7 days.
[*] [b]Preview[/b]: the top of the block previews the colour on the title you wear; with no title it says "Choose a title first".
[*] [b]Ending[/b]: after 7 days it goes back to gold by itself. With less than a day left, you get one reminder when you log in.
[*] [b]Changing again[/b]: picking another colour before then starts a new 7 days from that moment; the time left is not paid back.
[*] [b]Back to gold[/b]: any time, free; the time left is not paid back.
[/list]
[h3]Exchanging for Survivor Coins[/h3]
The server needs Minidoracat Economy (multiplayer only). Uses for points shows how much you can still exchange today; press "Exchange for survivor coins...".
[list]
[*] [b]Rate[/b]: 1 point = 1 Survivor Coin by default, set by the host.
[*] [b]Limits[/b]: by default up to 100 points per player per day, at least 10 per exchange; "All available" fills in the smaller of your balance and today's remaining limit.
[*] [b]Queued[/b]: when the Economy mod's daily allowance for this mod is used up, your points are held and paid automatically later (retried every hour and right after the Economy mod's daily reset).
[*] [b]Refunded[/b]: if your economy account cannot receive coins, the points come back and you are asked to contact an admin.
[*] [b]No reply[/b]: press "Ask again" to check the result; asking again never exchanges twice.
[*] [b]Imported achievements[/b]: points from achievements imported mid-save never reach your balance and cannot be exchanged.
[*] [b]Exchange history[/b]: Points history shows each exchange's state (Queued / Credited / Points returned). In the Economy admin ledger the reason reads "Quest points exchange"; from Economy 42.21.0-0.23.0 on, your wallet statement and the receipts on the Economy admin's Player page read it too.
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
[*] [b]Tracker panel background opacity (%)[/b]: 50 to 100, 80 by default; under 80 the text gets a black shadow.
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
[tr][td]Free swaps per day[/td][td]1[/td][/tr]
[tr][td]Uses for points[/td][td]Paid swaps: on, 50 points, up to 3 a day; streak shield: on, 200 points, 1 a week at most; point titles: on, 1,000 / 2,000 / 3,500 / 5,000 points, this season's title 1,500 points; title colour: on, 300 points for 7 days[/td][/tr]
[tr][td]Weekly quests[/td][td]3, 60 points each[/td][/tr]
[tr][td]Server goal[/td][td]On, 50 points when reached, target ×1.1 of last week[/td][/tr]
[tr][td]Streaks[/td][td]3 quests count as a day, 1 grace day per week[/td][/tr]
[tr][td]Players see the quests by theme[/td][td]Off (admins only)[/td][/tr]
[tr][td]Newcomer quests[/td][td]On, 100 points + title[/td][/tr]
[tr][td]Achievement points[/td][td]10 / 20 / 30 / 50 / 80 per tier, hidden 30[/td][/tr]
[tr][td]Difficulty[/td][td]Normal (Easy ×0.6, Hard ×1.6; only thresholds and quest targets; skill levels and towns visited have a ceiling and stay as they are)[/td][/tr]
[tr][td]Season length[/td][td]28 days (7-180)[/td][/tr]
[tr][td]Exchange[/td][td]On, 1 point = 1 Survivor Coin, 100 points per player per day, at least 10[/td][/tr]
[tr][td]Sponsored hordes[/td][td]Off; when on, three difficulties: Normal 600, Hard 1,200, Nightmare 2,500 points (toughness 1 / 2 / 3, 15 / 20 / 25 min per wave, all on the "Default" preset); at least 50 per pledge, filled within 30 min, 1 a day at most, pays back at most 50% of the pool, 10% back to sponsors on a clear, starts 15 min after the fund is full[/td][/tr]
[tr][td]Server-wide donation[/td][td]Off; when on, a 10,000-point target, at least 10 per donation, Saturday 21:00, "Default" preset, toughness 3, 30 min warning, 60 min wait for players[/td][/tr]
[tr][td]Squad contracts[/td][td]On (multiplayer only); Hunt 150 × players / 60 min / stake 100, Melee hunt 100 / 60 / 150, Long haul 400 / 120 / 250; met: 50% of the stake back, plus 30% for those with 30% of a share in kills; 3 per player per day, 10 min to gather, 2 to 6 players, 10 at once at most[/td][/tr]
[tr][td]Server-wide notices[/td][td]On, from tier 3, 1 per player per minute[/td][/tr]
[tr][td]Hordes[/td][td]Automatic hordes off (settings in "Horde settings")[/td][/tr]
[tr][td]Not ranked[/td][td]Offline for 180 days[/td][/tr]
[/table]
=== ⚙️ Admin panel
{{img:08-admin-basic-en.jpg}}
Open "Admin" on the left of the window (its own group at the bottom of the list); only roles listed in the "Admin roles" sandbox option see it, and the server checks every action again.
[h3]How changes work[/h3]
[list]
[*] [b]Tabs[/b]: settings come first (General, Achievements, Titles, Quests, Season, Points, Towns, Hordes); after the divider come operations (Players, Report, Balance, History; see "Admin panel: operations tabs"). For Hordes see "Horde settings".
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
[*] [b]Count only levels the character gained itself[/b] (at the bottom, off by default): when on, the levels a character starts with do not count toward skill achievements, the total skill level or the highest skill level; a skill counts, at its current level, once that character has raised it by at least one level. Levels already recorded and achievements already unlocked stay; characters already in play start from the levels they have when it is turned on. An account whose character had already survived 24 hours at its first login keeps all the levels it had then.
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
[h3]Points[/h3]
{{img:11-admin-exchange-en.jpg}}
[list]
[*] [b]Exchange settings[/b]: on/off, rate, per-player daily limit, minimum per exchange.
[*] [b]Today[/b]: exchanged today, estimated daily exchange, and the Economy mod's daily limit for this mod with today's usage, all server-wide totals.
[*] [b]Warnings[/b]: shown at the top when the Economy limit is 0, cannot be read, this mod is disabled in the Economy mod, or the estimate exceeds the limit; see "Economy integration".
[*] [b]Change the limit[/b]: the button opens the Economy mod's "Integration sources" page.
[*] [b]Uses for points[/b]: on the same tab, no Economy mod needed. An on/off for paid swaps, streak shields and point titles each, with prices, times per day or week, and the prices of the four titles and the season title (0 for the season title = not sold). Spending only takes points from the balance; season points and leaderboards stay the same.
[*] [b]Turning one off[/b]: titles and shield days players already bought are kept. Sponsored hordes and the server-wide donation are set on the Hordes tab; see "Sponsored horde and donation settings".
[/list]
[h3]Title colour and squad contracts[/h3]
{{img:22-admin-contracts-en.jpg}}
[list]
[*] [b]Title colour[/b]: "Players can rent a title colour", the price of each rent and the days it lasts (1-90). Players can always go back to gold for free, even with it off.
[*] [b]Squad contracts[/b]: "Players can start squad contracts"; stake back when met (%), the bonus for those who pulled their weight (% of the stake), the kills that count as pulling your weight (% of a share), most per player per day, time to gather, fewest and most players, most at once; for each of the three contracts "Open to players", target per player, time limit and stake.
[*] [b]Less comes back than goes in[/b]: stake back plus bonus may be 95% at most, or Apply refuses it; the fewest players cannot be more than the most.
[*] [b]Contracts already started keep their terms[/b]: stake, target, time limit and percentages are fixed when a contract is started. Contracts only open on multiplayer servers.
[/list]
[h3]Towns[/h3]
[list]
[*] [b]12 built in[/b]: Muldraugh, West Point, Riverside, Rosewood, Louisville, Brandenburg, Ekron, Irvington, Echo Creek, Fallas Lake, March Ridge, Valley Station; each can be disabled.
[*] [b]Custom towns[/b]: a name and two corners; "Use my position" fills in coordinates.
[*] [b]Used for[/b]: town achievements, the Towns visited board and the newcomer step "leave your starting town".
[/list]
=== ⚙️ Admin panel: operations tabs
The four tabs after the divider: Players, Report, Balance, History.
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
[*] [b]Points spent[/b]: the points section also lists the points players spent in the period, in total and for quest swaps, streak shields, titles, title colours, sponsored hordes, the server-wide donation and squad contracts (horde refunds and the 10% back, and contract stakes that came back, already taken off; Survivor Coin exchanges listed apart).
[*] [b]Squad contracts[/b]: for each contract, how many were started, met and not met in the period, and the share met.
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
[*] [b]Now[/b]: the current horde's place, state, preset, "wave W/N", how many are cleared and its times; while it waits for players, the time it waits until (nobody by then: it fails); during a rest "next wave in M:SS". "Cancel this horde" before it starts, "Stop this horde" after (it fails, the cleared waves still pay, its zombies on the field are removed); both ask first. Below: "Today N / M hordes, next roll HH:MM" and "Refresh".
[*] [b]Start a horde[/b]: skips the roll and starts a horde at a random spot, even with automatic hordes off; it does not count toward the daily limit. On the same row pick the "Preset" and fill in "Warning" (0 to 120 min, 0 starts it now) and "Wait for players" (1 to 240 min); they start at 15 and 60 and keep what you type. The preset list shows only applied presets, and changes still waiting for "Apply" are not used. With a horde already planned or running, cancel or stop it first. Starting and stopping are listed in History but cannot be undone.
[*] [b]Recent results[/b]: the last 5 hordes with the waves cleared and the points paid ("(capped)" when the cap was hit), the kills for cleared hordes and the reason for failures.
[*] [b]Spots[/b]: stand where a horde should appear, fill in "Spot name" and press "Add my current position"; up to 32 spots, one picked at random for each horde. Each row has a "Map" button that opens the world map on the spot; "Remove" asks first, since you have to go back to the place to add it again. Automatic hordes and "Start a horde" need at least one spot. The zombies walk in from 30-40 tiles around the spot, so keep spots more than 60 tiles from player bases.
[*] [b]Horde corpses[/b]: "Most corpses kept (0 = keep all)" and "Remove the rest after the end (min)", 500 and 10 by default. Only the corpses of zombies this mod spawned for a horde are removed, with everything on them; player and other zombie corpses stay. Over the limit the oldest go first; after a horde ends (cleared, failed or stopped) and the minutes pass, once a player is near the spot, the corpses of that horde and older ones within 60 tiles are removed, at most 100 a second. When parts of that area are not loaded yet, it is gone over again every minute, up to 30 times. Corpses dragged more than 60 tiles away stay.
[*] [b]Time windows[/b]: "Automatic hordes" (off by default), then one entry per window: the start and end time (HH:MM in the sandbox time zone; an end earlier than the start runs past midnight and belongs to the day it starts, equal means all day) and "chance per hour"; the window's "Preset", "Warning" and "Wait for players" minutes (how long each wave waits for someone within 30 tiles before the horde fails); the seven weekday buttons (pick at least one) and "Remove". "Add a window" up to 8. Each window rolls once an hour during its time and, on a hit, schedules a horde within that hour; identical windows each roll on their own, and only one horde runs at a time. Below: "Hordes per day at most (all windows)" and "Wait after a server start (min)": after a restart or a crash a horde carries on from the last world save, and a horde planned or running before the restart starts no wave during this wait (0 to 60, 0 = no wait); start and waiting times that passed while the server was down count from the end of the wait. Hordes planned after the start keep their own warning.
[*] [b]Sponsored hordes and the server-wide donation[/b]: below the time windows and above the presets; see "Sponsored horde and donation settings".
[*] [b]Horde presets[/b]: each preset is a set of waves, kinds and reward. A window's hordes play the preset that window picks. "Edit preset" picks the one the three sections below change, and their titles name it; "Copy as new preset" copies every setting of the current one (named like "Default 2"), up to 8 presets; "Preset name" takes up to 32 characters, every preset but "Default" needs one, and no two may share a name (the server checks too). "Delete preset" lists the windows that will use "Default" instead and asks first; "Default" cannot be deleted. Below: "Used by" and the windows that use this preset.
[*] [b]Waves · preset name[/b]: one row per wave with "Base" and "Per extra player" (%), and the wave's size for 1 and 4 players; "Add a wave" up to 10 (it copies the last row), at least one stays. Below: "Rest between waves (s)", "Time limit per wave (min)" and "Most alive at once (zombies)", with the server's sandbox delete threshold next to it: keep "Most alive at once" below it, or the game may delete far zombies, which do not count as kills.
[*] [b]Kinds · preset name[/b]: one row per kind above 0 with "Weight", "Share", "Points each", "Toughness (×)" and "Remove". Weights are relative and need not add up to 100; only kinds above 0 appear, and the warning lists only those. Toughness runs from 0.1 to 10 (a comma works as the decimal point, as in 0,5): 1× uses the zombie Toughness from the server sandbox, 2× takes twice the damage to bring down. Health tops out at 30 after the multiplier (about 8× for zombies with sandbox Toughness "Tough"), and kinds from other mods are multiplied on their own health. Players do not see toughness. Add others from the "Add a kind..." dropdown: they start at weight 10 and, without points of their own, at the regular zombies' points. A kind whose mod was removed shows "Not installed" and can be removed. Sprinters are made sprinters as they spawn, whatever the sandbox "Speed": they appear even when the sandbox has no sprinters, so remove their row if you want none. With the sandbox "Day/Night Zombie Speed Effect" set to Night or Day, they go back to the sandbox speed when day and night switch.
[*] [b]Reward · preset name[/b]: "Points cap per horde" and the preset's estimate box (every wave cleared) for 1, 4 and 8 players, marked "(cap)" where the cap cuts it. The wave sizes, shares and estimate follow what you type.
[*] [b]Like other settings[/b]: spots, windows, presets and fields go into pending changes and take effect with "Apply" at the bottom; they are kept in History and written to config.json (see "Settings file config.json"). A horde already scheduled keeps the preset and settings it was planned with.
[/list]
[table]
[tr][th]Setting[/th][th]Default[/th][/tr]
[tr][td]Time windows[/td][td]Every day 19:00 to 23:00, 30% per hour, "Default" preset, 15 min warning, 60 min wait for players per wave; 1 horde per day at most[/td][/tr]
[tr][td]Wait after a server start[/td][td]10 min[/td][/tr]
[tr][td]Horde corpses[/td][td]500 kept at most; the rest near the spot removed 10 min after a horde ends[/td][/tr]
[tr][td]"Default" preset waves[/td][td]1 wave of 30 zombies, +50% per extra player; 30 s rest between waves; 15 min per wave; 200 alive at once at most[/td][/tr]
[tr][td]"Default" preset kinds (weight / points each / toughness)[/td][td]Regular zombies 80 / 5 / 1×, Sprinters 20 / 8 / 1×[/td][/tr]
[tr][td]"Default" preset reward[/td][td]Points cap of 500 per horde[/td][/tr]
[/table]
=== ⚙️ Sponsored horde and donation settings
{{img:23-admin-donate-en.jpg}}
Both sections sit on the "Admin > Hordes" tab; for the rules players see, read "Sponsored hordes and server-wide donation". Like other settings, changes take effect with "Apply".
[h3]Sponsored hordes[/h3]
[list]
[*] [b]Fields[/b]: "Players can sponsor a horde" (off by default), smallest pledge, most per day, most paid back (%, 0-90), back to sponsors on a clear (%, 0-50), fund time limit, warning and wait-for-players minutes.
[*] [b]Difficulty tiers[/b]: up to 4, cheapest first, one row each: name, preset, price (points), toughness and minutes per wave. "Add tier" adds one, each row's "Remove" takes it away.
[*] [b]Names[/b]: normal, hard and nightmare show as Normal, Hard and Nightmare in each player's language; a blank name shows "Tier N"; no two may share a name.
[*] [b]Toughness[/b]: multiplies the preset's toughness, and the points per kill and the cap with it. Horde zombies start from 1× health; the sandbox zombie Toughness does not change them.
[*] [b]Minutes per wave[/b]: the same value as the preset means it follows the preset; another value is used for that tier.
[*] [b]With one tier[/b]: players see no difficulty, as before. With 2 or more, clearing the last tier counts for the "Nightmare Conqueror" achievement.
[*] [b]Cap[/b]: a horde pays at most the pooled points × most paid back %, or the preset's cap × toughness if lower. Most paid back plus back to sponsors may not be over 90%, so less comes back than goes in.
[*] [b]Now[/b]: shows an open fund (points pooled, sponsors, when it ends) and today's sponsored hordes; a sponsored horde's state reads "(sponsored)".
[*] [b]Open funds keep their terms[/b]: a fund plays the tier, preset and percentages it opened with; later changes or a deleted preset do not affect it. Deleting a preset moves the tiers that use it to "Default". Turned off after a fund is full, that horde still starts.
[/list]
[table]
[tr][th]Tier (default)[/th][th]Preset[/th][th]Price[/th][th]Toughness[/th][th]Minutes per wave[/th][/tr]
[tr][td]normal (Normal)[/td][td]Default[/td][td]600[/td][td]1[/td][td]The preset's (15)[/td][/tr]
[tr][td]hard (Hard)[/td][td]Default[/td][td]1,200[/td][td]2[/td][td]20[/td][/tr]
[tr][td]nightmare (Nightmare)[/td][td]Default[/td][td]2,500[/td][td]3[/td][td]25[/td][/tr]
[/table]
[list]
[*] [b]Other defaults[/b]: smallest pledge 50, 1 a day at most, 50% most paid back, 10% back on a clear, 30 min fund time limit, 15 min warning, 60 min wait for players.
[/list]
[h3]Server-wide donation[/h3]
[list]
[*] [b]Fields[/b]: "Players can donate points (server-wide)" (off by default), target (points), smallest donation, weekday and time of the horde (sandbox time zone), preset, toughness, warning and wait-for-players minutes. Defaults: 10,000 points, 10, Saturday 21:00, "Default" preset, toughness 3, warning 30, wait 60.
[*] [b]Cap[/b]: that horde pays at most the preset's cap × toughness, which must be under the target, or Apply refuses it.
[*] [b]State[/b]: the top of the section shows the round's points and donations; once full, when the extra horde comes and what the next round has so far.
[*] [b]After a round fills[/b]: its horde keeps the toughness, target, warning and wait from then and still comes if the donation is turned off; only the preset's id is kept, so changes to that preset's content apply. Deleting the preset moves it to "Default".
[*] [b]Not counted per day[/b]: sponsored and donation hordes do not count toward the automatic hordes per day.
[/list]
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
[*] [b]When the file applies while the panel is open[/b]: an open admin panel switches to the new settings. Changes not applied yet that touch a setting the file changed are refused at Apply and dropped (the bar says how many), so make them again on the reloaded settings; changes to other settings apply as usual. An Undo on the History tab after that is refused and reloads the same way. The same happens when another admin changes settings in the panel.
[*] [b]Not in the panel[/b]: leaderboards (boards), community goal rotation (goal.rotation), newcomer title and days (newbie.title, newbie.days) change only in this file.
[*] [b]Hordes (hordes)[/b]: every setting of the Hordes tab: enabled, windows (up to 8 {days, from, to, chance, preset, leadMin, waitMin}: days such as "12345", 1 = Monday; from and to "HH:MM"; chance per hour; preset = the id of the window's preset; always written whole), maxPerDay, resumeMin (minutes after a server start before a horde from before the restart starts a wave, 0 to 60), corpses ({max, afterMin}: horde corpses kept at most, 0 to 5000, 0 = none removed; minutes after the end before the rest go, 0 to 240), presets (preset id to preset, up to 8, default is always there; an id starts with a letter and has only letters, digits, _ and -; each has name, waves (up to 10 {base, perPlayer}, perPlayer = % of base per extra player; always written whole), kinds (kind id to weight; built in: vanilla, runner), points (kind id to points per kill; a kind left out pays like vanilla), hp (kind id to toughness, 0.1 to 10), limitMin, restSec, maxAlive, cap), spots (up to 32 {name, x, y, z}, always written whole). A window whose preset does not exist, or a preset name that is blank (default may be) or shared, stops the whole file. Keys left out of a preset other than default (except name and hp) are filled from the defaults on read and written back; no hp means 1× for all. Ranges and an example are in the GitHub README.
[*] [b]Uses for points (shop)[/b]: swap ({enabled, pts, perDay}: price per paid swap 1-10000, at most 1-10 a day), shield ({enabled, pts, perWeek}: price of a shield day 1-10000, bought at most 1-7 times a week), titles ({enabled, season, list}: list = the prices of the four titles spend_1 to spend_4, 1-100000 each; season = the season title's price 0-100000, 0 = not sold), color ({enabled, pts, days}: title colour price 1-100000, lasting 1-90 days). Turning one off ("enabled": false) keeps the titles and shield days players already bought.
[*] [b]Sponsored hordes (hordes.paid)[/b]: {enabled, minPledge, fundMin, maxPerDay, rewardPct, backPct, tiers, leadMin, waitMin}, off by default. minPledge 1-10000, fundMin 5-240, maxPerDay 1-24 (apart from hordes.maxPerDay), rewardPct 0-90 (0 = no points), backPct 0-50 (% back to each sponsor on a clear; rewardPct + backPct at most 90), leadMin 0-120, waitMin 1-240. tiers: 1 to 4 {name, preset, pts, hp, limitMin}, always written whole: name up to 32 characters, may be blank, no two alike; preset must be in presets; pts 100-100000, never below the tier before; hp 0.1-10; limitMin 1-120, left out = the preset's.
[*] [b]0.7.0 sponsor settings[/b]: hordes.paid's pts and preset became tiers. A file still written that way is converted at start into one tier (name normal, hp 1) and written back; a rewardPct of 81-90 gets backPct = 90 - rewardPct.
[*] [b]Server-wide donation (donate)[/b]: {enabled, target, min, day, time, preset, hp, leadMin, waitMin}, off by default. target 100-10000000, min 1-10000, day 1-7 (1 = Monday), time "HH:MM" (sandbox time zone), preset must be in presets, hp 0.1-10, leadMin 0-120, waitMin 1-240; while on, the preset's cap × hp must be under target.
[*] [b]Squad contracts (contracts)[/b]: {enabled, returnPct, bonusPct, sharePct, perDay, joinMin, minSize, maxSize, maxActive, list}. returnPct, bonusPct, sharePct 0-100 (returnPct + bonusPct at most 95), perDay 1-20, joinMin 1-60, minSize 2-6, maxSize 2-12 (not below minSize), maxActive 1-50; list holds hunt, melee and long, each {enabled, perMember, limitMin, stake}: perMember 1-100000, limitMin 5-600, stake 1-100000.
[*] [b]Older horde settings[/b]: 0.2.0's from, to, chance, count, perZombie and split are gone, and waves, kinds, points, time limits and the like moved from hordes into presets. A file still written the old way is converted at start or on the next read and written back: from/to/chance become one window on every day, count becomes one wave of its middle value that does not grow with players, perZombie becomes every kind's points, and split is dropped; these settings become the "Default" preset (presets.default), and leadMin and waitMin go into every window. An old key is kept, not moved or dropped, when its new key is already in the file (say a window has its own leadMin and hordes has one too) or its value was not valid before either (say "leadMin": false); then the file is not applied and status.json names that key, so fix it by hand.
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
[*] [b]A death clears this season's results[/b] (off by default): when on, any death of a player's character (hordes included) sets that player's season stats and season points to zero at once: every season board counts them from 0, and the season rank and the participation reward only look at points earned after the death. Not touched: the points balance (still spendable and exchangeable), all-time stats and boards, unlocked achievements and titles, quest progress, the streak. What is cleared cannot be restored; the player gets a notice on death and the season boards say so at the top.
[/list]
=== ⚙️ Economy integration
[list]
[*] [b]Registers itself[/b]: once the server is up, this mod registers with the Economy mod as the integration source "Quests & Achievements" and pays in Survivor Coins.
[*] [b]The limit you must set[/b]: the Economy mod gives every integration source a daily mint limit of 0 by default, shared by all players on the server. Open the Economy admin's "Integration sources" page and set the "Daily issue cap" for Quests & Achievements; until you do, every exchange is queued and nothing is paid.
[*] [b]Choosing the limit[/b]: roughly players who exchange per day × per-player daily limit × rate; the estimate on this mod's "Points" admin tab helps.
[*] [b]Queue and retries[/b]: when the allowance is used up, rate-limited, the Economy mod is not ready or does not answer, the exchange is queued and retried every hour, plus right after the Economy mod's daily reset.
[*] [b]Refunds[/b]: any other refusal (for example a player's economy account cannot receive coins) refunds the points. One exchange is never paid twice.
[*] [b]Day change[/b]: when the Economy mod provides its day-change API (versions after 42.21.0-0.20.1), the daily and weekly reset happen at the same moment as the Economy mod's daily reward; reading the limit and today's usage needs the same versions. Older Economy versions still exchange, but the admin page cannot show the limit.
[/list]
=== ⚙️ Data and backups
[table]
[tr][th]Contents[/th][th]Location[/th][/tr]
[tr][td]Setting overrides, seasons, server-wide quest and server goal, timed events, hordes (the current one and the last 20 results, each with everyone's kills, players joined, MVPs and deaths), horde funds, the server-wide donation, squad contracts, audit (last 500)[/td][td]Global ModData shared table MinidoracatQuest in the world save[/td][/tr]
[tr][td]Each account's stats, quests, points, achievements, titles, preferences, tracked items, exchange queue and recent points history[/td][td]Global ModData account tables MinidoracatQuest_A00-A15 (16 tables)[/td][/tr]
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
[*] [b]Horde kinds[/b]: registerHordeKind (from API_REVISION 2; check with type that it is a function) registers a kind of zombie; your mod only spawns them, this mod handles timing, counting and clearing. 8 kinds per mod, 32 in all; a new kind's weight starts at 0 until an admin adds it from the Hordes tab's dropdown, and until it has points of its own a kill pays what a regular zombie pays. The toughness an admin sets in a preset multiplies the health you set (up to 30; 1× leaves it alone). When the zombies it takes die, their corpses and everything on them are removed by the host's Horde corpses settings, so spawn should return only the zombies it just spawned; if your kind carries special loot, tell hosts in your description.
[*] [b]Your own build flow[/b]: built(player) (from API_REVISION 3; check with type that it is a function). If your mod puts things into the world through its own flow, call it once on the server after the build is done and the materials are taken: it counts as 1 build (achievement, daily and weekly quests, leaderboard), at most 30 a minute. Do not call it for builds that took no materials. Recipes that go through vanilla building need no call; this mod counts them itself.
[*] [b]Spawned zombies[/b]: only appearance, health, walk type and speed and some state flags of a server-spawned zombie reach clients, so set them when you spawn it; strength, sight and hearing are worked out on each computer, and modData does not sync. The engine reuses zombie objects without clearing useless from their last life (such a zombie ignores sounds and players), so call setUseless(false) at spawn if your kind should be drawn in.
[/list]
=== ⚠️ Known limitations
[list]
[*] [b]Anonymity only applies on this mod's leaderboard screens[/b]: the game lets clients read the save's shared data, so a modified client can see who is anonymous and every account's points.
[*] [b]The character who finishes an action comes from the client[/b]: which character crafting, building, repairs or fishing are credited to follows the character the client sent in the vanilla action; the server still verifies identity and applies per-minute limits.
[*] [b]Distance is a straight line per minute[/b]: detours and back-and-forth count less; only the driver earns driving distance, not passengers; a jump too large for one minute (teleport) is ignored.
[*] [b]Per-minute limits[/b]: each stat has a per-minute limit; anything above it does not count and is logged as an anomaly for admins.
[*] [b]Corpses burnt on a campfire do not count[/b]: a campfire burns corpses on its square, but nobody can be credited with it; clearing corpses counts burials and corpses burnt with petrol and a lighter.
[*] [b]Exchange is multiplayer only[/b]: the Economy mod supports dedicated servers only.
[*] [b]Split screen[/b]: players 2-4 do not earn progress; the tracker panel and head titles are for player 1 only.
[*] [b]Head titles approximate the vanilla rules[/b]: players in a vehicle get none. When the server shows names only on mouse-over (the vanilla default), the mod checks the floor square under the mouse and the squares around it, plus the player's body; vanilla uses the object under the mouse, so pointing at a wall or a tall object can differ by one square.
[*] [b]Chat titles[/b]: only lines that arrive while the author wears a title get one; a title changed or taken off later does not always update lines already shown. A mod that rewrites the whole vanilla chat window may keep them from appearing.
[*] [b]Horde zombies that wander off become normal[/b]: a zombie away from every player is stored by the game and the mod cannot recognise it when it comes back, so it stops counting for the horde and is not removed when time runs out.
[*] [b]After a server restart or crash a horde carries on from the last world save[/b]: in a wave that was cut off, the zombies alive at the save and those not out yet come again after the start; the zombies that were out are brought back by the game as normal zombies and do not count, so there are some extra normal zombies near the spot. A crash takes every Quest record back to the last world save; vanilla does not save on a timer (SaveWorldEveryMinutes 0), so hosts should set it to 15 to 30 minutes.
[*] [b]Wild zombies near the spot come too[/b]: horde zombies follow a sound from the spot every 5 seconds, and wild zombies nearby hear it as well; they do not count for the horde. The sound reaches at most 49 tiles, so it does not stir zombies farther away that are not loaded.
[*] [b]Removed zombies can linger for a few seconds[/b]: when time runs out or an admin stops a horde, the player in charge of those zombies (usually the closest one) may still see them for up to about 8 seconds.
[*] [b]Horde deaths do not look at the cause[/b]: from the first wave until the end, any death within 50 tiles of the spot counts for the death notice and the results, whether a bite, a fall or bleeding; deaths farther away do not. At most 50 deaths are kept per horde.
[*] [b]Results open on their own only for players at the spot[/b]: only players online, alive and within 50 tiles when the horde ends get them; players who left, died or were offline press "View results" on the Hordes page. With a controller you get a notice instead of the window.
[*] [b]Hiding a horde is not saved[/b]: "Hide this horde" lasts until you log out; after you log in again the horde shows again.
[*] [b]Mid-save import is partial[/b]: only kills, days survived and skill levels; crafting, distance, fishing and the rest count from when the mod is added.
[*] [b]Player identity[/b]: on Steam servers a name is bound to its Steam account the first time it comes online; switching Steam accounts makes you a different player, and there is no way to unbind yet. No-Steam servers cannot stop someone respawning under another player's name; a modified client may take a name that has not come online to be bound yet.
[*] [b]Event logs keep growing[/b]: see "Data and backups".
[*] [b]Squad contracts are multiplayer only[/b]: single player has no Squad contracts page, and the achievements page leaves out "Contractor".
[*] [b]A squad that breaks up for lack of players uses no daily contract[/b]: the stakes come back and the day's count stays, so the same player can start one again and again; each player can be in one contract at a time.
[*] [b]Contracts carry on right after a restart[/b]: only the downtime is given back; unlike hordes, there is no wait for players to reconnect.
[*] [b]No refunds from the server-wide donation[/b]: donations are kept; a round not full keeps filling, and a full round whose horde does not happen is moved, not refunded.
[/list]
=== ❓ FAQ
[h3]My quest is not advancing?[/h3]
[list]
[*] Progress counts from the moment the quest appears; earlier play does not count.
[*] Split screen players 2-4 do not earn progress.
[*] Burning a corpse counts only when the fire starts: with fire turned off on the server, in a safehouse that does not allow fire, on water or on a square already burning, the petrol and the lighter are used but it does not count.
[*] Eggs count only when taken with "Grab Eggs" from a henhouse nest box; milking and shearing count when the action ends by itself after taking some (the animal has no more milk or wool, the container is full, or the animal gets scared and runs off), not when you cancel it.
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
[h3]Does spending points lower my rank?[/h3]
[list]
[*] No. Ranks use points earned; exchanging for Survivor Coins, quest swaps, streak shields, point titles, title colours, sponsored hordes, the server-wide donation and squad contract stakes only spend your balance. A squad contract bonus counts as earned points and adds to your ranks.
[/list]
[h3]What if a horde fund is not filled?[/h3]
[list]
[*] When the fund's time limit (30 minutes by default) runs out before it is full, everyone gets all their points back, offline players too; Points history says "Fund not filled, refunded".
[*] If the horde cannot happen after the fund is full (no spot, cancelled by an admin, nobody came), all points come back too; once the zombies appear there is no refund.
[/list]
[h3]I cannot see sponsored hordes or a use for points?[/h3]
[list]
[*] Sponsored hordes and the server-wide donation are off by default: an admin turns them on under "Admin > Hordes", and the server needs a horde spot. The host can also turn the other uses off one by one; the Points page lists only the ones this server has on.
[/list]
[h3]Why can I not see squad contracts?[/h3]
[list]
[*] Squad contracts are only on multiplayer servers; single player has no such page.
[*] On a multiplayer server the host may have turned them off ("Players can start squad contracts" under "Admin > Points").
[/list]
[h3]Where does the stake go when a contract is not met?[/h3]
[list]
[*] It is lost: it is not given to anyone or turned into another reward.
[*] Even a met contract returns only half, plus a 30% bonus for those who pulled their weight, so squad contracts are a way to spend points, not a shortcut to earn them.
[/list]
[h3]My title colour ended. What now?[/h3]
[list]
[*] It goes back to gold by itself; you get a reminder at login when less than a day is left.
[*] To keep it, change it again on the Points page (another 300 points for 7 days).
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
