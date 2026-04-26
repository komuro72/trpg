class_name RightPanel
extends CanvasLayer

## 右パネル：現在エリアの敵情報（1体1行）＋同室NPC
## Phase 5: 実装完了
## Phase 10-2 準備: AIデバッグパネル廃止（F1 は MessageWindow に移管）
## Phase 13: 1体1行表示・フェイスアイコン（HP色）・状態テキスト・NPC表示に刷新

var _enemy_managers: Array = []
var _npc_managers: Array = []
var _vision_system: VisionSystem
var _map_data: MapData
var _player_controller: PlayerController
var _control: Control
var _font: Font

## フェイスアイコン用テクスチャキャッシュ（パス → Texture2D）
var _face_cache: Dictionary = {}


func setup(enemy_managers: Array, vision_system: VisionSystem = null, map_data: MapData = null) -> void:
	_enemy_managers = enemy_managers
	_vision_system  = vision_system
	_map_data       = map_data


func set_npc_managers(npc_managers: Array) -> void:
	_npc_managers = npc_managers


func set_player_controller(pc: PlayerController) -> void:
	_player_controller = pc


func _ready() -> void:
	layer = 10
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)


func _process(_delta: float) -> void:
	if _control != null:
		_control.queue_redraw()


func _on_draw() -> void:
	var gs  := GlobalConstants.GRID_SIZE
	var pw  := GlobalConstants.PANEL_TILES * gs
	var vh  := _control.size.y
	var vw  := _control.size.x
	var px: int = int(vw) - pw

	# パネル背景・左端ライン
	_control.draw_rect(Rect2(px, 0, pw, vh), Color(0.08, 0.08, 0.12, 0.92))
	_control.draw_line(Vector2(px, 0), Vector2(px, vh), Color(0.3, 0.3, 0.4, 0.8), 1)

	if _font == null:
		return

	_draw_content(px, pw, vh, gs)


# --------------------------------------------------------------------------
# 表示本体
# --------------------------------------------------------------------------

func _draw_content(px: int, pw: int, clip_y: float, gs: int) -> void:
	# 現在エリアを取得（操作キャラがいる部屋で判定する）
	var current_area := ""
	if _player_controller != null and _player_controller.character != null \
			and _map_data != null and is_instance_valid(_player_controller.character):
		current_area = _map_data.get_area(_player_controller.character.grid_pos)
	elif _vision_system != null:
		current_area = _vision_system.get_current_area()

	# 現在エリアの可視敵リスト（最大 MAX_ROWS 体）
	var visible_enemies: Array[Character] = []
	for em_var: Variant in _enemy_managers:
		var em := em_var as PartyManager
		if not is_instance_valid(em):
			continue
		for enemy: Character in em.get_enemies():
			if not is_instance_valid(enemy) or not enemy.visible:
				continue
			if _map_data != null and not current_area.is_empty():
				if _map_data.get_area(enemy.grid_pos) != current_area:
					continue
			visible_enemies.append(enemy)
			if visible_enemies.size() >= MAX_ROWS:
				break
		if visible_enemies.size() >= MAX_ROWS:
			break

	# 現在エリアの同室 NPC（未加入・可視）
	var visible_npcs: Array[Character] = []
	for nm_var: Variant in _npc_managers:
		var nm := nm_var as PartyManager
		if not is_instance_valid(nm):
			continue
		for npc: Character in nm.get_members():
			if not is_instance_valid(npc) or not npc.visible:
				continue
			if _map_data != null and not current_area.is_empty():
				if _map_data.get_area(npc.grid_pos) != current_area:
					continue
			visible_npcs.append(npc)

	var current_target: Character = null
	if _player_controller != null:
		current_target = _player_controller.get_current_target()

	# row_h = gs * 0.74：14 行収容を確保（gs * 0.80 だと 13 行が上限だった）
	# row_y = 4.0：上端余白を 6→4 に詰めて余裕を確保
	# 14 NPC 同室時の必要高さ：14 × 0.74gs + 4_top + 4_bottom ≈ 10.36gs + 8 ≤ 11gs
	var row_h := int(gs * 0.74)
	var row_y := 4.0

	for enemy: Character in visible_enemies:
		if row_y + float(row_h) > clip_y - 4.0:
			break
		_draw_char_row(enemy, px, pw, row_y, row_h, current_target, false)
		row_y += float(row_h)

	# NPC セクション（いる場合のみセパレーター＋行を表示）
	if not visible_npcs.is_empty():
		if row_y + 8.0 < clip_y - 4.0:
			_control.draw_line(
				Vector2(float(px) + 6.0, row_y + 3.0),
				Vector2(float(px + pw) - 6.0, row_y + 3.0),
				Color(0.35, 0.60, 0.35, 0.70), 1)
			row_y += 8.0
		for npc: Character in visible_npcs:
			if row_y + float(row_h) > clip_y - 4.0:
				break
			_draw_char_row(npc, px, pw, row_y, row_h, current_target, true)
			row_y += float(row_h)


func _draw_char_row(c: Character, px: int, pw: int, row_y: float, row_h: int,
		current_target: Character, is_npc: bool) -> void:
	var pad := 4

	# ターゲットハイライト（白枠＋薄い白背景）
	if current_target != null and current_target == c:
		_control.draw_rect(
			Rect2(float(px) + 1.0, row_y + 1.0, float(pw) - 2.0, float(row_h) - 2.0),
			Color(0.8, 0.8, 0.9, 0.18))
		_control.draw_rect(
			Rect2(float(px) + 1.0, row_y + 1.0, float(pw) - 2.0, float(row_h) - 2.0),
			Color(1.0, 1.0, 1.0, 0.80), false, 1)

	# フェイスアイコン（HP状態色をモジュレートとして適用）
	var icon_size := row_h - pad * 2
	var icon_rect := Rect2(float(px) + float(pad), row_y + float(pad),
		float(icon_size), float(icon_size))
	var tex := _get_face_texture(c)
	var hp_col := _hp_modulate(c)
	if tex != null:
		_control.draw_texture_rect(tex, icon_rect, false, hp_col)
	else:
		var ph_col := c.placeholder_color if is_instance_valid(c) else Color(0.35, 0.35, 0.40)
		_control.draw_rect(icon_rect, ph_col * hp_col)

	# テキストエリア（上段：名前＋ランク、下段：状態＋クラス）
	var tx    := float(px) + float(pad + icon_size + pad)
	var tw    := float(pw) - (tx - float(px)) - float(pad)
	var ty1   := row_y + float(row_h) * 0.46   # 名前行
	var ty2   := row_y + float(row_h) * 0.80   # 状態行

	# 種族名（character_name）
	var name_str := ""
	if c.character_data != null:
		name_str = c.character_data.character_name
		if name_str.is_empty():
			name_str = c.character_data.character_id
	if name_str.is_empty():
		name_str = String(c.name)

	_control.draw_string(_font,
		Vector2(tx, ty1),
		name_str,
		HORIZONTAL_ALIGNMENT_LEFT, tw - 20.0, 12, Color.WHITE)

	# ランク（右端・上段）
	if c.character_data != null and not c.character_data.rank.is_empty():
		var rank := c.character_data.rank
		_control.draw_string(_font,
			Vector2(float(px + pw) - 20.0, ty1),
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _rank_color(rank))

	# 状態テキスト（GlobalConstants の共通マッピング）
	var cond := c.get_condition()
	var cond_col := GlobalConstants.condition_text_color(cond)

	var cond_str := cond
	# NPC はクラス名も表示
	if is_npc and c.character_data != null:
		var class_jp := GlobalConstants.CLASS_NAME_JP.get(c.character_data.class_id, "") as String
		if not class_jp.is_empty():
			cond_str = class_jp + "  " + cond
	_control.draw_string(_font,
		Vector2(tx, ty2),
		cond_str,
		HORIZONTAL_ALIGNMENT_LEFT, tw, 9, cond_col)

	# 行区切り線
	_control.draw_line(
		Vector2(float(px), row_y + float(row_h) - 1),
		Vector2(float(px + pw), row_y + float(row_h) - 1),
		Color(0.20, 0.20, 0.25, 0.5), 1)


# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

const MAX_ROWS: int = 12


func _get_face_texture(c: Character) -> Texture2D:
	if c.character_data == null:
		return null
	var path := c.character_data.sprite_face
	if path.is_empty():
		path = c.character_data.sprite_front
	if path.is_empty():
		return null
	if _face_cache.has(path):
		return _face_cache[path] as Texture2D
	var tex := load(path) as Texture2D
	_face_cache[path] = tex
	return tex


## フィールド上のキャラクタースプライトと同じ HP状態→色 マッピング
## wounded 以降は 3Hz 点滅（GlobalConstants.condition_sprite_modulate）
func _hp_modulate(c: Character) -> Color:
	if not is_instance_valid(c) or c.max_hp <= 0:
		return Color.WHITE
	return GlobalConstants.condition_sprite_modulate(c.get_condition())


func _rank_color(rank: String) -> Color:
	match rank:
		"S", "A": return Color(1.0, 0.30, 0.30)
		"B", "C": return Color(1.0, 0.65, 0.20)
		_:        return Color(1.0, 1.0, 0.30)
