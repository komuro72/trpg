# 詳細仕様書

## Phase 1: 主人公1人の移動・画像表示

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
  game_map.tscn     メインシーン（GameMapノード）
scripts/
  game_map.gd       グリッド描画・シーン管理
  character.gd      キャラクター基底クラス（Phase1は四角形で仮表示）
  player_controller.gd  プレイヤー入力処理
  party.gd          パーティー管理（将来の複数パーティー対応）
```

### アーキテクチャメモ
- `Character` と `PlayerController / AIController` は分離設計
  - 操作切替時はコントローラーを差し替えるだけで対応できる
- `Party` クラスは最初から用意し、`active_character` で操作対象を管理
- `Character.move_to()` が向きを自動更新する（将来のアニメーション対応）

---

## Phase 2以降（未実装）
- HP・攻撃・当たり判定
- 仲間AI・操作切替
- 指示システム
- ステージ・UI・バランス調整
