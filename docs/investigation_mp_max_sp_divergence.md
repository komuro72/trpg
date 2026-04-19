# 味方クラス JSON の mp / max_sp フィールド調査（2026-04-18）

> CLAUDE.md の記述（廃止済み）と実際のクラス JSON（フィールドが残存）の
> 乖離を調査。コード修正・JSON 編集は伴わない。

## 結論

**パターン (A)**：CLAUDE.md の記述が正しい。クラス JSON の `mp` / `max_sp` は **完全に未使用の legacy フィールド**で、ランタイムは `assets/master/stats/class_stats.json` の `energy` 値から `max_mp` / `max_sp` を算出している。JSON 側にフィールドが残っているだけで、値は読み取られない。

**推奨対応: (X)** — `mp` / `max_sp` フィールドを全クラス JSON から削除（base_defense 廃止と同じ手順）。

---

## 1. フィールドの実態

### 味方 7 クラス JSON の現状

| ファイル | mp | max_sp | クラス種別 |
|---|---:|---:|---|
| `fighter-sword.json`  | ー  | 60 | 物理（SP 使用） |
| `fighter-axe.json`    | ー  | 60 | 物理（SP 使用） |
| `archer.json`         | ー  | 60 | 物理（SP 使用） |
| `scout.json`          | ー  | 60 | 物理（SP 使用） |
| `magician-fire.json`  | 60 | ー | 魔法（MP 使用） |
| `magician-water.json` | 60 | **0** | 魔法（MP 使用・異常値あり） |
| `healer.json`         | 80 | ー | 魔法（MP 使用） |

### 敵固有 5 クラス JSON の現状
`mp` / `max_sp` はどれも存在しない（zombie / wolf / salamander / harpy / dark-lord）。敵固有クラスは元々これらのフィールドを持たなかった可能性が高い。

### なぜ残っているか
- Phase 12-15（2026-03-XX）で「ステータス生成を設定ファイル方式に移行」した際に `vitality` / `energy` ベースへ一本化
- その後のリファクタで class JSON からは **読み取らなくなった**が、物理削除は行わずに留まっている（history.md Phase 12-15 記述も「mp / max_sp フィールドは廃止」と宣言のみ）
- Config Editor が「味方クラス」タブで表示するため、編集ツールから見ると「現役フィールド」のように見えてしまう

---

## 2. コード参照

### `class_json.get(...)` の呼び出し箇所
`scripts/` 配下を全数検索した結果、`class_json.get("mp")` / `class_json.get("max_sp")` の呼び出しは **ゼロ件**。
（`class_json.get` を呼ぶのは `character_generator.gd:122-125, 274-275` と `player_controller.gd:256` のみで、読まれているキーは `is_flying` / `behavior_description` / `attack_type` / `attack_range` / `slots` のみ）

### `CharacterData.load_from_json()` での参照
- [character_data.gd:148-149](scripts/character_data.gd#L148)
  ```gdscript
  data.max_mp = int(d.get("mp", 0))
  data.max_sp = int(d.get("max_sp", 0))
  ```
- **呼び出し元は敵スポーンのみ**：`PartyManager._spawn_enemy_member()`（[party_manager.gd:265](scripts/party_manager.gd#L265)）が `enemies/<enemy>.json` をロードする時に使用。クラス JSON には使われない
- 敵 JSON の `"mp"` / `"max_sp"` 値はロード時に一旦 `data.max_mp` / `data.max_sp` に入るが、直後の `apply_enemy_stats()` で **max_sp は `stats.energy` で、max_mp は 0 で上書き**される（[character_generator.gd:253-254](scripts/character_generator.gd#L253)）ため、最終的には反映されない

→ つまり **敵 JSON の `mp` も味方クラス JSON の `mp/max_sp` も、どちらもランタイムには届かない**。

### ランタイムの max_mp / max_sp 決定経路（味方・NPC）
```
CharacterGenerator.generate(chosen_class)
  ├── _calc_stats(class, rank, sex, age, build)
  │     └── class_stats.json の energy エントリを読む
  │           { "base": 30, "rank": 10 } 等
  └── data.max_mp / data.max_sp を stats.energy で設定
        ├── chosen_class ∈ MAGIC_CLASS_IDS（magician-fire/water, healer）
        │     → data.max_mp = stats.energy, data.max_sp = 0
        └── それ以外
              → data.max_mp = 0,           data.max_sp = stats.energy
```

クラス JSON は **一切登場しない**経路。

### Character.max_mp / Character.max_sp への代入
```
Character._init_stats() ([character.gd:266, 268])
  max_mp = character_data.max_mp
  max_sp = character_data.max_sp
  mp = max_mp
  sp = max_sp
```
`character_data` の値は上記 generate 経由で計算された値のみ。

---

## 3. energy ベースの代替経路（詳細）

### `assets/master/stats/class_stats.json` の energy
全 7 クラスが `"energy": { "base": 30, "rank": 10 }` と統一された値を持つ。意図的に共通化されている。

### `_calc_stats()` の計算式（[character_generator.gd:471-493](scripts/character_generator.gd#L471)）
```
raw = base + rank × RANK_VALUE[rank]
    + sex_bonus + age_bonus + build_bonus
    + randi() % (rand_max + 1)
value = max(0, round(raw))
```

- rank C (= 0) → base 30
- rank B (= 1) → 40
- rank A (= 2) → 50

属性補正と乱数で ±10 程度ずれる。つまり実際の `max_mp` / `max_sp` は **およそ 25〜60** の範囲に収まる。

### クラス JSON の mp / max_sp 値との比較
- クラス JSON: `mp = 60 / 60 / 80`, `max_sp = 60 / 60 / 60 / 60`
- energy 計算結果: rank A で約 40〜55, rank C で約 25〜40

→ **値域からして既に一致していない**（クラス JSON の値のほうが大きい）。仮にクラス JSON が使われていたらゲーム挙動が変わるレベルで乖離している。

### 優先度
`character_generator.gd:103-110` の分岐が `data.max_mp` / `data.max_sp` に値を直接代入している（クラス JSON の値は上書き候補にすら入らない）。よって **energy が唯一の入力源**。

---

## 4. 乖離パターンの判定

**(A) 該当**：CLAUDE.md の記述通り、クラス JSON の mp/max_sp は完全未使用。実際は energy から計算されている。

- (B) ではない：クラス JSON の mp/max_sp はどこからも読まれていない
- (C) ではない：条件分岐で使い分けるロジックも存在しない
- (D) ではない：単純な「フィールドの物理削除忘れ」

---

## 5. magician-water の `max_sp = 0` の意味

### 経緯の推測
- magician-water は Phase 12-2（水魔導士クラス追加時）に magician-fire のクラス JSON を **コピー＋編集**して作成されたと推測される
- magician-fire に `max_sp` は無かった → コピー時に `max_sp: 0` を明示的に追加した形跡。あるいは Config Editor の JSON 保存時に全フィールド書き出しで 0 が入った可能性
- いずれにせよ **削除忘れ**で、意味論的には `max_sp: 0` ≒ `max_sp` フィールドなし（どちらも「非表示」）

### 現在の動作への影響
- magician-water は MAGIC_CLASS_IDS に含まれる → `data.max_sp = 0` が `generate()` で設定される
- 結果的にクラス JSON の `max_sp: 0` と一致する（偶然の一致）
- しかし **JSON 側で値が読まれていないので、0 でも 1000 でも挙動は同じ**

---

## 6. 推奨対応

### (X) クラス JSON の mp / max_sp を完全削除 — **最推奨**

理由：
1. **コードから一切参照されない**ため削除しても挙動変化なし
2. Config Editor 味方クラスタブで現役フィールドに見えるのが混乱のもと（base_defense と同じ問題）
3. base_defense 廃止で前例が確立している（同じ手順で処理可能）
4. CLAUDE.md 450-452 行の記述が整合する

懸念：敵固有クラス 5 ファイルには元から無いので、削除対象は味方 7 クラスのみで済む。

### (Y) CLAUDE.md の記述を修正 — 非推奨

理由：現状の CLAUDE.md の記述（energy で代替）は**実装として正しい**。「まだ廃止されていない」と書くと嘘になる。JSON 側を合わせる方向が正しい。

### (Z) mp → max_mp にリネーム + magician-water の max_sp = 0 のみ削除 — 非推奨

理由：どちらもランタイムに届かないフィールドなので、リネームしても意味がない。削除 (X) のほうが一貫性がある。

---

## 作業量見積もり（(X) を採用する場合）

### JSON 変更
- `assets/master/classes/magician-fire.json`: `"mp": 60,` を削除
- `assets/master/classes/magician-water.json`: `"mp": 60,` と `"max_sp": 0,` を削除
- `assets/master/classes/healer.json`: `"mp": 80,` を削除
- `assets/master/classes/fighter-sword.json`: `"max_sp": 60,` を削除
- `assets/master/classes/fighter-axe.json`: `"max_sp": 60,` を削除
- `assets/master/classes/archer.json`: `"max_sp": 60,` を削除
- `assets/master/classes/scout.json`: `"max_sp": 60,` を削除

合計 7 ファイル・8 行削除

### コード変更
- `scripts/config_editor.gd:84` の `CLASS_PARAM_GROUPS`「リソース」グループから `"mp"` / `"max_sp"` を削除（残りは `heal_mp_cost` / `buff_mp_cost`）
- `scripts/character_data.gd:148-149` の敵 JSON ロード時の mp/max_sp 読み込みも削除可能だが、**敵 JSON 側の `mp` フィールド（dark_priest / dark_mage / dark_lord / goblin_mage / lich / demon）**も同時に整理するなら含める

### ドキュメント更新
- 特になし（CLAUDE.md は既に廃止宣言済み）
- `docs/history.md` に削除履歴を追記

作業量目安: **S（小）**。base_defense 廃止と同等か、それよりやや簡単（コード変更箇所が少ない）。
