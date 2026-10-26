# MinidoracatQuestFor42 架構與介面契約

實作的權威依據。改網路指令、資料形狀、facade 或檔案擁有者前，先改這份。

## 0. 原則

- **伺服器權威**：統計、任務進度、積分、成就、名次都在伺服器算。客戶端只能讀資料、換任務、設偏好與稱號、送兌換與管理指令；沒有任何指令能加進度。
- **單一全域** `MinidoracatQuest`，檔頭一律 `MinidoracatQuest = MinidoracatQuest or {}`，模組掛在它底下（`MinidoracatQuest.Stats` …）。對其他 MOD 的 facade 是 `MinidoracatQuest.v1`，所有伺服器模組載入成功後才賦值。
- **多人專用伺服器為主，單機也能用**：SP 的 `sendServerCommand` 是 no-op，回覆經 `Net.send` 直接呼叫客戶端接收函式（KnoxPass 寫法）；SP 一律視為管理員；兌換在 SP 關閉（經濟系統只支援多人）。
- **Lua 原始碼只用 ASCII**。顯示文字走翻譯鍵：`IGUI_MQ_*`（`IG_UI.json`）、`Sandbox_MinidoracatQuest_*`（`Sandbox.json`）。伺服器只送鍵與參數，不送成品字串。
- **Kahlua**：沒有 `next`、`xpcall`、`math.random`（亂數用 `ZombRand` 或本 MOD 的種子亂數）；`table.sort` 的比較器必須嚴格弱序、不得對同一元素回 true；`os.date` 固定 UTC；`getTimestampMs()` 是現實時間。`verify_mod.py` 會掃。
- **玩家身分**照家族 `conventions.md`「玩家身分」：授權、記帳、推播一律經 `Identity.principal(player)`，綁定表放伺服器私有檔，不放 Global ModData。
- **安全邊界**：每個指令都在伺服器重新檢查欄位型別、範圍、權限；限流與冷卻在伺服器做，客戶端節流只是體驗。

## 1. 設計稿沒寫清楚、已在這裡裁定的細節

| # | 項目 | 裁定 |
|---|---|---|
| C1 | 榜單數 | 16 個內建榜。`skill_total`（技能總等級）只有總榜，其餘 15 個有本季與總榜，共 31 份名次。職業類由 facade `board=true` 的統計加入，內建 0 個 |
| C2 | 兌換退款 | 經濟系統回 `cap_exceeded`／`rate_limited`／`not_ready`／沒回應 → 排隊；其他錯誤一律退回積分並記稽核 `exchange_refused` |
| C3 | 每天換任務 | `daily.swapsPerDay = 1`，只限個人任務（全服任務不能換） |
| C4 | 改偏好 | 不限次數；今天的任務已經產生就從下次換日生效，還沒產生就立刻生效 |
| C5 | 成就數 | 內建約 110 項（目標 105～115），各類項數以 `Catalog.lua` 為準 |
| C6 | 職業 | 原版 25 個（含無業） |
| C7 | 稱號 | 每一級都能設稱號（`titles[tier]`），內建只在第 4 級（白金 IV；一般成就共 5 級，第 5 級只多積分）與部分隱藏成就給；facade 的 `title` 套在該成就最後一級 |
| C8 | 共同目標輪替 | 5 種：擊殺、製作、開車里程、釣魚、收成，依週次輪流 |
| C9 | 限時活動 | 管理員排程：名稱（純文字）、開始與結束（現實時間）、主題（11 個之一或 `all`）、倍率 1.5／2／3（1～5）。只乘「每日／每週任務」的積分，不影響成就與共同目標；同時最多 3 個 |
| C10 | 城鎮 | 內建原版城鎮至少 12 個（範圍取自原版地圖資料），服主可在管理面板加自訂城鎮（名稱＋矩形） |
| C11 | 難度 | 預設值寫在 `Catalog.lua`，不寫正式服數字。快速難度：輕鬆 ×0.6、普通 ×1、困難 ×1.6，只乘門檻與任務目標，不改積分。有上限的統計（`Catalog.scalable` 為假：單位 `level` 的技能等級／總等級／最高等級，與 `town.visited`）不乘，伺服器 `Achievements.scale` 與客戶端 `Client.scale` 同一規則 |
| C14 | 事件記錄檔 | `Lua/MinidoracatQuest/<serverKey>/events-YYYYMMDD.json`，每行一個 JSON 物件（NDJSON 內容，沿用設計稿的 `.json` 副檔名，因為 `getFileWriter` 只允許 `.txt`／`.json`）。不壓縮；Lua 不能刪檔，保留天數交給服主（README 寫） |
| C15 | 熱鍵 | 登記 `MinidoracatQuest_Toggle`，預設不綁（家族鍵表已沒有合格的單鍵）；Dock 入口帶 `bind` |
| C16 | 賽季結算時刻 | 結算時刻＝某天的每日重置時刻。畫面寫成前一天 23:59（`endsAt - 60000` 再格式化），凍結時間寫重置時刻 |
| C17 | 排隊重試 | 每小時重試一次，經濟系統換日後立刻重試一次；畫面文字寫「經濟系統今天的額度用完了，會自動補發」 |
| C18 | 新手任務 | 每個帳號一次（第一次看到帳號時開始），死亡不重來；舊帳號（匯入時存活超過 24 小時，或任何統計已超過新手門檻）跳過 |
| C19 | 儲存 | 共用表 `MinidoracatQuest`＋16 張帳號表 `MinidoracatQuest_A00`～`A15`（帳號名 hash 取 16 的餘數）。共用表不放帳號 |
| C21 | 分類字彙 | 三套各自獨立，見 §4.1：主題 11 個（每日任務與偏好）、成就分類 9 個、榜單分類 8 個 |
| C22 | 冷門任務 | 任務樣板帶 `rare = true` 的給 20 分，內建冷門：釣魚、誘捕、畜牧、縫紉、搜尋的任務 |
| C23 | 連續天數 | 一天完成 4 個中的 3 個算一天；每週一可補 1 次（漏的那天算寬限，仍計入天數）；週一重置寬限；換日時昨天沒達成且寬限已用 → 歸零；里程碑 3／7／14／30 天每次連續各領一次，歸零後重新累積可再領 |
| C24 | 全服任務算不算 | 算，4 個裡任 3 個 |
| C26 | 帳號欄位 | 補齊 `prefs`、`imported`、`hidden`、`titles`、`unseen` 等，見 §3.2 |
| C27 | 全服通知門檻 | 以等級序號判斷：`tier >= broadcast.minTier`（預設 3）。等級少於 3 的成就（隱藏成就、facade 加的）在最後一級解鎖時也通知 |
| C28 | 通知合併 | 同一位玩家 2 秒內的解鎖合成一則（「解鎖 N 項成就」＋前 3 個名稱）；同時最多 3 則由框架處理 |
| C29 | 參加獎 | 本季賺到 ≥ 250 的人都拿參加獎，前 10 名另拿名次獎（疊加）。有異常紀錄的帳號只標示、不預設排除；管理員排除要寫原因；24 小時沒處理就照凍結名單扣掉已排除的人發放 |
| C30 | 結算 | 到期時凍結名次（`frozen = { no, atMs, rows }`）並**立刻開新季**（季數 +1、新的起訖），所以審核期間賺的積分算進新季、不會掉；審核與發獎都用 `frozen.no` 那一季的凍結名單 → 發獎 → 寫歷史（最近 12 季：季數、起訖、前 10 名、各榜第 1 名）。帳號的本季欄位懶重置：讀到 `acc.sno ~= 目前季數` 時才清 `season` 與 `points.season`。季末各榜第 1 名在凍結時一併記下 |
| C31 | 任務樣板 | 見 §4.4 |
| C32 | 兩個不活躍門檻 | 各自獨立：30 天沒上線清掉 `day`／`week` 暫存；180 天沒上線不上榜（資料保留） |
| C33 | 兌換 | `exchange = { enabled = true, rate = 1, perDay = 100, min = 10 }`；「全部可換」＝ `min(餘額, 今天剩下的額度)` |
| C34 | 經濟系統 `rewardDay` | 本 MOD 以 `type(E.rewardDay) == "function"` 探測，不靠 `API_REVISION`；經濟系統那邊的版本規則由該 repo 決定 |
| C35 | 新手步驟 | 不分先後；在每日頁最上面顯示到完成或滿 7 天為止 |
| C36 | 每分鐘上限 | 用伺服器牆鐘（`getTimestampMs`）切每分鐘的窗；超量時每個帳號每個統計每分鐘只記一筆稽核 |

## 2. 檔案與擁有者

路徑相對 `MOD/MinidoracatQuestFor42/Contents/mods/MinidoracatQuestFor42/42/media/`。

| 檔案 | 擁有者 | 內容 |
|---|---|---|
| `lua/shared/MinidoracatQuest/Contract.lua` | Core | 常數：`MOD_ID`、`MODULE`、`PROTOCOL`、`LIMIT`、`CODE`（錯誤碼）、表名、主題／分類／榜單分類 id 清單 |
| `lua/shared/MinidoracatQuest/Util.lua` | Core | `hash(str)`（32 位元）、種子亂數 `rng(seed)`（`:int(a,b)`）、`pick`、`clamp`、`round`、JSON `encode`／`decode`（有大小與深度上限）、`logSafe` |
| `lua/shared/MinidoracatQuest/Sandbox.lua` | Core | 沙盒讀值（§9） |
| `lua/shared/MinidoracatQuest/Catalog.lua` | Catalog | 統計、成就、任務樣板、每週樣板、共同目標、新手、連續、稱號、榜單、內建城鎮、預設設定（§4） |
| `lua/server/MinidoracatQuest/Store.lua` | Core | Global ModData 共用表與 16 張帳號表、帳號存取、遷移 |
| `lua/server/MinidoracatQuest/Identity.lua` | Core | `principal(player)`，移植 Safehouse 的上線綁定，綁定表寫私有檔 |
| `lua/server/MinidoracatQuest/Clock.lua` | Core | 日界線、週界線、經濟系統 `rewardDay` 探測 |
| `lua/server/MinidoracatQuest/Audit.lua` | Core | `writeLog` 稽核、拒絕聚合、共用表的稽核環（500 筆） |
| `lua/server/MinidoracatQuest/EventLog.lua` | Core | 每日事件記錄檔（緩衝、定時寫出） |
| `lua/server/MinidoracatQuest/Config.lua` | Core | 有效設定＝Catalog 預設＋管理員覆寫；預覽、套用、復原、歷史 20 筆、`config.json` 同步（§3.5） |
| `lua/server/MinidoracatQuest/Stats.lua` | Core | `add`／`max`／`seed`、每分鐘上限、三個範圍、監聽者 |
| `lua/server/MinidoracatQuest/Points.lua` | Core | 發積分、扣積分、退回，三個數字的規則 |
| `lua/server/MinidoracatQuest/Net.lua` | Core | 送出（含 SP 直呼）、全服廣播、對在線帳號推播 |
| `lua/server/MinidoracatQuest/Server.lua` | Core | 指令分派（照 Safehouse `S.define`）與玩家指令 `hello`／`watch`／`seen`／`title`／`anon`／`records`；管理 op `cfg.*`、`acct.view`、`anom.list`、`towns.here` |
| `lua/server/MinidoracatQuest/Sync.lua` | Core | 組 `state`／`catalog`／`delta`，節流推送，通知佇列與合併 |
| `lua/server/MinidoracatQuest/API.lua` | Core | `MinidoracatQuest.v1`（`registerPack`、`pack.add`、`registerHordeKind`），最後一個載入 |
| `lua/server/MinidoracatQuest/Quests.lua` | Systems | 每日（偏好）、全服任務、換任務、連續、每週、共同目標、新手、限時活動 |
| `lua/server/MinidoracatQuest/Achievements.lua` | Systems | 等級判定、解鎖、稱號、通知、自訂成就、匯入舊進度、撤銷 |
| `lua/server/MinidoracatQuest/Exchange.lua` | Systems | 經濟系統整合、排隊、重試、退回 |
| `lua/server/MinidoracatQuest/Seasons.lua` | Systems | 賽季狀態機、改長度預覽與套用、結算審核、發獎、歷史 |
| `lua/server/MinidoracatQuest/Boards.lua` | Systems | 榜單定義、重算排程、快取、分頁、隱藏帳號 |
| `lua/server/MinidoracatQuest/Balance.lua` | Systems | 任務完成率、中位時間、調整建議 |
| `lua/server/MinidoracatQuest/Report.lua` | Systems | 管理「報表」頁：每日總數（`root.daily`）、帳號快照（一 tick 一張分表）、匯出 JSON |
| `lua/server/MinidoracatQuest/Trackers.lua` | Catalog | 遊戲事件、動作完成、每分鐘輪詢 → `Stats` |
| `lua/server/MinidoracatQuest/Towns.lua` | Catalog | 城鎮範圍（內建＋自訂）、座標查城鎮 |
| `lua/server/MinidoracatQuest/Hordes.lua` | Systems | 限時屍潮：時段與每小時擲骰、排定、預告、生成、擊殺歸屬、清除、發積分、管理 op `horde.*`、種類登記（§5.10） |
| `lua/client/MinidoracatQuest/*.lua` | ClientUI | 狀態快取、Dock、主視窗、玩家各頁、兌換視窗、通知、屍潮的小地圖整合（`HordeMap.lua`） |
| `lua/client/MinidoracatQuest/Admin*.lua` | AdminUI | 管理各頁 |
| `ui/MinidoracatQuest/**.png` | Icons | 成就圖示、Dock 圖示 |
| `sandbox-options.txt` | Core | §9 |

`Translate/*` 不由各切片直接改，見 §10。

伺服器載入順序：每個模組自己 `require` 它用到的模組；指令由擁有該資料的模組在載入時用 `Server.define`／`Server.defineAdmin` 登記（`swap`、`prefs`、`board`、`exchange` 與賽季、活動、撤銷、隱藏、平衡、難度、屍潮的管理 op 由 Systems 登記；`hello`、`watch`、`seen`、`title`、`anon`、`records` 與 `cfg.*`、`acct.view`、`anom.list`、`towns.here` 由 Core 登記）。`API.lua` 依序 `require` 全部伺服器模組（Core、Systems、Catalog 的檔名照上表，`Hordes` 在 `Towns` 之後），都成功後才賦值 `MinidoracatQuest.v1`。

離線測試檔的擁有者：`scripts/smoke_harness.lua`、`scripts/harness/env.lua`、`scripts/harness/modules.lua` 是 Core 的；各切片只寫自己的情境檔 `scripts/harness/t_core.lua`、`t_systems.lua`、`t_catalog.lua`、`t_client.lua`、`t_admin.lua`、`t_report.lua`、`t_hordes.lua`（屍潮伺服器）、`t_hordes_ui.lua`（屍潮客戶端）（可以再 `dofile` 自己的子檔 `t_<切片>_*.lua`）。runner 依固定順序載入存在的情境檔。

## 3. 資料

### 3.1 Global ModData

- 共用表 `MinidoracatQuest`（`ModData.getOrCreate`，在 `OnInitGlobalModData` 取得）：

```lua
root = {
  schema = 1,
  config = { overrides = {}, rev = 0 },      -- 管理員覆寫（§3.4），rev 每次套用 +1
  history = { },                              -- 最近 20 筆 { id, at, actor, summary, changes = { { path, before, after } } }；伺服器自寫的摘要：`event.add <id> <name>`、`event.remove <id> <name>`、`horde.now <id> <name>`、`horde.stop <id> <name>`（後兩個不能復原）、`season.length <天>`、`undo #<id>`，客戶端翻譯（舊列的活動摘要沒有 name，顯示 `#id`）
  season = { no = 1, startMs, endMs, lengthDays = 28, state = "running",   -- running | review | paying
             frozen = nil,                    -- { atMs, rows = { { user, pts, anomalies } } }
             excluded = {},                   -- user -> reason
             reviewDeadlineMs = nil },
  seasons = { },                              -- 最近 12 季 { no, startMs, endMs, top = { { user, pts } }, firsts = { boardId = user } }
  shared = { day = "2026-11-10", tid, stat, target, pts, done = 0 },
  goal = { week = "2026-W46", stat, target, progress = 0, minContrib, pts, reached = false, paid = false },
  weekTotals = { week = "2026-W45", totals = { [stat] = n } },  -- 上週全服量，算本週目標
  audit = { head = 0, items = {} },           -- 環形 500 筆 { at, kind, actor, user, detail }
  balance = { },                              -- tid -> { day -> { given, done, swaps, minutes = { ... 最多 64 筆 } } }，保留 14 天（週任務看上一個已結束的週）
  exchange = { day, coins = 0, days = {} },   -- 全服今天兌換量、最近 7 天
  daily = { },                                -- 報表每日總數，保留 30 天（§6.5）：dayKey -> { active, fresh, dGiven, dDone, dPlayers, wGiven, wDone, swaps = { tid = n }, pts = { kind = n }, coins, tiers }
  events = { },                               -- 限時活動 { id, name, theme, mult, startMs, endMs }
  hordes = { seq = 0,                         -- 屍潮（§5.10）；設定在 config 的 hordes 組，這裡只放即時狀態
             roll = { day, ws, slot = 0, n = 0 }, -- day：時段所屬的當地日期 "YYYY-MM-DD"；ws：那個時段的開始 ms；slot：已擲過的小時格數；n：今天自動排了幾場
             cur = nil,                       -- 同時最多一場，形狀見下
             log = { } },                     -- 結束的場次，新的在後，最多 20 筆（形狀見下）
}
```

屍潮 `cur`（排定時複製設定，之後改設定不影響這場）：

```lua
{ id, auto = bool, actor = user | "auto", name, x, y, z, town = townId | nil,   -- town：排定時的 Towns.at
  mix = { { kind = "vanilla", n = 24, nameKey }, { kind = "runner", n = 6, nameKey } },  -- 權重 > 0 的已登記種類；都沒有時全是 vanilla
  count, perZombie, split, limitMin, waitMin,
  state = "planned" | "announced" | "waiting" | "active",
  announceAt, startMs, expireAt (= startMs + waitMin), spawnAt, endsAt (= spawnAt + limitMin),
  spawned = 0, left = 0, killed = 0, kills = { [user] = n }, tries = 0 }
```

`log[i]`：`{ id, auto, name, town, state = "success" | "failed" | "cancelled", why, startMs, spawnAt, endedAt, spawned, killed, pool, split, paid = { [user] = pts }, kills = { [user] = n }, announced = bool }`。`why`：失敗是 `time`（時限到）、`nobody`（`expireAt` 前沒人到 50 格內）、`admin`（管理員停止）、`restart`（進行中時伺服器重開）、`spawn`（連續 10 次生成 0 隻）；取消一律 `admin`。`announced = false` 是預告前就取消的場次，玩家看不到。殭屍物件只在記憶體（`Hordes.live`），不進存檔。

- 帳號表 `MinidoracatQuest_A00`～`MinidoracatQuest_A15`：`{ schema = 1, accounts = { [user] = Account } }`。分表＝`Util.hash(user) % 16`，兩位數十進位補零。
- 每張表的 `schema` 比程式新 → 整份唯讀、不改寫；比程式舊 → 就地升級。第一天就有 `schema`。
- 客戶端能 `ModData.request` 整張表（引擎行為），所以這些表不放 SteamID、不放管理員私人資料。匿名只在本 MOD 的榜單畫面生效，README 要寫這個限制。

### 3.2 Account

```lua
Account = {
  v = 1,
  firstMs, seenMs,                              -- 第一次看到、最後上線
  seenDay = nil,                                -- 報表：最後有活動的 dayKey（統計、任務進度、hello），一天只算一次 active
  total = {}, life = {}, season = {},           -- stat -> number；season 屬於第 sno 季
  sno = 1,
  points = { season = 0, total = 0, balance = 0 },
  day = { key = "2026-11-10", quests = { Quest, Quest, Quest, Quest }, swaps = 1, done = 0 },
  week = { key = "2026-W46", quests = { Quest, Quest, Quest }, goalPart = 0 },
  streak = { days = 0, best = 0, last = nil, graceUsed = false, graceWeek = nil, paid = {} },  -- paid[3]=true …
  newbie = { startMs, steps = { false, false, false, false, false } },  -- nil：完成或跳過
  towns = {},                                   -- townId -> true
  achv = {},                                    -- achId -> 最高已解鎖等級
  titles = {}, title = nil,                     -- titleId -> true；目前使用的稱號
  prefs = {},                                   -- 最多 3 個主題 id
  anon = false,                                 -- 玩家自己選匿名
  hidden = nil,                                 -- 管理員移出排行榜：{ reason, actor, at }
  ex = { day, used = 0, seq = 0, queue = {}, log },  -- queue: { { seq, amount, coins, state = "queued", at, tries } }；log：結束的兌換 { at（結束時間）, amount, coins, state = "paid"|"refunded" }，新的在前，最多 10 筆（`Exchange.LOG`）
  unseen = 0,                                   -- Dock 徽章：還沒看過的完成與解鎖數
  pins = {},                                    -- 追蹤面板：最多 LIMIT.MAX_PINS（5）個，"d1"～"d4" 今天的每日格、"w1"～"w3" 本週格、"a:<achId>"
  imported = false,
  anomalies = 0,                                -- 本季超量次數（結算名單標示用）
}
```

Quest（每日、全服、每週共用）：

```lua
Quest = { tid, stat, theme, target, prog = 0, pts, state = "active", shared = nil, startMs, doneMs = nil, got = nil }
-- state: active | done | swapped | expired；pts 是基礎分，got 是完成時實際入帳（pts × 當下活動倍率，四捨五入，`Quests.questPts`）
```

### 3.3 範圍與重置

- `total`：跨角色累計，成就看這欄。`life`：這條命，死亡時清空（伺服器 `OnCharacterDeath`，`OnPlayerDeath` 在專用伺服器不觸發）。`season`：本季，懶重置（C30）。
- 帳號層級統計（Catalog `S(…, account = true)`：`quest.daily`、`quest.weekly`、`streak.best`、`achv.tiers`、`goal.done`、`season.joined`）不寫 `life`；我的紀錄頁「這條命」欄顯示「-」，跟「賺到的積分」一樣。
- 每日任務的進度是「指派之後的增量」，不是統計總量。

### 3.4 設定

有效設定＝`Catalog.DEFAULTS` 深層合併 `root.config.overrides`。路徑字串用點分隔（`achievements.zombie_kills.tiers`）。

```lua
DEFAULTS = {
  daily = { swapsPerDay = 1, pts = 15, rarePts = 20, sharedPts = 20, pool = { [tid] = { enabled, target = { min, max }, pts } } },
  weekly = { count = 3, pts = 60, pool = { [tid] = { enabled, target = { min, max }, pts } } },
  quests = { playerList = false },                      -- 玩家在設定頁看得到各主題的任務（管理員一律看得到）；客戶端判斷，§7
  goal = { enabled = true, pts = 50, growth = 1.1, rotation = { "zombie.kills", "craft.count", "drive.km", "fish.caught", "farm.harvest" },
           limits = { [stat] = { min, max, minContrib } } },
  streak = { need = 3, gracePerWeek = 1, milestones = { { days = 3, pts = 15 }, { days = 7, pts = 40 }, { days = 14, pts = 80 }, { days = 30, pts = 150, title = "streak_30" } } },
  newbie = { enabled = true, pts = 100, title = "newbie", days = 7 },
  achievements = { [achId] = { enabled = true, tiers = { … }, pts = { … }, titles = { [tier] = titleId } } },
  custom = { [customId] = { name = "純文字", cat, stat, tiers = { … }, pts = { … }, titles = { } } },
  difficulty = { preset = "normal", mult = 1 },          -- easy 0.6 | normal 1 | hard 1.6 | custom
  season = { lengthDays = 28 },                          -- 只能經賽季指令改，§5.9
  rewards = { top1 = 600, top3 = 400, top10 = 200, participation = 100, participationMin = 250, firstTitles = true },
  exchange = { enabled = true, rate = 1, perDay = 100, min = 10 },
  broadcast = { enabled = true, minTier = 3, perMinute = 1 },
  boards = { inactiveDays = 180, rebuildSeasonMs = 300000, rebuildTotalMs = 1800000 },
  towns = { custom = { }, disabled = { } },              -- custom: { { id, name, rects = { { x1=, y1=, x2=, y2= } } } }
  ceilings = { },                                        -- stat -> 每分鐘上限覆寫
  hordes = { enabled = false, from = "19:00", to = "23:00", chance = 30, maxPerDay = 1, leadMin = 15, waitMin = 60,
             count = { 20, 40 }, kinds = { vanilla = 80, runner = 20 }, limitMin = 15, perZombie = 5, split = "share",
             spots = { } },                              -- spots：{ { name, x, y, z } }；§5.10
}
```

- 修改單位是 change：`{ op = "set" | "del", path, value }`。`Config.validate` 依路徑家族檢查型別與範圍（門檻嚴格遞增且 1～1e9、積分 0～10000、等級最多 10、倍率 0.1～10、天數 7～180…）。
- `hordes` 組：`enabled` 布林；`from`／`to` 字串 `H:MM` 或 `HH:MM`（時 0～23、分 0～59；`to < from` 跨午夜，相等＝整天）；`chance` 整數 0～100；`maxPerDay` 1～24；`leadMin` 0～120；`waitMin` 1～240；`count` `{ min, max }` 整數 1～100 且 min ≤ max（整組替換）；`kinds` 分支，鍵是種類 id（`[%w_:-]`，最長 64，外掛種類是 `<modId>:<id>`），值整數 0～100；`limitMin` 1～120；`perZombie` 0～1000；`split` `"share"` 或 `"each"`；`spots` 整組替換，最多 32 個 `{ name = 1～64 字不含控制字元, x = 0～100000, y = 0～100000, z = -32～31 }`，不能有其他鍵。`hordes` 底下的未知鍵一樣驗證失敗。
- 套用時把每個 change 的舊值記進 `history`（最近 20 筆），復原就把舊值寫回，復原本身也是一筆歷史。
- 已解鎖的成就不因門檻提高而收回（只影響之後）。
- 限時活動 `events` 與賽季長度不走 `config`（它們有自己的狀態與指令），但同樣寫歷史與稽核。

### 3.5 私有檔

- 位置 `Lua/MinidoracatQuest/<serverKey>/`。`serverKey`：專用伺服器是 `getServerName()`；單人是 `sp_<getWorld():getWorld()>`（單人的 `getServerName()` 是空字串，`LuaManager.java:4099-4105`，而 `Zomboid/Lua` 整台電腦共用，家族 pitfalls「`Zomboid/Lua` 整台機器共用」）；`[%w_-]` 以外換成 `_`，取不到時用 `default`。
- `identity.txt`：身分綁定表，照 Safehouse `Registry.lua` 的 append-only＋讀回確認。
- `events-YYYYMMDD.json`：§1 C14。行格式 `{"t":<ms>,"k":"<kind>","u":"<user>",…}`，kind：`quest_done`、`week_done`、`goal_paid`、`streak`、`achv`、`points`、`exchange`、`season`、`admin`、`over`、`revoke`、`hide`、`horde`（屍潮結束：`{ id, state, why, spawned, killed }`，沒有 `u`）。
- `config.json`：管理員覆寫（和 `root.config.overrides` 同一棵樹，排序、縮排兩格）。開服與每 60 秒（`Config.POLL_MS`，掛在 `Server.onTick`，沒人在線也跑）讀一次；文字變了就解析、驗證，整份可用才套用：每個和目前不同的頂層組 `set`、檔案沒寫的組 `del`，記一筆操作者與摘要都是 `config.json` 的變更紀錄（可以復原），稽核與事件記錄寫 `admin`／`cfg.file`。解析失敗或驗證不過時整份不套用，`Config.file.status` 記下 `why`、`line`（JSON 停在第幾行）或 `path`（完整欄位路徑）。面板的套用與復原都會把覆寫寫回這個檔（`source = "panel"`）；檔案不見時重新寫出。前導的 BOM 會略過。
- `defaults.json`：每次開服重寫，`Catalog.DEFAULTS` 裡屬於 `Config.SCHEMA` 的組（不含 `season`，含 `hordes`），形狀和 `config.json` 相同。
- `status.json`：`Config.file.status` 的檔案版：`ok`、`source`（`boot`／`file`／`panel`）、`at`、`time`（UTC）、`rev`，失敗時加 `why`、`line`、`path`。

## 4. Catalog（`shared/MinidoracatQuest/Catalog.lua`）

`MinidoracatQuest.Catalog` 是純資料＋小工具，兩端都載。翻譯鍵由 id 推出，不在資料裡寫成品字串。

### 4.1 三套分類

- 主題（每日任務、偏好）11 個：`combat`、`build`、`craft`、`cook`、`tailor`、`farm`、`animal`、`fishtrap`、`forage`、`mech`、`explore`。鍵 `IGUI_MQ_Theme_<id>`。沒有偏好時三格依序從三組各抽一個：`combat`；`build craft cook tailor mech`；`farm animal fishtrap forage explore`。
- 成就分類 9 個：`combat`、`survival`、`skill`、`production`、`nature`、`explore`、`quest`、`hidden`、`job`。鍵 `IGUI_MQ_AchCat_<id>`。
- 榜單分類 8 個：`overall`、`combat`、`survival`、`skill`、`life`、`explore`、`quest`、`job`。鍵 `IGUI_MQ_BoardCat_<id>`。

### 4.2 統計

```lua
stats[id] = { id = "zombie.kills", kind = "count" | "max", ceil = 120, unit = "count" | "km" | "days" | "xp" | "level" }
```

- 鍵 `IGUI_MQ_Stat_<id 的點換成底線>`。`kind = "max"` 的統計（技能等級、單命存活天數、最長連續）用 `Stats.max`，不吃每分鐘上限。
- 內建 id 由 Catalog 擁有者定案，至少涵蓋：擊殺（總、近戰、槍械、車撞、各武器類）、狩獵、存活天數、技能等級（42.21.0 實際可升級的 35 個，`PerkFactory.java:98-141`）與總等級、經驗、製作、建造、烹飪、縫紉、鍛造、修車、接電、讀書、包紮、室內睡覺、播種、收成、釣魚、誘捕、搜尋、屠宰、擠奶、剪毛、撿蛋、步行、開車、擺放家具、造訪城鎮，以及任務類（每日完成、每週完成、最長連續、成就等級數）。
- `Catalog.perks`：35 個技能 id；`Catalog.statOrder`：統計的顯示順序（我的紀錄、管理面板的統計清單用）。

### 4.3 成就

```lua
achievements[i] = { id = "zombie_kills", cat = "combat", stat = "zombie.kills",
                    tiers = { 100, 1000, 5000, 20000, 50000 }, pts = { 10, 20, 30, 50, 80 },
                    titles = { [4] = "zombie_kills_4" }, icon = "zombie_kills", hidden = nil,
                    scope = nil }   -- 選用：scope = "life" 表示看這條命的統計（單命類成就），省略＝total
```

- 鍵：名稱 `IGUI_MQ_Ach_<id>`、說明 `IGUI_MQ_AchDesc_<id>`（`%1`＝門檻）、隱藏提示 `IGUI_MQ_AchHint_<id>`、稱號 `IGUI_MQ_Title_<titleId>`、等級 `IGUI_MQ_Tier_1`～`_4` 與 `IGUI_MQ_Tier_Legend`（`%1`＝羅馬數字）。
- 內建一般成就 5 級：積分 10／20／30／50／80，稱號在第 4 級。數量類第 5 級＝第 4 級 ×2.5；技能等級 2／4／6／8／10（體能、力量 6～10）、技能總等級 300（上限 35×10＝350）、造訪城鎮第 5 級 11（12 個是隱藏成就 `h_all_towns`）、存活與室內睡覺天數 730、成就等級數 450（全部 91×5＋17＝472 級）。
- 隱藏成就 17 個；`h_horde`（統計 `horde.wins` ≥ 1，帶同名稱號）是第一次參與成功的屍潮（§5.10）。
- 設定裡的 `pts` 比 `tiers` 短（4 級時代只改過積分的覆寫）時，缺的那幾級用內建積分補（`Catalog.fillPts`，伺服器、客戶端與管理面板同一規則）；`tiers` 只寫 4 個的覆寫照樣有效，那項成就就是 4 級。
- 登入補發：`hello` 在匯入之後對整份清單跑一次 `Achievements.evaluate(acc, user, { noBroadcast = true })`，補上新預設或調低的門檻已經給的等級；積分照一般成就發（本季、累計、餘額），通知本人、不發全服通知。只往上補，已拿的等級不重算，所以不會重發。
- 圖示 `media/ui/MinidoracatQuest/ach/<icon>.png`（128×128、透明底、只畫主體；等級框由 UI 畫）。缺檔時退回 UI 框架圖示或文字。
- 新增等級的預設：門檻＝上一級 ×2.5（取整到 2 位有效數字），積分＝上一級 ×1.5（取整到 10）。
- 隱藏成就只有 1 級，`hidden = true`，解鎖前客戶端只看到提示。
- 自訂成就（管理員）與 facade 成就合併進同一份清單，id 前綴分別是 `c:` 與 `<modId>:`。

### 4.4 任務樣板

```lua
daily[i]  = { tid = "d_kill", theme = "combat", stat = "zombie.kills", target = { 20, 40 }, step = 5, rare = nil }
weekly[i] = { tid = "w_kill", theme = "combat", stat = "zombie.kills", target = { 120, 180 }, step = 10 }
newbie    = { { stat = "zombie.kills", target = 5 }, { stat = "craft.count", target = 1 }, { stat = "book.read", target = 1 },
              { stat = "newbie.leave", target = 1 }, { stat = "sleep.indoor", target = 1 } }
```

- 名稱鍵 `IGUI_MQ_Q_<tid>`（`%1`＝目標）。積分由設定決定（§3.4），不寫在樣板。
- 同一天的個人任務不重複統計；全服任務只用日期當種子，從 `daily` 裡 `shared ~= false` 的樣板抽，目標取區間中位數。`xp.*` 樣板一律 `shared = false`：經驗是乘過職業加成的值（沒有加成 ×0.25、加成 3 級 ×1.66），同一個目標對非對口職業約難 6.6 倍。不是人人做得到的樣板（指定武器、開車撞、狩獵、夜釣）也是 `shared = false`。內建每日 47 個、每週 24 個。
- 選樣板時先找格子的主題；那個主題沒有不重複統計的樣板時，先從格子的備選主題找（偏好格：其他偏好主題；沒偏好的每日格與每週格：同一組），最後才是全部主題（`Quests.lua` 的 `pickT`、`slotAlts`）。
- 每個主題至少 3 個每日樣板、至少 1 個每週樣板（harness `t_catalog` 檢查）。

### 4.5 榜單

```lua
boards[i] = { id = "kills", cat = "combat", stat = "zombie.kills", periods = { "season", "total" } }
-- stat "@points" = 賺到的積分（本季用 points.season、總榜用 points.total）
```

內建 16 個：`points`（overall）；`kills`、`kills_melee`、`kills_firearm`（combat）；`life_days`（survival）；`skill_total`（只有 total）、`xp`（skill）；`crafted`、`built`、`harvested`、`fish`、`drive_km`（life）；`towns`（explore）；`daily_done`、`streak_best`、`achv_tiers`（quest）。鍵 `IGUI_MQ_Board_<id>`。

### 4.6 城鎮

`towns[i] = { id = "muldraugh", rects = { { x1 = 10540, y1 = 9240, x2 = 11160, y2 = 10760 } } }`（矩形一律用具名欄位），鍵 `IGUI_MQ_Town_<id>`。座標是 B42 世界方格座標，矩形含邊界。自訂城鎮在設定 `towns.custom`，用 `name` 純文字。

## 5. 伺服器模組 API

全部是 `MinidoracatQuest.<Module>.<fn>`。`acc` 是 Account，`user` 是 `principal` 回傳的帳號名。

### 5.1 Store（Core）

- `Store.ready()` → bool。`Store.root()` → 共用表。
- `Store.account(user, create)` → acc 或 nil。create 為 true 時建新帳號並填預設欄位。
- `Store.each(fn)`：逐帳號呼叫 `fn(user, acc)`（跨 16 張表）。只給榜單重算、結算與管理查詢用。`Store.eachIn(i, fn)`：只走第 i 張表（0～15），報表快照一 tick 走一張。
- `Store.touch(user, acc)`：更新 `seenMs`，季數不同時懶重置本季欄位。

### 5.2 Identity（Core）

- `Identity.principal(player)` → user 或 nil。`Identity.tick(now)`、`Identity.onNewGame(player)`。
- `Identity.steamMode`、`Identity.sidOf` 可被 E2E 覆寫。

### 5.3 Clock（Core）

- `Clock.now()` → ms。`Clock.dayKey(ms)` → `"YYYY-MM-DD"`、`Clock.nextResetMs(ms)`。有裝經濟系統且有 `rewardDay` 時用它，否則用沙盒 `ResetHour`＋`TimezoneOffset`。
- `Clock.weekKey(ms)` → `"YYYY-Www"`（週一開始，ISO 週）、`Clock.weekResetMs(ms)`、`Clock.weekday(ms)` → 1（週一）～7。
- 不變式：`floor((ms - shiftMs(ms)) / DAY)` 必須是當地日期的日數，週幾、週次、週界線都靠它。有 `rewardDay` 時位移要用 `nextMs - (key 的日數 + 1) × DAY` 推；只取 `nextMs % DAY` 會落在 0～1 天，UTC 以東的日數少 1，UTC+8 會變成週二才換週（2026-10-24 在 E2E 截圖發現，harness clock 段有回歸測試）。

### 5.4 Stats（Core）

- `Stats.add(who, stat, n, opts)`：`who` 是 player 或 user 字串。`n` 必須是有限正數；超過每分鐘上限的部分丟掉並 `Audit.over`。依序更新 `total`／`life`／`season`（帳號層級統計跳過 `life`，§3.3；`Stats.max` 同），然後呼叫監聽者。`opts.quiet` 給匯入用（不通知）。
- `Stats.max(who, stat, value, opts)`：三個範圍各取最大值。
- `Stats.seed(acc, user, stat, value, life)`：匯入用，寫 `total`（取最大值）；`life` 為真時 `life` 也取最大值（角色自己帶的計數，例如擊殺數）。不觸發任務、只觸發成就判定（安靜）。
- `Stats.resetLife(user)`。
- `Stats.listen(name, fn)`：`fn(acc, user, stat, delta, opts)`；監聽者在 pcall 裡執行，錯誤寫 log 不中斷。Systems 在載入時登記 `quests`、`goal`、`newbie`、`achievements`、`boards`。

### 5.5 Points（Core）

- `Points.award(acc, user, amount, kind, ref, opts)`：`kind` ∈ `quest`、`shared`、`week`、`goal`、`streak`、`achv`、`newbie`、`season`、`import`、`admin`、`horde`（屍潮獎勵，`ref` 是 `horde:<id>`）。
  - 一般：本季、累計、餘額都加。
  - `import`：只加累計。`season`（賽季獎勵）：只加餘額。
  - 限時活動倍率由呼叫端算好再傳。寫事件記錄 `points`。標記 `points` 榜為 dirty。
- `Points.spend(acc, amount)` → bool（只扣餘額）。`Points.refund(acc, amount)`。

### 5.6 Net、Sync（Core）

- `Net.send(player, cmd, payload)`：MP 用 `sendServerCommand(player, MODULE, cmd, payload)`；SP 直呼 `MinidoracatQuest.Client.receive(cmd, payload)`。
- `Net.toUser(user, cmd, payload)`：送給在線、身分通過的該帳號。`Net.broadcast(cmd, payload)`：送給所有身分通過的在線玩家。
- `Sync.state(user, acc)` → `state` payload（§6.3）。`Sync.dirty(user, part)`：part ∈ `day`、`week`、`goal`、`points`、`achv`、`streak`、`newbie`、`trk`、`pins`、`hordes`、`all`；`user = nil` 標給所有開著視窗或追蹤面板的人。
- `Sync.tick(now)`：每秒最多一輪，一輪只走一次在線名單。開著視窗（`watch`）的人收 `delta`，`delta` 帶不了的部分改送完整 `state`；只開追蹤面板（`track`）的人只收追蹤中的進度：有追蹤那一格的 `day`／`week`、`trk`、`pins`，以及 `hordes`（追蹤面板的屍潮列）（`all`、`events` 仍送完整 `state`）；兩者都沒有的人只收 `unseen`。
- 追蹤：`Sync.track(user, on)`、`Sync.pin(acc, user, id, on)` → ok, code（加入時檢查 `Sync.pinValid`：今天／本週還在進行的格、還有下一級的非隱藏成就；滿 5 個回 `TOO_MANY_PINS`；拿掉一律成功）、`Sync.unpin(acc, user, id, prefix)`（換日 `"d"`、換週 `"w"` 用 prefix 一次清掉；`Quests.swap` 清掉那一格；`Achievements.unlock` 到最高級清掉該成就）。`Sync.trk(acc)` → `{ [achId] = { t, v } }`：追蹤中成就的已解鎖等級與數值（scope `life` 取這條命，其餘取累計）。`Stats.listen("track")` 只在變動的統計屬於追蹤中的成就時標 `trk`（`Sync.pinStats`，熱路徑只查表）。
- 稱號：`Sync.titles()` → 在線玩家 `{ [user] = titleId }`；`Sync.titleChanged(user, acc)` 對所有人廣播 `titles { u, t }`（`hello`、`title` 指令、`Achievements.revoke` 拿掉戴著的稱號時）。
- `Sync.toast(user, t)`：t＝`{ kind, … }`（§6.3），2 秒內同一人的 `achv` 合併。`Sync.broadcastToast(t, achiever)`：全服通知，每位成就者每分鐘最多 1 則；成就者匿名時，一般玩家收到的那份沒有 `titleId`（頭上與聊天的稱號會認出是誰），管理員那份帶 `a` 與 `titleId`。
- `Sync.catalogChanged()`：設定改了以後對在線玩家廣播 `catalog`。

### 5.7 Server（Core）

- `Server.define(name, spec)`：同 Safehouse `S.define`。`spec = { kind = "query" | "mutation", fields = { f = "type" | "type?" }, admin = bool, cooldownMs, run = function(ctx) end }`。
- `Server.defineAdmin(op, spec)`：登記 `admin` 指令底下的一個 op。`spec` 同上（不用寫 `admin`，一律需要管理員），`fields` 是 `op` 以外的欄位；`kind = "mutation"` 的 op 成功後由 Server 統一寫稽核（`Audit.add("admin", actor, nil, { op = op })`）與事件記錄，回覆走 `admin` 推送 `{ op, ok, code, requestId, … }`。
- `ctx = { player, user, args, now, admin, command, requestId }`；`run` 回 `true, data` 或 `false, code, data`。管理 op 回 `true, Server.LATER` 表示現在不回覆，由 op 之後自己送 `admin { op, ok, code, requestId, … }`（報表快照要跨 tick 建）。
- 欄位型別：`int`、`num`、`bool`、`str`（≤ 64）、`text`（≤ 256）、`json`（≤ 32,000 bytes，伺服器端解碼成 table）。
- 每人 5 秒 20 個指令；每指令冷卻預設 300 ms（`board` 0.5 秒、`exchange` 3 秒）；冷卻中直接丟、不回覆。客戶端查榜每次至少隔 0.6 秒（`Client.BOARD_GAP_MS`），連點時只送最後一個。mutation 用 `requestId` 冪等（60 秒）。
- 管理員：SP 一律是；MP 看角色名是否在沙盒 `AdminRoles`（預設 `admin`），`getRole()` 為 nil 時不是。

### 5.8 Systems 模組（Systems 擁有）

- `Quests.ensure(acc, user, now)`：換日／換週時處理過期、連續天數結算、產生新任務、共同目標換週，回傳是否有變；換了任務清單就標 `all`（delta 只帶進度，不帶 `tid`／`target`，開著視窗的人改收完整 `state`）。`hello`、`Stats` 監聽、`Quests.tick` 都會呼叫。
- `Quests.swap(acc, user, slot)` → ok, code。`Quests.setPrefs(acc, list)` → ok, code。
- `Quests.tick(now)`：換日時處理全服任務、共同目標結算發獎（達成時貢獻 ≥ minContrib 的帳號各得 pts），並對開著視窗的玩家呼叫 `ensure`，視窗在重置那一刻就換成新任務。
- `Achievements.list()`：合併內建、自訂、facade 的有效清單（含設定覆寫的門檻）。`Achievements.evaluate(acc, user, opts)`：判定所有統計相關的成就，`opts.quiet` 時不通知、不發本季積分（只發累計）。`Achievements.revoke(user, achId, toTier, reason, actor)`。
- `Import.baseline(acc, user, player)`：每個帳號一次（`hello` 時）。目前角色的擊殺數、存活天數、35 個技能等級寫進 `total`，擊殺數也寫進 `life`（原版的擊殺數是這個角色的，不殺生天數靠它判斷）；符合的成就安靜解鎖。其他統計沒有舊值，從裝上那天開始算。
- `Exchange.init()`：`OnServerStarted` 探測 `MinidoracatEconomy.v1` 並 `registerSource({ modId = "MinidoracatQuestFor42", nameKey = "IGUI_MQ_Name", displayName = { EN = "Quests & Achievements" }, currencies = { "survivor" }, reasonCodes = { "mq_exchange" } })`。經濟系統的管理台用 `IGUI_MinidoracatEconomy_Reason_<原因碼>` 顯示原因（`ECWidgets.lua` `U.reasonText`，找不到鍵才寫「其他模組的原因：<碼>」）；這個鍵放在本 MOD 的 16 種語言翻譯檔，原因碼加 `mq_` 前綴，避免和其他整合來源的碼共用同一個鍵。`Exchange.available()`。`Exchange.request(acc, user, amount)` → ok, code, { state, coins }。`Exchange.tick(now)`：排隊重試，有一筆結束就標記 `points` 與 `exchange` 要重送。
- `Seasons.current()`、`Seasons.tick(now)`、`Seasons.previewLength(days)` → `{ endMs, nextStartMs }` 或 nil, code（新結算時刻至少在 24 小時後）、`Seasons.applyLength(days, actor)`、`Seasons.review()`、`Seasons.exclude(user, on, reason, actor)`、`Seasons.confirm(actor)`。
- `Boards.dirty(stat)`、`Boards.dirtyAll()`（`Config.apply`／`undo` 動到 `boards.*` 時呼叫：所有榜在接下來的 tick 重算，之後照新間隔排）、`Boards.tick(now)`（每 tick 最多重排一個榜）、`Boards.page(boardId, period, user, admin)`、`Boards.setHidden(user, on, reason, actor)`。
- `Balance.given(tid, now)`、`Balance.swapped(tid, now)`（換掉的那個樣板）、`Balance.done(tid, startMs, doneMs)`、`Balance.report(now)`：完成率＝done ÷（given − swaps），分母 0 時 `rate` 為 nil；每日樣板看近 7 天，每週樣板只看上一個已結束的週；(given − swaps) ≥ `Balance.MIN_GIVEN`（10）才給建議。
- `Report.add(field, key, n)`：今天那一列 `field += n`（key 不為 nil 時 `field[key] += n`）。`Report.seen(acc)`：`acc.seenDay` 不是今天時 `active + 1`。掛點：`Stats.add`、`hello` → `seen`；`Store.account` 建帳號 → `fresh`；`Quests` 產生每日（含全服、換來的）→ `dGiven`、每週 → `wGiven`，完成 → `dDone`／`wDone`，當天第一個每日完成 → `dPlayers`，`swap` → `swaps[tid]`；`Points.award`（`import` 除外）→ `pts[kind]`；`Exchange` 入帳 → `coins`；`Achievements` 非匯入解鎖 → `tiers`。全部 O(1)，換日時才重算 dayKey 並刪掉 30 天前的列。

### 5.9 Trackers、Towns（Catalog 擁有）

- `Trackers.install()`：在 `OnServerStarted` 掛事件與包裝原版動作的 `complete()`／`ISBuildIsoEntity:create`；原動作先跑，紀錄包在 `Trackers.guard`（pcall，每個掛點第一次出錯印一行 `[MinidoracatQuestFor42] Trackers: <掛點> failed: …`，記在 `Trackers.failed`）。42.21 封窗是建造實體（CraftRecipe 分類 `Barricades`），`ISBuildIsoEntity:create` 依分類記 `barricade.count` 或 `build.count`。每分鐘輪詢在線玩家（開車與步行里程、存活天數、城鎮、室內睡覺、新手「帶武器離開起始城鎮」）；一段里程換算的速度超過步行 0.5 km／分鐘或開車 4 km／分鐘就視為瞬移、整段不記。輪詢只處理 `imported` 的帳號、不建帳號：`hello` 的匯入要先安靜解鎖舊進度，先輪詢的話技能等級與存活天數會照一般解鎖（全服通知、本季積分）。
- `Towns.list()`、`Towns.at(x, y)` → townId 或 nil。

### 5.10 Hordes（Systems 擁有）

設定全在 `Config` 的 `hordes` 組（§3.4，`config.json` 一起同步），即時狀態在 `root.hordes`（§3.1）。

- 時段與擲骰（純函式，harness 用固定時鐘測）：時區用沙盒 `TimezoneOffset`（小時），不用經濟系統的換日。當地日 `d`（UTC＋tz 的日數）的時段 `ws = d × DAY − tz × HOUR + from`、`we = ws + 長度`（`to > from`：`to − from`；`to < from`：`to + 1440 − from`；相等：1440 分）。`Hordes.windowOf(cfg, d, tz)` → ws, we；`Hordes.window(cfg, now, tz)` → d, ws, we, K（找 d+1、d、d−1 中第一個 `ws − leadMin ≤ now < we` 的，晚的那天優先；K＝`ceil(長度 ÷ 1 小時)`），不在任何時段回 nil；`Hordes.slot(ws, we, k, leadMin)` → 第 k 格的開始 `S = ws + k 小時`、結束 `min(S + 1 小時, we)`、擲骰時刻 `S − leadMin`。
- `Hordes.roll(now, cfg, tz)`（每 tick）：`roll.day` 不是這個時段的日期就重設 `{ day, ws, slot = 0, n = 0 }`；同一天但時段開始（`ws`）變了（管理員改了 `from`）只把 `slot` 歸 0、`n` 保留，因為格數是從時段開始算的；擲骰時刻已到的格依序取走（`slot + 1`），下列情況跳過不擲：格已結束（停機錯過的小時不補擲）、`enabled` 關、沒有地點、已有 `cur`、`n ≥ maxPerDay`；否則 `ZombRand(100) < chance` 中了就在 `[max(S, now + leadMin), 格結束)` 挑整分鐘當開始時間（區間空的話不排）、`n + 1`。`Hordes.nextRoll(cfg, now, tz, roll)` → 下一次擲骰的時刻（管理頁），關閉或沒地點時 nil；它和 `horde.status` 用同一套重設規則看 `roll`，不改存檔。
- `Hordes.plan(cfg, startMs, actor)`：隨機地點、隻數在 `count` 範圍、`Hordes.mix(kinds, count)`（已登記且權重 > 0 的種類，先取整再把餘數一隻一隻給權重大的，同權重依 id；沒有可用權重時全是 vanilla）、複製設定，`announceAt = startMs − leadMin`，`state = "planned"`。`actor` nil＝自動。
- `Hordes.tick(now)`（`OnTickEvenPaused`，每秒最多一次）：Store 就緒後第一個 tick 跑 `Hordes.boot`（`cur` 是 `active` → 失敗 `restart`；殭屍留在世界上變一般殭屍），之後 `roll` 再 `step`：
  - `planned`：到 `announceAt` → `announced`，全服通知 `soon`；已經到 `startMs`（預告 0 分或手動）→ 直接 `waiting`，通知 `open`。
  - `announced`：到 `startMs` → `waiting`。
  - `waiting`：到 `expireAt` → 失敗 `nobody`；有身分通過的在線玩家在地點 50 格內（2D，`Hordes.RANGE`）→ 每個種類 `pcall(kind.spawn, x, y, z, n)`，只收 `instanceof(z, "IsoZombie")`、每種最多 n 隻，記進 `Hordes.live[z] = { horde, onlineId }`（只在記憶體）。收到 > 0 隻 → `active`（`spawnAt`、`endsAt`），通知 `spawn`；0 隻 → `tries + 1`，第 10 次（`Hordes.MAX_TRIES`）失敗 `spawn`。
  - `active`：活著＝這場的 `live` 項目裡 `onlineId` 還是生成時那個（不是 −1：`removeFromWorld` 會把它設成 −1；物件被引擎重用時會拿到新的）且 `not isDead()` 的；其餘從 `live` 拿掉（被引擎收起來的不追，變一般殭屍）。不看 `isExistInTheWorld()`：專用伺服器上剛生成的屍潮殭屍，所在格子的 moving objects 不列它，生成後 0～1.5 秒都是 false（E2E `quest-hz-1026e`）；第一版有這項，每一場都在下一個 tick 判成功、0 擊殺（`quest-hz-1026c`／`d`）。也不看 persistent outfit id：沒給外觀名稱生成的殭屍被標記「之後隨機穿衣」（`LuaManager.java:10661-10665`），穿上時會換 id。更新 `left`；活著 0 隻且 50 格內有玩家 → 成功；到 `endsAt` → 失敗 `time`。
- `Hordes.onZombieDead(z)`（自己的 `OnZombieDead`，Trackers 照樣記一般擊殺）：`live[z]` 存在就拿掉（同一隻的第二次事件因此不算），還是同一隻時 `killed + 1`、`left − 1`；`getAttackedBy()` 是 IsoPlayer 時 `Identity.principal` 的帳號 `kills + 1`。燒死等沒有攻擊者的算清掉、不算任何人的擊殺。
- `Hordes.finish(result, why, now)`：成功時參加者（擊殺 ≥ 1）各得 `share`：`max(1, floor(pool × n ÷ 有歸屬的擊殺總數 + 0.5))`、`each`：整個 `pool`（`pool = perZombie × spawned`；`pool` 為 0 時不發積分），`Points.award(…, "horde", "horde:<id>")`、`Stats.add(user, "horde.wins", 1)`、個人通知 `hordePaid`。`active` 時失敗 → 先拿掉 `live` 項目再對還活著的呼叫 `Hordes.clearZombie(z)`（`removeFromWorld` + `removeFromSquare`，唯一的清除函式；清除不算擊殺）。全服通知結果、事件記錄 `horde`、寫進 `log`、`cur = nil`。
- 每次狀態改變、擊殺、`left` 改變、結束都 `Sync.dirty(nil, "hordes")`。
- 種類：`Hordes.kinds[id] = { id, nameKey, spawn = fn(x, y, z, n) → ArrayList | Lua 陣列, modId? }`。內建 `vanilla`（`addZombiesInOutfitArea(x−5, y−5, x+5, y+5, z, n, nil, 50)`）與 `runner`（同上，再對每隻 `doSprinter()`；不用 `doZombieSpeed(1)`，它會擲骰），鍵 `IGUI_MQ_Horde_Kind_<id>`。`Hordes.registerKind(spec)`＝facade `registerHordeKind`（§8）。`Hordes.kindList()` → `{ { id, nameKey, builtin } }`，內建依 `Contract.HORDE_KINDS`，其餘依 id。
- `Hordes.stateHordes(acc, user, now)`：Sync provider `hordes`，見 §6.3。

## 6. 網路協定

模組名 `MinidoracatQuest`。客戶端 `sendClientCommand(player, "MinidoracatQuest", cmd, args)`，`args.protocol = 1`，mutation 另帶 `requestId`（8～64 字 `[%w_-]`）。

### 6.1 客戶端 → 伺服器

| cmd | kind | 欄位 | 伺服器回應 |
|---|---|---|---|
| `hello` | query | — | `catalog`、`state`、`titles { full, map }`；其他人收到 `titles { u, t }` |
| `watch` | query | `on: bool` | 開著視窗才收 `delta` |
| `track` | query | `on: bool` | 追蹤面板開著：視窗關著也收追蹤中的進度 |
| `pin` | mutation | `id: text`、`on: bool` | `result`＋`state`；`BAD_ARGS`（不能追蹤的項目）、`TOO_MANY_PINS` |
| `seen` | mutation | — | `result`；`unseen` 歸零 |
| `swap` | mutation | `slot: int`（1～3） | `result`＋`state` |
| `prefs` | mutation | `themes: str`（逗號分隔，最多 3 個） | `result`＋`state` |
| `title` | mutation | `id: str?`（空＝不用） | `result`＋`state`；所有人收到 `titles { u, t }` |
| `anon` | mutation | `on: bool` | `result`＋`state` |
| `board` | query | `board: str`、`period: str` | `board` |
| `records` | query | — | `records` |
| `exchange` | mutation | `amount: int` | `result`（含 `state`＝`paid`／`queued`／`refunded`、`coins`）＋`state` |
| `admin` | 依 op | `op: str`＋該 op 的欄位 | `admin` |

錯誤碼（`Contract.CODE`，客戶端用 `IGUI_MQ_Code_<CODE>`）：`OK`、`PROTOCOL_MISMATCH`、`BAD_ARGS`、`IDENTITY_UNVERIFIED`、`NOT_READY`、`FORBIDDEN`、`RATE_LIMITED`、`NO_SWAPS`、`BAD_SLOT`、`BAD_THEME`、`TOO_MANY_PREFS`、`TOO_MANY_PINS`、`TITLE_LOCKED`、`EXCHANGE_OFF`、`EXCHANGE_MIN`、`EXCHANGE_DAY_LIMIT`、`NOT_ENOUGH_POINTS`、`ECONOMY_MISSING`、`BAD_BOARD`、`BAD_CONFIG`、`BAD_SEASON_LENGTH`、`TOO_SOON`、`NOT_FOUND`、`FILE_ERROR`、`INTERNAL`、`HORDE_BUSY`、`NO_SPOTS`。

### 6.2 管理 op（`admin = true`，mutation 都寫稽核與事件記錄）

| op | 欄位 | 回應 data |
|---|---|---|
| `cfg.get` | — | `overrides`、`rev`、`history`（id、時間、操作者、摘要）、`file`（`config.json` 的同步狀態，同 `status.json`）、`dir`（設定檔資料夾，`Zomboid/Lua/` 底下的相對路徑，變更紀錄頁顯示） |
| `cfg.preview` | `changes: json` | `rows = { { path, before, after } }`、`ok` |
| `cfg.apply` | `changes: json`、`summary: text` | `historyId`、`rev` |
| `cfg.undo` | `historyId: int` | `historyId`、`rev` |
| `diff.preview` | `preset: str`、`mult: num?` | `changes`、`rows`、`estimate` |
| `season.preview` | `days: int` | `endMs`、`nextStartMs` |
| `season.apply` | `days: int` | `endMs` |
| `season.review` | — | `state`、`frozenAt`、`rows = { { rank, user, pts, anomalies, excluded, reason } }` |
| `season.exclude` | `user: str`、`on: bool`、`reason: text?` | — |
| `season.confirm` | — | — |
| `event.add` | `name: text`、`theme: str`、`mult: num`、`startMs: num`、`endMs: num` | `id` |
| `event.remove` | `id: int` | — |
| `ex.status` | — | `enabled`、`rate`、`perDay`、`todayCoins`、`estimate`（今天以前 7 個日曆天的平均，沒兌換的日子算 0；這 7 天都沒有兌換時用今天的量；乘上未來 24 小時最高的活動倍率）、`ecAvailable`、`ecCap`（拿不到為 nil） |
| `anom.list` | `days: int` | `rows = { { at, user, stat, n, ceil } }` |
| `acct.view` | `user: str` | 帳號摘要（三個積分、成就數、異常數、隱藏狀態） |
| `achv.revoke` | `user: str`、`achId: str`、`tier: int`、`reason: text` | — |
| `board.hide` | `user: str`、`on: bool`、`reason: text?` | — |
| `balance.report` | — | `rows = { { tid, given, done, swaps, rate, medianMin, suggest } }`（`rate` 不算換掉的，分母 0 時 nil）、`minGiven` |
| `report.get` | `days: int`（7 或 30） | §6.5 |
| `report.export` | — | `path`（`Zomboid/Lua/` 底下的相對路徑）；寫不出來回 `FILE_ERROR` |
| `towns.here` | — | 管理員目前座標與所在城鎮（加自訂城鎮用） |
| `horde.status` | — | `cur`（完整的 `cur`，含 `planned`、`count`、`mix`、`kills`）、`roll = { day, slot, n, max, nextAt, enabled }`（照 `Hordes.roll` 的重設規則顯示：時段換了日期時 `slot`、`n` 為 0，時段開始變了時 `slot` 為 0）、`log`（最近 10 筆，新的在前）、`kinds = { { id, nameKey, builtin } }` |
| `horde.now` | — | `id`；已有一場 `HORDE_BUSY`、沒有地點 `NO_SPOTS`。開始時間＝現在、立刻通知 `open`，不算進 `roll.n`；歷史 `horde.now <id> <name>`（不能復原） |
| `horde.stop` | `id: int` | —；不是目前那場 `NOT_FOUND`。`planned`／`announced` → 取消（預告過才通知 `cancel`）；`waiting` → 失敗 `admin`；`active` → 失敗 `admin` 並清掉剩下的；歷史 `horde.stop <id> <name>`（不能復原） |

自訂成就、自訂城鎮、任務池、每週任務、共同目標、連續獎勵、兌換設定、廣播設定、稱號顯示（`titles.head`、`titles.chat`），都是 `cfg.preview`／`cfg.apply` 的路徑。

### 6.3 伺服器 → 客戶端

- `result`：`{ ok, code, command, requestId, … }`。
- `catalog`：`{ rev, overrides = { achievements = {…}, daily = {…}, weekly = {…}, streak = {…}, rewards = {…}, exchange = {…} }, custom = { … }, packs = { … }, towns = { … } }`。客戶端拿 shared Catalog 的預設合併。
- `state`：

```lua
{ v = 1, user, admin, now, dayKey, resetAt, weekKey, weekResetAt,
  points = { season, total, balance },
  day = { quests = { … 4 個 Quest＋ptsNow }, swaps, done, sharedDone },   -- ptsNow：進行中＝基礎分 × 現在的活動倍率；完成＝got（客戶端沒有這欄就顯示 pts）
  week = { quests = { … 3 個，同上 }, goalPart },
  goal = { stat, target, progress, minContrib, pts, endsAt, reached } | nil,
  streak = { days, graceUsed, week = { 7 個 "done" | "grace" | "miss" | "" }, today = 1..7（週一＝1，`Clock.weekday`；客戶端金圈標示）, next = { days, pts } | nil },
  newbie = { steps = { … 5 個 bool }, pts } | nil,
  achv = { [achId] = tier }, titles = { titleId… }, title, prefs = { … }, anon,
  season = { no, startMs, endsAt, state },
  exchange = { available, enabled, rate, perDay, used, min, queued, hist },   -- hist：排隊中的（新的在前，at＝申請時間）接著 ex.log，合計最多 10 筆；兌換頁的「兌換紀錄」
  events = { { name, theme, mult, endsAt } },
  hordes = { cur = HordeView | nil, last = HordeLast | nil },   -- §5.10
  unseen,
  pins = { … }, trk = { [achId] = { t, v } } }     -- 追蹤面板（§5.6）
```

- `delta`：`{ day = { [i] = { prog, state, ptsNow } }, week = { [i] = { prog, state, ptsNow } }, goal = { progress, reached }, points = { … }, unseen, trk = { … }, pins = { … }, hordes = { cur, last } }`，只帶有變的欄位（`ptsNow` 只在完成時帶 `got`；活動開始或結束時 `Quests.watchEvents` 讓開著視窗的人收到完整 `state`）。只開追蹤面板的人不收 `goal`、`points`；`hordes` 兩種人都收。
- `HordeView`（`planned` 時不給玩家）：`{ id, name, town, x, y, z, state, kinds = { { id, nameKey } }, announceAt, startMs, expireAt, endsAt, spawned, left, killed, pool（生成後才有：perZombie × spawned）, perZombie, split, limitMin, mine（我的擊殺） }`，不帶隻數。`HordeLast`：最新一筆 `log`，結束後 10 分鐘內（`Hordes.LAST_MS`；預告前就取消的不給）：`{ id, name, town, state, why, endedAt, spawned, killed, pool, split, mine, got（我拿到的積分，沒參加為 nil） }`。
- `titles`：`{ full = true, map = { [user] = titleId } }`（登入時，在線玩家）或 `{ u, t }`（一人換了稱號或剛登入；`t` 為 nil 表示不戴）。
- `toast`：`{ kind = "achv", id, tier, pts }`、`{ kind = "achvMany", ids = { … 最多 3 }, n }`、`{ kind = "quest", tid, target, pts }`、`{ kind = "week", tid, target, pts }`（帶 `target`：視窗關著時客戶端的任務清單是登入時的快照，跨日後查不到新任務）、`{ kind = "goal", stat, pts }`、`{ kind = "streak", days, pts }`、`{ kind = "newbie", pts }`、`{ kind = "exchange", state, coins }`、`{ kind = "season", no, rank, pts }`、`{ kind = "broadcast", who, a, id, tier, titleId }`（`who` 為匿名時是 nil；`a` 是匿名者的帳號，只在送給管理員的那份，客戶端顯示「名字（匿名）」）。
- 屍潮通知：全服 `{ kind = "horde", ev, id, name, town, … }`，`ev`：`soon`（`startMs`、`kinds = { { id, nameKey } }`，不帶隻數）、`open`（同 `soon`；預告 0 分或手動開始）、`spawn`（`endsAt`、`limitMin`、`spawned`、`pool`、`split`）、`win`（`spawned`、`killed`、`pool`、`split`、`n`＝參加人數）、`fail`（`why`、`left`）、`cancel`（只在預告過的場次）。個人 `{ kind = "hordePaid", id, name, town, pts, kills, pct }`（`pct` 只在 `share`）。
- `board`：`{ board, period, status = "ok", season = { no, endsAt }, rows = { { r, n, a, v, t, d } … ≤ 50 }, me = { r, v, d } | nil, count }`。`n` 是名字（匿名時 nil，客戶端顯示「匿名倖存者」），`a` 是匿名那一列的帳號（只送給管理員，客戶端顯示「名字（匿名）」），`t` 稱號 id（匿名那一列只送給管理員：同一個稱號在頭上與聊天認得出是誰），`d` 名次變化（正＝上升，nil＝新上榜）。
- `records`：`{ rows = { { stat, season, life, total } … }, points = { season, total, balance } }`。客戶端不列沒有定義的統計（pack 移除後留下的 id）。
- `admin`：`{ op, ok, code, … }`。

### 6.4 單機

- `Net.send` 在 SP 直呼 `MinidoracatQuest.Client.receive(cmd, payload)`；客戶端的 `OnServerCommand` 處理函式也呼叫同一個 `receive`。
- 客戶端第一次送 `hello` 要等到 `OnGameStart` 之後的第一個 `OnTick`。

### 6.5 報表（`report.get`／`report.export`）

- 帳號快照：`report.get`／`report.export` 遇到沒有快照或快照超過 5 分鐘時，開始一輪走訪（`Report.start`），`OnTickEvenPaused` 每 tick 走一張分表，16 tick 後一次回覆所有等待中的請求（`Server.LATER`）；5 分鐘內的請求直接用快照。快照同時算 7 天與 30 天兩個窗：窗內有活動的帳號是 `seenMs` 在窗內或 `seenDay` ≥ 窗的第一天。
- `report.get` 回覆：

```lua
{ days, at,                                   -- at：快照時間
  rows = { { day, active, fresh, dGiven, dDone, dPlayers, wGiven, wDone, swaps, pts, coins, tiers } },  -- days 列，舊的在前，最後一列是今天；swaps、pts 是當天合計
  sum = { fresh, dGiven, dDone, dPlayers, wGiven, wDone, coins, tiers, swaps, pts,
          swapsBy = { tid = n }, ptsBy = { kind = n },
          dRate,                              -- dDone ÷ (dGiven − swaps)，分母 0 時 nil
          wRate },                            -- 只算已結束的週（7 天窗 1 週、30 天窗 3 週）的 wDone ÷ wGiven
  snap = { active, none, tierSum, streak7, exPlayers,   -- 窗內有活動的人數、其中沒有任何成就的、已解鎖級數合計、連續 ≥ 7 天、窗內兌換過的人
           unspent, holders, top10 },         -- 全部帳號：餘額合計、餘額 > 0 的人數、前 10 %（無條件進位）持有的比例
  achv = { { id, hidden, c = { n1, n2, … } } } }        -- 每個有效成就；c[k]＝窗內到第 k 級以上的人數；最高級人數多的在前
```

- `report.export` 寫 `Zomboid/Lua/MinidoracatQuest/<serverKey>/report-YYYY-MM-DD.json`（和 `config.json` 同一個資料夾，一天一個檔，同一天再匯出就覆寫），只有總數，沒有玩家名稱或帳號：

```lua
{ at, day, days = 30,
  daily = { { day, active, fresh, dGiven, dDone, dPlayers, wGiven, wDone, coins, tiers, swaps = { tid = n }, pts = { kind = n } } },
  sum = { … 同 report.get },
  players = { active7, active30, noAchv, tierSum, streak7, exchanged },
  achv = { [achId] = { n1, n2, … } },
  points = { unspent, holders, top10share },
  quests = { [tid] = { given, done, swaps, rate } } }   -- Balance.report 的窗（每日 7 天、每週上一個已結束的週）
```

## 7. 客戶端

- 接 UI 框架：`require "MinidoracatUI/V1"`，`MIN_REV = 22`，逐項探 `CAPABILITIES`（`window`、`controls`、`navList`、`scrollPanel`、`table`、`virtualList`、`tileGrid`、`toast`、`dock`、`dialog`、`dropdown`、`textWrap`）。缺框架或版本不足時只用 `HaloTextHelper` 顯示通知、視窗不開，不 error。
- Dock：`{ id = "quest", order = 70, icon = "media/ui/MinidoracatQuest/dock_trophy.png", iconKey = …, bind = "MinidoracatQuest_Toggle", getBadge = unseen }`。
- 視窗：左側 NavList `Window.nav`（每日任務、每週任務、成就、排行榜、我的紀錄、兌換（只在 `state.exchange` 可兌換或 `hist` 有資料時，spec 的 `shown`）；分隔後：設定）；管理（只有 `state.admin`）是另一個 NavList `Window.navAdmin`，貼在左欄底部（`Window.placeNav`：y＝max(`nav` 底＋`ADMIN_GAP` 12 px, 視窗高－自身高－6)，視窗版面或列出的頁面一變就重放；UI 框架的 NavList 沒有置底，所以分成兩個）。非管理員時隱藏。兩個清單只有一個有選取：`Window.select` 把頁面 id 設給擁有它的清單、另一個清掉（`setSelected(nil, true)`），兩個清單的 onSelect 都走 `Window.select`。右側內容；不透明視窗。列出的頁面一變（`Window.syncNav` 比對列出的頁面 id）就重建兩個 NavList，目前那頁不再列出時回到每日任務。預設大小＝內容寬（螢幕寬一半，夾在 640～1000 px）＋NavList 寬、高為螢幕高 82 %（460～1000 px），都不超過螢幕減 40 px（`Window.defaultSize`）；玩家拖過的大小由 ISLayoutManager 記住，大小和預設不同時標題列出現「重設大小」，按下回到預設大小並置中。
- 導覽的鍵盤與手把：NavList 到邊時 `onFocusKey` 回 false，Focus 引擎對鍵盤就停在原地，所以 `Window.lua` 只在這兩個實例上包 `onFocusKey`：`nav` 最後一列按下 → `Focus.focusControl(navAdmin)` 並停在它的第一列，`navAdmin` 第一列按上 → 回到 `nav` 最後一列；手把方向也先問同一個 `onFocusKey`（`Focus.onJoypadDir`）。`navAdmin` 隱藏（非管理員）時照原本行為。
- 頁面資料來源：每日／每週／成就／我的紀錄（積分卡）／兌換用 `state`；我的紀錄表格送 `records`；排行榜送 `board`（狀態機 loading → ready／empty／error，5 秒逾時）；設定頁送 `prefs`／`title`／`anon`。兌換頁的「兌換倖存幣...」開兌換視窗（`ExchangeDialog`），使用者 2026-10-24 要求兌換與兌換紀錄從我的紀錄分出來。
- 設定頁最後一段「各主題的任務」（預設收起）：`Client.questList()` 從 shared Catalog＋`catalog` 推送算出啟用的每日與每週樣板、乘過難度的目標範圍（和 `Quests` 的 `rollTarget` 同一捨入）與積分，不另送資料：預設值本來就在每個客戶端，`catalog.overrides` 也送給所有玩家，伺服器擋了也藏不住。`state.admin` 或 `quests.playerList` 為 true 才列出；設定關著時管理員看到的那段附註「只有管理員看得到」。套用設定後伺服器重送 `catalog`，清單跟著更新。
- 開視窗送 `watch {on=true}`，關視窗送 `{on=false}`；打開每日頁或成就頁時送 `seen`。
- 追蹤面板（`Hud.lua`）：`ISPanel` 衍生、放在最底層（`backMost`：每次 UI 更新引擎都把它移到最底，`UIManager.java:562-568`），所以每個視窗都蓋在它上面，包括比它早建立的物品欄與上次沒關的角色視窗，拖曳時 `ISPanel` 的 `bringToTop` 也一樣；用頁面同一套 canvas 指令繪製（`Draw.renderOps`），資料一變才重排，`render` 只走指令列。預設在原版左側欄右邊（`getPlayerData(0).equipped` 的右緣＋12），會碰到原版物品欄的標題列時（物品欄看得到、左右重疊、物品欄的 y 在面板標題列底線之上）改放在物品欄標題列下面 6 px；拖過的位置與收合狀態用 `ISLayoutManager` 記在 `layout.ini`（拖完或收合就寫）。顯示條件：MOD 選項開、有追蹤項目、角色活著、沒按 V（`ISUIHandler.allUIVisible`）、Esc 選單沒開；任務視窗開著也照樣顯示（使用者 2026-10-24：按「追蹤」要馬上看到），視窗蓋在它上面。每 500 ms 與資料變動時檢查，介面被藏起來時不自己出現。`hello` 時面板開著就送 `track {on=true}`，選項切換時送 on／off。卡片上的「追蹤」chip 送 `pin`；滿 5 個時其他 chip 停用並以 tooltip 說明。
- 稱號（`Titles.lua`）：`titles` 推送存成 `byUser`。聊天：檔案載入時包住 `ISChat.addLineInChat`（原版在 `OnGameStart` 才把它掛到 `OnAddMessage`，`ISChat.lua:1176`），作者戴著稱號時把訊息換成代理，`getTextWithPrefix()` 在 `[作者]` 後面插入 ` <SPACE> <PUSHRGB:…> 「稱號」 <POPRGB> `（稱號裡的 `<`、`>` 先轉成 `&lt;`、`&gt;`），其他方法轉給原訊息。頭上：每 500 ms 從 `getOnlinePlayers()` 挑 40 格內、有稱號、活著、不在車上的玩家；`OnPreUIDraw` 每幀照原版規則（`IsoGameCharacter.renderlast`／`updateUserName`）檢查後在名字上方一行畫字（黑色陰影＋金色）。兩者都只在多人、伺服器開關 `titles.head`／`titles.chat` 與玩家 MOD 選項都開時生效。
- 屍潮（伺服器見 §5.10）：管理「屍潮」分頁（`AdminHordes.lua`，排在「城鎮」後面）的狀態來自 `horde.status`，切進分頁、每次操作後與按「重新整理」時讀；設定全走變更草稿與底部「套用」。種類是清單框：比例大於 0 的種類一列（名稱、比例欄、移除；移除內建種類寫 0，其他種類刪鍵、送 `del`，只在草稿裡的（剛加入、還沒套用）從草稿拿掉，不送空變更），其餘已登記的種類在框下的下拉選單（選了草稿寫 10），套用的設定裡有、`horde.status` 沒列出的鍵標「未安裝」、可移除（`del`）；比例寫在 `hordes.kinds.<id>`，維持預設值的欄位不寫成變更；`horde.now`／`horde.stop` 先確認、按下就生效（像限時活動）。追蹤面板最上面一列是屍潮（預告、等人到場、進行中），不算 5 個追蹤名額、沒有 ×，沒有追蹤項目時有屍潮也顯示，倒數只在文字變了才重排。每日頁在限時活動下面放屍潮橫幅（預告、等人到場、進行中，結束後 10 分鐘內的成功／失敗／取消），這頁 30 秒才重畫，所以剩餘時間以分鐘計。`delta.hordes` 走通用的整份取代。`HordeMap.lua`：裝了小地圖才作用，地點前後左右各 10 格一塊區域加一個標記，資料變了才重建、其餘時候回同一張表；檔案載入時與 `OnGameStart` 各試一次註冊。
- 清單框（設計稿 r11，使用者 2026-10-26 選「原版管理員清單」樣式）：管理頁與玩家頁的清單都畫成原版管理員清單（`ISSafehousesList.lua:23-31`、`:67-82`）的樣子：直角的 `surface` 底、`border` 外框、表頭帶（`border` 透明度 × 0.3，下緣一條線）、條目之間一條線（× 0.9），沒有斑馬紋。管理頁用 `Flow:list`／`listHead`／`item`／`listEnd`（`AdminPanel.lua`）：框內 `F.ox`／`F.width` 換成框的，各頁的欄位算式不變，自己放位置的按鈕要加 `F.ox`；框由頁面 ScrollPanel 的 prerender 在所有子元件底下畫（`A.paintLists`，內容座標，不配置），不是元件，不擋按鈕，ui-mp 的版面檢查也看不到；沒關的框不畫。玩家頁用 Builder 的 `b:list`／`listHead`／`listSep`／`listEnd`（`Draw.lua`），底色指令先記下、`listEnd` 才補高度。

## 8. facade `MinidoracatQuest.v1`（伺服器）

`{ API_MAJOR = 1, API_REVISION = 2, registerPack(spec) → pack | nil, code, registerHordeKind(spec) → true | nil, "invalid_args" }`，`pack.add(player, statId, n) → true | false, code`。規則照設計稿：`modId` 為 `[A-Za-z0-9_-]` 最長 64；每個 MOD 統計 ≤ 32、成就 ≤ 64；每個 modId 每 tick 50 次；`n` 是 0～1000 的有限數；錯誤碼 `invalid_args`、`rate_limited`、`not_ready`。統計與成就 id 自動加 `<modId>:`；`board = true` 的統計進「職業」榜。

`registerHordeKind`（rev 2）：`spec = { modId, id, nameKey, spawn }`；`modId` `^[%w_%-]+$` ≤ 64、`id` `^[%w_%-]+$` ≤ 32、`nameKey` `^[%w_]+$` ≤ 128、`spawn(x, y, z, n)` 是函式，回傳 ArrayList 或 Lua 陣列；鍵 `<modId>:<id>` 最長 64（`hordes.kinds` 權重鍵的上限）；每個 modId ≤ 8 種、全部外掛 ≤ 32 種；同一個鍵再登記就取代。Quest 管時間、計數與清除；`spawn` 在 pcall 裡呼叫，只收真的 IsoZombie。登記後 `hordes.kinds.<modId>:<id>` 預設權重 0。消費者用 `type(v1.registerHordeKind) == "function"` 探測。

## 9. 沙盒選項（頁 `MinidoracatQuest`）

| 選項 | 型別 | 預設 | 用途 |
|---|---|---|---|
| `TimezoneOffset` | integer -12～14 | 8 | 沒裝經濟系統時的換日與顯示時區 |
| `ResetHour` | integer 0～23 | 0 | 沒裝經濟系統時的換日時刻（當地時間） |
| `AdminRoles` | string | `admin` | 可以開管理面板的角色名，逗號分隔 |

其餘都在管理面板改（存在 `config`）。

## 10. 翻譯

- 鍵前綴 `IGUI_MQ_`；沙盒 `Sandbox_MinidoracatQuest_*`。
- 平行開發期間，各切片不直接改 `Translate/`：把自己的鍵寫在 repo 根目錄 `temp/i18n/<切片>.json`（`{ "<key>": { "EN": "…", "CH": "…" } }`），由整合者合併進 16 個資料夾。合併後 `Translate/` 是唯一真相，`temp/i18n/` 刪除。
- 繁中用台灣用語、原版譯名（技能名、職業名照原版 CH）。`%1`～`%9` 佔位、字面 `%` 寫 `%%`。

## 11. 效能預算

- 每 tick：榜單最多重排一個；`Sync.tick` 每秒最多送一次；`Exchange.tick` 每小時；輪詢每分鐘、每 tick 最多處理 8 位在線玩家。
- 客戶端每幀：追蹤面板只走排好的繪製指令；頭上的稱號只處理每 500 ms 挑出的候選人（每人幾次引擎查詢與兩次 `DrawStringCentre`）。實測（2026-10-24 E2E `title-mp --define perf=1`，畫面上 1 位戴稱號的玩家、GameProfiler 開關各 5 段 15 秒）：重畫介面的那幾幀多約 0.05 ms，攤到每幀約 0.013 ms；整幀時間的差距小於段與段之間的雜訊。
- 封包：`board` ≤ 約 4 KB；`state` ≤ 約 8 KB；`catalog` ≤ 64 KB（自訂成就多時分頁送）。所有清單都有列數上限。
- `Stats.add` 是熱路徑：不建 table、不組字串（稽核路徑除外）。報表掛點只比較快取的 dayKey 與加數字；只有開報表時才走訪帳號，一 tick 一張分表。

## 12. 測試

- 離線：`scripts/smoke_harness.lua` 照 Safehouse 形狀（`scripts/harness/env.lua`、`modules.lua`、`t_*.lua`）。每個伺服器模組至少一個情境，安全邊界要有反面斷言（不能加進度、非管理員被擋、超量被丟、身分不符被擋）。
- 實機：`pz-family-docs/e2e/MinidoracatQuestFor42/scenarios/`。至少：`quest-mp`（擊殺與製作推進每日任務、換任務、連續天數）、`achv-mp`（解鎖、通知、全服通知）、`board-mp`（兩個客戶端、名次、冷卻）、`exchange-mp`（帶 Economy、排隊與入帳）、`admin-mp`（門檻改動預覽、套用、復原、賽季改長度）、`ui-sp`（單機開視窗各頁截圖）。

## 13. 實作定案（和前文不同時以本節為準）

| 項目 | 定案 |
|---|---|
| 未知指令 | 回 `BAD_ARGS` |
| `Sync.provider(part, fn)` | `fn(acc, user, now)` 回傳 `state` 的該欄位；沒登記的欄位省略 |
| `catalog.overrides` | 送整份 `config.overrides`（含 `difficulty`） |
| 任務目標區間 | 一律陣列 `{ min, max }`（樣板與 `daily.pool`／`weekly.pool` 同形狀） |
| mutation 回覆 | 玩家 mutation 成功時 Server 先送 `result` 再送 `state`；query 成功不送 `result`，只送該查詢的推送 |
| Core 額外函式 | `Config.addHistory(actor, summary, changes, undoable)`、`Audit.recent(filter, max)`、`Sync.dirty(nil, part)`（所有開著視窗的人）、`Sync.broadcastToast(t, achiever)`、`Store.serverKey/path/writeLines/readLines`、`Clock.dayStartMs/shiftMs/civil` |
| `Boards.profileChanged(user)` | `anon` 或 `title` 改變後 Server 會呼叫；空操作。榜單快取只存帳號、數值與名次，`Boards.page` 送出每一列時即時讀該帳號的 `anon`／`title`，所以下一次 `board` 回覆就是新名字與稱號，不用重算。管理員隱藏仍走 `Boards.setHidden` → `dirtyAll` 重算 |
| 新手欄位 | `Store.account(user, true)` 建帳號時，`newbie.enabled` 沒關就一起建 `newbie` |
| facade 分類 | pack 成就的 `life` 歸到 `job`；pack 任務主題不在 11 個主題時設 nil |
| facade 發布 | 全部伺服器模組的全域表都在才賦值 `v1` |
| `AdminRoles` | 逗號或分號分隔 |
| 賽季 `endMs` | `Store` 建表時留空，由 Seasons 計算 |
| 技能 | 42.21.0 可升級技能 35 個；技能類成就＝35 個技能＋技能總等級＋累計經驗 |
| 賽季稱號 | id `s<季數>_<kind>`（kind：`top1`、`top3`、`top10`、`first_<boardId>`），鍵 `IGUI_MQ_Title_season_<kind>`（`%1`＝季數） |
| 任務類統計 | 由 Systems 記錄，每分鐘上限 1000 |
