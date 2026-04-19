# ヒーラー関連実装構造の調査（2026-04-18）

> Config Editor「Healer」タブ統合検討・将来「クラス特有の行動」設計方針の材料。
> コード修正は伴わない調査レポート。

## サマリー

- **`healer.gd` / `healer_unit_ai.gd` / `healer_leader_ai.gd` は存在しない**。ヒーラー固有ロジックはすべて `scripts/unit_ai.gd`（基底クラス）内にある。
- **これは全クラス共通のパターン**。V スロット特殊攻撃（剣士・斧戦士・魔法使い等）も含め、「クラス固有の行動ロジック」はすべて基底 UnitAI 内で `class_id` / `attack_type` の match 文により分岐する構造。
- UnitAI サブクラス（`GoblinUnitAI` / `DarkLordUnitAI` 等）は存在するが、用途は「個性／性格」の表現（`obedience` 値、`_should_self_flee` / `_should_ignore_flee` / `_can_attack` / `_get_path_method` のオーバーライド）に限られる。戦闘行動ロジックには関与しない。
- **Config Editor「Healer」タブは定数 1 個（`HEALER_HEAL_THRESHOLD`）しか持たない**。`unit_ai.gd` 内からのみ参照されるため、カテゴリを `UnitAI` に変更するのが最も整合する。
- **統合作業量見積もり: S（小）**。JSON メタ情報の変更とタブ配列の更新だけで完結。

---

## 1. ヒーラー固有ロジックのコード配置

### 独立ファイル
| ファイル | 存在 |
|---|---|
| `scripts/healer.gd`           | ❌ 存在しない |
| `scripts/healer_unit_ai.gd`   | ❌ 存在しない |
| `scripts/healer_leader_ai.gd` | ❌ 存在しない |

ヒーラー固有ロジックを専用ファイルに切り出したものは **一切なし**。

### ヒーラー固有ロジックの所在
すべて `scripts/unit_ai.gd`（基底 UnitAI・2372 行）内に定義されている。該当箇所の概要：

| 機能 | 場所 | 行数 |
|---|---|---|
| `_generate_heal_queue()` 回復行動キュー生成 | [unit_ai.gd:1914-1934](scripts/unit_ai.gd#L1914) | ~21 |
| `_generate_buff_queue()` バフ行動キュー生成 | [unit_ai.gd:1939-1954](scripts/unit_ai.gd#L1939) | ~16 |
| `_find_heal_target()` 回復対象選定 | [unit_ai.gd:2121-2155](scripts/unit_ai.gd#L2121) | ~35 |
| `_find_heal_target_by_ratio()` 閾値付き最低HP検索 | [unit_ai.gd:2160-2173](scripts/unit_ai.gd#L2160) | ~14 |
| `_find_undead_target()` アンデッド特効対象選定 | [unit_ai.gd:2178-2193](scripts/unit_ai.gd#L2178) | ~16 |
| `_find_buff_target()` バフ対象選定 | [unit_ai.gd:2251-2264](scripts/unit_ai.gd#L2251) | ~14 |
| `_start_action` の `"heal"` 分岐（回復実行） | [unit_ai.gd:520-549](scripts/unit_ai.gd#L520) | ~30 |
| `_start_action` の `"buff"` 分岐（バフ実行） | [unit_ai.gd:551-570](scripts/unit_ai.gd#L551) | ~20 |
| `_start_action` の `"move_to_heal"/"move_to_buff"` 分岐 | [unit_ai.gd:502-518](scripts/unit_ai.gd#L502) | ~17（共有） |
| `_generate_queue` の `atype == "heal"` フォールバック | [unit_ai.gd:755-759](scripts/unit_ai.gd#L755) | ~5 |
| `_execute_attack` の `atype == "heal"` 早期return | [unit_ai.gd:1012-1015](scripts/unit_ai.gd#L1012) | ~4 |

**ヒーラー関連の合計：約 190 行**（基底 UnitAI 2372 行中の約 8%）

プレイヤー操作ヒーラー用の回復／バフ実行は別箇所：
- `_execute_heal` / `_execute_buff` in [player_controller.gd:1058, 1087](scripts/player_controller.gd#L1058)（~40 行）

---

## 2. ヒーラー固有ロジックの内容

### Z 攻撃（回復）の発動フロー — AI 操作時
1. `_generate_queue()` 先頭で優先的に `_generate_heal_queue()` を呼ぶ（ATTACK/FLEE/WAIT いずれの戦略よりも上位）
2. `_generate_heal_queue()`：
   - `heal_mp_cost <= 0` または MP 不足なら空配列（スキップ）
   - `_find_heal_target()` で味方の回復対象を検索 → いれば `move_to_heal` + `heal` キューを返す
   - いなければ `_find_undead_target()` でアンデッド敵を検索 → いれば同じキュー（回復魔法がダメージになる）
3. 上記が空なら通常の `_generate_queue` に戻る（ATTACK戦略でターゲットがいれば `_execute_attack`）
4. `_execute_attack` で `atype == "heal"` かつ非アンデッドなら早期 return（攻撃空振り防止）

### V 特殊攻撃（防御バフ）の発動フロー
1. `_generate_queue` 先頭で `_generate_buff_queue()` を呼ぶ
2. `_generate_buff_queue()`：
   - `buff_mp_cost <= 0` または MP 不足でスキップ
   - `_should_use_special_skill()` で special_skill 指示（aggressive/strong_enemy/disadvantage/never）を評価
   - `_find_buff_target()` で `defense_buff_timer <= 0` の同パーティーメンバーを検索
   - 見つかれば `move_to_buff` + `buff` キューを返す
3. `_execute_v_attack()` の match には healer ケースなし（バフは `_generate_buff_queue` の専用キューで実行）

### 回復対象選定ロジック（`_find_heal_target`）
`current_order.heal` の値で挙動分岐：
- **`"aggressive"`**：候補中 HP 率 < `NEAR_DEATH_THRESHOLD` (0.25) の最低 HP
- **`"leader_first"`**：リーダー HP 率 < `HEALER_HEAL_THRESHOLD` (0.5) なら最優先。その後 aggressive と同じ判定
- **`"lowest_hp_first"`**：候補中 HP 率 < `HEALER_HEAL_THRESHOLD` (0.5) の最低 HP
- **`"none"`**：null を返す（回復しない）

候補リスト = `_party_peers`（自パーティーメンバー）＋ `_player`（hero）。敵ヒーラーは対象から除外される（`is_friendly` 一致チェック）。

### アンデッド特効の判定
3 箇所で判定：
- `_find_undead_target()`：敵陣営で `character_data.is_undead == true` かつ射程内のキャラを返す
- `_start_action` の `"heal"`：ターゲットが `is_undead == true` かつ敵陣営なら `take_damage()` を呼ぶ（通常回復の代わりに）
- `character.gd:1055-1056`：攻撃側 `attack_type == "heal"` かつ防御側 `is_undead == true` のとき、ダメージ計算の分岐（回復力をそのままダメージに）

### その他ヒーラー固有の処理
- **クラス判定**：`cd.class_id in ["magician-fire", "magician-water", "healer"]`（MP/SPポーション自動使用の分岐、`unit_ai.gd:2214`）
- **Vスロット特殊攻撃のクラスマッチ**：`_generate_special_attack_queue` の match には healer ケースなし（コメント「ヒーラーの防御バフは _generate_buff_queue() で処理するためここでは扱わない」）
- **ATTACK 戦略の分岐**：`_generate_queue` の ATTACK 分岐で `atype == "heal"` かつターゲット非アンデッドなら `_generate_move_queue()` にフォールバック

---

## 3. HEALER_HEAL_THRESHOLD の参照箇所

| ファイル | 行 | 用途 |
|---|---|---|
| `scripts/global_constants.gd` | 76 | 宣言 |
| `scripts/global_constants.gd` | 328 | CONFIG_KEYS 配列 |
| `scripts/unit_ai.gd` | 2144 | `_find_heal_target()` の `leader_first` モード |
| `scripts/unit_ai.gd` | 2152 | `_find_heal_target()` の `lowest_hp_first` モード |

**参照実体は `unit_ai.gd` のみ**（2 箇所・いずれも `_find_heal_target()` 内）。ヒーラー専用ファイルからの参照は存在しない（そもそもそういうファイルがない）。

---

## 4. 他クラス固有ロジックの配置との比較

### V 特殊攻撃の発動判定
`_generate_special_attack_queue()`（[unit_ai.gd:1989-2032](scripts/unit_ai.gd#L1989)）の match 文で `class_id` ごとに分岐：
- `fighter-sword` → 突進斬り：隣接 2 体以上 かつ 前方に敵＋着地可能マス
- `scout`         → スライディング：隣接 2 体以上
- `fighter-axe`   → 振り回し：隣接 2 体以上
- `archer`        → ヘッドショット：ターゲットありで常時
- `magician-fire` → 炎陣：隣接 2 体以上（敵密集）
- `magician-water`→ 無力化水魔法：ターゲットありで非スタン状態
- healer          → （記載なし・バフは `_generate_buff_queue` 別ルート）

### V 特殊攻撃の実行
`_execute_v_attack()`（[unit_ai.gd:1059](scripts/unit_ai.gd#L1059)）の match で `class_id` ごとに `_v_rush_slash` / `_v_whirlwind` / `_v_headshot` / `_v_flame_circle` / `_v_water_stun` / `_v_sliding` を呼ぶ（6 メソッドで計約 240 行）。**すべて `unit_ai.gd` 内**。

### ヒーラーとの配置比較
| 項目 | ヒーラー | 他クラス（V 攻撃） |
|---|---|---|
| 専用ファイル | なし | なし |
| 基底 UnitAI 内 | `_generate_heal_queue` / `_find_heal_target` 等 | `_generate_special_attack_queue` / `_v_*` メソッド |
| 分岐キー | `attack_type == "heal"`（実質 `class_id == "healer"` / `dark-priest`） | `class_id` の match |
| 実行フロー | 専用キュー（`heal` / `buff` アクション） | 専用アクション（`v_attack`） |

**結論：配置パターンは一致**。ヒーラー固有だけ別扱いではなく、全クラスがこのパターンに従っている。

---

## 5. 設計観点の所見

### UnitAI サブクラスの責務分担（現状）
基底 UnitAI 内：
- クラス固有の「何をするか」（攻撃・回復・V スロット特殊攻撃・炎陣設置等）
- class_id / attack_type による match 分岐

サブクラス（`GoblinUnitAI`, `DarkLordUnitAI`, `NpcUnitAI` 等）内：
- 「どういう性格か」の調整：`obedience` 値、`_should_self_flee` / `_should_ignore_flee` / `_can_attack` / `_get_path_method` のオーバーライド
- 例外的にサブクラス固有 `_process` 拡張（`DarkLordUnitAI._process` がワープ＋炎陣設置を追加。これは頻度が固定ループで発火する特殊ケースのため）

**14 個の UnitAI サブクラスのうち、最大でも 119 行（DarkLordUnitAI）。半数以上は 30 行未満**。基底 UnitAI がアクション定義を一元管理する意図がうかがえる。

### Config Editor「Healer」タブの UnitAI 統合可能性

**作業量見積もり：S（小）**

| 変更 | 対象 | 規模 |
|---|---|---|
| `HEALER_HEAL_THRESHOLD` の category を `Healer` → `UnitAI` | `assets/master/config/constants_default.json` 1 箇所 | 1 行 |
| `TABS` 配列から `"Healer"` を削除 | `scripts/config_editor.gd:25-33` | 1 行 |
| CLAUDE.md / docs/spec.md / docs/history.md のタブ名リスト更新 | 4〜5 箇所 | 数行 |

コードロジックには一切影響しない（定数の扱いは変わらない）。ビルド・動作確認も不要レベルの変更。

### 方式選択：match 文 vs フックメソッド
将来「魔法使い火専用」「剣士専用」等のクラス固有ロジックが増える場合：

**(A) 現行の match 文方式を維持**
- 利点：新クラス追加時は基底 UnitAI 内の match に 1 ケース追加するだけ（目線が 1 箇所）
- 欠点：基底 UnitAI が膨らみ続ける。現時点で 2372 行。更に成長すると可読性低下

**(B) フックメソッド方式（サブクラスで `_generate_class_queue()` をオーバーライド）**
- 利点：クラス固有ロジックがサブクラスに集約される（関心の分離）
- 欠点：現在の 14 サブクラスを書き換える必要あり。性格用の `_should_*` と戦闘ロジックの混在で粒度が不揃いになる恐れ

**現状の所見**：
- 基底 UnitAI 2372 行のうち、クラス固有分岐が占める割合は V 攻撃 ~240 行 + ヒーラー ~190 行 = ~430 行（約 18%）
- まだ (A) で十分耐えるサイズ。将来 3000 行を超えたら (B) への段階的移行を検討する判断タイミング
- いずれの方式でも、性格（`obedience` / `_should_*`）と行動（`_generate_*` / `_v_*`）は別軸なので、サブクラスに両方を同居させる場合は命名・ブロック分けで明確化が必要

### 将来「魔法使い火専用」「剣士専用」が増えた場合の影響
- 現行パターンを維持すれば、基底 UnitAI の該当 match 文にケース追加するだけ
- サブクラス（例：`FighterSwordUnitAI`）を作る必要はない（性格に差異がなければ）
- 既存 `GoblinUnitAI` 等と対称性を保つなら、プレイヤー側クラスごとに UnitAI サブクラスを作る手もあるが、現在は作られていない（`PartyLeaderPlayer` → 素の `UnitAI` 生成）
- 既存 `DarkPriestUnitAI`（敵ヒーラー・24 行）がほぼ空のラッパーになっているのは、性格差分だけが必要でロジックは基底で十分な証拠
