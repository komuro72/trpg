extends Node2D

## グリッドマップ
## タイル描画 + キャラクター生成 + プレイヤー入力制御
## Phase 3: LLM生成ダンジョンの非同期読み込み、F5再生成に対応

## タイル色（将来タイル画像に差し替える場合はここを変更する）
const COLOR_FLOOR       := Color(0.40, 0.40, 0.40)       # 床: グレー
const COLOR_WALL        := Color(0.20, 0.20, 0.20)       # 壁: 暗いグレー
const COLOR_GRID_LINE   := Color(0.30, 0.30, 0.30, 0.5)  # グリッド線: 半透明

const DUNGEON_JSON_PATH  := "res://assets/master/maps/dungeon_generated.json"
const FALLBACK_JSON_PATH := "res://assets/master/maps/dungeon_01.json"

## 表示するフロア番号（0-indexed）
const CURRENT_FLOOR := 0

var map_data: MapData
var party: Party
var player_controller: PlayerController
var hero: Character
var camera_controller: CameraController
var enemy_manager: EnemyManager
var hud: HUD

var _generating_label: Label


func _ready() -> void:
	# F5（再生成）はどの状態でも受け付ける
	if FileAccess.file_exists(DUNGEON_JSON_PATH):
		_load_generated_dungeon()
	else:
		_start_generation()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_F5:
			_regenerate()


## 既存のdungeon_generated.jsonを読み込んで即座にセットアップ
func _load_generated_dungeon() -> void:
	var raw: Variant = JSON.parse_string(_read_file(DUNGEON_JSON_PATH))
	if raw != null and raw is Dictionary:
		var floors: Array = ((raw as Dictionary).get("dungeon", {}) as Dictionary).get("floors", [])
		if CURRENT_FLOOR < floors.size():
			map_data = DungeonBuilder.build_floor(floors[CURRENT_FLOOR] as Dictionary)
			_finish_setup()
			return

	push_error("game_map: dungeon_generated.json のパースに失敗しました。フォールバック使用")
	map_data = MapData.load_from_json(FALLBACK_JSON_PATH)
	_finish_setup()


## LLMでダンジョン生成を開始し、生成中ラベルを表示する
func _start_generation() -> void:
	_show_generating_label()

	var gen := DungeonGenerator.new()
	gen.name = "DungeonGenerator"
	add_child(gen)
	gen.generation_completed.connect(_on_generation_completed)
	gen.generation_failed.connect(_on_generation_failed)
	gen.generate()


func _on_generation_completed(_dungeon_data: Dictionary) -> void:
	# 保存済みのJSONを読み込んでシーンをリロード
	get_tree().reload_current_scene()


func _on_generation_failed(error: String) -> void:
	push_error("game_map: ダンジョン生成失敗: [" + error + "] → フォールバック使用")
	_hide_generating_label()
	map_data = MapData.load_from_json(FALLBACK_JSON_PATH)
	_finish_setup()


## F5キー：既存データを削除して再生成
func _regenerate() -> void:
	if FileAccess.file_exists(DUNGEON_JSON_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DUNGEON_JSON_PATH))
	get_tree().reload_current_scene()


## セットアップ完了（map_dataが確定してから呼ぶ）
func _finish_setup() -> void:
	_setup_hero()
	_setup_enemies()
	_setup_controller()
	_setup_camera()
	_setup_hud()
	queue_redraw()


# --------------------------------------------------------------------------
# セットアップ処理
# --------------------------------------------------------------------------

func _setup_hero() -> void:
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

	# 全パーティーのメンバーをまとめて1つのEnemyManagerに渡す
	var all_members: Array = []
	for ep: Variant in map_data.enemy_parties:
		var members: Array = (ep as Dictionary).get("members", [])
		all_members.append_array(members)

	if all_members.is_empty():
		return

	enemy_manager = EnemyManager.new()
	enemy_manager.name = "EnemyManager"
	add_child(enemy_manager)
	enemy_manager.setup(all_members, hero, map_data)


func _setup_controller() -> void:
	player_controller = PlayerController.new()
	player_controller.character = hero
	player_controller.map_data = map_data
	if enemy_manager != null:
		player_controller.blocking_characters = enemy_manager.get_enemies()
	player_controller.name = "PlayerController"
	add_child(player_controller)


func _setup_camera() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)

	var gs := GlobalConstants.GRID_SIZE
	var cam := Camera2D.new()
	cam.name = "Camera"
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


func _setup_hud() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	var enemies: Array[Character] = []
	if enemy_manager != null:
		enemies = enemy_manager.get_enemies()
	hud.setup(hero, enemies)


# --------------------------------------------------------------------------
# 生成中ラベル
# --------------------------------------------------------------------------

func _show_generating_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "GeneratingLayer"
	add_child(canvas)

	_generating_label = Label.new()
	_generating_label.text = "ダンジョン生成中..."
	_generating_label.add_theme_font_size_override("font_size", 28)
	_generating_label.add_theme_color_override("font_color", Color.WHITE)
	_generating_label.set_anchors_preset(Control.PRESET_CENTER)
	canvas.add_child(_generating_label)


func _hide_generating_label() -> void:
	var canvas := get_node_or_null("GeneratingLayer")
	if canvas != null:
		canvas.queue_free()


# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## キャラクターの死亡シグナルを受け取り、パーティーから除去する
func _on_character_died(character: Character) -> void:
	party.remove_member(character)


func _draw() -> void:
	if map_data == null:
		return
	var gs := GlobalConstants.GRID_SIZE

	for y in range(map_data.map_height):
		for x in range(map_data.map_width):
			var tile := map_data.get_tile(Vector2i(x, y))
			var fill_color := COLOR_FLOOR if tile == MapData.TileType.FLOOR else COLOR_WALL
			var rect := Rect2(x * gs, y * gs, gs, gs)

			draw_rect(rect, fill_color)
			draw_rect(rect, COLOR_GRID_LINE, false)
