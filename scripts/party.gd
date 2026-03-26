class_name Party
extends RefCounted

## パーティー管理クラス
## 将来の複数パーティー連携を見越した設計

var members: Array = []
var active_character: Character = null


func add_member(character: Character) -> void:
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
