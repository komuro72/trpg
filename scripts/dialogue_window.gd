class_name DialogueWindow
extends CanvasLayer

## 会話ウィンドウ
## フィールドエリア下部にポップアップ表示する。フォントサイズは GRID_SIZE に連動。
## 操作: ↑↓ で選択、Z / Enter で決定、Esc で閉じる。
## プレイヤー起点: 3択（仲間に / 連れて行って / 立ち去る）
## NPC 起点: 2択（承諾する / 断る）

signal choice_confirmed(choice_id: String)
signal dismissed()

const CHOICE_JOIN_US   := "join_us"    ## 「仲間になってほしい」
const CHOICE_JOIN_THEM := "join_them"  ## 「一緒に連れて行ってほしい」
const CHOICE_CANCEL    := "cancel"

enum _State { HIDDEN, SHOWING, REJECTED }

var _state:         _State = _State.HIDDEN
var _npc_manager:   PartyManager
var _npc_initiates: bool         = false
var _choices:       Array[String] = []
var _choice_index:  int           = 0
var _reject_timer:  float         = 0.0

var _control: Control
var _font:    Font


func _ready() -> void:
	layer   = 15
	visible = false
	_font   = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)


func show_dialogue(nm: PartyManager, npc_initiates: bool) -> void:
	_npc_manager   = nm
	_npc_initiates = npc_initiates
	_state         = _State.SHOWING
	_choice_index  = 0
	_choices.clear()
	if npc_initiates:
		_choices.assign([CHOICE_JOIN_US, CHOICE_CANCEL])
	else:
		_choices.assign([CHOICE_JOIN_US, CHOICE_JOIN_THEM, CHOICE_CANCEL])
	visible = true
	_control.queue_redraw()


func show_rejected() -> void:
	_state        = _State.REJECTED
	_reject_timer = 1.8
	_control.queue_redraw()


func hide_dialogue() -> void:
	_state  = _State.HIDDEN
	visible = false


func _process(delta: float) -> void:
	if _state == _State.HIDDEN:
		return

	if _state == _State.REJECTED:
		_reject_timer -= delta
		if _reject_timer <= 0.0:
			hide_dialogue()
			dismissed.emit()
		return

	# SHOWING: 入力処理
	if Input.is_action_just_pressed("ui_up"):
		_choice_index = (_choice_index - 1 + _choices.size()) % _choices.size()
		_control.queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		_choice_index = (_choice_index + 1) % _choices.size()
		_control.queue_redraw()
	elif Input.is_action_just_pressed("attack") \
			or Input.is_action_just_pressed("ui_accept") \
			or Input.is_action_just_pressed("ui_right"):
		choice_confirmed.emit(_choices[_choice_index])
	elif Input.is_action_just_pressed("ui_cancel") \
			or Input.is_action_just_pressed("menu_back") \
			or Input.is_action_just_pressed("ui_left"):
		hide_dialogue()
		dismissed.emit()


func _on_draw() -> void:
	if _state == _State.HIDDEN or _font == null:
		return

	var vp    := _control.size
	var gs    := GlobalConstants.GRID_SIZE
	var gs_f  := float(gs)
	var pw    := float(GlobalConstants.PANEL_TILES * gs)
	var field_x  := pw
	var field_w  := vp.x - pw * 2.0
	var field_cx := field_x + field_w * 0.5

	if _state == _State.REJECTED:
		_draw_rejected(field_cx, vp.y, gs_f)
		return

	_draw_panel(field_x, field_w, vp.y, gs_f)


# --------------------------------------------------------------------------
# 拒否メッセージ（画面下部・中央寄せ）
# --------------------------------------------------------------------------

func _draw_rejected(field_cx: float, vp_h: float, gs_f: float) -> void:
	var fs  := maxi(16, int(gs_f * 0.19))
	var w   := maxf(340.0, gs_f * 3.5)
	var h   := maxf(72.0, gs_f * 0.80)
	var rx  := field_cx - w * 0.5
	var ry  := vp_h - h - 20.0
	_control.draw_rect(Rect2(rx, ry, w, h), Color(0.12, 0.04, 0.04, 0.97))
	_control.draw_rect(Rect2(rx, ry, w, h), Color(0.80, 0.20, 0.20, 0.90), false, 2)
	_control.draw_string(_font,
		Vector2(rx + 24.0, ry + h * 0.62),
		"断られた...",
		HORIZONTAL_ALIGNMENT_LEFT, w - 48.0, fs, Color(1.0, 0.50, 0.50))


# --------------------------------------------------------------------------
# メインパネル（フィールド下部ポップアップ）
# --------------------------------------------------------------------------

func _draw_panel(field_x: float, field_w: float, vp_h: float, gs_f: float) -> void:
	# フォントサイズ（GRID_SIZE に連動）
	var fs_title := maxi(15, int(gs_f * 0.18))  # タイトル行
	var fs_body  := maxi(13, int(gs_f * 0.16))  # メンバー行・選択肢
	var fs_hint  := maxi(10, int(gs_f * 0.13))  # 操作ヒント

	# 行高
	var row_mem := maxf(22.0, gs_f * 0.27)   # メンバー行
	var row_cho := maxf(26.0, gs_f * 0.32)   # 選択肢行

	var pad := maxf(18.0, gs_f * 0.20)

	# パネル横幅（フィールド幅いっぱい・左右 16px マージン）
	var panel_w := field_w - 32.0
	var px      := field_x + 16.0

	# パネル高さを動的に計算
	var member_count := _npc_manager.get_members().size() if _npc_manager != null else 0
	var choice_count := _choices.size()
	var offer_h      := row_cho if _npc_initiates else 0.0

	var panel_h := pad                                           # 上余白
	panel_h += float(fs_title) + 10.0                           # タイトル行
	panel_h += 14.0 + 1.0 + 12.0                                # セパレーター
	panel_h += float(member_count) * row_mem + 8.0              # メンバー一覧
	panel_h += 12.0 + 1.0 + 12.0                                # セパレーター
	panel_h += offer_h                                           # NPC 申し出文
	panel_h += float(choice_count) * (row_cho + 4.0) + 8.0     # 選択肢
	panel_h += 10.0 + float(fs_hint) + pad                      # ヒント・下余白
	panel_h = maxf(panel_h, gs_f * 2.4)

	# 画面下部に配置
	var py := vp_h - panel_h - 16.0

	# パネル背景・枠線
	_control.draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.06, 0.12, 0.97))
	_control.draw_rect(Rect2(px, py, panel_w, panel_h),
		Color(0.50, 0.50, 0.72, 0.90), false, 2)

	var y := py + pad

	# ── タイトル ──────────────────────────────────────────
	var title: String = _get_npc_leader_name() + " が話しかけてきた" \
		if _npc_initiates else "話しかける"
	_control.draw_string(_font,
		Vector2(px + pad, y + float(fs_title)),
		title, HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_title,
		Color(0.88, 0.88, 1.00))
	y += float(fs_title) + 14.0

	# セパレーター
	_draw_sep(px, y, panel_w, pad)
	y += 14.0

	# ── NPC メンバー一覧 ───────────────────────────────────
	# 列 X 座標（GRID_SIZE 比例）
	var col_name := px + pad
	var col_rank := col_name + gs_f * 2.1
	var col_cls  := col_rank + gs_f * 0.9
	var col_cond := col_cls  + gs_f * 2.0

	if _npc_manager != null:
		for member: Character in _npc_manager.get_members():
			if not is_instance_valid(member):
				continue
			var cd: CharacterData = member.character_data
			var nm_str:  String = cd.character_name if cd != null else String(member.name)
			var cls_str: String = cd.class_id       if cd != null else ""
			var rnk_str: String = cd.rank           if cd != null else "C"
			var ratio  := float(member.hp) / float(member.max_hp) if member.max_hp > 0 else 0.0
			var cond_s := "healthy" if ratio > 0.6 else ("wounded" if ratio > 0.3 else "critical")
			var cond_col: Color
			match cond_s:
				"healthy": cond_col = Color(0.40, 0.90, 0.40)
				"wounded": cond_col = Color(1.00, 0.80, 0.20)
				_:         cond_col = Color(1.00, 0.35, 0.35)
			var rank_col := Color(1.0, 0.4, 0.4) if rnk_str in ["S", "A"] \
				else Color(1.0, 0.65, 0.2)
			var ty := y + float(fs_body)
			_control.draw_string(_font, Vector2(col_name, ty),
				nm_str,           HORIZONTAL_ALIGNMENT_LEFT, gs_f * 2.0, fs_body, Color.WHITE)
			_control.draw_string(_font, Vector2(col_rank, ty),
				"[%s]" % rnk_str, HORIZONTAL_ALIGNMENT_LEFT, gs_f * 0.8, fs_body, rank_col)
			_control.draw_string(_font, Vector2(col_cls, ty),
				cls_str,          HORIZONTAL_ALIGNMENT_LEFT, gs_f * 1.9, fs_body, Color(0.70, 0.70, 0.90))
			_control.draw_string(_font, Vector2(col_cond, ty),
				cond_s,           HORIZONTAL_ALIGNMENT_LEFT, gs_f * 1.5, fs_body, cond_col)
			y += row_mem
	y += 8.0

	# セパレーター
	_draw_sep(px, y, panel_w, pad)
	y += 14.0

	# ── NPC 申し出テキスト（NPC 起点のみ） ──────────────────
	if _npc_initiates:
		_control.draw_string(_font,
			Vector2(px + pad, y + float(fs_body)),
			"「一緒に連れて行ってもらえないか...」",
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_body,
			Color(0.80, 0.92, 0.80))
		y += row_cho

	# ── 選択肢 ────────────────────────────────────────────
	var choice_labels: Dictionary
	if _npc_initiates:
		choice_labels = {
			CHOICE_JOIN_US:   "（承諾する）",
			CHOICE_CANCEL:    "（断る）",
		}
	else:
		choice_labels = {
			CHOICE_JOIN_US:   "「仲間になってほしい」",
			CHOICE_JOIN_THEM: "「一緒に連れて行ってほしい」",
			CHOICE_CANCEL:    "（立ち去る）",
		}

	for i: int in range(_choices.size()):
		var cid    := _choices[i]
		var label  := choice_labels.get(cid, cid) as String
		var is_sel := (i == _choice_index)
		var rh     := row_cho
		if is_sel:
			_control.draw_rect(Rect2(px + pad, y, panel_w - pad * 2.0, rh),
				Color(0.22, 0.32, 0.62, 0.75))
		var arrow  := "▶  " if is_sel else "    "
		var tx_col := Color.WHITE if is_sel else Color(0.76, 0.76, 0.88)
		_control.draw_string(_font,
			Vector2(px + pad + 4.0, y + float(fs_body) + (rh - float(fs_body)) * 0.5 + 2.0),
			arrow + label,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0 - 4.0, fs_body, tx_col)
		y += rh + 4.0
	y += 4.0

	# ── 操作ヒント ────────────────────────────────────────
	_control.draw_string(_font,
		Vector2(px + pad, py + panel_h - pad * 0.6),
		"↑↓ : 選択    Z / 右 : 決定    X / 左 / Esc : 閉じる",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs_hint, Color(0.48, 0.48, 0.58))


func _draw_sep(px: float, y: float, panel_w: float, pad: float) -> void:
	_control.draw_line(
		Vector2(px + pad, y),
		Vector2(px + panel_w - pad, y),
		Color(0.35, 0.35, 0.55, 0.65), 1)


func _get_npc_leader_name() -> String:
	if _npc_manager == null:
		return "NPC"
	var members := _npc_manager.get_members()
	if members.is_empty():
		return "NPC"
	var first := members[0] as Character
	if not is_instance_valid(first):
		return "NPC"
	if first.character_data != null and not first.character_data.character_name.is_empty():
		return first.character_data.character_name
	return String(first.name)
