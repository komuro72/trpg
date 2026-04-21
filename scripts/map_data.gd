class_name MapData
extends RefCounted

## タイルマップデータ管理
## タイルの種別・配置・移動可否クエリを担う。描画は game_map.gd が行う。
## Phase 2-2: load_from_json() でマップ・スポーン情報をJSONから読み込めるように拡張。
## Phase 5:   OBSTACLE（旧RUBBLE）タイルを追加。is_walkable_for() で飛行キャラ対応。
## Phase 11-1: STAIRS_DOWN / STAIRS_UP タイルを追加。

enum TileType { FLOOR = 0, WALL = 1, OBSTACLE = 2, CORRIDOR = 3, STAIRS_DOWN = 4, STAIRS_UP = 5 }

## デフォルトマップサイズ定数（player_controller.gd のフォールバック用に残す）
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 15

## 実際に使用するマップサイズ（JSONから上書き可能）
var map_width: int = MAP_WIDTH
var map_height: int = MAP_HEIGHT

## タイルデータ（行優先: _tiles[y][x]）
var _tiles: Array = []

## スポーン情報（JSONから読み込む）
## [{party_id: int, members: [{character_id: String, x: int, y: int}]}]
var player_parties: Array = []
var enemy_parties: Array = []
var npc_parties: Array = []

## エリアマップ（グリッド座標 → エリアID文字列）
## DungeonBuilderが部屋・通路ごとにIDを設定する
var _area_map: Dictionary = {}   # Vector2i -> String

## エリア名テーブル（エリアID → 表示名）
## DungeonBuilderがLLM生成JSONのnameフィールドから設定する
var _area_names: Dictionary = {}  # String -> String

## エリア隣接テーブル（エリアID → 隣接エリアIDの配列）
## build_adjacency() で構築。VisionSystem の先行可視化に使用
var _adjacent_areas: Dictionary = {}  # String -> Array[String]

## 安全エリアタイル集合（敵は進入不可）
## DungeonBuilder が is_safe_room=true の部屋の内部 FLOOR タイルをマークする
var _safe_tiles: Dictionary = {}  # Vector2i -> true


func _init() -> void:
	_generate_room()


## 外周がWALL、内側がFLOORの四角い部屋を生成する（JSON非使用時のデフォルト）
func _generate_room() -> void:
	_tiles = []
	for y in range(map_height):
		var row: Array = []
		for x in range(map_width):
			if x == 0 or x == map_width - 1 or y == 0 or y == map_height - 1:
				row.append(TileType.WALL)
			else:
				row.append(TileType.FLOOR)
		_tiles.append(row)


## JSONファイルからMapDataを生成する。読み込み失敗時はデフォルトマップにフォールバック
static func load_from_json(path: String) -> MapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MapData: JSONファイルが見つかりません: " + path)
		return MapData.new()
	var json_text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		push_error("MapData: JSONのパースに失敗しました: " + path)
		return MapData.new()
	var d := parsed as Dictionary

	var data := MapData.new()  # _generate_room() で一度生成してから上書き
	data.map_width  = int(d.get("width",  MAP_WIDTH))
	data.map_height = int(d.get("height", MAP_HEIGHT))

	# タイルデータをJSONから上書き
	var tiles_json: Array = d.get("tiles", [])
	if tiles_json.size() == data.map_height:
		data._tiles = []
		for row: Variant in tiles_json:
			data._tiles.append(Array(row))

	data.player_parties = d.get("player_parties", [])
	data.enemy_parties  = d.get("enemy_parties",  [])
	data.npc_parties    = d.get("npc_parties",    [])
	return data


## 全タイルをWALLで初期化する（DungeonBuilderが使用）
func init_all_walls(w: int, h: int) -> void:
	map_width  = w
	map_height = h
	_tiles = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(TileType.WALL)
		_tiles.append(row)


## 指定座標のタイルを書き込む（DungeonBuilderが使用）
func set_tile(pos: Vector2i, tile: TileType) -> void:
	if pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height:
		_tiles[pos.y][pos.x] = tile


## 指定座標のタイル種別を返す。範囲外はWALLとして扱う
func get_tile(pos: Vector2i) -> TileType:
	if pos.x < 0 or pos.x >= map_width or pos.y < 0 or pos.y >= map_height:
		return TileType.WALL
	return _tiles[pos.y][pos.x]


## 地上キャラ用の移動可否（FLOOR・CORRIDOR・階段）
func is_walkable(pos: Vector2i) -> bool:
	var tile := get_tile(pos)
	return tile == TileType.FLOOR or tile == TileType.CORRIDOR \
		or tile == TileType.STAIRS_DOWN or tile == TileType.STAIRS_UP


## 指定座標のエリアIDを設定する（DungeonBuilderが使用）
func set_tile_area(pos: Vector2i, area_id: String) -> void:
	if pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height:
		_area_map[pos] = area_id


## 指定座標のエリアIDを返す（エリア情報がない場合は空文字）
func get_area(pos: Vector2i) -> String:
	return _area_map.get(pos, "")


## エリア名を設定する（DungeonBuilderが使用）
func set_area_name(area_id: String, name: String) -> void:
	_area_names[area_id] = name


## エリアIDに対応する表示名を返す（設定されていない場合は空文字）
func get_area_name(area_id: String) -> String:
	return _area_names.get(area_id, "")


## マップ内に存在するエリアIDの一覧を返す（UnitAI の探索行動に使用）
func get_all_area_ids() -> Array[String]:
	var result: Array[String] = []
	for pos: Variant in _area_map.keys():
		var area := _area_map[pos] as String
		if not result.has(area):
			result.append(area)
	return result


## 指定エリアIDに属する全タイル座標を返す（VisionSystem の視界計算に使用）
func get_tiles_in_area(area_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos: Variant in _area_map.keys():
		if _area_map[pos] == area_id:
			result.append(pos as Vector2i)
	return result


## 指定エリアに隣接するエリアIDの配列を返す
func get_adjacent_areas(area_id: String) -> Array[String]:
	return _adjacent_areas.get(area_id, []) as Array[String]


## エリア隣接テーブルを構築する（セットアップ完了後に1回呼ぶ）
## タイル同士が上下左右で隣接し、異なるエリアIDを持つ場合に「隣接」と判定する
func build_adjacency() -> void:
	_adjacent_areas.clear()
	for pos: Variant in _area_map.keys():
		var area: String = _area_map[pos] as String
		if area.is_empty():
			continue
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			var npos := (pos as Vector2i) + offset
			var neighbor: String = _area_map.get(npos, "") as String
			if neighbor.is_empty() or neighbor == area:
				continue
			if not _adjacent_areas.has(area):
				_adjacent_areas[area] = [] as Array[String]
			var adj: Array[String] = _adjacent_areas[area] as Array[String]
			if not adj.has(neighbor):
				adj.append(neighbor)


## 指定タイル種別の全座標を返す（階段位置の検索に使用）
func find_stairs(tile_type: TileType) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(map_height):
		for x in range(map_width):
			if _tiles[y][x] == tile_type:
				result.append(Vector2i(x, y))
	return result


## 飛行フラグを考慮した移動可否
## 地上：FLOOR・CORRIDOR・STAIRS可。飛行：FLOOR・CORRIDOR・OBSTACLE・STAIRS可（WALLは不可）
func is_walkable_for(pos: Vector2i, flying: bool) -> bool:
	var tile := get_tile(pos)
	match tile:
		TileType.FLOOR, TileType.CORRIDOR, \
		TileType.STAIRS_DOWN, TileType.STAIRS_UP: return true
		TileType.OBSTACLE: return flying
		_: return false


## 安全エリアとしてマークする（DungeonBuilder が使用）
func mark_safe_tile(pos: Vector2i) -> void:
	_safe_tiles[pos] = true


## 指定座標が安全エリア（敵進入不可）かどうか
func is_safe_tile(pos: Vector2i) -> bool:
	return _safe_tiles.has(pos)


## 全ての安全タイル座標を返す（味方の撤退先選択に使用）
func get_safe_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos: Variant in _safe_tiles.keys():
		result.append(pos as Vector2i)
	return result


## 敵（非友好キャラ）用の移動可否。安全エリアも通過不可とする
func is_walkable_for_enemy(pos: Vector2i, flying: bool) -> bool:
	if not is_walkable_for(pos, flying):
		return false
	return not is_safe_tile(pos)


# --------------------------------------------------------------------------
# FLEE 逃走先決定 API（2026-04-21 ステップ 3 追加）
# --------------------------------------------------------------------------

## 指定フロアの避難先エリア ID 一覧を返す
## フロア 0: 安全部屋群のエリア ID（get_safe_tiles() から導出・重複排除）
## フロア 1 以降: 上り階段タイルのあるエリア ID（find_stairs(STAIRS_UP) から導出・重複排除）
## 該当エリアが存在しない場合は空配列
func get_refuge_area_ids(floor_id: int) -> Array[String]:
	var result: Array[String] = []
	if floor_id == 0:
		for pos: Variant in _safe_tiles.keys():
			var area: String = _area_map.get(pos, "") as String
			if not area.is_empty() and not result.has(area):
				result.append(area)
	else:
		var ups: Array[Vector2i] = find_stairs(TileType.STAIRS_UP)
		for pos: Vector2i in ups:
			var area: String = _area_map.get(pos, "") as String
			if not area.is_empty() and not result.has(area):
				result.append(area)
	return result


## 2 つのエリア間の部屋単位の距離（ホップ数）を BFS で返す
## from == to の場合は 0、到達不能の場合は -1
## `_adjacent_areas`（build_adjacency() で構築済み）を参照
func get_area_distance(from_area_id: String, to_area_id: String) -> int:
	if from_area_id.is_empty() or to_area_id.is_empty():
		return -1
	if from_area_id == to_area_id:
		return 0
	var visited: Dictionary = {from_area_id: true}
	var queue: Array = [[from_area_id, 0]]
	while not queue.is_empty():
		var head: Array = queue.pop_front() as Array
		var cur: String = head[0] as String
		var dist: int = head[1] as int
		var neighbors: Array[String] = _adjacent_areas.get(cur, []) as Array[String]
		for n: String in neighbors:
			if visited.has(n):
				continue
			if n == to_area_id:
				return dist + 1
			visited[n] = true
			queue.append([n, dist + 1])
	return -1


## エリアの内側出口タイル一覧を返す
## 定義: そのエリア内のタイルのうち、4 近傍に異なるエリア ID（非空）を持つタイルがあるタイル
## A* のゴールとして使い、そのエリア内で完結する経路を探索させる
func get_exit_tiles_from(area_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if area_id.is_empty():
		return result
	for pos_var: Variant in _area_map.keys():
		if _area_map[pos_var] != area_id:
			continue
		var pos := pos_var as Vector2i
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor_area: String = _area_map.get(pos + offset, "") as String
			if not neighbor_area.is_empty() and neighbor_area != area_id:
				result.append(pos)
				break
	return result


## 内側出口タイルから隣接する別エリアの ID 一覧を返す
## 1 つの出口タイルが複数の別エリアに接することもあり得るので Array[String] を返す
## （通路タイルがちょうど 3 エリアの交点にいるようなケースを想定）
func get_adjacent_area_ids_of_exit(exit_tile: Vector2i) -> Array[String]:
	var result: Array[String] = []
	var own_area: String = _area_map.get(exit_tile, "") as String
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor_area: String = _area_map.get(exit_tile + offset, "") as String
		if neighbor_area.is_empty() or neighbor_area == own_area:
			continue
		if not result.has(neighbor_area):
			result.append(neighbor_area)
	return result
