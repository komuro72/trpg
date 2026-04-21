# 調査：敵パーティーのリーダー行「指示値」は有効か・死にコードか・表示のみか

- **調査日付**：2026-04-21
- **調査目的**：PartyStatusWindow の敵リーダー行に表示される `mv=密集 battle=攻撃 tgt=最近 hp=戦闘継続` などの指示値について、(A) 表示だけで意味なし / (B) 死にコード / (C) 実際に敵の行動に効いているのどれに該当するかを 7 フィールド × 実行動への反映経路で切り分ける。
- **前回調査書との関係**：`docs/investigation_enemy_order_system.md`（2026-04-21 発行）では「敵 UnitAI の指示フィールドは味方と別経路で行動が決まる・値はほぼ固定／デフォルトのまま」と結論づけた。本調査はその結論を、**リーダー行の表示経路**（`get_global_orders_hint()`）に焦点を絞って再点検し、表示と実行動のズレを行番号付きで明文化する。

---

## 1. 表示値の出所マップ

### 敵リーダー行の表示は **「戦略 (`_party_strategy`) から合成した仮想ヒント」** である

`PartyStatusWindow._draw_party_block()`（`scripts/party_status_window.gd:444`）は以下を呼ぶ：

```gdscript
var hint: Dictionary = pm.get_global_orders_hint()
# ...
var mv_str:     String = _label("move", hint.get("move", "-") as String)
var battle_str: String = _label("battle_policy", hint.get("battle_policy", "-") as String)
var tgt_str:    String = _label("target", hint.get("target", "-") as String)
var hp_str:     String = _label("on_low_hp", hint.get("on_low_hp", "-") as String)
# （敵は show_orders=false のため item= は描画しない）
```

`pm.get_global_orders_hint()` は `PartyManager._leader_ai.get_global_orders_hint()` を呼び、**敵の場合は** `PartyLeader.get_global_orders_hint()`（`scripts/party_leader.gd:420`）に到達する：

```gdscript
func get_global_orders_hint() -> Dictionary:
    var hint: Dictionary
    if not _global_orders.is_empty():
        hint = _global_orders.duplicate()
    else:
        match _party_strategy:
            Strategy.ATTACK:
                hint = {"move": "cluster", "battle_policy": "attack",   "target": "nearest", ...}
            Strategy.FLEE:
                hint = {"move": "cluster", "battle_policy": "retreat",  "target": "nearest", "on_low_hp": "flee", ...}
            Strategy.WAIT:
                hint = {"move": "standby", "battle_policy": "defense",  "target": "nearest", ...}
            Strategy.DEFEND:
                hint = {"move": "same_room", "battle_policy": "defense", ...}
            Strategy.EXPLORE:
                hint = {"move": "explore",     "battle_policy": "attack", ...}
            Strategy.GUARD_ROOM:
                hint = {"move": "guard_room",  "battle_policy": "retreat", ...}
            _:
                hint = {"move": "-", ...}
    # 戦況判断（_combat_situation の統計）を追加
    hint["combat_situation"] = ...
    return hint
```

### 敵での挙動

- 敵パーティーは **`_global_orders` がセットされない**（前回調査書 L27 のセットアップ表）。`_global_orders.is_empty()` が常に true
- したがって `match _party_strategy:` の分岐が毎回実行される
- **表示されている `mv / battle / tgt / hp` は、敵の戦略（ATTACK/FLEE/WAIT/…）から PartyLeader が組み立てた「辞書リテラル」である**
- これは **UnitAI が実際に保持している `_move_policy` / `_combat` / `_target` / `_on_low_hp` とは完全に別経路**。表示と実行動が連動していない

### プレイヤー／NPC との違い

| パーティー種別 | `_global_orders` | `get_global_orders_hint()` の出所 |
|---|---|---|
| プレイヤー | `Party.global_orders` への参照共有（`game_map._hero_manager.set_global_orders(...)`） | `_global_orders.duplicate()` → OrderWindow の実値が出る |
| NPC（未合流） | 空 | `NpcLeaderAI.get_global_orders_hint()` が NPC 固有のデフォルト辞書（`move=follow / battle_policy=attack / target=same_as_leader / on_low_hp=retreat / ...`）+ 戦略上書きを組み立てる |
| NPC（合流済み） | 参照共有 | プレイヤーと同じく OrderWindow 実値 |
| **敵** | **空** | **`PartyLeader.get_global_orders_hint()` の `match _party_strategy` が生成する仮想ヒント** |

表示例「`mv=密集 battle=攻撃 tgt=最近 hp=戦闘継続`」は、敵が `Strategy.ATTACK` の状態にあるとき `PartyLeader.get_global_orders_hint()` の ATTACK ブランチが返す `{"move": "cluster", "battle_policy": "attack", "target": "nearest", "on_low_hp": "keep_fighting"}` を日本語化したもの。

---

## 2. 各フィールドの判定表

- **行動への反映経路**は「敵の UnitAI が `receive_order()` で受け取り、`_determine_effective_action()` や各 `_generate_*_queue()` で参照するかどうか」で判定する
- 「ヘッダー表示値」と「UnitAI に届く値」が敵では別経路なので、**表示値が実行動を駆動しているかどうかは別問題**
- 行番号は `scripts/unit_ai.gd` が基準（特記しない限り）

| # | 指示フィールド | 表示値の出所（敵・`get_global_orders_hint`） | UnitAI 側のフィールド | 敵での UnitAI 代入経路 | 参照箇所（行番号） | 敵行動への反映 | 判定 |
|---|---|---|---|---|---|---|---|
| 1 | **mv**（move） | `match _party_strategy` で戦略依存に合成。ATTACK→"cluster" / FLEE→"cluster" / WAIT→"standby" / EXPLORE→"explore" / GUARD_ROOM→"guard_room" | `_move_policy` | `_assign_orders` L254 で **敵は `is_friendly=false` 分岐スキップ** → ローカル変数初期値 `"spread"` 固定。ただし `Strategy.GUARD_ROOM` のときは L278 で `"guard_room"` に上書き／`on_low_hp=retreat`+瀕死 は L282 で `"cluster"` に上書き | `_generate_move_queue` L778（match 分岐）／L687-717（clusrer・follow・same_room 判定）／L1451, 1502, 1546（経路選択） | `"spread"` は match のどの分岐にも該当しない → デフォルト（L790「formation 満たさなければ formation 寄り・満たせば wait」）。`"guard_room"` のときだけ L887 の home 帰還キュー。表示上は ATTACK なので `mv=密集(cluster)` だが UnitAI 実値は `spread` で不一致 | **(A) 表示だけで意味なし**（`_global_orders` 非反映）。ただし戦略が GUARD_ROOM になる場面では偶然一致する（表示=`mv=帰還`・UnitAI=`"guard_room"`） |
| 2 | **battle**（battle_policy） | `match _party_strategy` で合成。ATTACK→"attack" / FLEE→"retreat" / WAIT→"defense" / etc. | 対応するフィールドなし（`_combat` と直接対応せず） | **そもそも UnitAI に `battle_policy` は渡されない**。`_assign_orders` L248 は `member.current_order.combat`（Character デフォルト `"attack"`）を `_combat` に入れる | `_combat` の参照は `_determine_effective_action` L2191 の match のみ | 表示 `battle=攻撃` と UnitAI `_combat="attack"` が「偶然一致」するだけ。戦略 FLEE 時、表示は `battle=撤退` だが `_combat` は依然として `"attack"`（敵は戦略 FLEE を別経路 `_party_fleeing=true` で駆動） | **(A) 表示だけで意味なし**（`battle_policy` という概念が UnitAI 側に存在しない。`_combat` は別値・別経路） |
| 3 | **tgt**（target） | `match _party_strategy` で合成。全戦略で `"target": "nearest"` 固定 | `_target`（`Character` 参照） | `_assign_orders` L250 で `tgt_policy = order.get("target", "same_as_leader")` → 敵は Character デフォルト `"same_as_leader"`。L293 で `leader_target`（`_select_target_for(leader)` 経由・EnemyLeaderAI では `_find_nearest_friendly`）を割当 | `_target` 参照：L157, 439, 473, 493, 500, 601, 1088, 1111, 1135, 1162 ほか多数（攻撃・隊形・近接判定で使用） | 表示 `tgt=最近(nearest)` と実効挙動（最近友好の選択）は**実質一致**。ただし経路は違う（表示はヒント組立・実値は `current_order.target="same_as_leader"` → `leader_target` → `_find_nearest_friendly`） | **(A) 表示だけで意味なし**（同じ結果になるのは偶然。`_global_orders.target` の値が変わっても UnitAI には届かない） |
| 4 | **hp**（on_low_hp） | `match _party_strategy` で合成。ATTACK/WAIT/DEFEND/EXPLORE/GUARD_ROOM→"keep_fighting" / FLEE→"flee" | `_on_low_hp` | `_assign_orders` L249 で `member.current_order.on_low_hp`（Character デフォルト `"retreat"`）を渡す | `_determine_effective_action` L2179 の match（`"flee"` / `"retreat"`）／`_assign_orders` L282-284 で `move_policy` の `"cluster"` 上書き条件にも使う | UnitAI 実値は常に `"retreat"`（敵は `current_order.on_low_hp` を書き換えない）。表示は戦略 ATTACK のとき `hp=戦闘継続(keep_fighting)` だが UnitAI は `"retreat"`。瀕死時は WAIT（=defense 相当）＋ `move_policy="cluster"` になる。表示と実動は**方針が逆**（戦闘継続のはずが撤退する） | **(A) 表示だけで意味なし**（`_global_orders.on_low_hp` が UnitAI に届かないため表示は無意味。実動は Character デフォルト `"retreat"` 固定） |
| 5 | **item**（item_pickup） | show_orders=false で **敵リーダー行に描画しない**（`_draw_party_block` L468 で else 分岐・`item=` 省略）。ただし hint 辞書には戦略別の値（ATTACK/FLEE/WAIT/... すべて `"item_pickup": "avoid"`）が入っている | `_item_pickup` | `_assign_orders` L320 で `member.current_order.item_pickup`（Character デフォルト `"passive"`）を渡す | `_find_item_pickup_target` L905-933 | 敵視点で `_is_combat_safe()` が true になる場面は限定的（`_combat_situation` で `nearby_enemy`=friendly が常に存在するため戦況 SAFE になりにくい）。`"passive"` で近隣アイテムを拾う経路は理論上動作するが、前提条件を満たしにくい | **(A) 表示されていない + (B) 機能するが前提を満たしにくい**（ハイブリッド。表示しないので見た目問題はない。UnitAI 実値 `"passive"` は `_global_orders.item_pickup` と無関係） |
| 6 | **hp_potion** | 敵は **リーダー行ヘッダーに描画しない**（`get_global_orders_hint` 出力には含まれるが、`_draw_party_block` は `mv / battle / tgt / hp / item` しか取り出さない） | `_hp_potion` | `_assign_orders` L318 で `_global_orders.get("hp_potion", "never")` → 敵は空辞書なので `"never"` 固定 | `_generate_potion_queue` L2099：`"use"` かつ瀕死＋在庫ありで使用 | 敵は通常ポーションを持たない設計 + UnitAI 実値 `"never"` 固定 → キュー生成されない | **(A) 表示されていない + (C) 実質無効**（敵はポーション在庫を持たないのでロジック通過しても意味なし） |
| 7 | **sp_mp_potion** | 同上（描画しない） | `_sp_mp_potion` | `_assign_orders` L319 で同様に `"never"` 固定 | `_generate_potion_queue` L2107：`"use"` + energy < 50% | 同上 | **(A) 表示されていない + (C) 実質無効** |

### 判定まとめ

- 本タスクの対象は「リーダー行ヘッダーに **描画されている** 4 フィールド（mv / battle / tgt / hp）」。残り 3（item / hp_potion / sp_mp_potion）は**そもそも敵リーダー行に描画されない**
- 描画される 4 フィールド：**全て (A) 表示だけで意味なし**
- 描画されない 3 フィールド：**item = (A)+(B) / hp_potion・sp_mp_potion = (A)+(C)**（内部ロジック上は参照されるが敵では無意味）

### 判定基準の再定義

タスク依頼の(A)(B)(C)定義に厳密に沿うと以下：

| 元定義 | 敵側での該当 |
|---|---|
| (A) 表示だけで意味のない情報 | **mv / battle / tgt / hp**（4 件）：表示値と実動値が別経路で算出されており、表示値を変えても実動は変わらない |
| (B) 死にコード | **なし**：(A) と(B) の違いは「UnitAI に届くかどうか」。敵では `_global_orders` 自体が空なので「値を変える」操作自体が不可能（`_global_orders` を書き換える UI がない）。したがって厳密に(B)と呼べるケースはない |
| (C) 敵の行動に効いている | **なし**：表示値（get_global_orders_hint）から UnitAI への連結パスがない |

---

## 3. 敵行動を実際に駆動している経路の再確認

前回調査書 L162-193 の 4 経路を再確認。

### 3-1. パーティー戦略（`_party_strategy`）
変わらず。`EnemyLeaderAI._evaluate_party_strategy()`（`scripts/enemy_leader_ai.gd:38`）が friendly 生存判定で ATTACK/WAIT を返す。種族サブクラスが FLEE を追加。`_apply_range_check()`（`scripts/party_leader.gd:475`）が GUARD_ROOM に上書き。

### 3-2. 種族固有フック（UnitAI サブクラス）
変わらず。`_should_ignore_flee()` / `_should_self_flee()` / `_can_attack()`（`scripts/unit_ai.gd:2204-2213`）。`_determine_effective_action` L2163-2200 で参照。

### 3-3. 敵個別 JSON フィールド
変わらず。`chase_range` / `territory_range` / `projectile_type` / `is_undead` / `is_flying` / `instant_death_immune`。

### 3-4. ハードコード種族ロジック
変わらず。DarkLordUnitAI のワープ・LichUnitAI の火水交互など。

### 今回の新発見
前回調査書では `tgt` 指示値が UnitAI に届いているかを「プレイヤー側の同期（OrderWindow）で届く」と記述していたが、**敵では `current_order.target`（Character デフォルト `"same_as_leader"`）が使われ、`leader_target` 経由で `_find_nearest_friendly` の結果が入る**。表示ヒントの `"nearest"` とは経路が別で偶然同じ結果。

- `_assign_orders` L286-299 の target 選択 match：敵は `"same_as_leader"` 分岐に入る（Character デフォルト）
- `leader_target` は `_select_target_for(leader)`（`EnemyLeaderAI._select_target_for` = `_find_nearest_friendly`）
- つまり**敵の全メンバーはリーダーが見つけた最近友好を共有する**（個別に nearest 選択していない）

この挙動は表示値「tgt=最近(nearest)」とは意味が異なる（nearest=各個体にとっての最近・same_as_leader=リーダーにとっての最近）。ほとんどの場面で結果は近いが厳密には違う。

---

## 4. 結論

### 4-1. 判定内訳

| 判定 | 件数 | フィールド |
|---|---|---|
| (A) 表示だけで意味なし | **4 件**（描画対象全て） | mv / battle / tgt / hp |
| (A) 表示されていない + ほぼ無効 | 3 件（非描画） | item / hp_potion / sp_mp_potion |
| (B) 死にコード | 0 件 | — |
| (C) 有効 | 0 件 | — |

**合計 7 件中、敵のリーダー行ヘッダーに描画される 4 件はすべて (A) 表示だけで意味なし** に該当。残り 3 件は描画されていない。

### 4-2. 敵指示体系は味方と「実質同じ」か「完全に異なる」か

**完全に異なる**。

- 味方（プレイヤー・NPC 合流済み）：`_global_orders` が `Party.global_orders` と参照共有 → OrderWindow 操作が即 UnitAI に届く（メンバーの `current_order` への同期経由）→ 行動に反映
- 敵：`_global_orders` は常に空辞書 → PartyLeader が戦略 (`_party_strategy`) から仮想ヒントを合成して「表示だけ」出している → UnitAI の実動は `current_order`（Character デフォルト固定）＋ 種族フック＋ハードコードで決まる
- 敵の**表示と実動が一致するケースは偶然のみ**（たとえば戦略 ATTACK で表示 `battle=攻撃`・UnitAI `_combat="attack"` は結果同じだが、戦略が FLEE になっても `_combat` は `"attack"` のまま。駆動は `_party_fleeing=true` 別経路）

### 4-3. PartyStatusWindow の敵リーダー行表示への扱い提案

**現状**：敵リーダー行に `mv=密集 battle=攻撃 tgt=最近 hp=戦闘継続` が表示される。これは**敵の戦略 ATTACK を「味方と同じ言葉で説明したラベル」**。プレイヤーが混同すると「この敵に指示を出している」と誤解しかねない。

**提案（3 択）**：

1. **(推奨) 敵リーダー行から指示値を消し、代わりに `戦略: 攻撃/撤退/待機/帰還` を表示する**
   - `_draw_party_block` の else 分岐（L468）を「敵用ヘッダー」として分離し、`get_current_strategy_name()`（`party_leader.gd:416`）の結果を直接表示
   - 「敵は指示ではなく戦略で動いている」ことを視覚的に明示できる
   - 前回調査書 L206-207 の推奨アクションとも一致
2. **(代替) 現状維持 + 敵リーダー行に `(戦略由来)` の注記を付ける**
   - 手軽だが冗長。`mv=密集 (戦略由来)` のような表示
3. **(非推奨) 現状維持**
   - 開発者が混乱する可能性あり

個人的には **提案 1 が最適**。CLAUDE.md「使っていないものは残さない」原則にも沿う。変更コストは `_draw_party_block` のヘッダー組立て分岐を 1 箇所追加する程度で小さい。

---

## 5. 前回調査書との整合性

### 結論の一致

前回調査書 L216-219 の結論：「敵 8 フィールド中すべて (A) 4 件 + (B) 3 件 + (C) 1 件 のいずれかに該当。値は入るが実質無意味／デフォルト固定」。

→ **本調査と整合**。前回は「UnitAI 側のフィールドが空か・固定か」で分類、本調査は「リーダー行表示経路」で分類したが、結論はどちらも「敵の指示体系は表示も実動もプレイヤー／NPC と別系統」。

### 前回の分類 vs 今回の分類の対応

前回（UnitAI 実値ベース）と今回（表示値ベース）で分類基準が異なるため、直接マッピングはできない。対応表：

| 前回の分類 | 前回の対象 | 今回の分類 | 今回の対象 |
|---|---|---|---|
| (A) 意図的に設定しない（敵に不要） | `_special_skill` / `_hp_potion` / `_sp_mp_potion` / `_item_pickup` | (A) 表示だけで意味なし | mv / battle / tgt / hp（描画対象） |
| (B) 設定する仕組みはあるがデフォルト値のまま | `_combat` / `_battle_formation` / `_on_low_hp` | （今回の枠組みには存在しない） | — |
| (C) 仕組み自体がない（味方専用設計） | `_move_policy` | — | — |

### 前回との矛盾はあるか

**なし**。今回新たに発見した点は以下のみ：
- 前回調査書では敵リーダー行の**ヘッダー表示経路**（`get_global_orders_hint`）を分析していなかった
- 表示値は `_global_orders` でも `current_order` でもなく、**戦略からの仮想ヒント合成**という第 3 のデータソース
- この仮想ヒントは UnitAI の実動と完全に独立しており、敵では「見かけの指示」にすぎない

前回の「(B) 3 件・(C) 1 件」はあくまで **UnitAI 側 `_combat` / `_battle_formation` / `_on_low_hp` / `_move_policy`** の話であり、リーダー行ヘッダーに出ている値とは別物。本調査はこの区別を明確化した。

---

## 完了報告

1. **判定表の行数**：7 行（mv / battle / tgt / hp / item / hp_potion / sp_mp_potion）
2. **内訳**：(A) 4 件（描画対象：mv / battle / tgt / hp）+ (A) 3 件（非描画：item / hp_potion / sp_mp_potion）。(B) 0 件・(C) 0 件
3. **総合結論**：敵の指示体系は味方と**完全に異なる**。敵リーダー行ヘッダーの指示値は `PartyLeader.get_global_orders_hint()` が戦略（`_party_strategy`）から合成した仮想ラベルで、UnitAI の実動（`current_order` ＋ 種族フック ＋ ハードコード）とは別経路
4. **表示扱い提案**：敵リーダー行ヘッダーから `mv/battle/tgt/hp` を削除し、代わりに `戦略: 攻撃/撤退/待機/帰還` を表示するのが最もシンプル。CLAUDE.md の「使っていないものは残さない」原則とも整合。現状維持だと「敵に指示している」という誤解を生む
