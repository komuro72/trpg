class_name NpcManager
extends PartyManager

## NPC マネージャー
## CharacterGenerator でランダムキャラクターを生成してスポーンする。
## is_friendly = true を設定して緑のマーカーでフィールド表示する。
## NpcLeaderAI を使用して敵を攻撃する。

var _enemy_list: Array[Character] = []


## 攻撃対象の敵リストを設定する（game_map が全マネージャー生成後に呼ぶ）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies
	# AI 起動済みの場合は直接転送
	if _leader_ai != null and _leader_ai is NpcLeaderAI:
		(_leader_ai as NpcLeaderAI).set_enemy_list(enemies)


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


## NPC 用スポーン：class_id でキャラクターをランダム生成する
## drop_items は NPC には不使用（PartyManager との署名互換のために宣言）
func setup(spawn_list: Array, player: Character, map_data: MapData, drop_items: Array = []) -> void:
	_player   = player
	_map_data = map_data
	for spawn_info: Variant in spawn_list:
		var info              := spawn_info as Dictionary
		var class_id: String   = info.get("class_id", "fighter-sword") as String
		var pos               := Vector2i(int(info.get("x", 0)), int(info.get("y", 0)))
		var items             := info.get("items", []) as Array
		var image_set_override: String = info.get("image_set", "") as String
		var member            := _spawn_member(class_id, pos, image_set_override)
		# 初期装備を付与する
		if member.character_data != null and not items.is_empty():
			member.character_data.apply_initial_items(items)
		# global_orders デフォルト値（Party.global_orders と同一）をメンバーの current_order に反映
		# Character.current_order のデフォルトは Party.global_orders と一致しているが、
		# クラス依存の battle_formation / combat はここで確定する
		_apply_attack_preset_to_member(member)
		_members.append(member)


## CharacterGenerator でキャラクターを生成してスポーンする
## image_set_override: JSON で指定されたフォルダ名（空ならランダム選択のまま）
func _spawn_member(class_id: String, grid_pos: Vector2i, image_set_override: String = "") -> Character:
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

	# name（例: "NpcManager0"）をプレフィックスにして複数マネージャー間の名前衝突を防ぐ
	member.name = "%s_%s_%d" % [name, class_id.replace("-", "_"), _members.size()]
	get_parent().add_child(member)
	member.sync_position()
	member.died.connect(_on_member_died)
	return member


## NpcLeaderAI を生成するファクトリ
func _create_leader_ai(_leader: Character) -> PartyLeaderAI:
	var ai := NpcLeaderAI.new()
	ai.name = "NpcLeaderAI"
	ai.set_enemy_list(_enemy_list)
	return ai
