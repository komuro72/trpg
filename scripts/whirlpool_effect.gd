class_name WhirlpoolEffect
extends Node2D

## 渦エフェクト（水魔法の無力化スタンで発生）
## スタン中キャラクターに重ねて表示する渦エフェクト。
## 画像（assets/images/effects/whirlpool.png）があればスプライト表示、
## なければシアン色の渦を _draw() で描画する。
## 外部から queue_free() されるまで回転を継続する。

const EFFECT_IMAGE_PATH := "res://assets/images/effects/whirlpool.png"

## 回転速度（rad/s）
const ROT_SPEED: float = PI * 1.5  # 270°/秒

## フォールバック描画用の色
const VORTEX_COLOR: Color = Color(0.3, 0.8, 1.0, 0.6)

var _sprite: Sprite2D = null
var _use_sprite: bool = false


func _ready() -> void:
	z_index = -1  # キャラクタースプライトより奥に表示
	# 画像があればスプライトで表示
	if ResourceLoader.exists(EFFECT_IMAGE_PATH):
		var tex := load(EFFECT_IMAGE_PATH) as Texture2D
		if tex != null:
			_sprite = Sprite2D.new()
			_sprite.texture = tex
			# GRID_SIZE に合わせてスケール（画像サイズに依存しない）
			var gs := float(GlobalConstants.GRID_SIZE)
			var scale_val := gs / float(tex.get_width())
			_sprite.scale = Vector2(scale_val, scale_val)
			add_child(_sprite)
			_use_sprite = true


func _process(delta: float) -> void:
	rotation += ROT_SPEED * delta
	if not _use_sprite:
		queue_redraw()


func _draw() -> void:
	if _use_sprite:
		return
	# フォールバック: シアン色の渦を描画
	var gs := float(GlobalConstants.GRID_SIZE)
	var r := gs * 0.45
	# 渦巻き（3周のスパイラル）
	var pts := PackedVector2Array()
	var steps := 24
	for i: int in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := t * PI * 6.0  # 3周
		var radius := r * (1.0 - t * 0.7)  # 外から内へ
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	var col := VORTEX_COLOR
	col.a = 0.6
	draw_polyline(pts, col, 2.0, true)
