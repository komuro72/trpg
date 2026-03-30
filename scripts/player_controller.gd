class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Phase 4: NORMAL/TARGETING/FIRINGステートマシン・Z/Xキー攻撃スロット・飛翔体対応
## Phase 6-0: クラスJSONのスロット定義を読み込み、クラスごとの攻撃動作に対応
##   - action: "melee" → マンハッタン距離・近接判定
##   - action: "ranged" / "ranged_area" → ユークリッド距離・飛翔体
##   - damage_mult がスロット単位で適用される（背面2倍等の方向補正とは別）
## Phase 6-1: ホールド方式ターゲット選択
##   - 攻撃キーホールド中 = ターゲット選択モード
##   - キーリリース時にターゲットあり→攻撃発動、なし→ノーコストキャンセル
##   - ターゲットソート: 前方±45°を距離順、次いでそれ以外を距離順
##   - ホールド中に射程内の敵リストをリアルタイム更新

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

const MOVE_INTERVAL_INITIAL: float = 0.20
const MOVE_INTERVAL_REPEAT:  float = 0.10
const CLASS_JSON_DIR := "res://assets/master/classes/"

## 前方コーン判定しきい値（cos 45° ≈ 0.707）
const FORWARD_CONE_DOT: float = 0.707

## デフォルトスロット（クラスデータが存在しない場合のフォールバック）
const DEFAULT_SLOT_Z: Dictionary = {
	"name": "近接攻撃", "action": "melee",  "type": "physical",
	"range": 1, "damage_mult": 1.0, "pre_delay": 0.0
}
const DEFAULT_SLOT_X: Dictionary = {
	"name": "遠距離攻撃", "action": "ranged", "type": "physical",
	"range": 5, "damage_mult": 1.0, "pre_delay": 0.0
}

enum Mode       { NORMAL, TARGETING, FIRING }
enum AttackSlot { Z, X }

var _mode:          Mode       = Mode.NORMAL
var _attack_slot:   AttackSlot = AttackSlot.Z
var _valid_targets: Array[Character] = []
var _target_index:  int = 0  # valid_targets.size() = キャンセル選択

var _move_timer:   float = 0.0
var _move_holding: bool  = false
var _cursor: TargetCursor = null

## ホールド開始時からのpre_delayカウントダウン（0以下で発動可能）
var _pre_delay_remaining: float = 0.0

## FIRING ステート用：発動待ちの情報
var _pending_target:    Character  = null
var _pending_slot_data: Dictionary = {}

## クラスJSONから読み込んだスロットデータ
var _slot_z: Dictionary = {}
var _slot_x: Dictionary = {}


func _ready() -> void:
	_load_class_slots()


# --------------------------------------------------------------------------
# クラス別スロット初期化
# --------------------------------------------------------------------------

## character のクラスIDに基づいてスロットデータをロードする
## クラスデータが存在しない場合はデフォルト（近接Z・遠距離X）を使用
func _load_class_slots() -> void:
	_slot_z = DEFAULT_SLOT_Z.duplicate()
	_slot_x = DEFAULT_SLOT_X.duplicate()
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
	var x_data: Variant = slots.get("X")
	if x_data != null and x_data is Dictionary:
		_slot_x = (x_data as Dictionary).duplicate()


func _get_slot(slot: AttackSlot) -> Dictionary:
	match slot:
		AttackSlot.Z: return _slot_z
		AttackSlot.X: return _slot_x
	return DEFAULT_SLOT_Z.duplicate()


# --------------------------------------------------------------------------
# メインループ
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if character == null or is_blocked:
		return

	match _mode:
		Mode.NORMAL:
			_process_normal(delta)
		Mode.TARGETING:
			_process_targeting(delta)
		Mode.FIRING:
			_process_firing(delta)


func _process_normal(delta: float) -> void:
	# 攻撃キーホールドでターゲット選択モードへ
	if Input.is_action_pressed("attack_melee"):
		_enter_targeting(AttackSlot.Z)
		return
	elif Input.is_action_pressed("attack_ranged"):
		_enter_targeting(AttackSlot.X)
		return

	# 移動処理
	_move_timer -= delta
	var dir := _get_input_direction()
	if dir == Vector2i.ZERO:
		_move_holding = false
		_move_timer   = 0.0
		return
	if not _move_holding:
		_try_move(dir)
		_move_holding = true
		_move_timer   = MOVE_INTERVAL_INITIAL
	elif _move_timer <= 0.0:
		_try_move(dir)
		_move_timer = MOVE_INTERVAL_REPEAT


func _process_targeting(delta: float) -> void:
	# ホールド中も pre_delay をカウントダウン
	_pre_delay_remaining -= delta

	# キーリリース検出 → 発動 or キャンセル
	if not _is_slot_held(_attack_slot):
		if _target_index < _valid_targets.size():
			_commit_attack()
		else:
			_exit_targeting()
		return

	# ターゲットリストをリアルタイム更新（敵の移動・死亡に対応）
	_refresh_targets()

	# 循環選択（右/下 = 次、左/上 = 前）
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
		_cycle_target(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
		_cycle_target(-1)


func _process_firing(delta: float) -> void:
	# 残り pre_delay を消化してから発動
	_pre_delay_remaining -= delta
	if _pre_delay_remaining <= 0.0:
		_execute_pending()


# --------------------------------------------------------------------------
# ターゲット選択
# --------------------------------------------------------------------------

func _enter_targeting(slot: AttackSlot) -> void:
	_attack_slot  = slot
	_mode         = Mode.TARGETING
	_move_holding = false
	_move_timer   = 0.0

	# ホールド開始時点から pre_delay カウント開始
	var sd := _get_slot(slot)
	_pre_delay_remaining = float(sd.get("pre_delay", 0.0))

	_valid_targets = _get_sorted_targets(slot)
	_target_index  = 0  # 先頭の敵を自動選択（敵なしならキャンセル選択）
	character.is_targeting_mode = true

	if map_node != null:
		_cursor = TargetCursor.new()
		_cursor.z_index = 3
		map_node.add_child(_cursor)

	_update_cursor()


func _exit_targeting() -> void:
	_mode = Mode.NORMAL
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	_valid_targets.clear()
	_target_index        = 0
	_pre_delay_remaining = 0.0
	character.is_targeting_mode = false
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null


## キーリリース時にターゲットが確定していたら発動（残 pre_delay があれば FIRING へ）
func _commit_attack() -> void:
	_pending_target    = _valid_targets[_target_index]
	_pending_slot_data = _get_slot(_attack_slot)

	# カーソル片付け（is_targeting_mode は FIRING 中も維持）
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	_valid_targets.clear()
	_target_index = 0
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null

	if _pre_delay_remaining <= 0.0:
		_execute_pending()
	else:
		_mode = Mode.FIRING


func _execute_pending() -> void:
	_mode = Mode.NORMAL
	character.is_targeting_mode = false
	_pre_delay_remaining = 0.0

	if not is_instance_valid(_pending_target):
		_pending_target    = null
		_pending_slot_data = {}
		return

	var sd:     Dictionary = _pending_slot_data
	var action: String     = str(sd.get("action", "melee"))

	if action == "melee":
		_execute_melee(_pending_target, sd)
	elif action == "ranged" or action == "ranged_area":
		_execute_ranged(_pending_target, sd)

	_pending_target    = null
	_pending_slot_data = {}


## ターゲットリストをリフレッシュ（ホールド中の毎フレーム更新）
func _refresh_targets() -> void:
	# 現在選択中の敵を記憶しておく
	var prev_target: Character = null
	if _target_index < _valid_targets.size():
		prev_target = _valid_targets[_target_index]

	_valid_targets = _get_sorted_targets(_attack_slot)

	if _valid_targets.is_empty():
		_target_index = 0  # キャンセル選択状態
		_update_cursor()
		return

	# 前回選択していた敵が新リストにあれば維持
	if prev_target != null and is_instance_valid(prev_target):
		var idx := _valid_targets.find(prev_target)
		if idx >= 0:
			_target_index = idx
			_update_cursor()
			return

	# 消えた場合は先頭に戻す（キャンセルインデックスは超えないよう保護）
	_target_index = 0
	_update_cursor()


func _cycle_target(dir: int) -> void:
	var total := _valid_targets.size() + 1  # + キャンセル
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


## 有効なターゲットを前方±45°優先・距離順でソートして返す
func _get_sorted_targets(slot: AttackSlot) -> Array[Character]:
	return _sort_targets(_get_valid_targets(slot))


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


## 攻撃キーが現在ホールド中かを返す
func _is_slot_held(slot: AttackSlot) -> bool:
	match slot:
		AttackSlot.Z: return Input.is_action_pressed("attack_melee")
		AttackSlot.X: return Input.is_action_pressed("attack_ranged")
	return false


## 指定スロットの有効なターゲット一覧を返す（ソートなし）
## "melee" → マンハッタン距離、"ranged"/"ranged_area" → ユークリッド距離
func _get_valid_targets(slot: AttackSlot) -> Array[Character]:
	var sd:        Dictionary = _get_slot(slot)
	var action:    String     = str(sd.get("action", "melee"))
	var range_val: int        = int(sd.get("range",  1))
	var result: Array[Character] = []
	for c: Character in blocking_characters:
		if not is_instance_valid(c):
			continue
		# 味方キャラクター（仲間NPC含む）は攻撃対象にしない
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
		elif action == "ranged" or action == "ranged_area":
			var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
			if dist <= float(range_val):
				result.append(c)
	return result


# --------------------------------------------------------------------------
# 攻撃実行
# --------------------------------------------------------------------------

func _execute_melee(target: Character, slot_data: Dictionary) -> void:
	var dmg_mult: float = float(slot_data.get("damage_mult", 1.0))
	character.face_toward(target.grid_pos)
	var dir_mult   := Character.get_direction_multiplier(character, target)
	var raw_damage := int(float(character.attack) * dmg_mult)
	target.take_damage(raw_damage, dir_mult)
	var skill_name: String = str(slot_data.get("name", "近接"))
	print("[Player] %s → %s  スキル%.1fx 方向%.1fx  HP:%d/%d" % \
			[skill_name, target.name, dmg_mult, dir_mult, target.hp, target.max_hp])


func _execute_ranged(target: Character, slot_data: Dictionary) -> void:
	var dmg_mult: float = float(slot_data.get("damage_mult", 1.0))
	character.face_toward(target.grid_pos)
	var raw_damage := int(float(character.attack) * dmg_mult)
	_spawn_projectile(target, raw_damage)


func _spawn_projectile(target: Character, raw_damage: int) -> void:
	if map_node == null:
		return
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)
	proj.setup(character.position, target.position, true, target, raw_damage, 1.0)


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
		character.move_to(new_pos)
	else:
		# 移動先に友好的キャラクターがいれば npc_bumped を発火する
		for blocker: Character in blocking_characters:
			if not is_instance_valid(blocker):
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
		if blocker.is_flying != character.is_flying:
			continue
		if pos in blocker.get_occupied_tiles():
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
