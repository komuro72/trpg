extends Node2D

## グリッドマップ
## タイル描画 + キャラクター生成 + プレイヤー入力制御
## Phase 3: LLM生成ダンジョンの非同期読み込み、F5再生成に対応
## Phase 5: GRID_SIZE動的計算・視界システム・3カラムUIパネル

## タイル画像パス
const TILE_IMAGE_FLOOR    := "res://assets/images/tiles/tile_floor.png"
const TILE_IMAGE_WALL     := "res://assets/images/tiles/tile_wall.png"
const TILE_IMAGE_RUBBLE   := "res://assets/images/tiles/tile_rubble.png"
const TILE_IMAGE_CORRIDOR := "res://assets/images/tiles/tile_corridor.png"

## タイル画像が存在しない場合のフォールバック色
const COLOR_FLOOR       := Color(0.40, 0.40, 0.40)
const COLOR_WALL        := Color(0.20, 0.20, 0.20)
const COLOR_RUBBLE      := Color(0.55, 0.45, 0.35)
const COLOR_CORRIDOR    := Color(0.30, 0.30, 0.35)
const COLOR_GRID_LINE   := Color(0.0, 0.0, 0.0, 0.15)

const DUNGEON_JSON_PATH  := "res://assets/master/maps/dungeon_generated.json"
const FALLBACK_JSON_PATH := "res://assets/master/maps/dungeon_01.json"

## 表示するフロア番号（0-indexed）
const CURRENT_FLOOR := 0

var map_data: MapData
var party: Party
var player_controller: PlayerController
var hero: Character
var camera_controller: CameraController
var enemy_managers: Array[EnemyManager] = []
var vision_system: VisionSystem
var left_panel: LeftPanel
var right_panel: RightPanel
var message_window: MessageWindow
var area_name_display: AreaNameDisplay

var _generating_label: Label
var _tile_textures: Dictionary = {}  # TileType(int) -> Texture2D


func _ready() -> void:
	# 画面サイズから GRID_SIZE を動的計算（最小32px）
	GlobalConstants.initialize(get_viewport().get_visible_rect().size)

	if FileAccess.file_exists(DUNGEON_JSON_PATH):
		_load_generated_dungeon()
	else:
		_start_generation()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_F1:
				if right_panel != null:
					right_panel.toggle_debug()
			KEY_F5:
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
	_load_tile_textures()
	_setup_hero()
	_setup_enemies()
	_setup_controller()
	_setup_camera()
	_setup_vision_system()
	_setup_panels()
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
	# ランダム生成：グラフィックセット走査 → ランク・名前・ステータスをランダム決定
	var generated_data := CharacterGenerator.generate_character()
	hero.character_data = generated_data if generated_data != null else CharacterData.create_hero()
	hero.name = "Hero"
	add_child(hero)
	hero.sync_position()

	party = Party.new()
	party.add_member(hero)
	hero.died.connect(_on_character_died)


func _setup_enemies() -> void:
	if map_data.enemy_parties.is_empty():
		return

	# enemy_parties の各パーティーごとに別々の EnemyManager を生成する
	var idx := 0
	for ep: Variant in map_data.enemy_parties:
		var members: Array = (ep as Dictionary).get("members", [])
		if members.is_empty():
			continue
		var em := EnemyManager.new()
		em.name = "EnemyManager%d" % idx
		add_child(em)
		em.setup(members, hero, map_data)
		# VisionSystem が視界管理を担うため、距離ベースのアクティブ化を無効化
		em.set_vision_controlled(true)
		enemy_managers.append(em)
		idx += 1

	# 全 EnemyManager の敵を結合したリストを各マネージャーに配布する
	# BaseAI._is_passable() が他パーティーの敵座標も占有チェックに使用するため
	var all_enemies: Array[Character] = []
	for em: EnemyManager in enemy_managers:
		all_enemies.append_array(em.get_enemies())
	for em: EnemyManager in enemy_managers:
		em.set_all_enemies(all_enemies)


func _setup_controller() -> void:
	player_controller = PlayerController.new()
	player_controller.character = hero
	player_controller.map_data = map_data
	player_controller.map_node = self
	# 全 EnemyManager の敵を結合して blocking_characters に設定
	for em: EnemyManager in enemy_managers:
		player_controller.blocking_characters.append_array(em.get_enemies())
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


func _setup_vision_system() -> void:
	vision_system = VisionSystem.new()
	vision_system.name = "VisionSystem"
	add_child(vision_system)
	vision_system.setup(hero, map_data)
	for em: EnemyManager in enemy_managers:
		vision_system.add_enemy_manager(em)
	vision_system.area_changed.connect(_on_area_changed)
	vision_system.tiles_revealed.connect(queue_redraw)


func _setup_panels() -> void:
	# 左パネル（味方ステータス）
	left_panel = LeftPanel.new()
	left_panel.name = "LeftPanel"
	add_child(left_panel)
	left_panel.setup(party)
	left_panel.set_active_character(hero)

	# 右パネル（現在エリアの敵情報）
	right_panel = RightPanel.new()
	right_panel.name = "RightPanel"
	add_child(right_panel)
	var managers: Array = []
	for em: EnemyManager in enemy_managers:
		managers.append(em)
	right_panel.setup(managers, vision_system, map_data)

	# メッセージウィンドウ
	message_window = MessageWindow.new()
	message_window.name = "MessageWindow"
	add_child(message_window)

	# エリア名表示
	area_name_display = AreaNameDisplay.new()
	area_name_display.name = "AreaNameDisplay"
	add_child(area_name_display)

	# 起動時の初期エリア名を表示
	if vision_system != null:
		_on_area_changed(vision_system.get_current_area())


func _on_area_changed(new_area: String) -> void:
	if area_name_display == null or map_data == null:
		return
	# 名前なしエリア（通路など）では空文字を渡して非表示にする
	var area_name := map_data.get_area_name(new_area) if not new_area.is_empty() else ""
	area_name_display.show_area_name(area_name)


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


## タイル画像をプリロードする（画像がない場合はフォールバック色を使用）
func _load_tile_textures() -> void:
	_tile_textures.clear()
	var paths := {
		MapData.TileType.FLOOR:    TILE_IMAGE_FLOOR,
		MapData.TileType.WALL:     TILE_IMAGE_WALL,
		MapData.TileType.RUBBLE:   TILE_IMAGE_RUBBLE,
		MapData.TileType.CORRIDOR: TILE_IMAGE_CORRIDOR,
	}
	for tile_type: int in paths:
		var path: String = paths[tile_type]
		if ResourceLoader.exists(path):
			_tile_textures[tile_type] = load(path) as Texture2D


func _draw() -> void:
	if map_data == null:
		return
	var gs := GlobalConstants.GRID_SIZE

	# 可視タイル集合を取得（空の場合はエリアデータなし→全タイル描画）
	var visible_tiles := vision_system.get_visible_tiles() if vision_system != null else {}
	var use_vision    := not visible_tiles.is_empty()

	for y in range(map_data.map_height):
		for x in range(map_data.map_width):
			var pos  := Vector2i(x, y)
			# 未訪問タイルは描画しない（背景の黒のまま）
			if use_vision and not visible_tiles.has(pos):
				continue

			var tile := map_data.get_tile(pos)
			var rect := Rect2(x * gs, y * gs, gs, gs)

			if _tile_textures.has(int(tile)):
				draw_texture_rect(_tile_textures[int(tile)] as Texture2D, rect, false)
			else:
				var fill_color: Color
				match tile:
					MapData.TileType.FLOOR:    fill_color = COLOR_FLOOR
					MapData.TileType.RUBBLE:   fill_color = COLOR_RUBBLE
					MapData.TileType.CORRIDOR: fill_color = COLOR_CORRIDOR
					_:                         fill_color = COLOR_WALL
				draw_rect(rect, fill_color)

			draw_rect(rect, COLOR_GRID_LINE, false)
