class_name MapData
extends RefCounted

## タイルマップデータ管理
## タイルの種別・配置・移動可否クエリを担う。描画は game_map.gd が行う。
## Phase 2-2: load_from_json() でマップ・スポーン情報をJSONから読み込めるように拡張。

enum TileType { FLOOR = 0, WALL = 1 }

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
	return data


## 指定座標のタイル種別を返す。範囲外はWALLとして扱う
func get_tile(pos: Vector2i) -> TileType:
	if pos.x < 0 or pos.x >= map_width or pos.y < 0 or pos.y >= map_height:
		return TileType.WALL
	return _tiles[pos.y][pos.x]


## 指定座標が移動可能か（FLOORのみtrue）
func is_walkable(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.FLOOR
