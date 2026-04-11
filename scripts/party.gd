class_name Party
extends RefCounted

## パーティー管理クラス
## 将来の複数パーティー連携を見越した設計

var members: Array = []
var active_character: Character = null

## 加入順インデックスカウンター（add_member() 呼び出しごとに増加）
var _next_join_index: int = 0

## パーティー全体の方針（OrderWindow の全体方針行が管理。AI の move_policy・各種行動条件に反映）
## move:         全員の移動方針（move_policy と対応。follow/same_room/cluster/explore/standby）
## target:       全員のデフォルトターゲット方針（nearest/weakest/same_as_leader/support）
## on_low_hp:    低HP時の行動（keep_fighting/retreat/flee。NEAR_DEATH_THRESHOLD で判定）
## item_pickup:  アイテム取得方針（aggressive=積極/passive=近くなら(ITEM_PICKUP_RANGE)/avoid=拾わない）
## hp_potion:    HPポーション自動使用（use=瀕死時に自動使用/never=使わない）
## sp_mp_potion: SP/MPポーション自動使用（use=特殊攻撃前に自動使用/never=使わない）
var global_orders: Dictionary = {
	"move":         "follow",
	"target":       "nearest",
	"on_low_hp":    "keep_fighting",
	"item_pickup":  "passive",
	"hp_potion":    "use",
	"sp_mp_potion": "never",
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
