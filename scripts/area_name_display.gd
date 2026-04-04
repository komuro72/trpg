class_name AreaNameDisplay
extends CanvasLayer

## エリア名表示：現在いるエリアの名前をフィールド上部中央に常時表示
## 上行：「第N階層」（常時表示）
## 下行：部屋名（名前ありエリアのみ）

var _control: Control
var _font: Font
var _name:        String = ""   ## 現在の部屋名（空文字=部屋名なし）
var _floor_index: int    = 0    ## 現在のフロアインデックス（0始まり）


func _ready() -> void:
	layer = 11
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)


## エリア名を設定して再描画。空文字を渡すと部屋名行を非表示にする（階層行は残る）
func show_area_name(area_name: String) -> void:
	_name = area_name
	if _control != null:
		_control.queue_redraw()


## 現在フロアインデックスを設定して再描画
func set_floor(floor_index: int) -> void:
	_floor_index = floor_index
	if _control != null:
		_control.queue_redraw()


func _on_draw() -> void:
	if _font == null:
		return

	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var vw      := _control.size.x
	var field_w := float(vw - 2 * pw)
	var cx      := float(pw) + field_w * 0.5

	var floor_font_size := maxi(12, int(float(gs) * 0.18))
	var room_font_size  := maxi(14, int(float(gs) * 0.22))

	var floor_label := "第%d階層" % (_floor_index + 1)
	var floor_tw    := _font.get_string_size(floor_label, HORIZONTAL_ALIGNMENT_LEFT, -1, floor_font_size).x

	var has_room := not _name.is_empty()
	var room_tw  := 0.0
	if has_room:
		room_tw = _font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, room_font_size).x

	# ボックスサイズ
	var pad_x   := 36.0
	var pad_top := 6.0
	var pad_bot := 6.0
	var line_gap := 4.0
	var box_w := maxf(floor_tw, room_tw) + pad_x

	var floor_line_h := float(floor_font_size) + line_gap
	var room_line_h  := float(room_font_size)  + line_gap if has_room else 0.0
	var box_h := pad_top + floor_line_h + room_line_h + pad_bot

	var bx := cx - box_w * 0.5
	var by := float(gs) * 0.35

	# 背景
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.04, 0.04, 0.08, 0.88))
	# 枠線（ゴールド調）
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.65, 0.55, 0.30, 0.80),
		false, 1)

	# 上行：「第N階層」（薄めのゴールド）
	var floor_y := by + pad_top + float(floor_font_size)
	_control.draw_string(_font,
		Vector2(cx - floor_tw * 0.5, floor_y),
		floor_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, floor_font_size,
		Color(1.0, 0.92, 0.65, 0.70))

	# 下行：部屋名（明るいゴールド）
	if has_room:
		var room_y := floor_y + line_gap + float(room_font_size)
		_control.draw_string(_font,
			Vector2(cx - room_tw * 0.5, room_y),
			_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, room_font_size,
			Color(1.0, 0.92, 0.65, 1.0))
