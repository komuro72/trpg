class_name AreaNameDisplay
extends CanvasLayer

## エリア名表示：現在いるエリアの名前をフィールド上部中央に常時表示
## 名前なしエリア（空文字）では非表示にする

var _control: Control
var _font: Font
var _name: String = ""


func _ready() -> void:
	layer = 11
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)


## エリア名を設定して表示する。空文字を渡すと非表示になる
func show_area_name(area_name: String) -> void:
	_name = area_name
	if _control != null:
		_control.queue_redraw()


func _on_draw() -> void:
	if _name.is_empty() or _font == null:
		return

	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var vw      := _control.size.x
	var field_w := float(vw - 2 * pw)
	var cx      := float(pw) + field_w * 0.5

	var font_size := maxi(14, int(float(gs) * 0.22))
	var text_w    := _font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var box_w     := text_w + 36.0
	var box_h     := float(font_size) * 1.9
	var bx        := cx - box_w * 0.5
	var by        := float(gs) * 0.35

	# 背景
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.04, 0.04, 0.08, 0.88))
	# 枠線（ゴールド調）
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.65, 0.55, 0.30, 0.80),
		false, 1)
	# テキスト（ゴールド調）
	_control.draw_string(_font,
		Vector2(cx - text_w * 0.5, by + box_h * 0.68),
		_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(1.0, 0.92, 0.65, 1.0))
