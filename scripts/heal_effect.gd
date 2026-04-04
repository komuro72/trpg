class_name HealEffect
extends Node2D

## 回復エフェクト（Phase 11-4 実装）
## mode = "cast"  → ヒーラー側: 白金の波紋が外へ広がる
## mode = "hit"   → ターゲット側: 緑〜白の波紋が内へ縮まる + 中央グロー
##
## 案A（コード描画）を採用。HitEffect より再生時間を長く、サイズは大きめ。
## draw_arc() でリングを3本重ね、位相をずらして動きに奥行きを出す。

const DURATION:    float = 0.60   ## HitEffect（約0.375s）より遅め
const RING_COUNT:  int   = 3
const RING_WIDTH:  float = 2.5

## "cast"（キャスト側・外広がり）または "hit"（ターゲット側・内縮み）
var mode: String = "hit"

var _timer: float = 0.0


func _ready() -> void:
	z_index = 5   # キャラクター(z=1)・HitEffect(z=5) と同レベル


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t     := _timer / DURATION          # 0.0 → 1.0
	var gs    := float(GlobalConstants.GRID_SIZE)
	var max_r := gs * 0.55

	if mode == "cast":
		## キャスト側: 白金（Color(1.0, 0.95, 0.6)）のリングが外へ広がる
		for i: int in RING_COUNT:
			var phase  := float(i) / float(RING_COUNT)
			var ring_t := fmod(t + phase, 1.0)   # 0→1 を繰り返す（3本の位相差）
			var r      := max_r * ring_t
			var alpha  := (1.0 - ring_t) * 0.80
			var col    := Color(1.0, 0.95, 0.6, alpha)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, RING_WIDTH)
	else:
		## ターゲット側: 緑〜白のリングが内へ縮まる + 中央グロー
		for i: int in RING_COUNT:
			var phase  := float(i) / float(RING_COUNT)
			var ring_t := fmod(t + phase, 1.0)
			var r      := max_r * (1.0 - ring_t)   # 外から内へ
			var alpha  := (1.0 - ring_t) * 0.80
			## 時間経過で緑から白に変化
			var col := Color(0.4, 1.0, 0.55, alpha).lerp(
					Color(1.0, 1.0, 1.0, alpha), ring_t)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, RING_WIDTH)
		## 中央グロー（sin カーブでふわっと出て消える）
		var glow_a := sin(t * PI) * 0.35
		draw_circle(Vector2.ZERO, max_r * 0.28, Color(0.7, 1.0, 0.7, glow_a))
