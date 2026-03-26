class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Character ノードに差し替え可能なコントローラー設計

var character: Character = null
var map_size: Vector2i = Vector2i(20, 15)

# キー長押し時の移動間隔（秒）
const MOVE_INTERVAL_INITIAL: float = 0.20
const MOVE_INTERVAL_REPEAT: float = 0.10

var _move_timer: float = 0.0
var _holding: bool = false


func _process(delta: float) -> void:
	if character == null:
		return

	_move_timer -= delta

	var dir := _get_input_direction()

	if dir == Vector2i.ZERO:
		_holding = false
		_move_timer = 0.0
		return

	if not _holding:
		# 最初のキー入力：即座に移動
		_try_move(dir)
		_holding = true
		_move_timer = MOVE_INTERVAL_INITIAL
	elif _move_timer <= 0.0:
		# 長押し：一定間隔で移動
		_try_move(dir)
		_move_timer = MOVE_INTERVAL_REPEAT


func _get_input_direction() -> Vector2i:
	if Input.is_action_pressed("ui_right"):
		return Vector2i(1, 0)
	elif Input.is_action_pressed("ui_left"):
		return Vector2i(-1, 0)
	elif Input.is_action_pressed("ui_down"):
		return Vector2i(0, 1)
	elif Input.is_action_pressed("ui_up"):
		return Vector2i(0, -1)
	return Vector2i.ZERO


func _try_move(dir: Vector2i) -> void:
	var new_pos := character.grid_pos + dir
	if _is_within_map(new_pos):
		character.move_to(new_pos)


func _is_within_map(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < map_size.x and pos.y >= 0 and pos.y < map_size.y
