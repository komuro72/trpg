class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Phase 4: NORMAL/TARGETINGステートマシン・Z/Xキー攻撃スロット・飛翔体対応
## Phase 6-0: クラスJSONのスロット定義を読み込み、クラスごとの攻撃動作に対応
##   - _ready() でクラスJSONを参照してスロットデータを設定
##   - action: "melee" → マンハッタン距離・近接判定
##   - action: "ranged" / "ranged_area" → ユークリッド距離・飛翔体
##   - damage_mult がスロット単位で適用される（背面2倍等の方向補正とは別）

var character: Character = null
var map_data: MapData = null

## 移動先の占有チェック対象
var blocking_characters: Array[Character] = []

## 飛翔体・ターゲットカーソルの add_child 用
var map_node: Node2D = null

const MOVE_INTERVAL_INITIAL: float = 0.20
const MOVE_INTERVAL_REPEAT:  float = 0.10
const CLASS_JSON_DIR := "res://assets/master/classes/"

## デフォルトスロット（クラスデータが存在しない場合のフォールバック）
const DEFAULT_SLOT_Z: Dictionary = {
	"name": "近接攻撃", "action": "melee",  "type": "physical",
	"range": 1, "damage_mult": 1.0
}
const DEFAULT_SLOT_X: Dictionary = {
	"name": "遠距離攻撃", "action": "ranged", "type": "physical",
	"range": 5, "damage_mult": 1.0
}

enum Mode       { NORMAL, TARGETING }
enum AttackSlot { Z, X }

var _mode:          Mode       = Mode.NORMAL
var _attack_slot:   AttackSlot = AttackSlot.Z
var _valid_targets: Array[Character] = []
var _target_index:  int = 0  # valid_targets.size() = キャンセル選択

var _move_timer: float = 0.0
var _holding:    bool  = false
var _cursor: TargetCursor = null

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
	if character == null:
		return

	if _mode == Mode.TARGETING:
		_process_targeting()
		return

	# 攻撃スロット（Z/X）
	if Input.is_action_just_pressed("attack_melee"):
		_enter_targeting(AttackSlot.Z)
		return
	elif Input.is_action_just_pressed("attack_ranged"):
		_enter_targeting(AttackSlot.X)
		return

	# 移動処理
	_move_timer -= delta
	var dir := _get_input_direction()
	if dir == Vector2i.ZERO:
		_holding = false
		_move_timer = 0.0
		return
	if not _holding:
		_try_move(dir)
		_holding = true
		_move_timer = MOVE_INTERVAL_INITIAL
	elif _move_timer <= 0.0:
		_try_move(dir)
		_move_timer = MOVE_INTERVAL_REPEAT


func _process_targeting() -> void:
	# 死亡したターゲットを除去
	var live: Array[Character] = []
	for c: Character in _valid_targets:
		if is_instance_valid(c):
			live.append(c)
	if live.size() != _valid_targets.size():
		_valid_targets = live
		if _valid_targets.is_empty():
			_exit_targeting()
			return
		_target_index = mini(_target_index, _valid_targets.size())
		_update_cursor()

	# 循環選択（右/下 = 次、左/上 = 前）
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
		_cycle_target(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
		_cycle_target(-1)
	# 確定（キャンセル選択中に押した場合はキャンセル扱い）
	elif _attack_slot == AttackSlot.Z and Input.is_action_just_pressed("attack_melee"):
		_confirm_attack()
	elif _attack_slot == AttackSlot.X and Input.is_action_just_pressed("attack_ranged"):
		_confirm_attack()


# --------------------------------------------------------------------------
# ターゲット選択
# --------------------------------------------------------------------------

func _enter_targeting(slot: AttackSlot) -> void:
	_valid_targets = _get_valid_targets(slot)
	if _valid_targets.is_empty():
		return  # 有効なターゲットなし

	_attack_slot  = slot
	_mode         = Mode.TARGETING
	_target_index = 0
	_holding      = false
	_move_timer   = 0.0
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
	_target_index = 0
	character.is_targeting_mode = false
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null


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
		tgt.is_targeted = true


## 指定スロットの有効なターゲット一覧を返す
## "melee" → マンハッタン距離、"ranged"/"ranged_area" → ユークリッド距離
func _get_valid_targets(slot: AttackSlot) -> Array[Character]:
	var sd:       Dictionary = _get_slot(slot)
	var action:   String     = str(sd.get("action", "melee"))
	var range_val: int       = int(sd.get("range",  1))
	var result: Array[Character] = []
	for c: Character in blocking_characters:
		if not is_instance_valid(c):
			continue
		if action == "melee":
			# 飛行ターゲットへの近接攻撃は不可（地上→飛行・飛行→飛行）
			if c.is_flying:
				continue
			var dx := abs(c.grid_pos.x - character.grid_pos.x)
			var dy := abs(c.grid_pos.y - character.grid_pos.y)
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

func _confirm_attack() -> void:
	if _target_index >= _valid_targets.size():
		_exit_targeting()
		return

	var target := _valid_targets[_target_index]
	var sd     := _get_slot(_attack_slot)
	var action: String = str(sd.get("action", "melee"))

	if action == "melee":
		_execute_melee(target, sd)
	elif action == "ranged" or action == "ranged_area":
		_execute_ranged(target, sd)

	_exit_targeting()


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
	var range_val: int  = int(slot_data.get("range", 5))
	character.face_toward(target.grid_pos)
	# 発射時点の射程チェック（射程外なら空振り、弾は飛ぶ）
	var dist     := Vector2(character.grid_pos).distance_to(Vector2(target.grid_pos))
	var will_hit := dist <= float(range_val)
	var raw_damage := int(float(character.attack) * dmg_mult)
	_spawn_projectile(target, will_hit, raw_damage)


func _spawn_projectile(target: Character, will_hit: bool, raw_damage: int) -> void:
	if map_node == null:
		return
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)
	proj.setup(character.position, target.position, will_hit, target, raw_damage, 1.0)


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
