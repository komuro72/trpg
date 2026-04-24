class_name FlameCircle
extends Node2D

## 炎陣エフェクト・ダメージゾーン（魔法使い(火)のVスロット特殊攻撃）
## 設置座標を中心に radius タイルの範囲で tick_interval 秒ごとにダメージを与え続ける。
## duration 秒後に自動削除。
## 画像（assets/images/effects/flame.png）があれば各タイルにスプライトを配置、
## なければコード描画にフォールバック。

const FLAME_IMAGE_PATH := "res://assets/images/effects/flame.png"

var _center_grid:   Vector2i = Vector2i.ZERO
var _radius:        int      = 3
var _damage:        int      = 1
var _tick_interval: float    = 0.5
var _duration:      float    = 2.5
var _elapsed:       float    = 0.0
var _tick_elapsed:  float    = 0.0
var _attacker:      Character = null
var _targets:       Array    = []  ## blocking_characters の参照

var _use_sprites:   bool     = false
## 各タイルのスプライト情報 { sprite: Sprite2D, phase: float, rot_speed: float }
var _flame_sprites: Array    = []


## 初期化。visual_pos = ワールド座標（キャスター位置）、center_grid = グリッド座標
func setup(visual_pos: Vector2, center_grid: Vector2i, radius: int, damage: int,
		duration: float, tick_interval: float, attacker: Character,
		targets: Array) -> void:
	position       = visual_pos
	_center_grid   = center_grid
	_radius        = radius
	_damage        = damage
	_duration      = duration
	_tick_interval = tick_interval
	_attacker      = attacker
	_targets.assign(targets)
	_setup_flame_sprites()


func _setup_flame_sprites() -> void:
	if not ResourceLoader.exists(FLAME_IMAGE_PATH):
		return
	var tex := load(FLAME_IMAGE_PATH) as Texture2D
	if tex == null:
		return
	_use_sprites = true
	var gs := float(GlobalConstants.GRID_SIZE)
	var base_scale := gs / float(tex.get_width())
	# 中心から半径内の各タイルにスプライトを配置
	for dy: int in range(-_radius, _radius + 1):
		for dx: int in range(-_radius, _radius + 1):
			var dist := absi(dx) + absi(dy)  # マンハッタン距離
			if dist > _radius or (dx == 0 and dy == 0):
				continue
			# 中心からの距離に応じてスケールを小さくする（外側ほど小さい炎）
			var dist_ratio := float(dist) / float(_radius)
			var scale_factor := lerpf(1.0, 0.6, dist_ratio)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.scale = Vector2(base_scale * scale_factor, base_scale * scale_factor)
			spr.position = Vector2(float(dx) * gs, float(dy) * gs)
			spr.modulate.a = 0.8
			add_child(spr)
			# 各タイルで位相・回転速度をランダムにずらす
			_flame_sprites.append({
				"sprite": spr,
				"phase": randf() * TAU,
				"rot_speed": randf_range(-1.5, 1.5),
				"base_scale": base_scale * scale_factor,
			})
	# 中央にも大きめの炎を配置
	var center_spr := Sprite2D.new()
	center_spr.texture = tex
	center_spr.scale = Vector2(base_scale * 1.2, base_scale * 1.2)
	center_spr.position = Vector2.ZERO
	center_spr.modulate.a = 0.9
	add_child(center_spr)
	_flame_sprites.append({
		"sprite": center_spr,
		"phase": 0.0,
		"rot_speed": 0.8,
		"base_scale": base_scale * 1.2,
	})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return
	_tick_elapsed += delta
	if _tick_elapsed >= _tick_interval:
		_tick_elapsed -= _tick_interval
		_deal_damage_tick()
	# スプライトのアニメーション
	if _use_sprites:
		var t := Time.get_ticks_msec() / 1000.0
		var fade := 1.0 - clampf((_elapsed - _duration + 0.5) / 0.5, 0.0, 1.0)  # 最後の0.5秒でフェードアウト
		for entry: Variant in _flame_sprites:
			var d := entry as Dictionary
			var spr := d["sprite"] as Sprite2D
			if not is_instance_valid(spr):
				continue
			var phase: float = d["phase"] as float
			var bs: float = d["base_scale"] as float
			# スケールの脈動（0.85〜1.15）
			var pulse := sin(t * 3.0 + phase) * 0.15 + 1.0
			spr.scale = Vector2(bs * pulse, bs * pulse)
			# アルファの揺らぎ + フェードアウト
			var alpha_pulse := sin(t * 2.5 + phase + 1.0) * 0.15 + 0.75
			spr.modulate.a = alpha_pulse * fade
	else:
		queue_redraw()


func _deal_damage_tick() -> void:
	if not is_instance_valid(_attacker):
		return
	for entry: Variant in _targets:
		if not is_instance_valid(entry):
			continue
		var ch := entry as Character
		if ch == null or ch.is_friendly or ch.hp <= 0:
			continue
		var dist := Vector2(_center_grid).distance_to(Vector2(ch.grid_pos))
		if dist <= float(_radius):
			ch.take_damage(_damage, 1.0, _attacker, true)


func _draw() -> void:
	if _use_sprites:
		return
	# フォールバック: コード描画（画像がない場合）
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
