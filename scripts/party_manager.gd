class_name PartyManager
extends Node

## パーティーマネージャー（敵・NPC・プレイヤーパーティー共通）
## 全パーティー種別（敵・NPC・プレイヤー）を統合管理するクラス
## リーダーAI（PartyLeaderAI）+ 個体AI（UnitAI）の2層構造でAIを管理する
##
## 利用可能な party_type: "enemy" / "npc" / "player"

## VisionSystem 未接続時の距離ベースアクティブ化しきい値
const ACTIVATION_RANGE: int = 5

## 全メンバーが死亡したときに発火する。items: ドロップアイテム配列、room_id: 部屋のエリアID
signal party_wiped(items: Array, room_id: String)

## パーティー種別（"enemy" / "npc" / "player"）
var party_type: String = "enemy"

## 攻撃対象の敵リスト（NPC・プレイヤーパーティー用。game_map から設定）
var _enemy_list: Array[Character] = []

## パーティーカラー（Character.party_color の一括設定に使用。TRANSPARENT=リング非表示）
var party_color: Color = Color.TRANSPARENT

## RightPanel / vision_system からのアクセスに使用する後方互換プロパティ
var enemy_ai: PartyLeader:
	get: return _leader_ai

var _members:    Array[Character] = []
var _leader:     Character
var _leader_ai:  PartyLeader
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
	# --- デバッグ ---
	if party_type == "npc":
		var own_in := 0
		for m: Character in _members:
			if is_instance_valid(m) and m in all_members:
				own_in += 1
		print("[DBG_PM_SAM] %s: all=%d own_members=%d own_in_all=%d ai=%s" % [
			name, all_members.size(), _members.size(), own_in,
			"yes" if _leader_ai != null else "no"])


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


## 攻撃対象の敵リストを設定する（game_map が全マネージャー生成後に呼ぶ）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies
	# AI 起動済みの場合は直接転送
	if _leader_ai != null:
		if _leader_ai is NpcLeaderAI:
			(_leader_ai as NpcLeaderAI).set_enemy_list(enemies)
		elif _leader_ai is PartyLeaderPlayer:
			(_leader_ai as PartyLeaderPlayer).set_enemy_list(enemies)


## battle_policy="attack" プリセットをクラスに応じてメンバーに適用する
static func _apply_attack_preset_to_member(ch: Character) -> void:
	if ch.character_data == null:
		return
	var cid := ch.character_data.class_id
	match cid:
		"healer":
			ch.current_order["battle_formation"] = "rear"
			ch.current_order["combat"]           = "attack"
			ch.current_order["heal"]             = "lowest_hp_first"
		"archer", "magician-fire", "magician-water":
			ch.current_order["battle_formation"] = "rear"
			ch.current_order["combat"]           = "attack"
		"fighter-axe":
			ch.current_order["battle_formation"] = "rush"
			ch.current_order["combat"]           = "attack"
		_:  # fighter-sword, scout
			ch.current_order["battle_formation"] = "surround"
			ch.current_order["combat"]           = "attack"


## 既存のキャラクターをスポーンせずにAI管理下に置く
## 主にプレイヤーキャラクター（hero）のAI管理に使用する。
## died シグナルは呼び出し元が別途管理するため接続しない。
func setup_adopted(member: Character, player: Character, map_data: MapData) -> void:
	_player   = player
	_map_data = map_data
	_members.append(member)
	# _elect_leader() / _start_ai() は activate() で呼ばれるため不要


## メンバーをスポーンしてパーティーを構成する
## spawn_list: [{ "enemy_id" or "character_id" or "class_id": String, "x": int, "y": int }]
## drop_items: ドロップアイテムの辞書リスト（dungeon_builder から渡される）
func setup(spawn_list: Array, player: Character, map_data: MapData, drop_items: Array = []) -> void:
	_player     = player
	_map_data   = map_data
	_drop_items = drop_items.duplicate()
	if party_type == "npc":
		_setup_npc(spawn_list)
	else:
		_setup_enemy(spawn_list)
	# 初期リーダーを決定して is_leader フラグを設定する
	_elect_leader()


## 敵パーティーのスポーン処理
func _setup_enemy(spawn_list: Array) -> void:
	# スポーン位置の1つ目からエリアID（部屋ID）を検出する
	if not spawn_list.is_empty():
		var first := spawn_list[0] as Dictionary
		var fpos  := Vector2i(int(first.get("x", 0)), int(first.get("y", 0)))
		_room_id  = _map_data.get_area(fpos)
	for spawn_info: Variant in spawn_list:
		var info    := spawn_info as Dictionary
		var char_id: String = info.get("enemy_id", info.get("character_id", ""))
		var pos     := Vector2i(int(info.get("x", 0)), int(info.get("y", 0)))
		var member  := _spawn_enemy_member(char_id, pos)
		_members.append(member)


## NPC パーティーのスポーン処理（CharacterGenerator によるランダム生成＋初期装備付与）
func _setup_npc(spawn_list: Array) -> void:
	for spawn_info: Variant in spawn_list:
		var info              := spawn_info as Dictionary
		var class_id: String   = info.get("class_id", "fighter-sword") as String
		var pos               := Vector2i(int(info.get("x", 0)), int(info.get("y", 0)))
		var items             := info.get("items", []) as Array
		var image_set_override: String = info.get("image_set", "") as String
		var member            := _spawn_npc_member(class_id, pos, image_set_override)
		# 初期装備を付与する
		if member.character_data != null and not items.is_empty():
			member.character_data.apply_initial_items(items)
		# クラス依存の battle_formation / combat を確定する
		_apply_attack_preset_to_member(member)
		_members.append(member)


func _spawn_enemy_member(char_id: String, grid_pos: Vector2i) -> Character:
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
	# name をプレフィックスにして複数マネージャー間の名前衝突を防ぐ
	member.name = name + "_" + char_id.capitalize() + str(_members.size())
	get_parent().add_child(member)
	member.sync_position()
	member.died.connect(_on_member_died)
	return member


## CharacterGenerator でNPCキャラクターを生成してスポーンする
## image_set_override: JSON で指定されたフォルダ名（空ならランダム選択のまま）
func _spawn_npc_member(class_id: String, grid_pos: Vector2i, image_set_override: String = "") -> Character:
	var member := Character.new()
	member.grid_pos          = grid_pos
	member.placeholder_color = Color(0.2, 0.9, 0.3)
	member.is_friendly       = true

	var generated_data := CharacterGenerator.generate_character(class_id)
	if generated_data != null:
		if not image_set_override.is_empty():
			CharacterGenerator.apply_image_set_override(generated_data, image_set_override)
		member.character_data = generated_data
	else:
		var fallback := CharacterData.new()
		fallback.character_name = class_id
		member.character_data   = fallback

	member.name = "%s_%s_%d" % [name, class_id.replace("-", "_"), _members.size()]
	get_parent().add_child(member)
	member.sync_position()
	member.died.connect(_on_member_died)
	return member


## メンバーリストを返す（生存・死亡問わず全メンバー）
func get_members() -> Array[Character]:
	return _members


## 後方互換エイリアス（get_enemies() は get_members() と同義）
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


## パーティー種別・キャラ種に応じた PartyLeader サブクラスを生成するファクトリ
func _create_leader_ai(leader: Character) -> PartyLeader:
	match party_type:
		"player":
			var ai := PartyLeaderPlayer.new()
			ai.name = "PartyLeaderPlayer"
			ai.set_enemy_list(_enemy_list)
			return ai
		"npc":
			var ai := NpcLeaderAI.new()
			ai.name = "NpcLeaderAI"
			ai.set_enemy_list(_enemy_list)
			return ai
		_:  # "enemy"
			return _create_enemy_leader_ai(leader)


## 敵パーティー用：種族に応じた LeaderAI を生成する
func _create_enemy_leader_ai(leader: Character) -> PartyLeader:
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
				and _leader_ai._party_strategy == PartyLeader.Strategy.FLEE
		if not is_fleeing:
			return  # 追跡で出た可能性があるため制圧対象にしない
	# 全メンバーが「死亡 or FLEE 離脱」 → 制圧完了
	party_wiped.emit(_drop_items, _room_id)
	_room_id = ""  # 二重発火防止
