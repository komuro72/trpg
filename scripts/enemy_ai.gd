class_name EnemyAI
extends Node

## 敵パーティーのAI行動制御
## Phase 2-3: LLMにパーティー単位で状況を送り、行動シーケンスをキューに積む。
## Phase 2-4: pop_next_action() / complete_action() を使って実際の移動・攻撃を実行する。

## キューがこの数以下になったら再リクエスト
const QUEUE_REFILL_THRESHOLD := 1

var _enemies: Array[Character] = []
var _player: Character
var _behavior_description: String = ""

var _llm: LLMClient

## メンバーIDごとのアクションキュー { "Goblin0": [{action, target, ...}, ...] }
var _queues: Dictionary = {}
## 現在実行中のアクション { "Goblin0": {action, target, ...} }
var _current: Dictionary = {}

## 攻撃されたなど状況が大きく変わったときに true にする
var _force_regen: bool = false


## アクティブ化後に EnemyManager から呼び出す
func setup(enemies: Array[Character], player: Character, behavior_description: String) -> void:
	_enemies           = enemies
	_player            = player
	_behavior_description = behavior_description

	_llm = LLMClient.new()
	_llm.name = "LLMClient"
	add_child(_llm)
	_llm.response_received.connect(_on_response_received)
	_llm.request_failed.connect(_on_request_failed)

	_request_actions()


func _process(_delta: float) -> void:
	if _enemies.is_empty():
		return

	# 強制再生成（攻撃を受けたなど状況変化）
	if _force_regen and not _llm.is_requesting:
		_force_regen = false
		_request_actions()
		return

	# キューが残り少なくなったら補充リクエスト
	if not _llm.is_requesting and _is_queue_low():
		_request_actions()


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
		"party":             {"members": members},
		"visible_characters": visible,
		"current_actions":   _current.duplicate(),
		"remaining_queue":   remaining
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
		var e       := entry as Dictionary
		var id      := e.get("id", "") as String
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
## Phase 2-4 から呼び出すインターフェース
## -------------------------------------------------------------------

## 次のアクションをキューから取り出す（なければ空 Dictionary）
func pop_next_action(enemy_id: String) -> Dictionary:
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
