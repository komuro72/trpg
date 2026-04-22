class_name Character
extends Node2D

## キャラクター基底クラス
## Phase 1-2: Sprite2D による4方向画像切替。素材がない場合はプレースホルダー表示。
## Phase 2-1: HP・攻撃力・防御力・死亡処理を追加。
## Phase 5:   トップビュー対応。rotation で方向を表現。is_flying フラグを追加。
##             フィールド画像（sprite_top）は下向き基準。DOWN = 0°
## Phase 8:   MP・バフ（defense_up）フィールド追加。use_mp()/heal()/apply_defense_buff() 追加。
## Phase 9-1: 歩行アニメーション追加。move_to() 呼び出しごとに walk1→top→walk2→top を再生。
##             walk1/walk2 画像がない場合は top 固定のままフォールバック。
##             位置補間を追加。move_to(pos, duration) で視覚上の滑らかな移動を実現。
##             衝突判定・grid_pos はグリッド単位のまま即時更新。

## 向き定義（トップビュー基準：DOWN=画面下, UP=画面上, LEFT=左, RIGHT=右）
enum Direction { DOWN, UP, LEFT, RIGHT }

## キャラクターが死亡してフィールドから除去されたときに発火する
signal died(character: Character)
## ダメージを受けたときに発火（attacker はダメージ源・null の場合もある）
signal took_damage_from(attacker: Character)
## ダメージを与えたときに発火（target はダメージを受けたキャラクター）
signal dealt_damage_to(target: Character)

## コミット競合チェック用：全キャラクターを静的に管理
static var _all_chars: Array = []

var grid_pos: Vector2i = Vector2i(0, 0)
var facing: Direction = Direction.DOWN
var character_data: CharacterData = null

## パーティー加入順インデックス（Party.add_member() が設定。ソート表示に使用）
var join_index: int = 0
## プレイヤーが直接操作中のキャラクターであることを示すフラグ（UnitAI は処理をスキップする）
var is_player_controlled: bool = false

## 基本ステータス（装備補正込みの最終値。character_data から _ready() で初期化・
## 装備変更時 refresh_stats_from_equipment() で再計算。13 ステータス全てに適用する統一設計）
## 素値（装備補正前の値）が必要な場合は character_data.X を直接参照する（例：OrderWindow の素値/補正値 2 列表示）
var hp:                 int   = 1
var max_hp:             int   = 1   ## = character_data.max_hp + 装備補正（"vitality" キー）
## エネルギー（全クラス共通。UI 表示は character_data.is_magic_class() で
## 魔法クラス→「MP」/ 非魔法クラス→「SP」として切り替え）
var energy:             int   = 0
var max_energy:         int   = 0   ## = character_data.max_energy + 装備補正（"energy" キー）
var power:              int   = 1   ## 物理威力 or 魔法威力（クラスに応じて使い分け）
var skill:              int   = 0   ## 物理技量 or 魔法技量（命中・クリティカル率の基礎値）
var attack_range:       int   = 1   ## 射程（装備 "range_bonus" キーで補正）
var is_flying:          bool  = false

## 防御強度 3 フィールド（装備補正込み・方向別に独立判定）
var block_right_front:  int   = 0   ## 正面・右側面で有効（剣士・斧戦士・斥候・ハーピー等）
var block_left_front:   int   = 0   ## 正面・左側面で有効（剣士・斧戦士・ハーピー等）
var block_front:        int   = 0   ## 正面のみ有効（弓使い・魔法使い・ヒーラー・ゾンビ等）

## 耐性（逓減カーブ適用前の能力値。装備補正込み）
var physical_resistance: int  = 0   ## 物理耐性能力値（ダメージ軽減率は resistance_to_ratio で算出）
var magic_resistance:    int  = 0   ## 魔法耐性能力値

var defense_accuracy:    int  = 50  ## 防御判定の成功率 %（装備補正込み）

## リーダーシップ・従順度（NPC 合流交渉で参照される値・装備補正込み）
var leadership:          int   = 5
var obedience:           float = 0.5  ## 0.0〜1.0 スケール（character_data と同じ）

## 移動速度（0〜100 スコア・装備補正込み。get_move_duration() で逆比例補正して実時間化）
var move_speed:          float = 50.0

## 最後にダメージを与えたキャラクター（ドロップ帰属の追跡用）
var last_attacker: Character = null

## 現在いるフロアインデックス（0 = 最上層）
var current_floor: int = 0

## エネルギー自動回復の端数蓄積（整数回復のロスをなくす）
var _energy_recovery_accum: float = 0.0
## エネルギーの自動回復速度は GlobalConstants.ENERGY_RECOVERY_RATE を参照

## スタン状態（水魔法等で発生。is_stunned=true 中は UnitAI が行動をスキップする）
var is_stunned:   bool  = false
var stun_timer:   float = 0.0
var _stun_effect: Node2D = null  ## スタンエフェクトノード（スタン中のみ存在）

## スライディング中フラグ（斥候の特殊攻撃中は take_damage() を無視する）
var is_sliding:   bool  = false


## 状態ラベルを返す（HP 割合に基づく。GlobalConstants の閾値で判定）
## AI の戦力評価で敵のHP推定に使用する（直接 hp を参照してはならないため）
func get_condition() -> String:
	if max_hp <= 0:
		return "healthy"
	var ratio := float(hp) / float(max_hp)
	if ratio >= GlobalConstants.CONDITION_HEALTHY_THRESHOLD:
		return "healthy"
	elif ratio >= GlobalConstants.CONDITION_WOUNDED_THRESHOLD:
		return "wounded"
	elif ratio >= GlobalConstants.CONDITION_INJURED_THRESHOLD:
		return "injured"
	return "critical"

## バフ状態（一時的な防御力アップ。0=なし、>0=残り秒数）
## NOTE: 現在はバリアエフェクト表示のみ（numeric な効果なし）。base_defense / defense
## 廃止（2026-04-18）に伴い DEFENSE_BUFF_BONUS による加算は撤去された。バランス微調整時に
## 物理耐性などへの再割り当てを検討
var defense_buff_timer: float = 0.0
## 持続時間は呼出側（SkillExecutor.execute_buff 経由 slot.duration）から指定する
## バリアエフェクトノード（バフ中のみ存在。null=バフなし or 未生成）
var _buff_effect: Node2D = null
## フレンドリーフラグ（NPC など味方側キャラクターに設定。緑のリングで表示）
var is_friendly: bool = false
## プレイヤーパーティー合流フラグ（PartyManager から伝播される）
## true = 主人公または加入済み NPC / false = 未加入 NPC または敵
var joined_to_player: bool = false

## 個別指示（OrderWindow で設定）
## move:             explore=探索 / same_room=同室追従 / cluster=密集 / guard_room=部屋を守る / standby=待機
## battle_formation: surround=包囲 / front=前衛 / rear=後衛 / same_as_leader=リーダーと同じ
## combat:           aggressive=積極攻撃 / support=援護 / standby=待機
## target:           nearest=最近傍 / weakest=最弱 / same_as_leader=リーダーと同じ
## on_low_hp:        keep_fighting=戦い続ける / fall_back=後退 / flee=逃走
##   2026-04-21 リネーム：retreat → fall_back（全体方針 battle_policy="retreat" との内部名重複を解消）
var current_order: Dictionary = {
	"move":             "follow",
	"battle_formation": "surround",
	"combat":           "attack",
	"target":           "same_as_leader",
	"on_low_hp":        "fall_back",
	"item_pickup":      "passive",
	"special_skill":    "strong_enemy",
	"heal":             "lowest_hp_first",
}

## プレースホルダー色（素材がない場合に使用）
var placeholder_color: Color = Color(0.3, 0.7, 1.0)

## パーティーカラーリング（TRANSPARENT=非表示、WHITE=プレイヤーパーティー、その他=NPCパーティー）
## 敵パーティーは TRANSPARENT のままにしてリングを表示しない
var party_color: Color = Color.TRANSPARENT:
	set(value):
		party_color = value
		queue_redraw()

## パーティーリング表示フラグ。
## 未接触NPCパーティー（話しかけたことのないNPC）は false でリング非表示。
## プレイヤーパーティー・敵パーティー・接触済みNPCは true
var party_ring_visible: bool = true:
	set(value):
		party_ring_visible = value
		queue_redraw()

## パーティーリーダーフラグ（true のとき二重リングで表示）
var is_leader: bool = false:
	set(value):
		is_leader = value
		queue_redraw()

## 状態フラグ（modulate制御用）
## is_targeting_mode は setter で構えスプライトへの切替を行う
var is_targeting_mode: bool = false:
	set(value):
		is_targeting_mode = value
		_update_ready_sprite()
## AI攻撃モーション中フラグ（UnitAI が ATTACKING_PRE/POST で制御）
var is_attacking: bool = false:
	set(value):
		is_attacking = value
		_update_ready_sprite()
var is_targeted: bool = false         # ターゲットとして選択されている
## FieldOverlay が設定するハイライト乗数（ターゲット選択中に game_map が書き換える）
## Color.WHITE = 通常、Color(2.5,2.5,2.5) = 明るく強調
var highlight_override: Color = Color.WHITE
## ガード中フラグ（player_controller が X/B ホールド中にセット）
var is_guarding: bool = false:
	set(value):
		is_guarding = value
		_update_ready_sprite()

var _sprite: Sprite2D
var _has_texture: bool = false

## 歩行アニメーション用キャッシュテクスチャ（_load_walk_sprites() で設定）
var _tex_top:    Texture2D = null
var _tex_walk1:  Texture2D = null
var _tex_walk2:  Texture2D = null
var _tex_guard:  Texture2D = null
var _tex_attack: Texture2D = null

## アウトライン用 ShaderMaterial（遅延初期化）
var _outline_material: ShaderMaterial = null

## 視覚的位置補間（グリッド単位の瞬時移動を滑らかに見せる）
## grid_pos・衝突判定は move_to() で即時更新。position だけを補間する
var _visual_from:     Vector2 = Vector2.ZERO  ## 補間開始位置（ワールド座標）
var _visual_to:       Vector2 = Vector2.ZERO  ## 補間終了位置（ワールド座標）
var _visual_elapsed:  float   = 0.0           ## 補間開始からの経過時間（秒）
var _visual_duration: float   = 0.0           ## 補間総時間（秒）。0 = 補間なし
var _pending_grid_pos: Vector2i = Vector2i(-1, -1)  ## 移動先グリッド座標（半マス到達で grid_pos に反映）
var _grid_pos_committed: bool = true  ## grid_pos が確定済みか（false = 半マス待ち）
var _turn_target_facing: Direction = Direction.DOWN  ## 向き変更アニメーションの目標向き
var _turn_tween: Tween = null                        ## 向き変更 tween（実行中は非 null）


func _ready() -> void:
	_all_chars.append(self)
	z_index = 1  # タイル（z_index=0）より手前に表示
	_init_stats()
	_setup_sprite()
	sync_position()


func _exit_tree() -> void:
	_all_chars.erase(self)


func _process(delta: float) -> void:
	_update_modulate()
	# 時間停止中は敵・NPC の移動補間を停止する（プレイヤー操作キャラは常に動かす）
	if GlobalConstants.world_time_running or is_player_controlled:
		_update_visual_move(delta)
	# タイマー類も停止
	if not GlobalConstants.world_time_running:
		return
	_recover_energy(delta)
	# スタンタイマーを消化する
	if stun_timer > 0.0:
		stun_timer -= delta
		if stun_timer <= 0.0:
			stun_timer = 0.0
			is_stunned = false
			if _sprite != null:
				_sprite.rotation = 0.0
			_remove_stun_effect()
	elif is_stunned:
		# 念のため（タイマーが0なのに stunned のまま残るケースの保護）
		is_stunned = false
		if _sprite != null:
			_sprite.rotation = 0.0
		_remove_stun_effect()
	# スタン中はスプライトを回転させてふらふら表現
	if is_stunned and _sprite != null:
		_sprite.rotation += delta * 4.0
	# バフタイマーを消化する
	if defense_buff_timer > 0.0:
		defense_buff_timer -= delta
		if defense_buff_timer <= 0.0:
			defense_buff_timer = 0.0
			_remove_buff_effect()


## HP・モードに応じてスプライトの色を更新する
## Character ノード自体の modulate は WHITE のまま維持し、
## _draw() で描くリングが HP 色の影響を受けないようにする
func _update_modulate() -> void:
	if _sprite == null:
		return

	# ターゲットとして選択中：白く輝かせる
	if is_targeted:
		var s: float = GlobalConstants.TARGETED_MODULATE_STRENGTH
		_sprite.modulate = Color(s, s, s, 1.0)
		return

	# スタン中：シアン点滅
	if is_stunned:
		var t2 := Time.get_ticks_msec() / 1000.0
		var pulse := (sin(t2 * TAU * GlobalConstants.STUN_PULSE_HZ) + 1.0) * 0.5
		_sprite.modulate = Color.WHITE.lerp(Color(0.3, 0.9, 1.0), 0.5 + pulse * 0.5)
		return

	# HP状態ラベルによる色（healthy=白 / wounded=黄 / injured=橙 / critical=赤、wounded以降は点滅）
	_sprite.modulate = GlobalConstants.condition_sprite_modulate(get_condition())

	# FieldOverlay によるハイライト乗数を適用（White = 変化なし）
	if highlight_override != Color.WHITE:
		_sprite.modulate *= highlight_override


## character_data からステータスを初期化する
## refresh_stats_from_equipment() が 13 ステータス全てを素値＋装備補正で計算するため
## ここでは素値コピーを行わず（refresh_stats_from_equipment に一本化）・hp/energy の現在値だけ初期化する
func _init_stats() -> void:
	if character_data == null:
		return
	is_flying    = character_data.is_flying
	refresh_stats_from_equipment()
	# max 値が確定した後に現在値を上限値へ初期化する（refresh 後に hp/energy を埋める）
	hp           = max_hp
	energy       = max_energy


## 装備補正をキャラのパラメータに反映する（13 ステータス全て）
## 装備変更時（_init_stats / OrderWindow._do_equip）に呼ぶ。
## 素値（character_data.X）+ 装備補正（全 equipped スロットの stats.X 合計）= Character.X
## 注意：hp / energy は max 値と共に変動するが、このメソッドでは max 値のみ再計算する
## （現在値の hp / energy は維持される。装備付け替えで max が上がった場合は上限クランプで調整）
func refresh_stats_from_equipment() -> void:
	if character_data == null:
		return
	var cd := character_data
	max_hp              = cd.max_hp              + int(cd.get_equipment_bonus("vitality"))
	max_energy          = cd.max_energy          + int(cd.get_equipment_bonus("energy"))
	power               = cd.power               + int(cd.get_equipment_bonus("power"))
	skill               = cd.skill               + int(cd.get_equipment_bonus("skill"))
	attack_range        = cd.attack_range        + int(cd.get_equipment_bonus("range_bonus"))
	block_right_front   = cd.block_right_front   + int(cd.get_equipment_bonus("block_right_front"))
	block_left_front    = cd.block_left_front    + int(cd.get_equipment_bonus("block_left_front"))
	block_front         = cd.block_front         + int(cd.get_equipment_bonus("block_front"))
	physical_resistance = cd.physical_resistance + int(cd.get_equipment_bonus("physical_resistance"))
	magic_resistance    = cd.magic_resistance    + int(cd.get_equipment_bonus("magic_resistance"))
	defense_accuracy    = cd.defense_accuracy    + int(cd.get_equipment_bonus("defense_accuracy"))
	leadership          = cd.leadership          + int(cd.get_equipment_bonus("leadership"))
	obedience           = cd.obedience           +     cd.get_equipment_bonus("obedience")
	move_speed          = cd.move_speed          +     cd.get_equipment_bonus("move_speed")
	# 現在値が新しい max を超える場合は上限クランプ（装備で max が下がった場合等）
	if hp > max_hp:
		hp = max_hp
	if energy > max_energy:
		energy = max_energy


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	add_child(_sprite)
	_load_top_sprite()
	_load_walk_sprites()
	_apply_direction_rotation()
	_setup_outline_material()


## アウトライン用 ShaderMaterial を起動時に確定する（遅延生成だと反映されないため）
func _setup_outline_material() -> void:
	var shader: Shader = load("res://assets/shaders/outline.gdshader")
	if shader == null:
		return
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = shader
	_outline_material.set_shader_parameter("outline_enabled", false)
	_sprite.material = _outline_material


## アウトラインを表示する。screen_px はスクリーンピクセル単位の太さ
func set_outline(color: Color, screen_px: float) -> void:
	if _outline_material == null:
		return
	# テクスチャピクセル単位に変換（テクスチャ幅 / GRID_SIZE × screen_px）
	var tex_px: float = screen_px
	if _sprite != null and _sprite.texture != null:
		var tex_w: float = _sprite.texture.get_size().x
		if tex_w > 0.0:
			tex_px = screen_px * tex_w / float(GlobalConstants.GRID_SIZE)
	_outline_material.set_shader_parameter("outline_enabled", true)
	_outline_material.set_shader_parameter("outline_color", color)
	_outline_material.set_shader_parameter("outline_width", tex_px)


## アウトラインを非表示にする
func clear_outline() -> void:
	if _outline_material != null:
		_outline_material.set_shader_parameter("outline_enabled", false)


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
		_tex_top = tex  # 歩行アニメ用にキャッシュ
		_sprite.texture = tex
		var tex_size := tex.get_size()
		if tex_size.x > 0:
			var scale_factor := float(GlobalConstants.GRID_SIZE) / tex_size.x
			_sprite.scale = Vector2(scale_factor, scale_factor)
		_sprite.visible = true
		_has_texture = true
	else:
		_tex_top = null
		_sprite.texture = null
		_sprite.visible = false
		_has_texture = false

	queue_redraw()


## 歩行アニメ用テクスチャを事前読み込みする（walk1/walk2 がない場合は null のまま）
##
## 【既存キャラへの適用方法】
## パターン A（image_set フォルダ方式）:
##   CharacterGenerator 経由で生成されるキャラは、image_set フォルダ内の
##   walk1.png / walk2.png が自動で sprite_walk1 / sprite_walk2 に設定される。
##   フォルダに walk1.png / walk2.png を追加するだけで歩行アニメが有効になる。
##
## パターン B（JSON 直接指定方式）:
##   hero.json など直接 JSON で管理するキャラは sprites.walk1 / sprites.walk2 に
##   画像パスを明示する。例: "walk1": "res://assets/images/characters/test/walk1.png"
##   Godot でインポート済みの画像のみ有効（.import ファイルが必要）。
func _load_walk_sprites() -> void:
	_tex_walk1  = null
	_tex_walk2  = null
	_tex_guard  = null
	_tex_attack = null
	if character_data == null:
		return
	var w1 := character_data.sprite_walk1
	if not w1.is_empty() and ResourceLoader.exists(w1):
		_tex_walk1 = load(w1) as Texture2D
	var w2 := character_data.sprite_walk2
	if not w2.is_empty() and ResourceLoader.exists(w2):
		_tex_walk2 = load(w2) as Texture2D
	var gd := character_data.sprite_top_guard
	if not gd.is_empty() and ResourceLoader.exists(gd):
		_tex_guard = load(gd) as Texture2D
	var atk := character_data.sprite_top_attack
	if not atk.is_empty() and ResourceLoader.exists(atk):
		_tex_attack = load(atk) as Texture2D


## ターゲット選択モード・攻撃モーション中・ガード中に応じてスプライトを切り替える
## 優先順: guard.png（ガード中）> attack.png（攻撃中）> ready.png（ターゲット選択中）> top.png（通常）
func _update_ready_sprite() -> void:
	if _sprite == null or character_data == null:
		return
	var path: String
	if is_guarding:
		# ガード中: guard.png → ready.png → top の順でフォールバック
		if not character_data.sprite_top_guard.is_empty() \
				and ResourceLoader.exists(character_data.sprite_top_guard):
			path = character_data.sprite_top_guard
		elif not character_data.sprite_top_ready.is_empty() \
				and ResourceLoader.exists(character_data.sprite_top_ready):
			path = character_data.sprite_top_ready
		else:
			path = character_data.sprite_top
	elif is_attacking:
		# 攻撃中: attack.png → ready.png → top の順でフォールバック
		if not character_data.sprite_top_attack.is_empty() \
				and ResourceLoader.exists(character_data.sprite_top_attack):
			path = character_data.sprite_top_attack
		elif not character_data.sprite_top_ready.is_empty() \
				and ResourceLoader.exists(character_data.sprite_top_ready):
			path = character_data.sprite_top_ready
		else:
			path = character_data.sprite_top
	else:
		var use_ready := is_targeting_mode \
				and not character_data.sprite_top_ready.is_empty()
		path = character_data.sprite_top_ready if use_ready else character_data.sprite_top
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


## 素材がない場合のプレースホルダー描画 + パーティーカラーリング描画（ローカル座標 = 回転前）
func _draw() -> void:
	var gs   := GlobalConstants.GRID_SIZE
	var half := gs * 0.5

	if not _has_texture:
		var margin := 8
		# キャラクター本体（円形）
		draw_circle(Vector2.ZERO, half - margin, placeholder_color)
		# 向きインジケーター（ローカル上方向 = 前方、回転で向きが変わる）
		draw_rect(Rect2(-4, -(half - margin - 2), 8, 10), Color.WHITE)

	# パーティーカラーリング（TRANSPARENT でなければ描画。未接触NPCは party_ring_visible=false で非表示）
	if party_color != Color.TRANSPARENT and party_ring_visible:
		_draw_party_ring(float(gs))


## パーティーカラーのリングを描画する
## 通常メンバー：外周に1本、リーダー：外周＋内周の2本（二重リング）
func _draw_party_ring(gs: float) -> void:
	const RING_WIDTH := 3.0
	const OUTER_RATIO := 0.46
	const INNER_RATIO := 0.34
	draw_arc(Vector2.ZERO, gs * OUTER_RATIO, 0.0, TAU, 64, party_color, RING_WIDTH, true)
	if is_leader:
		draw_arc(Vector2.ZERO, gs * INNER_RATIO, 0.0, TAU, 64, party_color, RING_WIDTH, true)


## 視覚的な移動アニメーション中かどうかを返す
## PlayerController の先行入力バッファがアニメーション完了タイミングを検出するために使用
func is_moving() -> bool:
	return _visual_duration > 0.0


## このキャラクターが占有するグリッド座標の一覧を返す
## 将来的に複数マスを占有するキャラクターはこのメソッドをオーバーライドする
func get_occupied_tiles() -> Array[Vector2i]:
	# 移動中（grid_pos 未確定）は移動先も占有タイルに含める
	if not _grid_pos_committed and _pending_grid_pos != Vector2i(-1, -1) \
			and _pending_grid_pos != grid_pos:
		return [grid_pos, _pending_grid_pos]
	return [grid_pos]


## 移動先が確定前（t<50%）かどうかを返す
func is_pending() -> bool:
	return not _grid_pos_committed and _pending_grid_pos != Vector2i(-1, -1) \
			and _pending_grid_pos != grid_pos


## 移動先グリッド座標を返す（移動中でなければ grid_pos を返す）
func get_pending_grid_pos() -> Vector2i:
	if _pending_grid_pos != Vector2i(-1, -1):
		return _pending_grid_pos
	return grid_pos


## 向き変更アニメーションを開始する（PlayerController から呼ぶ）
## target: 目標向き  duration: アニメーション時間（秒）  last_dir: 180°時の回転方向判定用
func start_turn_animation(target: Direction, duration: float, last_dir: Vector2i) -> void:
	_turn_target_facing = target
	var from_rot := rotation
	var to_rot   := _direction_to_rotation(target)
	var delta    := _calc_turn_delta_rad(from_rot, to_rot, last_dir)
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_property(self, "rotation", from_rot + delta, duration)


## 向き変更を確定する（ディレイ完了時に PlayerController から呼ぶ）
func complete_turn() -> void:
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
		_turn_tween = null
	facing = _turn_target_facing
	_apply_direction_rotation()


## 最短回転角を計算する（符号付きラジアン）
## 180° の場合は last_dir の横成分で回転方向を決定する
static func _calc_turn_delta_rad(from_rot: float, to_rot: float, last_dir: Vector2i) -> float:
	var delta := to_rot - from_rot
	while delta > PI:
		delta -= TAU
	while delta <= -PI:
		delta += TAU
	# 180° のとき last_dir.x で方向を決定（横入力があれば横向きで短い方、なければ時計回り）
	if absf(absf(delta) - PI) < 0.01:
		if last_dir.x < 0:
			delta = PI    # 反時計回り（LEFT 経由）
		else:
			delta = -PI   # 時計回り（RIGHT 経由）
	return delta


## 進行中の移動をアボートして元の位置に戻す（AI の競合解決用）
func abort_move() -> void:
	if _visual_duration <= 0.0:
		return
	var gs := GlobalConstants.GRID_SIZE
	position = Vector2(grid_pos.x * gs + gs * 0.5, grid_pos.y * gs + gs * 0.5)
	_visual_duration    = 0.0
	_pending_grid_pos   = Vector2i(-1, -1)
	_grid_pos_committed = true
	if is_guarding:
		_update_ready_sprite()
	elif _tex_top != null and not (is_targeting_mode or is_attacking):
		_sprite.texture = _tex_top


## グリッド座標をワールド座標に即座スナップする（初期配置・テレポート用）
## 補間中の場合もキャンセルして確定する
func sync_position() -> void:
	var gs := GlobalConstants.GRID_SIZE
	position = Vector2(
		grid_pos.x * gs + gs * 0.5,
		grid_pos.y * gs + gs * 0.5
	)
	_visual_duration    = 0.0  # 補間キャンセル
	_grid_pos_committed = true


## グリッド移動（向きを更新して rotation を変更する）
## duration: 視覚的な移動にかける時間（秒）。呼び出し側の移動間隔に合わせること
## grid_pos は半マス到達時点（進捗50%）で更新される
## 壁や他キャラに塞がれて移動できない状態で、歩行アニメーション（walk1→top→walk2→top）
## だけを再生する。位置・グリッド座標・向きは変更しない
func walk_in_place(duration: float = 0.4) -> void:
	_pending_grid_pos   = grid_pos
	_grid_pos_committed = true
	_visual_from        = position
	_visual_to          = position
	_visual_elapsed     = 0.0
	_visual_duration    = maxf(duration, 0.01)


## 1 マス移動の論理時間（秒・game_speed=1.0 時の値）を返す
## 設計原則「移動関連の二層構造」：ベース値 × 能力値補正の逆比例式で算出
##   実効値 = BASE_MOVE_DURATION × 50 / move_speed
## ガード中は GUARD_MOVE_DURATION_WEIGHT を掛ける（通常 2.0 倍 = 50% 速度）
## 下限は 0.10 秒（ハードコード・設計前提）
## 呼出側は通常 `get_move_duration() / GlobalConstants.game_speed` で実時間に変換する
func get_move_duration() -> float:
	## self.move_speed は装備補正込みの最終値（refresh_stats_from_equipment で更新）
	## 未初期化・0 以下の場合は 50.0（標準値）にフォールバック
	var ms: float = move_speed if move_speed > 0.0 else 50.0
	var duration := GlobalConstants.BASE_MOVE_DURATION * 50.0 / ms
	if is_guarding:
		duration *= GlobalConstants.GUARD_MOVE_DURATION_WEIGHT
	return maxf(0.10, duration)


func move_to(new_grid_pos: Vector2i, duration: float = 0.4) -> void:
	# ガード中は向きを変更しない（facing を維持）
	if not is_guarding:
		var d := new_grid_pos - grid_pos
		if d.x > 0:
			facing = Direction.RIGHT
		elif d.x < 0:
			facing = Direction.LEFT
		elif d.y > 0:
			facing = Direction.DOWN
		elif d.y < 0:
			facing = Direction.UP
		start_turn_animation(facing, duration, d)

	# grid_pos は半マス到達で更新する（_update_visual_move で処理）
	_pending_grid_pos   = new_grid_pos
	_grid_pos_committed = false

	# 視覚的な位置補間を開始（現在の視覚位置から新グリッド位置へ）
	var gs := GlobalConstants.GRID_SIZE
	_visual_from    = position
	_visual_to      = Vector2(new_grid_pos.x * gs + gs * 0.5, new_grid_pos.y * gs + gs * 0.5)
	_visual_elapsed  = 0.0
	_visual_duration = maxf(duration, 0.01)


## ターゲット方向に向きを変える（移動なし）
func face_toward(target_grid_pos: Vector2i) -> void:
	var delta := target_grid_pos - grid_pos
	if abs(delta.x) >= abs(delta.y):
		facing = Direction.RIGHT if delta.x > 0 else Direction.LEFT
	else:
		facing = Direction.DOWN if delta.y > 0 else Direction.UP
	_apply_direction_rotation()


## 視覚的位置補間とウォークアニメーションを毎フレーム更新する（_process() から呼ぶ）
## position をグリッド間で滑らかに補間し、進捗に応じてスプライトフレームを切り替える
## ready/attacking モード中はスプライト切替のみ停止（位置補間は継続）
func _update_visual_move(delta: float) -> void:
	if _visual_duration <= 0.0:
		return

	_visual_elapsed = minf(_visual_elapsed + delta, _visual_duration)
	var t := _visual_elapsed / _visual_duration
	position = _visual_from.lerp(_visual_to, t)

	# 半マス到達（進捗50%）で grid_pos を確定する
	# 移動先が他キャラに取られていたらアボート（競合防止）
	if not _grid_pos_committed and t >= 0.5:
		var dest := _pending_grid_pos
		var conflict := false
		for ch: Character in _all_chars:
			if ch == self or not is_instance_valid(ch):
				continue
			if ch.current_floor != current_floor or ch.is_flying != is_flying:
				continue
			if ch.grid_pos == dest:
				conflict = true
				break
		if conflict:
			abort_move()
			return
		grid_pos = _pending_grid_pos
		_grid_pos_committed = true

	# スプライトフレームを進捗（0→1）で切り替え
	# シーケンス: 0%～25%=walk1, 25%～50%=top, 50%～75%=walk2, 75%～100%=top
	# ターゲット/攻撃モード中は歩行アニメをスキップ（ガード中でも歩行中は通常サイクル）
	if not (is_targeting_mode or is_attacking):
		if _tex_walk1 != null or _tex_walk2 != null:
			var frame := int(t * 4.0) % 4
			match frame:
				0: _sprite.texture = _tex_walk1 if _tex_walk1 != null else _tex_top
				1: _sprite.texture = _tex_top
				2: _sprite.texture = _tex_walk2 if _tex_walk2 != null else _tex_top
				3: _sprite.texture = _tex_top

	if _visual_elapsed >= _visual_duration:
		# 補間完了時に grid_pos が未確定なら確定する（安全策）
		if not _grid_pos_committed:
			grid_pos = _pending_grid_pos
			_grid_pos_committed = true
		_visual_duration = 0.0
		# 補間完了 → top に戻す（ガード中は guard.png へ復帰・_update_ready_sprite() に任せる）
		if is_guarding:
			_update_ready_sprite()
		elif not (is_targeting_mode or is_attacking) and _tex_top != null:
			_sprite.texture = _tex_top


## エネルギーを時間経過で自動回復する（_process() から毎フレーム呼ぶ）
func _recover_energy(delta: float) -> void:
	if max_energy > 0 and energy < max_energy:
		_energy_recovery_accum += GlobalConstants.ENERGY_RECOVERY_RATE * delta
		var gain := int(_energy_recovery_accum)
		if gain > 0:
			energy = mini(energy + gain, max_energy)
			_energy_recovery_accum -= float(gain)
	else:
		_energy_recovery_accum = 0.0


## エネルギーを消費する。消費可能なら true を返す
## 魔法クラスでは MP、非魔法クラスでは SP として UI 表示されるが内部データは同一
func use_energy(cost: int) -> bool:
	if cost <= 0:
		return true
	if energy < cost:
		return false
	energy -= cost
	return true


## HP を回復する（最大HP を超えない）
func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)
	SoundManager.play_from(SoundManager.HEAL, self)


## 消耗品を使用する（Phase 10-3〜）
## item: inventory 内の辞書（category == "consumable"）
## 効果キー：restore_hp / restore_energy
func use_consumable(item: Dictionary) -> void:
	var effect: Dictionary = item.get("effect", {}) as Dictionary
	var restore_hp_val: int = int(effect.get("restore_hp", 0))
	var restore_energy_val: int = int(effect.get("restore_energy", 0))
	var char_name := character_data.character_name if character_data != null else str(name)
	if restore_hp_val > 0:
		heal(restore_hp_val)  # heal() 内で効果音を再生
		MessageLog.add_battle(character_data, null,
			"%sがヒールポーションを使い、自身のHPを回復した" % char_name, self)
	if restore_energy_val > 0:
		energy = mini(energy + restore_energy_val, max_energy)
		SoundManager.play_from(SoundManager.HEAL, self)
		# UI ラベルをクラス種別で切り替え（内部は同じ energy）
		var energy_label := "MP" if character_data != null and character_data.is_magic_class() else "SP"
		MessageLog.add_battle(character_data, null,
			"%sがエナジーポーションを使い、自身の%sを回復した" % [char_name, energy_label], self)
	# インベントリからアイテムを削除
	if character_data != null:
		character_data.inventory.erase(item)


## 防御バフを付与する（重複時はタイマーをリセット・エフェクトも再生成）
## duration: 持続秒数（slot.duration 由来）。0 以下なら何もしない（早期リターン）
func apply_defense_buff(duration: float = 0.0) -> void:
	if duration <= 0.0:
		return  # 呼出側が slot.duration を渡す前提。0 は「バフを付けない」の意
	defense_buff_timer = duration
	# 既存エフェクトがあれば削除してから再生成（タイマーリセット時に視覚的なフィードバック）
	_remove_buff_effect()
	var effect := BuffEffect.new()
	effect.z_index = 1
	add_child(effect)
	_buff_effect = effect


## バリアエフェクトを削除する
func _remove_buff_effect() -> void:
	if _buff_effect != null and is_instance_valid(_buff_effect):
		_buff_effect.queue_free()
	_buff_effect = null


## スタンを付与する（duration 秒間 is_stunned=true。UnitAI の行動をスキップさせる）
## attacker: スタンの発生源（battle メッセージ生成に使用。null 可）
func apply_stun(duration: float, attacker: Character = null) -> void:
	is_stunned = true
	stun_timer = maxf(stun_timer, duration)  # 残り時間が長い方を採用
	# スタンエフェクトを生成（既存があればタイマーリセットのみ）
	if _stun_effect == null or not is_instance_valid(_stun_effect):
		_stun_effect = WhirlpoolEffect.new()
		add_child(_stun_effect)
	var char_name := character_data.character_name if character_data != null else str(name)
	MessageLog.add_combat("[スタン] %s がスタンした（%.1f秒）" % [char_name, duration])
	# 自然言語バトルメッセージ
	if MessageLog != null:
		var atk_name := _battle_name(attacker)
		var def_name := _battle_name(self)
		var atk_data: CharacterData = attacker.character_data \
				if attacker != null and is_instance_valid(attacker) else null
		var msg := "%sが%sに水魔法を放ち、動きを封じた" % [atk_name, def_name]
		MessageLog.add_battle(atk_data, character_data, msg, attacker, self)


## スタンエフェクトを削除する
func _remove_stun_effect() -> void:
	if _stun_effect != null and is_instance_valid(_stun_effect):
		_stun_effect.queue_free()
	_stun_effect = null


## ダメージを受ける（Phase 12-14: クリティカル・新防御ロジック対応版）
## attack_is_magic:      true なら魔法耐性を、false なら物理耐性を適用
## attacker:             ダメージ源（方向判定・クリティカル判定・ドロップ帰属追跡用。null 可）
## suppress_battle_msg:  true のとき battle メッセージを生成しない（スタン攻撃等でスタン側にまとめる場合）
func take_damage(raw_amount: int, multiplier: float = 1.0, attacker: Character = null,
		attack_is_magic: bool = false, suppress_battle_msg: bool = false) -> void:
	if is_sliding:
		return  # スライディング中は無敵
	if attacker != null:
		last_attacker = attacker

	# 0. クリティカル判定（攻撃側の skill から算出）
	var is_critical := false
	if attacker != null:
		var atk_skill: int = attacker.skill
		var crit_chance: float = float(atk_skill) / GlobalConstants.CRITICAL_RATE_DIVISOR
		if randf() < crit_chance:
			is_critical = true
			multiplier *= 2.0  # クリティカル: ダメージ2倍

	# 1. 防御判定（クラス別ロジック・背面は常にスキップ）
	var blocked := 0
	var dir_result := ""
	var defense_succeeded := false
	if attacker != null and character_data != null:
		dir_result = _calc_attack_direction(attacker)
		if dir_result != "back":
			# ガード中＋正面攻撃：ブロック成功率100%・防御強度分カット
			# 側面・背面は通常の防御判定と同じ（防御技量で成功率が決まる）
			if is_guarding and dir_result == "front":
				defense_succeeded = true
				blocked = _calc_block_power_front_guard()
			else:
				blocked = _calc_block_per_class(dir_result)
				if blocked > 0:
					defense_succeeded = true

	# 2. 防御強度を差し引き
	var raw_after_mult: int = int(float(raw_amount) * multiplier)
	var after_block: int = maxi(0, raw_after_mult - blocked)
	var is_fully_blocked: bool = blocked > 0 and raw_after_mult <= blocked

	# 3. 耐性適用（逓減軽減）
	## Character.physical_resistance / magic_resistance は装備補正済みの最終値。
	## resistance_to_ratio で 0〜1 の軽減率に変換してからダメージに乗算する
	var resistance := 0.0
	if attack_is_magic:
		resistance = CharacterData.resistance_to_ratio(magic_resistance)
	else:
		resistance = CharacterData.resistance_to_ratio(physical_resistance)
	var actual: int = maxi(1, int(float(after_block) * (1.0 - resistance)))

	# 戦闘計算ログ出力（デバッグ用 COMBAT メッセージ）
	_log_damage(attacker, raw_amount, multiplier, attack_is_magic,
		dir_result, defense_succeeded, blocked, resistance, actual, is_critical)

	hp = max(0, hp - actual)
	_spawn_hit_effect(actual)
	# クリティカル時は HitEffect をもう1発重ねて強調
	if is_critical:
		_spawn_hit_effect(actual)
	SoundManager.play_from(SoundManager.TAKE_DAMAGE, self)

	# 自然言語バトルメッセージ出力
	if not suppress_battle_msg:
		_emit_damage_battle_msg(attacker, raw_amount, actual,
			is_critical, blocked, is_fully_blocked, attack_is_magic)

	# シグナル発火（共闘フラグ更新など各システムが購読）
	took_damage_from.emit(attacker)
	if attacker != null and is_instance_valid(attacker):
		attacker.dealt_damage_to.emit(self)
	if hp <= 0:
		die()


## 攻撃者から見た防御側の方向を返す（"front" / "left" / "right" / "back"）
## atan2 で4象限判定：防御側の facing を基準に攻撃者の相対角度を計算する
func _calc_attack_direction(attacker: Character) -> String:
	# 防御側から見た攻撃者の相対位置ベクトル（ワールド座標差）
	var dx := attacker.grid_pos.x - grid_pos.x
	var dy := attacker.grid_pos.y - grid_pos.y
	if dx == 0 and dy == 0:
		return "front"

	# 攻撃が来る角度（atan2: y上向き=0、時計回り正）
	var angle_attack := atan2(float(dy), float(dx))

	# 防御側の facing 方向角度（DOWN=π/2、UP=-π/2、RIGHT=0、LEFT=π）
	var facing_angle: float
	match facing:
		Direction.DOWN:  facing_angle = PI / 2.0
		Direction.UP:    facing_angle = -PI / 2.0
		Direction.RIGHT: facing_angle = 0.0
		Direction.LEFT:  facing_angle = PI
		_:               facing_angle = PI / 2.0

	# 防御側の正面方向からの相対角度（-π〜π に正規化）
	var rel := angle_attack - facing_angle
	while rel >  PI: rel -= TAU
	while rel < -PI: rel += TAU

	# 4象限（±45° = ±π/4）で判定
	var quarter := PI / 4.0
	if rel >= -quarter and rel < quarter:
		return "front"
	elif rel >= PI - quarter or rel < -(PI - quarter):
		return "back"
	elif rel >= quarter:
		return "right"
	else:
		return "left"


## ガード中正面攻撃のブロック量（成功率100%・全防御強度フィールドの合計）を返す
## Character の block_* は素値＋装備補正の最終値（refresh_stats_from_equipment で更新）
func _calc_block_power_front_guard() -> int:
	return block_right_front + block_left_front + block_front


## 防御強度3フィールドによるブロック量を返す（各フィールドを独立してロール）
## Character の block_* / defense_accuracy は装備補正済みの最終値を参照する
## block_right_front: 正面・右側面で有効（剣士・斧戦士・斥候・ハーピー・ダークロード等）
## block_left_front:  正面・左側面で有効（剣士・斧戦士・ハーピー・ダークロード等）
## block_front:       正面のみ有効（弓使い・魔法使い・ヒーラー・ゾンビ・ウルフ等）
func _calc_block_per_class(direction: String) -> int:
	var acc: float = float(defense_accuracy) / 100.0
	var total := 0

	# block_right_front: 正面・右側面で有効
	if block_right_front > 0 and direction in ["front", "right"]:
		if randf() < acc:
			total += block_right_front

	# block_left_front: 正面・左側面で有効
	if block_left_front > 0 and direction in ["front", "left"]:
		if randf() < acc:
			total += block_left_front

	# block_front: 正面のみ有効
	if block_front > 0 and direction == "front":
		if randf() < acc:
			total += block_front

	return total


## ======================================================================
## 自然言語バトルメッセージ生成（MessageLog.add_battle に渡す文章を作る）
## ======================================================================

## ダメージ量を日本語の段階ラベルに変換する
static func _damage_label(dmg: int) -> String:
	if dmg <= GlobalConstants.DAMAGE_LEVEL_SMALL:
		return "小ダメージ"
	elif dmg <= GlobalConstants.DAMAGE_LEVEL_MEDIUM:
		return "中ダメージ"
	elif dmg <= GlobalConstants.DAMAGE_LEVEL_LARGE:
		return "大ダメージ"
	else:
		return "特大ダメージ"


## バトルメッセージ用のキャラクター表示名を返す
## 味方（player/npc）は個別名（例：「ヘレン」）、敵は個別敵 JSON の name（種族名、例：「ホブゴブリン」）
## どちらも character_data.character_name を参照する（`load_from_json` で JSON の "name" から取り込み済み）
## 空の場合は character_id にフォールバック
static func _battle_name(ch: Character) -> String:
	if ch == null or not is_instance_valid(ch) or ch.character_data == null:
		return "不明"
	if not ch.character_data.character_name.is_empty():
		return ch.character_data.character_name
	return ch.character_data.character_id


## 攻撃動詞フレーズを返す（mode: "normal"=し, "negative"=したが, "critical"=クリ用）
static func _weapon_action(attacker: Character, mode: String) -> String:
	if attacker == null or not is_instance_valid(attacker) or attacker.character_data == null:
		return "攻撃し" if mode != "negative" else "攻撃したが"
	var cd := attacker.character_data
	var atype := cd.attack_type
	var weapon_type: String = cd.equipped_weapon.get("item_type", "") as String
	match atype:
		"heal":
			return "回復魔法をかけ"
		"dive":
			if mode == "negative":
				return "急降下攻撃を仕掛けたが"
			return "急降下攻撃を仕掛け"
		"magic":
			if mode == "critical":
				return "強烈な魔法を放ち"
			elif mode == "negative":
				return "魔法を放ったが"
			return "魔法を放ち"
		"ranged":
			if mode == "critical":
				return "弓で正確に射抜き"
			elif mode == "negative":
				return "弓で攻撃したが"
			return "弓で攻撃し"
		"melee":
			var wlabel: String
			match weapon_type:
				"sword":  wlabel = "剣"
				"axe":    wlabel = "斧"
				"dagger": wlabel = "短剣"
				_:        wlabel = "武器"
			if mode == "critical":
				return "%sで渾身の一撃を放ち" % wlabel
			elif mode == "negative":
				return "%sで攻撃したが" % wlabel
			return "%sで攻撃し" % wlabel
	return "攻撃し" if mode != "negative" else "攻撃したが"


## 自然言語ダメージバトルメッセージを MessageLog.add_battle に送出する
func _emit_damage_battle_msg(attacker: Character, raw: int, actual: int,
		is_critical: bool, blocked: int, is_fully_blocked: bool,
		attack_is_magic: bool) -> void:
	if MessageLog == null:
		return
	var atk_data: CharacterData = attacker.character_data \
			if attacker != null and is_instance_valid(attacker) else null
	var def_data: CharacterData = character_data

	var atk_name := _battle_name(attacker)
	var def_name := _battle_name(self)
	var atk_color := _party_name_color(attacker)
	var def_color := _party_name_color(self)
	var dmg_label := _damage_label(actual)
	var dmg_color := _damage_label_color(actual)
	var dmg_bold  := _damage_is_huge(actual)

	var msg: String
	var segments: Array = []

	# ── アンデッド特効（ヒーラーがアンデッドを攻撃）
	if atk_data != null and atk_data.attack_type == "heal" \
			and def_data != null and def_data.is_undead:
		msg = "%sが%sに聖なる光を放ち、%sを与えた" % [atk_name, def_name, dmg_label]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["に聖なる光を放ち、", Color.WHITE],
			[dmg_label, dmg_color, dmg_bold], ["を与えた", Color.WHITE],
		])

	# ── ヘッドショット（即死）
	elif raw >= 9999:
		msg = "%sが%sを射抜き、即座に倒した" % [atk_name, def_name]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["を射抜き、即座に倒した", Color.WHITE],
		])

	# ── 完全ブロック
	elif is_fully_blocked:
		var verb := _weapon_action(attacker, "negative")
		msg = "%sが%sに%s、%sは盾で防いだ" % [atk_name, def_name, verb, def_name]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["に" + verb + "、", Color.WHITE],
			[def_name, def_color], ["は盾で防いだ", Color.WHITE],
		])

	# ── クリティカルヒット
	elif is_critical:
		var verb := _weapon_action(attacker, "critical")
		msg = "%sが%sに%s、%sを与えた" % [atk_name, def_name, verb, dmg_label]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["に" + verb + "、", Color.WHITE],
			[dmg_label, dmg_color, dmg_bold], ["を与えた", Color.WHITE],
		])

	# ── 部分ブロック
	elif blocked > 0:
		var verb := _weapon_action(attacker, "negative")
		msg = "%sが%sに%s、%sは盾で防ぎ、%sに抑えた" % \
				[atk_name, def_name, verb, def_name, dmg_label]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["に" + verb + "、", Color.WHITE],
			[def_name, def_color], ["は盾で防ぎ、", Color.WHITE],
			[dmg_label, dmg_color, dmg_bold], ["に抑えた", Color.WHITE],
		])

	# ── 0ダメージ（耐性等で吸収）
	elif actual <= 1:
		var verb := _weapon_action(attacker, "negative")
		msg = "%sが%sに%s、ダメージを与えられなかった" % [atk_name, def_name, verb]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["に" + verb + "、ダメージを与えられなかった", Color.WHITE],
		])

	# ── 通常攻撃
	else:
		var verb := _weapon_action(attacker, "normal")
		msg = "%sが%sに%s、%sを与えた" % [atk_name, def_name, verb, dmg_label]
		segments = _make_segs([
			[atk_name, atk_color], ["が", Color.WHITE],
			[def_name, def_color], ["に" + verb + "、", Color.WHITE],
			[dmg_label, dmg_color, dmg_bold], ["を与えた", Color.WHITE],
		])

	MessageLog.add_battle(atk_data, def_data, msg, attacker, self, segments)


## segments 配列を {text,color,bold} の辞書配列に変換するヘルパー
## 入力: [[text, color], [text, color, bold], ...]
static func _make_segs(raw: Array) -> Array:
	var result: Array = []
	for s: Array in raw:
		var d := {"text": s[0] as String, "color": s[1] as Color}
		if s.size() >= 3:
			d["bold"] = s[2] as bool
		result.append(d)
	return result


## パーティー所属に応じた名前色を返す
## 自パーティー（joined_to_player=true）=青系 / 未加入NPC（is_friendly=true）=水色系 / 敵=暗めの緑
static func _party_name_color(ch: Character) -> Color:
	if ch == null or not is_instance_valid(ch):
		return Color.WHITE
	if ch.joined_to_player:
		return Color(0.50, 0.75, 1.00)   # 自パーティー：青
	if ch.is_friendly:
		return Color(0.55, 0.90, 1.00)   # 未加入NPC：水色
	return Color(0.30, 0.65, 0.35)       # 敵：暗めの緑（状態ラベルの明るい緑と区別）


## ダメージ量に応じたラベル色を返す
## 小=白 / 中=黄 / 大=オレンジ / 特大=赤
static func _damage_label_color(dmg: int) -> Color:
	if dmg <= GlobalConstants.DAMAGE_LEVEL_SMALL:
		return Color.WHITE
	elif dmg <= GlobalConstants.DAMAGE_LEVEL_MEDIUM:
		return Color(1.00, 0.95, 0.30)   # 黄
	elif dmg <= GlobalConstants.DAMAGE_LEVEL_LARGE:
		return Color(1.00, 0.65, 0.20)   # オレンジ
	else:
		return Color(1.00, 0.30, 0.30)   # 赤


## ダメージ量が特大かどうか（太字描画フラグ用）
static func _damage_is_huge(dmg: int) -> bool:
	return dmg > GlobalConstants.DAMAGE_LEVEL_LARGE


## 戦闘計算ログを出力する
func _log_damage(attacker: Character, raw: int, mult: float, is_magic: bool,
		dir: String, def_ok: bool, blocked: int, resist: float, actual: int,
		is_critical: bool = false) -> void:
	if MessageLog == null:
		return
	var atk_name := _char_display_name(attacker)
	var tgt_name := _char_display_name(self)

	# ベースダメージ（クリティカル前）＋クリティカル補正後のダメージ
	var base_dmg := raw                        # クリティカル前のベースダメージ
	var after_crit := int(float(raw) * mult)   # クリティカル後・防御前のダメージ

	# ベースダメージの算出内訳（威力 × 攻撃タイプ倍率 [× クラス補正]）
	var calc_detail := ""
	if attacker != null and attacker.character_data != null:
		var atype: String = attacker.character_data.attack_type
		var t_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get(atype, 1.0) as float
		var type_jp: Dictionary = {
			"melee": "近接", "ranged": "遠距離", "dive": "降下", "magic": "魔法"
		}
		var type_label: String = type_jp.get(atype, atype) as String
		var type_base := int(float(attacker.power) * t_mult)
		if type_base == raw:
			# damage_mult が実質 1.0（クラス補正なし）
			calc_detail = "（威力%d × %s×%.1f）" % [attacker.power, type_label, t_mult]
		else:
			# damage_mult != 1.0（クラス補正あり。int 切り捨て誤差が出ることがある）
			var inferred_dmg_mult := float(raw) / float(type_base) if type_base > 0 else 1.0
			calc_detail = "（威力%d × %s×%.1f × クラス補正×%.2f）" % \
					[attacker.power, type_label, t_mult, inferred_dmg_mult]

	var dmg_label: String
	if is_critical:
		dmg_label = "ベースダメージ%d%s [クリティカル!×2]→%d" % [base_dmg, calc_detail, after_crit]
	else:
		dmg_label = "ベースダメージ%d%s" % [base_dmg, calc_detail]

	# 方向・防御部分（after_crit を基準に計算）
	var dir_str: String
	var dir_jp := _dir_to_jp(dir)
	if dir == "back" or dir.is_empty():
		dir_str = "方向:%s→防御スキップ" % dir_jp if not dir.is_empty() else ""
	elif def_ok:
		dir_str = "方向:%s→防御成功(強度%d)→%d" % [dir_jp, blocked, maxi(0, after_crit - blocked)]
	else:
		dir_str = "方向:%s→防御失敗→%d" % [dir_jp, after_crit]

	# 耐性部分
	var resist_label: String
	if is_magic:
		resist_label = "魔法耐性%d%%" % int(resist * 100.0)
	else:
		resist_label = "耐性%d%%" % int(resist * 100.0)

	var hp_after := maxi(0, hp - actual)
	var text := "%s → %s: %s" % [atk_name, tgt_name, dmg_label]
	if not dir_str.is_empty():
		text += " / %s" % dir_str
	text += " / %s→最終%d / HP%d→%d" % [resist_label, actual, hp, hp_after]
	MessageLog.add_combat(text, grid_pos)


## 回復ログを出力する
func log_heal(healer: Character, amount: int, hp_before: int) -> void:
	if MessageLog == null:
		return
	var h_name := _char_display_name(healer)
	var t_name := _char_display_name(self)
	var text := "%s → %s: 回復 魔力%d → HP%d→%d" % [
		h_name, t_name, amount, hp_before, hp]
	MessageLog.add_combat(text, grid_pos)
	# 自然言語バトルメッセージ（回復）
	var healer_data: CharacterData = healer.character_data \
			if healer != null and is_instance_valid(healer) else null
	var heal_name := _battle_name(healer)
	var target_name := _battle_name(self)
	var heal_color := _party_name_color(healer)
	var target_color := _party_name_color(self)
	var battle_msg := "%sが%sに回復魔法をかけ、HPを回復した" % [heal_name, target_name]
	var segments := _make_segs([
		[heal_name, heal_color], ["が", Color.WHITE],
		[target_name, target_color], ["に回復魔法をかけ、HPを回復した", Color.WHITE],
	])
	MessageLog.add_battle(healer_data, character_data, battle_msg, healer, self, segments)


## キャラクターの表示名を返す
static func _char_display_name(ch: Character) -> String:
	if ch == null or not is_instance_valid(ch):
		return "不明"
	if ch.character_data != null and not ch.character_data.character_name.is_empty():
		return ch.character_data.character_name
	if ch.character_data != null and not ch.character_data.character_id.is_empty():
		return ch.character_data.character_id
	return ch.name


## 方向を日本語に変換する
static func _dir_to_jp(dir: String) -> String:
	match dir:
		"front": return "正面"
		"back":  return "背面"
		"left":  return "左側面"
		"right": return "右側面"
	return dir


## ヒット位置に HitEffect を生成する（親ノードに追加してワールド座標固定）
## damage を渡してエフェクトサイズをダメージ量に比例させる
func _spawn_hit_effect(actual_damage: int) -> void:
	if not visible:
		return  # 別フロアのキャラはエフェクトを出さない
	var parent := get_parent()
	if parent == null:
		return
	var effect := HitEffect.new()
	effect.damage = actual_damage
	effect.position = position
	parent.add_child(effect)


## 回復エフェクトを生成する（AI・プレイヤー両方から呼び出し可能）
## eff_mode: "cast"（キャスト側・外広がり）または "hit"（ターゲット側・内縮み）
func spawn_heal_effect(eff_mode: String) -> void:
	if not visible:
		return  # 別フロアのキャラはエフェクトを出さない
	var parent := get_parent()
	if parent == null:
		return
	var effect := HealEffect.new()
	effect.mode     = eff_mode
	effect.position = position
	parent.add_child(effect)


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
	SoundManager.play_from(SoundManager.DEATH, self)
	# 自然言語バトルメッセージ（死亡通知）
	if MessageLog != null:
		var def_name := _battle_name(self)
		var atk_data: CharacterData = last_attacker.character_data \
				if last_attacker != null and is_instance_valid(last_attacker) else null
		MessageLog.add_battle(atk_data, character_data, "%sは倒れた" % def_name, last_attacker, self)
	died.emit(self)
	queue_free()
