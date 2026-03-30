class_name OrderWindow
extends CanvasLayer

## パーティー指示ウィンドウ（刷新版）
## Tab キーで開閉。全体方針プリセット + 5項目個別設定 + 操作キャラ切替。
## 操作:
##   全体方針行: ←→ でプリセット選択, Z/Enter で全メンバーに適用
##   メンバー行: ↑↓ で行移動, ←→ で列移動, Z で値を切替（操作列は切替発動）
##   閉じる行:  Z/Enter または Esc で閉じる

signal closed()
## 操作キャラの切替を要求する（game_map が受け取って実際の切替を行う）
signal switch_requested(new_character: Character)

# ── 定数 ─────────────────────────────────────────────────────────────────────

## 全体方針プリセット名
const PRESETS: Array[String] = ["攻撃", "防衛", "待機", "追従", "撤退", "探索"]

## プリセット → [combat, battle_formation, move, target, on_low_hp]
## 探索（index=5）: move はリーダーのみ "explore"、他メンバーは "same_room" に上書きする
const PRESET_TABLE: Array = [
	["aggressive", "surround", "same_room", "nearest",        "keep_fighting"], # 攻撃
	["support",    "surround", "cluster",   "same_as_leader", "retreat"],        # 防衛
	["standby",    "surround", "cluster",   "nearest",        "retreat"],        # 待機
	["support",    "surround", "cluster",   "same_as_leader", "retreat"],        # 追従
	["standby",    "surround", "cluster",   "nearest",        "flee"],           # 撤退
	["aggressive", "surround", "explore",   "nearest",        "retreat"],        # 探索
]

## 5項目の内部値一覧（COL_KEYS 順）
const COL_OPTIONS: Array = [
	["explore", "same_room", "cluster", "guard_room", "standby"], # move
	["surround", "front", "rear", "same_as_leader"],              # battle_formation
	["aggressive", "support", "standby"],                          # combat
	["nearest", "weakest", "same_as_leader"],                     # target
	["keep_fighting", "retreat", "flee"],                          # on_low_hp
]

## 5項目の表示ラベル（COL_KEYS 順）
const COL_LABELS: Array = [
	["探索", "同じ部屋", "密集", "部屋守る", "待機"],             # move
	["包囲", "前衛", "後衛", "リーダーと同じ"],                   # battle_formation
	["積極攻撃", "援護", "待機"],                                  # combat
	["最近傍", "最弱", "リーダーと同じ"],                         # target
	["戦い続ける", "後退", "逃走"],                               # on_low_hp
]

## テーブルヘッダー文字列（5項目のみ。操作列は別途描画）
const COL_HEADERS: Array[String] = ["移動", "隊形", "戦闘", "ターゲット", "低HP"]

## 5項目のキー名（current_order のキー順）
const COL_KEYS: Array[String] = ["move", "battle_formation", "combat", "target", "on_low_hp"]

## 列数合計（0=操作、1..5=5項目）
const TOTAL_COLS := 6

# ── 内部状態 ──────────────────────────────────────────────────────────────────

enum _FocusArea { GLOBAL_POLICY, MEMBER_TABLE, CLOSE }

var _party:          Party
var _focus_area:     _FocusArea = _FocusArea.GLOBAL_POLICY
var _policy_cursor:  int = 0   ## 全体方針カーソル（0〜4）
var _applied_policy: int = -1  ## 最後に適用したプリセット
var _member_cursor:  int = 0   ## メンバー行カーソル
var _col_cursor:     int = 1   ## 列カーソル（0=操作, 1..4=4項目）

## 現在プレイヤーが操作中のキャラクター（"操作中" / "切替" 表示に使用）
var _controlled_char: Character = null

## 毎フレーム更新するソート済みメンバーキャッシュ
var _sorted_members: Array = []

var _control: Control
var _font:    Font


# ── セットアップ ──────────────────────────────────────────────────────────────

func setup(party: Party) -> void:
	_party = party


## 現在操作中のキャラクターをセットする（切替後に game_map から呼ばれる）
func set_controlled(ch: Character) -> void:
	_controlled_char = ch


# ── 開閉 ─────────────────────────────────────────────────────────────────────

func open_window() -> void:
	if _party == null:
		return
	_focus_area    = _FocusArea.GLOBAL_POLICY
	_policy_cursor = 0
	_member_cursor = 0
	_col_cursor    = 1   # 戦闘列をデフォルトフォーカス
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
				_apply_preset(_policy_cursor)
			elif Input.is_action_just_pressed("ui_down"):
				if members_count > 0:
					_focus_area    = _FocusArea.MEMBER_TABLE
					_member_cursor = 0
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
					# 操作列：選択しているメンバーへ操作キャラを切り替える
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
					# 1..4 列：値を1段階進める（param index は col - 1）
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


## 全体方針プリセットを全メンバーに適用する
## 探索（index=5）: パーティーリーダーのみ move=explore、他は move=same_room
func _apply_preset(preset_index: int) -> void:
	_applied_policy = preset_index
	if _party == null:
		return
	var p: Array = PRESET_TABLE[preset_index]
	var is_explore := (preset_index == PRESETS.size() - 1)  # 探索プリセット
	var sorted := _party.sorted_members()
	for mi: int in range(sorted.size()):
		var ch := sorted[mi] as Character
		if not is_instance_valid(ch):
			continue
		var move_val: String = p[2] as String
		if is_explore and mi > 0:
			move_val = "same_room"  # リーダー以外は同室追従
		ch.current_order = {
			"combat":           p[0] as String,
			"battle_formation": p[1] as String,
			"move":             move_val,
			"target":           p[3] as String,
			"on_low_hp":        p[4] as String,
		}


## 指定メンバー（sorted_members インデックス）の指定パラメーター列の値を1段階進める
## col_param_index: 0=move, 1=battle_formation, 2=combat, 3=target, 4=on_low_hp
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


## 指定キャラの指定パラメーター列（0..3）の現在の表示ラベルを返す
func _get_col_label(ch: Character, col_param_index: int) -> String:
	var key:  String = COL_KEYS[col_param_index]
	var opts: Array  = COL_OPTIONS[col_param_index] as Array
	var lbls: Array  = COL_LABELS[col_param_index] as Array
	var val:  String = ch.current_order.get(key, opts[0] as String) as String
	var idx: int     = opts.find(val)
	if idx < 0:
		return val
	return lbls[idx] as String


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

	var pad   := maxf(18.0, gs_f * 0.20)
	var row_h := maxf(26.0, gs_f * 0.28)

	var member_count := _sorted_members.size()

	# ── パネルサイズ計算 ──────────────────────────────────────────────────────
	var panel_w := clampf(field_w * 0.90, 500.0, 960.0)
	var panel_h := pad
	panel_h += float(fs_title) + 10.0          # タイトル
	panel_h += 12.0 + 1.0 + 12.0              # セパレーター
	panel_h += row_h + 8.0                    # 全体方針行
	panel_h += 12.0 + 1.0 + 12.0              # セパレーター
	panel_h += row_h                           # ヘッダー行
	panel_h += float(member_count) * row_h + 8.0
	panel_h += 12.0 + 1.0 + 12.0              # セパレーター
	panel_h += row_h                           # 閉じるボタン
	panel_h += float(fs_hint) + pad           # ヒント・下余白

	var px := field_cx - panel_w * 0.5
	var py := vp.y * 0.5 - panel_h * 0.5

	# パネル背景・枠線
	_control.draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.06, 0.12, 0.97))
	_control.draw_rect(Rect2(px, py, panel_w, panel_h),
		Color(0.50, 0.50, 0.72, 0.90), false, 2)

	var y := py + pad

	# ── タイトル ─────────────────────────────────────────────────────────────
	_control.draw_string(_font,
		Vector2(px + pad, y + float(fs_title)),
		"パーティー指示",
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
	# 列: [名前, 操作, 移動, 隊形, 戦闘, ターゲット, 低HP]
	# 名前18%, 操作10%, 各5項目 (72%/5=14.4%)
	var col_xs := _get_col_xs(px, panel_w, pad)

	# ── ヘッダー行 ────────────────────────────────────────────────────────────
	_control.draw_string(_font, Vector2(col_xs[0], y + row_h * 0.66),
		"名前", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, Color(0.55, 0.55, 0.70))
	# 操作列ヘッダー
	var op_h_col: Color = Color(1.0, 1.0, 0.3) \
		if (_focus_area == _FocusArea.MEMBER_TABLE and _col_cursor == 0) \
		else Color(0.55, 0.55, 0.70)
	_control.draw_string(_font, Vector2(col_xs[1], y + row_h * 0.66),
		"操作", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, op_h_col)
	# 4項目ヘッダー
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

		# 名前
		var cd     := ch.character_data
		var nm_str := cd.character_name \
			if (cd != null and not cd.character_name.is_empty()) \
			else String(ch.name)
		var name_w := col_xs[1] - col_xs[0] - 4.0
		_control.draw_string(_font, Vector2(col_xs[0], y + row_h * 0.67),
			nm_str, HORIZONTAL_ALIGNMENT_LEFT, name_w, fs_body, Color.WHITE)

		# 操作列
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
			op_color = Color(0.45, 1.0, 0.55)   # 緑：操作中
		elif op_focused:
			op_color = Color(1.0, 1.0, 0.3)     # 黄：フォーカス中
		else:
			op_color = Color(0.80, 0.80, 0.80)
		var op_w := col_xs[2] - col_xs[1] - 4.0
		_control.draw_string(_font, Vector2(col_xs[1], y + row_h * 0.67),
			op_txt, HORIZONTAL_ALIGNMENT_LEFT, op_w, fs_body, op_color)

		# 4項目列
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

	# ── 操作ヒント ────────────────────────────────────────────────────────────
	_control.draw_string(_font,
		Vector2(px + pad, py + panel_h - float(fs_hint) - pad * 0.45),
		"↑↓:行移動  ←→:列/方針切替  Z/Enter:切替/値切替  Tab/Esc:閉じる",
		HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_hint,
		Color(0.46, 0.46, 0.56))


## 列のX座標配列を返す: [名前, 操作, 移動, 隊形, 戦闘, ターゲット, 低HP]（7要素）
func _get_col_xs(px: float, panel_w: float, pad: float) -> Array[float]:
	var avail     := panel_w - pad * 2.0
	var name_r    := 0.18   # 名前列
	var control_r := 0.10   # 操作列
	# 残り (0.72) を COL_HEADERS.size()=5 で均等分割
	var item_r := (1.0 - name_r - control_r) / float(COL_HEADERS.size())
	var xs: Array[float] = []
	xs.append(px + pad)                                      # [0] 名前
	xs.append(px + pad + avail * name_r)                     # [1] 操作
	for ci: int in range(COL_HEADERS.size()):                # [2..6] 5項目
		xs.append(px + pad + avail * (name_r + control_r + item_r * float(ci)))
	return xs


func _draw_sep(px: float, y: float, panel_w: float, pad: float) -> void:
	_control.draw_line(
		Vector2(px + pad, y),
		Vector2(px + panel_w - pad, y),
		Color(0.35, 0.35, 0.55, 0.65), 1)
