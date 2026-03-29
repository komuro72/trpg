class_name PartyManager
extends Node

## パーティーマネージャー（敵・NPC・プレイヤーパーティー共通）
## 旧 EnemyManager を汎用化したクラス
## リーダーAI（PartyLeaderAI）+ 個体AI（UnitAI）の2層構造でAIを管理する
##
## 利用可能な party_type: "enemy" / "npc" / "player"

## VisionSystem 未接続時の距離ベースアクティブ化しきい値
const ACTIVATION_RANGE: int = 5

## パーティー種別
var party_type: String = "enemy"

## RightPanel / vision_system からのアクセスに使用する後方互換プロパティ
## BaseAI 時代の enemy_ai に相当。PartyLeaderAI を返す
var enemy_ai: PartyLeaderAI:
	get: return _leader_ai

var _members:    Array[Character] = []
var _leader:     Character
var _leader_ai:  PartyLeaderAI
var _player:     Character
var _map_data:   MapData
var _activated:  bool = false
var _vision_controlled: bool = false
var _all_members: Array[Character] = []  ## 全パーティー合算（AI 起動時に渡す）


## VisionSystem から呼ばれる。true なら距離ベースのアクティブ化を無効にする
func set_vision_controlled(enabled: bool) -> void:
	_vision_controlled = enabled


## 全パーティー合算メンバーリストを設定する（game_map が全マネージャー生成後に呼ぶ）
func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members
	if _leader_ai != null:
		_leader_ai.set_all_members(all_members)


## 後方互換エイリアス（game_map が set_all_enemies() を呼んでいるため）
func set_all_enemies(all_enemies: Array[Character]) -> void:
	set_all_members(all_enemies)


## メンバーをスポーンしてパーティーを構成する
## spawn_list: [{ "enemy_id" or "character_id": String, "x": int, "y": int }]
func setup(spawn_list: Array, player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	for spawn_info: Variant in spawn_list:
		var info    := spawn_info as Dictionary
		var char_id: String = info.get("enemy_id", info.get("character_id", ""))
		var pos     := Vector2i(int(info.get("x", 0)), int(info.get("y", 0)))
		var member  := _spawn_member(char_id, pos)
		_members.append(member)


func _spawn_member(char_id: String, grid_pos: Vector2i) -> Character:
	var member := Character.new()
	member.grid_pos = grid_pos
	member.placeholder_color = Color(1.0, 0.4, 0.2)
	member.character_data = CharacterData.load_from_json(
		"res://assets/master/enemies/" + char_id + ".json"
	)
	# 敵画像フォルダが存在すればランダムに選択して適用する（なければ JSON パスを維持）
	CharacterGenerator.apply_enemy_graphics(member.character_data)
	# name（例: "EnemyManager0"）をプレフィックスにして複数マネージャー間の名前衝突を防ぐ
	member.name = name + "_" + char_id.capitalize() + str(_members.size())
	get_parent().add_child(member)
	member.sync_position()
	member.died.connect(_on_member_died)
	return member


## メンバーリストを返す（生存・死亡問わず全メンバー）
func get_members() -> Array[Character]:
	return _members


## 後方互換エイリアス（EnemyManager.get_enemies() の置き換え）
func get_enemies() -> Array[Character]:
	return _members


## VisionSystem から呼ばれる：訪問済みエリアに基づいてメンバーの表示を更新する
## visited_areas: { area_id: String -> true } プレイヤーパーティーの訪問済みエリア集合
func update_visibility(player_area: String, map_data: MapData,
		visited_areas: Dictionary) -> void:
	for member: Character in _members:
		if not is_instance_valid(member):
			continue
		var member_area := map_data.get_area(member.grid_pos)
		# エリア情報がない場合（静的マップ等）は常に表示
		if member_area.is_empty():
			member.visible = true
		else:
			# 訪問済みエリアのメンバーは表示（一度見たら消えない）
			member.visible = visited_areas.has(member_area)
		# AI アクティブ化：プレイヤーと同じエリアに初めて入ったとき
		var in_same_area := not player_area.is_empty() and player_area == member_area
		if in_same_area and not _activated:
			_activated = true
			_start_ai()


## 毎フレーム距離チェック（VisionSystem 未使用時のフォールバック）
func _process(_delta: float) -> void:
	if _activated or _player == null or _members.is_empty() or _vision_controlled:
		return
	for member: Character in _members:
		if float((member.grid_pos - _player.grid_pos).length()) <= float(ACTIVATION_RANGE):
			_activated = true
			_start_ai()
			break


## 生存メンバーの先頭をリーダーに選出する
func _elect_leader() -> void:
	_leader = null
	for member: Character in _members:
		if is_instance_valid(member) and member.hp > 0:
			_leader = member
			return


## キャラ種に応じた PartyLeaderAI サブクラスを生成するファクトリ
func _create_leader_ai(leader: Character) -> PartyLeaderAI:
	var char_id := ""
	if leader != null and leader.character_data != null:
		char_id = leader.character_data.character_id
	if char_id.begins_with("goblin") or char_id.is_empty():
		var ai := GoblinLeaderAI.new()
		ai.name = "GoblinLeaderAI"
		return ai
	# 将来の種別追加: hobgoblin, zombie, wolf などはここで分岐する
	var ai := GoblinLeaderAI.new()
	ai.name = "GoblinLeaderAI"
	return ai


## AI を生成して起動する（エリア入室またはアクティブ化トリガー時）
func _start_ai() -> void:
	if _members.is_empty():
		return
	_elect_leader()
	if _leader == null:
		return
	_leader_ai = _create_leader_ai(_leader)
	add_child(_leader_ai)
	_leader_ai.setup(_members, _player, _map_data, _all_members)


## メンバー死亡時の処理
func _on_member_died(character: Character) -> void:
	_members.erase(character)
	# リーダーが死亡した場合は再選出
	if character == _leader:
		_elect_leader()
	# AI に状況変化を通知（逃走判定の再評価を即座に行わせる）
	if _leader_ai != null:
		_leader_ai.notify_situation_changed()
