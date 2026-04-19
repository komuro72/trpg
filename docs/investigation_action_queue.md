# アクションキュー実装 調査（2026-04-18）

> UnitAI のアクションキューが何を管理し、特殊行動がキュー経由か
> 独立経路かを正確に把握するための調査。Player/AI 統一の設計
> 判断材料とする。

## 結論サマリー

- **UnitAI のキューは「移動〜攻撃までの手順シーケンス」を保持する**。ワープ・炎陣設置・スタン付与・回復実処理など**効果発動自体はキュー外**で実行される
- キューが保持するのは **`{"action": "<type>", "target": Character?, "goal": Vector2i?, "item": Dictionary?}` 形式の辞書**。12 種の `action` 値で分岐
- **PlayerController にキューは存在しない**。ステートマシン（NORMAL/PRE_DELAY/TARGETING/POST_DELAY）+ 入力バッファ（`_move_buffer` / `_attack_buffer`）で動く、完全別アーキテクチャ
- **9 種の特殊行動のうち、キュー経由は 5 種（attack/heal/buff/v_attack/use_potion）のみ**。残り 4 種（dark-lord ワープ・dark-lord 炎陣・apply_stun 処理・BuffEffect 生成）はキュー外で直接呼ばれる
- **キューを統一的に使う設計への移行難度は L（大）**。現状の設計はそもそも Player 側にキューがないため、「キュー統一」より先に **Player 側を UnitAI と同じキュー駆動に揃える or UnitAI 側を PlayerController と同じ「即時実行」モデルに揃える**大きな決断が必要
- 実用的な推奨は **「キュー駆動を AI 側だけのまま維持し、代わりに SkillExecutor を抽出して効果発動の計算式を共通化」**（前回の投資レポートと同じ結論）

---

## 1. アクションキューのデータ構造

### 1-1. フィールド定義（[unit_ai.gd:42-43](scripts/unit_ai.gd#L42)）
```gdscript
var _queue:          Array      = []  ## アクションキュー
var _current_action: Dictionary = {}  ## 実行中アクション
```

- 型：**`Array`**（要素は `Dictionary`・専用クラスではない）
- 実行中アクションは別フィールド（`_current_action`）として切り分け保持
- `_queue[0]` がまだ `pop_front` されていなければ「先頭」・`_current_action` は `_pop_action()` で取り出されて保持

### 1-2. アクション辞書の形式
```gdscript
{"action": "<type>", "target": Character?, "goal": Vector2i?, "item": Dictionary?}
```
- 必須キー：`"action"`（文字列で種類識別）
- 任意キー：`"target"`（回復先・バフ先・ポーション対象）/ `"goal"`（探索座標）/ `"item"`（ポーション辞書）
- バリデーションは `_start_action` 内で個別に実施（target 指定が必要なのに null なら `_complete_action()` でスキップ）

### 1-3. 優先度 / サイズ制限
- **優先度概念なし**（配列の FIFO・先頭から `pop_front`）
- **サイズ制限なし**（`QUEUE_MIN_LEN = 3` は補充のしきい値であって上限ではない）

---

## 2. 定義されているアクション種類（12 種）

| action | 処理 | 必要パラメータ | 遷移先 state |
|---|---|---|---|
| `move_to_attack`  | ターゲットの隣接マスへ A* 移動 | `_target` | MOVING |
| `move_to_formation` | リーダーの隊形位置へ移動 | `_leader_ref` | MOVING |
| `move_to_explore` | 指定座標へ A* 移動（探索） | `goal: Vector2i` | MOVING |
| `move_to_heal`    | 回復対象の隣接マスへ移動 | `target: Character` | MOVING |
| `move_to_buff`    | バフ対象の隣接マスへ移動 | `target: Character` | MOVING |
| `move_to_home`    | `_home_position` へ移動（帰還） | （自動）| MOVING |
| `flee`            | 脅威から 5 マス逃走 | `_target`（脅威）| MOVING |
| `attack`          | 通常攻撃（ATTACKING_PRE → POST 経由）| `_target` | ATTACKING_PRE |
| `v_attack`        | V 特殊攻撃（同上フローで `_execute_v_attack`） | `_target` 任意 | ATTACKING_PRE |
| `heal`            | 回復実行（HP or アンデッドダメージ）| `target: Character` | WAITING |
| `buff`            | 防御バフ付与 | `target: Character` | WAITING |
| `use_potion`      | ポーション使用 | `item: Dictionary` | WAITING |
| `wait`            | 待機 | — | WAITING |

- **全 13 種の処理は `_start_action()`（[unit_ai.gd:433](scripts/unit_ai.gd#L433)）の match 文に集約**
- パラメータが足りないアクションは `_complete_action()` で即キャンセル → 次のアクションへ

---

## 3. キューへの追加経路

### 3-1. 主要経路：`_generate_queue()`
[unit_ai.gd:683](scripts/unit_ai.gd#L683) の `_generate_queue(strategy, target)` が**唯一のキュー構築エントリーポイント**。内部でサブジェネレーターを呼び分け：

| サブジェネレーター | 役割 | 優先順位 |
|---|---|---|
| `_generate_stair_queue` | 階段追従キュー（フロア追従）| **最優先**（move_policy 判定で先行）|
| `_generate_potion_queue` | ポーション使用キュー | 2 |
| `_generate_heal_queue`   | 回復・アンデッド特効キュー | 3 |
| `_generate_buff_queue`   | バフキュー | 4 |
| `_generate_special_attack_queue` | V 攻撃キュー（ATTACK 戦略時のみ）| 5 |
| `_generate_move_queue`   | 通常移動キュー | 最後 |

### 3-2. キュー置き換えトリガー
`receive_order()` が呼ばれた時（[unit_ai.gd:294](scripts/unit_ai.gd#L294)）に以下の条件で置き換え：
- `_strategy` が変化した
- `_target` が変化した
- `move_policy` が変化した
- 階段タイルに乗ったのに `move_policy` が stairs_* でない
- V 攻撃の可否状態が変化した
- キューサイズが `QUEUE_MIN_LEN=3` 未満になった（移動中除く）

**条件不成立なら既存キューを温存**（CLAUDE.md 1139 行の「即座に置き換え」とは異なり、条件付き温存）。

### 3-3. キュー置き換えの特殊パス
- **アイテム取得ナビ**（[unit_ai.gd:260-269](scripts/unit_ai.gd#L260)）：戦況 SAFE 時にフロアアイテムを発見すると、**他の生成経路を無視して即時 `_queue = [move_to_explore]` に差し替え**
- **MOVING 中のアイテム発見**（[unit_ai.gd:382-389](scripts/unit_ai.gd#L382)）：1 マス移動完了ごとに再チェック
- **`notify_situation_changed()`**（[unit_ai.gd:308](scripts/unit_ai.gd#L308)）：WAIT 中なら即 IDLE に戻してキュー破棄。次フレームで `receive_order` が再生成

### 3-4. A* 経路探索の結果は **キューに入らない**
- A* は `_step_toward_goal()` → `_get_next_step()` → `_astar()` で **1 マスずつ取得**（全経路を事前展開しない）
- `_goal: Vector2i` を持って、タイムスリップ時に都度再探索
- **MOVING 状態は 1 アクション = 全経路**（`_timer <= 0` のたびに 1 歩進む）

---

## 4. キューの実行タイミング

### 4-1. `_process(delta)` の構造（[unit_ai.gd:333](scripts/unit_ai.gd#L333)）
```
if world_time_running == false: return
if is_stunned:
    _state = IDLE
    _queue.clear()
    return
_reeval_timer -= delta
if _reeval_timer <= 0:
    _fallback_evaluate_action()  # order ない時のみ

match _state:
    IDLE:
        action = _pop_action()    # キューから取り出し
        if action:
            _start_action(action)  # ここで _state が変わる
        elif _queue.is_empty():
            receive_order(_order)  # キュー空なら再生成
    MOVING:
        ... 1 歩進む / 到達で _complete_action()
    WAITING:
        ... _timer 消化で _complete_action()
    ATTACKING_PRE:
        ... pre_delay 経過で _execute_attack() または _execute_v_attack()
        → ATTACKING_POST
    ATTACKING_POST:
        ... post_delay 経過で IDLE
```

### 4-2. 1 フレームに何アクション？
- 基本：**1 アクションのみ**進行（`_state` ベース）
- 例外：`_start_action()` 内で前提条件不成立（target null 等）なら即 `_complete_action()` する → 実質スキップ → 次フレームで次のアクション

### 4-3. アクションの途中経過
| state | 保持する進捗 |
|---|---|
| MOVING | `_goal`（目的地）+ `_timer`（次の 1 歩まで）|
| WAITING | `_timer`（残り時間）|
| ATTACKING_PRE | `_timer`（pre_delay 残り）+ `_attack_target` |
| ATTACKING_POST | `_timer`（post_delay 残り）|
| IDLE | なし（次のアクションを取り出す準備）|

### 4-4. キューが空のとき
- `IDLE` で `_pop_action()` が空辞書を返す
- `_queue` も空 → `receive_order(_order)` を再実行（オーダーありなら再生成）
- オーダー空なら `_fallback_evaluate_action()`（`_reeval_timer` 経由で定期的に再評価）

---

## 5. 特殊行動 9 種の実装パターン比較

| # | 特殊行動 | キュー経由？ | 実処理の呼び出し箇所 |
|---|---|:-:|---|
| a | **Player ヒーラーの Z 回復** | ❌ **独立経路** | `player_controller.gd:_execute_heal` を TARGETING 確定後に直接呼び出す |
| b | **AI ヒーラーの Z 回復** | ✅ **キュー経由**（`move_to_heal` → `heal`）| `_start_action` の `"heal":` 分岐で直接計算・`tgt.heal()` |
| c | **magician-fire の炎陣設置**（Player）| ❌ **独立経路** | TARGETING なし・`_execute_flame_circle` が `FlameCircle.new()` を直接生成 |
| c' | **magician-fire の炎陣設置**（AI）| ✅ **キュー経由**（`v_attack`）→ ATTACKING_PRE 経由で `_execute_v_attack` → `_v_flame_circle` |
| d | **magician-water のスタン**（Player）| ❌ **独立経路** | `_execute_water_stun` が `Projectile.setup()` に `stun_duration` を渡す |
| d' | **magician-water のスタン**（AI）| ✅ **キュー経由**（`v_attack`）→ `_v_water_stun` が `_target.apply_stun()` |
| e | **healer の防御バフ**（Player）| ❌ **独立経路** | `_execute_buff` が `target.apply_defense_buff()` を直接呼ぶ |
| e' | **healer の防御バフ**（AI）| ✅ **キュー経由**（`move_to_buff` → `buff`）| `_start_action` の `"buff":` で `apply_defense_buff()` |
| f | **dark-lord のワープ** | ❌ **完全にキュー外** | `DarkLordUnitAI._process` が `super._process()` と**並行**で warp timer を消化・`_do_warp()` が `_member.grid_pos = dest` で瞬間移動 |
| g | **dark-lord の炎陣設置** | ❌ **完全にキュー外** | ワープ直後に `_place_flame_circle()` が `FlameCircle.new()` を直接生成（キューを通らない）|
| h | **harpy の降下攻撃** | ✅ **キュー経由**（`attack`）→ `_execute_attack` の `dive` ケース | 通常攻撃と同じフロー。`attack_type="dive"` で分岐するだけ |
| i | **通常の melee 攻撃**（AI）| ✅ **キュー経由**（`move_to_attack` → `attack`）| 標準的なシーケンス |
| i' | **通常の melee 攻撃**（Player）| ❌ **独立経路** | ステートマシン（NORMAL → PRE_DELAY → TARGETING → POST_DELAY）で `_execute_melee` を TARGETING 確定後に呼ぶ |

### 集計

#### キュー経由で実行される特殊行動（5 種）
b / c' / d' / e' / h / i（AI 側の全行動）

#### キュー外で実行される特殊行動（6 種）
- **Player 側は全てキュー外**（a / c / d / e / i' 他）
- **dark-lord 固有**（f / g）：AI 側でも完全独立

---

## 6. アクションの中断・キャンセル

### 6-1. キュー置き換えポリシー（現状）
CLAUDE.md 1139 行（参考仕様・未使用の LLM 時代スペック）：
> 返ってきたシーケンスは既存キューと実行中アクションを即座に置き換えて開始する（追加方式ではなく置き換え方式）

**現状は「条件付き置き換え」**：
| 条件 | 動作 |
|---|---|
| 戦略 / ターゲット / move_policy が変化 | ✅ 即置き換え |
| V 攻撃の可否状態が変化 | ✅ 即置き換え |
| 階段タイルに乗ったのに move_policy が stairs_* 以外 | ✅ 即置き換え |
| キューサイズ < 3 | ✅ 補充 |
| 上記以外（安定状態） | ❌ **温存**（LLM 時代の仕様とは異なる） |

### 6-2. 実行中アクションへの影響
- **MOVING / WAITING 中の置き換え**：キュー置き換え時に `_state = IDLE` + `_current_action = {}` にリセット
- **ATTACKING_PRE / POST 中の置き換え**：キュー置き換えはするが、`_state` は維持（攻撃モーションは完遂させる）
- **スタン発動時**（`is_stunned`）：`_queue.clear()` で完全破棄・`_state = IDLE`

### 6-3. 特殊行動の中断
- **dark-lord のワープ + 炎陣**：キュー外で走るため、キュー置き換えでも中断されない（ワープは同一フレームで完了するが、炎陣はセットアップ後は独立に存続）
- **FlameCircle**（設置済み）：duration が尽きるまで自動で継続。途中で破棄する機構なし
- **Projectile**（飛翔中）：目標まで飛び続ける。発射元が死亡しても問題なし（`safe_attacker` で null チェック）
- **スタン付与**：`Character.stun_timer` のカウントダウンで消化（AI 側のキューとは無関係）

---

## 7. Player 側のキュー

### 7-1. **PlayerController にキューは存在しない**
代わりに：

| フィールド | 役割 |
|---|---|
| `_mode: Mode` | 現在モード（NORMAL / PRE_DELAY / TARGETING / POST_DELAY）|
| `_move_buffer: Vector2i` | 先行入力バッファ（移動方向）|
| `_attack_buffer: bool` | 攻撃入力バッファ |
| `_pre_delay_remaining: float` | PRE_DELAY 残り時間 |
| `_post_delay_remaining: float` | POST_DELAY 残り時間 |
| `_pending_move_dir: Vector2i` | TARGETING 中に溜まった移動入力 |

### 7-2. 動作フロー（Player 通常攻撃）
```
NORMAL
  └── Z 押下 → _enter_pre_delay()
      └── _mode = PRE_DELAY, _pre_delay_remaining = slot.pre_delay
PRE_DELAY
  └── timer 消化 → TARGETING 遷移（射程表示）
TARGETING
  └── Z 確定 → _execute_melee/ranged/heal/...（即実行）
      → _mode = POST_DELAY
POST_DELAY
  └── timer 消化 → NORMAL
```

UnitAI の `ATTACKING_PRE → _execute_attack → ATTACKING_POST` と類似の流れだが、**キューを介さずに直接呼び出す**のが本質的な違い。

### 7-3. 2 系統の共通点・相違点

| 観点 | UnitAI（キュー駆動）| PlayerController（ステートマシン+バッファ）|
|---|---|---|
| 行動シーケンス | 事前に Array で構築 | 入力に応じてその場で遷移 |
| 先行入力 | ❌（キュー内で逐次処理） | ✅（`_move_buffer` / `_attack_buffer`）|
| ターゲット選択 | AI が `_target` を自動決定 | TARGETING モードでプレイヤーが選択 |
| pre_delay / post_delay | 両方あり | 両方あり（モード名で表現）|
| キャンセル | キュー置き換えで実現 | X 押下で TARGETING を抜ける |
| 実処理の呼び出し | `_start_action` の match → `_execute_attack` / `_v_*` | TARGETING 確定時に直接 `_execute_melee/ranged/heal/...` |

---

## 8. 所感

### 8-1. 設計としての完成度
**キュー設計自体は整っている**が、以下の違和感がある：

- ✅ **良い点**
  - 辞書ベースで素朴・理解しやすい
  - アクション種 12 個が `_start_action` の match 文に集約されていて見通しが良い
  - `_generate_queue` が優先順位を明示している
  - キュー置き換えポリシー（条件付き）は合理的

- ⚠️ **違和感**
  - LLM 時代の「純粋置き換え」から「条件付き温存」に進化したが、CLAUDE.md 1139 行が更新されていない → 仕様と実装が乖離
  - **dark-lord のワープ・炎陣設置がキュー外**：キュー設計から逸脱した例外。他に同じ発想で特殊敵を追加すると形骸化する
  - アイテム取得ナビが `_queue = [...]` で直接差し替え → キュー置き換えポリシーを経由しない特別扱い
  - **Player 側にキューがない**：統一感がない

### 8-2. キューを統一的に使うリファクタリングの現実性

#### 選択肢 1: Player 側を UnitAI のキュー駆動に揃える
- **難度**：🔴 **L（大）**
- **理由**：Player は入力駆動（イベントベース）・UnitAI は時間駆動（タイマーベース）。根本から思想が異なる。Player にキューを持たせると「TARGETING 中にプレイヤーが指示を途中で変える」「先行入力」「ガードホールド」などの対話的な操作感を実装するのが格段に難しくなる。**推奨しない**

#### 選択肢 2: UnitAI 側を「即時実行」モデルに揃える
- **難度**：🟠 **M（中）**
- **理由**：AI は意思決定 → シーケンス構築 → 1 ステップずつ消化の構造が性に合っている。キューを排除すると「AI の思考サイクル」の可視性が落ちる。**推奨しない**

#### 選択肢 3: キュー駆動を AI 側のみで維持し、**効果発動の計算式だけ共通化**
- **難度**：🟢 **M（中）**（前回の投資レポートの **「SkillExecutor 抽出」** 案）
- **理由**：
  - キュー設計自体はむしろ維持すべき（AI が複数ステップの計画を立てる性質と合致）
  - 問題は「キュー経由 or 独立経路」ではなく「実処理の計算式が二重実装」
  - `_start_action "heal"` の計算ブロック（約 30 行）と `_execute_heal` の計算ブロック（約 30 行）を `SkillExecutor.execute_heal(caster, target, slot)` に抽出すれば、キュー設計は温存しつつ乖離バグを構造的に解消できる
  - **推奨**

#### 選択肢 4: dark-lord を slots.V 経由に移しつつ、キュー経由の実装にする
- **難度**：🟡 **S〜M**
- **理由**：`DarkLordUnitAI._process` のワープタイマーを独立実装のまま維持しつつ、`_do_warp` 内で `_queue.push_front({"action": "v_attack"})` のようにキューに入れる手もある。ただし「ワープ + 炎陣設置」は 1 フレームで完結する独立処理なのでキューに入れる意義が薄い。**見送りでよい**

### 8-3. 推奨
**選択肢 3（SkillExecutor 抽出）を最優先**。キュー設計自体は変更せず、「キュー内の `action` 処理（`_start_action` 各分岐）」と「PlayerController の `_execute_*` 各メソッド」の**中身**を同じ `SkillExecutor.execute_xxx(actor, target, slot)` に揃える。

キューを統一的に使う設計への全面移行は労力対効果が悪く、Player の対話性を損なうリスクが大きいため**推奨しない**。

---

## 付録：関連コード参照

| 対象 | 場所 |
|---|---|
| `_queue` 定義 | [unit_ai.gd:42](scripts/unit_ai.gd#L42) |
| `_pop_action` | [unit_ai.gd:998](scripts/unit_ai.gd#L998) |
| `_complete_action` | [unit_ai.gd:1007](scripts/unit_ai.gd#L1007) |
| `_start_action` 全分岐 | [unit_ai.gd:433-605](scripts/unit_ai.gd#L433) |
| `_generate_queue` | [unit_ai.gd:683](scripts/unit_ai.gd#L683) |
| `_process` 本体 | [unit_ai.gd:333](scripts/unit_ai.gd#L333) |
| `receive_order` キュー置き換え | [unit_ai.gd:294](scripts/unit_ai.gd#L294) |
| `notify_situation_changed` | [unit_ai.gd:308](scripts/unit_ai.gd#L308) |
| DarkLord ワープ（キュー外）| [dark_lord_unit_ai.gd:31-46](scripts/dark_lord_unit_ai.gd#L31) |
| Player ステートマシン | [player_controller.gd:61-63, 340-378](scripts/player_controller.gd#L61) |
| Player 入力バッファ | [player_controller.gd:72-76](scripts/player_controller.gd#L72) |
