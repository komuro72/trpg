class_name MessageWindow
extends CanvasLayer

## メッセージウィンドウ：フィールド画面下部に固定サイズで常時表示
## 5行分の高さを確保し、新しいメッセージが追加されたら自動スクロール
## MessageLog（Autoload）の共有バッファを表示する
## 会話モード：選択肢をインラインで表示し、プレイヤーの入力を受け付ける

const VISIBLE_LINES: int = 5

## 会話の選択肢が確定したとき発火する
signal choice_confirmed(choice_id: String)
## 会話がキャンセル（Esc / X / 左キー）されたとき発火する
signal dialogue_dismissed()

## 会話モードの状態
var _dialogue_active: bool = false
var _dialogue_choices: Array[Dictionary] = []  ## [{ "id": String, "label": String }]
var _dialogue_cursor: int = 0
var _reject_timer: float = 0.0
var _reject_active: bool = false

var _control: Control
var _font: Font


func _ready() -> void:
	layer = 12
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)

	if MessageLog != null:
		MessageLog.entry_added.connect(_on_entry_changed)


## 後方互換: 既存の show_message() 呼び出しをシステムメッセージとして転送する
func show_message(msg: String) -> void:
	if MessageLog != null:
		MessageLog.add_system(msg)


## 後方互換: OrderWindow のログ行が参照する log_entries
var log_entries: Array[String]:
	get:
		var result: Array[String] = []
		if MessageLog != null:
			for e: Dictionary in MessageLog.get_visible_entries():
				result.append(e.get("text", "") as String)
		return result


# --------------------------------------------------------------------------
# 会話モード
# --------------------------------------------------------------------------

## 選択肢を表示して会話モードに入る
## choices: [{ "id": "join_us", "label": "「仲間になってほしい」" }, ...]
func start_dialogue(choices: Array[Dictionary]) -> void:
	_dialogue_choices = choices
	_dialogue_cursor  = 0
	_dialogue_active  = true
	_reject_active    = false
	if _control != null:
		_control.queue_redraw()


## 拒否メッセージを表示する（一定時間後に自動で消える）
func show_rejected(msg: String = "断られた...") -> void:
	show_message(msg)
	_reject_active = true
	_reject_timer  = 1.5
	_dialogue_active = false
	_dialogue_choices.clear()


## 会話モードを終了する
func end_dialogue() -> void:
	_dialogue_active = false
	_dialogue_choices.clear()
	_reject_active = false
	if _control != null:
		_control.queue_redraw()


## 会話モード中かどうか
func is_dialogue_active() -> bool:
	return _dialogue_active


func _process(delta: float) -> void:
	if _reject_active:
		_reject_timer -= delta
		if _reject_timer <= 0.0:
			_reject_active = false
			dialogue_dismissed.emit()
		return

	if not _dialogue_active:
		return

	# 会話モードの入力処理
	if Input.is_action_just_pressed("ui_up"):
		_dialogue_cursor = (_dialogue_cursor - 1 + _dialogue_choices.size()) % _dialogue_choices.size()
		_control.queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		_dialogue_cursor = (_dialogue_cursor + 1) % _dialogue_choices.size()
		_control.queue_redraw()
	elif Input.is_action_just_pressed("attack") \
			or Input.is_action_just_pressed("ui_accept"):
		# 決定は Z / A のみ（左右キーは移動と競合するため無効）
		if _dialogue_cursor < _dialogue_choices.size():
			var cid: String = _dialogue_choices[_dialogue_cursor].get("id", "") as String
			choice_confirmed.emit(cid)
	elif Input.is_action_just_pressed("menu_back"):
		# キャンセルは X / B のみ（左右キーは移動と競合するため無効）
		end_dialogue()
		dialogue_dismissed.emit()


func _on_entry_changed() -> void:
	if _control != null:
		_control.queue_redraw()


func _on_draw() -> void:
	if _font == null or MessageLog == null:
		return

	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var vw      := _control.size.x
	var vh      := _control.size.y
	var field_w := float(vw - 2 * pw)

	var fs := clampi(int(float(gs) * 0.16), 10, 16)
	var line_h := float(fs) * 1.5

	# 会話モード中は選択肢分の行を追加
	var choice_lines := _dialogue_choices.size() if _dialogue_active else 0
	var total_lines := VISIBLE_LINES + choice_lines
	if _dialogue_active and choice_lines > 0:
		total_lines += 1  # ヒント行

	var box_w := field_w - 16.0
	var box_h := line_h * float(total_lines) + 12.0
	var bx := float(pw) + 8.0
	var by := float(vh) - box_h - 6.0

	# 半透明背景（会話中は少し濃く）
	var bg_alpha := 0.82 if _dialogue_active else 0.65
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.04, 0.04, 0.08, bg_alpha))

	# 会話中は枠線を追加
	if _dialogue_active:
		_control.draw_rect(
			Rect2(bx, by, box_w, box_h),
			Color(0.50, 0.50, 0.72, 0.70), false, 1)

	# ── ログメッセージ（上部） ──
	var visible: Array[Dictionary] = MessageLog.get_visible_entries()
	var start_idx := maxi(0, visible.size() - VISIBLE_LINES)
	var text_x := bx + 8.0
	var text_y := by + 6.0 + float(fs)

	for i: int in range(start_idx, visible.size()):
		var entry := visible[i]
		var col: Color = entry.get("color", Color.WHITE) as Color
		_control.draw_string(_font,
			Vector2(text_x, text_y),
			entry.get("text", "") as String,
			HORIZONTAL_ALIGNMENT_LEFT, box_w - 16.0, fs, col)
		text_y += line_h

	# ── 選択肢（下部） ──
	if _dialogue_active and not _dialogue_choices.is_empty():
		# セパレーター
		var sep_y := by + 6.0 + line_h * float(VISIBLE_LINES) + 2.0
		_control.draw_line(
			Vector2(bx + 8.0, sep_y),
			Vector2(bx + box_w - 8.0, sep_y),
			Color(0.40, 0.40, 0.60, 0.60), 1)

		var choice_y := sep_y + 4.0 + float(fs)
		for i: int in range(_dialogue_choices.size()):
			var choice := _dialogue_choices[i]
			var label: String = choice.get("label", "") as String
			var is_sel := (i == _dialogue_cursor)
			if is_sel:
				_control.draw_rect(
					Rect2(bx + 6.0, choice_y - float(fs) + 2.0, box_w - 12.0, line_h),
					Color(0.22, 0.32, 0.62, 0.75))
			var arrow := "▶ " if is_sel else "   "
			var tx_col := Color.WHITE if is_sel else Color(0.70, 0.70, 0.82)
			_control.draw_string(_font,
				Vector2(text_x, choice_y),
				arrow + label,
				HORIZONTAL_ALIGNMENT_LEFT, box_w - 24.0, fs, tx_col)
			choice_y += line_h

		# 操作ヒント
		var hint_fs := maxi(9, fs - 2)
		_control.draw_string(_font,
			Vector2(text_x, choice_y + 2.0),
			"↑↓:選択  Z:決定  X:閉じる",
			HORIZONTAL_ALIGNMENT_LEFT, box_w - 24.0, hint_fs,
			Color(0.45, 0.45, 0.55))
