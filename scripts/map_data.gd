class_name MapData
extends RefCounted

## タイルマップデータ管理
## タイルの種別・配置・移動可否クエリを担う。描画は game_map.gd が行う。
## Phase 2-2: load_from_json() でマップ・スポーン情報をJSONから読み込めるように拡張。
## Phase 5:   RUBBLE タイルを追加。is_walkable_for() で飛行キャラ対応。

enum TileType { FLOOR = 0, WALL = 1, RUBBLE = 2, CORRIDOR = 3 }

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


## 地上キャラ用の移動可否（FLOOR・CORRIDOR）
func is_walkable(pos: Vector2i) -> bool:
	var tile := get_tile(pos)
	return tile == TileType.FLOOR or tile == TileType.CORRIDOR


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


## 指定エリアIDに属する全タイル座標を返す（VisionSystem の視界計算に使用）
func get_tiles_in_area(area_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos: Variant in _area_map.keys():
		if _area_map[pos] == area_id:
			result.append(pos as Vector2i)
	return result


## 飛行フラグを考慮した移動可否
## 地上：FLOOR・CORRIDOR可。飛行：FLOOR・CORRIDOR・RUBBLE可（WALLは不可）
func is_walkable_for(pos: Vector2i, flying: bool) -> bool:
	var tile := get_tile(pos)
	match tile:
		TileType.FLOOR, TileType.CORRIDOR: return true
		TileType.RUBBLE: return flying
		_: return false
