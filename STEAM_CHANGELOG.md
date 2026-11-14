[h1]Minidoracat Quests & Achievements for B42 42.22.2-0.9.0[/h1]
[i]2026-11-15[/i]

這一版把夜間任務的時段寫清楚、讓自由建造蓋的東西也算建造，並給伺服器管理員兩個預設關閉的新開關。

[b]English summary[/b]
[list]
[*] Night quests and achievements now state their hours: 21:00–06:00 in game time. The rule itself did not change.
[*] Things you build with Build Anything and pay materials for now count as building (achievement, daily and weekly quests, leaderboard). Build Anything needs its own update for this.
[*] Admins, off by default: "A death clears this season's results" (Season tab) resets a player's season stats and season points when their character dies; balance, all-time stats, achievements and titles stay.
[*] Admins, off by default: "Count only levels the character gained itself" (Achievements tab) stops starting skill levels from counting toward skill achievements.
[*] Modders: the server API is now revision 3 with built(player).
[/list]

[h3]✨ 新增[/h3]
[list]
[*] [b]夜間的任務與成就寫出時段[/b]：「在夜間擊殺殭屍」「在夜間釣魚」的任務與成就說明現在寫明 21 點到 6 點（遊戲內的時間）。規則沒有變。
[*] [b]自由建造（Build Anything）蓋的也算建造[/b]：用自由建造付材料蓋的圖塊，算進建造成就、每日與每週的建造任務和建造排行榜（自由建造也要更新到支援的版本）。沒扣材料的（建造作弊、材料倍率 0）和原地替換不算；它的配方項目本來就會算。
[*] [b]管理員新開關「死亡時清掉本季成績」[/b]（預設關，在管理面板「賽季」頁最下面）：打開後，角色一死亡，這位玩家的本季統計與本季積分立刻歸零，所有本季排行榜從 0 重新排，賽季結算的名次與參加獎也只看死亡之後賺到的積分。
[list]
[*] 不受影響：積分餘額（照樣能花、能兌換）、累計統計與累計榜、已解鎖的成就與稱號、任務進度、連續天數。
[*] 清掉的無法復原。玩家死亡時會收到通知，本季榜上方也會寫明這條規則。
[/list]
[*] [b]管理員新開關「只算角色自己升上去的等級」[/b]（預設關，在管理面板「成就」頁最下面）：打開後，角色開局就有的技能等級不算進技能成就、技能總等級與最高技能等級，某項技能要由這個角色自己再升至少一級才算。已經記下的等級與已解鎖的成就不會收回。
[/list]
