## ConfigEditor （開発用定数エディタ）
## F4 で表示・非表示トグル。ゲーム中に開いた場合は world_time_running を停止する。
##
## 使い方：シーン（game_map / title_screen）で ConfigEditor.tscn を instance 化して
##         add_child する。F4 入力検出は各シーン側で行い、toggle() を呼ぶ。
##         表示中は本クラスが _unhandled_input で F4/ESC を受け取り閉じる。
##
## タブ構成：
##   constants_default.json の `category` フィールドで振り分ける。
##   TABS 配列に定義されていないカテゴリを持つ定数は「Unknown」タブに集める。
##   新タブを追加したい場合は TABS 配列の末尾に追加するだけで済む（UI は自動構築）。
##   タブ名の末尾に " ●" が付くと、そのタブ内にデフォルト値と異なる定数が1個以上ある印。
##
## 将来：定数が100個規模になったらタブ内をさらにサブグループ化する検討あり。
##       現状は各タブ直下にフラットに定数を列挙する。

extends CanvasLayer

const HIGHLIGHT_BG_COLOR: Color = Color(1.0, 1.0, 0.8)
const PANEL_BG_COLOR:     Color = Color(0.10, 0.10, 0.14, 0.98)
const TITLE_TEXT:         String = "Config Editor (開発用)"

## カテゴリタブの順序（依存順：上位概念 → 下位概念）
## 定数がないタブもプレースホルダーとして表示する
const TABS: Array[String] = [
	"Character",
	"UnitAI",
	"PartyLeader",
	"NpcLeaderAI",
	"Healer",
	"PlayerController",
	"EnemyLeaderAI",
]
## TABS に含まれないカテゴリの定数を集める予備タブ
const UNKNOWN_TAB: String = "Unknown"

var _root_panel:    PanelContainer = null
var _tab_container: TabContainer   = null
var _status_lbl:    Label          = null
## 各タブ名 → そのタブ内の VBox（ここに行を add）
var _tab_rows: Dictionary = {}
## 各タブ名 → プレースホルダーラベル（空タブ用。定数があれば hide）
var _tab_placeholders: Dictionary = {}
## 各タブ名 → TabContainer 上のインデックス（set_tab_title 用）
var _tab_indices: Dictionary = {}
## 行ごとのウィジェット参照
## row_widgets[key] = {"panel", "style", "editor", "default_display", "type", "tab"}
var _row_widgets: Dictionary = {}

## F4 押下中のゲーム時間停止復帰用（開く前の値を記憶）
var _prev_world_time_running: bool = true

## ゲーム中に開かれたか（タイトル画面では false）
var _opened_in_game: bool = false


func _ready() -> void:
	visible = false  # デフォルト非表示
	_build_ui()
	_refresh_all()


## F4 などから呼ぶトグル関数
func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	_opened_in_game = GlobalConstants.world_time_running
	_prev_world_time_running = GlobalConstants.world_time_running
	GlobalConstants.world_time_running = false
	visible = true
	_refresh_all()
	_set_status("", Color.WHITE)


func close() -> void:
	visible = false
	if _opened_in_game:
		GlobalConstants.world_time_running = _prev_world_time_running
	_opened_in_game = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			# Ctrl+Tab / Ctrl+PageDown → 次タブ、Ctrl+Shift+Tab / Ctrl+PageUp → 前タブ
			if ke.ctrl_pressed and _tab_container != null and _tab_container.get_tab_count() > 0:
				if ke.keycode == KEY_TAB:
					var dir := -1 if ke.shift_pressed else 1
					_cycle_tab(dir)
					get_viewport().set_input_as_handled()
					return
				if ke.keycode == KEY_PAGEDOWN:
					_cycle_tab(1)
					get_viewport().set_input_as_handled()
					return
				if ke.keycode == KEY_PAGEUP:
					_cycle_tab(-1)
					get_viewport().set_input_as_handled()
					return
			if ke.keycode == KEY_F4 or ke.keycode == KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()


func _cycle_tab(dir: int) -> void:
	if _tab_container == null:
		return
	var n := _tab_container.get_tab_count()
	if n <= 0:
		return
	_tab_container.current_tab = (_tab_container.current_tab + dir + n) % n


# ============================================================================
# UI 構築
# ============================================================================

func _build_ui() -> void:
	# 画面中央のパネル（幅60% × 高さ70%）
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_w: float = vp_size.x * 0.60
	var panel_h: float = vp_size.y * 0.70
	var panel_x: float = (vp_size.x - panel_w) * 0.5
	var panel_y: float = (vp_size.y - panel_h) * 0.5

	_root_panel = PanelContainer.new()
	_root_panel.position = Vector2(panel_x, panel_y)
	_root_panel.size = Vector2(panel_w, panel_h)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = PANEL_BG_COLOR
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.35, 0.40, 0.55)
	_root_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)

	# タイトル
	var title := Label.new()
	title.text = TITLE_TEXT
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	outer.add_child(title)

	# ステータスメッセージ行
	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 12)
	outer.add_child(_status_lbl)

	# ヘッダー行（タブより上に共通表示）
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	outer.add_child(hdr)
	_add_hdr_label(hdr, "定数名", 260)
	_add_hdr_label(hdr, "説明", 380)
	_add_hdr_label(hdr, "編集", 200)
	_add_hdr_label(hdr, "デフォルト", 120)

	# タブコンテナ
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_tab_container)

	# 宣言順にタブを生成（定数ゼロでも空タブを表示）
	for tab_name: String in TABS:
		_build_tab(tab_name)
	# 未知カテゴリ用の Unknown タブを常に末尾に（未分類定数が出たらここに集まる）
	_build_tab(UNKNOWN_TAB)

	# 各定数行を所属タブに追加
	for key: String in GlobalConstants.CONFIG_KEYS:
		_build_row(key)

	# 初期状態のタブ名（● インジケータ）を一度更新
	_update_tab_indicators()

	# 下部ボタン
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 12)
	outer.add_child(btn_box)

	var btn_save := Button.new()
	btn_save.text = "保存"
	btn_save.custom_minimum_size = Vector2(120, 36)
	btn_save.pressed.connect(_on_save_pressed)
	btn_box.add_child(btn_save)

	var btn_reset := Button.new()
	btn_reset.text = "すべてデフォルトに戻す"
	btn_reset.custom_minimum_size = Vector2(200, 36)
	btn_reset.pressed.connect(_on_reset_pressed)
	btn_box.add_child(btn_reset)

	var btn_commit := Button.new()
	btn_commit.text = "現在値をすべてデフォルト化"
	btn_commit.custom_minimum_size = Vector2(220, 36)
	btn_commit.pressed.connect(_on_commit_pressed)
	btn_box.add_child(btn_commit)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box.add_child(spacer)

	var btn_close := Button.new()
	btn_close.text = "閉じる (F4)"
	btn_close.custom_minimum_size = Vector2(120, 36)
	btn_close.pressed.connect(close)
	btn_box.add_child(btn_close)


func _add_hdr_label(parent: HBoxContainer, text: String, width: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	parent.add_child(lbl)


## タブ名に対応する VBox を生成して TabContainer に追加する
## 空タブの時のプレースホルダーも同時に配置（後で定数が入れば自動で hide）
func _build_tab(tab_name: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.name = tab_name
	_tab_container.add_child(scroll)
	var tab_idx := _tab_container.get_tab_count() - 1
	_tab_container.set_tab_title(tab_idx, tab_name)
	_tab_indices[tab_name] = tab_idx

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	_tab_rows[tab_name] = vbox

	var placeholder := Label.new()
	placeholder.text = "このカテゴリには定数がまだ登録されていません。"
	placeholder.add_theme_font_size_override("font_size", 12)
	placeholder.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(placeholder)
	_tab_placeholders[tab_name] = placeholder


func _build_row(key: String) -> void:
	var meta := GlobalConstants._get_meta_for(key)
	var type_name: String = meta.get("type", "float") as String
	var desc: String = meta.get("description", "") as String
	var category: String = meta.get("category", "") as String

	# 所属タブを決定。TABS にない or 空文字は Unknown タブに振る
	var target_tab: String = UNKNOWN_TAB
	if TABS.has(category):
		target_tab = category
	elif not category.is_empty():
		push_warning("[ConfigEditor] 未知のカテゴリ '%s' を Unknown タブに振り分け (key=%s)" % [category, key])
	else:
		push_warning("[ConfigEditor] category 未定義の定数を Unknown タブに振り分け (key=%s)" % key)

	var target_vbox := _tab_rows.get(target_tab) as VBoxContainer
	if target_vbox == null:
		push_warning("[ConfigEditor] タブ '%s' の VBox が見つかりません。行生成をスキップ (key=%s)" % [target_tab, key])
		return

	# このタブに定数が入るのでプレースホルダーは隠す
	if _tab_placeholders.has(target_tab):
		(_tab_placeholders[target_tab] as Label).visible = false

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color.TRANSPARENT
	row_style.content_margin_left   = 6
	row_style.content_margin_right  = 6
	row_style.content_margin_top    = 4
	row_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", row_style)
	target_vbox.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	# 定数名（等幅）
	var name_lbl := Label.new()
	name_lbl.text = key
	name_lbl.custom_minimum_size = Vector2(260, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	# 説明
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.custom_minimum_size = Vector2(380, 0)
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc_lbl)

	# 編集ウィジェット
	var editor: Control = null
	match type_name:
		"float", "int":
			editor = _make_numeric_editor(key, meta, type_name == "int")
		"color":
			editor = _make_color_editor(key)
		_:
			editor = Label.new()
			(editor as Label).text = "(未対応の型: %s)" % type_name
	editor.custom_minimum_size = Vector2(200, 0)
	row.add_child(editor)

	# デフォルト値表示
	var default_display: Control = null
	if type_name == "color":
		default_display = _make_color_swatch(GlobalConstants.get_default_value(key))
	else:
		default_display = Label.new()
		(default_display as Label).custom_minimum_size = Vector2(120, 0)
		(default_display as Label).add_theme_font_size_override("font_size", 12)
	row.add_child(default_display)

	_row_widgets[key] = {
		"panel": panel,
		"style": row_style,
		"editor": editor,
		"default_display": default_display,
		"type": type_name,
		"tab": target_tab,
	}


func _make_numeric_editor(key: String, meta: Dictionary, is_int: bool) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = float(meta.get("min", 0.0))
	sb.max_value = float(meta.get("max", 100.0))
	sb.step      = float(meta.get("step", 1.0 if is_int else 0.01))
	sb.rounded   = is_int
	sb.value     = float(GlobalConstants.get(key))
	sb.value_changed.connect(_on_numeric_changed.bind(key, is_int))
	return sb


func _make_color_editor(key: String) -> ColorPickerButton:
	var btn := ColorPickerButton.new()
	btn.color = GlobalConstants.get(key) as Color
	btn.edit_alpha = false
	btn.color_changed.connect(_on_color_changed.bind(key))
	return btn


func _make_color_swatch(value: Variant) -> ColorRect:
	var cr := ColorRect.new()
	cr.custom_minimum_size = Vector2(120, 22)
	cr.color = _to_color(value)
	return cr


func _to_color(v: Variant) -> Color:
	if v is Color:
		return v as Color
	if v is Array:
		var a := v as Array
		var r: float = float(a[0]) if a.size() >= 1 else 0.0
		var g: float = float(a[1]) if a.size() >= 2 else 0.0
		var b: float = float(a[2]) if a.size() >= 3 else 0.0
		var al: float = float(a[3]) if a.size() >= 4 else 1.0
		return Color(r, g, b, al)
	return Color.MAGENTA  # fallback


# ============================================================================
# 値の更新ハンドラ
# ============================================================================

func _on_numeric_changed(value: float, key: String, is_int: bool) -> void:
	if is_int:
		GlobalConstants.set(key, int(value))
	else:
		GlobalConstants.set(key, value)
	_update_row_highlight(key)


func _on_color_changed(color: Color, key: String) -> void:
	GlobalConstants.set(key, color)
	_update_row_highlight(key)


# ============================================================================
# ボタン
# ============================================================================

func _on_save_pressed() -> void:
	var ok := GlobalConstants.save_constants()
	if ok:
		_set_status("保存しました: %s" % GlobalConstants.CONFIG_USER_PATH, Color(0.55, 1.0, 0.55))
	else:
		_set_status(GlobalConstants.last_config_error, Color(1.0, 0.5, 0.5))


func _on_reset_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "すべての定数をデフォルト値に戻します。よろしいですか？\n（UI 上の値のみ変更・保存は別途「保存」ボタンで）"
	dlg.title = "デフォルトに戻す"
	add_child(dlg)
	dlg.confirmed.connect(_on_reset_confirmed.bind(dlg))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_reset_confirmed(dlg: ConfirmationDialog) -> void:
	GlobalConstants.reset_to_defaults()
	_refresh_all()
	if GlobalConstants.last_config_error.is_empty():
		_set_status("デフォルト値に戻しました（未保存）", Color(0.55, 1.0, 0.55))
	else:
		_set_status(GlobalConstants.last_config_error, Color(1.0, 0.5, 0.5))
	dlg.queue_free()


func _on_commit_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "現在値を constants_default.json の value として書き換えます。\nこれは復帰不能な上書きです。よろしいですか？"
	dlg.title = "現在値をデフォルト化"
	add_child(dlg)
	dlg.confirmed.connect(_on_commit_confirmed.bind(dlg))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_commit_confirmed(dlg: ConfirmationDialog) -> void:
	var ok := GlobalConstants.commit_as_defaults()
	if ok:
		_refresh_all()  # デフォルト列の再描画
		_set_status("現在値を constants_default.json に書き込みました", Color(0.55, 1.0, 0.55))
	else:
		_set_status(GlobalConstants.last_config_error, Color(1.0, 0.5, 0.5))
	dlg.queue_free()


# ============================================================================
# 行ごとの表示更新
# ============================================================================

func _refresh_all() -> void:
	for key: String in GlobalConstants.CONFIG_KEYS:
		if not _row_widgets.has(key):
			continue
		var w := _row_widgets[key] as Dictionary
		var editor := w.get("editor") as Control
		# 編集ウィジェットに現在値を反映
		if editor is SpinBox:
			(editor as SpinBox).value = float(GlobalConstants.get(key))
		elif editor is ColorPickerButton:
			(editor as ColorPickerButton).color = GlobalConstants.get(key) as Color
		# デフォルト値ラベル
		var default_val: Variant = GlobalConstants.get_default_value(key)
		var disp := w.get("default_display") as Control
		if disp is Label:
			(disp as Label).text = _format_default(default_val)
		elif disp is ColorRect:
			(disp as ColorRect).color = _to_color(default_val)
		# 背景色（現在値 ≠ デフォルトなら薄黄）
		_update_row_highlight(key)
	# 全行更新の後にタブインジケータも再計算
	_update_tab_indicators()


func _update_row_highlight(key: String) -> void:
	if not _row_widgets.has(key):
		return
	var w := _row_widgets[key] as Dictionary
	var style := w.get("style") as StyleBoxFlat
	var cur: Variant = GlobalConstants.get_config_value(key)
	var dflt: Variant = GlobalConstants.get_default_value(key)
	if _values_equal(cur, dflt):
		style.bg_color = Color.TRANSPARENT
	else:
		style.bg_color = HIGHLIGHT_BG_COLOR
	# この行を含むタブの ● インジケータを再計算
	var tab_name := w.get("tab", UNKNOWN_TAB) as String
	_update_tab_title(tab_name)


## タブ名に定数が変更されている印（●）を付けるか外すか判定
func _update_tab_title(tab_name: String) -> void:
	if not _tab_indices.has(tab_name):
		return
	var idx := int(_tab_indices[tab_name])
	var has_change := false
	for k: String in GlobalConstants.CONFIG_KEYS:
		if not _row_widgets.has(k):
			continue
		var w := _row_widgets[k] as Dictionary
		if (w.get("tab", "") as String) != tab_name:
			continue
		var cur: Variant = GlobalConstants.get_config_value(k)
		var dflt: Variant = GlobalConstants.get_default_value(k)
		if not _values_equal(cur, dflt):
			has_change = true
			break
	var title: String = tab_name + " ●" if has_change else tab_name
	_tab_container.set_tab_title(idx, title)


## 全タブのインジケータを一括更新（_refresh_all から呼ぶ）
func _update_tab_indicators() -> void:
	for tab_name: String in _tab_indices.keys():
		_update_tab_title(tab_name as String)


func _values_equal(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if a is Array and b is Array:
		var aa := a as Array
		var bb := b as Array
		if aa.size() != bb.size():
			return false
		for i in range(aa.size()):
			if not is_equal_approx(float(aa[i]), float(bb[i])):
				return false
		return true
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _format_default(v: Variant) -> String:
	if v == null:
		return "—"
	if v is Array:
		var a := v as Array
		var parts: Array[String] = []
		for x: Variant in a:
			parts.append(_format_number(float(x)))
		return "[" + ", ".join(parts) + "]"
	if v is float:
		return _format_number(float(v))
	if v is int:
		return str(int(v))
	return String(str(v))


## GDScript の printf は %g 未対応のため、%.4f に丸めてから末尾ゼロを削る
## 整数扱いの float は "3" 形式、小数は "0.35" 形式で返す
func _format_number(f: float) -> String:
	if is_equal_approx(f, float(int(f))):
		return "%d" % int(f)
	var s := "%.4f" % f
	if s.contains("."):
		s = s.rstrip("0")
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


func _set_status(msg: String, color: Color) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override("font_color", color)
