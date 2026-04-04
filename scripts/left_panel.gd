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

	# キャラクター名 + クラス名 + ランク
	var name_str: String = c.character_data.character_name \
		if (c.character_data != null and not c.character_data.character_name.is_empty()) \
		else String(c.name)
	var class_jp := ""
	var rank_str := ""
	if c.character_data != null:
		class_jp = GlobalConstants.CLASS_NAME_JP.get(c.character_data.class_id, "") as String
		rank_str = c.character_data.rank
	var header := name_str
	if not class_jp.is_empty():
		header += " " + class_jp
	if not rank_str.is_empty():
		header += " " + rank_str
	_control.draw_string(_font,
		Vector2(tx, fy + float(pad) + 13.0),
		header, HORIZONTAL_ALIGNMENT_LEFT, tw, 13, Color.WHITE)

	# HPバー・MPバー（絶対値表示）
	# ゲージ幅は HP_REF / MP_REF を基準とした絶対値。
	# 背景（暗）= バー全幅、中間（薄暗）= max_hp/REF まで、前景（色付き）= current/REF まで。
	var bar_y := fy + float(pad) + 20.0
	var bar_h := 7.0

	var hp_cur_r := minf(float(c.hp)    / HP_REF, 1.0)
	var hp_max_r := minf(float(c.max_hp)/ HP_REF, 1.0)
	_draw_bar(tx, bar_y, tw, bar_h, hp_cur_r, Color.TRANSPARENT, hp_max_r)

	var content_y := bar_y + bar_h + 4.0   # バー直下の開始 y
	var class_id := c.character_data.class_id if c.character_data != null else ""
	if class_id in MAGIC_CLASS_IDS:
		# 魔法クラス：MPバー（濃い青）
		if c.max_mp > 0:
			var mp_cur_r := minf(float(c.mp)    / MP_REF, 1.0)
			var mp_max_r := minf(float(c.max_mp)/ MP_REF, 1.0)
			_draw_bar(tx, content_y, tw, bar_h, mp_cur_r, Color(0.2, 0.5, 1.0), mp_max_r)
			content_y += bar_h + 4.0
	else:
		# 非魔法クラス：SPバー（水色）
		if c.max_sp > 0:
			var sp_cur_r := minf(float(c.sp)    / SP_REF, 1.0)
			var sp_max_r := minf(float(c.max_sp)/ SP_REF, 1.0)
			_draw_bar(tx, content_y, tw, bar_h, sp_cur_r, Color(0.4, 0.8, 1.0), sp_max_r)
			content_y += bar_h + 4.0

	# 状態テキスト
	var cond     := _condition(c)
	var cond_col := Color(0.4, 0.9, 0.4) if cond == "healthy" \
		else (Color(1.0, 0.8, 0.2) if cond == "wounded" else Color(1.0, 0.35, 0.35))
	_control.draw_string(_font,
		Vector2(tx, content_y + 10.0),
		cond, HORIZONTAL_ALIGNMENT_LEFT, tw, 10, cond_col)
	content_y += 13.0

	# 指示状態（OrderWindow の COL_LABELS と完全一致する表記）
	var ord: Dictionary = c.current_order
	var move_a: String  = {"explore": "探索", "same_room": "同じ部屋", "cluster": "密集",
		"guard_room": "部屋を守る", "standby": "待機"}.get(
		ord.get("move",             "same_room") as String, "同じ部屋") as String
	var bform_a: String = {"surround": "包囲", "front": "前衛", "rear": "後衛",
		"same_as_leader": "リーダーと同じ"}.get(
		ord.get("battle_formation", "surround")  as String, "包囲") as String
	var combat_a: String = {"aggressive": "積極攻撃", "support": "援護", "standby": "待機"}.get(
		ord.get("combat",           "aggressive") as String, "積極攻撃") as String
	var target_a: String = {"nearest": "最近傍", "weakest": "最弱", "same_as_leader": "リーダーと同じ"}.get(
		ord.get("target",           "nearest")   as String, "最近傍") as String
	var lowh_a: String   = {"keep_fighting": "戦い続ける", "retreat": "後退", "flee": "逃走"}.get(
		ord.get("on_low_hp",        "retreat")   as String, "後退") as String
	var pickup_a: String = {"aggressive": "積極的に拾う", "passive": "近くのみ", "avoid": "拾わない"}.get(
		ord.get("item_pickup",      "aggressive") as String, "積極的に拾う") as String
	var ord_color := Color(0.55, 0.90, 0.65)
	var fs_ord := 9
	_control.draw_string(_font,
		Vector2(tx, content_y + 9.0),
		"%s / %s / %s" % [move_a, combat_a, target_a],
		HORIZONTAL_ALIGNMENT_LEFT, tw, fs_ord, ord_color)
	_control.draw_string(_font,
		Vector2(tx, content_y + 21.0),
		"%s / %s / %s" % [bform_a, lowh_a, pickup_a],
		HORIZONTAL_ALIGNMENT_LEFT, tw, fs_ord, ord_color)

	# 消耗品表示（全キャラ。所持品なしの場合は非表示）
	if c.character_data != null:
		var consumables := c.character_data.get_consumables()
		if not consumables.is_empty():
			# 同名アイテムをまとめて「名前×N」形式に集約
			var counts: Dictionary = {}
			var order: Array = []
			for item: Dictionary in consumables:
				var iname: String = item.get("item_name", "アイテム") as String
				if not counts.has(iname):
					counts[iname] = 0
					order.append(iname)
				counts[iname] = int(counts[iname]) + 1
			var parts: Array = []
			for iname: String in order:
				var n: int = int(counts[iname])
				parts.append("%s×%d" % [iname, n] if n > 1 else iname as String)
			var item_text: String = "消: " + "  ".join(parts)
			_control.draw_string(_font,
				Vector2(tx, content_y + 33.0),
				item_text, HORIZONTAL_ALIGNMENT_LEFT, tw, 9, Color(0.9, 0.85, 0.5))

	# カード下区切り線
	_control.draw_line(
		Vector2(fx, fy + fh - 1),
		Vector2(fx + fw, fy + fh - 1),
		Color(0.25, 0.25, 0.30, 0.7), 1)


## HP/MP/SP の絶対値表示用基準値（これがバー全幅に対応する量）
const HP_REF: float = 300.0
const MP_REF: float = 120.0
const SP_REF: float = 120.0

## 魔法クラスのID一覧（MPバーを表示するクラス。それ以外はSPバーを表示）
const MAGIC_CLASS_IDS: Array = ["magician-fire", "magician-water", "healer"]

## fill_ratio  : 前景（現在値）の幅 = w * fill_ratio
## fill_color  : 前景色の指定（TRANSPARENT なら HP 残量で自動色分け）
## max_ratio   : 中間層（最大値）の幅 = w * max_ratio。1.0 なら全幅
func _draw_bar(x: float, y: float, w: float, h: float, fill_ratio: float,
		fill_color: Color = Color.TRANSPARENT, max_ratio: float = 1.0) -> void:
	# 暗い全幅背景
	_control.draw_rect(Rect2(x, y, w, h), Color(0.10, 0.10, 0.13))
	# 中間層（最大値の位置まで赤く表示 → 前景で覆われた部分が現在値、残りが減少量）
	var cap_w := w * clampf(max_ratio, 0.0, 1.0)
	if cap_w > 0.0:
		_control.draw_rect(Rect2(x, y, cap_w, h), Color(0.55, 0.10, 0.10))
	# 前景（現在値）
	if fill_ratio > 0.0:
		var fill: Color
		if fill_color.a > 0.0:
			fill = fill_color
		else:
			# HP 色: max に対する割合で色分け
			var ratio_of_max := fill_ratio / max_ratio if max_ratio > 0.0 else 0.0
			if ratio_of_max > 0.6:
				fill = Color(0.25, 0.80, 0.30)
			elif ratio_of_max > 0.3:
				fill = Color(0.90, 0.70, 0.10)
			else:
				fill = Color(0.90, 0.20, 0.20)
		_control.draw_rect(Rect2(x, y, w * clampf(fill_ratio, 0.0, 1.0), h), fill)


func _condition(c: Character) -> String:
	var ratio := float(c.hp) / float(c.max_hp) if c.max_hp > 0 else 0.0
	if ratio > 0.6:
		return "healthy"
	elif ratio > 0.3:
		return "wounded"
	return "critical"
