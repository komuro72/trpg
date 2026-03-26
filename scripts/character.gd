class_name Character
extends Node2D

## キャラクター基底クラス
## Phase 1-2: Sprite2D による4方向画像切替。素材がない場合はプレースホルダー表示。

## 向き定義（ドラクエ風：FRONT=手前, BACK=奥, LEFT=左, RIGHT=右）
enum Direction { FRONT, BACK, LEFT, RIGHT }

var grid_pos: Vector2i = Vector2i(0, 0)
var facing: Direction = Direction.FRONT
var character_data: CharacterData = null

## プレースホルダー色（素材がない場合に使用）
var placeholder_color: Color = Color(0.3, 0.7, 1.0)

var _sprite: Sprite2D
var _has_texture: bool = false


func _ready() -> void:
	z_index = 1  # タイル（z_index=0）より手前に表示
	_setup_sprite()
	sync_position()


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true

	# 表示スケール: GRID_SIZE / ソース横幅 → 縦方向も同率でGRID_SIZE*2になる
	var scale_factor := float(GlobalConstants.GRID_SIZE) / float(GlobalConstants.SPRITE_SOURCE_WIDTH)
	_sprite.scale = Vector2(scale_factor, scale_factor)

	add_child(_sprite)
	_apply_direction_texture()


## 現在の向きに対応するテクスチャを Sprite2D に設定する
func _apply_direction_texture() -> void:
	if character_data == null:
		_has_texture = false
		_sprite.visible = false
		queue_redraw()
		return

	var path := character_data.get_sprite_path(facing)
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
		_sprite.visible = true
		_has_texture = true
	else:
		_sprite.texture = null
		_sprite.visible = false
		_has_texture = false

	queue_redraw()


## 素材がない場合のプレースホルダー描画
func _draw() -> void:
	if _has_texture:
		return

	var gs := GlobalConstants.GRID_SIZE
	var half := gs * 0.5
	var margin := 6

	# キャラクター本体（四角形）
	draw_rect(
		Rect2(-half + margin, -half + margin, gs - margin * 2, gs - margin * 2),
		placeholder_color
	)

	# 向きインジケーター（白い小矩形）
	var offset := _get_indicator_offset()
	draw_rect(Rect2(offset.x - 5, offset.y - 5, 10, 10), Color.WHITE)


func _get_indicator_offset() -> Vector2:
	match facing:
		Direction.FRONT: return Vector2(0, 12)
		Direction.BACK:  return Vector2(0, -12)
		Direction.LEFT:  return Vector2(-12, 0)
		Direction.RIGHT: return Vector2(12, 0)
	return Vector2.ZERO


## グリッド座標をワールド座標に同期する
func sync_position() -> void:
	var gs := GlobalConstants.GRID_SIZE
	position = Vector2(
		grid_pos.x * gs + gs * 0.5,
		grid_pos.y * gs + gs * 0.5
	)


## グリッド移動（向きを更新してテクスチャを切り替える）
func move_to(new_grid_pos: Vector2i) -> void:
	var delta := new_grid_pos - grid_pos
	if delta.x > 0:
		facing = Direction.RIGHT
	elif delta.x < 0:
		facing = Direction.LEFT
	elif delta.y > 0:
		facing = Direction.FRONT
	elif delta.y < 0:
		facing = Direction.BACK

	grid_pos = new_grid_pos
	sync_position()
	_apply_direction_texture()
