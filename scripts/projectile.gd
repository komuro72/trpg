class_name Projectile
extends Node2D

## 飛翔体（遠距離攻撃の弾）
## 発射元から目標座標まで直線飛行し、着弾時にダメージを与える。
## 命中判定は発射時点で確定済み（will_hit）。

const SPEED := 2000.0  # px/秒（移動での回避不可）

var _dest:       Vector2
var _will_hit:   bool
var _target:     Character
var _damage:     int
var _multiplier: float
var _done:       bool = false


## 発射設定。add_child 後すぐに呼ぶこと。
func setup(from: Vector2, to: Vector2, will_hit: bool,
		target: Character, damage: int, multiplier: float) -> void:
	position    = from
	_dest       = to
	_will_hit   = will_hit
	_target     = target
	_damage     = damage
	_multiplier = multiplier


func _process(delta: float) -> void:
	if _done:
		return
	var to_dest := _dest - position
	var step    := SPEED * delta
	if to_dest.length() <= step:
		position = _dest
		_on_arrive()
	else:
		position += to_dest.normalized() * step


func _on_arrive() -> void:
	_done = true
	if _will_hit and is_instance_valid(_target):
		_target.take_damage(_damage, _multiplier)
		print("[Player] 遠距離攻撃 → %s  HP:%d/%d" % \
				[_target.name, _target.hp, _target.max_hp])
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.8, 0.0))  # 黄色の円（仮素材）
