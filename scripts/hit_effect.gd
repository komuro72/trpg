class_name HitEffect
extends Node2D

## ヒットエフェクト（3層構成・プロシージャル描画）
## 1. リング（波紋）— 中心から外に広がる。ダメージ量で最大サイズ変動
## 2. 光条（十字フラッシュ）— 中心に一瞬だけ表示、リングより先にフェードアウト
## 3. パーティクル散布 — 小さな光の粒が中心から放射状に飛び散る
##
## 加算合成（CanvasItemMaterial.BLEND_MODE_ADD）で描画。
## クリティカルヒット時は2個重なり自然に輝度が上がる。

## 総再生時間（秒）
const DURATION: float = 0.40
## リング描画の太さ
const RING_WIDTH: float = 2.5
## 光条の終了タイミング（DURATION に対する比率）
const BURST_RATIO: float = 0.375  # 0.15s / 0.40s
## パーティクルがフェード開始するタイミング（比率）
const PARTICLE_FADE_START: float = 0.7
## ダメージ基準値（この値で scale = 1.0）
const REFERENCE_DAMAGE: float = 20.0
## 最小スケール（極小ダメージでも視認できる下限）
const MIN_SCALE: float = 0.2

## ダメージ量（add_child 前に設定すること）
var damage: int = int(REFERENCE_DAMAGE)

var _timer: float = 0.0

# パーティクルデータ（_ready で初期化）
var _particle_angles: PackedFloat32Array
var _particle_speeds: PackedFloat32Array
var _particle_sizes: PackedFloat32Array


func _ready() -> void:
	z_index = 5  # キャラクター(z=1)より手前

	# 加算合成マテリアル
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

	# パーティクル初期化
	var count: int = clampi(int(6.0 + 4.0 * _damage_scale()), 6, 20)
	_particle_angles.resize(count)
	_particle_speeds.resize(count)
	_particle_sizes.resize(count)
	for i: int in count:
		_particle_angles[i] = randf() * TAU
		_particle_speeds[i] = randf_range(0.7, 1.3)
		_particle_sizes[i] = randf_range(1.5, 3.0)


## ダメージ量に応じたスケール係数（上限なし・下限 MIN_SCALE）
func _damage_scale() -> float:
	return maxf(MIN_SCALE, float(damage) / REFERENCE_DAMAGE)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = _timer / DURATION  # 0.0 → 1.0
	var gs: float = float(GlobalConstants.GRID_SIZE)
	var ds: float = _damage_scale()

	_draw_ring(t, gs, ds)
	_draw_burst(t, gs, ds)
	_draw_particles(t, gs, ds)


## --- 層1: リング（波紋） ---
func _draw_ring(t: float, gs: float, ds: float) -> void:
	var max_r: float = gs * 0.55 * ds
	# ease-out: 最初に速く広がり減速
	var r: float = max_r * (1.0 - pow(1.0 - t, 2.0))
	var alpha: float = (1.0 - t) * 0.9

	# 外リング（黄橙）
	var col := Color(1.0, 0.85, 0.3, alpha)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, RING_WIDTH)
	# 内リング（やや暗め・細め）
	var inner_r: float = r * 0.65
	var inner_col := Color(1.0, 0.7, 0.2, alpha * 0.6)
	draw_arc(Vector2.ZERO, inner_r, 0.0, TAU, 36, inner_col, RING_WIDTH * 0.7)


## --- 層2: 光条（十字フラッシュ） ---
func _draw_burst(t: float, gs: float, ds: float) -> void:
	# 光条の持続を大ダメージ時にわずかに延長
	var burst_ratio: float = minf(BURST_RATIO * (1.0 + ds * 0.15), 0.5)
	if t > burst_ratio:
		return

	var bt: float = t / burst_ratio  # 0→1（バースト内の進行度）

	# 中心グロー（白）
	var glow_r: float = gs * 0.20 * ds * (0.3 + bt * 0.7)
	var glow_alpha: float = (1.0 - bt) * 1.0
	draw_circle(Vector2.ZERO, glow_r, Color(1.0, 1.0, 1.0, glow_alpha))

	# 十字光条（4方向）
	var line_len: float = gs * 0.30 * ds * (0.4 + bt * 0.6)
	var line_alpha: float = (1.0 - bt) * 0.85
	var line_col := Color(1.0, 0.95, 0.7, line_alpha)
	var line_w: float = 2.0
	# 右・左・上・下
	draw_line(Vector2.ZERO, Vector2(line_len, 0.0), line_col, line_w)
	draw_line(Vector2.ZERO, Vector2(-line_len, 0.0), line_col, line_w)
	draw_line(Vector2.ZERO, Vector2(0.0, -line_len), line_col, line_w)
	draw_line(Vector2.ZERO, Vector2(0.0, line_len), line_col, line_w)
	# 斜め45°（やや短く・薄く）
	var diag_len: float = line_len * 0.6
	var diag_col := Color(1.0, 0.95, 0.7, line_alpha * 0.6)
	var d: float = diag_len * 0.7071  # cos(45°)
	draw_line(Vector2.ZERO, Vector2(d, -d), diag_col, line_w * 0.7)
	draw_line(Vector2.ZERO, Vector2(-d, -d), diag_col, line_w * 0.7)
	draw_line(Vector2.ZERO, Vector2(d, d), diag_col, line_w * 0.7)
	draw_line(Vector2.ZERO, Vector2(-d, d), diag_col, line_w * 0.7)


## --- 層3: パーティクル散布 ---
func _draw_particles(t: float, gs: float, ds: float) -> void:
	var max_travel: float = gs * 0.50 * ds
	var count: int = _particle_angles.size()

	for i: int in count:
		var angle: float = _particle_angles[i]
		var spd: float = _particle_speeds[i]
		var sz: float = _particle_sizes[i]

		# ease-out で最初に速く飛び、減速
		var travel_t: float = 1.0 - pow(1.0 - t, 1.5)
		var dist: float = max_travel * travel_t * spd
		var pos := Vector2(cos(angle), sin(angle)) * dist

		# フェード
		var alpha: float = 1.0
		if t > PARTICLE_FADE_START:
			alpha = (1.0 - t) / (1.0 - PARTICLE_FADE_START)

		# 白→オレンジ
		var col := Color(1.0, 1.0, 0.9, alpha).lerp(
				Color(1.0, 0.6, 0.2, alpha), t)

		draw_circle(pos, sz, col)
