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
var _hero:                Character = null

var _control:       Control
var _redraw_timer:  float = 0.0
const REDRAW_INTERVAL: float = 0.20  ## パーティー状態の再描画間隔（秒）


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
		get_floor: Callable, p_hero: Character) -> void:
	_party              = p_party
	_get_enemy_managers = get_enemy_managers
	_get_npc_managers   = get_npc_managers
	_get_floor          = get_floor
	_hero               = p_hero


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

	# 背景パネル
	_control.draw_rect(Rect2(px, py, pw, ph), Color(0.04, 0.04, 0.12, 0.92))
	_control.draw_rect(Rect2(px, py, pw, ph), Color(0.45, 0.55, 0.85, 0.7), false, 1.5)

	# タイトル行
	var floor_idx: int = int(_get_floor.call()) if _get_floor.is_valid() else 0
	var title := "■ DEBUG WINDOW  [F1で閉じる]  Floor: %d" % floor_idx
	_control.draw_string(font, Vector2(px + PAD, py + PAD + HDR_FS),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, HDR_FS, Color(0.8, 0.8, 1.0))

	var title_bottom: float = py + HDR_FS + PAD * 2.5
	_control.draw_line(Vector2(px, title_bottom), Vector2(px + pw, title_bottom),
		Color(0.45, 0.55, 0.85, 0.5), 1.0)

	# コンテンツ領域
	var c_top: float = title_bottom + 2.0
	var c_h: float   = ph - (title_bottom - py) - 2.0
	var div_y: float = c_top + c_h * 0.55  # 上55%：パーティー状態

	# 上半分：パーティー状態
	_draw_party_state(font, px + PAD, c_top + 2.0, pw - PAD * 2, div_y - c_top - 4.0)

	# 区切り線
	_control.draw_line(Vector2(px + PAD, div_y), Vector2(px + pw - PAD, div_y),
		Color(0.45, 0.55, 0.85, 0.5), 1.0)

	# 下半分：ログ
	_draw_log(font, px + PAD, div_y + 4.0, pw - PAD * 2, (py + ph) - div_y - 8.0)


# --------------------------------------------------------------------------
# パーティー状態
# --------------------------------------------------------------------------

func _draw_party_state(font: Font, x: float, y_start: float,
		w: float, h: float) -> void:
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
		cy = _draw_party_block(font, em, "敵", Color(1.0, 0.45, 0.45), x, cy, w, bottom)

	# NPC パーティー
	for nm_v: Variant in nms:
		if cy >= bottom:
			break
		var nm := nm_v as NpcManager
		if nm == null or not is_instance_valid(nm):
			continue
		cy = _draw_party_block(font, nm, "NPC", Color(0.45, 1.0, 0.55), x, cy, w, bottom)

	# プレイヤーパーティー
	if _party != null and cy < bottom:
		_draw_player_party(font, x, cy, w, bottom)


func _draw_party_block(font: Font, pm: PartyManager, type_label: String,
		header_color: Color, x: float, y: float, w: float, bottom: float) -> float:
	var members: Array[Character] = pm.get_members()
	if members.is_empty():
		return y

	# 生存数カウント
	var alive: int = 0
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m) and m.hp > 0:
			alive += 1

	# ヘッダー（リーダー名・戦略）
	var leader_name: String = ""
	var first_class: String = ""
	if not members.is_empty():
		var first := members[0] as Character
		if is_instance_valid(first) and first.character_data != null:
			leader_name = first.character_data.character_name
			first_class = GlobalConstants.CLASS_NAME_JP.get(first.character_data.class_id, "")

	var strategy: String = pm.get_strategy_name()
	var header := "[%s] %s(%s)  生存:%d/%d  戦略:%s" % [
		type_label, leader_name, first_class, alive, members.size(), strategy]
	_control.draw_string(font, Vector2(x, y + FS), header,
		HORIZONTAL_ALIGNMENT_LEFT, w, FS, header_color)
	y += LINE_H

	# メンバー行
	for m_v: Variant in members:
		if y >= bottom:
			break
		var m := m_v as Character
		if m == null or not is_instance_valid(m):
			continue
		y = _draw_member_line(font, m, x + INDENT, y, w - INDENT, bottom)

	return y + 3.0


func _draw_player_party(font: Font, x: float, y: float, w: float, bottom: float) -> float:
	if y >= bottom:
		return y

	_control.draw_string(font, Vector2(x, y + FS), "[プレイヤー]",
		HORIZONTAL_ALIGNMENT_LEFT, w, FS, Color(0.45, 0.75, 1.0))
	y += LINE_H

	if _party == null:
		return y

	var sorted: Array = _party.sorted_members()
	for m_v: Variant in sorted:
		if y >= bottom:
			break
		var m := m_v as Character
		if m == null or not is_instance_valid(m):
			continue
		y = _draw_member_line(font, m, x + INDENT, y, w - INDENT, bottom)

	return y + 3.0


func _draw_member_line(font: Font, ch: Character, x: float, y: float,
		w: float, bottom: float) -> float:
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
	var stun:  String = " [スタン]"  if ch.is_stunned   else ""
	var guard: String = " [ガード]"  if ch.is_guarding  else ""
	var line   := "%s%s(%s)[%s]  HP:%d/%d%s%s" % [
		star, name_str, class_jp, rank_str, ch.hp, ch.max_hp, stun, guard]
	_control.draw_string(font, Vector2(x, y + FS), line,
		HORIZONTAL_ALIGNMENT_LEFT, w, FS, char_color)
	y += LINE_H

	# 指示概要（current_order が非空なら表示）
	var order: Dictionary = ch.current_order
	if not order.is_empty() and y < bottom:
		var form_str: String = str(order.get("battle_formation", ""))
		var comb_str: String = str(order.get("combat", ""))
		var tgt_str:  String = str(order.get("target", ""))
		var heal_str: String = str(order.get("heal", ""))
		var detail: String
		if heal_str.is_empty():
			detail = "  form=%s  cbt=%s  tgt=%s" % [form_str, comb_str, tgt_str]
		else:
			detail = "  form=%s  cbt=%s  heal=%s" % [form_str, comb_str, heal_str]
		_control.draw_string(font, Vector2(x + 6.0, y + FS), detail,
			HORIZONTAL_ALIGNMENT_LEFT, w - 6.0, FS - 1, Color(0.60, 0.60, 0.60))
		y += LINE_H

	return y


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
