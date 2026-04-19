# ヒーラーのアンデッド特効ダメージ計算 調査（2026-04-18）

> Config Editor「味方クラス」タブで healer の `Z_damage_mult` が空で
> `Z_heal_mult` のみ設定されている件の調査。

## 結論サマリー

- **パターン A**：現行実装は `heal_mult` を「回復量」と「アンデッドへのダメージ」両方に使う設計
- ただし **AI 側（`unit_ai.gd`）と Player 側（`player_controller.gd`）で計算式が異なる致命的な実装不一致がある**
  - Player 側：`power × heal_mult` をダメージ／回復量として使用（設計通り）
  - AI 側：**`heal_mult` を無視して生の `power` を使用**（バグ）
- ダメージ種別は `attack_is_magic=true` として扱われ、被ダメージ側の **magic_resistance** が適用される（「アンデッド特効」は「アンデッドは phys_res は高いが magic_res は低い」という設計で自然に成立している）
- 明示的な特効ボーナス倍率（×2 等）は **なし**

## 推奨対応

**(W) バグ修正 + リネーム検討の2段階**

1. 最優先：`unit_ai.gd:526-547` の `heal` 分岐で `heal_mult` を適用するようバグ修正（Player 側と計算式を揃える）
2. 次に **(Y)** `Z_heal_mult` を `Z_effect_mult` にリネーム、または **(X)** 現状維持しドキュメントで「Z_heal_mult はアンデッドへのダメージ倍率も兼ねる」と明記

---

## 1. 回復量の計算式

### Player 側（ヒーラー操作）— [player_controller.gd:1049-1054](scripts/player_controller.gd#L1049)
```gdscript
func _execute_heal(target: Character, slot_data: Dictionary) -> void:
    var cost := _slot_cost(slot_data)
    if cost > 0:
        character.use_energy(cost)
    var heal_mult  := float(slot_data.get("heal_mult", 0.3))
    var heal_amount := maxi(1, int(float(character.power) * heal_mult))
    ...
```

**計算式**：`heal_amount = max(1, int(power × slot.heal_mult))`

### AI 側（CPU ヒーラー・敵 dark_priest）— [unit_ai.gd:520-547](scripts/unit_ai.gd#L520)
```gdscript
"heal":
    ...
    # 通常回復
    if _member.use_energy(cost):
        var power := _member.character_data.power if _member.character_data else 0
        var hp_before := tgt.hp
        tgt.heal(power)  # heal() 内で HEAL SE 再生
```

**計算式**：`heal_amount = power`（**heal_mult 非参照**）

### 不一致の影響
- Player ヒーラー（power 50・heal_mult 0.3）：回復量 = **15**
- AI ヒーラー（power 50）：回復量 = **50**
- AI 版は Player 版の **3.3 倍**回復する

## 2. アンデッド特効ダメージの計算式

### Player 側 — [player_controller.gd:1059-1065](scripts/player_controller.gd#L1059)
```gdscript
# アンデッド特効：回復量をダメージとして適用
if not target.is_friendly and target.character_data != null and target.character_data.is_undead:
    target.take_damage(heal_amount, 1.0, character, true)  # attack_is_magic=true
```
→ `take_damage(power × heal_mult, 1.0, ..., attack_is_magic=true)`

### AI 側 — [unit_ai.gd:530-538](scripts/unit_ai.gd#L530)
```gdscript
# アンデッド特効：回復量をダメージとして適用
if tgt.character_data != null and tgt.character_data.is_undead \
        and tgt.is_friendly != _member.is_friendly:
    if _member.use_energy(cost):
        var power := _member.character_data.power if _member.character_data else 0
        tgt.take_damage(power, 1.0, _member, true)  # ★ heal_mult なし
```
→ `take_damage(power, 1.0, ..., attack_is_magic=true)` — **heal_mult 未適用**

### 共通ポイント
- `ATTACK_TYPE_MULT`（他の近接/遠距離/魔法攻撃に適用される `0.2〜0.3` の係数）は **適用されない**（heal 経路は別系統）
- `take_damage` の `attack_is_magic=true` により **magic_resistance** が適用される
- 明示的な特効ボーナス（×2 等）は **なし**
- メッセージ表示だけ「アンデッド特効」の演出がある（[character.gd:1025-1032](scripts/character.gd#L1025) の `atk_data.attack_type == "heal" and def_data.is_undead` 分岐）

## 3. 実ダメージ量シミュレーション

### 前提
- **skeleton**（stat_type=fighter-sword, rank B, stat_bonus: physical_resistance +30）
  - physical_resistance: 35(base) + 10(rank) + 30(bonus) = **75** → 軽減率 `75/175 = 42.9%`
  - magic_resistance: 20(base) + 0 + 0 = **20** → 軽減率 `20/120 = 16.7%`
- **healer**（rank A）・**fighter-sword**（rank A）：`power = 50`
- 防御判定失敗（`blocked = 0`）を前提
- 通常のダメージ：`power × ATTACK_TYPE_MULT × damage_mult`

### ケース比較（skeleton への攻撃）

| 攻撃者 | 経路 | 計算式 | ベースダメージ | 耐性 | 最終ダメージ |
|---|---|---|---:|---|---:|
| **Player ヒーラー** Z 回復 | `power × heal_mult` | `50 × 0.3` | 15 | magic 16.7% | **12** |
| **AI ヒーラー** Z 回復 | `power`（heal_mult なし） | `50` | 50 | magic 16.7% | **41** |
| **Player ヒーラー** X 回復（大） | `power × heal_mult` | `50 × 0.6` | 30 | magic 16.7% | **24** |
| **Fighter-sword** 斬撃 | `power × 0.3(melee) × 1.0` | `50 × 0.3` | 15 | physical 42.9% | **8** |

### 解釈
- **Player ヒーラー Z > 剣士 Z**（12 vs 8）→ 特効として機能している
- **AI ヒーラー Z は Player ヒーラー Z の 3〜4 倍**（41 vs 12）→ 仕様ではなくバグ
- 「特効」の本質は「被弾側が phys_res 高・magic_res 低」の構造から生まれる差（特効ボーナス倍率ではない）

## 4. 設計パターンの判定

| パターン | 説明 | 該当性 |
|---|---|---|
| **A** Z_heal_mult 兼用（回復・ダメージ同じ倍率） | heal_mult × power が両方の base | ✅ **Player 側のみ**該当 |
| **B** Z_damage_mult を別に持つべき（未実装） | ダメージ用の別倍率が必要 | ❌（現状は heal_mult で足りている） |
| **C** 回復量 × 特効ボーナス | heal_amount × 2 等 | ❌ ボーナスなし |
| **D** 回復量の整数値をダメージとして渡す | heal_amount をそのまま take_damage に | ✅ **Player 側**はこれ（heal_amount = power × heal_mult） |

**結論：A + D のハイブリッド（Player 側のみ正しく実装、AI 側は heal_mult 漏れ）**

Config Editor で `Z_damage_mult` が空欄なのは、**heal タイプのスロットでは `damage_mult` を使わず `heal_mult` が兼用する**という設計の反映。設計としては妥当。

## 5. 推奨対応

### 5-1. 最優先：AI 側の heal_mult 適用漏れを修正（バグ修正）

現状の [unit_ai.gd:520-547](scripts/unit_ai.gd#L520) は slot 定義を読まずに生の `power` を使っている。Player 側と同じく `slots.Z.heal_mult` を参照して計算すべき。

修正イメージ：
```gdscript
# character_data に heal_mult を保持するか、または slot 定義から直接読む
var heal_mult := _get_z_heal_mult()  # 新設ヘルパー
var heal_amount := maxi(1, int(float(_member.character_data.power) * heal_mult))
...
tgt.take_damage(heal_amount, 1.0, _member, true)
...
tgt.heal(heal_amount)
```

必要な下準備：
- `CharacterData` に `z_heal_mult: float` フィールドを追加
- `CharacterGenerator._build_data` / `apply_enemy_stats` で `slots.Z.heal_mult` をロード

この修正は「ヒーラーが敵 dark_priest にも等しく適用される」ことを意味し、**敵ヒーラーの回復力が激減する（power 50 → heal 15）**。バランス調整が必要になる可能性がある。

### 5-2. 次善：用語のリネーム検討（バランス調整後）

#### (X) 現状維持 + ドキュメント補強
- 現在の `Z_heal_mult` のまま
- CLAUDE.md に「ヒーラーの `heal_mult` はアンデッドへのダメージ倍率も兼ねる」と明記
- メリット：変更不要
- デメリット：名前からアンデッド用であることが分からない

#### (Y) `Z_heal_mult` → `Z_effect_mult` にリネーム（兼用を明示）
- 意味：回復・ダメージ両用の効果倍率
- メリット：意図が明確
- デメリット：JSON・コード・Config Editor すべて変更、既存セーブデータに影響なし（マスターのみ）

#### (Z) アンデッドダメージ用の別倍率を追加
- 例：`Z_undead_damage_mult: 1.0` を新設し、`heal_amount × undead_damage_mult` でダメージ計算
- メリット：バランス調整の自由度が高まる（「ヒーラーは回復量 ×1.5 のダメージをアンデッドに与える」等）
- デメリット：現状は「回復量と等しいダメージ」で自然に機能しているので、過剰設計になる可能性

**推奨順序**: バグ修正（5-1）→ 動作確認 → バランス再評価 → (X) か (Y) を選択

---

## 付録：関連コードへのリンク

| 処理 | 場所 |
|---|---|
| Player 回復実行 | [player_controller.gd:1049](scripts/player_controller.gd#L1049) `_execute_heal` |
| AI 回復実行 | [unit_ai.gd:520](scripts/unit_ai.gd#L520) `"heal":` 分岐 |
| AI 回復キュー生成 | [unit_ai.gd:1910](scripts/unit_ai.gd#L1910) `_generate_heal_queue` |
| take_damage 本体 | [character.gd:780](scripts/character.gd#L780) |
| アンデッド特効メッセージ分岐 | [character.gd:1025](scripts/character.gd#L1025) |
| 耐性逓減変換 | [character_data.gd:326](scripts/character_data.gd#L326) `resistance_to_ratio` |
| healer.json slot 定義 | [assets/master/classes/healer.json](assets/master/classes/healer.json) |
