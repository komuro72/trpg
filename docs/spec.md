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
scripts/dungeon_generator.gd              LLMでダンジョン構造JSONを生成・保存（新規。現在は未使用・将来削除対象）
scripts/dungeon_builder.gd               構造JSONからMapDataをビルド（新規）
scripts/game_map.gd                      ダンジョン読み込み・F5シーン再スタート
scripts/map_data.gd                      init_all_walls() / set_tile() 追加
scripts/llm_client.gd                    max_tokens を var に変更（現在は未使用・将来削除対象）
scripts/enemy_manager.gd                 enemy_id / character_id の両キーに対応
assets/master/maps/dungeon_generated.json  外部から配置した場合に使用（.gitignore済み）
.gitignore                               dungeon_generated.json を追加
```

### DungeonGenerator（dungeon_generator.gd）※現在未使用・将来削除対象
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
  3. 各部屋を `_carve_room()`（外周1タイルをWALL残しで内部FLOOR展開）
  4. 各通路を `_carve_corridor()`（L字形、3タイル幅 = `CORRIDOR_HALF_WIDTH=1`）
  5. スポーン情報を `_build_spawn_data()` で構築
- `_carve_corridor()` — 部屋中心点間をL字で繋ぐ（横→縦の順）
- `_build_spawn_data()` — 入口部屋の中心をプレイヤースポーンに、各部屋の `enemy_party.members` を `enemy_parties` に設定

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

### LLMClient の変更点 ※現在未使用・将来削除対象
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
| `move_speed` | float | 移動速度（秒/タイル。標準0.4） |
| `leadership` | int | 統率力（リーダー側。クラス・ランクから算出、確定後不変。当面値のみ保持） |
| `obedience` | float | 従順度（個体側 0.0〜1.0。クラス・種族・ランクから算出、確定後不変。当面値のみ保持） |
| `inventory` | Array | アイテムインスタンスの辞書リスト（装備中・未装備品・消耗品すべて含む） |

**装備パラメータ（アイテムインスタンス側に持つ・CharacterData には含まない）**
| フィールド名 | 型 | 説明 |
|-----------|-----|------|
| `block_power` | int | 防御強度。防御成功時に無効化できるダメージ量。武器・盾が持つ |

> **注記**: `attack_power`（物理攻撃力）と `magic_power`（魔法威力）は近接/遠距離/魔法を統合した確定仕様。Phase 10-2 以降でも分離しない。

### OrderWindow での表示
- ステータスは素値・補正値（装備合算）・最終値の3列表示（例：攻撃力 15 +3 → 18）
- ヒーラー（attack_type="heal"）には命中精度行を表示しない（回復魔法は必中のため）

### 命中・被ダメージ計算（詳細は「ステータス仕様更新」節を参照）
1. **着弾判定**（accuracy）：命中精度が基準値未満 → 外れ or 誤射（将来実装）
2. **防御判定**（defense_accuracy）：背面攻撃はスキップ。成功時に武器・盾の block_power でダメージカット
3. **耐性適用**（physical/magic resistance）：割合軽減
4. **最終ダメージ確定**（最低1）

### ダメージ計算への装備補正反映（Phase 10-2 実装予定）
```
攻撃力   = attack_power (素値) + 武器 attack_power
命中精度 = accuracy (素値)     + 武器 accuracy
魔法威力 = magic_power (素値)  + 杖 magic_power
物理耐性 = 素値 + 防具 physical_resistance + 盾 physical_resistance
魔法耐性 = 素値 + 防具 magic_resistance    + 盾 magic_resistance
防御強度 = 素値 + 武器 block_power         + 盾 block_power
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
| F5 | シーン再スタート（`get_tree().reload_current_scene()`） |

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
- **NPCから話しかけてくる場合**: 上記2択のどちらかで申し出、プレイヤーが承諾/拒否を選択
- **NPCの申し出ロジック（当面）**: パーティーに重傷者が多い場合、相手パーティーの傘下に入る形で申し出
- **NPCリーダーAIの承諾/拒否判断（当面）**: 双方のパーティー総合力を比較して判断

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
- 15部屋・8敵パーティー（ゴブリン計21体）・5NPCパーティー（10体）
- 4列×4行 + 1部屋のグリッドレイアウト（14×12 タイルルーム）
- 起動時は dungeon_handcrafted.json を直接読み込む

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
  - プレイヤー起点（矢印キーバンプ）は `try_trigger_for_member()` 経由で呼ばれる
  - これにより「立ち去る」選択後に毎フレーム再トリガーされるバグを防止
- 会話トリガー条件: 現エリアに生存敵なし + プレイヤーと NPC 隣接（距離1）+ 通路でない（エリアID空は除外）
- `is_area_enemy_free(area)` はゲームマップの敵入室中断チェックでも共用
- `try_trigger_for_member(member: Character)`: 矢印キーバンプ時に PlayerController 経由で呼ばれる。同じ条件を確認して `dialogue_requested` を発火

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

**DialogueWindow（CanvasLayer layer=15）**
- 画面下部ポップアップ（`vp_h - panel_h - 16px` に配置）
- パネル幅: フィールド幅 - 32px（左右パネルの内側いっぱい）
- フォントサイズ: GRID_SIZE 連動（1080p基準: タイトル≈18px、本文≈16px、ヒント≈13px）
- プレイヤー起点: 3択（仲間に / 連れて行って / 立ち去る）
- NPC 起点: 2択（承諾する / 断る）＋ NPC の申し出セリフ表示
- `show_rejected()` で拒否メッセージを 1.8 秒表示後に自動クローズ
- 操作: ↑↓ 選択 / Z・Enter 決定 / Esc キャンセル

**NpcLeaderAI の新メソッド**
| メソッド | 説明 |
|---------|------|
| `wants_to_initiate() -> bool` | 重傷者（HP<50%）が過半数なら true |
| `get_party_strength() -> float` | 全メンバーの max_hp 合計 |
| `will_accept(offer_type, player_strength) -> bool` | "join_us": NPC 総合力 ≤ プレイヤー総合力×1.5 なら承諾。"join_them": 常に承諾 |

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

飛行キャラ（`is_flying = true`）は WALL・RUBBLE・地上キャラ占有タイルを通過できる。
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
    _           → DefaultLeaderAI（goblin-archer, goblin-mage, zombie, harpy, salamander, dark-knight, dark-mage, dark-priest）
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
assets/images/projectiles/
  arrow.png        矢（弓使い・ゴブリンアーチャー）
  magic_bullet.png 魔法弾（魔法使い・ゴブリンメイジ・ダークメイジ）
  flame.png        炎（サラマンダー）
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
- `CharacterGenerator._calc_stats()` で defense_mult を使って耐性計算（上限 0.75 でクランプ）
- `CharacterData.get_total_physical_resistance()` / `get_total_magic_resistance()`: 素値＋装備補正を合算し 0.95 でクランプ

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
2. **防御判定**（`defense_accuracy` で成功/失敗）
   - 成功時 `_calc_block_power(direction)` でカット量を決定
     - front: weapon_block + shield_block / left: shield_block / right: weapon_block / back: 0
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

### Phase 10-3: 消耗品の使用

#### 変更ファイル
| ファイル | 変更内容 |
|---------|---------|
| `scripts/player_controller.gd` | LT ホールド中の A/B/X/Y をアイテムスロット1〜4として処理 |
| `scripts/character.gd` | `use_consumable(slot_index)` メソッド追加 |

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

## Phase 11: フロア・ダンジョン拡張（未実装）

### Phase 11-1: 階段実装・フロア遷移

#### 仕様
- 階段を踏んだキャラのみ移動（パーティー分断あり）
- 操作キャラが別フロアに移動したらカメラはそのキャラを追う
- 残ったメンバーは AI 行動継続
- 上のフロアへの移動も可能（往来自由）
- 倒した敵はフロアをまたいでも復活しない
- 敵も階段を使って別フロアに移動できる（原則は部屋を守るため自発的には移動しない）
- フロアは縦方向につながったひとつの大きなダンジョンとして扱う（フロア単位の独立概念なし）

#### 設計メモ
- MapData を複数フロア分保持する仕組みが必要（`floors: Array[MapData]`）
- VisionSystem・CameraController・EnemyManager 等のフロア切替対応が必要
- 現行の `CURRENT_FLOOR = 0` 定数を廃止して動的に管理

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

## Phase 12: ステージ・バランス調整（未実装）

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
- `move_to(new_grid_pos, duration=0.4)`: grid_pos を即時更新（衝突判定維持）し、position を duration 秒かけて補間開始
- `sync_position()`: 即座スナップ＋補間キャンセル（初期配置・テレポート用）
- `is_moving() -> bool`: `_visual_duration > 0.0` を返す（PlayerController の gate 判定に使用）
- `_update_visual_move(delta)`: _process() から毎フレーム呼ぶ。位置補間とスプライトフレーム切替を行う

### game_speed による速度制御
GlobalConstants に `var game_speed: float = 1.0` を追加。将来の設定画面からここを変更することで全体速度を調整できる。

| 対象 | 基準値 | 実効値の計算 |
|------|--------|-------------|
| UnitAI MOVE_INTERVAL | 1.2s | `MOVE_INTERVAL / game_speed` |
| UnitAI WAIT_DURATION | 3.0s | `WAIT_DURATION / game_speed` |
| PlayerController MOVE_INTERVAL | 0.30s | `MOVE_INTERVAL / game_speed` |

- `game_speed = 1.0`: 標準速度（1タイル1.2秒）
- `game_speed = 2.0`: 2倍速（1タイル0.6秒）

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

### ウィンドウ構成
```
┌──────────────────────────────────┐
│  [上部] キャラ一覧テーブル        │
│    全体方針プリセット行           │
│    メンバー行: 名前・5指示項目    │
│    ↑↓行移動 / ←→列移動 / Z切替  │
├──────────────────────────────────┤
│  [下部] 選択中キャラ詳細          │
│    ステータス（素値・補正・最終値）│
│    装備スロット（武器・防具・盾）  │
│    所持アイテム（消耗品スロット）  │
└──────────────────────────────────┘
```

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
  potion_hp.json      HPポーション
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

### 防御強度の計算
```
使用可能な防御強度 = 攻撃方向に応じた装備の防御強度の合計

正面:   equipped_shield.defense_strength + equipped_weapon.defense_strength
左側面: equipped_shield.defense_strength
右側面: equipped_weapon.defense_strength
背面:   0（防御判定スキップ）
```
- 盾未装備の場合、盾の防御強度は 0 として計算

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
| （新規） | 防御強度（defense_strength） | 武器・盾のパラメータ |

### 防御精度（defense_accuracy）
- キャラクター固有の素値（クラス基準値 × ランク/体格/性別/年齢 補正）
- 防御判定の成功確率を決定（実装時に確率計算の詳細を定義）
- 装備による補正なし

### 防御強度（defense_strength）
- 武器・盾それぞれが持つ数値
- 防御判定成功時に「使用可能な防御強度の合計」をダメージから引く
- 例: 剣（防御強度3）+ 盾（防御強度5）装備、正面から攻撃
  → 防御判定成功時に最大8ダメージをカット

### 被ダメージ計算の全フロー
```
1. 着弾判定
   命中精度が基準値未満 → 外れ or 誤射（将来実装）

2. 防御判定（背面攻撃はスキップ）
   判定成功（防御精度に基づく確率）:
     カット量 = 攻撃方向に応じた使用可能な防御強度の合計
     残ダメージ = max(0, 攻撃ダメージ - カット量)
   判定失敗:
     残ダメージ = 攻撃ダメージ

3. 耐性適用
   残ダメージ × (1.0 - 物理or魔法耐性%)

4. 最終ダメージ
   max(1, 残ダメージ)    ← 最低1は保証
```

### CharacterData のフィールド変更
- `evasion` → `defense_accuracy: float` にリネーム
- `equipped_weapon / equipped_armor / equipped_shield: ItemData` を追加（装備スロット）
- アイテムシステム実装前は装備スロットは null のまま（防御強度0として計算）

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

## Git / GitHub
- リポジトリ: https://github.com/komuro72/trpg
- ブランチ: master
- `.godot/` フォルダはGitignore済み
- `.uid` ファイルはコミット対象（Godot 4 のリソース解決に必要）
