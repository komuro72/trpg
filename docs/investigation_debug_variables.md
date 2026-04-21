# PartyStatusWindow 表示拡充のための状態変数棚卸し調査

## 調査概要

- **調査日付**：2026-04-21
- **調査対象ファイル数**：23 ファイル（PartyLeader 系 7 + UnitAI 系 16。ただし UnitAI 系タスク指示は 15 ファイル = 本体 `unit_ai.gd` + サブクラス 14）
- **調査目的**：PartyStatusWindow（F1 で開くデバッグウィンドウ）の表示内容を拡充するための事前調査。「現在値を見たい変数」（状態変数・キャッシュ値・タイマー・フラグ・キュー等）を網羅的に棚卸しする

### 調査対象ファイル

**PartyLeader 系（7 ファイル）**
- `scripts/party_leader.gd`（基底クラス）
- `scripts/party_leader_ai.gd`
- `scripts/party_leader_player.gd`
- `scripts/npc_leader_ai.gd`
- `scripts/enemy_leader_ai.gd`
- `scripts/goblin_leader_ai.gd`
- `scripts/hobgoblin_leader_ai.gd`
- `scripts/wolf_leader_ai.gd`

**UnitAI 系（15 ファイル）**
- `scripts/unit_ai.gd`（基底クラス）
- `scripts/npc_unit_ai.gd`
- `scripts/goblin_unit_ai.gd`
- `scripts/goblin_archer_unit_ai.gd`
- `scripts/goblin_mage_unit_ai.gd`
- `scripts/hobgoblin_unit_ai.gd`
- `scripts/wolf_unit_ai.gd`
- `scripts/zombie_unit_ai.gd`
- `scripts/harpy_unit_ai.gd`
- `scripts/salamander_unit_ai.gd`
- `scripts/dark_knight_unit_ai.gd`
- `scripts/dark_mage_unit_ai.gd`
- `scripts/dark_priest_unit_ai.gd`
- `scripts/dark_lord_unit_ai.gd`
- `scripts/lich_unit_ai.gd`

### スコープ（列挙対象）

- 時間とともに変わる `var`（状態変数・キャッシュ値・タイマー・フラグ等）
- リアルタイム評価の結果を保持する辞書（例：`_combat_situation`）
- UnitAI のステート・キュー・ターゲット・残タイマー等

### 除外対象

- `const` / static 定数（`REEVAL_INTERVAL` / `WAIT_DURATION` / `RANK_VALUES` / `MP_ATTACK_COST` 等）
- 初期化時にしか変わらない参照（`_member` / `_map_data` / `_player` 等の識別参照）
- Config Editor で編集できる設定値
- 単なる Node 参照（`_party_ref` は参照先が変わり得ないので除外）

「状態」と「参照」の判断に迷う場合は両方挙げ、分類を備考に明記した。

### 優先度の凡例

- **高**：バグ調査や挙動理解でよく参照する（状態遷移・キャッシュ結果・ターゲット・現在のキュー等）
- **中**：たまに見たい（タイマー残値・カウンタ・クールダウン・主要フラグ類）
- **低**：普段は不要（内部用の最適化キャッシュ・古典的フラグ等）

### PartyStatusWindow での「表示済」について

現在 PartyStatusWindow（`scripts/party_status_window.gd`）が `pm.get_global_orders_hint()` 経由で間接的に表示しているのは以下。これらは備考欄に「**表示済**」と記す。
- `_combat_situation` の中身のうち `situation` / `power_balance` / `hp_status` / `full_party_*` / `nearby_allied_*` / `nearby_enemy_*` の合計 15 キー
- メンバー単位：`Character.hp` / `max_hp` / `is_stunned` / `is_guarding` / `is_player_controlled` / `character_data.character_name` / `rank` / `current_floor`（これらは Character 側のプロパティで本調査対象外）
- UnitAI 由来：`get_debug_goal_str()`（_state / _queue 先頭 / _attack_target / _target / _leader_ref / _move_policy をまとめた 1 行表現）

---

## PartyLeader 系

| クラス | 変数名 | 型 | 意味 | 変化タイミング | 表示候補の優先度 | 備考 |
|-------|-------|---|------|-------------|----------------|------|
| PartyLeader | `_party_strategy` | `Strategy` (enum int) | 現在のパーティー戦略（ATTACK / FLEE / WAIT / DEFEND / EXPLORE / GUARD_ROOM） | `_assign_orders()` → `_apply_range_check(_evaluate_party_strategy())`。1.5s タイマー or notify_situation_changed() | **高** | `get_current_strategy_name()` で日本語化可。get_global_orders_hint() の `battle_policy` キーに反映されて**表示済**（ただし戦略直接値ではなく battle_policy 変換後） |
| PartyLeader | `_prev_strategy` | `Strategy` (enum int) | 前回の戦略（変更検出用） | `_assign_orders()` で `_party_strategy` と比較→代入 | 低 | ログ出力判定用。UI 表示の必要性低 |
| PartyLeader | `_combat_situation` | `Dictionary` | 最新の戦略評価結果。`_evaluate_strategic_status()` の戻り値 | 1.5s タイマー or `notify_situation_changed()` で再評価 | **高** | キー：`situation` / `power_balance` / `hp_status` / `full_party_strength` / `full_party_rank_sum` / `full_party_tier_sum` / `full_party_hp_ratio` / `nearby_allied_strength` / `nearby_allied_rank_sum` / `nearby_allied_tier_sum` / `nearby_allied_hp_ratio` / `nearby_enemy_strength` / `nearby_enemy_rank_sum` / `nearby_enemy_tier_sum`。**すべて get_global_orders_hint 経由で表示済** |
| PartyLeader | `_reeval_timer` | `float` | 戦略再評価タイマー残秒数（初期 0.0、REEVAL_INTERVAL=1.5s で再評価→リセット） | `_process(delta)` で減算 / `notify_situation_changed()` で 0 に | **中** | 「次の再評価まであと何秒」が見えると AI の反応性デバッグに便利 |
| PartyLeader | `_party_members` | `Array[Character]` | パーティーメンバーリスト（死亡しても配列から削除されない） | `setup()` で初期設定後、構造的には不変（メンバー個体の hp が変化） | 中 | サイズが `alive/total` 表示に使われる。Array そのものよりメンバーの生死比率が見たい |
| PartyLeader | `_unit_ais` | `Dictionary` | member.name → UnitAI のマップ | setup() で構築後、動的変化なし | 低 | 参照用。表示価値は低い |
| PartyLeader | `_visited_areas` | `Dictionary` | 訪問済みエリアID集合（全 UnitAI で共有） | UnitAI `_generate_queue()` 冒頭で現在エリアを追加 | **中** | 探索進捗（訪問済み数 / 全エリア数）として表示価値あり |
| PartyLeader | `_global_orders` | `Dictionary` | Party.global_orders への参照（move / battle_policy / target / on_low_hp / item_pickup / hp_potion / sp_mp_potion） | プレイヤーの OrderWindow 操作で更新 | **高** | 指示内容が見えると AI 挙動の予測ができる。get_global_orders_hint で一部**表示済** |
| PartyLeader | `_friendly_list` | `Array[Character]` | 敵 AI 用の攻撃対象友好キャラリスト | set_friendly_list() で初期設定後、要素の hp/visibility が変化 | 低 | 参照型の識別リスト。生死は Character 側で見られる |
| PartyLeader | `_all_members` | `Array[Character]` | 全パーティー合算メンバー（戦況判断で同陣営他パ戦力加算に使用） | set_all_members() で更新 | 低 | 戦況判断の中間計算用 |
| PartyLeader | `joined_to_player` | `bool` | 合流済み NPC パーティーか | set_follow_hero_floors() で更新 | **中** | NPC が合流済みかの判定。プレイヤー合流前後で挙動変化 |
| PartyLeader | `log_enabled` | `bool` | ログ出力抑制フラグ | 一時パーティー生成時に false | 低 | デバッグ出力制御。UI 表示価値低 |
| PartyLeader | `_initial_count` | `int` | 初期メンバー数（逃走判定の基準） | setup() で確定後不変 | 低 | 不変値。RANK_VALUES と同様に初期化後固定 |
| PartyLeader | `_prev_leader_floor` | `int` | リーダーの前回フロア（変化検知用・-999=未初期化） | _process で更新 | 低 | 内部フラグ。UI 価値低 |
| PartyLeaderPlayer | `_enemy_list` | `Array[Character]` | プレイヤー用攻撃対象敵リスト | set_enemy_list() で更新 | 低 | 参照型。中身の生死は Character 側 |
| NpcLeaderAI | `_enemy_list` | `Array[Character]` | 敵リスト（攻撃対象） | set_enemy_list() | 低 | 同上 |
| NpcLeaderAI | `_was_refused` | `bool` | 会話で一度断られたフラグ（二度と自発申し出しない） | mark_refused() で true に（恒久） | **中** | NPC 会話挙動のデバッグに有用 |
| NpcLeaderAI | `_auto_item_timer` | `float` | 自動装備・ポーション受け渡しの実行タイマー（0.0〜AUTO_ITEM_INTERVAL/game_speed） | `_process(delta)` で増加 → リセット | 低 | 2s 周期の内部タイマー。表示価値低 |
| NpcLeaderAI | `has_fought_together` | `bool` | 同じ敵パーティーと共闘した実績（合流スコアに加点） | notify_fought_together() | **中** | 合流交渉の難易度に影響。表示すると会話判定を予測できる |
| NpcLeaderAI | `has_been_healed` | `bool` | プレイヤー側ヒーラーに回復された実績（合流スコア加点） | notify_healed() | **中** | 同上 |
| NpcLeaderAI | `_prev_target_floor` | `int` | 前回の目標フロア（変化検出・ログ出力抑制用。-1=未初期化） | `_get_target_floor()` 内で比較→更新 | 低 | 内部ログ抑止用 |
| NpcLeaderAI | `suppress_floor_navigation` | `bool` | フロア遷移スコア判断をスキップして常に "explore" を返すフラグ | 外部から設定 | **中** | 未加入 NPC の挙動を制御する可視フラグ |

### PartyLeader 系の統計
- 行数：22 行（`_reeval_timer` / `_prev_leader_floor` 等の内部タイマーを含む）

---

## UnitAI 系

| クラス | 変数名 | 型 | 意味 | 変化タイミング | 表示候補の優先度 | 備考 |
|-------|-------|---|------|-------------|----------------|------|
| UnitAI | `obedience` | `float` | 従順度（0.0=完全自律 / 1.0=完全従順）。サブクラスで `_init()` に上書き | 初期化後不変 | 低 | ほぼ定数扱い（サブクラスで _init() 固定値）。変化しないため除外候補 |
| UnitAI | `_state` | `_State` (enum int) | ステートマシン状態（IDLE / MOVING / WAITING / ATTACKING_PRE / ATTACKING_POST） | 毎フレーム `_process()` 内で遷移 | **高** | `get_debug_goal_str()` 末尾に `_state_label()` で**表示済**（IDLE/MOV/WAIT/ATKp/ATKpost） |
| UnitAI | `_goal` | `Vector2i` | 現在の移動目標タイル | `_start_action` / `_step_toward_goal` で更新 | **高** | 行動先の可視化に有用。`get_debug_goal_str()` で部分的に**表示済**（move_to_explore のみ座標） |
| UnitAI | `_timer` | `float` | 状態タイマー残秒数（MOVING / WAITING / ATTACKING_PRE / ATTACKING_POST 共通） | `_process` の delta 減算 | **高** | 「攻撃前の pre_delay 残秒数」「wait 残秒数」がわかる |
| UnitAI | `_attack_target` | `Character` | 現在の攻撃対象（ATTACKING_PRE / POST 中の確定ターゲット） | `_start_action("attack")` で設定 | **高** | `get_debug_goal_str()` の攻撃状態で**表示済** |
| UnitAI | `_order` | `Dictionary` | PartyLeader から最後に受け取ったオーダー | `receive_order()` で毎回更新 | 中 | 辞書中身は個別フィールドに展開されている（`_combat` 等）。_order 自体より展開後の値のほうが有用 |
| UnitAI | `_queue` | `Array` | アクションキュー（辞書の配列） | `_generate_queue()` で生成、`_pop_action()` で先頭消費 | **高** | キュー長・先頭 action が行動予測に有用。`get_debug_goal_str()` で先頭 action が**表示済** |
| UnitAI | `_current_action` | `Dictionary` | 実行中アクション（_pop_action で _queue から移動したもの） | `_pop_action()` / `_complete_action()` | **高** | 現在何をしているかの核心。`get_debug_goal_str()` に反映済み |
| UnitAI | `_combat` | `String` | 戦闘方針 `attack` / `defense` / `flee` / `standby` | `receive_order` で order 辞書から代入 | 中 | 個別メンバーの指示方針 |
| UnitAI | `_on_low_hp` | `String` | 低HP時行動 `keep_fighting` / `retreat` / `flee` | 同上 | 中 | 個別指示 |
| UnitAI | `_party_fleeing` | `bool` | パーティーレベル撤退指示 | receive_order | **中** | パーティー全体の FLEE 中かどうか |
| UnitAI | `_target` | `Character` | リーダーから指定された攻撃対象（未確定の狙い） | receive_order | **高** | 行動予測に必須。`get_debug_goal_str()` で部分**表示済** |
| UnitAI | `_reeval_timer` | `float` | フォールバック再評価タイマー残秒（オーダーなし時用） | `_process(delta)` で減算 | 低 | 通常経路（PartyLeader から毎回 order 発行）では使わない |
| UnitAI | `_strategy` | `int` | 内部判断キャッシュ（0=ATTACK / 1=FLEE / 2=WAIT） | receive_order / _fallback_evaluate_action で更新 | **中** | UnitAI レベルでの最終判断結果。戦略と異なることがあり（party_fleeing や種族 should_self_flee の影響）有用 |
| UnitAI | `_move_policy` | `String` | 移動方針（explore / same_room / cluster / guard_room / standby / spread / follow / stairs_down / stairs_up / gather） | receive_order で order.move から代入 | **高** | メンバー個別の移動戦略。`get_debug_goal_str()` で部分**表示済** |
| UnitAI | `_battle_formation` | `String` | 戦闘隊形 `surround` / `rush` / `rear` | receive_order | 中 | 経路選定（ASTAR / ASTAR_FLANK）に影響 |
| UnitAI | `_hp_potion` | `String` | HP ポーション自動使用指示 (`use` / `never`) | receive_order | 中 | ポーション自動使用の可視化 |
| UnitAI | `_sp_mp_potion` | `String` | エナジーポーション自動使用指示 | receive_order | 中 | 同上 |
| UnitAI | `_item_pickup` | `String` | アイテム取得指示 `aggressive` / `passive` / `avoid` | receive_order | 中 | アイテム走行の挙動に影響 |
| UnitAI | `_special_skill` | `String` | 特殊攻撃指示 `aggressive` / `strong_enemy` / `disadvantage` / `never` | receive_order | 中 | V スロット発動判定 |
| UnitAI | `_combat_situation` | `Dictionary` | PartyLeader から受け取った戦況評価結果のコピー | receive_order | 中 | PartyLeader 側の同名辞書と同内容（リーダー側で**表示済**）。メンバー単位で見る必要性は低い |
| UnitAI | `_leader_ref` | `Character` | 隊形計算の基準リーダーキャラ | receive_order の leader フィールド | 中 | 参照先が変わり得る（リーダー交代・joined_to_player 切替）ので状態扱い |
| UnitAI | `_guard_room_area` | `String` | guard_room 時に記憶した部屋 ID（初回設定後不変） | move_policy="guard_room" 時に一度だけ設定、他ポリシーで "" にリセット | 低 | guard_room 移動用の内部状態 |
| UnitAI | `_home_position` | `Vector2i` | スポーン地点（敵の縄張り帰還の基点） | setup() で初期化後不変 | 低 | 本来は不変参照。_apply_range_check / guard_room 動作の見える化に有用 |
| UnitAI | `_floor_following` | `bool` | フロア追従中か（_is_passable で友好キャラをすり抜け可能に） | `_generate_queue` 冒頭で都度判定・代入 | **中** | 「リーダーを追って階段へ向かっている最中」がわかる |
| UnitAI | `_follow_hero_floors` | `bool` | hero が別フロアにいるとき階段追従するか（合流済みメンバーのみ true） | setup / set_follow_hero_floors() | 低 | ほぼ初期化時に固定 |
| UnitAI | `_all_floor_items` | `Dictionary` | フロアアイテム辞書参照 `{floor_idx: {Vector2i: item}}` | set_floor_items() で一度だけ設定、中身は game_map が動的更新 | 低 | 参照型 |
| UnitAI | `_vision_system` | `VisionSystem` | explore 行動に使う参照 | set_vision_system() | 低 | 参照。中身の変化は VisionSystem 側で管理 |
| UnitAI | `_visited_areas` | `Dictionary` | パーティー共有の訪問済みエリア辞書（参照） | `_generate_queue` で現在エリアを追加 | 中 | PartyLeader 側と同実体。explore 進捗に有用 |
| UnitAI | `_all_members` | `Array[Character]` | 占有チェック用の全メンバー（参照） | set_all_members() | 低 | 参照。中身変化は Character 側 |
| UnitAI | `_party_peers` | `Array[Character]` | 同一パーティーメンバー（heal/buff 対象限定用） | set_party_peers() | 低 | 初期設定後不変 |
| GoblinArcherUnitAI | （なし） | — | — | — | — | UnitAI の変数セットのみ。MIN_CLOSE_RANGE は const |
| GoblinMageUnitAI | （なし） | — | — | — | — | UnitAI の変数のみ。MP_ATTACK_COST は const |
| DarkMageUnitAI | （なし） | — | — | — | — | 同上 |
| LichUnitAI | `_lich_water` | `bool` | 次の攻撃が水弾かどうか（火/水交互切り替え） | `_on_after_attack()` で toggle | **中** | Lich 固有。UI 表示価値は低めだが挙動理解に有用 |
| DarkLordUnitAI | `_warp_timer` | `float` | ワープ間隔タイマー残秒（WARP_INTERVAL=3.0s 周期） | `_process(delta)` で減算（`delta / game_speed` の逆方向バグあり※） | **高** | ラスボスの次ワープまでの残時間。表示価値大。※投稿済みの逆方向バグは docs/investigation_movement_constants.md 参照 |
| NpcUnitAI | （なし） | — | — | — | — | UnitAI の変数セットのみ |
| GoblinUnitAI | （なし） | — | — | — | — | 同上 |
| HobgoblinUnitAI | （なし） | — | — | — | — | 同上 |
| WolfUnitAI | （なし） | — | — | — | — | 同上 |
| ZombieUnitAI | （なし） | — | — | — | — | 同上 |
| HarpyUnitAI | （なし） | — | — | — | — | 同上 |
| SalamanderUnitAI | （なし） | — | — | — | — | UnitAI の変数のみ。MIN_CLOSE_RANGE は const |
| DarkKnightUnitAI | （なし） | — | — | — | — | UnitAI の変数のみ |
| DarkPriestUnitAI | （なし） | — | — | — | — | UnitAI の変数のみ |

### UnitAI 系の統計
- 行数：37 行（基底 31 + 派生固有 2 + 「なし」プレースホルダ 9 = 42。うち実データ行は 33。※「なし」行を除外した実質データ行は 33） 
  - 分母の数え方により、「実変数を持つ行」は 33 行、「プレースホルダ含む全行」は 42 行

### 補遺：メンバー個体の状態判定関数

UnitAI 内の `_is_*` / `_can_*` / `_should_*` パターンの関数を網羅し、メンバー個体の状態を変数ではなく関数経由で表現しているものを洗い出した。PartyStatusWindow への表示候補の 2 次取得口として利用できる。

分類：
- **(A) リーダー依存**：`_combat_situation` / `_order` 等 PartyLeader から受け取った情報の読み出しのみ
- **(B) メンバー固有判定**：メンバー個体のステータス・位置・所属クラス・サブクラス固有ロジックを参照

#### _is_combat_safe()
- 分類：(A) リーダー依存
- 概要：戦況が SAFE（同エリアに敵なし）かどうかを返す。アイテム取得指示 `passive` の発動ゲートに使う
- 判定根拠：`_combat_situation["situation"]`（リーダー側の評価結果を order 経由で受領したもの）のみ参照

#### _is_stair_tile(pos)
- 分類：(B) メンバー固有判定（補助関数）
- 概要：指定タイルが階段（STAIRS_DOWN / STAIRS_UP）かどうかを返す
- 判定根拠：`_map_data.get_tile(pos)`。メンバー個体の状態は見ないがフロア追従・探索で使われる補助

#### _is_walkable_for_self(pos)
- 分類：(B) メンバー固有判定
- 概要：`_member` にとって歩行可能か判定（非友好キャラは安全エリアに入れない制約を含む）
- 判定根拠：`_map_data.is_walkable_for(pos, _member.is_flying)` / `_member.is_friendly` / `_map_data.is_safe_tile(pos)`

#### _is_dest_occupied_by_other(pos)
- 分類：(B) メンバー固有判定（互換エイリアス）
- 概要：旧名。`_is_dest_blocked_by_other(pos)` に委譲するだけ
- 判定根拠：下記 `_is_dest_blocked_by_other` と同じ

#### _is_dest_blocked_by_other(pos)
- 分類：(B) メンバー固有判定
- 概要：移動先座標が他キャラの確定位置でブロックされているか調べる。離脱中（is_pending）の相手は無視
- 判定根拠：`_all_members[*].grid_pos / is_flying / current_floor / is_pending() / get_pending_grid_pos()`・`_player` 同様

#### _is_passable(pos)
- 分類：(B) メンバー固有判定
- 概要：通行可能チェック。飛行・地上レイヤー別、フロア追従中は友好キャラすり抜け可、pending 目的地もブロック
- 判定根拠：`_member.is_flying` / `_floor_following` / `_all_members[*]` 各種状態 / `_player` 状態

#### _can_attack_target(target, atype)
- 分類：(B) メンバー固有判定
- 概要：攻撃タイプ別の攻撃可否判定（melee: 隣接地上のみ / ranged: 射程内 / dive: 隣接地上）
- 判定根拠：`_member.attack_range` / `_member.grid_pos` / `target.is_flying` / `target.grid_pos`

#### _should_use_special_skill()
- 分類：(A) リーダー依存
- 概要：`_special_skill` 指示と戦況から V スロット発動すべきかを判定（aggressive / strong_enemy / disadvantage / never）
- 判定根拠：`_special_skill`（order 由来）・`_combat_situation["power_balance" / "hp_status"]`（リーダー評価結果）

#### _can_rush_slash_through()
- 分類：(B) メンバー固有判定
- 概要：突進斬り（fighter-sword）の経路判定。前方最大2マスに敵がいて、着地可能な空きマスがあるか
- 判定根拠：`_member.facing` / `_member.grid_pos` / `_enemy_on_tile()` / `_is_empty_floor()`

#### _is_empty_floor(pos)
- 分類：(B) メンバー固有判定（補助関数）
- 概要：指定タイルが歩行可能でかつ誰も占有していないか（突進斬りの着地判定）
- 判定根拠：`_map_data.is_walkable_for(pos, false)` / `_all_members[*].grid_pos / current_floor`

#### _should_ignore_flee()
- 分類：(B) メンバー固有判定（サブクラスフック）
- 概要：FLEE 指示を無視する種族（強気キャラ）が true を返す。基底は常に false
- 判定根拠：サブクラスで固定値 return。ステータスは参照しない（種族＝クラス判定そのもの）
- **サブクラスのオーバーライド有無**：DarkKnightUnitAI / DarkLordUnitAI / DarkMageUnitAI / DarkPriestUnitAI / HarpyUnitAI / HobgoblinUnitAI / LichUnitAI / SalamanderUnitAI / ZombieUnitAI（9 種族が true を返す）

#### _should_self_flee()
- 分類：(B) メンバー固有判定（サブクラスフック）
- 概要：自己判断で逃走するか（ゴブリン系が HP 低下時に true を返す）。基底は常に false
- 判定根拠：サブクラス側で `_member.hp / _member.max_hp` を `SELF_FLEE_HP_THRESHOLD (0.3)` と比較（メンバーステータス参照あり）
- **サブクラスのオーバーライド有無**：GoblinUnitAI / GoblinArcherUnitAI / GoblinMageUnitAI（ゴブリン系 3 種で HP30% 未満時 true）

#### _can_attack()
- 分類：(B) メンバー固有判定（サブクラスフック）
- 概要：メンバーが攻撃可能な状態か（MP 不足の魔法系が false を返す）。基底は常に true
- 判定根拠：サブクラス側で `_member.energy` と MP_ATTACK_COST を比較（エネルギーの実値参照あり）
- **サブクラスのオーバーライド有無**：GoblinMageUnitAI / DarkMageUnitAI / LichUnitAI（魔法系 3 種で MP 不足時 false）

#### _has_v_slot_cost()
- 分類：(B) メンバー固有判定
- 概要：V スロットのエネルギーコストが足りているかを返す
- 判定根拠：`_member.character_data.v_slot_cost` と `_member.energy`

#### _count_adjacent_enemies() / _count_enemies_in_range(range_tiles)
- 分類：(B) メンバー固有判定（bool ではないが状態判定扱い）
- 概要：隣接 8 マス（斜め含む）または半径 N タイル内の敵数を返す。特殊攻撃の発動判定に使用
- 判定根拠：`_member.grid_pos` / `_all_members[*]` の位置・陣営・生死

#### _enemy_on_tile(pos)
- 分類：(B) メンバー固有判定（補助関数）
- 概要：指定タイルに敵キャラが占有しているか
- 判定根拠：`_all_members[*]` の位置・陣営・生死

#### 補遺の統計
- 抽出した判定関数の総数：**17 関数**（`_is_*` 5 + `_can_*` 2 + `_should_*` 2 + フック 3 + 補助 5 = 17）
- 分類内訳：(A) リーダー依存 = **2**（`_is_combat_safe` / `_should_use_special_skill`）／ (B) メンバー固有判定 = **15**
- サブクラスオーバーライド持ち：3 種類のフックに対して計 15 オーバーライド（ignore_flee×9 + self_flee×3 + can_attack×3）

---

## Character 系

`class_name Character` は `scripts/character.gd` の 1 ファイルのみ（`extends Character` なし）。派生クラスは存在しないため Character 本体の `var` と getter 系関数のみを列挙する。初期化時にのみ値が確定する参照（`character_data` 等）は「不変」と明記したうえで含める。

| 種別 | 名前 | 型 | 意味 | 変化タイミング | 表示候補の優先度 | 備考 |
|-----|------|---|------|-------------|----------------|------|
| var    | `_all_chars` | `Array` (static) | 全 Character 静的リスト（競合チェック用） | `_ready()` で append / `_exit_tree()` で erase | 低 | 静的共有配列。個体の状態ではない |
| var    | `grid_pos` | `Vector2i` | 現在のグリッド座標 | `move_to()` 進捗 50% / `sync_position()` / `abort_move()` | **高** | **既に表示済**（DebugWindow の `[Fx]` やメンバー行位置） |
| var    | `facing` | `Direction` | 向き（DOWN/UP/LEFT/RIGHT） | `move_to()` / `face_toward()` / `complete_turn()` | **中** | 方向インジケーター等で間接的に表示済 |
| var    | `character_data` | `CharacterData` | 個体データ参照（クラス・装備・名前・ステータス素値） | 初期化時に代入後不変 | 低 | 不変。クラス ID・名前等の取得口として頻出（2026-04-21 再分類で 中 → 低） |
| var    | `join_index` | `int` | パーティー加入順（左パネル表示順） | `Party.add_member()` で設定後不変 | 低 | 不変値・UI ソート用 |
| var    | `is_player_controlled` | `bool` | プレイヤー直接操作中フラグ | 操作切替時に更新 | **高** | **既に表示済**（`★` 印・get_global_orders_hint 経由） |
| var    | `hp` | `int` | 現在 HP | ダメージ・回復で変化 | **高** | **既に表示済**（HP:x/y） |
| var    | `max_hp` | `int` | 最大 HP | 初期化時に `character_data.max_hp` で設定後不変 | 低 | **既に表示済**（HP:x/y の分母）。不変値。2026-04-21 再分類で 中 → 低 |
| var    | `energy` | `int` | 現在エネルギー（UI 上 MP/SP 表示） | 攻撃消費・`_recover_energy()`・`use_energy()`・`use_consumable()` | **高** | 未表示。V スロット発動可否・ポーション自動使用判断に直結 |
| var    | `max_energy` | `int` | 最大エネルギー | 初期化時設定後不変 | 低 | 未表示。energy 分母として併記候補。不変値。2026-04-21 再分類で 中 → 低 |
| var    | `power` | `int` | 物理/魔法威力（素値＋装備補正） | `refresh_stats_from_equipment()` で再計算 | 低 | ほぼ不変（装備変更時のみ更新）。2026-04-21 再分類で 中 → 低 |
| var    | `skill` | `int` | 物理/魔法技量（命中・クリティカル率基礎） | 初期化時のみ | 低 | ほぼ不変（装備補正なし） |
| var    | `attack_range` | `int` | 射程（装備補正込み） | `refresh_stats_from_equipment()` | 低 | ほぼ不変 |
| var    | `is_flying` | `bool` | 飛行キャラか | 初期化時のみ（character_data から） | 低 | 不変 |
| var    | `last_attacker` | `Character` | 最後にダメージを与えた相手（ドロップ帰属追跡） | `take_damage()` で更新 | 低 | 死亡帰属用。表示価値低 |
| var    | `current_floor` | `int` | 現在フロア（0=最上層） | フロア遷移で変化 | **高** | **既に表示済**（`[Fx]` プレフィックス）。別フロア判定で頻出 |
| var    | `_energy_recovery_accum` | `float` | エネルギー回復の端数蓄積（0.0〜1.0） | `_recover_energy()` で増加→整数化時リセット | 低 | 内部最適化用 |
| var    | `is_stunned` | `bool` | スタン状態（水魔法等） | `apply_stun()` / `_process()` タイマー消化 | **高** | **既に表示済**（`[ス]` アイコン） |
| var    | `stun_timer` | `float` | スタン残秒 | `apply_stun()` で maxf、`_process()` 減算 | **中** | 表示拡張候補（例：`[ス2.1s]`） |
| var    | `_stun_effect` | `Node2D` | スタンエフェクトノード（スタン中のみ存在） | `apply_stun()` / `_remove_stun_effect()` | 低 | 内部参照。is_stunned で判別可 |
| var    | `is_sliding` | `bool` | スライディング特殊攻撃中（無敵） | `SkillExecutor.execute_sliding()` / 完了時 | **中** | take_damage 無視中か見えると挙動理解が早い |
| var    | `defense_buff_timer` | `float` | 防御バフ残秒（0=なし） | `apply_defense_buff()` / `_process()` 減算 | **中** | バフ持続の可視化 |
| var    | `_buff_effect` | `Node2D` | バリアエフェクトノード（バフ中のみ存在） | `apply_defense_buff()` / `_remove_buff_effect()` | 低 | 内部参照。defense_buff_timer で判別可 |
| var    | `is_friendly` | `bool` | 友好陣営フラグ（NPC・味方側） | 初期化時設定後不変 | 低 | 不変。party_color と近い意味。2026-04-21 再分類で 中 → 低 |
| var    | `joined_to_player` | `bool` | プレイヤーパーティー合流済みか | PartyManager から伝播 | **高** | **既に表示済**（パーティー色分岐・表示済の青/水色色分け） |
| var    | `current_order` | `Dictionary` | 個別指示（move / battle_formation / combat / target / on_low_hp / item_pickup / special_skill / heal） | OrderWindow 操作で変化 | **中** | 既に UnitAI 側 `_order` 展開後の値として**表示済**。キャラ側生コピーの需要は低い |
| var    | `placeholder_color` | `Color` | プレースホルダー描画色（画像なし時） | 設定後不変 | 低 | 描画専用・不変 |
| var    | `party_color` | `Color` | パーティーリング色（setter で redraw） | PartyManager から設定 | 低 | 視覚のみ・表示価値低（色分けは既に表示済み） |
| var    | `party_ring_visible` | `bool` | パーティーリング表示可否 | 会話接触で true に | 低 | 視覚のみ |
| var    | `is_leader` | `bool` | リーダーフラグ（二重リング） | PartyManager 設定後不変 | 低 | 既に表示済（リーダー行ヘッダ）。不変。2026-04-21 再分類で 中 → 低 |
| var    | `is_targeting_mode` | `bool` | ターゲット選択モード中（構えスプライト切替） | PlayerController ステート遷移 | **中** | プレイヤー操作時の攻撃フェーズ可視化 |
| var    | `is_attacking` | `bool` | AI 攻撃モーション中 | UnitAI ATTACKING_PRE/POST で ON/OFF | **中** | UnitAI._state の ATKp/ATKpost と連動（既に表示済） |
| var    | `is_targeted` | `bool` | ターゲットとして選択中（白輝かせ） | ターゲット選択処理で ON/OFF | 低 | 視覚フィードバック用 |
| var    | `highlight_override` | `Color` | ハイライト乗数（FieldOverlay から設定） | TARGETING 中に game_map が設定 | 低 | 視覚のみ |
| var    | `is_guarding` | `bool` | ガード中（X/B ホールド） | PlayerController で ON/OFF | **高** | **既に表示済**（`[ガ]` アイコン） |
| var    | `_sprite` | `Sprite2D` | メインスプライトノード | `_setup_sprite()` で生成後不変 | 低 | Node 参照 |
| var    | `_has_texture` | `bool` | テクスチャ読み込み成功したか | `_load_top_sprite()` | 低 | 描画分岐用 |
| var    | `_tex_top` | `Texture2D` | トップ画像キャッシュ | `_load_walk_sprites()` 等で読み込み | 低 | キャッシュ。不変 |
| var    | `_tex_walk1` | `Texture2D` | 歩行1画像キャッシュ | 同上 | 低 | キャッシュ |
| var    | `_tex_walk2` | `Texture2D` | 歩行2画像キャッシュ | 同上 | 低 | キャッシュ |
| var    | `_tex_guard` | `Texture2D` | ガード画像キャッシュ | 同上 | 低 | キャッシュ |
| var    | `_tex_attack` | `Texture2D` | 攻撃画像キャッシュ | 同上 | 低 | キャッシュ |
| var    | `_outline_material` | `ShaderMaterial` | アウトライン用シェーダマテリアル | `_setup_outline_material()` で生成 | 低 | 視覚専用 |
| var    | `_visual_from` | `Vector2` | 位置補間の開始ワールド座標 | `move_to()` / `walk_in_place()` | 低 | 描画補間内部用 |
| var    | `_visual_to` | `Vector2` | 位置補間の終了ワールド座標 | 同上 | 低 | 同上 |
| var    | `_visual_elapsed` | `float` | 位置補間の経過秒 | `_update_visual_move()` で増加 | 低 | 内部タイマー |
| var    | `_visual_duration` | `float` | 位置補間の総秒数（0=補間なし） | `move_to()` / `walk_in_place()` / 完了時 0 | **中** | `is_moving()` の裏。移動中か判別できる |
| var    | `_pending_grid_pos` | `Vector2i` | 移動先グリッド（半マス到達で grid_pos に反映） | `move_to()` / 進捗 50% / `abort_move()` | **中** | 移動予約の可視化（衝突デバッグで有用） |
| var    | `_grid_pos_committed` | `bool` | grid_pos 確定済みか（false=半マス待ち） | 同上 | 低 | `is_pending()` ヘルパ経由の内部状態 |
| var    | `_turn_target_facing` | `Direction` | 向き変更アニメ中の目標向き | `start_turn_animation()` / `complete_turn()` | 低 | 内部状態 |
| var    | `_turn_tween` | `Tween` | 向き変更 Tween | 同上 | 低 | 内部参照 |
| getter | `get_condition()` | `String` | HP% に基づく状態ラベル（healthy / wounded / injured / critical） | hp 変化時に自動反映 | **高** | **既に表示済**（色判定・DebugWindow 色分け） |
| getter | `is_moving()` | `bool` | 視覚的な移動アニメ中か（`_visual_duration > 0.0`） | hp 非依存・毎フレーム問い合わせ | **中** | PlayerController の先行入力バッファ判定 |
| getter | `get_occupied_tiles()` | `Array[Vector2i]` | 占有グリッド一覧（移動中は旧＋新の 2 マス） | 移動中は 2 マス、それ以外 1 マス | 低 | 複数マス占有対応の拡張ポイント |
| getter | `is_pending()` | `bool` | 移動先が確定前（t<50%）か | 移動中のみ true | **中** | 衝突判定・押し出しで重要 |
| getter | `get_pending_grid_pos()` | `Vector2i` | 移動先グリッド（移動中でなければ grid_pos） | 移動中のみ pending を返す | **中** | AI の衝突予約チェックで頻用 |
| getter (static) | `_direction_to_rotation(dir)` | `float` | Direction → 回転角 | 静的変換 | 低 | 計算ユーティリティ |
| getter (static) | `_calc_turn_delta_rad(...)` | `float` | 最短回転角計算 | 静的変換 | 低 | 計算ユーティリティ |
| getter | `get_move_duration()` | `float` | 1 マス移動の論理秒（move_speed 逆比例・ガード時 2 倍・下限 0.10s） | character_data.move_speed / is_guarding で動的 | **高** | Step 1-B 後のキャラ速度デバッグに直結。Wolf/Zombie の実速確認 |
| getter (static) | `_damage_label(dmg)` | `String` | ダメージ量→段階ラベル（小/中/大/特大） | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_battle_name(ch)` | `String` | バトルメッセージ用表示名 | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_weapon_action(attacker, mode)` | `String` | 攻撃動詞フレーズ生成 | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_make_segs(raw)` | `Array` | セグメント配列変換ヘルパ | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_party_name_color(ch)` | `Color` | 所属別名前色 | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_damage_label_color(dmg)` | `Color` | ダメージラベル色 | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_damage_is_huge(dmg)` | `bool` | 特大ダメージ判定（太字用） | 静的変換 | 低 | メッセージ生成補助 |
| getter (static) | `_char_display_name(ch)` | `String` | 表示名（個別名→ID→node.name フォールバック） | 静的変換 | 低 | ログ出力補助 |
| getter (static) | `_dir_to_jp(dir)` | `String` | 方向文字列 → 日本語 | 静的変換 | 低 | ログ出力補助 |
| getter (static) | `dir_to_vec(dir)` | `Vector2i` | Direction → グリッド方向ベクトル | 静的変換 | 低 | 計算ユーティリティ |
| getter | `_calc_attack_direction(attacker)` | `String` | 攻撃者方向（front/left/right/back） | take_damage() 内部で毎回算出 | 低 | 防御判定の内部補助 |
| getter | `_calc_block_power_front_guard()` | `int` | ガード中正面の合計防御強度 | 毎攻撃算出 | 低 | 計算補助 |
| getter | `_calc_block_per_class(direction)` | `int` | 防御強度 3 フィールド独立ロールのブロック合計 | 毎攻撃算出 | 低 | 計算補助 |

### Character 系の統計
- var：**50 行**（うち static 1 = `_all_chars`、setter 付き 6 = `party_color` / `party_ring_visible` / `is_leader` / `is_targeting_mode` / `is_attacking` / `is_guarding`）
- getter：**20 行**（2026-04-21 に dead code `get_direction_multiplier` を削除したため 21 → 20）
- 合計：**70 行**

### 優先度内訳（2026-04-21 再分類後）
再分類の原則：「ゲーム中に一度でも変化する状態」を 中 以上、「初期化後不変」「装備変更時のみ変化」「描画キャッシュ」を 低 に寄せる。

- **高**：10 行（`grid_pos` / `is_player_controlled` / `hp` / `energy` / `current_floor` / `is_stunned` / `joined_to_player` / `is_guarding` / `get_condition()` / `get_move_duration()`）
- **中**：12 行（`facing` / `stun_timer` / `is_sliding` / `defense_buff_timer` / `current_order` / `is_targeting_mode` / `is_attacking` / `_visual_duration` / `_pending_grid_pos` / `is_moving()` / `is_pending()` / `get_pending_grid_pos()`）
- **低**：48 行（不変参照・装備変更時のみ変化・内部最適化キャッシュ・描画専用・メッセージ生成補助の static 群など）

### 再分類で 中 → 低 に移したもの（2026-04-21）
- `character_data` — 初期化時代入後不変
- `max_hp` — 初期化時設定後不変
- `max_energy` — 初期化時設定後不変
- `power` — 装備変更時のみ変化（ほぼ不変）
- `is_friendly` — 初期化時設定後不変
- `is_leader` — PartyManager 設定後不変

### 所見
- **既に表示済の項目が多い**：`hp` / `max_hp` / `grid_pos` / `current_floor` / `is_stunned` / `is_guarding` / `is_player_controlled` / `joined_to_player` / `get_condition()` は PartyStatusWindow で既表示。Character 層で新しく見たい状態は `energy` / `max_energy` / `defense_buff_timer` / `is_sliding` あたりに集中する
- **dead code 削除完了（2026-04-21）**：`get_direction_multiplier()`（static）は `character.gd` から物理削除。現行ダメージ計算で方向は防御可否のみに影響する仕様（CLAUDE.md「命中・被ダメージ計算」節）どおり。あわせて `move_to()` 内のコメント「`guard_facing を維持`」を「`facing を維持`」に修正（`guard_facing` は存在しない変数だった）
- **setter 経由 redraw 群**（`party_color` / `party_ring_visible` / `is_leader` / `is_targeting_mode` / `is_attacking` / `is_guarding`）は視覚連動のため変化頻度は低いが、is_targeting_mode / is_attacking / is_guarding は操作モードの可視化に有用。UnitAI._state と Character.is_attacking は連動するため、どちらか一方だけ表示すれば十分
- **エネルギー系の可視化価値が高い**：`energy` / `max_energy` はポーション自動使用・V スロット発動可否・ヒーラー回復判定の全てに影響するが現状未表示。拡張時の第一候補
- **Character 派生クラスは存在しない**：`class_name Character` + `extends Node2D` の 1 ファイルのみ。今後種族別派生を作る余地はあるが、現状は全種族が同じ Character 実装を共有（種族差は UnitAI 派生側で吸収）

---

## 所感・表示設計への示唆

### 優先度高のグルーピング案

以下の 3 グループに分けて表示すると 1 メンバーあたり 3 行程度で収まる。

1. **行動ライン**（「何をしているか」を 1 行にまとめる現行 `get_debug_goal_str()` の拡張）
   - 現状：`→攻撃ゴブリン[ATKp]` のように目標と状態を 1 行に集約
   - 追加候補：残タイマー `_timer`（ATKp/ATKpost なら attack delay 残秒、MOVING なら step 残秒）、キュー長（先読み深度）
   - 例：`→攻撃ゴブリン[ATKp 0.34s|q3]` のように状態 + 残タイマー + キュー長

2. **指示ライン**（「何を指示されているか」を表示）
   - `_move_policy` / `_combat` / `_battle_formation` / `_on_low_hp` / `_special_skill` を一括表示
   - 例：`M:follow C:attack F:surround L:retreat S:strong`
   - これにより「指示された通りに動いているか」の検証が容易になる

3. **リソース・フラグ行**（状態アイコンの拡張）
   - 現行：`[ス][ガ]`（stun/guard）のみ
   - 追加候補：`_party_fleeing`（P↓）/ `_floor_following`（F↑）/ `_has_v_slot_cost()`（V 発動可）/ `_hp_potion="use"`（自動 HP 使用中）/ NpcLeaderAI の `joined_to_player`（★合流済）
   - リッチの `_lich_water`、ダークロードの `_warp_timer` は種族固有として 4 列目に置く

### パーティーレベルの追加表示案

現状ヘッダー行は 12 項目あり長い。以下を追加する場合は 2 行に分割するか、選択中リーダーのみ詳細表示にするのが望ましい。

- `_reeval_timer`：次の再評価まで残秒（例：`re:0.8s`）
- `_visited_areas` のサイズ / 全エリア数：`探索 8/12`
- NpcLeaderAI の `_prev_target_floor`：目標フロアが変わったタイミング診断
- `has_fought_together` / `has_been_healed`：合流交渉に影響する実績フラグ
- `_was_refused`：一度断られたか（アイコン 1 つで済む）

### 1 パーティー当たりの表示量の目安

現状：ヘッダー 1 行 + メンバー横並び 1 行 = **2 行** / パーティー
拡張後の想定：ヘッダー 1 行 + メンバー（行動ライン 1 行 + 指示ライン 1 行）= **1 + 2N 行** / パーティー（N=メンバー数）

フロア 0 に全 12 NPC パーティーが居るケースでは 1+2×1=3 行 × 12 = 36 行。プレイヤー＋NPC合算で 40〜50 行。敵を含めるとフロアごと 60 行前後になるので、画面 85%×85% に収まる上限に近い。

**提案**：
- 選択中リーダーのパーティーのみ「詳細モード」で 3 行、他は現行の 2 行サマリー
- Ctrl+F1 等で「常時詳細」切り替えを用意

### 副次的な発見

- `NpcLeaderAI._prev_target_floor` と `PartyLeader._prev_leader_floor` は「変化検出用のスナップショット」で似たパターン。将来は PartyLeader 基底に持ち上げて統一できる余地あり
- `UnitAI.obedience` は `_init()` でサブクラス固定値を設定する事実上の定数。「状態変数」として扱うかは疑問。表示には不要
- `UnitAI._all_floor_items` は Dictionary 参照で game_map が更新する。PartyStatusWindow 側から floor_items 数をフロア単位で集計すると「未回収アイテム数」が可視化できる（本調査スコープ外だが表示候補として有望）
- UnitAI 側の `_combat_situation` は PartyLeader 側と同一内容が order 経由でコピーされる。同じ値がリーダー層とメンバー層で 2 重に保持されているので、メンバー側での表示は冗長
