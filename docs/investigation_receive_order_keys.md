# `receive_order()` 辞書キー全棚卸し調査

調査日: 2026-04-21
調査対象コミット: master（2026-04-21 時点）

## 1. 概要

PartyLeader から UnitAI へ配布される `receive_order()` 辞書の全キーを棚卸しし、PartyStatusWindow での表示対応を確認する。

### 背景
FLEE 時の逃走先決定ロジック実装（`flee_recommended_goal` キー新設の議論）の最中に、既存の `receive_order` 辞書に含まれる `leader` / `party_fleeing` / `combat_situation` が PartyStatusWindow に十分に表示されていないことが判明した。2026-04-21 の [`docs/investigation_debug_variables.md`](investigation_debug_variables.md) は UnitAI / PartyLeader の**自前の変数**が対象で、`receive_order()` 経由でリーダーから配布される値は棚卸し対象から漏れていた。

### 既存調査との関係
| ドキュメント | 対象 |
|---|---|
| [`investigation_debug_variables.md`](investigation_debug_variables.md) | UnitAI / PartyLeader の**自前の状態変数** |
| **本調査** | **receive_order 経由で配布される値** |
| [`investigation_enemy_order_system.md`](investigation_enemy_order_system.md) / [`investigation_enemy_order_effective.md`](investigation_enemy_order_effective.md) | 敵に対する指示が実動に効くか |

本調査は「receive_order ペイロード」に特化し、他 3 調査と相補関係にある。

## 2. 配布ルートの確認

- **唯一の配布ポイント**: [`party_leader.gd:310-323`](../scripts/party_leader.gd:310) の `unit_ai.receive_order({...})`
- **サブクラスでの override**: `PartyLeaderPlayer` / `PartyLeaderAI` / `EnemyLeaderAI` / `NpcLeaderAI` / `GoblinLeaderAI` ほか種族固有 AI は `_assign_orders()` を override していない（grep 確認済み）
- **追加キーなし**：サブクラスが辞書に項目を足すケースは存在せず、配布ペイロードは基底の 12 キーが全て

## 3. 全キー一覧マトリクス（12 キー）

| # | キー名 | 分類 | UnitAI 保存先 | 主な参照箇所 | PartyStatusWindow 表示 | 値の動性 | 表示推奨度 | 備考 |
|---|---|---|---|---|---|---|---|---|
| 1 | `target` | 指示 | `_target` | [`unit_ai.gd:246`](../scripts/unit_ai.gd:246)・`_determine_effective_action` / `_generate_queue` | goal_str 経由で「→攻撃◯◯」等として表示（高） | 動的 | 維持 | VAR_PRIORITY の `attack_target`/`goal_str` として登録済 |
| 2 | `combat` | 指示 | `_combat` | [`unit_ai.gd:236`](../scripts/unit_ai.gd:236)・`_determine_effective_action` | 指示グループ `C:` | 中程度（指示変更時） | 維持 | VAR_PRIORITY 中 |
| 3 | `on_low_hp` | 指示 | `_on_low_hp` | [`unit_ai.gd:237`](../scripts/unit_ai.gd:237)・`_determine_effective_action`（retreat 判定） | 指示グループ `L:` | 基本固定 | 維持 | VAR_PRIORITY 中 |
| 4 | `move` | 指示 | `_move_policy` | [`unit_ai.gd:228`](../scripts/unit_ai.gd:228)・`_generate_queue` | 指示グループ `M:` | 動的（戦略で自動上書き） | 維持 | VAR_PRIORITY 中 |
| 5 | `battle_formation` | 指示 | `_battle_formation` | [`unit_ai.gd:230`](../scripts/unit_ai.gd:230)・`_generate_queue` | 指示グループ `F:` | 基本固定 | 維持 | VAR_PRIORITY 中 |
| 6 | `leader` | **パーティー文脈** | `_leader_ref` | [`unit_ai.gd:240-244`](../scripts/unit_ai.gd:240)・30+ 箇所で参照（隊形・フロア追従・回復対象選定） | **なし**（リーダー行 ★ で間接表示のみ） | 基本固定（リーダー死亡・合流時のみ変化） | **要検討**（下記推奨事項参照） | 味方メンバーのみ非 null。敵メンバーでは常に null |
| 7 | `party_fleeing` | パーティー文脈 | `_party_fleeing` | [`unit_ai.gd:238`](../scripts/unit_ai.gd:238)・`_determine_effective_action` / `_generate_queue` | `P↓` で表示（低） | 動的（戦略変更時） | 維持 | ヘッダー行の `strategy=FLEE` と意味が重複するが、P↓ は**メンバー側の受信値**を表示するためデバッグ価値あり |
| 8 | `hp_potion` | 指示 | `_hp_potion` | [`unit_ai.gd:231`](../scripts/unit_ai.gd:231)・`_is_should_use_hp_potion` | 指示グループ `HP:` | 基本固定 | 維持 | VAR_PRIORITY 中 |
| 9 | `sp_mp_potion` | 指示 | `_sp_mp_potion` | [`unit_ai.gd:232`](../scripts/unit_ai.gd:232)・`_should_use_special_skill` / `_use_potion` | 指示グループ `E:` | 基本固定 | 維持 | VAR_PRIORITY 中 |
| 10 | `item_pickup` | 指示 | `_item_pickup` | [`unit_ai.gd:233, 260-270`](../scripts/unit_ai.gd:233)・初回判定 / `_generate_queue` | 指示グループ `I:`（味方のみ） | 基本固定 | 維持 | 敵は `_item_pickup` を常に "passive" 固定（指示ライン自体を廃止済） |
| 11 | `special_skill` | 指示 | `_special_skill` | [`unit_ai.gd:234`](../scripts/unit_ai.gd:234)・`_should_use_special_skill` | 指示グループ `S:` | 基本固定 | 維持 | VAR_PRIORITY 中 |
| 12 | `combat_situation` | 戦況判断 | `_combat_situation` | [`unit_ai.gd:235`](../scripts/unit_ai.gd:235)・`_is_combat_safe` / `_should_use_special_skill` / 種族フック（`_can_attack`, `_should_self_flee`） | ヘッダー行の `戦況:xxx` | 動的 | 維持 | 内訳辞書 15 キーをヘッダーで集約表示済 |

### 分類の内訳
- **指示**（OrderWindow で設定可能）: 9 キー（#1-5, #8-11）
- **パーティー文脈**: 2 キー（#6 `leader` / #7 `party_fleeing`）
- **戦況判断**: 1 キー（#12 `combat_situation`）
- 合計: **12 キー**
- 第 4 分類の必要性: なし（既存 3 分類で全てカバー）

## 4. Dead Transmission 候補

**結論: 見つからない**。

12 キー全てが UnitAI 側で参照されている。

| キー | 根拠 |
|---|---|
| `target` | `_determine_effective_action` / `_generate_queue` の攻撃ターゲット選定 |
| `combat` | `_determine_effective_action` で戦闘方針に従う |
| `on_low_hp` | HP 危機時の行動判定（retreat → cluster 上書き等） |
| `move` | `_generate_queue` で全ポリシー分岐 |
| `battle_formation` | `_generate_queue` の ASTAR/ASTAR_FLANK 選択 |
| `leader` | `_leader_ref` 経由で 30+ 箇所（隊形・フロア追従・回復ターゲット） |
| `party_fleeing` | `_determine_effective_action` で逃走優先度を上げる |
| `hp_potion` | `_is_should_use_hp_potion` の自動使用判定 |
| `sp_mp_potion` | `_should_use_special_skill` の発動ゲート |
| `item_pickup` | `_generate_queue` のアイテムゴール生成 |
| `special_skill` | `_should_use_special_skill` の発動条件 |
| `combat_situation` | `_is_combat_safe`（アイテム走行ゲート）・`_should_use_special_skill`（INFERIOR 時のみ発動）ほか |

## 5. 表示追加候補

### 5-1. `_leader_ref` （優先度: 低〜中）

**現状**: VAR_PRIORITY 未登録・PartyStatusWindow で非表示。リーダー行の `▶` マーカーと `★` 記号で間接的には可視化されているが、**どのキャラが各メンバーの隊形基準か**を直接見る手段がない。

**追加すると分かること**:
- 合流済みパーティーでリーダーが変わったとき、各メンバーが正しい基準を受け取っているか
- 非リーダー 1 人ずつが別のリーダー参照を持っていないか（本来は同一パーティー内で統一されるはず）
- クロスフロア追従判定（`_leader_ref.current_floor != _member.current_floor`）の入力側確認

**デメリット**:
- 同じパーティー内で全メンバーが同じ値を持つため、メンバー行に出すと冗長
- 敵メンバーでは常に null（表示する意味がない）

**推奨案**: パーティーヘッダー行に `leader_ref=<名前>` を 1 つだけ追加する形（味方パーティーのみ・詳細度「中」）。敵ヘッダーには出さない。優先度は低めだが、合流系バグの再発時にデバッグしやすくなる。

### 5-2. 他キーの追加候補

なし。他の 11 キーは既に PartyStatusWindow または指示ラインで可視化されている。

## 6. 表示削除候補

**結論: なし**。

`party_fleeing` （P↓ フラグ）がヘッダーの `strategy=FLEE` と一見重複するが、以下の理由で**両方残すのが適切**:

- ヘッダー `strategy=FLEE` は PartyLeader 側の決定（送信側）
- メンバー行 `P↓` は UnitAI 側の受信値（受信側）
- 両者が乖離するバグ（配布漏れ・タイミング差）のデバッグには両方見える必要がある

他 10 キーも参照頻度が高く、削除候補なし。

## 7. 敵・味方の扱い差

| キー | 味方 | 敵 |
|---|---|---|
| `target` | 指示グループ経由（`target_policy` → `_select_target_for`） | 同左（自律判断） |
| `combat` | OrderWindow で設定 | デフォルト `"attack"` 固定 |
| `on_low_hp` | OrderWindow で設定 | デフォルト `"retreat"` 固定 |
| `move` | OrderWindow で設定（explore/cluster/follow/etc.） | デフォルト `"spread"` 固定 |
| `battle_formation` | OrderWindow で設定 | デフォルト `"surround"` 固定 |
| `leader` | リーダーキャラ参照（味方非リーダー）または `_player`（合流時） | 常に null |
| `party_fleeing` | 動的 | 動的 |
| `hp_potion` | OrderWindow で設定 | 常に `"never"` |
| `sp_mp_potion` | OrderWindow で設定 | 常に `"never"` |
| `item_pickup` | OrderWindow で設定 | 常に `"passive"`（ただしロジック上拾わない） |
| `special_skill` | OrderWindow で設定 | 常に `"strong_enemy"`（実動は `is_friendly==false` で抑止） |
| `combat_situation` | 動的 | 動的 |

2026-04-21 の敵メンバー指示ライン廃止（[`investigation_enemy_order_system.md`](investigation_enemy_order_system.md)）を踏まえると、敵では#2〜#5・#8〜#11 が常にデフォルト値固定で、表示価値が低い（既に廃止済）。

## 8. FLEE 実装議論への引き継ぎ

### 8-1. `flee_recommended_goal` 新設時の注意点

新キーを追加する場合:
- 分類: **パーティー文脈情報**（`_leader_ref` / `_party_fleeing` と同じ分類）
- 配布元: [`party_leader.gd:310-323`](../scripts/party_leader.gd:310) の辞書に追加
- UnitAI 側: `receive_order` で `_flee_recommended_goal: Vector2i` に保存
- PartyStatusWindow: `party_fleeing` が true のときのみ表示（敵は表示しない・味方のみ・詳細度「低」）

### 8-2. 敵 FLEE との関係

敵パーティーでも `_party_strategy == Strategy.FLEE` になるケースがある（ゴブリン系の HP 低下時など）。このとき `party_fleeing = true` が敵メンバーに配布されている:

1. `PartyLeader._evaluate_party_strategy()` → `Strategy.FLEE`
2. `PartyLeader._assign_orders()` → `party_fleeing = true` 配布
3. UnitAI 側: `_determine_effective_action()` で flee 優先度上昇
4. **ただし** 種族フック `_should_ignore_flee()` が true のキャラ（DarkKnight / Zombie など）は無視

FLEE 実装のスコープは味方のみだが、敵の `party_fleeing` は既存動作を壊さないようにすること。

## 9. 結論

- `receive_order()` 配布ペイロードは 12 キー、サブクラスでの追加なし
- **Dead transmission は見つからない**（全キーが何らかの形で参照されている）
- **表示追加候補は `_leader_ref` の 1 件のみ**（優先度: 低〜中・パーティーヘッダーに 1 行追加する形を推奨）
- 表示削除候補なし
- 新規分類の必要なし（既存 3 分類で網羅）
- FLEE 実装で `flee_recommended_goal` 新設時は**パーティー文脈情報**として位置付け、配布元は [`party_leader.gd:310-323`](../scripts/party_leader.gd:310)、PartyStatusWindow 表示は味方のみ・詳細度「低」が妥当

### 次タスク引き継ぎ（CLAUDE.md 反映）

本ドキュメントの棚卸し結果は CLAUDE.md 未反映。次タスクで以下を検討:
1. 「パーティーシステムのアーキテクチャ」→「データの流れ」の `receive_order` ペイロード一覧に分類情報（指示 / パーティー文脈 / 戦況判断）を明記
2. `_leader_ref` をパーティーヘッダーに追加するかの最終判断（優先度低のため後回し可）
3. FLEE 実装時は本分類方針に従い `flee_recommended_goal` を追加する
