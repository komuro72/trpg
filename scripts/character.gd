class_name Character
extends Node2D

## キャラクター基底クラス
## Phase 1-2: Sprite2D による4方向画像切替。素材がない場合はプレースホルダー表示。
## Phase 2-1: HP・攻撃力・防御力・死亡処理を追加。
## Phase 5:   トップビュー対応。rotation で方向を表現。is_flying フラグを追加。
##             フィールド画像（sprite_top）は下向き基準。DOWN = 0°

## 向き定義（トップビュー基準：DOWN=画面下, UP=画面上, LEFT=左, RIGHT=右）
enum Direction { DOWN, UP, LEFT, RIGHT }

## キャラクターが死亡してフィールドから除去されたときに発火する
signal died(character: Character)

var grid_pos: Vector2i = Vector2i(0, 0)
var facing: Direction = Direction.DOWN
var character_data: CharacterData = null

## 基本ステータス（character_data から _ready() で初期化）
var hp: int = 1
var max_hp: int = 1
var attack: int = 1
var defense: int = 0
var is_flying: bool = false

## プレースホルダー色（素材がない場合に使用）
var placeholder_color: Color = Color(0.3, 0.7, 1.0)

## 状態フラグ（modulate制御用）
## is_targeting_mode は setter で構えスプライトへの切替を行う
var is_targeting_mode: bool = false:
	set(value):
		is_targeting_mode = value
		_update_ready_sprite()
## AI攻撃モーション中フラグ（EnemyAI が ATTACKING_PRE/POST で制御）
var is_attacking: bool = false:
	set(value):
		is_attacking = value
		_update_ready_sprite()
var is_targeted: bool = false         # ターゲットとして選択されている

var _sprite: Sprite2D
var _has_texture: bool = false


func _ready() -> void:
	z_index = 1  # タイル（z_index=0）より手前に表示
	_init_stats()
	_setup_sprite()
	sync_position()


func _process(_delta: float) -> void:
	_update_modulate()


## HP・モードに応じてキャラクターの色を更新する
func _update_modulate() -> void:
	var t := Time.get_ticks_msec() / 1000.0

	# ターゲットとして選択中：白く輝かせる
	if is_targeted:
		modulate = Color(1.5, 1.5, 1.5, 1.0)
		return

	# HP状態による色
	var ratio := float(hp) / float(max_hp) if max_hp > 0 else 1.0
	if ratio > 0.6:
		modulate = Color.WHITE
	elif ratio > 0.3:
		modulate = Color(1.0, 1.0, 0.65)      # 軽傷：やや黄色
	elif ratio > 0.1:
		modulate = Color(1.0, 0.65, 0.25)     # 重傷：オレンジ
	else:
		var pulse := (sin(t * TAU * 3.0) + 1.0) * 0.5
		modulate = Color.WHITE.lerp(Color(1.0, 0.15, 0.15), pulse)  # 瀕死：赤く点滅


## character_data からステータスを初期化する
func _init_stats() -> void:
	if character_data == null:
		return
	max_hp    = character_data.max_hp
	hp        = max_hp
	attack    = character_data.attack
	defense   = character_data.defense
	is_flying = character_data.is_flying


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	_load_top_sprite()
	_apply_direction_rotation()


## フィールド表示用画像（トップビュー）を読み込む。テクスチャサイズに合わせてスケールを自動計算する
func _load_top_sprite() -> void:
	if character_data == null:
		_has_texture = false
		_sprite.visible = false
		queue_redraw()
		return

	var path := character_data.sprite_top
	if not path.is_empty() and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_sprite.texture = tex
		var tex_size := tex.get_size()
		if tex_size.x > 0:
			var scale_factor := float(GlobalConstants.GRID_SIZE) / tex_size.x
			_sprite.scale = Vector2(scale_factor, scale_factor)
		_sprite.visible = true
		_has_texture = true
	else:
		_sprite.texture = null
		_sprite.visible = false
		_has_texture = false

	queue_redraw()


## ターゲット選択モード・攻撃モーション中に応じてスプライトを切り替える
## sprite_top_ready が設定されていれば構え画像を、なければ通常画像を使う
func _update_ready_sprite() -> void:
	if _sprite == null or character_data == null:
		return
	var use_ready := (is_targeting_mode or is_attacking) and not character_data.sprite_top_ready.is_empty()
	var path := character_data.sprite_top_ready if use_ready else character_data.sprite_top
	if path.is_empty() or not ResourceLoader.exists(path):
		return  # テクスチャなし状態を維持
	var tex: Texture2D = load(path)
	_sprite.texture = tex
	var tex_size := tex.get_size()
	if tex_size.x > 0:
		_sprite.scale = Vector2.ONE * float(GlobalConstants.GRID_SIZE) / tex_size.x
	_sprite.visible = true
	_has_texture = true


## 向きを rotation に反映する（ノード全体を回転させるためプレースホルダーにも適用される）
func _apply_direction_rotation() -> void:
	rotation = _direction_to_rotation(facing)


## Direction → 回転角（ラジアン）
## トップビュー基準：画像が下向き（DOWN）= 0°、時計回り正
static func _direction_to_rotation(dir: Direction) -> float:
	match dir:
		Direction.DOWN:  return 0.0
		Direction.UP:    return PI
		Direction.RIGHT: return -PI / 2.0
		Direction.LEFT:  return PI / 2.0
	return 0.0


## 素材がない場合のプレースホルダー描画（ローカル座標 = 回転前）
func _draw() -> void:
	if _has_texture:
		return

	var gs := GlobalConstants.GRID_SIZE
	var half := gs * 0.5
	var margin := 8

	# キャラクター本体（円形）
	draw_circle(Vector2.ZERO, half - margin, placeholder_color)

	# 向きインジケーター（ローカル上方向 = 前方、回転で向きが変わる）
	draw_rect(Rect2(-4, -(half - margin - 2), 8, 10), Color.WHITE)


## このキャラクターが占有するグリッド座標の一覧を返す
## 将来的に複数マスを占有するキャラクターはこのメソッドをオーバーライドする
func get_occupied_tiles() -> Array[Vector2i]:
	return [grid_pos]


## グリッド座標をワールド座標に同期する
func sync_position() -> void:
	var gs := GlobalConstants.GRID_SIZE
	position = Vector2(
		grid_pos.x * gs + gs * 0.5,
		grid_pos.y * gs + gs * 0.5
	)


## グリッド移動（向きを更新して rotation を変更する）
func move_to(new_grid_pos: Vector2i) -> void:
	var delta := new_grid_pos - grid_pos
	if delta.x > 0:
		facing = Direction.RIGHT
	elif delta.x < 0:
		facing = Direction.LEFT
	elif delta.y > 0:
		facing = Direction.DOWN
	elif delta.y < 0:
		facing = Direction.UP

	grid_pos = new_grid_pos
	sync_position()
	_apply_direction_rotation()


## ターゲット方向に向きを変える（移動なし）
func face_toward(target_grid_pos: Vector2i) -> void:
	var delta := target_grid_pos - grid_pos
	if abs(delta.x) >= abs(delta.y):
		facing = Direction.RIGHT if delta.x > 0 else Direction.LEFT
	else:
		facing = Direction.DOWN if delta.y > 0 else Direction.UP
	_apply_direction_rotation()


## ダメージを受ける（方向倍率 × 攻撃力 − 防御力、最低1ダメージ保証）
func take_damage(raw_amount: int, multiplier: float = 1.0) -> void:
	var actual: int = max(1, int(float(raw_amount) * multiplier) - defense)
	hp = max(0, hp - actual)
	_spawn_hit_effect(actual)
	if hp <= 0:
		die()


## ヒット位置に HitEffect を生成する（親ノードに追加してワールド座標固定）
## damage を渡してエフェクトサイズをダメージ量に比例させる
func _spawn_hit_effect(actual_damage: int) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var effect := HitEffect.new()
	effect.damage = actual_damage
	effect.position = position
	parent.add_child(effect)


## 攻撃者から対象を攻撃したときの方向ダメージ倍率を返す
## 正面：1.0倍 / 側面：1.5倍 / 背面：2.0倍
static func get_direction_multiplier(attacker: Character, target: Character) -> float:
	# targetから見たattackerの位置 = 攻撃が来る方向
	var attack_from := attacker.grid_pos - target.grid_pos
	var target_fwd  := dir_to_vec(target.facing)
	if attack_from == target_fwd:
		return 1.0  # 正面
	elif attack_from == -target_fwd:
		return 2.0  # 背面
	return 1.5      # 側面


## Direction enum → グリッド方向ベクトル
static func dir_to_vec(dir: Direction) -> Vector2i:
	match dir:
		Direction.DOWN:  return Vector2i( 0,  1)
		Direction.UP:    return Vector2i( 0, -1)
		Direction.LEFT:  return Vector2i(-1,  0)
		Direction.RIGHT: return Vector2i( 1,  0)
	return Vector2i.ZERO


## 死亡処理：シグナルを発火してフィールドから除去する
func die() -> void:
	died.emit(self)
	queue_free()
