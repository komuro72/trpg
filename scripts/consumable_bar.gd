class_name ConsumableBar
extends CanvasLayer

## 消耗品バー：画面上部・部屋名ラベルの左側に操作キャラの消耗品を表示（Phase 10-3〜）
## 消耗品を種類ごとにアイコン（カラーブロック）＋「×n」で横並び表示。
## 選択中の種類は白い枠でハイライトする。

## アイテム種別ごとのアイコン色
const ITEM_COLORS: Dictionary = {
	"potion_heal":   Color(0.85, 0.20, 0.20),   # 赤：HP回復
	"potion_energy": Color(0.20, 0.40, 0.90),   # 青：エネルギー回復
	# legacy（旧保存データ対応。将来削除）
	"potion_hp":     Color(0.85, 0.20, 0.20),
	"potion_mp":     Color(0.20, 0.40, 0.90),
	"potion_sp":     Color(0.20, 0.80, 0.30),
}
const DEFAULT_COLOR := Color(1.0, 0.85, 0.15)  # 黄：その他消耗品

const ICON_SIZE_RATIO: float = 0.50   # GRID_SIZE に対するアイコンサイズの比率
const ITEM_GAP:        int   = 6      # アイテム間余白（px）
const H_PAD:           int   = 8      # バー左右内側余白（px）
const COUNT_FONT_SIZE: int   = 10     # 数量表示フォントサイズ（アイコン右下）
const DIM_MODULATE := Color(0.45, 0.45, 0.45, 0.75)  # 使用/装備不可時のグレーアウト色
const DETAIL_BOX_W: float = 280.0     # 詳細表示エリアの幅（px）
const DETAIL_BOX_H_EXPANDED: float = 220.0  # ACTION/TRANSFER モード時の拡張高さ

var _character: Character = null
var _control: Control
var _font: Font
var _tex_cache: Dictionary = {}  # image_path -> Texture2D or null

## V スロットのクールダウン残り秒数（player_controller が毎フレーム更新）
var v_slot_cooldown: float = 0.0

## 表示モード（GlobalConstants.ConsumableDisplayMode を使用）
var display_mode: GlobalConstants.ConsumableDisplayMode = GlobalConstants.ConsumableDisplayMode.NORMAL

## ITEM_SELECT モード用（_item_ui_display の辞書配列）
var item_list:  Array = []
var item_index: int   = 0

## ACTION_SELECT モード用（アクション文字列配列）
var action_list:  Array = []
var action_index: int   = 0
## 各アクションの詳細情報（右側パネル表示用）。要素: {"label": String, "lines": Array[String]}
var action_info: Array = []

## TRANSFER_SELECT モード用（キャラ名文字列配列）
var transfer_list:  Array = []
var transfer_index: int   = 0
## 各メンバーの詳細情報。要素: {"name": String, "can_equip": bool, "lines": Array[String]}
var transfer_info: Array = []
## パネル見出し（例：「渡す：渡す先」「渡して装備させる：渡す先」）
var transfer_label: String = ""

## 後方互換フィールド（旧コードとの整合用。display_mode に統一予定）
var is_selecting: bool = false
var select_index: int  = -1


## 操作キャラクターを設定して表示を更新する
func update_character(character: Character) -> void:
	_character = character
	refresh()


## 表示を再描画する（選択変更・アイテム増減時に呼ぶ）
func refresh() -> void:
	if _control != null:
		_control.queue_redraw()


func _ready() -> void:
	layer = 11
	_font = ThemeDB.fallback_font
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.focus_mode = Control.FOCUS_NONE
	add_child(_control)
	_control.draw.connect(_on_draw)


func _load_texture(image_path: String) -> Texture2D:
	if image_path.is_empty():
		return null
	if _tex_cache.has(image_path):
		return _tex_cache[image_path] as Texture2D
	var res_path := "res://" + image_path
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = ResourceLoader.load(res_path, "Texture2D") as Texture2D
	_tex_cache[image_path] = tex
	return tex


func _on_draw() -> void:
	# モード別描画（ACTION_SELECT / TRANSFER_SELECT は ITEM_SELECT と共通のアイコン列 +
	# 右側パネルに動的内容を描画する統合 UI）
	match display_mode:
		GlobalConstants.ConsumableDisplayMode.ACTION_SELECT, \
		GlobalConstants.ConsumableDisplayMode.TRANSFER_SELECT:
			_draw_item_list()
			return

	# V スロットクールダウン表示（消耗品がなくても表示する）
	if v_slot_cooldown > 0.0 and _font != null:
		var gs    := GlobalConstants.GRID_SIZE
		var pw    := GlobalConstants.PANEL_TILES * gs
		var by    := float(gs) * 0.35
		var box_h := float(gs) * 0.65
		var vw    := _control.size.x
		var cx    := float(pw) + (float(vw - 2 * pw)) * 0.5
		var cd_text := "V: %d" % ceili(v_slot_cooldown)
		var bx    := cx + 80.0
		_control.draw_rect(Rect2(bx - 4.0, by + 2.0, 54.0, box_h - 4.0),
				Color(0.1, 0.05, 0.0, 0.75))
		_control.draw_string(_font, Vector2(bx, by + box_h * 0.72),
				cd_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color(1.0, 0.65, 0.2, 0.95))

	# ITEM_SELECT モード：item_list（player_controller が設定した表示用リスト）を使用
	if display_mode == GlobalConstants.ConsumableDisplayMode.ITEM_SELECT:
		_draw_item_list()
		return

	if _character == null or not is_instance_valid(_character) \
			or _character.character_data == null:
		return

	var cd          := _character.character_data
	var consumables := cd.get_consumables()
	# 選択モード以外かつ消耗品が空の場合は非表示
	if consumables.is_empty() and not is_selecting:
		return

	# 種類ごとにグループ集計（インベントリ内の出現順を維持）
	var group_keys: Array = []   # item_type の順序リスト
	var groups:     Dictionary = {}  # item_type -> { count: int, item_name: String, image: String }
	for item_v: Variant in consumables:
		var item  := item_v as Dictionary
		var itype := item.get("item_type", "unknown") as String
		if not groups.has(itype):
			group_keys.append(itype)
			groups[itype] = {
				"count":     0,
				"item_name": item.get("item_name", itype) as String,
				"image":     item.get("image", "") as String,
				"category":  item.get("category", "") as String,
				"usable":    _is_consumable_usable(item),
			}
		(groups[itype] as Dictionary)["count"] = \
			int((groups[itype] as Dictionary)["count"]) + 1

	# 選択モード中は先頭に「なし（—）」スロットを追加
	var show_none_slot := is_selecting

	# 選択中アイテムの種別を取得
	var sel_type := ""
	if is_selecting:
		# 選択モード中は select_index で判定（-1=なし枠）
		if select_index >= 0 and select_index < consumables.size():
			sel_type = (consumables[select_index] as Dictionary).get("item_type", "") as String
		# select_index == -1 のときは sel_type="" のまま（なし枠をハイライト）
	else:
		var sel := cd.get_selected_consumable()
		sel_type = sel.get("item_type", "") as String if not sel.is_empty() else ""

	# レイアウト計算（数量はアイコン右下オーバーレイ表示）
	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var icon_sz := int(float(gs) * ICON_SIZE_RATIO)
	var item_w  := icon_sz
	var none_w  := icon_sz
	var n       := group_keys.size()
	var total_w := float(n * item_w + (n - 1) * ITEM_GAP + H_PAD * 2)
	if show_none_slot:
		total_w += float(none_w + ITEM_GAP)
	var box_h   := float(gs) * 0.65
	var by      := float(gs) * 0.35

	# バーが空（消耗品0・選択モードのみ）でも最小幅を確保
	if group_keys.is_empty() and show_none_slot:
		total_w = float(none_w + H_PAD * 2)

	# フィールド左半分の中央に配置
	var vw      := _control.size.x
	var field_w := float(vw - 2 * pw)
	var left_half_cx := float(pw) + field_w * 0.25
	var bx      := left_half_cx - total_w * 0.5

	# 背景
	_control.draw_rect(Rect2(bx, by, total_w, box_h),
		Color(0.04, 0.04, 0.08, 0.88))
	# 枠線（ゴールド調：部屋名ラベルに合わせる）
	_control.draw_rect(Rect2(bx, by, total_w, box_h),
		Color(0.65, 0.55, 0.30, 0.80), false, 1)

	var x := bx + float(H_PAD)

	# 「なし（—）」スロットを先頭に描画（選択モード中のみ）
	if show_none_slot:
		var iy        := by + (box_h - float(icon_sz)) * 0.5
		var icon_rect := Rect2(x, iy, float(icon_sz), float(icon_sz))
		# 灰色の「—」ブロック
		_control.draw_rect(icon_rect, Color(0.35, 0.35, 0.35, 0.85))
		if _font != null:
			var text_x := x + float(icon_sz) * 0.5
			var text_y := by + box_h * 0.68
			_control.draw_string(_font, Vector2(text_x - 3.0, text_y),
				"\u2014", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.85, 0.85, 0.95))
		# なし枠が選択中（sel_type == "" かつ選択モード）ならハイライト
		if is_selecting and select_index < 0:
			_control.draw_rect(icon_rect, Color(1.0, 1.0, 1.0, 0.95), false, 2)
		x += float(none_w + ITEM_GAP)

	# 各アイテムグループを描画
	for key_v: Variant in group_keys:
		var itype  := key_v as String
		var info   := groups[itype] as Dictionary
		var count  := int(info["count"])
		var is_sel := (itype == sel_type) and (not is_selecting or select_index >= 0)

		var iy        := by + (box_h - float(icon_sz)) * 0.5
		var icon_rect := Rect2(x, iy, float(icon_sz), float(icon_sz))
		var img_path  := info["image"] as String
		if img_path.is_empty():
			img_path = "assets/images/items/" + itype + ".png"
		var tex       := _load_texture(img_path)
		var dim: bool = not bool(info.get("usable", true))
		_draw_item_icon(icon_rect, tex, itype, info.get("category", "") as String,
				true, count, is_sel, dim)

		x += float(item_w + ITEM_GAP)


## 選択中のアイテム詳細を右側パネルに描画する（ITEM_SELECT / ACTION_SELECT / TRANSFER_SELECT 共通）
func _draw_detail_pane(bx_end: float, by: float, box_h: float) -> void:
	if _font == null or item_list.is_empty():
		return
	if item_index < 0 or item_index >= item_list.size():
		return
	var entry := item_list[item_index] as Dictionary
	var dx := bx_end + float(ITEM_GAP)
	var dw := DETAIL_BOX_W
	# ACTION_SELECT / TRANSFER_SELECT はパネル高さを拡張
	var dh: float = box_h
	if display_mode == GlobalConstants.ConsumableDisplayMode.ACTION_SELECT \
			or display_mode == GlobalConstants.ConsumableDisplayMode.TRANSFER_SELECT:
		dh = DETAIL_BOX_H_EXPANDED
	_control.draw_rect(Rect2(dx, by, dw, dh), Color(0.04, 0.04, 0.08, 0.88))
	_control.draw_rect(Rect2(dx, by, dw, dh), Color(0.65, 0.55, 0.30, 0.80), false, 1)

	var name_s: String = entry.get("item_name", "") as String
	var usable: bool   = bool(entry.get("usable", true))
	var name_col: Color = Color(1.0, 1.0, 1.0, 0.95) if usable else Color(0.6, 0.6, 0.6, 0.8)

	# 1行目：アイテム名
	var tx := dx + 8.0
	var ty := by + 14.0
	_control.draw_string(_font, Vector2(tx, ty), name_s,
		HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 13, name_col)
	ty += 16.0

	match display_mode:
		GlobalConstants.ConsumableDisplayMode.ACTION_SELECT:
			_draw_action_list_detail(dx, ty, dw, by + dh)
		GlobalConstants.ConsumableDisplayMode.TRANSFER_SELECT:
			_draw_transfer_list_detail(dx, ty, dw, by + dh)
		_:
			# ITEM_SELECT：stats / effect
			var info_lines: Array[String] = _build_detail_lines(entry)
			var info_col: Color = Color(0.85, 0.85, 0.9, 0.9) if usable \
				else Color(0.55, 0.55, 0.6, 0.75)
			for line: String in info_lines:
				if ty > by + dh - 4.0:
					break
				_control.draw_string(_font, Vector2(tx, ty), line,
					HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 11, info_col)
				ty += 13.0


## ACTION_SELECT モードの詳細：アクション一覧 + 選択中の詳細行
func _draw_action_list_detail(dx: float, y_start: float, dw: float, y_end: float) -> void:
	var tx := dx + 8.0
	var ty := y_start
	var sel_color := Color(0.9, 0.8, 0.3)
	# アクション一覧（縦並び）
	for i: int in range(action_list.size()):
		if ty > y_end - 16.0:
			break
		var label: String = action_list[i] as String
		var is_sel := (i == action_index)
		var row_h := 16.0
		var row_rect := Rect2(dx + 4.0, ty - 11.0, dw - 8.0, row_h)
		if is_sel:
			_control.draw_rect(row_rect,
				Color(sel_color.r, sel_color.g, sel_color.b, 0.20))
		var col: Color = sel_color if is_sel else Color(0.85, 0.85, 0.85, 0.9)
		_control.draw_string(_font, Vector2(tx, ty), label,
			HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 12, col)
		ty += row_h
	# 選択中アクションの詳細行
	ty += 4.0
	if action_index >= 0 and action_index < action_info.size():
		var info: Dictionary = action_info[action_index] as Dictionary
		var lines: Array = info.get("lines", []) as Array
		for line_v: Variant in lines:
			if ty > y_end - 4.0:
				break
			_control.draw_string(_font, Vector2(tx, ty), line_v as String,
				HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 11,
				Color(0.85, 0.95, 0.85, 0.9))
			ty += 13.0


## TRANSFER_SELECT モードの詳細：渡す先メンバー一覧 + 選択中メンバーの装備可否/補正
func _draw_transfer_list_detail(dx: float, y_start: float, dw: float, y_end: float) -> void:
	var tx := dx + 8.0
	var ty := y_start
	# 見出し
	if not transfer_label.is_empty():
		_control.draw_string(_font, Vector2(tx, ty), transfer_label,
			HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 11, Color(0.75, 0.85, 0.95, 0.9))
		ty += 14.0
	var sel_color := Color(0.4, 0.9, 0.6)
	# メンバー一覧
	for i: int in range(transfer_list.size()):
		if ty > y_end - 32.0:
			break
		var nm: String = transfer_list[i] as String
		var can_equip := true
		if i < transfer_info.size():
			can_equip = bool((transfer_info[i] as Dictionary).get("can_equip", true))
		var is_sel := (i == transfer_index)
		var row_h := 16.0
		var row_rect := Rect2(dx + 4.0, ty - 11.0, dw - 8.0, row_h)
		if is_sel:
			_control.draw_rect(row_rect,
				Color(sel_color.r, sel_color.g, sel_color.b, 0.20))
		var base_col: Color = sel_color if is_sel else Color(0.85, 0.85, 0.85, 0.9)
		var suffix := "" if can_equip else "（装備不可）"
		var col: Color = base_col if can_equip else Color(0.6, 0.6, 0.6, 0.85)
		_control.draw_string(_font, Vector2(tx, ty), nm + suffix,
			HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 12, col)
		ty += row_h
	# 選択中メンバーの詳細行
	ty += 4.0
	if transfer_index >= 0 and transfer_index < transfer_info.size():
		var info: Dictionary = transfer_info[transfer_index] as Dictionary
		var lines: Array = info.get("lines", []) as Array
		for line_v: Variant in lines:
			if ty > y_end - 4.0:
				break
			_control.draw_string(_font, Vector2(tx, ty), line_v as String,
				HORIZONTAL_ALIGNMENT_LEFT, dw - 16.0, 11,
				Color(0.85, 0.95, 0.85, 0.9))
			ty += 13.0


## entry（item_list の要素）から詳細行を構築する
func _build_detail_lines(entry: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var cat: String = entry.get("category", "") as String
	# 装備品：stats（補正値）
	var stats: Dictionary = entry.get("stats", {}) as Dictionary
	const STAT_LABELS: Dictionary = {
		"power":              "威力",
		"block_right_front":  "右手防御",
		"block_left_front":   "左手防御",
		"block_front":        "両手防御",
		"physical_resistance":"物理耐性",
		"magic_resistance":   "魔法耐性",
		"range_bonus":        "射程",
	}
	for key_v: Variant in stats.keys():
		var key := key_v as String
		var val := int(stats[key])
		if val == 0:
			continue
		var label: String = STAT_LABELS.get(key, key) as String
		var sign_s: String = "+" if val > 0 else ""
		lines.append("%s %s%d" % [label, sign_s, val])
	# 消耗品：effect
	# restore_energy は固定で「MP/SP回復」（ポーションを他メンバーに渡すこともあるため
	# 閲覧中キャラのクラスで決め打ちしない）
	var effect: Dictionary = entry.get("effect", {}) as Dictionary
	var EFFECT_LABELS: Dictionary = {
		"restore_hp":     "HP回復",
		"restore_energy": "MP/SP回復",
	}
	for key_v: Variant in effect.keys():
		var key := key_v as String
		var val := int(effect[key])
		if val == 0:
			continue
		var label: String = EFFECT_LABELS.get(key, key) as String
		lines.append("%s %d" % [label, val])
	if lines.is_empty():
		# 装備不可/使用不可の理由
		if not bool(entry.get("usable", true)):
			lines.append(_unusable_reason(cat))
	return lines


## 使用/装備不可の理由メッセージを返す
func _unusable_reason(category: String) -> String:
	match category:
		"weapon", "armor", "shield":
			return "このクラスでは装備できない"
		"consumable":
			return "このキャラには効果がない"
		_:
			return "使用不可"


## アイコン本体 + 右下の個数オーバーレイを描画する（全モード共通）
## dim=true でアイテム使用不可のグレーアウト、show_count=true で個数表示
func _draw_item_icon(icon_rect: Rect2, tex: Texture2D, itype: String, category: String,
		show_count: bool, count: int, highlight: bool, dim: bool = false) -> void:
	if tex != null:
		var col := Color.WHITE if not dim else DIM_MODULATE
		_control.draw_texture_rect(tex, icon_rect, false, col)
	else:
		var base_col := ITEM_COLORS.get(itype, DEFAULT_COLOR) as Color
		if category == "weapon":
			base_col = Color(0.7, 0.7, 0.9)
		elif category == "armor" or category == "shield":
			base_col = Color(0.5, 0.7, 0.5)
		if dim:
			base_col = base_col.darkened(0.5)
			base_col.a = 0.75
		_control.draw_rect(icon_rect, base_col)
	# 選択中：白い枠でハイライト
	if highlight:
		_control.draw_rect(icon_rect, Color(1.0, 1.0, 1.0, 0.95), false, 2)
	# 個数を右下にオーバーレイ表示（小さめフォント＋影付き）
	if show_count and count > 1 and _font != null:
		var txt: String = str(count)
		var fs: int = COUNT_FONT_SIZE
		var ts: Vector2 = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var px: float = icon_rect.position.x + icon_rect.size.x - ts.x - 2.0
		var py: float = icon_rect.position.y + icon_rect.size.y - 2.0
		# 影（黒）
		_control.draw_string(_font, Vector2(px + 1.0, py + 1.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
		# 本体（黄系）
		var num_col: Color = Color(1.0, 0.95, 0.4, 1.0) if not dim \
			else Color(0.75, 0.7, 0.4, 0.9)
		_control.draw_string(_font, Vector2(px, py), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, num_col)


## ITEM_SELECT モード：item_list（装備品＋消耗品の混合表示リスト）を描画する
func _draw_item_list() -> void:
	if item_list.is_empty():
		return
	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var icon_sz := int(float(gs) * ICON_SIZE_RATIO)
	var item_w  := icon_sz
	var n       := item_list.size()
	var total_w := float(n * item_w + (n - 1) * ITEM_GAP + H_PAD * 2)
	var box_h   := float(gs) * 0.65
	var by      := float(gs) * 0.35
	var vw      := _control.size.x
	var field_w := float(vw - 2 * pw)
	# 詳細パネル分を見越して少し左寄せ（詳細パネルは右隣に描画）
	var bx      := float(pw) + field_w * 0.25 - (total_w + DETAIL_BOX_W) * 0.5

	_control.draw_rect(Rect2(bx, by, total_w, box_h), Color(0.04, 0.04, 0.08, 0.88))
	_control.draw_rect(Rect2(bx, by, total_w, box_h), Color(0.65, 0.55, 0.30, 0.80), false, 1)

	var x := bx + float(H_PAD)
	for i: int in range(n):
		var entry   := item_list[i] as Dictionary
		var itype   := entry.get("item_type", "unknown") as String
		var count   := int(entry.get("count", 1))
		var cat     := entry.get("category", "") as String
		var img_path := entry.get("image", "") as String
		if img_path.is_empty():
			img_path = "assets/images/items/" + itype + ".png"
		var iy      := by + (box_h - float(icon_sz)) * 0.5
		var icon_r  := Rect2(x, iy, float(icon_sz), float(icon_sz))

		var tex := _load_texture(img_path)
		var dim: bool = not bool(entry.get("usable", true))
		_draw_item_icon(icon_r, tex, itype, cat, true, count, i == item_index, dim)

		x += float(item_w + ITEM_GAP)

	# 右側に詳細パネルを描画
	_draw_detail_pane(bx + total_w, by, box_h)


## 消耗品が現在のキャラクターで使用できるかを簡易判定する（max_energy チェック）
func _is_consumable_usable(item: Dictionary) -> bool:
	if _character == null or not is_instance_valid(_character):
		return true
	var effect: Dictionary = item.get("effect", {}) as Dictionary
	var restore_energy := int(effect.get("restore_energy", 0))
	if restore_energy > 0 and _character.max_energy == 0:
		return false
	return true


## ACTION_SELECT / TRANSFER_SELECT モード：テキストリストを横並びで描画する
func _draw_list_menu(entries: Array, sel: int, sel_color: Color) -> void:
	if entries.is_empty() or _font == null:
		return
	var gs    := GlobalConstants.GRID_SIZE
	var pw    := GlobalConstants.PANEL_TILES * gs
	var box_h := float(gs) * 0.65
	var by    := float(gs) * 0.35
	const ENTRY_PAD_X := 10
	const ENTRY_H     := 22

	# 各エントリの幅を計算
	var entry_widths: Array[float] = []
	for e_v: Variant in entries:
		var w := _font.get_string_size(e_v as String, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		entry_widths.append(w + float(ENTRY_PAD_X * 2))

	var total_w: float = 0.0
	for w_v: Variant in entry_widths:
		total_w += w_v as float
	total_w += float(ITEM_GAP * (entries.size() - 1)) + float(H_PAD * 2)

	var vw  := _control.size.x
	var bx  := float(pw) + (float(vw - 2 * pw)) * 0.25 - total_w * 0.5

	_control.draw_rect(Rect2(bx, by, total_w, box_h), Color(0.04, 0.04, 0.08, 0.88))
	_control.draw_rect(Rect2(bx, by, total_w, box_h), Color(0.65, 0.55, 0.30, 0.80), false, 1)

	var x := bx + float(H_PAD)
	for i: int in range(entries.size()):
		var label := entries[i] as String
		var ew    := entry_widths[i] as float
		var text_col := sel_color if i == sel else Color(0.85, 0.85, 0.85, 0.9)
		if i == sel:
			_control.draw_rect(Rect2(x, by + 2.0, ew, box_h - 4.0),
				Color(sel_color.r, sel_color.g, sel_color.b, 0.20))
			_control.draw_rect(Rect2(x, by + 2.0, ew, box_h - 4.0),
				sel_color, false, 1)
		_control.draw_string(_font, Vector2(x + float(ENTRY_PAD_X), by + box_h * 0.68),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_col)
		x += ew + float(ITEM_GAP)
