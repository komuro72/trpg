class_name DungeonBuilder
extends RefCounted

## ダンジョン構造JSONからMapDataを構築する
## Phase 3: フィールド生成

## 通路の幅（中心から左右に何タイル広げるか）。1 → 3タイル幅の通路
const CORRIDOR_HALF_WIDTH := 1

## マップ四方に追加する境界壁のタイル数。
## カメラリミット付近に到達できなくするためにキャラが歩けない壁領域を確保する
const MAP_BORDER := 6


## 指定フロアのMapDataを構築して返す
## floor_data: DungeonGeneratorが生成したfloors[]の1要素
static func build_floor(floor_data: Dictionary) -> MapData:
	var rooms: Array = floor_data.get("rooms", [])
	if rooms.is_empty():
		push_error("DungeonBuilder: roomsが空です")
		return MapData.new()

	# マップサイズを全部屋の外接矩形から計算
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

	# 四方に MAP_BORDER タイルの境界壁を追加（キャラがカメラリミット付近に到達できないようにする）
	var offset := Vector2i(MAP_BORDER, MAP_BORDER)
	var map_w := max_x + MAP_BORDER * 2 + 2
	var map_h := max_y + MAP_BORDER * 2 + 2

	var data := MapData.new()
	data.init_all_walls(map_w, map_h)

	# Step1: 部屋を床に展開（外周1タイルは壁として保持。wall_tiles/obstacle_tiles はまだ適用しない）
	for room: Variant in rooms:
		var r := room as Dictionary
		_carve_room(data, r, offset)

	# Step2: 通路を床に展開（外周壁タイルを CORRIDOR に変換して出入り口を作る）
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
			_carve_corridor(data, room_map[from_id] as Dictionary, room_map[to_id] as Dictionary, offset)

	# Step3: 通路掘削後に wall_tiles / obstacle_tiles を適用
	# （通路が先に開通しているため CORRIDOR タイルは上書きしない。部屋形状の壁と障害物のみ設定）
	for room: Variant in rooms:
		var r := room as Dictionary
		_apply_room_overlays(data, r, offset)

	# 階段タイルを配置
	var stairs: Array = floor_data.get("stairs", [])
	_place_stairs(data, stairs, offset)

	# スポーン情報を構築
	_build_spawn_data(data, floor_data, rooms, offset)

	data.build_adjacency()
	return data


## 部屋を床タイルに展開する（内部のみ・外周はWALL・wall_tiles/obstacle_tilesは適用しない）
static func _carve_room(data: MapData, room: Dictionary, offset: Vector2i) -> void:
	var rx: int = int(room.get("x",      0)) + offset.x
	var ry: int = int(room.get("y",      0)) + offset.y
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


## 通路掘削後に部屋のオーバーレイ（wall_tiles / obstacle_tiles）を適用する
## CORRIDOR タイルは上書きしない（通路として確保された出入り口を塞がない）
## wall_tiles: 内部をWALLに戻すタイル [{"rx": 相対x, "ry": 相対y}, ...]
## obstacle_tiles: OBSTACLEタイルを配置 [{"rx": 相対x, "ry": 相対y}, ...]
## rx/ry は部屋の左上隅からの相対座標
static func _apply_room_overlays(data: MapData, room: Dictionary, offset: Vector2i) -> void:
	var rx: int = int(room.get("x", 0)) + offset.x
	var ry: int = int(room.get("y", 0)) + offset.y
	var area_id := room.get("id", "") as String

	# wall_tiles: 内部の指定タイルをWALLに戻す（L字・T字など非矩形形状用）
	var wall_tiles: Array = room.get("wall_tiles", [])
	for wt: Variant in wall_tiles:
		var wtd := wt as Dictionary
		var wx: int = rx + int(wtd.get("rx", 0))
		var wy: int = ry + int(wtd.get("ry", 0))
		var wpos := Vector2i(wx, wy)
		# CORRIDOR（通路として開通済み）は上書きしない
		if data.get_tile(wpos) != MapData.TileType.CORRIDOR:
			data.set_tile(wpos, MapData.TileType.WALL)
			data.set_tile_area(wpos, "")

	# obstacle_tiles: 内部の指定タイルをOBSTACLEに設定
	var obstacle_tiles: Array = room.get("obstacle_tiles", [])
	for ot: Variant in obstacle_tiles:
		var otd := ot as Dictionary
		var ox: int = rx + int(otd.get("rx", 0))
		var oy: int = ry + int(otd.get("ry", 0))
		var opos := Vector2i(ox, oy)
		# CORRIDOR（通路として開通済み）は上書きしない
		if data.get_tile(opos) != MapData.TileType.CORRIDOR:
			data.set_tile(opos, MapData.TileType.OBSTACLE)
			data.set_tile_area(opos, area_id)


## 2部屋間をL字通路で接続する
static func _carve_corridor(data: MapData, from_room: Dictionary, to_room: Dictionary, offset: Vector2i) -> void:
	var fx: int = int(from_room.get("x", 0)) + int(from_room.get("width",  10)) / 2 + offset.x
	var fy: int = int(from_room.get("y", 0)) + int(from_room.get("height", 10)) / 2 + offset.y
	var tx: int = int(to_room.get("x",   0)) + int(to_room.get("width",   10)) / 2 + offset.x
	var ty: int = int(to_room.get("y",   0)) + int(to_room.get("height",  10)) / 2 + offset.y

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


## MapDataのスポーン情報を構築する（offset を加算して実マップ座標に変換する）
static func _build_spawn_data(data: MapData, floor_data: Dictionary, rooms: Array, offset: Vector2i) -> void:
	var entrance_id := floor_data.get("entrance_room", "") as String
	var room_map    := _build_room_map(rooms)

	# プレイヤースポーン（入口部屋の player_party があれば使用、なければ中心1人）
	if room_map.has(entrance_id):
		var er := room_map[entrance_id] as Dictionary
		var pp: Variant = er.get("player_party")
		var pp_members: Array = []
		if pp != null and pp is Dictionary:
			pp_members = (pp as Dictionary).get("members", [])
		if not pp_members.is_empty():
			data.player_parties = [{"party_id": 1, "members": _offset_members(pp_members, offset)}]
		else:
			var px: int = int(er.get("x", 2)) + int(er.get("width",  10)) / 2 + offset.x
			var py: int = int(er.get("y", 2)) + int(er.get("height", 10)) / 2 + offset.y
			data.player_parties = [
				{"party_id": 1, "members": [{"character_id": "hero", "x": px, "y": py}]}
			]

	# 敵スポーン（各部屋のenemy_partyから収集、party_idは部屋ごと）
	data.enemy_parties = []
	data.npc_parties   = []
	var party_id := 1
	for room: Variant in rooms:
		var r := room as Dictionary
		if r.get("is_entrance", false):
			continue
		var ep: Variant = r.get("enemy_party")
		if ep != null and ep is Dictionary:
			var members: Array = (ep as Dictionary).get("members", [])
			if not members.is_empty():
				data.enemy_parties.append({
					"party_id": party_id,
					"members":  _offset_members(members, offset),
					"items":    (ep as Dictionary).get("items", [])
				})
				party_id += 1
		var np: Variant = r.get("npc_party")
		if np != null and np is Dictionary:
			var members: Array = (np as Dictionary).get("members", [])
			if not members.is_empty():
				data.npc_parties.append({
					"party_id": party_id,
					"members":  _offset_members(members, offset)
				})
				party_id += 1


## メンバーリストの x/y 座標に offset を加算した新しいリストを返す
static func _offset_members(members: Array, offset: Vector2i) -> Array:
	var result: Array = []
	for m: Variant in members:
		var md := (m as Dictionary).duplicate()
		md["x"] = int(md.get("x", 0)) + offset.x
		md["y"] = int(md.get("y", 0)) + offset.y
		result.append(md)
	return result


## 階段タイルを配置する
## stairs: [{"type": "stairs_down"/"stairs_up", "x": int, "y": int}, ...]
static func _place_stairs(data: MapData, stairs: Array, offset: Vector2i) -> void:
	for stair: Variant in stairs:
		var s := stair as Dictionary
		var x: int = int(s.get("x", 0)) + offset.x
		var y: int = int(s.get("y", 0)) + offset.y
		var pos := Vector2i(x, y)
		var stype := s.get("type", "") as String
		if stype == "stairs_down":
			data.set_tile(pos, MapData.TileType.STAIRS_DOWN)
		elif stype == "stairs_up":
			data.set_tile(pos, MapData.TileType.STAIRS_UP)
