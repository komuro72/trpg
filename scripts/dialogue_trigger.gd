class_name DialogueTrigger
extends Node

## 会話トリガー
## プレイヤーと NPC の隣接を検出し、部屋内に敵がいなければ会話を開始する。
## 条件:
##   1. 現在エリアに生存敵がいない
##   2. プレイヤーと NPC メンバーが隣接（マンハッタン距離 1）
##   3. 会話中でない
## NPC が自発的に話しかけたいか（wants_to_initiate）も判断して通知する。

## 会話開始を要求するシグナル（npc_initiates: NPC が先に話しかけてきた場合 true）
signal dialogue_requested(npc_manager: NpcManager, npc_initiates: bool)

var _player:          Character
var _npc_managers:    Array[NpcManager]   = []
var _enemy_managers:  Array[EnemyManager] = []
var _vision_system:   VisionSystem
var _map_data:        MapData
var _dialogue_active: bool = false


func setup(player: Character, npc_managers: Array[NpcManager],
		enemy_managers: Array[EnemyManager], vision_system: VisionSystem,
		map_data: MapData) -> void:
	_player         = player
	_npc_managers   = npc_managers
	_enemy_managers = enemy_managers
	_vision_system  = vision_system
	_map_data       = map_data


## 会話アクティブ状態を設定する（game_map が会話開始/終了時に呼ぶ）
func set_dialogue_active(active: bool) -> void:
	_dialogue_active = active


## 現在のプレイヤーエリアに生存している敵がいないか確認する
func is_area_enemy_free(current_area: String) -> bool:
	if current_area.is_empty():
		return false
	for em: EnemyManager in _enemy_managers:
		if not is_instance_valid(em):
			continue
		for enemy: Character in em.get_enemies():
			if not is_instance_valid(enemy) or enemy.hp <= 0:
				continue
			if _map_data == null:
				return false
			if _map_data.get_area(enemy.grid_pos) == current_area:
				return false
	return true


func _process(_delta: float) -> void:
	if _dialogue_active or _player == null:
		return

	var current_area := _vision_system.get_current_area() if _vision_system != null else ""
	# 通路（エリアIDなし）では会話しない
	if current_area.is_empty():
		return
	# 現在エリアに生存敵がいれば会話不可
	if not is_area_enemy_free(current_area):
		return

	for nm: NpcManager in _npc_managers:
		if not is_instance_valid(nm):
			continue
		if not _has_adjacent_visible_member(nm):
			continue
		var npc_initiates := _npc_wants_to_initiate(nm)
		set_dialogue_active(true)
		dialogue_requested.emit(nm, npc_initiates)
		return


## NpcManager の生存・可視メンバーがプレイヤーに隣接しているか確認する
func _has_adjacent_visible_member(nm: NpcManager) -> bool:
	for member: Character in nm.get_members():
		if not is_instance_valid(member) or not member.visible or member.hp <= 0:
			continue
		var d := member.grid_pos - _player.grid_pos
		if abs(d.x) + abs(d.y) == 1:
			return true
	return false


## NpcLeaderAI が自発的に会話を開始したいか確認する
func _npc_wants_to_initiate(nm: NpcManager) -> bool:
	var leader_ai := nm.enemy_ai
	if leader_ai == null or not is_instance_valid(leader_ai):
		return false
	if leader_ai is NpcLeaderAI:
		return (leader_ai as NpcLeaderAI).wants_to_initiate()
	return false
