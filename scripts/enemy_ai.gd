class_name EnemyAI
extends Node

## 敵パーティーのAI行動制御
## Phase 2-3: LLMにパーティー単位で状況を送り、行動シーケンスをキューに積む。
## Phase 2-4: キューからアクションを取り出し、移動・待機を実行する（move / wait）。

const QUEUE_REFILL_THRESHOLD := 1
const MOVE_INTERVAL  := 0.4   # タイル移動の間隔（秒）
const WAIT_DURATION  := 1.0   # wait アクションの待機時間（秒）

enum _State { IDLE, MOVING, WAITING }

var _enemies: Array[Character] = []
var _player: Character
var _map_data: MapData
var _behavior_description: String = ""
var _llm: LLMClient

## メンバーIDごとのアクションキュー { "Goblin0": [{action, ...}, ...] }
var _queues: Dictionary = {}
## 現在実行中のアクション { "Goblin0": {action, ...} }
var _current: Dictionary = {}

## 各敵のステートマシン状態
var _states: Dictionary = {}   # enemy_id -> _State
## 移動中の目標グリッド座標
var _goals: Dictionary = {}    # enemy_id -> Vector2i
## タイマー（移動間隔 / 待機時間）
var _timers: Dictionary = {}   # enemy_id -> float

var _force_regen: bool = false


## アクティブ化後に EnemyManager から呼び出す
func setup(enemies: Array[Character], player: Character, behavior_description: String, map_data: MapData) -> void:
	_enemies              = enemies
	_player               = player
	_map_data             = map_data
	_behavior_description = behavior_description

	for enemy: Character in _enemies:
		_states[enemy.name] = _State.IDLE
		_timers[enemy.name] = 0.0

	_llm = LLMClient.new()
	_llm.name = "LLMClient"
	add_child(_llm)
	_llm.response_received.connect(_on_response_received)
	_llm.request_failed.connect(_on_request_failed)

	_request_actions()


func _process(delta: float) -> void:
	if _enemies.is_empty():
		return

	# 各敵のアクションを処理
	for enemy: Character in _enemies:
		_tick_enemy(enemy, delta)

	# 強制再生成（攻撃を受けたなど状況変化）
	if _force_regen and not _llm.is_requesting:
		_force_regen = false
		_request_actions()
		return

	# キューが残り少なくなったら補充リクエスト
	if not _llm.is_requesting and _is_queue_low():
		_request_actions()


## -------------------------------------------------------------------
## アクション実行（ステートマシン）
## -------------------------------------------------------------------

func _tick_enemy(enemy: Character, delta: float) -> void:
	var id    := enemy.name
	var state := _states.get(id, _State.IDLE) as _State

	match state:
		_State.IDLE:
			var action := _pop_action(id)
			if not action.is_empty():
				_start_action(enemy, action)

		_State.MOVING:
			_timers[id] -= delta
			if _timers[id] <= 0.0:
				var still_moving := _step_toward_goal(enemy)
				if still_moving:
					_timers[id] = MOVE_INTERVAL
				else:
					_states[id] = _State.IDLE
					complete_action(id)

		_State.WAITING:
			_timers[id] -= delta
			if _timers[id] <= 0.0:
				_states[id] = _State.IDLE
				complete_action(id)


func _start_action(enemy: Character, action: Dictionary) -> void:
	var id := enemy.name
	match action.get("action", "") as String:
		"move":
			var goal := _resolve_goal(enemy, action)
			if goal == enemy.grid_pos:
				complete_action(id)
				return
			_goals[id]  = goal
			_states[id] = _State.MOVING
			_timers[id] = MOVE_INTERVAL
		"wait":
			_states[id] = _State.WAITING
			_timers[id] = WAIT_DURATION
		_:
			# attack 等は Phase 2-4 後半で実装。今は完了扱い
			complete_action(id)


## target と relative_position から目標グリッド座標を計算する
func _resolve_goal(enemy: Character, action: Dictionary) -> Vector2i:
	if _player == null:
		return enemy.grid_pos
	var rel    := action.get("relative_position", "adjacent") as String
	var offset := _relative_offset(_player.facing, rel)
	var goal   := _player.grid_pos + offset

	# 目標が歩行不可なら隣接タイルを探す
	if _map_data != null and not _map_data.is_walkable(goal):
		for adj: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var alt := _player.grid_pos + adj
			if _map_data.is_walkable(alt):
				return alt

	return goal


## 目標方向へ1タイル進む。まだ移動中なら true、到達またはスタックなら false
func _step_toward_goal(enemy: Character) -> bool:
	var id   := enemy.name
	var goal := _goals.get(id, enemy.grid_pos) as Vector2i
	if enemy.grid_pos == goal:
		return false

	var dx := goal.x - enemy.grid_pos.x
	var dy := goal.y - enemy.grid_pos.y

	# 差が大きい軸を優先して試みる
	var candidates: Array[Vector2i] = []
	if abs(dx) >= abs(dy):
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
	else:
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))

	for step: Vector2i in candidates:
		var next := enemy.grid_pos + step
		if _is_passable(next):
			enemy.move_to(next)
			return enemy.grid_pos != goal  # 到達したら false

	return false  # スタック（壁や他キャラで塞がれている）


## 歩行可能かつ他キャラが占有していないか確認する
## get_occupied_tiles() を使うため将来の複数マスキャラにも対応
func _is_passable(pos: Vector2i) -> bool:
	if _map_data != null and not _map_data.is_walkable(pos):
		return false
	for other: Character in _enemies:
		if pos in other.get_occupied_tiles():
			return false
	if _player != null and pos in _player.get_occupied_tiles():
		return false
	return true


## target の向きを基準に relative_position のオフセットを返す
func _relative_offset(facing: Character.Direction, rel_pos: String) -> Vector2i:
	var fwd := _dir_to_vec(facing)
	match rel_pos:
		"front":      return fwd
		"back":       return Vector2i(-fwd.x, -fwd.y)
		"left_side":
			match facing:
				Character.Direction.FRONT: return Vector2i(-1,  0)
				Character.Direction.BACK:  return Vector2i( 1,  0)
				Character.Direction.RIGHT: return Vector2i( 0, -1)
				Character.Direction.LEFT:  return Vector2i( 0,  1)
		"right_side":
			match facing:
				Character.Direction.FRONT: return Vector2i( 1,  0)
				Character.Direction.BACK:  return Vector2i(-1,  0)
				Character.Direction.RIGHT: return Vector2i( 0,  1)
				Character.Direction.LEFT:  return Vector2i( 0, -1)
		"adjacent":   return fwd
	return Vector2i.ZERO


func _dir_to_vec(dir: Character.Direction) -> Vector2i:
	match dir:
		Character.Direction.FRONT: return Vector2i( 0,  1)
		Character.Direction.BACK:  return Vector2i( 0, -1)
		Character.Direction.LEFT:  return Vector2i(-1,  0)
		Character.Direction.RIGHT: return Vector2i( 1,  0)
	return Vector2i.ZERO


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


## 攻撃を受けたなど状況が大きく変わったときに呼び出す
func notify_situation_changed() -> void:
	_force_regen = true


## -------------------------------------------------------------------
## LLM リクエスト構築
## -------------------------------------------------------------------

func _request_actions() -> void:
	if _enemies.is_empty():
		return
	var situation := _build_situation()
	var prompt    := _build_prompt(situation)
	_llm.request(prompt)


func _build_situation() -> Dictionary:
	var members: Array = []
	for enemy: Character in _enemies:
		members.append({
			"id":        enemy.name,
			"position":  {"x": enemy.grid_pos.x, "y": enemy.grid_pos.y},
			"facing":    _dir_to_str(enemy.facing),
			"hp":        enemy.hp,
			"condition": _condition(enemy),
			"status":    (_current.get(enemy.name, {}) as Dictionary).get("action", "ready")
		})

	var visible: Array = []
	if _player != null:
		visible.append({
			"type":      "player",
			"position":  {"x": _player.grid_pos.x, "y": _player.grid_pos.y},
			"facing":    _dir_to_str(_player.facing),
			"hp":        _player.hp,
			"condition": _condition(_player)
		})

	var remaining: Array = []
	for enemy: Character in _enemies:
		var q: Array = _queues.get(enemy.name, [])
		if not q.is_empty():
			remaining.append({"id": enemy.name, "queue": q.duplicate()})

	return {
		"party":              {"members": members},
		"visible_characters": visible,
		"current_actions":    _current.duplicate(),
		"remaining_queue":    remaining
	}


func _build_prompt(situation: Dictionary) -> String:
	var p := "あなたはタクティクスRPGの敵AIです。\n"
	p += "キャラクターの行動傾向: " + _behavior_description + "\n\n"
	p += "現在の状況:\n" + JSON.stringify(situation, "  ") + "\n\n"
	p += "上記の状況を踏まえて、各メンバーの行動シーケンスをJSONで返してください。\n"
	p += "relative_position の種類: front / back / left_side / right_side / adjacent\n"
	p += "説明文は不要です。以下の形式のJSONのみ返してください:\n"
	p += '{"actions":[{"id":"...","sequence":[{"action":"move"|"attack"|"wait","target":"player","relative_position":"...（moveのみ）","attack_type":"physical"（attackのみ）}]}]}'
	return p


## -------------------------------------------------------------------
## LLM レスポンス処理
## -------------------------------------------------------------------

func _on_response_received(result: Dictionary) -> void:
	var actions: Array = result.get("actions", [])
	for entry: Variant in actions:
		var e        := entry as Dictionary
		var id       := e.get("id", "") as String
		var sequence: Array = e.get("sequence", [])
		if id.is_empty() or sequence.is_empty():
			continue
		if not _queues.has(id):
			_queues[id] = []
		(_queues[id] as Array).append_array(sequence)

	print("[EnemyAI] キュー更新: ", _queues)


func _on_request_failed(error: String) -> void:
	push_error("[EnemyAI] LLMリクエスト失敗: " + error)


## -------------------------------------------------------------------
## ユーティリティ
## -------------------------------------------------------------------

func _is_queue_low() -> bool:
	for enemy: Character in _enemies:
		if (_queues.get(enemy.name, []) as Array).size() <= QUEUE_REFILL_THRESHOLD:
			return true
	return false


func _condition(c: Character) -> String:
	var ratio := float(c.hp) / float(c.max_hp)
	if ratio > 0.6:
		return "healthy"
	elif ratio > 0.3:
		return "wounded"
	return "critical"


func _dir_to_str(dir: Character.Direction) -> String:
	match dir:
		Character.Direction.FRONT: return "front"
		Character.Direction.BACK:  return "back"
		Character.Direction.LEFT:  return "left"
		Character.Direction.RIGHT: return "right"
	return "front"
