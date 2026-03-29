class_name UnitAI
extends Node

## 個体AI基底クラス（2層AIアーキテクチャの個体レイヤー）
## PartyLeaderAI からオーダーを受け取り、担当キャラクター1体の行動を実行する
## ステートマシン・A*経路探索・アクションキュー管理を担う
## サブクラスは _resolve_strategy() をオーバーライドして自己保存ロジックを実装する

enum Strategy   { ATTACK, FLEE, WAIT }
enum PathMethod { DIRECT, ASTAR, ASTAR_FLANK }

const MOVE_INTERVAL  := 0.4  ## タイル移動の間隔（秒）
const WAIT_DURATION  := 1.0  ## wait アクションの待機時間（秒）
const QUEUE_MIN_LEN  := 3    ## キューがこれ以下になったら補充するしきい値

## 従順度（0.0=完全自律 / 1.0=完全にリーダー指示に従う）
## サブクラスで上書きする。ゴブリン=0.5（自己HP危機時のみリーダー指示を上書き）
var obedience: float = 1.0

enum _State { IDLE, MOVING, WAITING, ATTACKING_PRE, ATTACKING_POST }

## セットアップで渡されるもの
var _member:      Character                   ## 担当キャラクター
var _player:      Character                   ## プレイヤー（ターゲット・_is_passable 用）
var _map_data:    MapData
var _all_members: Array[Character] = []       ## 全パーティー合算（占有チェック用）

## ステートマシン
var _state:         _State = _State.IDLE
var _goal:          Vector2i
var _timer:         float  = 0.0
var _attack_target: Character

## 現在のオーダー・キュー
var _order:          Dictionary = {}  ## PartyLeaderAI から受け取ったオーダー
var _queue:          Array      = []  ## アクションキュー
var _current_action: Dictionary = {}  ## 実行中アクション

## デバッグ・再評価用
var _strategy:         Strategy = Strategy.WAIT
var _ordered_strategy: Strategy = Strategy.WAIT  ## リーダーから受け取った指示戦略（上書き前）
var _target:           Character
var _reeval_timer:     float    = 0.0  ## フォールバック再評価タイマー（オーダーなし時）

const _REEVAL_FALLBACK := 1.5  ## フォールバック再評価間隔（秒）


func setup(member: Character, player: Character, map_data: MapData,
		all_members: Array[Character]) -> void:
	_member      = member
	_player      = player
	_map_data    = map_data
	_all_members = all_members
	_goal        = member.grid_pos


func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members


## PartyLeaderAI からオーダーを受け取る
## order: { "strategy": UnitAI.Strategy(int), "target": Character }
func receive_order(order: Dictionary) -> void:
	_order = order
	var ordered_strategy := order.get("strategy", Strategy.WAIT) as Strategy
	# キュー再適用時に target が既にfreeされている場合に備えて安全にキャストする
	var raw_target: Variant = order.get("target", null)
	var ordered_target: Character = null
	if raw_target != null and is_instance_valid(raw_target):
		ordered_target = raw_target as Character

	# リーダーから受け取った指示戦略を保持（デバッグ・上書き検出用）
	_ordered_strategy = ordered_strategy

	# 自己保存フック：必要ならリーダー指示を上書き
	var effective_strategy := _resolve_strategy(ordered_strategy)
	var effective_target   := ordered_target

	# 変化なし かつ キューが十分残っていればスキップ
	if effective_strategy == _strategy and effective_target == _target \
			and _queue.size() >= QUEUE_MIN_LEN:
		return

	_strategy = effective_strategy
	_target   = effective_target

	var new_queue := _generate_queue(effective_strategy, effective_target)
	if new_queue.is_empty():
		return
	_queue = new_queue

	# 攻撃モーション中でなければ即置き換えて IDLE に戻す
	if _state != _State.ATTACKING_PRE and _state != _State.ATTACKING_POST:
		_current_action = {}
		_state = _State.IDLE
		if _member != null and is_instance_valid(_member):
			_member.is_attacking = false


## 状況変化通知（PartyLeaderAI から呼ばれる）
func notify_situation_changed() -> void:
	_reeval_timer = 0.0


## デバッグ情報を返す（RightPanel / PartyLeaderAI.get_debug_info() が収集）
## 返す形式は BaseAI.get_debug_info() と同一（互換性維持）
func get_debug_info() -> Dictionary:
	return {
		"name":             _member.name if (_member != null and is_instance_valid(_member)) else "?",
		"strategy":         int(_strategy),
		"ordered_strategy": int(_ordered_strategy),
		"target_name":      _target.name if (_target != null and is_instance_valid(_target)) else "-",
		"current_action":   _current_action.duplicate(),
		"queue":            _queue.duplicate(),
		"grid_pos":         _member.grid_pos if (_member != null and is_instance_valid(_member)) else Vector2i.ZERO,
	}


# --------------------------------------------------------------------------
# ステートマシン
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _member == null or not is_instance_valid(_member):
		return

	# フォールバック：オーダーを受け取っていない場合の自律再評価
	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = _REEVAL_FALLBACK
		if _order.is_empty():
			_fallback_evaluate()

	match _state:
		_State.IDLE:
			var action := _pop_action()
			if not action.is_empty():
				_start_action(action)
			elif _queue.is_empty():
				if not _order.is_empty():
					# オーダーを再適用してキューを補充
					receive_order(_order)
				else:
					_fallback_evaluate()

		_State.MOVING:
			_timer -= delta
			if _timer <= 0.0:
				var still_moving := _step_toward_goal()
				if still_moving:
					_timer = MOVE_INTERVAL
				else:
					_state = _State.IDLE
					_complete_action()

		_State.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				_state = _State.IDLE
				_complete_action()

		_State.ATTACKING_PRE:
			_timer -= delta
			if _timer <= 0.0:
				_execute_attack()
				_member.is_attacking = false
				_state = _State.ATTACKING_POST
				var post := _member.character_data.post_delay if _member.character_data else 0.5
				_timer = post

		_State.ATTACKING_POST:
			_timer -= delta
			if _timer <= 0.0:
				_state = _State.IDLE
				_complete_action()


func _start_action(action: Dictionary) -> void:
	match action.get("action", "") as String:
		"move_to_attack":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			var goal := _calc_attack_goal(_target, _get_path_method())
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = MOVE_INTERVAL

		"flee":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			var goal := _find_flee_goal(_target)
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = MOVE_INTERVAL

		"attack":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			# 飛行ターゲットへの近接攻撃は不可
			if _target.is_flying:
				_complete_action()
				return
			# 隣接していなければスキップ
			var d := _target.grid_pos - _member.grid_pos
			if abs(d.x) + abs(d.y) != 1:
				_complete_action()
				return
			_attack_target = _target
			_state = _State.ATTACKING_PRE
			_timer = _member.character_data.pre_delay if _member.character_data else 0.3
			_member.is_attacking = true

		"wait":
			_state = _State.WAITING
			_timer = WAIT_DURATION

		_:
			_complete_action()


## 目標に向かって1タイル進む。移動継続中なら true、到達またはスタックなら false
func _step_toward_goal() -> bool:
	if _target != null and is_instance_valid(_target):
		var action_type := _current_action.get("action", "") as String
		if action_type == "move_to_attack":
			_goal = _calc_attack_goal(_target, _get_path_method())
		elif action_type == "flee":
			_goal = _find_flee_goal(_target)

	if _member.grid_pos == _goal:
		return false

	var next := _get_next_step(_goal)
	if next != _member.grid_pos:
		_member.move_to(next)
		return _member.grid_pos != _goal

	return false  # スタック


func _get_next_step(goal: Vector2i) -> Vector2i:
	var method := _get_path_method()
	if method == PathMethod.DIRECT:
		return _next_step_direct(goal)
	var path := _astar(_member.grid_pos, goal)
	if path.is_empty():
		return _next_step_direct(goal)
	return path[0]


func _next_step_direct(goal: Vector2i) -> Vector2i:
	var dx := goal.x - _member.grid_pos.x
	var dy := goal.y - _member.grid_pos.y
	var candidates: Array[Vector2i] = []
	if abs(dx) >= abs(dy):
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
	else:
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
	for step: Vector2i in candidates:
		var next := _member.grid_pos + step
		if _is_passable(next):
			return next
	return _member.grid_pos


# --------------------------------------------------------------------------
# フォールバック評価（オーダーなし時の自律行動）
# --------------------------------------------------------------------------

func _fallback_evaluate() -> void:
	var new_strategy := _evaluate_strategy()
	var new_target   := _select_target()
	if new_strategy == _strategy and new_target == _target and _queue.size() >= QUEUE_MIN_LEN:
		return
	_strategy = new_strategy
	_target   = new_target
	var new_queue := _generate_queue(new_strategy, new_target)
	if new_queue.is_empty():
		return
	_queue = new_queue
	if _state != _State.ATTACKING_PRE and _state != _State.ATTACKING_POST:
		_current_action = {}
		_state = _State.IDLE
		if is_instance_valid(_member):
			_member.is_attacking = false


# --------------------------------------------------------------------------
# キュー管理
# --------------------------------------------------------------------------

func _generate_queue(strategy: Strategy, target: Character) -> Array:
	match strategy:
		Strategy.ATTACK:
			if target == null or not is_instance_valid(target):
				return [{"action": "wait"}]
			var q: Array = []
			for _i: int in range(4):
				q.append({"action": "move_to_attack"})
				q.append({"action": "attack"})
			return q
		Strategy.FLEE:
			if target == null or not is_instance_valid(target):
				return [{"action": "wait"}]
			var q: Array = []
			for _i: int in range(5):
				q.append({"action": "flee"})
			return q
		Strategy.WAIT:
			return [{"action": "wait"}]
	return [{"action": "wait"}]


func _pop_action() -> Dictionary:
	if _queue.is_empty():
		return {}
	var action := _queue[0] as Dictionary
	_queue.pop_front()
	_current_action = action
	return action


func _complete_action() -> void:
	_current_action = {}


# --------------------------------------------------------------------------
# 攻撃実行
# --------------------------------------------------------------------------

func _execute_attack() -> void:
	if _attack_target == null or not is_instance_valid(_attack_target):
		return
	var multiplier := Character.get_direction_multiplier(_member, _attack_target)
	_attack_target.take_damage(_member.attack, multiplier)


# --------------------------------------------------------------------------
# 目標座標計算
# --------------------------------------------------------------------------

func _calc_attack_goal(target: Character, method: PathMethod) -> Vector2i:
	if method == PathMethod.ASTAR_FLANK:
		return _find_flank_goal(target)
	return _find_adjacent_goal(target)


## ターゲットに隣接する最近傍の空きタイルを返す（他の敵が占有していないもの）
func _find_adjacent_goal(target: Character) -> Vector2i:
	var d := target.grid_pos - _member.grid_pos
	if abs(d.x) + abs(d.y) == 1:
		return _member.grid_pos
	var best      := _member.grid_pos
	var best_dist := 999999
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var candidate := target.grid_pos + offset
		if candidate == _member.grid_pos:
			return candidate
		if _is_passable(candidate):
			var dist := _manhattan(_member.grid_pos, candidate)
			if dist < best_dist:
				best_dist = dist
				best = candidate
	return best


func _find_flank_goal(target: Character) -> Vector2i:
	var facing_vec := Character.dir_to_vec(target.facing)
	var behind     := target.grid_pos - facing_vec
	if _map_data != null and _map_data.is_walkable_for(behind, _member.is_flying):
		return behind
	return _find_adjacent_goal(target)


func _find_flee_goal(threat: Character) -> Vector2i:
	var dx := _member.grid_pos.x - threat.grid_pos.x
	var dy := _member.grid_pos.y - threat.grid_pos.y
	var flee_dir := Vector2i(
		sign(dx) if dx != 0 else (randi() % 3 - 1),
		sign(dy) if dy != 0 else (randi() % 3 - 1)
	)
	if flee_dir == Vector2i.ZERO:
		flee_dir = Vector2i(1, 0)
	var goal := _member.grid_pos
	for i: int in range(1, 6):
		var candidate := _member.grid_pos + flee_dir * i
		if _map_data != null and _map_data.is_walkable_for(candidate, _member.is_flying):
			goal = candidate
		else:
			break
	if goal == _member.grid_pos:
		var alts: Array[Vector2i] = [
			Vector2i(flee_dir.y,  flee_dir.x),
			Vector2i(-flee_dir.y, -flee_dir.x),
		]
		for alt: Vector2i in alts:
			var candidate := _member.grid_pos + alt
			if _map_data != null and _map_data.is_walkable_for(candidate, _member.is_flying):
				return candidate
	return goal


# --------------------------------------------------------------------------
# A* 経路探索
# --------------------------------------------------------------------------

func _astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return []
	var open_set:  Array[Vector2i] = [start]
	var came_from: Dictionary      = {}
	var g_score:   Dictionary      = {start: 0}
	var f_score:   Dictionary      = {start: _manhattan(start, goal)}
	var max_iter   := 400
	var iter       := 0
	while not open_set.is_empty() and iter < max_iter:
		iter += 1
		var current := open_set[0] as Vector2i
		for p: Vector2i in open_set:
			if (f_score.get(p, 99999) as int) < (f_score.get(current, 99999) as int):
				current = p
		if current == goal:
			var path: Array[Vector2i] = []
			var c := current
			while c != start:
				path.push_front(c)
				c = came_from[c] as Vector2i
			return path
		open_set.erase(current)
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor := current + offset
			if not _is_passable(neighbor):
				continue
			var tentative_g: int = (g_score.get(current, 99999) as int) + 1
			if tentative_g < (g_score.get(neighbor, 99999) as int):
				came_from[neighbor] = current
				g_score[neighbor]   = tentative_g
				f_score[neighbor]   = tentative_g + _manhattan(neighbor, goal)
				if neighbor not in open_set:
					open_set.append(neighbor)
	return []


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# --------------------------------------------------------------------------
# 通行可能チェック
# --------------------------------------------------------------------------

## 歩行可能かつ同レイヤーの他キャラが占有していないか確認する
## _all_members（全パーティー合算）を参照することで他パーティーとの重複も防ぐ
func _is_passable(pos: Vector2i) -> bool:
	if _map_data != null and not _map_data.is_walkable_for(pos, _member.is_flying):
		return false
	for other: Character in _all_members:
		if not is_instance_valid(other):
			continue
		if other == _member:
			continue
		if other.is_flying != _member.is_flying:
			continue
		if pos in other.get_occupied_tiles():
			return false
	if _player != null and is_instance_valid(_player):
		if _player.is_flying == _member.is_flying and pos in _player.get_occupied_tiles():
			return false
	return true


# --------------------------------------------------------------------------
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

## 自己保存ロジック：リーダーからのオーダー戦略を上書きするか判断する
## デフォルト: 常にリーダー指示通り（obedience=1.0 相当）
func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	return ordered_strategy


## フォールバック：オーダーなし時の戦略評価（自律モード）
func _evaluate_strategy() -> Strategy:
	return Strategy.WAIT


## フォールバック：オーダーなし時のターゲット選択
func _select_target() -> Character:
	return _player


## 経路探索方法を選択する
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
