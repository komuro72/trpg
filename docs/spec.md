# 詳細仕様書

## Phase 1: 主人公1人の移動・画像表示 ✅ 完了

### グリッド定数
| 定数 | 値 | 説明 |
|------|-----|------|
| CELL_SIZE | 48px | 1グリッドセルのピクセルサイズ |
| MAP_WIDTH | 20 | マップ横幅（セル数） |
| MAP_HEIGHT | 15 | マップ縦幅（セル数） |

### 操作
| 入力 | 動作 |
|------|------|
| 矢印キー（↑↓←→） | 主人公を1マス移動 |
| 長押し | 一定間隔で連続移動（初回200ms、リピート100ms） |

### ファイル構成
```
scenes/
  game_map.tscn          メインシーン（GameMapノード）
scripts/
  game_map.gd            グリッド描画・シーン管理
  character.gd           キャラクター基底クラス（Phase1は四角形で仮表示）
  player_controller.gd   プレイヤー入力処理
  party.gd               パーティー管理（将来の複数パーティー対応）
docs/
  spec.md                本ファイル
```

### アーキテクチャメモ
- `Character` と `PlayerController / AIController` は分離設計
  - 操作切替時はコントローラーを差し替えるだけで対応できる
- `Party` クラスは最初から用意し、`active_character` で操作対象を管理
- `Character.move_to()` が向きを自動更新する（将来のアニメーション対応）
- キャラクターの向きは `Direction` enum（DOWN / UP / LEFT / RIGHT）で管理

### Git / GitHub
- リポジトリ: https://github.com/komuro72/trpg
- ブランチ: master
- `.godot/` フォルダはGitignore済み
- `.uid` ファイルはコミット対象（Godot 4のリソース解決に必要）

---

## Phase 2: 戦闘基盤（未実装）
- HP・攻撃・当たり判定
- ダメージ計算
- 敵キャラクター（仮）

## Phase 3: 仲間AI・操作切替（未実装）
- AIController の実装
- プレイヤー操作キャラクターの切替

## Phase 4: 指示システム（未実装）
- 攻撃 / 防衛 / 待機 / 追従 / 撤退

## Phase 5: ステージ・UI・バランス調整（未実装）

## Phase 6: Steam配布準備（未実装）
