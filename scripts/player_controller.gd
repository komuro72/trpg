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
var map_node: Node2D = null

## 会話中など入力を一時的に無効化するフラグ
var is_blocked: bool = false

## 移動先に友好的キャラクターがいたときに発火するシグナル（会話トリガー用）
signal npc_bumped(npc_member: Character)

## パーティーメンバー切り替えリクエストシグナル（game_map が処理）
signal switch_char_requested(new_char: Character)

## 移動アニメーションの1タイルあたりの時間・基準値（秒）
## この定数が移動速度を決める。game_speed で割った値が実効値になる
## 【旧方式との違い】タイマーによる移動間隔制御を廃止し、アニメーション完了を
## 次移動の gate として使う先行入力バッファ方式に変更（Phase 9-1）
const MOVE_INTERVAL: float = 0.30
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

## パーティーメンバーリスト（game_map から設定。LB/RBキャラ切り替えに使用）
var _party_sorted_members: Array[Character] = []

## 消耗品選択モード（C/Xホールド中）
var _consumable_select_mode: bool = false

## V スロットクールダウン（秒）
const V_SLOT_COOLDOWN: float = 2.0
var _v_slot_cooldown: float = 0.0


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

	# 消耗品選択モード中：LB/RBで消耗品循環
	if _consumable_select_mode:
		if event.is_action_pressed("switch_char_next", false):
			_cycle_consumable_select(1)
		elif event.is_action_pressed("switch_char_prev", false):
			_cycle_consumable_select(-1)
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

func _process(delta: float) -> void:
	# V スロットクールダウンのカウントダウン（is_blocked 中も進める）
	if _v_slot_cooldown > 0.0:
		_v_slot_cooldown = maxf(0.0, _v_slot_cooldown - delta)
		if consumable_bar != null:
			consumable_bar.v_slot_cooldown = _v_slot_cooldown
			consumable_bar.refresh()

	if character == null:
		return

	# world_time_running を現在の状態に応じて更新する（is_blocked チェックより前）
	_update_world_time()

	if is_blocked:
		# ブロック中（メニュー等）はガードを解除する
		if character.is_guarding:
			character.is_guarding = false
		# 消耗品選択モードも解除する
		if _consumable_select_mode:
			_exit_consumable_select(false)
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
	# C/X ホールド：消耗品選択モード
	# 攻撃押下中は無効（_mode が PRE_DELAY/TARGETING/POST_DELAY に移行するため、ここには来ない）
	var c_held := Input.is_action_pressed("use_item")
	if c_held and not _consumable_select_mode:
		_enter_consumable_select()
	elif not c_held and _consumable_select_mode:
		_exit_consumable_select(true)  # リリース時に使用を試みる

	# 消耗品選択モード中はその他のアクションを抑制（V/Y・移動はブロックしない）
	if _consumable_select_mode:
		_process_guard_and_move(_delta)
		return

	# 特殊スキル（V/Y）
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

	# 攻撃キー押下で PRE_DELAY へ（ガード中は先に解除）
	if Input.is_action_just_pressed("attack"):
		_using_v_slot = false
		if character.is_guarding:
			character.is_guarding = false
		_move_buffer = Vector2i.ZERO
		_enter_pre_delay()
		return

	_process_guard_and_move(_delta)


## ガード入力・移動入力を処理する（通常モード・消耗品選択モード共通）
func _process_guard_and_move(_delta: float) -> void:
	# ガード（X/B ホールド）。消耗品選択モード中は C/X を use_item が使うため競合しない
	var want_guard := Input.is_action_pressed("menu_back")
	if character.is_guarding != want_guard:
		character.is_guarding = want_guard

	var dir := _get_input_direction()

	# アニメーション中は新たな移動をブロック
	# キーが押されていればバッファに上書き記録、離されたらバッファをクリア
	if character.is_moving():
		_move_buffer = dir  # ZERO でも上書き（離したらキャンセル）
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

	# アニメーション完了後：バッファ入力を優先し、次いで現在の入力を使用
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
	# 時間停止中でも死亡による対象消失を検出するためリフレッシュ
	_refresh_targets()

	# X/B でキャンセル（ノーコスト）
	if Input.is_action_just_pressed("menu_back"):
		_exit_targeting()
		return

	# Z/A（または V 使用中は special_skill）で確定
	var confirm_pressed := false
	if _using_v_slot:
		confirm_pressed = Input.is_action_just_pressed("special_skill")
	else:
		confirm_pressed = Input.is_action_just_pressed("attack")
	if confirm_pressed:
		if _target_index < _valid_targets.size():
			_confirm_target()
		else:
			_exit_targeting()  # キャンセル枠で確定 = キャンセル
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
	_post_delay_remaining -= delta
	if _post_delay_remaining <= 0.0:
		_post_delay_remaining = 0.0
		_mode = Mode.NORMAL
		if is_instance_valid(character):
			character.is_attacking = false


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

	_mode                = Mode.PRE_DELAY
	_move_buffer         = Vector2i.ZERO
	_pre_delay_remaining = float(sd.get("pre_delay", 0.0))
	character.is_targeting_mode = true

	# カーソルをあらかじめ生成してターゲット候補を表示
	_valid_targets = _get_sorted_targets()
	_target_index  = 0
	if map_node != null:
		_cursor = TargetCursor.new()
		_cursor.z_index = 3
		map_node.add_child(_cursor)
	_update_cursor()


## PRE_DELAY 消化後に TARGETING モードへ移行する
func _start_targeting() -> void:
	_mode = Mode.TARGETING
	_refresh_targets()
	_update_cursor()


func _exit_targeting() -> void:
	_mode = Mode.NORMAL
	_using_v_slot = false
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
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
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	_valid_targets.clear()
	_target_index = 0
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null
	character.is_targeting_mode = false

	var action: String = str(sd.get("action", "melee"))
	var was_v := _using_v_slot
	_using_v_slot = false

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
	# キャンセル状態かどうかを先に記録する
	# （_target_index == size のとき prev_target が null になり、リセットされていたバグの修正）
	var was_cancel := _target_index >= _valid_targets.size()
	var prev_target: Character = null
	if not was_cancel:
		prev_target = _valid_targets[_target_index]

	_valid_targets = _get_sorted_targets()

	if _valid_targets.is_empty():
		_target_index = 0  # キャンセル選択状態（size=0 なので 0 >= size は true）
		_update_cursor()
		return

	# キャンセル状態だった場合はキャンセルを維持（0 にリセットしない）
	if was_cancel:
		_target_index = _valid_targets.size()
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
	var total := _valid_targets.size() + 1  # 末尾がキャンセルスロット
	_target_index = (_target_index + dir + total) % total
	_update_cursor()


func _update_cursor() -> void:
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	if _cursor == null:
		return
	if _target_index >= _valid_targets.size():
		_cursor.visible = false  # キャンセル選択中は非表示
	else:
		_cursor.visible = true
		var tgt := _valid_targets[_target_index]
		_cursor.position = tgt.position
		tgt.is_targeted  = true


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
	if _mode == Mode.PRE_DELAY or _mode == Mode.POST_DELAY:
		GlobalConstants.world_time_running = true
		return
	if _mode == Mode.TARGETING:
		GlobalConstants.world_time_running = false
		return
	# NORMAL モード：キャラの状態で判定
	if character != null:
		if character.is_moving() or character.is_guarding \
				or character.is_attacking or character.is_sliding:
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
			# 射程内の is_friendly な味方（自分を除く）が対象
			if not c.is_friendly or c == character:
				continue
			var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
			if dist <= float(range_val):
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
			if dx + dy <= range_val:
				result.append(c)
		elif action == "ranged" or action == "ranged_area" or action == "water_stun" \
				or action == "headshot":
			var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
			if dist <= float(range_val):
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
	character.face_toward(target.grid_pos)
	var raw_damage := int(float(character.attack_power) * dmg_mult)
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
	character.face_toward(target.grid_pos)
	var is_magic   := (slot_data.get("type", "physical") as String) == "magic"
	var base_power := character.magic_power if is_magic else character.attack_power
	var raw_damage := int(float(base_power) * dmg_mult)
	SoundManager.play_attack(character)
	_spawn_projectile(target, raw_damage, is_magic)


func _execute_water_stun(target: Character, slot_data: Dictionary) -> void:
	var mp_cost := int(slot_data.get("mp_cost", 0))
	if mp_cost > 0:
		character.use_mp(mp_cost)
	var dmg_mult      := float(slot_data.get("damage_mult", 0.5))
	var stun_duration := float(slot_data.get("stun_duration", 3.0))
	var raw_damage    := int(float(character.magic_power) * dmg_mult)
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
	var heal_amount := maxi(1, int(float(character.magic_power) * heal_mult))
	character.face_toward(target.grid_pos)
	# キャスト側エフェクト（外広がり・白金）
	_spawn_heal_effect(character.position, "cast")
	# 回復実行（heal() 内で HEAL SE 再生）
	target.heal(heal_amount)
	# ターゲット側エフェクト（内縮み・緑）
	_spawn_heal_effect(target.position, "hit")
	var skill_name := str(slot_data.get("name", "回復"))
	MessageLog.add_combat("[%s] %s → %s +%d HP" % \
		[skill_name, _char_name(character), _char_name(target), heal_amount])


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
# V スロット特殊スキル
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
	var dmg_mult   := float(_slot_v.get("damage_mult", 1.0))
	var raw_damage := int(float(character.attack_power) * dmg_mult)
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
	var dmg_mult   := float(_slot_v.get("damage_mult", 1.2))
	var raw_damage := int(float(character.attack_power) * dmg_mult)
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
		var raw_damage := int(float(character.attack_power) * 3.0)
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
	var dmg_mult    := float(_slot_v.get("damage_mult", 0.8))
	var damage      := maxi(1, int(float(character.magic_power) * dmg_mult))
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


func _try_move(dir: Vector2i) -> void:
	var new_pos := character.grid_pos + dir
	if _can_move_to(new_pos):
		# ガード中は移動速度50%（duration を2倍にする）
		var duration := MOVE_INTERVAL / GlobalConstants.game_speed
		if character.is_guarding:
			duration *= 2.0
		character.move_to(new_pos, duration)
	else:
		# 移動先に友好的キャラクターがいれば npc_bumped を発火する
		for blocker: Character in blocking_characters:
			if not is_instance_valid(blocker):
				continue
			if blocker.current_floor != character.current_floor:
				continue
			if blocker.is_flying != character.is_flying:
				continue
			if new_pos in blocker.get_occupied_tiles() and blocker.is_friendly:
				npc_bumped.emit(blocker)
				break


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
		if pos in blocker.get_occupied_tiles():
			return false
	return true


# --------------------------------------------------------------------------
# 消耗品
# --------------------------------------------------------------------------

## キャラクター切り替え（LB/RB 通常時）
## _party_sorted_members の現在キャラの隣を選んで switch_char_requested を発火する
func _switch_character(dir: int) -> void:
	if _party_sorted_members.is_empty() or character == null:
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


## 消耗品選択モード開始（C/X ホールド時）
## 現在の選択位置を維持したまま選択モードに入る（フォーカスは変わらない）
func _enter_consumable_select() -> void:
	_consumable_select_mode = true
	if character == null or character.character_data == null:
		return
	var cd := character.character_data
	# ConsumableBar を選択モード表示に切り替え（select_index は現在値を渡す）
	if consumable_bar != null:
		consumable_bar.is_selecting = true
		consumable_bar.select_index = cd.selected_consumable_index
		consumable_bar.refresh()


## 消耗品選択モード終了（C/X リリース時）
## do_use=true なら「なし」以外が選択中の場合に使用を試みる
func _exit_consumable_select(do_use: bool) -> void:
	_consumable_select_mode = false
	if do_use and character != null and character.character_data != null:
		var cd := character.character_data
		# selected_consumable_index >= 0 なら使用（-1=「なし」は不使用）
		if cd.selected_consumable_index >= 0:
			_use_selected_consumable()
	# ConsumableBar を通常表示に戻す
	if consumable_bar != null:
		consumable_bar.is_selecting = false
		consumable_bar.select_index = -1
		consumable_bar.refresh()


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


## 消耗品選択モード中の LB/RB によるグループ循環
## -1（なし）→ 使用可能グループ0 → … → 最後 → -1（なし） の順で循環
## 使用できない消耗品種別（MPポーション/SPポーション）はスキップする
func _cycle_consumable_select(dir: int) -> void:
	if character == null or character.character_data == null:
		return
	var cd   := character.character_data
	var list := cd.get_consumables()
	if list.is_empty():
		return
	# 使用可能なグループキーリストを構築（使えない種別は除外）
	var group_keys: Array[String] = []
	var seen: Dictionary = {}
	for item_v: Variant in list:
		var item  := item_v as Dictionary
		var itype := item.get("item_type", "") as String
		if not seen.has(itype) and _is_consumable_usable_by_char(item):
			seen[itype] = true
			group_keys.append(itype)
	if group_keys.is_empty():
		return
	var group_count := group_keys.size()
	# 現在のグループインデックス（-1=なし枠）
	var cur_type := ""
	if cd.selected_consumable_index >= 0 and cd.selected_consumable_index < list.size():
		cur_type = (list[cd.selected_consumable_index] as Dictionary).get("item_type", "") as String
	var cur_grp := group_keys.find(cur_type)  # 使用可能グループに見つからなければ -1（なし枠扱い）
	# 循環計算（-1=なし枠 を含めて group_count+1 の循環）
	var total    := group_count + 1
	var grp_idx  := (cur_grp + 1 + dir + total) % total - 1  # -1=なし枠
	if grp_idx < 0:
		# なし枠を選択
		cd.selected_consumable_index = -1
	else:
		var next_type := group_keys[grp_idx]
		for i: int in range(list.size()):
			if (list[i] as Dictionary).get("item_type", "") == next_type:
				cd.selected_consumable_index = i
				break
	if consumable_bar != null:
		consumable_bar.select_index = cd.selected_consumable_index
		consumable_bar.refresh()


## 消耗品スロットをグループ（item_type）単位で循環する（dir: +1=次 / -1=前）
func _cycle_consumable(dir: int) -> void:
	if character == null or character.character_data == null:
		return
	var cd   := character.character_data
	var list := cd.get_consumables()
	if list.is_empty():
		return

	# グループキーリスト（出現順・重複なし）を構築
	var group_keys: Array[String] = []
	var seen: Dictionary = {}
	for item_v: Variant in list:
		var itype := (item_v as Dictionary).get("item_type", "") as String
		if not seen.has(itype):
			seen[itype] = true
			group_keys.append(itype)

	# 現在の選択グループを特定
	var cur_type := ""
	if cd.selected_consumable_index < list.size():
		cur_type = (list[cd.selected_consumable_index] as Dictionary)\
			.get("item_type", "") as String
	var cur_grp := group_keys.find(cur_type)
	if cur_grp < 0:
		cur_grp = 0

	# 次グループへ循環
	var next_grp := (cur_grp + dir + group_keys.size()) % group_keys.size()
	var next_type := group_keys[next_grp]

	# next_type の最初のアイテムのインデックスへセット
	for i: int in range(list.size()):
		if (list[i] as Dictionary).get("item_type", "") == next_type:
			cd.selected_consumable_index = i
			break

	if consumable_bar != null:
		consumable_bar.refresh()


## 選択中の消耗品を使用する
func _use_selected_consumable() -> void:
	if character == null or character.character_data == null:
		return
	var cd   := character.character_data
	var item := cd.get_selected_consumable()
	if item.is_empty():
		return
	var effect: Dictionary = item.get("effect", {}) as Dictionary
	var heal_hp:    int = int(effect.get("heal_hp",    0))
	var restore_mp: int = int(effect.get("restore_mp", 0))
	var restore_sp: int = int(effect.get("restore_sp", 0))
	# 効果のないアイテムは使用しない
	if heal_hp == 0 and restore_mp == 0 and restore_sp == 0:
		return

	var used_type := item.get("item_type", "") as String

	# 使用実行（heal / MP回復・効果音は use_consumable 内）
	character.use_consumable(item)

	# inventory から同グループの先頭1個を削除（remove_at で確実に1個だけ消す）
	var inv := cd.inventory
	for i: int in range(inv.size()):
		var entry := inv[i] as Dictionary
		if entry.get("item_type", "") == used_type \
				and entry.get("category", "") == "consumable":
			inv.remove_at(i)
			break

	# 使用後インデックス: 同グループに残りがあれば維持、なければクランプ
	var remaining := cd.get_consumables()
	var found_same := false
	for i: int in range(remaining.size()):
		if (remaining[i] as Dictionary).get("item_type", "") == used_type:
			cd.selected_consumable_index = i
			found_same = true
			break
	if not found_same:
		cd.selected_consumable_index = \
			clampi(cd.selected_consumable_index, 0, maxi(0, remaining.size() - 1))

	var item_name: String = item.get("item_name", "アイテム") as String
	var char_name: String = cd.character_name if not cd.character_name.is_empty() \
		else String(character.name)
	MessageLog.add_system("%s は %s を使った！" % [char_name, item_name])
	if consumable_bar != null:
		consumable_bar.refresh()


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
