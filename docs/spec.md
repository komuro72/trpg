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

#### グリッド定数（game_map.gd / character.gd）
| 定数 | 値 | 説明 |
|------|-----|------|
| CELL_SIZE | 48px | 1グリッドセルのピクセルサイズ |
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

### Phase 1-2: グラフィック表示（スプライト・4方向アニメーション）

#### 概要
仮の四角形をスプライトに差し替え、4方向・歩行アニメーションを実装する。

#### 追加・変更予定ファイル
```
scripts/
  character_data.gd      画像パス・アニメーション定義の一元管理（新規）
assets/characters/       スプライトシート格納ディレクトリ（新規）
```

#### 実装内容
- `character.gd` の `_draw()` を `AnimatedSprite2D` に置き換え
- `CharacterData` リソースクラスで画像パスを管理（CLAUDE.md 方針）
- アニメーション名の規則: `walk_down` / `walk_up` / `walk_left` / `walk_right`
- 待機アニメーション: `idle_down` / `idle_up` / `idle_left` / `idle_right`
- Phase 1 はプロトタイプ素材（AI生成 or 仮矩形）。配布前に差し替え前提

#### 留意点
- スプライトは正面向き（ドラクエ風）→ 斜め見下ろしマップ上では `y_sort_enabled` での Zオーダー制御が必要（Phase 1-3 と連携）
- `CharacterData.gd` のパスを変えるだけで素材差し替えができる設計にする

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
- `CELL_SIZE = 48` はタイルサイズと一致させる
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
