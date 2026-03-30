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

## NPC パーティーに割り当てるカラープール（生成順に割り当て・使い回しなし）
const _NPC_PARTY_COLORS: Array = [
	Color(0.40, 0.90, 1.00),  # 水色
	Color(0.50, 1.00, 0.40),  # 黄緑
	Color(1.00, 0.60, 0.10),  # 橙
	Color(0.80, 0.30, 1.00),  # 紫
	Color(1.00, 1.00, 0.30),  # 黄
	Color(1.00, 0.50, 0.80),  # ピンク
	Color(0.50, 0.80, 1.00),  # 空色
	Color(1.00, 0.20, 0.20),  # 赤
	Color(0.20, 0.90, 0.70),  # 青緑
]

var map_data: MapData
var party: Party
var player_controller: PlayerController
var hero: Character
var camera_controller: CameraController
var enemy_managers: Array[EnemyManager] = []
var npc_managers: Array[NpcManager] = []
## 初期パーティーメンバー（仲間加入済み）用の一時 NpcManager リスト
var _pre_joined_npc_managers: Array[NpcManager] = []
## hero の AI 管理専用マネージャー（is_player_controlled=false 時に UnitAI が動作する）
var _hero_manager: NpcManager
var vision_system: VisionSystem
var left_panel: LeftPanel
var right_panel: RightPanel
var message_window: MessageWindow
var area_name_display: AreaNameDisplay
var dialogue_trigger: DialogueTrigger
var dialogue_window: DialogueWindow
var order_window: OrderWindow

var _generating_label: Label
var _tile_textures: Dictionary = {}  # TileType(int) -> Texture2D
var _dialogue_npc_manager: NpcManager  ## 現在会話中の NpcManager
var _dialogue_npc_initiates: bool = false


func _ready() -> void:
	# 画面サイズから GRID_SIZE を動的計算（最小32px）
	GlobalConstants.initialize(get_viewport().get_visible_rect().size)

	if FileAccess.file_exists(DUNGEON_JSON_PATH):
		_load_generated_dungeon()
	else:
		_start_generation()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_F1:
				if right_panel != null:
					right_panel.toggle_debug()
			KEY_F5:
				_regenerate()
			KEY_TAB:
				_toggle_order_window()


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
	_setup_npcs()
	_setup_initial_allies()
	_link_all_character_lists()
	_setup_controller()
	_setup_camera()
	_setup_vision_system()
	_setup_panels()
	_setup_dialogue_system()
	_merge_pre_joined_allies()
	_setup_order_window()
	queue_redraw()


func _process(_delta: float) -> void:
	# 会話中に敵が部屋に入ってきたら会話を中断する
	if dialogue_window == null or not dialogue_window.visible:
		return
	if dialogue_trigger == null:
		return
	var area := vision_system.get_current_area() if vision_system != null else ""
	if not dialogue_trigger.is_area_enemy_free(area):
		_close_dialogue()


# --------------------------------------------------------------------------
# セットアップ処理
# --------------------------------------------------------------------------

func _setup_hero() -> void:
	var spawn_pos := Vector2i(2, 2)
	var class_id  := ""
	if map_data.player_parties.size() > 0:
		var members: Array = (map_data.player_parties[0] as Dictionary).get("members", [])
		if members.size() > 0:
			var m := members[0] as Dictionary
			spawn_pos = Vector2i(int(m.get("x", 2)), int(m.get("y", 2)))
			class_id  = m.get("class_id", "") as String

	hero = Character.new()
	hero.grid_pos = spawn_pos
	hero.placeholder_color = Color(0.3, 0.7, 1.0)
	var gen_data := CharacterGenerator.generate_character(class_id)
	hero.character_data = gen_data if gen_data != null else CharacterData.create_hero()
	hero.name = "Hero"
	hero.party_color = Color.WHITE
	hero.is_leader = true
	hero.is_player_controlled = true  # 起動時は hero がプレイヤー操作
	add_child(hero)
	hero.sync_position()

	hero.is_friendly = true  # _assign_orders() で current_order.move を適用するために必要

	party = Party.new()
	party.add_member(hero)
	hero.died.connect(_on_character_died)

	# hero の AI 管理マネージャー（is_player_controlled=false 時に自律行動する）
	_hero_manager = NpcManager.new()
	_hero_manager.name = "HeroManager"
	add_child(_hero_manager)
	_hero_manager.setup_adopted(hero, hero, map_data)
	_hero_manager.set_vision_controlled(true)  # VisionSystem には登録しない
	_hero_manager.activate()


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


func _setup_npcs() -> void:
	if map_data.npc_parties.is_empty():
		return

	# 全敵リストを収集（NPC の攻撃対象として渡す）
	var all_enemies: Array[Character] = []
	for em: EnemyManager in enemy_managers:
		all_enemies.append_array(em.get_enemies())

	var idx := 0
	for np: Variant in map_data.npc_parties:
		var members: Array = (np as Dictionary).get("members", [])
		if members.is_empty():
			continue
		var nm := NpcManager.new()
		nm.name = "NpcManager%d" % idx
		add_child(nm)
		nm.setup(members, hero, map_data)
		nm.set_vision_controlled(true)
		nm.set_enemy_list(all_enemies)
		# カラープールから順番に色を割り当てる
		var color: Color = _NPC_PARTY_COLORS[idx % _NPC_PARTY_COLORS.size()] as Color
		nm.set_party_color(color)
		npc_managers.append(nm)
		idx += 1


## player_parties[0] の 2番目以降のメンバーを NpcManager として配置し、
## 後で _merge_pre_joined_allies() でプレイヤーパーティーに即時合流させる
func _setup_initial_allies() -> void:
	var all_members: Array = []
	if map_data.player_parties.size() > 0:
		all_members = (map_data.player_parties[0] as Dictionary).get("members", [])
	if all_members.size() <= 1:
		return

	var all_enemies: Array[Character] = []
	for em: EnemyManager in enemy_managers:
		all_enemies.append_array(em.get_enemies())

	var color_offset := npc_managers.size()
	for i: int in range(1, all_members.size()):
		var m := all_members[i] as Dictionary
		var nm := NpcManager.new()
		nm.name = "PreJoinedManager%d" % (i - 1)
		add_child(nm)
		nm.setup([m], hero, map_data)
		nm.set_vision_controlled(true)
		nm.set_enemy_list(all_enemies)
		var color := _NPC_PARTY_COLORS[(color_offset + i - 1) % _NPC_PARTY_COLORS.size()] as Color
		nm.set_party_color(color)
		npc_managers.append(nm)
		_pre_joined_npc_managers.append(nm)


## 初期配置の仲間 NpcManager をプレイヤーパーティーに即時合流させる
## _setup_dialogue_system() 後に呼ぶこと
func _merge_pre_joined_allies() -> void:
	for nm: NpcManager in _pre_joined_npc_managers:
		if is_instance_valid(nm):
			# VisionSystem による起動を待たず AI を直接起動してから合流させる
			# （_finish_setup() は同一フレームで完了するため _process() より先に実行される）
			nm.activate()
			_merge_npc_into_player_party(nm)
	_pre_joined_npc_managers.clear()


## 敵・NPC 合算の衝突回避リストを全マネージャーに配布する
## _setup_enemies / _setup_npcs 後に呼ぶこと
func _link_all_character_lists() -> void:
	var all_combatants: Array[Character] = []
	var all_enemies: Array[Character] = []
	for em: EnemyManager in enemy_managers:
		all_combatants.append_array(em.get_enemies())
		all_enemies.append_array(em.get_enemies())
	for nm: NpcManager in npc_managers:
		all_combatants.append_array(nm.get_members())
	for em: EnemyManager in enemy_managers:
		em.set_all_members(all_combatants)
	for nm: NpcManager in npc_managers:
		nm.set_all_members(all_combatants)
	# hero マネージャーにも衝突回避リストと攻撃対象リストを渡す
	if _hero_manager != null:
		_hero_manager.set_all_members(all_combatants)
		_hero_manager.set_enemy_list(all_enemies)


func _setup_controller() -> void:
	player_controller = PlayerController.new()
	player_controller.character = hero
	player_controller.map_data = map_data
	player_controller.map_node = self
	# 敵・NPC を結合して blocking_characters に設定（プレイヤーが重ならないようにする）
	for em: EnemyManager in enemy_managers:
		player_controller.blocking_characters.append_array(em.get_enemies())
	for nm: NpcManager in npc_managers:
		player_controller.blocking_characters.append_array(nm.get_members())
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
	vision_system.set_party(party)
	for em: EnemyManager in enemy_managers:
		vision_system.add_enemy_manager(em)
	for nm: NpcManager in npc_managers:
		vision_system.add_npc_manager(nm)
	vision_system.area_changed.connect(_on_area_changed)
	vision_system.tiles_revealed.connect(queue_redraw)

	# VisionSystem を各マネージャーの LeaderAI に配布（explore 行動で参照する）
	for nm: NpcManager in npc_managers:
		nm.set_vision_system(vision_system)
	for em: EnemyManager in enemy_managers:
		em.set_vision_system(vision_system)
	if _hero_manager != null:
		_hero_manager.set_vision_system(vision_system)


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
# 会話システム
# --------------------------------------------------------------------------

func _setup_dialogue_system() -> void:
	dialogue_trigger = DialogueTrigger.new()
	dialogue_trigger.name = "DialogueTrigger"
	add_child(dialogue_trigger)
	dialogue_trigger.setup(hero, npc_managers, enemy_managers, vision_system, map_data)
	dialogue_trigger.dialogue_requested.connect(_on_dialogue_requested)
	# 矢印キーバンプによる会話トリガーを接続
	if player_controller != null:
		player_controller.npc_bumped.connect(_on_npc_bumped)

	dialogue_window = DialogueWindow.new()
	dialogue_window.name = "DialogueWindow"
	add_child(dialogue_window)
	dialogue_window.choice_confirmed.connect(_on_dialogue_choice)
	dialogue_window.dismissed.connect(_on_dialogue_dismissed)


# --------------------------------------------------------------------------
# 指示システム
# --------------------------------------------------------------------------

func _setup_order_window() -> void:
	order_window = OrderWindow.new()
	order_window.name = "OrderWindow"
	add_child(order_window)
	order_window.setup(party)
	order_window.set_controlled(hero)
	order_window.closed.connect(_on_order_window_closed)
	order_window.switch_requested.connect(_on_switch_character_requested)


## Tab キーで指示ウィンドウを開閉する（プレイヤーがリーダーのときのみ開ける）
func _toggle_order_window() -> void:
	if order_window == null:
		return
	if order_window.visible:
		order_window.close_window()
		return
	# 指示モードはプレイヤーがリーダーのときのみ有効
	if hero == null or not hero.is_leader:
		return
	# 会話中・その他のブロック中は開かない
	if player_controller != null and player_controller.is_blocked:
		return
	player_controller.is_blocked = true
	order_window.open_window()


func _on_order_window_closed() -> void:
	if player_controller != null:
		player_controller.is_blocked = false


## 指示ウィンドウの「切替」を選択したときに呼ばれる
## 操作キャラクターを new_char に切り替え、カメラ・パネルを更新する
func _on_switch_character_requested(new_char: Character) -> void:
	if player_controller == null or not is_instance_valid(new_char):
		return
	var old_char := player_controller.character
	if old_char == new_char:
		return

	# AI フラグ更新（旧操作キャラを AI 制御に戻し、新キャラをプレイヤー操作に切替）
	if old_char != null and is_instance_valid(old_char):
		old_char.is_player_controlled = false
	new_char.is_player_controlled = true

	# PlayerController の担当キャラを切り替え
	player_controller.character = new_char
	player_controller._load_class_slots()

	# blocking_characters を更新（新キャラを除外・旧キャラを追加）
	player_controller.blocking_characters.erase(new_char)
	if old_char != null and is_instance_valid(old_char):
		if not player_controller.blocking_characters.has(old_char):
			player_controller.blocking_characters.append(old_char)

	# カメラを新キャラに即座に切り替え
	if camera_controller != null:
		camera_controller.set_follow_target(new_char)

	# 左パネルのハイライトを更新
	if left_panel != null:
		left_panel.set_active_character(new_char)

	party.set_active(new_char)


func _on_npc_bumped(npc_member: Character) -> void:
	if dialogue_trigger == null or player_controller == null:
		return
	if player_controller.is_blocked:
		return
	dialogue_trigger.try_trigger_for_member(npc_member)


func _on_dialogue_requested(nm: NpcManager, npc_initiates: bool) -> void:
	_dialogue_npc_manager   = nm
	_dialogue_npc_initiates = npc_initiates
	player_controller.is_blocked = true
	# 会話中は対象 NPC の AI を一時停止（メンバーが動き回らないようにする）
	nm.set_process_mode(Node.PROCESS_MODE_DISABLED)
	dialogue_window.show_dialogue(nm, npc_initiates)


func _on_dialogue_choice(choice_id: String) -> void:
	if _dialogue_npc_manager == null or not is_instance_valid(_dialogue_npc_manager):
		_close_dialogue()
		return

	if choice_id == DialogueWindow.CHOICE_CANCEL:
		_close_dialogue()
		return

	# NPC の承諾/拒否判定（NPC が自発的に申し出た場合は常に承諾）
	var accepted := true
	if not _dialogue_npc_initiates:
		var leader_ai := _dialogue_npc_manager.enemy_ai
		if leader_ai != null and is_instance_valid(leader_ai) and leader_ai is NpcLeaderAI:
			var player_strength := _calc_party_strength(party)
			accepted = (leader_ai as NpcLeaderAI).will_accept(choice_id, player_strength)

	if not accepted:
		dialogue_window.show_rejected()
		return

	# 合流処理
	if choice_id == DialogueWindow.CHOICE_JOIN_US:
		_merge_npc_into_player_party(_dialogue_npc_manager)
	elif choice_id == DialogueWindow.CHOICE_JOIN_THEM:
		_merge_player_into_npc_party(_dialogue_npc_manager)

	_close_dialogue()


func _on_dialogue_dismissed() -> void:
	_close_dialogue()


func _close_dialogue() -> void:
	# 一時停止していた NPC の AI を再開（合流後も AI 行動を継続させる）
	if _dialogue_npc_manager != null and is_instance_valid(_dialogue_npc_manager):
		_dialogue_npc_manager.set_process_mode(Node.PROCESS_MODE_INHERIT)
	_dialogue_npc_manager = null
	if player_controller != null:
		player_controller.is_blocked = false
	if dialogue_trigger != null:
		dialogue_trigger.set_dialogue_active(false)
	if dialogue_window != null:
		dialogue_window.hide_dialogue()


## NPC 全員をプレイヤーパーティーに加入させる（プレイヤーがリーダー維持）
func _merge_npc_into_player_party(nm: NpcManager) -> void:
	for member: Character in nm.get_members():
		if is_instance_valid(member) and member.hp > 0:
			party.add_member(member)
			member.visible = true
			# プレイヤーパーティーの白リングに統一。is_leader は false（hero が維持）
			member.party_color = Color.WHITE
			member.is_leader = false
	# VisionSystem の管理から外す（常に表示）
	if vision_system != null:
		vision_system.remove_npc_manager(nm)
	# 再会話を防ぐため npc_managers から除外
	npc_managers.erase(nm)
	# dialogue_trigger の参照リストも更新
	dialogue_trigger.setup(hero, npc_managers, enemy_managers, vision_system, map_data)


## プレイヤー側が NPC パーティーに合流する（NPC リーダーがリーダーになる）
func _merge_player_into_npc_party(nm: NpcManager) -> void:
	var npc_members := nm.get_members()
	# 合流後は NPC のパーティーカラーに統一する
	var new_color: Color = nm.party_color
	# 既存のプレイヤーパーティーメンバー（hero など）を NPC カラーに変更
	for member: Variant in party.members:
		var ch := member as Character
		if is_instance_valid(ch):
			ch.party_color = new_color
			ch.is_leader = false
	# NPC メンバーを追加（カラーは既に nm.party_color 設定済み）
	for member: Character in npc_members:
		if is_instance_valid(member) and member.hp > 0:
			party.add_member(member)
			member.visible = true
	# NPC リーダーをパーティーのアクティブキャラとして設定（左パネルでハイライト）
	if not npc_members.is_empty() and is_instance_valid(npc_members[0] as Character):
		if left_panel != null:
			left_panel.set_active_character(npc_members[0] as Character)
	if vision_system != null:
		vision_system.remove_npc_manager(nm)
	npc_managers.erase(nm)
	dialogue_trigger.setup(hero, npc_managers, enemy_managers, vision_system, map_data)


## パーティーの総合力（最大HP合計）を返す
func _calc_party_strength(p: Party) -> float:
	var total := 0.0
	for m: Variant in p.members:
		var ch := m as Character
		if is_instance_valid(ch):
			total += float(ch.max_hp)
	return total


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
