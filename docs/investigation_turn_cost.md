# 向き変更コストの現状調査

## 目的
攻撃範囲拡大（近接キャラの斜め前追加）と「攻撃ボタン押下中の振り向き」実装を踏まえ、向き変更コストの仕様を統一的に再設計するための事前調査。

## サマリー

### コスト発生マトリクス

| 局面 | 主体 | コスト | 値 | 実装 |
|---|---|---|---|---|
| 通常移動の向き変更 | プレイヤー | **あり**（操作不能ブロック） | `TURN_DELAY=0.15s` | [player_controller.gd:1248](../scripts/player_controller.gd#L1248) |
| 通常移動の向き変更 | AI（味方/敵共通） | **なし**（即時） | — | [character.gd:578 (move_to)](../scripts/character.gd#L578) |
| 攻撃ボタン押下中の振り向き | プレイヤー | **なし**（即時） | — | [player_controller.gd:570 (_try_facing_change_from_input)](../scripts/player_controller.gd#L570) |
| 攻撃実行時の方向転換 | プレイヤー / AI 共通 | **なし**（即時） | — | [skill_executor.gd:34, 82, 110, 208, 241, 373](../scripts/skill_executor.gd#L34) |
| ガード中の向き変更 | プレイヤーのみ（AI ガードなし） | **不可**（向き固定） | — | [character.gd:580 (move_to)](../scripts/character.gd#L580) |
| AI 移動時の向き変更 | AI | **なし**（move_to で即時） | — | [unit_ai.gd:620](../scripts/unit_ai.gd#L620) |
| AI V スキル直前の向き変更 | AI | **なし**（face_toward で即時） | — | [unit_ai.gd:1086, 1160](../scripts/unit_ai.gd#L1086) |

### 一行結論
- 向き変更コストが**唯一存在するのはプレイヤーの通常移動時**（`TURN_DELAY = 0.15s` の操作不能ブロック）
- それ以外（プレイヤー攻撃中・AI 全般・SkillExecutor 攻撃実行）はすべて**即時**で無コスト

---

## 1. 向き変更がコストを持つ局面（詳細）

### 1-1. 通常移動時の向き変更（プレイヤー）— **コストあり**

**実装**：[player_controller.gd:1240-1252](../scripts/player_controller.gd#L1240) `_try_move`

```gdscript
func _try_move(dir: Vector2i) -> void:
    var new_pos := character.grid_pos + dir
    # ガード中は向き固定
    if not character.is_guarding:
        var target_facing := _compute_facing_for(new_pos - character.grid_pos)
        if target_facing != character.facing:
            # 向きが異なる → まず回転だけ行い移動しない
            _is_turning = true
            _turn_timer = GlobalConstants.TURN_DELAY / GlobalConstants.game_speed
            _pending_move_dir = dir
            character.start_turn_animation(target_facing, _turn_timer, ...)
            return
```

**挙動**：
- 移動方向が現在の `facing` と異なる場合、**移動せず回転のみ**を行う
- 回転中（`_is_turning=true`）は次フレームの移動入力をブロックする（[player_controller.gd:444-449](../scripts/player_controller.gd#L444)）
- `_turn_timer` を `TURN_DELAY / game_speed` で初期化し、毎フレームデクリメント
- タイマー完了で `_is_turning=false`、`character.complete_turn()` を呼び `facing` を確定
- 完了時に入力キーがまだ押されていれば移動再開（[player_controller.gd:451-455](../scripts/player_controller.gd#L451)）
- `_is_turning` 中は `world_time_running=true`（時間進行）。入力ブロック＝プレイヤー操作だけが止まる

**値**：`GlobalConstants.TURN_DELAY = 0.15`（秒）。Config Editor の Effect カテゴリで調整可能 ([global_constants.gd:280](../scripts/global_constants.gd#L280))

**重要な副次効果**：
- TURN_DELAY 中は **`character.facing` が古い値のまま**（complete_turn で初めて更新）
- `_turn_target_facing` には目標値が保存されているが、外部参照は不可
- → 0.15 秒間「視覚的には回転中だが、論理的には旧向き」の状態が続く

### 1-2. 攻撃ボタン押下中の振り向き（プレイヤー）— **コストなし**

**実装**：[player_controller.gd:570-581](../scripts/player_controller.gd#L570) `_try_facing_change_from_input`

```gdscript
func _try_facing_change_from_input() -> void:
    if not is_instance_valid(character):
        return
    var dir := _get_input_direction()
    if dir == Vector2i.ZERO:
        return
    var target_facing := _compute_facing_for(dir)
    if target_facing == character.facing:
        return
    character.face_toward(character.grid_pos + dir)
    if map_node != null:
        map_node.queue_redraw()
```

**挙動**：
- PRE_DELAY および TARGETING（押下中）で矢印キー入力を検出
- `character.face_toward()` を呼んで**即時に `facing` を更新**＋`rotation` も即時スナップ
- TURN_DELAY のような操作不能ブロックは**ない**

**呼出箇所**：
- [player_controller.gd:523](../scripts/player_controller.gd#L523) `_process_pre_delay`
- [player_controller.gd:629](../scripts/player_controller.gd#L629) `_process_targeting`（押下中のみ）

### 1-3. 攻撃実行時の方向転換（SkillExecutor）— **コストなし**

**実装**：[skill_executor.gd](../scripts/skill_executor.gd)

各スキル関数の冒頭で `attacker.face_toward(target.grid_pos)` を呼び、ダメージ計算前に**即時で対象を向く**。プレイヤー/AI 共通：

| スキル | 行 |
|---|---|
| `execute_heal` | [skill_executor.gd:34](../scripts/skill_executor.gd#L34) |
| `execute_melee` | [skill_executor.gd:82](../scripts/skill_executor.gd#L82) |
| `execute_ranged` | [skill_executor.gd:110](../scripts/skill_executor.gd#L110) |
| `execute_water_stun` | [skill_executor.gd:208](../scripts/skill_executor.gd#L208) |
| `execute_buff` | [skill_executor.gd:241](../scripts/skill_executor.gd#L241) |
| `execute_headshot` | [skill_executor.gd:373](../scripts/skill_executor.gd#L373) |
| `execute_rush` / `execute_sliding` / `execute_flame_circle` | 攻撃者の `facing` を読むのみ（呼出前に AI 側で `face_toward` 済 — [unit_ai.gd:1086, 1160](../scripts/unit_ai.gd#L1086)） |

**プレイヤー側の重複**：プレイヤーは既に `_try_facing_change_from_input` でターゲット方向を向いているケースが多いが、`_confirm_target` → `SkillExecutor.execute_*` で再度 `face_toward` が呼ばれる。冪等な操作なので問題は起きないが、無駄ではある。

**heal / buff_defense（全方向対象）**：自分自身を回復対象に選んだ場合、`face_toward(self.grid_pos)` は `delta == Vector2.ZERO` のため向き不変（`face_toward` の `if abs(delta.x) >= abs(delta.y)` で `delta.x=0, delta.y=0` → DOWN ではなく DOWN になるが、もとの向きが上書きされる可能性あり、[character.gd:605-611](../scripts/character.gd#L605) を要確認）。

### 1-4. ガード中の向き変更（プレイヤー）— **不可**

**実装**：
- `is_guarding` は `Character` のフラグ ([character.gd:153](../scripts/character.gd#L153))
- ガード中の向き固定は [character.gd:580](../scripts/character.gd#L580) `move_to` で実装：

```gdscript
func move_to(new_grid_pos: Vector2i, duration: float = 0.4) -> void:
    # ガード中は向きを変更しない（guard_facing を維持）
    if not is_guarding:
        var d := new_grid_pos - grid_pos
        if d.x > 0:
            facing = Direction.RIGHT
        ...
        start_turn_animation(facing, duration, d)
    # 向き更新スキップ後も移動自体は実行される
```

- プレイヤー操作側の `_try_move` では `if not character.is_guarding` で TURN_DELAY ブロックもスキップ ([player_controller.gd:1243](../scripts/player_controller.gd#L1243))
- ガード中も**移動自体はできる**（向きが固定されたまま位置のみ移動）

**「guard_facing」変数は存在しない**：
- コメント上だけ「guard_facing を維持」と書かれているが、実体は `facing` を変更しないだけ
- ガード解除 → 移動 → 再ガードのサイクルで実質的に向き変更可能（ガード ON/OFF 自体には遅延なし）
- ガード入力（`menu_back` ホールド）は `_process_guard_and_move` 冒頭で毎フレーム `is_action_pressed` 判定 ([player_controller.gd:439-441](../scripts/player_controller.gd#L439))。瞬時に切替可能

### 1-5. AI 操作時の向き変更（味方/敵共通）— **コストなし**

**実装**：[unit_ai.gd:620](../scripts/unit_ai.gd#L620)

```gdscript
_member.move_to(next, _get_move_interval())
```

- AI は `_member.move_to(next, ...)` を呼ぶだけ
- `Character.move_to` 内で `facing` が**即時更新** ([character.gd:583-589](../scripts/character.gd#L583))
- `start_turn_animation` で視覚的な回転 tween は走るが、論理 `facing` は move 開始時点で確定
- TURN_DELAY 相当の操作不能ブロックは**ない**
- AI のキューは `character.is_moving()` の完了を待って次アクションに進むだけ（向き変更分の追加待機なし）

### 1-6. 敵キャラの向き変更（EnemyLeaderAI / UnitAI）

EnemyLeaderAI も NpcLeaderAI もプレイヤー以外は全て UnitAI 経由で動く → 1-5 と同じ。**コストなし**。

---

## 2. 向き変更の角度依存性

### 90° vs 180° の挙動差

**実装**：[character.gd:524-536](../scripts/character.gd#L524) `_calc_turn_delta_rad`

```gdscript
static func _calc_turn_delta_rad(from_rot, to_rot, last_dir) -> float:
    var delta := to_rot - from_rot
    while delta > PI:  delta -= TAU
    while delta <= -PI: delta += TAU
    # 180° のとき last_dir.x で回転方向を決定
    if absf(absf(delta) - PI) < 0.01:
        if last_dir.x < 0:  delta = PI    # 反時計回り（LEFT 経由）
        else:               delta = -PI   # 時計回り（RIGHT 経由）
    return delta
```

**結論**：
- **時間に差はなし**。90°回転も180°回転も**同じ duration（TURN_DELAY=0.15s）で完了**
- 180°時は `last_dir.x` の符号で「反時計回り or 時計回り」だけ決定（経由ルートが視覚的に変わるだけ）
- 角度に応じてコストが変わる実装は**ない**

### 180° の方向決定ルール（視覚演出のみ）
- `last_dir.x < 0`（左方向の入力）→ 反時計回り（LEFT 経由）
- `last_dir.x >= 0`（右方向の入力 or 縦方向）→ 時計回り（RIGHT 経由）

---

## 3. 向き変更の実装箇所

### 集約状況：**部分的に集約**

#### Character クラス内（推奨される正規ルート）

| メソッド | 役割 | 即時/tween | コスト |
|---|---|---|---|
| `face_toward(grid_pos)` ([:605](../scripts/character.gd#L605)) | 即時に facing 更新＋rotation スナップ | 即時 | なし |
| `move_to(grid_pos, dur)` ([:578](../scripts/character.gd#L578)) | facing 更新＋start_turn_animation で tween | 即時+tween | なし |
| `start_turn_animation(target, dur, last_dir)` ([:501](../scripts/character.gd#L501)) | rotation の tween のみ（facing は変更しない） | tween | なし |
| `complete_turn()` ([:514](../scripts/character.gd#L514)) | tween キル＋ facing 確定 | 即時 | なし |
| `_apply_direction_rotation()` ([:427](../scripts/character.gd#L427)) | rotation を facing に同期（即時） | 即時 | なし |
| `_calc_turn_delta_rad(from, to, last_dir)` ([:524](../scripts/character.gd#L524)) | 最短回転角の計算（180°時の方向決定） | — | — |
| `_direction_to_rotation(dir)` ([:433](../scripts/character.gd#L433)) | Direction → ラジアン変換（DOWN=0、UP=π、RIGHT=-π/2、LEFT=π/2） | — | — |

#### 直接 facing を書き換える箇所
- [character.gd:583-589](../scripts/character.gd#L583) `move_to` 内（ガード時はスキップ）
- [character.gd:608-610](../scripts/character.gd#L608) `face_toward` 内
- [character.gd:518](../scripts/character.gd#L518) `complete_turn` 内（`_turn_target_facing` から代入）

→ **`facing = ...` の直接代入は Character 内のみ**。外部から `set_facing()` 的な汎用ヘルパーは無い。`face_toward(grid_pos)` 経由で書き換える慣例。

### GlobalConstants 上の関連定数

| 定数 | 値 | カテゴリ | 説明 |
|---|---|---|---|
| `TURN_DELAY` | 0.15 秒 | Effect | 向き変更ブロック時間（プレイヤー通常移動のみ） |

回転速度系の定数は `TURN_DELAY` 1 つのみ。`ROTATION_SPEED` / `TURN_SPEED` 等は存在しない。

---

## 4. 防御判定との関係

### 4-1. 攻撃方向の判定ロジック

**実装**：[character.gd:846-879](../scripts/character.gd#L846) `_calc_attack_direction(attacker)` → `"front" / "left" / "right" / "back"`

- 防御側の `facing` を基準に、攻撃者の相対位置から `atan2` で角度算出
- ±π/4（±45°）の 4 象限で判定：
  - 正面（front）：±45°
  - 背面（back）：180°±45°
  - 左 / 右側面：それ以外

### 4-2. 防御フィールド × 方向対応表

**実装**：[character.gd:899-925](../scripts/character.gd#L899) `_calc_block_per_class(direction)`

| フィールド | 有効方向 | 保有クラス例 |
|---|---|---|
| `block_right_front` | 正面・右側面 | 剣士・斧戦士・斥候・ハーピー |
| `block_left_front` | 正面・左側面 | 剣士・斧戦士・ハーピー |
| `block_front` | 正面のみ | 弓使い・魔法使い・ヒーラー・ゾンビ・ウルフ |

- 各フィールドは独立に `defense_accuracy / 100.0` の確率でロール
- 成功すれば値合計、失敗 0
- 背面攻撃は**全フィールドスキップ**（直前の if 分岐 [character.gd:795](../scripts/character.gd#L795)）

### 4-3. ガード中正面攻撃の特例

**実装**：[character.gd:884-891](../scripts/character.gd#L884) `_calc_block_power_front_guard`

```gdscript
func _calc_block_power_front_guard() -> int:
    var brf := cd.block_right_front + cd.get_weapon_block_right_bonus()
    var blf := cd.block_left_front  + cd.get_shield_block_left_bonus()
    var bf  := cd.block_front       + cd.get_weapon_block_front_bonus()
    return brf + blf + bf  # 確率判定なし、3 フィールド合計を全カット
```

- 正面攻撃時のみガードが効く（左右側面・背面は通常の防御判定）
- 確率ロールなし（100% 成功）＋ 3 フィールド全合計

### 4-4. 敵の向き変更速度と背後取り成立条件

**現状**：
- 敵 AI は `move_to` 経由で**移動する瞬間に facing を即時更新**
- 敵が静止して攻撃中・PRE_DELAY/POST_DELAY 中は facing が変わらない
- 攻撃前に SkillExecutor の `face_toward(target)` で**ターゲット方向に即時回転**

**背後取りが成立する条件**：
1. 敵が静止または別方向移動中に、自分が敵の背後に回り込む
2. 敵が攻撃モーション中（PRE_DELAY/POST_DELAY）はターゲット方向を向き続けるので、別敵が背後を取れる
3. 敵が他キャラに `face_toward` した直後の窓では、新たな攻撃者の背後取りが成立し得る

**プレイヤー側の TURN_DELAY との比較**：
- プレイヤー：通常移動の向き変更で 0.15 秒の遅延 → 敵から見て「向きが古い」窓ができる → 敵が背後取りしやすい
- AI 同士：向き変更が即時なので背後取りが起きにくい（移動するだけで自動で正面が更新される）

→ **プレイヤーが敵の背後を取る方が、敵がプレイヤーの背後を取るより難しい構造**になっている可能性あり

### 4-5. 古い実装の残骸：`get_direction_multiplier`

**実装**：[character.gd:1268-1278](../scripts/character.gd#L1268)

```gdscript
## 攻撃者から対象を攻撃したときの方向ダメージ倍率を返す
## 正面：1.0倍 / 側面：1.5倍 / 背面：2.0倍
static func get_direction_multiplier(attacker, target) -> float:
    ...
```

- CLAUDE.md では「ダメージの方向倍率（旧 1.0/1.5/2.0 倍）は廃止」と明記
- **コード上どこからも呼ばれていない**（`Grep` で確認済み）→ 完全に dead code
- **削除候補**

---

## 5. 現状の「非対称性」の洗い出し

### プレイヤー vs AI

| 場面 | プレイヤー | AI（味方/敵） | 非対称性 |
|---|---|---|---|
| 通常移動の向き変更 | TURN_DELAY (0.15s) ブロック | 即時（move 内で同時更新） | **大** |
| 攻撃中の向き変更 | 即時（face_toward） | 即時（attacker.face_toward in SkillExecutor） | なし |
| 攻撃実行時のターゲット方向回転 | 即時 | 即時 | なし |
| ガード | あり（X/B ホールドで向き固定） | なし（AI はガードしない） | **大** |

### 味方 vs 敵
- プレイヤー操作キャラ以外（味方 NPC・敵）は全て UnitAI 経由 → **完全対称**

### クラス / 種族
- 全クラス・全種族で `move_speed` ステータスは異なるが、向き変更コスト（TURN_DELAY）は**全プレイヤーキャラ共通の固定値**
- AI 側はクラス差・種族差なく即時

### Player ↔ AI の論理 facing 同期タイミング差

| 主体 | move_to 呼出時の facing | move_to 完了時 |
|---|---|---|
| プレイヤー（TURN_DELAY 経由） | **0.15s 後に complete_turn で確定** | TURN_DELAY 完了後、改めて move_to 実行 |
| プレイヤー（同方向 / ガード中） | move_to 内で即時更新 | tween 完了後 visual のみ |
| AI | move_to 内で即時更新 | tween 完了後 visual のみ |

→ プレイヤーは TURN_DELAY 中の 0.15 秒間、**論理 facing が古い値のまま**。この間に攻撃を受けた場合、防御判定は古い向きで行われる（背後取りされやすい窓）。

---

## 6. 設計上の問題点・指摘事項

### 6-1. プレイヤー TURN_DELAY 中の論理 facing 不一致
- TURN_DELAY 中は `_turn_target_facing` には目標値が入るが、`facing` は古いまま
- この間に攻撃を受けると、視覚（回転中）と防御判定（旧向き）が一致しない
- **意図的か事故か不明**（spec / history.md に明示記述なし）

### 6-2. ガード中の向き固定の実装が「コメントベース」
- `guard_facing` 変数は存在せず、単に `move_to` で `if not is_guarding` 分岐
- コメント「guard_facing を維持」は変数を実装したかったが断念した名残の可能性
- 「ガード解除 → 1 タイル移動して向き変更 → 再ガード」のサイクルが瞬時に可能（X/B ホールドの ON/OFF にコストなし）

### 6-3. SkillExecutor の `face_toward` がプレイヤーで重複
- プレイヤーは PRE_DELAY/TARGETING で既にターゲット方向に回転済みのケースが多い
- それでも SkillExecutor 側で `face_toward(target.grid_pos)` が呼ばれる（冪等なので副作用なし）
- 設計ミスではないが、責務の分割が曖昧（「方向決定はどこで行うか」が両所に分散）

### 6-4. 自己対象 heal/buff の `face_toward(self.grid_pos)` 挙動
- delta が ZERO の場合、`face_toward` は `if abs(0) >= abs(0)` → true 分岐 → `delta.x > 0`（false）→ LEFT に向く
- 自己回復で **意図せず LEFT を向く可能性**あり（要動作確認）
- 実害はないがバグの温床

### 6-5. AI の向き変更が無コストな結果
- AI は移動のたびに即時で正面更新 → プレイヤーが敵の背後を取りにくい
- TURN_DELAY 廃止 or AI にも同等のターン遅延を入れる、のいずれかで対称性を取れる
- 現状は「プレイヤー不利」の非対称性

### 6-6. 古い `get_direction_multiplier` が dead code として残存
- CLAUDE.md で「廃止」明記済みだがコード未削除
- [character.gd:1268-1278](../scripts/character.gd#L1268)

### 6-7. 回転速度系の定数が `TURN_DELAY` 1 つのみ
- AI 用の `AI_TURN_DELAY` や攻撃中用の `ATTACK_TURN_DELAY` などは存在しない
- 新仕様で複数の文脈別コストを導入する場合、まず定数体系の設計が必要

---

## 7. 統一設計の選択肢（参考）

調査結果を踏まえた、向き変更コスト統一案の方向性：

### 案 A: TURN_DELAY 廃止
- プレイヤーの通常移動も AI と同じく即時向き変更
- 利点：完全対称、操作レスポンス向上
- 欠点：「振り向きの溜め」がなくなり、近接戦闘の駆け引きが減る

### 案 B: AI にも対応する遅延を実装
- AI の向き変更に同じ TURN_DELAY を適用（攻撃前 face_toward / 移動時 move_to の冒頭で待機）
- 利点：完全対称、背後取りのチャンスが対等
- 欠点：実装コスト大（UnitAI のキュー設計に手を入れる必要）、AI 全体のテンポ低下

### 案 C: コンテキスト別に細分化
- 通常移動：プレイヤーのみ TURN_DELAY、AI 即時（現状維持）
- 攻撃中の振り向き：プレイヤー / AI ともに即時（現状維持）
- 攻撃実行時の方向転換：プレイヤー / AI ともに即時（現状維持）
- ガード中：プレイヤーのみ向き固定（現状維持）
- 利点：現状維持で実装コスト最小
- 欠点：非対称性は残る

### 案 D: TURN_DELAY のみ「攻撃中以外」に適用
- プレイヤー / AI ともに、通常移動と攻撃ウィンドアップ突入時に TURN_DELAY を消費
- 攻撃中・ターゲット選定中の振り向きは即時
- 利点：論理 facing と視覚 rotation の不一致が起きにくい
- 欠点：AI 実装コストあり

---

## 参照
- [docs/spec.md](spec.md) — 詳細仕様
- [docs/history.md](history.md) — 過去の変更履歴（TURN_DELAY 導入経緯：行 745, 819, 845）
- [CLAUDE.md](../CLAUDE.md) — 装備システム・命中・被ダメージ計算
