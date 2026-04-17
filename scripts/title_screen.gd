## TitleScreen
## タイトル画面：背景＋ロゴ＋「Press any button / key」
## Phase 13: タイトル・セーブ・メニューシステム

extends Node

var _control:       Control   = null
var _font:          Font      = null
var _tex_bg:        Texture2D = null
var _blink_timer:   float     = 0.0
var _show_prompt:   bool      = true
var _transitioning: bool      = false
var _config_editor: CanvasLayer = null  ## F4 ConfigEditor


func _ready() -> void:
	GlobalConstants.initialize(get_viewport().get_visible_rect().size)

	# 背景画像（なければグラデーションフォールバック）
	var bg_path := "res://assets/images/ui/title_bg.png"
	if ResourceLoader.exists(bg_path):
		_tex_bg = load(bg_path) as Texture2D

	_font = ThemeDB.fallback_font

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	canvas.add_child(_control)
	_control.draw.connect(_on_draw)


func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= 0.55:
		_blink_timer  = 0.0
		_show_prompt  = not _show_prompt
	_control.queue_redraw()


func _input(event: InputEvent) -> void:
	if _transitioning:
		return
	# F4: ConfigEditor トグル（他の「any key → main menu」遷移より優先・捕捉）
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_F4:
			_toggle_config_editor()
			get_viewport().set_input_as_handled()
			return
		# ConfigEditor 表示中は any-key 遷移を抑止
		if _config_editor != null and _config_editor.visible:
			return
	var pressed := false
	if event is InputEventKey:
		var ke2 := event as InputEventKey
		pressed = ke2.pressed and not ke2.echo
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	if pressed:
		_transitioning = true
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## F4 ConfigEditor トグル（初回のみ生成）
func _toggle_config_editor() -> void:
	if _config_editor == null:
		var packed: PackedScene = load("res://scenes/config_editor.tscn") as PackedScene
		if packed == null:
			return
		_config_editor = packed.instantiate() as CanvasLayer
		add_child(_config_editor)
	if _config_editor.has_method("toggle"):
		_config_editor.call("toggle")


func _on_draw() -> void:
	if _font == null or _control == null:
		return
	var vp := _control.size

	# ─── 背景 ───────────────────────────────────────────────────
	if _tex_bg != null:
		# 幅に合わせて均等スケール。画像が縦長なら下部をクロップ（伸長しない）
		var tw := float(_tex_bg.get_width())
		var th := float(_tex_bg.get_height())
		if tw > 0.0 and th > 0.0:
			# ソース矩形：幅フル・高さは画面アスペクト分のみ（上から）
			var src_h := tw * vp.y / vp.x
			src_h = minf(src_h, th)  # 画像高さを超えないようにクランプ
			var src_rect := Rect2(0.0, 0.0, tw, src_h)
			_control.draw_texture_rect_region(_tex_bg, Rect2(Vector2.ZERO, vp), src_rect)
	else:
		# 暗いグラデーション風（2段重ね）
		_control.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.04, 0.10))
		_control.draw_rect(Rect2(0.0, vp.y * 0.55, vp.x, vp.y * 0.45),
			Color(0.02, 0.02, 0.07, 0.80))

	# ─── プロンプト（点滅） ─────────────────────────────────────
	if _show_prompt:
		_control.draw_string(_font,
			Vector2(0.0, vp.y * 0.88),
			"Press any button / key",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 26,
			Color(0.90, 0.90, 0.90, 0.90))
