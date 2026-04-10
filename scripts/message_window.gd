class_name MessageWindow
extends CanvasLayer

## メッセージウィンドウ（Phase 14〜 アイコン行方式 + 上半身画像）
## ・左：操作キャラの上半身画像（front.png クロップ）
## ・中央：アイコン+テキストログ（スクロール）
## ・右：操作キャラが交戦した相手の上半身画像
## ・バトルメッセージ：行左端に [攻撃側face] → [被攻撃側face] アイコン
## ・システムメッセージ：アイコンなし

const VISIBLE_LINES: int = 7
const MSG_FONT_SIZE:  int = 20

## front.png のバスト領域クロップ（1024x1024 画像の上半分中央部分）
const BUST_SRC_X: float = 256.0
const BUST_SRC_Y: float = 0.0
const BUST_SRC_W: float = 512.0
const BUST_SRC_H: float = 512.0

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
# 上半身画像管理
# --------------------------------------------------------------------------
## 左エリア：現在の操作キャラ（game_map から set_player_character() で設定）
var _player_char_data:   CharacterData = null
## 右エリア：操作キャラが交戦した相手（battle_message_added シグナルで自動更新）
var _combat_target_data: CharacterData = null

## バスト画像キャッシュ（front.png 用。face アイコン用の _tex_cache とは別）
var _bust_cache: Dictionary = {}

# --------------------------------------------------------------------------
# 描画用ノード
# --------------------------------------------------------------------------
var _control: Control
var _font:    Font

## アイコン用テクスチャキャッシュ（face.png 用）
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
		MessageLog.battle_message_added.connect(_on_battle_message)


# --------------------------------------------------------------------------
# 公開 API：上半身画像の設定
# --------------------------------------------------------------------------

## 左エリアの操作キャラを設定する。右エリアもリセットする。
## game_map.gd の操作キャラ切り替え時・初期設定時に呼ぶ。
func set_player_character(data: CharacterData) -> void:
	_player_char_data   = data
	_combat_target_data = null  # 操作キャラが変わったら交戦相手もリセット
	if _control != null:
		_control.queue_redraw()


## 右エリアの交戦相手を設定する。
func set_combat_target(data: CharacterData) -> void:
	_combat_target_data = data
	if _control != null:
		_control.queue_redraw()


# --------------------------------------------------------------------------
# 後方互換 API
# --------------------------------------------------------------------------

func show_message(msg: String) -> void:
	if MessageLog != null:
		MessageLog.add_system(msg)


var log_entries: Array[String]:
	get:
		var result: Array[String] = []
		if MessageLog != null:
			for e: Dictionary in MessageLog.get_visible_entries():
				result.append(e.get("text", "") as String)
		return result


func start_dialogue(choices: Array[Dictionary]) -> void:
	_dialogue_choices = choices
	_dialogue_cursor  = 0
	_dialogue_active  = true
	_reject_active    = false
	if _control != null:
		_control.queue_redraw()


func show_rejected(msg: String = "断られた...") -> void:
	show_message(msg)
	_reject_active   = true
	_reject_timer    = 1.5
	_dialogue_active = false
	_dialogue_choices.clear()


func end_dialogue() -> void:
	_dialogue_active = false
	_dialogue_choices.clear()
	_reject_active = false
	if _control != null:
		_control.queue_redraw()


func is_dialogue_active() -> bool:
	return _dialogue_active


# --------------------------------------------------------------------------
# シグナルハンドラ
# --------------------------------------------------------------------------

func _on_entry_changed() -> void:
	if _control != null:
		_control.queue_redraw()


## バトルメッセージ受信：操作キャラが関与していれば右エリアを更新する
func _on_battle_message(atk_data: CharacterData, def_data: CharacterData,
		_message: String, _atk_char: Character, def_char: Character) -> void:
	if _player_char_data == null:
		return
	# 操作キャラが攻撃側 → 右エリアは被攻撃側
	if atk_data == _player_char_data:
		# defender が死亡済みなら右エリアをクリア
		if def_char != null and is_instance_valid(def_char) and def_char.hp <= 0:
			_combat_target_data = null
		else:
			set_combat_target(def_data)
	# 操作キャラが被攻撃側 → 右エリアは攻撃側
	elif def_data == _player_char_data:
		set_combat_target(atk_data)


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

	## MSG_FONT_SIZE は固定値。アイコンは右パネルと同サイズ（gs * 2/3）
	var fs      := MSG_FONT_SIZE
	var icon_sz := float(maxi(20, gs * 2 / 3))
	var line_h  := float(fs) * 1.5

	# ── 中央テキストエリアのウィンドウサイズ
	var margin_x := maxf(vw * 0.28, float(pw) + 4.0)
	var box_w    := vw - 2.0 * margin_x
	var box_h    := line_h * float(VISIBLE_LINES) + 16.0
	var bx       := margin_x
	var by       := vh - box_h - 6.0

	# ── 上半身画像エリア（正方形・ウィンドウ高さと同じ）
	var img_size := box_h
	var left_x   := bx - img_size
	var right_x  := bx + box_w

	# ── 全体背景（左バスト + 中央 + 右バスト）
	_control.draw_rect(
		Rect2(left_x, by, img_size + box_w + img_size, box_h),
		Color(0.03, 0.03, 0.07, 0.80))
	# 外枠
	_control.draw_rect(
		Rect2(left_x, by, img_size + box_w + img_size, box_h),
		Color(0.30, 0.30, 0.45, 0.50), false, 1)

	# ── 左バスト画像（操作キャラ）
	_draw_bust(_player_char_data, left_x, by, img_size)
	# 左セパレータ
	_control.draw_line(
		Vector2(bx, by + 4.0),
		Vector2(bx, by + box_h - 4.0),
		Color(0.30, 0.30, 0.45, 0.40), 1)

	# ── 右バスト画像（交戦相手）
	_draw_bust(_combat_target_data, right_x, by, img_size)
	# 右セパレータ
	_control.draw_line(
		Vector2(right_x, by + 4.0),
		Vector2(right_x, by + box_h - 4.0),
		Color(0.30, 0.30, 0.45, 0.40), 1)

	# ── アイコン列の幅
	var arrow_str  := "→ "
	var arrow_w    := _font.get_string_size(arrow_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_col_w := icon_sz + arrow_w + icon_sz + 6.0

	# ── バトル行テキスト領域
	var battle_text_x := bx + 8.0 + icon_col_w
	var battle_text_w := box_w - 16.0 - icon_col_w

	# ── システム行テキスト領域
	var sys_text_x := bx + 8.0
	var sys_text_w := box_w - 16.0

	# ── 表示エントリ取得・同アイコンペアをグループ化
	var visible: Array[Dictionary] = MessageLog.get_visible_entries()
	if visible.is_empty():
		return
	var groups := _build_display_groups(visible)

	# ── 下から積み上げて収まるグループ範囲を決定
	var avail_h := box_h - 8.0
	var total_h := 0.0
	var start_g := groups.size()
	for i: int in range(groups.size() - 1, -1, -1):
		var gh := _group_height(groups[i], battle_text_w, sys_text_w, fs, line_h, icon_sz)
		if total_h + gh > avail_h:
			break
		total_h += gh
		start_g = i

	# ── 下詰めで描画開始 Y を決定
	var entry_y := by + 4.0 + (avail_h - total_h)
	entry_y = maxf(entry_y, by + 4.0)

	# ── 各グループを描画
	for i: int in range(start_g, groups.size()):
		var group      := groups[i] as Dictionary
		var gh         := _group_height(group, battle_text_w, sys_text_w, fs, line_h, icon_sz)
		var is_battle  : bool   = group.get("is_battle", false) as bool
		var col        : Color  = group.get("color", Color.WHITE) as Color
		var text       : String = group.get("text", "") as String

		if is_battle:
			var atk_data: CharacterData = group.get("atk_data") as CharacterData
			var def_data: CharacterData = group.get("def_data") as CharacterData

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

			# テキスト（\n 区切りで複数行）
			_control.draw_multiline_string(_font,
				Vector2(battle_text_x, entry_y + float(fs)),
				text, HORIZONTAL_ALIGNMENT_LEFT, battle_text_w, fs, -1, col)
		else:
			# システム・デバッグ行：アイコンなし・フル幅
			_control.draw_multiline_string(_font,
				Vector2(sys_text_x, entry_y + float(fs)),
				text, HORIZONTAL_ALIGNMENT_LEFT, sys_text_w, fs, -1, col)

		entry_y += gh


# --------------------------------------------------------------------------
# ヘルパー：グループ化・高さ計算
# --------------------------------------------------------------------------

## 連続する同アイコンペアのバトルエントリをまとめて表示グループを作る
## 異なるペア・システムメッセージは個別グループになる
func _build_display_groups(entries: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var i := 0
	while i < entries.size():
		var e          := entries[i] as Dictionary
		var is_battle  : bool = int(e.get("type", 0)) == int(MessageLog.MsgType.BATTLE)
		if not is_battle:
			groups.append({
				"is_battle": false,
				"text":  e.get("text",  "") as String,
				"color": e.get("color", Color.WHITE) as Color,
			})
			i += 1
			continue
		# バトルエントリ：同ペアが続く限りまとめる
		var atk_data : CharacterData = e.get("attacker_data") as CharacterData
		var def_data : CharacterData = e.get("defender_data") as CharacterData
		var color    : Color         = e.get("color", Color.WHITE) as Color
		var lines    : PackedStringArray = PackedStringArray([e.get("text", "") as String])
		i += 1
		while i < entries.size():
			var nxt := entries[i] as Dictionary
			if int(nxt.get("type", 0)) != int(MessageLog.MsgType.BATTLE):
				break
			if (nxt.get("attacker_data") as CharacterData) != atk_data:
				break
			if (nxt.get("defender_data") as CharacterData) != def_data:
				break
			lines.append(nxt.get("text", "") as String)
			i += 1
		groups.append({
			"is_battle": true,
			"atk_data": atk_data,
			"def_data": def_data,
			"text":  "\n".join(lines),
			"color": color,
		})
	return groups


## グループの描画高さを返す
func _group_height(group: Dictionary, battle_tw: float, sys_tw: float,
		fs: int, line_h: float, icon_sz: float) -> float:
	var is_battle : bool   = group.get("is_battle", false) as bool
	var text      : String = group.get("text", "") as String
	if _font == null or text.is_empty():
		return line_h
	var tw := battle_tw if is_battle else sys_tw
	var sz := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, tw, fs)
	var text_h := sz.y + 4.0
	if is_battle:
		return maxf(icon_sz + 4.0, text_h)
	return text_h


# --------------------------------------------------------------------------
# ヘルパー：テクスチャ管理
# --------------------------------------------------------------------------

## CharacterData から上半身バスト用テクスチャを返す（sprite_front / キャッシュあり）
func _load_bust_tex(data: CharacterData) -> Texture2D:
	if data == null:
		return null
	var path := data.sprite_front
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _bust_cache.has(path):
		return _bust_cache.get(path) as Texture2D
	var tex := load(path) as Texture2D
	if tex != null:
		_bust_cache[path] = tex
	return tex


## CharacterData から face.png テクスチャを返す（キャッシュあり）
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


## 上半身バスト画像（または暗幕）を描画する
func _draw_bust(data: CharacterData, x: float, y: float, size: float) -> void:
	var rect := Rect2(x, y, size, size)
	var tex  := _load_bust_tex(data)
	if tex == null:
		_control.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.65))
		return
	var tex_size := tex.get_size()
	var src_rect: Rect2
	if tex_size.x >= 1024 and tex_size.y >= 512:
		# 1024x1024 front.png: 上半分中央をクロップ
		src_rect = Rect2(BUST_SRC_X, BUST_SRC_Y, BUST_SRC_W, BUST_SRC_H)
	else:
		src_rect = Rect2(Vector2.ZERO, tex_size)
	_control.draw_texture_rect_region(tex, rect, src_rect)


## キャラクターアイコン（正方形）を描画する（face.png / グレーフォールバック）
func _draw_face_icon(data: CharacterData, x: float, y: float, size: float) -> void:
	var rect := Rect2(x, y, size, size)
	var tex  := _load_face_tex(data)
	if tex == null:
		_control.draw_rect(rect, Color(0.28, 0.28, 0.33, 0.80))
		return
	_control.draw_texture_rect(tex, rect, false)
