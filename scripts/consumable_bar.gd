class_name ConsumableBar
extends CanvasLayer

## 消耗品バー：画面上部・部屋名ラベルの左側に操作キャラの消耗品を表示（Phase 10-3〜）
## 消耗品を種類ごとにアイコン（カラーブロック）＋「×n」で横並び表示。
## 選択中の種類は白い枠でハイライトする。

## アイテム種別ごとのアイコン色
const ITEM_COLORS: Dictionary = {
	"potion_hp": Color(0.85, 0.20, 0.20),   # 赤：HP回復
	"potion_mp": Color(0.20, 0.40, 0.90),   # 青：MP回復
	"potion_sp": Color(0.20, 0.80, 0.30),   # 緑：SP回復
}
const DEFAULT_COLOR := Color(1.0, 0.85, 0.15)  # 黄：その他消耗品

const ICON_SIZE_RATIO: float = 0.50   # GRID_SIZE に対するアイコンサイズの比率
const COUNT_TEXT_W:    int   = 28     # "×n" テキスト確保幅（px）
const ITEM_GAP:        int   = 6      # アイテム間余白（px）
const H_PAD:           int   = 8      # バー左右内側余白（px）

var _character: Character = null
var _control: Control
var _font: Font
var _tex_cache: Dictionary = {}  # image_path -> Texture2D or null

## V スロットのクールダウン残り秒数（player_controller が毎フレーム更新）
var v_slot_cooldown: float = 0.0

## 表示モード（player_controller が設定。Phase 12-12〜）
enum DisplayMode { NORMAL, ITEM_SELECT, ACTION_SELECT, TRANSFER_SELECT }
var display_mode: DisplayMode = DisplayMode.NORMAL

## ITEM_SELECT モード用（_item_ui_display の辞書配列）
var item_list:  Array = []
var item_index: int   = 0

## ACTION_SELECT モード用（アクション文字列配列）
var action_list:  Array = []
var action_index: int   = 0

## TRANSFER_SELECT モード用（キャラ名文字列配列）
var transfer_list:  Array = []
var transfer_index: int   = 0

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
	# モード別描画
	match display_mode:
		DisplayMode.ACTION_SELECT:
			_draw_list_menu(action_list, action_index, Color(0.9, 0.8, 0.3))
			return
		DisplayMode.TRANSFER_SELECT:
			_draw_list_menu(transfer_list, transfer_index, Color(0.4, 0.9, 0.6))
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
	if display_mode == DisplayMode.ITEM_SELECT:
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
				"image":     item.get("image", "") as String
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

	# レイアウト計算
	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var icon_sz := int(float(gs) * ICON_SIZE_RATIO)
	var item_w  := icon_sz + COUNT_TEXT_W
	var none_w  := icon_sz + ITEM_GAP  # なし枠は「×n」なしで幅を詰める
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

		# アイコン（画像優先・なければカラーブロック）
		var iy        := by + (box_h - float(icon_sz)) * 0.5
		var icon_rect := Rect2(x, iy, float(icon_sz), float(icon_sz))
		var img_path  := info["image"] as String
		var tex       := _load_texture(img_path)
		if tex != null:
			_control.draw_texture_rect(tex, icon_rect, false)
		else:
			var col := ITEM_COLORS.get(itype, DEFAULT_COLOR) as Color
			_control.draw_rect(icon_rect, col)
		# 選択中：白い枠でハイライト
		if is_sel:
			_control.draw_rect(icon_rect, Color(1.0, 1.0, 1.0, 0.95), false, 2)

		# ×n ラベル
		if _font != null:
			_control.draw_string(_font,
				Vector2(x + float(icon_sz) + 2.0, by + box_h * 0.68),
				"\u00d7%d" % count,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(1.0, 0.92, 0.65, 1.0))

		x += float(item_w + ITEM_GAP)


## ITEM_SELECT モード：item_list（装備品＋消耗品の混合表示リスト）を描画する
func _draw_item_list() -> void:
	if item_list.is_empty():
		return
	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var icon_sz := int(float(gs) * ICON_SIZE_RATIO)
	var item_w  := icon_sz + COUNT_TEXT_W
	var n       := item_list.size()
	var total_w := float(n * item_w + (n - 1) * ITEM_GAP + H_PAD * 2)
	var box_h   := float(gs) * 0.65
	var by      := float(gs) * 0.35
	var vw      := _control.size.x
	var field_w := float(vw - 2 * pw)
	var bx      := float(pw) + field_w * 0.25 - total_w * 0.5

	_control.draw_rect(Rect2(bx, by, total_w, box_h), Color(0.04, 0.04, 0.08, 0.88))
	_control.draw_rect(Rect2(bx, by, total_w, box_h), Color(0.65, 0.55, 0.30, 0.80), false, 1)

	var x := bx + float(H_PAD)
	for i: int in range(n):
		var entry   := item_list[i] as Dictionary
		var itype   := entry.get("item_type", "unknown") as String
		var count   := int(entry.get("count", 1))
		var cat     := entry.get("category", "") as String
		var img_path := entry.get("image", "") as String
		var iy      := by + (box_h - float(icon_sz)) * 0.5
		var icon_r  := Rect2(x, iy, float(icon_sz), float(icon_sz))

		var tex := _load_texture(img_path)
		if tex != null:
			_control.draw_texture_rect(tex, icon_r, false)
		else:
			var col := ITEM_COLORS.get(itype, DEFAULT_COLOR) as Color
			if cat == "weapon":
				col = Color(0.7, 0.7, 0.9)
			elif cat == "armor" or cat == "shield":
				col = Color(0.5, 0.7, 0.5)
			_control.draw_rect(icon_r, col)

		# 選択中ハイライト
		if i == item_index:
			_control.draw_rect(icon_r, Color(1.0, 1.0, 1.0, 0.95), false, 2)

		if _font != null and count > 1:
			_control.draw_string(_font,
				Vector2(x + float(icon_sz) + 2.0, by + box_h * 0.68),
				"\u00d7%d" % count,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.65, 1.0))

		x += float(item_w + ITEM_GAP)


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
