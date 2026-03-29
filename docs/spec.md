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
| SPRITE_SOURCE_WIDTH | 512px | スプライト素材の元サイズ（横） |
| SPRITE_SOURCE_HEIGHT | 1024px | スプライト素材の元サイズ（縦） |

- スケール自動計算: `GRID_SIZE / SPRITE_SOURCE_WIDTH` = 0.125
- 表示サイズ: 64 × 128px（GRID_SIZE × GRID_SIZE*2 の縦長 1:2 比率）

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
- タイル種別: `enum TileType { FLOOR = 0, WALL = 1, RUBBLE = 2, CORRIDOR = 3 }`
- マップサイズ定数: `MAP_WIDTH = 20`, `MAP_HEIGHT = 15`
- マップデータ: `_tiles: Array`（Array[Array[int]]、行優先 `_tiles[y][x]`）
- 初期マップ: `_init()` で外周WALL・内側FLOORの四角い部屋を生成
- `get_tile(pos: Vector2i) -> TileType`: 範囲外は WALL を返す
- `is_walkable(pos: Vector2i) -> bool`: FLOOR・CORRIDOR が true
- `is_walkable_for(pos, flying)`: FLOOR・CORRIDOR は常に可。RUBBLE は flying=true のみ可。WALL は不可

#### タイル仕様
| タイル | 値 | 地上通過 | 飛行通過 | 画像 | フォールバック色 |
|-------|-----|---------|---------|------|--------------|
| FLOOR | 0 | ✅ | ✅ | tile_floor.png | Color(0.40, 0.40, 0.40) |
| WALL | 1 | ✗ | ✗ | tile_wall.png | Color(0.20, 0.20, 0.20) |
| RUBBLE | 2 | ✗ | ✅ | tile_rubble.png | Color(0.55, 0.45, 0.35) |
| CORRIDOR | 3 | ✅ | ✅ | tile_corridor.png | Color(0.30, 0.30, 0.35) |

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
| `behavior_description` | String | LLM行動生成用の自然言語説明 |

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
scripts/enemy_ai.gd        旧実装（LLMベース）。DungeonGenerator用 llm_client.gd は残す
```

#### LLMClient（llm_client.gd）
- DungeonGenerator のマップ生成専用として引き続き使用
- 敵AIからは完全に分離済み

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
| `MOVE_INTERVAL` | 0.4秒 | タイル移動の間隔 |
| `WAIT_DURATION` | 1.0秒 | wait アクションの待機時間 |
| `REEVAL_INTERVAL` | 1.5秒 | 定期再評価の間隔 |

```
IDLE → キューからアクションを取り出す
  "move_to_attack" → MOVING（MOVE_INTERVAL 秒ごとに1タイル移動、毎タイルゴール再計算、到達で IDLE）
  "flee"           → MOVING（脅威から離れる方向へ移動）
  "wait"           → WAITING（WAIT_DURATION 秒後に IDLE）
  "attack"         → ATTACKING_PRE（pre_delay 秒）
                       → _execute_attack()（方向倍率付きダメージ）
                     → ATTACKING_POST（post_delay 秒）→ IDLE
```

- 攻撃の隣接判定: `abs(dx) + abs(dy) == 1`（マンハッタン距離=1 のみ）
- 隣接していない場合はアクションをスキップして次へ

#### 方向ダメージ倍率（Character.get_direction_multiplier）
```
attack_from = attacker.grid_pos - target.grid_pos  # targetから見た攻撃方向
target_fwd  = Character.dir_to_vec(target.facing)

attack_from == target_fwd   → 正面 → 1.0倍
attack_from == -target_fwd  → 背面 → 2.0倍
それ以外                    → 側面 → 1.5倍
```

#### プレイヤーの攻撃（PlayerController）
- スペース / Enter キー（ui_accept）で発動
- 向いている方向の隣接マスを `blocking_characters` から検索
- ヒットした敵に `get_direction_multiplier` の倍率付きで `take_damage` を呼ぶ
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
  base_ai.gd              ★レガシー（[レガシー]コメント追加済み・将来削除）
  goblin_ai.gd            ★レガシー（[レガシー]コメント追加済み・将来削除）
```

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
| `BaseAI` | `UnitAI` + `PartyLeaderAI` | 移行完了。[レガシー]コメント付きで残存 |
| `GoblinAI` | `GoblinUnitAI` + `GoblinLeaderAI` | 移行完了。[レガシー]コメント付きで残存 |
| `EnemyManager` | `PartyManager` | `class EnemyManager extends PartyManager` として後方互換ラッパーに変更 |

### 後方互換の仕組み
- `EnemyManager extends PartyManager` により `game_map.gd` / `vision_system.gd` / `right_panel.gd` は無変更
- `PartyManager.enemy_ai` プロパティが `_leader_ai`（PartyLeaderAI）を返すため `em.enemy_ai.get_debug_info()` が動作
- `right_panel.gd` が使用する `BaseAI.Strategy.*` の int 値と `UnitAI.Strategy.*` の int 値は一致（ATTACK=0, FLEE=1, WAIT=2）

---

## Phase 3: フィールド生成 ✅ 完了

### 新規・変更ファイル
```
scripts/dungeon_generator.gd              LLMでダンジョン構造JSONを生成・保存（新規）
scripts/dungeon_builder.gd               構造JSONからMapDataをビルド（新規）
scripts/game_map.gd                      非同期ダンジョン読み込み・F5再生成対応
scripts/map_data.gd                      init_all_walls() / set_tile() 追加
scripts/llm_client.gd                    max_tokens を var に変更（外部から変更可能に）
scripts/enemy_manager.gd                 enemy_id / character_id の両キーに対応
assets/master/maps/dungeon_generated.json  実行時生成（.gitignore済み）
.gitignore                               dungeon_generated.json を追加
```

### DungeonGenerator（dungeon_generator.gd）
- `class_name DungeonGenerator extends Node`
- `FLOOR_COUNT = 3`（一度に生成するフロア数。10にすると4096トークンでギリギリ）
- `MAX_TOKENS = 4096`（LLMClientの`max_tokens`をこの値に設定）
- `generate()` — LLMにプロンプトを送信。毎回 `randi()` のシード値をプロンプトに含めることで異なるマップを生成
- `_on_response_received()` — `{"dungeon":{"floors":[...]}}` と `{"floors":[...]}` 両形式に対応。保存は常に前者の正規化形式
- `SAVE_PATH = "res://assets/master/maps/dungeon_generated.json"`
- シグナル: `generation_completed(dungeon_data)` / `generation_failed(error)`

### DungeonBuilder（dungeon_builder.gd）
- `class_name DungeonBuilder extends RefCounted`（静的メソッドのみ）
- `static func build_floor(floor_data: Dictionary) -> MapData`
  1. 全部屋の外接矩形からマップサイズを計算（+余白2タイル）
  2. `init_all_walls()` で全タイルをWALL初期化
  3. 各部屋を `_carve_room()`（外周1タイルをWALL残しで内部FLOOR展開）
  4. 各通路を `_carve_corridor()`（L字形、3タイル幅 = `CORRIDOR_HALF_WIDTH=1`）
  5. スポーン情報を `_build_spawn_data()` で構築
- `_carve_corridor()` — 部屋中心点間をL字で繋ぐ（横→縦の順）
- `_build_spawn_data()` — 入口部屋の中心をプレイヤースポーンに、各部屋の `enemy_party.members` を `enemy_parties` に設定

### game_map.gd の変更点
- `DUNGEON_JSON_PATH = "res://assets/master/maps/dungeon_generated.json"` をプライマリパスに
- `FALLBACK_JSON_PATH = "res://assets/master/maps/dungeon_01.json"` を静的フォールバックとして保持
- `CURRENT_FLOOR = 0`（表示するフロアのインデックス）
- `_ready()`:
  - JSONが存在 → `_load_generated_dungeon()` で即時読み込み
  - 存在しない → `_start_generation()` でLLM生成開始
- `_input()` でF5キーを検知 → `DirAccess.remove_absolute()` でJSON削除 → `reload_current_scene()`
- `_on_generation_completed()` → `reload_current_scene()`（保存済みJSONを次回起動で読む）
- `_on_generation_failed()` → フォールバックでダンジョン01を使用
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
- LLM生成JSONの `name` フィールドから DungeonBuilder が設定
- `_carve_room()` で部屋名を設定
- `build_floor()` の通路ループで `corridor_<from>_<to>` 形式のIDに通路名を設定

### LLMClient の変更点
- `const MAX_TOKENS := 1024` → `var max_tokens: int = 1024`（DungeonGeneratorが4096に上書き）
- JSONパース失敗時に先頭200文字を `push_error` で出力（デバッグ用）

### EnemyManager の変更点
- `info.get("character_id", "")` → `info.get("enemy_id", info.get("character_id", ""))`
  - 生成マップは `enemy_id` キー、静的マップは `character_id` キーを使うため両対応

### 動作フロー
```
初回起動:
  dungeon_generated.json なし
  → DungeonGenerator.generate() → LLMリクエスト（最大4096トークン）
  → 受信 → dungeon_generated.json 保存
  → reload_current_scene()
  → _load_generated_dungeon() → DungeonBuilder.build_floor(floors[0])
  → _finish_setup()

2回目以降:
  dungeon_generated.json あり
  → _load_generated_dungeon() → 即時起動

F5キー:
  dungeon_generated.json を削除 → reload_current_scene() → 初回起動フローへ
```

### 既知の制約・将来の拡張
- 現在は `CURRENT_FLOOR = 0` の1フロアのみ表示。フロア遷移は Phase 9 以降で実装予定
- `FLOOR_COUNT = 3` → 将来的に増やす場合、フロアごとに難易度を変えるプロンプトも追加
- 通路形状はL字固定。将来はより複雑な通路パターンも対応予定

## キャラクターステータス仕様

### ステータス一覧
| フィールド名（予定） | 型 | 説明 |
|-------------------|-----|------|
| `max_hp` | int | 最大HP |
| `max_mp` | int | 最大MP（魔法使用時に消費） |
| `melee_attack` | int | 近接攻撃力 |
| `melee_accuracy` | float | 近接命中精度 |
| `ranged_attack` | int | 遠隔攻撃力 |
| `ranged_accuracy` | float | 遠隔命中精度 |
| `magic_attack` | int | 魔法攻撃力 |
| `magic_accuracy` | float | 魔法命中精度 |
| `physical_resistance` | float | 物理攻撃耐性（割合軽減%。将来変更可。防具による補正も予定） |
| `magic_resistance` | float | 魔法攻撃耐性（同上） |
| `other_resistance` | Dictionary | その他耐性（炎・毒など随時追加） |
| `evasion` | float | 回避力（剣・盾による受け流しも含む） |
| `move_speed` | float | 移動速度（秒/タイル。標準0.4） |

### 命中判定（二段階）
1. **着弾判定**（命中精度）：攻撃が狙った対象に向かうか。命中精度が低いと別の敵・味方に誤射する可能性
2. **回避判定**（回避力）：着弾した対象が剣・盾で受け流すか、身をかわせるか

> 現在の実装（`attack` / `defense`）はこの仕様への移行前の暫定値。Phase 4以降で段階的に置き換える。

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
| キー | 種別 | 射程 |
|-----|------|------|
| Z | 近接攻撃 | マンハッタン距離 1（隣接4方向のみ） |
| X | 遠距離攻撃 | ユークリッド距離 5タイル以内 |
| C/V | 未実装（将来用） | — |

### ターゲット選択モード
- Z/X キー押下で TARGETING モードに入る（移動停止）
- 矢印キー（右/下 = 次、左/上 = 前）で循環選択：敵1 → 敵2 → キャンセル → 敵1…
- 同じキーを再押しで確定・攻撃実行
- キャンセルを選択して同キーを押すと NORMAL モードに戻る（Escape キーは使わない）
- 有効なターゲットが0体なら TARGETING モードに入らない
- ターゲットが死亡したら自動的に候補から除外し、全滅なら自動キャンセル
- 壁による遮断チェックは将来実装（現時点は射程のみ判定）
- 実行時点で射程外になっていたら空振り（飛翔体は飛ぶ）

### ターゲット選択中のpre_delay進行（未実装・仕様確定）
- Z/X キー押下時点から `pre_delay_timer` のカウントを開始する
- ターゲット選択中も `pre_delay_timer` は進行し続ける（選択操作でリセットしない）
- 選択確定時：`pre_delay_timer >= pre_delay` なら即発動、未満なら残り時間を待ってから発動
- 実装イメージ（PlayerController）:
  ```
  _enter_targeting() 内:
    _pre_delay_elapsed = 0.0  # タイマー開始

  _process(delta) 内（TARGETING中）:
    _pre_delay_elapsed += delta

  _confirm_attack() 内:
    var remaining = character_data.pre_delay - _pre_delay_elapsed
    if remaining > 0:
      await get_tree().create_timer(remaining).timeout
    _execute_attack()
  ```
- 効果：プレイヤーが慌てずにターゲットを選べる。素早く選べばほぼ待ち時間なし

### PlayerController ステートマシン
```
NORMAL:
  Z キー → _enter_targeting(MELEE)  ※有効ターゲットなしなら何もしない
  X キー → _enter_targeting(RANGED)
  矢印キー → 移動（従来どおり）

TARGETING:
  右/下 矢印キー → _cycle_target(+1)
  左/上 矢印キー → _cycle_target(-1)
  同スロットキー → _confirm_attack()（キャンセル選択中なら _exit_targeting()）
  全ターゲット死亡 → 自動 _exit_targeting()
```

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
scripts/player_controller.gd  NORMAL/TARGETINGステートマシン・Z/Xキー対応（全面改修）
scripts/character.gd          face_toward(target_grid_pos) 追加
scripts/game_map.gd           player_controller.map_node = self を追加
```

## Phase 5: グラフィック＆UI強化（一部完了）

### Phase 5 実装済み（トップビュー・タイル画像・飛行キャラ対応）

#### 変更ファイル
```
scripts/map_data.gd            RUBBLEタイル・is_walkable_for() 追加
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
| FLOOR | 0 | ✅ | ✅ | tile_floor.png |
| WALL | 1 | ✗ | ✗ | tile_wall.png |
| RUBBLE | 2 | ✗ | ✅ | tile_rubble.png |
| CORRIDOR | 3 | ✅ | ✅ | tile_corridor.png |

- `is_walkable_for(pos, flying: bool)`: FLOOR・CORRIDOR は常に可、RUBBLE は flying=true のみ可、WALL は不可
- `is_walkable(pos)`: 後方互換用（FLOOR・CORRIDOR が true）
- DungeonBuilder の `_carve_corridor()` が通路セルに CORRIDOR を設定（部屋の FLOOR は上書きしない）

#### タイル描画（game_map.gd）
- `_load_tile_textures()`: 起動時に4種の画像をプリロード。`_finish_setup()` から呼び出し
- `_draw()`: 画像があれば `draw_texture_rect`、なければフォールバック色で描画
  - フォールバック色: FLOOR=Color(0.40,0.40,0.40) / WALL=Color(0.20,0.20,0.20) / RUBBLE=Color(0.55,0.45,0.35) / CORRIDOR=Color(0.30,0.30,0.35)
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
| F5 | ダンジョン再生成（dungeon_generated.json 削除 → シーンリロード） |

#### エディター設定（project.godot 外・開発環境）
- Editor Settings → 実行 → ウィンドウの配置 → **Game Embed Mode = Disabled**
  - 別ウィンドウで起動。エディター上部ツールバーが非表示になる

#### キャラクター状態表示（character.gd）
- `is_targeting_mode: bool`（setter: 変更時に `_update_ready_sprite()` を呼び出してスプライト切替）
  - true 時: `character_data.sprite_top_ready` があればその画像に切替（未設定なら sprite_top のまま）
  - false 時: `sprite_top` に戻す
- `is_attacking: bool`（setter: EnemyAI の ATTACKING_PRE 開始時に true、ATTACKING_POST 終了時に false）
  - `is_targeting_mode OR is_attacking` のどちらかが true なら構え画像に切替
  - 将来の仲間AI実装時も同じフラグで対応可能
- `is_targeted: bool`（選択されたターゲット：`Color(1.5, 1.5, 1.5, 1.0)` の白く輝く表現）
- `_update_modulate()` で優先順位：ターゲット選択中 > HP状態
  - is_targeted が true: `Color(1.5, 1.5, 1.5, 1.0)`（オーバーブライト白）
  - HP状態: ratio>0.6=白, ratio>0.3=黄(0.65), ratio>0.1=オレンジ(0.65), それ以下=赤点滅

#### ヒットエフェクト（hit_effect.gd）
- `take_damage()` 呼び出し時に `_spawn_hit_effect()` で HitEffect を生成（`get_parent().add_child()`）
- HitEffect はキャラクターの親ノード（game_map）に追加し、world 座標でヒット位置に表示
- `assets/images/effects/hit_01.png`〜`hit_06.png` が存在すれば AnimatedSprite2D でアニメーション再生
  - FRAME_FPS = 16.0 / SOURCE_SIZE = 512.0 / スケール: `GRID_SIZE / SOURCE_SIZE * 1.3`
  - `animation_finished` で自動 `queue_free()`
- ファイルなしの場合: 白い円（r=GRID_SIZE*0.60）が広がりながら0.14秒でフェードアウト
- 推奨アセット: Kenney Particle Pack（CC0 / https://kenney.nl/assets/particle-pack）
  - spark / star 系の PNG 6枚を `hit_01.png`〜`hit_06.png` にリネームして配置

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

**デバッグ表示内容（現在エリアの敵のみ・`BaseAI.get_debug_info()` から取得）:**

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

**BaseAI.get_debug_info() の返却形式:**
```
[
  {
    "name": "Goblin0",
    "strategy": int（BaseAI.Strategy 列挙値）,
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

#### RightPanel（right_panel.gd）
- `CanvasLayer` (layer=10) → `Control` → `draw` シグナル
- `enemy.visible == true` の敵を character_id ごとに集計
- 表示: "種類名 ×N" + ランク文字
- ランク色: S/A=赤, B/C=オレンジ
- `CharacterData.rank: String`（デフォルト "C"、JSON の `"rank"` キーから読み込み）
- ランクはS/A/B/Cの4段階（Phase 6-0でD/E/Fを廃止・統一）

#### MessageWindow（message_window.gd）
- `CanvasLayer` (layer=12) → `Control` → `draw` シグナル
- `show_message(msg)` でタイマーリセット・alpha=1.0
- 表示: `DISPLAY_DURATION=3.0` 秒後に `FADE_DURATION=0.5` 秒でフェードアウト
- 表示位置: フィールドエリア下中央（`vw - 2*pw` 幅の80%）
- ※ エリア入室通知は AreaNameDisplay に移行。現在呼び出し元なし（将来のシステムメッセージ用に保持）

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
4. `最終ステータス = クラス基準値 × ランク補正 × 体格補正 × 性別補正 × 年齢補正` で計算

### ステータス決定構造
| 要素 | 補正幅 | 方向性 |
|------|--------|--------|
| ランク（S〜C） | 約2倍差 | 見た目に非依存。純粋な強さ |
| 体格（slim/medium/muscular） | 約2倍差 | サブクラス的機能。muscular=高火力低回避、slim=低火力高回避 |
| 性別（male/female） | ±20% | male=近接攻撃力・HP高め、female=速度・回避・魔法系高め |
| 年齢（young/adult/elder） | ±20% | young=速度・回避高め、adult=バランス、elder=魔法・耐性高め |

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

### 配置
- ダンジョンのNPC配置はマップJSONの `npc_parties` に記述（enemy_parties と同構造）
- LLM生成ダンジョンでは DungeonGenerator がNPCパーティーも生成（Phase 6-1で追加）

### 行動
- NPC用AIController：敵AIと同構造、ターゲットは敵
- NPCはプレイヤーエリアに入ったタイミングでアクティブ化

### 仲間加入（Phase 6-2で詳細決定）
- 加入条件・会話トリガー・UIは Phase 6-2 で設計

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

### Phase 6-1: 仲間NPCの配置と基本AI行動（未実装）
- ダンジョンにNPCパーティーを配置
- NPC用AIController実装

### Phase 6-2: 仲間の加入の仕組み（未実装）
- プレイヤーパーティーへのNPC加入フロー
- 加入UI・会話トリガー

### Phase 6-3: 操作キャラの切替（未実装）
- `AIController` の本実装
- `Party.set_active()` を使ったプレイヤー操作キャラクターの切替

## Phase 7: 指示システム（未実装）
- 攻撃 / 防衛 / 待機 / 追従 / 撤退
- 指示UI（コマンドメニュー）

## Phase 8: 敵のバリエーション（未実装）
- ゴブリン以外の敵を追加
- `behavior_description` の自然言語説明で行動パターンをLLMに伝える

## Phase 9: ステージ・バランス調整（未実装）

## Phase 10: Steam配布準備（未実装）

---

## Git / GitHub
- リポジトリ: https://github.com/komuro72/trpg
- ブランチ: master
- `.godot/` フォルダはGitignore済み
- `.uid` ファイルはコミット対象（Godot 4 のリソース解決に必要）
