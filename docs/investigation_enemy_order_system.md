# 調査：敵パーティーの指示フィールド（UnitAI order system）

- **調査日付**：2026-04-21
- **調査目的**：PartyStatusWindow メンバー行の指示グループ（`M/C/F/L/S/HP/E/I`）が敵パーティーでは大半が `-` 扱いになる現象の原因を、プレイヤー／NPC／敵の 3 系統で完全トレースする。アーキテクチャ上は 3 系統とも `PartyLeader._assign_orders()` → `UnitAI.receive_order()` を通るはずだが、実態としての差がどこで発生しているか、および敵の行動が実際は何で駆動されているかを明らかにする。

## 調査対象ファイル
- `scripts/party_leader.gd`（基底クラス・`_assign_orders()` 本体）
- `scripts/party_leader_ai.gd`（AI 基底層・定期再評価）
- `scripts/party_leader_player.gd`（プレイヤーパーティー用）
- `scripts/npc_leader_ai.gd`（NPC パーティー用）
- `scripts/enemy_leader_ai.gd`（敵基底）
- `scripts/goblin_leader_ai.gd` / `hobgoblin_leader_ai.gd` / `wolf_leader_ai.gd`（種族固有の代表）
- `scripts/unit_ai.gd`（`receive_order()` 受取・各フィールド定義）
- `scripts/party.gd`（`global_orders` 辞書構造）
- `scripts/order_window.gd`（プレイヤー入力 → `global_orders` / `current_order` 同期）
- `scripts/party_manager.gd`（`_apply_attack_preset_to_member` と `_setup_enemy` / `_setup_npc`）
- `scripts/character.gd`（`current_order` のデフォルト定義）
- `scripts/party_status_window.gd`（表示側：`_build_orders_field_list` / `_shorten`）
- `scripts/game_map.gd`（`set_global_orders` 呼出箇所）

---

## 前提整理：3 系統のセットアップ差

| パーティー種別 | `_global_orders` の配線 | `current_order` の初期化 |
|---|---|---|
| プレイヤー | `game_map.gd:315` `_hero_manager.set_global_orders(party.global_orders)` で **参照共有** | `OrderWindow._sync_all_global_to_members()` で `global_orders` の対応キー（`move/target/on_low_hp/item_pickup`）を全メンバーの `current_order` に流し込む。`battle_policy` もクラス別プリセットで `battle_formation` / `combat` / `heal` にバラされる |
| NPC（未合流） | **呼ばれない**。`_global_orders = {}` のまま | `PartyManager._setup_npc()` → `_apply_attack_preset_to_member(member)` で `special_skill` / `battle_formation` / `combat` / `heal` をクラス依存で設定 |
| NPC（合流済み） | `game_map.gd:1058, 1108` `nm.set_global_orders(party.global_orders)` で合流時点からプレイヤーと参照共有 | 既に設定済み（未合流時の `_apply_attack_preset_to_member` 結果） |
| 敵 | **呼ばれない**。`_global_orders = {}` のまま | `PartyManager._setup_enemy()` は `_apply_attack_preset_to_member` を呼ばない。`Character.current_order`（L122）のデフォルト辞書がそのまま使われる |

`Character.current_order` の初期値：
```
move=follow / battle_formation=surround / combat=attack / target=same_as_leader
on_low_hp=retreat / item_pickup=passive / special_skill=strong_enemy / heal=lowest_hp_first
```

`Party.global_orders` の初期値：
```
move=follow / battle_policy=attack / target=same_as_leader / on_low_hp=retreat
item_pickup=passive / hp_potion=use / sp_mp_potion=use
```
（`battle_formation` / `combat` / `special_skill` キーは **存在しない**）

---

## 1. フィールド比較マトリクス

`PartyLeader._assign_orders()`（`scripts/party_leader.gd:208-323`）が共通経路。PartyLeaderPlayer / NpcLeaderAI / EnemyLeaderAI いずれも **オーバーライドしていない**（サブクラスは `_evaluate_party_strategy()` / `_select_target_for()` / `_create_unit_ai()` のみオーバーライド）。

| UnitAI フィールド | プレイヤーパ | NPC パ（未合流） | 敵パ | UnitAI 側で実際に参照される場面 |
|---|---|---|---|---|
| `_move_policy` | `_global_orders.move`（存在）→ メンバー `current_order.move`（OrderWindow が同期済み）。`member.is_friendly=true` 分岐に入って取得。さらに `Strategy.EXPLORE` / `GUARD_ROOM` / `on_low_hp=retreat`+瀕死 の上書き規則あり | `_global_orders={}` のため fallback で `member.current_order.move`（Character デフォルト `"follow"`）→ NpcLeaderAI 側の `Strategy.EXPLORE` / `FLEE` により `_get_explore_move_policy()` の戻り値（`explore` / `stairs_down` / `stairs_up` / `cluster`）に上書きされる | `member.is_friendly=false` のため **`"spread"`（`_assign_orders` L254 のローカル変数初期値）で固定**。`EXPLORE` / `GUARD_ROOM` は敵では出ない（`EnemyLeaderAI._evaluate_party_strategy()` は `ATTACK` / `WAIT` のみ、サブクラスが `FLEE` を追加）。ただし `GUARD_ROOM` は `_apply_range_check()` 経由で敵にも発生する | `_generate_move_queue()` 内で `cluster` / `follow` / `same_room` / `explore` / `stairs_down` / `stairs_up` / `standby` / `guard_room` の分岐。敵の `"spread"` はこの match に該当しないので実質 **デフォルト（標的接近）** |
| `_combat` | `member.current_order.combat`（OrderWindow の `battle_policy` プリセット経由で `attack` / `defense` / `flee`） | `PartyManager._apply_attack_preset_to_member` により `"attack"` | `member.current_order.combat` = Character デフォルト `"attack"` | `_determine_effective_action()` L2191 で `attack/aggressive → ATTACK`・`flee → FLEE`・`defense/support/standby → WAIT` |
| `_battle_formation` | `member.current_order.battle_formation`（OrderWindow の `battle_policy` プリセットがクラス別に `surround/rear/rush/gather` 等を代入） | `_apply_attack_preset_to_member` により `healer→rear` / `archer,magician→rear` / `fighter-axe→rush` / 他→`surround` | `member.current_order.battle_formation` = Character デフォルト `"surround"` | `_generate_attack_queue()` 付近 L760, L2239 の match で接近隊形を切替 |
| `_on_low_hp` | `member.current_order.on_low_hp`（OrderWindow の専用列で切替） | Character デフォルト `"retreat"` | Character デフォルト `"retreat"` | `_determine_effective_action()` L2179：`flee → FLEE（逃げない種族除く）` / `retreat → WAIT+cluster` |
| `_special_skill` | `member.current_order.special_skill`（OrderWindow の専用列で切替） | `_apply_attack_preset_to_member` により `"strong_enemy"` | Character デフォルト `"strong_enemy"` | `_should_use_special_skill()` L1834 で MP/SP 条件と戦況比較。**ただし敵 UnitAI は `_generate_special_attack_queue` / `_generate_buff_queue` の冒頭で `_member.is_friendly == false` なら空配列を返すため V スロットは原則発動しない**（CLAUDE.md「敵の V スロット発動方針」参照）。例外：dark-lord はキュー外処理 |
| `_hp_potion` | `_global_orders.hp_potion`（OrderWindow の全体方針行で `use` / `never` を切替）| `_global_orders={}` のため default `"never"` | `_global_orders={}` のため default `"never"` | `_check_autouse_potions()` L2099：`use` かつ瀕死＋在庫ありで使用。敵は通常ポーションを持たないので意味なし |
| `_sp_mp_potion` | `_global_orders.sp_mp_potion` | default `"never"` | default `"never"` | 同上 L2107：`use` かつ energy 50% 未満で使用 |
| `_item_pickup` | `member.current_order.item_pickup`（`global_orders.item_pickup` を OrderWindow が同期） | Character デフォルト `"passive"`（`_apply_attack_preset_to_member` は触らない） | Character デフォルト `"passive"` | `_find_item_pickup_target()` L904：`avoid` なら無効化。敵もロジック上は `passive` で動くが、戦況が敵視点で SAFE になる場面は限定的 |

### マトリクス末尾の補足：表示上「`-`」になる条件

`party_status_window.gd:907 _shorten()` は `null` または空文字列で `"-"` を返す。

- UnitAI の各フィールドは宣言時に**非空の文字列デフォルト**が入っている（`"same_room"` / `"surround"` / `"attack"` / `"retreat"` / `"never"` / `"passive"` / `"strong_enemy"`）。よって `ai.get("_move_policy")` 等は原則 `-` にならず、具体値文字列が返る。
- **真に `-` になる経路**：UnitAI が未セットアップ（`_create_unit_ai` 前）や、サブクラス側でそのフィールドを `@export`（`PROPERTY_USAGE_SCRIPT_VARIABLE` 外）で再宣言していない等、`Object.get()` が null 相当を返す場合。**通常はここに到達しない**。
- したがって「敵メンバー行のほぼ全てが `-`」という観察は、表示ロジック経路で UnitAI 参照が取れていない（`ai == null` フォールバック）か、`_detail_level < 1` で `_build_orders_field_list` 自体が呼ばれていない可能性がある。コード上は敵も `M:spread C:attack F:surround L:retreat S:strong_en HP:never E:never I:passive` の固定文字列が出るはずである。

> 観察された「ほぼ `-`」が事実であれば、追加調査ポイントは **(a)** ステータスウィンドウが敵パーティーのメンバー行について `ai` を正しく取得できているか（`get_unit_ai(member.name)` の結果が null になっていないか）、**(b)** 描画経路で敵に限り異なる関数を通っていないか、**(c)** 初期オーダー発行（`setup()` L77 の `_assign_orders()`）が敵では何らかの理由でスキップされていないか、の 3 点に絞られる。本調査のスコープ外だが、次タスクで確認すべき。

---

## 2. 各パーティー種別の `_assign_orders()` 実装

**共通**：サブクラスはオーバーライドしておらず、基底 `PartyLeader._assign_orders()` が全系統で実行される。メンバーごとに以下の辞書を `UnitAI.receive_order()` に渡す。

### プレイヤーパ（`PartyLeaderPlayer`）
```
target:            _select_target_for(member)（_enemy_list の最近敵）または same_as_leader/weakest/support
combat:            member.current_order.combat                    （← OrderWindow の battle_policy プリセット）
on_low_hp:         member.current_order.on_low_hp                 （← 全体方針行）
move:              _global_orders.move → fallback current_order.move
                   （さらに Strategy.EXPLORE=joined_to_player=true ならスキップ / on_low_hp=retreat+瀕死なら cluster 上書き）
battle_formation:  member.current_order.battle_formation          （← battle_policy プリセット）
leader:            leader_char（Character）または _player 参照
party_fleeing:     (_party_strategy == FLEE)                      （ battle_policy="retreat" 時）
hp_potion:         _global_orders.hp_potion                       （"use"/"never"・全体方針）
sp_mp_potion:      _global_orders.sp_mp_potion                    （"use"/"never"・全体方針）
item_pickup:       member.current_order.item_pickup               （← 全体方針同期キー）
special_skill:     member.current_order.special_skill             （← OrderWindow 個別列）
combat_situation:  _combat_situation                              （_evaluate_strategic_status の結果）
```

### NPC パ（未合流・`NpcLeaderAI`）
```
target:            _select_target_for(member)（_enemy_list の最近・可視敵）
combat:            member.current_order.combat                    （_apply_attack_preset で "attack"）
on_low_hp:         member.current_order.on_low_hp                 （Character デフォルト "retreat"）
move:              _global_orders.move（空）→ current_order.move（"follow"）
                   → NpcLeaderAI._get_explore_move_policy() による上書き（explore/stairs_down/stairs_up/cluster）
                   → Strategy.GUARD_ROOM なら "guard_room"
battle_formation:  _apply_attack_preset 結果（クラス依存）
leader:            leader_char または _player（joined_to_player=true 時）
party_fleeing:     (_party_strategy == FLEE)                      （戦況 CRITICAL で切替）
hp_potion:         "never"（_global_orders 未設定のデフォルト）
sp_mp_potion:      "never"（同上）
item_pickup:       Character デフォルト "passive"
special_skill:     "strong_enemy"（_apply_attack_preset 経由）
combat_situation:  _combat_situation
```

### NPC パ（合流済み）
`nm.set_global_orders(party.global_orders)` が呼ばれるためプレイヤーと同じ経路。OrderWindow 操作が即反映される。`joined_to_player=true` によって `Strategy.EXPLORE` の階段遷移ロジックがスキップされ、プレイヤーを formation_ref として追従する。

### 敵パ（`EnemyLeaderAI` + 種族サブクラス）
```
target:            _select_target_for(member)（_find_nearest_friendly でプレイヤー/NPC 最近）
combat:            member.current_order.combat                    （Character デフォルト "attack"）
on_low_hp:         member.current_order.on_low_hp                 （同 "retreat"）
move:              member.is_friendly=false のため if 分岐をスキップ → "spread"（ローカル初期値）
                   → Strategy.GUARD_ROOM（_apply_range_check 発動時）なら "guard_room"
                   → on_low_hp=retreat+瀕死で "cluster"
battle_formation:  member.current_order.battle_formation          （同 "surround"）
leader:            null（if member.is_friendly 分岐内でしか formation_ref を設定しないため）
party_fleeing:     (_party_strategy == FLEE)                      （GoblinLeaderAI / WolfLeaderAI が alive < 50% で発動）
hp_potion:         "never"（未設定デフォルト）
sp_mp_potion:      "never"（同上）
item_pickup:       "passive"（Character デフォルト）
special_skill:     "strong_enemy"（Character デフォルト）
combat_situation:  _combat_situation（ただし is_enemy_party=true として算出。full_party ベース）
```

**ポイント**：敵の `move` は `_assign_orders()` L256 の `if member.is_friendly` ブロックをスキップするため常に `"spread"`。この文字列は `_generate_move_queue()` の match のどの分岐にも該当せず、実質「パターン指定なし」の扱い。敵の実際の移動（ターゲット追跡）は `_determine_effective_action()` が返す `ATTACK` 状態から、UnitAI の攻撃キュー生成ロジック側で `_target` 位置への A* 経路生成により決まる。

---

## 3. 敵で空（または無意味）になるフィールドの分類

敵は 8 フィールド中 **値自体は入っている**が、半数以上は**実質的に意味を持たない／デフォルトのまま**。区分：

| フィールド | 分類 | 補足 |
|---|---|---|
| `_move_policy` | **(C) 仕組み自体がない**（`"spread"` に固定） | `is_friendly=false` で分岐スキップ。`_generate_move_queue()` の match のどの分岐にも該当しない。敵の移動は「`_target` に向けた A* 経路」で実装されており、move_policy は実質参照されない |
| `_combat` | **(B) 設定されるがデフォルト値のまま** | Character デフォルト `"attack"` が常に渡る。`_determine_effective_action` の combat 分岐は **`is_friendly` とは無関係に** 機能するため、値自体は使われている。ただし**値は固定**で EnemyLeaderAI / 種族サブクラスが動的に変える仕組みがない（常に `attack`） |
| `_battle_formation` | **(B)** | Character デフォルト `"surround"` が常に渡る。`_generate_attack_queue` / `_plan_formation_move` の match で参照されるので効果はあるが、種族サブクラスが書き換える手段がないため全敵 `surround` で固定 |
| `_on_low_hp` | **(B)** | Character デフォルト `"retreat"`。`_determine_effective_action` で機能するが、全敵で「瀕死時は `retreat`（＝`WAIT+cluster`）」で固定。種族サブクラスが上書き不可 |
| `_special_skill` | **(A) 意図的に設定しない**（部分的に C） | 値は `"strong_enemy"` が入るが、`_generate_special_attack_queue` / `_generate_buff_queue` の冒頭で **`_member.is_friendly == false` なら空配列を返す**（CLAUDE.md 参照）。よって敵は V スロットを使わない設計 |
| `_hp_potion` | **(A)** | 敵はポーション在庫を持たないので `"never"` で問題ない |
| `_sp_mp_potion` | **(A)** | 同上 |
| `_item_pickup` | **(A)** | 敵はアイテム取得指示を持たない設計（`_evaluate_strategic_status` で敵視点は `nearby_enemy=friendly` が常に存在 → 戦況が SAFE になりにくく `_find_item_pickup_target` の前提条件を満たさない）。`show_orders=false` で `PartyStatusWindow` のヘッダー行も省略される |

### 分類内訳
- **(A) 意図的に設定しない（敵に不要）**：4 件（`_special_skill`, `_hp_potion`, `_sp_mp_potion`, `_item_pickup`）
- **(B) 設定する仕組みはあるがデフォルト値のまま**：3 件（`_combat`, `_battle_formation`, `_on_low_hp`）
- **(C) 仕組み自体がない（味方専用設計）**：1 件（`_move_policy`）

---

## 4. 敵の行動は実際に何で決まっているか

UnitAI の指示フィールドは「ほぼ固定値が渡るだけ」で、敵の行動バリエーションは以下の 4 経路で実装されている。

### 4-1. パーティー戦略（`_party_strategy` / `_party_fleeing`）
- `EnemyLeaderAI._evaluate_party_strategy()`：`_has_alive_friendly()` なら `ATTACK`、いなければ `WAIT`
- `GoblinLeaderAI._evaluate_party_strategy()`：生存率 < `PARTY_FLEE_ALIVE_RATIO`（0.5）で `FLEE` を追加、それ以外は super
- `WolfLeaderAI` / `HobgoblinLeaderAI` も同様に `FLEE` を追加する種族実装
- `PartyLeader._apply_range_check()`：敵専用の縄張り・追跡範囲判定。`territory_range` / `chase_range` を超えると `GUARD_ROOM`（帰還）に切替

この `_party_strategy`（FLEE など）が `party_fleeing` として UnitAI に伝わり、`_determine_effective_action()` L2163 で FLEE 行動を駆動する。

### 4-2. 種族固有フック（UnitAI サブクラス）
`unit_ai.gd:2204-2213` の 3 フック：

| フック | デフォルト | オーバーライド例 |
|---|---|---|
| `_should_ignore_flee() -> bool` | `false` | `DarkKnightUnitAI` 等が `true`（FLEE 指示を無視して戦闘継続） |
| `_should_self_flee() -> bool` | `false` | `GoblinUnitAI` が `hp < SELF_FLEE_HP_THRESHOLD(0.3)` で `true`（ハードコード） |
| `_can_attack() -> bool` | `true` | 魔法系が MP 不足なら `false`（MP 回復まで `WAIT`） |

`_determine_effective_action()` は `_party_fleeing` → `_should_self_flee` → `_can_attack` → `_on_low_hp` → `_is_combat_safe` → `_combat` の順で評価する（unit_ai.gd:2161-2200）。敵の行動分岐は主にこのフック群で決まっており、UnitAI フィールド（`_combat` 等のデフォルト値）は決定木の末端でしか効いていない。

### 4-3. 敵個別 JSON フィールドの参照箇所
- `chase_range` / `territory_range`：`PartyLeader._all_members_out_of_range()` / `_any_member_can_engage()` / `_all_members_at_home()` 等 `_apply_range_check` 系で参照（敵専用）
- `behavior_description`：**コードから参照されない**。種族サブクラス実装時に Claude Code が読む自然言語仕様（CLAUDE.md に明記）
- `projectile_type`：`SkillExecutor` 側で ranged 攻撃時に弾種を切替
- `is_undead` / `is_flying` / `instant_death_immune`：ダメージ計算・経路探索・V スロット判定で参照

### 4-4. ハードコード種族ロジック（キュー外処理）
- `DarkLordUnitAI._update_dark_lord_behavior()`：3 秒間隔でランダムワープ移動＋炎陣発動。通常のアクションキュー経由ではなく `_process` と並走（CLAUDE.md「例外的実装」）
- `LichUnitAI`：火弾／水弾を `_lich_water` フラグで交互切替
- `GoblinUnitAI._should_self_flee()` の HP30% 閾値もハードコード（`GlobalConstants.SELF_FLEE_HP_THRESHOLD`）

---

## 5. 推奨される設計変更（所感）

**結論：(C') 分離を明確化する方向で小規模な整理を行う**（現状維持寄り）。

理由：
1. 敵の UnitAI フィールドは**値自体は入っている**（空ではない）。「ほぼ `-` 表示」が事実だとすれば、受取済みの値が表示側に届いていないか、`_detail_level` / `show_orders` の切替条件に引っ掛かっている可能性が高く、**根源は表示層の問題**。データフロー自体はプレイヤー／NPC／敵で同じ経路を通っている。
2. 敵の行動は意図的に「パーティー戦略 + 種族フック + ハードコード」の 3 経路で設計されており、UnitAI フィールドを味方と同じ粒度で制御する必要はない（CLAUDE.md「敵 AI が使わない指示」の方針どおり）。
3. 一方で、マトリクスの (B) 区分（`_combat` / `_battle_formation` / `_on_low_hp`）は「値は渡るが種族側から上書き不能」という中途半端な状態。これは DRY 観点で**無害だが非対称な死コード**。

**具体的な推奨アクション**：
- `PartyStatusWindow` の敵行において、意図的に (A) (C) 区分のフィールドを**非表示**にし、(B) 区分のみ表示する（現状は `show_orders=false` で `item_pickup` のみ省略）。`_build_orders_field_list` に「敵向け省略リスト」引数を追加し、`_move_policy` / `_special_skill` / `_hp_potion` / `_sp_mp_potion` / `_item_pickup` を敵では出さない構成にする。
- または、**敵表示では指示グループ自体をスキップし、代わりに「パーティー戦略」「種族フック状態」を表示する**ことで「敵は別系統で動いている」ことを視覚的に明示する。
- `EnemyLeaderAI._assign_orders()` を薄くオーバーライドして、敵の不要フィールドには明示的に空文字列を入れる（現在のデフォルト値を渡す動作をコードで明示）ことも検討余地。ただし実行時挙動は変わらないため優先度は低い。

変更コストは低く、CLAUDE.md の「使っていないものは残さない」原則にも沿う。ただし「ほぼ `-` 表示」の根本原因が `ai == null` 等の別系統バグなら、そちらを先に確定させる必要がある。

---

## 完了報告メモ

1. マトリクス行数：**8 行**（派生追加なし）
2. 敵の指示フィールドで「実質無意味／デフォルト固定」になっているもの：**8 中 8 件**（値は入るが、(A) 4 件 + (B) 3 件 + (C) 1 件のいずれかに該当）
3. 分類内訳：(A) 4 件、(B) 3 件、(C) 1 件
4. 推奨設計変更：敵行は (A) (C) フィールドを非表示にし、(B) のみ表示。根本的な表示「`-`」の原因が別系統（表示層の参照取得失敗）の疑いが強いため、表示パスの追加調査を先行させるのが安全
