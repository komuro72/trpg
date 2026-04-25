# Investigation: PartyStatusWindow `mv=追従` vs non-leader `move:密集` mismatch

## 観察された不整合

```
[NPC] ... mv=追従 ...
  クレア[A](剣士) ... move:↓階段 ... leader
  ヴィオラ[B](斥候) ... move:密集 ...
```

ヘッダー `mv=追従`（= `_global_orders.move == "follow"`）に対して、
非リーダーメンバーの行では `move:密集`（= `_move_policy == "cluster"`）が表示される。

結論を先に：**Hypothesis B が正解**。
ヘッダーとメンバー行は **意図的に別フィールド** を読んでいる。
4/25 の NPC 階段ナビ規約違反修正で、`_global_orders.move` には
OrderWindow 定義値（`follow / cluster / same_room / standby / explore`）
しか書き込まないことになっており、階段ナビ中（`pol == "stairs_down/up"`）は
`hint["move"]` を更新しない設計になっている。
このため、リーダーが階段ナビ中（`_move_policy = "stairs_down"`）でも
`hint["move"]` は NPC ベースラインの `"follow"` のまま残る。
非リーダーは `_assign_orders()` の explore 分岐で `_move_policy = "cluster"` に
書き換えられているので、ヘッダー/メンバー行の食い違いは**仕様どおりの帰結**で、
実害（AI 行動の不一致）はない。

---

## 1. ヘッダー `mv=` ソース

- **ファイル**：`scripts/party_status_window.gd`
- **行**：415-416、430
  ```gdscript
  var mv_raw:     String = hint.get("move", "-") as String
  var mv_str:     String = _label("move", mv_raw)
  ```
  - `hint` は line 396 で `pm.get_global_orders_hint()` から取得
  - 生成順序：
    1. `PartyManager.get_global_orders_hint()` → `_leader_ai.get_global_orders_hint()`
    2. `PartyLeader.get_global_orders_hint()` (`scripts/party_leader.gd:668`) は
       `_build_orders_part()` を呼ぶ
    3. NpcLeaderAI が `_build_orders_part()` を override
       (`scripts/npc_leader_ai.gd:217-243`)
       - 行 219-227：NPC ベースライン辞書（`"move": "follow"` 等）を返却
       - 行 229-230：`_global_orders` の値を上書きマージ（合流済みなら反映）
       - 行 239-242：`_is_in_explore_mode()` 中、かつ `pol == "explore"` のとき
         のみ `hint["move"] = "explore"` で上書き。
         **`stairs_down` / `stairs_up` の場合は `hint["move"]` を更新しない**
         （4/25 改訂で意図的にスコープ外）

- **ラベル変換**：`_label("move", val)`（行 1085-1094）
  - 階段値の特例：`stairs_down → "↓階段"`, `stairs_up → "↑階段"`
  - その他：`_label_cache["move"]` 経由で OrderWindow 定数の `"follow" → "追従"` /
    `"cluster" → "密集"` / `"same_room" → "同じ部屋"` / `"standby" → "待機"` /
    `"explore" → "探索"` にマッピング（`scripts/order_window.gd:22-23`）

## 2. メンバー行 `move:` ソース

- **ファイル**：`scripts/party_status_window.gd`
- **行**：852-857
  ```gdscript
  func _build_move_policy_part(ai: UnitAI) -> String:
      if not _show_var("move_policy"):
          return ""
      if ai == null or not is_instance_valid(ai):
          return ""
      return "move:%s" % _label("move", str(ai.get("_move_policy")))
  ```
  - `ai` は対象メンバーの `UnitAI` インスタンス
  - 直接 `UnitAI._move_policy`（`scripts/unit_ai.gd:66`）を読む
  - 詳細度は `_show_var("move_policy")`（priority 1 = 中・行 70）

- **`_move_policy` への書き込み経路**：
  `UnitAI.receive_order(order)` 行 224-235
  ```gdscript
  var new_move := order.get("move", "spread") as String
  ...
  _move_policy = new_move
  ```
  - `receive_order` は `PartyLeader._assign_orders()` から
    （`scripts/party_leader.gd:418-432`）呼ばれ、`order["move"]` には
    per-member に算出された `move_policy` が入る

- **ラベル変換**：ヘッダーと同じ `_label("move", val)` を使用（共通）

## 3. 個別メンバー override パス（`_assign_orders()`）

`scripts/party_leader.gd:_assign_orders()`（行 297-432）でのみ
`unit_ai.receive_order({"move": move_policy})` が発行される。
`move_policy` の決定経路：

| トリガー | リーダー | 非リーダー | 場所 |
|---|---|---|---|
| 通常時（味方）| `party_orders.get("move")` (= hint["move"]・基底) | 同左 | party_leader.gd:361 |
| 通常時（敵）| `_global_orders.get("move", current_order.move)` 相当（味方ガード外）| 同左 | party_leader.gd:361 で `m.is_friendly` ガード（敵は `move_policy = "spread"` 初期値のままになる） |
| `_is_in_explore_mode()` + `pol == "stairs_down"` | `"stairs_down"` | `"cluster"` | party_leader.gd:374-381 |
| `_is_in_explore_mode()` + `pol == "stairs_up"` | `"stairs_up"` | `"cluster"` | 同上 |
| `_is_in_explore_mode()` + `pol == "explore"` | `"explore"` | `"cluster"` | party_leader.gd:382-385 |
| `_is_in_guard_room_mode()` | `"guard_room"` | `"guard_room"` | party_leader.gd:386-387 |
| `joined_to_player == true` | 全員に explore 分岐スキップ（line 375 `if not joined_to_player`） | 同左 | party_leader.gd:375 |

`_is_in_explore_mode()` フックの実装：
- 基底 `PartyLeader._is_in_explore_mode()`（行 883）：`_party_strategy == EXPLORE`（敵専用）
- `NpcLeaderAI._is_in_explore_mode()`（行 119-120）：`not _has_visible_enemy()`
  → NPC は敵が見えない間は常に explore モード

`_get_explore_move_policy()` の実装：
- 基底 `PartyLeader._get_explore_move_policy()`（行 863-864）：常に `"explore"`
- `NpcLeaderAI._get_explore_move_policy()`（行 183-196）：
  目標フロアと現在フロアの差分から `stairs_down` / `stairs_up` / `explore` を返す

## 4. `_global_orders.move` 更新パス

- **初期値**：`scripts/party_leader.gd:40` で `var _global_orders: Dictionary = {}`（空辞書）
- **`set_global_orders()` 経由（参照共有）**：`scripts/party_leader.gd:164-165`
  - `scripts/game_map.gd:337` — プレイヤーパーティーの `_hero_manager` に
    `party.global_orders` を渡す（OrderWindow 操作と参照共有）
  - `scripts/game_map.gd:1102` — 同パスのリーダー再選出時
  - `scripts/game_map.gd:1158` — NPC 合流時に `nm.set_global_orders(party.global_orders)` で
    プレイヤーの `Party.global_orders` を NpcLeaderAI に渡す
  - `scripts/party_manager.gd:154-157` — PartyManager.set_global_orders → leader_ai 転送
  - `scripts/party_manager.gd:529` — リーダー再生成時に再アタッチ
- **`_global_orders["..."] = ...` の直接代入**：
  - `scripts/npc_leader_ai.gd:337` — `_global_orders["battle_policy"] = new_policy`
    （CRITICAL/SAFE 自動切替・**`move` キーは触らない**）
- **NPC が `_global_orders["move"]` に書き込む経路は現存しない**（4/25 の修正で
  `stairs_down/up` の書き込みを廃止済み）。
- 未合流 NPC の `_global_orders` は空のまま。`_build_orders_part()` の
  ベースライン `{"move": "follow", ...}` がヘッダーに使われる。

## 5. 仮説判定

### 観察データ
- ヘッダー：`mv=追従`（= `hint["move"] == "follow"`）
- リーダー行：`move:↓階段`（= `_move_policy == "stairs_down"`）
- 非リーダー行：`move:密集`（= `_move_policy == "cluster"`）
- 状況：NPC パーティー（`joined_to_player == false`）・敵未検知（探索モード）・
  リーダーが下フロア向け階段ナビ中

### 仮説評価

- **A: ヘッダー描画バグ** ✗ —
  ヘッダーは `hint["move"]` を正しく読み、`_label("move", "follow")` で「追従」を
  正しく表示している。バグではない。
- **B: 個別ライン書き換えとヘッダー読み取りの不一致**（**正解**）—
  - `_assign_orders()` の explore 分岐（party_leader.gd:374-385）が、
    リーダーには `pol`（= `"stairs_down"`）、非リーダーには `"cluster"` を
    `move_policy` として配布し、`receive_order()` 経由で `_move_policy` に流し込む。
    → リーダー行 `move:↓階段` / 非リーダー行 `move:密集` は **整合**。
  - 一方、ヘッダーの読み取り元 `_build_orders_part()`（npc_leader_ai.gd:217-243）は、
    4/25 改訂で「`stairs_*` / `target_floor` を `_global_orders.move` に書き込まない」
    方針に変更済み。`pol == "stairs_down"` の場合 `hint["move"]` は NPC ベースライン
    の `"follow"` のままになる。
    → ヘッダー `mv=追従` は **規約どおりの帰結**。
  - つまりヘッダーとメンバー行は **異なるフィールド**（`hint["move"]` と
    `_move_policy`）を読んでいて、`_assign_orders()` 側だけに per-member 配布が
    存在するため、階段ナビ中は必ず食い違う。これは 4/25 改訂時に意図された動作。
- **C: `_global_orders.move` が実は `"cluster"`** ✗ —
  - 未合流 NPC では `_global_orders` は空辞書のまま（書き込み経路なし・項目 4 参照）。
  - 「`mv=追従`」と表示されている時点で、`hint["move"] = "follow"` であり
    `_global_orders["move"]` 由来ではなく `_build_orders_part()` のベースライン由来。
  - 仮に `_global_orders["move"] == "cluster"` ならヘッダーは `mv=密集` になるはず。

### 結論

Hypothesis **B** が正解。証拠の決定打：
1. `npc_leader_ai.gd:239-242`：`pol == "explore"` のときのみ `hint["move"]` 更新。
   `stairs_*` の場合は更新しない（**4/25 改訂で意図的に追加された分岐**）。
2. `party_leader.gd:377-381`：explore モードかつ `pol in ["stairs_down","stairs_up"]`
   のとき、リーダー → `pol`、非リーダー → `"cluster"`（per-member 配布）。
3. `party_leader.gd:418-432` → `unit_ai.gd:235`：`_move_policy = order.move`（
   per-member 配布された値が直接書き込まれる）。

ヘッダーは「OrderWindow 規約に準拠したパーティー全体指示」を表示し、メンバー行は
「UnitAI が実際に従っている個別 move policy」を表示する設計。
両者は階段ナビ中に必然的にずれるが、これは**規約と表示の整合に基づく仕様**であり、
ゲーム挙動に影響するバグではない。

### 補足：CLAUDE.md「残タスク」記述との対応

CLAUDE.md の `mv=` と `move:` の不整合調査タスクで挙げられた 3 つの仮説候補：
- 「NPC ベースラインの `_global_orders.move` が `cluster` で…別フィールド由来の可能性」
  → **半分正解**。`_global_orders` 自体は空だが、ヘッダーが読む `hint["move"]` の
  ベースライン値は `"follow"`（`cluster` ではない）。「ヘッダー値が別フィールド由来」
  の部分が今回の事象に対応する。
- 「`_assign_orders()` の `_is_in_explore_mode()` 分岐で非リーダーを `cluster`
  固定化している箇所の影響」
  → **正解**（party_leader.gd:381）
- 「ヘッダー表示ロジック自体の不具合」
  → 不具合ではなく、4/25 規約改訂による意図的な乖離

修正の方向性（CLAUDE.md「優先度：中」項目「`_global_orders.move` への `explore`
書き込み」と同根）：`stairs_*` 値も `_global_orders.move` には書き込まない方針を
維持しつつ、ヘッダー表示側で「リーダーの `_move_policy` を補助表示する」
（例：`mv=追従(L:↓階段)`）等の表示拡張を検討してもよい。
ただし現状は「規約準拠の表示 vs 実挙動」を意図的に分離しているので、
変更は別タスクの設計判断が必要。
