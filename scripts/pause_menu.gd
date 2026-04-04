## PauseMenu
## ポーズメニュー：オプション・タイトルへ戻る・ゲームに戻る
## Phase 13: タイトル・セーブ・メニューシステム

extends Node

const _SPEED_OPTS := [0.5, 1.0, 1.5, 2.0]

enum _State {
	MAIN,
	OPTIONS,
	RETURN_CONFIRM,
}

signal closed()

var _state:    _State = _State.MAIN
var _cursor:   int    = 0
var _opt_cursor:    int   = 0
var _opt_volume:    float = 1.0
var _opt_speed_idx: int   = 1

var _control:  Control = null
var _font:     Font    = null
var _visible:  bool    = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font

	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)

	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	_control.visible = false
	canvas.add_child(_control)
	_control.draw.connect(_on_draw)


func _process(_delta: float) -> void:
	if _visible:
		_control.queue_redraw()


func _input(event: InputEvent) -> void:
	# START ボタンはメニューの開閉をトグル（PROCESS_MODE_ALWAYS なので常に受け取る）
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed and jb.button_index == JOY_BUTTON_START:
			if _visible:
				close()
			else:
				open()
			return

	if not _visible:
		return

	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		match ke.physical_keycode:
			KEY_UP:    _nav(-1)
			KEY_DOWN:  _nav(1)
			KEY_LEFT:  _on_left()
			KEY_RIGHT: _on_right()
			KEY_Z:     _on_confirm()
			KEY_X, KEY_ESCAPE: _on_back()
	elif event is InputEventJoypadButton:
		var jb2 := event as InputEventJoypadButton
		if not jb2.pressed:
			return
		match jb2.button_index:
			JOY_BUTTON_DPAD_UP:    _nav(-1)
			JOY_BUTTON_DPAD_DOWN:  _nav(1)
			JOY_BUTTON_DPAD_LEFT:  _on_left()
			JOY_BUTTON_DPAD_RIGHT: _on_right()
			JOY_BUTTON_A:          _on_confirm()
			JOY_BUTTON_B:          _on_back()
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_Y:
			if jm.axis_value < -0.5:
				_nav(-1)
			elif jm.axis_value > 0.5:
				_nav(1)


# --------------------------------------------------------------------------
# 公開インターフェース
# --------------------------------------------------------------------------

func is_open() -> bool:
	return _visible


func open() -> void:
	if _visible:
		return
	_visible = true
	_control.visible = true
	_state  = _State.MAIN
	_cursor = 0
	_opt_cursor = 0
	_opt_volume    = _read_bus_volume()
	_opt_speed_idx = _speed_index_of(GlobalConstants.game_speed)
	get_tree().paused = true


func close() -> void:
	if not _visible:
		return
	_visible = false
	_control.visible = false
	get_tree().paused = false
	emit_signal("closed")


# --------------------------------------------------------------------------
# ナビゲーション
# --------------------------------------------------------------------------

func _nav(dir: int) -> void:
	match _state:
		_State.MAIN:
			_cursor = wrapi(_cursor + dir, 0, 3)
		_State.OPTIONS:
			_opt_cursor = wrapi(_opt_cursor + dir, 0, _opt_item_count())
		_State.RETURN_CONFIRM:
			_cursor = wrapi(_cursor + dir, 0, 2)


func _on_left() -> void:
	if _state == _State.OPTIONS:
		_opt_change(-1)


func _on_right() -> void:
	if _state == _State.OPTIONS:
		_opt_change(1)


func _on_confirm() -> void:
	match _state:
		_State.MAIN:       _main_confirm()
		_State.OPTIONS:    _opt_confirm()
		_State.RETURN_CONFIRM: _return_confirm()


func _on_back() -> void:
	match _state:
		_State.MAIN:
			close()
		_State.OPTIONS:
			_apply_options()
			_state  = _State.MAIN
			_cursor = 0
		_State.RETURN_CONFIRM:
			_state  = _State.MAIN
			_cursor = 0


# --------------------------------------------------------------------------
# 状態ごとの確定処理
# --------------------------------------------------------------------------

func _main_confirm() -> void:
	match _cursor:
		0:  # オプション
			_opt_volume    = _read_bus_volume()
			_opt_speed_idx = _speed_index_of(GlobalConstants.game_speed)
			_state      = _State.OPTIONS
			_opt_cursor = 0
		1:  # タイトルへ戻る
			_state  = _State.RETURN_CONFIRM
			_cursor = 1  # デフォルトは「いいえ」
		2:  # ゲームに戻る
			close()


func _opt_confirm() -> void:
	if _opt_cursor == _opt_item_count() - 1:  # ← 戻る
		_apply_options()
		_state  = _State.MAIN
		_cursor = 0


func _return_confirm() -> void:
	if _cursor == 0:  # はい
		_apply_options()
		SaveManager.flush_playtime()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
	else:            # いいえ
		_state  = _State.MAIN
		_cursor = 0


func _apply_options() -> void:
	SoundManager.set_volume(_opt_volume)
	GlobalConstants.game_speed = _SPEED_OPTS[_opt_speed_idx]


# --------------------------------------------------------------------------
# オプション操作
# --------------------------------------------------------------------------

func _opt_item_count() -> int:
	return 3  ## 音量・ゲーム速度・← 戻る


func _opt_items() -> Array[String]:
	var items: Array[String] = []
	items.append("音量:  %d%%" % int(_opt_volume * 100.0))
	items.append("ゲーム速度:  %sx" % str(_SPEED_OPTS[_opt_speed_idx]))
	items.append("← 戻る")
	return items


func _opt_change(dir: int) -> void:
	match _opt_cursor:
		0:  # 音量
			_opt_volume = clampf(_opt_volume + dir * 0.1, 0.0, 1.0)
			SoundManager.set_volume(_opt_volume)
		1:  # ゲーム速度
			_opt_speed_idx = wrapi(_opt_speed_idx + dir, 0, _SPEED_OPTS.size())


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------

func _on_draw() -> void:
	if _font == null or _control == null or not _visible:
		return
	var vp := _control.size

	# 暗幕
	_control.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.65))

	# パネル
	var pw := 480.0
	var ph := 320.0
	var px := (vp.x - pw) * 0.5
	var py := (vp.y - ph) * 0.5
	_control.draw_rect(Rect2(px, py, pw, ph), Color(0.08, 0.08, 0.14, 0.95))
	_control.draw_rect(Rect2(px, py, pw, ph), Color(0.30, 0.30, 0.50, 0.80), false, 2.0)

	# タイトル
	_control.draw_string(_font,
		Vector2(0.0, py + 42.0), "ポーズ",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 28, Color(0.85, 0.85, 0.95))

	match _state:
		_State.MAIN:            _draw_main(vp, px, py, pw, ph)
		_State.OPTIONS:         _draw_options(vp, px, py, pw, ph)
		_State.RETURN_CONFIRM:  _draw_return_confirm(vp, px, py, pw, ph)


func _draw_main(vp: Vector2, px: float, py: float, pw: float, _ph: float) -> void:
	var items := ["オプション", "タイトルへ戻る", "ゲームに戻る"]
	var item_h := 52.0
	var start_y := py + 90.0
	for i: int in items.size():
		var y := start_y + i * item_h
		_draw_panel_item(vp, px, pw, y, items[i], i == _cursor, item_h)


func _draw_options(vp: Vector2, px: float, py: float, pw: float, _ph: float) -> void:
	_control.draw_string(_font,
		Vector2(0.0, py + 80.0), "オプション",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color(0.75, 0.75, 0.85))
	var items := _opt_items()
	var item_h := 48.0
	var start_y := py + 108.0
	for i: int in items.size():
		var y := start_y + i * item_h
		_draw_panel_item(vp, px, pw, y, items[i], i == _opt_cursor, item_h)
	if _opt_cursor <= 1:
		_control.draw_string(_font,
			Vector2(0.0, py + 108.0 + items.size() * item_h + 10.0),
			"← → で変更",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, Color(0.55, 0.55, 0.65))


func _draw_return_confirm(vp: Vector2, _px: float, py: float, _pw: float, _ph: float) -> void:
	_control.draw_string(_font,
		Vector2(0.0, py + 120.0),
		"タイトル画面へ戻りますか？",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, Color.WHITE)
	_control.draw_string(_font,
		Vector2(0.0, py + 152.0),
		"（プレイ時間が保存されます）",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 16, Color(0.65, 0.65, 0.75))
	var items := ["はい", "いいえ"]
	var item_h := 52.0
	var start_y := py + 180.0
	for i: int in items.size():
		var y := start_y + i * item_h
		_draw_panel_item(vp, 0.0, vp.x, y, items[i], i == _cursor, item_h)


func _draw_panel_item(vp: Vector2, px: float, pw: float, y: float, label: String, selected: bool, height: float) -> void:
	if selected:
		_control.draw_rect(
			Rect2(px + pw * 0.15, y, pw * 0.70, height - 4.0),
			Color(0.20, 0.35, 0.55, 0.85), true, 1.0)
		_control.draw_string(_font,
			Vector2(0.0, y + height * 0.68), label,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, Color.WHITE)
	else:
		_control.draw_string(_font,
			Vector2(0.0, y + height * 0.68), label,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color(0.70, 0.70, 0.80))


# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

func _read_bus_volume() -> float:
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	return db_to_linear(db)


func _speed_index_of(spd: float) -> int:
	for i: int in _SPEED_OPTS.size():
		if absf(_SPEED_OPTS[i] - spd) < 0.01:
			return i
	return 1
