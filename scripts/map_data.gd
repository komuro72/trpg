class_name MapData
extends RefCounted

## タイルマップデータ管理
## タイルの種別・配置・移動可否クエリを担う。描画は game_map.gd が行う。

enum TileType { FLOOR = 0, WALL = 1 }

const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 15

## タイルデータ（行優先: _tiles[y][x]）
var _tiles: Array = []


func _init() -> void:
	_generate_room()


## 外周がWALL、内側がFLOORの四角い部屋を生成する
func _generate_room() -> void:
	_tiles = []
	for y in range(MAP_HEIGHT):
		var row: Array = []
		for x in range(MAP_WIDTH):
			if x == 0 or x == MAP_WIDTH - 1 or y == 0 or y == MAP_HEIGHT - 1:
				row.append(TileType.WALL)
			else:
				row.append(TileType.FLOOR)
		_tiles.append(row)


## 指定座標のタイル種別を返す。範囲外はWALLとして扱う
func get_tile(pos: Vector2i) -> TileType:
	if pos.x < 0 or pos.x >= MAP_WIDTH or pos.y < 0 or pos.y >= MAP_HEIGHT:
		return TileType.WALL
	return _tiles[pos.y][pos.x]


## 指定座標が移動可能か（FLOORのみtrue）
func is_walkable(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.FLOOR
