class_name RightPanel
extends CanvasLayer

## 右パネル：現在エリアの敵情報 ＋ AIキューデバッグ表示
## 上半分: 敵情報（種類・数・ランク）
## 下半分: AIデバッグ（戦略・ターゲット・キュー）── F1 で ON/OFF
## Phase 5: 実装完了

var _enemy_managers: Array = []
var _vision_system: VisionSystem
var _map_data: MapData
var _control: Control
var _font: Font
var _debug_visible: bool = true  ## デフォルト ON（開発中。リリース版では false に変更する）


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
	add_child(_control)
	_control.draw.connect(_on_draw)


func _process(_delta: float) -> void:
	if _control != null:
		_control.queue_redraw()


## F1 キーで切替（game_map._input から呼び出す）
func toggle_debug() -> void:
	_debug_visible = not _debug_visible


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

	# デバッグONのとき上半分に敵情報・下半分にデバッグ情報
	var split_y := vh * 0.5 if _debug_visible else vh

	_draw_enemy_section(px, pw, split_y, gs)
	if _debug_visible:
		_draw_debug_section(px, pw, split_y, vh, gs)


# --------------------------------------------------------------------------
# 上半分：敵情報
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
# 下半分：AIキューデバッグ表示
# --------------------------------------------------------------------------

func _draw_debug_section(px: int, pw: int, start_y: float, end_y: float, gs: int) -> void:
	var fs_title := 11  # タイトルフォントサイズ
	var fs_name  := 10  # キャラ名・戦略行フォントサイズ
	var fs_queue :=  9  # キュー行フォントサイズ
	var lh_name  := float(fs_name)  * 1.6  # 名前行の行高
	var lh_queue := float(fs_queue) * 1.6  # キュー行の行高
	var mx       := float(px) + 6.0       # 左マージン

	# セパレーターライン
	_control.draw_line(
		Vector2(float(px), start_y),
		Vector2(float(px + pw), start_y),
		Color(0.20, 0.40, 0.35, 0.9), 1.5)

	# タイトル
	var title_bottom := start_y + float(fs_title) * 1.5
	_control.draw_string(_font,
		Vector2(mx, start_y + float(fs_title) * 1.1),
		"AI DEBUG", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_title, Color(0.35, 0.75, 0.55))
	_control.draw_line(
		Vector2(float(px), title_bottom),
		Vector2(float(px + pw), title_bottom),
		Color(0.20, 0.40, 0.35, 0.5), 1)

	var current_area := _vision_system.get_current_area() if _vision_system != null else ""
	var row_y        := title_bottom + 4.0

	for em_var: Variant in _enemy_managers:
		var em := em_var as EnemyManager
		if not is_instance_valid(em) or em.enemy_ai == null:
			continue

		# パーティーヘッダー行：リーダー戦略 + 生存数/初期数
		var lh_party := float(fs_name) * 1.5
		if row_y + lh_party <= end_y:
			var pinfo       := em.enemy_ai.get_party_debug_info()
			var p_strat     := int(pinfo.get("party_strategy", int(BaseAI.Strategy.WAIT)))
			var alive_count := int(pinfo.get("alive_count",   0))
			var init_count  := int(pinfo.get("initial_count", 0))
			var header_str  := "▶ %s  %d/%d" % [_strategy_str(p_strat), alive_count, init_count]
			_control.draw_string(_font,
				Vector2(mx, row_y + lh_party * 0.75),
				header_str, HORIZONTAL_ALIGNMENT_LEFT, float(pw) - 8.0, fs_name,
				_strategy_color(p_strat))
			row_y += lh_party

		for info_var: Variant in em.enemy_ai.get_debug_info():
			var info := info_var as Dictionary
			if row_y + lh_name + lh_queue + 4.0 > end_y:
				break  # 画面下端に近ければ打ち切り

			# エリアフィルタリング（現在いるエリアの敵のみ表示）
			if _map_data != null and not current_area.is_empty():
				var gp: Variant = info.get("grid_pos")
				if gp != null:
					if _map_data.get_area(gp as Vector2i) != current_area:
						continue

			var e_name          := info.get("name", "?") as String
			var strat           := int(info.get("strategy",         int(BaseAI.Strategy.WAIT)))
			var ordered_strat   := int(info.get("ordered_strategy", strat))
			var t_name          := info.get("target_name", "-") as String
			var cur_act         := info.get("current_action", {}) as Dictionary
			var queue           := info.get("queue", []) as Array
			var overriding      := strat != ordered_strat  # 個体がリーダー指示を上書き中

			# 行1: キャラ名  戦略（上書き時は * 付き）  →ターゲット
			_control.draw_string(_font,
				Vector2(mx + 8.0, row_y + lh_name * 0.75),
				e_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_name, Color(0.85, 0.85, 0.85))
			var strat_label := _strategy_str(strat) + ("*" if overriding else "")
			_control.draw_string(_font,
				Vector2(mx + 60.0, row_y + lh_name * 0.75),
				strat_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_name, _strategy_color(strat))
			_control.draw_string(_font,
				Vector2(mx + 102.0, row_y + lh_name * 0.75),
				"→" + t_name, HORIZONTAL_ALIGNMENT_LEFT, float(pw) - 108.0, fs_name,
				Color(0.60, 0.60, 0.70))
			row_y += lh_name

			# 行2: [現在アクション] キュー（最大6件、超過分は…で省略）
			var queue_str := ""
			if not cur_act.is_empty():
				queue_str = "[%s]" % _action_abbr(cur_act)
			var shown := 0
			for q_var: Variant in queue:
				if shown >= 6:
					queue_str += "…"
					break
				queue_str += " " + _action_abbr(q_var as Dictionary)
				shown += 1
			if queue_str.is_empty():
				queue_str = "（空）"
			_control.draw_string(_font,
				Vector2(mx + 10.0, row_y + lh_queue * 0.75),
				queue_str, HORIZONTAL_ALIGNMENT_LEFT, float(pw) - 18.0, fs_queue,
				Color(0.50, 0.65, 0.70))
			row_y += lh_queue + 3.0  # 敵間の余白


# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

func _rank_color(rank: String) -> Color:
	match rank:
		"S", "A": return Color(1.0, 0.30, 0.30)
		"B", "C": return Color(1.0, 0.65, 0.20)
		_:        return Color(1.0, 1.0, 0.30)


func _strategy_str(strat: int) -> String:
	match strat:
		BaseAI.Strategy.ATTACK: return "攻撃"
		BaseAI.Strategy.FLEE:   return "逃走"
		BaseAI.Strategy.WAIT:   return "待機"
	return "?"


func _strategy_color(strat: int) -> Color:
	match strat:
		BaseAI.Strategy.ATTACK: return Color(1.0, 0.40, 0.40)
		BaseAI.Strategy.FLEE:   return Color(1.0, 0.85, 0.20)
		BaseAI.Strategy.WAIT:   return Color(0.45, 0.80, 0.45)
	return Color.WHITE


func _action_abbr(action: Dictionary) -> String:
	match action.get("action", "") as String:
		"move_to_attack": return "移"
		"attack":         return "攻"
		"flee":           return "逃"
		"wait":           return "待"
		"":               return "-"
	return "?"
