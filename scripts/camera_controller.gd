class_name CameraController
extends Node

## カメラコントローラー
## デッドゾーン方式でキャラクターを追従。
## Phase 9-1: 滑らかスクロールを実装。
##   - デッドゾーン判定をキャラクターの視覚位置（character.position）に対して行う
##   - _cam_target（デッドゾーン境界で更新するピクセル目標座標）と
##     _cam_pos（_cam_target に向かって指数減衰 lerp する実座標）の2段構成
##   - Camera2D.limit_* によるマップ端制限はそのまま維持

## デッドゾーン比率（画面サイズに対する割合）
## X はパネル分だけ視野が狭くなるため早めにスクロールさせる
const DEAD_ZONE_RATIO_X: float = 0.20
const DEAD_ZONE_RATIO_Y: float = 0.40

## 追従速度の指数減衰係数（大きいほど速く追いつく）
## 10.0 → キャラ移動 0.3s 中に約 95% 追従
const FOLLOW_SPEED: float = 10.0

var character: Character = null
var camera: Camera2D = null

## カメラが向かうべきピクセル座標（デッドゾーン判定で更新）
var _cam_target: Vector2
## 現在のカメラ位置（_cam_target に向かって補間中）
var _cam_pos: Vector2


func _ready() -> void:
	if character == null or camera == null:
		return
	var init_pos := _char_world_pos()
	_cam_target  = init_pos
	_cam_pos     = init_pos
	_apply()


func _process(delta: float) -> void:
	if character == null or camera == null:
		return

	# キャラクターの視覚位置（補間済み）でデッドゾーン判定し、_cam_target を更新
	_update_target(_char_world_pos())

	# 指数減衰 lerp でカメラを滑らかに追従
	_cam_pos = _cam_pos.lerp(_cam_target, 1.0 - exp(-FOLLOW_SPEED * delta))
	_apply()


## キャラクターの視覚位置を受けてデッドゾーン判定を行い _cam_target を更新する
func _update_target(char_pos: Vector2) -> void:
	var dz   := _dead_zone_half_px()
	var diff := char_pos - _cam_target

	if diff.x > dz.x:
		_cam_target.x = char_pos.x - dz.x
	elif diff.x < -dz.x:
		_cam_target.x = char_pos.x + dz.x

	if diff.y > dz.y:
		_cam_target.y = char_pos.y - dz.y
	elif diff.y < -dz.y:
		_cam_target.y = char_pos.y + dz.y


## デッドゾーンの半径をピクセル単位で返す
## X方向はサイドパネル分を除いたフィールド幅を基準にする
func _dead_zone_half_px() -> Vector2:
	var vp_size  := get_viewport().get_visible_rect().size
	var gs       := float(GlobalConstants.GRID_SIZE)
	var panel_px := float(GlobalConstants.PANEL_TILES * GlobalConstants.GRID_SIZE)
	var field_w  := vp_size.x - 2.0 * panel_px
	return Vector2(
		maxf(gs, field_w  * DEAD_ZONE_RATIO_X * 0.5),
		maxf(gs, vp_size.y * DEAD_ZONE_RATIO_Y * 0.5)
	)


## 追従対象を切り替え、カメラを即座に新しいキャラクターの位置にスナップする
func set_follow_target(new_character: Character) -> void:
	character = new_character
	if new_character != null and is_instance_valid(new_character):
		var pos    := _char_world_pos()
		_cam_target = pos
		_cam_pos    = pos
		_apply()


## 追従対象キャラクターのワールド座標を返す（position = 視覚補間済みの座標）
func _char_world_pos() -> Vector2:
	if character == null or not is_instance_valid(character):
		return _cam_pos
	return character.position


## カメラ座標を Camera2D に反映する
## Camera2D.limit_* がマップ端制限を担うため、ここでは直接セットするだけ
func _apply() -> void:
	camera.global_position = _cam_pos
