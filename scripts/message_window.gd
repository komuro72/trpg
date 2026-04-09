class_name MessageWindow
extends CanvasLayer

## メッセージウィンドウ（Phase 14〜 アイコン行方式）
## ・画面中央寄せ（左右マージン・パネル幅以上）・高さ10行相当
## ・バトルメッセージ：行左端に [攻撃側face] → [被攻撃側face] アイコン2枚を表示
## ・システムメッセージ：アイコンなし（フル幅テキスト）
## ・スクロール型：最新エントリが常に下端に表示される

const VISIBLE_LINES: int = 7
const MSG_FONT_SIZE:  int = 20

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
# 描画用ノード
# --------------------------------------------------------------------------
var _control: Control
var _font:    Font

## テクスチャキャッシュ（ファイルパス → Texture2D）
var _tex_cache: Dictionary = {}


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
	_reject_active   = true
	_reject_timer    = 1.5
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


# --------------------------------------------------------------------------
# _process（リジェクトタイマー）
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _reject_active:
		_reject_timer -= delta
		if _reject_timer <= 0.0:
			_reject_active = false
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

	## MSG_FONT_SIZE は固定値・MSG_ICON_SIZE = MSG_FONT_SIZE * 2
	var fs      := MSG_FONT_SIZE
	var icon_sz := float(fs * 2)
	var line_h  := float(fs) * 1.5

	# ── ウィンドウ全体（画面幅の40〜50%・左右28%マージン）
	var margin_x := maxf(vw * 0.28, float(pw) + 4.0)
	var box_w    := vw - 2.0 * margin_x
	var box_h    := line_h * float(VISIBLE_LINES) + 16.0
	var bx       := margin_x
	var by       := vh - box_h - 6.0

	# ── アイコン列の幅（攻撃側アイコン + 矢印 + 被攻撃側アイコン + 右マージン）
	var arrow_str := "→ "
	var arrow_w   := _font.get_string_size(arrow_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_col_w := icon_sz + arrow_w + icon_sz + 6.0

	# ── バトル行のテキスト開始 X とテキスト幅
	var battle_text_x := bx + 8.0 + icon_col_w
	var battle_text_w := box_w - 16.0 - icon_col_w

	# ── システム行のテキスト開始 X とテキスト幅
	var sys_text_x := bx + 8.0
	var sys_text_w := box_w - 16.0

	# ── 背景
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.03, 0.03, 0.07, 0.80))
	# ── 外枠
	_control.draw_rect(
		Rect2(bx, by, box_w, box_h),
		Color(0.30, 0.30, 0.45, 0.50), false, 1)

	# ── 表示エントリ取得
	var visible: Array[Dictionary] = MessageLog.get_visible_entries()
	if visible.is_empty():
		return

	# ── 下から積み上げて収まるエントリ範囲を決定
	var avail_h := box_h - 8.0
	var total_h := 0.0
	var start_i := visible.size()
	for i: int in range(visible.size() - 1, -1, -1):
		var eh := _entry_height(visible[i], battle_text_w, sys_text_w, fs, line_h, icon_sz)
		if total_h + eh > avail_h:
			break
		total_h += eh
		start_i = i

	# ── 下詰めで描画開始 Y を決定
	var entry_y := by + 4.0 + (avail_h - total_h)
	entry_y = maxf(entry_y, by + 4.0)

	# ── 各エントリを描画
	for i: int in range(start_i, visible.size()):
		var entry  := visible[i]
		var eh     := _entry_height(entry, battle_text_w, sys_text_w, fs, line_h, icon_sz)
		var is_battle: bool = int(entry.get("type", 0)) == int(MessageLog.MsgType.BATTLE)
		var col: Color = entry.get("color", Color.WHITE) as Color
		var text: String = entry.get("text", "") as String

		if is_battle:
			var atk_data: CharacterData = entry.get("attacker_data") as CharacterData
			var def_data: CharacterData = entry.get("defender_data") as CharacterData

			# 攻撃側アイコン
			_draw_face_icon(atk_data, bx + 8.0, entry_y, icon_sz)

			# 矢印（アイコンの縦中央に揃える）
			var arrow_y := entry_y + icon_sz * 0.5 + float(fs) * 0.35
			_control.draw_string(_font,
				Vector2(bx + 8.0 + icon_sz + 2.0, arrow_y),
				arrow_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.70, 0.70, 0.70))

			# 被攻撃側アイコン
			_draw_face_icon(def_data, bx + 8.0 + icon_sz + arrow_w, entry_y, icon_sz)

			# テキスト（折り返し）
			_control.draw_multiline_string(_font,
				Vector2(battle_text_x, entry_y + float(fs)),
				text, HORIZONTAL_ALIGNMENT_LEFT, battle_text_w, fs, -1, col)
		else:
			# システム・デバッグ行：アイコンなし・フル幅
			_control.draw_multiline_string(_font,
				Vector2(sys_text_x, entry_y + float(fs)),
				text, HORIZONTAL_ALIGNMENT_LEFT, sys_text_w, fs, -1, col)

		entry_y += eh


# --------------------------------------------------------------------------
# ヘルパー：エントリ高さ計算
# --------------------------------------------------------------------------

## エントリ1件の描画高さ（ピクセル）を返す
func _entry_height(entry: Dictionary, battle_tw: float, sys_tw: float,
		fs: int, line_h: float, icon_sz: float) -> float:
	var is_battle: bool = int(entry.get("type", 0)) == int(MessageLog.MsgType.BATTLE)
	var text: String = entry.get("text", "") as String
	if _font == null or text.is_empty():
		return line_h
	var tw := battle_tw if is_battle else sys_tw
	var sz := _font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, tw, fs)
	var text_h := sz.y + 4.0  # テキスト高さ + 行間マージン
	if is_battle:
		# アイコン高さとテキスト高さの大きい方
		return maxf(icon_sz + 4.0, text_h)
	return text_h


# --------------------------------------------------------------------------
# ヘルパー：テクスチャ管理
# --------------------------------------------------------------------------

## CharacterData から face.png テクスチャを返す（キャッシュあり）
## face.png がなければ null（グレーフォールバックは _draw_face_icon が担当）
func _load_face_tex(data: CharacterData) -> Texture2D:
	if data == null:
		return null
	var path := data.sprite_face
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _tex_cache.has(path):
		return _tex_cache.get(path) as Texture2D
	var tex := load(path) as Texture2D
	if tex != null:
		_tex_cache[path] = tex
	return tex


## キャラクターアイコン（正方形）を指定座標に描画する
## テクスチャがない場合はグレーの正方形をフォールバック表示
func _draw_face_icon(data: CharacterData, x: float, y: float, size: float) -> void:
	var rect := Rect2(x, y, size, size)
	var tex  := _load_face_tex(data)
	if tex == null:
		# グレーフォールバック（キャラなし or 画像なし）
		_control.draw_rect(rect, Color(0.28, 0.28, 0.33, 0.80))
		return
	# face.png（256x256）は全体を縮小して表示
	_control.draw_texture_rect(tex, rect, false)
