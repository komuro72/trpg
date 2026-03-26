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
  global_constants.gd    GRID_SIZE等のグローバル定数（Autoload）
  character_data.gd      画像パス一元管理リソースクラス
assets/characters/       スプライト素材格納ディレクトリ（仮素材なし→プレースホルダー表示）
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
- フィールド: `character_id`, `sprite_front`, `sprite_back`, `sprite_left`, `sprite_right`
- `static func create_hero() -> CharacterData` でヒーロー用データを生成
- 画像パス規則: `res://assets/characters/{id}_front.png` など

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

### Phase 1-3: フィールド・マップ基盤（タイルマップ・Zオーダー）

#### 概要
現在の `_draw()` によるシンプルなグリッドを `TileMap` に置き換え、Zオーダーを整備する。

#### 追加・変更予定ファイル
```
scenes/
  game_map.tscn          TileMapLayer ノードを追加
assets/tiles/            タイルセット素材（新規）
scripts/
  game_map.gd            TileMap 初期化処理を追加
```

#### 実装内容
- Godot 4 の `TileMapLayer` ノードを使用
- レイヤー構成（暫定）:
  - Layer 0: 地面（grass, dirt など）
  - Layer 1: 障害物（木、岩など）→ Phase 2 の衝突判定と連携
- Zオーダー: `y_sort_enabled = true` を GameMap ノードに設定し、キャラクターのフィートY座標でソート
- Phase 1 はプロトタイプタイルで可（単色 or 仮素材）

#### 留意点
- `GlobalConstants.GRID_SIZE`（=64）はタイルサイズと一致させる
- 斜め見下ろし視点では将来的にアイソメトリック対応が必要になる可能性があるが、Phase 1 は真上見下ろしで進める

---

### Phase 1-4: カメラ・スクロール（追従・範囲制限）

#### 概要
主人公の移動に追従する `Camera2D` を実装し、マップ端でのクリッピングを行う。

#### 追加・変更予定ファイル
```
scenes/
  game_map.tscn          Camera2D ノードを Hero の子に追加
scripts/
  game_map.gd            カメラ範囲制限の設定
```

#### 実装内容
- `Camera2D` を `Hero` ノードの子として配置（自動追従）
- カメラ範囲制限（`limit_left` / `limit_right` / `limit_top` / `limit_bottom`）をマップサイズに合わせて設定
  - `limit_right = MAP_WIDTH * CELL_SIZE`
  - `limit_bottom = MAP_HEIGHT * CELL_SIZE`
- スムーズ追従: `position_smoothing_enabled = true`（任意）

#### 留意点
- マップがウィンドウサイズより小さい場合はカメラ追従不要（範囲制限のみ）
- 将来のマップ拡張を見越して、マップサイズは定数から動的に取得する設計にする

---

### Phase 1-5: 統合・動作確認

#### チェックリスト
- [ ] スプライトが4方向それぞれ正しく表示・切り替わる
- [ ] 歩行アニメーションが移動中に再生され、停止時にidle になる
- [ ] タイルマップが表示され、キャラクターとのZオーダーが正しい
- [ ] カメラがキャラクターに追従し、マップ端で止まる
- [ ] 長押し移動・マップ端での停止が正常動作する
- [ ] `CharacterData.gd` の画像パスを変えるだけで素材を差し替えられる

---

## Phase 2: 戦闘基盤（未実装）
- HP・攻撃・当たり判定
- ダメージ計算
- 敵キャラクター（仮）
- `AIController` の基礎実装

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
