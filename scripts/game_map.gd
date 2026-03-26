extends Node2D

## グリッドマップ
## タイル描画 + キャラクター生成 + プレイヤー入力制御
## Phase 2-2: マップデータをJSONから読み込み、敵をEnemyManagerで配置。

## タイル色（将来タイル画像に差し替える場合はここを変更する）
const COLOR_FLOOR       := Color(0.40, 0.40, 0.40)       # 床: グレー
const COLOR_WALL        := Color(0.20, 0.20, 0.20)       # 壁: 暗いグレー
const COLOR_GRID_LINE   := Color(0.30, 0.30, 0.30, 0.5)  # グリッド線: 半透明

const MAP_JSON_PATH := "res://assets/master/maps/dungeon_01.json"

var map_data: MapData
var party: Party
var player_controller: PlayerController
var hero: Character
var camera_controller: CameraController
var enemy_manager: EnemyManager


func _ready() -> void:
	_setup_map()
	_setup_hero()
	_setup_enemies()
	_setup_controller()
	_setup_camera()


func _setup_map() -> void:
	map_data = MapData.load_from_json(MAP_JSON_PATH)


func _setup_hero() -> void:
	# JSONのスポーン情報からヒーローの初期座標を取得。なければデフォルト位置
	var spawn_pos := Vector2i(2, 2)
	if map_data.player_parties.size() > 0:
		var members: Array = (map_data.player_parties[0] as Dictionary).get("members", [])
		if members.size() > 0:
			var m := members[0] as Dictionary
			spawn_pos = Vector2i(int(m.get("x", 2)), int(m.get("y", 2)))

	hero = Character.new()
	hero.grid_pos = spawn_pos
	hero.placeholder_color = Color(0.3, 0.7, 1.0)
	hero.character_data = CharacterData.create_hero()
	hero.name = "Hero"
	add_child(hero)
	hero.sync_position()

	party = Party.new()
	party.add_member(hero)
	hero.died.connect(_on_character_died)


func _setup_enemies() -> void:
	if map_data.enemy_parties.is_empty():
		return
	var members: Array = (map_data.enemy_parties[0] as Dictionary).get("members", [])
	enemy_manager = EnemyManager.new()
	enemy_manager.name = "EnemyManager"
	add_child(enemy_manager)
	enemy_manager.setup(members, hero)


func _setup_controller() -> void:
	player_controller = PlayerController.new()
	player_controller.character = hero
	player_controller.map_data = map_data
	player_controller.name = "PlayerController"
	add_child(player_controller)


func _setup_camera() -> void:
	# マップ外を黒で表示
	RenderingServer.set_default_clear_color(Color.BLACK)

	var gs := GlobalConstants.GRID_SIZE
	var cam := Camera2D.new()
	cam.name = "Camera"
	# マップ端でカメラを止める（Godot の limit 機能で自動クランプ）
	cam.limit_left   = 0
	cam.limit_right  = map_data.map_width  * gs
	cam.limit_top    = 0
	cam.limit_bottom = map_data.map_height * gs
	add_child(cam)

	camera_controller = CameraController.new()
	camera_controller.character = hero
	camera_controller.camera    = cam
	camera_controller.name      = "CameraController"
	add_child(camera_controller)


## キャラクターの死亡シグナルを受け取り、パーティーから除去する
func _on_character_died(character: Character) -> void:
	party.remove_member(character)


func _draw() -> void:
	var gs := GlobalConstants.GRID_SIZE

	for y in range(map_data.map_height):
		for x in range(map_data.map_width):
			var tile := map_data.get_tile(Vector2i(x, y))
			var fill_color := COLOR_FLOOR if tile == MapData.TileType.FLOOR else COLOR_WALL
			var rect := Rect2(x * gs, y * gs, gs, gs)

			# タイル塗りつぶし
			draw_rect(rect, fill_color)
			# グリッド線（アウトライン）
			draw_rect(rect, COLOR_GRID_LINE, false)
