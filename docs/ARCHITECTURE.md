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
| `lua/server/MinidoracatQuest/Hordes.lua` | Systems | 限時屍潮：時段與每小時擲骰、排定、預告、開始前提醒、生成、擊殺歸屬、清除、發積分、參加統計、最近場次、管理 op `horde.*`、種類登記（§5.10） |
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
             roll = { [rollKey] = { day, ws, slot = 0 } },  -- 每個時段一份；rollKey＝Hordes.winKeys(windows) 的第 i 個：winKey（from .. "-" .. to .. "-" .. days），完全相同的時段第 2、3…個加 "#2"、"#3"，各有自己的格與機率；day：時段所屬的當地日期 "YYYY-MM-DD"；ws：那天時段的開始 ms；slot：已擲過的小時格數；設定裡沒有的鍵在下次擲骰時拿掉
             perDay = { [day] = n },         -- 每個當地日期自動排了幾場（所有時段一起算），只留最近 3 天；舊版的單一 roll { day, n } 開服時搬進來
             cur = nil,                       -- 同時最多一場，形狀見下
             log = { } },                     -- 結束的場次，新的在後，最多 20 筆（形狀見下）
}
```

屍潮 `cur`（排定時從時段（或「開一場」）與它的方案複製設定，之後改設定不影響這場）：

```lua
{ id, auto = bool, actor = user | "auto", name, x, y, z, town = townId | nil,   -- town：排定時的 Towns.at
  state = "planned" | "announced" | "waiting" | "active" | "rest",
  announceAt, startMs, expireAt (= 這一波等人的期限：第 1 波 startMs + waitMin，之後每波＝休息結束 + waitMin), reminded = bool,
  preset,                                     -- 方案名稱字串（排定時的 name；預設方案是 ""），管理頁狀態列顯示
  waves = { { base, perPlayer } }, wave = 1,                 -- wave：目前（或下一個）波次，從 1 起
  weights = { [kindId] = 權重 }, points = { [kindId] = 每隻積分 }, hp = { [kindId] = 耐打倍率 },   -- hp 缺的種類＝1
  cap, limitMin, waitMin, restSec, maxAlive,  -- waitMin：時段或「開一場」的等人分鐘；其餘來自方案
  -- 目前這一波
  size, queued, spawned, left (= 活著 + queued), killed,
  mix = { { kind, n, nameKey } }, queue = { [kindId] = 還沒生成的隻數 }, angle, endsAt, nextAt, tries,
  -- 整場
  firstSpawnAt, totalSpawned, totalKilled, cleared, kills = { [user] = n },   -- kills：整場（含失敗那一波）
  waveGot = { [user] = pts }, waveKills = { [user] = n },   -- 這一波的擊殺價值與擊殺數，清光才併進 got／gotKills
  got = { [user] = pts },                     -- 清光的波次的擊殺價值（發獎依據，未套上限）
  gotKills = { [user] = n } }                 -- 清光的波次的擊殺數（hordePaid 通知的 kills）
```

開服第一個 tick（`Hordes.boot`）`cur` 沒有 `waves`（0.2.0 排定的）就補成新形狀：一波 `max(1, count)` 隻、`perPlayer = 0`，`weights` 取自舊 `mix` 的隻數，`points`／`cap`／`restSec`／`maxAlive` 等沒複製到的值取 `Hordes.presetOf(目前設定, "default")`，`hp = {}`，`totalSpawned`／`totalKilled`／`firstSpawnAt` 取舊的 `spawned`／`killed`／`spawnAt`，拿掉 `count`、`perZombie`、`split`、`spawnAt`，標 dirty，照常進行。補好之前 `Hordes.stateHordes` 不送沒有 `waves` 的 `cur`。

`log[i]`：`{ id, auto, name, town, state = "success" | "failed" | "cancelled", why, startMs, spawnAt (= firstSpawnAt), endedAt, waves (= 波數), cleared, spawned (= totalSpawned), killed (= totalKilled), pool, capped, paid = { [user] = pts }, kills = { [user] = n }, announced = bool }`。`why`：失敗是 `time`（這一波時限到）、`nobody`（這一波 `expireAt` 前沒人到 30 格內）、`admin`（管理員停止）、`restart`（進行中時伺服器重開）、`spawn`（這一波連續 10 批生成 0 隻、一隻都沒出來）；取消一律 `admin`。`announced = false` 是預告前就取消的場次，玩家看不到。玩家的屍潮任務頁從這裡讀最近 10 場（`Hordes.recent`）。改版前的舊紀錄（沒有 `waves`）載入時由 `Store` 的 `fillRoot` 補成新形狀：`waves = 1`、`cleared` 成功是 1 否則 0、`pool`＝`paid` 的總和（實際發出的）、拿掉 `split`；沒有 `capped`。殭屍物件只在記憶體（`Hordes.live[z] = { horde, onlineId, kind }`），不進存檔。

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
  day = { key = "2026-11-10", quests = { Quest, Quest, Quest, Quest }, swaps = 1, done = 0, offline = nil },   -- offline：玩家不在線時產生（§4 經驗任務），上線時重抽
  week = { key = "2026-W46", quests = { Quest, Quest, Quest }, goalPart = 0 },
  streak = { days = 0, best = 0, last = nil, graceUsed = false, graceWeek = nil, paid = {} },  -- paid[3]=true …
  newbie = { startMs, steps = { false, false, false, false, false } },  -- nil：完成或跳過
  towns = {},                                   -- townId -> true
  achv = {},                                    -- achId -> 最高已解鎖等級
  titles = {}, title = nil,                     -- titleId -> true；目前使用的稱號
  titleAt = nil,                                -- titleId -> 第一次拿到的伺服器時間（ms）；所有發稱號的地方都走 Store.grantTitle，撤銷時一起刪；設計稿 r13 之前拿到的沒有時間，不回補
  titleSrc = nil,                               -- titleId -> 發它的來源（第一次）："a:<achId>:<tier>"、"streak:<days>"、"newbie"、"season:<no>:<rank>"、"first:<boardId>"；撤銷依它刪（服主 2026-10-27）；0.2.0 之前拿到的沒有，不回補
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
- 帳號層級統計（Catalog `S(…, account = true)`：`quest.daily`、`quest.weekly`、`streak.best`、`achv.tiers`、`goal.done`、`season.joined`、`horde.joined`、`horde.wins`、`horde.kills`、`horde.mvp`）不寫 `life`；我的紀錄頁「這條命」欄顯示「-」，跟「賺到的積分」一樣。
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
  achievements = { [achId] = { enabled = true, tiers = { … }, pts = { … }, titles = { [tier] = titleId } } },   -- titles 整份取代預設（SCHEMA 葉節點）：沒寫的級不給稱號（服主 2026-10-27）
  custom = { [customId] = { name = "純文字", cat, stat, tiers = { … }, pts = { … }, titles = { } } },
  difficulty = { preset = "normal", mult = 1 },          -- easy 0.6 | normal 1 | hard 1.6 | custom
  season = { lengthDays = 28 },                          -- 只能經賽季指令改，§5.9
  rewards = { top1 = 600, top3 = 400, top10 = 200, participation = 100, participationMin = 250, firstTitles = true },
  exchange = { enabled = true, rate = 1, perDay = 100, min = 10 },
  broadcast = { enabled = true, minTier = 3, perMinute = 1 },
  boards = { inactiveDays = 180, rebuildSeasonMs = 300000, rebuildTotalMs = 1800000 },
  towns = { custom = { }, disabled = { } },              -- custom: { { id, name, rects = { { x1=, y1=, x2=, y2= } } } }
  ceilings = { },                                        -- stat -> 每分鐘上限覆寫
  hordes = { enabled = false,
             windows = { { days = "1234567", from = "19:00", to = "23:00", chance = 30, preset = "default", leadMin = 15, waitMin = 60 } },
             maxPerDay = 1,
             presets = { default = { name = "", waves = { { base = 30, perPlayer = 50 } }, kinds = { vanilla = 80, runner = 20 },
                 points = { vanilla = 5, runner = 8 }, hp = { }, limitMin = 15, restSec = 30, maxAlive = 200, cap = 500 } },
             spots = { } },                             -- presets：方案 id -> 方案（name "" 時客戶端顯示翻譯的「預設」）；spots：{ { name, x, y, z } }；§5.10
}
```

- 修改單位是 change：`{ op = "set" | "del", path, value }`。`Config.validate` 依路徑家族檢查型別與範圍（門檻嚴格遞增且 1～1e9、積分 0～10000、等級最多 10、倍率 0.1～10、天數 7～180…）。
- `hordes` 組：`enabled` 布林；`windows` 整組替換，1～8 個，每個正好 `{ days, from, to, chance, preset, leadMin, waitMin }`：`days` 字串 `1`～`7`（1＝星期一、7＝星期日）各最多一次、1～7 字，`from`／`to` 字串 `H:MM` 或 `HH:MM`（時 0～23、分 0～59；`to < from` 跨午夜，相等＝整天），`chance` 整數 0～100（每小時一次的機率），`preset` 方案 id，`leadMin` 0～`Contract.LIMIT.MAX_LEAD`（120），`waitMin` 1～240（每一波等人的分鐘）；`maxPerDay` 1～24（所有時段合計）；`presets` 分支，鍵是方案 id，值 `{ name, waves, kinds, points, hp, limitMin, restSec, maxAlive, cap }`：`name` 字串 0～32 字（Kahlua 的 `#` 以 UTF-16 字元計，中文也是 32 字；家族 `pitfalls.md`），不含控制字元；`waves` 整組替換，1～10 個，每個正好 `{ base, perPlayer }`：`base` 1～9999、`perPlayer` 0～1000（每多 1 人加 `base` 的幾 %）；`kinds` 分支，鍵是種類 id（`[%w_:-]`，最長 64，外掛種類是 `<modId>:<id>`），值整數 0～100（相對權重，不必加到 100）；`points` 同樣的鍵，值整數 0～1000（每隻積分，沒有的種類用 `points.vanilla`）；`hp` 同樣的鍵，值 0.1～10 的數（耐打倍率，可小數；沒有的種類＝1）；`limitMin` 1～120（每一波的時限）；`restSec` 0～600；`maxAlive` 10～2000；`cap` 1～1000000（單場積分上限）。方案 id（`presets` 的鍵與時段的 `preset`）是 `Config.child()` 的另一種 key 規則，只有 `hordes.presets` 用：`^%a[%w_%-]*$`、最長 64，英文字母開頭，不能有冒號。純數字的鍵會被 JSON 解碼成 number、數字開頭的 id 在 `parsePath` 會出錯，所以兩種都擋成 `unknown`／`path`；客戶端產生的 `p2`～`p8` 符合。路徑例：`hordes.presets.p2.limitMin`、`hordes.presets.default.kinds.runner`、`hordes.presets.p2.hp.runner`、`hordes.presets.p2`（整個方案 set／del），最長 5 段。`spots` 整組替換，最多 32 個 `{ name = 1～64 字不含控制字元, x = 0～100000, y = 0～100000, z = -32～31 }`，不能有其他鍵。`hordes` 底下的未知鍵（含 2026-10-27 拿掉的 `from`、`to`、`chance`、`count`、`perZombie`、`split`，與 2026-10-28 搬進方案與時段的頂層 `leadMin`、`waitMin`、`waves`、`kinds`、`points`、`limitMin`、`restSec`、`maxAlive`、`cap`）一樣驗證失敗。`validateAll` 在套用後的有效設定上另外檢查（接在自訂成就數量檢查之後）：方案數 ≤ `Contract.LIMIT.MAX_PRESETS`（8），否則 `{ why = "presets" }`；每個時段的 `preset` 都在 `presets` 裡，否則 `{ why = "preset", path = "hordes.windows.<i>.preset" }`；接著依 id 排序（`U.sort`）逐一檢查方案：預設以外的方案缺 `waves`、`kinds`、`points`、`cap`、`limitMin`、`restSec`、`maxAlive` → `{ why = "presetPart", path = "hordes.presets.<id>.<第一個缺的欄位，照前面的順序>" }`（`hp` 可以不寫＝全部 1 倍；例：從面板 del `hordes.presets.p2.kinds`）；預設以外的方案名稱沒寫、空字串或只有空白字元 → `{ why = "presetName", path = "hordes.presets.<id>.name" }`；兩個方案的名稱字串完全相同（只比非空的，大小寫不同不算同名，預設方案有名稱也一起比）→ `{ why = "presetSame", path = "hordes.presets.<id 排序在後的那個>.name" }`。所以預設以外的方案一定完整、名稱非空且不重複；管理頁的同樣檢查（§7）只是立即提示。`default` 在 `Catalog.DEFAULTS` 裡，del 它的覆寫只會回到預設值，所以一定在。
- 屍潮設定搬家：`Config.migrate(tree)`（純函式，overrides 形狀，改了回 true）把 `hordes` 的舊鍵就地改成新形狀，分三步。第一步（2026-10-27，0.2.0 的鍵）：舊鍵只在「新鍵還沒有、而且舊值過得了舊版驗證」時換掉並刪除：`from`／`to`／`chance` 有任何一個、沒有 `windows`，補上預設後（`from` 或 "19:00"、`to` 或 "23:00"、`chance` 或 30）兩個時刻都是 `H:MM`／`HH:MM`（00:00～23:59）、`chance` 是 0～100 的整數 → `windows = { { days = "1234567", from, to, chance } }`，三個舊鍵刪掉；`count` 是 2 個 1～100 的整數 `{ a, b }`、`a ≤ b`、沒有 `waves` → `waves = { { base = floor((a + b) ÷ 2 + 0.5), perPlayer = 0 } }`；`perZombie = p` 是 0～1000 的整數、沒有 `points` → `points` 的 `vanilla`、`runner` 與 `kinds` 的每個鍵都是 `p`；`split` 一律刪掉（只剩照擊殺價值分）。第二步（2026-10-28，方案制）：頂層有覆寫的 `waves`、`kinds`、`points`、`cap`、`limitMin`、`restSec`、`maxAlive` 搬進 `presets.default.<鍵>`，那個鍵已經有值就不搬；頂層的 `leadMin`／`waitMin` 各自只在值過得了舊驗證（`leadMin` 0～120、`waitMin` 1～240 的整數）、而且所有時段都還沒有自己這個鍵時才搬：`windows` 沒有覆寫時先照 `Catalog.DEFAULTS.hordes.windows` 建一份，每個時段填頂層的值，搬完才刪掉頂層鍵。值不合法（例如 `false`、超出範圍）或有時段已經有自己的這個鍵（舊鍵在新鍵旁邊）時，頂層鍵留著，整份在 `hordes.leadMin`／`hordes.waitMin` 驗證失敗、檔案不改寫，不用預設值替換。時段缺的 `preset` 填 `"default"`，缺的 `leadMin`／`waitMin`（頂層沒有可搬的值時）填舊預設 15／60；頂層鍵留著被拒的情況下這些填值不會生效。第三步：預設以外的方案缺的欄位（`name`、`hp` 除外）照 `Catalog.DEFAULTS.hordes.presets.default` 補上整份的值（`U.copy`），補過就算改過，`applyFile` 把完整的形狀寫回 `config.json`。前兩步涵蓋：0.2.0 的形狀（`from`／`to`／`chance`、`count`、`perZombie`、`split`、`kinds`、`leadMin`、`waitMin`、`limitMin`）與方案制之前的開發版形狀（頂層 `windows`／`waves`／`points`／`cap`／`restSec`／`maxAlive`、`leadMin`、`waitMin`）。換不了的舊鍵留著，整棵樹在它的路徑驗證失敗（`status.json` 寫出那個 `path`）：舊值本來就不合法時不悄悄改用新預設，新舊鍵同時在時（照舊形狀改的檔案）也不丟掉那次修改。開服時（`Config.fileBoot`）先對 `root.config.overrides` 跑一次（改了就 `invalidate` 並記一行 log）；讀 `config.json` 時對解析出的樹先跑再比較，改過就在套用後重寫檔案。`cfg.undo` 復原前先照套用的規則驗證，舊路徑或舊值回 `BAD_CONFIG`、不寫。
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
- 成就分類 10 個：`combat`、`survival`、`skill`、`production`、`nature`、`explore`、`quest`、`horde`、`hidden`、`job`。鍵 `IGUI_MQ_AchCat_<id>`。
- 榜單分類 8 個：`overall`、`combat`、`survival`、`skill`、`life`、`explore`、`quest`、`job`。鍵 `IGUI_MQ_BoardCat_<id>`。

### 4.2 統計

```lua
stats[id] = { id = "zombie.kills", kind = "count" | "max", ceil = 120, unit = "count" | "km" | "days" | "xp" | "level" }
```

- 鍵 `IGUI_MQ_Stat_<id 的點換成底線>`。`kind = "max"` 的統計（技能等級、單命存活天數、最長連續）用 `Stats.max`，不吃每分鐘上限。
- 內建 id 由 Catalog 擁有者定案，至少涵蓋：擊殺（總、近戰、槍械、車撞、各武器類）、狩獵、存活天數、技能等級（42.21.0 實際可升級的 35 個，`PerkFactory.java:98-141`）與總等級、經驗、製作、建造、烹飪、縫紉、鍛造、修車、接電、讀書、包紮、室內睡覺、播種、收成、釣魚、誘捕、搜尋、屠宰、擠奶、剪毛、撿蛋、步行、開車、擺放家具、造訪城鎮，任務類（每日完成、每週完成、最長連續、成就等級數），以及屍潮（參加、清光、擊殺、單場最多擊殺；§5.10）。
- `Catalog.perks`：35 個技能 id；`Catalog.statOrder`：統計的顯示順序（我的紀錄、管理面板的統計清單用）。

### 4.3 成就

```lua
achievements[i] = { id = "zombie_kills", cat = "combat", stat = "zombie.kills",
                    tiers = { 100, 1000, 5000, 20000, 50000 }, pts = { 10, 20, 30, 50, 80 },
                    titles = { [4] = "zombie_kills_4" }, icon = "zombie_kills", hidden = nil,
                    scope = nil }   -- 選用：scope = "life" 表示看這條命的統計（單命類成就），省略＝total
```

- 鍵：名稱 `IGUI_MQ_Ach_<id>`、說明 `IGUI_MQ_AchDesc_<id>`（`%1`＝門檻）、隱藏提示 `IGUI_MQ_AchHint_<id>`、稱號 `IGUI_MQ_Title_<titleId>`、等級 `IGUI_MQ_Tier_1`～`_4` 與 `IGUI_MQ_Tier_Legend`（`%1`＝羅馬數字）。
- 內建一般成就 5 級：積分 10／20／30／50／80，稱號在第 4 級。數量類第 5 級＝第 4 級 ×2.5；技能等級 2／4／6／8／10（體能、力量 6～10）、技能總等級 300（上限 35×10＝350）、造訪城鎮第 5 級 11（12 個是隱藏成就 `h_all_towns`）、存活與室內睡覺天數 730、成就等級數 450（全部 94×5＋17＝487 級）。
- 屍潮類 3 個（設計稿 r12）：`horde_wins`（`horde.wins`，3／10／25／50／125）、`horde_kills`（`horde.kills`，25／100／300／800／2000）、`horde_mvp`（`horde.mvp`，1／3／8／20／50）。
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
- 經驗任務（服主 2026-10-27）：統計是 `xp.<Perk>` 的每日樣板（含其他 MOD 的；`xp.total` 不算）只派給 `Quests.xpEligible(player, perk)` 為真的玩家：`getXp():getPerkBoost(perk) >= 1` 且 `getPerkLevel(perk) < 10`。10 級引擎不再給經驗也不觸發 `AddXP`（42.21.0 `IsoGameCharacter.java:17455-17456`），沒加成多數技能 ×0.25（`:17464-17479`）。`genDay` 與 `swap` 都先用 `playerPool` 濾掉不符合的，`pickT` 照常退到同主題的其他樣板；玩家用 `Net.playerOf` 找，不在線就當不符合。不在線時產生的一天（共同目標、賽季結算經 `Stats.add(使用者名稱)` 觸發 `ensure`）記 `day.offline`，先不算進報表與平衡的派發數；`onStat` 讓其中一格第一次有進度時才記派發並清旗標（`countGiven`），`ensure` 看到旗標還在且玩家在線就重抽。全服任務不抽 `xp.<Perk>`（其他 MOD 的任務沒有 `shared` 欄位）。
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
- `Achievements.list()` → `list, byStat, all`：合併內建、自訂、facade 的有效清單（含設定覆寫的門檻）；`all` 是 id → 定義，含停用的（撤銷用）。每個定義帶 `defTitles`（定義本身的稱號，撤銷時給沒有 `titleSrc` 的舊稱號用）。`Achievements.evaluate(acc, user, opts)`：判定所有統計相關的成就，`opts.quiet` 時不通知、不發本季積分（只發累計）。`Achievements.revoke(user, achId, toTier, reason, actor)`：停用的成就也能撤（服主 2026-10-27）；刪 `titleSrc` 是 `a:<achId>:<被撤的級>` 的稱號，沒有紀錄的稱號另刪那一級現在設定的 id 與 `defTitles` 的 id（有別的來源紀錄的不刪）。
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

設定全在 `Config` 的 `hordes` 組（§3.4，`config.json` 一起同步），即時狀態在 `root.hordes`（§3.1）。時段管「什麼時候、預告多久、等人多久、用哪個方案」，方案管「怎麼打」：波次、種類、積分、耐打、時限、休息、場上上限與單場積分上限。每天最多幾場仍是所有時段合計。

- 時段與擲骰（純函式，harness 用固定時鐘測）：時區用沙盒 `TimezoneOffset`（小時），不用經濟系統的換日。每個時段 `win = { days, from, to, chance, preset, leadMin, waitMin }` 各自算，下面的 `leadMin` 都是那個時段自己的 `win.leadMin`：當地日 `d`（UTC＋tz 的日數）的星期＝`Hordes.weekday(d)`＝`(d + 3) % 7 + 1`（1＝星期一），只有 `days` 裡的星期開；時段 `ws = d × DAY − tz × HOUR + from`、`we = ws + 長度`（`to > from`：`to − from`；`to < from`：`to + 1440 − from`；相等：1440 分），時段屬於它開始的那一天。`Hordes.windowOf(win, d, tz)` → ws, we；`Hordes.window(win, now, tz)` → d, ws, we, K（找 d+1、d、d−1 中第一個是它的星期、`ws − win.leadMin ≤ now < we` 的，晚的那天優先；K＝`ceil(長度 ÷ 1 小時)`），不在時段回 nil；`Hordes.slot(ws, we, k, leadMin)`（呼叫端傳 `win.leadMin`）→ 第 k 格的開始 `S = ws + k 小時`、結束 `min(S + 1 小時, we)`、擲骰時刻 `S − leadMin`。`Hordes.winKey(win)`＝`from-to-days`；`Hordes.winKeys(windows)` → 每個時段的 roll 鍵：`winKey`，完全相同的時段第 2、3…個加 `#2`、`#3`，所以它們各擲各的（`roll` 與 `nextRoll` 都用它）。
- `Hordes.roll(now, cfg, tz)`（每 tick）：逐個時段（鍵＝`winKeys` 的第 i 個），`roll[鍵]` 不是這天、這個 `ws` 就重設 `{ day, ws, slot = 0 }`（管理員改了 `from` 是新的鍵，從第 0 格擲）；擲骰時刻已到的格依序取走（`slot + 1`），下列情況跳過不擲：格已結束（停機錯過的小時不補擲）、`enabled` 關、沒有地點、已有 `cur`、`perDay[那天] ≥ maxPerDay`（所有時段共用）；否則 `ZombRand(100) < win.chance` 中了就在 `[max(S, now + win.leadMin), 格結束)` 挑整分鐘當開始時間（區間空的話不排），用這個時段的方案、`leadMin`、`waitMin` 排定，`perDay[那天] + 1`（只留最近 3 天）。設定裡沒有的鍵，`roll` 那一份拿掉。`Hordes.nextRoll(cfg, now, tz, roll, perDay)` → 所有時段裡最早的下一次擲骰（管理頁；往後找 7 天，各時段用自己的 `leadMin`），關閉或沒地點時 nil；不改存檔。
- `Hordes.presetOf(cfg, id)` → `cfg.presets[id] or cfg.presets.default`，不另外補欄位：預設以外的方案一定完整（讀檔時補齊、`validateAll` 擋 `presetPart`，§3.4），`default` 由 `Catalog.DEFAULTS` 合併；`hp` 沒寫＝全部 1 倍。
- `Hordes.plan(cfg, startMs, actor, win)`：`win = { preset, leadMin, waitMin }` 是排到的那個時段，或 `startNow` 組出來的同形狀表。隨機地點，從 `presetOf(cfg, win.preset)` 複製 `waves`、`kinds`（→ `weights`）、`points`、`hp`、`cap`、`limitMin`、`restSec`、`maxAlive`，`preset`＝方案的 `name`（預設方案是 `""`），`waitMin = win.waitMin`，`wave = 1`，`announceAt = startMs − win.leadMin`，`state = "planned"`。`actor` nil＝自動。`Hordes.startNow(actor, now, lead, presetId, wait)`（`horde.now`）＝`plan(cfg, now + lead 分, actor, { preset = presetId, leadMin = lead, waitMin = wait })`：預告立刻發，不算進 `perDay`；省略時 `lead` 0、`wait` 60、`presetId` `"default"`。
- 耐打：`spawnAt` 把殭屍記進 `Hordes.live` 之後，`mult = cur.hp and cur.hp[種類] or 1`；`mult ~= 1` 時 `z:setHealth(math.min(z:getHealth() × mult, Hordes.HP_MAX))`，`HP_MAX = 30`。其他 MOD 的種類乘在它 `spawn` 裡設好的血量上。上限的原因：殭屍封包把 `health × 1000` 轉成 short 送出，超過 32.767 會繞成負數（`NetworkZombieAI.java:169`、`NetworkZombiePacker.java:243`）。玩家端的預告、追蹤面板與結果通知不顯示耐打。
- `Hordes.mix(weights, count)` → `{ { kind, n, nameKey } }`：已登記的種類照 `Catalog.hordeMix`（權重 > 0 的、依 `kindList` 順序；先取整，餘數一隻一隻給權重大的，同權重依 id；沒有可用權重時全是 vanilla）。`Catalog.hordeWaveSize(base, perPlayer, players)`＝`max(1, floor(base × (1 + perPlayer ÷ 100 × (max(players, 1) − 1)) + 0.5))`；管理頁的預覽用同兩個函式。
- `Hordes.tick(now)`（`OnTickEvenPaused`，每秒最多一次）：Store 就緒後第一個 tick 跑 `Hordes.boot`（`cur` 沒有 `waves` 先補成新形狀，§3.1；`active` → 失敗 `restart`，清光的波次照發，殭屍留在世界上變一般殭屍；`planned`／`announced`／`waiting`／`rest` 照常），之後 `roll` 再 `step`：
  - `planned`：到 `announceAt` → `announced`，全服通知 `soon`；已經到 `startMs`（預告 0 分或手動）→ 直接 `waiting`，通知 `open`。這時離開始 ≤ 2 分（`Hordes.REMIND_MS`）就記成已提醒（`reminded`），預告本身就是提醒。
  - `announced`：到 `startMs − REMIND_MS` 而且還沒提醒 → 個人通知 `remind`（一次，只給地點 30 格內活著的在線玩家：開始時有人在附近就會出波，讓不想參加的人離開）；到 `startMs` → `waiting`。
  - `rest`：到 `nextAt` → `wave + 1`、`waiting`、`expireAt = now + waitMin`。
  - `waiting`：到 `expireAt` → 失敗 `nobody`；地點 30 格內（2D，`Hordes.RANGE`）有身分通過、活著的在線玩家（`Hordes.nearCount(cur, range)`，`range` 省略＝`RANGE`）→ 開波：`size = Catalog.hordeWaveSize(base, perPlayer, 人數)`、`mix = Hordes.mix(weights, size)`、`queue`、`queued = left = size`、`spawned = killed = tries = 0`、隨機 `angle`、`endsAt = now + limitMin`、`state = "active"`，通知 `spawn`，同一個 tick 接著跑 `active`。
  - `active`（每秒）：(1) 活著＝這場的 `live` 項目裡 `onlineId` 還是生成時那個（不是 −1：`removeFromWorld` 會把它設成 −1；物件被引擎重用時會拿到新的）且 `not isDead()` 的；其餘從 `live` 拿掉（被引擎收起來的不追，變一般殭屍）。不看 `isExistInTheWorld()`：專用伺服器上剛生成的屍潮殭屍，所在格子的 moving objects 不列它，生成後 0～1.5 秒都是 false（E2E `quest-hz-1026e`）；第一版有這項，每一場都在下一個 tick 判成功、0 擊殺（`quest-hz-1026c`／`d`）。也不看 persistent outfit id：沒給外觀名稱生成的殭屍被標記「之後隨機穿衣」（`LuaManager.java:10661-10665`），穿上時會換 id。(2) 補殭屍：這批最多 `min(maxAlive − 活著, queued, Hordes.BATCH = 40)` 隻，用 `Catalog.hordeMix(mix 的種類, queue, n)` 照剩下的比例分種類，輪流放到 `Hordes.exits(cur)` 的各出口，每個（出口, 種類）一次 `pcall(kind.spawn, ex, ey, z, k)`；沒有出口就在地點（舊做法）。`spawn` 出錯時每場每種類只記一行 log（`Hordes.spawnErr[種類] = 場次 id`，只在記憶體；不然壞掉的種類每批每個出口都記），出錯前收下的照算。只收 `instanceof(z, "IsoZombie")`、最多 k 隻，先 `setOwner(nil)`、`setOwnerPlayer(nil)` 再記進 `Hordes.live[z] = { horde, onlineId, kind }`（只在記憶體）。清擁有者是因為引擎重用殭屍物件時不清上一輪的網路擁有者：被殺死時歸某個客戶端管的物件，再拿出來時還掛在那個客戶端名下、那個客戶端的清單裡卻沒有它，伺服器就不送給任何客戶端（E2E `quest-hzloop-1026e`：生成時帶擁有者的 17 隻兩端都沒看到；清掉之後 `1026d` 40 隻都看到）；沒有擁有者時下一次 `NetworkZombieManager.updateAuth` 照常指派。一批收到 0 隻（`queued > 0`）→ `tries + 1`，有收到就歸 0；連續 `Hordes.MAX_TRIES`（10）批：這一波一隻都沒出來 → 失敗 `spawn`，否則剩下的不出了（`queued = 0`）。(3) 活著 > 0 時每 `Hordes.LURE_MS`（5000）`pcall(addSound, nil, x, y, z, r, r)`（出錯每場只記一次），`r = Hordes.lureRadius()`＝`ceil(LURE_REACH ÷ 倍率)` 夾在 `LURE_REACH`（48＝`RING_MAX` 40＋`SPREAD` 8）～`LURE_MAX`（49），倍率 ≤ 0 時 49：讓聽力打折後還盡量傳到 48 格。上限 49：半徑 50 起聲音也會驚動虛擬（沒載入的）人口，把 `maxAlive` 以外的野生殭屍帶進來（`ZombiePopulationManager.java:489-505`）；已載入、在範圍內的野生殭屍照樣會來。倍率＝`Hordes.lureMult()`＝沙盒 `ZombieLore.Hearing`（1：×3；2 與讀不到：×1；3 與隨機的 4／5：×0.45。聽距是每隻殭屍自己的聽力算的，4 每隻擲 1～3、5 擲 2～3（`IsoZombie.java:3904-3907`），總有一部分聽力差，所以照差算；`WorldSoundManager.java:511-523`）×天氣（`1 − 雨 × 0.33 − 霧 × 0.1`，`IsoGameCharacter.java:15224-15227`），最小 0。晴天、聽力普通時 `r` 是 48。伺服器不跑殭屍 AI，聲音送到擁有這些殭屍的客戶端，殭屍走向地點（E2E `quest-lure-1027b`／`c`，速度 2：45／45 每 5 秒，30～40 格外的 32 隻 60 秒內全到、8 個方向；30／30（等於大雨）只到 7／32；不發聲音不動；伺服器 `setTarget` 30 秒就被擁有者客戶端蓋掉、沒有用）。(4) `left = 活著 + queued`；`queued = 0`、活著 0 隻、地點 `Hordes.CLEAR_RANGE`（50）格內（2D，`nearCount(cur, 50)`）有玩家 → 這一波清光（不用開波的 30：出口 30～40 格、散布 8 格，追出去殺最後幾隻的人也算）：`waveGot` 併進 `got`、`waveKills` 併進 `gotKills`，兩者清空、`cleared + 1`；還有下一波 → `rest`、`nextAt = now + restSec`，通知 `rest`；最後一波 → 成功。(5) 到 `endsAt` → 失敗 `time`。
    單機（`not isServer()`）沒有 `onlineId`（只有專用伺服器發，`VirtualZombieManager.java:207-221`，每隻都是 −1），(1) 的「活著」改成殭屍還在 `getCell():getZombieList()` 裡且 `not isDead()`：生成那一幀就在、`removeFromWorld` 拿掉（`IsoZombie.java:4366`），`OnZombieDead` 時也還在；單機的 `isExistInTheWorld()` 生成那一幀同樣是 false、0.5 秒後才 true。修正前（E2E `quest-hsp-pre-1027a`）每一波在下一個 tick 判清光、0 擊殺，整場「成功」不發積分。被卸載、又在同一秒內被引擎重用成別隻的物件，在 `OnZombieCreate`（`Hordes.onZombieCreate`；引擎只在 `VirtualZombieManager.java:203` 觸發，早於 `spawnAt` 登記新的屍潮殭屍）就從 `live` 拿掉，不會被當成同一隻（專用伺服器也一樣處理）。
- `Hordes.exits(cur)`：先算 `Hordes.exitMax()`＝`min(RING_MAX 40, floor(lureRadius × lureMult) − SPREAD 8)`（生成散在出口周圍 11 × 11 格，角落離出口 7.07 格，也要聽得到誘餌；晴天、聽力普通或靈敏是 40）；`exitMax < RING_MIN`（30：倍率約 0.78 以下，例如大雨、下雨又起濃霧、沙盒聽覺「差」或隨機）時回 `{}`，那一波在地點生成。否則從 `cur.angle` 起 `Hordes.EXITS`（8）個方向，每個離地點 `RING_MIN`～`exitMax` 格（`ZombRand`）；保留離每位活著的在線玩家都 ≥ `GAP`（25，歐氏）、離至少一位 ≤ `REACH`（43，Chebyshev：最小的客戶端只保證載入 48 格，留 5 格給生成的 11 × 11 散布），而且那一格載入了、可以站（伺服器的 `getCell():getGridSquare` 在沒載入的 cell 回 nil，`IsoCell.java:3190-3192`；`isFree(false)`：有地板、沒有 solid／樹，`IsoGridSquare.java:3394`；不是水 `isWaterSquare()`，生成本來就拒絕水，`VirtualZombieManager.java:254-255`）的點。在 pcall 裡呼叫，出錯記 log、當成沒有出口。
- `Hordes.onZombieDead(z)`（自己的 `OnZombieDead`，Trackers 照樣記一般擊殺）：`live[z]` 存在就拿掉（同一隻的第二次事件因此不算），還是同一隻、`active` 時 `killed + 1`、`totalKilled + 1`、`left − 1`；`getAttackedBy()` 是 IsoPlayer 時 `Identity.principal` 的帳號 `kills + 1`、`waveKills + 1`、`waveGot + points[種類]`（沒有就 `points.vanilla`，再沒有 0）、`Stats.add(user, "horde.kills", 1)`。燒死等沒有攻擊者的算清掉、不算任何人的擊殺。
- `Hordes.finish(result, why, now)`：先 `cur = nil`（後面哪一步出錯，下一個 tick 也不會再結算、再發一次）。任何結果都發清光的波次：`value = sum(got)`、`pool = min(value, cap)`、`capped = value > cap`；每人 `floor(pool × got ÷ value)`，餘下的一分一分給小數部分大的（同分依帳號名），總和正好 `pool`；> 0 才 `Points.award(…, "horde", "horde:<id>")` 與個人通知 `hordePaid`（`kills`＝`gotKills`，清光的波次裡的擊殺；失敗那一波的 `waveGot`／`waveKills` 不算）。參加者＝擊殺 ≥ 1 的帳號（`kills`，整場），不論結果各 `horde.joined + 1`（取消的場次在生成前，沒有參加者）；只有成功時 `horde.wins + 1`，參加者 2 人以上時擊殺最多的（並列都算）`horde.mvp + 1`。`active` 時失敗 → 先拿掉 `live` 項目再對還活著的呼叫 `Hordes.clearZombie(z)`（`removeFromWorld` + `removeFromSquare`，唯一的清除函式；清除不算擊殺），清掉的 onlineId 送一次 `hordeClear`（§6.3）。全服通知結果、事件記錄 `horde`（`spawned`、`killed` 是整場）、寫進 `log`。
- `Hordes.cull()`：伺服器上的沙盒 `SandboxVars.ZombieConfig.ZombiesCountBeforeDelete`（42.21.0 `SandboxOptions.java:2044`，0～5000，0＝關；一位玩家附近超過這個數，引擎刪掉遠處沒有目標的殭屍，被刪的屍潮殭屍算走掉），讀不到是 nil；給 `horde.status`，管理頁在 `maxAlive` 旁顯示。
- 每次狀態改變、擊殺、`left` 改變、結束都 `Sync.dirty(nil, "hordes")`。
- 種類：`Hordes.kinds[id] = { id, nameKey, spawn = fn(x, y, z, n) → ArrayList | Lua 陣列, modId? }`。內建 `vanilla`（`addZombiesInOutfitArea(x−5, y−5, x+5, y+5, z, n, nil, 50)`，再對每隻 `setUseless(false)`：引擎重用殭屍物件時不重設 `useless`（`VirtualZombieManager.java:271-329`），帶著它的殭屍不理聲音也不追人（`IsoZombie.java:1594`、`:2060`），會一直站在出口；E2E `quest-hz-1027l`）與 `runner`（同上，再對每隻 `doSprinter()`；不用 `doZombieSpeed(1)`，它會擲骰），鍵 `IGUI_MQ_Horde_Kind_<id>`。其他 MOD 登記的種類不清，旗標由它們自己設（可能是故意要站著的）。`Hordes.registerKind(spec)`＝facade `registerHordeKind`（§8）。`Hordes.kindList()` → `{ { id, nameKey, builtin } }`，內建依 `Contract.HORDE_KINDS`，其餘依 id。
- `Hordes.stateHordes(acc, user, now)`：Sync provider `hordes`，見 §6.3。
- `Hordes.recent(user, n)`：`log` 裡預告過的最近 n 場（`Hordes.RECENT` 10），新的在前，每場帶這個帳號的擊殺 `mine` 與得分 `got`；`records` 回覆的 `hordes`（§6.3）。全服共用 `log`，不另存每個帳號的紀錄。

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
| `horde.status` | — | `cur`（完整的 `cur`，含 `planned`、`preset`、`waves`、`weights`、`hp`、`mix`、`queue`、`kills`、`got`）、`roll = { n（今天，當地日）, max, nextAt, enabled }`、`log`（最近 10 筆，新的在前）、`kinds = { { id, nameKey, builtin } }`、`cull`（`Hordes.cull()`，讀不到為 nil） |
| `horde.now` | `lead: int?`（分，0～120，`Contract.LIMIT.MAX_LEAD`）、`wait: int?`（分，1～240）、`preset: str?`（方案 id） | `id`；已有一場 `HORDE_BUSY`、沒有地點 `NO_SPOTS`、`lead`／`wait` 超出範圍或 `preset` 不在套用中的設定 `BAD_ARGS`。開始時間＝現在＋`lead` 分：0 時立刻通知 `open`，大於 0 時立刻預告 `soon`；每一波等人 `wait` 分；用 `preset` 的方案。省略時 `lead` 0、`wait` 60、`preset` `"default"`。不算進 `perDay`；歷史 `horde.now <id> <name>`（不能復原） |
| `horde.stop` | `id: int` | —；不是目前那場 `NOT_FOUND`。`planned`／`announced` → 取消（預告過才通知 `cancel`）；`waiting`／`rest` → 失敗 `admin`；`active` → 失敗 `admin` 並清掉剩下的；清光的波次照發；歷史 `horde.stop <id> <name>`（不能復原） |

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
  achv = { [achId] = tier }, titles = { titleId… }, titleAt = { [titleId] = ms } | nil, titleSrc = { [titleId] = src } | nil, title, prefs = { … }, anon,
  season = { no, startMs, endsAt, state },
  exchange = { available, enabled, rate, perDay, used, min, queued, hist },   -- hist：排隊中的（新的在前，at＝申請時間）接著 ex.log，合計最多 10 筆；兌換頁的「兌換紀錄」
  events = { { name, theme, mult, endsAt } },
  hordes = { on, cur = HordeView | nil, last = HordeLast | nil },   -- §5.10；on：玩家「屍潮任務」頁要不要列出
  unseen,
  pins = { … }, trk = { [achId] = { t, v } } }     -- 追蹤面板（§5.6）
```

- `delta`：`{ day = { [i] = { prog, state, ptsNow } }, week = { [i] = { prog, state, ptsNow } }, goal = { progress, reached }, points = { … }, unseen, trk = { … }, pins = { … }, hordes = { on, cur, last } }`，只帶有變的欄位（`ptsNow` 只在完成時帶 `got`；活動開始或結束時 `Quests.watchEvents` 讓開著視窗的人收到完整 `state`）。只開追蹤面板的人不收 `goal`、`points`；`hordes` 兩種人都收。
- `hordes.on`：自動屍潮開著（`hordes.enabled`）、`log` 有紀錄或目前有一場（不含 `planned`）時為 true；套用設定不推 `hordes`，管理員剛打開自動屍潮時，玩家下次開視窗（`watch` 送完整 `state`）或下一次屍潮推送才看到分頁。`HordeView`（`planned` 時不給玩家）：`{ id, name, town, x, y, z, state, kinds = { { id, nameKey } }, announceAt, startMs, expireAt, endsAt, nextAt, wave, waves（波數）, size（這一波隻數，開波前 0）, left, killed（這一波）, limitMin, mine（我的擊殺）, got（我在清光的波次的擊殺價值，未套上限） }`。`HordeLast`：最新一筆 `log`，結束後 10 分鐘內（`Hordes.LAST_MS`；預告前就取消的不給）：`{ id, name, town, state, why, endedAt, waves, cleared, spawned, killed, pool, capped, mine, got（我拿到的積分，沒拿到為 nil） }`。
- `titles`：`{ full = true, map = { [user] = titleId } }`（登入時，在線玩家）或 `{ u, t }`（一人換了稱號或剛登入；`t` 為 nil 表示不戴）。
- `toast`：`{ kind = "achv", id, tier, pts }`、`{ kind = "achvMany", ids = { … 最多 3 }, n }`、`{ kind = "quest", tid, target, pts }`、`{ kind = "week", tid, target, pts }`（帶 `target`：視窗關著時客戶端的任務清單是登入時的快照，跨日後查不到新任務）、`{ kind = "goal", stat, pts }`、`{ kind = "streak", days, pts }`、`{ kind = "newbie", pts }`、`{ kind = "exchange", state, coins }`、`{ kind = "season", no, rank, pts }`、`{ kind = "broadcast", who, a, id, tier, titleId }`（`who` 為匿名時是 nil；`a` 是匿名者的帳號，只在送給管理員的那份，客戶端顯示「名字（匿名）」）。
- 屍潮通知：全服 `{ kind = "horde", ev, id, name, town, … }`，`ev`：`soon`（`startMs`、`kinds = { { id, nameKey } }`、`waves`，不帶隻數）、`open`（同 `soon`；預告 0 分或手動開始）、`spawn`（每一波：`wave`、`waves`、`size`、`endsAt`、`limitMin`）、`rest`（一波清光、還有下一波：`wave`＝清光的那一波、`waves`、`nextAt`）、`win`（`waves`、`spawned`、`killed`、`pool`、`capped`、`n`＝參加人數）、`fail`（`why`、`wave`＝失敗的那一波、`waves`、`cleared`、`pool`＝清光的波次發出的、`capped`）、`cancel`（只在預告過的場次）。個人 `{ kind = "horde", ev = "remind", id, name, town, startMs }`（開始前 2 分，地點 30 格內的人）與 `{ kind = "hordePaid", id, name, town, pts, kills, capped }`（`kills`＝清光的波次裡的擊殺 `gotKills`，就是這筆積分算的那些；失敗那一波的擊殺只在 `log.kills`）。客戶端把 `startMs` 寫成「N 分鐘後」（至少 1），不寫時刻：玩家會當成遊戲內時間。
- `hordeClear`：`{ ids = { onlineId … } }`，每場一次：失敗時還在場上而被伺服器清掉（`Hordes.clearZombie`）的屍潮殭屍，送給位置在這些殭屍外框 120 格內的玩家（客戶端只拿得到 96 格內的殭屍，42.21.0 `GameServer.java:2808-2809`、`UdpConnection.java:224-226`；onlineId 是會繞回的 short 計數，`IsoObjectID.java:48-54`，遠方客戶端可能有別隻同 id 的殭屍）。伺服器的 `removeFromWorld` 不送引擎的刪除封包，客戶端照引擎 `ZombieDeleteOnClient` 的做法（`ZombieDeleteOnClientPacket.java:44-47`）自己移除這些 id 的殭屍（自己擁有的也移除）；不送的話客戶端要等遠端殭屍逾時（`IsoZombie.java:3294-3295`）才清掉，200 隻圍著玩家時 15～91 秒。只在專用伺服器送：單機只有一個世界，`clearZombie` 已經移除；而且單機每隻殭屍的 id 都是 −1，送了客戶端會把 cell 裡每一隻殭屍都刪掉。
- `board`：`{ board, period, status = "ok", season = { no, endsAt }, rows = { { r, n, a, v, t, d } … ≤ 50 }, me = { r, v, d } | nil, count }`。`n` 是名字（匿名時 nil，客戶端顯示「匿名倖存者」），`a` 是匿名那一列的帳號（只送給管理員，客戶端顯示「名字（匿名）」），`t` 稱號 id（匿名那一列只送給管理員：同一個稱號在頭上與聊天認得出是誰），`d` 名次變化（正＝上升，nil＝新上榜）。
- `records`：`{ rows = { { stat, season, life, total } … }, points = { season, total, balance }, hordes = { { id, name, town, state, why, endedAt, waves, cleared, spawned, killed, mine, got } … ≤ 10 } }`（`hordes`：`Hordes.recent`，新的在前）。客戶端不列沒有定義的統計（pack 移除後留下的 id）。
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
- 更新概要（UI 框架 rev 24 `WhatsNew`）：`Entry.lua` 檔案載入時探測 `API_MAJOR == 1`、`API_REVISION >= 24`、`CAPABILITIES.whatsNew` 後呼叫 `WhatsNew.register({ modId, since, name = "IGUI_MQ_Name", text = "IGUI_MQ_WhatsNew" })`，四欄字面值、一欄一行（`release_train.py ready` 用 regex 讀）；有新概要的版本才改 `since`。
- 視窗：左側 NavList `Window.nav`（每日任務、每週任務、屍潮任務（只在 `state.hordes.on`）、成就、排行榜、我的紀錄、兌換（只在 `state.exchange` 可兌換或 `hist` 有資料時，spec 的 `shown`）；分隔後：設定）；管理（只有 `state.admin`）是另一個 NavList `Window.navAdmin`，貼在左欄底部（`Window.placeNav`：y＝max(`nav` 底＋`ADMIN_GAP` 12 px, 視窗高－自身高－6)，視窗版面或列出的頁面一變就重放；UI 框架的 NavList 沒有置底，所以分成兩個）。非管理員時隱藏。兩個清單只有一個有選取：`Window.select` 把頁面 id 設給擁有它的清單、另一個清掉（`setSelected(nil, true)`），兩個清單的 onSelect 都走 `Window.select`。右側內容；不透明視窗。列出的頁面一變（`Window.syncNav` 比對列出的頁面 id）就重建兩個 NavList，目前那頁不再列出時回到每日任務。預設大小＝內容寬（螢幕寬一半，夾在 640～1000 px）＋NavList 寬、高為螢幕高 82 %（460～1000 px），都不超過螢幕減 40 px（`Window.defaultSize`）；玩家拖過的大小由 ISLayoutManager 記住，大小和預設不同時標題列出現「重設大小」，按下回到預設大小並置中。
- 導覽的鍵盤與手把：NavList 到邊時 `onFocusKey` 回 false，Focus 引擎對鍵盤就停在原地，所以 `Window.lua` 只在這兩個實例上包 `onFocusKey`：`nav` 最後一列按下 → `Focus.focusControl(navAdmin)` 並停在它的第一列，`navAdmin` 第一列按上 → 回到 `nav` 最後一列；手把方向也先問同一個 `onFocusKey`（`Focus.onJoypadDir`）。`navAdmin` 隱藏（非管理員）時照原本行為。
- 頁面資料來源：每日／每週／成就／我的紀錄（積分卡）／兌換用 `state`；我的紀錄表格送 `records`；排行榜送 `board`（狀態機 loading → ready／empty／error，5 秒逾時）；設定頁送 `prefs`／`title`／`anon`。兌換頁的「兌換倖存幣...」開兌換視窗（`ExchangeDialog`），使用者 2026-10-24 要求兌換與兌換紀錄從我的紀錄分出來。屍潮任務頁（`PageHordes.lua`，設計稿 r12）：上方是每日頁同一個屍潮橫幅（沒有進行中的場次時一行說明），接著四格累計（`horde.joined`／`wins`／`kills`／`mvp`，讀 `records` 的統計），再來是 `records.hordes` 的清單框（時間、地點、結果、我的擊殺、得分）；打開時送 `records`，開著時 `state.hordes.last` 換成比清單新的場次就再送一次。成就頁的「屍潮」類跟這一頁同一個條件（`PageHordes.shown()`，即 `state.hordes.on`）：沒開過屍潮的伺服器拿不到，卡片、分類按鈕與「已解鎖／總數」都不算它（`PageAchievements.visible`；使用者 2026-10-26 照建議）；catalog 不動，通知與管理頁照樣找得到。
- 設定頁最後一段「各主題的任務」（預設收起）：`Client.questList()` 從 shared Catalog＋`catalog` 推送算出啟用的每日與每週樣板、乘過難度的目標範圍（和 `Quests` 的 `rollTarget` 同一捨入）與積分，不另送資料：預設值本來就在每個客戶端，`catalog.overrides` 也送給所有玩家，伺服器擋了也藏不住。`state.admin` 或 `quests.playerList` 為 true 才列出；設定關著時管理員看到的那段附註「只有管理員看得到」。套用設定後伺服器重送 `catalog`，清單跟著更新。
- 開視窗送 `watch {on=true}`，關視窗送 `{on=false}`；打開每日頁或成就頁時送 `seen`。
- 追蹤面板（`Hud.lua`）：`ISPanel` 衍生、放在最底層（`backMost`：每次 UI 更新引擎都把它移到最底，`UIManager.java:562-568`），所以每個視窗都蓋在它上面，包括比它早建立的物品欄與上次沒關的角色視窗，拖曳時 `ISPanel` 的 `bringToTop` 也一樣；用頁面同一套 canvas 指令繪製（`Draw.renderOps`），資料一變才重排，`render` 只走指令列。預設在原版左側欄右邊（`getPlayerData(0).equipped` 的右緣＋12），會碰到原版物品欄的標題列時（物品欄看得到、左右重疊、物品欄的 y 在面板標題列底線之上）改放在物品欄標題列下面 6 px；拖過的位置與收合狀態用 `ISLayoutManager` 記在 `layout.ini`（拖完或收合就寫）。顯示條件：MOD 選項開、有追蹤項目、角色活著、沒按 V（`ISUIHandler.allUIVisible`）、Esc 選單沒開；任務視窗開著也照樣顯示（使用者 2026-10-24：按「追蹤」要馬上看到），視窗蓋在它上面。每 500 ms 與資料變動時檢查，介面被藏起來時不自己出現。`hello` 時面板開著就送 `track {on=true}`，選項切換時送 on／off。卡片上的「追蹤」chip 送 `pin`；滿 5 個時其他 chip 停用並以 tooltip 說明。
- 稱號（`Titles.lua`）：`titles` 推送存成 `byUser`。聊天：檔案載入時包住 `ISChat.addLineInChat`（原版在 `OnGameStart` 才把它掛到 `OnAddMessage`，`ISChat.lua:1176`），作者戴著稱號時把訊息換成代理，`getTextWithPrefix()` 在 `[作者]` 後面插入 ` <SPACE> <PUSHRGB:…> 「稱號」 <POPRGB> `（稱號裡的 `<`、`>` 先轉成 `&lt;`、`&gt;`），其他方法轉給原訊息。頭上：每 500 ms 從 `getOnlinePlayers()` 挑 40 格內、有稱號、活著、不在車上的玩家；`OnPreUIDraw` 每幀照原版規則（`IsoGameCharacter.renderlast`／`updateUserName`）檢查後在名字上方一行畫字（黑色陰影＋金色）。兩者都只在多人、伺服器開關 `titles.head`／`titles.chat` 與玩家 MOD 選項都開時生效。
- 稱號清單（設計稿 r13，2026-10-27）：`Draw.titleSources(achs, cfg, no)` 列出每個稱號與條件（成就各級、連續里程碑、新手、本季名次與各榜第一；各榜第一照 `Seasons` 結算，排除 `@points` 榜與沒有賽季期的榜），每列 `{ id, name, group, cond, ach?, tier?, hidden?, hint?, off?, custom?, alt? }`：`custom` 是管理員換掉預設文字、`alt` 是被換掉的預設 id（沒有 `titleSrc` 的舊稱號靠它查條件）。條件文字由 `Draw.achTitleCond(a, tier)`、`streakTitleCond(days, cfg)`、`newbieTitleCond(cfg)` 組。`Draw.seasonTitle(id, cfg)` 解析 `s<季數>_<kind>`，榜單已不存在（拿掉的 MOD）時回 nil。成就的稱號照原始覆寫整份取代預設（`Client.defs` 讀 `catalog.overrides.achievements`，不經 `C.merge` 逐鍵合併；和伺服器 `Config.SCHEMA` 一致）。管理「稱號」分頁（`AdminTitles.lua`，排在「成就」後面，只能看）傳管理員的草稿視圖（`AdminModel.achievements`，含停用、自訂與還沒套用的修改，門檻乘上草稿的 `difficulty.mult`；其他 MOD 的成就來自 `Client.defs()`，乘的是已套用的倍率），依分類分組，停用的變灰加「（停用）」，隱藏成就多一行玩家看到的提示，已結算的前幾季只寫一行（審核期間 `season.reviewNo` 那季還沒發，不算）。玩家「我的紀錄」在稱號選單下面列「我的稱號」：只列已取得的（服主 2026-10-27 選），條件先看 `state.titleSrc`（`a:<achId>:<tier>` 找 `Client.defs().allAch` 的那一級、`streak:<days>`、`newbie`；管理員改名幾次都查得到，服主 2026-10-27），沒有紀錄時用 `titleSources`：同一個 id 有幾個來源時（管理員可以填重複的文字）先用玩家已達成的（`state.achv[ach] >= tier`），其次是其他非隱藏的來源，沒解鎖的隱藏成就不提供條件；都找不到時寫「來源已移除」。`state.titleAt` 新的在前，沒有時間的寫「早期取得」排最後（目錄順序）。
- 屍潮（伺服器見 §5.10）：管理「屍潮」分頁（`AdminHordes.lua`，排在「城鎮」後面）的狀態來自 `horde.status`，切進分頁、每次操作後與按「重新整理」時讀；設定全走變更草稿與底部「套用」。段落順序（方案制設計稿 `temp/plan-presets-1028/`）：開頭一段說明（`HordeNote`，沒有頁標題）；目前狀態（狀態列、開一場列、最近結果）；地點；時段；屍潮方案；波次 · <方案名>；種類 · <方案名>；獎勵 · <方案名>。狀態列寫第 W／N 波、已清、方案名稱（`HordeCurPlan` 的「方案「%6」」）、休息時「M:SS 後下一波」（`nextAt − Client.serverNow()`，用伺服器時鐘，倒數以這次排版為準）；最近結果（清光 C／N 波、發出的分數，達上限另外標）載入完才畫標題，讀取中是清單框的「讀取中」占位；「中止／取消這一場」固定在那一列的列尾。地點列有「地圖」鈕（`Draw.showOnMap`，`Draw.mapAllowed()` 為假時不顯示）；移除地點先 `A.ask({ danger = true })`（「移除後，要回到現場才能再加回來。」）；「用我現在的位置新增」是一般按鈕，地點名稱欄和其他欄位同寬。時段是清單框，每段一筆三行：開始～結束（HH:MM）與每小時機率；「方案」下拉（key `w:p<i>`，只列草稿裡看得到的方案）、「預告」（`hordes.windows.<i>.leadMin`）與「等人到場」（`.waitMin`）分鐘；星期一～日 7 顆切換鈕與移除。`hordes.windows` 整組寫進草稿（欄位是 `.N.from／.to／.chance／.leadMin／.waitMin`，方案下拉與星期鈕直接改 `.N.preset`、`.N.days`）；至少 1 段（只剩 1 段時移除停用）、最多 8 段（`AM.MAX_WINDOWS`，新增照 `Catalog.DEFAULTS.hordes.windows[1]`）；某段沒選星期時那段標錯，頁面的 `check` 擋住「套用」。時段下面的全域表單只剩「每天最多幾場（所有時段合計）」。屍潮方案段：說明「每個方案是一組波次、種類與獎勵…」，一列「編輯方案」下拉（`pre:pick`）、「複製成新方案」（`pre:copy`）、「刪除方案」（`pre:del`），「方案名稱」欄（`hordes.presets.<id>.name`，最多 32 字，`AM.MAX_NAME`；Kahlua 的 `#` 以 UTF-16 字元計），再一行「用到這個方案：<時段>」或「沒有時段用這個方案」。目前編輯的方案存在 `P.pages.hordes.preset`（頁面狀態，不是設定；預設 `"default"`），下面三段的路徑都是 `hordes.presets.<這個 id>.…`。複製：新 id 取 `p2`～`p8` 最小的空號（符合 §3.4 的方案 id 規則），名稱「<原名> 2」、撞名往上加，複製來源合併後的全部欄位，切到新方案並進草稿；滿 8 個（`Contract.LIMIT.MAX_PRESETS`）時按鈕停用、旁邊用警示色寫「最多 8 個方案」。刪除：「預設」的按鈕停用；其他先 `A.ask({ danger = true })`，標題「刪除方案「<名>」」，內文列出會改用「預設」的時段與「按下方「套用」後才生效。」，按鈕「刪除方案」／「保留」；確定後那些時段的 `preset` 改 `"default"`（windows 整組進草稿）、方案本身 `del`，只在草稿裡的方案直接從草稿拿掉，頁面切回「預設」；草稿裡刪掉的方案，名稱退回已套用的值，所以時段預覽的「之前」欄寫名稱、不寫 id。頁面 `check` 另擋：非預設方案名稱空白、所有方案的顯示名稱重複（`name` 為 `""` 的預設方案顯示翻譯的「預設」），訊息寫怎麼改；伺服器的 `validateAll` 也擋（`presetName`／`presetSame`，§3.4），頁面這一層是立即提示。名稱改好後錯誤記號會消失（`A.textField` 重新填值、`A.collect` 收值時都清掉記號）。波次也是清單框：基本隻數、每多 1 人 %、1 人與 4 人的預估（`Catalog.hordeWaveSize`），`.waves` 整組；至少 1 波、最多 10 波（`AM.MAX_WAVES`），新增一波複製最後一列，說明放在「新增一波」那一列下面。新增、移除、方案下拉與星期鈕先把這頁打的值收進草稿（有欄位不合法就不動），清單改完若和套用中的相同就從草稿拿掉。下面是 `.restSec`、`.limitMin`、`.maxAlive`，「場上同時最多」下面列 `horde.status.cull`（伺服器讀到的沙盒 `ZombiesCountBeforeDelete`，讀不到就不列）。時段、波次、方案加滿時「最多 N …」用警示色。種類是清單框：權重大於 0 的種類一列（名稱、權重、占比、每隻積分、耐打（倍）、移除；占比＝權重 ÷ 已登記且權重大於 0 的種類權重總和；耐打是 `.hp.<kind>`，範圍鍵 `hordeHp = { 0.1, 10 }`、可小數，沒設時顯示 1；`AM.check` 對非整數、上限小於 1000 的範圍（`hordeHp`、成長倍率、活動倍率等）把「,」當小數點，`0,5`＝0.5，整數欄位的「,」照舊當千分位刪掉；移除內建種類（`base().kinds` 有的）在任何方案都寫 0、積分不動，其他種類的鍵都刪、送 `del`，只在草稿裡的（剛加入、還沒套用）從草稿拿掉，不送空變更；預設以外的方案一定完整，沒有可以退回的預設值），其餘已登記的種類在框下的下拉選單（選了草稿寫權重 10；沒有自己的積分時寫入一般殭屍那一列目前顯示的積分：欄位上打的值合法就用它，否則草稿的），套用的設定裡有、`horde.status` 沒列出的鍵標「未安裝」、可移除（`del`）；權重寫在 `.kinds.<id>`、積分寫在 `.points.<id>`，維持預設值的欄位不寫成變更。說明多一句「耐打 1 倍照伺服器沙盒的殭屍韌性；2 倍要打兩倍的傷害才會倒。」（「韌性」是原版沙盒選項 `Sandbox_ZToughness` 的繁中名）。獎勵段是「單場積分上限（分）」（`.cap`）、說明與估算框：框內第一行是「「%1」方案估算（每一波都清光）」，下面 1／4／8 人、每一波都清光時發多少（`Catalog.hordeWaveSize`＋`Catalog.hordeMix`＋每隻積分，超過上限的寫上限並標出）。波次預估、占比與估算照欄位上打的值算（`live(pg, key, fallback)`：值合法、而且是這次排版排出、看得到的欄位才用打的值；上次排版沒排出而隱藏的舊欄位（例如剛移除的種類列）不算，改用草稿值），欄位一改就重排（TextField `onChange`）。沒有自己積分的種類（其他 MOD 加的），積分欄位還是繼承來的值時，估算跟著一般殭屍欄位上打的積分走（伺服器發的就是 `points[種類] or points.vanilla`）。確認畫面：時段、波次各寫成一行文字（`A.hordeValue`；時段含方案名稱、預告與等人分鐘）；方案路徑的列寫「方案「<名>」：<欄位標籤>」（`A.fLabel` 對 `hordes.presets.<id>.<欄位>` 用 `F_hordes_<欄位>` 的標籤），整個方案的 set／del 寫「新增方案「<名>」」「刪除方案「<名>」」；權重、積分與耐打列寫出種類名稱。伺服器回的 `why`（`preset`、`presets`、`presetName`、`presetSame`、`presetPart`）由 `A.whyText` 讀 `IGUI_MQ_Admin_Why_<why>`，字串沒有參數、說法對檔案與管理頁都通（大多來自手改 `config.json`），路徑由 `BAD_CONFIG`／`FileBad` 的 `pathLabel` 顯示。`horde.now`／`horde.stop` 先確認、按下就生效（像限時活動）。開一場那一列：「方案」下拉（`now:pre`）只列**已套用**的方案（`AM.get({ overrides, defaults }, …)` 合併，不含草稿；理由同下面的地點），預設選「預設」；「預告」（`now:lead`）與「等人到場」（`now:wait`）初值是 `Catalog.DEFAULTS.hordes.windows[1]` 的 15／60，管理員改過就保留，用 `AM.check` 的 `hordeLead`／`hordeWait` 檢查，不合法時標紅、顯示範圍、不送出；送 `horde.now { lead, wait, preset }`，確認文字寫方案名稱（例：「要用「%1」方案在隨機地點開一場屍潮嗎？玩家現在收到預告，%2 分鐘後開始。」），預告 0 時改成現在開始；套用中的設定沒有地點、地點只在草稿裡時，底列說先按「套用」、不確認也不送（伺服器只看套用的設定，會回 `NO_SPOTS`「請先新增地點」，清單卻看得到剛加的地點；2026-10-26 試玩按了三次）。點「自動屍潮」的文字也會切換開關。`delta.hordes` 走通用的整份取代。`HordeMap.lua`：裝了小地圖才作用，地點前後左右各 10 格一塊區域加一個標記，資料變了才重建、其餘時候回同一張表；檔案載入時與 `OnGameStart` 各試一次註冊。
- 屍潮的玩家介面（多波改版，設計稿 `temp/plan-hordes-1027/`）：追蹤面板最上面一列是屍潮（預告、等人到場、進行中、波與波之間的休息），不算 5 個追蹤名額、沒有 ×，沒有追蹤項目時有屍潮也顯示，倒數只在文字變了才重排。倒數都寫出是什麼的倒數：預告「4:29 後開始」、等人與進行中「剩 52:10」、休息「0:24 後下一波」；超過一波時名稱是「第 W／N 波 · 地點」（休息中「第 W／N 波清光 · 地點」），預告不加（`Draw.hordeName`）；追蹤列的地點照設計稿只寫地點名、不寫城鎮（`Draw.hordeName(h, true)`：帶城鎮時前綴與倒數把地點擠掉，`quest-hui-en-1027a`），橫幅與通知帶城鎮。第二行先寫座標（「x, y · 開始時 30 格內有人就出現」「x, y · 有人走進 30 格內就開始」），長的語言截斷時切掉的是規則、不是座標（harness 檢查 16 語都以 `%1, %2` 開頭）；進行中是進度條與「已清 n／這一波隻數」；休息時「N 後下一波」放在第二行開頭、後面寫下一波會從外圍出現（第一行留給名稱：英文第一行放不下「Wave 2/3 cleared」加地點加倒數）。預告、等人、休息時第二行右邊有「地圖」按鈕（停在上面顯示「在地圖上顯示」）：`Draw.showOnMap(0, x, y)` 開原版世界地圖、中心在地點（`ISWorldMap.ShowWorldMap(playerNum, x, y, 16)`，`ISWorldMap.lua:1500`；小地圖包住它，所以屍潮標記也看得到）；`Draw.mapAllowed()`（`ISWorldMap.IsAllowed()`，`:1491`：教學模式或沙盒關掉世界地圖時為 false）為 false 就不畫；它的點擊範圍是 `p.mapHit`，不在取消追蹤的 `p.hits` 裡。每日頁在限時活動下面放屍潮橫幅（`PageDaily.hordeBlock`／`hordeBanner`，屍潮任務頁同一個）：預告、等人到場、進行中、休息，結束後 10 分鐘內的成功／失敗／取消；這頁 30 秒才重畫，所以剩餘時間以分鐘計。預告寫可能出現的種類、座標與 30 格規則，右邊「N 後開始」（`IGUI_MQ_Horde_StartsIn`，和追蹤面板同一個鍵）；等人與進行中的標題帶波次、右邊「剩 N」（等人是到 `expireAt`、進行中是到 `endsAt`）；進行中寫已清、這一波隻數與我的擊殺，不寫總獎勵；休息寫下一波與地點、右邊「N 後下一波」；成功寫清光幾波、我的擊殺與得分，失敗寫哪一波、原因、清光的波次照發多少，超過一場上限時加一句「每個人照比例縮小」。預告、等人、休息時橫幅右下角有「地圖」按鈕（頁面 pool 的按鈕 `hordeMap`，鍵盤與手把也按得到）。屍潮任務頁清單的結果寫波次：「清光 3／3 波」、多波失敗「失敗：第 3 波時間到（清光 2 波）」、「已取消」；結果欄放不下時換行、那一列跟著變高（ES 的多波失敗原本截掉清光波數，`quest-hui-es-1027b`）。通知：預告與開始（附波數）、開始前 2 分鐘提醒、每波出現（第 W／N 波、隻數、時限）、休息（下一波與倒數）、成功（清光幾波、隻數、人數、發出的總分）、失敗（哪一波、原因、清光的波次照發多少）、取消、個人的 `hordePaid`（得分、清光的波次裡的擊殺；超過上限時加那一句）；通知內文最多 6 行（`Draw.toast`；4 行時 EN 預告最後的種類、ES 到上限那一句被截）。
- 清單框（設計稿 r11，使用者 2026-10-26 選「原版管理員清單」樣式，之後補要「有點顏色交錯」與排行榜、兌換紀錄的表頭）：管理頁與玩家頁的清單都畫成原版管理員清單（`ISSafehousesList.lua:23-31`、`:67-82`）的樣子：直角的 `surface` 底、`border` 外框、表頭帶（`border` 透明度 × 0.3，下緣一條線）、條目之間一條線（× 0.9），每隔一筆整筆上 `hover` 底色（第 2、4、6…筆；一筆可以是好幾列，換行的說明、按鈕列都在同一條色帶裡）。管理頁用 `Flow:list`／`listHead`／`item`／`listEnd`（`AdminPanel.lua`）：框內 `F.ox`／`F.width` 換成框的，各頁的欄位算式不變，自己放位置的按鈕要加 `F.ox`；`F:item()` 記下每筆的上緣，框由頁面 ScrollPanel 的 prerender 在所有子元件底下畫（`A.paintLists`，內容座標，不配置），不是元件，不擋按鈕，ui-mp 的版面檢查也看不到；沒關的框不畫。玩家頁用 Builder 的 `b:list`／`listHead`／`listSep`／`listEnd`（`Draw.lua`）：底色與每筆的色帶先記成指令，下一個 `listSep` 或 `listEnd` 才補高度。

## 8. facade `MinidoracatQuest.v1`（伺服器）

`{ API_MAJOR = 1, API_REVISION = 2, registerPack(spec) → pack | nil, code, registerHordeKind(spec) → true | nil, "invalid_args" }`，`pack.add(player, statId, n) → true | false, code`。規則照設計稿：`modId` 為 `[A-Za-z0-9_-]` 最長 64；每個 MOD 統計 ≤ 32、成就 ≤ 64；每個 modId 每 tick 50 次；`n` 是 0～1000 的有限數；錯誤碼 `invalid_args`、`rate_limited`、`not_ready`。統計與成就 id 自動加 `<modId>:`；`board = true` 的統計進「職業」榜。

`registerHordeKind`（rev 2）：`spec = { modId, id, nameKey, spawn }`；`modId` `^[%w_%-]+$` ≤ 64、`id` `^[%w_%-]+$` ≤ 32、`nameKey` `^[%w_]+$` ≤ 128、`spawn(x, y, z, n)` 是函式，回傳 ArrayList 或 Lua 陣列；鍵 `<modId>:<id>` 最長 64（方案的 `kinds`／`points`／`hp` 鍵的上限）；每個 modId ≤ 8 種、全部外掛 ≤ 32 種；同一個鍵再登記就取代。Quest 管時間、計數與清除；`spawn` 在 pcall 裡呼叫，只收真的 IsoZombie。登記後每個方案的 `hordes.presets.<方案>.kinds.<modId>:<id>` 預設權重 0。方案的 `hp` 倍率乘在 `spawn` 設好的血量上，最高 `Hordes.HP_MAX`（30，§5.10）。消費者用 `type(v1.registerHordeKind) == "function"` 探測。

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
