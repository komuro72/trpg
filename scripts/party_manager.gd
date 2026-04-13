class_name PartyManager
extends Node

## パーティーマネージャー（敵・NPC・プレイヤーパーティー共通）
## 旧 EnemyManager を汎用化したクラス
## リーダーAI（PartyLeaderAI）+ 個体AI（UnitAI）の2層構造でAIを管理する
##
## 利用可能な party_type: "enemy" / "npc" / "player"

## VisionSystem 未接続時の距離ベースアクティブ化しきい値
const ACTIVATION_RANGE: int = 5

## 全メンバーが死亡したときに発火する。items: ドロップアイテム配列、room_id: 部屋のエリアID
signal party_wiped(items: Array, room_id: String)

## パーティー種別
var party_type: String = "enemy"

## パーティーカラー（Character.party_color の一括設定に使用。TRANSPARENT=リング非表示）
var party_color: Color = Color.TRANSPARENT

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
var suppress_ai_log: bool = false        ## true ならリーダーAIのログ出力を抑制する
var joined_to_player: bool = false       ## true なら隊形基準を _player（hero）にする（合流済み NPC パーティー）
var _all_members:    Array[Character] = []  ## 全パーティー合算（AI 起動時に渡す）
var _friendly_list:  Array[Character] = []  ## 攻撃対象の友好キャラ一覧（敵 AI 用・activate 時に渡す）
var _drop_items:     Array = []             ## ドロップアイテム（全滅時に party_wiped で転送）
var _room_id:        String = ""            ## このパーティーが属する部屋のエリアID
var _floor_items:    Dictionary = {}        ## フロアアイテム辞書（activate 前に set_floor_items が呼ばれた場合のキャッシュ）
var _vision_system_ref: VisionSystem = null ## VisionSystem 参照（activate 前キャッシュ）
var _global_orders:  Dictionary = {}        ## Party.global_orders 参照（activate 前キャッシュ）


## VisionSystem から呼ばれる。true なら距離ベースのアクティブ化を無効にする
func set_vision_controlled(enabled: bool) -> void:
	_vision_controlled = enabled


## パーティーカラーを設定し、全メンバーの party_color を更新する
func set_party_color(color: Color) -> void:
	party_color = color
	for member: Character in _members:
		if is_instance_valid(member):
			member.party_color = color


## VisionSystem を LeaderAI 経由で各 UnitAI に配布する（explore 行動に必要）
func set_vision_system(vs: VisionSystem) -> void:
	_vision_system_ref = vs
	if _leader_ai != null:
		_leader_ai.set_vision_system(vs)


## 現在の戦略名を返す（DebugWindow 表示用）
func get_strategy_name() -> String:
	if _leader_ai != null:
		return _leader_ai.get_current_strategy_name()
	return "-"


## 全体指示のヒントを返す（DebugWindow 表示用）
func get_global_orders_hint() -> Dictionary:
	if _leader_ai != null:
		return _leader_ai.get_global_orders_hint()
	return {}


## 現在の探索移動方針を返す（game_map が NPC の階段使用意図を判定するために使用）
func get_explore_move_policy() -> String:
	if _leader_ai != null:
		return _leader_ai.get_explore_move_policy()
	return "explore"


## MapData を更新し LeaderAI 経由で各 UnitAI に反映する（フロア遷移時に使用）
func set_map_data(new_map_data: MapData) -> void:
	_map_data = new_map_data
	if _leader_ai != null:
		_leader_ai.set_map_data(new_map_data)


## 特定メンバーの UnitAI の map_data のみ更新する（個別フロア遷移時に使用）
func set_member_map_data(member: Character, new_map_data: MapData) -> void:
	if _leader_ai != null:
		_leader_ai.set_member_map_data(member.name, new_map_data)


## 全パーティー合算メンバーリストを設定する（game_map が全マネージャー生成後に呼ぶ）
func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members
	if _leader_ai != null:
		_leader_ai.set_all_members(all_members)


## 攻撃対象となる友好キャラ一覧を保存し、LeaderAI が既に起動済みなら即座に渡す
func set_friendly_list(friendlies: Array[Character]) -> void:
	_friendly_list = friendlies
	if _leader_ai != null:
		_leader_ai.set_friendly_list(friendlies)


## Party.global_orders dict への参照を LeaderAI に渡す（hp_potion / sp_mp_potion 設定の反映に使用）
func set_global_orders(orders: Dictionary) -> void:
	_global_orders = orders
	if _leader_ai != null:
		_leader_ai.set_global_orders(orders)


## フロアアイテム辞書の参照を LeaderAI 経由で全 UnitAI に配布する（game_map から呼ばれる）
func set_floor_items(items: Dictionary) -> void:
	_floor_items = items
	if _leader_ai != null:
		_leader_ai.set_floor_items(items)


## 後方互換エイリアス（game_map が set_all_enemies() を呼んでいるため）
func set_all_enemies(all_enemies: Array[Character]) -> void:
	set_all_members(all_enemies)


## 既存のキャラクターをスポーンせずにAI管理下に置く
## 主にプレイヤーキャラクター（hero）のAI管理に使用する。
## died シグナルは呼び出し元が別途管理するため接続しない。
func setup_adopted(member: Character, player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	_members.append(member)
	# _elect_leader() / _start_ai() は activate() で呼ばれるため不要


## メンバーをスポーンしてパーティーを構成する
## spawn_list: [{ "enemy_id" or "character_id": String, "x": int, "y": int }]
## drop_items: ドロップアイテムの辞書リスト（dungeon_builder から渡される）
func setup(spawn_list: Array, player: Character, map_data: MapData, drop_items: Array = []) -> void:
	_player     = player
	_map_data   = map_data
	_drop_items = drop_items.duplicate()
	# スポーン位置の1つ目からエリアID（部屋ID）を検出する
	if not spawn_list.is_empty():
		var first := spawn_list[0] as Dictionary
		var fpos  := Vector2i(int(first.get("x", 0)), int(first.get("y", 0)))
		_room_id  = map_data.get_area(fpos)
	for spawn_info: Variant in spawn_list:
		var info    := spawn_info as Dictionary
		var char_id: String = info.get("enemy_id", info.get("character_id", ""))
		var pos     := Vector2i(int(info.get("x", 0)), int(info.get("y", 0)))
		var member  := _spawn_member(char_id, pos)
		_members.append(member)
	# 初期リーダーを決定して is_leader フラグを設定する
	_elect_leader()


func _spawn_member(char_id: String, grid_pos: Vector2i) -> Character:
	var member := Character.new()
	member.grid_pos = grid_pos
	member.placeholder_color = Color(1.0, 0.4, 0.2)
	# enemy_id はハイフン区切り（例: "goblin-archer"）だがファイル名はアンダーバー（goblin_archer.json）
	var file_name := char_id.replace("-", "_") + ".json"
	member.character_data = CharacterData.load_from_json(
		"res://assets/master/enemies/" + file_name
	)
	# 敵画像フォルダが存在すればランダムに選択して適用する（なければ JSON パスを維持）
	CharacterGenerator.apply_enemy_graphics(member.character_data)
	# enemy_list.json に基づいてステータスを0-100スケールで生成・上書きする
	CharacterGenerator.apply_enemy_stats(member.character_data)
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
## friendly_areas: フレンドリーキャラ（プレイヤー+NPC）が占有するエリアIDの辞書
## current_floor: 現在のフロアインデックス（-1 = フィルタなし）
## 敵マネージャーの場合、friendly_areas のいずれかにメンバーがいればアクティブ化する
func update_visibility(player_area: String, map_data: MapData,
		visited_areas: Dictionary, friendly_areas: Dictionary = {},
		current_floor: int = -1, show_all: bool = false) -> void:
	for member: Character in _members:
		if not is_instance_valid(member):
			continue
		# 別フロアのキャラクターは非表示（フロアをまたいだ誤表示を防ぐ）
		if current_floor >= 0 and member.current_floor != current_floor:
			member.visible = false
			continue
		var member_area := map_data.get_area(member.grid_pos)
		# エリア情報がない場合（静的マップ等）は常に表示
		if member_area.is_empty() or show_all:
			member.visible = true
		else:
			# 訪問済みエリアのメンバーは表示（一度見たら消えない）
			member.visible = visited_areas.has(member_area)
		# AI アクティブ化：フレンドリーキャラと同じエリアに初めて入ったとき
		var in_friendly_area := not member_area.is_empty() and (
			player_area == member_area or friendly_areas.has(member_area))
		if in_friendly_area and not _activated:
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


## 生存メンバーの先頭をリーダーに選出し、is_leader フラグを更新する
func _elect_leader() -> void:
	_leader = null
	for member: Character in _members:
		if is_instance_valid(member) and member.hp > 0:
			_leader = member
			break
	_update_leader_flags()


## 全メンバーの is_leader フラグを _leader に合わせて更新する
func _update_leader_flags() -> void:
	for member: Character in _members:
		if is_instance_valid(member):
			member.is_leader = (member == _leader)


## キャラ種に応じた PartyLeaderAI サブクラスを生成するファクトリ
func _create_leader_ai(leader: Character) -> PartyLeaderAI:
	var char_id := ""
	if leader != null and leader.character_data != null:
		char_id = leader.character_data.character_id

	match char_id:
		"goblin":
			var ai := GoblinLeaderAI.new()
			ai.name = "GoblinLeaderAI"
			return ai
		"hobgoblin":
			var ai := HobgoblinLeaderAI.new()
			ai.name = "HobgoblinLeaderAI"
			return ai
		"wolf":
			var ai := WolfLeaderAI.new()
			ai.name = "WolfLeaderAI"
			return ai

	# goblin-archer, goblin-mage, zombie, harpy, salamander,
	# dark-knight, dark-mage, dark_priest, dark-priest など
	var ai := EnemyLeaderAI.new()
	ai.name = "EnemyLeaderAI"
	return ai


## アクティブ状態を返す（デバッグ用）
func is_active() -> bool:
	return _activated


## プレイヤーパーティー合流フラグを設定し、LeaderAI・UnitAI に伝播する
func set_joined_to_player(value: bool) -> void:
	joined_to_player = value
	if _leader_ai != null:
		# set_follow_hero_floors() が joined_to_player の更新と UnitAI への伝播を行う
		_leader_ai.set_follow_hero_floors(value)


## AI を明示的に起動する（VisionSystem 経由ではなく直接起動が必要な場合に使用）
func activate() -> void:
	if not _activated:
		_activated = true
		_start_ai()


## AI を生成して起動する（エリア入室またはアクティブ化トリガー時）
func _start_ai() -> void:
	if _members.is_empty():
		return
	_elect_leader()
	if _leader == null:
		return
	_leader_ai = _create_leader_ai(_leader)
	if suppress_ai_log:
		_leader_ai.log_enabled = false
	_leader_ai.joined_to_player = joined_to_player  # 合流フラグを伝播
	if not _friendly_list.is_empty():
		_leader_ai.set_friendly_list(_friendly_list)
	if not _floor_items.is_empty():
		_leader_ai.set_floor_items(_floor_items)
	if not _global_orders.is_empty():
		_leader_ai.set_global_orders(_global_orders)
	add_child(_leader_ai)
	_leader_ai.setup(_members, _player, _map_data, _all_members)
	# VisionSystem は setup 後に渡す（UnitAI が生成済みである必要があるため）
	if _vision_system_ref != null:
		_leader_ai.set_vision_system(_vision_system_ref)


## メンバー死亡時の処理
func _on_member_died(character: Character) -> void:
	_members.erase(character)
	# リーダーが死亡した場合は再選出
	if character == _leader:
		_elect_leader()
	# AI に状況変化を通知（逃走判定の再評価を即座に行わせる）
	if _leader_ai != null:
		_leader_ai.notify_situation_changed()
	# NPC 死亡デバッグログ
	if character.is_friendly:
		var cd := character.character_data
		var name_str := cd.character_name if cd != null else "?"
		var class_str := GlobalConstants.CLASS_NAME_JP.get(
				cd.class_id if cd != null else "", cd.class_id if cd != null else "?") as String
		var floor_str := "F%d" % character.current_floor
		MessageLog.add_ai("[NPC死亡] %s（%s・%s）" % [name_str, class_str, floor_str])
	# 全メンバー死亡 or 離脱 → 制圧チェック
	if party_type == "enemy":
		_check_room_suppression()


## 部屋制圧判定：全メンバーが「死亡 or 敵走離脱」なら party_wiped を発火する
## 呼び出しタイミング：メンバー死亡時
func _check_room_suppression() -> void:
	if _room_id.is_empty() or _map_data == null:
		return
	# 既に発火済みなら再発火しない（_drop_items を空にして判別）
	# ※ _drop_items が元から空のパーティーは常に通過するが、
	#   _members が空でないなら制圧未完了なので問題ない
	for member: Character in _members:
		if not is_instance_valid(member):
			continue
		# 生存かつ部屋の中にいる → 制圧未完了
		var member_area := _map_data.get_area(member.grid_pos)
		if member_area == _room_id:
			return
		# 部屋の外にいる場合：FLEE 戦略なら離脱扱い、それ以外は追跡中
		var is_fleeing := _leader_ai != null \
				and _leader_ai._party_strategy == PartyLeaderAI.Strategy.FLEE
		if not is_fleeing:
			return  # 追跡で出た可能性があるため制圧対象にしない
	# 全メンバーが「死亡 or FLEE 離脱」 → 制圧完了
	party_wiped.emit(_drop_items, _room_id)
	_room_id = ""  # 二重発火防止
