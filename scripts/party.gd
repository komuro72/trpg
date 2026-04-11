class_name Party
extends RefCounted

## パーティー管理クラス
## 将来の複数パーティー連携を見越した設計

var members: Array = []
var active_character: Character = null

## 加入順インデックスカウンター（add_member() 呼び出しごとに増加）
var _next_join_index: int = 0

## パーティー全体の方針（OrderWindow の全体方針行が管理。将来 AI が参照予定）
var global_orders: Dictionary = {
	"combat":       "aggressive",
	"target":       "nearest",
	"on_low_hp":    "keep_fighting",
	"item_pickup":  "aggressive",
	"hp_potion":    "50pct",
	"sp_mp_potion": "save",
}


func add_member(character: Character) -> void:
	character.join_index = _next_join_index
	_next_join_index += 1
	members.append(character)
	if active_character == null:
		active_character = character


func remove_member(character: Character) -> void:
	members.erase(character)
	# freed メンバーも合わせて除去する
	members = members.filter(func(m: Variant) -> bool: return is_instance_valid(m))
	if active_character == character or not is_instance_valid(active_character):
		# 有効な最初のメンバーを新しい active_character に設定
		active_character = null
		for m: Variant in members:
			if is_instance_valid(m):
				active_character = m as Character
				break


func set_active(character: Character) -> void:
	if character in members:
		active_character = character


## リーダーを先頭に固定し、残りを join_index 昇順（加入が古い順）で返す
## 左パネル・指示ウィンドウの表示順に使用する
func sorted_members() -> Array:
	var leader: Character = null
	var others: Array = []
	for m: Variant in members:
		if not is_instance_valid(m):
			continue
		var ch := m as Character
		if ch == null:
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
