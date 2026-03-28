class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Phase 4: NORMAL/TARGETINGステートマシン・Z/Xキー攻撃スロット・飛翔体対応

var character: Character = null
var map_data: MapData = null

## 移動先の占有チェック対象。get_occupied_tiles() で判定するため複数マスキャラにも対応
var blocking_characters: Array[Character] = []

## 飛翔体・ターゲットカーソルの add_child 用
var map_node: Node2D = null

const MOVE_INTERVAL_INITIAL: float = 0.20
const MOVE_INTERVAL_REPEAT:  float = 0.10
const MELEE_RANGE:  int = 1  # マンハッタン距離
const RANGED_RANGE: int = 5  # ユークリッド距離（タイル数）

enum Mode       { NORMAL, TARGETING }
enum AttackSlot { MELEE, RANGED }

var _mode:          Mode       = Mode.NORMAL
var _attack_slot:   AttackSlot = AttackSlot.MELEE
var _valid_targets: Array[Character] = []
var _target_index:  int = 0  # valid_targets.size() = キャンセル選択

var _move_timer: float = 0.0
var _holding:    bool  = false
var _cursor: TargetCursor = null


func _process(delta: float) -> void:
	if character == null:
		return

	if _mode == Mode.TARGETING:
		_process_targeting()
		return

	# 攻撃スロット（Z/X）
	if Input.is_action_just_pressed("attack_melee"):
		_enter_targeting(AttackSlot.MELEE)
		return
	elif Input.is_action_just_pressed("attack_ranged"):
		_enter_targeting(AttackSlot.RANGED)
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
	elif _attack_slot == AttackSlot.MELEE and Input.is_action_just_pressed("attack_melee"):
		_confirm_attack()
	elif _attack_slot == AttackSlot.RANGED and Input.is_action_just_pressed("attack_ranged"):
		_confirm_attack()


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
	# 全ターゲットのハイライトを解除
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
	# 全ターゲットのハイライトをリセット
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
		tgt.is_targeted = true  # 選択中ターゲットをハイライト


func _confirm_attack() -> void:
	if _target_index >= _valid_targets.size():
		_exit_targeting()
		return

	var target := _valid_targets[_target_index]
	match _attack_slot:
		AttackSlot.MELEE:
			_execute_melee(target)
		AttackSlot.RANGED:
			_execute_ranged(target)

	_exit_targeting()


func _execute_melee(target: Character) -> void:
	character.face_toward(target.grid_pos)
	var multiplier := Character.get_direction_multiplier(character, target)
	target.take_damage(character.attack, multiplier)
	print("[Player] 近接攻撃 → %s  %.1fx  HP:%d/%d" % \
			[target.name, multiplier, target.hp, target.max_hp])


func _execute_ranged(target: Character) -> void:
	character.face_toward(target.grid_pos)
	# 発射時点の射程チェック（射程外なら空振り、弾は飛ぶ）
	var dist   := Vector2(character.grid_pos).distance_to(Vector2(target.grid_pos))
	var will_hit := dist <= float(RANGED_RANGE)
	_spawn_projectile(target, will_hit)


func _spawn_projectile(target: Character, will_hit: bool) -> void:
	if map_node == null:
		return
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)
	proj.setup(character.position, target.position, will_hit, target, character.attack, 1.0)


## 指定スロットの有効なターゲット一覧を返す
func _get_valid_targets(slot: AttackSlot) -> Array[Character]:
	var result: Array[Character] = []
	for c: Character in blocking_characters:
		if not is_instance_valid(c):
			continue
		match slot:
			AttackSlot.MELEE:
				var dx: int = abs(c.grid_pos.x - character.grid_pos.x)
				var dy: int = abs(c.grid_pos.y - character.grid_pos.y)
				# 飛行ターゲットへの近接攻撃は不可（地上→飛行・飛行→飛行）
				if c.is_flying:
					continue
				if dx + dy <= MELEE_RANGE:
					result.append(c)
			AttackSlot.RANGED:
				var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
				if dist <= float(RANGED_RANGE):
					result.append(c)
	return result


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
		# map_data未設定時のフォールバック（境界チェックのみ）
		if not (pos.x >= 0 and pos.x < MapData.MAP_WIDTH \
				and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT):
			return false

	for blocker: Character in blocking_characters:
		if not is_instance_valid(blocker):
			continue
		# 飛行属性が異なるキャラクターとはすり抜け可能
		if blocker.is_flying != character.is_flying:
			continue
		if pos in blocker.get_occupied_tiles():
			return false

	return true
