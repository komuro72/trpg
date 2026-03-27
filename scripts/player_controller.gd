class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Character ノードに差し替え可能なコントローラー設計

var character: Character = null
var map_data: MapData = null

## 移動先の占有チェック対象。get_occupied_tiles() で判定するため複数マスキャラにも対応
var blocking_characters: Array[Character] = []

# キー長押し時の移動間隔（秒）
const MOVE_INTERVAL_INITIAL: float = 0.20
const MOVE_INTERVAL_REPEAT: float = 0.10

var _move_timer: float = 0.0
var _holding: bool = false


func _process(delta: float) -> void:
	if character == null:
		return

	# 攻撃（スペースキー）：移動とは独立して処理
	if Input.is_action_just_pressed("ui_accept"):
		_attack()

	_move_timer -= delta

	var dir := _get_input_direction()

	if dir == Vector2i.ZERO:
		_holding = false
		_move_timer = 0.0
		return

	if not _holding:
		_try_move(dir)
		_holding = true
		_move_timer = MOVE_INTERVAL_INITIAL
	elif _move_timer <= 0.0:
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
	if _can_move_to(new_pos):
		character.move_to(new_pos)


## 向いている方向の隣接マスにいる敵を攻撃する
func _attack() -> void:
	var attack_pos := character.grid_pos + Character.dir_to_vec(character.facing)
	for blocker: Character in blocking_characters:
		if attack_pos in blocker.get_occupied_tiles():
			var multiplier := Character.get_direction_multiplier(character, blocker)
			blocker.take_damage(character.attack, multiplier)
			print("[Player] → %s  %.1fx  HP:%d/%d" % \
				[blocker.name, multiplier, blocker.hp, blocker.max_hp])
			return


## 移動可否を判定する（WALL・範囲外・キャラクター占有は不可）
func _can_move_to(pos: Vector2i) -> bool:
	if map_data != null:
		if not map_data.is_walkable(pos):
			return false
	else:
		# map_data未設定時のフォールバック（境界チェックのみ）
		if not (pos.x >= 0 and pos.x < MapData.MAP_WIDTH \
				and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT):
			return false

	for blocker: Character in blocking_characters:
		if pos in blocker.get_occupied_tiles():
			return false

	return true
