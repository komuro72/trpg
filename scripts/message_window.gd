class_name MessageWindow
extends CanvasLayer

## メッセージウィンドウ（Phase 14〜 刷新版）
## ・画面中央寄せ（左右15%余白）・高さ10行
## ・左右にバスト画像エリア（正方形・高さいっぱい）、中央にテキストエリア
## ・MessageLog.battle_message_added シグナルで左右画像とテキストを更新
## ・GlobalConstants.MESSAGE_WINDOW_SCROLL_MODE で表示方式を切り替え
##   false（リセット型）: 画像が切り替わったらテキストをリセット
##   true（スクロール型）: テキストは流れ続け、画像は随時更新

const VISIBLE_LINES: int = 10

## front.png のバスト領域クロップ（1024x1024 画像の上半分中央部分）
const BUST_SRC_X:  float = 256.0
const BUST_SRC_Y:  float = 0.0
const BUST_SRC_W:  float = 512.0
const BUST_SRC_H:  float = 512.0

## 会話の選択肢が確定したとき発火する（後方互換用・現在は NpcDialogueWindow が担当）
signal choice_confirmed(choice_id: String)
## 会話がキャンセルされたとき発火する（後方互換用）
signal dialogue_dismissed()

# --------------------------------------------------------------------------
# 会話モード（後方互換用スタブ。現在は NpcDialogueWindow が担当）
# --------------------------------------------------------------------------
var _dialogue_active:  bool = false
var _dialogue_choices: Array[Dictionary] = []
var _dialogue_cursor:  int = 0
var _reject_timer:     float = 0.0
var _reject_active:    bool = false

# --------------------------------------------------------------------------
# バスト画像管理
# --------------------------------------------------------------------------
## 左（攻撃・回復側）キャラクターデータと読み込んだテクスチャ
var _left_char_data:  CharacterData = null
var _right_char_data: CharacterData = null
var _left_tex:        Texture2D = null
var _right_tex:       Texture2D = null

## テクスチャキャッシュ（ファイルパス → Texture2D）
var _tex_cache: Dictionary = {}

## リセット型モード用：現在の対戦カーソルと蓄積バトルメッセージ
var _current_pair_key:  String = ""
var _battle_lines:      Array[Dictionary] = []  ## { text, color }

# --------------------------------------------------------------------------
# 描画用ノード
# --------------------------------------------------------------------------
var _control: Control
var _font:    Font


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
		MessageLog.battle_message_added.connect(_on_battle_message)


# --------------------------------------------------------------------------
# 後方互換 API
# --------------------------------------------------------------------------

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


## 後方互換: 会話モード開始（スタブ）
func start_dialogue(choices: Array[Dictionary]) -> void:
	_dialogue_choices = choices
	_dialogue_cursor  = 0
	_dialogue_active  = true
	_reject_active    = false
	if _control != null:
		_control.queue_redraw()


## 後方互換: 拒否メッセージ表示（スタブ）
func show_rejected(msg: String = "断られた...") -> void:
	show_message(msg)
	_reject_active = true
	_reject_timer  = 1.5
	_dialogue_active = false
	_dialogue_choices.clear()


## 後方互換: 会話モード終了（スタブ）
func end_dialogue() -> void:
	_dialogue_active = false
	_dialogue_choices.clear()
	_reject_active = false
	if _control != null:
		_control.queue_redraw()


## 後方互換: 会話モード中かどうか
func is_dialogue_active() -> bool:
	return _dialogue_active


# --------------------------------------------------------------------------
# シグナルハンドラ
# --------------------------------------------------------------------------

func _on_entry_changed() -> void:
	if _control != null:
		_control.queue_redraw()


## バトルメッセージが追加されたとき画像とテキストを更新する
func _on_battle_message(atk_data: CharacterData, def_data: CharacterData,
		message: String) -> void:
	# ── 画像更新
	_left_char_data  = atk_data
	_right_char_data = def_data
	_left_tex  = _load_bust_tex(atk_data)
	_right_tex = _load_bust_tex(def_data)

	var new_pair_key := _get_char_key(atk_data) + "|" + _get_char_key(def_data)

	if not GlobalConstants.MESSAGE_WINDOW_SCROLL_MODE:
		# リセット型: ペアが変わったらテキストをクリア
		if new_pair_key != _current_pair_key:
			_battle_lines.clear()
			_current_pair_key = new_pair_key
		# バトルラインに追加
		_battle_lines.append({"text": message, "color": Color(1.0, 0.60, 0.20)})
		if _battle_lines.size() > VISIBLE_LINES:
			_battle_lines = _battle_lines.slice(_battle_lines.size() - VISIBLE_LINES)
	else:
		# スクロール型: _current_pair_key だけ更新（テキストは MessageLog の流れに任せる）
		_current_pair_key = new_pair_key

	if _control != null:
		_control.queue_redraw()


# --------------------------------------------------------------------------
# ヘルパー：テクスチャ管理
# --------------------------------------------------------------------------

## CharacterData からバスト用テクスチャを返す（キャッシュあり）
## sprite_front → sprite_face の順で試みる。なければ null
func _load_bust_tex(data: CharacterData) -> Texture2D:
	if data == null:
		return null
	var path := data.sprite_front
	if path.is_empty() or not ResourceLoader.exists(path):
		path = data.sprite_face
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _tex_cache.has(path):
		return _tex_cache.get(path) as Texture2D
	var tex := load(path) as Texture2D
	if tex != null:
		_tex_cache[path] = tex
	return tex


## CharacterData からペアキー文字列を生成する（画像変更検出用）
static func _get_char_key(data: CharacterData) -> String:
	if data == null:
		return ""
	return data.sprite_front + "|" + data.character_id


# --------------------------------------------------------------------------
# _process（会話モード入力・リジェクトタイマー）
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _reject_active:
		_reject_timer -= delta
		if _reject_timer <= 0.0:
			_reject_active = false
			dialogue_dismissed.emit()
		return

	if not _dialogue_active:
		return

	if Input.is_action_just_pressed("ui_up"):
		_dialogue_cursor = (_dialogue_cursor - 1 + _dialogue_choices.size()) % _dialogue_choices.size()
		_control.queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		_dialogue_cursor = (_dialogue_cursor + 1) % _dialogue_choices.size()
		_control.queue_redraw()
	elif Input.is_action_just_pressed("attack") \
			or Input.is_action_just_pressed("ui_accept"):
		if _dialogue_cursor < _dialogue_choices.size():
			var cid: String = _dialogue_choices[_dialogue_cursor].get("id", "") as String
			choice_confirmed.emit(cid)
	elif Input.is_action_just_pressed("menu_back"):
		end_dialogue()
		dialogue_dismissed.emit()


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------

func _on_draw() -> void:
	if _font == null or MessageLog == null:
		return

	var gs  := GlobalConstants.GRID_SIZE
	var pw  := GlobalConstants.PANEL_TILES * gs
	var vw  := _control.size.x
	var vh  := _control.size.y

	var fs     := clampi(int(float(gs) * 0.16), 10, 16)
	var line_h := float(fs) * 1.5

	# ── ウィンドウ全体サイズ（15% 余白、ただしパネル幅より狭くなる場合はパネル幅を使用）
	var margin_x := maxf(vw * 0.12, float(pw) + 4.0)
	var box_w    := vw - 2.0 * margin_x
	var box_h    := line_h * float(VISIBLE_LINES) + 16.0
	var bx       := margin_x
	var by       := vh - box_h - 6.0

	# ── 画像エリア（正方形・高さいっぱい）
	var img_size := box_h

	# ── テキストエリア
	var text_bx := bx + img_size + 8.0
	var text_w  := box_w - 2.0 * img_size - 16.0

	# ── 背景
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.03, 0.03, 0.07, 0.80))

	# ── 外枠
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.30, 0.30, 0.45, 0.50), false, 1)

	# ── 左バスト画像（攻撃・回復側）
	_draw_bust(_left_tex, bx, by, img_size)
	# 左右の区切り線
	_control.draw_line(
		Vector2(bx + img_size, by + 4.0),
		Vector2(bx + img_size, by + box_h - 4.0),
		Color(0.30, 0.30, 0.45, 0.40), 1)

	# ── 右バスト画像（被攻撃・回復対象側）
	_draw_bust(_right_tex, bx + box_w - img_size, by, img_size)
	_control.draw_line(
		Vector2(bx + box_w - img_size, by + 4.0),
		Vector2(bx + box_w - img_size, by + box_h - 4.0),
		Color(0.30, 0.30, 0.45, 0.40), 1)

	# ── テキストエリア描画
	var text_y := by + 8.0 + float(fs)

	if not GlobalConstants.MESSAGE_WINDOW_SCROLL_MODE:
		# リセット型: 現在のペアのバトルメッセージを表示
		var start := maxi(0, _battle_lines.size() - VISIBLE_LINES)
		for i: int in range(start, _battle_lines.size()):
			var entry := _battle_lines[i]
			var col: Color = entry.get("color", Color.WHITE) as Color
			_control.draw_string(_font,
				Vector2(text_bx, text_y),
				entry.get("text", "") as String,
				HORIZONTAL_ALIGNMENT_LEFT, text_w, fs, col)
			text_y += line_h
	else:
		# スクロール型: MessageLog の visible エントリを最新 N 行表示
		var visible: Array[Dictionary] = MessageLog.get_visible_entries()
		var start := maxi(0, visible.size() - VISIBLE_LINES)
		for i: int in range(start, visible.size()):
			var entry := visible[i]
			var col: Color = entry.get("color", Color.WHITE) as Color
			_control.draw_string(_font,
				Vector2(text_bx, text_y),
				entry.get("text", "") as String,
				HORIZONTAL_ALIGNMENT_LEFT, text_w, fs, col)
			text_y += line_h

	# ── 会話モード中の選択肢（後方互換。現在は NpcDialogueWindow が担当）
	if _dialogue_active and not _dialogue_choices.is_empty():
		var sep_y := by + box_h - line_h * float(_dialogue_choices.size()) - float(fs) * 2.0
		_control.draw_line(
			Vector2(text_bx, sep_y),
			Vector2(text_bx + text_w, sep_y),
			Color(0.40, 0.40, 0.60, 0.60), 1)
		var choice_y := sep_y + 4.0 + float(fs)
		for i: int in range(_dialogue_choices.size()):
			var choice := _dialogue_choices[i]
			var label: String = choice.get("label", "") as String
			var is_sel := (i == _dialogue_cursor)
			if is_sel:
				_control.draw_rect(
					Rect2(text_bx - 2.0, choice_y - float(fs) + 2.0, text_w + 4.0, line_h),
					Color(0.22, 0.32, 0.62, 0.75))
			var arrow := "▶ " if is_sel else "   "
			var tx_col := Color.WHITE if is_sel else Color(0.70, 0.70, 0.82)
			_control.draw_string(_font,
				Vector2(text_bx, choice_y),
				arrow + label,
				HORIZONTAL_ALIGNMENT_LEFT, text_w, fs, tx_col)
			choice_y += line_h


## バスト画像（または暗幕）を指定座標に描画する
func _draw_bust(tex: Texture2D, x: float, y: float, size: float) -> void:
	var img_rect := Rect2(x, y, size, size)
	if tex == null:
		# 暗幕（半透明の黒）
		_control.draw_rect(img_rect, Color(0.0, 0.0, 0.0, 0.65))
		return

	var tex_size := tex.get_size()
	var src_rect: Rect2
	if tex_size.x >= 1024 and tex_size.y >= 512:
		# 1024x1024 front.png: 上半分中央をクロップ
		src_rect = Rect2(BUST_SRC_X, BUST_SRC_Y, BUST_SRC_W, BUST_SRC_H)
	else:
		# face.png（256×256）等: 全体を使用
		src_rect = Rect2(Vector2.ZERO, tex_size)

	_control.draw_texture_rect_region(tex, img_rect, src_rect)
