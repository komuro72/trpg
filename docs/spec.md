# 詳細仕様書

> **運用ルール**: このファイルはClaude Codeが管理する。実装前に参照し、実装後に更新する。

---

## Phase 1: 主人公1人の移動・画像表示・フィールド表示

### Phase 1-1: キャラクター基盤 ✅ 完了

#### 実装済みファイル
```
scenes/
  game_map.tscn          メインシーン（GameMap ノード）
scripts/
  game_map.gd            グリッド描画・シーン初期化
  character.gd           キャラクター基底クラス
  player_controller.gd   プレイヤー入力処理
  party.gd               パーティー管理
```

#### グリッド定数（Phase 1-1 時点 / GlobalConstants導入前）
| 定数 | 値 | 説明 |
|------|-----|------|
| CELL_SIZE | 48px | ※Phase 1-2 で GRID_SIZE=64 に変更済み |
| MAP_WIDTH | 20 | マップ横幅（セル数） |
| MAP_HEIGHT | 15 | マップ縦幅（セル数） |

#### キャラクター表示（character.gd）
- 仮表示：水色の四角形（36×36px、CELL_SIZE=48 からmargin 6px）
- 向きインジケーター：白い10×10px の小矩形（移動方向に追従）
- 向き enum: `Direction { DOWN, UP, LEFT, RIGHT }`
- `move_to(new_grid_pos)` で移動＋向き更新＋`queue_redraw()`

#### 入力（player_controller.gd）
| 入力 | 動作 |
|------|------|
| 矢印キー（↑↓←→） | 主人公を1マス移動 |
| 長押し（初回） | 200ms 待機後に連続移動開始 |
| 長押し（リピート） | 100ms 間隔で連続移動 |

#### パーティー（party.gd）
- `members: Array` でキャラクターリストを管理
- `active_character` で現在の操作対象を保持
- `add_member` / `remove_member` / `set_active` を実装済み

#### アーキテクチャ上の決定事項
- `Character` と `PlayerController` は分離設計。Phase 3 の操作切替は `PlayerController` を `AIController` に差し替えるだけで対応
- `Party` は Phase 1 から用意済み
- グリッド座標 → ワールド座標変換は `sync_position()` に集約

---

### Phase 1-2: グラフィック表示（スプライト・4方向切替） ✅ 完了

#### 実装済みファイル
```
scripts/
  global_constants.gd               GRID_SIZE等のグローバル定数（Autoload）
  character_data.gd                 JSONからデータ読み込みリソースクラス
assets/images/characters/           味方キャラクター画像
assets/master/characters/hero.json  主人公マスターデータ
assets/master/enemies/goblin.json   ゴブリンマスターデータ
assets/master/enemies/enemies_list.json  読み込む敵JSONのリスト
```
変更ファイル: `character.gd`, `game_map.gd`, `project.godot`

#### GlobalConstants（global_constants.gd / Autoload）
| 定数 | 値 | 説明 |
|------|-----|------|
| GRID_SIZE | 64px | グリッド1マスのピクセルサイズ（旧 CELL_SIZE=48 から変更） |
| ~~SPRITE_SOURCE_WIDTH~~ | ~~512px~~ | ~~スプライト素材の元サイズ（横）~~（**2026-04-19 削除**：未使用・dead constant） |
| ~~SPRITE_SOURCE_HEIGHT~~ | ~~1024px~~ | ~~スプライト素材の元サイズ（縦）~~（**2026-04-19 削除**：未使用・dead constant） |

- ~~スケール自動計算: `GRID_SIZE / SPRITE_SOURCE_WIDTH` = 0.125~~
- ~~表示サイズ: 64 × 128px（GRID_SIZE × GRID_SIZE\*2 の縦長 1:2 比率）~~
- 現行はキャラクタートップ画像が 1024x1024 で `tex.get_size()` から動的にスケール計算する実装に置き換え済み

#### CharacterData（character_data.gd）
- `class_name CharacterData extends Resource`
- フィールド: `character_id`, `character_name`, `sprite_front/back/left/right`, `max_hp`, `attack`, `defense`, `behavior_description`
- `static func load_from_json(path: String) -> CharacterData` でJSONから生成
- `static func create_hero() / create_goblin()` はJSONパスを渡すラッパー
- 画像パス規則: `res://assets/images/characters/{id}_front.png`（味方）/ `res://assets/images/enemies/{id}_front.png`（敵）

#### キャラクター向き（character.gd）
- enum: `Direction { DOWN, UP, LEFT, RIGHT }`（トップビュー基準：DOWN=画面下、UP=画面上）
- 移動方向マッピング:
  - delta.y > 0 → DOWN, delta.y < 0 → UP
  - delta.x > 0 → RIGHT, delta.x < 0 → LEFT

#### スプライト表示（character.gd）
- `Sprite2D` を `_ready()` 内でコード生成（`add_child`）
- `character_data` に有効な画像パスがあれば `Sprite2D.texture` に設定
- 画像ファイルが存在しない場合: `Sprite2D` を非表示にし `_draw()` プレースホルダーを表示
- 向き変更時（`move_to()` → `_apply_direction_texture()`）にテクスチャを切り替え
- `CELL_SIZE` 参照をすべて `GlobalConstants.GRID_SIZE` に変更

#### game_map.gd の変更点
- `const CELL_SIZE` を廃止し `GlobalConstants.GRID_SIZE` を参照
- ヒーロー生成時に `CharacterData.create_hero()` を設定

---

### Phase 1-3: フィールド・マップ基盤（タイルマップ・Zオーダー） ✅ 完了

#### 実装済みファイル
```
scripts/
  map_data.gd            タイルデータ管理（新規）
```
変更ファイル: `game_map.gd`, `player_controller.gd`, `character.gd`

#### MapData（map_data.gd）
- `class_name MapData extends RefCounted`
- タイル種別: `enum TileType { FLOOR = 0, WALL = 1, OBSTACLE = 2, CORRIDOR = 3 }`
- マップサイズ定数: `MAP_WIDTH = 20`, `MAP_HEIGHT = 15`
- マップデータ: `_tiles: Array`（Array[Array[int]]、行優先 `_tiles[y][x]`）
- 初期マップ: `_init()` で外周WALL・内側FLOORの四角い部屋を生成
- `get_tile(pos: Vector2i) -> TileType`: 範囲外は WALL を返す
- `is_walkable(pos: Vector2i) -> bool`: FLOOR・CORRIDOR が true
- `is_walkable_for(pos, flying)`: FLOOR・CORRIDOR は常に可。OBSTACLE は flying=true のみ可。WALL は不可

#### タイル仕様
| タイル | 値 | 地上通過 | 飛行通過 | 画像 | フォールバック色 |
|-------|-----|---------|---------|------|--------------|
| FLOOR | 0 | ✅ | ✅ | floor.png | Color(0.40, 0.40, 0.40) |
| WALL | 1 | ✗ | ✗ | wall.png | Color(0.20, 0.20, 0.20) |
| OBSTACLE | 2 | ✗ | ✅ | obstacle.png | Color(0.55, 0.45, 0.35) |
| CORRIDOR | 3 | ✅ | ✅ | corridor.png | Color(0.30, 0.30, 0.35) |

#### タイル描画（game_map.gd）
- `_load_tile_textures()`: 起動時に4種の画像をプリロード。画像なしならフォールバック色
- `_draw()`: 画像があれば `draw_texture_rect`、なければフォールバック色で描画
- グリッド線: `COLOR_GRID_LINE = Color(0,0,0,0.15)` で全タイルにアウトライン

#### DungeonBuilder の通路処理
- `_carve_corridor()` で通路セルに `CORRIDOR` タイルを設定
- 部屋の FLOOR タイルは上書きしない（通路が部屋を通過する場合も FLOOR を保持）

#### 移動制限（player_controller.gd）
- `var map_data: MapData = null` を追加
- `_try_move()` を変更: `map_data.is_walkable(new_pos)` が false なら移動しない
- `map_data` が null の場合は従来の `_is_within_map()` にフォールバック
- MapData.get_tile() が範囲外を WALL 扱いするため、境界チェックも兼ねる

#### Zオーダー（character.gd）
- `z_index = 1` を `_ready()` で設定
- GameMap（z_index=0）の `_draw()` で描画されるタイルより手前に表示
- 将来の `y_sort_enabled` 対応は Phase 1-3 以降で整備

---

### Phase 1-4: カメラ・スクロール（追従・範囲制限） ✅ 完了

#### 実装済みファイル
```
scripts/
  camera_controller.gd   デッドゾーン追従カメラ制御（新規）
```
変更ファイル: `game_map.gd`

#### CameraController（camera_controller.gd）
- `class_name CameraController extends Node`
- `var character: Character` / `var camera: Camera2D` の参照を保持
- `_process()` でキャラクターのグリッド座標変化を検知、変化時に `_update()` を呼ぶ

#### デッドゾーン方式
- `DEAD_ZONE_RATIO = 0.70`（画面サイズの70%）
- デッドゾーンは `(viewport_size × 0.70)` ピクセルの矩形。カメラ中心に対して±half_cells 以内なら固定
- `_dead_zone_half_cells()`: `floor(viewport × 0.70 / 2 / GRID_SIZE)` でグリッドセル数に変換（最小1）
- キャラクターがデッドゾーンを超えたら `_cam_grid` をスナップ（グリッド単位）
- なめらかスクロールは将来のアニメーション実装時に追加

#### マップ端制限・マップ外の黒表示
- `Camera2D.limit_*` をマップピクセルサイズに設定 → Godot が自動でカメラをクランプ
  - `limit_left = 0`, `limit_right = MAP_WIDTH × GRID_SIZE`
  - `limit_top = 0`, `limit_bottom = MAP_HEIGHT × GRID_SIZE`
- マップが画面より小さい場合: Camera2D の limit が自動でマップを中央表示
- マップ外の背景色: `RenderingServer.set_default_clear_color(Color.BLACK)` で黒に設定

#### game_map.gd の変更点
- `_setup_camera()` を追加（Camera2D + CameraController の生成・設定）
- `_ready()` の末尾で `_setup_camera()` を呼び出す
- 視界システム・探索状態管理は実装しない（将来のフェーズで追加予定）

---

### Phase 1-5: 統合・動作確認

#### チェックリスト ✅ 完了
- [x] スプライトが4方向それぞれ正しく表示・切り替わる
- [x] タイルマップが表示され、キャラクターとのZオーダーが正しい
- [x] カメラがキャラクターに追従し、マップ端で止まる
- [x] 長押し移動・マップ端での停止が正常動作する
- [x] `CharacterData.gd` の画像パスを変えるだけで素材を差し替えられる
- [ ] 歩行アニメーション（将来フェーズで追加予定）

---

## Phase 2: 戦闘基盤

### テスト構成
- 味方：プレイヤー操作の主人公1人
- 敵：ゴブリン3体（固定配置）
- クリア条件は未実装（Phase 2 は動作確認のみ）

---

### アセットディレクトリ構成リファクタリング ✅ 完了（Phase 2-1 と同タイミング）

#### 変更内容
- `assets/characters/` → `assets/images/characters/`（味方キャラクター画像）
- `assets/images/enemies/`（敵キャラクター画像置き場）を新設
- `assets/master/characters/`（味方JSONマスターデータ）を新設
- `assets/master/enemies/`（敵JSONマスターデータ）を新設

#### ファイル構成（変更後）
```
assets/
  images/
    characters/    味方キャラクター画像（hero_front.png 等）
    enemies/       敵キャラクター画像（goblin_front.png 等、仮素材まだなし）
  master/
    characters/    hero.json
    enemies/       goblin.json, enemies_list.json
    maps/          dungeon_01.json
```

#### CharacterData のJSON化
- ハードコードされたパラメータ・画像パスをすべて廃止
- `static func load_from_json(path: String) -> CharacterData` を追加
- `create_hero()` / `create_goblin()` はJSONパスへのラッパーとして残す

---

### Phase 2-1: キャラクターステータス基盤 ✅ 完了

#### 変更ファイル
```
scripts/
  character_data.gd                      JSON読み込み方式に変更・create_goblin() 追加
  character.gd                           ステータス変数・take_damage()・die() 追加
  game_map.gd                            died シグナル接続・_on_character_died() 追加
assets/master/characters/hero.json       主人公マスターデータ（新規）
assets/master/enemies/goblin.json        ゴブリンマスターデータ（新規）
assets/master/enemies/enemies_list.json  敵ファイルリスト（新規）
assets/images/characters/               画像移動元: assets/characters/
```

#### CharacterData の追加フィールド
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `max_hp` | int | 最大HP |
| `attack` | int | 攻撃力 |
| `defense` | int | 防御力 |
| `behavior_description` | String | 行動特性の自然言語説明（当初LLM用・現在は参照のみ） |

#### テスト用ステータス
| キャラクター | max_hp | attack | defense | behavior_description |
|------------|--------|--------|---------|----------------------|
| 主人公（hero） | 100 | 10 | 5 | （空欄） |
| ゴブリン（goblin） | 30 | 5 | 2 | "集団で行動する。臆病な性格で強いと思った相手からはすぐ逃げる。" |

#### Character の追加仕様
- `signal died(character: Character)` — 死亡時に発火
- `var hp / max_hp / attack / defense` — `_ready()` で `character_data` から初期化
- `take_damage(raw_amount: int)` — ダメージ計算: `max(1, raw_amount - defense)` を HP から減算。HP が 0 以下で `die()` を呼ぶ
- `die()` — `died` シグナルを emit し `queue_free()` でフィールドから除去

#### game_map.gd の変更点
- `hero.died.connect(_on_character_died)` でシグナル接続
- `_on_character_died(character)` で `party.remove_member(character)` を呼ぶ

---

### Phase 2-2: 敵の配置 ✅ 完了

#### 新規・変更ファイル
```
assets/master/maps/dungeon_01.json   マップ定義（タイル・スポーン情報）（新規）
scripts/map_data.gd                  load_from_json()・スポーン情報フィールド追加
scripts/enemy_manager.gd             敵スポーン・アクティブ化管理（新規）
scripts/game_map.gd                  JSON読み込み・_setup_enemies() 追加
```

#### dungeon_01.json の構造
| フィールド | 内容 |
|-----------|------|
| `id` | マップID |
| `width` / `height` | マップサイズ（20×15） |
| `tiles` | 2次元配列（0=FLOOR, 1=WALL）。外周WALL・内側FLOOR |
| `player_parties` | `[{party_id, members: [{character_id, x, y}]}]` |
| `enemy_parties` | 同形式。party_id:1 にゴブリン3体 |

#### スポーン配置（dungeon_01.json）
| キャラクター | 座標 |
|------------|------|
| 主人公（hero） | (2, 2) |
| ゴブリン1 | (10, 5) |
| ゴブリン2 | (11, 5) |
| ゴブリン3 | (10, 6) |

#### MapData の変更点
- `map_width` / `map_height` をインスタンス変数に昇格（JSON上書き対応）
- `player_parties` / `enemy_parties` 配列を追加
- `static func load_from_json(path) -> MapData`：JSON読み込みファクトリ。失敗時はデフォルトマップにフォールバック
- `get_tile()` / `is_walkable()` のサイズ参照を `map_width`/`map_height` に変更
- `MAP_WIDTH`/`MAP_HEIGHT` 定数は `player_controller.gd` フォールバック用に残す

#### EnemyManager（enemy_manager.gd）
- `class_name EnemyManager extends Node`
- `const ACTIVATION_RANGE = 5`（ユークリッド距離）
- `setup(spawn_list, player, map_data)` — JSONのmembersリストから敵をスポーン
- `set_vision_controlled(enabled: bool)` — true で距離ベースのアクティブ化を無効化（VisionSystem 使用時）
- `set_all_enemies(all_enemies: Array[Character])` — 全パーティー合算の敵リストを設定。game_map が全 EnemyManager 生成後に呼び出す。AI 起動済みの場合は即座に反映
- `get_enemies() -> Array[Character]` — `_enemies` 配列の参照を返す
- `_spawn_enemy(char_id, grid_pos)` — `get_parent().add_child()` でGameMapに追加
- `_process()` — 未アクティブかつ `_vision_controlled=false` の時のみ距離チェック。5マス以内で `_activated = true`
- アクティブ化後は `_start_ai()` で敵種別に応じた BaseAI サブクラスを生成してセットアップ
- 現在は goblin 系すべてに GoblinAI を使用（Phase 6以降で種類を拡張）
- `update_visibility(player_area, map_data, visited_areas)` — VisionSystem から毎フレーム呼び出し。訪問済みエリアの敵を表示し、同一エリアに入ったら AI をアクティブ化
- 敵死亡時は `_on_enemy_died()` で `_enemies` と `enemy_party` から除去し `enemy_ai.notify_situation_changed()` を呼ぶ

#### game_map.gd の変更点
- `_setup_map()` → `MapData.load_from_json(MAP_JSON_PATH)` に変更
- `_setup_hero()` → `map_data.player_parties[0]` からスポーン座標を取得
- `_setup_enemies()` → `enemy_parties` の各パーティーごとに別々の `EnemyManager` を生成（`EnemyManager0`、`EnemyManager1`…）
  - 旧: `all_members` を結合して1つの EnemyManager → 新: パーティーごとに独立した EnemyManager
  - `var enemy_managers: Array[EnemyManager] = []` に変更（旧 `var enemy_manager: EnemyManager`）
- `_setup_controller()` → 全 EnemyManager の `get_enemies()` を `append_array` で結合して `blocking_characters` に設定
- `_setup_vision_system()` → 全 EnemyManager を `vision_system.add_enemy_manager()` でループ追加
- `_setup_panels()` → `enemy_managers` を展開した `Array` を `right_panel.setup()` に渡す
- `_setup_camera()` / `_draw()` → `MapData.MAP_WIDTH/HEIGHT` 定数から `map_data.map_width/height` インスタンス変数に変更

---

### Phase 2-3: ルールベースAI行動生成 ✅ 完了（LLMベースから変更）

#### 新規・変更ファイル
```
scripts/base_ai.gd         ルールベースAI基底クラス（新規）
scripts/goblin_ai.gd       ゴブリン専用AI（新規）
scripts/enemy_manager.gd   _start_ai() を BaseAI サブクラス生成に変更
scripts/enemy_ai.gd        旧実装（LLMベース）
```

#### LLMClient（llm_client.gd）・DungeonGenerator（dungeon_generator.gd）
- コードは残存しているが現在は未使用（将来削除対象）
- 敵AIはルールベースに完全移行済み。ゲーム内からのLLM呼び出しは行っていない

#### BaseAI（base_ai.gd）
- `class_name BaseAI extends Node`
- `setup(enemies, player, map_data)` — アクティブ化後に EnemyManager から呼び出す。`_all_enemies` を自パーティーの `enemies` で初期化（`set_all_enemies()` で全パーティー分に上書きされる）
- `set_all_enemies(all_enemies: Array[Character])` — 全パーティー合算の敵リストを設定。game_map が全 EnemyManager 生成後に各マネージャー経由で呼び出す
- `enum Strategy { ATTACK, FLEE, WAIT }` — 戦略の種類
- `enum PathMethod { DIRECT, ASTAR, ASTAR_FLANK }` — 経路探索方法
- `_enemies: Array[Character]` — 自パーティーの敵（戦略・キュー管理用）
- `_all_enemies: Array[Character]` — 全パーティー合算の敵（`_is_passable` 占有チェック用）
- `_queues: Dictionary` — メンバーIDごとのアクションキュー `{ "Goblin0": [{...}, ...] }`
- `_current: Dictionary` — 現在実行中のアクション
- `_strategies: Dictionary` — enemy_id → 現在の戦略（再評価スキップ判定に使用）
- `_targets: Dictionary` — enemy_id → 攻撃対象キャラクター
- `_path_methods: Dictionary` — enemy_id → PathMethod
- `_reeval_timers: Dictionary` — 定期再評価タイマー（REEVAL_INTERVAL=1.5秒）
- `_initial_count: int` — 初期敵数（逃走判定の基準）
- `notify_situation_changed()` — 全敵の再評価タイマーを即時リセット
- `complete_action(enemy_id)` — `_current` から除去

**キュー管理方式:**
- 定期（1.5秒ごと）または即時（仲間死亡時）に `_do_evaluate_and_refill()` を呼ぶ
- 戦略・ターゲットが変わらず、かつキューが `QUEUE_MIN_LEN=3` 以上残っていればスキップ
- 変化があれば新しいキューで置き換え、攻撃モーション中でなければ IDLE に戻す

**アクション種別:**
| アクション | 説明 |
|-----------|------|
| `move_to_attack` | ターゲットに隣接するまで A* 移動（毎タイルゴール再計算） |
| `attack` | 隣接ターゲットへ近接攻撃（未隣接ならスキップ） |
| `flee` | ターゲットから離れる方向へ移動 |
| `wait` | WAIT_DURATION=1.0秒 待機 |

**A* 経路探索:**
- `_astar(start, goal, mover)` → start を除くタイル列を返す（空なら経路なし）
- **全タイルで `_is_passable` を使用（ゴールタイルも含む）**。占有チェックをスキップしないことで複数の敵が同一マスに集中するのを防ぐ
- max_iter=400 で無限ループ防止
- 経路なし時は `_next_step_direct()` にフォールバック（差が大きい軸優先の直進）

**`_find_adjacent_goal`（ターゲット隣接ゴール計算）:**
- ターゲットの隣接4タイルを走査し、`_is_passable(candidate, enemy)` で通行可能かつ**他の敵が占有していない**タイルの中から最近傍を返す
- `is_walkable_for` のみで判定しないことで、同じパーティーの複数の敵が同一タイルをゴールとして選択することを防ぐ
- 毎ステップ `_step_toward_goal` 内で再計算されるため、先に到着した敵がいれば別のタイルへ自動的に切り替わる

**ASTAR_FLANK:**
- ターゲットの向きの反対方向タイルをゴールに設定
- 到達不可なら通常の隣接ゴールにフォールバック

**種類固有AIフック（サブクラスがオーバーライド）:**
- `_evaluate_strategy(enemy)` → Strategy
- `_select_target(enemy)` → Character
- `_select_path_method(enemy)` → PathMethod

#### GoblinAI（goblin_ai.gd）
- `class_name GoblinAI extends BaseAI`
- `_evaluate_strategy()`:
  - `FLEE`: HP < 30% OR 生存仲間 < 初期数の50%
  - `ATTACK`: プレイヤーが生存
  - `WAIT`: それ以外
- `_select_target()`: プレイヤー（現在はプレイヤーのみ）
- `_select_path_method()`: ASTAR

#### CharacterData の追加フィールド
| フィールド | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `pre_delay` | float | 0.3 | 攻撃前の溜め時間（秒） |
| `post_delay` | float | 0.5 | 攻撃後の硬直時間（秒） |

### Phase 2-4: 移動・攻撃の実装 ✅ 完了

#### 新規・変更ファイル
```
scripts/base_ai.gd           ステートマシン・A*移動・攻撃実行ロジック（Phase 2-3 で統合）
scripts/enemy_manager.gd     setup() に map_data 追加、get_enemies() 追加
scripts/game_map.gd          map_data を渡す・HUD セットアップ追加
scripts/character.gd         get_occupied_tiles() / dir_to_vec() / get_direction_multiplier() 追加
                             take_damage() に multiplier 引数追加
scripts/player_controller.gd 攻撃入力・blocking_characters・占有チェック追加
scripts/hud.gd               ステータスHUD（新規）
```

#### BaseAI ステートマシン（完成版）
| 定数 | 値 | 説明 |
|------|-----|------|
| `MOVE_INTERVAL` | 1.2秒（基準値） | タイル移動の間隔（game_speed で除算） |
| `WAIT_DURATION` | 1.0秒 | wait アクションの待機時間 |
| `REEVAL_INTERVAL` | 1.5秒 | 定期再評価の間隔 |

```
IDLE → キューからアクションを取り出す
  "move_to_attack" → MOVING（MOVE_INTERVAL/game_speed 秒ごとに1タイル移動、毎タイルゴール再計算、到達で IDLE）
  "flee"           → MOVING（脅威から離れる方向へ移動）
  "wait"           → WAITING（WAIT_DURATION 秒後に IDLE）
  "attack"         → ATTACKING_PRE（pre_delay 秒）
                       → _execute_attack()（方向倍率付きダメージ）
                     → ATTACKING_POST（post_delay 秒）→ IDLE
```

- 攻撃の隣接判定: `abs(dx) + abs(dy) == 1`（マンハッタン距離=1 のみ）
- 隣接していない場合はアクションをスキップして次へ

#### 攻撃方向の判定（Character.get_attack_direction）
```
attack_from = attacker.grid_pos - target.grid_pos  # targetから見た攻撃方向
target_fwd  = Character.dir_to_vec(target.facing)
target_right = target_fwd.rotated(PI/2)  # キャラ正面から見て右方向

attack_from == target_fwd   → 正面
attack_from == -target_fwd  → 背面（防御判定スキップ）
dot(attack_from, target_right) > 0 → 右側面（武器のみ防御可）
それ以外                    → 左側面（盾のみ防御可）
```

> ※ Phase 2 実装時点では `get_direction_multiplier` として1.0/1.5/2.0倍で管理していた。
> アイテムシステム実装フェーズで `get_attack_direction` に移行し倍率を廃止する。

#### プレイヤーの攻撃（PlayerController）
- スペース / Enter キー（ui_accept）で発動
- 向いている方向の隣接マスを `blocking_characters` から検索
- ヒットした敵に攻撃方向を渡して `take_damage` を呼ぶ
- 移動と独立して処理（移動中でも攻撃可能）

#### 占有チェック設計（Character.get_occupied_tiles）
- `Character.get_occupied_tiles() -> Array[Vector2i]` — 現在は `[grid_pos]` を返す
- 将来の複数マスキャラはオーバーライドで対応
- `PlayerController.blocking_characters` / `EnemyAI._is_passable()` の両方で使用
- `EnemyManager.get_enemies()` が `_enemies` の参照を返すため、敵の死亡が自動反映

#### ステータスHUD（hud.gd）
- `class_name HUD extends CanvasLayer`（layer=10、常に最前面）
- 半透明背景パネル + Label で左上に表示
- `setup(player, enemies)` — GameMap から呼び出す。enemies は参照渡し
- 毎フレーム `is_instance_valid()` でチェックし、死亡した敵は自動で非表示
- 表示形式:
  ```
  ■ Player  HP: 80 / 100  [healthy]

  ▲ Goblin0  HP: 30 / 30  [healthy]
  ▲ Goblin1  HP: 15 / 30  [wounded]
  ▲ Goblin2  HP: 8 / 30   [critical]
  ```

##### relative_position → オフセット変換（プレイヤーの向き基準）
| プレイヤーの向き | down_side | up_side | left_side | right_side |
|----------------|-----------|---------|-----------|------------|
| DOWN (+Y)      | (0,+1)    | (0,-1)  | (-1,0)    | (+1,0)     |
| UP (-Y)        | (0,-1)    | (0,+1)  | (+1,0)    | (-1,0)     |
| RIGHT (+X)     | (+1,0)    | (-1,0)  | (0,-1)    | (0,+1)     |
| LEFT (-X)      | (-1,0)    | (+1,0)  | (0,+1)    | (0,-1)     |

##### 占有チェック設計（複数マスキャラ対応）
- `Character.get_occupied_tiles() -> Array[Vector2i]` — 現在は `[grid_pos]` を返す
- 将来の複数マスキャラはこのメソッドをオーバーライドするだけで対応
- `PlayerController.blocking_characters: Array[Character]` に敵リストを渡す
  - 複数 EnemyManager 対応後は各 `get_enemies()` を `append_array` で結合したコピー配列を使用
  - コピー配列のため敵死亡時に自動削除されない → `_can_move_to()` で `is_instance_valid(blocker)` チェックを追加して freed ノードをスキップ
- `BaseAI._is_passable()` は `_all_enemies`（全パーティー合算リスト）を参照するため、パーティーをまたいだ占有チェックも正しく動作する
  - `other == moving_enemy` のスキップで自分自身をブロックしない
  - `is_instance_valid(other)` で解放済みノードをスキップ

## AIアーキテクチャ仕様（2層構造）✅ Phase 6-0 で実装済み

> BaseAI/GoblinAI/EnemyManager を以下の構造に移行完了。
> 目標：敵・NPC・プレイヤーパーティーを統一的に扱えるAI基盤。

### ファイル構成
```
scripts/
  party_manager.gd        パーティー管理（汎用。旧EnemyManagerの後継）
  party_leader_ai.gd      リーダーAI基底クラス
  goblin_leader_ai.gd     ゴブリン用リーダーAI
  unit_ai.gd              個体AI基底クラス
  goblin_unit_ai.gd       ゴブリン用個体AI
  enemy_manager.gd        ★後方互換ラッパー（class EnemyManager extends PartyManager）
```
※ 旧 `base_ai.gd` / `goblin_ai.gd` / `enemy_ai.gd` / `llm_client.gd` / `dungeon_generator.gd` は 2026-04-19 に物理削除済み

---

### PartyManager（party_manager.gd）

`class_name PartyManager extends Node`

**旧EnemyManagerからの変更点:**
- `party_type: String`（"enemy" / "npc" / "player"）
- リーダー管理（`_elect_leader()` / `_create_leader_ai()`）を追加
- `enemy_ai: PartyLeaderAI` プロパティ（get: _leader_ai を返す、後方互換）
- `set_all_enemies()` / `get_enemies()` を後方互換エイリアスとして保持

**主要フィールド:**
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `_members: Array[Character]` | Array | パーティー全メンバー |
| `_leader: Character` | Character | 現在のリーダー |
| `_leader_ai: PartyLeaderAI` | Node | リーダーAIインスタンス（AI起動後） |
| `enemy_ai` | PartyLeaderAI | `_leader_ai` へのアクセサ（後方互換） |
| `party_type: String` | String | "enemy" / "npc" / "player" |
| `_all_members: Array[Character]` | Array | 全パーティー合算（AI起動時に渡す） |

**主要メソッド:**
- `setup(spawn_list, player, map_data)` — スポーン・ダイシグナル接続
- `set_all_members(all)` / `set_all_enemies(all)` — 全パーティー合算リストを設定
- `get_members()` / `get_enemies()` — メンバーリストを返す（後者は後方互換エイリアス）
- `set_vision_controlled()` / `update_visibility()` — 視界制御（旧EnemyManagerから移行）
- `_elect_leader()` — 生存メンバーの先頭をリーダーに選出
- `_create_leader_ai(leader)` — キャラ種に応じた PartyLeaderAI を生成（ファクトリ）
- `_start_ai()` — エリア入室時に呼ばれ PartyLeaderAI を生成・起動
- `_on_member_died(character)` — メンバー死亡通知・リーダー再選出・AI通知

---

### PartyLeaderAI（party_leader_ai.gd）

`class_name PartyLeaderAI extends Node`

**役割:** パーティー全体の戦略決定・各メンバーへの指示出し

**主要フィールド:**
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `_party_members: Array[Character]` | Array | PartyManager._members の参照（同一配列） |
| `_unit_ais: Dictionary` | Dict | member.name → UnitAI |
| `_party_strategy: Strategy` | enum | 現在のパーティー戦略 |
| `_reeval_timer: float` | float | 定期再評価タイマー |
| `_initial_count: int` | int | 初期メンバー数（逃走判定の基準） |

**enum Strategy:** `{ ATTACK=0, FLEE=1, WAIT=2, DEFEND=3 }`
- ATTACK/FLEE/WAIT は UnitAI.Strategy と int 値が一致（オーダー経由で渡すため）

**主要メソッド:**
- `setup(members, player, map_data, all_members)` — 初期化・全メンバー分の UnitAI を生成して `_assign_orders()`
- `set_all_members(all_members)` — 各 UnitAI に反映
- `_process(delta)` — 定期再評価（REEVAL_INTERVAL=1.5秒）
- `_assign_orders()` — `_evaluate_party_strategy()` を呼び、各 UnitAI に `receive_order()` を発行
- `notify_situation_changed()` — 再評価タイマーをリセット・`_assign_orders()` 即時実行・全 UnitAI に伝播
- `get_debug_info()` → Array — 各 UnitAI の `get_debug_info()` を収集（旧 BaseAI と同形式）

**サブクラスフック（オーバーライド）:**
- `_create_unit_ai(member)` → UnitAI — メンバーの種別に応じた UnitAI を返す
- `_evaluate_party_strategy()` → Strategy
- `_select_target_for(member)` → Character

---

### GoblinLeaderAI（goblin_leader_ai.gd）

`class_name GoblinLeaderAI extends PartyLeaderAI`

- `_create_unit_ai()`: `GoblinUnitAI.new()` を返す
- `_evaluate_party_strategy()`:
  - `FLEE`: 生存メンバー < 初期数の50%
  - `ATTACK`: プレイヤーが生存
  - `WAIT`: それ以外
- `_select_target_for()`: プレイヤー

---

### UnitAI（unit_ai.gd）

`class_name UnitAI extends Node`

**役割:** リーダーの指示を受けて個体の行動を実行。1インスタンス = 1キャラクター担当

**旧BaseAIとの主な違い:**
- 辞書ベースの多体管理 → 1体専用のシンプルなフィールド
- パーティー戦略判断をリーダーに移譲。自己保存のみ担当
- `receive_order(order)` でリーダーからオーダーを受け取る
- `_fallback_evaluate()` でオーダーなし時の自律行動（後方互換用）

**obedience（従順度）による行動:**
| 従順度 | 挙動 |
|--------|------|
| 1.0（人間NPC） | リーダーの指示を忠実に実行 |
| 0.5（ゴブリン） | 自己HP危機時のみ逃走に切替。それ以外はリーダー指示に従う |
| 0.0（ゾンビ） | リーダー指示を無視。常に最近傍の人間を追跡 |

**主要フィールド:**
- `_member: Character` — 担当キャラクター（1体）
- `_order: Dictionary` — 最後に受け取ったオーダー `{ "strategy": int, "target": Character }`
- `_queue: Array` — アクションキュー
- `_current_action: Dictionary` — 実行中アクション
- `_all_members: Array[Character]` — 全パーティー合算（_is_passable 用）

**オーダー形式:**
```gdscript
{
  "strategy": int,        # UnitAI.Strategy と同じ int 値（ATTACK=0, FLEE=1, WAIT=2）
  "target":   Character,  # 攻撃/追従対象
}
```

**主要メソッド:**
- `setup(member, player, map_data, all_members)` — 初期化
- `receive_order(order)` — オーダーを受け取り、自己保存フック後にキューを再構築
- `notify_situation_changed()` — フォールバック再評価タイマーをリセット
- `get_debug_info()` → Dictionary — RightPanel 用（旧 BaseAI.get_debug_info() と同形式）
- `_astar()` / `_find_adjacent_goal()` / `_is_passable()` — 旧 BaseAI から移植

**ステートマシン:** 旧BaseAIと同一（IDLE / MOVING / WAITING / ATTACKING_PRE / ATTACKING_POST）

**サブクラスフック（オーバーライド）:**
- `_resolve_strategy(ordered_strategy)` → Strategy — 自己保存による指示上書き
- `_evaluate_strategy()` — フォールバック用（オーダーなし時）
- `_get_path_method()` → PathMethod

---

### GoblinUnitAI（goblin_unit_ai.gd）

`class_name GoblinUnitAI extends UnitAI`

- `obedience = 0.5`
- `_should_override_order()`: HP < 30% のとき逃走に切替（リーダー指示を上書き）
- `_select_path_method()`: ASTAR

---

### 旧クラスとの対応
| 旧クラス | 新クラス | 状態 |
|---------|---------|------|
| `BaseAI` | `UnitAI` + `PartyLeaderAI` | 移行完了。**2026-04-19 に物理削除済み** |
| `GoblinAI` | `GoblinUnitAI` + `GoblinLeaderAI` | 移行完了。**2026-04-19 に物理削除済み** |
| `EnemyManager` | `PartyManager` | `class EnemyManager extends PartyManager` として後方互換ラッパーに変更 |

### 後方互換の仕組み
- `EnemyManager extends PartyManager` により `game_map.gd` / `vision_system.gd` / `right_panel.gd` は無変更
- `PartyManager.enemy_ai` プロパティが `_leader_ai`（PartyLeaderAI）を返すため `em.enemy_ai.get_debug_info()` が動作
- `right_panel.gd` が使用する `BaseAI.Strategy.*` の int 値と `UnitAI.Strategy.*` の int 値は一致（ATTACK=0, FLEE=1, WAIT=2）

---

## Phase 3: フィールド生成 ✅ 完了

### 新規・変更ファイル
```
scripts/dungeon_generator.gd              LLMでダンジョン構造JSONを生成・保存（新規・2026-04-19 に物理削除済み）
scripts/dungeon_builder.gd               構造JSONからMapDataをビルド（新規）
scripts/game_map.gd                      ダンジョン読み込み・F5シーン再スタート
scripts/map_data.gd                      init_all_walls() / set_tile() 追加
scripts/llm_client.gd                    max_tokens を var に変更（2026-04-19 に物理削除済み）
scripts/enemy_manager.gd                 enemy_id / character_id の両キーに対応
assets/master/maps/dungeon_generated.json  外部から配置した場合に使用（.gitignore済み）
.gitignore                               dungeon_generated.json を追加
```

### DungeonGenerator（dungeon_generator.gd）※2026-04-19 に物理削除済み
- コードは残存しているが、dungeon_handcrafted.json が存在する限り呼ばれない
- `class_name DungeonGenerator extends Node`
- `FLOOR_COUNT = 3`（一度に生成するフロア数）
- `MAX_TOKENS = 4096`
- `generate()` — LLMにプロンプトを送信。毎回 `randi()` のシード値をプロンプトに含めることで異なるマップを生成
- `SAVE_PATH = "res://assets/master/maps/dungeon_generated.json"`
- シグナル: `generation_completed(dungeon_data)` / `generation_failed(error)`

### DungeonBuilder（dungeon_builder.gd）
- `class_name DungeonBuilder extends RefCounted`（静的メソッドのみ）
- `static func build_floor(floor_data: Dictionary) -> MapData`
  1. 全部屋の外接矩形からマップサイズを計算（+余白2タイル）
  2. `init_all_walls()` で全タイルをWALL初期化
  3. 各部屋を `_carve_room()`（外周1タイルをWALL残しで内部FLOOR展開 → wall_tiles/obstacle_tiles 適用）
  4. 各通路を `_carve_corridor()`（L字形、3タイル幅 = `CORRIDOR_HALF_WIDTH=1`）
  5. スポーン情報を `_build_spawn_data()` で構築
- `_carve_corridor()` — 部屋中心点間をL字で繋ぐ（横→縦の順）
- `_build_spawn_data()` — 入口部屋の中心をプレイヤースポーンに、各部屋の `enemy_party.members` を `enemy_parties` に設定
- **`_carve_room()` 拡張（Phase 13-4）**：部屋JSONの `wall_tiles` / `obstacle_tiles` フィールドを処理
  - `wall_tiles`: 内部をWALLに戻す（非矩形形状用）。`[{"rx": 相対x, "ry": 相対y}, ...]` で指定。rx/ry は部屋左上隅からの相対座標
  - `obstacle_tiles`: 内部をOBSTACLEに設定。飛行キャラは通過可、地上キャラは不可
  - 処理順：FLOOR展開 → wall_tiles適用 → obstacle_tiles適用。後続のcorridor掘削でFLOOR以外のタイルはCORRIDORに上書きされる（通路の疎通は常に保証）

### game_map.gd の変更点
- `DUNGEON_JSON_PATH = "res://assets/master/maps/dungeon_generated.json"` をプライマリパスに
- `FALLBACK_JSON_PATH = "res://assets/master/maps/dungeon_01.json"` を静的フォールバックとして保持
- `CURRENT_FLOOR = 0`（表示するフロアのインデックス）
- `_ready()`: `_load_handcrafted_dungeon()` を直接呼び出す
- `_input()` でF5キーを検知 → `get_tree().reload_current_scene()` でシーン再スタート
- 読み込み失敗時 → `FALLBACK_JSON_PATH`（dungeon_01.json）でフォールバック
- `_setup_enemies()` — `enemy_parties` の各エントリごとに別々の `EnemyManager` を生成（Phase 2-2 の設計と同じ）
- 生成中は「ダンジョン生成中...」ラベルをCanvasLayerで表示

### MapData の追加メソッド
| メソッド | 説明 |
|---------|------|
| `init_all_walls(w, h)` | 指定サイズで全WALL初期化（DungeonBuilderが使用） |
| `set_tile(pos, tile)` | 指定座標のタイルを書き込む（DungeonBuilderが使用） |
| `set_area_name(area_id, name)` | エリアIDに表示名を設定（DungeonBuilderが使用） |
| `get_area_name(area_id) -> String` | エリアIDの表示名を返す（設定なし→空文字） |

**エリア名テーブル (`_area_names: Dictionary`):**
- JSONの `name` フィールドから DungeonBuilder が設定（Claude Code が dungeon_handcrafted.json に直接記述）
- `_carve_room()` で部屋名を設定
- `build_floor()` の通路ループで `corridor_<from>_<to>` 形式のIDに通路名を設定

### LLMClient の変更点 ※2026-04-19 に物理削除済み
- `const MAX_TOKENS := 1024` → `var max_tokens: int = 1024`（DungeonGeneratorが4096に上書き）
- JSONパース失敗時に先頭200文字を `push_error` で出力（デバッグ用）

### EnemyManager の変更点
- `info.get("character_id", "")` → `info.get("enemy_id", info.get("character_id", ""))`
  - 生成マップは `enemy_id` キー、静的マップは `character_id` キーを使うため両対応

### 動作フロー（現在の運用）
```
起動:
  _load_handcrafted_dungeon()
  → DungeonBuilder.build_floor(floors[0])
  → _finish_setup()

F5キー:
  get_tree().reload_current_scene()
```

### 既知の制約・将来の拡張
- 現在は `CURRENT_FLOOR = 0` の1フロアのみ表示。フロア遷移は Phase 9 以降で実装予定
- `FLOOR_COUNT = 3` → 将来的に増やす場合、フロアごとに難易度を変えるプロンプトも追加
- 通路形状はL字固定。将来はより複雑な通路パターンも対応予定

## キャラクターステータス仕様

### ステータス一覧（確定仕様）

**CharacterData フィールド**
| フィールド名 | 型 | 説明 |
|------------|-----|------|
| `max_hp` | int | 最大HP |
| `max_mp` | int | 最大MP（魔法使用時に消費） |
| `attack_power` | int | 物理攻撃力（近接・遠距離共通。分離予定なし） |
| `accuracy` | float | 命中精度（物理・魔法共通。装備実装時に有効化） |
| `magic_power` | int | 魔法威力（攻撃魔法・回復魔法の両方に効く。分離予定なし） |
| `physical_resistance` | float | 物理攻撃耐性（割合軽減%。将来実装） |
| `magic_resistance` | float | 魔法攻撃耐性（割合軽減%。将来実装） |
| `other_resistance` | Dictionary | その他耐性（炎・毒など随時追加。将来実装） |
| `defense_accuracy` | float | 防御精度。防御判定の成功しやすさ。キャラ固有素値・装備による変化なし |
| `move_speed` | float | 移動速度（0-100 スコア・高いほど速い・標準 50）。実効値は `Character.get_move_duration()` が算出（Step 1-B・2026-04-20〜） |
| `leadership` | int | 統率力（リーダー側。クラス・ランクから算出、確定後不変。当面値のみ保持） |
| `obedience` | float | 従順度（個体側 0.0〜1.0。クラス・種族・ランクから算出、確定後不変。当面値のみ保持） |
| `inventory` | Array | アイテムインスタンスの辞書リスト（装備中・未装備品・消耗品すべて含む） |

**CharacterData の防御強度フィールド（クラス固有値・装備補正なし）**
| フィールド名 | 型 | 有効方向 | 保有クラス例 |
|-----------|-----|---------|------------|
| `block_right_front` | int | 正面・右側面 | 剣士・斧戦士・斥候・ハーピー・ダークロード |
| `block_left_front`  | int | 正面・左側面 | 剣士・斧戦士・ハーピー・ダークロード |
| `block_front`       | int | 正面のみ   | 弓使い・魔法使い・ヒーラー・ゾンビ・ウルフ・サラマンダー |

> **注記**: `attack_power`（物理攻撃力）と `magic_power`（魔法威力）は近接/遠距離/魔法を統合した確定仕様。Phase 10-2 以降でも分離しない。

### OrderWindow での表示
- ステータスは素値・補正値（装備合算）・最終値の3列表示（例：攻撃力 15 +3 → 18）
- ヒーラー（attack_type="heal"）には命中精度行を表示しない（回復魔法は必中のため）
- 防御強度は保有フィールドのみ表示（「右手防御強度」「左手防御強度」「両手防御強度」）

### 命中・被ダメージ計算
1. **着弾判定**（accuracy）：命中精度が基準値未満 → 外れ or 誤射（将来実装）
2. **防御判定**（defense_accuracy）：背面攻撃はスキップ。各フィールドを独立してロール。成功したフィールドの合計をダメージカット
3. **耐性適用**（physical/magic resistance）：割合軽減
4. **最終ダメージ確定**（最低1）

### ダメージ計算への装備補正反映
```
物理威力 = power (素値) + 武器 power
魔法威力 = power (素値) + 武器 power
物理技量 = skill (素値) + 武器 skill
物理耐性 = 素値 + 防具 physical_resistance + 盾 physical_resistance
魔法耐性 = 素値 + 防具 magic_resistance    + 盾 magic_resistance
防御強度 = block_right_front / block_left_front / block_front（クラス固有値・装備補正なし）
```

---

## 敵キャラクター一覧

| 敵 | 攻撃タイプ | 移動 | 特徴・行動パターン |
|----|-----------|------|------------------|
| ゴブリン | 近接 | 標準 | 集団行動。臆病で強い相手からすぐ逃げる |
| ホブゴブリン | 近接 | 標準 | ゴブリンの強化版。数体を手下にする。狂暴で攻撃的 |
| ゴブリンアーチャー | 遠距離（弓） | 標準 | 遠距離から弓で攻撃 |
| ゴブリンメイジ | 遠距離（魔法） | 標準 | 遠距離から魔法で攻撃 |
| ゾンビ | 近接（つかみ） | 低速 | 近くの人間に向かってくる |
| ウルフ | 近接（かみつき＝つかみ効果） | 高速 | 集団行動 |
| ハーピー | 近接 | 飛行 | 障害物無視移動。空中時は直接攻撃不可。攻撃時のみ降下 |
| サラマンダー | 遠距離（炎＝魔法効果） | 標準 | 遠距離から火を吐く |
| ダークナイト | 近接 | 標準 | 人間型の強敵 |
| ダークメイジ | 遠距離（魔法） | 標準 | 人間型。後方から魔法攻撃 |
| ダークプリースト | 支援（回復・バリア） | 標準 | 人間型。後方で仲間を回復・強化 |

---

## Phase 4: 攻撃バリエーション ✅ 完了

### 攻撃スロット
| キー | 種別 | 備考 |
|-----|------|------|
| Z/A | 攻撃（melee/ranged 自動判定） | クラスの slots.Z.action で決定 |
| X/B | メニュー戻る | フィールドでは当面未使用（将来の防御・回避に予約） |
| C/V | 未実装（将来用） | — |

**攻撃タイプ自動判定（Phase 10-2 で Z/X 2ボタン → Z/A 1ボタンに統合）**
- `slots.Z.action == "melee"` → マンハッタン距離 1（隣接4方向のみ）
- `slots.Z.action == "ranged"` → ユークリッド距離（rangeフィールド値）

### ターゲット選択モード（ホールド方式 / Phase 6-1 で変更）
- 攻撃キーをホールドしている間が TARGETING モード（移動停止）
- ホールド開始時点から `pre_delay` のカウントダウンを開始
- ホールド中、ターゲットリストをリアルタイム更新（敵の移動・死亡に対応）
- ターゲットソート優先度（`_sort_targets()`）:
  1. 前方±45°（`cos(45°) ≒ 0.707` による dot 積判定）の敵を距離順
  2. それ以外の敵を距離順
- 矢印キー（右/下 = 次、左/上 = 前）で循環選択：敵1 → 敵2 → キャンセル → 敵1…
- 先頭の敵が自動選択される（敵1体なら即フォーカス）
- キーリリース時の処理:
  - フォーカスあり → `_commit_attack()` → FIRING または即発動
  - キャンセル選択 / 敵なし → ノーコストキャンセル
- 壁による遮断チェックは将来実装（現時点は射程のみ判定）
- 空振りなし（キーリリース時に対象が射程外でもヒット確定）

### ターゲット選択中のpre_delay進行 ✅ 実装済み（Phase 6-1）
- ホールド開始時点から `_pre_delay_remaining` のカウントダウンを開始する
- TARGETING 中も毎フレームカウントダウンし続ける（選択操作でリセットしない）
- キーリリース時（`_commit_attack()`）:
  - `_pre_delay_remaining <= 0` → 即 `_execute_pending()`
  - `_pre_delay_remaining > 0` → Mode.FIRING へ移行し、消化後に `_execute_pending()`
- 効果：プレイヤーが慌てずにターゲットを選べる。素早く選べばほぼ待ち時間なし

### PlayerController ステートマシン（Phase 6-1 版）
```
NORMAL:
  Z ホールド → _enter_targeting(Z)  ※有効ターゲットなしでも TARGETING に入る
  X ホールド → _enter_targeting(X)
  矢印キー   → 移動（従来どおり）

TARGETING:
  毎フレーム: _pre_delay_remaining -= delta
  毎フレーム: _refresh_targets()（リアルタイムリスト更新）
  右/下 矢印キー → _cycle_target(+1)
  左/上 矢印キー → _cycle_target(-1)
  攻撃キーリリース → フォーカスあり: _commit_attack() / なし: _exit_targeting()

FIRING:
  毎フレーム: _pre_delay_remaining -= delta
  _pre_delay_remaining <= 0 → _execute_pending() → NORMAL
```

**PlayerController の主要フィールド（Phase 6-1 追加分）:**
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `_pre_delay_remaining` | float | ホールド開始からのpre_delayカウントダウン |
| `_pending_target` | Character | FIRINGステート用・発動待ちターゲット |
| `_pending_slot_data` | Dictionary | FIRINGステート用・発動待ちスロットデータ |
| `FORWARD_CONE_DOT` | float | 前方判定しきい値（cos45° = 0.707） |

### 飛翔体（Projectile）
- `class_name Projectile extends Node2D`
- 速度：`SPEED = 2000.0`（px/秒）。発射後は直線飛行、斜め対応
- 命中判定は発射時点で確定（`will_hit: bool`）。現時点は常に `true`
- 着弾時：`will_hit == true` かつターゲット生存 → `take_damage()` 呼び出し
- 仮素材：黄色の円（半径5px、`draw_circle`）

### ターゲットカーソル（TargetCursor）
- `class_name TargetCursor extends Node2D`
- 選択中ターゲットの位置に黄色リングを描画（`draw_arc`）
- キャンセル選択中は `visible = false`

### 新規ファイル
```
scripts/projectile.gd      飛翔体（直線飛行・着弾時ダメージ）
scripts/target_cursor.gd   ターゲット選択カーソル
```

### 変更ファイル
```
scripts/player_controller.gd  NORMAL/TARGETINGステートマシン・Z/Xキー対応（Phase 4）
                               ホールド方式・FIRINGステート・ターゲットソート（Phase 6-1で全面改修）
scripts/character.gd          face_toward(target_grid_pos) 追加
scripts/game_map.gd           player_controller.map_node = self を追加
```

## Phase 5: グラフィック＆UI強化（一部完了）

### Phase 5 実装済み（トップビュー・タイル画像・飛行キャラ対応）

#### 変更ファイル
```
scripts/map_data.gd            OBSTACLEタイル・is_walkable_for() 追加
scripts/character_data.gd      sprite_top・sprite_front・is_flying 対応
scripts/character.gd           rotation方式・is_flying・_load_top_sprite() 追加
scripts/game_map.gd            タイル画像描画・COLOR_GRID_LINE・_load_tile_textures() 追加
scripts/player_controller.gd   is_walkable_for()・飛行レイヤー分離・近接攻撃飛行制限
scripts/enemy_ai.gd            is_walkable_for()・飛行レイヤー分離・近接攻撃飛行制限
assets/master/characters/hero.json    sprites を top/front 形式に変更、is_flying 追加
assets/master/enemies/goblin.json     同上
```

#### タイル種別（map_data.gd）
| タイプ | 値 | 地上通過 | 飛行通過 | 画像ファイル |
|-------|-----|---------|---------|------------|
| FLOOR | 0 | ✅ | ✅ | floor.png |
| WALL | 1 | ✗ | ✗ | wall.png |
| OBSTACLE | 2 | ✗ | ✅ | obstacle.png |
| CORRIDOR | 3 | ✅ | ✅ | corridor.png |

- `is_walkable_for(pos, flying: bool)`: FLOOR・CORRIDOR は常に可、OBSTACLE は flying=true のみ可、WALL は不可
- `is_walkable(pos)`: 後方互換用（FLOOR・CORRIDOR が true）
- DungeonBuilder の `_carve_corridor()` が通路セルに CORRIDOR を設定（部屋の FLOOR は上書きしない）

#### タイルセット方式（game_map.gd）
- タイル画像は `assets/images/tiles/{category}_{id}/` フォルダに配置
  - floor.png / wall.png / obstacle.png / corridor.png
  - corridor.png 省略時は floor.png にフォールバック
- `_tile_set_id`: フロアデータの `tile_set` フィールドから取得（デフォルト: "stone_00001"）
- `_load_tile_textures()`: `TILE_SET_DIR + _tile_set_id + "/floor.png"` 等のパスを構築して読み込み。`_crop_single_tile()` で高解像度画像の左上1/4を切り出し
- `_draw()`: 画像があれば `draw_texture_rect`、なければフォールバック色で描画
  - フォールバック色: FLOOR=Color(0.40,0.40,0.40) / WALL=Color(0.20,0.20,0.20) / OBSTACLE=Color(0.55,0.45,0.35) / CORRIDOR=Color(0.30,0.30,0.35)
- グリッド線: `COLOR_GRID_LINE = Color(0,0,0,0.15)` で全タイルにアウトライン

#### トップビュー対応（character.gd / character_data.gd）
- `CharacterData`: `sprite_top`（フィールド表示）・`sprite_front`（UI表示）の2枚構成
- `is_flying: bool`（JSONの `is_flying` から読み込み）
- JSON `sprites` フォーマット: `{"top": "res://...hero_top.png", "front": "res://...hero_front.png"}`
- `character.gd`:
  - `_load_top_sprite()`: `sprite_top` を1枚ロード。テクスチャサイズから `GRID_SIZE / tex_size.x` でスケール計算
  - `_apply_direction_rotation()`: ノード全体の `rotation` を向きに応じて設定
  - DOWN=0.0, UP=PI, RIGHT=-PI/2, LEFT=PI/2（トップビュー基準、画像下向き=0°）
  - 向きインジケーター（プレースホルダー）: ローカル上方向に白い矩形

#### 飛行キャラ対応（player_controller.gd / enemy_ai.gd）
- 飛行属性が異なるキャラクター同士はすり抜け可能（占有チェックをスキップ）
- 近接攻撃制限:
  - 地上→飛行: 不可（`c.is_flying` が true なら候補に含めない）
  - 飛行→地上: 可能
  - 飛行→飛行: 不可
  - 遠距離: 双方向で有効（制限なし）
- `_is_passable(pos, moving_enemy)`: 飛行属性が異なる他キャラは通過可能として扱う

### Phase 5 追加実装（UI・視界システム・キャラ状態表示）✅ 完了

#### 変更ファイル
```
scripts/global_constants.gd    GRID_SIZE 動的計算・PANEL_TILES 定数追加
scripts/character.gd           _update_modulate()・HitEffect生成・is_targeting_mode setter追加
scripts/character_data.gd      rank・sprite_top_ready フィールド追加
scripts/player_controller.gd   is_targeting_mode・is_targeted フラグ制御追加
scripts/enemy_ai.gd            エリア情報を LLM 状況 JSON に追加
scripts/enemy_manager.gd       set_vision_controlled()・update_visibility() 追加
scripts/camera_controller.gd   X デッドゾーンをフィールド幅基準に変更
scripts/game_map.gd            GlobalConstants.initialize()・VisionSystem・UIパネル追加
scripts/target_cursor.gd       描画なし（is_targeted modulate で代替）
```

#### 新規ファイル
```
scripts/vision_system.gd    プレイヤーエリア追跡・EnemyManager 可視性通知
scripts/left_panel.gd       左パネル（CanvasLayer）：味方ステータス表示
scripts/right_panel.gd      右パネル（CanvasLayer）：現在エリアの敵情報表示
scripts/message_window.gd   メッセージウィンドウ（CanvasLayer）：エリア入室通知
scripts/hit_effect.gd       ヒットエフェクト（AnimatedSprite2D / フォールバック円）
```

#### GRID_SIZE 動的計算（global_constants.gd）
- `TILES_VERTICAL = 11`（縦タイル数固定・1920x1080基準で 1080/11 ≈ 98px）
- `PANEL_TILES = 3`（左右パネル幅をタイル数で指定）
- `initialize(viewport_size)`: `GRID_SIZE = max(32, viewport_height / TILES_VERTICAL)`
- `game_map.gd` の `_ready()` 冒頭で呼び出す

#### ウィンドウ設定（project.godot `[display]`）
| 設定 | 値 | 備考 |
|-----|-----|------|
| `window/size/viewport_width` | 1920 | |
| `window/size/viewport_height` | 1080 | |
| `window/size/borderless` | true | タイトルバーなし |
| `window/size/mode` | 未設定（Windowed） | 配布時にフルスクリーン(mode=3)予定 |

#### キー操作（game_map.gd `_input()`）
| キー | 動作 |
|-----|------|
| Esc | `get_tree().quit()` でゲーム終了 |
| F1 | `right_panel.toggle_debug()` — AIデバッグパネル ON/OFF |
| F5 | シーン再スタート（`get_tree().reload_current_scene()`） |

#### エディター設定（project.godot 外・開発環境）
- Editor Settings → 実行 → ウィンドウの配置 → **Game Embed Mode = Disabled**
  - 別ウィンドウで起動。エディター上部ツールバーが非表示になる

#### キャラクター状態表示（character.gd）
- `is_targeting_mode: bool`（setter: 変更時に `_update_ready_sprite()` を呼び出してスプライト切替）
  - true 時: `character_data.sprite_top_ready` があればその画像に切替（未設定なら sprite_top のまま）
  - false 時: `sprite_top` に戻す
- `is_attacking: bool`（setter: UnitAI の ATTACKING_PRE 開始時に true、ATTACKING_POST 終了時に false）
  - `is_targeting_mode OR is_attacking` のどちらかが true なら構え画像に切替
  - 将来の仲間AI実装時も同じフラグで対応可能
- `is_targeted: bool`（選択されたターゲット：`Color(1.5, 1.5, 1.5, 1.0)` の白く輝く表現）
- `_update_modulate()` で優先順位：ターゲット選択中 > HP状態
  - is_targeted が true: `Color(1.5, 1.5, 1.5, 1.0)`（オーバーブライト白）
  - HP状態: ratio>0.6=白, ratio>0.3=黄(0.65), ratio>0.1=オレンジ(0.65), それ以下=赤点滅

#### ヒットエフェクト（hit_effect.gd）
- `take_damage()` 呼び出し時に `_spawn_hit_effect()` で HitEffect を生成（`get_parent().add_child()`）
- HitEffect はキャラクターの親ノード（game_map）に追加し、world 座標でヒット位置に表示
- 3層構成のプロシージャル描画（`_draw()`）。加算合成（`CanvasItemMaterial.BLEND_MODE_ADD`）
  - 層1: リング（波紋）— `draw_arc()` × 2本。黄橙色。ease-out で広がる
  - 層2: 光条（十字フラッシュ）— 白い中心グロー + 8方向ライン。0.15秒でフェードアウト
  - 層3: パーティクル散布 — 6〜20個の光粒が放射状に飛散。白→オレンジにlerp
- 総再生時間: 0.40秒。ダメージスケール: `max(0.2, damage / 20.0)`
  - リング最大半径 = `GRID_SIZE * 0.55 * damage_scale`
  - パーティクル数 = `clamp(6 + 4 * damage_scale, 6, 20)`
  - 大ダメージ時は光条の持続が微増
- クリティカル時は2個重なり加算合成で自然に輝度上昇。パーティクルはランダム角度で二重散布

#### CharacterData の追加フィールド（Phase 5）
| フィールド | 型 | JSON キー | 説明 |
|-----------|-----|-----------|------|
| `sprite_top_ready` | String | `sprites.top_ready`（優先）または `ready_image` | 構え画像（ターゲット選択中・攻撃モーション中に使用） |
| `rank` | String | `rank` | 敵ランク（S/A/B/C/D/E/F） |

**JSONキーの優先順位（`sprite_top_ready` の読み込み）:**
1. `sprites.top_ready`（hero.json 形式）
2. `ready_image`（トップレベル・旧互換）

#### アセット配置状況（動作確認済み）
| ファイル | 状態 | 説明 |
|---------|------|------|
| `assets/images/characters/hero_top_ready.png` | ✅ 配置済み | ターゲット選択中の構え画像 |
| `assets/master/characters/hero.json` | ✅ 更新済み | `sprites.top_ready` を追加 |
| `assets/images/enemies/goblin_top_ready.png` | ✅ 配置済み | 攻撃モーション中の構え画像 |
| `assets/master/enemies/goblin.json` | ✅ 更新済み | `sprites.top_ready` を追加 |
| `assets/images/effects/hit_01〜06.png` | 未配置 | Kenney Particle Pack から追加予定（フォールバック動作中） |

#### 視界システム（vision_system.gd）
- `signal area_changed(new_area: String)` — エリア変化通知
- `signal tiles_revealed()` — 新エリア訪問時に game_map の queue_redraw() をトリガー
- `const PLAYER_PARTY_ID = 1`（将来の複数パーティー対応のための定数）
- `_visited_by_party: Dictionary`（`{ party_id: int -> { area_id: String -> true } }`）
- `_visible_tiles: Dictionary`（`{ Vector2i -> true }`）訪問済みエリアのタイル＋隣接壁タイル
- `_has_area_data: bool` — エリアデータが存在しない場合（静的マップ）は視界無効化

**setup(player, map_data):**
1. プレイヤーの開始エリアを即座に訪問済みにする（`_visit_area()`）
2. `_has_area_data` を設定（開始エリアが空文字なら false）

**_process() の流れ:**
1. `map_data.get_area(player.grid_pos)` でエリアID取得
2. エリアが変わったら `area_changed` emit + 未訪問なら `_visit_area()` 呼び出し
3. 毎フレーム `enemy_manager.update_visibility(area, map_data, visited_areas)` を呼び出し

**_visit_area(party_id, area_id):**
1. `_visited_by_party` に追記
2. `_reveal_tiles(area_id)` でタイルキャッシュを更新（8方向隣接壁も含む）
3. `tiles_revealed` emit

**公開メソッド:**
- `is_area_visited(area_id) -> bool` — いずれかのパーティーが訪問済みか
- `get_visible_tiles() -> Dictionary` — 可視タイルキャッシュを返す（空=全タイル表示）
- `get_current_area() -> String`

#### EnemyManager 視界制御（enemy_manager.gd）
- `set_vision_controlled(true)` → 距離ベースのアクティブ化を無効化
- `update_visibility(player_area, map_data, visited_areas: Dictionary)`:
  - 各敵の `enemy_area = map_data.get_area(enemy.grid_pos)` を取得
  - `enemy_area.is_empty()` → 常に visible=true（静的マップ互換）
  - それ以外 → `visited_areas.has(enemy_area)` が true なら visible=true（訪問済みは常に表示）
  - AI アクティブ化: `player_area == enemy_area` かつ未アクティブ時に `_start_ai()` 呼び出し

#### タイル可視化（game_map.gd `_draw()`）
- `vision_system.get_visible_tiles()` で可視タイル辞書を取得
- 辞書が空（エリアデータなし）→ 全タイルを従来通り描画
- 辞書に含まれないタイル座標 → skip（背景の黒のまま・未訪問表現）
- `vision_system.tiles_revealed` → `queue_redraw()` で新エリア訪問時に再描画

#### RightPanel のエリアフィルタリング
- `setup(enemy_managers, vision_system, map_data)` — vision_system と map_data を受け取る
- `vision_system.get_current_area()` で現在エリアを取得
- 敵の `map_data.get_area(enemy.grid_pos)` が current_area と一致するものだけ表示
- vision_system / map_data が null の場合はフィルタなし（後方互換）

#### AIデバッグパネル（RightPanel 下半分）
- `var _debug_visible: bool = true` — デフォルト ON（リリース版では false に変更する）
- `toggle_debug()` — ON/OFF 切替（game_map の F1 キーから呼ぶ）
- ON時: パネルを上半分（敵情報）＋下半分（AI デバッグ）に分割（`split_y = vh * 0.5`）
- OFF時: 敵情報が全体を使用

**デバッグ表示内容（現在エリアの敵のみ・`UnitAI.get_debug_info()` から取得）:**

| 行 | 内容 | フォント |
|----|------|---------|
| 1行目 | キャラ名 / 戦略（攻撃=赤・逃走=黄・待機=緑） / →ターゲット名 | 10px |
| 2行目 | `[現在アクション]` キュー（最大6件、省略時は…） | 9px |

**アクション略語:**
| アクション | 略語 |
|-----------|------|
| `move_to_attack` | 移 |
| `attack` | 攻 |
| `flee` | 逃 |
| `wait` | 待 |

**UnitAI.get_debug_info() の返却形式:**
```
[
  {
    "name": "Goblin0",
    "strategy": int（UnitAI.Strategy 列挙値）,
    "target_name": "Hero",
    "current_action": {"action": "move_to_attack"},
    "queue": [{"action": "attack"}, {"action": "move_to_attack"}, ...],
    "grid_pos": Vector2i(x, y)
  },
  ...
]
```

#### MapData の追加メソッド
- `get_tiles_in_area(area_id: String) -> Array[Vector2i]`
  - `_area_map` を走査して指定 area_id に属する全タイル座標を返す

#### 3カラムUIレイアウト
- 左パネル: 幅 = `PANEL_TILES * GRID_SIZE`、x=0 から
- フィールド: 幅 = `vp_width - 2 * panel_width`、中央
- 右パネル: 幅 = `PANEL_TILES * GRID_SIZE`、x=vp_width-panel_width から
- カメラ X デッドゾーン: `field_width * 0.70 / 2 / GRID_SIZE`（パネル分を除外）
- 左右均等なのでカメラの X オフセット不要

#### LeftPanel（left_panel.gd）
- `CanvasLayer` (layer=10) → `Control` (PRESET_FULL_RECT) → `draw` シグナルでカスタム描画
- 上75%: 味方カード（フェイスアイコン・名前・HPバー・MPバー・状態テキスト）
  - アクティブキャラクター: 青枠ハイライト
  - HPバー色: 緑(>60%) / 黄(>30%) / 赤(≤30%)
  - MPバー: 常に空（将来実装）
- 下25%: ミニマップ予約エリア（"MAP" テキスト表示）

**フェイスアイコン表示（Phase 6-0/6-1で実装）:**
- `sprite_face`（face.png）を優先し、未設定なら `sprite_front`（front.png）を使用
- **TextureRect ノード方式**: `draw_texture_rect()` はカスタム描画コールバック内で白く表示される Godot 4 の制限があるため、`TextureRect` ノードを子として追加する方式を採用
- `_icon_nodes: Dictionary`（`Character → TextureRect`）でメンバーごとにノードをキャッシュ
- `_update_icon_nodes()` を毎フレーム呼び出し、位置・サイズ・テクスチャを更新
- テクスチャなし（画像未設定・ロード失敗）の場合はカスタムドローで `placeholder_color` を描画
- `expand_mode = TextureRect.EXPAND_IGNORE_SIZE`: テクスチャの元サイズを無視してセット済みの `size` で表示

#### RightPanel（right_panel.gd）
- `CanvasLayer` (layer=10) → `Control` → `draw` シグナル
- `enemy.visible == true` の敵を character_id ごとに集計
- 表示: "種類名 ×N" + ランク文字
- ランク色: S/A=赤, B/C=オレンジ
- `CharacterData.rank: String`（デフォルト "C"、JSON の `"rank"` キーから読み込み）
- ランクはS/A/B/Cの4段階（Phase 6-0でD/E/Fを廃止・統一）

#### MessageWindow（message_window.gd）
- `CanvasLayer` (layer=12) → `Control` → `draw` シグナル
- Phase 13-1 でアイコン行方式に刷新。Phase 13-3 でスムーズスクロール追加
- **レイアウト**
  - 左エリア：操作キャラの `front.png`（上半分中央クロップ）
  - 中央：アイコン+テキストログ（スクロール型・7行）
  - 右エリア：操作キャラが交戦した相手の `front.png`
- **バトルメッセージ**：行左端に `[攻撃側face] → [被攻撃側face]` アイコン2枚+テキスト
- **システムメッセージ**：アイコンなし（フル幅テキスト）
- **スムーズスクロール**
  - `_scroll_offset`：新エントリの高さ（px）を初期値として設定し `SCROLL_DURATION=0.15秒` で 0 まで線形補間
  - 最新エントリがウィンドウ下端から滑り込む。`world_time_running` は変更しない（時間停止なし）
  - スクロール中に下端を超えるエントリは描画スキップ（正常な見切れ）
  - 上端パディング 8px（`avail_h = box_h - 12.0`・`entry_y` 最低値 `by + 8.0`）で最上段エントリの上端欠けを防止
  - エントリ描画は `SubViewportContainer`（`_svc`）+ `SubViewport`（`_svp`）+ 内部 Control（`_scroll_content`）構成で実現。`_on_scroll_draw()` で担当。SubViewport のサイズ境界がピクセル単位のクリップ領域になる。スクロール中は退場グループ（`groups[start_g - 1]`）を y=`-exit_gh + _scroll_offset` に描画し、上端から滑らかにクリップアウトされる
- **グループ表示**：連続する同 (attacker, defender) ペアのバトルエントリを `\n` 結合して1ブロックに統合
- **デバッグ表示**：`MessageLog.debug_visible`（デフォルト false）。F1 キーでトグル。debug_visible=true 時はエリアフィルターを無視してすべてのメッセージを表示
- `set_player_character(data)` / `set_combat_target(data)` の公開 API で左右バスト画像を制御

#### AreaNameDisplay（area_name_display.gd）
- `CanvasLayer` (layer=11) → `Control` → `draw` シグナル
- `show_area_name(area_name)` で名前を設定して再描画。空文字で非表示
- タイマー・フェードなし。エリアにいる間は常時表示（alpha=1.0固定）
- 表示位置: フィールドエリア上部中央（`by = gs * 0.35`）
- スタイル: 暗い背景 + ゴールド枠線 + ゴールド調テキスト
- フォントサイズ: `maxi(14, int(gs * 0.22))`（GRID_SIZEに連動）
- game_map.gd の `_on_area_changed()` → `map_data.get_area_name(area_id)` で名前を取得して表示
  - 名前なしエリア（通路など）では空文字を渡して非表示
  - 起動時は `_setup_panels()` 末尾で初期エリア名を即時表示

---

## クラスシステム

### クラス定義
| クラス | ファイル名表記 | 武器タイプ | Z（通常） | X（ため） | C（第3） |
|--------|--------------|-----------|----------|----------|---------|
| 剣士 | fighter-sword | 剣 | 近接物理：斬撃 | 強斬撃 | — |
| 斧戦士 | fighter-axe | 斧 | 近接物理：振り下ろし | 大振り | — |
| 弓使い | archer | 弓 | 遠距離物理：速射 | 狙い撃ち | — |
| 魔法使い(火) | magician-fire | 杖 | 遠距離魔法：火弾(単体) | 火炎(単体高威力) | 火炎範囲 |
| ヒーラー | healer | 杖 | 支援：回復(単体小) | 回復(単体大) | 防御バフ(単体) |
| 斥候 | scout | ダガー | 近接物理：刺突 | 急所狙い | — |

### 設計メモ
- 攻撃スロット ZXCV（最大4）。C/V は Phase 4 時点で空き
- ヒーラーは攻撃スロットに攻撃アクションを持たない（支援専用）
- クラスデータは `assets/master/classes/{class_id}.json` に定義（Phase 6-0で作成）
- 将来拡張：魔法使いの属性分化（水・土・風）、槍兵・飛翔系・両手武器系、状態異常回復

---

## キャラクター生成システム

### 生成フロー
1. 利用可能なグラフィックセット一覧から対象クラスに合うものをランダム選出
2. `assets/master/names.json` から性別に合う名前をランダム選出
3. ランク（S/A/B/C）をランダム決定（グラフィックとは独立）
4. `_calc_stats()` でステータスを計算（設定ファイル方式・下記参照）

### ステータス決定構造（設定ファイル方式・2026-04-07〜）
```
最終値 = class_base + rank × class_rank_bonus
       + sex_bonus + age_bonus + build_bonus
       + randi() % (random_max + 1)
小数を含む場合は加算後に roundi() で整数化
```

#### 設定ファイル
| ファイル | 内容 |
|---------|------|
| `assets/master/stats/class_stats.json` | クラスごとの base（ランクC時基本値）と rank（1段階ごとの加算値） |
| `assets/master/stats/attribute_stats.json` | sex / age / build の補正値、および各ステータスの random_max |

- 両ファイルは `CharacterGenerator._load_stat_configs()` が初回 `_calc_stats()` 呼び出し時にロードし静的キャッシュに保持する
- 対象ステータス: vitality / energy / power / skill / defense_accuracy / physical_resistance / magic_resistance / move_speed / leadership / obedience

#### vitality / energy の格納先
| ステータスキー | 格納先 | 備考 |
|--------------|--------|------|
| `vitality` | `character_data.max_hp` | hp はゲーム開始時に max_hp で初期化 |
| `energy` | 魔法クラス→`max_mp` / 非魔法クラス→`max_sp` | mp / sp はゲーム開始時に上限値で初期化 |

- 魔法クラス判定: `["magician-fire", "magician-water", "healer"]`（`CharacterGenerator.MAGIC_CLASS_IDS`）
- クラスJSON（`assets/master/classes/*.json`）の `"mp"` / `"max_sp"` フィールドは廃止（energy で代替）

#### move_speed の扱い（Step 1-B・2026-04-20〜）
- class_stats / enemy_class_stats / attribute_stats で 0〜100 スケールのスコアを生成
- `character_data.move_speed` に**直接格納**（float 型だが意味は 0-100 スコア）
- 実効値算出は `Character.get_move_duration() -> float`（character.gd）が担当：
  ```gdscript
  duration = GlobalConstants.BASE_MOVE_DURATION * 50.0 / move_speed
  if is_guarding:
      duration *= GlobalConstants.GUARD_MOVE_DURATION_WEIGHT
  return maxf(0.10, duration)  # 下限ハードコード
  ```
  - move_speed=50 → 0.40s/タイル（標準・BASE_MOVE_DURATION そのもの）
  - move_speed=100 → 0.20s/タイル（最速）
  - move_speed=25 → 0.80s/タイル（最遅に近い）
  - 下限 0.10 秒はハードコード（Config Editor 対象外・設計前提）
- **旧 `_convert_move_speed()` は廃止**（character_generator.gd から削除）。味方・敵ともに `data.move_speed = float(stats.move_speed)` で 0-100 値を直接代入
- 呼出側は `get_move_duration() / GlobalConstants.game_speed` で実時間秒に変換する

#### obedience の変換
- 0〜100 の整数スコアで生成し `/ 100.0` で 0.0〜1.0 に変換して格納

#### 要素別の方向性
| 要素 | 設定箇所 | 方向性 |
|------|---------|--------|
| ランク（S〜C） | class_stats.json の rank 値 | rank C=0, S=3 の倍率で加算 |
| 性別（male/female） | attribute_stats.json の sex | male=威力・物理耐性・統率力高め、female=技量・魔法耐性・防御技量高め |
| 年齢（young/adult/elder） | attribute_stats.json の age | young=威力・移動速度高め、adult=バランス、elder=技量・魔法耐性高め |
| 体格（slim/medium/muscular） | attribute_stats.json の build | muscular=威力・物理耐性高め、slim=技量・防御技量高め |
| 乱数 | attribute_stats.json の random_max | ステータスごとに幅を設定（max_hp:15、その他:10、leadership/obedience:20） |

### 各クラスのステータス最大値（設定ファイル方式・理論値）
`max = base + rank×3 + max(sex_bonus) + max(age_bonus) + max(build_bonus) + random_max`

| クラス | vitality | energy | power | skill | phys_res | magic_res | def_acc |
|--------|----------|--------|-------|-------|----------|-----------|---------|
| fighter-sword | 75 | 80 | 75 | 75 | 90 | 30 | 70 |
| fighter-axe | 80 | 80 | 80 | 70 | 95 | 30 | 65 |
| archer | 70 | 80 | 75 | 80 | 85 | 35 | 65 |
| scout | 70 | 80 | 65 | 80 | 80 | 30 | 75 |
| magician-fire | 65 | 80 | 80 | 80 | 35 | 85 | 60 |
| magician-water | 65 | 80 | 80 | 80 | 35 | 85 | 60 |
| healer | 70 | 80 | 75 | 75 | 40 | 85 | 60 |

全ステータス 0〜100 の範囲内に収まっていることを確認。

### グラフィックセット（CharacterData の画像パス）
```
assets/images/characters/{class}_{sex}_{age}_{build}_{id}/
  top.png      フィールド表示（rotationで方向対応）
  ready.png    構えポーズ（ターゲット選択中・攻撃モーション中）
  front.png    全身正面（UI表示用）
  face.png     顔アイコン（LeftPanel表示用）
```
- `character_data.gd` で `sprite_top`, `sprite_top_ready`, `sprite_front`, `sprite_face` として管理
- セットフォルダパスを `image_set` フィールドに持ち、各パスは `image_set + "/top.png"` 等で構成

### names.json フォーマット
```json
{
  "male": ["アルフォンス", "ベルナール", ...],
  "female": ["アリシア", "ベアトリス", ...]
}
```

---

## NPC仕様

### 配置（Phase 6-1〜）
- マップJSON の rooms[] 内の `npc_party` フィールドに記述
  - メンバーは `{ "class_id": "fighter-sword", "x": int, "y": int }` 形式
- DungeonBuilder が `npc_party` を収集し `MapData.npc_parties` に格納
- game_map の `_setup_npcs()` が各パーティーの `NpcManager` を生成・起動

### フィールド表示
- `Character.is_friendly = true` を設定（将来の識別用フラグ。現在は視覚的差別化なし）
- テクスチャあり：通常のキャラクタースプライトをそのまま表示（アウトラインなし）
- テクスチャなし：緑（Color(0.2, 0.9, 0.3)）のプレースホルダー円（アウトラインリングなし）

### AI（NpcLeaderAI + NpcUnitAI）
- `NpcManager` が `CharacterGenerator.generate_character(class_id)` でメンバーをランダム生成
- `NpcLeaderAI._evaluate_party_strategy()`: 生存敵あり → ATTACK、なし → WAIT
- `NpcLeaderAI._select_target_for()`: 担当メンバーに最近傍の生存敵を割り当て
- `NpcUnitAI`: 従順度 1.0（完全にリーダー指示に従う）、A* 経路探索
- 敵リストは `NpcManager.set_enemy_list(enemies)` で game_map から渡す
- VisionSystem がプレイヤーと同エリアに入った瞬間にAIをアクティブ化

### 仲間加入（Phase 6-2で実装）

#### 会話トリガー
- **前提条件**: 現在の部屋内の敵が全滅していること
- プレイヤーとNPC（いずれのメンバー）が隣接したら会話開始
  - 話しかける相手はリーダーでなくてもよい（パーティー内で情報共有されている前提）
  - どちらから近づいてもよい（NPC 側から近寄ってくることもある）
- 会話中もリアルタイム進行を継続（ポーズなし）
- 敵が部屋に侵入したら会話を即座に中断

#### 会話UI
- NPCパーティー情報を表示：メンバーの名前・クラス・ランク
- **プレイヤーから話しかけた場合の選択肢**
  | 選択肢 | 効果 |
  |--------|------|
  | 「仲間になってほしい」 | 相手パーティー全員がプレイヤー側に加入。プレイヤーがリーダー維持 |
  | 「一緒に連れて行ってほしい」 | プレイヤー側が相手パーティーに加入。NPCリーダーがリーダーになる |
- **NPC自発申し出**: 現在は無効（`wants_to_initiate()` は常に false）。プレイヤー起点のみ対応
- **NpcLeaderAI の承諾/拒否判断（スコア比較方式）**:
  - `join_us`（NPC がプレイヤー傘下に入る）のみスコア比較。`join_them` は常に承諾。
  - **足切り条件（先にチェック）**: NPC パーティーの現在フロアが `_get_target_floor()` の返値より低い場合は即座に拒否。適正フロアに到達していない = まだ下層探索の必要がなく仲間を増やすメリットが薄い
  - **プレイヤー側スコア** = リーダーの統率力
                              + パーティーランク和 × 10
                              + 共闘フラグ（`has_fought_together`） × 5
                              + 回復フラグ（`has_been_healed`） × 5
  - **NPC 側スコア** = (100 − 従順度平均×100) + パーティーランク和 × 10
  - プレイヤー側スコア ≥ NPC 側スコア なら承諾
  - **ランク数値**: C=3, B=4, A=5, S=6
  - 数値は `NpcLeaderAI` の定数（`RANK_VALUES / RANK_SCORE_PER_RANK / FOUGHT_TOGETHER_BONUS / HEALED_BONUS`）で管理
- **`has_fought_together` 更新タイミング**: NPC メンバーが敵を攻撃した（`Character.dealt_damage_to` シグナル）または敵から攻撃を受けた（`Character.took_damage_from` シグナル）ときにイベント駆動で更新。NPC とプレイヤーが同フロア・同エリアにいる場合のみセット（`game_map._check_fought_together()`）
- **`has_been_healed` 更新タイミング**: プレイヤー側ヒーラーがNPCメンバーを回復したとき（`player_controller.healed_npc_member` シグナル → `game_map._on_npc_healed()`）

#### 合流処理
- 承諾された場合、NPC パーティー全員が合流
- 合流後の元NPCはプレイヤーパーティーのメンバーとしてAI行動
- 左パネルに合流メンバーを追加表示
- プレイヤーがリーダーでなくなった場合も、プレイヤーが直接操作するキャラは変わらない

---

## Phase 6: 仲間AI・操作切替

### Phase 6-0: 準備（実装済み）

#### AIアーキテクチャのリファクタリング（実装済み）
- `BaseAI` / `GoblinAI` / `EnemyManager` → `PartyManager` + `PartyLeaderAI` + `UnitAI` に移行
- 詳細仕様: 本ファイルの「AIアーキテクチャ仕様（2層構造）」セクション参照
- 移行後もゴブリン3体の既存動作を維持

#### クラス・キャラクター生成（実装済み）

##### クラスJSONファイル
- `assets/master/classes/{class_id}.json` に各クラスのデータを定義（6クラス）
- フィールド: `id`, `name`, `weapon_type`, `base_hp`, `base_attack`, `base_defense`,
  `pre_delay`, `post_delay`, `is_flying`, `behavior_description`, `slots`
- `slots` はスロットキー（Z/X/C/V）ごとに `{name, action, type, range, damage_mult, pre_delay, post_delay}` を定義
  - `action`: melee / ranged / ranged_area / heal / buff_defense
  - `type`: physical / magic / support
  - ヒーラーのみ `heal_mult`, `buff_duration` を使用
  - `null` は未実装スロット

##### CharacterGenerator（character_generator.gd）
- `CharacterGenerator.generate_character(class_id: String = "") -> CharacterData`
  - `assets/images/characters/` を走査してグラフィックセット一覧を取得
  - ランク: C=50%, B=30%, A=15%, S=5% でランダム決定
  - `assets/master/names.json` から性別に合う名前をランダム選択
  - ステータス = クラス基準値 × ランク × 体格 × 性別 × 年齢
- `CharacterGenerator.scan_graphic_sets(class_id: String = "") -> Array[Dictionary]`
  - フォルダ名をパースして `{class, sex, age, build, id, folder}` を返す

##### ステータス補正値（実装値）
| 要素 | S | A | B | C |
|------|---|---|---|---|
| ランク | 2.0 | 1.5 | 1.2 | 1.0 |

| 体格 | hp | attack | defense |
|------|-----|--------|---------|
| slim | 0.85 | 0.80 | 0.90 |
| medium | 1.00 | 1.00 | 1.00 |
| muscular | 1.15 | 1.25 | 1.10 |

| 性別 | hp | attack |
|------|-----|--------|
| male | 1.10 | 1.10 |
| female | 0.90 | 0.90 |

| 年齢 | hp | attack | defense |
|------|-----|--------|---------|
| young | 0.90 | 1.00 | 0.90 |
| adult | 1.00 | 1.00 | 1.00 |
| elder | 1.05 | 0.95 | 1.10 |

##### CharacterData の追加フィールド（Phase 6-0〜）
- `class_id: String` — クラスID（例: "fighter-sword"）
- `image_set: String` — グラフィックセットフォルダパス
- `sprite_face: String` — 顔アイコン（face.png）パス。LeftPanel表示に使用
- `sex: String` — 性別（male / female）
- `age: String` — 年齢（young / adult / elder）
- `build: String` — 体格（slim / medium / muscular）
- `rank: String` — デフォルト "C"（旧: "D"。S/A/B/C の4段階に統一）

##### LeftPanel の更新（Phase 6-0〜）
- フェイスアイコン表示を `sprite_face` 優先に変更（なければ `sprite_front` を使用）

### Phase 6-1: 仲間NPCの配置と基本AI行動（実装済み）

#### 手作りダンジョン（dungeon_handcrafted.json）
- フロア1〜4：12部屋×4フロア（3列×4行、10×8タイルルーム）＋ボスフロア1部屋（30×22）
- 起動時は dungeon_handcrafted.json を直接読み込む
- **Phase 13-4 改修**：全49部屋に `wall_tiles`・`obstacle_tiles` を追加して形状にバリエーションを付与
  - 各部屋に cut-NE/NW/SE/SW/N/S/all/対角/右ストリップなど8種類のカットパターンを適用（3種以上/フロア）
  - 各部屋に1〜2個のOBSTACLEタイル（岩・瓦礫など）を配置
  - ボス部屋：4角3×3カット＋4本2×2障害物柱

#### 新規ファイル
| ファイル | 役割 |
|---------|------|
| `scripts/npc_manager.gd` | NPC 生成・管理（CharacterGenerator 使用） |
| `scripts/npc_leader_ai.gd` | リーダーAI（敵をターゲット） |
| `scripts/npc_unit_ai.gd` | 個体AI（従順度1.0、A*）|
| `assets/master/maps/dungeon_handcrafted.json` | 手作りダンジョン |

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/map_data.gd` | `npc_parties: Array = []` 追加 |
| `scripts/dungeon_builder.gd` | `_build_spawn_data()` で `npc_party` 収集 |
| `scripts/character.gd` | `is_friendly: bool` フラグ追加（アウトラインリングなし） |
| `scripts/vision_system.gd` | `add_npc_manager()` / NPC visibility 更新 |
| `scripts/game_map.gd` | `_setup_npcs()` / `_load_handcrafted_dungeon()` / NPC 登録 / `_link_all_character_lists()` 追加 |
| `scripts/party_manager.gd` | `_spawn_member()` のノード名にマネージャー名プレフィックスを追加（名前衝突防止） |
| `scripts/unit_ai.gd` | `receive_order()` 内で freed オブジェクトへのキャストを `is_instance_valid()` でガード |

#### 初期3人パーティー構成（Phase 6-1 後期追加）

dungeon_handcrafted.json の入口部屋に `player_party` フィールドを追加し、3人編成でゲームを開始できるようにした。

**dungeon_handcrafted.json 入口部屋の player_party フィールド**
```json
"player_party": {
  "members": [
    { "class_id": "fighter-sword", "x": 9, "y": 8 },
    { "class_id": "archer",        "x": 8, "y": 8 },
    { "class_id": "healer",        "x": 10, "y": 8 }
  ]
}
```

**DungeonBuilder の変更**
- `_build_spawn_data()` で入口部屋の `player_party` を読み込む
- `player_party` がなければ従来通りマップ中央に hero 1人を配置（フォールバック）

**game_map.gd の変更**
- `_setup_initial_allies()`: `player_parties[0].members[1+]` を NpcManager 経由でスポーン
  - CharacterGenerator で `class_id` を元にランダム生成（名前・ランク・ステータス等）
  - `npc_managers` に追加し、`_pre_joined_npc_managers` にも記録
- `_merge_pre_joined_allies()`: `_finish_setup()` の最後に呼び出し
  - `nm.activate()` で VisionSystem を経由せず直接 AI 起動
  - `_merge_npc_into_player_party(nm)` で通常の合流処理

**PartyManager.activate() の追加**
```gdscript
func activate() -> void:
    if not _activated:
        _activated = true
        _start_ai()
```
- AI をプログラム側から直接起動（VisionSystem のエリア入室を待たずに使用可能）

#### パーティーカラー・リングシステム
- `PartyManager.set_party_color(color)`: 全メンバーの `character.party_color` を一括更新
- `Character.party_color: Color`（TRANSPARENT=リング非表示）
- ゲーム開始時に各パーティーに色を設定し、フィールド上で味方/敵/NPCを視覚的に区別

#### バグ修正メモ
- **ノード名衝突（`@Node2D@N` キャラ出現）**: 複数の NpcManager が同名ノードをシーンツリーに追加すると Godot が自動リネームする。`party_manager.gd._spawn_member()` でノード名に `self.name`（マネージャー名）をプレフィックスとして付与することで解消。
- **freed オブジェクトクラッシュ**: `unit_ai.gd._process()` がキュー空時に `receive_order(_order)` を再呼び出しする際、`_order` 内に保存済みのターゲット参照が既に `queue_free()` されている場合にキャストでクラッシュ。`is_instance_valid()` チェックを追加して `null` 扱いに変更。
- **NPC-プレイヤー重複**: `player_controller.blocking_characters` に NPC メンバーが含まれていなかった。`game_map._setup_controller()` で NPC メンバーも追加。
- **NPC-敵重複**: `_all_members`（AI の `_is_passable()` 占有チェック用）に自パーティーのみが入っており、双方が相手の座標を無視して重複。`game_map._link_all_character_lists()` を追加し、敵全員＋NPC全員の合算リストを全マネージャーに配布することで解消。

### Phase 6-2: 仲間の加入の仕組み（実装済み）

#### 新規ファイル
| ファイル | 役割 |
|---------|------|
| `scripts/dialogue_trigger.gd` | 隣接チェック・エリア敵全滅確認・NPC 自発申し出検出 |
| `scripts/dialogue_window.gd` | 会話UI（画面下部ポップアップ・GRID_SIZE 連動フォント） |

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/npc_leader_ai.gd` | `wants_to_initiate()` / `get_party_strength()` / `will_accept()` 追加 |
| `scripts/vision_system.gd` | `remove_npc_manager()` 追加（合流後に管理から除外） |
| `scripts/player_controller.gd` | `is_blocked` フラグ追加・`_get_valid_targets()` で `is_friendly` チェック追加 |
| `scripts/game_map.gd` | `_setup_dialogue_system()` / 合流処理 / 敵入室中断 / NPC 一時停止 |

#### 実装詳細

**DialogueTrigger**
- `_process()` は **NPC 自発（wants_to_initiate=true）のみ** 自動トリガー
  - プレイヤー起点（A ボタン）は `try_trigger_for_member()` 経由で呼ばれる
  - これにより「立ち去る」選択後に毎フレーム再トリガーされるバグを防止
- 会話トリガー条件（`try_trigger_for_member()`）:
  1. **話しかけたメンバーのエリアに生存敵がいない**（いれば `dialogue_blocked("enemy_in_area")` を発火）
  2. **同パーティーの別メンバーが戦闘中エリアにいない**（いれば `dialogue_blocked("member_in_combat")` を発火）
  3. 通路（エリアIDなし）には出ないので is_area_enemy_free が false を返すことで自然に除外
- `is_area_enemy_free(area)` はゲームマップの敵入室中断チェックでも共用
- `try_trigger_for_member(member: Character)`: A ボタン押下時に PlayerController 経由で呼ばれる。上記条件を確認して `dialogue_requested` または `dialogue_blocked` を発火
- `dialogue_blocked(member, reason)` シグナルを `game_map._on_dialogue_blocked()` が受信し、MessageLog にシステムメッセージを出力
  - `"enemy_in_area"` → 「○○は戦いに集中している」
  - `"member_in_combat"` → 「○○の仲間が戦闘中のため話せない」

**PlayerController の変更（矢印キーバンプ）**
```gdscript
signal npc_bumped(npc_member: Character)

func _try_move(dir: Vector2i) -> void:
    var new_pos := character.grid_pos + dir
    if _can_move_to(new_pos):
        character.move_to(new_pos)
    else:
        for blocker: Character in blocking_characters:
            if not is_instance_valid(blocker): continue
            if blocker.is_flying != character.is_flying: continue
            if new_pos in blocker.get_occupied_tiles() and blocker.is_friendly:
                npc_bumped.emit(blocker)
                break
```

**game_map.gd の接続**
```gdscript
player_controller.npc_bumped.connect(_on_npc_bumped)

func _on_npc_bumped(npc_member: Character) -> void:
    if dialogue_trigger == null or player_controller.is_blocked:
        return
    dialogue_trigger.try_trigger_for_member(npc_member)
```

**会話UI（MessageWindow統合）** ※旧 DialogueWindow は廃止済み
- MessageWindow下部に選択肢をインライン表示（会話モード）
- NPC メンバー情報をメッセージとして表示（名前・ランク・クラス・状態）
- プレイヤー起点: 3択（仲間に / 連れて行って / 立ち去る）
- NPC 起点: 2択（承諾する / 断る）＋ NPC の申し出セリフ表示
- `show_rejected()` で拒否メッセージを 1.5 秒表示後に `dialogue_dismissed` 発火
- 操作: ↑↓ 選択 / Z・右 決定 / X・左・Esc 閉じる

**NpcLeaderAI の会話関連メソッド・フィールド**
| メソッド / フィールド | 説明 |
|--------------------|------|
| `wants_to_initiate() -> bool` | 常に `false`（NPC自発申し出は現在無効） |
| `has_fought_together: bool` | 同エリアで共に戦闘したことがあるか |
| `has_been_healed: bool` | プレイヤー側ヒーラーに回復されたことがあるか |
| `is_in_combat() -> bool` | 現在 ATTACK 戦略中か |
| `notify_fought_together()` | `has_fought_together = true` にセット |
| `notify_healed()` | `has_been_healed = true` にセット |
| `_get_target_floor() -> int` | 現在の状態に基づく目標フロアを返す（HP/Energy 補正込み）。`_get_explore_move_policy()` と `will_accept()` の共通処理 |
| `will_accept(offer_type, player_party) -> bool` | "join_us": 足切り（適正フロア未到達は即拒否）→スコア比較で承諾/拒否。"join_them": 常に承諾 |

**合流処理（game_map.gd）**
- 会話開始時: `nm.set_process_mode(DISABLED)` で NPC AI を一時停止（会話中に動き回らないようにする）
- 会話終了時: `set_process_mode(INHERIT)` で AI を再開
- 合流後: NPC メンバーを `party` に追加・`visible = true`・VisionSystem と `npc_managers` から除外（再会話防止）
- "連れて行ってほしい": NPC 先頭メンバーを `left_panel.set_active_character()` でハイライト
- `player_controller._get_valid_targets()` に `is_friendly` チェックを追加し、合流後の仲間は攻撃不可

#### バグ修正メモ（Phase 6-2）
- **合流後に仲間を攻撃できる**: `blocking_characters` に NPC が残るため。`_get_valid_targets()` で `is_friendly == true` のキャラをスキップすることで解消。
- **会話中に NPC が動き回る**: 会話開始時に `nm.set_process_mode(PROCESS_MODE_DISABLED)` で NPC 全体を一時停止。
- **Array[String] クラッシュ**: `show_dialogue()` 内でリテラル配列（型なし `Array`）を `Array[String]` に直接代入するとランタイムエラー。`.assign()` で解消。

### 敵キャラクター画像対応（Phase 6-0 拡張 / Phase 6-2 完了後に実装）

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character_generator.gd` | 敵画像スキャン・適用メソッドを追加 |
| `scripts/party_manager.gd` | `_spawn_member()` で `apply_enemy_graphics()` を呼び出し |

#### フォルダ構成
```
assets/images/enemies/
  {enemy_type}_{sex}_{age}_{build}_{id}/
    top.png      フィールド表示用
    ready.png    構え（ターゲット選択中・攻撃中）
    front.png    UI表示用
    face.png     右パネル等のアイコン用（将来）
```
- 味方（`characters/`）と同一ファイル構成
- `enemy_type` には `-` が含まれる（例: `goblin-archer`、`dark-knight`）

#### CharacterGenerator の追加メソッド

**`scan_enemy_graphic_sets(enemy_type: String = "") -> Array[Dictionary]`**
- `assets/images/enemies/` 内のフォルダを走査
- `_parse_enemy_folder_name()` でフォルダ名を解析
- `enemy_type` が空なら全セット、指定があれば一致するセットのみ返す

**`_parse_enemy_folder_name(folder: String) -> Dictionary`**
- フォーマット: `{enemy_type}_{sex}_{age}_{build}_{id}`
- `enemy_type` に `-` が含まれるため、味方の `KNOWN_CLASSES` プレフィックスマッチは使えない
- 代わりに `"_male_"` / `"_female_"` を検索して境界を検出（最初に見つかった方を採用）
- 解析結果: `{ "enemy_type", "sex", "age", "build", "id", "folder" }`

**`apply_enemy_graphics(data: CharacterData) -> void`**
- `data.character_id`（例: `"goblin"`、`"dark-knight"`）で対応フォルダを検索
- 複数ヒットした場合はランダムに1つ選択
- `data.sprite_top / sprite_top_ready / sprite_front / sprite_face / image_set` を上書き
- `data.sex / age / build` もフォルダ情報で更新
- フォルダが見つからない場合は何もしない（JSON 指定パスまたはプレースホルダーを維持）

#### party_manager._spawn_member() の変更
```gdscript
member.character_data = CharacterData.load_from_json(...)
# 敵画像フォルダが存在すればランダムに選択して適用する（なければ JSON パスを維持）
CharacterGenerator.apply_enemy_graphics(member.character_data)
```

#### フォールバック優先順位
1. `assets/images/enemies/{enemy_type}_*/` フォルダが存在 → フォルダ内の画像を使用
2. フォルダなし + JSON に `sprites.top` 等が指定されている → JSON のパスを使用
3. JSON にもパスなし → `_has_texture = false` でプレースホルダー（橙色矩形）表示

---

### Phase 6-3: 操作キャラの切替（未実装）
- `AIController` の本実装
- `Party.set_active()` を使ったプレイヤー操作キャラクターの切替

---

## Phase 7: 指示システム ✅ 実装済み（刷新版）

### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character.gd` | `current_order` を5項目構造に刷新 |
| `scripts/order_window.gd` | 5項目・6プリセット対応に刷新 |
| `scripts/party_leader_ai.gd` | `_assign_orders()` を新キー対応に更新・`set_vision_system()` 追加 |
| `scripts/party_manager.gd` | `set_vision_system()` 追加 |
| `scripts/unit_ai.gd` | `_move_policy`・`_battle_formation` 追加・explore 行動実装 |
| `scripts/map_data.gd` | `get_all_area_ids()` 追加 |
| `scripts/vision_system.gd` | `set_party()` 追加（パーティー全員の探索トリガー） |
| `scripts/left_panel.gd` | 指示略称を2行5項目表示に更新 |
| `scripts/game_map.gd` | VisionSystem を各マネージャーの LeaderAI に配布 |

### 指示項目（Character.current_order）

| キー | 選択肢 | デフォルト | 説明 |
|-----|--------|-----------|------|
| `move` | explore / same_room / cluster / guard_room / standby | same_room | 移動方針 |
| `battle_formation` | surround / front / rear / same_as_leader | surround | 戦闘隊形 |
| `combat` | aggressive / support / standby | aggressive | 戦闘姿勢 |
| `target` | nearest / weakest / same_as_leader | nearest | ターゲット選択 |
| `on_low_hp` | keep_fighting / retreat / flee | retreat | 低HP時の行動 |

### 全体方針プリセット（6種）

| プリセット | combat | battle_formation | move | target | on_low_hp | 備考 |
|-----------|--------|-----------------|------|--------|-----------|------|
| 攻撃 | aggressive | surround | same_room | nearest | keep_fighting | |
| 防衛 | support | surround | cluster | same_as_leader | retreat | |
| 待機 | standby | surround | cluster | nearest | retreat | |
| 追従 | support | surround | cluster | same_as_leader | retreat | |
| 撤退 | standby | surround | cluster | nearest | flee | |
| 探索 | aggressive | surround | explore(リーダー) / same_room(他) | nearest | retreat | リーダーが未訪問エリアを探索 |

### 移動方針（move_policy）の動作

| 値 | 動作 |
|----|------|
| explore | 未訪問エリアに向かう。全訪問済みならランダムエリアを巡回 |
| same_room | リーダーと同じ部屋に留まる |
| cluster | リーダーから5マス以内を維持 |
| guard_room | 初回設定時の部屋に留まり守る |
| standby | その場で待機。隣接の敵のみ攻撃 |

### 戦闘隊形（battle_formation）の動作

| 値 | PathMethod | 動作 |
|----|-----------|------|
| surround | ASTAR | ターゲットの隣接空きタイルへ |
| front | ASTAR | ターゲットの隣接空きタイルへ（surround と同じ） |
| rear | ASTAR_FLANK | ターゲットの背後へ回り込む |
| same_as_leader | ASTAR | surround と同じ |

### 低HP時（on_low_hp）の処理

- `keep_fighting`: 変更なし
- `retreat`: 戦略を WAIT に切替 + move_policy を "cluster" に上書き（リーダーそばに退避）
- `flee`: 戦略を FLEE に切替

### 指示のAI反映フロー

```
Character.current_order
  → PartyLeaderAI._assign_orders() (1.5秒ごと / 状況変化時)
    → 有効戦略決定（combat / on_low_hp / party_strategy の優先判定）
    → UnitAI.receive_order({
        "strategy": int, "target": Character,
        "combat": String, "move": String,
        "battle_formation": String, "leader": Character
      })
      → UnitAI._generate_queue() でアクションキュー生成
```

### 探索行動（explore）の実装

- `VisionSystem.set_party(party)` でパーティー全員の移動を探索トリガーとして登録
- `UnitAI.set_vision_system(vs)` で VisionSystem への参照を保持
- `_find_explore_target()`: `MapData.get_all_area_ids()` で全エリア取得 → `VisionSystem.is_area_visited()` で未訪問エリアを検出 → 最近傍エリアの代表タイルへ
- `move_to_explore` アクション: ゴールは `_start_action()` で固定（`move_to_attack` と異なりリアルタイム更新しない）

### 左パネル略称（2行表示）

- 行1: 移動 + 戦闘 + 標的（例: `室 積 近`）
- 行2: 隊形 + 低HP（例: `囲 退`）

| キー | 略称マッピング |
|-----|--------------|
| move | 探=explore / 室=same_room / 密=cluster / 守=guard_room / 待=standby |
| battle_formation | 囲=surround / 前=front / 後=rear / 同=same_as_leader |
| combat | 積=aggressive / 援=support / 待=standby |
| target | 近=nearest / 弱=weakest / 同=same_as_leader |
| on_low_hp | 継=keep_fighting / 退=retreat / 逃=flee |

### バグ修正メモ（Phase 7）

**初期パーティーメンバーが動かない問題**
- **原因**: `_finish_setup()` は1フレームで同期実行される。VisionSystem.setup() は初期エリアを設定するが `update_visibility()` は呼ばない。pre-joined NpcManager は `_vision_controlled=true` のため、VisionSystem の `_process()` が動く前に `remove_npc_manager()` で除外されてしまい、AI が起動しないまま party に合流する。
- **修正**: `PartyManager.activate()` を public で追加。`_merge_pre_joined_allies()` で `nm.activate()` を呼んでから merge することで、VisionSystem を経由せず直接 AI を起動する。

**事前合流メンバーと敵が重なる問題**
- **原因**: 最初の修正案では plain `Character` ノードを直接生成したため、`blocking_characters` に登録されず敵の占有チェックから除外されていた。
- **修正**: NpcManager 経由でスポーン（`_setup_initial_allies()`）し、`_link_all_character_lists()` の前に `npc_managers` に追加する。これにより通常 NPC と同じ経路で全マネージャーの衝突リストに自動登録される。

**hero の move=explore が操作切替後に動作しない問題**
- **原因**: `hero` は `PlayerController` のみが管理しており `UnitAI` が存在しなかった。`is_player_controlled = false` になっても `current_order` を読んで行動する AI がなかった。
- **修正**:
  - `PartyManager.setup_adopted(member, player, map_data)` を追加（スポーンなしで既存キャラを AI 管理下に置く）。
  - `UnitAI._is_passable()` に `_player != _member` ガードを追加（hero の自己AI がタイルを自分でブロックしないように）。
  - `game_map._setup_hero()` で `NpcManager`（`_hero_manager`）を生成し、`setup_adopted(hero, hero, map_data)` → `activate()` で AI を起動。
  - `game_map._link_all_character_lists()` で `_hero_manager.set_all_members()` と `set_enemy_list()` を配布。
  - `game_map._setup_vision_system()` で `_hero_manager.set_vision_system()` を配布。
  - `hero.is_friendly = true` を設定（`_assign_orders()` で `current_order.move` を反映させるために必要）。

### 未実装（今後）
- 統率力・従順度パラメータの実際の影響（値は保持済み）

## Phase 8 Step 1: 未実装行動の追加 ✅ 実装済み

### 新規ファイル
| ファイル | 役割 |
|---------|------|
| `scripts/dive_effect.gd` | 降下攻撃エフェクト（空色→白フラッシュ円アニメーション） |
| `assets/master/enemies/harpy.json` | ハーピーのマスターデータ（dive・is_flying=true） |
| `assets/master/enemies/dark_priest.json` | ダークプリーストのマスターデータ（ranged・回復・バフ） |

### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character_data.gd` | `max_mp`, `attack_type`, `attack_range`, `heal_power`, `heal_mp_cost`, `buff_mp_cost` フィールド追加 |
| `scripts/character.gd` | `mp`, `max_mp`, `defense_buff_timer` フィールド追加。`use_mp()`, `heal()`, `apply_defense_buff()`, `get_effective_defense()` メソッド追加。`take_damage()` がバフ込み防御力を使用 |
| `scripts/unit_ai.gd` | 攻撃タイプ対応・飛行移動・回復/バフ行動実装 |
| `scripts/party_leader_ai.gd` | 回復/バフ専用キャラに Strategy.WAIT を渡すロジック追加 |
| `assets/master/enemies/enemies_list.json` | harpy, dark_priest を追加 |

### 飛行移動仕様

飛行キャラ（`is_flying = true`）は WALL・OBSTACLE・地上キャラ占有タイルを通過できる。
飛行同士はブロックし合う（`_is_passable()` 内でレイヤー一致のみ占有チェック）。

### 攻撃タイプ（CharacterData.attack_type）

| タイプ | 区分 | カウンター | 攻撃可能な対象 |
|--------|------|-----------|-------------|
| `melee` | 近接 | 有効 | 地上のみ（地上→飛行NG、飛行→飛行NG）|
| `ranged` | 遠距離 | 無効 | 飛行・地上両方（射程: attack_range タイル） |
| `dive` | 降下 | 有効 | 地上のみ・飛行キャラが使用（方向倍率なし） |

カウンター実装は将来予定。現在はタイプ区別のみ。

### UnitAI の攻撃タイプ対応

- `_get_attack_type()`: CharacterData.attack_type を返す
- `_can_attack_target(target, atype)`: タイプ別の攻撃可否判定
  - melee: 隣接距離1 かつ target.is_flying == false
  - ranged: マンハッタン距離 ≤ attack_range
  - dive: 隣接距離1 かつ target.is_flying == false（攻撃者は飛行）
- `_calc_attack_goal()`: ranged の場合は `_find_ranged_goal()` で射程内最近傍へ
- `_execute_attack()`: タイプに応じてダメージ計算
  - melee: 方向倍率あり
  - ranged: Projectile を生成
  - dive: 方向倍率なし + DiveEffect 表示

### 回復・バフ行動

`_generate_queue()` の先頭で `_generate_heal_queue()` → `_generate_buff_queue()` を評価し、
発動条件を満たしていれば戦略より優先してキューに積む。

**回復行動（heal_power > 0 のキャラ）**
- 発動条件: パーティー内に HP50% 以下のメンバーがいる かつ mp >= heal_mp_cost
- 対象: is_friendly == true のメンバーで最もHPが低いキャラ
- 射程: attack_range タイル（隣接 or 遠距離は JSON で設定）
- アクション: `move_to_heal` → `heal`（MPを消費してtgt.heal(heal_power)）

**バフ行動（buff_mp_cost > 0 のキャラ）**
- 発動条件: バフが切れているメンバーがいる かつ mp >= buff_mp_cost
- 対象: defense_buff_timer <= 0.0 の is_friendly == true メンバー
- アクション: `move_to_buff` → `buff`（MPを消費してtgt.apply_defense_buff()）

**防御バフの仕様（Character クラス）**
- `DEFENSE_BUFF_BONUS = 3`（加算）
- `DEFENSE_BUFF_DURATION = 10.0`（秒）
- `take_damage()` が `get_effective_defense()` を呼び、バフ込み防御力でダメージ計算

**LeaderAI の扱い**
- `heal_power > 0` または `buff_mp_cost > 0` のキャラは `_assign_orders()` で常に `Strategy.WAIT` を渡す
- UnitAI._generate_queue() の先頭チェックが回復/バフを優先実行する

### DiveEffect（降下攻撃エフェクト）

空色→白のフラッシュ円が上から落下して 0.4 秒で消えるアニメーション。
羽ばたきを表す斜め線2本も描画。`z_index = 3`。

### ハーピーのマスターデータ

```json
{ "attack_type": "dive", "is_flying": true, "attack_range": 1, ... }
```

グラフィックは仮素材（後で差し替え予定）。飛行中は地上からの近接攻撃を受けない。

### ダークプリーストのマスターデータ

```json
{ "attack_type": "ranged", "attack_range": 4, "mp": 30,
  "heal_power": 10, "heal_mp_cost": 5, "buff_mp_cost": 8, ... }
```

## Phase 8 Step 2+3: 種族別AIルーチン・ダンジョン生成組み込み ✅ 実装済み

### UnitAI への追加（unit_ai.gd）
- `_get_move_interval() -> float`: 移動間隔の仮想メソッド（デフォルト=MOVE_INTERVAL/game_speed=1.2秒÷倍率）
- `_on_after_attack() -> void`: 攻撃後フック（MP消費などに使用）
- `_execute_attack()` から `_on_after_attack()` を呼び出すよう修正

### 新規 LeaderAI ファイル
| ファイル | 種族 | 特徴 |
|---------|------|------|
| default_leader_ai.gd | 汎用（ゴブリン以外） | 逃走しない。_create_unit_ai() でcharacter_idから種別UnitAIを生成 |
| hobgoblin_leader_ai.gd | hobgoblin | 絶対逃走しない。混成パーティー（hobgoblin+goblin）対応 |
| wolf_leader_ai.gd | wolf | 50%生存割れで逃走。WolfUnitAI を生成 |

### 新規 UnitAI ファイル
| ファイル | 種族 | 主な特徴 |
|---------|------|---------|
| hobgoblin_unit_ai.gd | hobgoblin | 絶対逃走しない、melee正面突進 |
| goblin_archer_unit_ai.gd | goblin-archer | HP<30%逃走、MIN_CLOSE_RANGE(2)以下で後退 |
| goblin_mage_unit_ai.gd | goblin-mage | HP<30%逃走、MP消費(2/攻撃)、MP不足でWAIT |
| zombie_unit_ai.gd | zombie | 逃走しない、DIRECT経路、移動2倍遅い |
| wolf_unit_ai.gd | wolf | ASTAR_FLANK(側面回り込み)、移動0.67倍速い |
| harpy_unit_ai.gd | harpy | 逃走しない、dive攻撃（UnitAI基底で処理済み） |
| salamander_unit_ai.gd | salamander | 逃走しない、MIN_CLOSE_RANGE(2)以下で後退 |
| dark_knight_unit_ai.gd | dark-knight | 逃走しない、melee正面突進 |
| dark_mage_unit_ai.gd | dark-mage | 逃走しない、MP消費(2/攻撃)、MP不足でWAIT |
| dark_priest_unit_ai.gd | dark-priest | 逃走しない（WAIT維持）、heal/buffはUnitAI基底で自動処理 |

### 新規 JSON マスターデータ
| ファイル | id | rank | 特徴 |
|---------|-----|------|------|
| hobgoblin.json | hobgoblin | A | HP:45 ATK:12 DEF:4 melee |
| goblin_archer.json | goblin-archer | C | HP:18 ATK:6 ranged range:5 |
| goblin_mage.json | goblin-mage | C | HP:15 ATK:9 MP:20 ranged range:5 |
| zombie.json | zombie | C | HP:35 ATK:6 melee（遅・直進） |
| wolf.json | wolf | C | HP:22 ATK:9 melee（速・側面） |
| salamander.json | salamander | B | HP:28 ATK:10 ranged range:4 |
| dark_knight.json | dark-knight | A | HP:55 ATK:14 DEF:6 melee |
| dark_mage.json | dark-mage | B | HP:22 ATK:12 MP:30 ranged range:5 |

### party_manager._create_leader_ai() 更新
```gdscript
match char_id:
    "goblin"    → GoblinLeaderAI
    "hobgoblin" → HobgoblinLeaderAI
    "wolf"      → WolfLeaderAI
    _           → EnemyLeaderAI（goblin-archer, goblin-mage, zombie, harpy, salamander, dark-knight, dark-mage, dark-priest）
```

### dungeon_handcrafted.json 更新
- 11種の敵に対応（Claude Code が手作りで更新）
- フロア別配置ガイドライン（浅い層：goblin/zombie/wolf中心、深い層：dark系中心）を反映
- 旧 dungeon_handcrafted.json を削除（後続バグ修正で再作成・内容を刷新）

## Phase 8 バグ修正 ✅ 実装済み

### 敵グラフィック非表示バグ
`_spawn_member()` がハイフン区切りの enemy_id（例: "goblin-mage"）でJSONファイルをそのまま検索していたため、アンダーバー区切りのファイル（goblin_mage.json）が見つからずプレースホルダー色で表示されていた。

**修正（party_manager.gd）**
```gdscript
var file_name := char_id.replace("-", "_") + ".json"
member.character_data = CharacterData.load_from_json(
    "res://assets/master/enemies/" + file_name
)
```

### dark_priest.json id 不一致
dark_priest.json の `"id": "dark_priest"` がアンダーバーだったため、`apply_enemy_graphics("dark_priest")` が画像フォルダ `dark-priest_...`（ハイフン）を見つけられずプレースホルダー表示になっていた。

**修正**: `"id": "dark-priest"` に変更（フォルダ名と一致）

### dungeon_handcrafted.json 再作成
Phase 8 Step 3 で削除した手作りダンジョンを再作成。Claude Code が管理するデフォルトダンジョンとして使用。

**読み込み（game_map.gd）**
- 起動時に `dungeon_handcrafted.json` を直接読み込む
- 読み込み失敗時は `dungeon_01.json` にフォールバック

**dungeon_handcrafted.json 構成（6部屋1フロア）**
| 部屋ID | 名前 | 内容 |
|--------|------|------|
| r1_1 | 廃墟の入口 | プレイヤー3人（hero, archer, healer）スタート |
| r1_2 | ゴブリンの集会所 | goblin×3 + goblin-archer×1 |
| r1_3 | 狼の縄張り | wolf×4 |
| r1_4 | ゾンビの霊廟 | zombie×2 + NPC（fighter-sword + healer） |
| r1_5 | 魔術師の書斎 | hobgoblin×1 + goblin×2 + goblin-mage×1 |
| r1_6 | 闇の司令室 | dark-knight + dark-mage + dark-priest + salamander |

## Phase 9: 操作感・表現強化

### Phase 9-1: 歩行アニメーション・滑らか移動 ✅ 完了
詳細仕様: 本ファイルの「歩行アニメーション仕様」節を参照。

### Phase 9-2: ゲームパッド対応 ✅ 完了
詳細仕様: 本ファイルの「ゲームパッド対応仕様」節を参照。

### Phase 9-3: 飛翔体グラフィック

#### 画像ファイル
```
assets/images/effects/
  arrow.png        矢（弓使い・ゴブリンアーチャー）
  fire_bullet.png  火弾（魔法使い(火)・ゴブリンメイジ・サラマンダー）
  water_bullet.png 水弾（魔法使い(水)・リッチ）
  thunder_bullet.png 雷弾（デーモン）
  whirlpool.png    渦（水魔法スタンエフェクト）
```
- 当面は magic_bullet.png と flame.png は同じ画像でも可

#### Projectile（projectile.gd）の変更点
- `image_path: String` フィールド追加（`CharacterData.attack_type` と `character_id` から決定）
- `_ready()` で画像ロード。ファイルなしの場合は既存の黄色円フォールバックを維持
- `rotation` を速度ベクトルの角度に合わせて設定（飛行方向に向ける）

#### 飛翔体画像の決定ロジック
```
character_id が "goblin-archer" or class_id が "archer" → arrow.png
attack_type が "magic" → magic_bullet.png
character_id が "salamander" → flame.png
それ以外の ranged → magic_bullet.png（フォールバック）
```

#### 飛翔体なし（回復・バフ）
- ヒーラー・ダークプリーストの回復/バフは飛翔体を生成しない
- 将来的に別途エフェクト（光の輪など）を追加予定

### Phase 9-4: 効果音

#### 使用アセット
- Kenney 等の CC0 アセットを使用
- 採用したアセットは CLAUDE.md のライセンステーブルに追加する

#### AudioManager（audio_manager.gd）
- Autoload として登録
- `play_sfx(sfx_name: String)` でワンショット再生
- 音源ファイルは `assets/audio/sfx/` 以下に配置

#### 効果音一覧
| sfx_name | タイミング |
|---------|---------|
| `attack_slash` | 近接攻撃発動（剣士・斥候） |
| `attack_axe` | 近接攻撃発動（斧戦士） |
| `attack_shoot` | 弓発射 |
| `attack_magic` | 魔法弾発射 |
| `attack_flame` | 炎発射 |
| `hit_physical` | 物理攻撃命中 |
| `hit_magic` | 魔法攻撃命中 |
| `damaged` | ダメージを受けた |
| `die` | 死亡 |
| `heal` | 回復 |
| `room_enter` | 部屋に入った |
| `item_get` | アイテム取得 |
| `stairs` | 階段を使った |

- BGMは将来実装（当面なし）

---

## Phase 10: アイテム・装備システム（未実装）

詳細仕様: 本ファイルの「アイテムシステム詳細仕様」節・「ステータス仕様更新」節を参照。

### Phase 10-1: アイテムデータ基盤 ✅ 完了

#### ステータスフィールド統合（フェーズ10-1の範囲）

| 変更前 | 変更後 | 型 | 説明 |
|--------|--------|-----|------|
| `attack` | `attack_power` | int | 物理攻撃力（melee/ranged 共用。Phase 10-2 で分離） |
| `heal_power` | `magic_power` | int | 魔法攻撃力＋回復力の統合値（Phase 10-2 で分離） |
| （なし） | `accuracy` | float | 命中精度（0.0 固定。Phase 10-2 で有効化） |
| （なし） | `inventory` | Array | アイテムインスタンスの辞書リスト |
| `attack_type` 値 | "magic" 追加 | String | goblin-mage/dark-mage/salamander/dark-priest に適用 |

- `last_attacker: Character` を `character.gd` に追加（ドロップ帰属追跡）
- `take_damage(raw, mult, attacker=null)` に attacker パラメータ追加
- `magic_power` を使用するキャラの attack_type は "magic"。damage 計算で `magic_power` を参照
- ヒーラー（attack_type="heal"）は攻撃しない。回復行動は `magic_power` を使用
- クラス JSON: `base_attack_power`（物理系）または `base_magic_power`（魔法/回復系）で記述
  - healer.json: `base_magic_power: 30`（ゼロではないので実際に回復できる）

#### 新規ファイル
```
assets/master/items/
  sword.json / axe.json / bow.json / dagger.json / staff.json
  armor_plate.json / armor_cloth.json / armor_robe.json
  shield.json
  potion_hp.json / potion_mp.json
```
- ItemData は辞書（Dictionary）として character.inventory に格納（専用 GDScript クラスは Phase 10-2 で実装）

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character_data.gd` | `attack_power`, `magic_power`, `accuracy` フィールド追加; `inventory: Array` 追加 |
| `scripts/character.gd` | `attack_power`, `magic_power`; `last_attacker: Character`; `take_damage()` に attacker param |
| `scripts/unit_ai.gd` | attack_type=="magic" → `magic_power`; それ以外 → `attack_power` |
| `scripts/player_controller.gd` | `attack` → `attack_power` |
| `scripts/base_ai.gd` | `attack` → `attack_power` |
| `scripts/enemy_ai.gd` | `attack` → `attack_power` |
| `scripts/character_generator.gd` | `base_attack_power`/`base_magic_power` を読んで `attack_power`/`magic_power` を設定 |
| `scripts/party_leader_ai.gd` | `heal_power` → `magic_power` |
| `scripts/order_window.gd` | `attack` → `attack_power`; `heal_power` → `magic_power`; inventory 表示 |
| `assets/master/classes/*.json` | `base_attack` → `base_attack_power`/`base_magic_power` |
| `assets/master/enemies/*.json` | `attack` → `attack_power`/`magic_power`; magic 系に `"attack_type":"magic"` |
| `assets/master/maps/dungeon_handcrafted.json` | 各 enemy_party に `items` 配列追加 |
| `scripts/dungeon_builder.gd` | `_build_spawn_data()` で items を enemy_party に通す |
| `scripts/party_manager.gd` | `signal party_wiped(items, killer)` 追加（後に `room_id` 方式に変更。下記参照） |
| `scripts/game_map.gd` | `_floor_items` で床散布管理; `_check_item_pickup()` で自動取得; `_draw()` でアイテムマーカー描画 |

### Phase 10-2: 装備システム ✅ 完了

#### 耐性ステータスの追加

- `CharacterData` に `physical_resistance: float`・`magic_resistance: float`・`defense_accuracy: float` を追加
- クラス JSON（assets/master/classes/*.json）に `base_physical_resistance`・`base_magic_resistance` を追加
- 敵 JSON（assets/master/enemies/*.json）にも同フィールドを追加
- `CharacterGenerator._calc_stats()` で defense_mult を使って耐性計算（能力値 = int(基準値 × 補正)）
- 耐性は能力値（整数）で管理。軽減率への変換: `resistance_to_ratio(score) = score / (score + 100.0)`
- `CharacterData.get_total_physical_resistance_score()` / `get_total_magic_resistance_score()`: 素値＋装備補正の能力値合計
- `CharacterData.get_total_physical_resistance()` / `get_total_magic_resistance()`: 変換後の軽減率を返す

#### 初期装備の付与

- `CharacterData.apply_initial_items(items: Array)`: items から `equipped: true` のものを装備スロットにセット
- `CharacterData._equip_item(item)`: category に応じて equipped_weapon / equipped_armor / equipped_shield にセット
- `dungeon_handcrafted.json` の player_party・npc_party メンバーに `items` フィールドで初期装備を定義
- `game_map._setup_hero()` と `npc_manager.setup()` が `apply_initial_items()` を呼び出す

#### ダメージ計算への装備補正反映

`character.gd` の `take_damage(raw, mult, attacker=null, attack_is_magic=false)` を全面改訂:

1. **攻撃方向判定**（`_calc_attack_direction(attacker)`）
   - atan2 で攻撃者→防御者方向角と防御者向き角の差を計算
   - 正面 ±45°→ "front"、背面 ±45°→ "back"、右 ±45°→ "right"、左→ "left"
   - 背面攻撃は防御判定をスキップ
2. **防御判定**（`defense_accuracy` で各フィールドを独立してロール）
   - `block_right_front`：正面・右側面で有効　`block_left_front`：正面・左側面で有効　`block_front`：正面のみ有効
   - 成功したフィールドの合計値をダメージからカット / 背面: 0（スキップ）
3. **耐性適用**（物理 or 魔法耐性で割合軽減）
   - 残ダメージ × (1 - resistance)。最低 1 ダメージ保証

- `player_controller._execute_ranged()`: is_magic フラグを `_spawn_projectile()` に渡す
- `unit_ai._execute_attack()` ranged/magic: `is_magic = (atype == "magic")` を projectile に渡す
- `projectile.gd.setup()`: attacker・is_magic 引数追加。着弾時に `take_damage(d, m, attacker, is_magic)` を呼ぶ

#### ドロップ処理（部屋制圧方式・床散布）

- `party_manager.gd`:
  - `signal party_wiped(items: Array, room_id: String)` に変更（旧: `killer: Character`）
  - `_room_id: String` を追加。`setup()` 時に最初のスポーン位置から `map_data.get_area()` で部屋IDを取得
  - 全滅時に `party_wiped.emit(_drop_items, _room_id)` を発火
- `game_map.gd`:
  - `_floor_items: Dictionary = {}` 追加（Vector2i → item Dictionary、1マス1個）
  - `_on_enemy_party_wiped(items, room_id)`:
    - `map_data.get_tiles_in_area(room_id)` で部屋のFLOORタイル一覧を取得
    - `candidates.shuffle()` 後、アイテム数分だけ `_floor_items` に1個ずつ配置
    - メッセージ「アイテムが部屋に散らばった！（N個）」を表示
  - `_check_item_pickup()`: `_process()` から毎フレーム呼び出し
    - パーティー全メンバーの `grid_pos` を `_floor_items` のキーと照合
    - `item_pickup == "avoid"` かつ AI 制御中はスキップ
    - 該当マスのアイテムを `inventory.append()`、`_floor_items.erase()`、メッセージ表示
  - `_draw()` でフロアアイテムを黄色マーカー（50%サイズの矩形）で描画。ビジョン外は非表示
  - `_check_item_pickup()` は `party.sorted_members()`（合流済みメンバー全員）を毎フレームチェックし、同マスのアイテムを自動取得する（`item_pickup == "avoid"` 時のみスキップ）

#### UnitAI アイテム取得ナビゲーション（合流済みメンバー専用）

- `unit_ai.gd` に `_item_pickup: String` / `_all_floor_items: Dictionary` フィールドを追加
- `receive_order()` で `item_pickup` キーを受け取り `_item_pickup` に格納
- `set_floor_items(items: Dictionary)`: `_all_floor_items` に `_floor_items` 参照をセット（Dictionary は参照型のため以降の更新が自動反映される）
- `_find_item_pickup_target() -> Vector2i`: `_item_pickup` に応じて目標アイテム座標を返す
  - `"aggressive"`: 同一部屋のアイテムのみ対象（通路にいる場合は対象外）
  - `"passive"`: `GlobalConstants.ITEM_PICKUP_RANGE`（=2）マス以内のアイテムのみ対象
  - `"avoid"`: 常に `(-1,-1)` を返す
- `_generate_queue()` の `Strategy.WAIT` ブランチ先頭でアイテムターゲットを確認し、見つかればそこへ向かう `move_to_explore` アクションを生成（`Strategy.ATTACK` / `Strategy.FLEE` 時は行わない）
- `party_leader_ai.set_floor_items()`: 全 UnitAI に配布
- `party_manager.set_floor_items()`: LeaderAI へのパススルー
- `game_map.gd` で設定タイミング：
  - `_setup_hero()` 後に `_hero_manager.set_floor_items(_floor_items)`
  - `_merge_npc_into_player_party()` / `_merge_player_into_npc_party()` で `nm.set_floor_items(_floor_items)`

#### item_pickup 指示の追加

- `Character.current_order` に `"item_pickup": "aggressive"` をデフォルト追加
- `OrderWindow.COL_OPTIONS/COL_LABELS/COL_HEADERS/COL_KEYS` に 6 列目として取得指示を追加
  - aggressive=積極的に拾う / passive=近くのみ / avoid=拾わない
- `PRESET_TABLE` に item_pickup 列を追加（全 6 preset 更新）
- `_apply_preset()` で item_pickup を current_order に反映
- `LeftPanel` 行2: 隊形+低HP+取得 の 3 略称表示に変更

#### OrderWindow 改修（Phase 10-2 追加分）

- **6a: 名前列サブメニュー + アイテム画面**
  - 「操作」列を削除。名前列（col 0）をインタラクティブ化
  - Z 押下でサブメニュー表示（操作切替 / アイテム）
  - `_submenu_open / _submenu_cursor` で状態管理
  - `_execute_submenu()` で操作切替を実行; アイテムは `_item_mode = ITEM_LIST` に遷移
  - `_get_col_xs()` から control_r（0.10）を削除、name_r を 0.22 に拡大
  - **アイテム画面の状態遷移（`_ItemMode` enum）**
    - `OFF` → `ITEM_LIST`（未装備品一覧）→ `ACTION_MENU`（装備する/渡す）→ `TRANSFER_SELECT`（渡す相手）
    - 各状態で Esc を押すと1つ前の状態に戻る。`close_window()` で OFF にリセット
  - **主要メソッド**
    - `_handle_item_input()`: 各 _ItemMode の入力処理（`_handle_input()` 内で最初に分岐）
    - `_get_unequipped_items(ch)`: `is_same()` で装備スロット参照と比較し未装備品を抽出
    - `_can_equip(ch, item)`: `CLASS_EQUIP_TYPES` 定数でクラス vs item_type を照合
    - `_build_action_items(ch, item)`: 「装備する」（can_equip 時）/ 「渡す」（リーダー操作中 かつ 他メンバーあり）
    - `_do_equip(ch, item)`: category に応じた装備スロットに item 参照をセット（inventory は変更しない。旧スロット参照を外すことで旧装備は自動的に未装備扱いになる）
    - `_do_transfer(from_ch, to_ch, item)`: `from_ch.inventory.erase(item)` → `to_ch.inventory.append(item)`
    - `_get_transfer_targets()`: `_item_char` 以外の有効パーティーメンバー
    - `_get_char_name(ch)`: character_name 優先の表示名ヘルパー
  - **描画（オーバーレイ方式）**
    - `_draw_item_overlay()`: _item_mode に応じて3つのサブ関数に委譲
    - `_draw_item_list_overlay()`: 未装備品一覧。装備可能アイテムは ◆ マーク、名前+カテゴリ+補正値サマリを表示
    - `_draw_action_menu_overlay()`: 「装備する / 渡す」のリスト
    - `_draw_transfer_select_overlay()`: 渡す相手一覧（所持件数を表示）
  - **`CLASS_EQUIP_TYPES` 定数**（クラスID → 許可 item_type 配列）
    - fighter-sword: [sword, armor_plate, shield]
    - fighter-axe: [axe, armor_plate, shield]
    - archer: [bow, armor_cloth]
    - scout: [dagger, armor_cloth]
    - magician-fire: [staff, armor_robe]
    - healer: [staff, armor_robe]
- **6b: ステータス行の追加**
  - `_get_stat_rows()` に物理耐性・魔法耐性行を追加（`"pct"` type: 0-100% 表示）
  - 攻撃力・魔法力の bonus に `get_weapon_attack_bonus()` / `get_weapon_magic_bonus()` を反映
  - stat 描画に `"pct"` ケースを追加（素値%・補正値%・最終値% 表示）
- **6c: ログ行**
  - 「閉じる」行を「ログ」行に変更（`_FocusArea.CLOSE` = ログ行）
  - Z 押下でログモード（`_log_mode = true`）に入り最新エントリ位置にスクロール
  - ログモード中 ↑↓ でスクロール、Z/Enter/Esc でログモード終了
  - `MessageWindow.log_entries: Array[String]`（最大 50 件）を追加。`show_message()` 呼び出し時に自動追記

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character_data.gd` | `physical_resistance`, `magic_resistance`, `defense_accuracy`, `equipped_weapon/armor/shield`, `inventory` 追加; `apply_initial_items()`, `_equip_item()`, `get_weapon_*_bonus()`, `get_total_*_resistance()` 追加 |
| `scripts/character_generator.gd` | `_calc_stats()` で耐性計算追加。`generate_character()` でクラス JSON から耐性読み込み |
| `scripts/character.gd` | `take_damage()` 全面改訂（atan2方向判定・防御強度カット・耐性軽減）; `_calc_attack_direction()`, `_calc_block_power()` 追加 |
| `scripts/projectile.gd` | `setup()` に attacker・is_magic 引数追加; `_on_arrive()` で `take_damage(d, m, attacker, is_magic)` 呼び出し |
| `scripts/player_controller.gd` | `_execute_melee/ranged()` から方向倍率を削除; is_magic フラグを take_damage/projectile に渡す |
| `scripts/unit_ai.gd` | ranged/magic projectile に `_member`・`is_magic` を渡す |
| `scripts/order_window.gd` | 名前列サブメニュー・アイテム画面（ITEM_LIST/ACTION_MENU/TRANSFER_SELECT）・物理/魔法耐性行・ログ行追加; 操作列削除 |
| `scripts/left_panel.gd` | 行2 を「隊形+低HP+取得」の3略称に変更 |
| `scripts/message_window.gd` | `log_entries: Array[String]` 追加; `show_message()` で自動追記 |
| `scripts/game_map.gd` | `_on_enemy_party_wiped()` で MessageWindow 通知; `order_window.setup(party, message_window)` |
| `scripts/npc_manager.gd` | `setup()` で `apply_initial_items()` 呼び出し |
| `assets/master/classes/*.json` | `base_physical_resistance`, `base_magic_resistance` 追加 |
| `assets/master/enemies/*.json` | `physical_resistance`, `magic_resistance` 追加 |
| `assets/master/maps/dungeon_handcrafted.json` | player_party メンバーに初期装備 items フィールド追加 |

### 操作体系の刷新 ✅ 完了（Phase 10-2 と同時実施）

#### 概要
攻撃を Z/X の2ボタンから Z/A の1ボタンに統合し、X/B をメニュー戻るとして再割り当て。
合わせてメニュー内のナビゲーションを左/右キーで統一。

#### InputMap 変更（project.godot）
| 変更内容 | 旧 | 新 |
|---------|-----|-----|
| `attack_melee` → `attack` | Z + Joypad 0（A） | Z + Joypad 0（A）（名称変更） |
| `attack_ranged` → 削除 | X + Joypad 2（X） | — |
| `menu_back` → 新規追加 | — | X + Joypad 1（B） |

#### player_controller.gd
- `AttackSlot` enum を `{ Z, X }` → `{ Z }` のみに縮小（X関連フィールドをすべて削除）
- 削除: `DEFAULT_SLOT_X`、`_slot_x`、`_attack_slot` フィールド
- `_process_normal()`: `attack_ranged` チェック削除。`attack` 1アクションのみ
- `_enter_targeting()`: 引数 `slot: AttackSlot` を削除。常に `_get_slot()` から slot Z を使用
- `_is_slot_held()`: `Input.is_action_pressed("attack")` のみを返す（シンプル化）
- `_get_slot()`: `_slot_x` 廃止。`_slot_z` を返すだけ（空なら `DEFAULT_SLOT_Z` を返す）
- `_load_class_slots()`: `_slot_x` 初期化・X スロット読み込みを削除

#### order_window.gd
- `attack_melee` → `attack` に全置換
- 名前列（col 0）の左右キー:
  - 右キー: サブメニューを開く（Z/accept と同等）
  - 左キー: ウィンドウを閉じる
- 指示列（col 1-6）の左キー: 従来通り列移動（変更なし）
- サブメニュー: `ui_right` = 決定、`ui_left` / `menu_back` = 閉じる
- アイテム画面（ITEM_LIST / ACTION_MENU / TRANSFER_SELECT）:
  - `ui_right` = 決定（`attack` / `ui_accept` と同等）
  - `ui_left` / `menu_back` = 1つ前の状態に戻る
- ログ行（CLOSE エリア）:
  - `ui_right` / `attack` = ログスクロールモード開始
  - `ui_left` / `menu_back` = ウィンドウを閉じる
- ログスクロールモード: `menu_back` でモード終了（`ui_cancel` と同等）

#### dialogue_window.gd
- `attack_melee` → `attack` に変更
- `ui_right` = 選択確定（`attack` / `ui_accept` と同等）
- `ui_left` / `menu_back` = 会話ウィンドウを閉じる
- ヒントテキスト: `↑↓ : 選択    Z / 右 : 決定    X / 左 / Esc : 閉じる`

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `project.godot` | attack_melee → attack、attack_ranged 削除、menu_back 追加 |
| `scripts/player_controller.gd` | AttackSlot.X / _slot_x / DEFAULT_SLOT_X 削除; 1ボタン統合 |
| `scripts/order_window.gd` | attack → attack に全置換; 左/右キーナビゲーション追加 |
| `scripts/dialogue_window.gd` | attack → attack に変更; 左/右キーナビゲーション追加 |

---

### MessageWindow拡張・AIデバッグパネル廃止（Phase 10-2 準備） ✅ 完了

#### 概要
- RightPanel からAIデバッグ表示（下半分）を削除。敵情報表示のみ残す
- MessageWindow をフィールド画面下部5行固定表示にリファクタリング
- MessageLog（Autoload）を新設し、MessageWindow と OrderWindow でログバッファを共有
- F1キーを MessageLog のデバッグメッセージ表示トグルに転用

#### 新規ファイル
| ファイル | 役割 |
|---------|------|
| `scripts/message_log.gd` | メッセージログ管理（Autoload）。メッセージ種別・色分け・デバッグフィルタ |

#### メッセージ種別
| 種別 | enum | 色 | デバッグ専用 | 用途 |
|------|------|-----|------------|------|
| システム | SYSTEM | 白 | No | エリア入室、アイテム取得、会話イベント等 |
| 戦闘計算 | COMBAT | 黄 | Yes | 攻撃・回復の計算過程 |
| AI戦略変更 | AI | 水色 | Yes | リーダーAIの全体指示変更時 |

- `debug_visible: bool = true`（デフォルトON）で COMBAT / AI の表示を制御
- `get_visible_entries()` でフィルタ済みエントリを返す
- `entry_added` シグナルで MessageWindow / OrderWindow に再描画を通知

#### MessageWindow 変更内容
- フィールド画面下部に固定サイズ・5行表示・半透明背景で常時表示
- 最新メッセージに自動スクロール
- `show_message()` は後方互換として `MessageLog.add_system()` に委譲
- `log_entries` プロパティは後方互換として `MessageLog.get_visible_entries()` のテキスト配列を返す

#### RightPanel 変更内容
- `toggle_debug()` メソッド削除
- `_debug_visible` フラグ削除
- `_draw_debug_section()` メソッド削除
- 敵情報表示はパネル全高を使用

#### OrderWindow 変更内容
- ログ行が `MessageLog.get_visible_entries()` を直接参照（色分け対応）
- アイテム装備・受け渡しメッセージを `MessageLog.add_system()` に直接出力

#### game_map.gd 変更内容
- F1キーハンドラ: `right_panel.toggle_debug()` → `MessageLog.toggle_debug()`

#### Strategy enum 拡張
- `PartyLeaderAI.Strategy` に `EXPLORE = 4` を追加
  - パーティーレベル専用（UnitAI には `ATTACK` + `move=explore` に変換して渡す）
  - `_assign_orders()` で EXPLORE 戦略時に `effective_strat = ATTACK`、`move_policy = "explore"` を設定
  - DEFEND/EXPLORE 等の UnitAI 未対応値は WAIT に安全に変換（デフォルトケース）

#### NPC/敵パーティーのデフォルト戦略
- NPC パーティー（NpcLeaderAI）：敵なし時 `WAIT` → `EXPLORE` に変更（探索行動）
- 敵パーティー：`WAIT` のまま（VisionSystem でアクティブ化時に `ATTACK` に遷移）

#### AI戦略変更ログ
- `party_leader_ai.gd` に `_prev_strategy` フィールド追加（変更検出用）
- `_assign_orders()` で戦略変更時に `_log_strategy_change(old_strategy)` を呼び出し
- ログフォーマット: `[AI] {リーダー名}: {旧プリセット}→{新プリセット}（{理由}）`
  - 例: `[AI] ゴブリン: 待機→攻撃（敵発見）`
- サブクラスが `_get_strategy_change_reason()` をオーバーライドして理由を提供
  - GoblinLeaderAI / WolfLeaderAI: FLEE → "仲間50%以下"
  - NpcLeaderAI: ATTACK → "敵を検知"、EXPLORE → "敵なし・周辺探索"

#### ログ抑制
- `PartyLeaderAI.log_enabled: bool = true`: false でログ出力を抑制
- `PartyManager.suppress_ai_log: bool = false`: true なら `_start_ai()` で leader_ai.log_enabled = false を設定
- `_has_player_controlled_member()`: プレイヤー操作中メンバーがいるパーティーのログを抑制
- 適用箇所:
  - `_hero_manager`: suppress_ai_log = true（プレイヤー操作中はログ不要）
  - 初期仲間の一時 NpcManager: suppress_ai_log = true（合流前のログ抑制）

#### 戦闘計算ログ（暫定）
- `character.gd._log_damage()`: take_damage の計算過程をログ出力
  - フォーマット: `{攻撃者} → {対象}: 攻撃力{値} / 方向:{方向}→{防御結果} / 耐性{値}%→最終{ダメージ}`
- `character.gd.log_heal()`: 回復ログを出力（unit_ai から呼び出し）
  - フォーマット: `{回復者} → {対象}: 回復 魔力{値} → HP{回復前}→{回復後}`
- 装備補正はパラメータに事前反映する方式のため、ログには武器名・装備補正の内訳を表示しない

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/message_log.gd` | 新規: Autoload。メッセージ種別・色分け・デバッグフィルタ |
| `scripts/message_window.gd` | 全面改訂: 固定5行表示・MessageLog 参照 |
| `scripts/right_panel.gd` | AIデバッグ表示削除。敵情報のみ |
| `scripts/order_window.gd` | ログ行を MessageLog 参照に変更・色分け対応 |
| `scripts/game_map.gd` | F1 → MessageLog.toggle_debug(); hero_manager・初期仲間の suppress_ai_log 設定 |
| `scripts/party_manager.gd` | suppress_ai_log フラグ追加; _start_ai() で leader_ai.log_enabled に反映 |
| `scripts/party_leader_ai.gd` | Strategy.EXPLORE 追加; log_enabled・_has_player_controlled_member()・_log_strategy_change(old)・_get_strategy_change_reason(); EXPLORE 時の move_policy 変換 |
| `scripts/goblin_leader_ai.gd` | _get_strategy_change_reason() オーバーライド |
| `scripts/wolf_leader_ai.gd` | _get_strategy_change_reason() オーバーライド |
| `scripts/npc_leader_ai.gd` | デフォルト戦略 WAIT→EXPLORE; _get_strategy_change_reason() オーバーライド |
| `scripts/character.gd` | _log_damage()・log_heal()・_char_display_name()・_dir_to_jp() 追加 |
| `scripts/unit_ai.gd` | heal 実行時に log_heal() 呼び出し追加 |
| `project.godot` | MessageLog Autoload 追加 |

### 全キャラクター常時行動化（Phase 10-2 準備） ✅ 完了

#### 概要
- NPC パーティーをゲーム開始時に即座にアクティブ化（探索行動を開始）
- 敵パーティーはプレイヤー or NPC が部屋に入ったらアクティブ化
- デバッグログ（combat/ai）をプレイヤーのいるエリアに限定

#### アクティブ化ルール
| パーティー種別 | アクティブ化タイミング | デフォルト行動 |
|--------------|---------------------|-------------|
| プレイヤー | 常時アクティブ | — |
| NPC | ゲーム開始時（`_setup_vision_system()` 末尾で `activate()`） | EXPLORE |
| 敵 | フレンドリーキャラが部屋に入ったとき | WAIT → ATTACK |

#### 実装詳細

**NPC即時アクティブ化**
- `game_map._setup_vision_system()` 末尾で `_pre_joined_npc_managers` 以外の全 NpcManager に `activate()` 呼び出し
- VisionSystem 配布後に呼ぶ（explore 行動で `_vision_system.is_area_visited()` を参照するため）

**敵アクティブ化トリガー拡張**
- `vision_system._process()` でフレンドリーキャラ（プレイヤーパーティー + NPC）の占有エリアを `friendly_areas: Dictionary` に収集
- `party_manager.update_visibility()` に `friendly_areas` パラメータ追加（省略可能、後方互換）
- アクティブ化条件: `player_area == member_area or friendly_areas.has(member_area)`

**NPC表示制御**
- 変更なし。既存の `visited_areas.has(member_area)` でプレイヤー未訪問エリアのNPCは非表示のまま

**デバッグログエリアフィルタ**
- `message_log.gd` に `setup_area_filter(map_data, get_player_area)` 追加
- `add_combat()` / `add_ai()` に省略可能な `grid_pos: Vector2i = Vector2i(-1, -1)` パラメータ追加
- `_is_in_player_area(grid_pos)`: grid_pos のエリアがプレイヤーエリアと不一致ならバッファに入れない
- `character.gd._log_damage()` / `log_heal()` と `party_leader_ai.gd._log_strategy_change()` から grid_pos を渡す

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/message_log.gd` | setup_area_filter()・_is_in_player_area() 追加; add_combat/add_ai に grid_pos パラメータ |
| `scripts/party_manager.gd` | update_visibility() に friendly_areas パラメータ追加 |
| `scripts/vision_system.gd` | _process() でフレンドリーエリア収集、敵マネージャーに渡す |
| `scripts/game_map.gd` | _setup_vision_system() 末尾で NPC activate() + MessageLog フィルタ設定 |
| `scripts/character.gd` | _log_damage()・log_heal() で grid_pos を渡す |
| `scripts/party_leader_ai.gd` | _log_strategy_change() で leader_pos を渡す |

### 会話UIをMessageWindowに統合（Phase 10-2 準備） ✅ 完了

#### 概要
- DialogueWindow（専用ポップアップ）を廃止し、会話の選択肢をMessageWindow下部にインライン表示する
- NPC パーティー情報や会話の結果もメッセージとしてログに残る

#### MessageWindow の会話モード
- `start_dialogue(choices: Array[Dictionary])`: 選択肢をインライン表示して入力受付開始
  - choices: `[{ "id": String, "label": String }]`
- `end_dialogue()`: 会話モード終了
- `show_rejected(msg)`: 拒否メッセージ表示（1.5秒後に `dialogue_dismissed` 発火）
- `is_dialogue_active() -> bool`: 会話中かどうか
- シグナル: `choice_confirmed(choice_id)` / `dialogue_dismissed()`
- 入力: ↑↓で選択、Z/右で決定、X/左/Escで閉じる
- 会話中はウィンドウの背景が濃くなり枠線表示。選択肢はセパレーターで区切りカーソル付き

#### game_map.gd の変更
- DialogueWindow のノード生成・シグナル接続を廃止
- `_setup_dialogue_system()` で MessageWindow の `choice_confirmed` / `dialogue_dismissed` を接続
- `_on_dialogue_requested()`: NPC メンバー情報をメッセージ表示 → `message_window.start_dialogue()` で選択肢表示
- `_on_dialogue_choice()`: `message_window.end_dialogue()` → 結果メッセージ表示
- `_close_dialogue()`: `dialogue_window.hide_dialogue()` → `message_window.end_dialogue()`
- `_process()` の会話中断チェック: `dialogue_window.visible` → `message_window.is_dialogue_active()`
- `dialogue_window` 変数を削除

#### 会話フローのメッセージ
| タイミング | メッセージ |
|-----------|----------|
| NPC から話しかけられた | `{名前} のパーティーが話しかけてきた` |
| プレイヤーから話しかけた | `{名前} のパーティーに話しかけた` |
| メンバー情報 | `  {名前} [{ランク}] {クラス} ({状態})` × 人数分 |
| NPC が仲間に加入 | `{名前} のパーティーが仲間に加わった！` |
| NPC パーティーに合流 | `{名前} のパーティーに合流した！` |
| NPC が申し出を拒否 | `{名前} は申し出を断った` |
| 敵接近で会話中断 | `敵の接近により会話が中断された！` |

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/message_window.gd` | 会話モード追加（start_dialogue/end_dialogue/show_rejected/is_dialogue_active/入力処理/描画） |
| `scripts/game_map.gd` | DialogueWindow 廃止。MessageWindow に会話シグナル接続。NPC情報・結果をメッセージ表示 |

### 装備ステータス補正値反映（Phase 10-2 完了） ✅ 完了

#### 方式
- 装備補正は攻撃時に毎回加算するのではなく、装備変更時に Character のパラメータに事前反映する
- `Character.attack_power` / `magic_power` は装備補正込みの実効値を保持する

#### 実装詳細

**character.gd**:
- `refresh_stats_from_equipment()` を追加
  - `attack_power = cd.attack_power + cd.get_weapon_attack_bonus()`
  - `magic_power = cd.magic_power + cd.get_weapon_magic_bonus()`
- `_init_stats()` の末尾で呼び出し（初期装備の反映）
- defense は装備補正なし。耐性は `take_damage()` 内で `get_total_*_resistance()` 経由で既に装備込み

**character_data.gd**:
- `get_weapon_accuracy_bonus() -> float` を追加（武器の accuracy 補正）

**order_window.gd**:
- `_do_equip()` で装備変更後に `ch.refresh_stats_from_equipment()` を呼び出し
- `_get_stat_rows()` に命中精度（accuracy + 武器補正）・防御精度（defense_accuracy）行を追加

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character.gd` | `refresh_stats_from_equipment()` 追加; `_init_stats()` から呼び出し |
| `scripts/character_data.gd` | `get_weapon_accuracy_bonus()` 追加 |
| `scripts/order_window.gd` | `_do_equip()` で refresh 呼び出し; 命中精度・防御精度行追加 |

### UI改善・バグ修正（Phase 10-2） ✅ 完了

#### クラス名・ランク表示
- 左パネル: キャラ名の横にクラス名（日本語）とランクを表示（例：`エリカ 弓使い A`）
- OrderWindow: メンバーテーブルの名前列に同様に表示
- `GlobalConstants.CLASS_NAME_JP` テーブルで class_id → 日本語名を変換

#### 左パネルの個別指示表示
- OrderWindow の COL_LABELS と完全一致する表記に統一（例：`同じ部屋 / 積極攻撃 / 最近傍`）

#### 会話選択の操作修正
- 決定: Z / A のみ（`ui_right` 削除）
- キャンセル: X / B のみ（`ui_left` / `ui_cancel` 削除）
- フィールド上の会話は移動入力と競合するため、OrderWindow 内の左右キー操作とは別体系

#### キャラクター生成の重複防止
- `CharacterGenerator` に `_used_names` / `_used_image_sets` static 変数を追加
- 生成時に未使用の名前・画像セットを優先選択（枯渇時はフォールバック）
- `reset_used()` で使用済みリストをクリア（`game_map._ready()` で呼び出し・F5 再起動対応）

#### アイテム表示改善
- 装備可能アイテム: 通常色（白）、装備不可: 灰色で色分け
- 補正値を日本語表記に統一（`GlobalConstants.STAT_NAME_JP` テーブル使用）
  - attack_power → 攻撃力、magic_power → 魔力、accuracy → 命中、等
  - アイテム一覧・装備欄の両方に適用
- カテゴリ・タイプの冗長表記を削除し、アイテム名 + 補正値サマリのみに簡略化

#### 主人公のランダム生成化
- hero.json 固定から CharacterGenerator によるランダム生成に変更（他キャラと同様）
- `dungeon_handcrafted.json` の主人公定義を `character_id: "hero"` → `class_id: "fighter-sword"` に変更
- `game_map._setup_hero()` から hero.json 分岐を削除。常に `CharacterGenerator.generate_character(class_id)` を使用
- 画像セットの重複防止（`_used_image_sets`）も主人公に適用される

#### 耐性の能力値化
- 耐性を float（軽減率）から int（能力値）に変更
- 変換式: `軽減率 = 能力値 / (能力値 + 100.0)`（逓減カーブ。100で50%軽減）
- クラスJSON / 敵JSON: `0.12` → `12` 等（×100 で整数化）
- アイテムの耐性値はそのまま（元々整数で正しい値だった）
- `CharacterData`: `physical_resistance: float` → `int`。`get_total_*_resistance_score()` 追加
- `CharacterGenerator._calc_stats()`: 耐性計算を int 対応に変更
- OrderWindow: 耐性を能力値（整数）で表示（%表記ではなく）
- 戦闘ログ: 変換後の軽減率%で表示（既存のまま）

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/global_constants.gd` | CLASS_NAME_JP / STAT_NAME_JP テーブル追加 |
| `scripts/left_panel.gd` | クラス名・ランク表示; 個別指示を COL_LABELS と完全一致に |
| `scripts/order_window.gd` | 名前列にクラス名・ランク; アイテム色分け・日本語補正値（一覧・装備欄の両方） |
| `scripts/message_window.gd` | 会話選択の左右キー無効化 |
| `scripts/character_generator.gd` | _used_names / _used_image_sets 追跡; reset_used() |
| `scripts/game_map.gd` | _ready() で reset_used() 呼び出し; _setup_hero() から hero.json 分岐を削除 |
| `scripts/character_data.gd` | physical/magic_resistance を int 化; resistance_to_ratio() / get_total_*_resistance_score() 追加 |
| `scripts/character_generator.gd` | _calc_stats() の耐性計算を int 対応に変更 |
| `assets/master/classes/*.json` | base_physical/magic_resistance を float→int に変更 |
| `assets/master/enemies/*.json` | physical/magic_resistance を float→int に変更 |
| `assets/master/maps/dungeon_handcrafted.json` | 主人公 character_id:"hero" → class_id:"fighter-sword" |

#### カメラのデッドゾーン縮小
- `camera_controller.gd`: `DEAD_ZONE_RATIO` を 0.70 → 0.40 に変更
- 先読みマージンが拡大し、出会いがしらが軽減される

#### 隣接エリアの先行可視化
- プレイヤーパーティーメンバーの隣接タイル（4方向）が未訪問エリアに属していればそのエリアを可視化
- 通路の端に立つと次の部屋の中が見える（部屋のタイルに隣接するまで発動しない）
- `map_data.gd`: `build_adjacency()` / `get_adjacent_areas()` / `_adjacent_areas` 追加（将来用に保持）
- `vision_system.gd`: `_reveal_adjacent_areas()` 追加（タイル隣接チェック方式）
- `game_map.gd`: `_finish_setup()` で `map_data.build_adjacency()` を呼び出し

#### 移動時の grid_pos 半マス遅延更新
- `character.gd`: `move_to()` で `grid_pos` を即時更新せず `_pending_grid_pos` に保存
- `_update_visual_move()`: 進捗50%（半マス到達）で `grid_pos = _pending_grid_pos` を確定
- `get_occupied_tiles()`: 移動中は旧位置と移動先の両方を返す（二重占有防止）
- `sync_position()`: テレポート時は即時確定のまま（変更なし）
- 効果: 視界・衝突判定が視覚位置と一致し、移動の不自然さが解消

#### パーティーメンバー押し出しシステム（player_controller.gd）
- **目的**: 加入済みパーティーメンバーが移動先を塞いでいる場合に押し出す（abort_move の押し戻しを防ぐ）
- **対象**: `is_friendly=true` かつ `blocking_characters` に含まれない（＝加入済み）かつ `is_flying=false` のキャラクター
- **アルゴリズム** (`_try_push(target_char, push_dir, depth)`):
  1. 深度が3以上なら失敗 return
  2. 候補方向：前方・左90°・右90° の順に試みる
  3. 各方向の dest = target_char.grid_pos + cand_dir を `_can_push_to()` で走行可否確認
  4. dest に別の押し出し可能な味方がいる場合は再帰的に `_try_push(next_ally, cand_dir, depth+1)`
  5. 再帰成功 or 誰もいない → `target_char.move_to(dest, duration)` でプレイヤーと同時アニメーション
  6. 全方向失敗なら false を返す
- **統合** (`_try_move()`): `_can_move_to(new_pos)` が true のとき `_find_pushable_ally(new_pos)` でチェック。押し出し失敗ならプレイヤーも移動しない
- **`_can_push_to(pos, ch)`**: タイル走行可否 + blocking_characters（敵・未加入NPC）ブロックチェック

| ファイル | 変更内容 |
|---------|---------|
| `scripts/camera_controller.gd` | DEAD_ZONE_RATIO 0.70→0.40 |
| `scripts/vision_system.gd` | _reveal_adjacent_areas() 追加（タイル隣接チェック方式） |
| `scripts/map_data.gd` | build_adjacency() / get_adjacent_areas() / _adjacent_areas 追加 |
| `scripts/game_map.gd` | _finish_setup() で build_adjacency() 呼び出し |
| `scripts/character.gd` | move_to() 半マス遅延; _pending_grid_pos / _grid_pos_committed; get_occupied_tiles() 拡張 |

---

### Phase 10-3: 消耗品の使用 ✅ 完了

#### 設計方針
固定スロット管理は行わない。`CharacterData.inventory` 内の消耗品（`category=="consumable"`）リストを `selected_consumable_index` で循環選択して使用する。

#### 操作仕様

| 操作 | キーボード | ゲームパッド |
|------|-----------|-------------|
| アイテム使用（選択中） | C | X（Joypad Button 2） |
| 前の消耗品に循環 | — | LT（Joypad Button 6） |
| 次の消耗品に循環 | — | RT（Joypad Button 7） |

#### 消耗品フォーマット（assets/master/items/）
- `potion_hp.json`：`category: "consumable"`, `effect.heal_hp: 30`
- `potion_mp.json`：`category: "consumable"`, `effect.restore_mp: 20`

#### 使用条件
- ヒールポーション → HP < max_hp のとき使用可
- MPポーション → MP < max_mp のとき使用可
- 使用後：inventory から削除、インデックスを再クランプ、MessageLog にシステムメッセージ

#### 消耗品バー UI（ConsumableBar）

- `scripts/consumable_bar.gd`（CanvasLayer, layer=11）
- 配置：画面上部・部屋名ラベル（AreaNameDisplay）の左側。右端を部屋名左端から RIGHT_MARGIN=24px 空けて配置
- 消耗品を `item_type` ごとにグループ化し横並び表示
  - アイコン：カラーブロック（HP=赤、MP=青、その他=黄）
  - カウント：「×n」テキスト
  - 選択中グループ：白い枠でハイライト
- `update_character(character)` / `refresh()` で再描画
- 更新トリガー：操作キャラ切替・アイテム取得（消耗品のみ）・LT/RT循環・C/X使用後
- 消耗品が0個のとき何も描画しない（visible フラグではなく空判定）
- 左パネルへの消耗品表示（[C] アイテム名）は将来検討

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/character_data.gd` | `selected_consumable_index`・`get_consumables()`・`get_selected_consumable()` 追加 |
| `scripts/character.gd` | `use_consumable(item)` 追加（heal_hp → heal()、restore_mp → mp 直接加算） |
| `scripts/player_controller.gd` | `_process_normal()` で `use_item`/`slot_prev`/`slot_next` 入力処理。`_cycle_consumable()`・`_use_selected_consumable()` 追加。`consumable_bar` 参照を追加し循環・使用後に `refresh()` |
| `scripts/consumable_bar.gd` | 新規作成。CanvasLayer として消耗品バー UI を描画 |
| `scripts/game_map.gd` | `_setup_panels()` で ConsumableBar を生成・PlayerController に渡す。操作キャラ切替時・アイテム拾得時に更新 |
| `scripts/left_panel.gd` | アクティブキャラ欄に `[C] アイテム名 (n/total)` を表示（将来整理予定） |
| `project.godot` | InputMap に `use_item`（C + Joypad 2）・`slot_prev`（Joypad 6）・`slot_next`（Joypad 7）追加 |

### Phase 10-4: 指示／ステータスウィンドウ統合 ✅ 完了

詳細仕様: 本ファイルの「指示／ステータスウィンドウ統合仕様」節を参照。

#### 実装済みファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/order_window.gd` | 下部ステータス詳細・装備スロット（空）・所持アイテム（空）パネルを追加 |
| `scripts/game_map.gd` | Tab 開閉条件を「誰でも開ける」に変更（旧：リーダーのみ）。player_controller null チェック追加 |

#### 実装メモ
- `_get_stat_rows(ch)` でキャラのステータス行データ（type: num/float/str/hp_mp）を生成
- `_draw_status_section()` で下部パネルを描画。左側に顔/全身画像・右側に素値・補正値・最終値の3列表示（補正値は現在すべて 0）
- `_get_selected_char()` でフォーカス行のキャラを選択（フォーカスなければ操作キャラ）
- `_is_editable()` でリーダー判定。false の場合は指示変更キーを無効化しタイトルに「（閲覧のみ）」表示
- 装備・アイテム欄は「（なし）」プレースホルダー（Phase 10-2/3 実装後に実データ表示）
- `_get_char_front_texture(ch)`: sprite_front → sprite_face の順でループして試す。ファイルが存在しない場合（ResourceLoader.exists() = false）も次を試す。不在パスは null キャッシュして再チェックを省略
  - **注意**: CharacterGenerator 生成キャラは常に sprite_front にパスが入るが front.png がない場合があるため、ファイル存在チェックが必須
- カーソル位置記憶：`open_window()` でリセットせず前回位置を維持
- 全体方針→個別方針の下移動時に `_col_cursor = 0`（操作列から開始）

---

## Phase 11: フロア・ダンジョン拡張

### Phase 11-1: 階段実装・フロア遷移（実装済み）

#### 実装内容

**タイル・データ層**
- `MapData.TileType`: `STAIRS_DOWN = 4`, `STAIRS_UP = 5` を追加
- `GlobalConstants`: `TILE_STAIRS_DOWN = 4`, `TILE_STAIRS_UP = 5` 定数追加
- `MapData.find_stairs(tile_type)`: 指定タイル種の全座標を返す
- `MapData.is_walkable()` / `is_walkable_for()`: 階段を FLOOR 同等（地上・飛行とも通行可）として扱う

**ダンジョンビルダー**
- `DungeonBuilder.build_floor()`: 内部で `_place_stairs()` を呼び出し、JSON の `stairs` 配列をタイルに展開
- JSON 形式: `"stairs": [{"type": "stairs_down"/"stairs_up", "x": int, "y": int}]`
- `build_floor()` 末尾で `data.build_adjacency()` を呼ぶ（game_map.gd からは削除済み）

**VisionSystem（マルチフロア対応）**
- `_floor_visited: Array` / `_floor_visible_tiles: Array` でフロアごとに訪問・可視データを保持
- `_visible_tiles` は現在フロアの辞書への参照（GDScript の参照セマンティクスを活用）
- `switch_floor(floor_index, map_data, player)`: アクティブフロアを切り替え、参照を再バインド
- `remove_enemy_manager(em)` を追加

**game_map.gd（マルチフロア対応）**
- `const CURRENT_FLOOR` を廃止。`var _current_floor_index: int = 0` に変更
- `_all_floor_data: Array` / `_all_map_data: Array[MapData]`: 全フロアのデータを起動時一括構築
- `_per_floor_enemies: Array` / `_per_floor_npcs: Array`: フロアごとの管理リスト
- `map_data` / `enemy_managers` / `npc_managers` は現在フロアのエイリアス
- `_setup_floor_enemies(idx)` / `_setup_floor_npcs(idx)`: 指定フロアの敵・NPC をセットアップ
- 未訪問フロアは `_transition_floor()` での初訪問時に遅延セットアップ
- `_check_stairs_step()`: hero が静止中かつ階段タイルを踏んでいれば遷移
- `_transition_floor(direction)`: フロア遷移処理（マップ更新・hero 位置・VisionSystem・カメラリミット）
- `_update_camera_limits(cam)`: camera2D のリミットを現在 map_data に合わせて更新
- `_update_character_visibility()`: 非カレントフロアのキャラを強制非表示
- 階段タイルを茶色/黄土色で描画。▼/▲ シンボルをフォールバックフォントで重ね描き
- 遷移クールダウン 1.5 秒（`_stair_cooldown`）で連続遷移を防止

**dungeon_handcrafted.json**
- 3フロア構成に更新
  - フロア0（廃墟）: r1_6 右奥に `stairs_down`（x:53, y:29）
  - フロア1（地下牢）: `stairs_up`（x:8, y:7）+ `stairs_down`（x:51, y:7）。3部屋（入口・囚人の広間・地下の奥地）
  - フロア2（深淵）: `stairs_up`（x:8, y:7）。2部屋（深淵の回廊・暗黒の祭壇[ボス部屋]）

#### 当面の制限
- パーティーメンバーはフロア遷移しない（hero のみ）
- 敵は階段を使って移動しない（部屋守備 AI のまま）
- right_panel の敵情報は旧フロアのままになる場合がある（将来対応）

### Phase 11-2: 10フロア対応・ダンジョン事前生成方式への移行

#### 仕様
- ダンジョンは10フロア構成を標準とする
- 深いフロアほど強い敵を配置・アイテムの補正値も高くなる
- 配布時は Claude Code で事前に100〜1000個のダンジョンJSONを生成してストック、プレイ時にランダム選択
- ゲーム内LLMリアルタイム生成は廃止済み（F5 は現在シーン再スタート）

#### 事前生成方式の設計メモ
- 生成スクリプトはゲーム本体とは独立したツールとして実装
- 生成済みダンジョンデータを `assets/master/maps/generated/dungeon_XXXX.json` に保存
- ゲーム起動時にリストからランダム選択して読み込む

---

## Phase 12: ステージ・バランス調整

### Phase 12-17: 敵ステータス生成システム（実装済み）

#### 設定ファイル

**`assets/master/stats/enemy_class_stats.json`**
敵専用ステータスタイプ（zombie / wolf / salamander / harpy / dark-lord）の base / rank を定義。
人間クラス（fighter-sword 等）は既存の `class_stats.json` を流用するため、このファイルには含まない。

**`assets/master/stats/enemy_list.json`**
全16敵種のステータス設定を一元管理。各エントリのフィールド：
- `stat_type`：参照するステータステーブルのキー（`class_stats.json` または `enemy_class_stats.json`）
- `rank`：生成時のデフォルトランク（C/B/A/S）
- `stat_bonus`：`_calc_stats()` 計算後に加算する補正値辞書（100でクランプ）

| 敵 | stat_type | rank | stat_bonus |
|----|-----------|------|------------|
| goblin | fighter-axe | C | — |
| hobgoblin | fighter-axe | B | — |
| goblin-archer | archer | C | — |
| goblin-mage | magician-fire | C | — |
| zombie | zombie | C | — |
| skeleton | fighter-sword | B | physical_resistance: +30 |
| skeleton-archer | archer | B | physical_resistance: +30 |
| lich | magician-fire | B | physical_resistance: +30 |
| wolf | wolf | B | — |
| salamander | salamander | B | — |
| harpy | harpy | B | — |
| demon | magician-fire | A | — |
| dark-knight | fighter-sword | A | — |
| dark-mage | magician-fire | A | — |
| dark-priest | healer | A | — |
| dark-lord | dark-lord | S | — |

#### ステータス計算フロー
1. `_load_stat_configs()` で `class_stats.json` + `enemy_class_stats.json` を `_class_stats_cache` にマージ
2. `enemy_list.json` から `stat_type` / `rank` / `stat_bonus` を取得
3. `_calc_stats(stat_type, rank, sex, age, build)` でステータスを生成（sex/age/build は `apply_enemy_graphics()` が設定済み）
4. `stat_bonus` を加算（`mini(100, base + bonus)`）
5. `vitality` → `max_hp`、`energy` → `max_sp`（敵は MP/SP 区別なし・max_mp = 0）

#### 呼び出し順（`party_manager._spawn_member()`）
```
CharacterData.load_from_json()       ← 非ステータスフィールド（attack_type 等）
CharacterGenerator.apply_enemy_graphics()  ← sex/age/build を設定
CharacterGenerator.apply_enemy_stats()     ← ステータスを上書き（上記のフローで生成）
```

### Phase 12-16: クリティカルヒット（実装済み）

- **判定**：`character.gd` の `take_damage()` 冒頭で処理
  - クリティカル率 = 攻撃側 `skill ÷ 3`%（例: skill=30 → 10%）
  - `randf() < float(atk_skill) / 300.0` で判定
  - 成功時: ベースダメージ × 2.0（`power` ステータス自体は変化しない）
- **エフェクト**：`_spawn_hit_effect(actual)` を2回呼んで二重表示で強調
- **通知**：MessageLog の戦闘ログに「[クリティカル!×2]→X」と表示
- **SE・グラフィック**：既存の HitEffect / take_damage SE をそのまま流用

### 攻撃タイプ別ダメージ倍率（実装済み）

`GlobalConstants.ATTACK_TYPE_MULT` に定数として管理。  
ベースダメージ = `power × type_mult × damage_mult`

| attack_type | type_mult | 備考 |
|-------------|-----------|------|
| melee       | 0.5       | 近接攻撃（剣士・斧戦士・斥候） |
| ranged      | 0.2       | 遠距離物理（弓使い） |
| dive        | 0.5       | 降下攻撃（ハーピー） |
| magic       | 0.2       | 遠距離魔法（魔法使い系・goblin-mage 等） |

- `damage_mult` はスロット JSON の `damage_mult` フィールド（未指定時 1.0）
- player_controller・unit_ai 両方で適用
- 適用箇所: `_execute_melee` / `_execute_ranged` / `_execute_water_stun` / `_execute_whirlwind` / `_execute_rush` / `_execute_headshot`（×3.0 ケース） / `_execute_flame_circle` / `_execute_attack`（UnitAI）

### 人間キャラクターのランク上限（実装済み）

- `character_generator._random_rank_human()`：A=15%, B=35%, C=50%（Sなし）
- `generate_character()` 内で `_random_rank()` の代わりに使用
- Sランクはダークロード等のボス級専用（`enemy_list.json` で `"rank": "S"` を直接指定）

### 未加入NPC フロア遷移スコアロジック（実装済み）

`NpcLeaderAI._get_explore_move_policy()` が EXPLORE 戦略時の移動方針（`stairs_down` / `stairs_up` / `explore`）を決定する。

#### スコア計算

| 項目 | 内容 |
|------|------|
| ランク和スコア | 全メンバーの `RANK_VALUES`（C=3, B=4, A=5, S=6）の**合計** |
| 適正フロア | ランク和スコアと `GlobalConstants.FLOOR_RANK` を比較して決定 |
| HP チェック | 最低 HP 割合（ポーション回復量を加算）が `NPC_HP_THRESHOLD(0.5)` 未満 → 適正フロア-1 |
| エネルギーチェック | 平均 MP/SP 割合（ポーション回復量を加算）が `NPC_ENERGY_THRESHOLD(0.3)` 未満 → 適正フロア-1 |

#### `GlobalConstants.FLOOR_RANK`（ランク和ベース）

各フロアの敵パーティー構成（dungeon_handcrafted.json）を参照して設定。

| フロア | 必要ランク和 | 備考 |
|--------|---------|------|
| 0 | 0 | 入口フロア（誰でも滞在可） |
| 1 | 8 | F0→F1: ランクB×2（=8）以上。ランクC×2（=6）では不可 |
| 2 | 13 | F1→F2: ランクB×3（=12）では不可・B+A（=13）以上が必要 |
| 3 | 18 | F2→F3: ランクA×3（=15）では不可・A×3+B（=19）以上が必要 |
| 4 | 24 | 最下層（ボス）。事実上 NPC は到達しない |

#### 関連定数（`global_constants.gd`）

```
FLOOR_RANK: Dictionary = {0: 0, 1: 8, 2: 13, 3: 18, 4: 24}
NPC_HP_THRESHOLD: float = 0.5
NPC_ENERGY_THRESHOLD: float = 0.3
NPC_KNOWS_STAIRS_LOCATION: bool = false  # false=視界ベース探索 / true=地図持ち（テスト用）
```

#### ヘルパーメソッド（`npc_leader_ai.gd`）

- `_calc_recoverable_hp(member)`: インベントリ内の HP ポーション合計回復量を返す
- `_calc_recoverable_energy(member)`: インベントリ内の MP/SP ポーション合計回復量を返す（`max_mp > 0` ならMP、それ以外はSP）

#### 判定フロー

```
1. ランク和 = Σ(RANK_VALUES[member.rank])  ← C=3, B=4, A=5, S=6
2. 適正フロア = FLOOR_RANK 比較で決定
   - ランク和 >= FLOOR_RANK[current+1] → appropriate_floor = current + 1
   - ランク和 <  FLOOR_RANK[current] / 2 → appropriate_floor = current - 1
3. HP 最低割合 = min(各メンバーの (hp + ポーション回復) / max_hp)
4. エネルギー平均 = avg(各メンバーの (mp or sp + ポーション回復) / max_energy)
5. hp_fail or energy_fail → target_floor = max(0, appropriate_floor - 1)
6. target > current → "stairs_down"、target < current → "stairs_up"、同じ → "explore"
```

### NPC メンバー個別フロア遷移（Phase 12-7 追加修正）

NPC パーティーのリーダーが階段を踏んだとき、全員を一括転送するのではなく、リーダーのみ先に遷移し、残りのメンバーが各自階段へ歩いて個別に遷移する方式。

#### 遷移フロー

```
1. リーダーが階段タイルに静止 + move_policy が意図した方向と一致
   → _transition_npc_floor(nm, direction)
      ・リーダーのみ new_floor に転送（sync_position）
      ・リーダーの UnitAI map_data のみ新フロアに更新（set_member_map_data）
      ・NpcManager は全員揃うまで旧フロアリストに残す

2. 残メンバーの _assign_orders() で強制誘導
   ・party_leader_ai._assign_orders() にクロスフロア override を追加
   ・「未加入 NPC かつ非リーダーかつリーダーと別フロア」→ move_policy = "stairs_down"/"stairs_up" を強制
   ・strategy = WAIT にして戦闘中断（UnitAI は _generate_stair_queue() を呼ぶ）

3. 非リーダーが階段タイルに静止 + リーダーと別フロア
   → _transition_single_npc_member(nm, member, direction)
      ・そのメンバーのみ new_floor に転送
      ・そのメンバーの UnitAI map_data を新フロアに更新

4. 全メンバーが new_floor に揃ったとき
   → _per_floor_npcs を旧→新に更新
   → VisionSystem・dialogue_trigger を更新
   → _rebuild_blocking_characters()
```

#### 関連メソッド

| メソッド | 説明 |
|---------|------|
| `game_map._transition_npc_floor(nm, dir)` | リーダーのみ遷移（旧：全員一括） |
| `game_map._transition_single_npc_member(nm, ch, dir)` | 非リーダーメンバーを個別遷移 |
| `game_map._check_npc_member_stairs()` | 全メンバーを個別監視（旧：リーダーのみ） |
| `party_leader_ai.set_member_map_data(name, map)` | 特定メンバーの UnitAI map_data のみ更新 |
| `party_manager.set_member_map_data(ch, map)` | LeaderAI への passthrough |

#### NPC の階段探索（視界ベース）

`NPC_KNOWS_STAIRS_LOCATION = false`（デフォルト）の場合、`UnitAI._generate_stair_queue()` は訪問済みエリアにある階段のみを目標にする。

- 訪問済みエリアは `UnitAI._visited_areas: Dictionary`（エリアID→true）で管理
- `_visited_areas` は `PartyLeaderAI._visited_areas` の参照を全 UnitAI が共有（パーティー全員の知識を統合）
- `_generate_queue()` の先頭で現在エリアを記録。移動しながら自然に発見する
- 訪問済みエリアに目的の階段がなければ通常の `_generate_explore_queue()` にフォールバック（探索継続）
- `NPC_KNOWS_STAIRS_LOCATION = true` に切り替えると旧来の地図持ち動作に戻る（デバッグ・比較用）

#### ダンジョン階段配置（dungeon_handcrafted.json）

各方向6か所・フロア全体（3列×4行）に均等分散。

| フロア | stairs_up | stairs_down |
|-------|-----------|-------------|
| F0 | なし | r1_2/3/5/7/9/11（各行2列分散） |
| F1〜F3 | 行1〜2の全6室 | 行3〜4の全6室 |
| F4（ボス） | r5_1内6か所 | なし |

## Phase 13: Steam配布準備（未実装）

---

## 歩行アニメーション仕様（Phase 9-1 実装済み）

### 画像フォーマット
```
{class or enemy_type}_{sex}_{age}_{build}_{id}/
  top.png      通常立ち（静止中・フォールバック）
  walk1.png    歩行パターン1・左足を出した状態
  walk2.png    歩行パターン2・右足を出した状態
  ready.png    構えポーズ
  front.png    全身正面（UI用）
  face.png     顔アイコン（LeftPanel用）
```
- walk1/walk2 がない場合は top 固定のままフォールバック（既存キャラへの影響なし）

### アニメーション仕様
- 移動アニメーション（位置補間）と同期して駆動する（タイマーではなく進捗 t=0→1 ベース）
- アニメーションシーケンス: `walk1 → top → walk2 → top`（4フレーム）
  - t=0.0〜0.25: walk1
  - t=0.25〜0.50: top
  - t=0.50〜0.75: walk2
  - t=0.75〜1.00: top
- 構えモード（is_targeting_mode / is_attacking）中はスプライト切替を停止（位置補間は継続）
- 静止中: top.png 固定（または ready.png・is_attacking 中）

### CharacterData の追加フィールド
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `sprite_walk1` | String | 歩行パターン1のパス（空文字=フォールバック） |
| `sprite_walk2` | String | 歩行パターン2のパス（空文字=フォールバック） |

- CharacterGenerator が image_set フォルダから walk1.png / walk2.png を自動スキャン
- hero.json 等の直接 JSON 指定キャラは `sprites.walk1` / `sprites.walk2` を明示する

### character.gd の実装
#### 追加フィールド
| フィールド | 型 | 説明 |
|-----------|-----|------|
| `_tex_top` | Texture2D | top.png のキャッシュ |
| `_tex_walk1` | Texture2D | walk1.png のキャッシュ（なければ null） |
| `_tex_walk2` | Texture2D | walk2.png のキャッシュ（なければ null） |
| `_visual_from` | Vector2 | 補間開始ワールド座標 |
| `_visual_to` | Vector2 | 補間終了ワールド座標 |
| `_visual_elapsed` | float | 補間経過時間（秒） |
| `_visual_duration` | float | 補間総時間（秒）。0=補間なし |

#### 主要メソッド
- `move_to(new_grid_pos, duration=0.4)`: grid_pos は半マス到達（進捗50%）で更新。position を duration 秒かけて補間。移動中は旧位置+移動先の両方を占有タイルとして返す
- `sync_position()`: 即座スナップ＋補間キャンセル（初期配置・テレポート用）
- `is_moving() -> bool`: `_visual_duration > 0.0` を返す（PlayerController の gate 判定に使用）
- `_update_visual_move(delta)`: _process() から毎フレーム呼ぶ。位置補間とスプライトフレーム切替を行う

### game_speed による速度制御
GlobalConstants に `var game_speed: float = 1.0` を追加。将来の設定画面からここを変更することで全体速度を調整できる。

**Step 1-B（2026-04-20）以降の移動時間算出**：
| 対象 | 基準値 | 実効値の計算 |
|------|--------|-------------|
| 1 マス移動の論理時間 | `BASE_MOVE_DURATION = 0.40s` | `Character.get_move_duration() = BASE_MOVE_DURATION × 50 / move_speed`（ガード中は `× GUARD_MOVE_DURATION_WEIGHT = 2.0`） |
| 1 マス移動の実時間（Player） | 同上 | `character.get_move_duration() / game_speed` |
| 1 マス移動の実時間（UnitAI） | 同上 | `UnitAI._get_move_interval()` が `character.get_move_duration() / game_speed` を返す |
| UnitAI の WAIT_DURATION | 3.0s | `WAIT_DURATION / game_speed` |

- `game_speed = 1.0`: 標準速度（move_speed=50 なら 1 タイル 0.40 秒）
- `game_speed = 2.0`: 2 倍速
- 旧 `PlayerController.MOVE_INTERVAL = 0.30` / `UnitAI.MOVE_INTERVAL = 0.40`（SoT 分裂状態）は廃止・`BASE_MOVE_DURATION` に統合

### PlayerController の先行入力バッファ方式
#### 背景（旧タイマー方式の問題）
- **斜め移動問題**: アニメーション補間途中に別方向入力が来ると、中間視覚座標から新グリッド位置への斜め補間が発生していた
- **長押し停止問題**: OS のキーリピートと _move_timer の位相ズレ、または1フレームの ZERO 入力で `_move_holding=false` になり MOVE_INTERVAL_INITIAL(0.6s) 待機が再発していた

#### 解決策: 先行入力バッファ方式
```
_move_buffer: Vector2i  # 直近の方向入力を1つだけ保持（上書き方式）
```

1. `character.is_moving()` が true の間は移動をブロック
2. キーが押されていれば方向をバッファに上書き保存、**離されたらバッファを ZERO にクリア**
3. アニメーション完了後にバッファ → 現在入力の優先順で次の移動を実行
4. これにより斜め移動・長押し停止の両問題を解消

#### 定数
| 定数 | 値 | 説明 |
|------|-----|------|
| `MOVE_INTERVAL` | 0.30s | 1タイルの移動アニメーション時間・基準値 |

旧 `MOVE_INTERVAL_INITIAL`・`MOVE_INTERVAL_REPEAT`・`_move_timer`・`_move_holding` は廃止。

---

## ゲームパッド対応仕様

### Input Map 設定（project.godot）

| アクション名 | キーボード | ゲームパッド |
|------------|-----------|-------------|
| `ui_up` / `ui_down` / `ui_left` / `ui_right` | 矢印キー | 左スティック軸 or 十字キー |
| `attack` | Z | Joypad Button 0（A / Cross） |
| `menu_back` | X | Joypad Button 1（B / Circle） |
| `cycle_target_prev` | 矢印キー（左/上） + ターゲット中 | Joypad Button 9（LB / L1） |
| `cycle_target_next` | 矢印キー（右/下） + ターゲット中 | Joypad Button 10（RB / R1） |
| `open_order_window` | ※キーボードは別途処理 | Joypad Button 4（Select / Back） |
| `use_item_modifier` | — | Joypad Axis 2（LT / L2）ホールド |
| `game_quit` | ※キーボードは別途処理 | — |

※ アイテム使用（LTホールド中）は use_item_modifier が押されている間、A/B/X/Y をアイテムスロット1〜4に割り当て

### キーボード入力処理の実装メモ
Godot 4 では Tab・Esc キーが UI フォーカスナビゲーション / ui_cancel として特別処理されるため、
`event.is_action_pressed()` や `Input.is_action_just_pressed()` のアクション名方式では
キーボードの Tab / Esc を確実に検出できない。以下の方針で実装済み：

- **キーボード Tab / Esc**：`game_map._input()` の `physical_keycode` 直接マッチで処理
  ```gdscript
  KEY_ESCAPE → OrderWindow が開いていれば close_window()、そうでなければ get_tree().quit()
  KEY_TAB    → _toggle_order_window()
  KEY_F1     → AIデバッグパネル toggle
  KEY_F5     → シーン再スタート（get_tree().reload_current_scene()）
  ```
- **ゲームパッド Select ボタン**：`game_map._process()` の `Input.is_action_just_pressed("open_order_window")` でポーリング
- **全描画用 Control ノード**に `focus_mode = Control.FOCUS_NONE` を設定（UI フォーカス干渉防止）
  - 対象: order_window, left_panel, right_panel, dialogue_window, message_window, area_name_display

### ターゲット循環バグ修正
- キャンセル状態（`_target_index == _valid_targets.size()`）で `_refresh_targets()` が毎フレーム呼ばれると
  `prev_target = null` → インデックスが 0 にリセットされ、LB での後退が機能しなかった
- `was_cancel` フラグで「キャンセル選択中だったか」を保持し、refresh 後もキャンセル状態を維持するよう修正

### PlayerController の変更点
- 移動入力: `Input.get_vector()` で左スティック対応（デッドゾーン 0.3）
- ターゲット循環: ターゲットモード中に cycle_target_prev / next を検出
- アイテム使用モード: use_item_modifier ホールド中のみ A/B/X/Y をアイテムスロットとして扱う（将来実装）

---

## 指示／ステータスウィンドウ統合仕様

### 変更概要
既存の OrderWindow を拡張し、指示だけでなくステータス・装備・アイテムも確認できるウィンドウとする。

### 開閉ルール ✅ 実装済み
- Tab（キーボード）/ Select（ゲームパッド）/ Esc でいつでも開閉（ポーズなし・時間進行継続）
- 旧仕様（リーダー操作中のみ有効）を廃止：誰を操作中でも開ける
- **リーダー操作中**：指示の変更可（従来通り）
- **非リーダー操作中**：閲覧のみ（指示変更キーは無効。タイトルに「（閲覧のみ）」表示）
- 会話中・その他ブロック中（`player_controller.is_blocked == true`）は開かない

### ウィンドウ構成（確定仕様）
```
┌──────────────────────────────────────────────────────────────┐
│  タイトル「パーティー指示」                                   │
├──────────────────────────────────────────────────────────────┤
│  [全体共通設定: 6行]                                          │
│    移動：         追従  密集  同じ部屋  待機  探索           │
│    攻撃ターゲット：近傍  最弱  同じ  援護                    │
│    低HP時の行動： 戦闘継続  後退  逃走                       │
│    アイテム取得： 積極  近くなら  拾わない                   │
│    ヒールポーション： 瀕死なら使う  使わない                     │
│    MP/SPポーション：使う  使わない                           │
│    ↑↓:行選択  ←→:選択肢切替  ↓(最終行)→メンバー表        │
├──────────────────────────────────────────────────────────────┤
│  [個別設定テーブル: 名前+4列]                                 │
│  非ヒーラー:                                                  │
│    名前  │  ターゲット        │  隊形     │  戦闘       │  特殊攻撃         │
│          │近傍 最弱 同じ 援護│包囲 突進 後衛│攻撃 防御 逃走│積極 強敵 劣勢 使わない│
│  ヒーラー:                                                    │
│    名前  │  隊形     │  戦闘       │  回復                    │  特殊攻撃         │
│          │包囲 突進 後衛│攻撃 防御 逃走│積極 リーダー優先 瀕死優先 しない│積極 強敵 劣勢 使わない│
│    ↑↓:行移動  ←→:列移動/選択肢切替  Z:名前列でサブメニュー│
├──────────────────────────────────────────────────────────────┤
│  [下部] 選択中キャラ詳細                                      │
│    ステータス（素値・補正・最終値）                           │
│    装備スロット（武器・防具・盾）                             │
│    所持アイテム（未装備品）                                   │
└──────────────────────────────────────────────────────────────┘
```

**選択肢横並び（チップ形式）表示**
- 全体方針・個別指示ともに全選択肢を横並びで常時表示
- 現在選択中の項目はハイライト（フォーカスあり＋編集可：青背景＋黄文字、フォーカスあり＋閲覧のみ：薄い背景、フォーカスなし：薄い背景＋暗めの文字）
- ←→ キーで選択肢を切り替えるとハイライトが移動
- 表示ラベルは `short_labels`（省略形）を使用
- 利用可能な幅が足りない場合はチップを均等縮小（省略なし）

#### 全体共通設定（`Party.global_orders`）

| キー | 選択肢（値） | 表示ラベル | デフォルト |
|------|------------|----------|----------|
| `move` | follow / cluster / same_room / standby / explore | 追従 / 密集 / 同じ部屋 / 待機 / 探索 | — |
| `target` | nearest / weakest / same_as_leader / support | 最近傍 / 最弱優先 / リーダーと同じ / 援護 | same_as_leader |
| `on_low_hp` | keep_fighting / retreat / flee | 戦闘継続 / 後退 / 逃走 | retreat |
| `item_pickup` | aggressive / passive / avoid | 積極的に拾う / 近くなら拾う / 拾わない | passive |
| `hp_potion` | use / never | 瀕死なら使う / 使わない | use |
| `sp_mp_potion` | use / never | 必要なら使う / 使わない | use |

- 変更時に move/target/on_low_hp/item_pickup は全メンバーの `current_order` にも同期（AI 互換）
- hp_potion / sp_mp_potion は `global_orders` に加え `PartyLeaderAI._global_orders` 経由で UnitAI にも渡す（Phase 13-6 で実装済み）

**全体共通設定の選択肢定義**

`on_low_hp`（低HP時の行動）
- 戦闘継続（keep_fighting）：HPが低くても行動を変えない
- 後退（retreat）：敵の射程外まで下がる（後衛ポジション）。移動できない場合は防御
- 逃走（flee）：部屋から出て離脱する。移動できない場合は防御

`item_pickup`（アイテム取得）
- 積極的に拾う（aggressive）：同じ部屋にアイテムがあれば拾いに行く
- 近くなら拾う（passive）：現在地から `GlobalConstants.ITEM_PICKUP_RANGE` マス以内なら拾いに行く（デフォルト）
- 拾わない（avoid）：拾わない

`hp_potion`（ヒールポーション）
- 瀕死なら使う（use）：HP割合が `GlobalConstants.NEAR_DEATH_THRESHOLD` 以下で使用（デフォルト）。ヒーラーの回復判定・低HP時行動の閾値と共有
- 使わない（never）：使用しない

`sp_mp_potion`（MP/SPポーション）
- 使う（use）：特殊攻撃指示の条件を満たす状況でSP/MPが不足していたら使用。特殊攻撃指示が「使わない」の場合は使用しない
- 使わない（never）：ポーションは使用しない（自動回復を待つ）

**GlobalConstants 定数**（Phase 13-6 で実装済み）
- `ITEM_PICKUP_RANGE = 2`：近くなら拾うの距離閾値（マンハッタン距離2マス）
- `NEAR_DEATH_THRESHOLD = 0.25`：瀕死判定のHP割合閾値（25%）。ヒールポーション使用・ヒーラー回復判定・low_hp行動の閾値で共有
- `DISADVANTAGE_THRESHOLD = 0.6`：劣勢判定の味方平均HP割合閾値（60%）。特殊攻撃「劣勢なら使う」・深層移動判定で共有

#### 個別設定（`character.current_order`）

**非ヒーラー 4列（ターゲット → 隊形 → 戦闘 → 特殊攻撃）**

| キー | 選択肢 | 説明 |
|------|--------|------|
| `target` | nearest / weakest / same_as_leader / support | 最近傍 / 最弱優先 / リーダーと同じ / 援護 |
| `battle_formation` | surround / rush / rear | 包囲 / 突進 / 後衛 |
| `combat` | attack / defense / flee | 攻撃 / 防御 / 逃走 |
| `special_skill` | aggressive / strong_enemy / disadvantage / never | 積極的に使う / 強敵なら使う / 劣勢なら使う / 使わない |

**ヒーラー 4列（隊形 → 戦闘 → 回復 → 特殊攻撃）**

| キー | 選択肢 | 説明 |
|------|--------|------|
| `battle_formation` | surround / rush / rear | 包囲 / 突進 / 後衛 |
| `combat` | attack / defense / flee | 攻撃 / 防御 / 逃走 |
| `heal` | aggressive / leader_first / lowest_hp_first / none | 積極回復 / リーダー優先 / 瀕死度優先 / 回復しない |
| `special_skill` | aggressive / strong_enemy / disadvantage / never | 積極的に使う / 強敵なら使う / 劣勢なら使う / 使わない |

#### 各指示の定義

**移動**
- 追従（follow）：リーダーの真後ろ1マスに位置取る（ブロック時は隣接フォールバック。マンハッタン距離2以内で満足）
- 密集（cluster）：操作キャラの周囲1マスに位置取る
- 同じ部屋（same_room）：同じ部屋にいれば自由に動く
- 待機（standby）：その場から動かない
- 探索（explore）：リーダー位置に関係なく未訪問エリアを自律探索
- 移動と戦闘指示は独立（待機中でも戦闘指示が有効）
- 隊形（包囲/突進/後衛）は同じ部屋にいる場合のみ適用

**攻撃ターゲット**（全体共通・個別共通）
- 最近傍（nearest）：最も距離が近い敵
- 最弱優先（weakest）：ダメージ状態が最も悪い敵（同率なら距離で決定）
- リーダーと同じ（same_as_leader）：リーダーのターゲットに合わせる
- 援護（support）：HP割合が最も低い味方に最も近い敵を狙う

**隊形**
- 包囲（surround）：ターゲットの背後→側面→正面の優先順で空きマスに位置取る
- 突進（rush）：ターゲットへ最短経路で向かう
- 後衛（rear）：射程距離を保つ（マージンあり）

**戦闘**
- 攻撃（attack）：ターゲット方針に従って積極的に攻撃する
- 防御（defense）：ガードしながら反撃のみ
- 逃走（flee）：戦闘を避けて離脱する

**回復**（ヒーラー専用・`heal_mode` キーで管理）
- 積極回復（aggressive）：HP率 < `NEAR_DEATH_THRESHOLD` (0.25) のうち最もHP率が低い1人を回復
- リーダー優先（leader_first）：リーダーが HP率 < `HEALER_HEAL_THRESHOLD` (0.5) なら最優先、それ以外は `aggressive` と同じ
- 瀕死度優先（lowest_hp_first）：HP率 < `HEALER_HEAL_THRESHOLD` (0.5) のうち最もHP率が低い1人を回復（無駄回復防止）
- 回復しない（none）：回復行動を取らない（ヒーラーが戦闘に集中する）
- 自分優先は選択肢に含めない（ヒーラーは他者優先のキャラクター設定）

**特殊攻撃**
- 積極的に使う（aggressive）：クールタイム明け次第使用
- 強敵なら使う（strong_enemy）：相手ランク ≧ 自分ランク
- 劣勢なら使う（disadvantage）：味方パーティーの平均HP割合が閾値以下（閾値は `GlobalConstants` に定数定義・深層移動判定など他ロジックと共有）
- 使わない（never）：使用しない

### ステータス3列表示（下部）
```
攻撃力         15   +5   →  20
防御精度       12    0   →  12
物理耐性       10%  +5%  →  15%
```
- 「素値」: CharacterData の基礎パラメータ
- 「補正値」: 装備による合計補正
- 「最終値」: 素値 + 補正値（乗算の場合は別途計算）
- 開発中は全ステータス項目を表示（防御精度・防御強度・耐性 etc. 含む）
- 配布前にプレイヤーに見せる項目・隠す項目を再検討する

### 装備スロット表示（下部）
- 武器スロット・防具スロット・盾スロット（盾非対応クラスはグレーアウト）
- 各スロット: アイテム名 + 主要補正値の要約表示
- 未装備の場合: 「(なし)」表示

### 消耗品スロット表示（下部）
- 最大4スロット（ゲームパッドの LT+ABXY に対応）
- 各スロット: アイテム名 + 残数
- 空スロット: 「(空)」表示

---

## アイテムシステム詳細仕様

### ファイル構成
```
assets/master/items/
  sword.json          剣
  axe.json            斧
  bow.json            弓
  dagger.json         ダガー
  staff.json          杖
  armor_plate.json    鎧
  armor_cloth.json    服
  armor_robe.json     ローブ
  shield.json         盾
  potion_hp.json      ヒールポーション
  potion_mp.json      MPポーション
```

### アイテムJSONフォーマット
```json
{
  "item_type": "sword",
  "category": "weapon",
  "allowed_classes": ["fighter-sword"],
  "base_stats": {
    "melee_attack_min": 3,
    "melee_attack_max": 8,
    "melee_accuracy_min": 0.05,
    "melee_accuracy_max": 0.15,
    "defense_strength_min": 1,
    "defense_strength_max": 4
  },
  "depth_scale": 0.5
}
```
- `depth_scale`: フロア深度ごとの補正値上乗せ係数（深いほど強くなる割合）
- 消耗品は `base_stats` の代わりに `effect: { "heal_hp": 30 }` 等を持つ

### アイテムデータ（インスタンス）
各アイテムインスタンスは生成時にランダム補正値と名前を確定する。

```gdscript
class_name ItemData extends Resource

var item_type: String       # "sword", "shield" 等
var category: String        # "weapon", "armor", "consumable"
var item_name: String       # Claude Code が生成した名前（例: "古びた騎士の剣"）
var allowed_classes: Array  # 装備可能クラスID一覧
var stats: Dictionary       # 確定済み補正値 { "melee_attack": 5, ... }
var quantity: int           # 消耗品のみ使用（装備品は常に1）
```

### アイテム生成フロー
1. フロア深度 `d`（0〜）と種類（sword.json 等）を元にランダム補正値を計算
   - `stat = rand_range(base_min, base_max) + d * depth_scale`
2. Claude Code がダンジョン生成時に補正値サマリ＋フロア深度を考慮して名前を作成（dungeon_handcrafted.json に記述）
3. ItemData インスタンスを生成

### 装備補正の反映（CharacterData）
- `equipped_weapon: ItemData`・`equipped_armor: ItemData`・`equipped_shield: ItemData`
- `get_stat_total(stat_key)` メソッド: 素値 + 全装備の補正値合計を返す
- ステータスウィンドウの3列表示はこのメソッドから取得

### 防御強度の計算（3フィールド方式）
```
block_right_front: 正面・右側面で有効（剣士・斧戦士・斥候・ハーピー・ダークロード等）
block_left_front:  正面・左側面で有効（剣士・斧戦士・ハーピー・ダークロード等）
block_front:       正面のみ有効（弓使い・魔法使い・ヒーラー・ゾンビ・ウルフ・サラマンダー等）

各フィールドを defense_accuracy で独立ロール → 成功した分の合計をカット
背面: 0（全フィールドをスキップ）
```
- クラス固有値（class_stats.json / enemy_class_stats.json から生成）
- 装備による補正なし

### ドロップシステム
- `EnemyParty.drop_items: Array[ItemData]` にダンジョン生成時にアイテムを格納
- 全滅時に `_on_party_wiped()` が呼ばれ、トドメを刺したパーティーに `drop_items` を転送
- アイテムはそのパーティーの「パーティー共有インベントリ」に格納（個人所持ではない）
- プレイヤーはウィンドウ内でメンバーへ装備を割り当て可能

### 消耗品の使用
- ゲームパッド: LT ホールド中のみ A/B/X/Y = スロット1〜4に割り当て
- キーボード: 未定
- 使用はフィールドから即時発動（ウィンドウを開く必要なし）
- 使用対象: 自分自身のみ（現フェーズ。将来は仲間へも）

---

## ステータス仕様更新（防御精度・防御強度）

### 用語変更
| 変更前 | 変更後 | 備考 |
|--------|--------|------|
| 回避力（evasion） | 防御精度（defense_accuracy） | キャラ素値。装備による変化なし |
| defense_strength（装備側） | block_right_front / block_left_front / block_front（CharacterData側） | クラス固有値・方向別3フィールド |

### 防御精度（defense_accuracy）
- キャラクター固有の素値（クラス基準値 × ランク/体格/性別/年齢 補正）
- 防御判定の成功確率を決定
- 装備による補正なし

### 防御強度（3フィールド方式）
- CharacterData の固有値（class_stats.json / enemy_class_stats.json から生成）
- 装備による補正なし
- 各フィールドを defense_accuracy で独立ロール。成功したフィールドの合計をカット
- 例: 剣士（block_right_front=20, block_left_front=20）、正面から攻撃
  → 最大40ダメージカット（両フィールドが成功した場合）

### 被ダメージ計算の全フロー
```
1. 着弾判定
   命中精度が基準値未満 → 外れ or 誤射（将来実装）

2. 防御判定（背面攻撃はスキップ・各フィールドを defense_accuracy で独立ロール）
   block_right_front: 正面・右側面で有効 → ロール成功でカット量に加算
   block_left_front:  正面・左側面で有効 → ロール成功でカット量に加算
   block_front:       正面のみ有効       → ロール成功でカット量に加算
   残ダメージ = max(0, 攻撃ダメージ - カット量合計)
   ※ カット量 0 = 防御失敗扱い

3. 耐性適用
   残ダメージ × (1.0 - 物理or魔法耐性%)

4. 最終ダメージ
   max(1, 残ダメージ)    ← 最低1は保証
```

### CharacterData のフィールド変更
- `evasion` → `defense_accuracy: int` にリネーム
- `block_right_front` / `block_left_front` / `block_front: int` を追加（クラス固有・装備補正なし）
- `equipped_weapon / equipped_armor / equipped_shield: Dictionary` を追加（装備スロット）

### ステータス決定構造への追加
キャラクター生成時の 防御精度 補正（旧・回避力と同じ方向性で引き継ぐ）:
| 体格 | 方向性 |
|------|--------|
| slim | 高め |
| medium | 標準 |
| muscular | 低め |

| 年齢 | 方向性 |
|------|--------|
| young | 高め（素早い） |
| adult | 標準 |
| elder | 低め |

---

## Phase 13-9: 戦闘方針プリセット・集結隊形・後衛距離制限 ✅ 完了

### 全体方針 `battle_policy`
`Party.global_orders["battle_policy"]` に attack / defense / retreat の3択を追加。
OrderWindow の `GLOBAL_ROWS` に表示行として追加（move 行の直後）。

### BATTLE_POLICY_PRESET（`order_window.gd`）
クラスID × 戦闘方針 → `{battle_formation, combat}` のプリセットテーブル。
`_apply_battle_policy_preset(policy)` で全パーティーメンバーに一括適用。

**非ヒーラーのクラス別プリセット例**:
| クラス | 攻撃 | 防衛 | 撤退 |
|--------|------|------|------|
| fighter-sword | surround / attack | gather / defense | gather / flee |
| fighter-axe | rush / attack | gather / defense | gather / flee |
| archer | rear / attack | rear / defense | rear / flee |
| scout | surround / attack | gather / defense | gather / flee |
| magician-* | rear / attack | rear / defense | rear / flee |

**ヒーラーのプリセット（専用処理）**:
| 戦闘方針 | battle_formation | combat | heal (current_order["heal"]) |
|---------|-----------------|--------|------------------------------|
| 攻撃 | rear | attack | lowest_hp_first |
| 防衛 | rear | defense | lowest_hp_first |
| 撤退 | rear | flee | lowest_hp_first |

ヒーラーは `_is_healer(ch)` で判定して専用プリセットを適用。`BATTLE_POLICY_PRESET` テーブルには載せない。

### HEALER_COLS（5列、`order_window.gd`）
非ヒーラーの MEMBER_COLS（4列）に対し、ヒーラーは5列。
`_get_cols_for(ch)` でキャラクター別に切り替え。`_col_cursor` 循環は `_get_active_total_cols()` で動的取得。

| 列 | key | 選択肢（先頭がデフォルト） |
|----|-----|--------------------------|
| 0 | target | nearest / weakest / same_as_leader / support |
| 1 | battle_formation | surround / rush / rear / gather |
| 2 | combat | attack / defense / flee |
| 3 | heal | **lowest_hp_first** / aggressive / leader_first / none |
| 4 | special_skill | aggressive / strong_enemy / disadvantage / never |

`unit_ai._find_heal_target()` は `current_order.get("heal", "lowest_hp_first")` を参照。デフォルトは `"lowest_hp_first"`（瀕死度優先）。
`character.gd` の `current_order` 辞書に `"heal": "lowest_hp_first"` キーを追加済み。
非ヒーラー行の回復列（pos=3）には「－」をグレーで表示（`_is_healer(ch)` で判定）。

### global_orders の初期値をメンバーへ反映（`order_window.gd`）
`setup()` 呼び出し時（ゲーム開始時の1回）に `_sync_all_global_to_members()` を呼んで
`Party.global_orders` のデフォルト値（`"target": "same_as_leader"` 等）を
全メンバーの `current_order` に反映する。

- 対象キー：`"move"` / `"target"` / `"on_low_hp"` / `"item_pickup"`
- `battle_policy` も初期値（デフォルト `"attack"`）を `_apply_battle_policy_preset()` 経由で適用（クラスごとの `battle_formation` / `combat` が正しく設定される）
- `setup()` は1回しか呼ばれないため、プレイヤーの個別設定を上書きしない

### 集結隊形 "gather"（`unit_ai.gd`）
`_calc_party_centroid()` — `_party_peers` の全メンバーの `grid_pos` 平均を返すヘルパー。

| メソッド | gather の動作 |
|---------|--------------|
| `_formation_satisfied()` | 重心から2タイル以内なら満足 |
| `_target_in_formation_zone()` | 重心から4タイル以内の敵を攻撃 |
| `_formation_move_goal()` | `_calc_party_centroid()` を目標タイルとして返す |

### Strategy.ATTACK 中の battle_formation 優先（`unit_ai.gd`）
`_generate_queue()` の Strategy.ATTACK ブランチ（ターゲットあり）では `_move_policy`（follow/cluster 等）を無視し、`_battle_formation` のみで移動先を決定する。

| battle_formation | 動作 |
|-----------------|------|
| `rear` | 射程内なら現在位置から攻撃（2回）。射程外なら接近して攻撃 |
| `surround` / `rush` / `gather` | `move_to_attack` → `attack` で積極的に追跡・攻撃 |

`_move_policy`（follow/cluster/same_room 等）は Strategy.WAIT/EXPLORE 時のみ適用される。  
`standby` は例外として ATTACK 中でも移動しない（射程内のみ攻撃）。

### follow 追従ロジック（`unit_ai.gd`）

**`_formation_satisfied()`** の "follow" 判定：

| 条件 | 結果 |
|------|------|
| メンバーがリーダーの前方タイルにいる | 不満足（常に後ろに回り込む） |
| 後方が通行可 かつ メンバーが後方から1タイル以内（後方・左後方・右後方） | 満足 |
| 後方が壁・障害物 かつ メンバーがリーダー隣接 | 満足 |

**`_formation_move_goal()`** の "follow" 目標候補（優先順位順）：
1. 後方（リーダー facing 逆方向）
2. 左後方（リーダー視点）
3. 右後方
4. 左
5. 右
6. 任意の隣接タイル（フォールバック）

ATTACK 戦略中はこれらの formation ロジックは適用されず、`_battle_formation` のみで行動する。

### EXPLORE 戦略中の未加入 NPC パーティーの移動方針（`party_leader_ai._assign_orders()`）

| メンバー種別 | move_policy |
|------------|------------|
| NPC リーダー | `"explore"`（自律的に未訪問エリアへ向かう） |
| NPC 非リーダーメンバー | `current_order["move"]`（デフォルト `"follow"`：リーダーを追従） |
| 全員（フロア移動時） | `"stairs_down"` / `"stairs_up"` |

旧実装では全員 `"explore"` に上書きしていたため、非リーダーメンバーが独立して行動しリーダーより先に進む問題があった。

---

## Phase 13-10: 敵縄張り・追跡システム ✅ 完了

### 概要
敵がスポーン地点を「縄張り」として持ち、一定距離以上離れると帰還する。縄張り内に戻るまでは `GUARD_ROOM` 戦略で行動する。

### CharacterData フィールド追加
| フィールド | 型 | デフォルト | 説明 |
|-----------|-----|-----------|------|
| `chase_range` | int | 10 | 追跡を維持する最大距離（スポーン地点からではなく現在位置から目標まで） |
| `territory_range` | int | 50 | 縄張り範囲（スポーン地点からの最大許容距離） |

全16敵種JSONに追加済み。種族特性に応じた値：
- ゴブリン系・ゾンビ・スケルトン系・dark-lord: chase=10, territory=50
- wolf/hobgoblin: chase=6-8, territory=8（縄張り守備タイプ）
- salamander: chase=6, territory=8
- harpy: chase=10, territory=12
- dark-knight: chase=10, territory=18
- dark-mage/dark-priest: chase=6, territory=10
- lich: chase=8, territory=15
- demon: chase=10, territory=20

### UnitAI 追加
- `_home_position: Vector2i` — `setup()` 時点の `member.grid_pos` を記録
- `get_home_position() -> Vector2i`
- `_generate_guard_room_queue()` — スポーン地点から2タイル以内なら `wait`、それ以外は `move_to_home`
- `_start_action()` の `"move_to_home"` ケース — `_goal = _home_position` にしてMOVING状態へ
- `_generate_queue()` WAIT ブランチに `"guard_room"` move_policy ケースを追加

### PartyLeaderAI 追加
- `Strategy.GUARD_ROOM = 5` を enum に追加
- `_apply_range_check(base_strat) -> Strategy` — `_evaluate_party_strategy()` の結果をラップ
  - ATTACK → GUARD_ROOM: 全員が縄張り外（dist_home > territory_range）かつ目標が遠い（dist_target > chase_range）
  - GUARD_ROOM → ATTACK: 1体でも縄張り内かつ射程内の目標あり
  - GUARD_ROOM → WAIT: 全員がスポーン地点2タイル以内に帰還完了
- `_all_members_out_of_range()` / `_any_member_can_engage()` / `_all_members_at_home()` ヘルパー
- `_assign_orders()` の effective_strat 決定に GUARD_ROOM ブランチを追加（`move_policy = "guard_room"`）
- 友好パーティー（`first_member.is_friendly`）にはrange_checkを適用しない

---

## DebugWindow（F1 デバッグウィンドウ）✅ 完了

### 概要
F1 キーで画面中央に表示/非表示トグル。ゲームは進行継続。
- CanvasLayer（layer=15）・`process_mode = PROCESS_MODE_ALWAYS`
- 画面幅 70%・高さ 80%（**背景パネルなし・完全透過**）

### レイアウト
```
  ■ DEBUG WINDOW  [F1で閉じる]  Floor: N

▶ [敵] ゴブリン(斧戦士)  生存:2/3  mv=追従  battle=攻撃  ...  ← 選択中（▶マーカー）
    ゴブリン[C] HP:30/55  ゴブリン[B] HP:45/55  ゴブリン[C] HP:0/55  ← メンバー横並び1行

  [NPC] アリス(弓使い)  生存:2/2  mv=探索  ...
    ★アリス[B] HP:80/80  マルク[C] HP:72/80

  ──────────────────────────────────────────────
  ▼ combat / ai ログ
  [AI] ゴブリン: 待機→攻撃（敵発見）
  ゴブリン の攻撃：ノエル へ中ダメージ（HP 72/80）
```

各パーティーブロック = ヘッダー行1行 + メンバー横並び1行 の計2行（旧：ヘッダー + メンバー×N行）。
メンバーフォーマット：`★名前[ランク] HP:x/y [ス][ガ]`。幅を超えるメンバーは "..." で打ち切り。

### リーダー選択とカメラ追跡
- 上下キーで各パーティーのリーダー行を循環選択（DebugWindow表示中のみ）
- 選択中リーダーは行頭に黄色「▶」マーカーを表示
- 選択するとそのリーダーキャラをカメラが追跡（`leader_selected` シグナル → `game_map.set_debug_follow_target()`）
- F1で閉じると選択をリセット・カメラは操作キャラの追跡に戻る
- 追跡中のキャラが死亡・解放された場合は `game_map._process()` で自動リセット

### 実装詳細

#### `scripts/debug_window.gd`
| 定数 | 値 | 説明 |
|------|-----|------|
| LOG_MAX | 50 | ログ最大件数 |
| FS | 12 | フォントサイズ |
| LINE_H | 15.0 | 1行の高さ（px） |
| REDRAW_INTERVAL | 0.20s | パーティー状態の再描画間隔 |

- `setup(party, get_enemy_managers, get_npc_managers, get_floor, hero)` — Callable で参照渡し（フロア遷移後も常に最新データを参照）
- `MessageLog.debug_log_added` シグナルを購読し、combat/ai メッセージをリアルタイムで受信
- `signal leader_selected(leader: Character)` — 上下キーでリーダーを選択したとき発火
- `clear_selection()` — 選択をリセット（F1 閉じ時に game_map から呼ぶ）
- `_build_leader_list()` — 描画前に呼び出し、描画順のリーダーキャラ一覧を構築
- `_navigate_selection(dir)` — `_leader_list` を使って前/次のリーダーに移動

#### `scripts/game_map.gd` 追加
- `var _debug_follow_target: Character` — デバッグカメラ追跡対象（null=通常追跡）
- `set_debug_follow_target(ch)` — カメラ追跡対象を切り替え。null で操作キャラに戻す
- `_on_debug_leader_selected(leader)` — `leader_selected` シグナルハンドラ
- `_process()` に `is_instance_valid` ガードを追加（追跡対象が freed になったら自動リセット）

#### `party_leader_ai.gd` 追加メソッド
- `get_current_strategy_name() -> String` — 現在の戦略を日本語名で返す

#### `party_manager.gd` 追加メソッド
- `get_strategy_name() -> String` — leader_ai の `get_current_strategy_name()` を委譲

### `MessageLog` の変更点
| 変更点 | 内容 |
|--------|------|
| `debug_log_added` シグナル追加 | `(text: String, color: Color)` — DebugWindow が購読 |
| `add_combat()` / `add_ai()` | `entries` に追加しない。`debug_log_added` のみ emit |
| `get_visible_entries()` | `entries`（system / battle のみ）をそのまま返す |
| `debug_visible` / `toggle_debug()` | 削除 |

MessageWindow は `get_visible_entries()` を使うため、system / battle メッセージのみ表示される。
OrderWindow のログ行も同様（`entries` には combat/ai が格納されなくなった）。

---

## Phase 13-11: フロア0敵構成見直し・NPCデフォルト指示修正 ✅ 完了

### フロア0（地下1階）敵構成変更
`dungeon_handcrafted.json` のフロア0をゴブリンのみで構成するよう変更。

| 部屋 | 変更前 | 変更後 |
|------|-------|-------|
| r1_2 | goblin×2, **goblin-archer** | goblin×3 |
| r1_7 | goblin×3, **goblin-archer** | goblin×4 |
| r1_8 | goblin×2, **goblin-mage** | goblin×3 |
| r1_9 | **hobgoblin**, goblin×2 | goblin×3 |
| r1_10 | goblin, **goblin-archer×2** | goblin×3 |
| r1_11 | goblin×2, **goblin-mage** | goblin×3 |
| r1_12 | **hobgoblin**, **goblin-archer**, **goblin-mage** | goblin×3 |

goblin-archer / goblin-mage / hobgoblin はフロア1（r2_*）以降に継続登場。

### NPC current_order デフォルト修正

#### `character.gd` — `current_order` デフォルト値変更
| キー | 変更前 | 変更後 |
|-----|-------|-------|
| `move` | `"cluster"` | `"follow"` |
| `combat` | `"aggressive"` | `"attack"` |
| `target` | `"nearest"` | `"same_as_leader"` |
| `on_low_hp` | `"keep_fighting"` | `"retreat"` |
| `item_pickup` | `"aggressive"` | `"passive"` |

旧値（`"aggressive"` / `"keep_fighting"` / `"cluster"`）はいずれも現在の OrderWindow の選択肢に存在しない廃止値だった。

#### `npc_manager.gd` — `_apply_attack_preset_to_member()` 追加
```gdscript
static func _apply_attack_preset_to_member(ch: Character) -> void:
    # クラス別に battle_policy="attack" プリセットを適用
    match ch.character_data.class_id:
        "healer":           rear / attack / lowest_hp_first
        "archer", "magician-*": rear / attack
        "fighter-axe":      rush / attack
        _:                  surround / attack
```

`setup()` でスポーン後に全メンバーへ呼び出し。`OrderWindow._apply_battle_policy_preset()` と同等のロジック。

### デバッグ時フォグオブウォー無効化（前セッション）
- `vision_system.gd`：`debug_show_all: bool` フラグ追加
- F1でDebugWindow表示中は `get_visible_tiles()` が空辞書を返す → 全タイル描画
- `update_visibility()` に `show_all` 引数追加 → 未訪問エリアの敵・NPCも visible=true

### NPCによる敵アクティブ化修正（前セッション）
- `vision_system._process()`：NPC エリアの `is_area_visited()` チェックを廃止
- 未訪問部屋に NPC が入ったとき `friendly_areas` に加わり、敵AIが正しく起動する

---

## PartyManager 統合リファクタリング ✅ 完了

### 概要
NpcManager・EnemyManager を廃止し、PartyManager に統合。同時に hero_manager を NpcManager から PartyManager に切り替え、PartyLeaderPlayer を接続した。

### 変更内容

#### PartyManager（`party_manager.gd`）
- `party_type` プロパティ（`"enemy"` / `"npc"` / `"player"`）を追加
- `setup()` を `party_type` で分岐:
  - `"enemy"`: `_setup_enemy()` → 敵JSON読み込みスポーン（旧 PartyManager.setup のまま）
  - `"npc"`: `_setup_npc()` → CharacterGenerator でランダム生成＋初期装備付与（旧 NpcManager.setup を移植）
- `_spawn_enemy_member()`: 旧 `_spawn_member()` をリネーム
- `_spawn_npc_member()`: 旧 NpcManager._spawn_member() を移植
- `_create_leader_ai()` を `party_type` で分岐:
  - `"player"` → `PartyLeaderPlayer.new()`
  - `"npc"` → `NpcLeaderAI.new()`
  - `"enemy"` → `_create_enemy_leader_ai()` で種族別分岐
- `set_enemy_list()` / `_enemy_list`: NpcManager から移植。NpcLeaderAI / PartyLeaderPlayer 両方に転送
- `_apply_attack_preset_to_member()`: NpcManager から移植（static メソッド）

#### hero_manager（`game_map.gd`）
- 型を `NpcManager` → `PartyManager` に変更
- `party_type = "player"` を設定 → `_create_leader_ai()` が `PartyLeaderPlayer` を生成
- `suppress_floor_navigation = true` の行を削除（PartyLeaderPlayer はフロア遷移判断を持たない）

#### 削除ファイル
- `npc_manager.gd`: PartyManager に統合完了
- `enemy_manager.gd`: 後方互換ラッパー（空クラス）を廃止

#### 型参照の置き換え
以下のファイルで `NpcManager` / `EnemyManager` の型アノテーション・キャストを `PartyManager` に変更:
- `game_map.gd`: 変数宣言・for ループ・as キャスト（約80箇所）
- `vision_system.gd`: `add_enemy_manager()` / `add_npc_manager()` 等の引数型
- `right_panel.gd`: `setup()` / 描画ループ内のキャスト
- `dialogue_trigger.gd`: シグナル引数・setup()引数・メソッド引数
- `npc_dialogue_window.gd`: `show_dialogue()` / `show_party_full()` の引数
- `dialogue_window.gd`: 変数型・メソッド引数
- `debug_window.gd`: 描画ループ内のキャスト
- `base_ai.gd` / `enemy_ai.gd`: コメントのみ

---

## パーティー戦力評価メソッド ✅ 完了

### 概要
PartyLeader に `_evaluate_party_strength()` を追加し、NpcLeaderAI の適正フロア算出で使用。

### `_evaluate_party_strength()` （`party_leader.gd`）
```
戦力値 = ランク和 × HP充足率
ランク和 = 生存メンバー全員の RANK_VALUES（C=3, B=4, A=5, S=6）の合計
HP充足率 = min(1.0, (合計現HP + 合計ヒールポーション回復量) / 合計max_hp)
```
- ヒールポーションのみ計算に含める（MP/SPポーションは含めない）
- 生存メンバーが0人の場合は 0.0 を返す
- `_calc_total_potion_hp()` ヘルパーで HP ポーション回復量を合算

### `RANK_VALUES` の移動
`NpcLeaderAI` から `PartyLeader` 基底クラスに移動。全サブクラスから参照可能。

### NpcLeaderAI `_get_target_floor()` の変更
- 旧: ランク和のみで適正フロアを算出 + HP最低値チェック + MP/SPチェック
- 新: `_evaluate_party_strength()` の戻り値で適正フロアを算出 + MP/SPチェック
- HP チェックは `_evaluate_party_strength()` に統合（HP充足率がランク和に乗算されるため別途チェック不要）
- MP/SP チェック（ポーション込み平均充足率 < NPC_ENERGY_THRESHOLD → 目標フロア-1）は従来通り
- `_calc_recoverable_hp()` を削除（`_calc_total_potion_hp()` に統合済み）

### FLOOR_RANK 閾値の検証
`{0: 0, 1: 8, 2: 13, 3: 18, 4: 24}` — 調整不要。
- Cランク3人HP満タン: 戦力9.0 → F1適正（≥8）
- Bランク4人HP満タン: 戦力16.0 → F2適正（≥13）
- Bランク4人HP半分: 戦力8.0 → F1適正（F2の13に届かず自動降格）

---

## 状態ラベル・戦況判断システム ✅ 完了

### 状態ラベル（condition）

`Character.get_condition()` メソッドを追加。HP 割合に基づく 3 段階ラベルを返す。
閾値は `GlobalConstants` で管理:

| ラベル | HP割合 | 定数 |
|--------|--------|------|
| `"healthy"` | 75%以上 | `CONDITION_HEALTHY_THRESHOLD = 0.75` |
| `"wounded"` | 35%以上75%未満 | `CONDITION_WOUNDED_THRESHOLD = 0.35` |
| `"critical"` | 35%未満 | — |

旧実装（`_condition()` ローカル関数 × 5箇所コピペ、閾値不統一）を `Character.get_condition()` に統一。
全5箇所の `_condition()` 関数を削除し `get_condition()` 呼び出しに置き換え済み:
- `left_panel.gd` / `right_panel.gd` / `dialogue_window.gd`: UI表示で使用
- `enemy_ai.gd` / `hud.gd`: 旧コード（未使用だが整合性のため統一）

### HP% 推定関数

`PartyLeader._estimate_hp_ratio_from_condition(condition)`:
敵の戦力を過大評価する安全側に倒すため、各ラベルの閾値範囲の最大値を返す。

| condition | 推定HP% | 根拠 |
|-----------|---------|------|
| `"healthy"` | 1.0 | 75%〜100% の最大値 |
| `"wounded"` | 0.75 | 35%〜75% の最大値 |
| `"critical"` | 0.35 | 0%〜35% の最大値 |
| 不明 | 1.0 | 安全側 |

### `_evaluate_party_strength_for()` 拡張

`_evaluate_party_strength()` を汎用化:
```
func _evaluate_party_strength_for(members: Array, use_estimated_hp: bool = false) -> float
```
- `use_estimated_hp = false`（自軍）: 正確な HP% + ポーション回復量
- `use_estimated_hp = true`（敵）: `get_condition()` → `_estimate_hp_ratio_from_condition()` で HP 推定。ポーション回復量 = 0

既存の `_evaluate_party_strength()` は `_evaluate_party_strength_for(_party_members, false)` のラッパーとして残す。

### `_evaluate_combat_situation()` 実装

PartyLeader の共通メソッド。自パーティーのリーダーのエリア＋隣接エリアにいる敵の戦力を比較して戦況を分類する。

**対象エリアの決定**: リーダー（生存メンバー先頭）のエリア `my_area` と、`MapData.get_adjacent_areas(my_area)` で取得した隣接エリアを `target_areas` 辞書に収集する。通路にもエリアID（`c{フロア番号}_{連番}`。例：`c1_1`）が付与されているため、`部屋 ←→ 通路 ←→ 部屋` が隣接として扱われる。これにより部屋の境界付近で戦っても戦況がぶれない。

**対象の敵**: `_get_opposing_characters()` 仮想メソッドで取得し、同フロアかつ `target_areas` に属するエリアにいる敵のみフィルタ。
- EnemyLeaderAI（デフォルト）: `_friendly_list`（プレイヤー・NPC）
- NpcLeaderAI: `_enemy_list`（敵キャラ）
- PartyLeaderPlayer: `_enemy_list`（敵キャラ）

**判定ロジック**:
```
ratio = 自軍戦力 / 敵戦力
```

| 戦況 | enum値 | ratio 条件 | 定数 |
|------|--------|-----------|------|
| SAFE | 0 | 敵なし or 敵戦力0 | — |
| OVERWHELMING | 1 | ratio ≥ 2.0 | `COMBAT_RATIO_OVERWHELMING` |
| ADVANTAGE | 2 | ratio ≥ 1.2 | `COMBAT_RATIO_ADVANTAGE` |
| EVEN | 3 | ratio ≥ 0.8 | `COMBAT_RATIO_EVEN` |
| DISADVANTAGE | 4 | ratio ≥ 0.5 | `COMBAT_RATIO_DISADVANTAGE` |
| CRITICAL | 5 | ratio < 0.5 | — |

`GlobalConstants.CombatSituation` enum で定義。

**自軍側のフィルタ**: `_get_my_combat_members()` で取得したメンバーも `target_areas` に属するエリアに絞ってランク和・戦力を算出する（別フロア・離れた部屋の仲間は戦闘に参加できないため）。

**同陣営の他パーティー加算**: `_all_members` から以下の条件を満たすキャラを `ally_area_others` として収集し、そのランク和・戦力を自軍側に加算する:
- `is_friendly` が自軍と同じ（プレイヤー/NPC連合、または敵パーティー同士）
- 自パーティーのメンバーではない（二重カウント防止）
- 同フロアかつ `target_areas` に属するエリアにいる生存メンバー
- ポーション回復量は加算せず、HP状態は condition ラベルから推定（`use_estimated_hp=true`）

これにより、プレイヤー＋未加入NPCが同じ部屋で戦っているとき、敵はより逃げやすくなり、逆に敵が密集しているエリアでは敵が強気になる。

**HP充足率（HpStatus）は自パーティーのみ**で算出する（他パーティーのポーション所持数は把握不可のため）。

**戻り値**: `{ "situation": int, "power_balance": int, "hp_status": int, "my_rank_sum": int, "enemy_rank_sum": int }`

### 通路のエリアID

- ダンジョンJSON（`dungeon_handcrafted.json`）の各 `corridors` エントリに `id` フィールド（例：`c1_1`）を付与する
- 命名規則：`c{フロア番号}_{連番}`。連番は各フロアで1から開始
- `DungeonBuilder._carve_corridor()` は JSON の `id` を優先して corridor タイルに設定する（未指定時は従来形式 `corridor_{from}_{to}` にフォールバック）
- 隣接関係は `MapData.build_adjacency()` がタイル隣接から自動構築するため、明示的な隣接定義は不要

### 呼び出しタイミング

- `PartyLeader._process()`: 再評価タイマー（1.5秒間隔）で `_evaluate_combat_situation()` → `_assign_orders()`
- `notify_situation_changed()`: メンバー死亡時等に即時再評価

結果は `_assign_orders()` → `receive_order()` の `"combat_situation"` フィールドに含めて各 UnitAI に伝達。
UnitAI は `_combat_situation` フィールドに保存し、以下で参照する:
- `_is_combat_safe()`: 戦況が SAFE かどうかを返すヘルパー
- アイテム取得ナビゲーション: `_is_combat_safe()` が true のときのみ `item_pickup` 指示に従って拾いに行く（旧: `Strategy.WAIT` のときのみ）
- SAFE 時の1マス移動完了ごとにアイテムチェックを実行（`_State.MOVING` の `_timer <= 0` タイミング）。範囲内にアイテムがあればキューを差し替えてアイテムに向かう
- 将来: 特殊攻撃の AI 接続で DISADVANTAGE 時の積極使用判断に参照予定

### NpcLeaderAI の撤退ロジック

`_evaluate_party_strategy()` に戦況判断を組み込み:

| 戦況 | 戦略 |
|------|------|
| SAFE（敵なし） | EXPLORE（既存の探索ロジック） |
| OVERWHELMING / ADVANTAGE / EVEN | ATTACK（既存のまま） |
| DISADVANTAGE | ATTACK（将来：特殊攻撃を積極使用） |
| CRITICAL | FLEE（撤退。部屋から離脱） |

- FLEE → `party_fleeing=true` で UnitAI に伝達。UnitAI._determine_effective_action() が逃走を決定
- 部屋から離脱すると同エリアに敵がいなくなり、次の再評価で SAFE → EXPLORE に復帰
- `_get_explore_move_policy()` で目標フロアを再計算し、HP/MP/SP が不足なら上の階へ撤退
- EnemyLeaderAI には適用しない（種族固有 AI の既存 FLEE 判断を維持）

---

## 特殊攻撃のAI接続 ✅ 完了

### 戦況判断の拡張
`_evaluate_combat_situation()` の戻り値に `power_balance` と `hp_status` を追加:
- `power_balance` (PowerBalance enum): ランク和のみの戦力比（HP を含めない）
- `hp_status` (HpStatus enum): 自軍HP充足率（ポーション込み）
- `situation` (CombatSituation enum): 従来通りの総合判断

### 特殊攻撃の発動ロジック
`UnitAI._generate_special_attack_queue(target)` が特殊攻撃キュー生成の本体。判定は次の3段階を順に評価する:

1. **指示チェック** — `_should_use_special_skill()` が `special_skill` 指示（aggressive / strong_enemy / disadvantage / never）と `power_balance` / `hp_status` を照合。false なら空配列を返す（通常攻撃にフォールバック）
2. **コストチェック** — クラスの `v_slot_mp_cost` / `v_slot_sp_cost` のいずれかを満たす MP または SP を所持しているか確認。どちらも不足なら空配列
3. **クラスごとの使用条件** — `match cd.class_id` でクラスごとに発動判定（下表）。条件成立時は `[{"action": "move_to_attack"}, {"action": "v_attack"}]` を返す（炎陣は `move_to_attack` なし）

定数 `GlobalConstants.SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES = 2` を `min_adj` に読み込んで使う。

| クラス | 追加条件 | 備考 |
|--------|---------|------|
| fighter-sword（突進斬り） | `_count_adjacent_enemies() >= min_adj` **かつ** `_can_rush_slash_through()` が true | target が有効である必要あり |
| fighter-axe（振り回し） | `_count_adjacent_enemies() >= min_adj` | target 不要（周囲攻撃） |
| scout（スライディング） | `_count_adjacent_enemies() >= min_adj` | target が有効である必要あり。包囲脱出兼ダメージ |
| archer（ヘッドショット） | target が有効 | 通常攻撃の代わりに使用 |
| magician-fire（炎陣） | `_count_adjacent_enemies() >= min_adj` | target 不要。`v_attack` のみ（接近しない） |
| magician-water（無力化水魔法） | target が有効 かつ `not target.is_stunned` | スタン重ねがけを防止 |
| healer（防御バフ） | — | `_generate_buff_queue()` 側で別管理 |

### 特殊攻撃の補助関数（`unit_ai.gd`）

| 関数 | 役割 |
|------|------|
| `_count_adjacent_enemies()` | 自分の周囲 8 マス（斜め含む）にいる敵陣営生存キャラの占有タイルをスキャンし、重なった敵の数を返す。特殊攻撃の発動条件で使う |
| `_can_rush_slash_through()` | 突進斬りの経路判定。`Character.dir_to_vec(_member.facing)` で前方ベクトルを算出し、`pos1 = grid_pos + dir` / `pos2 = grid_pos + dir * 2` を対象に、(a) いずれかに敵がいる & (b) pos2 が空き FLOOR なら pos2 に着地、ダメなら pos1 に着地、のどちらかを満たすとき true |
| `_enemy_on_tile(pos)` | 指定タイルに敵陣営の生存キャラが占有しているか。同フロア・敵陣営・HP>0 の条件付き。突進斬りの経路判定で使う |
| `_is_empty_floor(pos)` | 指定タイルが歩行可能（`MapData.is_walkable_for(pos, false)`）かつ誰も占有していないか。突進斬りの着地判定で使う |

### 関連ファイル・行番号（現状）

| 項目 | 位置 |
|------|------|
| `SPECIAL_ATTACK_MIN_ADJACENT_ENEMIES` 定数定義 | `scripts/global_constants.gd:81` |
| `_generate_special_attack_queue()` 判定本体 | `scripts/unit_ai.gd:1977` |
| 呼び出し元（通常攻撃キュー生成内） | `scripts/unit_ai.gd:732` |
| `_count_adjacent_enemies()` | `scripts/unit_ai.gd:2025` |
| `_can_rush_slash_through()` | `scripts/unit_ai.gd:2051` |
| `_enemy_on_tile()` | `scripts/unit_ai.gd:2071` |
| `_is_empty_floor()` | `scripts/unit_ai.gd:2087` |

### receive_order への追加フィールド
- `special_skill`: `current_order` から読み込み（aggressive / strong_enemy / disadvantage / never）

### デフォルト設定
- `character.gd` の `current_order` に `special_skill: "strong_enemy"` を追加
- NPC の `_apply_attack_preset_to_member()` でも `"strong_enemy"` を設定

### AI Vスロット攻撃の実行
`_start_action` に `"v_attack"` ケースを追加。`_execute_v_attack()` でクラス別に分岐:

| クラス | メソッド | 処理 |
|--------|---------|------|
| fighter-sword | `_v_rush_slash` | ターゲット方向に最大2マス突進、経路上の敵にダメージ、空きマスに着地 |
| fighter-axe | `_v_whirlwind` | 周囲8マスの敵全員にダメージ |
| archer | `_v_headshot` | 即死耐性なし→`die()`で即死（防御・耐性を無視）、あり→3倍ダメージ |
| magician-fire | `_v_flame_circle` | 自分中心に半径3マスの炎陣設置 |
| magician-water | `_v_water_stun` | ターゲットに水弾＋2.5秒スタン |
| scout | `_v_sliding` | ターゲット方向に3マスダッシュ、敵・味方すり抜け |

- 特殊攻撃の `take_damage` は `suppress_battle_msg=true` で通常メッセージを抑制
- SP回復後にキューを再生成して特殊攻撃に切り替える仕組み（`_has_v_slot_cost()` チェック）
- キューに `v_attack` が含まれている場合はキュー再生成をスキップ

### エフェクト画像
```
assets/images/effects/
  arrow.png          矢
  fire_bullet.png    火弾
  water_bullet.png   水弾
  thunder_bullet.png 雷弾
  flame.png          炎陣エフェクト（スケール脈動＋アルファ揺らぎ）
  whirlpool.png      渦エフェクト（水魔法スタン、回転表示）
```

### メッセージ表記方針
- バトルメッセージは自然言語で記述し、記号的表現（`HP+30` 等）を避ける
- アイテム名統一: ヒールポーション / MPポーション / SPポーション（上級ポーション廃止）

---

## UnitAI Strategy リファクタリング ✅ 完了

### 概要
UnitAI の `enum Strategy { ATTACK, FLEE, WAIT }` を行動決定の中間変数としてのみ使用するように変更。
PartyLeader._assign_orders() が `strategy` を算出して渡す方式を廃止し、`combat` / `on_low_hp` / `party_fleeing` / `combat_situation` をそのまま UnitAI に渡す方式に変更。

### 変更内容

#### UnitAI（`unit_ai.gd`）
- `_resolve_strategy()` 仮想メソッドを廃止
- `_determine_effective_action() -> int` を新設（行動の最終決定）
  - 判定優先順位: party_fleeing → _should_self_flee() → _can_attack() → on_low_hp → combat_safe → combat
  - 戻り値: 0=ATTACK, 1=FLEE, 2=WAIT（内部判断用 int）
- 種族フックメソッドを新設:
  - `_should_ignore_flee() -> bool`: FLEE を無視する種族が true を返す
  - `_should_self_flee() -> bool`: 自己判断で逃走する種族が true を返す
  - `_can_attack() -> bool`: 攻撃不能な種族が false を返す
- `_generate_queue(strategy: int, target)` にシグネチャ変更
- `_generate_move_queue()` ヘルパーを追加（WAIT/ATTACK(ターゲットなし)共通の移動キュー生成）
- `_fallback_evaluate()` → `_fallback_evaluate_action()` にリネーム

#### PartyLeader（`party_leader.gd`）
- `_assign_orders()` から `effective_strat` 算出ロジックを削除
- `receive_order()` に渡す辞書から `"strategy"` キーを削除
- 代わりに `"party_fleeing"` / `"combat"` / `"on_low_hp"` / `"combat_situation"` をそのまま渡す

#### 種族 UnitAI サブクラス（12ファイル）
- 全ファイルの `_resolve_strategy()` を削除し、フックメソッドに置き換え:

| 種族 | _should_ignore_flee | _should_self_flee | _can_attack |
|------|-------------------|------------------|-------------|
| dark_knight / dark_lord / harpy / hobgoblin / zombie / salamander | true | — | — |
| dark_priest | true | — | — |
| dark_mage / lich | true | — | MP >= cost |
| goblin / goblin_archer | — | HP < 30% | — |
| goblin_mage | — | HP < 30% | MP >= cost |

- goblin_archer_unit_ai / salamander_unit_ai: `_generate_queue` シグネチャを `int` に変更

---

## Git / GitHub
- リポジトリ: https://github.com/komuro72/trpg
- ブランチ: master
- `.godot/` フォルダはGitignore済み
- `.uid` ファイルはコミット対象（Godot 4 のリソース解決に必要）

## メッセージウィンドウ アイコンサイズ調整（試験的）

### 目的
中央テキスト部の顔アイコンが大きく、メッセージが速く流れると追えない問題への対応。1メッセージあたりの縦幅を縮小して表示行数を増やす。

### 定数（`message_window.gd` 冒頭）
- `ICON_SCALE_RATIO = 1.0 / 3.0`：旧 2.0/3.0 の半分。GRID_SIZE に対する顔アイコン比率
- `ICON_MIN_SIZE = 20`：最小ピクセルサイズ
- `LINE_HEIGHT_RATIO = 1.25`：旧 1.5 から縮小。fs * この比率 = 行間

### 影響範囲
- 中央テキスト部の attacker/defender 顔アイコン（face.png）のみ
- 左右の上半身画像（front.png）は変更なし（`img_size = box_h` で背景高さ依存）

### 元に戻す手順
- `ICON_SCALE_RATIO = 2.0 / 3.0`、`LINE_HEIGHT_RATIO = 1.5` に戻す

## フロア間メンバー追従（UnitAI 側に移行）

### 設計
個別指示の移動方針はフロアの概念を持たないため、`cluster` / `follow` / `same_room`（リーダーを追う系）は UnitAI が「リーダーが別フロアにいるなら階段で追う」と解釈する。

### 実装
`unit_ai.gd:_generate_move_queue()` 冒頭で判定:
```gdscript
if _move_policy in ["cluster", "follow", "same_room"] \
        and _leader_ref != null and is_instance_valid(_leader_ref) \
        and _leader_ref != _member \
        and _leader_ref.current_floor != _member.current_floor:
    var dir = sign(_leader_ref.current_floor - _member.current_floor)
    return _generate_stair_queue(dir, true)
```

- `_leader_ref` は `receive_order` の `leader` フィールドから取得（`_assign_orders()` で formation_ref として渡される）
- `ignore_visited=true` で訪問済み制限を緩和（リーダーが既に階段を使っているため未踏でも追従可能）

### 適用範囲
- 対象: cluster / follow / same_room（リーダー追従系）
- 対象外: standby / explore / guard_room / stairs_down / stairs_up（自律 or 既に階段方針）
- 合流済みパーティー（joined_to_player=true）は `_generate_queue` 冒頭の `_generate_floor_follow_queue()`（hero 追従）が先に処理するため、ここには到達しない

### 既存仕様との関係
- 廃止: `party_leader.gd:_assign_orders()` の「クロスフロア追従ブロック」（move_policy を stairs_down/up に書き換える特殊処理）
- 維持: 既存の階段使用フロー（`_generate_stair_queue` → 階段タイル到達 → `_check_npc_member_stairs` → `_transition_single_npc_member`）

## DebugWindow メンバー目的表示

`UnitAI.get_debug_goal_str()` が現在の状態・キュー先頭・move_policy・leader_ref から短い説明文を返す。`_state` ラベル（IDLE/MOV/WAIT/ATKp/ATKpost）を末尾に併記する。

### 主な出力例
| 出力 | 状況 |
|------|------|
| `→DOWN階段(15,3)[MOV]` | 階段に向かって移動中 |
| `→攻撃Goblin[MOV]` | 攻撃対象に接近中 |
| `→Mary回復[MOV]` | 回復対象へ移動中 |
| `L追従(DOWN/キュー空/IDLE)` | リーダー追従系・別フロア・IDLE で再評価待ち |
| `L追従(DOWN/キュー空/WAIT)` | 同上・wait アクション執行中（3秒） |
| `[cluster]キュー空(IDLE)` | 同フロア・IDLE で再評価待ち |
| `攻撃→Goblin[ATKp]` | 攻撃前隙中 |

### 経路: PartyManager → PartyLeader → UnitAI
- `PartyManager.get_member_goal_str(member)` → `_leader_ai.get_member_goal_str(name)` → `unit_ai.get_debug_goal_str()`
- DebugWindow `_draw_members_goals_row` が各メンバーの結果を1行に横並び描画

## NPCリーダー降下時の追従ロジック（最終形）

### 配置: `unit_ai.gd:_generate_queue` 冒頭
戦略分岐（FLEE/ATTACK/WAIT）の前にクロスフロア追従を判定する。これによりリーダー単独降下で `Strategy.FLEE` になったときも、cluster/follow/same_room メンバーは階段優先で追従する。

```gdscript
if _move_policy in ["cluster", "follow", "same_room"] \
        and _leader_ref != null and is_instance_valid(_leader_ref) \
        and _leader_ref != _member \
        and _leader_ref.current_floor != _member.current_floor:
    var follow_dir: int = sign(_leader_ref.current_floor - _member.current_floor)
    return _generate_stair_queue(follow_dir, true)
```

### 即時通知: `party_leader.gd:_process`
リーダーの `current_floor` 変化を毎フレーム検知し、変化したら全 UnitAI に `notify_situation_changed()` を発火。

### WAIT中断: `unit_ai.gd:notify_situation_changed`
WAIT 中なら `_state = IDLE`、`_queue.clear()` で 3秒待たずに再評価できるようにする。

### 押し出し: `unit_ai.gd:_step_toward_goal`
明示的な `stairs_down/up` だけでなく、クロスフロア追従中（cluster/follow/same_room + leader 別フロア）も `_try_push_friendly_at` を呼んで階段周辺の友好キャラを押し出す。

## メッセージウィンドウ（追加）

### 対象なしバトルメッセージ
`add_battle(attacker_data, defender_data=null, ...)` で `defender_data` が null のときは矢印 `→` と右側アイコンを描画しない（ポーション使用・スライディング・空振り等の単独行動メッセージ用）。テキスト位置（`battle_text_x`）は不変なので対象ありメッセージと左揃えで揃う。

### per-target 表示
突進斬り・振り回しは敵1体ごとに「○○が突進斬りで△△を攻撃し、大ダメージを与えた」形式で `add_battle` を呼ぶ。`take_damage(...,suppress_battle_msg=true)` で per-hit の通常ダメージメッセージを抑止し、`_emit_v_skill_battle_msg(skill_name, atk, def, dmg)` ヘルパが HP 差分から `Character._damage_label()` で段階ラベル付与する。

---

## ダンジョン再構成（5フロア×20部屋） ✅ 完了

### 概要
従来の5フロア×12部屋（フロア0のみNPC4部屋/11人）構成を、**5フロア×20部屋・階段3か所**に拡張。生成は `work/gen_dungeon.py` の Python スクリプトで行い、JSON を直接出力する方式に変更（今後の再生成も容易）。

### レイアウト
- グリッド：4列 × 5行 = 20部屋／フロア
- 部屋サイズ：9×7（内部 7×5）
- 部屋ピッチ：横11タイル・縦9タイル（部屋間の壁2タイル）
- マップ外接：約44×45 + 境界6タイル = 約58×59
- 通路：隣接（右・下）をすべて結ぶ → 31本／フロア
- 階段位置：各部屋中央 (rx+4, ry+3)

### 部屋配分
| フロア | 主人公 | NPC | 敵部屋 | 上り階段 | 下り階段 | 備考 |
|-------|-------|-----|-------|--------|--------|------|
| 0 (地下1層) | 1 | 8パーティー / 12人 | 11（下り階段3部屋含む） | — | 3 | 空き0 |
| 1 (地下2層) | — | — | 17（下り階段3部屋含む） | 3（敵なし） | 3 | 空き0 |
| 2 (地下3層) | — | — | 17（下り階段3部屋含む） | 3（敵なし） | 3 | 空き0 |
| 3 (地下4層) | — | — | 17（下り階段3部屋含む） | 3（敵なし） | 3 | 空き0 |
| 4 (地下5層) | — | — | 17（ボス1+通常16） | 3（敵なし） | — | 空き0 |

**上り階段部屋は敵初期配置なし**（到着時の安全地帯。追跡してきた敵は入れる）

### NPC配置（フロア0のみ）
- 1人パーティー × 5
- 2人パーティー × 2
- 3人パーティー × 1
- 計 **8パーティー / 12人**
- 配置部屋：`r1_2, r1_3, r1_4, r1_5, r1_6, r1_7, r1_9, r1_10`（r1_8を除くフロア0前半）
- クラス：archer / fighter-sword / fighter-axe / healer / magician-fire / magician-water / scout をランダム選出
- 画像セット：14種をランダム割当（可能な限り重複回避）

### 敵配分
| フロア | 種族プール | パーティー人数 |
|-------|-----------|-------------|
| 0 | goblin, goblin_archer（ゴブリンのみ） | 2 |
| 1 | goblin, goblin_archer, goblin_mage, hobgoblin, wolf | 2〜3 |
| 2 | hobgoblin, wolf, zombie, harpy, salamander, dark_priest | 3〜4 |
| 3 | dark_knight, dark_mage, dark_priest, skeleton, skeleton_archer, lich | 4〜5 |
| 4 | dark_knight, demon, lich, skeleton, skeleton_archer | 4〜5 |

### ボス部屋（フロア4）
- 部屋ID：`r5_18`（最下行2列目 col=1, row=4）
- 構成：dark_lord 1体 + demon 1体 + lich 1体 + dark_knight 2体
- 部屋名：「魔王の玉座の間」
- ドロップ：魔王の大剣（power28/block_right_front20）、深淵の鎧（phys28/mag14）、ヒールポーション×3

### 非矩形部屋パターン
占有マス（敵/NPC/プレイヤー/階段位置）と衝突しない10パターンに絞って約25%の部屋に適用：
- `L1`〜`L4`：四隅のL字欠け
- `T1` / `T2`：上下のT字欠け
- `O1`：八角形風（四隅壁）
- `P2` / `P4` / `P6`：壁際の柱・障害物

入口部屋（フロア0のr1_1）とボス部屋（r5_18）には適用しない（スポーン位置保護）。

### 生成スクリプト
- パス：`work/gen_dungeon.py`
- 実行：`PYTHONIOENCODING=utf-8 python work/gen_dungeon.py > assets/master/maps/dungeon_handcrafted.json`
- 乱数シード固定（20260415）により再現性確保
- `work/` 配下はGodotのインポート対象外（CLAUDE.md記載）

### 既存仕様との関係
- Phase 12-8 の「各フロア階段3か所配置」と整合
- Phase 12-9 の「NPC配置をフロア0に集約」を継承・拡張（4部屋11人 → 8パーティー12人）
- Phase 13-4 の「49部屋に非矩形形状」は本再構成で置き換え（100部屋中 約25% に適用）
- Phase 13-11 の「フロア0をゴブリンのみ」は継承

---

## 時間停止オーバーレイ ✅ 完了

### 目的
`GlobalConstants.world_time_running = false` の間、ゲーム画面を少し暗く表示してプレイヤーに時間停止状態を視覚的に知らせる。

### 実装（`time_stop_overlay.gd`）
- `CanvasLayer` で `layer = 5`（ゲーム画面 layer=0 より手前・UI layer=10以上より奥）
- アンカー全画面の `ColorRect`（色 `Color(0, 0, 0.05, 0.35)`）を子に持ち、`_process` で `world_time_running` を監視して `visible` を切替
- フェードなし（瞬時切替）
- `mouse_filter = MOUSE_FILTER_IGNORE` で入力を透過

### 設置
- `game_map.gd:_finish_setup()` → `_setup_time_stop_overlay()` で生成

---

## 階段上の再遷移抑止 ✅ 完了

### 症状
プレイヤーが階段を下りて遷移先の階段（反対側）の上に静止したまま `_stair_cooldown`（1.5秒）が切れると、`_check_stairs_step()` が階段タイルを検知して再遷移してしまっていた。

### 修正
`game_map.gd:_check_stairs_step()` に `player_controller.stair_just_transitioned` をチェックするガードを追加。
```gdscript
if player_controller != null and player_controller.stair_just_transitioned:
    return
```
`stair_just_transitioned` は PlayerController が階段タイルから出た瞬間に false にリセットするため、プレイヤーが階段上に何秒留まっても再遷移せず、一歩外に出て再度戻れば通常通り遷移する。

---

## 安全部屋（安全エリア）システム ✅ 完了

### 概要
フロア0中央に「安全の広間」（`r1_10`・15×11タイル）を配置し、敵AIが進入できない安全エリアとして実装。プレイヤーと全NPCパーティー（8パーティー/12人）がここからスタートする。

### MapData 拡張（`map_data.gd`）
- **`_safe_tiles: Dictionary`**（Vector2i → true）：安全タイル集合
- **`mark_safe_tile(pos)`**：DungeonBuilder が使用。タイルを安全エリアに追加
- **`is_safe_tile(pos) -> bool`**：指定座標が安全エリアかどうか
- **`is_walkable_for_enemy(pos, flying) -> bool`**：`is_walkable_for` と同条件＋安全タイルは false を返す

### DungeonBuilder 拡張（`dungeon_builder.gd`）
- 部屋JSONに `"is_safe_room": true` フラグを追加
- `_carve_room` で `is_safe_room=true` の部屋の内部FLOORタイルをすべて `mark_safe_tile()`
- 安全部屋のCORRIDOR境界タイル（通路との接続箇所）は安全タイルに含めない（敵が通路まで来られる仕様）
- 複数NPCパーティーを1部屋に配置する場合、部屋JSONに `"npc_parties_multi": [...]` 配列で指定する（従来の `"npc_party"` とは別フィールド）
- 入口部屋（`is_entrance=true`）には敵を配置しないが、NPC配置は許可する（安全部屋が入口兼NPC集合地となるため）

### UnitAI 側のフィルタ（`unit_ai.gd`）
- `_is_walkable_for_self(pos) -> bool` ヘルパを新設：`_map_data.is_walkable_for(pos, _member.is_flying)` に加えて、`_member.is_friendly == false` かつ `is_safe_tile(pos)` なら false を返す
- A*経路探索（`_astar`）・移動可否判定・後方タイル検索など、既存の `_map_data.is_walkable_for(pos, _member.is_flying)` 呼び出しを `_is_walkable_for_self(pos)` に一括置換（約10箇所）
- 友好キャラ（プレイヤー・NPC）は従来通り通過可能・敵のみ安全タイルを拒否

### 安全部屋の配置仕様（フロア0のみ）
- 位置：フロア中央（グリッド(col=1, row=2)）・座標 x=10, y=18
- サイズ：15×11（通常の部屋 9×7 より大きい）
- 周辺の4部屋（r1_6/r1_9/r1_11/r1_14）と自動的に通路接続
- 部屋名：「安全の広間」
- 部屋ID：`r1_10`
- `is_entrance: true` かつ `is_safe_room: true`

### プレイヤー・NPC配置
- プレイヤー：部屋中央 (17, 23) にfighter-sword（主人公）
- NPC 8パーティー（計12人）：
  - 1人パーティー × 5（列: y=20/y=22）
  - 2人パーティー × 2（列: y=22/y=24）
  - 3人パーティー × 1（列: y=24/y=26）
- クラス：archer / fighter-sword / fighter-axe / healer / magician-fire / magician-water / scout をランダム選出
- 画像セット：14種を可能な限り重複なく割当

### フロア構成の更新
| フロア | 主人公 | NPC | 敵部屋 | 上り階段 | 下り階段 | 備考 |
|-------|-------|-----|-------|--------|--------|------|
| 0 (地下1層) | 1 | 8パーティー/12人（全員安全部屋） | 19（下り階段3部屋含む） | — | 3 | 安全部屋1 + 敵19 = 20 |
| 1 (地下2層) | — | — | 17（下り階段3部屋含む） | 3（敵なし） | 3 | 空き0 |
| 2 (地下3層) | — | — | 17（下り階段3部屋含む） | 3（敵なし） | 3 | 空き0 |
| 3 (地下4層) | — | — | 17（下り階段3部屋含む） | 3（敵なし） | 3 | 空き0 |
| 4 (地下5層) | — | — | 17（ボス含む） | 3（敵なし） | — | 空き0 |

旧仕様（フロア0: 1プレイヤー部屋 + 8 NPC部屋 + 11 敵部屋）から変更。安全部屋方式により主人公と全NPCが1部屋に集約される。

---

## 撤退先ロジック ✅ 完了

### 概要
味方パーティー（プレイヤー・NPC）が `Strategy.FLEE` になったとき、従来の「脅威の反対方向へ5マス」から、明確な撤退先に向かうよう変更。

### 撤退先の決定（`unit_ai.gd:_find_friendly_retreat_goal()`）
1. MapData に安全タイル（`_safe_tiles`）があれば **最寄りの安全タイル** を目的地とする（フロア0：安全部屋の内部タイル）
2. 安全タイルがないフロアでは **最寄りの上り階段**（`STAIRS_UP`）を目的地とする（フロア1〜4）
3. どちらも見つからない場合は `Vector2i(-1, -1)` を返して待機

### FLEE 分岐の変更（`unit_ai.gd:_generate_queue`）
- `_member.is_friendly == true` のとき：`_find_friendly_retreat_goal()` の結果を `move_to_explore` の goal に設定してキュー投入。到達済みなら `wait`
- `_member.is_friendly == false`（敵）：**従来通り** `_find_flee_goal(threat)` による脅威反対方向への逃走。縄張り帰還は `_apply_range_check` が並行処理

### 発動経路
| 起点 | 発動条件 |
|------|---------|
| NpcLeaderAI | `_evaluate_party_strategy()` が CRITICAL 時に `Strategy.FLEE` を返す → `party_fleeing=true` → UnitAI FLEE |
| PartyLeaderPlayer | `battle_policy == "retreat"` → `Strategy.FLEE` → `party_fleeing=true` → UnitAI FLEE |
| 個別指示 | `on_low_hp == "flee"` + HP 閾値割れ → `_determine_effective_action()` が FLEE を返す |

### 復帰
撤退先に到達してもキュー再生成（`_generate_queue`）のたびに戦況が再評価される。安全部屋に入ると敵は進入できないため `CombatSituation.SAFE` となり、`_determine_effective_action()` が ATTACK / WAIT に戻る。NpcLeaderAI では `Strategy.EXPLORE` に復帰して通常の探索行動を開始する。

### MapData 拡張
- `get_safe_tiles() -> Array[Vector2i]`：安全タイル集合の全座標を返す（`_find_friendly_retreat_goal` が使用）

### 敵側の挙動
敵パーティーの FLEE は変更なし：
- 個体レベル：`_should_self_flee()`（ゴブリン等、HP<30%）→ 脅威から逃走
- パーティーレベル：縄張り範囲外への脱走は `_apply_range_check` が GUARD_ROOM/`move_to_home` で帰還

---

## 未接触NPCパーティーのリング非表示 ✅ 完了

### 仕様
- プレイヤーが **話しかけたことのないNPCパーティー** はパーティーカラーリングを非表示
- 話しかけた瞬間に、そのNPCパーティー全員のリングが表示される
- 自パーティーメンバー（合流済み含む）は常にリング表示
- 敵パーティーは従来通り TRANSPARENT（リング非表示）で変更なし

### 実装

**`Character.gd`**
- `party_ring_visible: bool = true`（setter で `queue_redraw`）を追加
- `_draw` 内のリング描画条件に `and party_ring_visible` を追加

**`PartyManager.gd`**
- `contacted: bool = true`（player / enemy 用デフォルト）を追加
- `setup()` で `party_type == "npc"` のとき `contacted = false` にセット
- `set_party_color()`：メンバーの `party_ring_visible` を `contacted` 値で上書き
- `mark_contacted()`：`contacted=true` にし、全メンバーの `party_ring_visible=true` に更新

**`game_map.gd`**
- `_on_dialogue_requested()` 冒頭で `nm.mark_contacted()` を呼ぶ（プレイヤー起点・NPC起点のどちらでも接触記録）
- `_merge_npc_into_player_party()` / `_merge_player_into_npc_party()` で明示的に `member.party_ring_visible = true` を設定（安全策）

### セーブデータ
`SaveData` は hero 名・現在フロア・クリア回数・累計プレイ時間のメタデータのみを保持しており、ランタイムのNPC状態は保存されない。接触フラグ（`contacted`）はランタイム専用でセーブ対象外。新規ゲーム開始時は全NPCパーティーが未接触状態でスタートする。

---

## DebugWindow 表示順と選択順の対応 ✅ 完了

### 症状
DebugWindow の上下キー選択が表示順（プレイヤー → NPC → 敵）と一致せず、押下方向と画面上のカーソル移動が逆方向になることがあった。

### 原因
`_build_leader_list()` が敵 → NPC → プレイヤーの順でリストを構築しており、描画順（プレイヤー → NPC → 敵）と不一致だった。加えて `_get_any_leader()` が生存中の先頭を返す実装で、描画側の「`is_leader` 優先」とも差異があり、選択中マーカー `▶` の付与対象と選択カーソルがズレるケースがあった。

### 修正（`debug_window.gd`）
- `_build_leader_list()`：構築順を **プレイヤー → NPC → 敵** に変更（描画順と同じ）
- `_get_any_leader()`：`is_leader==true` のメンバーを優先し、なければ生存中の先頭にフォールバック（描画側の leader 判定と統一）

### F3 無敵モードとプレイヤーパーティー
既存実装でもプレイヤーパーティーを選択して F3 を押すと全メンバーが無敵化される仕様だったが、上記の選択順バグでプレイヤーがリスト末尾にあり到達しづらかった。表示順修正により、F1 で DebugWindow を開いた直後に Up/Down キーでプレイヤーパーティーを素早く選択できるようになった（無敵モードのロジック自体は変更なし）。

---

## 壁・味方ブロック時のその場歩行 ✅ 完了

### 症状
壁や他キャラに塞がれて進めないとき、`_try_move()` は移動を中止して何もせず返る。`character.is_moving()` が false のままになり、`_update_world_time()` が `world_time_running=false` に切り替えて画面が暗転・時間停止してしまっていた。

### 修正
- **`Character.walk_in_place(duration)`** 新設：位置・グリッド座標・向きを変えずに `_visual_duration` だけセットし、`_update_visual_move()` の歩行アニメサイクル（walk1→top→walk2→top）を再生する
- **`PlayerController._process_normal`**：`_try_move(effective_dir)` 呼び出し後に `character.is_moving() == false` かつ入力キーが保持されていれば `walk_in_place(MOVE_INTERVAL / game_speed)` を呼び出す

### 効果
- 壁・味方キャラに塞がれてもキーを押し続ける限り足踏みアニメが続く
- `is_moving()` が true を返すため `_update_world_time()` は `world_time_running=true` を維持 → 暗転・時間停止が発生しない
- キーを離せば通常通り停止（`_get_input_direction() == ZERO` で判定）
- `_is_turning` 中は適用しない（方向転換の回転アニメを妨害しないため）

---

## 勧誘結果の理由メッセージ ✅ 完了

### 仕様
NPCの勧誘（「仲間にする」選択）の承諾・拒否時に、判定スコアの主要因に応じた理由メッセージをMessageWindowに表示する。

### 承諾時メッセージ（reason → 表示文）
| reason | 条件 | メッセージ |
|--------|------|-----------|
| `dire` | NPCパーティーの合計HP割合 < 0.7 | 正直、助けがほしかった |
| `teamwork` | `has_fought_together` または `has_been_healed` が立っている | 一緒に戦った仲間なら信頼できる |
| `power` | 上記以外（純粋に戦力で承諾） | あなたのパーティーなら心強い |

優先順位：`dire` > `teamwork` > `power`。窮地（HP低下）が最優先。

### 拒否時メッセージ（reason → 表示文）
| reason | 重み計算 | メッセージ |
|--------|---------|-----------|
| `power_gap` | `max(0, (npc_rank_sum - player_rank_sum) × 10)` | あなたのパーティーでは心もとない |
| `no_teamwork` | `(共闘なし ? 5 : 0) + (回復なし ? 5 : 0)` | あなたのことをよく知らない |
| `independent` | `100 - 従順度平均 × 100` | 自分たちだけでやっていける |
| `unready` | 適正フロア未到達（足切り） | まだ下層に進む必要がない |

3つのウェイトを比較して最大を採用（`power_gap` を同値優先）。

### 実装
- `npc_leader_ai.gd`：`will_accept_with_reason(offer_type, player_party) -> Dictionary` を新設。`{accepted: bool, reason: String}` を返す
- `will_accept()` は後方互換用に残し、内部で `will_accept_with_reason` を呼ぶ
- `game_map.gd`：`_on_dialogue_choice` で `will_accept_with_reason` を呼び、`_get_decision_reason_text(reason, accepted)` で表示文を取得して `MessageLog.add_system` に追加
  - 承諾：`%s のパーティーが仲間に加わった！（<理由文>）`
  - 拒否：`断られた：<理由文>`
- `CHOICE_JOIN_THEM`（プレイヤーがNPC傘下に加わる）は常に承諾のため理由メッセージなし

### デバッグログ
`MessageLog.add_ai` に従来のスコア内訳＋選択された reason を付加（F1 DebugWindow 表示中のみ可視）。

---

## アイテムUI統合（アクション選択を右側パネルで完結） ✅ 完了

### 変更内容
従来は ACTION_SELECT / TRANSFER_SELECT のたびに別デザインのポップアップが表示されていた。これを廃止し、ITEM_SELECT と同じアイコン列 + 右側情報パネルの統合レイアウトに一本化。全フェーズでパネル内容だけが切り替わる形にした。

### アクション選択肢（動的構築）
| アクション | 表示条件 |
|-----------|---------|
| 使用する | 消耗品で `_is_consumable_usable_by_char` が true |
| 装備する | 装備品で `_can_equip_item` が true（自分のクラスで装備可） |
| 渡す | 未装備（操作中のキャラがリーダーでも非リーダーでも可。装備不可品でも可。渡し先0人時は "渡せる相手がいない" ログ表示で ACTION_SELECT に留まる） |
| 渡して装備させる | 装備品・未装備（同上。相手の装備可否に応じて差分または「装備不可」を表示） |
| キャンセル | 常に表示（必ず末尾） |

### 右側パネルの内容（display_mode で切替）
**ITEM_SELECT**
- アイテム名
- 装備品：stats（威力・右手防御・両手防御・物理耐性・魔法耐性・射程）
- 消耗品：effect（HP回復 / MP回復 / SP回復）

**ACTION_SELECT**
- アイテム名
- アクション縦並びリスト（カーソルハイライト）
- 選択中アクションに応じた詳細行：
  - 使用する：効果行
  - 装備する：「威力 3→11 (+8)」形式の装備前後差分

**TRANSFER_SELECT**
- アイテム名
- 見出し（「渡す：渡す先」 または 「渡して装備させる：渡す先」）
- メンバー名 + 装備品の場合「（装備不可）」の表記（グレー）
- 選択中メンバーに応じた詳細行：
  - 渡す：装備品で装備不可なら「装備不可（譲渡のみ）」
  - 渡して装備させる：装備可能なら装備前後差分、不可なら「装備不可」

### 実装ポイント
- **`player_controller.gd`**
  - `_enter_action_select`：`action_info` を構築（各アクションの詳細行配列を事前計算）
  - `_enter_transfer_select(auto_equip: bool)`：引数で2種類の譲渡モードを分岐。各メンバーの can_equip / diff を計算して `transfer_info` に詰める
  - `_execute_transfer`：`_transfer_equip_mode == true` かつ対象が装備可能なら自動装備＋メッセージ切替
  - ヘルパ：`_can_equip_item_for_char` / `_build_effect_lines` / `_build_equip_diff_lines`
- **`consumable_bar.gd`**
  - `_draw_list_menu` のポップアップ呼び出しを廃止
  - `_on_draw`：ACTION_SELECT / TRANSFER_SELECT でも `_draw_item_list` を呼ぶ（統合レイアウト）
  - `_draw_detail_pane`：display_mode で `_draw_action_list_detail` / `_draw_transfer_list_detail` / stat-only に分岐
  - `DETAIL_BOX_W = 280` / `DETAIL_BOX_H_EXPANDED = 220`（アクション/譲渡時はパネル縦拡張）
  - フィールド追加：`action_info: Array` / `transfer_info: Array` / `transfer_label: String`

### メッセージ変化
- 渡して装備させる：「%s は %s を %s に渡して装備させた」
- 通常の渡す：従来通り「%s は %s を %s に渡した」

---

## ヒーラー回復の射程改善 ✅ 完了

### 変更内容
ヒーラーの回復魔法・防御バフ（支援行動）について：
1. **自己回復を可能にする**：ターゲットリストに自分自身を含める
2. **方向制限を撤廃**：友軍（自分含む）への支援は全方向（360°）・距離制限（射程）は従来通り
3. **アンデッド特効は従来通り**：`heal` の attack_type だが敵アンデッド対象時は通常攻撃扱い → 前方コーン制限を維持

### 実装（`player_controller.gd:_get_valid_targets`）
- action == "heal" or "buff_defense" のとき、ループ前に `result.append(character)` で自分を対象に追加
- ループ内の方向制限（`_is_in_forward_cone`）を「アンデッド敵に対してのみ」適用するよう分岐
- 友軍（`c.is_friendly == true`）は距離チェックのみで対象化

### AI側
- `unit_ai.gd` の `_find_heal_target` / `_find_buff_target` は元から方向制限なし（距離ベースのみ）
- `_party_peers` に自分を含むため、AIヒーラーも自己回復可能（従来から）
- 今回の変更で AI 側の修正は不要

### 防御バフ（V スロット）について
回復と同じ支援行動として、自己対象・全方向対応を同時適用（action="buff_defense" 条件で同一処理）。

---

## ヒットエフェクト（hit_effect.gd）3層刷新 ✅ 完了

### 構成
- 層1: リング（波紋）— `draw_arc()` × 2本。黄橙色 `Color(1.0, 0.85, 0.3)` / `Color(1.0, 0.7, 0.2)`。ease-out `r = max_r * (1 - (1-t)^2)` で広がる
- 層2: 光条（十字フラッシュ）— 中心グロー `Color.WHITE` + 8方向（十字＋斜め45°）ライン。バーストは `BURST_RATIO = 0.375` の比率内で消える。`_damage_scale()` × 0.15 で大ダメージ時に持続延長
- 層3: パーティクル散布 — 6〜20個の光粒（`clampi(int(6 + 4 * ds), 6, 20)`）が放射状に飛散。白 `(1.0, 1.0, 0.9)` → オレンジ `(1.0, 0.6, 0.2)` にlerp。`PARTICLE_FADE_START = 0.7` 以降フェードアウト

### 共通仕様
- 総再生時間: `DURATION = 0.40s`（旧0.14sの約3倍）
- 加算合成: `_ready()` で `CanvasItemMaterial.BLEND_MODE_ADD` を設定。クリティカル時の2重スポーンが自然に輝度上昇
- ダメージスケール: `max(0.2, damage / 20.0)` は既存ロジックを継承
- パーティクル初期化: `_ready()` で `PackedFloat32Array` に angles / speeds / sizes をランダム生成

---

## メッセージウィンドウ拡張（Phase 14〜）

### 手動スクロール（ピクセル単位スムーズ）
- 入力アクション: `msg_scroll_up`（PageUp + 右スティック上 axis 3 -1.0）/ `msg_scroll_down`（PageDown + 右スティック下 axis 3 +1.0）
- 実装: `_handle_manual_scroll(delta)` で `Input.get_action_strength()` を取得し、2乗カーブで強度補正 × `MANUAL_SCROLL_SPEED = 900.0 px/s` × delta を `_manual_scroll_px` に加算
- 最大量: `_calc_max_scroll()` が全グループの合計高さ − avail_h を返す
- リセット: `_on_entry_changed()`（新メッセージ到着）で `_manual_scroll_px = 0.0`
- 描画: `_on_scroll_draw()` で `base_y = avail_h - all_total_h + _manual_scroll_px + anim_offset`。手動スクロール中は既存アニメーション（`_scroll_offset`）を無効化

### 拡大表示トグル
- 入力アクション: `msg_toggle_expand`（Home + R3 joypad button 8）
- 定数: `VISIBLE_LINES = 3` / `EXPANDED_LINES = 7`
- 拡大時: 中央テキスト部の `box_h = vh - 6.0`（画面上端まで）、左右バスト領域は `normal_box_h` サイズを維持し `bust_y = vh - img_size - 6.0` で下端寄せ
- 背景: 中央テキスト部と左右バストは個別に描画。左右バストは背景・枠線なし（テクスチャ未取得時も何も描画しない）
- 背景不透明度: `Color(0.03, 0.03, 0.07, 0.55)`（旧0.80）

### 文字色分け（segments）
- `MessageLog.add_battle()` に引数 `segments: Array = []` を追加
- セグメント形式: `{"text": String, "color": Color, "bold": bool（省略可）}`
- エントリ連結: `_build_display_groups` で同じ attacker/defender ペアを `{"text": "\n"}` セグメントで区切って統合
- 描画: `MessageWindow._draw_segments(x, y, max_w, fs, segments)` がセグメントを左端から順に描画。`"\n"` で改行、`bold=true` のときは 1px ずらして2回描画、幅超過時は自動折り返し（長いセグメント単位）

### 色ルール
| 対象 | 色 |
|------|-----|
| 通常テキスト | 白 |
| 自パーティー（`joined_to_player=true`）キャラ名 | `Color(0.50, 0.75, 1.00)` 青 |
| 未加入NPC（`is_friendly=true`）キャラ名 | `Color(0.55, 0.90, 1.00)` 水色 |
| 敵キャラ名 | `Color(0.30, 0.65, 0.35)` 暗い緑 |
| 小ダメージ | 白 |
| 中ダメージ | `Color(1.00, 0.95, 0.30)` 黄 |
| 大ダメージ | `Color(1.00, 0.65, 0.20)` オレンジ |
| 特大ダメージ | `Color(1.00, 0.30, 0.30)` 赤＋太字 |

### 色分けヘルパー（character.gd static）
- `_party_name_color(ch)` — 上記ルール
- `_damage_label_color(dmg)` — `DAMAGE_LEVEL_SMALL/MEDIUM/LARGE` で分岐
- `_damage_is_huge(dmg)` — 特大判定（太字フラグ用）
- `_make_segs(raw_array)` — `[[text, color, bold?], ...]` を辞書配列に変換

### 色分け対応済みメッセージ
- 通常攻撃・ブロック・クリティカル・ヘッドショット・0ダメージ（`character.gd._emit_damage_battle_msg`）
- アンデッド特効（`character.gd._emit_damage_battle_msg` 内の分岐）
- V スロットヒット（`player_controller.gd._emit_v_skill_battle_msg` / `unit_ai.gd._emit_v_skill_battle_msg`）
- V スロット空振り系（スライディング突進 / 振り回し空振り / 突進斬り外し / 炎陣設置）
- AI ヘッドショット（耐性あり=大ダメージ色、即死=特大色+太字）

---

## 状態ラベル 4 段階（healthy / wounded / injured / critical）

### 閾値（GlobalConstants）
| 状態 | HP率 | 定数 |
|------|------|------|
| healthy | ≥ 50% | `CONDITION_HEALTHY_THRESHOLD = 0.5` |
| wounded | ≥ 35% | `CONDITION_WOUNDED_THRESHOLD = 0.35` |
| injured | ≥ 25% | `CONDITION_INJURED_THRESHOLD = 0.25` |
| critical | < 25% | — |

### 色統一
| 状態 | テキスト/HPゲージ | スプライト modulate |
|------|------------------|---------------------|
| healthy | `Color(0.40, 0.90, 0.40)` 緑 | 白 |
| wounded | `Color(1.00, 0.85, 0.20)` 黄 | `Color(1.0, 0.65, 0.25)` オレンジ |
| injured | `Color(1.00, 0.60, 0.20)` オレンジ | `Color(1.0, 0.35, 0.35)` 赤 |
| critical | `Color(1.00, 0.35, 0.35)` 赤 | 白↔`Color(1.0, 0.15, 0.15)` で点滅 |

### 適用箇所
- `Character.get_condition()`: 4段階を返す
- `Character._update_sprite_modulate()`: スプライト色
- `left_panel._condition_text_color()`（static）: テキスト色（新設）
- `left_panel._hp_modulate()` / `right_panel._hp_modulate()`: キャラ画像テクスチャ色
- `left_panel._draw_bar()`: HPゲージ色（`Color.TRANSPARENT` 指定時の自動着色）
- `right_panel` 状態テキスト color match
- `dialogue_window` NPC 状態テキスト color match
- `debug_window` メンバー行の HP 色分け 2 箇所
- `party_leader._estimate_hp_ratio_from_condition()`: injured ケース追加（`CONDITION_WOUNDED_THRESHOLD = 0.35` を返す）

### 独立した閾値（変更なし）
- `NEAR_DEATH_THRESHOLD = 0.25`: ヒールポーション自動使用・heal "aggressive" モード対象選定で使用。状態ラベルとは別用途

---

## 攻撃フロー改善

### 他ボタンによる攻撃キャンセル＋機能切替
- `player_controller._handle_attack_switch_input()` を `_process_pre_delay()` と `_process_targeting()` の先頭で呼ぶ
- アイテムボタン（C/X）: 通常攻撃・特殊攻撃どちらでもキャンセル → アイテム UI 起動
- V/Y（特殊攻撃）: 通常攻撃中のみ。MP/SP・クールダウン OK なら通常攻撃キャンセル → V スロット発動（インスタント系は即時・ターゲット系は PRE_DELAY へ）
- Z/A（通常攻撃）: 特殊攻撃中のみ。キャンセル → 通常攻撃開始

### 射程内対象なし時の自動キャンセル
- 定数: `AUTO_CANCEL_FLASH = 0.25s`
- `_start_targeting()` で `_valid_targets.is_empty()` なら `_auto_cancel_remaining = AUTO_CANCEL_FLASH`
- `_process_targeting(delta)` 先頭でカウントダウン → 0 で `_exit_targeting()`。待機中は他の入力を一切受け付けない
- ヒーラー等の360度射程にも対応: `game_map._draw_tiles` の射程描画で `action == "heal" or "buff_defense"` 時は距離判定のみ（前方コーンフィルタなし）

---

## 安全部屋専用タイル画像（Phase 13 後）
- 画像: `assets/images/tiles/stone_00001/safe_floor.png`
- `game_map._safe_floor_tex: Texture2D` を追加。`_load_tile_textures()` で `safe_floor.png` がロードされる
- `_draw()` 内で `tile == FLOOR and _safe_floor_tex != null and draw_map.is_safe_tile(pos)` の場合のみ安全部屋テクスチャで描画
- 画像がない場合は通常の FLOOR テクスチャにフォールバック

---

## Character.joined_to_player フラグ
- 追加: `Character.joined_to_player: bool`（デフォルト false）
- 初期化: 主人公は `game_map._setup_hero()` で `true` に設定
- 伝播: `PartyManager.set_joined_to_player(value)` がメンバー全員の `joined_to_player` を更新
- 用途: メッセージ色分けの「自パーティー」判定（`Character._party_name_color()`）。将来の仲間/未加入NPC/敵 区別の汎用フラグとして使える

---

## アイテム名称統一（2026-04）
- ヒールポーション / MPポーション / SPポーション（`HP回復ポーション` 等の長い表記は廃止）
- SPポーションが `活力薬` と誤表記されていた箇所（`game_map.gd` / `dungeon_handcrafted.json` の 53 箇所）を統一

---

## 攻撃クールダウン全面見直し（2026-04-17）

### 定義場所（一元化）
- **味方（クラス持ち）**: `assets/master/classes/*.json` の **スロット単位**（`slots.Z` / `slots.V`）に `pre_delay` / `post_delay` を定義
  - クラス JSON の**トップレベル** `pre_delay` / `post_delay` は**廃止**（全7クラスの JSON から削除）
  - プレイヤーは `PlayerController._get_slot()` → `sd.pre_delay` / `sd.post_delay` で取得（既存の経路）
  - AI（UnitAI）は `CharacterData.get_z_pre_delay()` / `get_z_post_delay()` / `get_v_pre_delay()` / `get_v_post_delay()` で取得（新設）
  - → プレイヤーと AI が同じスロット値を参照するようになり、挙動が一致
- **敵（スロット構造なし）**: `assets/master/enemies/*.json` の**トップレベル** `pre_delay` / `post_delay` を維持
  - `CharacterData.pre_delay` / `post_delay` インスタンス変数は引き続き敵用に使用

### CharacterData の追加フィールド
- `z_pre_delay: float = 0.0` / `z_post_delay: float = 0.0` — 味方の slot Z 値
- `v_pre_delay: float = 0.0` / `v_post_delay: float = 0.0` — 味方の slot V 値
- `CharacterGenerator._build_data()` が `class_json.slots.Z` / `class_json.slots.V` の `pre_delay` / `post_delay` を読み込んで設定
- getter は「フィールド値 > 0 ならそれを返す、0 なら `pre_delay` / `post_delay`（敵用トップレベル）にフォールバック」

### 現在の数値（新）

#### 通常攻撃（スロット Z）
| クラス | pre_delay | post_delay |
|---|---|---|
| fighter-sword | 0.10 | 0.30 |
| fighter-axe | 0.20 | 0.45 |
| archer | 0.10 | 0.25 |
| magician-fire | 0.10 | 0.30 |
| magician-water | 0.10 | 0.30 |
| healer | 0.10 | 0.30 |
| scout | 0.05 | 0.20 |

#### 特殊攻撃（スロット V）
| クラス | 特殊攻撃 | pre_delay | post_delay |
|---|---|---|---|
| fighter-sword | 突進斬り | 0.25 | 0.50 |
| fighter-axe | 振り回し | 0.40 | 0.70 |
| archer | ヘッドショット | 0.40 | 0.50 |
| magician-fire | 炎陣 | 0.50 | 0.60 |
| magician-water | 無力化水魔法 | 0.60 | 0.60 |
| healer | 防御バフ | 0.40 | 0.50 |
| scout | スライディング | 0.15 | 0.40 |

### AI v_attack のフロー変更（UnitAI）
従来は `"v_attack"` アクション発行で即 `_execute_v_attack()` を直接呼び、各 `_v_*` メソッドが末尾で `_state = WAITING / _timer = 0.3〜0.5` のハードコード値を設定していた。

新フロー：
1. `_start_action` の `"v_attack"`: `_state = ATTACKING_PRE`, `_timer = get_v_pre_delay()`, `is_attacking = true`
2. `ATTACKING_PRE` ハンドラ: タイマー消化後、`_current_action.action` をチェックし `v_attack` なら `_execute_v_attack()`、それ以外なら `_execute_attack()`
3. 実行後、`_execute_v_attack()` が早期 `_complete_action()` した場合（ターゲット消失等）は state が変わっているので POST 遷移をスキップ
4. `_state = ATTACKING_POST`, `_timer = get_v_post_delay()` or `get_z_post_delay()`（アクション種別で分岐）

各 `_v_*` メソッド（`_v_rush_slash` / `_v_whirlwind` / `_v_headshot` / `_v_flame_circle` / `_v_water_stun` / `_v_sliding`）末尾の `_state = WAITING / _timer = X` 行を削除。ダメージ処理・移動・エフェクト・メッセージのみを担当する純関数的な設計に。

ヒーラーの `heal` / `buff` アクションも `_member.character_data.post_delay` 参照を `get_z_post_delay()` / `get_v_post_delay()` に変更（buff は V スロット相当）。

### game_speed 適用
- **プレイヤー**: `_process_pre_delay` / `_process_post_delay` の `_pre_delay_remaining -= delta` を `delta * GlobalConstants.game_speed` に変更
- **AI**: UnitAI の `_timer -= delta` を全て（MOVING / WAITING / ATTACKING_PRE / ATTACKING_POST）`delta * game_speed` に変更
- タイマー値の設定側は**「ゲーム内秒」で一貫保持**。カウントダウンで game_speed 倍数を掛けることで実時間を短縮
  - `_timer = MOVE_INTERVAL`（旧: `_get_move_interval()`＝pre-scaled から raw に変更）
  - `_timer = WAIT_DURATION`（旧: `WAIT_DURATION / game_speed` から raw に変更）
  - `move_to` の tween duration だけは実時間秒が必要なので `_get_move_interval()` を引き続き使用
- `_reeval_timer` は戦略再評価の実時間タイマーなので対象外（raw delta のまま）

### PRE_DELAY 中の射程オーバーレイ表示
- `PlayerController.is_in_attack_windup()` を新設（`_mode == PRE_DELAY or TARGETING` で true）
- `game_map._draw` の射程オーバーレイ判定を `player_controller.is_targeting()` → `player_controller.is_in_attack_windup()` に変更
- **PRE_DELAY 中は射程を表示するだけで、ターゲット選択（LB/RB 循環・確定）はできない**。選択ロジックは従来通り `TARGETING` モード以降
- ボタン押下直後から射程が見えるため、「押してから射程が出るまでワンテンポ遅れる」体感が解消

### 未変更（従来通り）
- `V_SLOT_COOLDOWN = 2.0` 秒（プレイヤー V スロット再発動の禁止時間・`game_speed` 影響なし）
- `AUTO_CANCEL_FLASH = 0.25` 秒（射程内対象なし時の射程表示時間・`game_speed` 影響なし）
- 敵の top-level `pre_delay` / `post_delay` 値は未変更
- `base_ai.gd` / `enemy_ai.gd` / `goblin_ai.gd` はレガシー（既存コメントで「未使用」と明記済み・今回は触らず）

---

## HP状態ラベルの色と点滅の統一（2026-04-17）

### 背景
スプライト・アイコン系（3色モデル：白/橙/赤+点滅）と、ゲージ・文字系（4色モデル：緑/黄/橙/赤）で色体系がズレていた。また色定数が各ファイルに手書きコピペされており、操作キャラの HP 減少に気付きにくい問題もあった。

### 新仕様
- 全要素で 4 段階の状態ラベル（healthy / wounded / injured / critical）を使用
- パレットを 3 系統に整理：SPRITE（白/黄/橙/赤）/ GAUGE（緑/黄/橙/赤）/ TEXT（緑/黄/橙/赤）
- 点滅は **スプライト・顔アイコン（左右パネル）のみ**。wounded / injured / critical の 3 段階で 3Hz 点滅（「色 ↔ 色×0.7」を `sin(t*TAU*3.0)` で lerp）
- ゲージ・文字・DebugWindow は静的色（点滅なし）
- DebugWindow の HP 色はスプライトパレットを流用（白/黄/橙/赤）

### 色定数（`GlobalConstants`）
```
CONDITION_PULSE_HZ = 3.0

CONDITION_COLOR_SPRITE_HEALTHY  = Color.WHITE
CONDITION_COLOR_SPRITE_WOUNDED  = Color(1.00, 0.85, 0.20)
CONDITION_COLOR_SPRITE_INJURED  = Color(1.00, 0.65, 0.25)
CONDITION_COLOR_SPRITE_CRITICAL = Color(1.00, 0.35, 0.35)

CONDITION_COLOR_GAUGE_HEALTHY  = Color(0.25, 0.80, 0.30)
CONDITION_COLOR_GAUGE_WOUNDED  = Color(0.95, 0.80, 0.15)
CONDITION_COLOR_GAUGE_INJURED  = Color(0.95, 0.55, 0.15)
CONDITION_COLOR_GAUGE_CRITICAL = Color(0.90, 0.20, 0.20)

CONDITION_COLOR_TEXT_HEALTHY  = Color(0.40, 0.90, 0.40)
CONDITION_COLOR_TEXT_WOUNDED  = Color(1.00, 0.85, 0.20)
CONDITION_COLOR_TEXT_INJURED  = Color(1.00, 0.60, 0.20)
CONDITION_COLOR_TEXT_CRITICAL = Color(1.00, 0.35, 0.35)
```

### ヘルパー関数（`GlobalConstants`）
- `ratio_to_condition(ratio: float) -> String` — HP 比率を条件文字列に変換
- `condition_sprite_modulate(cond) -> Color` — スプライト用（wounded 以降は点滅）
- `condition_sprite_color(cond) -> Color` — スプライトパレットの静的色（DebugWindow 用）
- `condition_gauge_color(cond) -> Color` — HPゲージ色（静的）
- `condition_text_color(cond) -> Color` — テキスト色（静的）
- `_pulse_color(base) -> Color` — 内部用。「色 ↔ 色×0.7」を `sin(t*TAU*CONDITION_PULSE_HZ)` で lerp

### 変更箇所
| ファイル | 変更内容 |
|---|---|
| `scripts/global_constants.gd` | 色定数12個 + `CONDITION_PULSE_HZ` + ヘルパー6関数を追加 |
| `scripts/character.gd` `_update_modulate` | 旧3色モデル（白/橙/赤+点滅）を削除し `condition_sprite_modulate(get_condition())` に統一 |
| `scripts/left_panel.gd` `_draw_bar` | HP ゲージ色分岐を削除し `condition_gauge_color(ratio_to_condition(ratio))` に統一 |
| `scripts/left_panel.gd` `_hp_modulate` | 色分岐を削除し `condition_sprite_modulate(get_condition())` を返すだけに |
| `scripts/left_panel.gd` `_condition_text_color` | 実装を `GlobalConstants.condition_text_color(cond)` のラッパーに短縮 |
| `scripts/right_panel.gd` `_hp_modulate` | 同上（left_panel と同じリファクタ） |
| `scripts/right_panel.gd` 状態テキスト色のインライン match | `GlobalConstants.condition_text_color(cond)` で置き換え |
| `scripts/dialogue_window.gd` 状態テキスト色のインライン match | 同上 |
| `scripts/debug_window.gd` HP 色分岐（2 箇所） | 共通関数 `_hp_color_for(ch)` に統合。内部で `condition_sprite_color` を呼ぶ |

### 点滅が効いて見える仕組み
- 左右パネルは `_process` で毎フレーム `queue_redraw()` しているため、顔アイコン modulate の点滅が自然に反映される
- `Character._update_modulate` は `_process` で毎フレーム呼ばれるため、フィールドスプライトの点滅も継続的に更新される
- HP ゲージ・状態ラベルテキスト・DebugWindow は同じ毎フレーム redraw の対象だが、色が静的なので見た目は変化しない

---

## Config Editor（開発用定数エディタ）

### 実装ファイル
- `scenes/config_editor.tscn` — CanvasLayer ルート（layer=20・script 取付のみ）
- `scripts/config_editor.gd` — UI 構築・編集ハンドラ
- `scripts/global_constants.gd` — ロード/セーブ関数（下記）
- `assets/master/config/constants.json` — ユーザー値（シンプル key:value）
- `assets/master/config/constants_default.json` — デフォルト値 + メタ情報

### 起動
- **タイトル画面**: `scripts/title_screen.gd._input` が `KEY_F4` を捕捉 → `_toggle_config_editor()` で `res://scenes/config_editor.tscn` を instance 化して add_child（初回のみ）。`set_input_as_handled()` で「any key → main menu」遷移より優先
- **ゲーム中**: `scripts/game_map.gd._input` の `KEY_F4` → `_toggle_config_editor()`。他 UI（OrderWindow / PauseMenu / DebugWindow / NpcDialogueWindow）表示中は無視。F4 押下後に `get_viewport().set_input_as_handled()` を呼んで ConfigEditor 側の `_unhandled_input` への伝搬を遮断（自己 close 防止）

### ConfigEditor の動作
- `toggle()` / `open()` / `close()` を公開
- `open()` 時：`_prev_world_time_running` に現在値を退避し、`world_time_running = false` に設定
- `close()` 時：ゲーム中（`_opened_in_game = true`）だった場合のみ `_prev_world_time_running` を復元
- `_unhandled_input` で KEY_F4 / KEY_ESCAPE を閉じる、Ctrl+Tab / Ctrl+Shift+Tab / Ctrl+PageUp / Ctrl+PageDown でタブ循環

### GlobalConstants 側の仕組み
- 対象定数は `const` ではなく `var` で宣言（Autoload 起動時に外部 JSON で代入されるため）
- `const CONFIG_KEYS: Array[String]` — 管理対象の定数名一覧
- `_ready()` → `_load_constants()`：`constants.json` を優先して読み、不足キーは `constants_default.json` の `value` で補完
- `get(key)` / `set(key, val)` は GDScript の Object 動的アクセスで実行
- `_apply_value(key, raw)` が type に応じて変換（float / int / color[r,g,b,a]）
- `save_constants()` — 現在値を `constants.json` に `JSON.stringify(out, "  ")` で書き込み
- `reset_to_defaults()` — `constants_default.json` の `value` で現在値を上書き（保存はしない）
- `commit_as_defaults()` — 現在値で `constants_default.json` の `value` を書き換え（破壊的）
- `get_config_value(key)` — Color は `[r,g,b,a]` 配列で返す（JSON 書き出し用）
- `get_default_value(key)` — `constants_default.json` の `value` を返す（UI 表示用）
- `_get_meta_for(key)` — type / category / min / max / step / description を返す
- `last_config_error: String` — 書き込み失敗時のエラーメッセージ（UI で赤字表示）

### UI 構造
- 画面中央に `PanelContainer`（幅 60% × 高さ 70%・不透明背景）
- 内部：VBox（Title → Status → Header → TabContainer → 下部ボタン行）
- TabContainer：`TABS` 配列（Character / UnitAI / PartyLeader / NpcLeaderAI / Healer / PlayerController / EnemyLeaderAI）+ Unknown の 8 タブ
- 各タブは ScrollContainer → VBox 構造。行は所属カテゴリのタブ VBox に add_child
- 空タブには「このカテゴリには定数がまだ登録されていません。」のプレースホルダー Label
- 行ごとのウィジェット：`PanelContainer{ HBox{ 定数名 Label, 説明 Label, SpinBox/ColorPickerButton, デフォルト値 Label/ColorRect } }`
- 現在値がデフォルトと異なる行は `Color(1.0, 1.0, 0.8)` の薄黄背景（行の `StyleBoxFlat.bg_color`）
- タブ内に非デフォルト値が 1 つでもあればタブ名末尾に ` ●` を付与（`_update_tab_title` / `_update_tab_indicators`）
- 下部ボタン：保存 / すべてデフォルトに戻す / 現在値をすべてデフォルト化 / 閉じる (F4)
- リセット・デフォルト化は `ConfirmationDialog` で確認

### 数値表示のフォーマット（`_format_number`）
- GDScript の `%` フォーマットは `%g` 未対応のため、`%.4f` で丸めて末尾ゼロを削る自前実装
- 整数扱い（`is_equal_approx(f, float(int(f)))`）なら `"%d"`、小数なら `0.35` 形式

### タブ追加手順
- 新カテゴリを追加したい場合：`config_editor.gd` の `TABS: Array[String]` の末尾に追記する
- `constants_default.json` の `category` フィールドを新タブ名に揃える
- 未登録カテゴリの定数は Unknown タブに自動振り分け（`push_warning` で警告も出す）

---

## Config Editor「味方クラス」タブ（Phase B）

### データフロー
1. ConfigEditor 初期化時に `_load_class_files()` が `assets/master/classes/*.json` を 7 ファイル読み込み、`_class_data[class_id]` に格納（`Dictionary` はキーの挿入順を保持）
2. `_flatten_class(data)` で `slots.Z.*` → `Z_*`, `slots.V.*` → `V_*` に平坦化して行表示に使う
3. ユーザーがセル編集 → `_on_class_cell_changed` が発火し、`_class_cell_styles[widget_key]` の `StyleBoxFlat.bg_color` を薄黄色に変更、`_class_dirty[class_id]` を更新
4. 「保存」ボタン押下 → `_save_class_files()` が dirty=true のクラスだけ書き戻し

### グループ定義
`config_editor.gd` の `CLASS_PARAM_GROUPS: Array` でパラメータ → グループ名を定義：
- 基本: id / name / weapon_type / attack_type / attack_range / behavior_description
- リソース: base_defense / mp / max_sp / heal_mp_cost / buff_mp_cost
- 特性: is_flying
- Zスロット（通常攻撃）: Z_name / Z_action / Z_type / Z_range / Z_damage_mult / Z_heal_mult / Z_pre_delay / Z_post_delay / Z_sp_cost / Z_mp_cost
- Vスロット（特殊攻撃）: V_name / V_action / V_type / V_range / V_damage_mult / V_sp_cost / V_mp_cost / V_pre_delay / V_post_delay / V_stun_duration / V_buff_duration / V_duration / V_tick_interval

未分類パラメータは「その他」グループに自動集約され、`push_warning` で警告される。

### 型変換ルール（`_coerce_class_value`）
元 JSON の値の型を見て以下に変換：
- **bool**: `"true"` / `"false"` を変換。それ以外は失敗
- **int**: `is_valid_int()` 優先、`is_valid_float()` なら int 切り捨て、それ以外は失敗
- **float**: `is_valid_float()` なら変換、それ以外は失敗
- **String**: そのまま

型変換が 1 つでも失敗したらそのクラス JSON の保存を中止し、`push_warning` でログ。

### キー順保持
`JSON.stringify(data, "  ", false)` で `sort_keys=false` を指定（Godot 4 のデフォルトは `true` でアルファベット順ソートされるため）。これにより元 JSON のキー挿入順と `slots.X` / `slots.C` などの未編集構造がそのまま保持される。

### UI 構造
- トップタブ「味方クラス」の中身：`ScrollContainer` → `VBoxContainer`
- ヘッダー行：「パラメータ」＋ 7 クラス ID の横並び
- グループ区切り：`PanelContainer + StyleBoxFlat`（濃い青背景）でタイトル表示
- 各行：`HBoxContainer{ パラメータ名 Label(220px) + 7×LineEdit(150px) }`。該当クラスに無いパラメータは `—` 表示（編集不可）
- セル幅定数：`CLASS_PARAM_COL_W = 220`（パラメータ名列）/ `CLASS_VALUE_COL_W = 150`（値セル）
- 左端の「パラメータ名」列の sticky（横スクロール固定）は未実装（Godot 標準コントロールでは一手間かかるため省略）

### 下部ボタンの挙動
`_on_top_tab_changed()` が上段タブ切替時に呼ばれ、ボタンの `disabled` を更新：
- **定数タブ**: 保存 / リセット / デフォルト化 すべて有効
- **味方クラスタブ**: 保存のみ有効。リセット・デフォルト化は無効化（デフォルト値を保持しない方針）
- **敵 / ステータス / アイテム**: すべて無効化（プレースホルダー段階）

`_on_save_pressed()` は現在の上段タブを見て分岐（`_current_top_tab_name()`）：
- TOP_TAB_CONSTANTS → `GlobalConstants.save_constants()`
- TOP_TAB_ALLY_CLASS → `_save_class_files()`
- TOP_TAB_STATS → `_save_stats_files()`

---

## Config Editor「ステータス」タブ（Phase B）

### 変更履歴
- **2026-04-17**: 「ステータス」トップタブ内に 2 サブタブ（クラスステータス・属性補正）として初期実装
- **2026-04-20**: トップタブを**フラット 3 タブに昇格**：`味方ステータス` / `属性補正` / `敵ステータス`。サブタブ構造を廃止。敵ステータス（`enemy_class_stats.json`）の編集対応を同時に追加。描画関数を `_build_class_stats_tab(parent, tab_name, source_id, data, class_ids)` に共通化

### 対象ファイル
- `assets/master/stats/class_stats.json`（**味方**クラス × ステータス × {base, rank}）
- `assets/master/stats/enemy_class_stats.json`（**敵固有**クラス × ステータス × {base, rank}・2026-04-20〜）
- `assets/master/stats/attribute_stats.json`（sex/age/build × ステータス + random_max・味方・敵で共用）

### トップタブ構成（2026-04-20〜）
全体のトップタブ順序：
```
定数 | 味方クラス | 味方ステータス | 属性補正 | 敵一覧 | 敵クラス | 敵ステータス | アイテム
```
- **味方ステータス** = `class_stats.json`（UI 簡潔化のため「ステータス」は内部的に「クラスステータス」の意味）
- **属性補正** = `attribute_stats.json`（味方・敵で共用なので味方ブロックと敵ブロックの橋渡し位置に独立タブとして配置）
- **敵ステータス** = `enemy_class_stats.json`（味方ステータスと同構造・同描画関数）

### データフロー
1. `_load_stats_files()` が `_class_stats_data` / `_enemy_class_stats_data` / `_attr_stats_data` に 3 つの JSON をパースして保持
2. 各トップタブ builder が UI を構築：
   - `_build_top_tab_ally_stats()` → `_build_class_stats_tab(parent, TOP_TAB_ALLY_STATS, "ally", _class_stats_data, CLASS_IDS)`
   - `_build_top_tab_attr_stats()` → 内部で `_build_attr_table()` / `_build_random_max_table()` を直接呼ぶ
   - `_build_top_tab_enemy_stats()` → `_build_class_stats_tab(parent, TOP_TAB_ENEMY_STATS, "enemy", _enemy_class_stats_data, ENEMY_CLASS_IDS)`
3. セル編集時：元値と比較して薄黄ハイライト、`_class_stats_dirty` / `_enemy_class_stats_dirty` / `_attr_stats_dirty` を更新
4. 「保存」ボタン押下 → `_save_stats_files()` が dirty のファイルだけ書き戻し（`sort_keys=false`）

### クラスステータス（味方ステータス / 敵ステータス共通）
- 行 = ステータス（vitality / energy / skill / ...）、列 = クラス
- 各セルは LineEdit 2 つ（base / rank）を HBox で横並び。セル幅 `STAT_CELL_W = 130`（サブセル `STAT_SUBCELL_W = 60`）
- 列ヘッダーは 2 段（クラス名 + base/rank の小ヘッダー）
- 画面上のクラス順：味方は `CLASS_IDS`（7 クラス）/ 敵は `ENEMY_CLASS_IDS`（zombie / wolf / salamander / harpy / dark-lord の 5 クラス）。JSON のクラス順は書き戻し時に保持
- 行順（ステータスキー順）は**先頭クラスが持つキー**を採用。敵クラスは leadership / obedience を持たないため、敵ステータスタブにはこれらの行が自然に表示されない（仕様どおり。敵 AI は従順度 100% 相当で動作する）
- 編集用 key = `"{source_id}|{class_id}|{stat}|{sub_key}"`（4 パーツ）。source_id ∈ {"ally", "enemy"}
- あるクラスに存在しないステータスはセル位置に「—」を描画（編集不可）
- ウィジェット参照 `_class_stats_cell_widgets` / `_class_stats_cell_styles` は味方・敵で**共用**（key 先頭の source_id で区別）。dirty 判定・ハイライト解除は source_id でフィルタ

### 属性補正
- 上段：8 列（male / female / young / adult / elder / slim / medium / muscular）の横断表
- 下段：1 列（random_max）の縦並び表
- セル幅 `ATTR_CELL_W = 80`、1 LineEdit / セル
- 属性順は `ATTR_CATEGORY_ORDER` 定数で定義（sex → age → build → random_max）
- 編集用 key = `"category|attr|stat"`（上段） / `"random_max|stat"`（下段）

### 保存処理
- `_apply_class_stats_edits(orig, source_id)` / `_apply_attr_stats_edits(orig)` で `duplicate(true)` した Dict に編集値を適用
- `_apply_class_stats_edits` は source_id で 4 パーツキーをフィルタ（味方保存時に敵セルを触らない／逆も同様）
- 値の型変換は味方クラスタブと同じ `_coerce_class_value()` を流用（bool / int / float / string）
- 型変換失敗時は null を返し、そのファイルの保存をスキップ（`push_warning` でログ）
- 保存成功後はメモリ上のデータを新 Dict で置換し、該当セルのハイライトを解除：
  - 味方保存時：`_clear_class_stats_styles_for("ally")` が `_class_stats_cell_styles` のうち source="ally" のセルだけ解除
  - 敵保存時：`_clear_class_stats_styles_for("enemy")` が source="enemy" のセルだけ解除
  - 属性補正保存時：従来どおり `_clear_cell_styles(_attr_cell_styles)` で全解除

### 制限事項
- Config Editor からは**新ステータスの追加は不可**（既存ステータスの値編集のみ）
- **新クラスの追加も不可**（CharacterData / 生成ロジック / class_stats.json / enemy_class_stats.json / UI 定数の全てを連動させる必要があるため）
- 新ステータス・新クラスを追加する場合は、JSON ファイルと `CharacterData` / `CharacterGenerator` などのコードを直接編集する別タスクとして実施
- 「すべてデフォルトに戻す」「現在値をすべてデフォルト化」は味方ステータス / 敵ステータス / 属性補正タブでは無効化（デフォルト値を保持しない方針・復帰は git 履歴で管理）

---

## 敵データの構造整理（Phase B 下準備・2026-04-17）

### 目的
「クラスで決まる項目」（攻撃タイプ・攻撃間隔・スロット定義等）を個別敵 JSON から集約し、人間クラスと対称な構造に統一する。Config Editor「敵クラス」タブ実装の前準備。

### ファイル追加（`assets/master/classes/`）
敵固有 5 クラスのクラス JSON を新規作成：
- `zombie.json` — 近接・つかみ（melee / pre 0.70 / post 0.80）
- `wolf.json` — 高速近接・かみつき（melee / pre 0.30 / post 0.40）
- `salamander.json` — 遠距離炎（magic / range 4 / pre 0.50 / post 0.70）
- `harpy.json` — 飛行降下攻撃（dive / is_flying=true / pre 0.40 / post 0.60）
- `dark-lord.json` — 近接斬撃（melee / pre 0.60 / post 0.90）。ワープ・炎陣は AI 側実装

構造は人間クラス JSON と同じ（`id` / `name` / `weapon_type` / `base_defense` / `attack_type` / `attack_range` / `is_flying` / `behavior_description` / `slots.Z` / `slots.V`）。敵固有クラスの slots.V は null（特殊攻撃なし）。

### ファイル名の表記ルール
- **クラス JSON**：ハイフン区切り（`fighter-sword.json` / `dark-lord.json`）
- **個別敵 JSON**：アンダースコア区切り（`dark_lord.json` / `fighter_axe` の命名は無し）
- これは既存の命名に合わせた差異。今回は揃えない

### 個別敵 JSON から除去したフィールド（16 ファイル）
すべて：
- `attack_type` / `attack_range`
- `pre_delay` / `post_delay`

dark-priest のみ（`heal` / `buff` は healer クラス経由で自動適用されるため）：
- `heal_mp_cost` / `buff_mp_cost`

demon の `projectile_type` は個別敵 JSON に残す（`magician-fire` 共用クラスでは指定できない個体特有の値）。

### 個別敵 JSON に残す項目
- `id` / `name`（個体名。ゴブリン vs ホブゴブリンのように同クラスでも個体名は異なる）
- `is_undead` / `is_flying` / `instant_death_immune`（個体フラグ）
- `chase_range` / `territory_range`（個体の行動範囲）
- `behavior_description`（**個体固有の特徴説明**。「臆病で逃げる」「狂暴」等の個性）
- `projectile_type`（demon のみ）
- `sprites`
- `hp` / `power` / `skill` / `mp` 等（legacy。`apply_enemy_stats()` で上書き）
- `rank`（legacy。enemy_list.json で上書き）

### `healer.json` の正規化
- 削除：top-level `heal_mp_cost` / `buff_mp_cost`
- 保持：`slots.Z.mp_cost`（heal コスト = 5）/ `slots.V.mp_cost`（buff コスト = 8）
- `CharacterGenerator._build_data` で action="heal" の slots.Z から `heal_mp_cost` を、action="buff_defense" の slots.V から `buff_mp_cost` を読む

### `CharacterGenerator.apply_enemy_stats()` の拡張
既存のステータス上書き処理に加えて、`_load_class_json(stat_type)` でクラス JSON を読み、以下を CharacterData に注入：
- `attack_type` / `attack_range`
- `class_id`（stat_type と同じ）
- `slots.Z` から `z_pre_delay` / `z_post_delay` / `heal_mp_cost`（action="heal" のとき）
- `slots.V` から `v_pre_delay` / `v_post_delay` / `v_slot_mp_cost` / `v_slot_sp_cost` / `buff_mp_cost`（action="buff_defense" のとき）

クラス JSON が見つからない場合は CharacterData の既定値（attack_type="melee" 等）のまま続行。

### 副次的な挙動変更
- **dark-priest の攻撃**：旧実装では `attack_type="magic"`（個別 JSON）だったが、`stat_type="healer"` → クラス `attack_type="heal"` に統一。結果、dark-priest は「回復・バフ専用」の純粋なヒーラーとなり、非アンデッド（プレイヤー）には攻撃を仕掛けなくなる
- **敵の攻撃クールダウン**：敵は全て同一クラスの Z スロット値を使うようになり、個別調整値は失われる。人間クラス流用敵（例：goblin は fighter-axe）は「前回調整した Z スロット値（0.20 / 0.45）」に統一される

### 参照フロー
```
PartyManager → CharacterData.load_from_json(enemy_path)  // 個体固有項目のみ
            → CharacterGenerator.apply_enemy_graphics(data)
            → CharacterGenerator.apply_enemy_stats(data)
                  ↓
                  _load_stat_configs() で class_stats + enemy_class_stats をマージ
                  _load_enemy_list() で stat_type を取得
                  _calc_stats(stat_type, rank, sex, age, build) でステータス算出
                  stat_bonus 加算
                  _load_class_json(stat_type) でクラス JSON ロード
                  → attack_type / attack_range / slots.Z/V 由来値を CharacterData に上書き
```

---

## Config Editor「敵クラス」タブ（Phase B）

### 概要
味方クラスタブの描画ロジックを流用し、対象クラス ID 配列を差し替えるだけで実装。敵固有 5 クラス（zombie / wolf / salamander / harpy / dark-lord）の JSON を横断表で編集可能にする。

### トップタブ構成の変更
旧：`[定数] [味方クラス] [敵] [ステータス] [アイテム]`（敵タブは 6 サブタブ：ゴブリン系 / ウルフ系 / ... のプレースホルダー）
新：`[定数] [味方クラス] [敵クラス] [敵一覧] [ステータス] [アイテム]`

敵タブとその `ENEMY_SUB_TABS` 定数（6 敵種グループ）を削除。敵一覧タブは引き続きプレースホルダー。

### 共通描画関数のリファクタ
味方クラスタブの実装を `_build_class_tab_common(parent, tab_name, class_list)` にパラメータ化し、以下の関数に `class_list: Array[String]` 引数を追加：
- `_build_class_grid(parent, class_list)`
- `_build_class_header_row(parent, class_list)`
- `_build_class_row(parent, param_key, class_list)`
- `_collect_all_flat_params(class_list)`

`CLASS_PARAM_GROUPS`（グループ分け定義）は味方・敵共通で同じものを使う。敵固有クラスに存在しないパラメータ（例：敵クラスには weapon_type なし等）は行全体が描画されない（`all_params.has(p)` チェック）。

### 定数追加
- `TOP_TAB_ENEMY_CLASS: String = "敵クラス"`
- `TOP_TAB_ENEMY_LIST:  String = "敵一覧"`
- `ENEMY_CLASS_IDS: Array[String] = ["zombie", "wolf", "salamander", "harpy", "dark-lord"]`

### データ管理
- `_class_data` は 12 クラス全て（味方 7 + 敵固有 5）を保持する 1 つの Dictionary
- `_load_class_files()` は味方・敵の全 12 クラスを一括ロード。再ロード防止のため既存キーはスキップ
- `_save_class_files()` は dirty フラグが立ったクラスのみを `all_ids = CLASS_IDS + ENEMY_CLASS_IDS` から抽出して書き戻す

### ボタンの有効化
- 保存ボタン：TOP_TAB_ALLY_CLASS / TOP_TAB_ENEMY_CLASS / TOP_TAB_CONSTANTS / TOP_TAB_STATS で有効
- リセット / デフォルト化ボタン：TOP_TAB_CONSTANTS のみ有効（敵クラスタブもデフォルト値を保持しない方針）
- 味方クラスと敵クラスは同じ `_save_class_files()` を共有し、どちらのタブから保存しても 12 クラス全ての dirty ファイルを書き戻す

---

## Config Editor「敵一覧」タブ（Phase B - Step 3）

### 概要
`enemy_list.json`（rank / stat_type / stat_bonus × 16 敵）と個別敵 JSON の非 legacy フィールド（is_undead / is_flying / instant_death_immune / behavior_description / chase_range / territory_range）を 1 つの横断表 UI で一括編集する。

### 定数
- `ENEMY_LIST_PATH: String = "res://assets/master/stats/enemy_list.json"`
- `ENEMY_DIR: String = "res://assets/master/enemies/"`
- `ENEMY_IDS: Array[String]`（16 敵の表示順。`enemy_list.json` と一致）
- `ENEMY_RANK_CHOICES`（C/B/A/S）
- `ENEMY_STAT_TYPE_CHOICES`（人間 7 + 敵固有 5 = 12 クラス）
- `ENEMY_STAT_BONUS_CHOICES`（"---" + 13 ステータス = 14 項目）
- `ENEMY_STAT_BONUS_SLOTS: int = 6`（1 敵あたりの stat_bonus 枠数）

### 敵 ID → ファイル名変換
`_enemy_id_to_filename(eid)` がハイフンをアンダースコアに置換：
- `goblin-archer` → `goblin_archer.json`
- `dark-lord` → `dark_lord.json`

### データ保持
- `_enemy_list_data: Dictionary`（元の `enemy_list.json` 全体）
- `_enemy_indiv_data: Dictionary`（enemy_id → 個別敵 JSON Dict × 16）
- `_enemy_list_dirty: bool`（enemy_list.json の変更フラグ）
- `_enemy_indiv_dirty: Dictionary`（enemy_id → bool）

### ウィジェット
| 列 | 種別 | key 形式 | 保存先 |
|---|---|---|---|
| 敵ID | Label（固定） | — | — |
| rank | OptionButton（C/B/A/S） | `{eid}\|rank` | enemy_list.json |
| stat_type | OptionButton（12クラス） | `{eid}\|stat_type` | enemy_list.json |
| is_undead | CheckBox | `{eid}\|is_undead` | 個別敵JSON |
| is_flying | CheckBox | `{eid}\|is_flying` | 個別敵JSON |
| instant_death_immune | CheckBox | `{eid}\|instant_death_immune` | 個別敵JSON |
| behavior_description | LineEdit | `{eid}\|behavior_description` | 個別敵JSON |
| chase_range | LineEdit | `{eid}\|chase_range` | 個別敵JSON |
| territory_range | LineEdit | `{eid}\|territory_range` | 個別敵JSON |
| stat_bonus × 6 | OptionButton + LineEdit | `{eid}\|bonus_{0..5}_key` / `bonus_{0..5}_val` | enemy_list.json |

### stat_bonus の展開・集約
- **展開（起動時）**：`enemy_list.json[eid].stat_bonus` の各キーを先頭から 6 枠に割り当て。余った枠は `---` + 空欄・編集不可
- **集約（保存時）**：6 枠のうち `---` 以外の枠を辞書化（同じキーが複数枠にあれば後ろ勝ち）。`int` 変換失敗スロットはスキップ
- 空ディクショナリ `{}` も保存対象として出力される

### Dirty 判定
- `_enemy_list_dirty`：`_enemy_list_has_any_diff()` が全敵の rank / stat_type / stat_bonus を元値と比較
- `_enemy_indiv_dirty[eid]`：`_enemy_indiv_has_any_diff(eid)` がその敵の bool 3 + 文字列・数値 3 を元値と比較
- ウィジェット変更時に各ハンドラが上記を再評価して bool を更新

### 保存（`_save_enemy_list_tab`）
1. `_enemy_list_dirty == true` なら `_apply_enemy_list_edits()` で新 Dict を構築 → `JSON.stringify(..., "  ", false)` で `enemy_list.json` に書き戻し（キー順保持）
2. 各 `eid` で `_enemy_indiv_dirty[eid] == true` なら `_apply_enemy_indiv_edits(eid)` で新 Dict を構築 → 個別敵 JSON ファイルに書き戻し
3. 書き戻し成功分は dirty フラグを false に戻し、該当セルのハイライトを解除

### 個別敵 JSON の legacy 保護
`_apply_enemy_indiv_edits` は `duplicate(true)` で元を複製してから編集対象 6 フィールドのみを「元値と異なる場合だけ」上書きする。**元にフィールドが無かった場合はデフォルト値（false / ""）から変化したときのみ追加**。これにより：
- legacy フィールド（hp / power / skill / sprites 等）は完全に保持される
- ユーザーが触らなかったフィールドは元 JSON に無ければ追加されない（diff ノイズ防止）

### 既知の制限
- 左端の「敵ID」列の sticky（横スクロール時固定）は未実装（Godot 標準で一手間かかるため）
- 新敵追加は不可（新敵は `enemy_list.json` と個別敵 JSON 両方を作る必要があるためコード変更範囲）
- stat_bonus で同じキーを複数枠に選択した場合、保存時は後ろ勝ちで辞書化される（エラーにしない）
