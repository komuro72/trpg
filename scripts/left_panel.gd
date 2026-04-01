class_name LeftPanel
extends CanvasLayer

## 左パネル：味方ステータス表示
## Phase 5: フェイスアイコン・名前・HPバー・MPバー・状態テキストを表示
##          アクティブキャラクターは青枠でハイライト。下25%はミニマップ予約エリア

var _party: Party
var _active_character: Character
var _control: Control
var _font: Font

## フェイスアイコン用 TextureRect ノードのキャッシュ（Character → TextureRect）
var _icon_nodes: Dictionary = {}


func setup(party: Party) -> void:
	_party = party


func set_active_character(c: Character) -> void:
	_active_character = c


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
		_update_icon_nodes()
		_control.queue_redraw()


## TextureRect ノードをパーティーに合わせて作成・更新・削除する
func _update_icon_nodes() -> void:
	if _party == null:
		return
	var gs        := GlobalConstants.GRID_SIZE
	var pw        := GlobalConstants.PANEL_TILES * gs
	var vh        := _control.size.y
	var minimap_h := int(vh * 0.25)
	var ally_h    := vh - minimap_h
	# ソート済みメンバーリストを使用（リーダー先頭・加入順）
	var members := _party.sorted_members()
	var count   := members.size()
	var pad     := 6

	# 現在のメンバーセット
	var current_set: Dictionary = {}
	for m: Variant in members:
		current_set[m] = true

	# 不要ノードを削除
	for key: Variant in _icon_nodes.keys():
		if not current_set.has(key) or not is_instance_valid(key as Object):
			(_icon_nodes[key] as TextureRect).queue_free()
			_icon_nodes.erase(key)

	if count == 0:
		return

	var card_h := ally_h / count
	for i: int in range(count):
		var member := members[i] as Character
		if not is_instance_valid(member):
			continue

		var icon_size := mini(mini(int(float(card_h)) - pad * 2, int(float(pw) * 0.42)), 88)
		var icon_x    := pad
		var icon_y    := i * card_h + pad

		# ノードを取得または新規作成
		var tr: TextureRect
		if _icon_nodes.has(member):
			tr = _icon_nodes[member] as TextureRect
		else:
			tr = TextureRect.new()
			tr.stretch_mode  = TextureRect.STRETCH_SCALE
			tr.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
			tr.mouse_filter  = Control.MOUSE_FILTER_IGNORE
			_control.add_child(tr)
			_icon_nodes[member] = tr

		# 位置・サイズを更新
		tr.position = Vector2(float(icon_x), float(icon_y))
		tr.size     = Vector2(float(icon_size), float(icon_size))

		# テクスチャを更新
		var icon_path: String = ""
		if member.character_data != null:
			icon_path = member.character_data.sprite_face
			if icon_path.is_empty():
				icon_path = member.character_data.sprite_front
		if not icon_path.is_empty():
			var tex := load(icon_path) as Texture2D
			if tex != null:
				tr.texture = tex
				tr.visible = true
				continue
		# テクスチャなし → 非表示（カスタムドローでプレースホルダー色を描画）
		tr.visible = false


func _on_draw() -> void:
	if _party == null:
		return
	var gs         := GlobalConstants.GRID_SIZE
	var pw         := GlobalConstants.PANEL_TILES * gs
	var vh         := _control.size.y
	var minimap_h  := int(vh * 0.25)
	var ally_h     := vh - minimap_h

	# パネル背景
	_control.draw_rect(Rect2(0, 0, pw, vh), Color(0.08, 0.08, 0.12, 0.92))

	# セパレーター（右端ライン）
	_control.draw_line(Vector2(pw, 0), Vector2(pw, vh), Color(0.3, 0.3, 0.4, 0.8), 1)

	# 味方カードを描画（リーダー先頭・加入順）
	var members := _party.sorted_members()
	var count   := members.size()
	if count > 0:
		var card_h := ally_h / count
		for i: int in range(count):
			var member := members[i] as Character
			if is_instance_valid(member):
				_draw_ally_card(member, 0.0, float(i * card_h), float(pw), float(card_h))

	# ミニマップ予約エリア
	_control.draw_rect(Rect2(0, ally_h, pw, minimap_h), Color(0.04, 0.04, 0.06, 0.95))
	_control.draw_line(Vector2(0, ally_h), Vector2(pw, ally_h), Color(0.3, 0.3, 0.4, 0.8), 1)
	if _font != null:
		_control.draw_string(_font,
			Vector2(float(pw) * 0.5 - 16.0, float(ally_h) + float(minimap_h) * 0.55),
			"MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.5, 0.7))


func _draw_ally_card(c: Character, fx: float, fy: float, fw: float, fh: float) -> void:
	var pad := 6

	# アクティブキャラクターは青枠
	if _active_character != null and c == _active_character:
		_control.draw_rect(Rect2(fx + 1, fy + 1, fw - 2, fh - 2),
			Color(0.3, 0.5, 0.9, 0.45))
		_control.draw_rect(Rect2(fx, fy, fw, fh),
			Color(0.4, 0.6, 1.0, 0.8), false, 2)

	# フェイスアイコン領域（TextureRect が非表示の場合はプレースホルダー色を描画）
	var icon_size := mini(mini(int(fh) - pad * 2, int(fw * 0.42)), 88)
	var icon_rect := Rect2(fx + pad, fy + pad, icon_size, icon_size)
	var has_icon  := _icon_nodes.has(c) and (_icon_nodes[c] as TextureRect).visible
	if not has_icon:
		_control.draw_rect(icon_rect, c.placeholder_color)

	if _font == null:
		return

	# 右側テキストエリア
	var tx := fx + float(pad + icon_size + pad)
	var tw := fw - tx - float(pad)

	# キャラクター名
	var name_str: String = c.character_data.character_name \
		if (c.character_data != null and not c.character_data.character_name.is_empty()) \
		else String(c.name)
	_control.draw_string(_font,
		Vector2(tx, fy + float(pad) + 13.0),
		name_str, HORIZONTAL_ALIGNMENT_LEFT, tw, 13, Color.WHITE)

	# HPバー
	var hp_ratio := float(c.hp) / float(c.max_hp) if c.max_hp > 0 else 0.0
	var bar_y    := fy + float(pad) + 20.0
	var bar_h    := 7.0
	_draw_bar(tx, bar_y, tw, bar_h, hp_ratio)
	_control.draw_string(_font,
		Vector2(tx, bar_y + bar_h + 10.0),
		"HP %d/%d" % [c.hp, c.max_hp],
		HORIZONTAL_ALIGNMENT_LEFT, tw, 10, Color(0.75, 0.75, 0.75))

	# MPバー（将来用：空）
	var mp_bar_y := bar_y + bar_h + 18.0
	_draw_bar(tx, mp_bar_y, tw, bar_h, 0.0)

	# 状態テキスト
	var cond     := _condition(c)
	var cond_col := Color(0.4, 0.9, 0.4) if cond == "healthy" \
		else (Color(1.0, 0.8, 0.2) if cond == "wounded" else Color(1.0, 0.35, 0.35))
	_control.draw_string(_font,
		Vector2(tx, mp_bar_y + bar_h + 10.0),
		cond, HORIZONTAL_ALIGNMENT_LEFT, tw, 10, cond_col)

	# 指示状態（6項目を1文字略称で2行表示）
	# 行1: 移動+戦闘+標的  行2: 隊形+低HP+取得
	# 移動: 探=explore 室=same_room 密=cluster 守=guard_room 待=standby
	# 戦闘: 積=aggressive 援=support 待=standby
	# 標的: 近=nearest 弱=weakest 同=same_as_leader
	# 隊形: 囲=surround 前=front 後=rear 同=same_as_leader
	# 低HP: 継=keep_fighting 退=retreat 逃=flee
	# 取得: 拾=aggressive 近=passive 無=avoid
	var ord: Dictionary = c.current_order
	var move_a: String  = {"explore": "探", "same_room": "室", "cluster": "密",
		"guard_room": "守", "standby": "待"}.get(
		ord.get("move",             "same_room") as String, "室") as String
	var bform_a: String = {"surround": "囲", "front": "前", "rear": "後",
		"same_as_leader": "同"}.get(
		ord.get("battle_formation", "surround")  as String, "囲") as String
	var combat_a: String = {"aggressive": "積", "support": "援", "standby": "待"}.get(
		ord.get("combat",           "aggressive") as String, "積") as String
	var target_a: String = {"nearest": "近", "weakest": "弱", "same_as_leader": "同"}.get(
		ord.get("target",           "nearest")   as String, "近") as String
	var lowh_a: String   = {"keep_fighting": "継", "retreat": "退", "flee": "逃"}.get(
		ord.get("on_low_hp",        "retreat")   as String, "退") as String
	var pickup_a: String = {"aggressive": "拾", "passive": "近", "avoid": "無"}.get(
		ord.get("item_pickup",      "aggressive") as String, "拾") as String
	var ord_color := Color(0.55, 0.90, 0.65)
	_control.draw_string(_font,
		Vector2(tx, mp_bar_y + bar_h + 22.0),
		"%s %s %s" % [move_a, combat_a, target_a],
		HORIZONTAL_ALIGNMENT_LEFT, tw, 10, ord_color)
	_control.draw_string(_font,
		Vector2(tx, mp_bar_y + bar_h + 34.0),
		"%s %s %s" % [bform_a, lowh_a, pickup_a],
		HORIZONTAL_ALIGNMENT_LEFT, tw, 10, ord_color)

	# カード下区切り線
	_control.draw_line(
		Vector2(fx, fy + fh - 1),
		Vector2(fx + fw, fy + fh - 1),
		Color(0.25, 0.25, 0.30, 0.7), 1)


func _draw_bar(x: float, y: float, w: float, h: float, ratio: float) -> void:
	_control.draw_rect(Rect2(x, y, w, h), Color(0.15, 0.15, 0.18))
	if ratio > 0.0:
		var fill: Color
		if ratio > 0.6:
			fill = Color(0.25, 0.80, 0.30)
		elif ratio > 0.3:
			fill = Color(0.90, 0.70, 0.10)
		else:
			fill = Color(0.90, 0.20, 0.20)
		_control.draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), h), fill)


func _condition(c: Character) -> String:
	var ratio := float(c.hp) / float(c.max_hp) if c.max_hp > 0 else 0.0
	if ratio > 0.6:
		return "healthy"
	elif ratio > 0.3:
		return "wounded"
	return "critical"
