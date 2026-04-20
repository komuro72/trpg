# 移動関連定数・パラメータの全体棚卸し

## 目的
向き変更コストを「移動速度に比例」で設計するための前提把握。
移動・時間系定数を網羅的に棚卸しし、**Source of Truth の一元化**と**Config Editor 反映**の観点で整理する。

## エグゼクティブサマリー

### 最重要発見

> **`character_data.move_speed` は完全にデッドデータ**

- `CharacterGenerator._convert_move_speed()` が 0-100 スコアを秒/タイルに変換して `character_data.move_speed` に格納している
- しかし **`character_data.move_speed` を読む箇所はコード上に存在しない**（grep で確認済み）
- 実際の移動時間は `MOVE_INTERVAL` 定数のみで決まる：プレイヤー= 0.30s 固定 / AI = 0.40s 固定（種族により ×0.67〜×2.0 倍率あり）
- ステータス UI（OrderWindow）には move_speed が表示されているが、**プレイヤーが見ても挙動には反映されない**

### 主な構造的問題

1. **move_speed が機能していない**：個体差（ステータス・装備）は移動速度に一切反映されない
2. **MOVE_INTERVAL が複数箇所に分散**：`PlayerController.MOVE_INTERVAL` と `UnitAI.MOVE_INTERVAL` の 2 ファイルに別々に定義（値も違う）。GlobalConstants 未登録・Config Editor 不可
3. **game_speed の適用が不統一**：3 種類のパターン（pre-scaled / post-scaled / 未対応）が混在
4. **エネルギー回復・スタン・バフ・自動キャンセルは game_speed の影響を受けない**（バランスの一貫性に問題）
5. **`dark_lord_unit_ai._warp_timer -= delta / game_speed` は game_speed の方向が逆**（バグの可能性）

---

## 1. 移動速度の計算式

### 1-1. 設計上の意図（spec / CLAUDE.md より）

```
最終 move_speed = class_base + rank × class_rank_bonus + sex_bonus + age_bonus + build_bonus + randi() % (random_max + 1)
```

- 0-100 のスコアで生成（[CLAUDE.md:699](../CLAUDE.md#L699)）
- 設定ファイル：
  - [class_stats.json](../assets/master/stats/class_stats.json) — クラスごとの base / rank
  - [enemy_class_stats.json](../assets/master/stats/enemy_class_stats.json) — 敵クラスごとの base / rank
  - [attribute_stats.json](../assets/master/stats/attribute_stats.json) — 性別・年齢・体格の補正値・random_max

### 1-2. 変換式（[character_generator.gd:511-515](../scripts/character_generator.gd#L511)）

```gdscript
## move_speed スコア（0-100）を秒/タイルに変換する
## score=0 → 0.80s（最遅）、score=100 → 0.20s（最速）
static func _convert_move_speed(score: int) -> float:
    return maxf(0.1, 0.8 - float(score) * 0.006)
```

| score | seconds/tile | 備考 |
|---|---|---|
| 0 | 0.80 | 最遅 |
| 50 | 0.50 | — |
| 100 | 0.20 | 最速 |

### 1-3. **実際の利用：完全な dead data**

`character_data.move_speed` は [character_data.gd:104](../scripts/character_data.gd#L104) に定義され、character_generator が値を入れるが、**コード上どこからも読まれていない**：

```bash
$ grep -rn "move_speed" scripts/
character_data.gd:103   # コメント
character_data.gd:104   # 定義
character_generator.gd:115, 263-264   # 書き込みのみ
character_generator.gd:511-515        # 変換関数
config_editor.gd:165, 216             # ステータス編集 UI
```

**= 全て「書き込み」または「定義」のみ。読み取りは存在しない。**

実際の 1 マス移動時間は：

| 主体 | 実装 | 値 |
|---|---|---|
| プレイヤー | `MOVE_INTERVAL / game_speed` ([player_controller.gd:45, 1262, 1269, 1410](../scripts/player_controller.gd#L45)) | `const MOVE_INTERVAL = 0.30` 固定 |
| AI（基底） | `MOVE_INTERVAL / game_speed` ([unit_ai.gd:13, 2245-2246](../scripts/unit_ai.gd#L13)) | `const MOVE_INTERVAL = 0.40` 固定 |
| Wolf AI | `MOVE_INTERVAL * 0.67` ([wolf_unit_ai.gd:23-24](../scripts/wolf_unit_ai.gd#L23)) | 標準の 1.5 倍速。**game_speed 未適用**！ |
| Zombie AI | `MOVE_INTERVAL * 2.0` ([zombie_unit_ai.gd:28-29](../scripts/zombie_unit_ai.gd#L28)) | 標準の半速。**game_speed 未適用**！ |

→ **Wolf / Zombie のオーバーライドは `_get_move_interval()` を return しているが、`game_speed` で割っていない**ため、ゲーム速度設定が無視される（バグ）

### 1-4. ガード中 50% 減速（[player_controller.gd:1263-1264, 1270-1271, 1410-1412](../scripts/player_controller.gd#L1263)）

```gdscript
var duration := MOVE_INTERVAL / GlobalConstants.game_speed
if character.is_guarding:
    duration *= 2.0
character.move_to(new_pos, duration)
```

- 「`MOVE_INTERVAL` を 2 倍 = 移動時間 2 倍 = 速度半減」というロジック
- **プレイヤーのみ**（player_controller 内で完結）
- AI には適用されない（AI はガードしない仕様）
- `_get_move_interval()` を経由しないため、Wolf / Zombie ガード時挙動は未定義（ただし AI はガードしないので問題なし）

### 1-5. 装備品による移動速度補正

**結論：存在しない**

- 装備マスター（[assets/master/items/](../assets/master/items/)）の `base_stats` キーには `power`, `block_*`, `physical_resistance`, `magic_resistance` のみ
- `move_speed` キーは未定義
- CLAUDE.md でも明記：「補正がかからないもの：defense_accuracy（防御技量）・**move_speed**・leadership・obedience・max_hp・max_mp」

### 1-6. GRID_SIZE の影響

- 移動時間は秒/タイル単位。タイルピクセルサイズ `GRID_SIZE` は移動時間に影響しない
- GRID_SIZE は描画とヒット判定のみに使用（[global_constants.gd:14](../scripts/global_constants.gd#L14)）

---

## 2. 時間系定数の全洗い出し

### 2-1. 全定数一覧

| 定数 | 値 | 単位 | 定義場所 | Config Editor | game_speed 適用 |
|---|---|---|---|---|---|
| **`PlayerController.MOVE_INTERVAL`** | 0.30 | s/tile | [player_controller.gd:45](../scripts/player_controller.gd#L45)（`const`） | ❌ 未登録 | ✅ pre-scaled |
| **`UnitAI.MOVE_INTERVAL`** | 0.40 | s/tile | [unit_ai.gd:13](../scripts/unit_ai.gd#L13)（`const`） | ❌ 未登録 | ✅ pre-scaled / post-scaled 混在 |
| `UnitAI.WAIT_DURATION` | 3.0 | s | [unit_ai.gd:14](../scripts/unit_ai.gd#L14)（`const`） | ❌ 未登録 | ✅ post-scaled |
| `UnitAI._REEVAL_FALLBACK` | 1.5 | s | [unit_ai.gd:54](../scripts/unit_ai.gd#L54)（`const`） | ❌ 未登録 | ❌ raw delta（未適用） |
| `UnitAI.QUEUE_MIN_LEN` | 3 | 個 | [unit_ai.gd:15](../scripts/unit_ai.gd#L15) | ❌ 未登録 | — |
| `PartyLeader.REEVAL_INTERVAL` | 1.5 | s | [party_leader.gd:20](../scripts/party_leader.gd#L20)（`const`） | ❌ 未登録 | ❌ raw delta（未適用） |
| `NpcLeaderAI.AUTO_ITEM_INTERVAL` | 2.0 | s | [npc_leader_ai.gd:22](../scripts/npc_leader_ai.gd#L22)（`const`） | ❌ 未登録 | ✅ 閾値で除算（pre-scaled） |
| `DarkLordUnitAI.WARP_INTERVAL` | 3.0 | s | [dark_lord_unit_ai.gd:12](../scripts/dark_lord_unit_ai.gd#L12)（`const`） | ❌ 未登録 | ⚠️ `delta / game_speed`（**逆方向バグの可能性**） |
| `DarkLordUnitAI.FLAME_DURATION` | 3.0 | s | [dark_lord_unit_ai.gd:15](../scripts/dark_lord_unit_ai.gd#L15)（`const`） | ❌ 未登録 | — (FlameCircle へ渡す) |
| `DebugWindow.REDRAW_INTERVAL` | 0.20 | s | [debug_window.gd:38](../scripts/debug_window.gd#L38)（`const`） | ❌ 未登録 | ❌ raw delta |
| `MessageWindow.SCROLL_DURATION` | 0.15 | s | [message_window.gd:21](../scripts/message_window.gd#L21)（`const`） | ❌ 未登録 | ❌ raw delta |
| `TimeStopOverlay.FADE_DURATION` | 0.1 | s | [time_stop_overlay.gd:9](../scripts/time_stop_overlay.gd#L9)（`const`） | ❌ 未登録 | ❌ raw delta |
| **`GlobalConstants.TURN_DELAY`** | 0.15 | s | [global_constants.gd:280](../scripts/global_constants.gd#L280) | ✅ Effect | ✅ pre-scaled |
| `GlobalConstants.AUTO_CANCEL_FLASH` | 0.25 | s | [global_constants.gd:283](../scripts/global_constants.gd#L283) | ✅ Effect | ❌ raw delta |
| `GlobalConstants.SLIDING_STEP_DUR` | 0.12 | s | [global_constants.gd:286](../scripts/global_constants.gd#L286) | ✅ Effect | ✅ pre-scaled |
| `GlobalConstants.ENERGY_RECOVERY_RATE` | 3.0 | /秒 | [global_constants.gd:273](../scripts/global_constants.gd#L273) | ✅ Character | ❌ raw delta |
| `GlobalConstants.STUN_PULSE_HZ` | 3.0 | Hz | [global_constants.gd:321](../scripts/global_constants.gd#L321) | ✅ Effect | ❌ raw delta |
| `GlobalConstants.CONDITION_PULSE_HZ` | 3.0 | Hz | [global_constants.gd:142](../scripts/global_constants.gd#L142) | ✅ Effect | ❌ raw delta |
| `GlobalConstants.PROJECTILE_SPEED` | 2000.0 | px/s | [global_constants.gd:306](../scripts/global_constants.gd#L306) | ✅ Effect | ❌ raw delta |
| `GlobalConstants.BUFF_EFFECT_ROT_SPEED_DEG` | 60.0 | deg/s | [global_constants.gd:298](../scripts/global_constants.gd#L298) | ✅ Effect | ❌ raw delta |
| `GlobalConstants.WHIRLPOOL_ROT_SPEED_DEG` | 270.0 | deg/s | [global_constants.gd:301](../scripts/global_constants.gd#L301) | ✅ Effect | ❌ raw delta |
| クラス JSON `slots.Z.pre_delay` / `post_delay` | クラスごと | s | [assets/master/classes/*.json](../assets/master/classes/) | ✅ 味方/敵クラスタブ | ✅ post-scaled |
| クラス JSON `slots.V.pre_delay` / `post_delay` / `duration` / `tick_interval` | クラスごと | s | 同上 | ✅ 同上 | ⚠️ pre/post_delay は post-scaled、duration / tick_interval は raw |
| 個別敵 JSON `pre_delay` / `post_delay` | 個体ごと | s | [assets/master/enemies/*.json](../assets/master/enemies/) | ✅ 敵一覧タブ | ✅ post-scaled |
| `PlayerController._v_slot_cooldown` 設定値 | 2.0 | s | [player_controller.gd](../scripts/player_controller.gd) | ❌ 未登録 | ❌ raw delta |
| `Character.stun_timer` 設定値 | slot.duration | s | [character.gd:206](../scripts/character.gd#L206) | スロット経由 | ❌ raw delta |
| `Character.defense_buff_timer` 設定値 | slot.duration | s | [character.gd:224](../scripts/character.gd#L224) | スロット経由 | ❌ raw delta |
| `Character._energy_recovery_accum` | — | — | [character.gd:670](../scripts/character.gd#L670) | — | ❌ raw delta |
| `FlameCircle._tick_interval` 設定値 | slot.tick_interval | s | [flame_circle.gd:15](../scripts/flame_circle.gd#L15) | スロット経由 | ❌ raw delta |
| `FlameCircle._duration` 設定値 | slot.duration | s | 同上 | スロット経由 | ❌ raw delta |
| `GameMap._npc_enemy_activate_timer` | 2.0 | s | [game_map.gd:226](../scripts/game_map.gd#L226) | ❌ 未登録 | ❌ raw delta |
| `GameMap._stair_cooldown` | — | s | [game_map.gd:207](../scripts/game_map.gd#L207) | ❌ 未登録 | ❌ raw delta |
| `DialogueWindow._reject_timer` | 1.8 | s | [dialogue_window.gd:58](../scripts/dialogue_window.gd#L58) | ❌ 未登録 | ❌ raw delta |
| `MessageWindow._reject_timer` | 1.5 | s | [message_window.gd:170](../scripts/message_window.gd#L170) | ❌ 未登録 | ❌ raw delta |

### 2-2. game_speed 適用パターンの 3 分類

#### パターン A: post-scaled（カウントダウン側で `delta * game_speed`）
タイマー値は「ゲーム内秒」で持ち、毎フレームの delta に game_speed を掛ける：
- PlayerController の `_pre_delay_remaining` / `_post_delay_remaining` ([:528, :644](../scripts/player_controller.gd#L528))
- UnitAI の `_timer`（MOVING / WAITING / ATTACKING_PRE / ATTACKING_POST）([:378, :400, :406, :427](../scripts/unit_ai.gd#L378))

#### パターン B: pre-scaled（タイマー初期化時に `/ game_speed`）
タイマー値は「実時間秒」で持ち、初期化時に game_speed で割る：
- PlayerController の `_turn_timer = TURN_DELAY / game_speed` ([:1249](../scripts/player_controller.gd#L1249))
- `walk_in_place(MOVE_INTERVAL / game_speed)` ([:508](../scripts/player_controller.gd#L508))
- `move_to(_, MOVE_INTERVAL / game_speed)` ([:1262, :1269, :1410](../scripts/player_controller.gd#L1262))
- `_get_move_interval()`（基底）は `MOVE_INTERVAL / game_speed` を返す ([:2246](../scripts/unit_ai.gd#L2246))
- NpcLeaderAI の閾値 `AUTO_ITEM_INTERVAL / game_speed` ([:292](../scripts/npc_leader_ai.gd#L292))

#### パターン C: 未対応（raw delta）
game_speed の影響を受けない：
- `_auto_cancel_remaining`（PlayerController [:552, :606](../scripts/player_controller.gd#L552)）
- `Character.stun_timer` / `defense_buff_timer` ([:206, :224](../scripts/character.gd#L206))
- `Character._energy_recovery_accum` ([:670](../scripts/character.gd#L670))
- `PartyLeader._reeval_timer` ([:188](../scripts/party_leader.gd#L188))
- `UnitAI._reeval_timer`（フォールバック）([:352](../scripts/unit_ai.gd#L352))
- `FlameCircle._elapsed` / `_tick_elapsed`（[:89, :93](../scripts/flame_circle.gd#L89)）
- `GameMap._npc_enemy_activate_timer` / `_stair_cooldown` 等
- DebugWindow / MessageWindow / TimeStopOverlay / Dialogue 系
- 飛翔体 / エフェクトの回転速度

#### パターン D: 異常パターン
- **`DarkLordUnitAI._warp_timer -= delta / GlobalConstants.game_speed`** ([:43](../scripts/dark_lord_unit_ai.gd#L43))
  - game_speed=2.0 のとき：`-= delta / 2.0` → タイマーが**ゆっくり**減る → ワープ間隔が**長く**なる
  - 期待挙動：game_speed=2.0 ならワープも 2 倍速で発生すべき → **逆方向**
  - パターン A の正しい形は `-= delta * game_speed`、または閾値側を `/ game_speed`

### 2-3. 重複・類似タイマー

#### REEVAL_INTERVAL 系
- `PartyLeader.REEVAL_INTERVAL = 1.5` ([party_leader.gd:20](../scripts/party_leader.gd#L20)) — リーダー意思決定の再評価
- `UnitAI._REEVAL_FALLBACK = 1.5` ([unit_ai.gd:54](../scripts/unit_ai.gd#L54)) — 個体 AI のフォールバック再評価
- 値が同じだが用途が異なる。GlobalConstants 化時は別定数として整理が必要

#### MOVE_INTERVAL 系
- `PlayerController.MOVE_INTERVAL = 0.30` — プレイヤー専用
- `UnitAI.MOVE_INTERVAL = 0.40` — AI 全体（敵・味方 NPC 共通）
- 値の違いがあるが、これは「プレイヤーが少し速く動く」設計か、または偶然の不整合か不明
- history.md の記録：1.2 → 0.40 に変更済み（[history.md:1487, 1585](history.md#L1487)）。プレイヤーの 0.30 はそれより速い

---

## 3. 移動関連の非対称性・不整合

### 3-1. プレイヤー vs AI の移動計算式

| 項目 | プレイヤー | AI（味方/敵） |
|---|---|---|
| 1 マス移動時間 | `MOVE_INTERVAL=0.30 / game_speed` | `MOVE_INTERVAL=0.40 / game_speed`（基底）|
| 個体差反映 | なし（move_speed 未参照） | なし（同上） |
| 種族差反映 | — | Wolf=×0.67、Zombie=×2.0（ただし game_speed 未適用） |
| ガード減速 | あり（`× 2.0`） | なし |
| 向き変更コスト | TURN_DELAY=0.15s | なし |

### 3-2. 味方 vs 敵
- 味方 NPC・敵ともに UnitAI 経由のため**完全対称**（個体差・種族差を除く）

### 3-3. クラス / 種族差
- `move_speed` ステータスはクラス・種族で異なる値が定義されている（[class_stats.json](../assets/master/stats/class_stats.json), [enemy_class_stats.json](../assets/master/stats/enemy_class_stats.json)）：
  | クラス / 種族 | base | rank |
  |---|---|---|
  | fighter-sword | 30 | 0 |
  | fighter-axe | 25 | 0 |
  | archer | 35 | 5 |
  | magician-fire | 30 | 0 |
  | magician-water | 25 | 0 |
  | healer | 25 | 0 |
  | scout | 25 | 0 |
  | zombie | 10 | 0 |
  | wolf | 40 | 5 |
  | salamander | 10 | 0 |
  | harpy | 40 | 0 |
  | dark-lord | 30 | 0 |
- **これらの値は実際の挙動に反映されない**（`character_data.move_speed` が読まれないため）
- 唯一の種族差は Wolf / Zombie の `_get_move_interval()` オーバーライド（クラス JSON ではなくコードに直書き）

### 3-4. ガード中の減速
- プレイヤー専用（[player_controller.gd:1263-1264, 1270-1271, 1410-1412](../scripts/player_controller.gd#L1263)）
- AI はガードシステムを持たない（X/B ホールドはプレイヤー入力）
- ガード自体の入力遅延・解除遅延はなし（`is_action_pressed` を毎フレーム読むだけ）

### 3-5. move_speed 値の分布
**※ 実際は反映されないため、設計上の値のみ記録**

スコアを `_convert_move_speed` で秒に変換した目安（rank=B、補正なしと仮定）：
- 最速：archer / wolf（base=35〜40、rank ボーナスあり）→ 0.6 弱の秒/タイル
- 中速：fighter-sword / magician-fire / dark-lord（base=30）→ 0.62 秒/タイル
- 標準：その他（base=25）→ 0.65 秒/タイル
- 最遅：zombie / salamander（base=10）→ 0.74 秒/タイル

→ これらが反映されていれば、本来のテンポは MOVE_INTERVAL=0.40 よりかなり遅い。**もし move_speed を有効化すると現状より全体的に遅くなる**

---

## 4. 定数の命名・配置の一貫性

### 4-1. 命名統一感
- **概念が混在**：
  - `MOVE_INTERVAL` — 1 タイル移動「時間」（秒）。"interval" は本来「間隔」だが実態は「duration」
  - `move_speed` — character_data のフィールド。スコアではなく秒/タイル変換後の値（こちらも実態は時間）
  - `_get_move_interval()` — 関数名。返り値は「時間」だが ENGLISH 的には "interval"
  - **どれも「時間」を表しているのに名前が "speed" / "interval" / "duration" で揺れている**
- `TURN_DELAY` — 「向き変更の遅延時間」。比較的明確
- `WAIT_DURATION` — 「待機時間」。明確
- `*_DUR` / `*_DURATION` / `*_INTERVAL` / `*_RATE` の使い分けが場当たり的

### 4-2. コメントと実装の乖離
- [character.gd:579](../scripts/character.gd#L579) `## ガード中は向きを変更しない（guard_facing を維持）` — `guard_facing` 変数は存在しない（[`investigation_turn_cost.md`](investigation_turn_cost.md) で指摘済み）
- [character_data.gd:103-104](../scripts/character_data.gd#L103) `## 移動速度（秒/タイル。低いほど速い。標準 0.4。_convert_move_speed() で 0-100 スコアから変換）` — 値は格納されるが**読まれない**ことに言及なし
- [character_generator.gd:511-513](../scripts/character_generator.gd#L511) `## move_speed スコア（0-100）を秒/タイルに変換する` — 同上、変換結果が使われない事実が伝わらない
- [unit_ai.gd:2243-2244](../scripts/unit_ai.gd#L2243) `## zombie=遅い(MOVE_INTERVAL*2.0) / wolf=速い(MOVE_INTERVAL*0.67) など` — game_speed 未適用の事実に言及なし

### 4-3. 配置の一貫性
- 移動関連定数は **3 ファイルに分散**：
  - `GlobalConstants.gd`: `TURN_DELAY` / `SLIDING_STEP_DUR` / `ENERGY_RECOVERY_RATE` / `AUTO_CANCEL_FLASH`
  - `PlayerController.gd`: `MOVE_INTERVAL`
  - `UnitAI.gd`: `MOVE_INTERVAL` / `WAIT_DURATION` / `_REEVAL_FALLBACK`
- `PlayerController` と `UnitAI` の `MOVE_INTERVAL` は**同名・別値・別ファイル**で SoT が分裂している

---

## 5. Config Editor への反映状況

### 5-1. 現状

| 編集可能 | 編集不可（GlobalConstants 内） | 編集不可（const / 各クラス内） |
|---|---|---|
| `TURN_DELAY` (Effect) | — | `PlayerController.MOVE_INTERVAL` |
| `AUTO_CANCEL_FLASH` (Effect) | — | `UnitAI.MOVE_INTERVAL` |
| `SLIDING_STEP_DUR` (Effect) | — | `UnitAI.WAIT_DURATION` |
| `ENERGY_RECOVERY_RATE` (Character) | — | `UnitAI._REEVAL_FALLBACK` |
| `STUN_PULSE_HZ` (Effect) | — | `PartyLeader.REEVAL_INTERVAL` |
| `PROJECTILE_SPEED` (Effect) | — | `NpcLeaderAI.AUTO_ITEM_INTERVAL` |
| 各種スロット duration / pre_delay / post_delay（クラス JSON 経由） | — | `DarkLordUnitAI.WARP_INTERVAL` / `FLAME_DURATION` |
| | | `DebugWindow.REDRAW_INTERVAL` ほか UI 系 |

### 5-2. カテゴリ分類の提案（外出し候補）

#### 「ゲーム挙動・バランスに影響」する定数（Movement または UnitAI / PartyLeader カテゴリへ）

| 定数 | 提案カテゴリ | 理由 |
|---|---|---|
| `PlayerController.MOVE_INTERVAL` | **新カテゴリ「Movement」** または UnitAI | プレイヤーの移動テンポを直接決める。バランス調整対象 |
| `UnitAI.MOVE_INTERVAL` | 同上 | AI 全体の移動テンポ。バランス調整対象 |
| `UnitAI.WAIT_DURATION` | UnitAI | AI の待機時間。テンポ・難易度に影響 |
| `UnitAI._REEVAL_FALLBACK` | UnitAI | AI 思考頻度。挙動の機敏さに影響 |
| `PartyLeader.REEVAL_INTERVAL` | PartyLeader | リーダー意思決定頻度。AI 全体の機敏さに影響 |
| `NpcLeaderAI.AUTO_ITEM_INTERVAL` | NpcLeaderAI | NPC のアイテム自動装備頻度 |
| `DarkLordUnitAI.WARP_INTERVAL` | （新カテゴリ「Boss」または UnitAI） | ボス挙動 |
| `DarkLordUnitAI.FLAME_DURATION` | 同上 | 同上 |
| Wolf / Zombie の倍率（`× 0.67` / `× 2.0`） | （個別 JSON 化が望ましい） | 種族個性。コードに直書きされている |

#### 「視覚演出のみ」（Effect カテゴリのまま）
- `DebugWindow.REDRAW_INTERVAL` / `MessageWindow.SCROLL_DURATION` / `TimeStopOverlay.FADE_DURATION`
- `DialogueWindow._reject_timer` / `MessageWindow._reject_timer`
- `Character` 内のスタンスピン速度（`delta * 4.0` ハードコード）

### 5-3. 「ゲーム挙動 vs 演出」の判断指針

| 判断 | 例 |
|---|---|
| ゲーム挙動 | キャラの移動・攻撃・回復・AI 思考の時間 |
| 演出 | UI の点滅・フェード・補間時間、エフェクトの回転速度 |
| グレー（迷う） | ENERGY_RECOVERY_RATE は **挙動**（攻撃可能タイミングを左右する）→ Character |
| グレー（迷う） | STUN_PULSE_HZ は **演出**（スタン秒数は別管理）→ Effect |

---

## 6. 向き変更コスト設計への示唆

### 6-1. 「向き変更時間 = 1 マス移動時間 × X%」方式の実装可否

**実装難度：中。ただし前提条件が複数ある。**

#### 必要な前提整備

1. **`character_data.move_speed` を実際に読むようにする**
   - 現状：MOVE_INTERVAL の固定値で全キャラが動く
   - 変更後：`character.character_data.move_speed` を参照して個体ごとの秒/タイルを決める
   - 影響範囲：`PlayerController._try_move` / `UnitAI._get_move_interval` / Wolf / Zombie のオーバーライド
   - 設計判断：MOVE_INTERVAL を「クラス/種族の標準値」として残し、個体補正で乗算するか、`move_speed` を絶対値として使うか

2. **MOVE_INTERVAL の集約**
   - PlayerController / UnitAI で別々の値 → 統一するか、別物として明示するか
   - GlobalConstants 化して Config Editor 編集可能にする

3. **Wolf / Zombie のオーバーライドの扱い**
   - 現状：`_get_move_interval()` を直接書き換え（game_speed 未適用バグあり）
   - 個体 JSON で `move_speed` 倍率として表現すれば SkillExecutor 化と同様の構造に揃う

#### 実装案

```gdscript
# Character か CharacterData に：
func get_move_duration() -> float:
    return character_data.move_speed  # 既に秒/タイル

func get_turn_duration() -> float:
    return get_move_duration() * GlobalConstants.TURN_TIME_RATIO  # 例: 0.4
```

- `TURN_TIME_RATIO = 0.4` のような Config Editor 定数を新設
- プレイヤーの TURN_DELAY を「MOVE_INTERVAL × TURN_TIME_RATIO」に置換
- AI 側にも同様のターン遅延を導入する場合、UnitAI の `_State.MOVING` 突入時に向き変更が必要なら `_State.TURNING` 経由にする

### 6-2. 基準キャラの候補

「最速の移動はこのキャラ」という基準を一つ決める必要がある：
- **archer**（base=35, rank=5、最速候補）
- **wolf**（base=40, rank=5、敵側最速）
- **fighter-sword**（base=30、人間平均）

`_convert_move_speed` の `seconds = 0.8 - score × 0.006` の式から、score=100 で 0.20s。基準を「score=100 = 0.20s」とするか、現状の MOVE_INTERVAL=0.30 を基準値として再校正するか要検討。

### 6-3. アンチパターン

- **ガード中の減速 (`× 2.0`) が TURN_DELAY に波及**
  - 現状：TURN_DELAY は `_try_move` 内のガード判定の**前**にあるブロックで `is_guarding` チェック済み（[player_controller.gd:1243-1252](../scripts/player_controller.gd#L1243)）
  - つまり：ガード中は TURN_DELAY 自体が**スキップ**される（向き変更しない）
  - 「TURN_DELAY を MOVE_INTERVAL × X% に変える」場合、ガード中は計算前に return する現状ロジックが効くため波及はしない
  - ただし「ガード中も向き変更可能」という別仕様に変える場合は、ガード時の MOVE_INTERVAL × 2.0 が TURN_DELAY にも反映されるよう注意が必要

- **game_speed の二重適用**
  - move_duration を `character_data.move_speed / game_speed` で計算した上で、さらに `delta * game_speed` で減算すると 1.0 に戻ってしまう
  - SoT を「ゲーム内秒で持ち、カウントダウンで game_speed を掛ける」（パターン A）に統一するなら、move_duration 自体は `character_data.move_speed`（生の秒）のまま使う

- **AI の REEVAL_INTERVAL がレスポンスに影響**
  - PartyLeader が 1.5 秒ごとに再評価 → 向き変更を伴うアクションも 1.5 秒粒度で再選定
  - TURN_DELAY を細かくしても、AI の意思決定が 1.5 秒遅れるなら体感は変わらない
  - REEVAL_INTERVAL の game_speed 未適用も合わせて改善する必要がある

### 6-4. 関連調査

- 向き変更の現状実装は [`docs/investigation_turn_cost.md`](investigation_turn_cost.md) 参照
- 攻撃クールダウン（pre_delay / post_delay）の game_speed 適用経緯は [`docs/history.md`](history.md) の "PRE_DELAY / TARGETING の game_speed 適用" 項を参照

---

## 7. 設計上の問題点まとめ（優先度付き）

### 高（バグ・機能不全）
1. **`character_data.move_speed` が完全 dead data**
   - 個体差・装備差が一切反映されない
   - ステータス UI に表示される値が実挙動と乖離 → プレイヤーを誤導する可能性
2. **Wolf / Zombie の `_get_move_interval()` が game_speed 未適用**
   - 速度設定（タイトル / ポーズメニュー）を変えても Wolf / Zombie だけ実時間が変わらない
3. **`DarkLordUnitAI._warp_timer` の `delta / game_speed` が逆方向**
   - 高速設定でボス行動が遅くなる

### 中（一貫性・保守性）
4. **`MOVE_INTERVAL` の SoT 分裂**
   - PlayerController と UnitAI に別々の `const` で定義
   - GlobalConstants 化と Config Editor 反映が必要
5. **game_speed 適用の 3 パターン混在**
   - スタン・バフ・自動キャンセル・回復は raw delta（実時間）
   - 攻撃 pre/post とプレイヤー TURN_DELAY はゲーム時間
   - ENERGY_RECOVERY_RATE は raw だが他のリソース系（攻撃クールダウン等）はゲーム時間
   - 設計原則の宣言が必要：「全タイマーは `delta * game_speed` で減算する」を統一ポリシーにできるか
6. **REEVAL_INTERVAL が PartyLeader と UnitAI で重複**
   - 値は同じ 1.5 だが、整理が必要

### 低（ドキュメント・命名）
7. **`MOVE_INTERVAL` / `move_speed` / `_get_move_interval()` の命名が混乱**
   - 「速度」「間隔」「時間」が混在。実態は全て「秒/タイル」
8. **コメントと実装の乖離**
   - `guard_facing` / `move_speed=0.4 標準` 等のコメント残骸
9. **move_speed 値の設計（0-100 スコア → 0.20-0.80 秒）が現状の 0.30 / 0.40 秒と整合していない**
   - もし有効化したら大半のキャラが現状より遅くなる
   - スケール再校正が必要

---

## 参照
- [docs/investigation_turn_cost.md](investigation_turn_cost.md) — 向き変更コストの現状調査（重複部分はこちらを参照）
- [docs/spec.md](spec.md) — 詳細仕様
- [docs/history.md](history.md) — 過去の変更経緯（MOVE_INTERVAL 値変更履歴：行 1487, 1580, 1585、game_speed 統一：行 2218, 2237）
- [CLAUDE.md](../CLAUDE.md) — ステータス定義・キャラ生成方針
