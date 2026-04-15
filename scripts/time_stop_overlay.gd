class_name TimeStopOverlay
extends CanvasLayer

## 時間停止中にゲーム画面を暗くするオーバーレイ
## layer=5: ゲーム画面(0)より手前、UIパネル(10+)より奥
## 切替時は FADE_DURATION 秒でアルファをフェードさせる

const DIM_ALPHA := 0.35
const FADE_DURATION := 0.1

var _rect: ColorRect
var _tween: Tween
var _target_dim: bool = false


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0.05, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	add_child(_rect)


func _process(_delta: float) -> void:
	var dim: bool = not GlobalConstants.world_time_running
	if dim == _target_dim:
		return
	_target_dim = dim
	var target_alpha: float = DIM_ALPHA if dim else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", target_alpha, FADE_DURATION)
