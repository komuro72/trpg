class_name EnemyManager
extends Node

## 敵の生成・アクティブ化・視界管理を担う
## Phase 2-2: マップJSONの配置情報に基づいてスポーン。
## Phase 2-3: アクティブ化後にルールベースAIを起動する（LLM不使用）。
## Phase 5:   VisionSystem と連携してエリア単位の視界管理を行う。

## プレイヤーがこのマス数（ユークリッド距離）以内に入ったらアクティブ化（距離フォールバック用）
const ACTIVATION_RANGE: int = 5

var enemy_party: Party
var enemy_ai: BaseAI
var _player: Character
var _enemies: Array[Character] = []
var _activated: bool = false
var _map_data: MapData

## VisionSystemが接続されている場合はtrue（距離ベースのアクティブ化を無効化）
var _vision_controlled: bool = false

## 全パーティー合算の敵リスト（BaseAI._is_passable の占有チェックに使用）
## game_map が全 EnemyManager 生成後に set_all_enemies() で設定する
var _all_enemies: Array[Character] = []


func set_vision_controlled(enabled: bool) -> void:
	_vision_controlled = enabled


## 全パーティー合算の敵リストを設定する（game_map が全 EnemyManager 生成後に呼び出す）
func set_all_enemies(all_enemies: Array[Character]) -> void:
	_all_enemies = all_enemies
	# すでに AI が起動済みの場合は即座に反映する
	if enemy_ai != null:
		enemy_ai.set_all_enemies(all_enemies)


## 敵をスポーンしてパーティーを構成する
## spawn_list: [{character_id, x, y}] の配列（dungeon_01.json の enemy_parties[n].members）
func setup(spawn_list: Array, player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	enemy_party = Party.new()
	for spawn_info: Variant in spawn_list:
		var info := spawn_info as Dictionary
		# "enemy_id"（生成マップ）と "character_id"（静的マップ）の両方に対応
		var char_id: String = info.get("enemy_id", info.get("character_id", ""))
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


## 毎フレーム距離チェック。VisionSystem未使用時のフォールバック
func _process(_delta: float) -> void:
	if _activated or _player == null or _enemies.is_empty() or _vision_controlled:
		return
	for enemy: Character in _enemies:
		if float((enemy.grid_pos - _player.grid_pos).length()) <= float(ACTIVATION_RANGE):
			_activated = true
			_start_ai()
			break


## VisionSystemから呼び出される：訪問済みエリアに基づいて敵の表示を更新する
## visited_areas: { area_id: String -> true } プレイヤーパーティーの訪問済みエリア集合
func update_visibility(player_area: String, map_data: MapData, visited_areas: Dictionary) -> void:
	for enemy: Character in _enemies:
		if not is_instance_valid(enemy):
			continue
		var enemy_area := map_data.get_area(enemy.grid_pos)
		# エリア情報がない場合（静的マップ等）は常に表示
		if enemy_area.is_empty():
			enemy.visible = true
		else:
			# 訪問済みエリアの敵は表示（一度見たら消えない）
			enemy.visible = visited_areas.has(enemy_area)
		# AI アクティブ化：プレイヤーと同じエリアに初めて入ったとき
		var in_same_area := not player_area.is_empty() and player_area == enemy_area
		if in_same_area and not _activated:
			_activated = true
			_start_ai()


## 敵種別に応じたルールベースAIを生成して起動する
func _start_ai() -> void:
	if _enemies.is_empty():
		return

	# character_id の先頭で種別判定（Phase 6以降で種類が増えたら拡張する）
	var char_id := ""
	if _enemies[0].character_data != null:
		char_id = _enemies[0].character_data.character_id

	var ai_node: BaseAI
	if char_id.begins_with("goblin") or char_id.is_empty():
		ai_node = GoblinAI.new()
		ai_node.name = "GoblinAI"
	else:
		# 未対応の敵種は GoblinAI をデフォルトとして使用（Phase 6で随時追加）
		ai_node = GoblinAI.new()
		ai_node.name = "GoblinAI"

	enemy_ai = ai_node
	add_child(enemy_ai)
	enemy_ai.setup(_enemies, _player, _map_data)
	# 全パーティー合算リストが設定済みなら AI に渡す
	if not _all_enemies.is_empty():
		enemy_ai.set_all_enemies(_all_enemies)


## 敵リストへの参照を返す
func get_enemies() -> Array[Character]:
	return _enemies


func _on_enemy_died(character: Character) -> void:
	_enemies.erase(character)
	enemy_party.remove_member(character)
	# 仲間が倒されたことを AI に通知して即座に戦略を再評価させる
	if enemy_ai != null:
		enemy_ai.notify_situation_changed()
