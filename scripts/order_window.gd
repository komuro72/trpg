class_name OrderWindow
extends CanvasLayer

## パーティー指示ウィンドウ（Phase 10-4 拡張版）
## Tab キーで開閉。全体方針プリセット + 5項目個別設定 + 操作キャラ切替。
## 下部にステータス詳細・装備スロット（空）・所持アイテム欄（空）を表示。
## リーダー操作中：指示の変更可。非リーダー操作中：閲覧のみ。
## 操作:
##   全体方針行: ←→ でプリセット選択, Z/Enter で全メンバーに適用（リーダーのみ）
##   メンバー行: ↑↓ で行移動, ←→ で列移動, Z で値を切替（操作列は切替発動）
##   閉じる行:  Z/Enter または Esc で閉じる

signal closed()
## 操作キャラの切替を要求する（game_map が受け取って実際の切替を行う）
signal switch_requested(new_character: Character)

# ── 定数 ─────────────────────────────────────────────────────────────────────

const PRESETS: Array[String] = ["攻撃", "防衛", "待機", "追従", "撤退", "探索"]

## プリセット → [combat, battle_formation, move, target, on_low_hp]
const PRESET_TABLE: Array = [
	["aggressive", "surround", "same_room", "nearest",        "keep_fighting"],
	["support",    "surround", "cluster",   "same_as_leader", "retreat"],
	["standby",    "surround", "cluster",   "nearest",        "retreat"],
	["support",    "surround", "cluster",   "same_as_leader", "retreat"],
	["standby",    "surround", "cluster",   "nearest",        "flee"],
	["aggressive", "surround", "explore",   "nearest",        "retreat"],
]

const COL_OPTIONS: Array = [
	["explore", "same_room", "cluster", "guard_room", "standby"],
	["surround", "front", "rear", "same_as_leader"],
	["aggressive", "support", "standby"],
	["nearest", "weakest", "same_as_leader"],
	["keep_fighting", "retreat", "flee"],
]

const COL_LABELS: Array = [
	["探索", "同じ部屋", "密集", "部屋守る", "待機"],
	["包囲", "前衛", "後衛", "リーダーと同じ"],
	["積極攻撃", "援護", "待機"],
	["最近傍", "最弱", "リーダーと同じ"],
	["戦い続ける", "後退", "逃走"],
]

const COL_HEADERS: Array[String] = ["移動", "隊形", "戦闘", "ターゲット", "低HP"]
const COL_KEYS: Array[String] = ["move", "battle_formation", "combat", "target", "on_low_hp"]
const TOTAL_COLS := 6

## 攻撃タイプの表示名
const ATTACK_TYPE_LABELS: Dictionary = {
	"melee": "近接", "ranged": "遠距離", "dive": "降下"
}

# ── 内部状態 ──────────────────────────────────────────────────────────────────

enum _FocusArea { GLOBAL_POLICY, MEMBER_TABLE, CLOSE }

var _party:          Party
var _focus_area:     _FocusArea = _FocusArea.GLOBAL_POLICY
var _policy_cursor:  int = 0
var _applied_policy: int = -1
var _member_cursor:  int = 0
var _col_cursor:     int = 1

var _controlled_char: Character = null
var _sorted_members: Array = []

var _control: Control
var _font:    Font

## front/face 画像テクスチャキャッシュ（パス → Texture2D）
var _texture_cache: Dictionary = {}


# ── セットアップ ──────────────────────────────────────────────────────────────

func setup(party: Party) -> void:
	_party = party


func set_controlled(ch: Character) -> void:
	_controlled_char = ch


# ── 開閉 ─────────────────────────────────────────────────────────────────────

func open_window() -> void:
	if _party == null:
		return
	# カーソル位置は前回のまま維持（_focus_area / _member_cursor / _col_cursor はリセットしない）
	visible = true
	_control.queue_redraw()


func close_window() -> void:
	visible = false
	closed.emit()


# ── Ready ─────────────────────────────────────────────────────────────────────

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


# ── 入力処理 ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not visible:
		return
	if _party != null:
		_sorted_members = _party.sorted_members()
	_handle_input()
	_control.queue_redraw()


func _handle_input() -> void:
	var members_count := _sorted_members.size()

	match _focus_area:
		_FocusArea.GLOBAL_POLICY:
			if Input.is_action_just_pressed("ui_left"):
				_policy_cursor = (_policy_cursor - 1 + PRESETS.size()) % PRESETS.size()
			elif Input.is_action_just_pressed("ui_right"):
				_policy_cursor = (_policy_cursor + 1) % PRESETS.size()
			elif Input.is_action_just_pressed("attack_melee") \
					or Input.is_action_just_pressed("ui_accept"):
				if _is_editable():
					_apply_preset(_policy_cursor)
			elif Input.is_action_just_pressed("ui_down"):
				if members_count > 0:
					_focus_area    = _FocusArea.MEMBER_TABLE
					_member_cursor = 0
					_col_cursor    = 0  # 操作列から開始
				else:
					_focus_area = _FocusArea.CLOSE
			elif Input.is_action_just_pressed("ui_cancel"):
				close_window()

		_FocusArea.MEMBER_TABLE:
			if Input.is_action_just_pressed("ui_up"):
				if _member_cursor <= 0:
					_focus_area = _FocusArea.GLOBAL_POLICY
				else:
					_member_cursor -= 1
			elif Input.is_action_just_pressed("ui_down"):
				if _member_cursor >= members_count - 1:
					_focus_area = _FocusArea.CLOSE
				else:
					_member_cursor += 1
			elif Input.is_action_just_pressed("ui_left"):
				_col_cursor = (_col_cursor - 1 + TOTAL_COLS) % TOTAL_COLS
			elif Input.is_action_just_pressed("ui_right"):
				_col_cursor = (_col_cursor + 1) % TOTAL_COLS
			elif Input.is_action_just_pressed("attack_melee") \
					or Input.is_action_just_pressed("ui_accept"):
				if _col_cursor == 0:
					# 操作列：常に切替可（リーダーでなくても）
					if _member_cursor < _sorted_members.size():
						var ch := _sorted_members[_member_cursor] as Character
						if is_instance_valid(ch):
							var already := _controlled_char != null \
								and is_instance_valid(_controlled_char) \
								and ch == _controlled_char
							if not already:
								switch_requested.emit(ch)
								_controlled_char = ch
				else:
					# 1..5 列：リーダー操作中のみ値変更可
					if _is_editable():
						_cycle_member_col(_member_cursor, _col_cursor - 1, +1)
			elif Input.is_action_just_pressed("ui_cancel"):
				close_window()

		_FocusArea.CLOSE:
			if Input.is_action_just_pressed("ui_up"):
				if members_count > 0:
					_focus_area    = _FocusArea.MEMBER_TABLE
					_member_cursor = members_count - 1
				else:
					_focus_area = _FocusArea.GLOBAL_POLICY
			elif Input.is_action_just_pressed("attack_melee") \
					or Input.is_action_just_pressed("ui_accept"):
				close_window()
			elif Input.is_action_just_pressed("ui_cancel"):
				close_window()


## 操作中のキャラクターがパーティーリーダーなら true（指示変更可）
func _is_editable() -> bool:
	return _controlled_char != null \
		and is_instance_valid(_controlled_char) \
		and _controlled_char.is_leader


func _apply_preset(preset_index: int) -> void:
	_applied_policy = preset_index
	if _party == null:
		return
	var p: Array = PRESET_TABLE[preset_index]
	var is_explore := (preset_index == PRESETS.size() - 1)
	var sorted := _party.sorted_members()
	for mi: int in range(sorted.size()):
		var ch := sorted[mi] as Character
		if not is_instance_valid(ch):
			continue
		var move_val: String = p[2] as String
		if is_explore and mi > 0:
			move_val = "same_room"
		ch.current_order = {
			"combat":           p[0] as String,
			"battle_formation": p[1] as String,
			"move":             move_val,
			"target":           p[3] as String,
			"on_low_hp":        p[4] as String,
		}


func _cycle_member_col(member_index: int, col_param_index: int, dir: int) -> void:
	if member_index >= _sorted_members.size():
		return
	var ch := _sorted_members[member_index] as Character
	if not is_instance_valid(ch):
		return
	var key:  String = COL_KEYS[col_param_index]
	var opts: Array  = COL_OPTIONS[col_param_index] as Array
	var cur: int     = opts.find(ch.current_order.get(key, opts[0] as String))
	if cur < 0:
		cur = 0
	cur = (cur + dir + opts.size()) % opts.size()
	ch.current_order[key] = opts[cur] as String


func _get_col_label(ch: Character, col_param_index: int) -> String:
	var key:  String = COL_KEYS[col_param_index]
	var opts: Array  = COL_OPTIONS[col_param_index] as Array
	var lbls: Array  = COL_LABELS[col_param_index] as Array
	var val:  String = ch.current_order.get(key, opts[0] as String) as String
	var idx: int     = opts.find(val)
	if idx < 0:
		return val
	return lbls[idx] as String


# ── ステータスデータ ──────────────────────────────────────────────────────────

## ステータス表示用の行データを生成する
## 各要素: { "label", "type": "num"|"float"|"str"|"hp_mp", ... }
func _get_stat_rows(ch: Character) -> Array:
	var rows: Array = []
	if ch == null or ch.character_data == null:
		return rows
	var cd: CharacterData = ch.character_data

	rows.append({"label": "HP",           "type": "hp_mp",  "current": ch.hp,   "max": ch.max_hp})
	rows.append({"label": "MP",           "type": "hp_mp",  "current": ch.mp,   "max": ch.max_mp})
	rows.append({"label": "攻撃力",        "type": "num",    "base": ch.attack,  "bonus": 0})
	rows.append({"label": "防御力",        "type": "num",    "base": ch.defense, "bonus": 0})
	rows.append({"label": "攻撃タイプ",    "type": "str",
		"value": ATTACK_TYPE_LABELS.get(cd.attack_type, cd.attack_type) as String})
	rows.append({"label": "射程(タイル)",  "type": "num",    "base": cd.attack_range, "bonus": 0})
	if cd.heal_power > 0:
		rows.append({"label": "回復力",    "type": "num",    "base": cd.heal_power,   "bonus": 0})
	rows.append({"label": "攻撃溜め(秒)",  "type": "float",  "base": cd.pre_delay,    "bonus": 0.0})
	rows.append({"label": "攻撃硬直(秒)",  "type": "float",  "base": cd.post_delay,   "bonus": 0.0})
	rows.append({"label": "ランク",        "type": "str",    "value": cd.rank})
	rows.append({"label": "飛行",          "type": "str",
		"value": "あり" if cd.is_flying else "なし"})
	rows.append({"label": "統率力",        "type": "num",    "base": cd.leadership, "bonus": 0})
	rows.append({"label": "従順度",        "type": "float",  "base": cd.obedience,  "bonus": 0.0})
	return rows


## front.png → face.png の順で画像テクスチャを返す（キャッシュ付き）
func _get_char_front_texture(ch: Character) -> Texture2D:
	if ch == null or not is_instance_valid(ch) or ch.character_data == null:
		return null
	var cd := ch.character_data
	# sprite_front → sprite_face の順で試す（ファイルが存在しない場合も次を試す）
	for path: String in [cd.sprite_front, cd.sprite_face]:
		if path.is_empty():
			continue
		if _texture_cache.has(path):
			var cached: Variant = _texture_cache[path]
			if cached != null:
				return cached as Texture2D
			continue  # null キャッシュ = ファイル不在、次を試す
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			_texture_cache[path] = tex
			if tex != null:
				return tex
		_texture_cache[path] = null  # 不在をキャッシュ
	return null


## 現在選択中のキャラクターを返す（ステータスパネルに表示するキャラ）
func _get_selected_char() -> Character:
	if _focus_area == _FocusArea.MEMBER_TABLE and _member_cursor < _sorted_members.size():
		var ch := _sorted_members[_member_cursor] as Character
		if is_instance_valid(ch):
			return ch
	if _controlled_char != null and is_instance_valid(_controlled_char):
		return _controlled_char
	if not _sorted_members.is_empty():
		var ch := _sorted_members[0] as Character
		if is_instance_valid(ch):
			return ch
	return null


# ── 描画 ─────────────────────────────────────────────────────────────────────

func _on_draw() -> void:
	if not visible or _font == null or _party == null:
		return

	var vp       := _control.size
	var gs_f     := float(GlobalConstants.GRID_SIZE)
	var pw       := float(GlobalConstants.PANEL_TILES * GlobalConstants.GRID_SIZE)
	var field_w  := vp.x - pw * 2.0
	var field_cx := pw + field_w * 0.5

	var fs_title := maxi(16, int(gs_f * 0.19))
	var fs_label := maxi(13, int(gs_f * 0.16))
	var fs_body  := maxi(12, int(gs_f * 0.15))
	var fs_hint  := maxi(10, int(gs_f * 0.13))
	var fs_stat  := maxi(11, int(gs_f * 0.135))

	var pad      := maxf(18.0, gs_f * 0.20)
	var row_h    := maxf(26.0, gs_f * 0.28)
	var stat_h   := maxf(18.0, gs_f * 0.21)  # ステータス行の高さ（本文より小さめ）

	var member_count := _sorted_members.size()

	# ステータスセクションの事前計算
	var sel_ch    := _get_selected_char()
	var stat_rows := _get_stat_rows(sel_ch)
	var n_stat    := stat_rows.size()

	# ステータスセクション合計高さ
	var status_section_h := 0.0
	if sel_ch != null:
		status_section_h += 25.0                            # sep
		status_section_h += float(fs_stat) + stat_h        # タイトル＋列ヘッダー行
		status_section_h += float(n_stat) * stat_h         # ステータス行
		status_section_h += 25.0                            # sep
		status_section_h += float(fs_stat) + 6.0           # 装備タイトル
		status_section_h += 3.0 * stat_h                   # 武器・防具・盾
		status_section_h += 25.0                            # sep
		status_section_h += float(fs_stat) + 6.0           # アイテムタイトル
		status_section_h += stat_h + pad * 0.5             # （なし）＋下余白

	# ── パネルサイズ計算 ──────────────────────────────────────────────────────
	var panel_w := clampf(field_w * 0.90, 500.0, 960.0)
	var panel_h := pad
	panel_h += float(fs_title) + 10.0
	panel_h += 25.0                                        # sep
	panel_h += row_h + 8.0                                 # 全体方針行
	panel_h += 25.0                                        # sep
	panel_h += row_h                                       # ヘッダー行
	panel_h += float(member_count) * row_h + 8.0
	panel_h += 25.0                                        # sep
	panel_h += row_h                                       # 閉じるボタン
	panel_h += status_section_h
	panel_h += float(fs_hint) + pad                        # ヒント＋下余白

	var px := field_cx - panel_w * 0.5
	var py := vp.y * 0.5 - panel_h * 0.5

	# パネル背景・枠線
	_control.draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.06, 0.12, 0.97))
	_control.draw_rect(Rect2(px, py, panel_w, panel_h),
		Color(0.50, 0.50, 0.72, 0.90), false, 2)

	var y := py + pad

	# ── タイトル ─────────────────────────────────────────────────────────────
	var title_str := "パーティー指示"
	if not _is_editable():
		title_str += "  （閲覧のみ）"
	_control.draw_string(_font,
		Vector2(px + pad, y + float(fs_title)),
		title_str,
		HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0,
		fs_title, Color(0.88, 0.88, 1.00))
	y += float(fs_title) + 10.0
	_draw_sep(px, y, panel_w, pad)
	y += 13.0

	# ── 全体方針行 ────────────────────────────────────────────────────────────
	var is_policy := (_focus_area == _FocusArea.GLOBAL_POLICY)
	if is_policy:
		_control.draw_rect(Rect2(px + 4.0, y, panel_w - 8.0, row_h),
			Color(0.18, 0.24, 0.48, 0.70))

	_control.draw_string(_font,
		Vector2(px + pad, y + row_h * 0.66),
		"全体方針：",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, Color(0.78, 0.78, 0.92))

	var lw  := _font.get_string_size("全体方針：", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label).x
	var px2 := px + pad + lw + 6.0
	for pi: int in range(PRESETS.size()):
		var is_cur := is_policy and (pi == _policy_cursor)
		var is_app := (pi == _applied_policy)
		var col: Color
		if is_cur:   col = Color(1.0, 1.0, 0.3)
		elif is_app: col = Color(0.35, 1.0, 0.45)
		else:        col = Color(0.55, 0.55, 0.70)
		var txt := "[%s]" % PRESETS[pi] if (is_cur or is_app) else PRESETS[pi]
		_control.draw_string(_font, Vector2(px2, y + row_h * 0.66),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_body, col)
		px2 += _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_body).x + 10.0
	y += row_h + 8.0

	_draw_sep(px, y, panel_w, pad)
	y += 13.0

	# ── テーブル列位置計算 ────────────────────────────────────────────────────
	var col_xs := _get_col_xs(px, panel_w, pad)

	# ── ヘッダー行 ────────────────────────────────────────────────────────────
	_control.draw_string(_font, Vector2(col_xs[0], y + row_h * 0.66),
		"名前", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, Color(0.55, 0.55, 0.70))
	var op_h_col: Color = Color(1.0, 1.0, 0.3) \
		if (_focus_area == _FocusArea.MEMBER_TABLE and _col_cursor == 0) \
		else Color(0.55, 0.55, 0.70)
	_control.draw_string(_font, Vector2(col_xs[1], y + row_h * 0.66),
		"操作", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, op_h_col)
	for ci: int in range(COL_HEADERS.size()):
		var h_col: Color = Color(1.0, 1.0, 0.3) \
			if (_focus_area == _FocusArea.MEMBER_TABLE and ci + 1 == _col_cursor) \
			else Color(0.55, 0.55, 0.70)
		_control.draw_string(_font, Vector2(col_xs[ci + 2], y + row_h * 0.66),
			COL_HEADERS[ci], HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, h_col)
	y += row_h

	# ── メンバー行 ────────────────────────────────────────────────────────────
	for mi: int in range(_sorted_members.size()):
		var ch := _sorted_members[mi] as Character
		if not is_instance_valid(ch):
			continue

		var is_mem := (_focus_area == _FocusArea.MEMBER_TABLE) and (mi == _member_cursor)
		if is_mem:
			_control.draw_rect(Rect2(px + 4.0, y, panel_w - 8.0, row_h),
				Color(0.18, 0.24, 0.48, 0.70))

		var cd     := ch.character_data
		var nm_str := cd.character_name \
			if (cd != null and not cd.character_name.is_empty()) \
			else String(ch.name)
		var name_w := col_xs[1] - col_xs[0] - 4.0
		_control.draw_string(_font, Vector2(col_xs[0], y + row_h * 0.67),
			nm_str, HORIZONTAL_ALIGNMENT_LEFT, name_w, fs_body, Color.WHITE)

		var is_controlled: bool = _controlled_char != null \
			and is_instance_valid(_controlled_char) \
			and ch == _controlled_char
		var op_focused := is_mem and (_col_cursor == 0)
		var op_txt: String
		if is_controlled:
			op_txt = "[操作中]"
		elif op_focused:
			op_txt = "▶[切替]"
		else:
			op_txt = "[切替]"
		var op_color: Color
		if is_controlled:
			op_color = Color(0.45, 1.0, 0.55)
		elif op_focused:
			op_color = Color(1.0, 1.0, 0.3)
		else:
			op_color = Color(0.80, 0.80, 0.80)
		var op_w := col_xs[2] - col_xs[1] - 4.0
		_control.draw_string(_font, Vector2(col_xs[1], y + row_h * 0.67),
			op_txt, HORIZONTAL_ALIGNMENT_LEFT, op_w, fs_body, op_color)

		for ci: int in range(COL_HEADERS.size()):
			var lbl     := _get_col_label(ch, ci)
			var focused := is_mem and (ci + 1 == _col_cursor)
			var c_col: Color = Color(1.0, 1.0, 0.3) if focused else Color(0.80, 0.80, 0.80)
			var txt2    := "◀%s▶" % lbl if focused else lbl
			var col_w: float
			if ci + 3 < col_xs.size():
				col_w = col_xs[ci + 3] - col_xs[ci + 2] - 4.0
			else:
				col_w = px + panel_w - pad - col_xs[ci + 2]
			_control.draw_string(_font, Vector2(col_xs[ci + 2], y + row_h * 0.67),
				txt2, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs_body, c_col)

		y += row_h
	y += 8.0

	_draw_sep(px, y, panel_w, pad)
	y += 13.0

	# ── 閉じるボタン ──────────────────────────────────────────────────────────
	var is_close := (_focus_area == _FocusArea.CLOSE)
	if is_close:
		_control.draw_rect(Rect2(px + 4.0, y, panel_w - 8.0, row_h),
			Color(0.18, 0.24, 0.48, 0.70))
	var c_col2 := Color(1.0, 1.0, 0.3) if is_close else Color(0.68, 0.68, 0.82)
	var c_txt  := "▶  閉じる" if is_close else "    閉じる"
	var c_tw   := _font.get_string_size(c_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_body).x
	_control.draw_string(_font,
		Vector2(px + panel_w * 0.5 - c_tw * 0.5, y + row_h * 0.67),
		c_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_body, c_col2)
	y += row_h

	# ── ステータスパネル（下部） ───────────────────────────────────────────────
	if sel_ch != null:
		_draw_status_section(px, y, panel_w, pad, sel_ch, stat_rows, stat_h, fs_stat)

	# ── 操作ヒント ────────────────────────────────────────────────────────────
	var hint_str := "↑↓:行移動  ←→:列/方針切替  Z/Enter:切替/値切替  Tab/Esc:閉じる"
	if not _is_editable():
		hint_str = "↑↓:行移動  ←→:列移動  Z/Enter:操作切替  Tab/Esc:閉じる（閲覧のみ）"
	_control.draw_string(_font,
		Vector2(px + pad, py + panel_h - float(fs_hint) - pad * 0.45),
		hint_str,
		HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_hint,
		Color(0.46, 0.46, 0.56))


## ステータス詳細・装備・アイテムセクションを描画する（左：front画像 / 右：ステータス数値）
func _draw_status_section(px: float, y_start: float, panel_w: float, pad: float,
		ch: Character, stat_rows: Array, stat_h: float, fs_stat: int) -> void:
	var y     := y_start
	var avail := panel_w - pad * 2.0

	# ── 左右分割レイアウト ────────────────────────────────────────────────────
	# 左列: front画像（最大 180px 正方形）
	# 右列: ステータス数値テーブル
	var img_col_w := minf(avail * 0.22, 180.0)
	var col_gap   := pad
	var stats_x0  := px + pad + img_col_w + col_gap
	var stats_avail := px + panel_w - pad - stats_x0

	# ステータス列 X 座標（ラベル 48%、素値 17%、補正値 17%、最終値 18%）
	var lbl_x   := stats_x0
	var base_x  := stats_x0 + stats_avail * 0.48
	var bonus_x := stats_x0 + stats_avail * 0.65
	var final_x := stats_x0 + stats_avail * 0.82

	var c_head  := Color(0.80, 0.80, 1.00)
	var c_lbl   := Color(0.65, 0.65, 0.80)
	var c_val   := Color(0.90, 0.90, 0.95)
	var c_bonus := Color(0.50, 0.55, 0.70)
	var c_dim   := Color(0.42, 0.42, 0.58)

	# ── ステータス区切り ──────────────────────────────────────────────────────
	_draw_sep(px, y, panel_w, pad)
	y += 13.0

	var cd    := ch.character_data
	var cname := (cd.character_name \
		if (cd != null and not cd.character_name.is_empty()) \
		else String(ch.name))

	# ── 左側: front / face 画像 ───────────────────────────────────────────────
	var tex := _get_char_front_texture(ch)
	if tex != null:
		_control.draw_texture_rect(tex,
			Rect2(px + pad, y, img_col_w, img_col_w), false)
	else:
		# プレースホルダー（キャラカラーを暗くして表示）
		var ph_col := ch.placeholder_color \
			if (is_instance_valid(ch) and ch.placeholder_color != Color.BLACK) \
			else Color(0.30, 0.30, 0.45)
		_control.draw_rect(Rect2(px + pad, y, img_col_w, img_col_w),
			Color(ph_col.r * 0.5, ph_col.g * 0.5, ph_col.b * 0.5, 0.85))

	# ── 右側: タイトル + 列ヘッダー ───────────────────────────────────────────
	_control.draw_string(_font, Vector2(lbl_x, y + float(fs_stat)),
		"ステータス：" + cname,
		HORIZONTAL_ALIGNMENT_LEFT, stats_avail, fs_stat, c_head)
	_control.draw_string(_font, Vector2(base_x,  y + float(fs_stat)),
		"素値",  HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)
	_control.draw_string(_font, Vector2(bonus_x, y + float(fs_stat)),
		"補正値", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)
	_control.draw_string(_font, Vector2(final_x, y + float(fs_stat)),
		"最終値", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)
	y += float(fs_stat) + stat_h

	# ── 右側: ステータス行 ────────────────────────────────────────────────────
	for row_v: Variant in stat_rows:
		var row   := row_v as Dictionary
		var label : String = row.get("label", "") as String
		var rtype : String = row.get("type",  "str") as String

		_control.draw_string(_font, Vector2(lbl_x, y + stat_h * 0.75),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_lbl)

		match rtype:
			"hp_mp":
				var cur : int = row.get("current", 0) as int
				var mx  : int = row.get("max",     0) as int
				var ratio := float(cur) / float(mx) if mx > 0 else 1.0
				var vc := Color(1.0, 0.25, 0.25)
				if   ratio > 0.6: vc = c_val
				elif ratio > 0.3: vc = Color(1.0, 0.95, 0.30)
				elif ratio > 0.1: vc = Color(1.0, 0.60, 0.20)
				_control.draw_string(_font, Vector2(base_x, y + stat_h * 0.75),
					"%d / %d" % [cur, mx],
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, vc)
			"num":
				var base  : int = row.get("base",  0) as int
				var bonus : int = row.get("bonus", 0) as int
				var final_v := base + bonus
				var fc := Color(1.0, 1.0, 0.55) if bonus != 0 else c_val
				_control.draw_string(_font, Vector2(base_x,  y + stat_h * 0.75),
					str(base),           HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_val)
				_control.draw_string(_font, Vector2(bonus_x, y + stat_h * 0.75),
					"%+d" % bonus,       HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_bonus)
				_control.draw_string(_font, Vector2(final_x, y + stat_h * 0.75),
					"→ " + str(final_v), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, fc)
			"float":
				var base  : float = row.get("base",  0.0) as float
				var bonus : float = row.get("bonus", 0.0) as float
				var final_v := base + bonus
				var fc := Color(1.0, 1.0, 0.55) if bonus != 0.0 else c_val
				_control.draw_string(_font, Vector2(base_x,  y + stat_h * 0.75),
					"%.2f" % base,       HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_val)
				_control.draw_string(_font, Vector2(bonus_x, y + stat_h * 0.75),
					"%+.2f" % bonus,     HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_bonus)
				_control.draw_string(_font, Vector2(final_x, y + stat_h * 0.75),
					"→ %.2f" % final_v, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, fc)
			"str":
				var val: String = row.get("value", "") as String
				_control.draw_string(_font, Vector2(base_x, y + stat_h * 0.75),
					val, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_val)

		y += stat_h

	# 画像の下端まで y を進める（画像がステータス行より長い場合）
	var img_bottom := y_start + 13.0 + img_col_w
	if y < img_bottom:
		y = img_bottom

	# ── 装備 ─────────────────────────────────────────────────────────────────
	_draw_sep(px, y, panel_w, pad)
	y += 13.0
	_control.draw_string(_font, Vector2(lbl_x, y + float(fs_stat)),
		"装備", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_head)
	y += float(fs_stat) + 6.0
	for slot: String in ["武器", "防具", "盾"]:
		_control.draw_string(_font, Vector2(lbl_x,  y + stat_h * 0.75),
			slot, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_lbl)
		_control.draw_string(_font, Vector2(base_x, y + stat_h * 0.75),
			"（なし）", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)
		y += stat_h

	# ── 所持アイテム ──────────────────────────────────────────────────────────
	_draw_sep(px, y, panel_w, pad)
	y += 13.0
	_control.draw_string(_font, Vector2(lbl_x, y + float(fs_stat)),
		"所持アイテム", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_head)
	y += float(fs_stat) + 6.0
	_control.draw_string(_font, Vector2(lbl_x, y + stat_h * 0.75),
		"（なし）", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)


# ── ユーティリティ ────────────────────────────────────────────────────────────

func _get_col_xs(px: float, panel_w: float, pad: float) -> Array[float]:
	var avail     := panel_w - pad * 2.0
	var name_r    := 0.18
	var control_r := 0.10
	var item_r    := (1.0 - name_r - control_r) / float(COL_HEADERS.size())
	var xs: Array[float] = []
	xs.append(px + pad)
	xs.append(px + pad + avail * name_r)
	for ci: int in range(COL_HEADERS.size()):
		xs.append(px + pad + avail * (name_r + control_r + item_r * float(ci)))
	return xs


func _draw_sep(px: float, y: float, panel_w: float, pad: float) -> void:
	_control.draw_line(
		Vector2(px + pad, y),
		Vector2(px + panel_w - pad, y),
		Color(0.35, 0.35, 0.55, 0.65), 1)
