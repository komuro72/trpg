## グローバル定数（Autoload: GlobalConstants）
## グリッドサイズ・UIレイアウト定数を管理する

extends Node

## 縦方向のタイル数（固定・GRID_SIZE計算の基準）
## 1920x1080 基準で GRID_SIZE ≈ 96px になるよう設定（1080 / 11 ≈ 98px）
const TILES_VERTICAL: int = 11

## 左右パネルの幅（タイル数単位）
const PANEL_TILES: int = 3

## グリッド1マスのピクセルサイズ（起動時に動的計算 / デフォルト64）
var GRID_SIZE: int = 64

## スプライト素材のソース解像度（差し替え時もここを変えるだけでスケールが追従する）
const SPRITE_SOURCE_WIDTH: int = 512
const SPRITE_SOURCE_HEIGHT: int = 1024


## 画面サイズからGRID_SIZEを計算する
## 縦方向タイル数を固定してGRID_SIZEを決定（最小32px）
func initialize(viewport_size: Vector2) -> void:
	GRID_SIZE = maxi(32, int(viewport_size.y / float(TILES_VERTICAL)))
