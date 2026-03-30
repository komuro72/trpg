class_name CameraController
extends Node

## カメラコントローラー
## デッドゾーン方式でキャラクターを追従。移動はグリッド単位スナップ。
## なめらかスクロールは将来のアニメーション実装時に追加予定。

## デッドゾーン比率（画面サイズに対する割合）
const DEAD_ZONE_RATIO: float = 0.70

var character: Character = null
var camera: Camera2D = null

## カメラ中心のグリッド座標
var _cam_grid: Vector2i
var _last_char_grid: Vector2i = Vector2i(-9999, -9999)


func _ready() -> void:
	if character == null or camera == null:
		return
	_cam_grid = character.grid_pos
	_apply()


func _process(_delta: float) -> void:
	if character == null or camera == null:
		return
	# キャラクターが移動したときだけ更新
	if character.grid_pos != _last_char_grid:
		_last_char_grid = character.grid_pos
		_update(character.grid_pos)


## キャラクターの新しいグリッド座標を受けてカメラ位置を更新する
func _update(char_grid: Vector2i) -> void:
	var dz := _dead_zone_half_cells()
	var diff := char_grid - _cam_grid

	# デッドゾーンを超えた分だけグリッド単位でカメラをスナップ
	if diff.x > dz.x:
		_cam_grid.x = char_grid.x - dz.x
	elif diff.x < -dz.x:
		_cam_grid.x = char_grid.x + dz.x

	if diff.y > dz.y:
		_cam_grid.y = char_grid.y - dz.y
	elif diff.y < -dz.y:
		_cam_grid.y = char_grid.y + dz.y

	_apply()


## デッドゾーンの半径をグリッドセル数で返す
## X方向はサイドパネル分を除いたフィールド幅を基準にする
func _dead_zone_half_cells() -> Vector2i:
	var vp_size  := get_viewport().get_visible_rect().size
	var gs       := float(GlobalConstants.GRID_SIZE)
	var panel_px := float(GlobalConstants.PANEL_TILES * GlobalConstants.GRID_SIZE)
	var field_w  := vp_size.x - 2.0 * panel_px
	return Vector2i(
		maxi(1, int(field_w * DEAD_ZONE_RATIO / 2.0 / gs)),
		maxi(1, int(vp_size.y * DEAD_ZONE_RATIO / 2.0 / gs))
	)


## 追従対象を切り替え、カメラ位置を即座に新しいキャラクターに合わせる
func set_follow_target(new_character: Character) -> void:
	character = new_character
	if new_character != null and is_instance_valid(new_character):
		_cam_grid = new_character.grid_pos
		_apply()
	_last_char_grid = Vector2i(-9999, -9999)  # 次フレームで強制更新


## カメラ座標を Camera2D に反映する
## Camera2D.limit_* がマップ端制限を担うため、ここでは直接セットするだけ
func _apply() -> void:
	var gs := float(GlobalConstants.GRID_SIZE)
	camera.global_position = Vector2(
		_cam_grid.x * gs + gs * 0.5,
		_cam_grid.y * gs + gs * 0.5
	)
