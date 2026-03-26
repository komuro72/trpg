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
- enum 変更: `Direction { FRONT, BACK, LEFT, RIGHT }`（旧 DOWN→FRONT, UP→BACK）
- 移動方向マッピング:
  - delta.y > 0 → FRONT, delta.y < 0 → BACK
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
- タイル種別: `enum TileType { FLOOR = 0, WALL = 1 }`
- マップサイズ定数: `MAP_WIDTH = 20`, `MAP_HEIGHT = 15`
- マップデータ: `_tiles: Array`（Array[Array[int]]、行優先 `_tiles[y][x]`）
- 初期マップ: `_init()` で外周WALL・内側FLOORの四角い部屋を生成
- `get_tile(pos: Vector2i) -> TileType`: 範囲外は WALL を返す
- `is_walkable(pos: Vector2i) -> bool`: FLOOR のみ true

#### タイル描画（game_map.gd）
| タイル | 色 | 値 |
|--------|----|----|
| FLOOR（床） | グレー | Color(0.40, 0.40, 0.40) |
| WALL（壁） | 暗いグレー | Color(0.20, 0.20, 0.20) |
| グリッド線 | 半透明ライン | Color(0.30, 0.30, 0.30, 0.5) |

- `_draw()` で全タイルをループ描画（`draw_rect` + アウトライン）
- `MapData` を `_setup_map()` で初期化し、`map_data` 変数で保持
- `PlayerController` に `map_data` を渡す
- 将来のタイル画像差し替えは `game_map.gd` の描画部分のみ変更すればよい

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
- `setup(spawn_list, player)` — JSONのmembersリストから敵をスポーン
- `_spawn_enemy(char_id, grid_pos)` — `get_parent().add_child()` でGameMapに追加
- `_process()` — 未アクティブ時のみ距離チェック。5マス以内で `_activated = true`
- アクティブ化後の行動は Phase 2-3（LLM）で実装予定
- 敵死亡時は `_on_enemy_died()` で `_enemies` と `enemy_party` から除去

#### game_map.gd の変更点
- `_setup_map()` → `MapData.load_from_json(MAP_JSON_PATH)` に変更
- `_setup_hero()` → `map_data.player_parties[0]` からスポーン座標を取得
- `_setup_enemies()` → `EnemyManager` を生成・追加、`enemy_manager.setup()` 呼び出し
- `_setup_camera()` / `_draw()` → `MapData.MAP_WIDTH/HEIGHT` 定数から `map_data.map_width/height` インスタンス変数に変更

---

### Phase 2-3: LLMによるAI行動生成（未実装）
- GodotからAnthropicのAPIを呼び出す基盤
- 自然言語の行動説明＋現在の状況をLLMに送信し行動を決定
- まずゴブリン1種類でテスト
- リアルタイムLLM判断 vs ルール事前生成は検証結果を踏まえて判断

### Phase 2-4: 移動・攻撃の実装（未実装）
- AI行動生成に基づく敵の移動・攻撃
- プレイヤーの攻撃
- 当たり判定・ダメージ処理

## Phase 3: 仲間AI・操作切替（未実装）
- `AIController` の本実装
- `Party.set_active()` を使ったプレイヤー操作キャラクターの切替
- 切替時: 旧キャラ → `AIController`、新キャラ → `PlayerController`

## Phase 4: 指示システム（未実装）
- 攻撃 / 防衛 / 待機 / 追従 / 撤退
- 指示 UI（コマンドメニュー）

## Phase 5: ステージ・UI・バランス調整（未実装）

## Phase 6: Steam配布準備（未実装）

---

## Git / GitHub
- リポジトリ: https://github.com/komuro72/trpg
- ブランチ: master
- `.godot/` フォルダはGitignore済み
- `.uid` ファイルはコミット対象（Godot 4 のリソース解決に必要）
