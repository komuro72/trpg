extends Node2D

## グリッドマップ（Phase 1）
## グリッド描画 + キャラクター生成 + プレイヤー入力制御

const CELL_SIZE: int = 48
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 15

const COLOR_BG := Color(0.10, 0.14, 0.10)
const COLOR_GRID := Color(0.25, 0.30, 0.25)
const COLOR_GRID_ACCENT := Color(0.35, 0.42, 0.35)  # 5セルごとの補助線

var party: Party
var player_controller: PlayerController
var hero: Character


func _ready() -> void:
	_setup_hero()
	_setup_controller()


func _setup_hero() -> void:
	hero = Character.new()
	hero.grid_pos = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
	hero.char_color = Color(0.3, 0.7, 1.0)  # 水色
	hero.name = "Hero"
	add_child(hero)
	hero.sync_position()

	party = Party.new()
	party.add_member(hero)


func _setup_controller() -> void:
	player_controller = PlayerController.new()
	player_controller.character = hero
	player_controller.map_size = Vector2i(MAP_WIDTH, MAP_HEIGHT)
	player_controller.name = "PlayerController"
	add_child(player_controller)


func _draw() -> void:
	var total_w := MAP_WIDTH * CELL_SIZE
	var total_h := MAP_HEIGHT * CELL_SIZE

	# 背景
	draw_rect(Rect2(0, 0, total_w, total_h), COLOR_BG)

	# グリッド線
	for x in range(MAP_WIDTH + 1):
		var color := COLOR_GRID_ACCENT if x % 5 == 0 else COLOR_GRID
		draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, total_h), color)

	for y in range(MAP_HEIGHT + 1):
		var color := COLOR_GRID_ACCENT if y % 5 == 0 else COLOR_GRID
		draw_line(Vector2(0, y * CELL_SIZE), Vector2(total_w, y * CELL_SIZE), color)
