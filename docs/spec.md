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

### Phase 2-3: LLMによるAI行動生成 ✅ 完了

#### 新規・変更ファイル
```
scripts/llm_client.gd      Anthropic API HTTPラッパー（新規）
scripts/enemy_ai.gd        アクションキュー管理・LLM呼び出し制御（新規）
scripts/enemy_manager.gd   アクティブ化後に EnemyAI を起動するよう変更
scripts/character_data.gd  pre_delay / post_delay フィールド追加
assets/master/enemies/goblin.json  pre_delay / post_delay 追加
```

#### LLMClient（llm_client.gd）
- `class_name LLMClient extends Node`
- APIキー: `res://api_key.txt` から読み込み（.gitignore済み）
- モデル: `claude-haiku-4-5-20251001` / max_tokens: 1024
- `request(prompt)` — HTTPRequest で非同期送信。`is_requesting` フラグで多重送信防止
- シグナル `response_received(result: Dictionary)` — パース済みDictionaryを返す
- シグナル `request_failed(error: String)` — エラー内容を返す
- LLMが ` ```json ... ``` ` で囲んで返した場合も `_extract_json()` で中身を取り出す

#### EnemyAI（enemy_ai.gd）
- `class_name EnemyAI extends Node`
- `setup(enemies, player, behavior_description, map_data)` — アクティブ化後に EnemyManager から呼び出す
- `_queues: Dictionary` — メンバーIDごとのアクションキュー `{ "Goblin0": [{...}, ...] }`
- `_current: Dictionary` — 現在実行中のアクション
- `QUEUE_REFILL_THRESHOLD = 1` — キューがこの数以下で再リクエスト
- `_force_regen: bool` — 攻撃を受けたなど状況変化時の強制再生成フラグ
- `notify_situation_changed()` — 外部から状況変化を通知（`_force_regen = true`）
- `complete_action(enemy_id)` — アクション完了を通知（`_current` から除去）

#### CharacterData の追加フィールド
| フィールド | 型 | デフォルト | 説明 |
|-----------|-----|----------|------|
| `pre_delay` | float | 0.3 | 攻撃前の溜め時間（秒） |
| `post_delay` | float | 0.5 | 攻撃後の硬直時間（秒） |

#### goblin.json の追加値
- `pre_delay: 0.3` / `post_delay: 0.5`

#### 動作確認
- プレイヤーが5マス以内に近づくと `EnemyAI.setup()` → LLMリクエスト開始
- レスポンス受信後 `[EnemyAI] キュー更新:` をコンソール出力
- Phase 2-4 で `pop_next_action()` が呼ばれてキューが消費されると自動補充される

#### LLM呼び出し設計上の決定事項
- LLMへのプロンプトはパーティー単位（3体まとめて1回のAPI呼び出し）
- 返答は行動シーケンス形式（`relative_position` で移動先を指定）
- リアルタイム判断方式（ルール事前生成ではなく）を採用

### Phase 2-4: 移動・攻撃の実装 ✅ 完了

#### 新規・変更ファイル
```
scripts/enemy_ai.gd          ステートマシン・移動・攻撃実行ロジック
scripts/enemy_manager.gd     setup() に map_data 追加、get_enemies() 追加
scripts/game_map.gd          map_data を渡す・HUD セットアップ追加
scripts/character.gd         get_occupied_tiles() / dir_to_vec() / get_direction_multiplier() 追加
                             take_damage() に multiplier 引数追加
scripts/player_controller.gd 攻撃入力・blocking_characters・占有チェック追加
scripts/hud.gd               ステータスHUD（新規）
```

#### EnemyAI ステートマシン（完成版）
| 定数 | 値 | 説明 |
|------|-----|------|
| `MOVE_INTERVAL` | 0.4秒 | タイル移動の間隔 |
| `WAIT_DURATION` | 1.0秒 | wait アクションの待機時間 |

```
IDLE → キューからアクションを取り出す
  "move"   → MOVING（MOVE_INTERVAL 秒ごとに1タイル移動、目標到達で IDLE）
  "wait"   → WAITING（WAIT_DURATION 秒後に IDLE）
  "attack" → ATTACKING_PRE（pre_delay 秒）
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
| プレイヤーの向き | front | back | left_side | right_side |
|----------------|-------|------|-----------|------------|
| FRONT (+Y)     | (0,+1)| (0,-1)| (-1,0)  | (+1,0)     |
| BACK (-Y)      | (0,-1)| (0,+1)| (+1,0)  | (-1,0)     |
| RIGHT (+X)     | (+1,0)| (-1,0)| (0,-1)  | (0,+1)     |
| LEFT (-X)      | (-1,0)| (+1,0)| (0,+1)  | (0,-1)     |

##### 占有チェック設計（複数マスキャラ対応）
- `Character.get_occupied_tiles() -> Array[Vector2i]` — 現在は `[grid_pos]` を返す
- 将来の複数マスキャラはこのメソッドをオーバーライドするだけで対応
- `PlayerController.blocking_characters: Array[Character]` に敵リストを渡す
  - `EnemyManager.get_enemies()` が `_enemies` の参照を返すため、敵の死亡が自動反映される
- `EnemyAI._is_passable()` も同メソッドで統一

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
- `_setup_enemies()` — 全 `enemy_parties` のメンバーをフラット化して1つのEnemyManagerに渡す
- 生成中は「ダンジョン生成中...」ラベルをCanvasLayerで表示

### MapData の追加メソッド
| メソッド | 説明 |
|---------|------|
| `init_all_walls(w, h)` | 指定サイズで全WALL初期化（DungeonBuilderが使用） |
| `set_tile(pos, tile)` | 指定座標のタイルを書き込む（DungeonBuilderが使用） |

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

## Phase 4: 攻撃バリエーション（未実装）
- 遠距離・範囲攻撃
- 既存の `pre_delay` / `post_delay` / `attack_type` 設計を活用

## Phase 5: 敵のバリエーション（未実装）
- ゴブリン以外の敵を追加
- `behavior_description` の自然言語説明で行動パターンをLLMに伝える

## Phase 6: UIまわり（未実装）
- HPバー・攻撃エフェクトなど

## Phase 7: 仲間AI・操作切替（未実装）
- `AIController` の本実装
- `Party.set_active()` を使ったプレイヤー操作キャラクターの切替
- 切替時: 旧キャラ → `AIController`、新キャラ → `PlayerController`

## Phase 8: 指示システム（未実装）
- 攻撃 / 防衛 / 待機 / 追従 / 撤退
- 指示 UI（コマンドメニュー）

## Phase 9: ステージ・バランス調整（未実装）

## Phase 10: Steam配布準備（未実装）

---

## Git / GitHub
- リポジトリ: https://github.com/komuro72/trpg
- ブランチ: master
- `.godot/` フォルダはGitignore済み
- `.uid` ファイルはコミット対象（Godot 4 のリソース解決に必要）
