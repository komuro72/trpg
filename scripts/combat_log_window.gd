## 戦闘・AI ログウィンドウ（F2キーで表示/非表示トグル）
## combat / ai ログ（最新50件・新着が下に追加）
## - combat=黄色、ai=水色（MessageWindow と同じ色分け）
## - `MessageLog.debug_log_added` シグナル経由で受信（エリアフィルタなし・全メッセージ表示）
## ログ蓄積はウィンドウの可視状態に関わらず常に行う（閉じていても最新50件は保持）

class_name CombatLogWindow
extends CanvasLayer

const LOG_MAX:  int   = 50
const FS:       int   = 12        ## フォントサイズ
const HDR_FS:   int   = 14        ## ヘッダー用フォントサイズ
const LINE_H:   float = 15.0      ## 1行の高さ
const PAD:      float = 8.0       ## 外側パディング

## combat / ai ログ（debug_log_added シグナル経由で追加）
var _log_entries: Array[Dictionary] = []  ## { "text": String, "color": Color }

var _control: Control


func _ready() -> void:
	layer = 15
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_control = Control.new()
	_control.name = "CombatLogPanel"
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control.draw.connect(_on_draw)
	add_child(_control)

	if MessageLog != null:
		MessageLog.debug_log_added.connect(_on_debug_log_added)


func _on_debug_log_added(text: String, color: Color) -> void:
	_log_entries.append({"text": text, "color": color})
	if _log_entries.size() > LOG_MAX:
		_log_entries = _log_entries.slice(_log_entries.size() - LOG_MAX)
	if visible:
		_control.queue_redraw()


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------

func _on_draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = _control.get_viewport_rect().size
	# 画面中央に 85% × 85% で配置
	var pw: float = vp.x * 0.85
	var ph: float = vp.y * 0.85
	var px: float = (vp.x - pw) * 0.5
	var py: float = (vp.y - ph) * 0.5

	# 背景パネルなし（完全透過）

	# タイトル行
	var title: String = "■ COMBAT / AI LOG  [F2で閉じる]"
	_control.draw_string(font, Vector2(px + PAD, py + PAD + HDR_FS),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, HDR_FS, Color(0.8, 0.8, 1.0))

	var title_bottom: float = py + HDR_FS + PAD * 2.5
	_control.draw_line(Vector2(px, title_bottom), Vector2(px + pw, title_bottom),
		Color(0.45, 0.55, 0.85, 0.5), 1.0)

	# ログ領域
	var c_top: float = title_bottom + 4.0
	var c_h: float   = ph - (title_bottom - py) - 8.0
	_draw_log(font, px + PAD, c_top, pw - PAD * 2, c_h)


func _draw_log(font: Font, x: float, y: float, w: float, h: float) -> void:
	var max_y: float = y + h

	if _log_entries.is_empty():
		_control.draw_string(font, Vector2(x, y + FS), "(ログなし)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS - 1, Color(0.45, 0.45, 0.45))
		return

	# 下端から逆算して表示できる行数を決定し、最新エントリを下に表示する
	var avail_h: float  = max_y - y
	var max_lines: int  = int(avail_h / LINE_H)
	var start: int      = maxi(0, _log_entries.size() - max_lines)

	for i: int in range(start, _log_entries.size()):
		if y >= max_y:
			break
		var entry: Dictionary = _log_entries[i]
		_control.draw_string(font, Vector2(x, y + FS),
			str(entry.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, w, FS - 1,
			entry.get("color", Color.WHITE) as Color)
		y += LINE_H
