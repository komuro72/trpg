# 調査：ダメージ計算ログの「スキル N.NN」表示の正体

調査日：2026-04-22
対象ログ例：`ゴブリンアーチャー → レグルス：ベースダメージ 8（威力 47 × 遠距離 0.2 × スキル 0.89）`

## 結論（先出し）

- 「スキル 0.89」は `damage_mult` を**逆算して表示**している値で、`damage_mult` そのもの（0.9）ではない
- ログラベル「スキル」は誤解を招く命名。実体は `damage_mult`（スロット JSON で定義されるダメージ倍率）
- 期待値 0.9 が 0.89 と表示されるのは、int 切り捨てが 2 箇所で発生する計算手順により逆算値にズレが生じているため
- spec.md の記述（`power × type_mult × damage_mult`）と実装の計算式は**一致**している。乖離はログ表示側のみ

## 1. ログ出力箇所の特定

### 該当関数
[scripts/character.gd:1177](scripts/character.gd:1177) の `_log_damage()` で戦闘計算ログを組み立てている。「威力」「遠距離」「スキル」のラベルは全てここが出所。

### 該当コード引用（`character.gd:1189-1212`）

```gdscript
# ベースダメージの算出内訳（威力 × 攻撃タイプ倍率 [× スキル倍率]）
var calc_detail := ""
if attacker != null and attacker.character_data != null:
    var atype: String = attacker.character_data.attack_type
    var t_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get(atype, 1.0) as float
    var type_jp: Dictionary = {
        "melee": "近接", "ranged": "遠距離", "dive": "降下", "magic": "魔法"
    }
    var type_label: String = type_jp.get(atype, atype) as String
    var type_base := int(float(attacker.power) * t_mult)
    if type_base == raw:
        # damage_mult が実質 1.0（スキル倍率なし）
        calc_detail = "（威力%d × %s×%.1f）" % [attacker.power, type_label, t_mult]
    else:
        # damage_mult != 1.0（スキル倍率あり。int 切り捨て誤差が出ることがある）
        var inferred_dmg_mult := float(raw) / float(type_base) if type_base > 0 else 1.0
        calc_detail = "（威力%d × %s×%.1f × スキル×%.2f）" % \
                [attacker.power, type_label, t_mult, inferred_dmg_mult]

var dmg_label: String
if is_critical:
    dmg_label = "ベースダメージ%d%s [クリティカル!×2]→%d" % [base_dmg, calc_detail, after_crit]
else:
    dmg_label = "ベースダメージ%d%s" % [base_dmg, calc_detail]
```

コメント「`damage_mult != 1.0（スキル倍率あり。int 切り捨て誤差が出ることがある）`」が実装者自身の認識を明示しており、表示値が正確な `damage_mult` ではなく逆算値であることは意図的。ラベル文字列が `スキル×%.2f` になっているのは単純な命名ミスと見られる（damage_mult は「スキル倍率」とコメントでも呼ばれているが、Character の `skill` ステータスとは別概念）。

## 2. 計算式の特定

### 「スキル」ラベルに渡される変数

`inferred_dmg_mult := float(raw) / float(type_base)`（[character.gd:1204](scripts/character.gd:1204)）

- `raw`：`_log_damage()` の引数として受け取るベースダメージ。呼出元は `take_damage()`（[character.gd:878](scripts/character.gd:878)）で、その `raw_amount` は攻撃側が `int(power × damage_mult × type_mult)` として計算して渡す値
- `type_base`：`int(attacker.power × t_mult)`（ログ組み立て時に再計算する「威力 × 攻撃タイプ倍率」の int 切り捨て値）

### raw の発生源（SkillExecutor）

[scripts/skill_executor.gd:105-107](scripts/skill_executor.gd:105)（`execute_ranged`）：

```gdscript
var dmg_mult: float = float(slot.get("damage_mult", 1.0))
var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
var raw_damage := int(float(attacker.power) * dmg_mult * type_mult)
```

同様に `execute_melee`（[skill_executor.gd:77-79](scripts/skill_executor.gd:77)）、`execute_flame_circle`（[skill_executor.gd:158-160](scripts/skill_executor.gd:158)）も `int(power × dmg_mult × type_mult)` で raw を計算。この raw が `target.take_damage(raw_damage, ...)` を経由して `_log_damage()` の `raw` 引数になる。

### 数値検証（ゴブリンアーチャー、power=47, ranged, damage_mult=0.9 のケース）

| ステップ | 式 | 結果 |
|---|---|---|
| 攻撃側：raw 計算 | `int(47.0 × 0.9 × 0.2)` = `int(8.46)` | **8** |
| ログ側：type_base 計算 | `int(47.0 × 0.2)` = `int(9.4)` | **9** |
| ログ側：inferred_dmg_mult | `8 / 9` = `0.8888...` | `%.2f` で **0.89** |

2 段階の int 切り捨て（raw 側で `8.46→8`、type_base 側で `9.4→9`）が合わないため、逆算値が真値 0.9 から 0.89 にズレる。つまり **「スキル 0.89」は damage_mult 0.9 を int 誤差込みで逆算した結果**で、実際の damage_mult は 0.9 のまま。

## 3. damage_mult の値確認

### archer クラスの Z スロット

[assets/master/classes/archer.json:14](assets/master/classes/archer.json:14)：

```json
"Z": {
  "name": "速射",
  "action": "ranged",
  "type": "physical",
  "range": 5,
  "damage_mult": 0.9,
  ...
}
```

goblin-archer は `enemy_list.json` で `stat_type: "archer"` のため、このクラス JSON の `damage_mult = 0.9` をそのまま参照する。期待値どおり。

### damage_mult が動的変動する箇所

`damage_mult` の代入・上書きを全ファイルで確認した範囲では、**ランタイムでの動的変更は見当たらない**。常にスロット JSON 由来の固定値を `float(slot.get("damage_mult", 1.0))` で読み取って使用している。ItemGenerator も damage_mult を扱っていない（`power` 等のステータスのみを装備補正する）。

ただし全件 grep ではなく SkillExecutor 内の参照確認にとどめた調査であるため、UnitAI / PlayerController 側で独自に計算する特殊経路（dark-lord のワープ・炎陣など、SkillExecutor を経由しないキュー外処理）の存在可能性は残る。もし必要であれば追加調査を行う。

## 4. spec.md との整合性

### spec.md の記述

- [docs/spec.md:2813](docs/spec.md:2813)：`ベースダメージ = power × type_mult × damage_mult`
- [docs/spec.md:3363-3380](docs/spec.md:3363)：被ダメージ計算フローは「1. 着弾判定 → 2. 防御判定 → 3. 耐性適用 → 4. 最終ダメージ」で、ベースダメージの中に「スキル」という概念は登場しない
- CLAUDE.md の「命中・被ダメージ計算」節（`ベースダメージ = power × type_mult × damage_mult`）も同じ記述

### 実装（SkillExecutor）

`int(power × damage_mult × type_mult)` — spec.md と**式としては一致**（乗算順序は float の結合則で等価、最後に int 切り捨て）。

### 乖離

- **計算式そのもの**は spec.md と実装で乖離なし
- **ログの表示ラベル**のみが乖離：spec.md で定義されているのは `damage_mult` だが、ログ上は「スキル」と表示している
- Character の `skill` ステータスはクリティカル率計算に使われる別概念（`CRITICAL_RATE_DIVISOR=300` で割ってクリティカル率を算出。[character.gd:839-843](scripts/character.gd:839) 参照）。`damage_mult` と「skill」の混同はログ表示の命名ミスと思われる

## 補足：なぜ「スキル」と名付けられているか（推測）

実装コメントに「damage_mult = スキル倍率」と書かれている（[character.gd:1200, 1203](scripts/character.gd:1200)）。クラス JSON のスロット名（「速射」「狙い撃ち」「突進斬り」等）が日本語で「スキル」に相当するため、スロットが持つ damage_mult を「スキル倍率」と呼んだ名残と思われる。しかしキャラクターの `skill` ステータス（技量）と用語衝突するため、UI 表示では紛らわしい。

## 推奨される対応（判断は Komuro）

1. **ログラベルのリネーム**：「スキル×%.2f」→「倍率×%.2f」または「damage×%.2f」に変更
2. **逆算表示の廃止**：`damage_mult` を引数で直接受け取り表示すれば int 誤差もなくなる（例：`_log_damage` に `damage_mult` を追加で渡す）
3. **現状維持**：デバッグログなので多少の誤差は許容し、ラベルだけ正しくする（上記 1 が最小コスト）

いずれも挙動には影響しない純粋なログ表示の修正。ダメージ計算式自体は spec.md どおり正しく動作している。
