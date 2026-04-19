# 敵の V スロット相当実装 調査（2026-04-18）

> dark-lord の「炎陣 + ワープ」が敵クラスタブに V スロット定義を持たない
> まま仕様通り動いているか、他の敵に V スロット相当の処理はないかを
> 調査。

## 結論サマリー

- **dark-lord の特殊行動（ワープ+炎陣）は `DarkLordUnitAI` に完全ハードコード**。slots.V は null で JSON からの参照は一切ない
- 炎陣のパラメータ（半径 / ダメージ / 持続 / tick 間隔）は const 4 個。magician-fire のクラス JSON とは**無関係**（別定義）
- ワープ間隔・探索半径・ワープ先決定ロジックも全部 const
- 他の敵 13 種（zombie / wolf / salamander / harpy / goblin系 / dark系）は V スロット相当の行動を**一切持たない**。いずれも `slots.V: null`
- 敵の energy 消費：基本攻撃の MP コストは `const MP_ATTACK_COST` ハードコード（goblin-mage / dark-mage / lich）。dark_priest のみ heal_cost / buff_cost 経由でクラス JSON 由来

**敵の V スロット化の作業量見積もり: M（中）** — dark_lord 固有ロジックを仕様通り slots.V 経由に移すのは型枠込みで実作業 2〜4 時間程度。

## 推奨対応

**段階移行を推奨**：
1. **Step A（最優先・S）**：CLAUDE.md「敵クラス `slots.V: null` と記述」を追加しつつ、dark_lord の const 値を `slots.V` に移して参照経路を JSON 化（既存の `v_duration` / `v_tick_interval` を拡張利用）
2. **Step B（中・M）**：敵魔法系（goblin-mage / dark-mage / lich）の MP_ATTACK_COST を JSON 由来（`slots.Z.cost`）に揃える
3. **Step C（将来）**：CharacterData に `v_action` / `v_class_behavior` 等のフラグを追加して、「AI が独自ロジックで発動する Vスロット」を表現する汎用枠組みを検討

---

## 1. dark-lord の実装

### 場所
- `scripts/dark_lord_unit_ai.gd`（119 行）
- `DarkLordUnitAI extends UnitAI`

### ワープ移動
```gdscript
const WARP_INTERVAL := 3.0   ## ワープ間隔（秒）
const WARP_RANGE    := 8     ## ワープ先の最大探索半径（タイル）
var _warp_timer: float = WARP_INTERVAL

func _process(delta: float) -> void:
    super._process(delta)  # 通常の AI 処理
    ...
    _warp_timer -= delta / GlobalConstants.game_speed
    if _warp_timer <= 0.0:
        _warp_timer = WARP_INTERVAL
        _do_warp()
```

- **発動条件**：`world_time_running=true` 中かつ `is_player_controlled=false` かつ `is_stunned=false` かつ `hp > 0`
- **間隔**：3 秒固定（`WARP_INTERVAL`・const・game_speed 除算）
- **ワープ先**：自分中心 8 タイル四方の**通過可能タイル（is_walkable + 非占有）**からランダムに選出
- **エネルギー消費なし**（MP/SP チェックもコスト消費もなし）

### 炎陣
```gdscript
const FLAME_RADIUS  := 2     ## 炎陣の半径（タイル）
const FLAME_DAMAGE  := 4     ## 炎陣の tick ダメージ
const FLAME_DURATION := 3.0  ## 炎陣の持続時間（秒）

func _do_warp() -> void:
    ...
    _place_flame_circle(_member.position)

func _place_flame_circle(world_pos: Vector2) -> void:
    ...
    flame.setup(
        world_pos,
        _member.grid_pos,
        FLAME_RADIUS,
        FLAME_DAMAGE,
        FLAME_DURATION,
        0.5,          # tick_interval（ハードコード・インラインリテラル）
        _member,
        _all_members
    )
```

- **発動タイミング**：ワープ完了直後に自動設置（ワープと 1 セット）
- **ダメージ**：**固定値 4**（`_member.power` と無関係。magician-fire の炎陣は `power × 0.8 × ATTACK_TYPE_MULT[magic]` なので別計算）
- **半径**：2 タイル固定（magician-fire は `slots.V.range = 3`）
- **持続**：3.0 秒固定（magician-fire は 2.5 秒）
- **tick**：0.5 秒（magician-fire と同じ）
- **エネルギー消費なし**

### magician-fire の炎陣との差異
| 項目 | dark-lord | magician-fire |
|---|---|---|
| 半径 | 2（const） | 3（JSON `range`）|
| tick ダメージ | 4 固定 | `power × 0.8 × type_mult`（JSON `damage_mult`）|
| 持続 | 3.0 秒（const） | 2.5 秒（JSON `duration`）|
| tick 間隔 | 0.5 秒（リテラル） | 0.5 秒（JSON `tick_interval`）|
| エネルギー消費 | なし | v_slot_cost（20）|

完全に別実装。dark-lord の方は「ボス専用の独自パターン」として分離されている。

### dark-lord の slots.V の状態
[dark-lord.json](assets/master/classes/dark-lord.json):
```json
"slots": {
    "Z": { "name": "暗黒斬", "action": "melee", ... },
    "V": null
}
```

**`V: null` なので CharacterData の v_slot_cost / v_duration / v_tick_interval はすべて既定値（0）**。ワープ/炎陣は完全に `DarkLordUnitAI` の独自コード。

---

## 2. 他の敵の特殊攻撃有無

### 敵固有クラス 5 種の slots.V
すべて `"V": null`：
| ファイル | slots.V | 備考 |
|---|---|---|
| `zombie.json` | null | 独自特殊攻撃なし |
| `wolf.json` | null | 独自特殊攻撃なし |
| `salamander.json` | null | 独自特殊攻撃なし（後退行動のみ）|
| `harpy.json` | null | 独自特殊攻撃なし |
| `dark-lord.json` | null | **ワープ+炎陣あり**（`DarkLordUnitAI` にハードコード）|

### 敵系 UnitAI（14 個）の特殊行動

| ファイル | 行数 | 特殊行動 |
|---|---:|---|
| `goblin_unit_ai.gd` | 27 | なし（`obedience` / self_flee のみ）|
| `goblin_archer_unit_ai.gd` | 42 | 近接時 `flee` キュー（後退）|
| `goblin_mage_unit_ai.gd` | 43 | MP 管理（const MP_ATTACK_COST=2・`use_energy` で消費）|
| `hobgoblin_unit_ai.gd` | 23 | なし |
| `wolf_unit_ai.gd` | 24 | なし |
| `harpy_unit_ai.gd` | 23 | なし（is_flying は CharacterData 経由）|
| `zombie_unit_ai.gd` | 29 | 直進移動（DIRECT）・低速（MOVE_INTERVAL×2）|
| `salamander_unit_ai.gd` | 38 | 近接時 `flee` キュー（後退）|
| `dark_knight_unit_ai.gd` | 23 | なし |
| `dark_mage_unit_ai.gd` | 39 | MP 管理（const MP_ATTACK_COST=2）|
| `dark_priest_unit_ai.gd` | 24 | なし（回復/バフは基底 UnitAI の `_generate_heal_queue` / `_generate_buff_queue` 経由）|
| `lich_unit_ai.gd` | 48 | MP 管理（MP_ATTACK_COST=3）+ 火水弾交互切替フラグ（`_lich_water`）|
| `dark_lord_unit_ai.gd` | 119 | **ワープ+炎陣（独自 `_process` オーバーライド）** |
| `npc_unit_ai.gd` | 15 | なし |

**Vスロット相当（「定期的に or 条件発動する強力な行動」）を持つのは dark_lord のみ**。他は基本攻撃の亜種（flee・MP管理・移動パターン）に留まる。

### 人間クラス流用敵（skeleton / skeleton-archer / demon / dark-knight 等）の V スロット
- `enemy_list.json` で `stat_type: fighter-sword` などを指定しても、個別敵は `slots.V: null` の自身の敵固有クラス JSON を使うわけではなく、**人間クラスの slots.V が適用される**（`apply_enemy_stats` が `_load_class_json(stat_type)` を読む）
- しかし **AI 側で敵の V スロット発動は起動しない**：`unit_ai.gd:_generate_special_attack_queue` の match 文には敵向け class_id ケースがない（fighter-sword 等を想定）
- → 人間クラス流用敵は stats だけ借りて V スロットは無効化されている状態

例：skeleton（stat_type=fighter-sword）は fighter-sword のクラス JSON にある「突進斬り」を持つが、`_generate_special_attack_queue` は発動しない。確認したい場合は実機で skeleton が突進斬りを使ってくるか確認。

---

## 3. 敵の V スロット化のしやすさ評価

### Step A: dark_lord のハードコード値を slots.V 経由に移す

最小限の変更で実現可能：

#### dark-lord.json 変更
```json
"V": {
    "name": "闇のワープ",
    "action": "warp_flame",
    "interval": 3.0,
    "range": 2,
    "damage": 4,
    "duration": 3.0,
    "tick_interval": 0.5
}
```

#### コード変更
- CharacterData に `v_interval` / `v_damage` フィールド追加（必要なら）
- または **DarkLordUnitAI が `_member.character_data.v_duration` / `v_tick_interval` を直接参照**（既存フィールドで足りる）
- `FLAME_DAMAGE` / `FLAME_RADIUS` / `WARP_INTERVAL` / `WARP_RANGE` を JSON 参照に置き換え

#### Config Editor への影響
- 敵クラスタブは味方クラスタブの描画ロジック流用済み。JSON に新キーを追加すれば自動表示される
- 既存の `V_duration` / `V_tick_interval` 列は利用可能
- 新キー（interval / damage / range）を表示したい場合は `CLASS_PARAM_GROUPS` の「Vスロット」に追記

**見積もり: S（小）** — 既存枠組みで吸収可能。

### Step B: 敵魔法系の MP_ATTACK_COST を JSON 化

`goblin_mage` / `dark_mage` / `lich` の攻撃コストを slots.Z.cost から読む：
- 現状：`const MP_ATTACK_COST := 2` or `3`
- 変更：`_member.character_data.heal_cost` 相当の `z_cost` フィールドを追加（or 既存の heal_cost を「Z スロットコスト」汎用フィールドにリネーム）
- `_can_attack()` / `_on_after_attack()` を JSON 参照に書き換え

**見積もり: M（中）** — CharacterData の汎用化が要るが、敵 3 種の差分吸収程度。

### Step C: 「AI 独自発動の V スロット」の汎用枠組み

現状は dark_lord のような「AI が周期発動する V スロット」を表現するデータモデルがない。将来類似の敵を追加する場合：
- `slots.V.trigger: "interval" | "on_damage" | "on_low_hp"` を新設
- `slots.V.interval: 3.0`（interval trigger 用）
- UnitAI 基底に `_process_v_trigger` を実装 → サブクラス不要で JSON 駆動

**見積もり: L（大）** — 設計・データモデル追加・複数箇所の調整が必要。将来の拡張時に検討。

---

## 4. 敵の energy コスト仕様

### 現状の敵 energy 消費パターン
| 敵 | energy 消費 | コスト源 |
|---|---|---|
| 物理敵（goblin / wolf / zombie / hobgoblin / dark-knight / skeleton / skeleton-archer / goblin-archer / harpy / salamander） | なし | — |
| 魔法敵（goblin-mage / dark-mage / lich） | 基本攻撃時 2〜3 | ハードコード const |
| dark-priest | 回復/バフ実行時 | クラス JSON（healer.json の slots.Z/V.cost）|
| dark-lord | なし | — |
| demon | ? | demon は `dark_mage` の UnitAI（DarkMageUnitAI）を流用。`MP_ATTACK_COST=2` を消費 |

### MP/SP 統合後の状況
- `_member.energy` / `_member.max_energy` は全敵に max_energy=stats.energy（0-100）でロード済み（2026-04-18 修正）
- 魔法敵は energy を消費するようになった（以前 max_mp=0 で機能していなかったバグは解消）
- ハードコードされた MP_ATTACK_COST は機能する（const 整数値・energy から減算）

### 敵クラス JSON の cost は必要か
- 物理敵：不要（消費しない）
- 魔法敵：JSON 統一を目指すなら必要（現状はハードコード）
- dark_priest：healer クラスを流用しており既に JSON 経由で動く

---

## 付録：関連コードリファレンス

| 対象 | 場所 |
|---|---|
| DarkLordUnitAI 全体 | [scripts/dark_lord_unit_ai.gd](scripts/dark_lord_unit_ai.gd) |
| ワープ timer | [dark_lord_unit_ai.gd:12-13, 31-46](scripts/dark_lord_unit_ai.gd#L31) |
| ワープ先探索 | [dark_lord_unit_ai.gd:66-85](scripts/dark_lord_unit_ai.gd#L66) |
| 炎陣設置 | [dark_lord_unit_ai.gd:88-108](scripts/dark_lord_unit_ai.gd#L88) |
| FlameCircle 本体 | [scripts/flame_circle.gd](scripts/flame_circle.gd) |
| dark-lord スポーン | [enemy_leader_ai.gd:30](scripts/enemy_leader_ai.gd#L30) `"dark-lord": return DarkLordUnitAI.new()` |
| 敵魔法 MP 管理 | [goblin_mage_unit_ai.gd](scripts/goblin_mage_unit_ai.gd) / [dark_mage_unit_ai.gd](scripts/dark_mage_unit_ai.gd) / [lich_unit_ai.gd](scripts/lich_unit_ai.gd) |
