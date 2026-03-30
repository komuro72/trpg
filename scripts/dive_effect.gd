class_name DiveEffect
extends Node2D

## 降下攻撃エフェクト（ハーピーなどの dive 攻撃時に表示する簡易エフェクト）
## 空色→白のフラッシュ円が上から落下して消えるアニメーション

const DURATION := 0.4   # 秒
const RADIUS   := 18.0  # px

var _timer: float = 0.0


func _ready() -> void:
	z_index = 3


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t       := _timer / DURATION            # 0.0 → 1.0
	var alpha   := 1.0 - t                      # フェードアウト
	var radius  := RADIUS * (0.5 + t * 0.5)    # 徐々に拡大
	var offset_y := -RADIUS * (1.0 - t)        # 上から落下
	var col     := Color(0.4, 0.8, 1.0, alpha).lerp(Color(1.0, 1.0, 1.0, alpha), t)
	draw_circle(Vector2(0.0, offset_y), radius, col)
	# 斜め線2本（羽ばたきイメージ）
	var line_alpha := alpha * 0.7
	var lc := Color(1.0, 1.0, 1.0, line_alpha)
	draw_line(Vector2(-radius, offset_y - radius * 0.3),
			  Vector2(0.0, offset_y), lc, 2.0)
	draw_line(Vector2( radius, offset_y - radius * 0.3),
			  Vector2(0.0, offset_y), lc, 2.0)
