## MainMenu
## メインメニュー：続きから始める・新しく始める・オプション
## Phase 13: タイトル・セーブ・メニューシステム

extends Node

# --------------------------------------------------------------------------
# 定数
# --------------------------------------------------------------------------
const SLOT_COUNT  := 3
const _SPEED_OPTS := [0.5, 1.0, 1.5, 2.0]  ## ゲーム速度の選択肢

enum _State {
	MAIN,
	SLOT_SELECT_NEW,
	OVERWRITE_CONFIRM,
	NAME_INPUT,
	SLOT_SELECT_CONT,
	OPTIONS,
}

# --------------------------------------------------------------------------
# 内部状態
# --------------------------------------------------------------------------
var _state:       _State = _State.MAIN
var _cursor:      int    = 0
var _sel_slot:    int    = 0   ## 選択中のスロット番号（1-3）
var _is_continue: bool   = false

## 名前入力フィールド
var _name_male_edit:   LineEdit = null
var _name_female_edit: LineEdit = null
var _name_focus:       int = 0  ## 0=男性名, 1=女性名, 2=決定ボタン

## 作成中のセーブデータ（NAME_INPUT 時に組み立て）
var _pending_save: SaveData = null

## オプション
var _opt_cursor:    int   = 0
var _opt_volume:    float = 0.5
var _opt_speed_idx: int   = 1   ## 1 = 1.0x

# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------
var _control: Control = null
var _font:    Font    = null
var _tex_bg:  Texture2D = null

# メインメニュー項目（動的に組み立て）
var _main_items: Array[String] = []


func _ready() -> void:
	GlobalConstants.initialize(get_viewport().get_visible_rect().size)

	_font = ThemeDB.fallback_font

	# 背景画像（タイトル画面と共通）
	var bg_path := "res://assets/images/ui/title_bg.png"
	if ResourceLoader.exists(bg_path):
		_tex_bg = load(bg_path) as Texture2D

	# デフォルト値を適用してから現在値に同期
	# （設定の永続化なし・起動のたびにデフォルト値で開始）
	SoundManager.set_volume(_opt_volume)
	GlobalConstants.game_speed = _SPEED_OPTS[_opt_speed_idx]
	_opt_volume    = _read_bus_volume()
	_opt_speed_idx = _speed_index_of(GlobalConstants.game_speed)

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	canvas.add_child(_control)
	_control.draw.connect(_on_draw)

	_rebuild_main_items()
	_cursor = 0


func _process(_delta: float) -> void:
	_control.queue_redraw()


func _input(event: InputEvent) -> void:
	# LineEdit がフォーカス中はキーボード操作をそちらに任せる
	if _state == _State.NAME_INPUT and _name_focus < 2:
		_handle_name_input_passthrough(event)
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
			KEY_X:     _on_back()
			KEY_ESCAPE: _on_back()
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
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
# ナビゲーション
# --------------------------------------------------------------------------

func _nav(dir: int) -> void:
	match _state:
		_State.MAIN:
			_cursor = wrapi(_cursor + dir, 0, _main_items.size())
		_State.SLOT_SELECT_NEW, _State.SLOT_SELECT_CONT:
			_cursor = wrapi(_cursor + dir, 0, SLOT_COUNT)
		_State.OVERWRITE_CONFIRM:
			_cursor = wrapi(_cursor + dir, 0, 2)
		_State.NAME_INPUT:
			_name_focus = wrapi(_name_focus + dir, 0, 3)
			_sync_name_focus()
		_State.OPTIONS:
			_opt_cursor = wrapi(_opt_cursor + dir, 0, _opt_item_count())


func _on_left() -> void:
	if _state == _State.OPTIONS:
		_opt_change(-1)


func _on_right() -> void:
	if _state == _State.OPTIONS:
		_opt_change(1)


func _on_confirm() -> void:
	match _state:
		_State.MAIN:           _main_confirm()
		_State.SLOT_SELECT_NEW:  _new_slot_confirm()
		_State.SLOT_SELECT_CONT: _cont_slot_confirm()
		_State.OVERWRITE_CONFIRM: _overwrite_confirm()
		_State.NAME_INPUT:     _name_input_confirm()
		_State.OPTIONS:        _opt_confirm()


func _on_back() -> void:
	match _state:
		_State.MAIN:
			pass  # タイトルへ戻る
		_State.SLOT_SELECT_NEW, _State.SLOT_SELECT_CONT, _State.OPTIONS:
			_set_state(_State.MAIN)
		_State.OVERWRITE_CONFIRM:
			_set_state(_State.SLOT_SELECT_NEW)
		_State.NAME_INPUT:
			if _name_focus < 2:
				_blur_name_fields()
				_name_focus = 2  # 決定ボタンにフォーカスを戻す
			else:
				_destroy_name_fields()
				_set_state(_State.SLOT_SELECT_NEW)


# --------------------------------------------------------------------------
# 状態遷移
# --------------------------------------------------------------------------

func _set_state(s: _State) -> void:
	_state  = s
	_cursor = 0
	_opt_cursor = 0


func _rebuild_main_items() -> void:
	_main_items.clear()
	if SaveManager.has_any_save():
		_main_items.append("続きから始める")
	_main_items.append("新しく始める")
	_main_items.append("オプション")


func _main_confirm() -> void:
	var item := _main_items[_cursor]
	match item:
		"続きから始める":
			_is_continue = true
			_set_state(_State.SLOT_SELECT_CONT)
		"新しく始める":
			_is_continue = false
			_set_state(_State.SLOT_SELECT_NEW)
		"オプション":
			_opt_volume    = _read_bus_volume()
			_opt_speed_idx = _speed_index_of(GlobalConstants.game_speed)
			_set_state(_State.OPTIONS)


func _new_slot_confirm() -> void:
	_sel_slot = _cursor + 1
	var sd := SaveManager.get_save_data(_sel_slot)
	if sd.exists:
		_set_state(_State.OVERWRITE_CONFIRM)
	else:
		_pending_save = SaveData.new()
		_pending_save.slot_index = _sel_slot
		_create_name_fields()
		_set_state(_State.NAME_INPUT)


func _cont_slot_confirm() -> void:
	_sel_slot = _cursor + 1
	var sd := SaveManager.get_save_data(_sel_slot)
	if not sd.exists:
		return  # 空スロットは無効
	SaveManager.start_session(_sel_slot, sd)
	_start_game()


func _overwrite_confirm() -> void:
	if _cursor == 0:  # はい
		_pending_save = SaveData.new()
		_pending_save.slot_index = _sel_slot
		_create_name_fields()
		_set_state(_State.NAME_INPUT)
	else:             # いいえ
		_set_state(_State.SLOT_SELECT_NEW)


func _name_input_confirm() -> void:
	if _name_focus < 2:
		# LineEdit フォーカス → 決定ボタンへ移動
		_blur_name_fields()
		_name_focus = 2
		return
	# 決定
	_pending_save.hero_name_male   = _name_male_edit.text.strip_edges()
	_pending_save.hero_name_female = _name_female_edit.text.strip_edges()
	SaveManager.write_save(_sel_slot, _pending_save)
	SaveManager.start_session(_sel_slot, _pending_save)
	_destroy_name_fields()
	_start_game()


func _opt_confirm() -> void:
	var last := _opt_item_count() - 1
	var second_last := _opt_item_count() - 2
	if _opt_cursor == last:       # ← 戻る
		_apply_options()
		_set_state(_State.MAIN)
	elif _opt_cursor == second_last:  # ゲーム終了
		_apply_options()
		get_tree().quit()


func _apply_options() -> void:
	SoundManager.set_volume(_opt_volume)
	GlobalConstants.game_speed = _SPEED_OPTS[_opt_speed_idx]
	# 名前変更を反映（アクティブセーブがあれば）
	var save := SaveManager.get_active_save()
	if save != null:
		SaveManager.write_save(SaveManager._active_slot, save)


func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game_map.tscn")


# --------------------------------------------------------------------------
# オプション操作
# --------------------------------------------------------------------------

func _opt_item_count() -> int:
	return 6  ## 音量・速度・男性名・女性名・ゲーム終了・← 戻る

func _opt_items() -> Array[String]:
	var items: Array[String] = []
	items.append("音量:  %d%%" % int(_opt_volume * 100.0))
	items.append("ゲーム速度:  %sx" % str(_SPEED_OPTS[_opt_speed_idx]))
	var mname := _get_opt_hero_name_male()
	var fname := _get_opt_hero_name_female()
	items.append("男性名:  " + (mname if not mname.is_empty() else "（ランダム）"))
	items.append("女性名:  " + (fname if not fname.is_empty() else "（ランダム）"))
	items.append("ゲーム終了")
	items.append("← 戻る")
	return items


func _get_opt_hero_name_male() -> String:
	var save := SaveManager.get_active_save()
	if save != null:
		return save.hero_name_male
	return ""


func _get_opt_hero_name_female() -> String:
	var save := SaveManager.get_active_save()
	if save != null:
		return save.hero_name_female
	return ""


func _opt_change(dir: int) -> void:
	match _opt_cursor:
		0:  # 音量
			_opt_volume = clampf(_opt_volume + dir * 0.1, 0.0, 1.0)
			SoundManager.set_volume(_opt_volume)
		1:  # ゲーム速度
			_opt_speed_idx = wrapi(_opt_speed_idx + dir, 0, _SPEED_OPTS.size())


# --------------------------------------------------------------------------
# 名前入力フィールド
# --------------------------------------------------------------------------

func _create_name_fields() -> void:
	var vp := _control.size
	var cx := vp.x * 0.5
	var cy := vp.y * 0.5
	var fw := 320.0

	_name_male_edit = LineEdit.new()
	_name_male_edit.placeholder_text = "男性名（空白でランダム）"
	_name_male_edit.max_length = 12
	_name_male_edit.size = Vector2(fw, 40.0)
	_name_male_edit.position = Vector2(cx - fw * 0.5, cy - 50.0)
	_control.add_child(_name_male_edit)

	_name_female_edit = LineEdit.new()
	_name_female_edit.placeholder_text = "女性名（空白でランダム）"
	_name_female_edit.max_length = 12
	_name_female_edit.size = Vector2(fw, 40.0)
	_name_female_edit.position = Vector2(cx - fw * 0.5, cy + 40.0)
	_control.add_child(_name_female_edit)

	_name_focus = 0
	_sync_name_focus()


func _sync_name_focus() -> void:
	if _name_male_edit == null or _name_female_edit == null:
		return
	match _name_focus:
		0:
			_name_male_edit.grab_focus()
		1:
			_name_female_edit.grab_focus()
		2:
			_blur_name_fields()


func _blur_name_fields() -> void:
	if _name_male_edit != null:
		_name_male_edit.release_focus()
	if _name_female_edit != null:
		_name_female_edit.release_focus()


func _destroy_name_fields() -> void:
	if _name_male_edit != null:
		_name_male_edit.queue_free()
		_name_male_edit = null
	if _name_female_edit != null:
		_name_female_edit.queue_free()
		_name_female_edit = null


## LineEdit フォーカス中は方向キー以外を LineEdit に渡す（Enterで次フィールドへ）
## ゲームパッドも同様に処理する
func _handle_name_input_passthrough(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		match ke.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus + 1, 0, 3)
				_sync_name_focus()
			KEY_UP:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus - 1, 0, 3)
				_sync_name_focus()
			KEY_DOWN:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus + 1, 0, 3)
				_sync_name_focus()
			KEY_ESCAPE, KEY_X:
				_blur_name_fields()
				_name_focus = 2
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_A:  # 決定：次のフィールドへ（キーボードの Enter 相当）
				_blur_name_fields()
				_name_focus = wrapi(_name_focus + 1, 0, 3)
				_sync_name_focus()
			JOY_BUTTON_B:  # キャンセル：決定ボタンへ
				_blur_name_fields()
				_name_focus = 2
				_sync_name_focus()
			JOY_BUTTON_DPAD_UP:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus - 1, 0, 3)
				_sync_name_focus()
			JOY_BUTTON_DPAD_DOWN:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus + 1, 0, 3)
				_sync_name_focus()
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_Y:
			if jm.axis_value < -0.5:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus - 1, 0, 3)
				_sync_name_focus()
			elif jm.axis_value > 0.5:
				_blur_name_fields()
				_name_focus = wrapi(_name_focus + 1, 0, 3)
				_sync_name_focus()


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------

func _on_draw() -> void:
	if _font == null or _control == null:
		return
	var vp := _control.size

	# ─── 背景（タイトル画面と同じ幅フィット・下部クロップ）
	if _tex_bg != null:
		var tw := float(_tex_bg.get_width())
		var th := float(_tex_bg.get_height())
		if tw > 0.0 and th > 0.0:
			var src_h := minf(tw * vp.y / vp.x, th)
			_control.draw_texture_rect_region(
				_tex_bg, Rect2(Vector2.ZERO, vp),
				Rect2(0.0, 0.0, tw, src_h))
	else:
		_control.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.06, 0.10))

	# 半透明オーバーレイ（テキスト視認性確保）
	_control.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.55))

	match _state:
		_State.MAIN:              _draw_main(vp)
		_State.SLOT_SELECT_NEW:   _draw_slot_select(vp, false)
		_State.SLOT_SELECT_CONT:  _draw_slot_select(vp, true)
		_State.OVERWRITE_CONFIRM: _draw_overwrite_confirm(vp)
		_State.NAME_INPUT:        _draw_name_input(vp)
		_State.OPTIONS:           _draw_options(vp)


func _draw_main(vp: Vector2) -> void:
	var item_h := 52.0
	var total  := _main_items.size() * item_h
	var start_y := vp.y * 0.5 - total * 0.5

	for i: int in _main_items.size():
		var y := start_y + i * item_h
		var selected := (i == _cursor)
		_draw_menu_item(vp, y, _main_items[i], selected, item_h)


func _draw_slot_select(vp: Vector2, is_cont: bool) -> void:
	var label := "スロット選択（続きから）" if is_cont else "スロット選択（新しく）"
	_control.draw_string(_font,
		Vector2(0.0, vp.y * 0.28), label,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, Color(0.75, 0.75, 0.85))

	var slot_h := 70.0
	var start_y := vp.y * 0.40
	for i: int in SLOT_COUNT:
		var slot  := i + 1
		var sd    := SaveManager.get_save_data(slot)
		var y     := start_y + i * slot_h
		var sel   := (i == _cursor)
		var empty := (not sd.exists) or (is_cont and not sd.exists)

		var bg_col := Color(0.20, 0.35, 0.55, 0.85) if sel else Color(0.10, 0.10, 0.18, 0.80)
		_control.draw_rect(Rect2(vp.x * 0.25, y, vp.x * 0.50, slot_h - 6.0), bg_col, true, 1.0)

		var text_col := Color.WHITE if sel else Color(0.70, 0.70, 0.80)
		var line1: String
		var line2: String
		if sd.exists:
			line1 = "スロット %d  Floor %d  クリア %d回  %s" % [
				slot, sd.current_floor + 1, sd.clear_count,
				SaveData.format_playtime(sd.playtime)]
			var mn := sd.hero_name_male   if not sd.hero_name_male.is_empty()   else "（男性名未設定）"
			var fn := sd.hero_name_female if not sd.hero_name_female.is_empty() else "（女性名未設定）"
			line2 = "  %s / %s" % [mn, fn]
		else:
			line1 = "スロット %d  ── 空のスロット" % slot
			line2  = ""

		_control.draw_string(_font,
			Vector2(vp.x * 0.27, y + 22.0), line1,
			HORIZONTAL_ALIGNMENT_LEFT, vp.x * 0.46, 18, text_col)
		if not line2.is_empty():
			_control.draw_string(_font,
				Vector2(vp.x * 0.27, y + 48.0), line2,
				HORIZONTAL_ALIGNMENT_LEFT, vp.x * 0.46, 15,
				Color(0.65, 0.65, 0.75))


func _draw_overwrite_confirm(vp: Vector2) -> void:
	_control.draw_string(_font,
		Vector2(0.0, vp.y * 0.40),
		"スロット %d を上書きしますか？" % _sel_slot,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 24, Color.WHITE)
	var items := ["はい", "いいえ"]
	var item_h := 52.0
	var start_y := vp.y * 0.50
	for i: int in items.size():
		_draw_menu_item(vp, start_y + i * item_h, items[i], i == _cursor, item_h)


func _draw_name_input(vp: Vector2) -> void:
	# 固定ピクセルオフセットで配置（画面サイズに依存しないレイアウト）
	var cy  := vp.y * 0.5   # 画面中央Y
	var cx  := vp.x * 0.5
	var fw  := 320.0         # フィールド幅

	# タイトル
	_control.draw_string(_font,
		Vector2(0.0, cy - 130.0),
		"主人公の名前を入力してください",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, Color(0.80, 0.80, 0.90))

	# ── 男性名 ──────────────────────────────────────────
	_control.draw_string(_font,
		Vector2(cx - fw * 0.5, cy - 70.0),
		"男性名", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.70, 0.80, 1.00) if _name_focus == 0 else Color(0.60, 0.60, 0.70))
	# フォーカス枠
	if _name_focus == 0:
		_control.draw_rect(Rect2(cx - fw * 0.5 - 2, cy - 50.0 - 2, fw + 4, 44.0),
			Color(0.70, 0.80, 1.00, 0.60), false, 2.0)

	# ── 女性名 ──────────────────────────────────────────
	_control.draw_string(_font,
		Vector2(cx - fw * 0.5, cy + 20.0),
		"女性名", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(1.00, 0.75, 0.85) if _name_focus == 1 else Color(0.60, 0.60, 0.70))
	if _name_focus == 1:
		_control.draw_rect(Rect2(cx - fw * 0.5 - 2, cy + 40.0 - 2, fw + 4, 44.0),
			Color(1.00, 0.75, 0.85, 0.60), false, 2.0)

	# ── 決定ボタン ─────────────────────────────────────
	var btn_col := Color(0.30, 0.65, 0.30) if _name_focus == 2 else Color(0.18, 0.38, 0.18)
	_control.draw_rect(Rect2(cx - 80.0, cy + 110.0, 160.0, 40.0), btn_col)
	_control.draw_string(_font,
		Vector2(0.0, cy + 110.0 + 28.0), "決定",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, Color.WHITE)

	_control.draw_string(_font,
		Vector2(0.0, cy + 170.0),
		"↑↓ で移動　Enter/Z で確定　Esc/X で戻る",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 16, Color(0.55, 0.55, 0.65))


func _draw_options(vp: Vector2) -> void:
	_control.draw_string(_font,
		Vector2(0.0, vp.y * 0.24), "オプション",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 26, Color(0.80, 0.80, 0.90))

	var items := _opt_items()
	var item_h := 48.0
	var total  := items.size() * item_h
	var start_y := vp.y * 0.5 - total * 0.5
	for i: int in items.size():
		var y := start_y + i * item_h
		_draw_menu_item(vp, y, items[i], i == _opt_cursor, item_h)

	# 音量・速度は ←→ で変更できることを示すヒント
	if _opt_cursor <= 1:
		_control.draw_string(_font,
			Vector2(0.0, vp.y * 0.86),
			"← → で変更",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 16, Color(0.55, 0.55, 0.65))


func _draw_menu_item(vp: Vector2, y: float, label: String, selected: bool, height: float) -> void:
	if selected:
		_control.draw_rect(
			Rect2(vp.x * 0.30, y, vp.x * 0.40, height - 4.0),
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
