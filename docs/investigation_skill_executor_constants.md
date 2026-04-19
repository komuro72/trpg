# 調査: SkillExecutor の定数・エフェクト実装の棚卸し

**調査日**: 2026-04-18
**対象**: `scripts/skill_executor.gd`（抽出完了後）および関連エフェクトクラス
**目的**: 定数の在処把握・エフェクト責務境界の確認・Config Editor 対応候補の洗い出し

---

## 1. SkillExecutor で参照している定数

### 1-a. クラス JSON の slot から読む値

各スキルが参照する slot フィールドの一覧（SkillExecutor 実装ベース）。

| Skill | heal_mult | damage_mult | range | duration | tick_interval | cost | type | name |
|---|---|---|---|---|---|---|---|---|
| **heal** | ✅ 0.3 | ✅ 1.0（undead時）| - | - | - | ✅ | - | ✅ 回復 |
| **melee** | - | ✅ 1.0 | - | - | - | ✅ | ✅ physical/magic | - |
| **ranged** | - | ✅ 1.0 | - | - | - | ✅ | ✅ physical/magic | - |
| **flame_circle** | - | ✅ 0.8 | ✅ 3 | ✅ 2.5 | ✅ 0.5 | ✅ | - | - |
| **water_stun** | - | ✅ 0.5 | - | ✅ 3.0（スタン）| - | ✅ | - | ✅ 水魔法 |
| **buff** | - | - | - | ✅ 0.0→Character.DEFENSE_BUFF_DURATION | - | ✅ | - | ✅ 防御バフ |
| **rush** | - | ✅ 1.2 | - | - | - | ✅ | - | - |
| **whirlwind** | - | ✅ 1.0 | - | - | - | ✅ | - | - |
| **headshot** | - | ✅ 3.0（immune時）| - | - | - | ✅ | - | - |
| **sliding** | - | - | - | - | - | ✅ | - | - |

- チェックマーク横は「slot 欠落時のフォールバック値」
- `cost` は `_slot_cost()` 経由で `"cost"` / `"mp_cost"` / `"sp_cost"` の順にフォールバック
- **一貫性**：全スキルがフォールバック値を持つため slot キー欠落で crash しない設計

### 1-b. GlobalConstants / 他の定数クラスから読む値

SkillExecutor 内で参照している外部定数：

| 定数 | 宣言場所 | 用途 | 参照回数 |
|---|---|---|---|
| `ATTACK_TYPE_MULT["melee"]` | GlobalConstants | 近接倍率 | 3（melee / rush / whirlwind）|
| `ATTACK_TYPE_MULT["ranged"]` | GlobalConstants | 遠距離倍率 | 3（ranged / water_stun / headshot 免疫）|
| `ATTACK_TYPE_MULT["magic"]` | GlobalConstants | 魔法倍率 | 2（heal undead / flame_circle）|
| `DAMAGE_LEVEL_LARGE` | GlobalConstants | ヘッドショット色選定 | 2 |

その他の GlobalConstants 定数（CONDITION_*、COMBAT_RATIO_*、HP_STATUS_* 等）は SkillExecutor からは参照していない（それらは戦況判断・UI 側で使用）。

### 1-c. Character / CharacterData から読む値

SkillExecutor が読み取り専用で参照しているフィールド：

**Character（インスタンス状態）:**
- `power` — 全ダメージ・回復計算の基礎値
- `is_friendly` — 陣営判定（rush / whirlwind の敵対識別、heal のアンデッド特効）
- `grid_pos` — 範囲計算、方向合わせ、A* 経路判定
- `facing` — `Character.dir_to_vec()` 経由で rush / sliding の方向取得
- `position` — Projectile / FlameCircle のワールド座標（キャスター・ターゲット）
- `hp` — 対象有効性チェック（死亡判定）
- `is_flying` — sliding の `is_walkable_for()` 判定
- `last_attacker` — headshot 即死時にドロップ帰属を設定

**CharacterData（固定属性）:**
- `is_undead` — heal のアンデッド特効判定
- `instant_death_immune` — headshot の即死可否
- `class_id` — ranged の水弾判定（`magician-water`）フォールバック
- `projectile_type` — ranged の弾種（demon の `thunder_bullet`）
- `character_name` — combat ログ・battle メッセージ用

Character / CharacterData はすべて read-only 参照。SkillExecutor は書き換えを行わない（ただし `use_energy()` / `face_toward()` / `take_damage()` / `heal()` / `apply_stun()` / `apply_defense_buff()` / `die()` / `spawn_heal_effect()` のパブリックメソッドを呼ぶ）。

### 1-d. ハードコード値（マジックナンバー候補）

SkillExecutor 内にまだ残っているハードコード：

| 箇所 | 値 | 意味 | Config Editor 化の優先度 |
|---|---|---|---|
| `execute_headshot` kill color | `DAMAGE_LEVEL_LARGE + 9999` | 「LARGE 閾値より充分大きい → 特大色」を表現する任意値 | 低（色選定ロジックの変形）|
| `_spawn_projectile` | `proj.z_index = 2` | 描画順 | 低（ゲーム性に影響なし）|
| `execute_flame_circle` | `flame.z_index = 1` | 描画順 | 低 |
| `proj.setup(..., 1.0, ...)` | `1.0` multiplier | 攻撃者由来の補正なし | 低 |
| `target.take_damage(..., 1.0, ...)` | `1.0` multiplier | 同上 | 低 |
| rush の step 探索範囲 | `range(1, 4)` = 最大3マス | 着地余地 1 マス含む | 中（CLAUDE.md 仕様「2マス」と一致が望ましい）|
| sliding の step 探索範囲 | `range(1, 4)` = 最大3マス | CLAUDE.md 仕様「3マス」と一致 | 低 |
| whirlwind の 8 マス走査 | `range(-1, 2)` × 2 | 隣接 8 マス | 低（幾何学的に固定）|

### 1-e. Character 内の暗黙参照（SkillExecutor 経由で間接的に効く定数）

Character 内部の定数が SkillExecutor の呼び出し結果に影響する：

| 定数 | 値 | 用途 |
|---|---|---|
| `Character.DEFENSE_BUFF_DURATION` | 10.0 | slot.duration = 0 時の buff フォールバック |
| `Character.ENERGY_RECOVERY_RATE` | 3.0 | energy 自動回復速度（SkillExecutor の cost 消費と連動）|
| take_damage 内のクリティカル率 | `skill / 300.0` | クリティカル判定（CLAUDE.md 仕様化済みだが定数化されていない）|

---

## 2. エフェクト系の実装場所

### 2-a. 視覚エフェクトクラス（5個）

| クラス | ファイル | 役割 | 生成場所 | 破棄 |
|---|---|---|---|---|
| **HitEffect** | `hit_effect.gd` | 被弾 3層プロシージャル（リング波紋＋光条フラッシュ＋パーティクル）| `Character._spawn_hit_effect()`（take_damage 内部） | 自己タイマー `queue_free` |
| **HealEffect** | `heal_effect.gd` | 回復エフェクト（cast=外広がり / hit=内縮み）| `Character.spawn_heal_effect()`（SkillExecutor から 4 箇所で呼び出し）+ `PlayerController._spawn_heal_effect()`（位置指定版・旧バフ実装で使用・現在未使用）| 自己タイマー `queue_free` |
| **BuffEffect** | `buff_effect.gd` | 防御バフの緑六角形バリア | `Character.apply_defense_buff()` 内部で生成 | Character がバフタイマー満了時に `_remove_buff_effect()` で手動 free |
| **WhirlpoolEffect** | `whirlpool_effect.gd` | 水魔法スタン中の渦 | `Character.apply_stun()` 内部で生成 | Character がスタン解除時に `_remove_stun_effect()` で手動 free |
| **DiveEffect** | `dive_effect.gd` | ハーピー降下攻撃のフラッシュ | `UnitAI._spawn_dive_effect()`（dive 分岐内）| 自己タイマー `queue_free` |

### 2-b. 継続オブジェクト（2個）

| クラス | ファイル | 役割 | 生成タイミング | 継続動作 | 破棄 |
|---|---|---|---|---|---|
| **FlameCircle** | `flame_circle.gd` | 炎陣の継続ダメージゾーン | `SkillExecutor.execute_flame_circle` / `dark_lord_unit_ai.gd:96`（キュー外・別系統）| `_process` で `tick_interval` ごとに範囲内敵に take_damage | `duration` 経過で自己 `queue_free` |
| **Projectile** | `projectile.gd` | 飛翔体（arrow / fire_bullet / water_bullet / thunder_bullet）| `SkillExecutor.execute_ranged` / `execute_water_stun` / `execute_headshot` / `PlayerController._spawn_projectile`（現在 V 系 headshot 経路削除後は未使用？要確認）| `_process` で直線飛行 2000 px/s | `_on_arrive` で `take_damage` / `apply_stun` 後 `queue_free` |

### 2-c. 状態効果の実装

| メソッド | ファイル | 副作用 |
|---|---|---|
| `Character.apply_stun(duration, attacker)` | character.gd:745 | `is_stunned = true` / WhirlpoolEffect 生成 / combat ログ / battle メッセージ（水魔法用の自然言語） |
| `Character.apply_defense_buff(duration)` | character.gd:725 | `defense_buff_timer` 更新 / BuffEffect 再生成（重複時タイマーリセット＋エフェクト再生成）|
| `Character.heal(amount)` | character.gd:692 | `hp += amount`（max_hp クランプ）/ HEAL SE 再生 |
| `Character.take_damage(...)` | character.gd:775 | クリティカル判定 / 防御判定 / 耐性適用 / HitEffect / battle メッセージ / die() 誘発 |
| `Character.die()` | character.gd（別箇所）| 死亡処理・シグナル発火・queue_free 予約 |

---

## 3. 責務境界の所感

### SkillExecutor が担う範囲
- **計算**: raw_damage（power × type_mult × damage_mult）
- **検証**: null / hp <= 0 / energy 不足の早期 return
- **資源消費**: `use_energy()`
- **向き合わせ**: `face_toward()`
- **SE**: `SoundManager.play_attack_from` / `play_hit_from` / `play_from` / `play(ARROW_SHOOT)`（headshot は `play_from` に統一済み）
- **ダメージ適用**: `target.take_damage()` 呼出
- **エフェクト生成**:
  - Character 経由: `spawn_heal_effect("cast"/"hit")`
  - 直接 new: `Projectile.new()` / `FlameCircle.new()`
- **メッセージ**: `MessageLog.add_combat()` / `add_battle()`
- **着地位置算出**: rush / sliding（caller が実際の移動を実行）

### SkillExecutor が委譲している範囲
- HitEffect 生成 → `Character.take_damage()` 内部
- クリティカル判定 → `Character.take_damage()` 内部
- 防御判定・耐性適用 → `Character.take_damage()` 内部
- 即死処理 → `Character.die()`（hp=0 セット後呼び出し）
- WhirlpoolEffect（スタン）→ `Character.apply_stun()` 内部
- BuffEffect（バフ）→ `Character.apply_defense_buff()` 内部
- Projectile の飛行・着弾 → Projectile 自身（`_process` / `_on_arrive`）
- FlameCircle の tick ダメージ → FlameCircle 自身
- 移動アニメ・UI ロックフラグ → 呼出側（Player: `move_to` + await / AI: `grid_pos` + `sync_position`）

### 責務境界の所感

**整っている点:**
1. **計算・ダメージ適用は SkillExecutor に集約**。Player / AI 乖離が解消。
2. **エフェクトクラスが単一責務**。HitEffect は被弾、HealEffect は回復、BuffEffect はバフ、と 1 エフェクト 1 用途。
3. **状態効果（stun / buff）は Character に集約**。apply_stun / apply_defense_buff がエフェクト生成と状態管理をセットで行うため、SkillExecutor は「どのキャラに何秒」を指定するだけでよい。
4. **Projectile / FlameCircle は自走**。設置後は `_process` で動くため SkillExecutor 側の管理は不要。

**散らかっている点:**
1. **エフェクト生成パターンが 2 系統混在**:
   - Character 経由（`spawn_heal_effect()`）— HealEffect / HitEffect / BuffEffect / WhirlpoolEffect
   - SkillExecutor 内で直接 `.new()` — Projectile（4 箇所）/ FlameCircle（1 箇所）
   - Projectile / FlameCircle も `Character` に wrapper を置けば一貫性が上がる（ただし setup 引数が多いので面倒）。
2. **DiveEffect が UnitAI 内に残留**。dive（harpy）は SkillExecutor 未移行のため。将来 `execute_dive` 抽出時に一緒に統一できる。
3. **FlameCircle の生成経路が 2 系統**:
   - `SkillExecutor.execute_flame_circle` — magician-fire
   - `dark_lord_unit_ai.gd:96` — dark-lord のキュー外処理
   - dark-lord を SkillExecutor 経由に統一すれば解消（既知の要整理項目）。
4. **HEAL SE の再生場所が分散**:
   - 通常回復: `Character.heal()` 内部で SE 再生
   - バフ付与: `SkillExecutor.execute_buff` が `play_from(HEAL, caster)` を直接再生
   - ステージング上は「HEAL SE は回復時のみ」のはずだが、buff でも同じ SE を鳴らしている（heal に相乗りしているため仕様）。
5. **SkillExecutor 内の `PlayerController._spawn_heal_effect` との重複**:
   - PlayerController 側に `_spawn_heal_effect(pos, mode)` が残っているが、現在の buff は SkillExecutor 経由。呼び出しがなければ削除候補。

---

## 4. Config Editor で編集可能にすべき候補

### 既に編集可能（対応済み）
- **各クラス JSON の slot フィールド**：`damage_mult` / `range` / `duration` / `tick_interval` / `cost` / `name` / `type` / `action`
  - → 「味方クラス」タブ・「敵クラス」タブで編集可能
- **ATTACK_TYPE_MULT**（4 種）
  - → 「定数」タブ（Character カテゴリ）で編集可能

### 編集候補（未対応・優先度高）

| 定数 | 現在の宣言 | 理由 | カテゴリ |
|---|---|---|---|
| **クリティカル率**（`skill / 300.0`）| character.gd:786 ハードコード | バランス調整の根幹パラメータ。CLAUDE.md には「skill ÷ 3 %」と仕様化済みだが未定数化 | Character |
| **Character.ENERGY_RECOVERY_RATE** | character.gd:58 const | energy 自動回復速度。各スキルの cost 値と直接連動 | Character |
| **Character.DEFENSE_BUFF_DURATION** | character.gd:89 const | buff のフォールバック値。slot.duration=10.0 があるので実質使われていない可能性あり（整理候補） | Character |
| **Projectile.SPEED**（2000.0 px/s）| projectile.gd const | 演出感のチューニング用 | Character or 新タブ |
| **FlameCircle の画像スケール・色**（画像パス等）| flame_circle.gd const | 将来の画像差し替え時に JSON 化 | 低優先 |

### 編集候補（未対応・優先度低）
- HitEffect / HealEffect / BuffEffect / WhirlpoolEffect / DiveEffect の内部色・時間パラメータ
- Projectile の z_index（2）
- `DAMAGE_LEVEL_LARGE + 9999` マジックナンバー

---

## 5. 所感

### 全体構造の健全性
- **SkillExecutor の設計は整っている**。slot を Dictionary として受け取る構造により Player / AI 共通で JSON 駆動の計算が可能。ATTACK_TYPE_MULT は GlobalConstants に外部化済み。
- **3 層構造の定数配置**が機能している：
  1. slot（クラス単位の可変値）— JSON
  2. GlobalConstants（ゲーム全体の閾値・倍率）— Config Editor 編集可
  3. Character 内 const（インスタンス固有の物理パラメータ）— コード直書き

### 整理の余地
1. **クリティカル率を GlobalConstants に昇格**（最優先・バランス調整に影響）
2. **ENERGY_RECOVERY_RATE を GlobalConstants に昇格**（スキルコスト調整と連動）
3. **DEFENSE_BUFF_DURATION のフォールバック撤廃 or 定数化**（slot.duration で必ず上書きされているため役目を再検討）
4. **FlameCircle / Projectile の Character ヘルパ化**（エフェクト生成の 2 系統混在を解消）
5. **DiveEffect を SkillExecutor.execute_dive に昇格**（将来の dive 移行時）
6. **dark-lord の FlameCircle 生成を SkillExecutor 経由に統一**（CLAUDE.md の要整理項目）
7. **PlayerController._spawn_heal_effect の呼出確認**（未使用なら削除）

### 結論
SkillExecutor 抽出の完了により、Player / AI の計算ロジック統一が達成された。定数の大半は既に Config Editor で編集可能で、残る未対応項目（クリティカル率・ENERGY_RECOVERY_RATE 等）も GlobalConstants 昇格のパターンで段階的に追加できる。エフェクト責務の散らかりは「Character 経由」と「SkillExecutor 直 new」の 2 パターンが混在する点のみで、ゲーム動作には影響なし。段階的な整理対象として記録する。
