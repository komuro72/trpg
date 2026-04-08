class_name OrderWindow
extends CanvasLayer

## パーティー指示ウィンドウ（Phase 10-4 拡張版）
## Tab キーで開閉。全体方針プリセット + 5項目個別設定 + 操作キャラ切替。
## 下部にステータス詳細・装備スロット・所持アイテム欄（未装備品のみ）を表示。
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

## プリセット → [combat, battle_formation, move, target, on_low_hp, item_pickup]
const PRESET_TABLE: Array = [
	["aggressive", "surround", "cluster",   "nearest",        "keep_fighting", "aggressive"],
	["support",    "surround", "cluster",   "same_as_leader", "retreat",       "passive"],
	["standby",    "surround", "cluster",   "nearest",        "retreat",       "avoid"],
	["support",    "surround", "cluster",   "same_as_leader", "retreat",       "passive"],
	["standby",    "surround", "cluster",   "nearest",        "flee",          "avoid"],
	["aggressive", "surround", "explore",   "nearest",        "retreat",       "aggressive"],
]

const COL_OPTIONS: Array = [
	["explore", "same_room", "cluster", "guard_room", "standby"],
	["surround", "front", "rear", "same_as_leader"],
	["aggressive", "support", "standby"],
	["nearest", "weakest", "same_as_leader"],
	["keep_fighting", "retreat", "flee"],
	["aggressive", "passive", "avoid"],
]

const COL_LABELS: Array = [
	["探索", "同じ部屋", "密集", "部屋守る", "待機"],
	["包囲", "前衛", "後衛", "リーダーと同じ"],
	["積極攻撃", "援護", "待機"],
	["最近傍", "最弱", "リーダーと同じ"],
	["戦い続ける", "後退", "逃走"],
	["積極的に拾う", "近くのみ", "拾わない"],
]

const COL_HEADERS: Array[String] = ["移動", "隊形", "戦闘", "ターゲット", "低HP", "取得"]
const COL_KEYS: Array[String] = ["move", "battle_formation", "combat", "target", "on_low_hp", "item_pickup"]
const TOTAL_COLS := 7

## 攻撃タイプの表示名
const ATTACK_TYPE_LABELS: Dictionary = {
	"melee": "近接", "ranged": "遠距離", "dive": "降下", "magic": "魔法", "heal": "回復"
}

# ── 内部状態 ──────────────────────────────────────────────────────────────────

enum _FocusArea { GLOBAL_POLICY, MEMBER_TABLE, CLOSE, LOG }

## 名前列Z押下時のサブメニュー項目
const SUBMENU_ITEMS: Array[String] = ["操作切替", "アイテム"]

## クラスID → 装備可能アイテムタイプ一覧
const CLASS_EQUIP_TYPES: Dictionary = {
	"fighter-sword": ["sword",  "armor_plate", "shield"],
	"fighter-axe":   ["axe",    "armor_plate", "shield"],
	"archer":        ["bow",    "armor_cloth"],
	"scout":         ["dagger", "armor_cloth"],
	"magician-fire": ["staff",  "armor_robe"],
	"healer":        ["staff",  "armor_robe"],
}

var _party:          Party
var _focus_area:     _FocusArea = _FocusArea.GLOBAL_POLICY
var _policy_cursor:  int = 0
var _applied_policy: int = -1
var _member_cursor:  int = 0
var _col_cursor:     int = 0

## 名前列サブメニュー状態
var _submenu_open:   bool = false
var _submenu_cursor: int  = 0

var _controlled_char: Character = null
var _sorted_members: Array = []

var _control: Control
var _font:    Font

## front/face 画像テクスチャキャッシュ（パス → Texture2D）
var _texture_cache: Dictionary = {}

## MessageWindow 参照（ログ表示に使用）
var _message_window: MessageWindow = null

## ログ表示モード・スクロール
var _log_mode:   bool = false
var _log_scroll: int  = 0

## アイテム画像テクスチャキャッシュ（img_path -> Texture2D or null）
var _item_tex_cache: Dictionary = {}

## アイテム画面の状態
enum _ItemMode { OFF, ITEM_LIST, ACTION_MENU, TRANSFER_SELECT }
var _item_mode:          _ItemMode = _ItemMode.OFF
var _item_char:          Character = null   ## アイテムを見ているキャラ
var _item_cursor:        int       = 0
var _cached_unequipped:  Array     = []     ## _item_char の未装備アイテムリスト（キャッシュ）
var _cached_grouped:     Array     = []     ## 同名アイテムをまとめたグループリスト（表示用）
var _selected_item:      Dictionary = {}    ## ITEM_LIST で選んだアイテム
var _action_items:       Array[String] = [] ## ACTION_MENU の選択肢
var _action_cursor:      int       = 0
var _transfer_cursor:    int       = 0


# ── セットアップ ──────────────────────────────────────────────────────────────

func setup(party: Party, message_window: MessageWindow = null) -> void:
	_party          = party
	_message_window = message_window


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
	_submenu_open = false
	_log_mode     = false
	_item_mode    = _ItemMode.OFF
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
			elif Input.is_action_just_pressed("attack") \
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
			elif Input.is_action_just_pressed("ui_cancel") \
					or Input.is_action_just_pressed("menu_back"):
				close_window()

		_FocusArea.MEMBER_TABLE:
			if _item_mode != _ItemMode.OFF:
				_handle_item_input()
			elif _submenu_open:
				# サブメニュー操作（名前列Z押下後）
				if Input.is_action_just_pressed("ui_up"):
					_submenu_cursor = (_submenu_cursor - 1 + SUBMENU_ITEMS.size()) % SUBMENU_ITEMS.size()
				elif Input.is_action_just_pressed("ui_down"):
					_submenu_cursor = (_submenu_cursor + 1) % SUBMENU_ITEMS.size()
				elif Input.is_action_just_pressed("attack") \
						or Input.is_action_just_pressed("ui_accept") \
						or Input.is_action_just_pressed("ui_right"):
					_execute_submenu(_member_cursor, _submenu_cursor)
					_submenu_open = false
				elif Input.is_action_just_pressed("ui_cancel") \
						or Input.is_action_just_pressed("menu_back") \
						or Input.is_action_just_pressed("ui_left"):
					_submenu_open = false
			else:
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
					if _col_cursor == 0:
						# 名前列左キー：ウィンドウを閉じる
						close_window()
					else:
						_col_cursor = (_col_cursor - 1 + TOTAL_COLS) % TOTAL_COLS
				elif Input.is_action_just_pressed("ui_right"):
					# 右キーは常に列移動（サブメニューを開くのは Z のみ）
					_col_cursor = (_col_cursor + 1) % TOTAL_COLS
				elif Input.is_action_just_pressed("attack") \
						or Input.is_action_just_pressed("ui_accept"):
					if _col_cursor == 0:
						# 名前列：サブメニューを開く
						_submenu_cursor = 0
						_submenu_open   = true
					else:
						# 1..6 列：リーダー操作中のみ値変更可
						if _is_editable():
							_cycle_member_col(_member_cursor, _col_cursor - 1, +1)
				elif Input.is_action_just_pressed("ui_cancel") \
						or Input.is_action_just_pressed("menu_back"):
					close_window()

		_FocusArea.CLOSE:
			if _log_mode:
				# ログ表示モード：スクロール操作
				if Input.is_action_just_pressed("ui_up"):
					_log_scroll = maxi(0, _log_scroll - 1)
				elif Input.is_action_just_pressed("ui_down"):
					var log_visible := MessageLog.get_visible_entries() if MessageLog != null else []
					_log_scroll = mini(_log_scroll + 1, maxi(0, log_visible.size() - 1))
				elif Input.is_action_just_pressed("attack") \
						or Input.is_action_just_pressed("ui_accept") \
						or Input.is_action_just_pressed("ui_cancel") \
						or Input.is_action_just_pressed("menu_back"):
					_log_mode = false
			else:
				if Input.is_action_just_pressed("ui_up"):
					if members_count > 0:
						_focus_area    = _FocusArea.MEMBER_TABLE
						_member_cursor = members_count - 1
					else:
						_focus_area = _FocusArea.GLOBAL_POLICY
				elif Input.is_action_just_pressed("attack") \
						or Input.is_action_just_pressed("ui_accept") \
						or Input.is_action_just_pressed("ui_right"):
					# ログ行でZ/右キーを押すとログモードを開始
					_log_mode   = true
					_log_scroll = 0
					if MessageLog != null:
						_log_scroll = maxi(0, MessageLog.get_visible_entries().size() - 1)
				elif Input.is_action_just_pressed("ui_cancel") \
						or Input.is_action_just_pressed("menu_back") \
						or Input.is_action_just_pressed("ui_left"):
					close_window()


## 名前列サブメニューの選択を実行する
func _execute_submenu(member_index: int, submenu_index: int) -> void:
	if member_index >= _sorted_members.size():
		return
	var ch := _sorted_members[member_index] as Character
	if not is_instance_valid(ch):
		return
	match submenu_index:
		0:  # 操作切替：常に有効
			var already := _controlled_char != null \
				and is_instance_valid(_controlled_char) \
				and ch == _controlled_char
			if not already:
				switch_requested.emit(ch)
				_controlled_char = ch
		1:  # アイテム：未装備品一覧を開く
			_item_char          = ch
			_cached_unequipped  = _get_unequipped_items(ch)
			_rebuild_grouped()
			_item_cursor        = 0
			_item_mode          = _ItemMode.ITEM_LIST


## アイテム画面の入力処理
func _handle_item_input() -> void:
	match _item_mode:
		_ItemMode.ITEM_LIST:
			if Input.is_action_just_pressed("ui_up"):
				_item_cursor = maxi(0, _item_cursor - 1)
			elif Input.is_action_just_pressed("ui_down"):
				_item_cursor = mini(_cached_grouped.size() - 1, _item_cursor + 1)
			elif Input.is_action_just_pressed("attack") \
					or Input.is_action_just_pressed("ui_accept") \
					or Input.is_action_just_pressed("ui_right"):
				if not _cached_grouped.is_empty() and _item_cursor < _cached_grouped.size():
					_selected_item = (_cached_grouped[_item_cursor] as Dictionary)["item"] as Dictionary
					_action_items  = _build_action_items(_item_char, _selected_item)
					if not _action_items.is_empty():
						_action_cursor = 0
						_item_mode     = _ItemMode.ACTION_MENU
			elif Input.is_action_just_pressed("ui_cancel") \
					or Input.is_action_just_pressed("menu_back") \
					or Input.is_action_just_pressed("ui_left"):
				_item_mode = _ItemMode.OFF

		_ItemMode.ACTION_MENU:
			if Input.is_action_just_pressed("ui_up"):
				_action_cursor = (_action_cursor - 1 + _action_items.size()) % _action_items.size()
			elif Input.is_action_just_pressed("ui_down"):
				_action_cursor = (_action_cursor + 1) % _action_items.size()
			elif Input.is_action_just_pressed("attack") \
					or Input.is_action_just_pressed("ui_accept") \
					or Input.is_action_just_pressed("ui_right"):
				var action: String = _action_items[_action_cursor] as String
				if action == "装備する":
					_do_equip(_item_char, _selected_item)
					var iname: String = _selected_item.get("item_name", "？") as String
					if MessageLog != null:
						MessageLog.add_system(
							"%s は %s を装備した" % [_get_char_name(_item_char), iname])
					_cached_unequipped = _get_unequipped_items(_item_char)
					_rebuild_grouped()
					_item_cursor = mini(_item_cursor, maxi(0, _cached_grouped.size() - 1))
					_item_mode   = _ItemMode.ITEM_LIST
				elif action == "渡す":
					_transfer_cursor = 0
					_item_mode       = _ItemMode.TRANSFER_SELECT
			elif Input.is_action_just_pressed("ui_cancel") \
					or Input.is_action_just_pressed("menu_back") \
					or Input.is_action_just_pressed("ui_left"):
				_item_mode = _ItemMode.ITEM_LIST

		_ItemMode.TRANSFER_SELECT:
			var targets := _get_transfer_targets()
			if Input.is_action_just_pressed("ui_up"):
				_transfer_cursor = maxi(0, _transfer_cursor - 1)
			elif Input.is_action_just_pressed("ui_down"):
				_transfer_cursor = mini(targets.size() - 1, _transfer_cursor + 1)
			elif Input.is_action_just_pressed("attack") \
					or Input.is_action_just_pressed("ui_accept") \
					or Input.is_action_just_pressed("ui_right"):
				if _transfer_cursor < targets.size():
					var to_ch := targets[_transfer_cursor] as Character
					var iname: String = _selected_item.get("item_name", "？") as String
					_do_transfer(_item_char, to_ch, _selected_item)
					if MessageLog != null:
						MessageLog.add_system(
							"%s は %s に %s を渡した" % [
								_get_char_name(_item_char), _get_char_name(to_ch), iname])
					_cached_unequipped = _get_unequipped_items(_item_char)
					_rebuild_grouped()
					_item_cursor = mini(_item_cursor, maxi(0, _cached_grouped.size() - 1))
					_item_mode   = _ItemMode.ITEM_LIST
			elif Input.is_action_just_pressed("ui_cancel") \
					or Input.is_action_just_pressed("menu_back") \
					or Input.is_action_just_pressed("ui_left"):
				_item_mode = _ItemMode.ACTION_MENU


## 同名アイテムをグループ化して _cached_grouped を再構築する
## 各エントリ: {"item": Dictionary, "count": int}（最初に見つかったアイテムを代表として使用）
func _rebuild_grouped() -> void:
	_cached_grouped = []
	for item_v: Variant in _cached_unequipped:
		var item := item_v as Dictionary
		var iname: String = item.get("item_name", "") as String
		var merged := false
		for g_v: Variant in _cached_grouped:
			var g := g_v as Dictionary
			if (g["item"] as Dictionary).get("item_name", "") == iname:
				g["count"] = int(g["count"]) + 1
				merged = true
				break
		if not merged:
			_cached_grouped.append({"item": item, "count": 1})


## 対象キャラの未装備アイテムを返す（装備スロットに入っていないもの）
func _get_unequipped_items(ch: Character) -> Array:
	if ch == null or not is_instance_valid(ch) or ch.character_data == null:
		return []
	var cd := ch.character_data
	var result: Array = []
	for item_v: Variant in cd.inventory:
		var item := item_v as Dictionary
		var equipped: bool = is_same(item, cd.equipped_weapon) \
			or is_same(item, cd.equipped_armor) \
			or is_same(item, cd.equipped_shield)
		if not equipped:
			result.append(item)
	return result


## そのキャラのクラスでアイテムを装備できるか
func _can_equip(ch: Character, item: Dictionary) -> bool:
	if ch == null or not is_instance_valid(ch) or ch.character_data == null:
		return false
	var itype: String = item.get("item_type", "") as String
	var cid: String   = ch.character_data.class_id
	var allowed: Array = CLASS_EQUIP_TYPES.get(cid, []) as Array
	return allowed.has(itype)


## アクションメニューの選択肢を構築する
func _build_action_items(ch: Character, item: Dictionary) -> Array[String]:
	var actions: Array[String] = []
	if _can_equip(ch, item):
		actions.append("装備する")
	# 渡す：リーダー操作中 かつ 対象が自分自身でないメンバーがいる場合
	if _is_editable() and _get_transfer_targets().size() > 0:
		actions.append("渡す")
	return actions


## アイテムを装備スロットにセットする（在庫は変更しない）
func _do_equip(ch: Character, item: Dictionary) -> void:
	if ch == null or not is_instance_valid(ch) or ch.character_data == null:
		return
	var cd := ch.character_data
	var cat: String = item.get("category", "") as String
	match cat:
		"weapon": cd.equipped_weapon = item
		"armor":  cd.equipped_armor  = item
		"shield": cd.equipped_shield = item
	ch.refresh_stats_from_equipment()


## アイテムを別キャラに受け渡す
func _do_transfer(from_ch: Character, to_ch: Character, item: Dictionary) -> void:
	if from_ch == null or to_ch == null:
		return
	if not is_instance_valid(from_ch) or not is_instance_valid(to_ch):
		return
	if from_ch.character_data == null or to_ch.character_data == null:
		return
	from_ch.character_data.inventory.erase(item)
	to_ch.character_data.inventory.append(item)


## 受け渡し先の候補リスト（_item_char 以外の有効パーティーメンバー）
func _get_transfer_targets() -> Array:
	var targets: Array = []
	for m_v: Variant in _sorted_members:
		var ch := m_v as Character
		if is_instance_valid(ch) and ch != _item_char:
			targets.append(ch)
	return targets


## キャラクターの表示名を返す
func _get_char_name(ch: Character) -> String:
	if ch == null or not is_instance_valid(ch):
		return "？"
	var cd := ch.character_data
	return cd.character_name \
		if (cd != null and not cd.character_name.is_empty()) \
		else String(ch.name)


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
			"item_pickup":      p[5] as String,
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
## 各要素: { "label", "type": "num"|"float"|"str"|"hp_mp"|"pct", ... }
func _get_stat_rows(ch: Character) -> Array:
	var rows: Array = []
	if ch == null or ch.character_data == null:
		return rows
	var cd: CharacterData = ch.character_data

	rows.append({"label": "HP",           "type": "hp_mp",  "current": ch.hp,   "max": ch.max_hp})
	var _magic_classes: Array = ["magician-fire", "magician-water", "healer"]
	if cd.class_id in _magic_classes:
		rows.append({"label": "MP",       "type": "hp_mp",  "current": ch.mp,   "max": ch.max_mp})
	else:
		rows.append({"label": "SP",       "type": "hp_mp",  "current": ch.sp,   "max": ch.max_sp})
	var _is_magic_cls := cd.class_id in _magic_classes
	var power_label := "魔法威力" if _is_magic_cls else "物理威力"
	rows.append({"label": power_label,    "type": "num",    "base": cd.power,
		"bonus": cd.get_weapon_power_bonus()})
	var skill_label := "魔法技量" if _is_magic_cls else "物理技量"
	rows.append({"label": skill_label, "type": "num",
		"base": cd.skill, "bonus": cd.get_weapon_skill_bonus()})
	# 防御強度（クラス固有値。保有するフィールドのみ表示）
	if cd.block_right_front > 0:
		rows.append({"label": "右手防御強度", "type": "num", "base": cd.block_right_front, "bonus": 0})
	if cd.block_left_front > 0:
		rows.append({"label": "左手防御強度", "type": "num", "base": cd.block_left_front,  "bonus": 0})
	if cd.block_front > 0:
		rows.append({"label": "正面防御強度", "type": "num", "base": cd.block_front,        "bonus": 0})
	rows.append({"label": "防御技量",      "type": "num",
		"base": cd.defense_accuracy, "bonus": 0})
	var phys_equip := cd.get_total_physical_resistance_score() - cd.physical_resistance
	rows.append({"label": "物理耐性",      "type": "num",
		"base": cd.physical_resistance, "bonus": phys_equip})
	var mag_equip := cd.get_total_magic_resistance_score() - cd.magic_resistance
	rows.append({"label": "魔法耐性",      "type": "num",
		"base": cd.magic_resistance, "bonus": mag_equip})
	rows.append({"label": "攻撃タイプ",    "type": "str",
		"value": ATTACK_TYPE_LABELS.get(cd.attack_type, cd.attack_type) as String})
	rows.append({"label": "射程(タイル)",  "type": "num",    "base": cd.attack_range, "bonus": cd.get_weapon_range_bonus()})
	rows.append({"label": "ランク",        "type": "str",    "value": cd.rank})
	rows.append({"label": "統率力",        "type": "num",    "base": cd.leadership, "bonus": 0})
	rows.append({"label": "従順度",        "type": "num",    "base": roundi(cd.obedience * 100.0), "bonus": 0})
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

	var pad:    float = maxf(18.0, gs_f * 0.20)
	var row_h:  float = maxf(26.0, gs_f * 0.28)
	var stat_h: float = maxf(18.0, gs_f * 0.21)  # ステータス行の高さ（本文より小さめ）

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
	var nm_h_col: Color = Color(1.0, 1.0, 0.3) \
		if (_focus_area == _FocusArea.MEMBER_TABLE and _col_cursor == 0) \
		else Color(0.55, 0.55, 0.70)
	_control.draw_string(_font, Vector2(col_xs[0], y + row_h * 0.66),
		"名前", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_label, nm_h_col)
	for ci: int in range(COL_HEADERS.size()):
		var h_col: Color = Color(1.0, 1.0, 0.3) \
			if (_focus_area == _FocusArea.MEMBER_TABLE and ci + 1 == _col_cursor) \
			else Color(0.55, 0.55, 0.70)
		_control.draw_string(_font, Vector2(col_xs[ci + 1], y + row_h * 0.66),
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
		# クラス名・ランクを付記
		if cd != null:
			var cls_jp: String = GlobalConstants.CLASS_NAME_JP.get(cd.class_id, "") as String
			if not cls_jp.is_empty():
				nm_str += " " + cls_jp
			if not cd.rank.is_empty():
				nm_str += " " + cd.rank
		var is_controlled: bool = _controlled_char != null \
			and is_instance_valid(_controlled_char) \
			and ch == _controlled_char
		var nm_focused := is_mem and (_col_cursor == 0)
		# 名前に操作状態を付記（操作中=★、名前列フォーカス時=▶）
		var nm_prefix := "★" if is_controlled else ("▶" if nm_focused else "  ")
		var nm_color: Color
		if is_controlled:  nm_color = Color(0.45, 1.0, 0.55)
		elif nm_focused:   nm_color = Color(1.0, 1.0, 0.3)
		else:              nm_color = Color(0.90, 0.90, 0.90)
		var name_w := col_xs[1] - col_xs[0] - 4.0
		_control.draw_string(_font, Vector2(col_xs[0], y + row_h * 0.67),
			nm_prefix + nm_str, HORIZONTAL_ALIGNMENT_LEFT, name_w, fs_body, nm_color)

		for ci: int in range(COL_HEADERS.size()):
			var lbl     := _get_col_label(ch, ci)
			var focused := is_mem and (ci + 1 == _col_cursor)
			var c_col: Color = Color(1.0, 1.0, 0.3) if focused else Color(0.80, 0.80, 0.80)
			var txt2    := "◀%s▶" % lbl if focused else lbl
			var col_w: float
			if ci + 2 < col_xs.size():
				col_w = col_xs[ci + 2] - col_xs[ci + 1] - 4.0
			else:
				col_w = px + panel_w - pad - col_xs[ci + 1]
			_control.draw_string(_font, Vector2(col_xs[ci + 1], y + row_h * 0.67),
				txt2, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs_body, c_col)

		y += row_h
	y += 8.0

	_draw_sep(px, y, panel_w, pad)
	y += 13.0

	# ── ログ行 ────────────────────────────────────────────────────────────────
	var is_log_row := (_focus_area == _FocusArea.CLOSE)
	if is_log_row:
		_control.draw_rect(Rect2(px + 4.0, y, panel_w - 8.0, row_h),
			Color(0.18, 0.24, 0.48, 0.70))
	var log_col: Color
	if _log_mode:     log_col = Color(0.40, 1.00, 0.80)
	elif is_log_row:  log_col = Color(1.0, 1.0, 0.3)
	else:             log_col = Color(0.68, 0.68, 0.82)
	var log_prefix := "▶  " if is_log_row else "    "
	var log_label  := log_prefix + ("ログ [表示中]" if _log_mode else "ログ")
	var log_tw     := _font.get_string_size(log_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_body).x
	_control.draw_string(_font,
		Vector2(px + panel_w * 0.5 - log_tw * 0.5, y + row_h * 0.67),
		log_label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_body, log_col)
	y += row_h

	# ── ステータスパネル（下部） ───────────────────────────────────────────────
	if _log_mode and MessageLog != null:
		_draw_log_section(px, y, panel_w, pad, fs_stat, stat_h)
	elif sel_ch != null:
		_draw_status_section(px, y, panel_w, pad, sel_ch, stat_rows, stat_h, fs_stat)

	# ── 操作ヒント ────────────────────────────────────────────────────────────
	# ── 名前列サブメニュー（オーバーレイ） ───────────────────────────────────────
	if _submenu_open and _focus_area == _FocusArea.MEMBER_TABLE:
		var sub_w:  float = 200.0
		var sub_ih: float = maxf(22.0, gs_f * 0.24)
		var sub_h:  float = SUBMENU_ITEMS.size() * sub_ih + 8.0
		var row_offset := py + pad + float(fs_title) + 10.0 + 13.0 + row_h + 8.0 + 13.0 \
			+ row_h + float(_member_cursor) * row_h
		var sub_x := col_xs[0]
		var sub_y := row_offset + row_h
		_control.draw_rect(Rect2(sub_x, sub_y, sub_w, sub_h), Color(0.10, 0.10, 0.20, 0.96))
		_control.draw_rect(Rect2(sub_x, sub_y, sub_w, sub_h),
			Color(0.60, 0.60, 0.85, 0.90), false, 1)
		for si: int in range(SUBMENU_ITEMS.size()):
			var sy := sub_y + 4.0 + float(si) * sub_ih
			var s_col: Color
			if si == _submenu_cursor:
				_control.draw_rect(Rect2(sub_x + 2.0, sy, sub_w - 4.0, sub_ih),
					Color(0.25, 0.35, 0.70, 0.80))
				s_col = Color(1.0, 1.0, 0.3)
			else:
				s_col = Color(0.80, 0.80, 0.90)
			_control.draw_string(_font, Vector2(sub_x + 10.0, sy + sub_ih * 0.72),
				SUBMENU_ITEMS[si], HORIZONTAL_ALIGNMENT_LEFT, sub_w - 14.0, fs_body, s_col)

	# ── アイテム画面オーバーレイ ──────────────────────────────────────────────────
	if _item_mode != _ItemMode.OFF:
		_draw_item_overlay(px, py, panel_w, pad, fs_body, fs_stat, stat_h)

	# ── 操作ヒント ────────────────────────────────────────────────────────────────
	var hint_str: String
	if _item_mode == _ItemMode.ITEM_LIST:
		hint_str = "↑↓:選択  Z/Enter:決定  Esc:戻る"
	elif _item_mode == _ItemMode.ACTION_MENU:
		hint_str = "↑↓:選択  Z/Enter:実行  Esc:戻る"
	elif _item_mode == _ItemMode.TRANSFER_SELECT:
		hint_str = "↑↓:選択  Z/Enter:渡す  Esc:戻る"
	elif _log_mode:
		hint_str = "↑↓:スクロール  Z/Enter/Esc:ログを閉じる  Tab:ウィンドウを閉じる"
	elif _submenu_open:
		hint_str = "↑↓:選択  Z/Enter:決定  Esc:キャンセル"
	elif _is_editable():
		hint_str = "↑↓:行移動  ←→:列/方針切替  Z/Enter:選択/値切替  Tab/Esc:閉じる"
	else:
		hint_str = "↑↓:行移動  ←→:列移動  Z/Enter:名前列で操作切替  Tab/Esc:閉じる（閲覧のみ）"
	_control.draw_string(_font,
		Vector2(px + pad, py + panel_h - float(fs_hint) - pad * 0.45),
		hint_str,
		HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2.0, fs_hint,
		Color(0.46, 0.46, 0.56))


## ログ表示セクション（MessageLog の共有バッファを一覧表示・色分け対応）
func _draw_log_section(px: float, y_start: float, panel_w: float, pad: float,
		fs_stat: int, stat_h: float) -> void:
	var y     := y_start + 13.0
	var avail := panel_w - pad * 2.0
	var lbl_x := px + pad

	_draw_sep(px, y_start, panel_w, pad)
	var log_visible: Array[Dictionary] = MessageLog.get_visible_entries() if MessageLog != null else []
	var visible_rows: int = 12
	var start_idx:    int = maxi(0, _log_scroll - visible_rows + 1)
	var end_idx:      int = mini(log_visible.size(), start_idx + visible_rows)

	_control.draw_string(_font, Vector2(lbl_x, y + float(fs_stat)),
		"ログ（%d件）  ↑↓:スクロール  Z/Esc:閉じる" % log_visible.size(),
		HORIZONTAL_ALIGNMENT_LEFT, avail, fs_stat, Color(0.80, 0.80, 1.00))
	y += float(fs_stat) + stat_h

	for i: int in range(start_idx, end_idx):
		var entry := log_visible[i]
		var is_cur := (i == _log_scroll)
		var base_col: Color = entry.get("color", Color.WHITE) as Color
		var e_col: Color = base_col if is_cur else base_col * Color(0.65, 0.65, 0.75, 1.0)
		var text: String = entry.get("text", "") as String
		_control.draw_string(_font, Vector2(lbl_x, y + stat_h * 0.75),
			"%d: %s" % [i + 1, text], HORIZONTAL_ALIGNMENT_LEFT, avail, fs_stat, e_col)
		y += stat_h


## ステータス詳細・装備・アイテムセクションを描画する（左：front画像 / 右：ステータス数値）
func _draw_status_section(px: float, y_start: float, panel_w: float, pad: float,
		ch: Character, stat_rows: Array, stat_h: float, fs_stat: int) -> void:
	var y     := y_start
	var avail := panel_w - pad * 2.0

	# ── 左右分割レイアウト ────────────────────────────────────────────────────
	# 左列: front画像（最大 180px 正方形）
	# 右列: ステータス数値テーブル
	var img_col_w: float = minf(avail * 0.22, 180.0)
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
			"pct":
				# 耐性(0.0〜1.0)をパーセント表示（base + bonus → total%）
				var base  : float = row.get("base",  0.0) as float
				var bonus : float = row.get("bonus", 0.0) as float
				var final_v := base + bonus
				var fc := Color(1.0, 1.0, 0.55) if bonus != 0.0 else c_val
				_control.draw_string(_font, Vector2(base_x,  y + stat_h * 0.75),
					"%d%%" % int(base * 100.0),        HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_val)
				_control.draw_string(_font, Vector2(bonus_x, y + stat_h * 0.75),
					"%+d%%" % int(bonus * 100.0),      HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_bonus)
				_control.draw_string(_font, Vector2(final_x, y + stat_h * 0.75),
					"→ %d%%" % int(final_v * 100.0),  HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, fc)
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
	var slot_defs: Array = [
		["武器", cd.equipped_weapon],
		["防具", cd.equipped_armor],
		["盾",   cd.equipped_shield],
	]
	for sd: Variant in slot_defs:
		var sd_arr   := sd as Array
		var equip    : Dictionary = sd_arr[1] as Dictionary
		var eq_icon_sz := stat_h - 2.0
		if equip.is_empty():
			_control.draw_string(_font, Vector2(lbl_x, y + stat_h * 0.75),
				"（なし）", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)
		else:
			# アイコンをlbl_xから描画（「武器」「防具」「盾」ラベルは非表示）
			var eq_icon_rect := Rect2(lbl_x, y + 1.0, eq_icon_sz, eq_icon_sz)
			var etex := _load_item_tex(equip)
			if etex != null:
				_control.draw_texture_rect(etex, eq_icon_rect, false)
			else:
				_control.draw_rect(eq_icon_rect, Color(0.35, 0.35, 0.50, 0.60))
			var ename: String = equip.get("item_name", "？") as String
			var estats: Dictionary = equip.get("stats", {}) as Dictionary
			var eparts: Array = []
			for k: String in ["power", "skill",
					"defense_strength", "physical_resistance", "magic_resistance"]:
				if estats.has(k):
					var v: int = int(estats[k])
					if v != 0:
						var jp: String = GlobalConstants.STAT_NAME_JP.get(k, k) as String
						eparts.append("%s+%d" % [jp, v])
			var estat_str := "" if eparts.is_empty() else " [%s]" % ", ".join(eparts)
			_control.draw_string(_font, Vector2(lbl_x + eq_icon_sz + 3.0, y + stat_h * 0.75),
				ename + estat_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_val)
		y += stat_h

	# ── 所持アイテム ──────────────────────────────────────────────────────────
	_draw_sep(px, y, panel_w, pad)
	y += 13.0
	_control.draw_string(_font, Vector2(lbl_x, y + float(fs_stat)),
		"所持アイテム", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_head)
	y += float(fs_stat) + 6.0
	# 未装備品のみ表示（同名アイテムは「×n」でまとめ表示）
	var inv: Array = _get_unequipped_items(ch)
	# 同名グループ化
	var inv_groups: Array = []
	for item_v2: Variant in inv:
		var item_d2 := item_v2 as Dictionary
		var iname2: String = item_d2.get("item_name", "") as String
		var merged2 := false
		for g2_v: Variant in inv_groups:
			var g2 := g2_v as Dictionary
			if (g2["item"] as Dictionary).get("item_name", "") == iname2:
				g2["count"] = int(g2["count"]) + 1
				merged2 = true
				break
		if not merged2:
			inv_groups.append({"item": item_d2, "count": 1})
	if inv_groups.is_empty():
		_control.draw_string(_font, Vector2(lbl_x, y + stat_h * 0.75),
			"（なし）", HORIZONTAL_ALIGNMENT_LEFT, -1, fs_stat, c_dim)
	else:
		var inv_icon_sz := stat_h - 2.0
		for g_v2: Variant in inv_groups:
			var g2    := g_v2 as Dictionary
			var item_d := g2["item"] as Dictionary
			var count2 := int(g2["count"])
			# アイコン描画
			var inv_icon_rect := Rect2(lbl_x, y + 1.0, inv_icon_sz, inv_icon_sz)
			var inv_tex := _load_item_tex(item_d)
			if inv_tex != null:
				_control.draw_texture_rect(inv_tex, inv_icon_rect, false)
			else:
				_control.draw_rect(inv_icon_rect, Color(0.35, 0.35, 0.50, 0.60))
			var iname: String = item_d.get("item_name", "???") as String
			var stats_d: Dictionary = item_d.get("stats", {}) as Dictionary
			# 主要補正値の要約（power/skill/physical_resistance 等）
			var stat_strs: Array = []
			for k: String in ["power", "skill", "defense_strength",
					"physical_resistance", "magic_resistance"]:
				if stats_d.has(k) and int(stats_d[k]) != 0:
					var jp: String = GlobalConstants.STAT_NAME_JP.get(k, k) as String
					stat_strs.append("%s+%d" % [jp, int(stats_d[k])])
			# 消耗品は effect を表示
			var effect_d: Dictionary = item_d.get("effect", {}) as Dictionary
			for ek: String in effect_d:
				stat_strs.append("%s:%d" % [ek, int(effect_d[ek])])
			var qty_str := " ×%d" % count2 if count2 > 1 else ""
			var stat_str := " [%s]" % ", ".join(stat_strs) if not stat_strs.is_empty() else ""
			_control.draw_string(_font, Vector2(lbl_x + inv_icon_sz + 3.0, y + stat_h * 0.75),
				iname + qty_str + stat_str, HORIZONTAL_ALIGNMENT_LEFT,
				avail - inv_icon_sz - 3.0, fs_stat, c_val)
			y += stat_h


# ── ユーティリティ ────────────────────────────────────────────────────────────

## アイテム辞書からアイコン画像を読み込む（image フィールド優先・なければ item_type から導出）
func _load_item_tex(item: Dictionary) -> Texture2D:
	var img_path := item.get("image", "") as String
	if img_path.is_empty():
		var itype := item.get("item_type", "") as String
		if not itype.is_empty():
			img_path = "assets/images/items/" + itype + ".png"
	if img_path.is_empty():
		return null
	if _item_tex_cache.has(img_path):
		return _item_tex_cache[img_path] as Texture2D
	var res_path := "res://" + img_path
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = ResourceLoader.load(res_path, "Texture2D") as Texture2D
	_item_tex_cache[img_path] = tex
	return tex


func _get_col_xs(px: float, panel_w: float, pad: float) -> Array[float]:
	var avail  := panel_w - pad * 2.0
	var name_r := 0.22
	var item_r := (1.0 - name_r) / float(COL_HEADERS.size())
	var xs: Array[float] = []
	xs.append(px + pad)  # [0] 名前列
	for ci: int in range(COL_HEADERS.size()):
		xs.append(px + pad + avail * (name_r + item_r * float(ci)))  # [1..n] 指示列
	return xs


func _draw_sep(px: float, y: float, panel_w: float, pad: float) -> void:
	_control.draw_line(
		Vector2(px + pad, y),
		Vector2(px + panel_w - pad, y),
		Color(0.35, 0.35, 0.55, 0.65), 1)


## アイテム画面のオーバーレイ（_item_mode に応じて切替描画）
func _draw_item_overlay(main_px: float, main_py: float, main_pw: float,
		pad: float, fs_body: int, fs_stat: int, row_h: float) -> void:
	# オーバーレイ幅はメインパネルより少し狭め
	var ow := minf(main_pw * 0.82, 700.0)
	var ox := main_px + (main_pw - ow) * 0.5

	match _item_mode:
		_ItemMode.ITEM_LIST:
			_draw_item_list_overlay(ox, main_py, ow, pad, fs_body, fs_stat, row_h)
		_ItemMode.ACTION_MENU:
			_draw_action_menu_overlay(ox, main_py, ow, pad, fs_body, row_h)
		_ItemMode.TRANSFER_SELECT:
			_draw_transfer_select_overlay(ox, main_py, ow, pad, fs_body, fs_stat, row_h)


## アイテム一覧オーバーレイ（未装備品リスト）
func _draw_item_list_overlay(ox: float, main_py: float, ow: float,
		pad: float, fs_body: int, fs_stat: int, row_h: float) -> void:
	var title_h: float = float(fs_body) + 10.0
	var groups := _cached_grouped
	var list_rows: int = maxi(1, groups.size())
	var oh: float = pad + title_h + 8.0 + float(list_rows) * row_h + pad
	var oy := main_py + 80.0

	_control.draw_rect(Rect2(ox, oy, ow, oh), Color(0.07, 0.07, 0.15, 0.97))
	_control.draw_rect(Rect2(ox, oy, ow, oh), Color(0.55, 0.55, 0.80, 0.90), false, 2)

	var cname := _get_char_name(_item_char)
	_control.draw_string(_font, Vector2(ox + pad, oy + pad + float(fs_body)),
		"%s の所持アイテム（未装備品）" % cname,
		HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0, fs_body, Color(0.88, 0.88, 1.00))

	var y := oy + pad + title_h + 8.0
	if groups.is_empty():
		_control.draw_string(_font, Vector2(ox + pad, y + row_h * 0.70),
			"アイテムなし", HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0,
			fs_stat, Color(0.50, 0.50, 0.60))
	else:
		var icon_sz := row_h - 6.0
		for ii: int in range(groups.size()):
			var group := groups[ii] as Dictionary
			var item  := group["item"] as Dictionary
			var count := int(group["count"])
			var is_cur := (ii == _item_cursor)
			if is_cur:
				_control.draw_rect(Rect2(ox + 2.0, y, ow - 4.0, row_h),
					Color(0.20, 0.28, 0.55, 0.80))
			# アイコン描画
			var icon_rect := Rect2(ox + pad, y + 3.0, icon_sz, icon_sz)
			var itex := _load_item_tex(item)
			if itex != null:
				_control.draw_texture_rect(itex, icon_rect, false)
			else:
				_control.draw_rect(icon_rect, Color(0.35, 0.35, 0.50, 0.70))
			var text_x := ox + pad + icon_sz + 4.0
			var iname: String = item.get("item_name", "？") as String
			var count_str := " ×%d" % count if count > 1 else ""
			# 主要補正値サマリ（日本語表記）
			var stats_d: Dictionary = item.get("stats", {}) as Dictionary
			var parts: Array = []
			for k: String in ["power", "skill",
					"physical_resistance", "magic_resistance", "defense_strength"]:
				if stats_d.has(k):
					var v: int = int(stats_d[k])
					if v != 0:
						var jp: String = GlobalConstants.STAT_NAME_JP.get(k, k) as String
						parts.append("%s+%d" % [jp, v])
			var effect_d: Dictionary = item.get("effect", {}) as Dictionary
			for ek: String in effect_d:
				parts.append("%s:%d" % [ek, int(effect_d[ek])])
			var stat_str := "" if parts.is_empty() else " [%s]" % ", ".join(parts)
			var can_equip := _can_equip(_item_char, item)
			var equip_mark := "◆" if can_equip else "  "
			var txt := "%s %s%s%s" % [equip_mark, iname, count_str, stat_str]
			# 装備可能：通常色（白/黄）、装備不可：灰色
			var c: Color
			if is_cur:
				c = Color(1.0, 1.0, 0.3)
			elif can_equip:
				c = Color(0.90, 0.90, 0.95)
			else:
				c = Color(0.50, 0.50, 0.58)
			_control.draw_string(_font, Vector2(text_x, y + row_h * 0.70),
				txt, HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0 - icon_sz - 4.0, fs_stat, c)
			y += row_h


## アクションメニューオーバーレイ
func _draw_action_menu_overlay(ox: float, main_py: float, ow: float,
		pad: float, fs_body: int, row_h: float) -> void:
	var iname: String = _selected_item.get("item_name", "？") as String
	var title_h: float = float(fs_body) + 10.0
	var list_rows: int = maxi(1, _action_items.size())
	var oh: float = pad + title_h + 8.0 + float(list_rows) * row_h + pad
	var oy := main_py + 80.0

	_control.draw_rect(Rect2(ox, oy, ow, oh), Color(0.07, 0.07, 0.15, 0.97))
	_control.draw_rect(Rect2(ox, oy, ow, oh), Color(0.55, 0.55, 0.80, 0.90), false, 2)

	_control.draw_string(_font, Vector2(ox + pad, oy + pad + float(fs_body)),
		iname + " をどうする？",
		HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0, fs_body, Color(0.88, 0.88, 1.00))

	var y := oy + pad + title_h + 8.0
	if _action_items.is_empty():
		_control.draw_string(_font, Vector2(ox + pad, y + row_h * 0.70),
			"操作できません", HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0,
			fs_body, Color(0.60, 0.60, 0.70))
	else:
		for ai: int in range(_action_items.size()):
			var is_cur := (ai == _action_cursor)
			if is_cur:
				_control.draw_rect(Rect2(ox + 2.0, y, ow - 4.0, row_h),
					Color(0.20, 0.28, 0.55, 0.80))
			var c: Color = Color(1.0, 1.0, 0.3) if is_cur else Color(0.85, 0.85, 0.90)
			var prefix := "▶ " if is_cur else "   "
			_control.draw_string(_font, Vector2(ox + pad, y + row_h * 0.70),
				prefix + (_action_items[ai] as String),
				HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0, fs_body, c)
			y += row_h


## 受け渡し相手選択オーバーレイ
func _draw_transfer_select_overlay(ox: float, main_py: float, ow: float,
		pad: float, fs_body: int, fs_stat: int, row_h: float) -> void:
	var iname: String = _selected_item.get("item_name", "？") as String
	var targets := _get_transfer_targets()
	var title_h: float = float(fs_body) + 10.0
	var list_rows: int = maxi(1, targets.size())
	var oh: float = pad + title_h + 8.0 + float(list_rows) * row_h + pad
	var oy := main_py + 80.0

	_control.draw_rect(Rect2(ox, oy, ow, oh), Color(0.07, 0.07, 0.15, 0.97))
	_control.draw_rect(Rect2(ox, oy, ow, oh), Color(0.55, 0.55, 0.80, 0.90), false, 2)

	_control.draw_string(_font, Vector2(ox + pad, oy + pad + float(fs_body)),
		"%s を誰に渡す？" % iname,
		HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0, fs_body, Color(0.88, 0.88, 1.00))

	var y := oy + pad + title_h + 8.0
	if targets.is_empty():
		_control.draw_string(_font, Vector2(ox + pad, y + row_h * 0.70),
			"渡せる相手がいません", HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0,
			fs_stat, Color(0.50, 0.50, 0.60))
	else:
		for ti: int in range(targets.size()):
			var to_ch := targets[ti] as Character
			if not is_instance_valid(to_ch):
				continue
			var is_cur := (ti == _transfer_cursor)
			if is_cur:
				_control.draw_rect(Rect2(ox + 2.0, y, ow - 4.0, row_h),
					Color(0.20, 0.28, 0.55, 0.80))
			var c: Color = Color(1.0, 1.0, 0.3) if is_cur else Color(0.85, 0.85, 0.90)
			var prefix := "▶ " if is_cur else "   "
			var tname := _get_char_name(to_ch)
			var inv_count: int = to_ch.character_data.inventory.size() \
				if to_ch.character_data != null else 0
			_control.draw_string(_font, Vector2(ox + pad, y + row_h * 0.70),
				"%s%s  （所持 %d 件）" % [prefix, tname, inv_count],
				HORIZONTAL_ALIGNMENT_LEFT, ow - pad * 2.0, fs_stat, c)
			y += row_h
