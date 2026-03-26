## グローバル定数（Autoload: GlobalConstants）
## グリッドサイズ・スプライト解像度など、プロジェクト全体で共有する定数を管理する

extends Node

## グリッド1マスのピクセルサイズ
const GRID_SIZE: int = 64

## スプライト素材のソース解像度（差し替え時もここを変えるだけでスケールが追従する）
const SPRITE_SOURCE_WIDTH: int = 512
const SPRITE_SOURCE_HEIGHT: int = 1024
