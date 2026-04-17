## ConfigEditor （開発用定数エディタ）
## F4 で表示・非表示トグル。ゲーム中に開いた場合は world_time_running を停止する。
##
## 使い方：シーン（game_map / title_screen）で ConfigEditor.tscn を instance 化して
##         add_child する。F4 入力検出は各シーン側で行い、toggle() を呼ぶ。
##         表示中は本クラスが _unhandled_input で F4/ESC を受け取り閉じる。
##
## タブ構成：
##   constants_default.json の `category` フィールドで振り分ける。
##   TABS 配列に定義されていないカテゴリを持つ定数は「Unknown」タブに集める。
##   新タブを追加したい場合は TABS 配列の末尾に追加するだけで済む（UI は自動構築）。
##   タブ名の末尾に " ●" が付くと、そのタブ内にデフォルト値と異なる定数が1個以上ある印。
##
## 将来：定数が100個規模になったらタブ内をさらにサブグループ化する検討あり。
##       現状は各タブ直下にフラットに定数を列挙する。

extends CanvasLayer

const HIGHLIGHT_BG_COLOR: Color = Color(1.0, 1.0, 0.8)
const PANEL_BG_COLOR:     Color = Color(0.10, 0.10, 0.14, 0.98)
const TITLE_TEXT:         String = "Config Editor (開発用)"

## カテゴリタブの順序（依存順：上位概念 → 下位概念）
## 定数がないタブもプレースホルダーとして表示する
const TABS: Array[String] = [
	"Character",
	"UnitAI",
	"PartyLeader",
	"NpcLeaderAI",
	"Healer",
	"PlayerController",
	"EnemyLeaderAI",
]
## TABS に含まれないカテゴリの定数を集める予備タブ
const UNKNOWN_TAB: String = "Unknown"

## トップレベルタブ（6種類）
## 将来ここに別ドメインのエディタを追加する際はこの配列と _build_top_tab_X を追加
const TOP_TAB_CONSTANTS:    String = "定数"
const TOP_TAB_ALLY_CLASS:   String = "味方クラス"
const TOP_TAB_ENEMY_CLASS:  String = "敵クラス"
const TOP_TAB_ENEMY_LIST:   String = "敵一覧"
const TOP_TAB_STATS:        String = "ステータス"
const TOP_TAB_ITEM:         String = "アイテム"

## ステータスタブ内のサブタブ名
const STATS_SUB_TABS: Array[String] = [
	"クラスステータス",
	"属性補正",
]

# ============================================================================
# クラス系タブ（味方クラス / 敵クラス）— Phase B
# ============================================================================
## 味方クラス（人間系 7 種）の順序
const CLASS_IDS: Array[String] = [
	"fighter-sword",
	"fighter-axe",
	"archer",
	"magician-fire",
	"magician-water",
	"healer",
	"scout",
]
## 敵固有クラス 5 種の順序
const ENEMY_CLASS_IDS: Array[String] = [
	"zombie",
	"wolf",
	"salamander",
	"harpy",
	"dark-lord",
]
const CLASS_DIR: String = "res://assets/master/classes/"

## クラスパラメータのグループ分け（表示順）
## slots.Z / slots.V は "Z_xxx" / "V_xxx" に平坦化して保存時に元の階層へ戻す
## ここに登場しないパラメータは「その他」グループに自動で集約される（警告あり）
const CLASS_PARAM_GROUPS: Array = [
	{
		"title": "基本",
		"params": ["id", "name", "weapon_type", "attack_type", "attack_range", "behavior_description"],
	},
	{
		"title": "リソース",
		"params": ["base_defense", "mp", "max_sp", "heal_mp_cost", "buff_mp_cost"],
	},
	{
		"title": "特性",
		"params": ["is_flying"],
	},
	{
		"title": "Zスロット（通常攻撃）",
		"params": [
			"Z_name", "Z_action", "Z_type", "Z_range",
			"Z_damage_mult", "Z_heal_mult",
			"Z_pre_delay", "Z_post_delay",
			"Z_sp_cost", "Z_mp_cost",
		],
	},
	{
		"title": "Vスロット（特殊攻撃）",
		"params": [
			"V_name", "V_action", "V_type", "V_range",
			"V_damage_mult",
			"V_sp_cost", "V_mp_cost",
			"V_pre_delay", "V_post_delay",
			"V_stun_duration", "V_buff_duration",
			"V_duration", "V_tick_interval",
		],
	},
]
## 味方クラスタブのセル幅
const CLASS_PARAM_COL_W:  int = 220
const CLASS_VALUE_COL_W:  int = 150

# ============================================================================
# ステータスタブ（Phase B）
# ============================================================================
const STATS_CLASS_PATH: String = "res://assets/master/stats/class_stats.json"
const STATS_ATTR_PATH:  String = "res://assets/master/stats/attribute_stats.json"

## クラスステータスのセル幅（LineEdit 2つ分）
const STAT_NAME_COL_W:  int = 200
const STAT_SUBCELL_W:   int = 60    # base / rank それぞれの LineEdit 幅
const STAT_CELL_W:      int = 130   # base + rank の HBox 幅

## 属性補正のセル幅
const ATTR_CELL_W:      int = 80

## 属性タブのカテゴリ順序（上段テーブル左から右）
const ATTR_CATEGORY_ORDER: Array = [
	{"category": "sex",   "keys": ["male", "female"]},
	{"category": "age",   "keys": ["young", "adult", "elder"]},
	{"category": "build", "keys": ["slim", "medium", "muscular"]},
]

# ============================================================================
# 敵一覧タブ（Phase B - Step 3）
# ============================================================================
const ENEMY_LIST_PATH: String = "res://assets/master/stats/enemy_list.json"
const ENEMY_DIR:       String = "res://assets/master/enemies/"

## 敵 16 種の表示順（enemy_list.json のキー順と一致させる）
const ENEMY_IDS: Array[String] = [
	"goblin", "hobgoblin", "goblin-archer", "goblin-mage",
	"zombie", "skeleton", "skeleton-archer", "lich",
	"wolf", "salamander", "harpy", "demon",
	"dark-knight", "dark-mage", "dark-priest", "dark-lord",
]

## rank ドロップダウン選択肢
const ENEMY_RANK_CHOICES: Array[String] = ["C", "B", "A", "S"]

## stat_type ドロップダウン選択肢（人間 7 + 敵固有 5 = 12 クラス）
const ENEMY_STAT_TYPE_CHOICES: Array[String] = [
	"fighter-sword", "fighter-axe", "archer",
	"magician-fire", "magician-water", "healer", "scout",
	"zombie", "wolf", "salamander", "harpy", "dark-lord",
]

## stat_bonus ドロップダウン選択肢（先頭 "---" = 未設定・計 14 個）
const ENEMY_STAT_BONUS_CHOICES: Array[String] = [
	"---",
	"vitality", "energy",
	"power", "skill",
	"defense_accuracy", "physical_resistance", "magic_resistance",
	"block_right_front", "block_left_front", "block_front",
	"move_speed", "leadership", "obedience",
]

## 1 敵あたりの stat_bonus 枠数（将来変更しやすいよう定数化）
const ENEMY_STAT_BONUS_SLOTS: int = 6

## 敵一覧タブの列幅
const ENEMY_ID_COL_W:          int = 130
const ENEMY_RANK_COL_W:        int = 60
const ENEMY_STAT_TYPE_COL_W:   int = 135
const ENEMY_CHECK_COL_W:       int = 40
const ENEMY_BEHAVIOR_COL_W:    int = 260
const ENEMY_RANGE_COL_W:       int = 55
const ENEMY_BONUS_KEY_W:       int = 135
const ENEMY_BONUS_VAL_W:       int = 40

var _root_panel:        PanelContainer = null
var _top_tab_container: TabContainer   = null  ## トップレベル：定数/味方クラス/敵/ステータス/アイテム
var _tab_container:     TabContainer   = null  ## 「定数」タブ内の既存カテゴリタブ
var _status_lbl:        Label          = null

## 下部ボタン参照（現在の上段タブに応じて有効/無効を切替）
var _btn_save:   Button = null
var _btn_reset:  Button = null
var _btn_commit: Button = null
var _btn_close:  Button = null

## 味方クラス（Phase B）: 起動時にクラスJSONをロードし、編集はメモリ上で保持
## 保存時にファイルへ書き戻す（変更があったファイルのみ）
var _class_data:         Dictionary = {}  ## class_id → 元の JSON Dictionary（キー順保持）
var _class_cell_widgets: Dictionary = {}  ## "class_id|param_key" → LineEdit
var _class_dirty:        Dictionary = {}  ## class_id → bool（書き戻し対象フラグ）
var _class_cell_styles:  Dictionary = {}  ## "class_id|param_key" → StyleBoxFlat（ハイライト制御）

## ステータス（Phase B）: 2 つの JSON をロード
## class_stats.json: クラス × ステータス × {base, rank}
## attribute_stats.json: sex/age/build × ステータス + random_max
var _class_stats_data: Dictionary = {}  ## 元 JSON（キー順保持）
var _attr_stats_data:  Dictionary = {}  ## 元 JSON（キー順保持）
var _class_stats_dirty: bool = false
var _attr_stats_dirty:  bool = false
## ウィジェット参照
## class_stats: key = "class_id|stat|base" or "class_id|stat|rank"
var _class_stats_cell_widgets: Dictionary = {}
var _class_stats_cell_styles:  Dictionary = {}
## attribute_stats: key = "category|attr|stat" or "random_max|stat"
var _attr_cell_widgets: Dictionary = {}
var _attr_cell_styles:  Dictionary = {}

## 敵一覧（Phase B - Step 3）
## enemy_list.json 全体は 1 つの Dictionary として保持し、個別敵 JSON は 16 個
## 個別 _enemy_indiv_dirty[eid] = true のファイルだけ保存時に書き戻す
## enemy_list.json は 1 ファイルなので _enemy_list_dirty: bool 1 つで管理
var _enemy_list_data:   Dictionary = {}  ## 元の enemy_list.json（キー順保持）
var _enemy_indiv_data:  Dictionary = {}  ## enemy_id → 元の個別敵 JSON Dict
var _enemy_list_dirty:  bool = false
var _enemy_indiv_dirty: Dictionary = {}  ## enemy_id → bool
## ウィジェット参照
## key 形式：
##   "{eid}|rank" → OptionButton
##   "{eid}|stat_type" → OptionButton
##   "{eid}|is_undead" / "is_flying" / "instant_death_immune" → CheckBox
##   "{eid}|behavior_description" / "chase_range" / "territory_range" → LineEdit
##   "{eid}|bonus_N_key" → OptionButton（N=0..5）
##   "{eid}|bonus_N_val" → LineEdit（N=0..5）
var _enemy_row_widgets: Dictionary = {}
var _enemy_cell_styles: Dictionary = {}  ## LineEdit 用ハイライトスタイル参照
## 各タブ名 → そのタブ内の VBox（ここに行を add）
var _tab_rows: Dictionary = {}
## 各タブ名 → プレースホルダーラベル（空タブ用。定数があれば hide）
var _tab_placeholders: Dictionary = {}
## 各タブ名 → TabContainer 上のインデックス（set_tab_title 用）
var _tab_indices: Dictionary = {}
## 行ごとのウィジェット参照
## row_widgets[key] = {"panel", "style", "editor", "default_display", "type", "tab"}
var _row_widgets: Dictionary = {}

## F4 押下中のゲーム時間停止復帰用（開く前の値を記憶）
var _prev_world_time_running: bool = true

## ゲーム中に開かれたか（タイトル画面では false）
var _opened_in_game: bool = false


func _ready() -> void:
	visible = false  # デフォルト非表示
	_build_ui()
	_refresh_all()


## F4 などから呼ぶトグル関数
func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	_opened_in_game = GlobalConstants.world_time_running
	_prev_world_time_running = GlobalConstants.world_time_running
	GlobalConstants.world_time_running = false
	visible = true
	_refresh_all()
	_set_status("", Color.WHITE)


func close() -> void:
	visible = false
	if _opened_in_game:
		GlobalConstants.world_time_running = _prev_world_time_running
	_opened_in_game = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			# Ctrl+Tab / Ctrl+PageDown → 次タブ（トップレベル）
			# Ctrl+Shift+Tab / Ctrl+PageUp → 前タブ（トップレベル）
			if ke.ctrl_pressed and _top_tab_container != null:
				if ke.keycode == KEY_TAB:
					var dir := -1 if ke.shift_pressed else 1
					_cycle_top_tab(dir)
					get_viewport().set_input_as_handled()
					return
				if ke.keycode == KEY_PAGEDOWN:
					_cycle_top_tab(1)
					get_viewport().set_input_as_handled()
					return
				if ke.keycode == KEY_PAGEUP:
					_cycle_top_tab(-1)
					get_viewport().set_input_as_handled()
					return
			if ke.keycode == KEY_F4 or ke.keycode == KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()


## トップレベル TabContainer のタブ循環
func _cycle_top_tab(dir: int) -> void:
	if _top_tab_container == null:
		return
	var n := _top_tab_container.get_tab_count()
	if n <= 0:
		return
	_top_tab_container.current_tab = (_top_tab_container.current_tab + dir + n) % n


# ============================================================================
# UI 構築
# ============================================================================

func _build_ui() -> void:
	# 画面中央のパネル（幅90% × 高さ85%。横断表を見越した広めサイズ）
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_w: float = vp_size.x * 0.90
	var panel_h: float = vp_size.y * 0.85
	var panel_x: float = (vp_size.x - panel_w) * 0.5
	var panel_y: float = (vp_size.y - panel_h) * 0.5

	_root_panel = PanelContainer.new()
	_root_panel.position = Vector2(panel_x, panel_y)
	_root_panel.size = Vector2(panel_w, panel_h)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = PANEL_BG_COLOR
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.35, 0.40, 0.55)
	_root_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)

	# タイトル
	var title := Label.new()
	title.text = TITLE_TEXT
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	outer.add_child(title)

	# ステータスメッセージ行
	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 12)
	outer.add_child(_status_lbl)

	# トップレベルタブ（定数 / 味方クラス / 敵 / ステータス / アイテム）
	_top_tab_container = TabContainer.new()
	_top_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_top_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_top_tab_container)

	_build_top_tab_constants(_top_tab_container)
	_build_top_tab_ally_class(_top_tab_container)
	_build_top_tab_enemy_class(_top_tab_container)
	_build_top_tab_enemy_list(_top_tab_container)
	_build_top_tab_stats(_top_tab_container)
	_build_top_tab_item(_top_tab_container)

	# 初期状態のタブ名（● インジケータ）を一度更新
	_update_tab_indicators()

	# タブ切替時にボタンの有効/無効を更新（上段タブに応じて作用対象が変わる）
	_top_tab_container.tab_changed.connect(_on_top_tab_changed)

	# 下部ボタン
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 12)
	outer.add_child(btn_box)

	_btn_save = Button.new()
	_btn_save.text = "保存"
	_btn_save.custom_minimum_size = Vector2(120, 36)
	_btn_save.pressed.connect(_on_save_pressed)
	btn_box.add_child(_btn_save)

	_btn_reset = Button.new()
	_btn_reset.text = "すべてデフォルトに戻す"
	_btn_reset.custom_minimum_size = Vector2(200, 36)
	_btn_reset.pressed.connect(_on_reset_pressed)
	btn_box.add_child(_btn_reset)

	_btn_commit = Button.new()
	_btn_commit.text = "現在値をすべてデフォルト化"
	_btn_commit.custom_minimum_size = Vector2(220, 36)
	_btn_commit.pressed.connect(_on_commit_pressed)
	btn_box.add_child(_btn_commit)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box.add_child(spacer)

	_btn_close = Button.new()
	_btn_close.text = "閉じる (F4)"
	_btn_close.custom_minimum_size = Vector2(120, 36)
	_btn_close.pressed.connect(close)
	btn_box.add_child(_btn_close)

	# 初期表示のボタン有効状態を設定
	_on_top_tab_changed(_top_tab_container.current_tab)


func _add_hdr_label(parent: HBoxContainer, text: String, width: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	parent.add_child(lbl)


# ============================================================================
# トップタブの構築
# ============================================================================

## 「定数」トップタブ：既存のカテゴリ TabContainer（8 タブ）
## ヘッダー行は各カテゴリタブの内側（タブバーの直下）に配置する
func _build_top_tab_constants(parent: TabContainer) -> void:
	var container := VBoxContainer.new()
	container.name = TOP_TAB_CONSTANTS
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 6)
	parent.add_child(container)
	parent.set_tab_title(parent.get_tab_count() - 1, TOP_TAB_CONSTANTS)

	# 内側のカテゴリタブ（既存の TABS 配列＋Unknown）
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(_tab_container)

	for tab_name: String in TABS:
		_build_tab(tab_name)
	_build_tab(UNKNOWN_TAB)

	# 各定数行を所属タブに追加
	for key: String in GlobalConstants.CONFIG_KEYS:
		_build_row(key)


## 「味方クラス」トップタブ：人間系 7 クラス JSON の横断表
func _build_top_tab_ally_class(parent: TabContainer) -> void:
	_build_class_tab_common(parent, TOP_TAB_ALLY_CLASS, CLASS_IDS)


## 「敵クラス」トップタブ：敵固有 5 クラス JSON の横断表（味方タブと同構造）
func _build_top_tab_enemy_class(parent: TabContainer) -> void:
	_build_class_tab_common(parent, TOP_TAB_ENEMY_CLASS, ENEMY_CLASS_IDS)


## 味方クラス / 敵クラス 共通：対象クラス ID 配列を受け取り同構造の横断表を組み立てる
func _build_class_tab_common(parent: TabContainer, tab_name: String,
		class_list: Array[String]) -> void:
	var container := VBoxContainer.new()
	container.name = tab_name
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(container)
	parent.set_tab_title(parent.get_tab_count() - 1, tab_name)

	_load_class_files()

	# 表の外側スクロール（縦横の両方）
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	scroll.add_child(grid)

	_build_class_grid(grid, class_list)


## クラスJSONを読み込む（味方 7 + 敵固有 5 = 12 クラス）
## 複数タブから呼ばれるため、既にロード済みの場合はスキップ
func _load_class_files() -> void:
	var all_class_ids: Array[String] = []
	all_class_ids.append_array(CLASS_IDS)
	all_class_ids.append_array(ENEMY_CLASS_IDS)
	for cid: String in all_class_ids:
		if _class_data.has(cid):
			continue  # 既にロード済み（他タブ初期化で読まれた）
		var path := CLASS_DIR + cid + ".json"
		if not FileAccess.file_exists(path):
			push_warning("[ConfigEditor] クラスJSONがありません: " + path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("[ConfigEditor] クラスJSONを開けません: " + path)
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(txt)
		if parsed == null or not parsed is Dictionary:
			push_warning("[ConfigEditor] クラスJSONのパースに失敗: " + path)
			continue
		_class_data[cid] = parsed
		_class_dirty[cid] = false


## class Dictionary を編集用の平坦な Dictionary に変換する
## 通常の top-level キーはそのまま、slots.Z.* は Z_* へ、slots.V.* は V_* へ
## slots.X / slots.C は表示しない（保存時は書き戻さないのでそのまま残る）
func _flatten_class(data: Dictionary) -> Dictionary:
	var flat: Dictionary = {}
	for raw_key: Variant in data.keys():
		var k := raw_key as String
		if k == "slots":
			var slots := data[k] as Dictionary
			for slot_key: String in ["Z", "V"]:
				var s: Variant = slots.get(slot_key)
				if s == null or not s is Dictionary:
					continue
				var slot_dict := s as Dictionary
				for raw_p: Variant in slot_dict.keys():
					var p := raw_p as String
					flat["%s_%s" % [slot_key, p]] = slot_dict[p]
		else:
			flat[k] = data[k]
	return flat


## 指定クラス群の平坦パラメータの和集合を、初出順で返す
func _collect_all_flat_params(class_list: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for cid: String in class_list:
		if not _class_data.has(cid):
			continue
		var flat := _flatten_class(_class_data[cid] as Dictionary)
		for raw_k: Variant in flat.keys():
			var k := raw_k as String
			if not seen.has(k):
				seen[k] = true
				out.append(k)
	return out


## グリッド本体を構築する（ヘッダー行 → グループごとに区切り + 行群）
## class_list は描画対象のクラス ID 配列（味方 CLASS_IDS / 敵 ENEMY_CLASS_IDS）
func _build_class_grid(parent: VBoxContainer, class_list: Array[String]) -> void:
	# パラメータ → グループ名 のマップを作成
	var param_to_group: Dictionary = {}
	for g_v: Variant in CLASS_PARAM_GROUPS:
		var g := g_v as Dictionary
		for p_v: Variant in g["params"]:
			param_to_group[p_v as String] = g["title"]

	var all_params := _collect_all_flat_params(class_list)
	var unclassified: Array[String] = []
	for p: String in all_params:
		if not param_to_group.has(p):
			unclassified.append(p)
	if not unclassified.is_empty():
		push_warning("[ConfigEditor] 未分類のクラスパラメータ（「その他」へ集約）: " + ", ".join(unclassified))

	# グループ順 = CLASS_PARAM_GROUPS + その他
	var groups_ordered: Array = CLASS_PARAM_GROUPS.duplicate()
	if not unclassified.is_empty():
		groups_ordered.append({"title": "その他", "params": unclassified})

	# ヘッダー行（パラメータ名 + クラスID）
	_build_class_header_row(parent, class_list)

	# グループごとに区切り → 行群
	for g_v: Variant in groups_ordered:
		var g := g_v as Dictionary
		var title: String = g["title"]
		# そのグループに該当パラメータが 1 つもない場合はセパレータも出さない
		var visible_params: Array[String] = []
		for p_v: Variant in g["params"]:
			var p := p_v as String
			if all_params.has(p):
				visible_params.append(p)
		if visible_params.is_empty():
			continue
		_add_class_group_separator(parent, title)
		for p: String in visible_params:
			_build_class_row(parent, p, class_list)


func _build_class_header_row(parent: VBoxContainer, class_list: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = "パラメータ"
	name_lbl.custom_minimum_size = Vector2(CLASS_PARAM_COL_W, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	row.add_child(name_lbl)

	for cid: String in class_list:
		var lbl := Label.new()
		lbl.text = cid
		lbl.custom_minimum_size = Vector2(CLASS_VALUE_COL_W, 0)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(lbl)


func _add_class_group_separator(parent: VBoxContainer, title: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.22, 0.30, 1.0)
	sb.content_margin_left   = 6
	sb.content_margin_right  = 6
	sb.content_margin_top    = 3
	sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	var lbl := Label.new()
	lbl.text = "─── %s ───" % title
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	panel.add_child(lbl)


func _build_class_row(parent: VBoxContainer, param_key: String,
		class_list: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	# 左列：パラメータ名
	var name_lbl := Label.new()
	name_lbl.text = param_key
	name_lbl.custom_minimum_size = Vector2(CLASS_PARAM_COL_W, 0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	# 対象クラス分のセル
	for cid: String in class_list:
		var flat: Dictionary = _flatten_class(_class_data.get(cid, {}) as Dictionary) \
			if _class_data.has(cid) else {}
		if flat.has(param_key):
			var cell := LineEdit.new()
			cell.text = _stringify_class_value(flat[param_key])
			cell.custom_minimum_size = Vector2(CLASS_VALUE_COL_W, 0)
			cell.add_theme_font_size_override("font_size", 11)
			# ハイライト用スタイル（初期は透明）
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.12, 0.12, 0.16)
			sb.content_margin_left   = 4
			sb.content_margin_right  = 4
			sb.content_margin_top    = 2
			sb.content_margin_bottom = 2
			cell.add_theme_stylebox_override("normal", sb)
			cell.add_theme_stylebox_override("focus", sb)
			row.add_child(cell)
			var widget_key := "%s|%s" % [cid, param_key]
			_class_cell_widgets[widget_key] = cell
			_class_cell_styles[widget_key] = sb
			cell.text_changed.connect(_on_class_cell_changed.bind(cid, param_key))
		else:
			# そのクラスにこのパラメータが存在しない（表示のみの空欄）
			var empty_lbl := Label.new()
			empty_lbl.text = "—"
			empty_lbl.custom_minimum_size = Vector2(CLASS_VALUE_COL_W, 0)
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
			row.add_child(empty_lbl)


## Variant → 表示用 String
func _stringify_class_value(v: Variant) -> String:
	if v == null:
		return ""
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(int(v))
	if v is float:
		return _format_number(float(v))
	return str(v)


## セル編集時：現在値と元値を比較し、差分があればハイライト・dirty 立て
func _on_class_cell_changed(new_text: String, class_id: String, param_key: String) -> void:
	var widget_key := "%s|%s" % [class_id, param_key]
	var cell := _class_cell_widgets.get(widget_key) as LineEdit
	var sb := _class_cell_styles.get(widget_key) as StyleBoxFlat
	if cell == null or sb == null:
		return
	# 元値
	var flat := _flatten_class(_class_data.get(class_id, {}) as Dictionary)
	var orig_text := _stringify_class_value(flat.get(param_key))
	var changed := new_text != orig_text
	sb.bg_color = HIGHLIGHT_BG_COLOR if changed else Color(0.12, 0.12, 0.16)
	# dirty フラグは「このクラスのいずれかのセルが元と違う」で判定
	_class_dirty[class_id] = _class_has_any_diff(class_id)


## 指定クラスに、元値と差分があるセルが1つでもあれば true
func _class_has_any_diff(class_id: String) -> bool:
	var flat := _flatten_class(_class_data.get(class_id, {}) as Dictionary)
	for raw_key: Variant in _class_cell_widgets.keys():
		var wk := raw_key as String
		if not wk.begins_with(class_id + "|"):
			continue
		var pk := wk.substr(class_id.length() + 1)
		var cell := _class_cell_widgets[wk] as LineEdit
		if cell == null:
			continue
		var orig_text := _stringify_class_value(flat.get(pk))
		if cell.text != orig_text:
			return true
	return false


## 変更されたクラスJSONをすべて書き戻す（味方・敵クラス両対応）
## 戻り値：{"saved": Array[String], "errors": Array[String]}
func _save_class_files() -> Dictionary:
	var result := {"saved": [], "errors": []}
	# 味方 + 敵固有クラスを合わせて 12 クラスすべてを対象にする
	var all_ids: Array[String] = []
	all_ids.append_array(CLASS_IDS)
	all_ids.append_array(ENEMY_CLASS_IDS)
	for cid: String in all_ids:
		if not _class_dirty.get(cid, false):
			continue
		# 元 JSON を複製してから編集値を適用
		var orig := _class_data[cid] as Dictionary
		var new_data: Variant = _apply_class_edits(cid, orig)
		if new_data == null:
			(result["errors"] as Array).append("%s: 型変換失敗（保存中止）" % cid)
			continue
		var path := CLASS_DIR + cid + ".json"
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			(result["errors"] as Array).append(
				"%s: 書き込み失敗 err=%d" % [cid, FileAccess.get_open_error()])
			continue
		# sort_keys=false：元 JSON のキー順を保持（Godot 4 のデフォルトは true でアルファベット順）
		f.store_string(JSON.stringify(new_data, "  ", false))
		f.close()
		# メモリ上の data を保存後の状態に更新
		_class_data[cid] = new_data
		_class_dirty[cid] = false
		(result["saved"] as Array).append(cid)
		# このクラスのハイライトを全解除
		_clear_class_highlights(cid)
	return result


## 指定クラスの全セルのハイライトを解除
func _clear_class_highlights(class_id: String) -> void:
	for raw_key: Variant in _class_cell_styles.keys():
		var wk := raw_key as String
		if not wk.begins_with(class_id + "|"):
			continue
		var sb := _class_cell_styles[wk] as StyleBoxFlat
		if sb != null:
			sb.bg_color = Color(0.12, 0.12, 0.16)


## 元 JSON を複製して編集値を適用。型変換失敗時は null を返す
func _apply_class_edits(class_id: String, orig: Dictionary) -> Variant:
	var out := (orig as Dictionary).duplicate(true) as Dictionary
	for raw_key: Variant in _class_cell_widgets.keys():
		var wk := raw_key as String
		if not wk.begins_with(class_id + "|"):
			continue
		var pk := wk.substr(class_id.length() + 1)
		var cell := _class_cell_widgets[wk] as LineEdit
		if cell == null:
			continue
		var text_val := cell.text
		# 保存先を決定：Z_/V_ は slots 配下、それ以外は top-level
		var is_z := pk.begins_with("Z_")
		var is_v := pk.begins_with("V_")
		if is_z or is_v:
			var slot_key := "Z" if is_z else "V"
			var p := pk.substr(slot_key.length() + 1)
			var slots: Variant = out.get("slots")
			if not slots is Dictionary:
				continue
			var slots_d := slots as Dictionary
			var slot: Variant = slots_d.get(slot_key)
			if not slot is Dictionary:
				continue
			var slot_d := slot as Dictionary
			if not slot_d.has(p):
				continue
			var coerced := _coerce_class_value(text_val, slot_d[p])
			if not bool(coerced.get("ok", false)):
				push_warning("[ConfigEditor] %s.%s 型変換失敗: '%s'" % [class_id, pk, text_val])
				return null
			slot_d[p] = coerced["value"]
		else:
			if not out.has(pk):
				continue
			var coerced := _coerce_class_value(text_val, out[pk])
			if not bool(coerced.get("ok", false)):
				push_warning("[ConfigEditor] %s.%s 型変換失敗: '%s'" % [class_id, pk, text_val])
				return null
			out[pk] = coerced["value"]
	return out


## 文字列 → 元値の型に合わせて変換。{"ok": true, "value": ...} / {"ok": false}
func _coerce_class_value(text: String, orig_value: Variant) -> Dictionary:
	if orig_value is bool:
		var low := text.to_lower().strip_edges()
		if low == "true":  return {"ok": true, "value": true}
		if low == "false": return {"ok": true, "value": false}
		return {"ok": false}
	if orig_value is int:
		if text.is_valid_int():
			return {"ok": true, "value": text.to_int()}
		if text.is_valid_float():
			return {"ok": true, "value": int(text.to_float())}
		return {"ok": false}
	if orig_value is float:
		if text.is_valid_float():
			return {"ok": true, "value": text.to_float()}
		return {"ok": false}
	# 文字列または null はそのまま
	return {"ok": true, "value": text}


## 「敵一覧」トップタブ：enemy_list.json + 個別敵 JSON の非 legacy フィールドを編集
func _build_top_tab_enemy_list(parent: TabContainer) -> void:
	var container := VBoxContainer.new()
	container.name = TOP_TAB_ENEMY_LIST
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(container)
	parent.set_tab_title(parent.get_tab_count() - 1, TOP_TAB_ENEMY_LIST)

	_load_enemy_list_files()

	# 横スクロールも効くように、縦横両方スクロール可能な ScrollContainer
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	scroll.add_child(grid)

	if _enemy_list_data.is_empty():
		var err := Label.new()
		err.text = "enemy_list.json が読み込めませんでした。"
		err.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		grid.add_child(err)
		return

	_build_enemy_list_header(grid)
	for eid: String in ENEMY_IDS:
		_build_enemy_list_row(grid, eid)


## enemy_list.json と個別敵 JSON 16 ファイルを読み込む
func _load_enemy_list_files() -> void:
	_enemy_list_data.clear()
	_enemy_indiv_data.clear()
	_enemy_indiv_dirty.clear()
	_enemy_list_dirty = false

	var el: Variant = _read_json_file(ENEMY_LIST_PATH)
	if el is Dictionary:
		_enemy_list_data = el as Dictionary

	for eid: String in ENEMY_IDS:
		var path := ENEMY_DIR + _enemy_id_to_filename(eid)
		var data: Variant = _read_json_file(path)
		if data is Dictionary:
			_enemy_indiv_data[eid] = data
			_enemy_indiv_dirty[eid] = false


## 敵 ID を個別敵 JSON ファイル名に変換する（ハイフン → アンダースコア）
## 例：goblin-archer → goblin_archer.json
func _enemy_id_to_filename(enemy_id: String) -> String:
	return enemy_id.replace("-", "_") + ".json"


func _build_enemy_list_header(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var cols: Array = [
		["敵ID",          ENEMY_ID_COL_W],
		["rank",          ENEMY_RANK_COL_W],
		["stat_type",     ENEMY_STAT_TYPE_COL_W],
		["undead",        ENEMY_CHECK_COL_W],
		["flying",        ENEMY_CHECK_COL_W],
		["死耐性",        ENEMY_CHECK_COL_W],
		["behavior",      ENEMY_BEHAVIOR_COL_W],
		["chase",         ENEMY_RANGE_COL_W],
		["territory",     ENEMY_RANGE_COL_W],
	]
	for entry: Variant in cols:
		var arr := entry as Array
		_add_enemy_hdr(row, arr[0] as String, int(arr[1]))

	for i: int in range(ENEMY_STAT_BONUS_SLOTS):
		var lbl := Label.new()
		lbl.text = "bonus %d" % (i + 1)
		lbl.custom_minimum_size = Vector2(ENEMY_BONUS_KEY_W + ENEMY_BONUS_VAL_W + 4, 0)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(lbl)


func _add_enemy_hdr(parent: HBoxContainer, text: String, width: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)


func _build_enemy_list_row(parent: VBoxContainer, eid: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	# 敵 ID（固定ラベル）
	var name_lbl := Label.new()
	name_lbl.text = eid
	name_lbl.custom_minimum_size = Vector2(ENEMY_ID_COL_W, 0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	var list_entry: Dictionary = (_enemy_list_data.get(eid, {}) as Dictionary)
	var indiv: Dictionary = (_enemy_indiv_data.get(eid, {}) as Dictionary)

	# rank OptionButton
	var rank_btn := _make_option_button(ENEMY_RANK_CHOICES,
		str(list_entry.get("rank", "C")), ENEMY_RANK_COL_W)
	rank_btn.item_selected.connect(_on_enemy_list_field_changed.bind(eid, "rank"))
	row.add_child(rank_btn)
	_enemy_row_widgets["%s|rank" % eid] = rank_btn

	# stat_type OptionButton
	var stat_btn := _make_option_button(ENEMY_STAT_TYPE_CHOICES,
		str(list_entry.get("stat_type", "fighter-axe")), ENEMY_STAT_TYPE_COL_W)
	stat_btn.item_selected.connect(_on_enemy_list_field_changed.bind(eid, "stat_type"))
	row.add_child(stat_btn)
	_enemy_row_widgets["%s|stat_type" % eid] = stat_btn

	# is_undead CheckBox
	_add_enemy_checkbox(row, eid, "is_undead", bool(indiv.get("is_undead", false)))
	# is_flying CheckBox
	_add_enemy_checkbox(row, eid, "is_flying", bool(indiv.get("is_flying", false)))
	# instant_death_immune CheckBox
	_add_enemy_checkbox(row, eid, "instant_death_immune",
		bool(indiv.get("instant_death_immune", false)))

	# behavior_description LineEdit
	_add_enemy_lineedit(row, eid, "behavior_description",
		str(indiv.get("behavior_description", "")), ENEMY_BEHAVIOR_COL_W)
	# chase_range LineEdit
	_add_enemy_lineedit(row, eid, "chase_range",
		_stringify_class_value(indiv.get("chase_range", 10)), ENEMY_RANGE_COL_W)
	# territory_range LineEdit
	_add_enemy_lineedit(row, eid, "territory_range",
		_stringify_class_value(indiv.get("territory_range", 50)), ENEMY_RANGE_COL_W)

	# stat_bonus 6 枠（既存値を先頭から展開）
	var stat_bonus: Dictionary = (list_entry.get("stat_bonus", {}) as Dictionary)
	var bonus_keys: Array = stat_bonus.keys()
	for i: int in range(ENEMY_STAT_BONUS_SLOTS):
		var key: String = "---"
		var val: int = 0
		if i < bonus_keys.size():
			key = bonus_keys[i] as String
			val = int(stat_bonus[key])
		_add_enemy_bonus_slot(row, eid, i, key, val)


## OptionButton を生成し、指定されたテキストの項目を選択状態にする
func _make_option_button(choices: Array[String], current_text: String, width: int) -> OptionButton:
	var btn := OptionButton.new()
	btn.custom_minimum_size = Vector2(width, 0)
	btn.add_theme_font_size_override("font_size", 11)
	var selected_idx := 0
	for i: int in range(choices.size()):
		btn.add_item(choices[i], i)
		if choices[i] == current_text:
			selected_idx = i
	btn.select(selected_idx)
	return btn


func _add_enemy_checkbox(parent: HBoxContainer, eid: String, field: String, value: bool) -> void:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(ENEMY_CHECK_COL_W, 0)
	parent.add_child(wrapper)
	var cb := CheckBox.new()
	cb.button_pressed = value
	cb.position = Vector2(ENEMY_CHECK_COL_W * 0.5 - 10, 2)
	wrapper.add_child(cb)
	cb.toggled.connect(_on_enemy_indiv_field_changed.bind(eid, field))
	_enemy_row_widgets["%s|%s" % [eid, field]] = cb


func _add_enemy_lineedit(parent: HBoxContainer, eid: String, field: String,
		text_val: String, width: int) -> void:
	var le := LineEdit.new()
	le.text = text_val
	le.custom_minimum_size = Vector2(width, 0)
	le.add_theme_font_size_override("font_size", 11)
	var sb := _make_cell_style()
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("focus", sb)
	parent.add_child(le)
	le.text_changed.connect(_on_enemy_indiv_field_text_changed.bind(eid, field))
	var wk := "%s|%s" % [eid, field]
	_enemy_row_widgets[wk] = le
	_enemy_cell_styles[wk] = sb


func _add_enemy_bonus_slot(parent: HBoxContainer, eid: String, slot_idx: int,
		key: String, value: int) -> void:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 2)
	pair.custom_minimum_size = Vector2(ENEMY_BONUS_KEY_W + ENEMY_BONUS_VAL_W + 4, 0)
	parent.add_child(pair)

	var key_btn := _make_option_button(ENEMY_STAT_BONUS_CHOICES, key, ENEMY_BONUS_KEY_W)
	key_btn.item_selected.connect(_on_enemy_bonus_slot_changed.bind(eid, slot_idx))
	pair.add_child(key_btn)
	_enemy_row_widgets["%s|bonus_%d_key" % [eid, slot_idx]] = key_btn

	var val_le := LineEdit.new()
	val_le.custom_minimum_size = Vector2(ENEMY_BONUS_VAL_W, 0)
	val_le.add_theme_font_size_override("font_size", 11)
	val_le.text = "" if key == "---" else str(value)
	val_le.editable = (key != "---")
	var sb := _make_cell_style()
	val_le.add_theme_stylebox_override("normal", sb)
	val_le.add_theme_stylebox_override("focus", sb)
	pair.add_child(val_le)
	val_le.text_changed.connect(_on_enemy_bonus_val_changed.bind(eid, slot_idx))
	var wk := "%s|bonus_%d_val" % [eid, slot_idx]
	_enemy_row_widgets[wk] = val_le
	_enemy_cell_styles[wk] = sb


# ----------------------------------------------------------------------------
# 敵一覧タブのハンドラ
# ----------------------------------------------------------------------------

## enemy_list.json 系の変更（rank / stat_type）。エンジン Dirty 立てて再評価
func _on_enemy_list_field_changed(_idx: int, eid: String, field: String) -> void:
	_enemy_list_dirty = _enemy_list_has_any_diff()
	# 視覚フィードバックは OptionButton には付けない（選択されたものが見えるため）


## 個別敵 JSON 系の bool 値変更（3 つのチェックボックス）
func _on_enemy_indiv_field_changed(_pressed: bool, eid: String, field: String) -> void:
	_enemy_indiv_dirty[eid] = _enemy_indiv_has_any_diff(eid)


## 個別敵 JSON 系の LineEdit 変更（behavior_description / chase_range / territory_range）
func _on_enemy_indiv_field_text_changed(new_text: String, eid: String, field: String) -> void:
	var wk := "%s|%s" % [eid, field]
	var sb := _enemy_cell_styles.get(wk) as StyleBoxFlat
	if sb != null:
		var orig := _enemy_indiv_orig_text(eid, field)
		sb.bg_color = HIGHLIGHT_BG_COLOR if new_text != orig else Color(0.12, 0.12, 0.16)
	_enemy_indiv_dirty[eid] = _enemy_indiv_has_any_diff(eid)


## stat_bonus のキー（OptionButton）変更：LineEdit の編集可否を切替、enemy_list 再評価
func _on_enemy_bonus_slot_changed(idx: int, eid: String, slot_idx: int) -> void:
	var key_btn := _enemy_row_widgets.get("%s|bonus_%d_key" % [eid, slot_idx]) as OptionButton
	var val_le  := _enemy_row_widgets.get("%s|bonus_%d_val" % [eid, slot_idx]) as LineEdit
	if key_btn == null or val_le == null:
		return
	var key := key_btn.get_item_text(idx)
	if key == "---":
		val_le.text = ""
		val_le.editable = false
	else:
		val_le.editable = true
		if val_le.text.is_empty():
			val_le.text = "0"
	_enemy_list_dirty = _enemy_list_has_any_diff()


## stat_bonus の値（LineEdit）変更
func _on_enemy_bonus_val_changed(new_text: String, eid: String, slot_idx: int) -> void:
	var wk := "%s|bonus_%d_val" % [eid, slot_idx]
	var sb := _enemy_cell_styles.get(wk) as StyleBoxFlat
	if sb != null:
		# bonus 値のハイライトは「本来の stat_bonus 辞書と一致するか」で判定するのが理想だが
		# 実装簡略化のため、新テキストが空でなく変更されているかで判定
		# （dirty 判定は _enemy_list_has_any_diff で厳密に行う）
		var changed := new_text != "0" and not new_text.is_empty()
		sb.bg_color = HIGHLIGHT_BG_COLOR if changed else Color(0.12, 0.12, 0.16)
	_enemy_list_dirty = _enemy_list_has_any_diff()


# ----------------------------------------------------------------------------
# 敵一覧タブの Dirty 判定
# ----------------------------------------------------------------------------

## 個別敵 JSON の元テキスト値（LineEdit 用に文字列化）
func _enemy_indiv_orig_text(eid: String, field: String) -> String:
	var indiv: Dictionary = (_enemy_indiv_data.get(eid, {}) as Dictionary)
	if field == "behavior_description":
		return str(indiv.get(field, ""))
	if field == "chase_range":
		return _stringify_class_value(indiv.get(field, 10))
	if field == "territory_range":
		return _stringify_class_value(indiv.get(field, 50))
	return str(indiv.get(field, ""))


## 指定敵の個別 JSON に差分があるか判定
func _enemy_indiv_has_any_diff(eid: String) -> bool:
	var indiv: Dictionary = (_enemy_indiv_data.get(eid, {}) as Dictionary)
	# bool 3 つ
	for f: String in ["is_undead", "is_flying", "instant_death_immune"]:
		var cb := _enemy_row_widgets.get("%s|%s" % [eid, f]) as CheckBox
		if cb == null:
			continue
		if cb.button_pressed != bool(indiv.get(f, false)):
			return true
	# 文字列 / 数値
	for f: String in ["behavior_description", "chase_range", "territory_range"]:
		var le := _enemy_row_widgets.get("%s|%s" % [eid, f]) as LineEdit
		if le == null:
			continue
		if le.text != _enemy_indiv_orig_text(eid, f):
			return true
	return false


## enemy_list.json に差分があるか判定（全敵を対象に rank / stat_type / stat_bonus を比較）
func _enemy_list_has_any_diff() -> bool:
	for eid: String in ENEMY_IDS:
		var orig_entry: Dictionary = (_enemy_list_data.get(eid, {}) as Dictionary)
		var rank_btn := _enemy_row_widgets.get("%s|rank" % eid) as OptionButton
		if rank_btn != null:
			var cur_rank := rank_btn.get_item_text(rank_btn.selected)
			if cur_rank != str(orig_entry.get("rank", "C")):
				return true
		var stat_btn := _enemy_row_widgets.get("%s|stat_type" % eid) as OptionButton
		if stat_btn != null:
			var cur_type := stat_btn.get_item_text(stat_btn.selected)
			if cur_type != str(orig_entry.get("stat_type", "")):
				return true
		# stat_bonus：現在の 6 枠から Dictionary を再構築して元と比較
		var cur_bonus := _build_bonus_dict_from_slots(eid)
		var orig_bonus: Dictionary = (orig_entry.get("stat_bonus", {}) as Dictionary)
		if cur_bonus != orig_bonus:
			return true
	return false


## 6 枠の UI 値から stat_bonus Dictionary を構築
## "---" スロットは無視。int 変換失敗スロットも無視（スキップ）
## 同じキーが複数枠にある場合は後ろ勝ち（UI 仕様として受け入れる）
func _build_bonus_dict_from_slots(eid: String) -> Dictionary:
	var out: Dictionary = {}
	for i: int in range(ENEMY_STAT_BONUS_SLOTS):
		var key_btn := _enemy_row_widgets.get("%s|bonus_%d_key" % [eid, i]) as OptionButton
		var val_le  := _enemy_row_widgets.get("%s|bonus_%d_val" % [eid, i]) as LineEdit
		if key_btn == null or val_le == null:
			continue
		var key := key_btn.get_item_text(key_btn.selected)
		if key == "---":
			continue
		if not val_le.text.is_valid_int():
			continue
		out[key] = val_le.text.to_int()
	return out


# ----------------------------------------------------------------------------
# 敵一覧タブの保存
# ----------------------------------------------------------------------------

## 敵一覧タブの保存：enemy_list.json + dirty な個別敵 JSON
func _save_enemy_list_tab() -> Dictionary:
	var result := {"saved": [], "errors": []}
	# 1. enemy_list.json（dirty の場合のみ）
	if _enemy_list_dirty:
		var new_list: Variant = _apply_enemy_list_edits()
		if new_list == null:
			(result["errors"] as Array).append("enemy_list.json: 型変換失敗")
		else:
			var f := FileAccess.open(ENEMY_LIST_PATH, FileAccess.WRITE)
			if f == null:
				(result["errors"] as Array).append(
					"enemy_list.json: 書き込み失敗 err=%d" % FileAccess.get_open_error())
			else:
				f.store_string(JSON.stringify(new_list, "  ", false))
				f.close()
				_enemy_list_data = new_list as Dictionary
				_enemy_list_dirty = false
				(result["saved"] as Array).append("enemy_list.json")
	# 2. 個別敵 JSON（dirty のみ）
	for eid: String in ENEMY_IDS:
		if not _enemy_indiv_dirty.get(eid, false):
			continue
		var new_indiv: Variant = _apply_enemy_indiv_edits(eid)
		if new_indiv == null:
			(result["errors"] as Array).append("%s: 型変換失敗" % _enemy_id_to_filename(eid))
			continue
		var path := ENEMY_DIR + _enemy_id_to_filename(eid)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			(result["errors"] as Array).append(
				"%s: 書き込み失敗 err=%d" % [_enemy_id_to_filename(eid), FileAccess.get_open_error()])
			continue
		f.store_string(JSON.stringify(new_indiv, "  ", false))
		f.close()
		_enemy_indiv_data[eid] = new_indiv as Dictionary
		_enemy_indiv_dirty[eid] = false
		(result["saved"] as Array).append(_enemy_id_to_filename(eid))
	# ハイライト解除（保存成功分）
	_clear_enemy_cell_highlights()
	return result


## LineEdit セル群のハイライトを全解除
func _clear_enemy_cell_highlights() -> void:
	for raw_key: Variant in _enemy_cell_styles.keys():
		var sb := _enemy_cell_styles[raw_key] as StyleBoxFlat
		if sb != null:
			sb.bg_color = Color(0.12, 0.12, 0.16)


## enemy_list.json の現在の UI 状態を反映した新 Dictionary を返す
## 元 JSON のキー順（16 敵の順序）を保持するため、元を duplicate してから上書き
func _apply_enemy_list_edits() -> Variant:
	var out := _enemy_list_data.duplicate(true) as Dictionary
	for eid: String in ENEMY_IDS:
		if not out.has(eid):
			continue
		var entry := out[eid] as Dictionary
		# rank
		var rank_btn := _enemy_row_widgets.get("%s|rank" % eid) as OptionButton
		if rank_btn != null:
			entry["rank"] = rank_btn.get_item_text(rank_btn.selected)
		# stat_type
		var stat_btn := _enemy_row_widgets.get("%s|stat_type" % eid) as OptionButton
		if stat_btn != null:
			entry["stat_type"] = stat_btn.get_item_text(stat_btn.selected)
		# stat_bonus
		entry["stat_bonus"] = _build_bonus_dict_from_slots(eid)
	return out


## 個別敵 JSON の現在の UI 状態を反映した新 Dictionary を返す
## 元 JSON（legacy を含む）を duplicate し、編集対象 6 フィールドのみ
## 「元値と違うときだけ」上書きする。元にフィールドが無かった場合は
## 値がデフォルトから変更された時だけ追加する。
func _apply_enemy_indiv_edits(eid: String) -> Variant:
	var orig: Dictionary = (_enemy_indiv_data.get(eid, {}) as Dictionary)
	var out := orig.duplicate(true) as Dictionary
	# bool 3 フィールド
	for f: String in ["is_undead", "is_flying", "instant_death_immune"]:
		var cb := _enemy_row_widgets.get("%s|%s" % [eid, f]) as CheckBox
		if cb == null:
			continue
		var orig_had := orig.has(f)
		var orig_val: bool = bool(orig.get(f, false))
		var cur_val: bool = cb.button_pressed
		if cur_val == orig_val and orig_had:
			continue  # 変化なし・元にあった → そのまま
		if cur_val == false and not orig_had:
			continue  # デフォルト値で元にも無かった → 追加しない
		out[f] = cur_val
	# 文字列
	var beh_le := _enemy_row_widgets.get("%s|behavior_description" % eid) as LineEdit
	if beh_le != null:
		var orig_beh := str(orig.get("behavior_description", ""))
		if beh_le.text != orig_beh:
			out["behavior_description"] = beh_le.text
		elif not orig.has("behavior_description") and beh_le.text.is_empty():
			pass  # デフォルトかつ元に無かった → 追加しない
	# int 2 フィールド
	for f: String in ["chase_range", "territory_range"]:
		var le := _enemy_row_widgets.get("%s|%s" % [eid, f]) as LineEdit
		if le == null:
			continue
		if not le.text.is_valid_int():
			push_warning("[ConfigEditor] %s.%s int 変換失敗: '%s'" % [eid, f, le.text])
			return null
		var cur: int = le.text.to_int()
		var orig_had := orig.has(f)
		if orig_had:
			out[f] = cur
		elif cur != 0:
			out[f] = cur
	return out


## 「ステータス」トップタブ：クラスステータス・属性補正のサブタブ
func _build_top_tab_stats(parent: TabContainer) -> void:
	var container := VBoxContainer.new()
	container.name = TOP_TAB_STATS
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(container)
	parent.set_tab_title(parent.get_tab_count() - 1, TOP_TAB_STATS)

	_load_stats_files()

	var sub_tc := TabContainer.new()
	sub_tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_tc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(sub_tc)

	_build_class_stats_sub_tab(sub_tc)
	_build_attr_stats_sub_tab(sub_tc)


## ステータス系 JSON をすべて読み込む
func _load_stats_files() -> void:
	var cs: Variant = _read_json_file(STATS_CLASS_PATH)
	_class_stats_data = cs as Dictionary if cs is Dictionary else {}
	var ats: Variant = _read_json_file(STATS_ATTR_PATH)
	_attr_stats_data = ats as Dictionary if ats is Dictionary else {}
	_class_stats_dirty = false
	_attr_stats_dirty = false


## JSON ファイルを読み込むヘルパ
func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[ConfigEditor] JSON がありません: " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[ConfigEditor] JSON を開けません: " + path)
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_warning("[ConfigEditor] JSON パース失敗: " + path)
		return null
	return parsed


# ----------------------------------------------------------------------------
# サブタブ：クラスステータス（class_stats.json）
# ----------------------------------------------------------------------------

## class_stats.json 編集用グリッド（列=クラス、行=ステータス、各セルに base/rank の 2 LineEdit）
func _build_class_stats_sub_tab(parent: TabContainer) -> void:
	var root := VBoxContainer.new()
	root.name = STATS_SUB_TABS[0]
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(root)
	parent.set_tab_title(parent.get_tab_count() - 1, STATS_SUB_TABS[0])

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	scroll.add_child(grid)

	if _class_stats_data.is_empty():
		var err := Label.new()
		err.text = "class_stats.json が読み込めませんでした。"
		err.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		grid.add_child(err)
		return

	# 画面上のクラス順は CLASS_IDS を使う。JSON に存在するクラスのみ表示
	var display_classes: Array[String] = []
	for cid: String in CLASS_IDS:
		if _class_stats_data.has(cid):
			display_classes.append(cid)

	# 先頭クラスのステータスキー順を行順として使う
	var stat_keys: Array[String] = []
	if not display_classes.is_empty():
		var first := _class_stats_data[display_classes[0]] as Dictionary
		for raw_k: Variant in first.keys():
			stat_keys.append(raw_k as String)

	# ヘッダー2段：クラス名（上）+ base/rank（下）
	_build_class_stats_header(grid, display_classes)

	# 各ステータス行
	for stat: String in stat_keys:
		_build_class_stats_row(grid, stat, display_classes)


func _build_class_stats_header(parent: VBoxContainer, classes: Array[String]) -> void:
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	parent.add_child(row1)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
	row1.add_child(spacer)
	for cid: String in classes:
		var lbl := Label.new()
		lbl.text = cid
		lbl.custom_minimum_size = Vector2(STAT_CELL_W, 0)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row1.add_child(lbl)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	parent.add_child(row2)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
	row2.add_child(spacer2)
	for _cid: String in classes:
		var pair := HBoxContainer.new()
		pair.custom_minimum_size = Vector2(STAT_CELL_W, 0)
		pair.add_theme_constant_override("separation", 4)
		row2.add_child(pair)
		var bl := Label.new()
		bl.text = "base"
		bl.custom_minimum_size = Vector2(STAT_SUBCELL_W, 0)
		bl.add_theme_font_size_override("font_size", 10)
		bl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pair.add_child(bl)
		var rl := Label.new()
		rl.text = "rank"
		rl.custom_minimum_size = Vector2(STAT_SUBCELL_W, 0)
		rl.add_theme_font_size_override("font_size", 10)
		rl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pair.add_child(rl)


func _build_class_stats_row(parent: VBoxContainer, stat: String, classes: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = stat
	name_lbl.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(name_lbl)

	for cid: String in classes:
		var class_entry := _class_stats_data[cid] as Dictionary
		var has_stat := class_entry.has(stat)
		var pair := HBoxContainer.new()
		pair.custom_minimum_size = Vector2(STAT_CELL_W, 0)
		pair.add_theme_constant_override("separation", 4)
		row.add_child(pair)
		if not has_stat:
			var dash1 := Label.new()
			dash1.text = "—"
			dash1.custom_minimum_size = Vector2(STAT_SUBCELL_W, 0)
			dash1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pair.add_child(dash1)
			var dash2 := Label.new()
			dash2.text = "—"
			dash2.custom_minimum_size = Vector2(STAT_SUBCELL_W, 0)
			dash2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pair.add_child(dash2)
			continue
		var entry := class_entry[stat] as Dictionary
		_add_class_stats_cell(pair, cid, stat, "base", entry.get("base", 0))
		_add_class_stats_cell(pair, cid, stat, "rank", entry.get("rank", 0))


func _add_class_stats_cell(parent: HBoxContainer, class_id: String, stat: String,
		sub_key: String, value: Variant) -> void:
	var cell := LineEdit.new()
	cell.text = _stringify_class_value(value)
	cell.custom_minimum_size = Vector2(STAT_SUBCELL_W, 0)
	cell.add_theme_font_size_override("font_size", 11)
	var sb := _make_cell_style()
	cell.add_theme_stylebox_override("normal", sb)
	cell.add_theme_stylebox_override("focus", sb)
	parent.add_child(cell)
	var key := "%s|%s|%s" % [class_id, stat, sub_key]
	_class_stats_cell_widgets[key] = cell
	_class_stats_cell_styles[key] = sb
	cell.text_changed.connect(_on_class_stats_cell_changed.bind(class_id, stat, sub_key))


func _on_class_stats_cell_changed(new_text: String, class_id: String, stat: String, sub_key: String) -> void:
	var key := "%s|%s|%s" % [class_id, stat, sub_key]
	var sb := _class_stats_cell_styles.get(key) as StyleBoxFlat
	if sb == null:
		return
	var orig := _class_stats_orig_text(class_id, stat, sub_key)
	var changed := new_text != orig
	sb.bg_color = HIGHLIGHT_BG_COLOR if changed else Color(0.12, 0.12, 0.16)
	_class_stats_dirty = _class_stats_has_any_diff()


func _class_stats_orig_text(class_id: String, stat: String, sub_key: String) -> String:
	if not _class_stats_data.has(class_id):
		return ""
	var class_entry := _class_stats_data[class_id] as Dictionary
	if not class_entry.has(stat):
		return ""
	var entry := class_entry[stat] as Dictionary
	return _stringify_class_value(entry.get(sub_key, 0))


func _class_stats_has_any_diff() -> bool:
	for raw_key: Variant in _class_stats_cell_widgets.keys():
		var wk := raw_key as String
		var cell := _class_stats_cell_widgets[wk] as LineEdit
		if cell == null:
			continue
		var parts := wk.split("|")
		if parts.size() != 3:
			continue
		var orig := _class_stats_orig_text(parts[0], parts[1], parts[2])
		if cell.text != orig:
			return true
	return false


# ----------------------------------------------------------------------------
# サブタブ：属性補正（attribute_stats.json）
# ----------------------------------------------------------------------------

func _build_attr_stats_sub_tab(parent: TabContainer) -> void:
	var root := VBoxContainer.new()
	root.name = STATS_SUB_TABS[1]
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(root)
	parent.set_tab_title(parent.get_tab_count() - 1, STATS_SUB_TABS[1])

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	if _attr_stats_data.is_empty():
		var err := Label.new()
		err.text = "attribute_stats.json が読み込めませんでした。"
		err.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		vbox.add_child(err)
		return

	# 属性補正テーブル
	_build_attr_group_separator(vbox, "属性補正")
	_build_attr_table(vbox)

	# random_max テーブル
	_build_attr_group_separator(vbox, "random_max（乱数上限）")
	_build_random_max_table(vbox)


func _build_attr_group_separator(parent: VBoxContainer, title: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.22, 0.30, 1.0)
	sb.content_margin_left   = 6
	sb.content_margin_right  = 6
	sb.content_margin_top    = 3
	sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	var lbl := Label.new()
	lbl.text = "─── %s ───" % title
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	panel.add_child(lbl)


func _build_attr_table(parent: VBoxContainer) -> void:
	# 収集：全属性キー（male/female/young/...）の列ヘッダー順
	var all_attrs: Array = []
	for entry: Variant in ATTR_CATEGORY_ORDER:
		var ent := entry as Dictionary
		for k: Variant in ent["keys"]:
			all_attrs.append({"category": ent["category"], "attr": k as String})

	# ステータス行順：任意の1属性の stats 順を取る
	var stat_keys: Array[String] = []
	for cell_entry: Variant in all_attrs:
		var ent := cell_entry as Dictionary
		var cat := ent["category"] as String
		var attr := ent["attr"] as String
		if _attr_stats_data.has(cat) and (_attr_stats_data[cat] as Dictionary).has(attr):
			var stats := (_attr_stats_data[cat] as Dictionary)[attr] as Dictionary
			for sk: Variant in stats.keys():
				stat_keys.append(sk as String)
			break

	# ヘッダー行
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	parent.add_child(hdr)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
	hdr.add_child(spacer)
	for cell_entry: Variant in all_attrs:
		var ent := cell_entry as Dictionary
		var lbl := Label.new()
		lbl.text = ent["attr"] as String
		lbl.custom_minimum_size = Vector2(ATTR_CELL_W, 0)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.add_child(lbl)

	# データ行
	for stat: String in stat_keys:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = stat
		name_lbl.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(name_lbl)
		for cell_entry: Variant in all_attrs:
			var ent := cell_entry as Dictionary
			var cat := ent["category"] as String
			var attr := ent["attr"] as String
			var v: Variant = null
			if _attr_stats_data.has(cat) and (_attr_stats_data[cat] as Dictionary).has(attr):
				var stats := (_attr_stats_data[cat] as Dictionary)[attr] as Dictionary
				v = stats.get(stat)
			_add_attr_cell(row, cat, attr, stat, v)


func _add_attr_cell(parent: HBoxContainer, category: String, attr: String,
		stat: String, value: Variant) -> void:
	if value == null:
		var dash := Label.new()
		dash.text = "—"
		dash.custom_minimum_size = Vector2(ATTR_CELL_W, 0)
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
		parent.add_child(dash)
		return
	var cell := LineEdit.new()
	cell.text = _stringify_class_value(value)
	cell.custom_minimum_size = Vector2(ATTR_CELL_W, 0)
	cell.add_theme_font_size_override("font_size", 11)
	var sb := _make_cell_style()
	cell.add_theme_stylebox_override("normal", sb)
	cell.add_theme_stylebox_override("focus", sb)
	parent.add_child(cell)
	var key := "%s|%s|%s" % [category, attr, stat]
	_attr_cell_widgets[key] = cell
	_attr_cell_styles[key] = sb
	cell.text_changed.connect(_on_attr_cell_changed.bind(category, attr, stat))


func _on_attr_cell_changed(new_text: String, category: String, attr: String, stat: String) -> void:
	var key := "%s|%s|%s" % [category, attr, stat]
	var sb := _attr_cell_styles.get(key) as StyleBoxFlat
	if sb == null:
		return
	var orig := _attr_orig_text(category, attr, stat)
	var changed := new_text != orig
	sb.bg_color = HIGHLIGHT_BG_COLOR if changed else Color(0.12, 0.12, 0.16)
	_attr_stats_dirty = _attr_stats_has_any_diff()


func _attr_orig_text(category: String, attr: String, stat: String) -> String:
	if not _attr_stats_data.has(category):
		return ""
	var cat_d := _attr_stats_data[category] as Dictionary
	if not cat_d.has(attr):
		return ""
	var stats := cat_d[attr] as Dictionary
	return _stringify_class_value(stats.get(stat, 0))


func _build_random_max_table(parent: VBoxContainer) -> void:
	if not _attr_stats_data.has("random_max"):
		var err := Label.new()
		err.text = "random_max セクションがありません。"
		err.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		parent.add_child(err)
		return
	var rm := _attr_stats_data["random_max"] as Dictionary

	# ヘッダー
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 4)
	parent.add_child(hdr)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
	hdr.add_child(spacer)
	var h_lbl := Label.new()
	h_lbl.text = "random_max"
	h_lbl.custom_minimum_size = Vector2(ATTR_CELL_W, 0)
	h_lbl.add_theme_font_size_override("font_size", 11)
	h_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	h_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_child(h_lbl)

	# 各ステータス行
	for raw_k: Variant in rm.keys():
		var stat := raw_k as String
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = stat
		name_lbl.custom_minimum_size = Vector2(STAT_NAME_COL_W, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(name_lbl)
		var cell := LineEdit.new()
		cell.text = _stringify_class_value(rm[stat])
		cell.custom_minimum_size = Vector2(ATTR_CELL_W, 0)
		cell.add_theme_font_size_override("font_size", 11)
		var sb := _make_cell_style()
		cell.add_theme_stylebox_override("normal", sb)
		cell.add_theme_stylebox_override("focus", sb)
		row.add_child(cell)
		var key := "random_max|%s" % stat
		_attr_cell_widgets[key] = cell
		_attr_cell_styles[key] = sb
		cell.text_changed.connect(_on_random_max_cell_changed.bind(stat))


func _on_random_max_cell_changed(new_text: String, stat: String) -> void:
	var key := "random_max|%s" % stat
	var sb := _attr_cell_styles.get(key) as StyleBoxFlat
	if sb == null:
		return
	var orig := ""
	if _attr_stats_data.has("random_max"):
		var rm := _attr_stats_data["random_max"] as Dictionary
		orig = _stringify_class_value(rm.get(stat, 0))
	var changed := new_text != orig
	sb.bg_color = HIGHLIGHT_BG_COLOR if changed else Color(0.12, 0.12, 0.16)
	_attr_stats_dirty = _attr_stats_has_any_diff()


func _attr_stats_has_any_diff() -> bool:
	for raw_key: Variant in _attr_cell_widgets.keys():
		var wk := raw_key as String
		var cell := _attr_cell_widgets[wk] as LineEdit
		if cell == null:
			continue
		var parts := wk.split("|")
		var orig := ""
		if parts.size() == 3:
			orig = _attr_orig_text(parts[0], parts[1], parts[2])
		elif parts.size() == 2 and parts[0] == "random_max":
			if _attr_stats_data.has("random_max"):
				var rm := _attr_stats_data["random_max"] as Dictionary
				orig = _stringify_class_value(rm.get(parts[1], 0))
		if cell.text != orig:
			return true
	return false


# ----------------------------------------------------------------------------
# セル共通
# ----------------------------------------------------------------------------

## LineEdit セル用の初期スタイル（濃い背景）
func _make_cell_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16)
	sb.content_margin_left   = 4
	sb.content_margin_right  = 4
	sb.content_margin_top    = 2
	sb.content_margin_bottom = 2
	return sb


# ----------------------------------------------------------------------------
# ステータス系ファイル保存
# ----------------------------------------------------------------------------

## class_stats.json + attribute_stats.json をまとめて保存
## 戻り値：{"saved": Array[String], "errors": Array[String]}
func _save_stats_files() -> Dictionary:
	var result := {"saved": [], "errors": []}
	# class_stats
	if _class_stats_dirty:
		var new_cs: Variant = _apply_class_stats_edits(_class_stats_data)
		if new_cs == null:
			(result["errors"] as Array).append("class_stats.json: 型変換失敗")
		else:
			var f := FileAccess.open(STATS_CLASS_PATH, FileAccess.WRITE)
			if f == null:
				(result["errors"] as Array).append(
					"class_stats.json: 書き込み失敗 err=%d" % FileAccess.get_open_error())
			else:
				f.store_string(JSON.stringify(new_cs, "  ", false))
				f.close()
				_class_stats_data = new_cs as Dictionary
				_class_stats_dirty = false
				_clear_cell_styles(_class_stats_cell_styles)
				(result["saved"] as Array).append("class_stats.json")
	# attribute_stats
	if _attr_stats_dirty:
		var new_at: Variant = _apply_attr_stats_edits(_attr_stats_data)
		if new_at == null:
			(result["errors"] as Array).append("attribute_stats.json: 型変換失敗")
		else:
			var f := FileAccess.open(STATS_ATTR_PATH, FileAccess.WRITE)
			if f == null:
				(result["errors"] as Array).append(
					"attribute_stats.json: 書き込み失敗 err=%d" % FileAccess.get_open_error())
			else:
				f.store_string(JSON.stringify(new_at, "  ", false))
				f.close()
				_attr_stats_data = new_at as Dictionary
				_attr_stats_dirty = false
				_clear_cell_styles(_attr_cell_styles)
				(result["saved"] as Array).append("attribute_stats.json")
	return result


## 指定した StyleBoxFlat 群を既定の暗色に戻す（保存後のハイライト解除）
func _clear_cell_styles(styles: Dictionary) -> void:
	for raw_key: Variant in styles.keys():
		var sb := styles[raw_key] as StyleBoxFlat
		if sb != null:
			sb.bg_color = Color(0.12, 0.12, 0.16)


## class_stats を編集値で書き換えて新 Dictionary を返す（元のキー順・ネスト構造を保持）
## 型変換失敗時は null を返す
func _apply_class_stats_edits(orig: Dictionary) -> Variant:
	var out := orig.duplicate(true) as Dictionary
	for raw_key: Variant in _class_stats_cell_widgets.keys():
		var wk := raw_key as String
		var parts := wk.split("|")
		if parts.size() != 3:
			continue
		var cid: String = parts[0]
		var stat: String = parts[1]
		var sub_key: String = parts[2]
		var cell := _class_stats_cell_widgets[wk] as LineEdit
		if cell == null:
			continue
		if not out.has(cid):
			continue
		var class_d := out[cid] as Dictionary
		if not class_d.has(stat):
			continue
		var entry := class_d[stat] as Dictionary
		if not entry.has(sub_key):
			continue
		var coerced := _coerce_class_value(cell.text, entry[sub_key])
		if not bool(coerced.get("ok", false)):
			push_warning("[ConfigEditor] class_stats %s.%s.%s 型変換失敗: '%s'" \
				% [cid, stat, sub_key, cell.text])
			return null
		entry[sub_key] = coerced["value"]
	return out


## attribute_stats を編集値で書き換えて新 Dictionary を返す
func _apply_attr_stats_edits(orig: Dictionary) -> Variant:
	var out := orig.duplicate(true) as Dictionary
	for raw_key: Variant in _attr_cell_widgets.keys():
		var wk := raw_key as String
		var parts := wk.split("|")
		var cell := _attr_cell_widgets[wk] as LineEdit
		if cell == null:
			continue
		# 3 パーツ = "category|attr|stat"（上段テーブル）
		if parts.size() == 3:
			var cat: String = parts[0]
			var attr: String = parts[1]
			var stat: String = parts[2]
			if not out.has(cat):
				continue
			var cat_d := out[cat] as Dictionary
			if not cat_d.has(attr):
				continue
			var attr_d := cat_d[attr] as Dictionary
			if not attr_d.has(stat):
				continue
			var coerced := _coerce_class_value(cell.text, attr_d[stat])
			if not bool(coerced.get("ok", false)):
				push_warning("[ConfigEditor] attribute_stats %s.%s.%s 型変換失敗: '%s'" \
					% [cat, attr, stat, cell.text])
				return null
			attr_d[stat] = coerced["value"]
		# 2 パーツ = "random_max|stat"（下段テーブル）
		elif parts.size() == 2 and parts[0] == "random_max":
			var stat: String = parts[1]
			if not out.has("random_max"):
				continue
			var rm := out["random_max"] as Dictionary
			if not rm.has(stat):
				continue
			var coerced := _coerce_class_value(cell.text, rm[stat])
			if not bool(coerced.get("ok", false)):
				push_warning("[ConfigEditor] attribute_stats random_max.%s 型変換失敗: '%s'" \
					% [stat, cell.text])
				return null
			rm[stat] = coerced["value"]
	return out


## 「アイテム」トップタブ：プレースホルダー
func _build_top_tab_item(parent: TabContainer) -> void:
	_add_placeholder_tab(parent, TOP_TAB_ITEM,
		"アイテムマスターの縦1列テーブルが入る予定です")


## プレースホルダー用のタブを追加する（中身はラベルのみ）
func _add_placeholder_tab(parent: TabContainer, tab_name: String, message: String) -> void:
	var wrap := VBoxContainer.new()
	wrap.name = tab_name
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)
	parent.set_tab_title(parent.get_tab_count() - 1, tab_name)

	var lbl := Label.new()
	lbl.text = message
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(lbl)


## タブ名に対応する VBox を生成して TabContainer に追加する
## 空タブの時のプレースホルダーも同時に配置（後で定数が入れば自動で hide）
func _build_tab(tab_name: String) -> void:
	# カテゴリタブの中身 = 外側 VBox（ヘッダー行 + スクロール領域）
	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.name = tab_name
	_tab_container.add_child(outer_vbox)
	var tab_idx := _tab_container.get_tab_count() - 1
	_tab_container.set_tab_title(tab_idx, tab_name)
	_tab_indices[tab_name] = tab_idx

	# ヘッダー行（タブバー直下に配置・各カテゴリタブで共通表示）
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	outer_vbox.add_child(hdr)
	_add_hdr_label(hdr, "定数名", 260)
	_add_hdr_label(hdr, "説明", 380)
	_add_hdr_label(hdr, "編集", 200)
	_add_hdr_label(hdr, "デフォルト", 120)

	# 行はスクロール領域内の VBox に追加する
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(scroll)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(rows_vbox)
	_tab_rows[tab_name] = rows_vbox

	var placeholder := Label.new()
	placeholder.text = "このカテゴリには定数がまだ登録されていません。"
	placeholder.add_theme_font_size_override("font_size", 12)
	placeholder.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	rows_vbox.add_child(placeholder)
	_tab_placeholders[tab_name] = placeholder


func _build_row(key: String) -> void:
	var meta := GlobalConstants._get_meta_for(key)
	var type_name: String = meta.get("type", "float") as String
	var desc: String = meta.get("description", "") as String
	var category: String = meta.get("category", "") as String

	# 所属タブを決定。TABS にない or 空文字は Unknown タブに振る
	var target_tab: String = UNKNOWN_TAB
	if TABS.has(category):
		target_tab = category
	elif not category.is_empty():
		push_warning("[ConfigEditor] 未知のカテゴリ '%s' を Unknown タブに振り分け (key=%s)" % [category, key])
	else:
		push_warning("[ConfigEditor] category 未定義の定数を Unknown タブに振り分け (key=%s)" % key)

	var target_vbox := _tab_rows.get(target_tab) as VBoxContainer
	if target_vbox == null:
		push_warning("[ConfigEditor] タブ '%s' の VBox が見つかりません。行生成をスキップ (key=%s)" % [target_tab, key])
		return

	# このタブに定数が入るのでプレースホルダーは隠す
	if _tab_placeholders.has(target_tab):
		(_tab_placeholders[target_tab] as Label).visible = false

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color.TRANSPARENT
	row_style.content_margin_left   = 6
	row_style.content_margin_right  = 6
	row_style.content_margin_top    = 4
	row_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", row_style)
	target_vbox.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	# 定数名（等幅）
	var name_lbl := Label.new()
	name_lbl.text = key
	name_lbl.custom_minimum_size = Vector2(260, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	# 説明
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.custom_minimum_size = Vector2(380, 0)
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc_lbl)

	# 編集ウィジェット
	var editor: Control = null
	match type_name:
		"float", "int":
			editor = _make_numeric_editor(key, meta, type_name == "int")
		"color":
			editor = _make_color_editor(key)
		_:
			editor = Label.new()
			(editor as Label).text = "(未対応の型: %s)" % type_name
	editor.custom_minimum_size = Vector2(200, 0)
	row.add_child(editor)

	# デフォルト値表示
	var default_display: Control = null
	if type_name == "color":
		default_display = _make_color_swatch(GlobalConstants.get_default_value(key))
	else:
		default_display = Label.new()
		(default_display as Label).custom_minimum_size = Vector2(120, 0)
		(default_display as Label).add_theme_font_size_override("font_size", 12)
	row.add_child(default_display)

	_row_widgets[key] = {
		"panel": panel,
		"style": row_style,
		"editor": editor,
		"default_display": default_display,
		"type": type_name,
		"tab": target_tab,
	}


func _make_numeric_editor(key: String, meta: Dictionary, is_int: bool) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = float(meta.get("min", 0.0))
	sb.max_value = float(meta.get("max", 100.0))
	sb.step      = float(meta.get("step", 1.0 if is_int else 0.01))
	sb.rounded   = is_int
	sb.value     = float(GlobalConstants.get(key))
	sb.value_changed.connect(_on_numeric_changed.bind(key, is_int))
	return sb


func _make_color_editor(key: String) -> ColorPickerButton:
	var btn := ColorPickerButton.new()
	btn.color = GlobalConstants.get(key) as Color
	btn.edit_alpha = false
	btn.color_changed.connect(_on_color_changed.bind(key))
	return btn


func _make_color_swatch(value: Variant) -> ColorRect:
	var cr := ColorRect.new()
	cr.custom_minimum_size = Vector2(120, 22)
	cr.color = _to_color(value)
	return cr


func _to_color(v: Variant) -> Color:
	if v is Color:
		return v as Color
	if v is Array:
		var a := v as Array
		var r: float = float(a[0]) if a.size() >= 1 else 0.0
		var g: float = float(a[1]) if a.size() >= 2 else 0.0
		var b: float = float(a[2]) if a.size() >= 3 else 0.0
		var al: float = float(a[3]) if a.size() >= 4 else 1.0
		return Color(r, g, b, al)
	return Color.MAGENTA  # fallback


# ============================================================================
# 値の更新ハンドラ
# ============================================================================

func _on_numeric_changed(value: float, key: String, is_int: bool) -> void:
	if is_int:
		GlobalConstants.set(key, int(value))
	else:
		GlobalConstants.set(key, value)
	_update_row_highlight(key)


func _on_color_changed(color: Color, key: String) -> void:
	GlobalConstants.set(key, color)
	_update_row_highlight(key)


# ============================================================================
# ボタン
# ============================================================================

## 現在の上段タブ名を返す（TOP_TAB_CONSTANTS / TOP_TAB_ALLY_CLASS / ...）
func _current_top_tab_name() -> String:
	if _top_tab_container == null:
		return ""
	return _top_tab_container.get_tab_title(_top_tab_container.current_tab)


## 上段タブが切り替わったときに下部ボタンの有効/無効を更新する
## - 定数タブ：保存 / リセット / デフォルト化がすべて有効
## - 味方クラス・敵クラス・敵一覧・ステータス：保存のみ有効（デフォルト値を保持しない方針）
## - アイテム：プレースホルダー段階なのですべて無効
func _on_top_tab_changed(_idx: int) -> void:
	if _btn_save == null:
		return
	var top := _current_top_tab_name()
	var is_constants := top == TOP_TAB_CONSTANTS
	var is_ally := top == TOP_TAB_ALLY_CLASS
	var is_enemy_class := top == TOP_TAB_ENEMY_CLASS
	var is_enemy_list := top == TOP_TAB_ENEMY_LIST
	var is_stats := top == TOP_TAB_STATS
	_btn_save.disabled = not (is_constants or is_ally or is_enemy_class or is_enemy_list or is_stats)
	_btn_reset.disabled = not is_constants
	_btn_commit.disabled = not is_constants


func _on_save_pressed() -> void:
	var top := _current_top_tab_name()
	match top:
		TOP_TAB_CONSTANTS:
			var ok := GlobalConstants.save_constants()
			if ok:
				_set_status("保存しました: %s" % GlobalConstants.CONFIG_USER_PATH, Color(0.55, 1.0, 0.55))
			else:
				_set_status(GlobalConstants.last_config_error, Color(1.0, 0.5, 0.5))
		TOP_TAB_ALLY_CLASS, TOP_TAB_ENEMY_CLASS:
			# 味方・敵どちらも _save_class_files が 12 クラス全て対象にまとめて書き戻す
			var result := _save_class_files()
			var saved: Array = result.get("saved", [])
			var errors: Array = result.get("errors", [])
			if errors.is_empty():
				if saved.is_empty():
					_set_status("変更なし（保存対象の差分がありません）", Color(0.8, 0.8, 0.6))
				else:
					_set_status("保存しました: %s" % ", ".join(saved), Color(0.55, 1.0, 0.55))
			else:
				_set_status("エラー: %s" % " / ".join(errors), Color(1.0, 0.5, 0.5))
		TOP_TAB_STATS:
			var result := _save_stats_files()
			var saved: Array = result.get("saved", [])
			var errors: Array = result.get("errors", [])
			if errors.is_empty():
				if saved.is_empty():
					_set_status("変更なし（保存対象の差分がありません）", Color(0.8, 0.8, 0.6))
				else:
					_set_status("保存しました: %s" % ", ".join(saved), Color(0.55, 1.0, 0.55))
			else:
				_set_status("エラー: %s" % " / ".join(errors), Color(1.0, 0.5, 0.5))
		TOP_TAB_ENEMY_LIST:
			var result := _save_enemy_list_tab()
			var saved: Array = result.get("saved", [])
			var errors: Array = result.get("errors", [])
			if errors.is_empty():
				if saved.is_empty():
					_set_status("変更なし（保存対象の差分がありません）", Color(0.8, 0.8, 0.6))
				else:
					_set_status("保存しました: %s" % ", ".join(saved), Color(0.55, 1.0, 0.55))
			else:
				_set_status("エラー: %s" % " / ".join(errors), Color(1.0, 0.5, 0.5))
		_:
			_set_status("このタブでは保存操作はありません", Color(0.8, 0.8, 0.6))


func _on_reset_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "すべての定数をデフォルト値に戻します。よろしいですか？\n（UI 上の値のみ変更・保存は別途「保存」ボタンで）"
	dlg.title = "デフォルトに戻す"
	add_child(dlg)
	dlg.confirmed.connect(_on_reset_confirmed.bind(dlg))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_reset_confirmed(dlg: ConfirmationDialog) -> void:
	GlobalConstants.reset_to_defaults()
	_refresh_all()
	if GlobalConstants.last_config_error.is_empty():
		_set_status("デフォルト値に戻しました（未保存）", Color(0.55, 1.0, 0.55))
	else:
		_set_status(GlobalConstants.last_config_error, Color(1.0, 0.5, 0.5))
	dlg.queue_free()


func _on_commit_pressed() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "現在値を constants_default.json の value として書き換えます。\nこれは復帰不能な上書きです。よろしいですか？"
	dlg.title = "現在値をデフォルト化"
	add_child(dlg)
	dlg.confirmed.connect(_on_commit_confirmed.bind(dlg))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


func _on_commit_confirmed(dlg: ConfirmationDialog) -> void:
	var ok := GlobalConstants.commit_as_defaults()
	if ok:
		_refresh_all()  # デフォルト列の再描画
		_set_status("現在値を constants_default.json に書き込みました", Color(0.55, 1.0, 0.55))
	else:
		_set_status(GlobalConstants.last_config_error, Color(1.0, 0.5, 0.5))
	dlg.queue_free()


# ============================================================================
# 行ごとの表示更新
# ============================================================================

func _refresh_all() -> void:
	for key: String in GlobalConstants.CONFIG_KEYS:
		if not _row_widgets.has(key):
			continue
		var w := _row_widgets[key] as Dictionary
		var editor := w.get("editor") as Control
		# 編集ウィジェットに現在値を反映
		if editor is SpinBox:
			(editor as SpinBox).value = float(GlobalConstants.get(key))
		elif editor is ColorPickerButton:
			(editor as ColorPickerButton).color = GlobalConstants.get(key) as Color
		# デフォルト値ラベル
		var default_val: Variant = GlobalConstants.get_default_value(key)
		var disp := w.get("default_display") as Control
		if disp is Label:
			(disp as Label).text = _format_default(default_val)
		elif disp is ColorRect:
			(disp as ColorRect).color = _to_color(default_val)
		# 背景色（現在値 ≠ デフォルトなら薄黄）
		_update_row_highlight(key)
	# 全行更新の後にタブインジケータも再計算
	_update_tab_indicators()


func _update_row_highlight(key: String) -> void:
	if not _row_widgets.has(key):
		return
	var w := _row_widgets[key] as Dictionary
	var style := w.get("style") as StyleBoxFlat
	var cur: Variant = GlobalConstants.get_config_value(key)
	var dflt: Variant = GlobalConstants.get_default_value(key)
	if _values_equal(cur, dflt):
		style.bg_color = Color.TRANSPARENT
	else:
		style.bg_color = HIGHLIGHT_BG_COLOR
	# この行を含むタブの ● インジケータを再計算
	var tab_name := w.get("tab", UNKNOWN_TAB) as String
	_update_tab_title(tab_name)


## タブ名に定数が変更されている印（●）を付けるか外すか判定
func _update_tab_title(tab_name: String) -> void:
	if not _tab_indices.has(tab_name):
		return
	var idx := int(_tab_indices[tab_name])
	var has_change := false
	for k: String in GlobalConstants.CONFIG_KEYS:
		if not _row_widgets.has(k):
			continue
		var w := _row_widgets[k] as Dictionary
		if (w.get("tab", "") as String) != tab_name:
			continue
		var cur: Variant = GlobalConstants.get_config_value(k)
		var dflt: Variant = GlobalConstants.get_default_value(k)
		if not _values_equal(cur, dflt):
			has_change = true
			break
	var title: String = tab_name + " ●" if has_change else tab_name
	_tab_container.set_tab_title(idx, title)


## 全タブのインジケータを一括更新（_refresh_all から呼ぶ）
func _update_tab_indicators() -> void:
	for tab_name: String in _tab_indices.keys():
		_update_tab_title(tab_name as String)


func _values_equal(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if a is Array and b is Array:
		var aa := a as Array
		var bb := b as Array
		if aa.size() != bb.size():
			return false
		for i in range(aa.size()):
			if not is_equal_approx(float(aa[i]), float(bb[i])):
				return false
		return true
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _format_default(v: Variant) -> String:
	if v == null:
		return "—"
	if v is Array:
		var a := v as Array
		var parts: Array[String] = []
		for x: Variant in a:
			parts.append(_format_number(float(x)))
		return "[" + ", ".join(parts) + "]"
	if v is float:
		return _format_number(float(v))
	if v is int:
		return str(int(v))
	return String(str(v))


## GDScript の printf は %g 未対応のため、%.4f に丸めてから末尾ゼロを削る
## 整数扱いの float は "3" 形式、小数は "0.35" 形式で返す
func _format_number(f: float) -> String:
	if is_equal_approx(f, float(int(f))):
		return "%d" % int(f)
	var s := "%.4f" % f
	if s.contains("."):
		s = s.rstrip("0")
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


func _set_status(msg: String, color: Color) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override("font_color", color)
