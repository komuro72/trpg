# base_defense フィールド使用状況調査（2026-04-18）

> Config Editor 味方クラスタブに表示される `base_defense` の実態と、
> 削除可否を判断するための調査。コード修正・JSON 編集は伴わない。

## 結論

**`base_defense` は使用中**。「使われていない疑い」は誤り。削除すると挙動が変わる（味方・NPC の被ダメージが増える）。

- **経路**：`class_json["base_defense"]` → `CharacterData.defense` → `Character.defense` → `take_damage()` 内で「ベースダメージから引かれる平ダメージカット値」として消費
- **対象**：プレイヤー・NPC（CharacterGenerator 経由で生成される味方系のみ）
- **未対象**：敵 16 種（`apply_enemy_stats` は `data.defense` を上書きしない。個別敵 JSON の `defense` フィールドがそのまま使われる）
- **UI 表示なし**：OrderWindow のステータス表示にも、CLAUDE.md のキャラクターステータス表にも `defense` は載っていない。**実装と仕様書が食い違っている**

---

## 1. 定義箇所

全 12 ファイルに `base_defense` が存在：

| ファイル | 値 | 分類 |
|---|---:|---|
| `classes/fighter-sword.json`  | 5 | 味方 |
| `classes/fighter-axe.json`    | 4 | 味方 |
| `classes/healer.json`         | 4 | 味方 |
| `classes/scout.json`          | 3 | 味方 |
| `classes/archer.json`         | 3 | 味方 |
| `classes/magician-fire.json`  | 2 | 味方 |
| `classes/magician-water.json` | 2 | 味方 |
| `classes/zombie.json`         | 2 | 敵固有 |
| `classes/wolf.json`           | 2 | 敵固有 |
| `classes/salamander.json`     | 2 | 敵固有 |
| `classes/harpy.json`          | 1 | 敵固有 |
| `classes/dark-lord.json`      | 8 | 敵固有 |

値は 1〜8 の範囲。戦士系が高く、魔法系が低い。

---

## 2. コード参照箇所

`base_defense` という文字列を含む GDScript 参照は **1 箇所のみ**：

- [scripts/character_generator.gd:113](scripts/character_generator.gd#L113)
  ```gdscript
  data.defense = int(class_json.get("base_defense", 3))
  ```

呼び出し元：`CharacterGenerator.generate()`（**味方系キャラクター生成のみ**で呼ばれる）

### `data.defense` の下流フロー

1. `CharacterGenerator.generate()` で `CharacterData.defense` が設定される
2. `Character._read_character_data()`（[character.gd:272](scripts/character.gd#L272)）で `Character.defense` にコピー
   ```gdscript
   defense = character_data.defense
   ```
3. `Character.get_effective_defense()`（[character.gd:793-796](scripts/character.gd#L793)）がバフ込みの値を返す
   ```gdscript
   func get_effective_defense() -> int:
       if defense_buff_timer > 0.0:
           return defense + DEFENSE_BUFF_BONUS  # バフ中は +3
       return defense
   ```
4. `Character.take_damage()`（[character.gd:838](scripts/character.gd#L838)）でダメージからカット
   ```gdscript
   var after_block: int = maxi(0, raw_after_mult - get_effective_defense() - blocked)
   ```
   `raw_after_mult` = `ベースダメージ × クリティカル倍率`。そこから `defense`（+バフ+3）と防御強度 `blocked` を両方引く。

### 敵側の挙動
- `apply_enemy_stats()`（[character_generator.gd:235-294](scripts/character_generator.gd#L235)）は `data.power` / `data.skill` / `data.physical_resistance` / `data.magic_resistance` / `data.defense_accuracy` / `data.block_*` を上書きするが **`data.defense` には触れない**
- 敵の `data.defense` 値は `CharacterData.load_from_json()`（[character_data.gd:161](scripts/character_data.gd#L161)）が **個別敵 JSON の `"defense"` フィールド**から読んだ値のまま残る
- 個別敵 JSON（16 ファイル全て）には `"defense"` フィールドが存在（ゴブリン 2 / ダークロード 8 等）
- **つまり敵は `classes/*.json` の `base_defense` を使わず、個別敵 JSON の `defense` を使っている**
- 敵固有クラス JSON（zombie / wolf / salamander / harpy / dark-lord）の `base_defense` は **完全に未使用のデッドデータ**

---

## 3. 類似フィールドとの関係

`CharacterData` のダメージ減衰系フィールド：

| フィールド | 説明 | 装備補正 | UI 表示 | CLAUDE.md 記載 |
|---|---|---|---|---|
| `defense` | **平ダメージカット値**（本調査対象） | なし | **なし** | **なし（未記載）** |
| `defense_accuracy` | 防御判定の成功率（0〜100） | なし | あり | あり（防御技量） |
| `block_front` / `block_left_front` / `block_right_front` | 防御成功時のカット値（方向別） | あり（武器・盾） | あり | あり（防御強度） |
| `physical_resistance` | 物理ダメージ逓減率の基礎値 | あり（防具） | あり | あり（物理攻撃耐性） |
| `magic_resistance` | 魔法ダメージ逓減率の基礎値 | あり（防具） | あり | あり（魔法攻撃耐性） |

### ダメージ計算フロー（[character.gd:799-848](scripts/character.gd#L799) から抜粋）
```
1. raw_amount × multiplier = raw_after_mult（クリティカル倍率込み）
2. 防御判定（方向別 block_*）→ blocked（成功時のみ値あり）
3. after_block = raw_after_mult - get_effective_defense() - blocked  ← ★ ここで defense が効く
4. 耐性適用: after_resist = after_block × (1 - resistance_rate)
5. 最終ダメージ確定（最低1）
```

### 仕様上の位置づけ
- CLAUDE.md「命中・被ダメージ計算」セクション（854 行付近）では、ダメージ計算フローに `defense`（平カット）が **一切登場しない**
- 仕様上は「防御強度 → 耐性」の 2 段階軽減だが、実装では「平カット → 防御強度 → 耐性」の 3 段階になっている
- `defense` は Phase 2 から残る legacy 仕様と推測される（当時は単一 defense だった → 後に防御強度・耐性が追加されたが `defense` も残された）

---

## 4. 削除した場合の影響

### 4-1. 単純削除は **不可**
- 味方・NPC の平ダメージカット（クラス依存 2〜5 ポイント）が消失
- 戦士系（fighter-sword = 5）が最も影響大
- 攻撃頻度・ダメージ規模次第で HP がもたない場合がある
- ゲームバランスの再調整が必要

### 4-2. JSON スキーマ検証
- JSON に対する schema 検証は実装されていない（コード検索で `schema` / `validate` の JSON 関連実装なし）
- `class_json.get("base_defense", 3)` のデフォルト値が 3 なので、フィールドがなくても起動自体はする
- Config Editor の `_coerce_class_value` は「元 JSON にあるキーだけ型合わせ」ロジックなので、フィールド削除も自動許容される

### 4-3. Config Editor の扱い
- [config_editor.gd:84](scripts/config_editor.gd#L84) の `CLASS_PARAM_GROUPS` で `"リソース"` グループに登録：
  ```gdscript
  "params": ["base_defense", "mp", "max_sp", "heal_mp_cost", "buff_mp_cost"],
  ```
- 単なる表示グループ分けで、特別扱いはない
- JSON からフィールドを削除すれば Config Editor 上でも「—」表示になる（`all_params.has(p)` チェックがあるため行自体が描画されない可能性あり）

### 4-4. 推奨する 3 択

#### (A) 正式ステータスとして昇格
- `CharacterData.defense` を CLAUDE.md のステータス表に追記（例：「基本防御」）
- OrderWindow で表示する
- 装備補正の対象にするかどうか検討（現在は素値のみ）
- 敵側も `apply_enemy_stats` から `base_defense` を読むように揃える

#### (B) 廃止して他フィールドに統合
- 物理/魔法耐性の基礎値に吸収（`physical_resistance` / `magic_resistance` に +X 加算）
- 防御強度（`block_front`）に加算
- いずれもバランス調整が必要
- 敵 16 個の個別 JSON の `defense` フィールドも同時削除

#### (C) 現状維持（ドキュメント補完のみ）
- `defense` を CLAUDE.md のステータス表とダメージ計算フローに明記
- 「UI 非表示の平カット値」として意図的な設計として記録
- コードは一切触らない
- 敵クラス JSON の `base_defense` は実際には未使用なので「敵クラス JSON では未使用（個別敵 JSON の `defense` が使われる）」と注記

### 4-5. 最小改修提案
もし「Config Editor 上で味方クラス全員 `base_defense=0` にしてゲーム確認→問題なし」なら (B) 系の廃止が通る。確認せず削除は非推奨。

---

## 補足：データフローサマリ

### 味方・NPC
```
classes/<class>.json
  └── base_defense (5 / 4 / 3 / 2 / 4 / 3 / 2)
       └── CharacterGenerator.generate() → CharacterData.defense
            └── Character._read_character_data() → Character.defense
                 └── take_damage() で平カット
```

### 敵
```
enemies/<enemy>.json
  └── defense (1〜8)
       └── CharacterData.load_from_json() → CharacterData.defense
            └── apply_enemy_stats() は上書きしない（素通り）
                 └── Character._read_character_data() → Character.defense
                      └── take_damage() で平カット

classes/<zombie|wolf|...>.json
  └── base_defense  ← 読み込まれず死んでいる
```
