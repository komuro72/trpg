class_name MessageWindow
extends CanvasLayer

## メッセージウィンドウ：画面下中央（フィールドエリア内）にポップアップ表示
## Phase 5: 3秒表示後に0.5秒かけてフェードアウト

const DISPLAY_DURATION: float = 3.0
const FADE_DURATION:    float = 0.5
const LOG_MAX:          int   = 50

var _control: Control
var _font: Font
var _message: String = ""
var _timer:   float  = 0.0
var _alpha:   float  = 0.0

## 直近50件のメッセージログ（OrderWindow ログ表示に使用）
var log_entries: Array[String] = []


func _ready() -> void:
	layer = 12
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)


func show_message(msg: String) -> void:
	_message = msg
	_timer   = DISPLAY_DURATION
	_alpha   = 1.0
	log_entries.append(msg)
	if log_entries.size() > LOG_MAX:
		log_entries = log_entries.slice(log_entries.size() - LOG_MAX)
	if _control != null:
		_control.queue_redraw()


func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_alpha = 0.0
	elif _timer <= FADE_DURATION:
		_alpha = _timer / FADE_DURATION
	else:
		_alpha = 1.0
	if _control != null:
		_control.queue_redraw()


func _on_draw() -> void:
	if _alpha <= 0.01 or _message.is_empty() or _font == null:
		return

	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var vw      := _control.size.x
	var vh      := _control.size.y
	var field_w := float(vw - 2 * pw)
	var box_w   := minf(field_w * 0.78, 480.0)
	var box_h   := 44.0
	var bx      := float(pw) + (field_w - box_w) * 0.5
	var by      := float(vh) - box_h - float(gs) * 0.4

	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.06, 0.06, 0.10, 0.88 * _alpha))
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.50, 0.50, 0.60, 0.55 * _alpha),
		false, 1)
	_control.draw_string(_font,
		Vector2(bx + 14.0, by + box_h * 0.65),
		_message,
		HORIZONTAL_ALIGNMENT_LEFT, box_w - 28.0, 15,
		Color(1.0, 1.0, 1.0, _alpha))
