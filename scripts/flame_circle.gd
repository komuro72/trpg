class_name FlameCircle
extends Node2D

## 炎陣エフェクト・ダメージゾーン（Phase 12-4: 魔法使い(火)のVスロット特殊スキル）
## 設置座標を中心に radius タイルの範囲で tick_interval 秒ごとにダメージを与え続ける。
## duration 秒後に自動削除。_draw() でアニメーションリングを描画。

var _center_grid:   Vector2i = Vector2i.ZERO
var _radius:        int      = 3
var _damage:        int      = 1
var _tick_interval: float    = 0.5
var _duration:      float    = 2.5
var _elapsed:       float    = 0.0
var _tick_elapsed:  float    = 0.0
var _attacker:      Character = null
var _targets:       Array    = []  ## blocking_characters の参照（Array[Character] として扱う）


## 初期化。visual_pos = ワールド座標（キャスター位置）、center_grid = グリッド座標
func setup(visual_pos: Vector2, center_grid: Vector2i, radius: int, damage: int,
		duration: float, tick_interval: float, attacker: Character,
		targets: Array) -> void:
	position    = visual_pos
	_center_grid   = center_grid
	_radius        = radius
	_damage        = damage
	_duration      = duration
	_tick_interval = tick_interval
	_attacker      = attacker
	_targets.assign(targets)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return
	_tick_elapsed += delta
	if _tick_elapsed >= _tick_interval:
		_tick_elapsed -= _tick_interval
		_deal_damage_tick()
	queue_redraw()


func _deal_damage_tick() -> void:
	if not is_instance_valid(_attacker):
		return
	for entry: Variant in _targets:
		var ch: Character = entry as Character
		if not is_instance_valid(ch) or ch.is_friendly or ch.hp <= 0:
			continue
		var dist := Vector2(_center_grid).distance_to(Vector2(ch.grid_pos))
		if dist <= float(_radius):
			ch.take_damage(_damage, 1.0, _attacker, true)


func _draw() -> void:
	var gs       := float(GlobalConstants.GRID_SIZE)
	var r        := float(_radius) * gs + gs * 0.4
	var progress := _elapsed / _duration
	var alpha    := maxf(0.0, 0.8 - progress * 0.5)
	var t        := Time.get_ticks_msec() / 1000.0

	# 地面グロー（半透明の円）
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.25, 0.05, 0.15 * alpha))

	# アニメーションリング（外へ広がる炎のリング）
	for i: int in range(4):
		var phase: float = fmod(t * 1.8 + float(i) * 0.25, 1.0)
		var ring_r:     float = r * (0.2 + phase * 0.8)
		var ring_alpha: float = (1.0 - phase) * alpha
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 48,
				Color(1.0, 0.5 - phase * 0.3, 0.1, ring_alpha), 3.0)

	# 中央の炎コア
	draw_circle(Vector2.ZERO, gs * 0.5, Color(1.0, 0.65, 0.1, 0.5 * alpha))
