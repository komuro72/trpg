# 敵クラスステータス（enemy_class_stats）の実装・利用状況調査

## 目的
move_speed 有効化（Step 1-B）の前提として、`enemy_class_stats.json` が設計通りに
ロード・合成・利用されているかを把握する。乖離が move_speed 限定なのか、
他のステータスにも広がっているのかを切り分ける。

## エグゼクティブサマリー

### 一行結論
- **数値ステータス 11 個のうち、move_speed のみ dead。残り 10 個は正常に runtime に反映されている**
- ただし設計上の重要な構造的問題が 4 つある（後述）

### 重要発見（4 点）

1. **`enemy_class_stats.json` は `apply_enemy_stats()` で正しくロードされ、合成式も class_stats と同じ**（base + rank × rank_bonus + 属性補正 + random）
2. **enemy_class_stats を使うのは 5 種だけ**（zombie / wolf / salamander / harpy / dark-lord）。他 11 種は人間の class_stats を流用
3. **`enemy_class_stats.json` は Config Editor で一切編集できない**。「敵クラス」タブはクラス JSON（攻撃定義）を編集するだけ。「ステータス」タブは class_stats / attribute_stats のみ
4. **move_speed は dead**（[`investigation_movement_constants.md`](investigation_movement_constants.md) で既に確認）— Wolf / Zombie のハードコード `× 0.67` / `× 2.0` で上書きされる

---

## 1. enemy_class_stats.json のロード・合成フロー

### 1-1. ロード経路

**入口**：[`character_generator.gd:235`](../scripts/character_generator.gd#L235) `apply_enemy_stats(data)`

呼出順序（[party_manager.gd:281-293](../scripts/party_manager.gd#L281)）:
```
PartyManager._spawn_enemy_member(char_id, pos)
  ├── CharacterData.load_from_json("enemies/{enemy}.json")
  ├── CharacterGenerator.apply_enemy_graphics(data)  # sex/age/build を画像フォルダ名から設定
  └── CharacterGenerator.apply_enemy_stats(data)     # ★ ここでステータス算出
```

**設定ファイルキャッシュ**（[character_generator.gd:422-451](../scripts/character_generator.gd#L422) `_load_stat_configs`）:
```
_class_stats_cache ← class_stats.json     # 7 クラス（fighter-sword 等）
_class_stats_cache ← enemy_class_stats.json （マージ）  # 5 クラス（zombie 等）追加
_attr_stats_cache  ← attribute_stats.json # 性別・年齢・体格・random_max
```

→ **`enemy_class_stats` は `class_stats` と同じ辞書にマージされる**ため、`_calc_stats(stat_type)` が両方のクラス ID を区別なく扱える設計。

### 1-2. 合成式

[`character_generator.gd:476-498`](../scripts/character_generator.gd#L476) `_calc_stats(class_id, rank, sex, age, build)`:

```gdscript
final = class_base + rank × class_rank_bonus
      + sex_bonus + age_bonus + build_bonus
      + randi() % (random_max + 1)
```

**敵専用クラス（zombie / wolf / etc.）にも完全に同じ式が適用される。**
味方（人間）クラスとの合成ロジックの差異は**ない**。

### 1-3. 合成後の格納先

[`character_generator.gd:252-264`](../scripts/character_generator.gd#L252):

| stat キー | 格納先 |
|---|---|
| `vitality` | `data.max_hp` |
| `energy` | `data.max_energy` |
| `power` | `data.power` |
| `skill` | `data.skill` |
| `physical_resistance` | `data.physical_resistance` |
| `magic_resistance` | `data.magic_resistance` |
| `defense_accuracy` | `data.defense_accuracy` |
| `block_right_front` | `data.block_right_front`（min(100, ...)） |
| `block_left_front` | `data.block_left_front`（min(100, ...)） |
| `block_front` | `data.block_front`（min(100, ...)） |
| `move_speed` | `data.move_speed`（`_convert_move_speed()` で秒/タイル変換） |

**stat_bonus 加算**：[character_generator.gd:249-250](../scripts/character_generator.gd#L249) `enemy_list.json` の stat_bonus を `_calc_stats()` 結果に加算（100 でクランプ）してから格納。

---

## 2. 各ステータスの利用状況

| ステータス | 合成 | 格納 | runtime 読取 | 状態 |
|---|---|---|---|---|
| **vitality** | ✅ `_calc_stats` | `data.max_hp` | [character.gd:262](../scripts/character.gd#L262) `max_hp = character_data.max_hp` | ✅ **正常** |
| **energy** | ✅ | `data.max_energy` | [character.gd:264](../scripts/character.gd#L264) `max_energy = character_data.max_energy` | ✅ **正常** |
| **power** | ✅ | `data.power` | [character.gd:266, 277](../scripts/character.gd#L266) `power = character_data.power + weapon_bonus` | ✅ **正常**（敵には装備なしなので weapon_bonus=0） |
| **skill** | ✅ | `data.skill` | [character.gd:267, 278](../scripts/character.gd#L267) `skill = character_data.skill` | ✅ **正常** |
| **defense_accuracy** | ✅ | `data.defense_accuracy` | [character.gd:903](../scripts/character.gd#L903) `cd.defense_accuracy / 100.0` | ✅ **正常** |
| **physical_resistance** | ✅ | `data.physical_resistance` | [character.gd:817](../scripts/character.gd#L817) → [character_data.gd:312](../scripts/character_data.gd#L312) `get_total_physical_resistance()` | ✅ **正常** |
| **magic_resistance** | ✅ | `data.magic_resistance` | [character.gd:815](../scripts/character.gd#L815) → [character_data.gd:317](../scripts/character_data.gd#L317) `get_total_magic_resistance()` | ✅ **正常** |
| **block_right_front** | ✅ | `data.block_right_front` | [character.gd:888, 905, 911](../scripts/character.gd#L888) `cd.block_right_front + weapon_bonus` | ✅ **正常** |
| **block_left_front** | ✅ | `data.block_left_front` | [character.gd:889, 906, 916](../scripts/character.gd#L889) | ✅ **正常** |
| **block_front** | ✅ | `data.block_front` | [character.gd:890, 907, 921](../scripts/character.gd#L890) | ✅ **正常** |
| **move_speed** | ✅ | `data.move_speed` | **読取なし**（grep 結果は config_editor / character_generator のみ） | ❌ **dead**（[`investigation_movement_constants.md`](investigation_movement_constants.md) 参照） |

### 2-1. move_speed の乖離詳細
詳細は [`investigation_movement_constants.md`](investigation_movement_constants.md) 参照。要点のみ：
- `data.move_speed` は格納されるが、実際の移動間隔は `MOVE_INTERVAL` 定数（プレイヤー 0.30s / AI 0.40s）で決まる
- Wolf / Zombie は `_get_move_interval()` を直接オーバーライド（`× 0.67` / `× 2.0`）し、`data.move_speed` を完全無視
- 結果：`enemy_class_stats.json` の `wolf.move_speed=40` / `zombie.move_speed=10` 等の設定値は **算出されてキャッシュに残るが、実挙動には一切反映されない**

---

## 3. 属性補正の適用状況

### 3-1. 敵にも属性補正は適用される
[character_generator.gd:481-483, 495](../scripts/character_generator.gd#L481):

```gdscript
var sex_table:   Dictionary = ((_attr_stats_cache.get("sex",   {}) as Dictionary).get(sex,   {})) ...
var age_table:   ... .get(age,   {}) ...
var build_table: ... .get(build, {}) ...

var raw: float = base_v + rank_b * rv + sex_b + age_b + bld_b + ...
```

`_calc_stats` は味方・敵を区別せず、`sex` / `age` / `build` 引数で `attribute_stats.json` から補正値を取り出す。

### 3-2. 敵の sex / age / build はどこから来るか
[character_generator.gd:207-229](../scripts/character_generator.gd#L207) `apply_enemy_graphics`:
- 敵画像フォルダ名（例：`goblin_male_adult_medium_01`）をパースして `sex` / `age` / `build` を設定
- `apply_enemy_stats` の前に必ず呼ばれるため、`_calc_stats` 呼出時には設定済み

### 3-3. attribute_stats.json は味方・敵共有
- 専用の「敵向け」セクションは**存在しない**
- 同じ `sex` / `age` / `build` キーを味方・敵が共有

### 3-4. 設計上の注意
- 敵の画像フォルダ命名（`{enemy_type}_{sex}_{age}_{build}_{id}`）が**ステータスにも影響する**
- 例：「ホブゴブリン男性壮年筋肉質」と「ホブゴブリン女性老年細身」では power などの数値が変わる
- 画像セットを差し替える際にステータスバランスも動く（仕様としては妥当）

---

## 4. ランダム補正の適用状況

[character_generator.gd:484, 494, 496](../scripts/character_generator.gd#L484):

```gdscript
var rand_table: Dictionary = (_attr_stats_cache.get("random_max", {})) as Dictionary
...
var rand_m: int = int(rand_table.get(stat_key, 0))
var raw: float = ... + float(randi() % (rand_m + 1) if rand_m > 0 else 0)
```

- ✅ **敵にも適用されている**
- `attribute_stats.json` の `random_max` セクションが味方・敵共有
- 同じステータスキーで同じ random_max 値が適用される

---

## 5. Config Editor への反映状況

### 5-1. 「ステータス」トップタブ
[config_editor.gd:1606-1628](../scripts/config_editor.gd#L1606) `_build_top_tab_stats`:

```gdscript
const STATS_CLASS_PATH: String = "res://assets/master/stats/class_stats.json"
const STATS_ATTR_PATH:  String = "res://assets/master/stats/attribute_stats.json"
```

→ **`class_stats.json` と `attribute_stats.json` のみ編集可能**
→ **`enemy_class_stats.json` は完全に未対応**（grep で `enemy_class_stats` の参照ゼロ）

### 5-2. 「敵クラス」トップタブ
[config_editor.gd:514-516](../scripts/config_editor.gd#L514) `_build_top_tab_enemy_class`:

```gdscript
func _build_top_tab_enemy_class(parent: TabContainer) -> void:
    _build_class_tab_common(parent, TOP_TAB_ENEMY_CLASS, ENEMY_CLASS_IDS)
```

→ **`assets/master/classes/{enemy_class_id}.json`** を編集（`attack_type` / `slots.Z` / `slots.V` 等）
→ **数値ステータス（vitality / power / skill / etc.）は対象外**

### 5-3. 「敵一覧」トップタブ
- `enemy_list.json` の rank / stat_type / stat_bonus を編集可能
- `stat_bonus` は OptionButton で 13 ステータスから選択して値を上書き
- ただし**ベース値（class_base / rank_bonus）は編集不可**

### 5-4. **enemy_class_stats.json は Config Editor で編集不可**

#### 編集できない結果
- zombie / wolf / salamander / harpy / dark-lord の **ベースステータス（base / rank）**を変更したい場合、JSON ファイル直編集が必要
- バランス調整時に Config Editor で完結しない
- 「ステータス」タブと同等の UI（クラス × ステータス × {base, rank} の表）を **`enemy_class_stats` 用にも提供すべき**

### 5-5. 表示から漏れているステータス（敵側全般）
- enemy_class_stats.json の全 11 ステータス（vitality / energy / power / skill / defense_accuracy / physical_resistance / magic_resistance / move_speed / block_right_front / block_left_front / block_front）は **どこからも編集できない**
- 唯一の編集経路：`enemy_list.json` の `stat_bonus`（個体補正のみ。ベース値は触れない）

---

## 6. 味方クラス（class_stats.json）との比較

### 6-1. 合成ロジックの差異
**ない**。`_calc_stats(class_id, ...)` は class_id をキーに `_class_stats_cache` を参照するだけ。
味方も敵も同じ関数・同じ式を通る。

### 6-2. 定義キー数の差異
| | 味方 class_stats | 敵 enemy_class_stats |
|---|---|---|
| クラス数 | 7（fighter-sword 等） | 5（zombie 等） |
| ステータス数 | 13 | 11 |
| 含まれないキー（敵側） | — | `leadership`, `obedience` |

→ 敵専用クラスは `leadership` / `obedience` を持たない
→ `_calc_stats` は class_table.keys() でループするため、enemy_class_stats のキーがない → デフォルト 0 になる
→ 影響範囲：
  - `leadership`：リーダー候補選出に影響しうるが、AI 側の参照箇所は限定的
  - `obedience`：個体 AI の従順度。敵は固定値（goblin=0.5 等）が UnitAI サブクラスで `obedience` 変数を直接設定するため、`character_data.obedience` は不参照
- **結果：実害なし**（enemy_class_stats に leadership / obedience を入れる必要は現状ない）

### 6-3. 味方で有効・敵で dead のステータス
- **`move_speed` のみ**（味方も敵も dead）
- 他の 10 ステータスは全て両陣営で正常動作

### 6-4. 「敵が人間 class_stats を借用」している事実
[`enemy_list.json`](../assets/master/stats/enemy_list.json) の stat_type を集計：

| stat_type | 使用敵 | 数 |
|---|---|---|
| `fighter-axe` | goblin / hobgoblin | 2 |
| `fighter-sword` | skeleton / dark-knight | 2 |
| `archer` | goblin-archer / skeleton-archer | 2 |
| `magician-fire` | goblin-mage / lich / demon / dark-mage | 4 |
| `healer` | dark-priest | 1 |
| `zombie` | zombie | 1 |
| `wolf` | wolf | 1 |
| `salamander` | salamander | 1 |
| `harpy` | harpy | 1 |
| `dark-lord` | dark-lord | 1 |

→ **16 敵中 11 敵が人間クラスを借用**、5 敵だけが enemy_class_stats を使う
→ skeleton / dark-knight などはバランス調整時に `class_stats.json["fighter-sword"]` をいじると味方の剣士も影響を受ける
→ **設計判断：味方 / 敵で同じ class_stats を共有することの是非**（仕様か事故か明記なし）

---

## 7. 設計上の問題点

### 高（バランス調整に直接影響）

#### 7-1. `enemy_class_stats.json` が Config Editor で編集不可
- 5 敵専用クラスのベース値・ランクボーナスを変えるには JSON 直編集が必要
- バランス調整サイクルで Config Editor の旨味を享受できない
- 改善案：「ステータス」タブのサブタブとして「敵クラスステータス」を追加。class_stats と同構造

#### 7-2. 味方の class_stats を 11 敵が借用
- skeleton の物理耐性を上げたい → `fighter-sword` の base を上げる → 味方の剣士も強くなる
- 個別調整の余地は `enemy_list.json` の `stat_bonus` のみ（加算のみ。減算不可）
- 改善案：
  - (a) 全敵を enemy_class_stats に分離（11 個増設）
  - (b) `stat_bonus` に負値を許容
  - (c) 現状維持（味方クラス＝敵としてもバランス取れる前提）

### 中（dead data）

#### 7-3. `move_speed` の dead data 問題
- 詳細は [`investigation_movement_constants.md`](investigation_movement_constants.md) 7-1 参照
- 敵側でも同じ問題（zombie / wolf の move_speed が runtime で読まれない）

### 低（命名・構造）

#### 7-4. enemy_class_stats が leadership / obedience を持たない非対称
- 影響なしだが、「ステータス キー数の不揃い」として将来の混乱の元
- 味方と統一して 13 キーにするか、明示的に「敵側は持たない」と仕様化するか

#### 7-5. `_class_stats_cache` への enemy_class_stats マージが暗黙的
- [character_generator.gd:440-447](../scripts/character_generator.gd#L440) で 1 つの辞書にマージ
- 「class_stats」という名前のキャッシュに敵クラスが混じっているのは可読性が低い
- 改善案：`_unified_class_stats_cache` 等にリネーム、またはマージしない設計

---

## 8. move_speed 有効化（Step 1-B）への含意

### 8-1. 敵側で必要な修正
move_speed を runtime で参照するように修正する場合：

1. **`character_data.move_speed` を実際に読む**
   - PlayerController と UnitAI の `MOVE_INTERVAL` 固定値を、`character.character_data.move_speed` に置換
2. **Wolf / Zombie のオーバーライドの扱い**
   - 現状の `× 0.67` / `× 2.0` のハードコードは廃止候補
   - 倍率を enemy_class_stats の base 値に反映させる（既に wolf.move_speed=40, zombie.move_speed=10 がある）
3. **Config Editor 対応**
   - enemy_class_stats を Config Editor で編集できるようにすると、調整サイクルが回る

### 8-2. 敵側スコア → 秒変換のスケール感
現状の enemy_class_stats（rank=B、属性補正 0、random なしと仮定）:

| 敵クラス | base | + rank×rb（B=1） | スコア計 | `_convert_move_speed()` 結果 |
|---|---|---|---|---|
| zombie | 10 | 0 | 10 | 0.74 秒/タイル |
| wolf | 40 | 5 | 45 | 0.53 秒/タイル |
| salamander | 10 | 0 | 10 | 0.74 秒/タイル |
| harpy | 40 | 0 | 40 | 0.56 秒/タイル |
| dark-lord | 30 | 0 | 30 | 0.62 秒/タイル |

人間クラスのスコア＝25〜40 から 0.55〜0.65 秒/タイル → ほぼ標準速度
zombie / salamander = 0.74 秒/タイル → 標準より 1.3〜1.5 倍遅い
wolf = 0.53 秒/タイル → 標準より速い

→ **設計値はおおむね妥当**。現状の `× 2.0`（zombie）/ `× 0.67`（wolf）と比較：
- zombie：現行 0.40 × 2.0 = 0.80s → 設計値 0.74s（ほぼ同じ）
- wolf：現行 0.40 × 0.67 = 0.27s → 設計値 0.53s（**設計値の方が遅い**）

→ Wolf を有効化すると現行より遅くなる。実プレイで体感調整が必要。

---

## 9. 関連調査
- [`docs/investigation_movement_constants.md`](investigation_movement_constants.md) — move_speed dead data の根本調査・MOVE_INTERVAL 重複・game_speed 適用パターン
- [`docs/investigation_turn_cost.md`](investigation_turn_cost.md) — 向き変更コストの現状（MOVE_INTERVAL との関係）
- [docs/history.md](history.md) — 2026-04-19 個別敵 JSON の数値ステータス削除（行 965 以降）
- [CLAUDE.md](../CLAUDE.md) — ステータス決定構造の仕様

---

## 付録：敵生成フローの全体図

```
PartyManager._spawn_enemy_member(char_id, pos)
  │
  ├─ Character.new()
  │
  ├─ CharacterData.load_from_json("enemies/{enemy}.json")
  │     └─ name / id / is_undead / is_flying / instant_death_immune /
  │        chase_range / territory_range / behavior_description /
  │        projectile_type / sprites
  │
  ├─ CharacterGenerator.apply_enemy_graphics(data)
  │     └─ 画像フォルダ名から sex / age / build を設定
  │
  └─ CharacterGenerator.apply_enemy_stats(data)
        ├─ _load_stat_configs() ※初回のみ
        │     ├─ class_stats.json → _class_stats_cache
        │     ├─ enemy_class_stats.json → 同 cache にマージ
        │     └─ attribute_stats.json → _attr_stats_cache
        │
        ├─ _load_enemy_list() ※初回のみ
        │     └─ enemy_list.json → _enemy_list_cache
        │
        ├─ entry = _enemy_list_cache[char_id]
        │     └─ stat_type / rank / stat_bonus を取得
        │
        ├─ stats = _calc_stats(stat_type, rank, sex, age, build)
        │     └─ class_base + rank × rank_bonus + 属性補正 + random
        │
        ├─ stat_bonus を加算（100 でクランプ）
        │
        ├─ data.max_hp / max_energy / power / skill / etc. を上書き
        │     └─ move_speed は秒/タイル変換して格納（dead）
        │
        └─ _load_class_json(stat_type) でクラス JSON を読み
              ├─ attack_type / attack_range
              ├─ class_id（stat_type を再代入）
              └─ slots.Z / slots.V（pre/post_delay / 各種コスト）
```
