class_name UnitAI
extends Node

## 個体AI基底クラス（2層AIアーキテクチャの個体レイヤー）
## PartyLeaderAI からオーダーを受け取り、担当キャラクター1体の行動を実行する
## ステートマシン・A*経路探索・アクションキュー管理を担う
## サブクラスは _resolve_strategy() をオーバーライドして自己保存ロジックを実装する
## Phase 8: 攻撃タイプ（melee/ranged/dive）対応・飛行移動・回復/バフ行動追加

enum Strategy   { ATTACK, FLEE, WAIT }
enum PathMethod { DIRECT, ASTAR, ASTAR_FLANK }

const MOVE_INTERVAL  := 1.2  ## タイル移動の間隔・基準値（秒）。game_speed=1.0 時の標準速度
const WAIT_DURATION  := 3.0  ## wait アクションの待機時間・基準値（秒）
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
var _vision_system: VisionSystem = null       ## 探索行動（explore）に使用

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

## 指示項目（receive_order で更新）
## move_policy:      explore / same_room / cluster / guard_room / standby / spread（敵デフォルト）
## battle_formation: surround / front / rear / same_as_leader
var _move_policy:      String    = "same_room"
var _battle_formation: String    = "surround"
var _leader_ref:       Character = null  ## 隊形計算の基準となるリーダーキャラ
var _guard_room_area:  String    = ""    ## guard_room 時の記憶部屋ID（初回設定後不変）


func setup(member: Character, player: Character, map_data: MapData,
		all_members: Array[Character]) -> void:
	_member      = member
	_player      = player
	_map_data    = map_data
	_all_members = all_members
	_goal        = member.grid_pos


func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members


## VisionSystem をセットする（explore 移動方針に必要）
func set_vision_system(vs: VisionSystem) -> void:
	_vision_system = vs


## PartyLeaderAI からオーダーを受け取る
## order: { "strategy": int, "target": Character, "combat": String,
##          "move": String, "battle_formation": String, "leader": Character }
func receive_order(order: Dictionary) -> void:
	_order = order
	var ordered_strategy := order.get("strategy", Strategy.WAIT) as Strategy
	var raw_target: Variant = order.get("target", null)
	var ordered_target: Character = null
	if raw_target != null and is_instance_valid(raw_target):
		ordered_target = raw_target as Character

	# 移動方針を更新
	var new_move := order.get("move", "spread") as String
	# guard_room: 初回設定時に現在地の部屋を記憶する
	if new_move == "guard_room":
		if _guard_room_area.is_empty() and _map_data != null \
				and _member != null and is_instance_valid(_member):
			var area := _map_data.get_area(_member.grid_pos)
			if not area.is_empty():
				_guard_room_area = area
	else:
		_guard_room_area = ""
	_move_policy = new_move

	_battle_formation = order.get("battle_formation", "surround") as String

	var raw_leader: Variant = order.get("leader", null)
	if raw_leader != null and is_instance_valid(raw_leader as Object):
		_leader_ref = raw_leader as Character
	else:
		_leader_ref = null

	_ordered_strategy = ordered_strategy
	var effective_strategy := _resolve_strategy(ordered_strategy)
	var effective_target   := ordered_target

	if effective_strategy == _strategy and effective_target == _target \
			and _queue.size() >= QUEUE_MIN_LEN:
		return

	_strategy = effective_strategy
	_target   = effective_target

	var new_queue := _generate_queue(effective_strategy, effective_target)
	if new_queue.is_empty():
		return
	_queue = new_queue

	if _state != _State.ATTACKING_PRE and _state != _State.ATTACKING_POST:
		_current_action = {}
		_state = _State.IDLE
		if _member != null and is_instance_valid(_member):
			_member.is_attacking = false


## 状況変化通知（PartyLeaderAI から呼ばれる）
func notify_situation_changed() -> void:
	_reeval_timer = 0.0


## デバッグ情報を返す（RightPanel / PartyLeaderAI.get_debug_info() が収集）
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
	# プレイヤーが直接操作中のキャラクターは AI 処理をスキップする
	if _member.is_player_controlled:
		return

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
					receive_order(_order)
				else:
					_fallback_evaluate()

		_State.MOVING:
			_timer -= delta
			if _timer <= 0.0:
				var still_moving := _step_toward_goal()
				if still_moving:
					_timer = _get_move_interval()
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
				_on_after_attack()
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
			_timer = _get_move_interval()

		"move_to_formation":
			var fgoal := _formation_move_goal()
			if fgoal == _member.grid_pos:
				_complete_action()
				return
			_goal  = fgoal
			_state = _State.MOVING
			_timer = _get_move_interval()

		"move_to_explore":
			var goal_var: Variant = action.get("goal", null)
			if goal_var == null:
				_complete_action()
				return
			var goal := goal_var as Vector2i
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = _get_move_interval()

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
			_timer = _get_move_interval()

		"attack":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			var atype := _get_attack_type()
			if not _can_attack_target(_target, atype):
				_complete_action()
				return
			_attack_target = _target
			_state = _State.ATTACKING_PRE
			_timer = _member.character_data.pre_delay if _member.character_data else 0.3
			_member.is_attacking = true

		"move_to_heal", "move_to_buff":
			var tgt_var: Variant = action.get("target", null)
			if tgt_var == null or not is_instance_valid(tgt_var as Object):
				_complete_action()
				return
			var tgt := tgt_var as Character
			var range_val := _member.character_data.attack_range if _member.character_data else 1
			if _manhattan(_member.grid_pos, tgt.grid_pos) <= range_val:
				_complete_action()
				return
			var goal := _find_adjacent_goal(tgt)
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = _get_move_interval()

		"heal":
			var tgt_var: Variant = action.get("target", null)
			if tgt_var == null or not is_instance_valid(tgt_var as Object):
				_complete_action()
				return
			var tgt := tgt_var as Character
			var range_val := _member.character_data.attack_range if _member.character_data else 1
			if _manhattan(_member.grid_pos, tgt.grid_pos) > range_val:
				_complete_action()
				return
			# 回復実行
			var cost := _member.character_data.heal_mp_cost if _member.character_data else 0
			if _member.use_mp(cost):
				var power := _member.character_data.magic_power if _member.character_data else 0
				tgt.heal(power)
				SoundManager.play(SoundManager.HEAL)
			_state = _State.WAITING
			_timer = _member.character_data.post_delay if _member.character_data else 0.5

		"buff":
			var tgt_var: Variant = action.get("target", null)
			if tgt_var == null or not is_instance_valid(tgt_var as Object):
				_complete_action()
				return
			var tgt := tgt_var as Character
			var range_val := _member.character_data.attack_range if _member.character_data else 1
			if _manhattan(_member.grid_pos, tgt.grid_pos) > range_val:
				_complete_action()
				return
			# バフ付与
			var cost := _member.character_data.buff_mp_cost if _member.character_data else 0
			if _member.use_mp(cost):
				tgt.apply_defense_buff()
			_state = _State.WAITING
			_timer = _member.character_data.post_delay if _member.character_data else 0.5

		"wait":
			_state = _State.WAITING
			_timer = WAIT_DURATION / GlobalConstants.game_speed

		_:
			_complete_action()


## 目標に向かって1タイル進む。移動継続中なら true、到達またはスタックなら false
func _step_toward_goal() -> bool:
	var action_type := _current_action.get("action", "") as String
	if action_type == "move_to_formation":
		_goal = _formation_move_goal()
	elif action_type == "move_to_explore":
		pass  # goal は _start_action で固定済み（リアルタイム更新しない）
	elif _target != null and is_instance_valid(_target):
		if action_type == "move_to_attack":
			_goal = _calc_attack_goal(_target, _get_path_method())
		elif action_type == "flee":
			_goal = _find_flee_goal(_target)

	if _member.grid_pos == _goal:
		return false

	var next := _get_next_step(_goal)
	if next != _member.grid_pos:
		_member.move_to(next, _get_move_interval())
		return _member.grid_pos != _goal

	return false


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
	# 回復・バフ行動は戦略に関わらず最優先でキューに積む
	var heal_q := _generate_heal_queue()
	if not heal_q.is_empty():
		return heal_q
	var buff_q := _generate_buff_queue()
	if not buff_q.is_empty():
		return buff_q

	match strategy:
		Strategy.ATTACK:
			if target == null or not is_instance_valid(target):
				return [{"action": "wait"}]
			var atype := _get_attack_type()
			# standby: 隣接のみ攻撃、移動しない（ranged/dive は射程内なら攻撃）
			if _move_policy == "standby":
				if _can_attack_target(target, atype):
					return [{"action": "attack"}]
				return [{"action": "wait"}]
			# 隊形が満たされていない場合はリーダーに向かってから攻撃
			if not _formation_satisfied():
				var q: Array = []
				for _i: int in range(3):
					q.append({"action": "move_to_formation"})
				q.append({"action": "wait"})
				return q
			# ターゲットが隊形ゾーン外にいる場合は追わない
			if not _target_in_formation_zone(target):
				return [{"action": "wait"}]
			# explore/spread は長いキューで頻繁な再評価を抑制
			var repeat := 4 if (_move_policy == "spread" or _move_policy == "explore") else 1
			var q: Array = []
			for _i: int in range(repeat):
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
			match _move_policy:
				"explore":
					return _generate_explore_queue()
				"standby":
					return [{"action": "wait"}]
				_:
					if not _formation_satisfied():
						return [{"action": "move_to_formation"}, {"action": "wait"}]
					return [{"action": "wait"}]

	return [{"action": "wait"}]


## 探索行動キューを生成する（move_policy == "explore" 時に使用）
func _generate_explore_queue() -> Array:
	var target_pos := _find_explore_target()
	if target_pos == Vector2i(-1, -1) or target_pos == _member.grid_pos:
		return [{"action": "wait"}]
	return [{"action": "move_to_explore", "goal": target_pos}]


## 探索目標タイルを選ぶ
## 未訪問エリアがあればその最近傍タイル、全訪問済みならランダムエリアのタイル
func _find_explore_target() -> Vector2i:
	if _map_data == null:
		return Vector2i(-1, -1)
	var all_areas := _map_data.get_all_area_ids()
	if all_areas.is_empty():
		return Vector2i(-1, -1)

	# 未訪問エリアを収集
	var unvisited: Array[String] = []
	for area_id: String in all_areas:
		if _vision_system == null or not _vision_system.is_area_visited(area_id):
			unvisited.append(area_id)

	if unvisited.is_empty():
		# 全訪問済み → ランダムなエリアを巡回
		var random_area := all_areas[randi() % all_areas.size()]
		var tiles := _map_data.get_tiles_in_area(random_area)
		if tiles.is_empty():
			return Vector2i(-1, -1)
		return tiles[randi() % tiles.size()]

	# 最近傍の未訪問エリアを選ぶ（各エリアの代表タイルで判定）
	var best_pos  := Vector2i(-1, -1)
	var best_dist := 999999
	for area_id: String in unvisited:
		var tiles := _map_data.get_tiles_in_area(area_id)
		if tiles.is_empty():
			continue
		# エリア内の中央付近のタイルを代表とする
		var mid := tiles[tiles.size() / 2]
		var d   := _manhattan(_member.grid_pos, mid)
		if d < best_dist and d > 0:
			best_dist = d
			best_pos  = mid
	return best_pos


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
	var atype := _get_attack_type()
	# magic attack_type は magic_power を使用。それ以外は attack_power
	var dmg_power := _member.magic_power if atype == "magic" else _member.attack_power
	match atype:
		"ranged", "magic":
			# 遠距離攻撃（物理弓/魔法）：飛翔体を生成して命中確定ダメージ
			_member.face_toward(_attack_target.grid_pos)
			SoundManager.play_attack(_member)
			var map_node := _member.get_parent()
			if map_node != null:
				var proj := Projectile.new()
				proj.z_index = 2
				map_node.add_child(proj)
				proj.setup(_member.position, _attack_target.position,
						true, _attack_target, dmg_power, 1.0)
		"dive":
			# 降下攻撃：方向倍率なし（飛行中の奇襲）、降下エフェクト表示
			SoundManager.play_attack(_member)
			_attack_target.take_damage(dmg_power, 1.0, _member)
			SoundManager.play_hit(_member)
			_spawn_dive_effect()
		_:
			# melee（近接攻撃）
			SoundManager.play_attack(_member)
			var multiplier := Character.get_direction_multiplier(_member, _attack_target)
			_attack_target.take_damage(dmg_power, multiplier, _member)
			SoundManager.play_hit(_member)


## 降下攻撃エフェクトを生成する（簡易：黄色→白のフラッシュ円）
func _spawn_dive_effect() -> void:
	var map_node := _member.get_parent()
	if map_node == null:
		return
	var effect := DiveEffect.new()
	effect.position = _member.position
	map_node.add_child(effect)


# --------------------------------------------------------------------------
# 目標座標計算
# --------------------------------------------------------------------------

func _calc_attack_goal(target: Character, method: PathMethod) -> Vector2i:
	var atype := _get_attack_type()
	if atype == "ranged" or atype == "magic":
		# 遠距離（物理/魔法）：射程内ならその場で攻撃。射程外なら射程内の最近傍タイルへ
		var range_val := _member.character_data.attack_range if _member.character_data else 5
		var dist := _manhattan(_member.grid_pos, target.grid_pos)
		if dist <= range_val:
			return _member.grid_pos
		return _find_ranged_goal(target, range_val)
	if method == PathMethod.ASTAR_FLANK:
		return _find_flank_goal(target)
	return _find_adjacent_goal(target)


## 遠距離攻撃用：ターゲットから range_val タイル以内で最近傍の通行可能タイルを返す
func _find_ranged_goal(target: Character, range_val: int) -> Vector2i:
	var best      := _member.grid_pos
	var best_dist := 999999
	var r := range_val
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var candidate := target.grid_pos + Vector2i(dx, dy)
			if _manhattan(candidate, target.grid_pos) > r:
				continue
			if not _is_passable(candidate):
				continue
			var d := _manhattan(_member.grid_pos, candidate)
			if d < best_dist:
				best_dist = d
				best      = candidate
	return best


## ターゲットに隣接する最近傍の空きタイルを返す（他のキャラが占有していないもの）
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
# 移動方針（move_policy）ロジック
# --------------------------------------------------------------------------

## 現在の移動方針制約が満たされているか確認する
func _formation_satisfied() -> bool:
	match _move_policy:
		"spread", "standby", "explore":
			return true
		"cluster":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			return _manhattan(_member.grid_pos, _leader_ref.grid_pos) <= 5
		"same_room":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			if _map_data == null:
				return true
			var my_area     := _map_data.get_area(_member.grid_pos)
			var leader_area := _map_data.get_area(_leader_ref.grid_pos)
			if my_area.is_empty() or leader_area.is_empty():
				return true
			return my_area == leader_area
		"guard_room":
			if _guard_room_area.is_empty() or _map_data == null:
				return true
			var my_area := _map_data.get_area(_member.grid_pos)
			return my_area == _guard_room_area
	return true


## ターゲットが移動方針ゾーン内にいるか確認する（ゾーン外の敵は追わない）
func _target_in_formation_zone(target: Character) -> bool:
	match _move_policy:
		"spread", "explore":
			return true
		"standby":
			# 待機中は隣接マスの敵のみ攻撃
			var dv := target.grid_pos - _member.grid_pos
			return abs(dv.x) + abs(dv.y) <= 1
		"cluster":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			var attack_goal := _find_adjacent_goal(target)
			return _manhattan(attack_goal, _leader_ref.grid_pos) <= 5
		"same_room":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			if _map_data == null:
				return true
			var target_area: String = _map_data.get_area(target.grid_pos)
			var leader_area: String = _map_data.get_area(_leader_ref.grid_pos)
			if target_area.is_empty() or leader_area.is_empty():
				return true
			return target_area == leader_area
		"guard_room":
			if _guard_room_area.is_empty() or _map_data == null:
				return true
			var target_area: String = _map_data.get_area(target.grid_pos)
			return target_area == _guard_room_area
	return true


## 移動方針ゴール：制約を満たすための目標タイルを返す
func _formation_move_goal() -> Vector2i:
	match _move_policy:
		"guard_room":
			# 守る部屋に戻る（最近傍タイル）
			if not _guard_room_area.is_empty() and _map_data != null:
				var tiles := _map_data.get_tiles_in_area(_guard_room_area)
				if not tiles.is_empty():
					var best      := tiles[0]
					var best_dist := _manhattan(_member.grid_pos, best)
					for t: Vector2i in tiles:
						var dist := _manhattan(_member.grid_pos, t)
						if dist < best_dist:
							best_dist = dist
							best      = t
					return best
			return _member.grid_pos
		_:
			# cluster / same_room → リーダーの隣接タイルへ
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return _member.grid_pos
			return _find_adjacent_goal(_leader_ref)


# --------------------------------------------------------------------------
# 通行可能チェック
# --------------------------------------------------------------------------

func _is_passable(pos: Vector2i) -> bool:
	if _map_data != null and not _map_data.is_walkable_for(pos, _member.is_flying):
		return false
	# 飛行キャラは地上キャラの占有タイルを通過できる（同レイヤーのみブロック）
	for other: Character in _all_members:
		if not is_instance_valid(other):
			continue
		if other == _member:
			continue
		# 飛行同士はブロックし合う。地上同士もブロックし合う。飛行↔地上は通過可能
		if other.is_flying != _member.is_flying:
			continue
		if pos in other.get_occupied_tiles():
			return false
	# _player == _member の場合（hero の自己AI）は自分のタイルをブロックしない
	if _player != null and is_instance_valid(_player) and _player != _member:
		if _player.is_flying == _member.is_flying and pos in _player.get_occupied_tiles():
			return false
	return true


# --------------------------------------------------------------------------
# 攻撃タイプヘルパー
# --------------------------------------------------------------------------

## キャラデータの attack_type を返す（未設定時は "melee"）
func _get_attack_type() -> String:
	if _member != null and _member.character_data != null:
		return _member.character_data.attack_type
	return "melee"


## 指定ターゲットに攻撃タイプで攻撃可能か判定する
## melee: 隣接かつターゲットが地上（飛行→地上OK、地上→飛行NG、飛行→飛行NG）
## ranged: 射程内かつ double-layer 無関係
## dive:  隣接かつターゲットが地上（地上→飛行NG。飛行→飛行NGは仕様）
func _can_attack_target(target: Character, atype: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	match atype:
		"ranged", "magic":
			var range_val := _member.character_data.attack_range if _member.character_data else 5
			return _manhattan(_member.grid_pos, target.grid_pos) <= range_val
		"dive":
			# 降下攻撃：飛行キャラが地上キャラに隣接して攻撃（ターゲットは地上のみ）
			if target.is_flying:
				return false
			var d := target.grid_pos - _member.grid_pos
			return abs(d.x) + abs(d.y) == 1
		_:  # melee
			# 地上→飛行・飛行→飛行は不可
			if target.is_flying:
				return false
			var d := target.grid_pos - _member.grid_pos
			return abs(d.x) + abs(d.y) == 1


# --------------------------------------------------------------------------
# 回復・バフキュー生成
# --------------------------------------------------------------------------

## 回復行動キューを返す。回復すべき状況でなければ空配列
func _generate_heal_queue() -> Array:
	if _member == null or _member.character_data == null:
		return []
	if _member.character_data.magic_power <= 0:
		return []
	var cost := _member.character_data.heal_mp_cost
	if _member.mp < cost:
		return []
	# パーティーメンバーで HP50% 以下のキャラを探す
	var heal_target := _find_heal_target()
	if heal_target == null:
		return []
	return [{"action": "move_to_heal", "target": heal_target},
			{"action": "heal", "target": heal_target}]


## バフ行動キューを返す。バフを付与すべき状況でなければ空配列
func _generate_buff_queue() -> Array:
	if _member == null or _member.character_data == null:
		return []
	if _member.character_data.buff_mp_cost <= 0:
		return []
	if _member.mp < _member.character_data.buff_mp_cost:
		return []
	# バフが切れているパーティーメンバーを探す
	var buff_target := _find_buff_target()
	if buff_target == null:
		return []
	return [{"action": "move_to_buff", "target": buff_target},
			{"action": "buff", "target": buff_target}]


## 回復対象（パーティー内で HP50% 以下かつ最もHPが低いキャラ）を返す
func _find_heal_target() -> Character:
	var best: Character = null
	var best_ratio := 0.51  # 50% 以下のみ対象
	for ch: Character in _all_members:
		if not is_instance_valid(ch) or ch.hp <= 0:
			continue
		if not ch.is_friendly:
			continue
		var ratio := float(ch.hp) / float(maxi(ch.max_hp, 1))
		if ratio < best_ratio:
			best_ratio = ratio
			best = ch
	return best


## バフ対象（パーティー内でバフが切れているキャラ）を返す
func _find_buff_target() -> Character:
	for ch: Character in _all_members:
		if not is_instance_valid(ch) or ch.hp <= 0:
			continue
		if not ch.is_friendly:
			continue
		if ch.defense_buff_timer <= 0.0:
			return ch
	return null


# --------------------------------------------------------------------------
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	return ordered_strategy


func _evaluate_strategy() -> Strategy:
	return Strategy.WAIT


func _select_target() -> Character:
	return _player


## 戦闘隊形（battle_formation）に基づいて経路探索方法を選択する
func _get_path_method() -> PathMethod:
	match _battle_formation:
		"rear": return PathMethod.ASTAR_FLANK
		_:      return PathMethod.ASTAR


## 移動間隔（秒/タイル）。サブクラスで上書きして速度変更可能
## zombie=遅い(MOVE_INTERVAL*2.0) / wolf=速い(MOVE_INTERVAL*0.67) など
## GlobalConstants.game_speed で割ることで設定画面の速度変更に対応する
func _get_move_interval() -> float:
	return MOVE_INTERVAL / GlobalConstants.game_speed


## 攻撃実行後に呼ばれるフック。MP消費などはここで行う（サブクラスでオーバーライド）
func _on_after_attack() -> void:
	pass
