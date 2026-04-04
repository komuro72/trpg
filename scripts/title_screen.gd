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
	var pressed := false
	if event is InputEventKey:
		var ke := event as InputEventKey
		pressed = ke.pressed and not ke.echo
	elif event is InputEventJoypadButton:
		pressed = (event as InputEventJoypadButton).pressed
	if pressed:
		_transitioning = true
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_draw() -> void:
	if _font == null or _control == null:
		return
	var vp := _control.size

	# ─── 背景 ───────────────────────────────────────────────────
	if _tex_bg != null:
		_control.draw_texture_rect(_tex_bg, Rect2(Vector2.ZERO, vp), false)
	else:
		# 暗いグラデーション風（2段重ね）
		_control.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.04, 0.10))
		_control.draw_rect(Rect2(0.0, vp.y * 0.55, vp.x, vp.y * 0.45),
			Color(0.02, 0.02, 0.07, 0.80))

	# ─── タイトルロゴ ────────────────────────────────────────────
	var title_font_size := 80
	var title := "Rally the Parties"
	# 影
	_control.draw_string(_font,
		Vector2(2.0, vp.y * 0.38 + 2.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, title_font_size,
		Color(0.0, 0.0, 0.0, 0.6))
	# 本体（ゴールド系）
	_control.draw_string(_font,
		Vector2(0.0, vp.y * 0.38), title,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, title_font_size,
		Color(1.0, 0.88, 0.55))

	# ─── サブタイトル ─────────────────────────────────────────────
	_control.draw_string(_font,
		Vector2(0.0, vp.y * 0.38 + 64.0),
		"リアルタイムタクティクスRPG",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22,
		Color(0.75, 0.75, 0.85, 0.80))

	# ─── プロンプト（点滅） ─────────────────────────────────────
	if _show_prompt:
		_control.draw_string(_font,
			Vector2(0.0, vp.y * 0.72),
			"Press any button / key",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 26,
			Color(0.90, 0.90, 0.90, 0.90))
