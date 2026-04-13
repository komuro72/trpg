## デバッグウィンドウ（F1キーで表示/非表示トグル）
## 上半分：現在フロアの全パーティー状態をリアルタイム表示
## 下半分：combat/ai ログ（最新50件）

class_name DebugWindow
extends CanvasLayer

const LOG_MAX:  int   = 50
const FS:       int   = 12        ## フォントサイズ
const HDR_FS:   int   = 14        ## ヘッダー用フォントサイズ
const LINE_H:   float = 15.0      ## 1行の高さ
const PAD:      float = 8.0       ## 外側パディング
const INDENT:   float = 14.0      ## メンバー行インデント

## combat / ai ログ（debug_log_added シグナル経由で追加）
var _log_entries: Array[Dictionary] = []  ## { "text": String, "color": Color }

## 参照（game_map から setup() で設定）
var _party:               Party     = null
var _get_enemy_managers:  Callable           ## () -> Array
var _get_npc_managers:    Callable           ## () -> Array
var _get_floor:           Callable           ## () -> int
var _get_map_data:        Callable           ## () -> MapData
var _hero:                Character = null

var _control:       Control
var _redraw_timer:  float = 0.0
const REDRAW_INTERVAL: float = 0.20  ## パーティー状態の再描画間隔（秒）

## リーダー選択（修正2）
var _selected_leader: Character = null  ## 選択中のリーダーキャラ（null=未選択）
var _leader_list: Array = []            ## 描画順のリーダーキャラ一覧（毎描画フレームで更新）

## リーダー選択が変わったとき発火（game_map がカメラを切り替えるために購読）
signal leader_selected(leader: Character)


func _ready() -> void:
	layer = 15
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_control = Control.new()
	_control.name = "DebugPanel"
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control.draw.connect(_on_draw)
	add_child(_control)

	if MessageLog != null:
		MessageLog.debug_log_added.connect(_on_debug_log_added)


## game_map から呼ぶ。Callable を渡すことで常に最新のフロアデータを参照できる
func setup(p_party: Party, get_enemy_managers: Callable, get_npc_managers: Callable,
		get_floor: Callable, get_map_data: Callable, p_hero: Character) -> void:
	_party              = p_party
	_get_enemy_managers = get_enemy_managers
	_get_npc_managers   = get_npc_managers
	_get_floor          = get_floor
	_get_map_data       = get_map_data
	_hero               = p_hero


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key: int = (event as InputEventKey).physical_keycode
		if key == KEY_UP:
			_navigate_selection(-1)
			get_viewport().set_input_as_handled()
		elif key == KEY_DOWN:
			_navigate_selection(1)
			get_viewport().set_input_as_handled()


## リーダー一覧内でカーソルを移動する。_leader_list は前回の描画で構築済み
func _navigate_selection(dir: int) -> void:
	# freed なエントリを除去
	_leader_list = _leader_list.filter(func(c: Variant) -> bool:
		return c != null and is_instance_valid(c))
	if _leader_list.is_empty():
		return
	var idx: int = _leader_list.find(_selected_leader)
	if idx < 0:
		idx = 0 if dir > 0 else _leader_list.size() - 1
	else:
		idx = (idx + dir + _leader_list.size()) % _leader_list.size()
	_selected_leader = _leader_list[idx] as Character
	leader_selected.emit(_selected_leader)
	_control.queue_redraw()


## ウィンドウを閉じるときに選択をリセットする（game_map から呼ぶ）
func clear_selection() -> void:
	_selected_leader = null
	_leader_list.clear()
	leader_selected.emit(null)


func _process(delta: float) -> void:
	if not visible:
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		_control.queue_redraw()


func _on_debug_log_added(text: String, color: Color) -> void:
	_log_entries.append({"text": text, "color": color})
	if _log_entries.size() > LOG_MAX:
		_log_entries = _log_entries.slice(_log_entries.size() - LOG_MAX)
	if visible:
		_control.queue_redraw()


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------

func _on_draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = _control.get_viewport_rect().size
	var px: float = vp.x * 0.15
	var py: float = vp.y * 0.10
	var pw: float = vp.x * 0.70
	var ph: float = vp.y * 0.80

	# 背景パネルなし（完全透過）

	# 描画前にリーダー一覧を構築（上下キー選択用）
	_leader_list = _build_leader_list()

	# 表示フロアを決定：選択中リーダーのフロア > プレイヤーのフロア
	var player_floor: int = int(_get_floor.call()) if _get_floor.is_valid() else 0
	var display_floor: int = player_floor
	if _selected_leader != null and is_instance_valid(_selected_leader):
		display_floor = _selected_leader.current_floor

	# タイトル行
	var title: String
	if display_floor != player_floor:
		title = "■ DEBUG WINDOW  [F1で閉じる]  Player:F%d  表示:F%d" % [player_floor, display_floor]
	else:
		title = "■ DEBUG WINDOW  [F1で閉じる]  Floor: %d" % player_floor
	_control.draw_string(font, Vector2(px + PAD, py + PAD + HDR_FS),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, HDR_FS, Color(0.8, 0.8, 1.0))

	var title_bottom: float = py + HDR_FS + PAD * 2.5
	_control.draw_line(Vector2(px, title_bottom), Vector2(px + pw, title_bottom),
		Color(0.45, 0.55, 0.85, 0.5), 1.0)

	# コンテンツ領域
	var c_top: float = title_bottom + 2.0
	var c_h: float   = ph - (title_bottom - py) - 2.0
	var div_y: float = c_top + c_h * 0.55  # 上55%：パーティー状態

	# 上半分：パーティー状態（表示フロアを引数で渡す）
	_draw_party_state(font, px + PAD, c_top + 2.0, pw - PAD * 2, div_y - c_top - 4.0, display_floor)

	# 区切り線
	_control.draw_line(Vector2(px + PAD, div_y), Vector2(px + pw - PAD, div_y),
		Color(0.45, 0.55, 0.85, 0.5), 1.0)

	# 下半分：ログ
	_draw_log(font, px + PAD, div_y + 4.0, pw - PAD * 2, (py + ph) - div_y - 8.0)


# --------------------------------------------------------------------------
# パーティー状態
# --------------------------------------------------------------------------

func _draw_party_state(font: Font, x: float, y_start: float,
		w: float, h: float, floor_idx: int) -> void:
	var cy: float  = y_start
	var bottom: float = y_start + h

	var ems: Array = _get_enemy_managers.call() if _get_enemy_managers.is_valid() else []
	var nms: Array = _get_npc_managers.call()   if _get_npc_managers.is_valid()   else []

	# 敵パーティー
	for em_v: Variant in ems:
		if cy >= bottom:
			break
		var em := em_v as PartyManager
		if em == null or not is_instance_valid(em):
			continue
		cy = _draw_party_block(font, em, "敵", Color(1.0, 0.45, 0.45),
				x, cy, w, bottom, floor_idx, false)

	# NPC パーティー
	for nm_v: Variant in nms:
		if cy >= bottom:
			break
		var nm := nm_v as NpcManager
		if nm == null or not is_instance_valid(nm):
			continue
		cy = _draw_party_block(font, nm, "NPC", Color(0.45, 1.0, 0.55),
				x, cy, w, bottom, floor_idx, true)

	# プレイヤーパーティー
	if _party != null and cy < bottom:
		_draw_player_party(font, x, cy, w, bottom, floor_idx)


## 描画順のリーダーキャラ一覧を構築する（上下キー選択の対象リスト）
## 全フロアのリーダーを含む（フロアをまたいだナビゲーションに対応）
func _build_leader_list() -> Array:
	var list: Array = []
	var ems: Array = _get_enemy_managers.call() if _get_enemy_managers.is_valid() else []
	var nms: Array = _get_npc_managers.call()   if _get_npc_managers.is_valid()   else []
	for em_v: Variant in ems:
		var em := em_v as PartyManager
		if em == null or not is_instance_valid(em):
			continue
		var leader := _get_any_leader(em.get_members())
		if leader != null:
			list.append(leader)
	for nm_v: Variant in nms:
		var nm := nm_v as NpcManager
		if nm == null or not is_instance_valid(nm):
			continue
		var leader := _get_any_leader(nm.get_members())
		if leader != null:
			list.append(leader)
	if _party != null:
		var leader := _get_any_leader(_party.sorted_members())
		if leader != null:
			list.append(leader)
	return list


## メンバーリストから生存中の先頭キャラを返す（フロア不問）
func _get_any_leader(members: Array) -> Character:
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m) and m.hp > 0:
			return m
	return null


## メンバーリストから指定フロアの先頭キャラを返す（旧互換・未使用になる可能性あり）
func _get_floor_leader(members: Array, floor_idx: int) -> Character:
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m) and m.current_floor == floor_idx:
			return m
	return null


## show_orders: false=敵（item 列を省略）、true=NPC/プレイヤー（全列表示）
func _draw_party_block(font: Font, pm: PartyManager, type_label: String,
		header_color: Color, x: float, y: float, w: float, bottom: float,
		floor_idx: int, show_orders: bool) -> float:
	var members: Array[Character] = pm.get_members()
	if members.is_empty():
		return y

	# 現在フロアのメンバーのみ対象
	var floor_members: Array[Character] = []
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m) and m.current_floor == floor_idx:
			floor_members.append(m)
	if floor_members.is_empty():
		return y

	# 生存数カウント（フロア内のみ）
	var alive: int = 0
	for m: Character in floor_members:
		if m.hp > 0:
			alive += 1

	# リーダー名・クラス
	var leader_name: String = ""
	var first_class: String = ""
	if not floor_members.is_empty():
		var first: Character = floor_members[0]
		if is_instance_valid(first) and first.character_data != null:
			leader_name = first.character_data.character_name
			first_class = GlobalConstants.CLASS_NAME_JP.get(first.character_data.class_id, "")

	# 全体指示ヒント
	var hint: Dictionary = pm.get_global_orders_hint()
	var mv_raw:     String = hint.get("move", "-") as String
	var mv_str:     String = _label("move", mv_raw)
	# 階段移動中は目標フロアを付加表示
	if mv_raw == "stairs_down" or mv_raw == "stairs_up":
		var tgt_f: String = hint.get("target_floor", "?") as String
		mv_str += "(F" + tgt_f + ")"
	var battle_str: String = _label("battle_policy", hint.get("battle_policy", "-") as String)
	var tgt_str:    String = _label("target",        hint.get("target",        "-") as String)
	var hp_str:     String = _label("on_low_hp",     hint.get("on_low_hp",     "-") as String)

	var header: String
	if show_orders:
		var item_str: String = _label("item_pickup", hint.get("item_pickup", "-") as String)
		header = "[%s] %s(%s)  生存:%d/%d  mv=%s  battle=%s  tgt=%s  hp=%s  item=%s" % [
			type_label, leader_name, first_class, alive, floor_members.size(),
			mv_str, battle_str, tgt_str, hp_str, item_str]
	else:
		header = "[%s] %s(%s)  生存:%d/%d  mv=%s  battle=%s  tgt=%s  hp=%s" % [
			type_label, leader_name, first_class, alive, floor_members.size(),
			mv_str, battle_str, tgt_str, hp_str]

	# ヘッダーが描画可能か確認
	if y + LINE_H > bottom:
		return y

	# 選択中リーダーの「▶」マーカー
	var leader_char: Character = floor_members[0] if not floor_members.is_empty() else null
	var is_selected: bool = (leader_char != null and _selected_leader != null
		and is_instance_valid(_selected_leader) and _selected_leader == leader_char)
	if is_selected:
		_control.draw_string(font, Vector2(x - INDENT, y + FS), "▶",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(1.0, 1.0, 0.3))
	_control.draw_string(font, Vector2(x, y + FS), header,
		HORIZONTAL_ALIGNMENT_LEFT, w - INDENT, FS, header_color)
	y += LINE_H

	# メンバー全員を1行に横並び表示
	if y < bottom:
		_draw_members_row(font, floor_members, x + INDENT, y, w - INDENT * 2)
		y += LINE_H

	return y + 2.0


func _draw_player_party(font: Font, x: float, y: float, w: float, bottom: float,
		floor_idx: int) -> float:
	if y >= bottom or _party == null:
		return y

	# 現在フロアのメンバーのみ対象
	var sorted: Array = _party.sorted_members()
	var floor_members: Array = []
	for m_v: Variant in sorted:
		var m := m_v as Character
		if is_instance_valid(m) and m.current_floor == floor_idx:
			floor_members.append(m)

	if floor_members.is_empty():
		return y

	var alive: int = 0
	for m_v: Variant in floor_members:
		var m := m_v as Character
		if m.hp > 0:
			alive += 1

	# リーダー名・クラス
	var leader_name: String = ""
	var first_class: String = ""
	var first_m := floor_members[0] as Character
	if is_instance_valid(first_m) and first_m.character_data != null:
		leader_name = first_m.character_data.character_name
		first_class = GlobalConstants.CLASS_NAME_JP.get(first_m.character_data.class_id, "")

	# 全体指示（party.global_orders を直接参照）
	var go: Dictionary = _party.global_orders
	var mv_str:     String = _label("move",          go.get("move",          "-") as String)
	var battle_str: String = _label("battle_policy", go.get("battle_policy", "-") as String)
	var tgt_str:    String = _label("target",        go.get("target",        "-") as String)
	var hp_str:     String = _label("on_low_hp",     go.get("on_low_hp",     "-") as String)
	var item_str:   String = _label("item_pickup",   go.get("item_pickup",   "-") as String)

	var header := "[プレイヤー] %s(%s)  生存:%d/%d  mv=%s  battle=%s  tgt=%s  hp=%s  item=%s" % [
		leader_name, first_class, alive, floor_members.size(),
		mv_str, battle_str, tgt_str, hp_str, item_str]
	if y + LINE_H > bottom:
		return y

	var player_leader: Character = floor_members[0] as Character if not floor_members.is_empty() else null
	var is_selected: bool = (player_leader != null and _selected_leader != null
		and is_instance_valid(_selected_leader) and _selected_leader == player_leader)
	if is_selected:
		_control.draw_string(font, Vector2(x - INDENT, y + FS), "▶",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(1.0, 1.0, 0.3))
	_control.draw_string(font, Vector2(x, y + FS), header,
		HORIZONTAL_ALIGNMENT_LEFT, w - INDENT, FS, Color(0.45, 0.75, 1.0))
	y += LINE_H

	# メンバー全員を1行に横並び表示
	if y < bottom:
		_draw_members_row(font, floor_members, x + INDENT, y, w - INDENT * 2)
		y += LINE_H

	return y + 2.0


## メンバー全員を1行に横並びで描画する
## 各メンバー：★名前[ランク] HP:x/y [ス][ガ]  （幅を超えたら打ち切り）
func _draw_members_row(font: Font, members: Array, x: float, y: float, w: float) -> void:
	var cx: float = x
	const SEP: String = "  "
	var sep_w: float = font.get_string_size(SEP, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x

	for i: int in range(members.size()):
		var m_v: Variant = members[i]
		var m := m_v as Character
		if not is_instance_valid(m):
			continue

		# HP比率で色分け
		var hp_pct: float = float(m.hp) / float(m.max_hp) if m.max_hp > 0 else 0.0
		var col: Color
		if hp_pct > 0.5:    col = Color(0.85, 0.85, 0.85)
		elif hp_pct > 0.25: col = Color(1.0, 1.0, 0.3)
		else:               col = Color(1.0, 0.35, 0.35)

		var cd := m.character_data
		var name_s: String = (cd.character_name if cd != null else "?") as String
		var rank_s: String = (cd.rank          if cd != null else "?") as String
		var star_s: String = "★" if m.is_player_controlled else ""
		var status: String = ""
		if m.is_stunned:  status += "ス"
		if m.is_guarding: status += "ガ"
		if not status.is_empty(): status = "[%s]" % status

		var part := "%s%s[%s] HP:%d/%d%s" % [star_s, name_s, rank_s, m.hp, m.max_hp, status]
		var part_w: float = font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x

		if cx + part_w > x + w:
			# 幅不足：省略を示す "..." を描いて打ち切り
			_control.draw_string(font, Vector2(cx, y + FS), "...",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.5, 0.5, 0.5))
			break

		_control.draw_string(font, Vector2(cx, y + FS), part,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, col)
		cx += part_w

		if i < members.size() - 1:
			_control.draw_string(font, Vector2(cx, y + FS), SEP,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.4, 0.4, 0.5))
			cx += sep_w


## show_orders: false=敵（skill= を省略）、true=NPC/プレイヤー（skill= を表示）
## HP・指示概要を1行に統合して表示する
func _draw_member_line(font: Font, ch: Character, x: float, y: float,
		w: float, bottom: float, show_orders: bool) -> float:
	if y >= bottom:
		return y

	var cd := ch.character_data
	var name_str: String  = cd.character_name if cd != null else "?"
	var class_jp: String  = GlobalConstants.CLASS_NAME_JP.get(cd.class_id if cd != null else "", "?")
	var rank_str: String  = cd.rank if cd != null else "?"
	var hp_pct: float     = float(ch.hp) / float(ch.max_hp) if ch.max_hp > 0 else 0.0

	# HP比率で色分け
	var char_color: Color
	if hp_pct > 0.5:
		char_color = Color(0.92, 0.92, 0.92)
	elif hp_pct > 0.25:
		char_color = Color(1.0, 1.0, 0.3)
	else:
		char_color = Color(1.0, 0.35, 0.35)

	var star:  String = "★" if ch.is_player_controlled else "  "
	var stun:  String = " [スタン]" if ch.is_stunned  else ""
	var guard: String = " [ガード]" if ch.is_guarding else ""

	# 指示概要を同一行に連結
	var order_str: String = ""
	var order: Dictionary = ch.current_order
	if not order.is_empty():
		var tgt_s: String = _label("target",           str(order.get("target",           "-")))
		var fm_s:  String = _label("battle_formation", str(order.get("battle_formation", "-")))
		var cbt_s: String = _label("combat",           str(order.get("combat",           "-")))
		var is_healer: bool = cd != null and cd.class_id == "healer"
		if is_healer:
			var heal_s: String = _label("heal", str(order.get("heal", "-")))
			order_str = "  tgt=%s fm=%s cbt=%s heal=%s" % [tgt_s, fm_s, cbt_s, heal_s]
		elif show_orders:
			var skill_s: String = _label("special_skill", str(order.get("special_skill", "-")))
			order_str = "  tgt=%s fm=%s cbt=%s skill=%s" % [tgt_s, fm_s, cbt_s, skill_s]
		else:
			order_str = "  tgt=%s fm=%s cbt=%s" % [tgt_s, fm_s, cbt_s]

	var line := "%s%s(%s)[%s]  HP:%d/%d%s%s%s" % [
		star, name_str, class_jp, rank_str, ch.hp, ch.max_hp, stun, guard, order_str]
	_control.draw_string(font, Vector2(x, y + FS), line,
		HORIZONTAL_ALIGNMENT_LEFT, w, FS, char_color)
	y += LINE_H

	return y


## OrderWindow の定数から構築したラベルキャッシュ（key → {option: label}）
var _label_cache: Dictionary = {}

## OrderWindow.GLOBAL_ROWS / MEMBER_COLS / HEALER_COLS からキャッシュを構築する
func _build_label_cache() -> void:
	if not _label_cache.is_empty():
		return
	for src: Array in [OrderWindow.GLOBAL_ROWS, OrderWindow.MEMBER_COLS, OrderWindow.HEALER_COLS]:
		for def_v: Variant in src:
			var def := def_v as Dictionary
			var key: String = def.get("key", "") as String
			if key.is_empty() or _label_cache.has(key):
				continue
			var opts: Array = def.get("options", [])
			var lbls: Array = def.get("labels",  [])
			var sub: Dictionary = {}
			for i: int in range(mini(opts.size(), lbls.size())):
				sub[opts[i] as String] = lbls[i] as String
			_label_cache[key] = sub


## key に対応する OrderWindow のラベルで val を変換する。未定義なら val をそのまま返す
func _label(key: String, val: String) -> String:
	if val == "-":
		return "-"
	# 階段移動方針は OrderWindow 定数に存在しないため個別処理
	if key == "move":
		if val == "stairs_down": return "↓階段"
		if val == "stairs_up":   return "↑階段"
	_build_label_cache()
	var sub := _label_cache.get(key, {}) as Dictionary
	return sub.get(val, val) as String


# --------------------------------------------------------------------------
# ログ表示
# --------------------------------------------------------------------------

func _draw_log(font: Font, x: float, y: float, w: float, h: float) -> void:
	var max_y: float = y + h

	_control.draw_string(font, Vector2(x, y + FS), "▼ combat / ai ログ",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.6, 0.6, 0.85))
	y += LINE_H + 2.0

	if _log_entries.is_empty():
		_control.draw_string(font, Vector2(x, y + FS), "(ログなし)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS - 1, Color(0.45, 0.45, 0.45))
		return

	# 下端から逆算して表示できる行数を決定し、最新エントリを下に表示する
	var avail_h: float  = max_y - y
	var max_lines: int  = int(avail_h / LINE_H)
	var start: int      = maxi(0, _log_entries.size() - max_lines)

	for i: int in range(start, _log_entries.size()):
		if y >= max_y:
			break
		var entry: Dictionary = _log_entries[i]
		_control.draw_string(font, Vector2(x, y + FS),
			str(entry.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, w, FS - 1,
			entry.get("color", Color.WHITE) as Color)
		y += LINE_H
