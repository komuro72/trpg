class_name BuffEffect
extends Node2D

## 防御バフエフェクト（Phase 12-6: ヒーラーのVスロット防御バフ）
## バフが有効な間キャラクターに重ねて表示し続ける永続エフェクト。
## 外部から queue_free() されるまで回転を継続する。
## HealEffect と異なり、自分では削除しない（character.gd が寿命を管理）。

## 六角形枠線色
const LINE_COLOR:  Color = Color(0.2, 0.9, 0.4, 0.80)
## 枠線幅
const LINE_WIDTH:  float = 2.0
## 回転速度は GlobalConstants.BUFF_EFFECT_ROT_SPEED_DEG（度/秒）を参照


func _ready() -> void:
	z_index = 1   # スプライト（z=0）より手前・HitEffect（親ノードに追加）より後ろ


func _process(delta: float) -> void:
	rotation += deg_to_rad(GlobalConstants.BUFF_EFFECT_ROT_SPEED_DEG) * delta
	queue_redraw()


func _draw() -> void:
	var gs    := float(GlobalConstants.GRID_SIZE)
	var r     := gs * 0.60   # 六角形の外接円半径

	# 6頂点を計算（ノード自体が回転するため角度オフセットは不要）
	var pts := PackedVector2Array()
	for i: int in range(6):
		var angle := float(i) * PI / 3.0
		pts.append(Vector2(cos(angle), sin(angle)) * r)

	# 六角形の枠線（polyline は自動クローズしないので先頭点を末尾に追加）
	var closed_pts := PackedVector2Array(pts)
	closed_pts.append(pts[0])
	draw_polyline(closed_pts, LINE_COLOR, LINE_WIDTH, true)
