class_name ConsumableBar
extends CanvasLayer

## 消耗品バー：画面上部・部屋名ラベルの左側に操作キャラの消耗品を表示（Phase 10-3〜）
## 消耗品を種類ごとにアイコン（カラーブロック）＋「×n」で横並び表示。
## 選択中の種類は白い枠でハイライトする。

## アイテム種別ごとのアイコン色
const ITEM_COLORS: Dictionary = {
	"potion_hp": Color(0.85, 0.20, 0.20),   # 赤：HP回復
	"potion_mp": Color(0.20, 0.40, 0.90),   # 青：MP回復
}
const DEFAULT_COLOR := Color(1.0, 0.85, 0.15)  # 黄：その他消耗品

const ICON_SIZE_RATIO: float = 0.50   # GRID_SIZE に対するアイコンサイズの比率
const COUNT_TEXT_W:    int   = 28     # "×n" テキスト確保幅（px）
const ITEM_GAP:        int   = 6      # アイテム間余白（px）
const H_PAD:           int   = 8      # バー左右内側余白（px）
const RIGHT_MARGIN:    float = 24.0   # 部屋名ラベルとの間隔（px）

var _character: Character = null
var _control: Control
var _font: Font


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


func _on_draw() -> void:
	if _character == null or not is_instance_valid(_character) \
			or _character.character_data == null:
		return

	var cd          := _character.character_data
	var consumables := cd.get_consumables()
	if consumables.is_empty():
		return

	# 種類ごとにグループ集計（インベントリ内の出現順を維持）
	var group_keys: Array = []   # item_type の順序リスト
	var groups:     Dictionary = {}  # item_type -> { count: int, item_name: String }
	for item_v: Variant in consumables:
		var item  := item_v as Dictionary
		var itype := item.get("item_type", "unknown") as String
		if not groups.has(itype):
			group_keys.append(itype)
			groups[itype] = {
				"count":     0,
				"item_name": item.get("item_name", itype) as String
			}
		(groups[itype] as Dictionary)["count"] = \
			int((groups[itype] as Dictionary)["count"]) + 1

	# 選択中アイテムの種別を取得
	var sel      := cd.get_selected_consumable()
	var sel_type := sel.get("item_type", "") as String if not sel.is_empty() else ""

	# レイアウト計算
	var gs      := GlobalConstants.GRID_SIZE
	var pw      := GlobalConstants.PANEL_TILES * gs
	var icon_sz := int(float(gs) * ICON_SIZE_RATIO)
	var item_w  := icon_sz + COUNT_TEXT_W
	var n       := group_keys.size()
	var total_w := float(n * item_w + (n - 1) * ITEM_GAP + H_PAD * 2)
	var box_h   := float(gs) * 0.65
	var by      := float(gs) * 0.35

	# 右端：フィールド中央の左側（部屋名ラベルとの間に RIGHT_MARGIN を確保）
	var vw      := _control.size.x
	var field_w := float(vw - 2 * pw)
	var cx      := float(pw) + field_w * 0.5
	var right_x := cx - RIGHT_MARGIN
	var bx      := right_x - total_w

	# 背景
	_control.draw_rect(Rect2(bx, by, total_w, box_h),
		Color(0.04, 0.04, 0.08, 0.88))
	# 枠線（ゴールド調：部屋名ラベルに合わせる）
	_control.draw_rect(Rect2(bx, by, total_w, box_h),
		Color(0.65, 0.55, 0.30, 0.80), false, 1)

	# 各アイテムグループを描画
	var x := bx + float(H_PAD)
	for key_v: Variant in group_keys:
		var itype  := key_v as String
		var info   := groups[itype] as Dictionary
		var count  := int(info["count"])
		var is_sel := (itype == sel_type)
		var col    := ITEM_COLORS.get(itype, DEFAULT_COLOR) as Color

		# アイコン（カラーブロック）
		var iy        := by + (box_h - float(icon_sz)) * 0.5
		var icon_rect := Rect2(x, iy, float(icon_sz), float(icon_sz))
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
