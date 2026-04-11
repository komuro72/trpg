class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Phase 4: NORMAL/TARGETING/FIRINGステートマシン・攻撃スロット・飛翔体対応
## Phase 6-0: クラスJSONのスロット定義を読み込み、クラスごとの攻撃動作に対応
##   - action: "melee" → マンハッタン距離・近接判定
##   - action: "ranged" / "ranged_area" → ユークリッド距離・飛翔体
##   - damage_mult がスロット単位で適用される（背面2倍等の方向補正とは別）
## Phase 6-1: ホールド方式ターゲット選択
##   - 攻撃キーホールド中 = ターゲット選択モード
##   - キーリリース時にターゲットあり→攻撃発動、なし→ノーコストキャンセル
##   - ターゲットソート: 前方±45°を距離順、次いでそれ以外を距離順
##   - ホールド中に射程内の敵リストをリアルタイム更新
## Phase 10-2: 攻撃を Z/A の1ボタンに統合。攻撃タイプはクラスのスロット定義から自動判定

var character: Character = null
var map_data: MapData = null

## 移動先の占有チェック対象
var blocking_characters: Array[Character] = []

## 飛翔体・ターゲットカーソルの add_child 用
var map_node: Node2D = null:
	set(v):
		map_node = v
		_setup_leader_indicator()

## 会話中など入力を一時的に無効化するフラグ
var is_blocked: bool = false

## 移動先に友好的キャラクターがいたときに発火するシグナル（会話トリガー用）
signal npc_bumped(npc_member: Character)

## プレイヤー側ヒーラーが未加入 NPC メンバーを回復したときに発火（has_been_healed フラグ更新用）
signal healed_npc_member(target: Character)

## パーティーメンバー切り替えリクエストシグナル（game_map が処理）
signal switch_char_requested(new_char: Character)

## 移動アニメーションの1タイルあたりの時間・基準値（秒）
## この定数が移動速度を決める。game_speed で割った値が実効値になる
## 【旧方式との違い】タイマーによる移動間隔制御を廃止し、アニメーション完了を
## 次移動の gate として使う先行入力バッファ方式に変更（Phase 9-1）
const MOVE_INTERVAL: float = 0.30
const TURN_DELAY:     float = 0.15   ## 向き変更ディレイ（秒）
const CLASS_JSON_DIR := "res://assets/master/classes/"

## 前方コーン判定しきい値（cos 45° ≈ 0.707）
const FORWARD_CONE_DOT: float = 0.707

## デフォルトスロット（クラスデータが存在しない場合のフォールバック）
const DEFAULT_SLOT_Z: Dictionary = {
	"name": "近接攻撃", "action": "melee",  "type": "physical",
	"range": 1, "damage_mult": 1.0, "pre_delay": 0.0
}

## PRE_DELAY: Z 押下後 pre_delay を消化中（時間進行・ターゲット候補を表示）
## TARGETING: ターゲット選択中（時間停止・d-pad で循環・Z で確定・X/B でキャンセル）
## POST_DELAY: 攻撃後硬直（時間進行・is_attacking=true）
enum Mode { NORMAL, PRE_DELAY, TARGETING, POST_DELAY }

var _mode: Mode = Mode.NORMAL
var _valid_targets: Array[Character] = []
var _target_index:  int = 0  # valid_targets.size() = キャンセル選択

## 先行入力バッファ（アニメーション中に受け付けた移動方向。ZERO=なし）
## 【問題1・2 の修正】アニメーション中は新たな移動をブロックし、この変数に上書き保存する。
## アニメーション完了後にバッファを処理することで以下の問題を解決する：
##   問題1（斜め移動）: 補間途中から別方向への補間開始を防ぐ
##   問題2（長押し停止）: OS キーリピートの位相ズレや瞬間的なZERO入力の影響を受けない
var _move_buffer: Vector2i = Vector2i.ZERO

## 攻撃先行入力バッファ（移動中・post_delay 中に攻撃ボタンが押されたら true に記録）
## 完了の瞬間に移動バッファより優先して攻撃モードに入る
var _attack_buffer: bool = false

## 向き変更ディレイ
var _is_turning:       bool     = false
var _turn_timer:       float    = 0.0
## 回転中に保留している移動方向（回転完了後にキーが押されていれば移動を実行）
var _pending_move_dir: Vector2i = Vector2i.ZERO

## 直前に攻撃した敵（ターゲット選択のデフォルトフォーカス優先候補）
var _last_attacked_target: Character = null

## X ボタン短押しによるアイテム選択 UI のフェーズ
## 0=NONE, 1=ITEM_SELECT, 2=ACTION_SELECT, 3=TRANSFER_SELECT
enum _ItemUIPhase { NONE = 0, ITEM_SELECT = 1, ACTION_SELECT = 2, TRANSFER_SELECT = 3 }
var _item_ui_phase: int = _ItemUIPhase.NONE

## アイテム選択 UI の状態データ
var _last_item_index:    int = 0          # X 連打時に前回位置を維持
var _item_action_cursor: int = 0
var _item_action_list:   Array[String] = []
var _transfer_cursor:    int = 0
var _item_ui_inv:        Array = []       # inventory スナップショット（生データ）
var _item_ui_display:    Array = []       # 表示用リスト（消耗品をグループ化した辞書配列）
## 表示エントリ構造: { item, count, inv_index, image, item_name, item_type, category }

## クラスID → 装備可能アイテムタイプ一覧（OrderWindow.CLASS_EQUIP_TYPES と同一）
const CLASS_EQUIP_TYPES: Dictionary = {
	"fighter-sword":  ["sword",  "armor_plate", "shield"],
	"fighter-axe":    ["axe",    "armor_plate", "shield"],
	"archer":         ["bow",    "armor_cloth"],
	"scout":          ["dagger", "armor_cloth"],
	"magician-fire":  ["staff",  "armor_robe"],
	"magician-water": ["staff",  "armor_robe"],
	"healer":         ["staff",  "armor_robe"],
}
var _cursor: TargetCursor = null

## フロア遷移直後に true にセット（game_map が設定）。
## 遷移先の階段タイルから出るまで移動ブロックを解除する
var stair_just_transitioned: bool = false

## 階段遷移クールダウン中に true（game_map が毎フレーム更新）。
## クールダウン中は遷移が起きないため、階段上でも移動をブロックしない
var stair_cooldown_active: bool = false

## Z 押下後の pre_delay カウントダウン（PRE_DELAY モード）
var _pre_delay_remaining: float = 0.0

## 攻撃後硬直カウントダウン（POST_DELAY モード）
var _post_delay_remaining: float = 0.0

## _input() で検出したターゲット循環方向（+1=次・-1=前・0=なし）
## is_action_just_pressed をポーリングするより確実にボタン1回を捕捉できる
var _cycle_direction: int = 0

## クラスJSONから読み込んだスロットデータ
var _slot_z: Dictionary = {}
var _slot_v: Dictionary = {}

## V スロット使用中フラグ（ターゲット選択・発動中にどのスロットを使うか判別）
var _using_v_slot: bool = false

## 消耗品バー UI（game_map から設定）
var consumable_bar: ConsumableBar = null

## パーティーリーダー（game_map から設定。LB/RBキャラ切り替えの可否判定に使用）
## ゲーム開始時は hero。NPC パーティーに合流してリーダーが変わった場合は更新される
var party_leader: Character = null

## プレイヤーが自パーティーのリーダーかどうか（NPC パーティーに合流した場合は false）
## LB/RB キャラ切り替えはこのフラグが true のときのみ有効
var player_is_leader: bool = true

## パーティーメンバーリスト（game_map から設定。LB/RBキャラ切り替えに使用）
var _party_sorted_members: Array[Character] = []

## リーダー方角インジケーター（非リーダー操作中・リーダーが画面外のとき表示）
var _leader_indicator: Node2D = null

## V スロットクールダウン（秒）
const V_SLOT_COOLDOWN: float = 2.0
var _v_slot_cooldown: float = 0.0


## 現在スロットの action と有効射程を返す（game_map の射程タイル描画に使用）
## { "action": String, "range": int }
func get_current_slot_range_info() -> Dictionary:
	var sd := _get_slot()
	var action: String = str(sd.get("action", "melee"))
	var range_bonus: int = 0
	if character != null and character.character_data != null:
		range_bonus = character.character_data.get_weapon_range_bonus()
	var range_val: int = int(sd.get("range", 1)) + range_bonus
	return { "action": action, "range": range_val }


## ターゲット選択モード中かどうかを返す（FieldOverlay が参照）
func is_targeting() -> bool:
	return _mode == Mode.TARGETING


## ターゲット選択中の有効ターゲットリストを返す（FieldOverlay が参照）
func get_valid_targets() -> Array[Character]:
	return _valid_targets


## ターゲット選択中（PRE_DELAY/TARGETING）の現在ターゲットを返す。非選択中は null
func get_current_target() -> Character:
	if _mode != Mode.TARGETING and _mode != Mode.PRE_DELAY:
		return null
	if _valid_targets.is_empty() or _target_index >= _valid_targets.size():
		return null
	return _valid_targets[_target_index]


func _ready() -> void:
	_load_class_slots()


## ターゲット循環ボタン（LB/RB）をイベント駆動で確実に捕捉する
## _process でのポーリング（is_action_just_pressed）は他ボタンホールド中に
## 取りこぼす場合があるため、_input() で毎イベントを直接受け取る方式に変更
func _input(event: InputEvent) -> void:
	# ターゲット選択モード中：LB/RBでターゲット循環
	if _mode == Mode.TARGETING:
		if event.is_action_pressed("cycle_target_next", false):
			_cycle_direction = 1
		elif event.is_action_pressed("cycle_target_prev", false):
			_cycle_direction = -1
		return

	# PRE_DELAY / POST_DELAY 中はキャラ切り替えを抑制
	if _mode == Mode.PRE_DELAY or _mode == Mode.POST_DELAY:
		return

	# アイテム UI 中：LB/RBでカーソル循環
	if _item_ui_phase != _ItemUIPhase.NONE:
		if event.is_action_pressed("switch_char_next", false) \
				or event.is_action_pressed("cycle_target_next", false):
			_cycle_direction = 1
		elif event.is_action_pressed("switch_char_prev", false) \
				or event.is_action_pressed("cycle_target_prev", false):
			_cycle_direction = -1
		return

	# 通常モード：LB/RBでキャラクター切り替え
	if _mode == Mode.NORMAL and not is_blocked:
		if event.is_action_pressed("switch_char_next", false):
			_switch_character(1)
		elif event.is_action_pressed("switch_char_prev", false):
			_switch_character(-1)


# --------------------------------------------------------------------------
# クラス別スロット初期化
# --------------------------------------------------------------------------

## character のクラスIDに基づいてスロットデータをロードする
## クラスデータが存在しない場合はデフォルト（近接攻撃）を使用
func _load_class_slots() -> void:
	_slot_z = DEFAULT_SLOT_Z.duplicate()
	if character == null or character.character_data == null:
		return
	var class_id := character.character_data.class_id
	if class_id.is_empty():
		return
	var class_json := _read_class_json(class_id)
	if class_json.is_empty():
		return
	var slots: Dictionary = class_json.get("slots", {}) as Dictionary
	var z_data: Variant = slots.get("Z")
	if z_data != null and z_data is Dictionary:
		_slot_z = (z_data as Dictionary).duplicate()
	var v_data: Variant = slots.get("V")
	if v_data != null and v_data is Dictionary:
		_slot_v = (v_data as Dictionary).duplicate()


func _get_slot() -> Dictionary:
	if _using_v_slot and not _slot_v.is_empty():
		return _slot_v
	return _slot_z if not _slot_z.is_empty() else DEFAULT_SLOT_Z.duplicate()


# --------------------------------------------------------------------------
# メインループ
# --------------------------------------------------------------------------

## リーダー方角インジケーターを初期化する（map_node 設定後の初回呼び出し時に生成）
func _setup_leader_indicator() -> void:
	if _leader_indicator != null or map_node == null:
		return
	_leader_indicator = Node2D.new()
	_leader_indicator.z_index = 10
	_leader_indicator.visible = false
	var gs := float(GlobalConstants.GRID_SIZE)
	var size := gs * 0.32
	# ローカル +X 方向を向く三角形。rotation で実際の向きに対応
	_leader_indicator.draw.connect(func() -> void:
		var col := Color.WHITE
		if is_instance_valid(party_leader) and party_leader.party_color != Color.TRANSPARENT:
			col = party_leader.party_color
		col.a = 0.80
		var pts := PackedVector2Array([
			Vector2(size,          0.0),
			Vector2(-size * 0.55,  size * 0.50),
			Vector2(-size * 0.55, -size * 0.50),
		])
		_leader_indicator.draw_colored_polygon(pts, col)
		# 輪郭線（視認性向上）
		_leader_indicator.draw_polyline(
			PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
			Color(1.0, 1.0, 1.0, 0.50), 1.5)
	)
	map_node.add_child(_leader_indicator)


## リーダー方角インジケーターを毎フレーム更新する
func _update_leader_indicator() -> void:
	_setup_leader_indicator()
	if _leader_indicator == null:
		return
	# 表示条件：操作キャラがリーダーでない かつ リーダーが有効
	# （player_is_leader はパーティー全体のリーダー権フラグであり、
	#   LB/RB で非リーダーキャラに切り替えても true のまま。
	#   正しくは character != party_leader で判定する）
	if character == null or not is_instance_valid(character) \
			or party_leader == null or not is_instance_valid(party_leader) \
			or character == party_leader:
		_leader_indicator.visible = false
		return
	# リーダーのスクリーン座標を取得して画面内外を判定
	var viewport := character.get_viewport()
	if viewport == null:
		_leader_indicator.visible = false
		return
	var screen_pos := viewport.get_canvas_transform() * party_leader.global_position
	if viewport.get_visible_rect().has_point(screen_pos):
		_leader_indicator.visible = false
		return
	# 操作キャラ → リーダーの方向ベクトル
	var dir := party_leader.global_position - character.global_position
	if dir.length_squared() < 1.0:
		_leader_indicator.visible = false
		return
	dir = dir.normalized()
	var gs := float(GlobalConstants.GRID_SIZE)
	_leader_indicator.global_position = character.global_position + dir * gs * 1.5
	_leader_indicator.rotation = dir.angle()
	_leader_indicator.visible = true
	_leader_indicator.queue_redraw()


func _process(delta: float) -> void:
	# V スロットクールダウンのカウントダウン（is_blocked 中も進める）
	if _v_slot_cooldown > 0.0:
		_v_slot_cooldown = maxf(0.0, _v_slot_cooldown - delta)
		if consumable_bar != null:
			consumable_bar.v_slot_cooldown = _v_slot_cooldown
			consumable_bar.refresh()

	if character == null:
		return

	_update_leader_indicator()

	# world_time_running を現在の状態に応じて更新する（is_blocked チェックより前）
	_update_world_time()

	if is_blocked:
		# ブロック中（メニュー等）はガードを解除する
		if character.is_guarding:
			character.is_guarding = false
		# アイテム UI も閉じる
		if _item_ui_phase != _ItemUIPhase.NONE:
			_exit_item_ui()
		return

	# アイテム選択 UI が開いている間は通常処理を差し替える
	if _item_ui_phase != _ItemUIPhase.NONE:
		_process_item_ui()
		return

	match _mode:
		Mode.NORMAL:
			_process_normal(delta)
		Mode.PRE_DELAY:
			_process_pre_delay(delta)
		Mode.TARGETING:
			_process_targeting(delta)
		Mode.POST_DELAY:
			_process_post_delay(delta)


func _process_normal(_delta: float) -> void:
	# X 短押し：アイテム選択 UI を開く
	if Input.is_action_just_pressed("use_item"):
		_enter_item_select()
		return

	# 特殊攻撃（V/Y）
	# インスタント系（sliding/whirlwind/rush/flame_circle）は just_pressed で即時発動
	# ターゲット系（headshot/water_stun/buff_defense）は just_pressed で PRE_DELAY へ
	if not _slot_v.is_empty():
		var v_action: String = _slot_v.get("action", "") as String
		var instant_actions: Array = ["sliding", "whirlwind", "rush", "flame_circle"]
		if instant_actions.has(v_action):
			if Input.is_action_just_pressed("special_skill"):
				if _v_slot_cooldown <= 0.0 and _has_v_slot_resources():
					_execute_v_instant(v_action)
		else:
			if Input.is_action_just_pressed("special_skill"):
				if _v_slot_cooldown <= 0.0 and _has_v_slot_resources():
					_using_v_slot = true
					_move_buffer  = Vector2i.ZERO
					_enter_pre_delay()
					return

	# 攻撃キー押下：隣接NPCがいれば会話を優先、いなければ通常攻撃
	if Input.is_action_just_pressed("attack"):
		var adj_npc := _find_adjacent_npc()
		if adj_npc != null:
			npc_bumped.emit(adj_npc)
			# 会話ウィンドウが開いた（is_blocked が立った）場合は攻撃しない
			if is_blocked:
				return
		_using_v_slot     = false
		_pending_move_dir = Vector2i.ZERO
		if character.is_guarding:
			character.is_guarding = false
		_move_buffer = Vector2i.ZERO
		_enter_pre_delay()
		return

	_process_guard_and_move(_delta)


## ガード入力・移動入力を処理する（通常モード）
func _process_guard_and_move(_delta: float) -> void:
	# ガード（X/B ホールド）
	var want_guard := Input.is_action_pressed("menu_back")
	if character.is_guarding != want_guard:
		character.is_guarding = want_guard

	# 向き変更ディレイ中は移動入力をブロック（攻撃は _process_normal で処理済み）
	if _is_turning:
		_turn_timer -= _delta
		if _turn_timer <= 0.0:
			_is_turning = false
			if is_instance_valid(character):
				character.complete_turn()
			# 回転完了：キーがまだ押されていれば移動を実行（離されていれば停止）
			var cur_dir := _get_input_direction()
			_pending_move_dir = Vector2i.ZERO
			if cur_dir != Vector2i.ZERO:
				_try_move(cur_dir)
		return

	var dir := _get_input_direction()

	# アニメーション中は新たな移動をブロック
	# キーが押されていればバッファに上書き記録、離されたらバッファをクリア
	if character.is_moving():
		_move_buffer = dir  # ZERO でも上書き（離したらキャンセル）
		# 移動中の攻撃ボタン押下をバッファに記録
		if Input.is_action_just_pressed("attack"):
			_attack_buffer = true
		elif Input.is_action_just_released("attack"):
			_attack_buffer = false
		return

	# 階段タイルに静止中は移動をブロック（game_map が遷移を処理する）
	# stair_just_transitioned=true なら遷移直後 → ブロックせず移動を許可する
	# stair_cooldown_active=true ならクールダウン中で遷移は起きない → ブロック不要
	# 上記いずれでもない（cooldown=0 かつ初回踏み）ときだけブロックして遷移を待つ
	if map_data != null:
		var cur_tile := map_data.get_tile(character.grid_pos)
		var on_stairs := cur_tile == MapData.TileType.STAIRS_DOWN \
				or cur_tile == MapData.TileType.STAIRS_UP
		if on_stairs:
			if not stair_just_transitioned and not stair_cooldown_active:
				_move_buffer = Vector2i.ZERO
				return
			# 遷移直後またはクールダウン中は移動を許可する
		else:
			stair_just_transitioned = false  # 階段タイルから出たらリセット

	# アニメーション完了後：攻撃バッファを移動バッファより優先
	if _attack_buffer:
		_attack_buffer = false
		_move_buffer   = Vector2i.ZERO
		_using_v_slot  = false
		if character.is_guarding:
			character.is_guarding = false
		_enter_pre_delay()
		return

	# 次いで移動バッファ → 現在の入力
	var effective_dir := _move_buffer if _move_buffer != Vector2i.ZERO else dir
	_move_buffer = Vector2i.ZERO
	if effective_dir == Vector2i.ZERO:
		return

	_try_move(effective_dir)


func _process_pre_delay(delta: float) -> void:
	# pre_delay を消化しながらターゲット候補を表示
	_pre_delay_remaining -= delta
	_refresh_targets()
	_update_cursor()
	if _pre_delay_remaining <= 0.0:
		_start_targeting()


func _process_targeting(_delta: float) -> void:
	# 死亡等による対象消失を検出してリフレッシュ
	_refresh_targets()

	# X/B でキャンセル（ノーコスト）
	if Input.is_action_just_pressed("menu_back"):
		_exit_targeting()
		return

	# Z/A（または V 使用中は special_skill）で確定。候補なしならキャンセル扱い
	var confirm_pressed := false
	if _using_v_slot:
		confirm_pressed = Input.is_action_just_pressed("special_skill")
	else:
		confirm_pressed = Input.is_action_just_pressed("attack")
	if confirm_pressed:
		if _valid_targets.is_empty():
			_exit_targeting()
		else:
			_confirm_target()
		return

	# 循環選択
	# ゲームパッド LB/RB: _input() で捕捉した _cycle_direction を使用（取りこぼし防止）
	# キーボード: 右/下=次・左/上=前（is_action_just_pressed で同フレーム検出）
	if _cycle_direction != 0:
		_cycle_target(_cycle_direction)
		_cycle_direction = 0
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
		_cycle_target(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
		_cycle_target(-1)


func _process_post_delay(delta: float) -> void:
	# 硬直中の攻撃ボタン押下をバッファに記録
	if Input.is_action_just_pressed("attack"):
		_attack_buffer = true
	elif Input.is_action_just_released("attack"):
		_attack_buffer = false
	_post_delay_remaining -= delta
	if _post_delay_remaining <= 0.0:
		_post_delay_remaining = 0.0
		_mode = Mode.NORMAL
		if is_instance_valid(character):
			character.is_attacking = false
		# 攻撃バッファがあれば即座に PRE_DELAY へ
		if _attack_buffer:
			_attack_buffer = false
			_using_v_slot = false
			_enter_pre_delay()
			return


# --------------------------------------------------------------------------
# ターゲット選択
# --------------------------------------------------------------------------

## Z 押下後に PRE_DELAY モードに入る（pre_delay 消化後に TARGETING へ）
func _enter_pre_delay() -> void:
	var sd := _get_slot()
	# MP/SP不足なら入れない
	var mp_cost := int(sd.get("mp_cost", 0))
	if mp_cost > 0 and character.mp < mp_cost:
		return
	var sp_cost := int(sd.get("sp_cost", 0))
	if sp_cost > 0 and character.sp < sp_cost:
		return

	_attack_buffer       = false
	_pending_move_dir    = Vector2i.ZERO
	_mode                = Mode.PRE_DELAY
	_move_buffer         = Vector2i.ZERO
	_pre_delay_remaining = float(sd.get("pre_delay", 0.0))
	character.is_targeting_mode = true

	_valid_targets = _get_sorted_targets()
	_target_index  = 0
	if map_node != null:
		_cursor = TargetCursor.new()
		_cursor.z_index = 3
		map_node.add_child(_cursor)
	_update_cursor()


## PRE_DELAY 消化後に TARGETING モードへ移行する
func _start_targeting() -> void:
	_refresh_targets()
	_mode = Mode.TARGETING
	# 射程内の全対象をグレー細アウトラインで下地表示
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.set_outline(Color(0.65, 0.65, 0.65), 1.0)
	_update_cursor()


func _exit_targeting() -> void:
	_mode = Mode.NORMAL
	_using_v_slot = false
	# 全キャラクターのアウトライン・is_targeted を完全クリア（漏れを防ぐため全体を走査）
	for c: Variant in Character._all_chars:
		if not is_instance_valid(c):
			continue
		var ch := c as Character
		if ch == null:
			continue
		ch.is_targeted = false
		ch.clear_outline()
	_valid_targets.clear()
	_target_index        = 0
	_pre_delay_remaining = 0.0
	_cycle_direction     = 0
	character.is_targeting_mode = false
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null


## TARGETING モードでターゲット確定 → 射程チェック → 攻撃実行 → POST_DELAY へ
func _confirm_target() -> void:
	var target := _valid_targets[_target_index]
	var sd     := _get_slot()

	# 射程チェック（pre_delay 中に敵が逃げた可能性）
	if not _is_target_in_range(target, sd):
		_exit_targeting()  # ノーコストキャンセル
		return

	# カーソル・ターゲットモード解除
	# 全キャラクターのアウトライン・is_targeted を完全クリア
	for c: Variant in Character._all_chars:
		if not is_instance_valid(c):
			continue
		var ch := c as Character
		if ch == null:
			continue
		ch.is_targeted = false
		ch.clear_outline()
	_valid_targets.clear()
	_target_index = 0
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null
	character.is_targeting_mode = false

	var action: String = str(sd.get("action", "melee"))
	var was_v := _using_v_slot
	_using_v_slot = false

	# 直前の攻撃対象を記録（heal/buff は除く）
	if action != "heal" and action != "buff_defense":
		_last_attacked_target = target

	if action == "melee":
		_execute_melee(target, sd)
	elif action == "ranged" or action == "ranged_area":
		_execute_ranged(target, sd)
	elif action == "water_stun":
		_execute_water_stun(target, sd)
	elif action == "heal":
		_execute_heal(target, sd)
	elif action == "buff_defense":
		_execute_buff(target, sd)
	elif action == "headshot":
		_execute_headshot(target, sd)

	if was_v:
		_start_v_cooldown()

	# post_delay 開始
	var post_dur := 0.0
	if character != null and character.character_data != null:
		post_dur = character.character_data.post_delay
	_enter_post_delay(post_dur)


## 射程内かどうかを判定する（TARGETING 確定時の再チェック用）
func _is_target_in_range(target: Character, sd: Dictionary) -> bool:
	if not is_instance_valid(target) or target.hp <= 0:
		return false
	var action: String = str(sd.get("action", "melee"))
	var range_bonus: int = character.character_data.get_weapon_range_bonus() \
		if character != null and character.character_data != null else 0
	var range_val: int = int(sd.get("range", 1)) + range_bonus
	if action == "melee":
		var dx: int = abs(target.grid_pos.x - character.grid_pos.x)
		var dy: int = abs(target.grid_pos.y - character.grid_pos.y)
		return dx + dy <= range_val
	else:
		var dist := Vector2(character.grid_pos).distance_to(Vector2(target.grid_pos))
		return dist <= float(range_val)


func _enter_post_delay(dur: float) -> void:
	if dur <= 0.0:
		_mode = Mode.NORMAL
		return
	_mode = Mode.POST_DELAY
	_post_delay_remaining = dur
	if is_instance_valid(character):
		character.is_attacking = true


## ターゲットリストをリフレッシュ（ホールド中の毎フレーム更新）
func _refresh_targets() -> void:
	var prev_target: Character = null
	if _target_index < _valid_targets.size():
		prev_target = _valid_targets[_target_index]

	var new_targets := _get_sorted_targets()
	# 新リストから外れた旧ターゲットのアウトラインをクリア
	for t: Character in _valid_targets:
		if is_instance_valid(t) and not new_targets.has(t):
			t.is_targeted = false
			t.clear_outline()
	_valid_targets = new_targets

	if _valid_targets.is_empty():
		_target_index = 0
		_update_cursor()
		return

	# 前回選択していた敵が新リストにあれば維持
	if prev_target != null and is_instance_valid(prev_target):
		var idx := _valid_targets.find(prev_target)
		if idx >= 0:
			_target_index = idx
			_update_cursor()
			return

	# 消えた場合は先頭へ
	_target_index = 0
	_update_cursor()


func _cycle_target(dir: int) -> void:
	if _valid_targets.is_empty():
		return
	_target_index = (_target_index + dir + _valid_targets.size()) % _valid_targets.size()
	_update_cursor()


func _update_cursor() -> void:
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
			t.set_outline(Color(0.65, 0.65, 0.65), 1.0)  # 非フォーカス：グレー細
	if _cursor == null:
		return
	if _valid_targets.is_empty():
		_cursor.visible = false
	else:
		_cursor.visible = true
		var tgt := _valid_targets[_target_index]
		_cursor.position = tgt.position
		tgt.is_targeted  = true
		tgt.set_outline(Color.WHITE, 2.5)  # フォーカス中：白太


## 有効なターゲットを返す（heal/buff_defense は距離→HP昇順、それ以外は前方コーン優先）
func _get_sorted_targets() -> Array[Character]:
	var sd:     Dictionary = _get_slot()
	var action: String     = str(sd.get("action", "melee"))
	if action == "heal" or action == "buff_defense":
		var targets := _get_valid_targets()
		targets.sort_custom(func(a: Character, b: Character) -> bool:
			var da := _dist_to(a)
			var db := _dist_to(b)
			if absf(da - db) > 0.01:
				return da < db
			var ra := float(a.hp) / float(maxi(a.max_hp, 1))
			var rb := float(b.hp) / float(maxi(b.max_hp, 1))
			return ra < rb)
		return targets
	return _sort_targets(_get_valid_targets())


## 前方±45°の敵を距離順 → その他の敵を距離順の順でソート
## 直前に攻撃した敵が有効なら先頭に移動（デフォルトフォーカス優先）
func _sort_targets(targets: Array[Character]) -> Array[Character]:
	var forward: Array[Character] = []
	var others:  Array[Character] = []
	for t: Character in targets:
		if _is_in_forward_cone(t):
			forward.append(t)
		else:
			others.append(t)
	forward.sort_custom(func(a: Character, b: Character) -> bool:
		return _dist_to(a) < _dist_to(b))
	others.sort_custom(func(a: Character, b: Character) -> bool:
		return _dist_to(a) < _dist_to(b))
	var result: Array[Character] = []
	result.append_array(forward)
	result.append_array(others)
	# 直前に攻撃した敵が生存・射程内・方向範囲内なら先頭に移動
	if _last_attacked_target != null and is_instance_valid(_last_attacked_target) \
			and _last_attacked_target.hp > 0 and result.has(_last_attacked_target):
		result.erase(_last_attacked_target)
		result.push_front(_last_attacked_target)
	return result


## キャラクターの向きから前方±45°コーン内にいるか判定
func _is_in_forward_cone(target: Character) -> bool:
	var fwd  := Vector2(Character.dir_to_vec(character.facing))
	var diff := Vector2(target.grid_pos - character.grid_pos)
	if diff == Vector2.ZERO:
		return false
	return fwd.dot(diff.normalized()) >= FORWARD_CONE_DOT


func _dist_to(target: Character) -> float:
	return Vector2(character.grid_pos).distance_to(Vector2(target.grid_pos))


## world_time_running を現在のモード・キャラ状態に応じて更新する
## 移動中・ガード中・pre_delay 中・post_delay 中・インスタントV実行中 → true
## ターゲット選択中（TARGETING）・無入力待機 → false
func _update_world_time() -> void:
	# アイテム UI 中は時間停止
	if _item_ui_phase != _ItemUIPhase.NONE:
		GlobalConstants.world_time_running = false
		return
	# 向き変更ディレイ中は時間進行
	if _is_turning:
		GlobalConstants.world_time_running = true
		return
	if _mode == Mode.PRE_DELAY or _mode == Mode.POST_DELAY:
		GlobalConstants.world_time_running = true
		return
	if _mode == Mode.TARGETING:
		GlobalConstants.world_time_running = false
		return
	# NORMAL モード：キャラの状態で判定
	# _move_buffer に入力が残っている間は「連続移動中」と判断して暗転させない
	if character != null:
		if character.is_moving() or character.is_guarding \
				or character.is_attacking or character.is_sliding \
				or _move_buffer != Vector2i.ZERO:
			GlobalConstants.world_time_running = true
			return
	GlobalConstants.world_time_running = false


## 有効なターゲット一覧を返す（ソートなし）
## "melee" → マンハッタン距離、"ranged"/"ranged_area" → ユークリッド距離
## "heal"/"buff_defense" → is_friendly な射程内の味方（自分除く）
func _get_valid_targets() -> Array[Character]:
	var sd:        Dictionary = _get_slot()
	var action:    String     = str(sd.get("action", "melee"))
	var range_bonus: int = character.character_data.get_weapon_range_bonus() \
		if character != null and character.character_data != null else 0
	var range_val: int = int(sd.get("range", 1)) + range_bonus
	var result: Array[Character] = []
	for c: Character in blocking_characters:
		if not is_instance_valid(c):
			continue
		if c.current_floor != character.current_floor:
			continue
		if action == "heal" or action == "buff_defense":
			var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
			if dist > float(range_val):
				continue
			# 正面±45°コーン外は対象にしない（ranged と同じ方向制限）
			if not _is_in_forward_cone(c):
				continue
			# "heal" のみ：アンデッド敵（is_undead=true）も特効ターゲットとして含める
			if action == "heal" and not c.is_friendly \
					and c.character_data != null and c.character_data.is_undead:
				result.append(c)
				continue
			# 射程内の is_friendly な味方（自分を除く）が対象
			if not c.is_friendly or c == character:
				continue
			result.append(c)
			continue
		# 攻撃系: 味方キャラクターは対象にしない
		if c.is_friendly:
			continue
		if action == "melee":
			# 飛行ターゲットへの近接攻撃は不可（地上→飛行・飛行→飛行）
			if c.is_flying:
				continue
			var dx: int = abs(c.grid_pos.x - character.grid_pos.x)
			var dy: int = abs(c.grid_pos.y - character.grid_pos.y)
			if dx + dy > range_val:
				continue
			# 前方5マス（左後・真後・右後を除く）：dot >= 0.0
			var fwd := Vector2(Character.dir_to_vec(character.facing))
			var diff := Vector2(c.grid_pos - character.grid_pos)
			if diff != Vector2.ZERO and fwd.dot(diff.normalized()) < 0.0:
				continue
			result.append(c)
		elif action == "ranged" or action == "ranged_area" or action == "water_stun" \
				or action == "headshot":
			var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
			if dist > float(range_val):
				continue
			# 正面±45度（前方90度コーン）のみ有効
			if not _is_in_forward_cone(c):
				continue
			result.append(c)
	return result


# --------------------------------------------------------------------------
# 攻撃実行
# --------------------------------------------------------------------------

func _execute_melee(target: Character, slot_data: Dictionary) -> void:
	var mp_cost := int(slot_data.get("mp_cost", 0))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	var sp_cost := int(slot_data.get("sp_cost", 0))
	if sp_cost > 0:
		character.use_sp(sp_cost)
	var dmg_mult: float = float(slot_data.get("damage_mult", 1.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)
	character.face_toward(target.grid_pos)
	var raw_damage := int(float(character.power) * dmg_mult * type_mult)
	var is_magic   := (slot_data.get("type", "physical") as String) == "magic"
	SoundManager.play_attack(character)
	target.take_damage(raw_damage, 1.0, character, is_magic)
	SoundManager.play_hit(character)
	var skill_name: String = str(slot_data.get("name", "近接"))
	print("[Player] %s → %s  スキル%.1fx  HP:%d/%d" % \
			[skill_name, target.name, dmg_mult, target.hp, target.max_hp])


func _execute_ranged(target: Character, slot_data: Dictionary) -> void:
	var mp_cost := int(slot_data.get("mp_cost", 0))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	var sp_cost := int(slot_data.get("sp_cost", 0))
	if sp_cost > 0:
		character.use_sp(sp_cost)
	var dmg_mult: float = float(slot_data.get("damage_mult", 1.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
	character.face_toward(target.grid_pos)
	var is_magic   := (slot_data.get("type", "physical") as String) == "magic"
	var raw_damage := int(float(character.power) * dmg_mult * type_mult)
	SoundManager.play_attack(character)
	_spawn_projectile(target, raw_damage, is_magic)


func _execute_water_stun(target: Character, slot_data: Dictionary) -> void:
	var mp_cost := int(slot_data.get("mp_cost", 0))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	var dmg_mult      := float(slot_data.get("damage_mult", 0.5))
	var stun_duration := float(slot_data.get("stun_duration", 3.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
	var raw_damage    := int(float(character.power) * dmg_mult * type_mult)
	character.face_toward(target.grid_pos)
	SoundManager.play(SoundManager.MAGIC_SHOOT)
	# 水弾を発射（着弾時にダメージ＋スタン付与）
	if map_node != null:
		var proj := Projectile.new()
		proj.z_index = 2
		map_node.add_child(proj)
		proj.setup(character.position, target.position, true, target,
				raw_damage, 1.0, character, true, stun_duration, true)
	var skill_name := str(slot_data.get("name", "水魔法"))
	MessageLog.add_combat("[%s] %s → %s" % \
		[skill_name, _char_name(character), _char_name(target)])


func _spawn_projectile(target: Character, raw_damage: int, is_magic: bool = false) -> void:
	if map_node == null:
		return
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)
	proj.setup(character.position, target.position, true, target, raw_damage, 1.0,
			character, is_magic)


func _execute_heal(target: Character, slot_data: Dictionary) -> void:
	var mp_cost := int(slot_data.get("mp_cost", 0))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	var heal_mult  := float(slot_data.get("heal_mult", 0.3))
	var heal_amount := maxi(1, int(float(character.power) * heal_mult))
	character.face_toward(target.grid_pos)
	# キャスト側エフェクト（外広がり・白金）
	_spawn_heal_effect(character.position, "cast")
	var skill_name := str(slot_data.get("name", "回復"))
	# アンデッド特効：回復量をダメージとして適用
	if not target.is_friendly and target.character_data != null and target.character_data.is_undead:
		target.take_damage(heal_amount, 1.0, character, true)
		_spawn_heal_effect(target.position, "hit")
		MessageLog.add_combat("[%s] %s → %s %d DMG（アンデッド特効）" % \
			[skill_name, _char_name(character), _char_name(target), heal_amount])
		return
	# 通常回復（heal() 内で HEAL SE 再生）
	target.heal(heal_amount)
	# ターゲット側エフェクト（内縮み・緑）
	_spawn_heal_effect(target.position, "hit")
	MessageLog.add_combat("[%s] %s → %s +%d HP" % \
		[skill_name, _char_name(character), _char_name(target), heal_amount])
	# 未加入 NPC への回復：has_been_healed フラグ更新用シグナルを発火
	# （パーティーメンバーでない友好キャラ = 未加入NPC）
	if target.is_friendly and not _party_sorted_members.has(target):
		healed_npc_member.emit(target)


func _execute_buff(target: Character, slot_data: Dictionary) -> void:
	var mp_cost := int(slot_data.get("mp_cost", 0))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	character.face_toward(target.grid_pos)
	target.apply_defense_buff()
	SoundManager.play(SoundManager.HEAL)
	_spawn_heal_effect(character.position, "cast")
	_spawn_heal_effect(target.position, "hit")
	var skill_name := str(slot_data.get("name", "防御バフ"))
	MessageLog.add_combat("[%s] %s → %s" % \
		[skill_name, _char_name(character), _char_name(target)])


func _spawn_heal_effect(pos: Vector2, eff_mode: String) -> void:
	if map_node == null:
		return
	var effect := HealEffect.new()
	effect.mode     = eff_mode
	effect.position = pos
	map_node.add_child(effect)


func _char_name(c: Character) -> String:
	if c.character_data != null and not c.character_data.character_name.is_empty():
		return c.character_data.character_name
	return str(c.name)


# --------------------------------------------------------------------------
# V スロット特殊攻撃
# --------------------------------------------------------------------------

## V スロットを使用するための MP/SP リソースが足りているかチェック
func _has_v_slot_resources() -> bool:
	if character == null:
		return false
	var mp_cost := int(_slot_v.get("mp_cost", 0))
	var sp_cost := int(_slot_v.get("sp_cost", 0))
	if mp_cost > 0 and character.mp < mp_cost:
		return false
	if sp_cost > 0 and character.sp < sp_cost:
		return false
	return true


## V スロットクールダウンを開始し ConsumableBar を更新する
func _start_v_cooldown() -> void:
	_v_slot_cooldown = V_SLOT_COOLDOWN
	if consumable_bar != null:
		consumable_bar.v_slot_cooldown = _v_slot_cooldown
		consumable_bar.refresh()


## インスタント V アクションを実行する（クールダウン開始後に各メソッドを呼ぶ）
func _execute_v_instant(action: String) -> void:
	_start_v_cooldown()
	match action:
		"sliding":      _execute_sliding()
		"whirlwind":    _execute_whirlwind()
		"rush":         _execute_rush()
		"flame_circle": _execute_flame_circle()


## 斥候：スライディング（3マスダッシュ・移動中無敵）
func _execute_sliding() -> void:
	var sp_cost := int(_slot_v.get("sp_cost", 20))
	if sp_cost > 0:
		character.use_sp(sp_cost)
	var dir      := Character.dir_to_vec(character.facing)
	var step_dur := 0.12 / GlobalConstants.game_speed
	character.is_sliding = true
	is_blocked = true
	for _i: int in range(3):
		if not is_instance_valid(character):
			break
		var next_pos := character.grid_pos + Vector2i(dir)
		# 壁・障害物で止まる（キャラクターは通り抜け）
		if map_data == null or not map_data.is_walkable_for(next_pos, character.is_flying):
			break
		character.move_to(next_pos, step_dur)
		await get_tree().create_timer(step_dur + 0.02).timeout
	if is_instance_valid(character):
		character.is_sliding = false
	is_blocked = false
	SoundManager.play(SoundManager.MELEE_DAGGER)
	if is_instance_valid(character):
		MessageLog.add_combat("[スライディング] %s が突進！" % _char_name(character))


## 斧戦士：振り回し（周囲8マスの敵全員にダメージ）
func _execute_whirlwind() -> void:
	var sp_cost  := int(_slot_v.get("sp_cost", 15))
	if sp_cost > 0:
		character.use_sp(sp_cost)
	var dmg_mult: float  = float(_slot_v.get("damage_mult", 1.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)
	var raw_damage := int(float(character.power) * dmg_mult * type_mult)
	character.is_attacking = true
	var hit_count := 0
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var check_pos := character.grid_pos + Vector2i(dx, dy)
			for ch: Character in blocking_characters:
				if not is_instance_valid(ch) or ch.is_friendly or ch.hp <= 0:
					continue
				if check_pos in ch.get_occupied_tiles():
					ch.take_damage(raw_damage, 1.0, character, false)
					hit_count += 1
					break
	SoundManager.play_attack(character)
	await get_tree().create_timer(0.5 / GlobalConstants.game_speed).timeout
	if is_instance_valid(character):
		character.is_attacking = false
	if hit_count > 0:
		MessageLog.add_combat("[振り回し] %s が周囲 %d 体を攻撃！" % [_char_name(character), hit_count])
	else:
		MessageLog.add_combat("[振り回し] %s が振り回した！（空振り）" % _char_name(character))


## 剣士：突進斬り（向いている方向に最大2マス前進、経路上の敵にダメージ）
func _execute_rush() -> void:
	var sp_cost    := int(_slot_v.get("sp_cost", 15))
	if sp_cost > 0:
		character.use_sp(sp_cost)
	var dmg_mult: float  = float(_slot_v.get("damage_mult", 1.2))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)
	var raw_damage := int(float(character.power) * dmg_mult * type_mult)
	var dir        := Character.dir_to_vec(character.facing)
	var step_dur   := 0.15 / GlobalConstants.game_speed
	character.is_attacking = true
	is_blocked = true
	var hit_count := 0
	for _step: int in range(2):
		if not is_instance_valid(character):
			break
		var next_pos := character.grid_pos + Vector2i(dir)
		if map_data == null or not map_data.is_walkable_for(next_pos, false):
			break
		# 経路上の敵にダメージ
		var enemy_here := _find_character_at(next_pos)
		if enemy_here != null and not enemy_here.is_friendly:
			enemy_here.take_damage(raw_damage, 1.0, character, false)
			SoundManager.play_attack(character)
			hit_count += 1
		character.move_to(next_pos, step_dur)
		await get_tree().create_timer(step_dur + 0.02).timeout
	if is_instance_valid(character):
		character.is_attacking = false
	is_blocked = false
	if hit_count > 0:
		MessageLog.add_combat("[突進斬り] %s が %d 体を攻撃！" % [_char_name(character), hit_count])
	else:
		MessageLog.add_combat("[突進斬り] %s が突進！" % _char_name(character))


## 弓使い：ヘッドショット（即死耐性なし→即死、あり→×3ダメージ）
## ターゲット選択モード経由で呼ばれる
func _execute_headshot(target: Character, slot_data: Dictionary) -> void:
	var sp_cost := int(slot_data.get("sp_cost", 25))
	if sp_cost > 0:
		character.use_sp(sp_cost)
	character.face_toward(target.grid_pos)
	SoundManager.play(SoundManager.ARROW_SHOOT)
	var is_immune: bool = false
	if target.character_data != null:
		is_immune = bool(target.character_data.instant_death_immune)
	if is_immune:
		var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
		var raw_damage := int(float(character.power) * 3.0 * type_mult)
		_spawn_projectile(target, raw_damage, false)
		MessageLog.add_combat("[ヘッドショット] %s → %s ×3ダメージ" % \
				[_char_name(character), _char_name(target)])
	else:
		_spawn_projectile(target, 99999, false)
		MessageLog.add_combat("[ヘッドショット] %s → %s 即死！" % \
				[_char_name(character), _char_name(target)])


## 魔法使い(火)：炎陣（自分を中心に半径3マスの炎ゾーンを設置・2.5秒間継続ダメージ）
func _execute_flame_circle() -> void:
	var mp_cost     := int(_slot_v.get("mp_cost", 20))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	var dmg_mult: float  = float(_slot_v.get("damage_mult", 0.8))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("magic", 1.0)
	var damage      := maxi(1, int(float(character.power) * dmg_mult * type_mult))
	var radius      := int(_slot_v.get("range", 3))
	var duration    := float(_slot_v.get("duration", 2.5))
	var tick_ivl    := float(_slot_v.get("tick_interval", 0.5))
	if map_node == null:
		return
	var flame := FlameCircle.new()
	flame.z_index = 1
	map_node.add_child(flame)
	flame.setup(character.position, character.grid_pos, radius, damage,
			duration, tick_ivl, character, blocking_characters)
	SoundManager.play(SoundManager.FLAME_SHOOT)
	MessageLog.add_combat("[炎陣] %s が炎を設置！（%d秒間）" % [_char_name(character), int(duration)])


## 指定グリッド座標にいる最初のキャラクターを返す（なければ null）
func _find_character_at(pos: Vector2i) -> Character:
	for ch: Character in blocking_characters:
		if not is_instance_valid(ch):
			continue
		if pos in ch.get_occupied_tiles():
			return ch
	return null


# --------------------------------------------------------------------------
# 移動
# --------------------------------------------------------------------------

func _get_input_direction() -> Vector2i:
	if Input.is_action_pressed("ui_right"): return Vector2i(1, 0)
	if Input.is_action_pressed("ui_left"):  return Vector2i(-1, 0)
	if Input.is_action_pressed("ui_down"):  return Vector2i(0, 1)
	if Input.is_action_pressed("ui_up"):    return Vector2i(0, -1)
	return Vector2i.ZERO


## 方向ベクトル→ Direction（face_toward と同じロジック）
func _compute_facing_for(dir: Vector2i) -> Character.Direction:
	if abs(dir.x) >= abs(dir.y):
		return Character.Direction.RIGHT if dir.x > 0 else Character.Direction.LEFT
	else:
		return Character.Direction.DOWN if dir.y > 0 else Character.Direction.UP


func _try_move(dir: Vector2i) -> void:
	var new_pos := character.grid_pos + dir
	# ガード中は向き固定
	if not character.is_guarding:
		var target_facing := _compute_facing_for(new_pos - character.grid_pos)
		if target_facing != character.facing:
			# 向きが異なる → まず回転だけ行い移動しない
			# 回転完了時にキーが押し続けられていれば _pending_move_dir から移動を再試行する
			_is_turning = true
			_turn_timer = TURN_DELAY / GlobalConstants.game_speed
			_pending_move_dir = dir
			character.start_turn_animation(target_facing, _turn_timer, new_pos - character.grid_pos)
			return
	# 向きが一致している（またはガード中）→ 直接移動
	if _can_move_to(new_pos):
		# ガード中は移動速度50%（duration を2倍にする）
		var duration := MOVE_INTERVAL / GlobalConstants.game_speed
		if character.is_guarding:
			duration *= 2.0
		character.move_to(new_pos, duration)
	# 移動できない場合（ガード中 or 向き一致で壁など）は何もしない
	# NPC との会話は Aボタン押下で起動（バンプ検出は廃止）


## マンハッタン距離1の未加入NPCキャラクターを返す（いなければ null）
## blocking_characters に残っている is_friendly キャラ＝未加入NPC
func _find_adjacent_npc() -> Character:
	if character == null:
		return null
	for blocker: Character in blocking_characters:
		if not is_instance_valid(blocker):
			continue
		if blocker.current_floor != character.current_floor:
			continue
		if not blocker.is_friendly:
			continue
		var d := blocker.grid_pos - character.grid_pos
		if abs(d.x) + abs(d.y) == 1:
			return blocker
	return null


## 移動可否を判定する（WALL・範囲外・同レイヤーキャラクター占有は不可）
func _can_move_to(pos: Vector2i) -> bool:
	if map_data != null:
		if not map_data.is_walkable_for(pos, character.is_flying):
			return false
	else:
		if not (pos.x >= 0 and pos.x < MapData.MAP_WIDTH \
				and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT):
			return false
	for blocker: Character in blocking_characters:
		if not is_instance_valid(blocker):
			continue
		if blocker.current_floor != character.current_floor:
			continue
		if blocker.is_flying != character.is_flying:
			continue
		if pos == blocker.grid_pos:
			return false
	return true


# --------------------------------------------------------------------------
# アイテム選択 UI（X ボタン短押し）
# --------------------------------------------------------------------------

## ITEM_SELECT フェーズへ移行する（インベントリが空なら何もしない）
func _enter_item_select() -> void:
	if character == null or character.character_data == null:
		return
	var inv := character.character_data.inventory
	if inv.is_empty():
		return
	_item_ui_inv = inv.duplicate()  # 生スナップショット

	# 表示用リストを構築：同種の消耗品はグループ化、装備品は1個ずつ
	# 装備スロットに入っているアイテムは除外（未装備品のみ表示）
	var cd := character.character_data
	_item_ui_display.clear()
	var seen_consumable: Dictionary = {}  # item_type -> display_index
	for i: int in range(_item_ui_inv.size()):
		var item  := _item_ui_inv[i] as Dictionary
		if is_same(item, cd.equipped_weapon) or is_same(item, cd.equipped_armor) \
				or is_same(item, cd.equipped_shield):
			continue
		var cat   := item.get("category", "") as String
		var itype := item.get("item_type", "unknown") as String
		if cat == "consumable" and seen_consumable.has(itype):
			# 既存グループのカウントを増やすだけ
			var di := seen_consumable[itype] as int
			(_item_ui_display[di] as Dictionary)["count"] = \
				int((_item_ui_display[di] as Dictionary)["count"]) + 1
		else:
			# 画像パス解決（item["image"] → assets/images/items/{type}.png へフォールバック）
			var img := item.get("image", "") as String
			if img.is_empty():
				img = "assets/images/items/" + itype + ".png"
			var entry := {
				"item":      item,
				"count":     1,
				"inv_index": i,
				"image":     img,
				"item_name": item.get("item_name", itype) as String,
				"item_type": itype,
				"category":  cat,
			}
			_item_ui_display.append(entry)
			if cat == "consumable":
				seen_consumable[itype] = _item_ui_display.size() - 1

	if _item_ui_display.is_empty():
		return
	_last_item_index = clampi(_last_item_index, 0, _item_ui_display.size() - 1)
	_item_ui_phase = _ItemUIPhase.ITEM_SELECT
	_cycle_direction = 0
	if consumable_bar != null:
		consumable_bar.item_list  = _item_ui_display
		consumable_bar.item_index = _last_item_index
		consumable_bar.display_mode = GlobalConstants.ConsumableDisplayMode.ITEM_SELECT
		consumable_bar.refresh()


## アイテム UI の各フェーズを毎フレーム処理する
func _process_item_ui() -> void:
	match _item_ui_phase:
		_ItemUIPhase.ITEM_SELECT:
			_process_item_select()
		_ItemUIPhase.ACTION_SELECT:
			_process_action_select()
		_ItemUIPhase.TRANSFER_SELECT:
			_process_transfer_select()


## ITEM_SELECT フェーズの入力処理
func _process_item_select() -> void:
	if _item_ui_display.is_empty():
		_exit_item_ui()
		return
	var n := _item_ui_display.size()

	# LB/RB（_input で捕捉）または矢印キーでアイテム循環
	if _cycle_direction != 0:
		_last_item_index = (_last_item_index + _cycle_direction + n) % n
		_cycle_direction = 0
		_sync_item_select_bar()
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
		_last_item_index = (_last_item_index + 1) % n
		_sync_item_select_bar()
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
		_last_item_index = (_last_item_index - 1 + n) % n
		_sync_item_select_bar()

	# Z/A または X（use_item）で決定 → ACTION_SELECT へ
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("use_item"):
		_enter_action_select()
		return

	# B（menu_back）でキャンセル
	if Input.is_action_just_pressed("menu_back"):
		_exit_item_ui()


## ConsumableBar の ITEM_SELECT 表示を現在の _last_item_index で更新
func _sync_item_select_bar() -> void:
	if consumable_bar == null:
		return
	consumable_bar.item_index = _last_item_index
	consumable_bar.refresh()


## 選択中アイテムに対して実行できるアクションリストを構築して ACTION_SELECT へ移行
func _enter_action_select() -> void:
	if _last_item_index >= _item_ui_display.size():
		_exit_item_ui()
		return
	var entry := _item_ui_display[_last_item_index] as Dictionary
	var item  := entry["item"] as Dictionary
	_item_action_list.clear()
	_item_action_cursor = 0

	var cat := item.get("category", "") as String
	# 使用する（消耗品で効果がある場合）
	if cat == "consumable" and _is_consumable_usable_by_char(item):
		_item_action_list.append("使用する")
	# 装備する
	if _can_equip_item(item):
		_item_action_list.append("装備する")
	# 渡す（リーダーのみ・未装備アイテム）
	if character != null and character.is_leader \
			and not _is_item_equipped(item) \
			and _party_sorted_members.size() > 1:
		_item_action_list.append("渡す")
	_item_action_list.append("キャンセル")

	_item_ui_phase = _ItemUIPhase.ACTION_SELECT
	if consumable_bar != null:
		consumable_bar.action_list  = _item_action_list
		consumable_bar.action_index = 0
		consumable_bar.display_mode = GlobalConstants.ConsumableDisplayMode.ACTION_SELECT
		consumable_bar.refresh()


## ACTION_SELECT フェーズの入力処理
func _process_action_select() -> void:
	# 上下でアクション選択
	if _cycle_direction != 0:
		_item_action_cursor = (_item_action_cursor + _cycle_direction \
			+ _item_action_list.size()) % _item_action_list.size()
		_cycle_direction = 0
		if consumable_bar != null:
			consumable_bar.action_index = _item_action_cursor
			consumable_bar.refresh()
	elif Input.is_action_just_pressed("ui_down"):
		_item_action_cursor = (_item_action_cursor + 1) % _item_action_list.size()
		if consumable_bar != null:
			consumable_bar.action_index = _item_action_cursor
			consumable_bar.refresh()
	elif Input.is_action_just_pressed("ui_up"):
		_item_action_cursor = (_item_action_cursor - 1 + _item_action_list.size()) \
			% _item_action_list.size()
		if consumable_bar != null:
			consumable_bar.action_index = _item_action_cursor
			consumable_bar.refresh()

	# Z/A または X で決定
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("use_item"):
		var action := _item_action_list[_item_action_cursor]
		if action == "キャンセル":
			# ITEM_SELECT に戻る
			_item_ui_phase = _ItemUIPhase.ITEM_SELECT
			if consumable_bar != null:
				consumable_bar.display_mode = GlobalConstants.ConsumableDisplayMode.ITEM_SELECT
				consumable_bar.item_index   = _last_item_index
				consumable_bar.refresh()
		elif action == "渡す":
			_enter_transfer_select()
		else:
			_execute_item_action(action)
		return

	# B でアイテム選択に戻る
	if Input.is_action_just_pressed("menu_back"):
		_item_ui_phase = _ItemUIPhase.ITEM_SELECT
		if consumable_bar != null:
			consumable_bar.display_mode = GlobalConstants.ConsumableDisplayMode.ITEM_SELECT
			consumable_bar.item_index   = _last_item_index
			consumable_bar.refresh()


## TRANSFER_SELECT フェーズへ移行する（リーダーが他メンバーにアイテムを渡す）
func _enter_transfer_select() -> void:
	var targets: Array[String] = []
	for ch: Character in _party_sorted_members:
		if is_instance_valid(ch) and ch != character:
			var nm := ch.character_data.character_name if ch.character_data != null else ""
			if nm.is_empty():
				nm = str(ch.name)
			targets.append(nm)
	if targets.is_empty():
		_exit_item_ui()
		return
	_transfer_cursor = 0
	_item_ui_phase = _ItemUIPhase.TRANSFER_SELECT
	if consumable_bar != null:
		consumable_bar.transfer_list  = targets
		consumable_bar.transfer_index = 0
		consumable_bar.display_mode   = GlobalConstants.ConsumableDisplayMode.TRANSFER_SELECT
		consumable_bar.refresh()


## TRANSFER_SELECT フェーズの入力処理
func _process_transfer_select() -> void:
	var count := consumable_bar.transfer_list.size() if consumable_bar != null else 0
	if count == 0:
		_exit_item_ui()
		return

	if _cycle_direction != 0:
		_transfer_cursor = (_transfer_cursor + _cycle_direction + count) % count
		_cycle_direction = 0
		if consumable_bar != null:
			consumable_bar.transfer_index = _transfer_cursor
			consumable_bar.refresh()
	elif Input.is_action_just_pressed("ui_down"):
		_transfer_cursor = (_transfer_cursor + 1) % count
		if consumable_bar != null:
			consumable_bar.transfer_index = _transfer_cursor
			consumable_bar.refresh()
	elif Input.is_action_just_pressed("ui_up"):
		_transfer_cursor = (_transfer_cursor - 1 + count) % count
		if consumable_bar != null:
			consumable_bar.transfer_index = _transfer_cursor
			consumable_bar.refresh()

	# Z/A または X で渡す確定
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("use_item"):
		_execute_transfer(_transfer_cursor)
		return

	# B でアクション選択に戻る
	if Input.is_action_just_pressed("menu_back"):
		_item_ui_phase = _ItemUIPhase.ACTION_SELECT
		if consumable_bar != null:
			consumable_bar.display_mode = GlobalConstants.ConsumableDisplayMode.ACTION_SELECT
			consumable_bar.refresh()


## アイテムアクションを実行する（使用・装備）
func _execute_item_action(action: String) -> void:
	if _last_item_index >= _item_ui_display.size():
		_exit_item_ui()
		return
	var item := (_item_ui_display[_last_item_index] as Dictionary)["item"] as Dictionary

	if action == "使用する":
		_use_item_from_ui(item)
	elif action == "装備する":
		_equip_item_from_ui(item)

	_exit_item_ui()


## アイテムを使用する（消耗品）
func _use_item_from_ui(item: Dictionary) -> void:
	if character == null or character.character_data == null:
		return
	var cd     := character.character_data
	var effect := item.get("effect", {}) as Dictionary
	var heal_hp    := int(effect.get("heal_hp",    0))
	var restore_mp := int(effect.get("restore_mp", 0))
	var restore_sp := int(effect.get("restore_sp", 0))
	if heal_hp == 0 and restore_mp == 0 and restore_sp == 0:
		return

	var used_type := item.get("item_type", "") as String
	character.use_consumable(item)

	# inventory から該当アイテムを1個削除
	var inv := cd.inventory
	for i: int in range(inv.size()):
		var entry := inv[i] as Dictionary
		if entry.get("item_type", "") == used_type \
				and entry.get("category", "") == "consumable":
			inv.remove_at(i)
			break

	var item_name := item.get("item_name", "アイテム") as String
	var char_name := cd.character_name if not cd.character_name.is_empty() else String(character.name)
	MessageLog.add_system("%s は %s を使った！" % [char_name, item_name])
	if consumable_bar != null:
		consumable_bar.refresh()


## アイテムを装備する
func _equip_item_from_ui(item: Dictionary) -> void:
	if character == null or character.character_data == null:
		return
	var cd    := character.character_data
	var itype := item.get("item_type", "") as String
	if itype in ["sword", "axe", "bow", "dagger", "staff"]:
		cd.equipped_weapon = item
	elif itype in ["armor_plate", "armor_cloth", "armor_robe"]:
		cd.equipped_armor = item
	elif itype == "shield":
		cd.equipped_shield = item
	else:
		return
	character.refresh_stats_from_equipment()
	var item_name := item.get("item_name", "アイテム") as String
	var char_name := cd.character_name if not cd.character_name.is_empty() else String(character.name)
	MessageLog.add_system("%s は %s を装備した！" % [char_name, item_name])


## アイテムを別キャラに渡す（transfer_idx: transfer_list のインデックス）
func _execute_transfer(transfer_idx: int) -> void:
	if character == null or character.character_data == null:
		return
	if _last_item_index >= _item_ui_display.size():
		_exit_item_ui()
		return
	var item := (_item_ui_display[_last_item_index] as Dictionary)["item"] as Dictionary

	# transfer_list のインデックス → _party_sorted_members の対応キャラを特定
	var others: Array[Character] = []
	for ch: Character in _party_sorted_members:
		if is_instance_valid(ch) and ch != character:
			others.append(ch)
	if transfer_idx >= others.size():
		_exit_item_ui()
		return
	var target_ch := others[transfer_idx]
	if not is_instance_valid(target_ch) or target_ch.character_data == null:
		_exit_item_ui()
		return

	# 渡す元の inventory からアイテムを1個削除
	var src_inv := character.character_data.inventory
	for i: int in range(src_inv.size()):
		if src_inv[i] == item:
			src_inv.remove_at(i)
			break

	# 渡す先に追加
	target_ch.character_data.inventory.append(item)

	var item_name   := item.get("item_name", "アイテム") as String
	var src_name    := character.character_data.character_name
	var target_name := target_ch.character_data.character_name
	MessageLog.add_system("%s は %s を %s に渡した" % [src_name, item_name, target_name])

	_exit_item_ui()


## アイテム選択 UI を閉じて NORMAL に戻す
func _exit_item_ui() -> void:
	_item_ui_phase = _ItemUIPhase.NONE
	_item_action_list.clear()
	_item_ui_inv.clear()
	_item_ui_display.clear()
	_cycle_direction = 0
	if consumable_bar != null:
		consumable_bar.display_mode = GlobalConstants.ConsumableDisplayMode.NORMAL
		consumable_bar.item_list    = []
		consumable_bar.action_list.clear()
		consumable_bar.transfer_list.clear()
		consumable_bar.refresh()


## アイテムがこのキャラのクラスで装備可能かチェック
func _can_equip_item(item: Dictionary) -> bool:
	if character == null or character.character_data == null:
		return false
	var class_id := character.character_data.class_id
	var allowed: Array = CLASS_EQUIP_TYPES.get(class_id, []) as Array
	var itype    := item.get("item_type", "") as String
	return allowed.has(itype)


## アイテムが現在装備中かどうか（value comparison）
func _is_item_equipped(item: Dictionary) -> bool:
	if character == null or character.character_data == null:
		return false
	var cd := character.character_data
	if not cd.equipped_weapon.is_empty() and cd.equipped_weapon == item:
		return true
	if not cd.equipped_armor.is_empty() and cd.equipped_armor == item:
		return true
	if not cd.equipped_shield.is_empty() and cd.equipped_shield == item:
		return true
	return false


# --------------------------------------------------------------------------
# キャラクター切り替え
# --------------------------------------------------------------------------

## キャラクター切り替え（LB/RB 通常時）
## _party_sorted_members の現在キャラの隣を選んで switch_char_requested を発火する
func _switch_character(dir: int) -> void:
	if _party_sorted_members.is_empty() or character == null:
		return
	# プレイヤーが自パーティーのリーダーのときのみ切り替え可
	# （NPC パーティーに合流してリーダーを譲った場合は無効）
	if not player_is_leader:
		return
	var idx := _party_sorted_members.find(character)
	if idx < 0:
		idx = 0
	var total := _party_sorted_members.size()
	if total <= 1:
		return
	var next_idx := (idx + dir + total) % total
	var next_char := _party_sorted_members[next_idx]
	if is_instance_valid(next_char) and next_char != character:
		switch_char_requested.emit(next_char)


## このキャラクターがアイテムを使用できるか判定する
## max_mp==0のキャラにMPポーションは不要・max_sp==0のキャラにSPポーションは不要
func _is_consumable_usable_by_char(item: Dictionary) -> bool:
	if character == null or character.character_data == null:
		return true
	var effect     := item.get("effect", {}) as Dictionary
	var restore_mp := int(effect.get("restore_mp", 0))
	var restore_sp := int(effect.get("restore_sp", 0))
	if restore_mp > 0 and character.max_mp == 0:
		return false
	if restore_sp > 0 and character.max_sp == 0:
		return false
	return true



# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

## クラス定義 JSON を読み込む
func _read_class_json(class_id: String) -> Dictionary:
	var path := CLASS_JSON_DIR + class_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}
