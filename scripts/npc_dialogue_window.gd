class_name NpcDialogueWindow
extends CanvasLayer

## NPC会話専用ウィンドウ（画面中央表示・ゲーム一時停止）
## NPC メンバーの顔画像・名前・クラスを上部に表示し、下部に選択肢を表示する。
## MAIN 状態：「仲間にする」「断る」の2択（デフォルト：仲間にする）
## CONFIRM 状態：「本当に仲間にしますか？」の確認ダイアログ（デフォルト：いいえ）
## 操作: ↑↓:選択  Z/A:決定  X/B:キャンセル/戻る

## 「仲間にする」を確定したとき発火する（choice_id = "join_us"）
signal choice_confirmed(choice_id: String)
## ウィンドウが閉じられたとき発火する（断る / Xキャンセル）
signal dismissed()
## パーティー満員ウィンドウが閉じられたとき発火する
signal party_full_closed()

const CHOICE_JOIN_US := "join_us"
const CHOICE_CANCEL  := "cancel"

enum _State { HIDDEN, MAIN, CONFIRM, PARTY_FULL }

var _state:          _State     = _State.HIDDEN
var _npc_manager:    NpcManager = null
var _npc_initiates:  bool       = false
var _main_cursor:    int        = 0   ## 0=仲間にする, 1=断る
var _confirm_cursor: int        = 1   ## 0=はい, 1=いいえ（デフォルト: いいえ）

var _control:    Control
var _font:       Font
var _tex_cache:  Dictionary = {}  ## path -> Texture2D or null


func _ready() -> void:
	layer        = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible      = false
	_font        = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter  = Control.MOUSE_FILTER_STOP
	_control.focus_mode    = Control.FOCUS_NONE
	_control.process_mode  = Node.PROCESS_MODE_ALWAYS
	add_child(_control)
	_control.draw.connect(_on_draw)


## パーティー満員のため仲間にできない旨を表示する
func show_party_full(nm: NpcManager) -> void:
	_npc_manager    = nm
	_state          = _State.PARTY_FULL
	visible         = true
	get_tree().paused = true
	_control.queue_redraw()


## NPC との会話ウィンドウを表示してゲームを一時停止する
func show_dialogue(nm: NpcManager, npc_initiates: bool) -> void:
	_npc_manager    = nm
	_npc_initiates  = npc_initiates
	_main_cursor    = 0
	_confirm_cursor = 1  # デフォルト: いいえ
	_state          = _State.MAIN
	visible         = true
	get_tree().paused = true
	_control.queue_redraw()


## ウィンドウを非表示にしてゲームを再開する
func hide_dialogue() -> void:
	_state            = _State.HIDDEN
	visible           = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if _state == _State.HIDDEN:
		return
	_handle_input()
	_control.queue_redraw()


func _handle_input() -> void:
	match _state:
		_State.MAIN:
			if Input.is_action_just_pressed("ui_up"):
				_main_cursor = (_main_cursor - 1 + 2) % 2
			elif Input.is_action_just_pressed("ui_down"):
				_main_cursor = (_main_cursor + 1) % 2
			elif Input.is_action_just_pressed("attack") \
					or Input.is_action_just_pressed("ui_accept"):
				if _main_cursor == 0:
					# 「仲間にする」→ 確認ダイアログへ
					_confirm_cursor = 1  # いいえ をデフォルト
					_state = _State.CONFIRM
				else:
					# 「断る」→ 即閉じる
					dismissed.emit()
			elif Input.is_action_just_pressed("menu_back"):
				dismissed.emit()

		_State.CONFIRM:
			if Input.is_action_just_pressed("ui_up"):
				_confirm_cursor = (_confirm_cursor - 1 + 2) % 2
			elif Input.is_action_just_pressed("ui_down"):
				_confirm_cursor = (_confirm_cursor + 1) % 2
			elif Input.is_action_just_pressed("attack") \
					or Input.is_action_just_pressed("ui_accept"):
				if _confirm_cursor == 0:
					# 「はい」→ 加入確定
					choice_confirmed.emit(CHOICE_JOIN_US)
				else:
					# 「いいえ」→ メイン選択肢に戻る
					_state = _State.MAIN
			elif Input.is_action_just_pressed("menu_back"):
				# Xキーで確認ダイアログからメイン選択肢に戻る
				_state = _State.MAIN

		_State.PARTY_FULL:
			if Input.is_action_just_pressed("attack") \
					or Input.is_action_just_pressed("ui_accept") \
					or Input.is_action_just_pressed("menu_back"):
				party_full_closed.emit()


func _on_draw() -> void:
	if _state == _State.HIDDEN or _font == null:
		return
	var gs  := float(GlobalConstants.GRID_SIZE)
	var vp  := _control.size
	_draw_panel(vp, gs)


func _draw_panel(vp: Vector2, gs: float) -> void:
	var members: Array[Character] = []
	if _npc_manager != null:
		for m: Character in _npc_manager.get_members():
			if is_instance_valid(m):
				members.append(m)
	var mem_count := members.size()

	var fs_title := maxi(15, int(gs * 0.18))
	var fs_body  := maxi(13, int(gs * 0.16))
	var fs_hint  := maxi(10, int(gs * 0.13))
	var row_cho  := maxf(28.0, gs * 0.32)
	var face_sz  := minf(gs * 1.3, 88.0)
	var pad      := maxf(16.0, gs * 0.20)

	# パネル幅（画面幅の60%か最大600px）
	var panel_w := minf(vp.x * 0.60, 600.0)
	panel_w = maxf(panel_w, gs * 6.0)

	# 高さを積み上げ計算
	var panel_h := pad
	panel_h += float(fs_title) + pad * 0.6          # タイトル行
	panel_h += 12.0 + 1.0 + 12.0                    # セパレーター

	# 顔画像行（顔 + 名前 + クラス）
	if mem_count > 0:
		panel_h += face_sz                           # 顔画像
		panel_h += float(fs_body) + 2.0             # 名前
		panel_h += float(fs_body) * 0.85 + 8.0      # クラス

	panel_h += 12.0 + 1.0 + 12.0                    # セパレーター

	if _state == _State.MAIN:
		panel_h += row_cho * 2.0 + 4.0 + 8.0        # 選択肢 2 行
	elif _state == _State.CONFIRM:
		panel_h += float(fs_body) + 12.0            # 確認テキスト
		panel_h += row_cho * 2.0 + 4.0 + 8.0        # はい/いいえ 2 行
	else:  # PARTY_FULL
		panel_h += float(fs_body) + 12.0            # 満員メッセージ
		panel_h += row_cho + 8.0                    # 閉じるボタン 1 行

	panel_h += float(fs_hint) + pad                 # ヒント + 下余白
	panel_h = maxf(panel_h, gs * 3.5)

	# 画面中央配置
	var px := (vp.x - panel_w) * 0.5
	var py := (vp.y - panel_h) * 0.45  # 少し上寄り

	# ── 暗幕オーバーレイ ───────────────────────────────────────────────────
	_control.draw_rect(Rect2(0.0, 0.0, vp.x, vp.y), Color(0.0, 0.0, 0.0, 0.55))

	# ── パネル背景・枠線 ─────────────────────────────────────────────────
	_control.draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.06, 0.12, 0.97))
	_control.draw_rect(Rect2(px, py, panel_w, panel_h),
		Color(0.50, 0.50, 0.72, 0.90), false, 2)

	var y := py + pad

	# ── タイトル ──────────────────────────────────────────────────────────
	var leader_name := _get_npc_leader_name()
	var title_str: String
	if _npc_initiates:
		title_str = "%s が話しかけてきた" % leader_name
	else:
		title_str = "%s のパーティーに話しかけた" % leader_name
	_control.draw_string(_font,
		Vector2(px + pad, y + float(fs_title)),
		title_str,
		HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_title,
		Color(0.88, 0.88, 1.00))
	y += float(fs_title) + pad * 0.6

	# セパレーター
	_draw_sep(px, y, panel_w, pad)
	y += 14.0

	# ── メンバー顔画像 + 名前・クラス ────────────────────────────────────
	if mem_count > 0:
		var total_face_w := float(mem_count) * face_sz + float(mem_count - 1) * 10.0
		var face_start_x := px + (panel_w - total_face_w) * 0.5

		for i: int in range(mem_count):
			var member: Character = members[i]
			var fx := face_start_x + float(i) * (face_sz + 10.0)

			# 顔画像（face.png → front.png の順）
			var tex := _get_face_texture(member)
			if tex != null:
				_control.draw_texture_rect(tex, Rect2(fx, y, face_sz, face_sz), false)
			else:
				_control.draw_rect(Rect2(fx, y, face_sz, face_sz),
					Color(0.20, 0.20, 0.28))
				# プレースホルダー文字
				_control.draw_string(_font,
					Vector2(fx + face_sz * 0.2, y + face_sz * 0.55),
					"?",
					HORIZONTAL_ALIGNMENT_LEFT, face_sz, int(face_sz * 0.4),
					Color(0.50, 0.50, 0.60))

		y += face_sz + 2.0

		# 名前行（各顔画像の下）
		for i: int in range(mem_count):
			var member: Character = members[i]
			var fx := face_start_x + float(i) * (face_sz + 10.0)
			var cd: CharacterData = member.character_data
			var nm_str := cd.character_name if cd != null else String(member.name)
			_control.draw_string(_font,
				Vector2(fx, y + float(fs_body)),
				nm_str,
				HORIZONTAL_ALIGNMENT_LEFT, face_sz, fs_body,
				Color.WHITE)
		y += float(fs_body) + 2.0

		# クラス行＋ランク
		for i: int in range(mem_count):
			var member: Character = members[i]
			var fx := face_start_x + float(i) * (face_sz + 10.0)
			var cd: CharacterData = member.character_data
			var cls_jp: String = GlobalConstants.CLASS_NAME_JP.get(
				cd.class_id if cd != null else "", "") as String
			var rank_str: String = cd.rank if cd != null else ""
			var sub_fs := int(fs_body * 0.82)
			var sub_y  := y + int(fs_body * 0.85)
			if not cls_jp.is_empty():
				_control.draw_string(_font,
					Vector2(fx, sub_y),
					cls_jp,
					HORIZONTAL_ALIGNMENT_LEFT, face_sz, sub_fs,
					Color(0.65, 0.65, 0.88))
			if not rank_str.is_empty():
				var rank_col := Color(1.0, 0.40, 0.40) if rank_str in ["S", "A"] \
					else Color(1.0, 0.65, 0.20)
				var cls_w := _font.get_string_size(cls_jp, HORIZONTAL_ALIGNMENT_LEFT,
					-1, sub_fs).x + 4.0
				_control.draw_string(_font,
					Vector2(fx + cls_w, sub_y),
					"[%s]" % rank_str,
					HORIZONTAL_ALIGNMENT_LEFT, face_sz - cls_w, sub_fs,
					rank_col)
		y += int(fs_body * 0.85) + 10.0

	# セパレーター
	_draw_sep(px, y, panel_w, pad)
	y += 14.0

	# ── 選択肢（MAIN 状態） ───────────────────────────────────────────────
	if _state == _State.MAIN:
		var choices: Array[String] = ["仲間にする", "断る"]
		for i: int in range(choices.size()):
			var is_sel := (i == _main_cursor)
			if is_sel:
				_control.draw_rect(
					Rect2(px + pad, y, panel_w - pad * 2.0, row_cho),
					Color(0.22, 0.32, 0.62, 0.75))
			var arrow  := "▶  " if is_sel else "    "
			var tx_col := Color.WHITE if is_sel else Color(0.76, 0.76, 0.88)
			_control.draw_string(_font,
				Vector2(px + pad + 4.0,
					y + float(fs_body) + (row_cho - float(fs_body)) * 0.5 + 2.0),
				arrow + choices[i],
				HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0 - 4.0, fs_body, tx_col)
			y += row_cho + 4.0

		# ヒント
		_control.draw_string(_font,
			Vector2(px + pad, py + panel_h - pad * 0.6),
			"↑↓:選択   Z/A:決定   X/B:閉じる",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_hint,
			Color(0.48, 0.48, 0.58))

	# ── 確認ダイアログ（CONFIRM 状態） ────────────────────────────────────
	elif _state == _State.CONFIRM:
		_control.draw_string(_font,
			Vector2(px + pad, y + float(fs_body)),
			"本当に仲間にしますか？",
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_body,
			Color(1.0, 0.92, 0.60))
		y += float(fs_body) + 12.0

		var conf_choices: Array[String] = ["はい", "いいえ"]
		for i: int in range(conf_choices.size()):
			var is_sel := (i == _confirm_cursor)
			if is_sel:
				_control.draw_rect(
					Rect2(px + pad, y, panel_w - pad * 2.0, row_cho),
					Color(0.22, 0.32, 0.62, 0.75))
			var arrow  := "▶  " if is_sel else "    "
			var tx_col := Color.WHITE if is_sel else Color(0.76, 0.76, 0.88)
			_control.draw_string(_font,
				Vector2(px + pad + 4.0,
					y + float(fs_body) + (row_cho - float(fs_body)) * 0.5 + 2.0),
				arrow + conf_choices[i],
				HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0 - 4.0, fs_body, tx_col)
			y += row_cho + 4.0

		# ヒント
		_control.draw_string(_font,
			Vector2(px + pad, py + panel_h - pad * 0.6),
			"↑↓:選択   Z/A:決定   X/B:戻る",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_hint,
			Color(0.48, 0.48, 0.58))

	# ── パーティー満員メッセージ（PARTY_FULL 状態） ──────────────────────
	else:
		_control.draw_string(_font,
			Vector2(px + pad, y + float(fs_body)),
			"これ以上仲間にできません（最大 %d 人）" % GlobalConstants.MAX_PARTY_MEMBERS,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_body,
			Color(1.0, 0.65, 0.25))
		y += float(fs_body) + 12.0

		# 閉じるボタン（常にハイライト）
		_control.draw_rect(
			Rect2(px + pad, y, panel_w - pad * 2.0, row_cho),
			Color(0.22, 0.32, 0.62, 0.75))
		_control.draw_string(_font,
			Vector2(px + pad + 4.0,
				y + float(fs_body) + (row_cho - float(fs_body)) * 0.5 + 2.0),
			"▶  閉じる",
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0 - 4.0, fs_body, Color.WHITE)

		# ヒント
		_control.draw_string(_font,
			Vector2(px + pad, py + panel_h - pad * 0.6),
			"Z/A・X/B:閉じる",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_hint,
			Color(0.48, 0.48, 0.58))


func _draw_sep(px: float, y: float, panel_w: float, pad: float) -> void:
	_control.draw_line(
		Vector2(px + pad, y),
		Vector2(px + panel_w - pad, y),
		Color(0.35, 0.35, 0.55, 0.65), 1)


## face.png → front.png の順で顔画像テクスチャを返す（キャッシュ付き）
func _get_face_texture(ch: Character) -> Texture2D:
	if ch == null or not is_instance_valid(ch) or ch.character_data == null:
		return null
	var cd := ch.character_data
	for path: String in [cd.sprite_face, cd.sprite_front]:
		if path.is_empty():
			continue
		if _tex_cache.has(path):
			var cached: Variant = _tex_cache[path]
			if cached != null:
				return cached as Texture2D
			continue
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			_tex_cache[path] = tex
			if tex != null:
				return tex
		_tex_cache[path] = null
	return null


## NPC パーティーのリーダー名を返す
func _get_npc_leader_name() -> String:
	if _npc_manager == null:
		return "NPC"
	for member: Character in _npc_manager.get_members():
		if is_instance_valid(member) and member.is_leader:
			if member.character_data != null \
					and not member.character_data.character_name.is_empty():
				return member.character_data.character_name
	for member: Character in _npc_manager.get_members():
		if is_instance_valid(member):
			if member.character_data != null \
					and not member.character_data.character_name.is_empty():
				return member.character_data.character_name
	return "NPC"
