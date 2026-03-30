class_name Party
extends RefCounted

## パーティー管理クラス
## 将来の複数パーティー連携を見越した設計

var members: Array = []
var active_character: Character = null

## 加入順インデックスカウンター（add_member() 呼び出しごとに増加）
var _next_join_index: int = 0


func add_member(character: Character) -> void:
	character.join_index = _next_join_index
	_next_join_index += 1
	members.append(character)
	if active_character == null:
		active_character = character


func remove_member(character: Character) -> void:
	members.erase(character)
	if active_character == character:
		active_character = members[0] if members.size() > 0 else null


func set_active(character: Character) -> void:
	if character in members:
		active_character = character


## リーダーを先頭に固定し、残りを join_index 昇順（加入が古い順）で返す
## 左パネル・指示ウィンドウの表示順に使用する
func sorted_members() -> Array:
	var leader: Character = null
	var others: Array = []
	for m: Variant in members:
		var ch := m as Character
		if not is_instance_valid(ch):
			continue
		if ch.is_leader and leader == null:
			leader = ch
		else:
			others.append(ch)
	others.sort_custom(func(a: Character, b: Character) -> bool:
		return a.join_index < b.join_index)
	var result: Array = []
	if leader != null:
		result.append(leader)
	result.append_array(others)
	return result
