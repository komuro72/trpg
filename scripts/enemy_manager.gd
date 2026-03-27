class_name EnemyManager
extends Node

## 敵の生成・アクティブ化を管理する
## Phase 2-2: マップJSONの配置情報に基づいてスポーン。プレイヤーが近づいたらアクティブ化。
## Phase 2-3: アクティブ化後に EnemyAI を起動してLLMによる行動生成を開始する。

## プレイヤーがこのマス数（ユークリッド距離）以内に入ったらアクティブ化
const ACTIVATION_RANGE: int = 5

var enemy_party: Party
var enemy_ai: EnemyAI
var _player: Character
var _enemies: Array[Character] = []
var _activated: bool = false


var _map_data: MapData


## 敵をスポーンしてパーティーを構成する
## spawn_list: [{character_id, x, y}] の配列（dungeon_01.json の enemy_parties[n].members）
func setup(spawn_list: Array, player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	enemy_party = Party.new()
	for spawn_info: Variant in spawn_list:
		var info := spawn_info as Dictionary
		var char_id: String = info.get("character_id", "")
		var pos := Vector2i(int(info.get("x", 0)), int(info.get("y", 0)))
		var enemy := _spawn_enemy(char_id, pos)
		enemy_party.add_member(enemy)
		_enemies.append(enemy)


func _spawn_enemy(char_id: String, grid_pos: Vector2i) -> Character:
	var enemy := Character.new()
	enemy.grid_pos = grid_pos
	enemy.placeholder_color = Color(1.0, 0.4, 0.2)  # オレンジ（仮素材）
	enemy.character_data = CharacterData.load_from_json(
		"res://assets/master/enemies/" + char_id + ".json"
	)
	enemy.name = char_id.capitalize() + str(_enemies.size())
	get_parent().add_child(enemy)
	enemy.sync_position()
	enemy.died.connect(_on_enemy_died)
	return enemy


## 毎フレーム距離チェック。未アクティブ時のみ実行
func _process(_delta: float) -> void:
	if _activated or _player == null or _enemies.is_empty():
		return
	for enemy: Character in _enemies:
		if float((enemy.grid_pos - _player.grid_pos).length()) <= float(ACTIVATION_RANGE):
			_activated = true
			_start_ai()
			break


## EnemyAI を生成してLLMによる行動生成を開始する
func _start_ai() -> void:
	var behavior := ""
	if not _enemies.is_empty() and _enemies[0].character_data != null:
		behavior = _enemies[0].character_data.behavior_description

	enemy_ai = EnemyAI.new()
	enemy_ai.name = "EnemyAI"
	add_child(enemy_ai)
	enemy_ai.setup(_enemies, _player, behavior, _map_data)


## 敵リストへの参照を返す（PlayerController の blocking_characters 等で利用）
## 配列は参照渡しなので敵が死亡して _enemies から削除されると自動で反映される
func get_enemies() -> Array[Character]:
	return _enemies


func _on_enemy_died(character: Character) -> void:
	_enemies.erase(character)
	enemy_party.remove_member(character)
