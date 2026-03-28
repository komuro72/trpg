class_name DungeonBuilder
extends RefCounted

## ダンジョン構造JSONからMapDataを構築する
## Phase 3: フィールド生成

## 通路の幅（中心から左右に何タイル広げるか）。1 → 3タイル幅の通路
const CORRIDOR_HALF_WIDTH := 1


## 指定フロアのMapDataを構築して返す
## floor_data: DungeonGeneratorが生成したfloors[]の1要素
static func build_floor(floor_data: Dictionary) -> MapData:
	var rooms: Array = floor_data.get("rooms", [])
	if rooms.is_empty():
		push_error("DungeonBuilder: roomsが空です")
		return MapData.new()

	# マップサイズを全部屋の外接矩形から計算（余白2タイル）
	var max_x := 0
	var max_y := 0
	for room: Variant in rooms:
		var r := room as Dictionary
		var rx: int = int(r.get("x", 0))
		var ry: int = int(r.get("y", 0))
		var rw: int = int(r.get("width",  10))
		var rh: int = int(r.get("height", 10))
		if rx + rw > max_x:
			max_x = rx + rw
		if ry + rh > max_y:
			max_y = ry + rh
	var map_w := max_x + 2
	var map_h := max_y + 2

	var data := MapData.new()
	data.init_all_walls(map_w, map_h)

	# 部屋を床に展開（外周1タイルは壁として保持）
	for room: Variant in rooms:
		var r := room as Dictionary
		_carve_room(data, r)

	# 通路を床に展開
	var corridors: Array = floor_data.get("corridors", [])
	var room_map := _build_room_map(rooms)
	for corridor: Variant in corridors:
		var c := corridor as Dictionary
		var from_id := c.get("from", "") as String
		var to_id   := c.get("to",   "") as String
		if room_map.has(from_id) and room_map.has(to_id):
			# 通路名をエリア名テーブルに登録（タイル展開前に設定）
			var corr_area_id := "corridor_%s_%s" % [from_id, to_id]
			var corr_name := c.get("name", "") as String
			if not corr_name.is_empty():
				data.set_area_name(corr_area_id, corr_name)
			_carve_corridor(data, room_map[from_id] as Dictionary, room_map[to_id] as Dictionary)

	# スポーン情報を構築
	_build_spawn_data(data, floor_data, rooms)

	return data


## 部屋を床タイルに展開する（内部のみ、外周はWALL）
static func _carve_room(data: MapData, room: Dictionary) -> void:
	var rx: int = int(room.get("x",      0))
	var ry: int = int(room.get("y",      0))
	var rw: int = int(room.get("width",  10))
	var rh: int = int(room.get("height", 10))
	var area_id := room.get("id", "") as String
	# 部屋の内側（外周1タイルを壁として残す）
	for y in range(ry + 1, ry + rh - 1):
		for x in range(rx + 1, rx + rw - 1):
			var pos := Vector2i(x, y)
			data.set_tile(pos, MapData.TileType.FLOOR)
			data.set_tile_area(pos, area_id)
	# 部屋名をエリア名テーブルに登録
	var room_name := room.get("name", "") as String
	if not room_name.is_empty():
		data.set_area_name(area_id, room_name)


## 2部屋間をL字通路で接続する
static func _carve_corridor(data: MapData, from_room: Dictionary, to_room: Dictionary) -> void:
	var fx: int = int(from_room.get("x", 0)) + int(from_room.get("width",  10)) / 2
	var fy: int = int(from_room.get("y", 0)) + int(from_room.get("height", 10)) / 2
	var tx: int = int(to_room.get("x",   0)) + int(to_room.get("width",   10)) / 2
	var ty: int = int(to_room.get("y",   0)) + int(to_room.get("height",  10)) / 2

	var hw := CORRIDOR_HALF_WIDTH
	var area_id := "corridor_%s_%s" % [from_room.get("id", ""), to_room.get("id", "")]

	# 横方向（fx → tx）をまず伸ばす
	var min_x := mini(fx, tx)
	var max_x := maxi(fx, tx)
	for x in range(min_x, max_x + 1):
		for dy in range(-hw, hw + 1):
			var pos := Vector2i(x, fy + dy)
			if data.get_tile(pos) != MapData.TileType.FLOOR:
				data.set_tile(pos, MapData.TileType.CORRIDOR)
				data.set_tile_area(pos, area_id)

	# 縦方向（fy → ty）を伸ばす
	var min_y := mini(fy, ty)
	var max_y := maxi(fy, ty)
	for y in range(min_y, max_y + 1):
		for dx in range(-hw, hw + 1):
			var pos := Vector2i(tx + dx, y)
			if data.get_tile(pos) != MapData.TileType.FLOOR:
				data.set_tile(pos, MapData.TileType.CORRIDOR)
				data.set_tile_area(pos, area_id)


## 部屋ID → 部屋データの辞書を作る
static func _build_room_map(rooms: Array) -> Dictionary:
	var m: Dictionary = {}
	for room: Variant in rooms:
		var r := room as Dictionary
		var id := r.get("id", "") as String
		if not id.is_empty():
			m[id] = r
	return m


## MapDataのスポーン情報を構築する
static func _build_spawn_data(data: MapData, floor_data: Dictionary, rooms: Array) -> void:
	var entrance_id := floor_data.get("entrance_room", "") as String
	var room_map    := _build_room_map(rooms)

	# プレイヤースポーン（入口部屋の中心）
	if room_map.has(entrance_id):
		var er := room_map[entrance_id] as Dictionary
		var px: int = int(er.get("x", 2)) + int(er.get("width",  10)) / 2
		var py: int = int(er.get("y", 2)) + int(er.get("height", 10)) / 2
		data.player_parties = [
			{
				"party_id": 1,
				"members": [{"character_id": "hero", "x": px, "y": py}]
			}
		]

	# 敵スポーン（各部屋のenemy_partyから収集、party_idは部屋ごと）
	data.enemy_parties = []
	var party_id := 1
	for room: Variant in rooms:
		var r := room as Dictionary
		if r.get("is_entrance", false):
			continue
		var ep: Variant = r.get("enemy_party")
		if ep == null or not ep is Dictionary:
			continue
		var members: Array = (ep as Dictionary).get("members", [])
		if members.is_empty():
			continue
		data.enemy_parties.append({
			"party_id": party_id,
			"members":  members
		})
		party_id += 1
