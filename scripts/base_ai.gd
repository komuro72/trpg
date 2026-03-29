class_name BaseAI
extends Node

## [レガシー] 旧ルールベース敵AI基底クラス
## Phase 6-0 のリファクタリングにより UnitAI + PartyLeaderAI の2層構造に移行しました。
## このクラスは後方互換のために残していますが、新しいコードでは使用しないでください。
## 新しい構造: UnitAI（個体）/ PartyLeaderAI（パーティー）/ PartyManager（管理）
##
## ステートマシン・移動（直進/A*/A*回り込み）・攻撃実行・キュー管理・定期再評価を担う
## 種類固有AIはこのクラスを継承し _evaluate_strategy/_select_target/_select_path_method をオーバーライドする

enum Strategy   { ATTACK, FLEE, WAIT }
enum PathMethod { DIRECT, ASTAR, ASTAR_FLANK }

const MOVE_INTERVAL   := 0.4   ## タイル移動の間隔（秒）
const WAIT_DURATION   := 1.0   ## wait アクションの待機時間（秒）
const REEVAL_INTERVAL := 1.5   ## 定期再評価間隔（秒）
const QUEUE_MIN_LEN   := 3     ## キューがこれ以下になったら再評価時に補充する

enum _State { IDLE, MOVING, WAITING, ATTACKING_PRE, ATTACKING_POST }

var _enemies: Array[Character] = []      ## 自パーティーの敵（戦略・キュー管理用）
var _all_enemies: Array[Character] = []  ## 全パーティーの敵（_is_passable 占有チェック用）
var _player: Character
var _map_data: MapData
var _initial_count: int = 0   ## 初期敵数（逃走判定の基準に使用）

var _queues: Dictionary = {}          # enemy_id -> Array
var _current: Dictionary = {}         # enemy_id -> Dictionary（実行中アクション）
var _states: Dictionary = {}          # enemy_id -> _State
var _goals: Dictionary = {}           # enemy_id -> Vector2i
var _timers: Dictionary = {}          # enemy_id -> float
var _attack_targets: Dictionary = {}  # enemy_id -> Character
var _reeval_timers: Dictionary = {}   # enemy_id -> float
var _strategies: Dictionary = {}      # enemy_id -> Strategy
var _targets: Dictionary = {}         # enemy_id -> Character (nullable)
var _path_methods: Dictionary = {}    # enemy_id -> PathMethod


## アクティブ化後に EnemyManager から呼び出す
func setup(enemies: Array[Character], player: Character, map_data: MapData) -> void:
	_enemies       = enemies
	_all_enemies   = enemies  # set_all_enemies() で全パーティー分に上書きされる
	_player        = player
	_map_data      = map_data
	_initial_count = enemies.size()


## 他パーティーも含む全敵リストを設定する（_is_passable での占有チェック用）
## EnemyManager から全マネージャー生成後に呼び出される
func set_all_enemies(all_enemies: Array[Character]) -> void:
	_all_enemies = all_enemies

	for enemy: Character in _enemies:
		var id := enemy.name
		_states[id]        = _State.IDLE
		_timers[id]        = 0.0
		_reeval_timers[id] = 0.0
		_strategies[id]    = Strategy.WAIT
		_targets[id]       = null
		_path_methods[id]  = PathMethod.ASTAR

	for enemy: Character in _enemies:
		_do_evaluate_and_refill(enemy)


func _process(delta: float) -> void:
	if _enemies.is_empty():
		return
	for enemy: Character in _enemies:
		if is_instance_valid(enemy):
			_tick_enemy(enemy, delta)


# --------------------------------------------------------------------------
# ステートマシン
# --------------------------------------------------------------------------

func _tick_enemy(enemy: Character, delta: float) -> void:
	var id    := enemy.name
	var state := _states.get(id, _State.IDLE) as _State

	# 定期再評価タイマー
	var rt: float = (_reeval_timers.get(id, 0.0) as float) - delta
	_reeval_timers[id] = rt
	if rt <= 0.0:
		_reeval_timers[id] = REEVAL_INTERVAL
		_do_evaluate_and_refill(enemy)

	match state:
		_State.IDLE:
			var action := _pop_action(id)
			if not action.is_empty():
				_start_action(enemy, action)
			elif (_queues.get(id, []) as Array).is_empty():
				_do_evaluate_and_refill(enemy)

		_State.MOVING:
			var t: float = (_timers.get(id, 0.0) as float) - delta
			_timers[id] = t
			if t <= 0.0:
				var still_moving := _step_toward_goal(enemy)
				if still_moving:
					_timers[id] = MOVE_INTERVAL
				else:
					_states[id] = _State.IDLE
					complete_action(id)

		_State.WAITING:
			var t: float = (_timers.get(id, 0.0) as float) - delta
			_timers[id] = t
			if t <= 0.0:
				_states[id] = _State.IDLE
				complete_action(id)

		_State.ATTACKING_PRE:
			var t: float = (_timers.get(id, 0.0) as float) - delta
			_timers[id] = t
			if t <= 0.0:
				_execute_attack(enemy)
				enemy.is_attacking = false
				_states[id] = _State.ATTACKING_POST
				var post := enemy.character_data.post_delay if enemy.character_data else 0.5
				_timers[id] = post

		_State.ATTACKING_POST:
			var t: float = (_timers.get(id, 0.0) as float) - delta
			_timers[id] = t
			if t <= 0.0:
				_states[id] = _State.IDLE
				complete_action(id)


func _start_action(enemy: Character, action: Dictionary) -> void:
	var id := enemy.name
	match action.get("action", "") as String:
		"move_to_attack":
			var target := _targets.get(id) as Character
			if target == null or not is_instance_valid(target):
				complete_action(id)
				return
			var method := _path_methods.get(id, PathMethod.ASTAR) as PathMethod
			var goal   := _calc_attack_goal(enemy, target, method)
			if goal == enemy.grid_pos:
				complete_action(id)
				return
			_goals[id]  = goal
			_states[id] = _State.MOVING
			_timers[id] = MOVE_INTERVAL

		"flee":
			var target := _targets.get(id) as Character
			if target == null or not is_instance_valid(target):
				complete_action(id)
				return
			var goal := _find_flee_goal(enemy, target)
			if goal == enemy.grid_pos:
				complete_action(id)
				return
			_goals[id]  = goal
			_states[id] = _State.MOVING
			_timers[id] = MOVE_INTERVAL

		"attack":
			var target := _targets.get(id) as Character
			if target == null or not is_instance_valid(target):
				complete_action(id)
				return
			# 飛行ターゲットへの近接攻撃は不可
			if target.is_flying:
				complete_action(id)
				return
			# 隣接していなければスキップ
			var d := target.grid_pos - enemy.grid_pos
			if abs(d.x) + abs(d.y) != 1:
				complete_action(id)
				return
			_attack_targets[id] = target
			_states[id] = _State.ATTACKING_PRE
			_timers[id] = enemy.character_data.pre_delay if enemy.character_data else 0.3
			enemy.is_attacking = true

		"wait":
			_states[id] = _State.WAITING
			_timers[id] = WAIT_DURATION

		_:
			complete_action(id)


## 目標に向かって1タイル進む。移動継続中なら true、到達またはスタックなら false
func _step_toward_goal(enemy: Character) -> bool:
	var id     := enemy.name
	var action := _current.get(id, {}) as Dictionary
	var target := _targets.get(id) as Character

	# ターゲット追従：毎タイルゴールを再計算
	if target != null and is_instance_valid(target):
		var action_type := action.get("action", "") as String
		if action_type == "move_to_attack":
			var method := _path_methods.get(id, PathMethod.ASTAR) as PathMethod
			_goals[id] = _calc_attack_goal(enemy, target, method)
		elif action_type == "flee":
			_goals[id] = _find_flee_goal(enemy, target)

	var goal := _goals.get(id, enemy.grid_pos) as Vector2i
	if enemy.grid_pos == goal:
		return false

	var method := _path_methods.get(id, PathMethod.ASTAR) as PathMethod
	var next   := _get_next_step(enemy, goal, method)

	if next != enemy.grid_pos:
		enemy.move_to(next)
		return enemy.grid_pos != goal

	return false  # スタック


## 経路探索方法に応じて次の1ステップを返す
func _get_next_step(enemy: Character, goal: Vector2i, method: PathMethod) -> Vector2i:
	if method == PathMethod.DIRECT:
		return _next_step_direct(enemy, goal)
	# ASTAR / ASTAR_FLANK ともに A* で経路探索
	var path := _astar(enemy.grid_pos, goal, enemy)
	if path.is_empty():
		return _next_step_direct(enemy, goal)  # フォールバック
	return path[0]


## 直進（差が大きい軸を優先。障害物があれば止まる）
func _next_step_direct(enemy: Character, goal: Vector2i) -> Vector2i:
	var dx := goal.x - enemy.grid_pos.x
	var dy := goal.y - enemy.grid_pos.y
	var candidates: Array[Vector2i] = []
	if abs(dx) >= abs(dy):
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
	else:
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
	for step: Vector2i in candidates:
		var next := enemy.grid_pos + step
		if _is_passable(next, enemy):
			return next
	return enemy.grid_pos


# --------------------------------------------------------------------------
# 目標座標計算
# --------------------------------------------------------------------------

## 経路方式に応じた攻撃目標座標を返す
func _calc_attack_goal(enemy: Character, target: Character, method: PathMethod) -> Vector2i:
	if method == PathMethod.ASTAR_FLANK:
		return _find_flank_goal(enemy, target)
	return _find_adjacent_goal(enemy, target)


## ターゲットに隣接する最近傍タイルを返す（既に隣接していれば現在地）
## 他の敵が占有しているタイルはスキップして、空きタイルを選ぶ
func _find_adjacent_goal(enemy: Character, target: Character) -> Vector2i:
	# 既に隣接していれば現在地を返す
	var d := target.grid_pos - enemy.grid_pos
	if abs(d.x) + abs(d.y) == 1:
		return enemy.grid_pos

	var best      := enemy.grid_pos
	var best_dist := 999999
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var candidate := target.grid_pos + offset
		if candidate == enemy.grid_pos:
			return candidate
		# is_walkable_for ではなく _is_passable で占有チェックも行う
		if _is_passable(candidate, enemy):
			var dist := _manhattan(enemy.grid_pos, candidate)
			if dist < best_dist:
				best_dist = dist
				best = candidate
	return best


## ターゲットの背後（向いている反対方向）タイルを返す。不可なら隣接ゴールにフォールバック
func _find_flank_goal(enemy: Character, target: Character) -> Vector2i:
	var facing_vec := Character.dir_to_vec(target.facing)
	var behind     := target.grid_pos - facing_vec
	if _map_data != null and _map_data.is_walkable_for(behind, enemy.is_flying):
		return behind
	return _find_adjacent_goal(enemy, target)


## 脅威から離れる方向に最大5タイル先の目標を返す
func _find_flee_goal(enemy: Character, threat: Character) -> Vector2i:
	var dx := enemy.grid_pos.x - threat.grid_pos.x
	var dy := enemy.grid_pos.y - threat.grid_pos.y
	var flee_dir := Vector2i(
		sign(dx) if dx != 0 else (randi() % 3 - 1),
		sign(dy) if dy != 0 else (randi() % 3 - 1)
	)
	if flee_dir == Vector2i.ZERO:
		flee_dir = Vector2i(1, 0)

	# 逃走方向に最大5タイル進んだ地点を目標に
	var goal := enemy.grid_pos
	for i: int in range(1, 6):
		var candidate := enemy.grid_pos + flee_dir * i
		if _map_data != null and _map_data.is_walkable_for(candidate, enemy.is_flying):
			goal = candidate
		else:
			break

	# 直進が壁ならば側面を試す
	if goal == enemy.grid_pos:
		var alts: Array[Vector2i] = [
			Vector2i(flee_dir.y, flee_dir.x),
			Vector2i(-flee_dir.y, -flee_dir.x)
		]
		for alt: Vector2i in alts:
			var candidate := enemy.grid_pos + alt
			if _map_data != null and _map_data.is_walkable_for(candidate, enemy.is_flying):
				return candidate
	return goal


# --------------------------------------------------------------------------
# A* 経路探索
# --------------------------------------------------------------------------

## start から goal までの経路（startを除いたタイル列）を返す。経路なしなら空配列
func _astar(start: Vector2i, goal: Vector2i, mover: Character) -> Array[Vector2i]:
	if start == goal:
		return []

	var open_set: Array[Vector2i]  = [start]
	var came_from: Dictionary      = {}
	var g_score: Dictionary        = {start: 0}
	var f_score: Dictionary        = {start: _manhattan(start, goal)}
	var max_iter  := 400   # 無限ループ防止（大きめマップでも余裕を持つ）
	var iter      := 0

	while not open_set.is_empty() and iter < max_iter:
		iter += 1

		# f_score 最小のノードを取得
		var current := open_set[0] as Vector2i
		for p: Vector2i in open_set:
			if (f_score.get(p, 99999) as int) < (f_score.get(current, 99999) as int):
				current = p

		if current == goal:
			# 経路を再構成（start は含まない）
			var path: Array[Vector2i] = []
			var c := current
			while c != start:
				path.push_front(c)
				c = came_from[c] as Vector2i
			return path

		open_set.erase(current)

		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor := current + offset
			# 全タイルで占有チェックを行う（ゴールタイルも含む）
			if not _is_passable(neighbor, mover):
				continue

			var tentative_g: int = (g_score.get(current, 99999) as int) + 1
			if tentative_g < (g_score.get(neighbor, 99999) as int):
				came_from[neighbor] = current
				g_score[neighbor]   = tentative_g
				f_score[neighbor]   = tentative_g + _manhattan(neighbor, goal)
				if neighbor not in open_set:
					open_set.append(neighbor)

	return []  # 経路なし


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# --------------------------------------------------------------------------
# キュー管理・戦略評価
# --------------------------------------------------------------------------

## 戦略・ターゲットを評価してキューを補充する（変化なし＋キュー十分なら何もしない）
func _do_evaluate_and_refill(enemy: Character) -> void:
	var id           := enemy.name
	var new_strategy := _evaluate_strategy(enemy)
	var new_target   := _select_target(enemy)
	var new_method   := _select_path_method(enemy)

	var old_strategy := _strategies.get(id, Strategy.WAIT) as Strategy
	var old_target   := _targets.get(id) as Character
	var queue_len    := (_queues.get(id, []) as Array).size()

	# 変化なし かつ キューが十分残っていればスキップ
	if new_strategy == old_strategy and new_target == old_target and queue_len >= QUEUE_MIN_LEN:
		return

	_strategies[id]   = new_strategy
	_targets[id]      = new_target
	_path_methods[id] = new_method

	var new_queue := _generate_queue(enemy, new_strategy, new_target)
	if new_queue.is_empty():
		return

	_queues[id] = new_queue

	# 攻撃モーション中でなければキューを即置き換えて IDLE に戻す
	var cur_state := _states.get(id, _State.IDLE) as _State
	if cur_state != _State.ATTACKING_PRE and cur_state != _State.ATTACKING_POST:
		_current.erase(id)
		_states[id] = _State.IDLE
		enemy.is_attacking = false


## 戦略に応じたアクションキューを生成する
func _generate_queue(_enemy: Character, strategy: Strategy, target: Character) -> Array:
	match strategy:
		Strategy.ATTACK:
			if target == null or not is_instance_valid(target):
				return [{"action": "wait"}]
			# 接近→攻撃 を複数セット積む
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


## キューから次のアクションを取り出す（内部用）
func _pop_action(enemy_id: String) -> Dictionary:
	if not _queues.has(enemy_id):
		return {}
	var q := _queues[enemy_id] as Array
	if q.is_empty():
		return {}
	var action := q[0] as Dictionary
	q.pop_front()
	_current[enemy_id] = action
	return action


## アクション完了を通知する
func complete_action(enemy_id: String) -> void:
	_current.erase(enemy_id)


## 攻撃を受けたなど状況が大きく変わったときに呼び出す（全敵を即再評価）
func notify_situation_changed() -> void:
	for enemy: Character in _enemies:
		_reeval_timers[enemy.name] = 0.0


## デバッグ表示用：各敵の現在のAI状態をDictionary配列で返す
## 返す辞書のキー: name / strategy(int) / target_name / current_action / queue / grid_pos
func get_debug_info() -> Array:
	var result: Array = []
	for enemy: Character in _enemies:
		if not is_instance_valid(enemy):
			continue
		var id      := enemy.name
		var strat   := int(_strategies.get(id, int(Strategy.WAIT)))
		var target  := _targets.get(id) as Character
		var queue   := (_queues.get(id, []) as Array).duplicate()
		var current := (_current.get(id, {}) as Dictionary).duplicate()
		result.append({
			"name":           id,
			"strategy":       strat,
			"target_name":    target.name if (target != null and is_instance_valid(target)) else "-",
			"current_action": current,
			"queue":          queue,
			"grid_pos":       enemy.grid_pos,
		})
	return result


# --------------------------------------------------------------------------
# 攻撃実行
# --------------------------------------------------------------------------

## 攻撃を実行する（ATTACKING_PRE 完了時に呼ばれる）
func _execute_attack(enemy: Character) -> void:
	var id     := enemy.name
	var target := _attack_targets.get(id) as Character
	if target == null or not is_instance_valid(target):
		return
	var multiplier := Character.get_direction_multiplier(enemy, target)
	target.take_damage(enemy.attack, multiplier)


# --------------------------------------------------------------------------
# 通行可能チェック
# --------------------------------------------------------------------------

## 歩行可能かつ同レイヤーの他キャラが占有していないか確認する
## _all_enemies（全パーティー合算）を参照することで他パーティーとの重複も防ぐ
func _is_passable(pos: Vector2i, moving_enemy: Character) -> bool:
	if _map_data != null and not _map_data.is_walkable_for(pos, moving_enemy.is_flying):
		return false
	for other: Character in _all_enemies:
		if not is_instance_valid(other):
			continue
		if other == moving_enemy:
			continue
		if other.is_flying != moving_enemy.is_flying:
			continue
		if pos in other.get_occupied_tiles():
			return false
	if _player != null and is_instance_valid(_player):
		if _player.is_flying == moving_enemy.is_flying and pos in _player.get_occupied_tiles():
			return false
	return true


# --------------------------------------------------------------------------
# 種類固有AIがオーバーライドするフック
# --------------------------------------------------------------------------

## 戦略を決定する（サブクラスがオーバーライドする）
func _evaluate_strategy(_enemy: Character) -> Strategy:
	return Strategy.WAIT


## 攻撃対象を選択する（サブクラスがオーバーライドする）
func _select_target(_enemy: Character) -> Character:
	return _player


## 経路探索方法を選択する（サブクラスがオーバーライドする）
func _select_path_method(_enemy: Character) -> PathMethod:
	return PathMethod.ASTAR
