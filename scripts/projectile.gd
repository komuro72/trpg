class_name Projectile
extends Node2D

## 飛翔体（遠距離攻撃の弾）
## 発射元から目標座標まで直線飛行し、着弾時にダメージを与える。
## 命中判定は発射時点で確定済み（will_hit）。

const SPEED := 2000.0  # px/秒（移動での回避不可）

const _ARROW_PATH          := "res://assets/images/effects/arrow.png"
const _FIRE_BULLET_PATH    := "res://assets/images/effects/fire_bullet.png"
const _WATER_BULLET_PATH   := "res://assets/images/effects/water_bullet.png"
const _THUNDER_BULLET_PATH := "res://assets/images/effects/thunder_bullet.png"

var _dest:           Vector2
var _will_hit:       bool
var _target:         Character
var _damage:         int
var _multiplier:     float
var _attacker:       Character
var _is_magic:       bool
var _is_water:       bool   = false  ## 水系魔法フラグ（水弾・無力化水魔法）
var _proj_type:      String = ""     ## キャラ固有の弾種 ("thunder_bullet" 等。Phase 12-12〜）
var _stun_duration:  float  = 0.0   ## スタン持続秒数（0=スタンなし）
var _done:           bool   = false

var _sprite:     Sprite2D = null
var _direction:  Vector2  = Vector2.RIGHT


## 発射設定。add_child 後すぐに呼ぶこと。
## stun_duration > 0 のとき着弾時にターゲットをスタンさせる
func setup(from: Vector2, to: Vector2, will_hit: bool,
		target: Character, damage: int, multiplier: float,
		attacker: Character = null, is_magic: bool = false,
		stun_duration: float = 0.0, is_water: bool = false,
		proj_type: String = "") -> void:
	position        = from
	_dest           = to
	_will_hit       = will_hit
	_target         = target
	_damage         = damage
	_multiplier     = multiplier
	_attacker       = attacker
	_is_magic       = is_magic
	_stun_duration  = stun_duration
	_is_water       = is_water
	_proj_type      = proj_type
	_direction      = (to - from).normalized()

	_setup_sprite()


func _setup_sprite() -> void:
	# 攻撃種別に応じた画像パスを選択
	var img_path: String
	if _proj_type == "thunder_bullet":
		img_path = _THUNDER_BULLET_PATH
	elif _is_water:
		img_path = _WATER_BULLET_PATH
	elif _is_magic:
		img_path = _FIRE_BULLET_PATH
	else:
		img_path = _ARROW_PATH

	if not ResourceLoader.exists(img_path):
		return  # 画像なし → _draw() のフォールバックを使用

	var tex := load(img_path) as Texture2D
	if tex == null:
		return

	_sprite = Sprite2D.new()
	_sprite.texture = tex
	# 画像サイズを飛翔体として適切なサイズ（64px）にスケール
	var img_size := maxf(float(tex.get_width()), float(tex.get_height()))
	if img_size > 0.0:
		var scale_val := 64.0 / img_size
		_sprite.scale = Vector2(scale_val, scale_val)
	# 下向き（↓）が正方向の画像なので -PI/2 オフセットで右向きを基準に補正
	_sprite.rotation = atan2(_direction.y, _direction.x) + PI / 2.0
	add_child(_sprite)


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
		# attacker が既に解放されている場合は null として渡す
		var safe_attacker: Character = _attacker \
				if is_instance_valid(_attacker) else null
		if _damage > 0:
			# スタン攻撃のときはダメージ側の battle メッセージを抑制し、
			# apply_stun() 側でまとめて自然言語メッセージを生成する
			var suppress := _stun_duration > 0.0
			_target.take_damage(_damage, _multiplier, safe_attacker, _is_magic, suppress)
			print("[Player] 遠距離攻撃 → %s  HP:%d/%d" % \
					[_target.name, _target.hp, _target.max_hp])
		if _stun_duration > 0.0:
			_target.apply_stun(_stun_duration, safe_attacker)
	queue_free()


func _draw() -> void:
	if _sprite != null:
		return  # 画像スプライトがあればフォールバック描画しない
	# 弾種別のフォールバック色
	var col: Color
	if _proj_type == "thunder_bullet":
		col = Color(0.8, 0.4, 1.0)  # 紫（雷）
	elif _is_water:
		col = Color(0.3, 0.7, 1.0)  # 水色
	elif _is_magic:
		col = Color(1.0, 0.4, 0.0)  # オレンジ（火）
	else:
		col = Color(1.0, 0.8, 0.0)  # 黄色（矢）
	draw_circle(Vector2.ZERO, 5.0, col)
