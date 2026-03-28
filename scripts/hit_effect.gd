class_name HitEffect
extends Node2D

## ヒットエフェクト
## assets/images/effects/hit_01.png〜hit_NN.png があれば AnimatedSprite2D で再生。
## ファイルが存在しない場合は白い円フラッシュでフォールバック。
## 再生完了後に自動で queue_free() する。
## damage プロパティをセットするとスケールがダメージ量に比例して変化する。
##
## 推奨アセット: Kenney Particle Pack (CC0)
##   https://www.kenney.nl/assets/particle-pack
##   パックの中から spark / star 系 PNG を6枚選び、
##   hit_01.png〜hit_06.png にリネームして assets/images/effects/ に配置する。
##   素材サイズ 512×512px 想定（SOURCE_SIZE で調整可）

const FRAME_PATHS: Array[String] = [
	"res://assets/images/effects/hit_01.png",
	"res://assets/images/effects/hit_02.png",
	"res://assets/images/effects/hit_03.png",
	"res://assets/images/effects/hit_04.png",
	"res://assets/images/effects/hit_05.png",
	"res://assets/images/effects/hit_06.png",
]
## アニメーション速度（fps）
const FRAME_FPS: float = 16.0
## 素材の元サイズ（px）。Kenney Particle Pack は 512
const SOURCE_SIZE: float = 512.0
## ダメージ基準値（この値で scale = 1.0）
const REFERENCE_DAMAGE: float = 20.0
## 最小スケール（極小ダメージでも視認できる下限）
const MIN_SCALE: float = 0.2

## ダメージ量（add_child 前に設定すること）
var damage: int = int(REFERENCE_DAMAGE)

## フォールバック用
var _fallback: bool = false
var _fallback_timer: float = 0.0
const FALLBACK_DURATION: float = 0.14


func _ready() -> void:
	z_index = 5  # キャラクター(z=1)より手前

	var textures: Array[Texture2D] = []
	for path: String in FRAME_PATHS:
		if ResourceLoader.exists(path):
			textures.append(load(path) as Texture2D)

	if not textures.is_empty():
		_start_anim(textures)
	else:
		_fallback = true
		_fallback_timer = FALLBACK_DURATION
		queue_redraw()


## ダメージ量に応じたスケール係数を返す（上限なし・下限 MIN_SCALE）
func _damage_scale() -> float:
	return maxf(MIN_SCALE, float(damage) / REFERENCE_DAMAGE)


func _start_anim(textures: Array[Texture2D]) -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("hit")
	frames.set_animation_loop("hit", false)
	frames.set_animation_speed("hit", FRAME_FPS)
	for tex: Texture2D in textures:
		frames.add_frame("hit", tex)

	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = frames
	var gs := GlobalConstants.GRID_SIZE
	anim.scale = Vector2.ONE * (float(gs) / SOURCE_SIZE) * 1.3 * _damage_scale()
	anim.animation_finished.connect(queue_free)
	add_child(anim)
	anim.play("hit")


func _process(delta: float) -> void:
	if not _fallback:
		return
	_fallback_timer -= delta
	if _fallback_timer <= 0.0:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	if not _fallback:
		return
	var r   := float(GlobalConstants.GRID_SIZE) * 0.60 * _damage_scale()
	var t   := _fallback_timer / FALLBACK_DURATION   # 1.0→0.0
	var a   := t * 0.85
	# 広がりながら薄くなる白い円
	draw_circle(Vector2.ZERO, r * (1.8 - t * 0.8), Color(1.0, 1.0, 1.0, a))
