class_name Character
extends Node2D

## キャラクター基底クラス
## Phase 1: 仮の四角形で表示。後でスプライトに差し替え予定。

const CELL_SIZE: int = 48

var grid_pos: Vector2i = Vector2i(0, 0)
var char_color: Color = Color.CYAN

# 向き定義（将来のスプライト方向に対応）
enum Direction { DOWN, UP, LEFT, RIGHT }
var facing: Direction = Direction.DOWN


func _ready() -> void:
	sync_position()


func _draw() -> void:
	var half := CELL_SIZE * 0.5
	var margin := 6

	# キャラクター本体（四角形）
	draw_rect(
		Rect2(-half + margin, -half + margin, CELL_SIZE - margin * 2, CELL_SIZE - margin * 2),
		char_color
	)

	# 向きインジケーター（白い小矩形）
	var indicator_offset := _get_indicator_offset()
	draw_rect(Rect2(indicator_offset.x - 5, indicator_offset.y - 5, 10, 10), Color.WHITE)


func _get_indicator_offset() -> Vector2:
	match facing:
		Direction.DOWN:
			return Vector2(0, 12)
		Direction.UP:
			return Vector2(0, -12)
		Direction.LEFT:
			return Vector2(-12, 0)
		Direction.RIGHT:
			return Vector2(12, 0)
	return Vector2.ZERO


## グリッド座標を実座標に同期する
func sync_position() -> void:
	position = Vector2(
		grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5,
		grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5
	)


## グリッド移動（方向を向きにも反映）
func move_to(new_grid_pos: Vector2i) -> void:
	var delta := new_grid_pos - grid_pos
	if delta.x > 0:
		facing = Direction.RIGHT
	elif delta.x < 0:
		facing = Direction.LEFT
	elif delta.y > 0:
		facing = Direction.DOWN
	elif delta.y < 0:
		facing = Direction.UP

	grid_pos = new_grid_pos
	sync_position()
	queue_redraw()
