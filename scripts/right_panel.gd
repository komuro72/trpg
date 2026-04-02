class_name RightPanel
extends CanvasLayer

## 右パネル：現在エリアの敵情報（種類・数・ランク）
## Phase 5: 実装完了
## Phase 10-2 準備: AIデバッグパネル廃止（F1 は MessageWindow に移管）

var _enemy_managers: Array = []
var _vision_system: VisionSystem
var _map_data: MapData
var _control: Control
var _font: Font


## enemy_managers: EnemyManager の配列
## vision_system: 現在エリア取得用（null 可・なければ全敵表示）
## map_data: 敵のエリアID取得用（null 可）
func setup(enemy_managers: Array, vision_system: VisionSystem = null, map_data: MapData = null) -> void:
	_enemy_managers = enemy_managers
	_vision_system  = vision_system
	_map_data       = map_data


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
	var px  := vw - pw  # 右パネルの左端 X

	# パネル背景・左端ライン
	_control.draw_rect(Rect2(px, 0, pw, vh), Color(0.08, 0.08, 0.12, 0.92))
	_control.draw_line(Vector2(px, 0), Vector2(px, vh), Color(0.3, 0.3, 0.4, 0.8), 1)

	if _font == null:
		return

	_draw_enemy_section(px, pw, vh, gs)


# --------------------------------------------------------------------------
# 敵情報
# --------------------------------------------------------------------------

func _draw_enemy_section(px: int, pw: int, clip_y: float, gs: int) -> void:
	# タイトル
	var title_h := int(gs * 0.75)
	_control.draw_string(_font,
		Vector2(float(px) + 8.0, float(title_h) * 0.72),
		"ENEMIES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.65, 0.80))
	_control.draw_line(
		Vector2(float(px), float(title_h)),
		Vector2(float(px + pw), float(title_h)),
		Color(0.30, 0.30, 0.40, 0.8), 1)

	# 現在エリアの可視敵のみ集計
	var current_area := _vision_system.get_current_area() if _vision_system != null else ""
	var groups: Dictionary = {}
	for em_var: Variant in _enemy_managers:
		var em := em_var as EnemyManager
		if not is_instance_valid(em):
			continue
		for enemy: Character in em.get_enemies():
			if not is_instance_valid(enemy) or not enemy.visible:
				continue
			if _map_data != null and not current_area.is_empty():
				if _map_data.get_area(enemy.grid_pos) != current_area:
					continue
			var cdata   := enemy.character_data
			var char_id := cdata.character_id if cdata else String(enemy.name) as String
			if not groups.has(char_id):
				var cname: String = (cdata.character_name if (cdata and not cdata.character_name.is_empty()) else char_id)
				var rank  := cdata.rank if cdata else "D"
				groups[char_id] = {"name": cname, "count": 0, "rank": rank}
			(groups[char_id] as Dictionary)["count"] = \
				int((groups[char_id] as Dictionary).get("count", 0)) + 1

	if groups.is_empty():
		_control.draw_string(_font,
			Vector2(float(px) + 8.0, float(title_h) + float(gs) * 0.65),
			"（なし）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.45, 0.55))
		return

	var row_h := int(gs * 0.80)
	var row_y := float(title_h) + 10.0
	for char_id: String in groups.keys():
		if row_y + float(row_h) > clip_y - 4.0:
			break
		var g        := groups[char_id] as Dictionary
		var name_str := g.get("name",  "?") as String
		var count    := int(g.get("count", 0))
		var rank     := g.get("rank",  "D") as String
		_control.draw_string(_font,
			Vector2(float(px) + 8.0, row_y + float(row_h) * 0.70),
			"%s ×%d" % [name_str, count],
			HORIZONTAL_ALIGNMENT_LEFT, float(pw) - 28.0, 13, Color.WHITE)
		_control.draw_string(_font,
			Vector2(float(px + pw) - 22.0, row_y + float(row_h) * 0.70),
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _rank_color(rank))
		row_y += float(row_h)


# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

func _rank_color(rank: String) -> Color:
	match rank:
		"S", "A": return Color(1.0, 0.30, 0.30)
		"B", "C": return Color(1.0, 0.65, 0.20)
		_:        return Color(1.0, 1.0, 0.30)
