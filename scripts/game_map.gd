extends Node2D

## グリッドマップ
## タイル描画 + キャラクター生成 + プレイヤー入力制御
## Phase 5: GRID_SIZE動的計算・視界システム・3カラムUIパネル

## タイルセットのベースディレクトリ
const TILE_SET_DIR := "res://assets/images/tiles/"
const DEFAULT_TILE_SET := "stone_00001"

## タイル画像が存在しない場合のフォールバック色
const COLOR_FLOOR         := Color(0.40, 0.40, 0.40)
const COLOR_WALL          := Color(0.20, 0.20, 0.20)
const COLOR_OBSTACLE      := Color(0.55, 0.45, 0.35)
const COLOR_CORRIDOR      := Color(0.30, 0.30, 0.35)
const COLOR_STAIRS_DOWN   := Color(0.60, 0.40, 0.20)
const COLOR_STAIRS_UP     := Color(0.70, 0.60, 0.30)
const COLOR_GRID_LINE     := Color(0.0, 0.0, 0.0, 0.15)

const HANDCRAFTED_JSON_PATH  := "res://assets/master/maps/dungeon_handcrafted.json"
const FALLBACK_JSON_PATH     := "res://assets/master/maps/dungeon_01.json"

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

## フロアごとの生データ（JSON Dictionary）
var _all_floor_data: Array = []
## フロアごとの MapData（インデックス = フロアインデックス）
var _all_map_data: Array[MapData] = []
## フロアごとの EnemyManager リスト（インデックス = フロアインデックス）
var _per_floor_enemies: Array = []  # Array of Array[EnemyManager]
## フロアごとの NpcManager リスト（インデックス = フロアインデックス）
var _per_floor_npcs: Array = []     # Array of Array[NpcManager]
## 現在表示中のフロアインデックス（0 = 最上層）
var _current_floor_index: int = 0
## 階段踏みつけ後のクールダウン（連続遷移防止）
var _stair_cooldown: float = 0.0

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
var consumable_bar: ConsumableBar
var dialogue_trigger: DialogueTrigger
var order_window: OrderWindow

var _tile_set_id: String = DEFAULT_TILE_SET  ## 現在のフロアのタイルセットID
var _tile_textures: Dictionary = {}  # TileType(int) -> Texture2D
## 床に散らばったアイテム（Vector2i → Dictionary）。1マスに1個
var _floor_items: Dictionary = {}
var _item_tex_cache: Dictionary = {}  # image_path -> Texture2D or null
var _dialogue_npc_manager: NpcManager  ## 現在会話中の NpcManager
var _dialogue_npc_initiates: bool = false


func _ready() -> void:
	# 画面サイズから GRID_SIZE を動的計算（最小32px）
	GlobalConstants.initialize(get_viewport().get_visible_rect().size)
	# キャラクター生成の使用済みリストをリセット（F5 再起動対応）
	CharacterGenerator.reset_used()
	_load_handcrafted_dungeon()


func _input(event: InputEvent) -> void:
	# キーボード専用：physical_keycode 直接マッチ（Tab/Esc は action 方式が効かないため）
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_ESCAPE:
				if order_window != null and order_window.visible:
					order_window.close_window()
				else:
					get_tree().quit()
			KEY_TAB:
				_toggle_order_window()
			KEY_F1:
				if MessageLog != null:
					MessageLog.toggle_debug()
			KEY_F2:
				_print_debug_floor_info()
			KEY_F5:
				get_tree().reload_current_scene()


## 手作りダンジョンJSON（dungeon_handcrafted.json）を読み込む
func _load_handcrafted_dungeon() -> void:
	var raw: Variant = JSON.parse_string(_read_file(HANDCRAFTED_JSON_PATH))
	if raw != null and raw is Dictionary:
		var floors: Array = ((raw as Dictionary).get("dungeon", {}) as Dictionary).get("floors", [])
		if not floors.is_empty():
			# 全フロアの MapData を事前構築する
			for fd: Variant in floors:
				var floor_data := fd as Dictionary
				_all_floor_data.append(floor_data)
				_all_map_data.append(DungeonBuilder.build_floor(floor_data))
				_per_floor_enemies.append([])
				_per_floor_npcs.append([])
			_current_floor_index = 0
			map_data = _all_map_data[0]
			_tile_set_id = (_all_floor_data[0] as Dictionary).get("tile_set", DEFAULT_TILE_SET) as String
			_finish_setup()
			return

	push_error("game_map: dungeon_handcrafted.json のパースに失敗しました。フォールバック使用")
	_all_map_data.append(MapData.load_from_json(FALLBACK_JSON_PATH))
	_all_floor_data.append({})
	_per_floor_enemies.append([])
	_per_floor_npcs.append([])
	map_data = _all_map_data[0]
	_finish_setup()


## セットアップ完了（map_dataが確定してから呼ぶ）
func _finish_setup() -> void:
	_load_tile_textures()
	_setup_hero()
	_setup_floor_enemies(_current_floor_index)
	_setup_floor_npcs(_current_floor_index)
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


func _process(delta: float) -> void:
	# 階段クールダウン
	if _stair_cooldown > 0.0:
		_stair_cooldown -= delta
	# PlayerController にクールダウン状態を通知（階段ブロック制御に使用）
	if player_controller != null:
		player_controller.stair_cooldown_active = (_stair_cooldown > 0.0)

	# ゲームパッドアクション（ポーリング方式）
	if Input.is_action_just_pressed("open_order_window"):
		_toggle_order_window()

	# 床アイテムの拾得チェック
	_check_item_pickup()

	# 階段踏み判定
	_check_stairs_step()

	# 会話中に敵が部屋に入ってきたら会話を中断する
	if message_window == null or not message_window.is_dialogue_active():
		return
	if dialogue_trigger == null:
		return
	var area := vision_system.get_current_area() if vision_system != null else ""
	if not dialogue_trigger.is_area_enemy_free(area):
		message_window.show_message("敵の接近により会話が中断された！")
		_close_dialogue()


# --------------------------------------------------------------------------
# セットアップ処理
# --------------------------------------------------------------------------

func _setup_hero() -> void:
	var spawn_pos := Vector2i(2, 2)
	var class_id := "fighter-sword"
	var hero_items: Array = []
	if map_data.player_parties.size() > 0:
		var members: Array = (map_data.player_parties[0] as Dictionary).get("members", [])
		if members.size() > 0:
			var m := members[0] as Dictionary
			spawn_pos  = Vector2i(int(m.get("x", 2)), int(m.get("y", 2)))
			class_id   = m.get("class_id", m.get("character_id", "fighter-sword")) as String
			hero_items = m.get("items",    []) as Array

	hero = Character.new()
	hero.grid_pos = spawn_pos
	hero.placeholder_color = Color(0.3, 0.7, 1.0)
	# CharacterGenerator でランダム生成（他キャラと同様）
	var hero_data := CharacterGenerator.generate_character(class_id)
	hero.character_data = hero_data if hero_data != null else CharacterData.new()
	# 初期装備を付与する
	if hero.character_data != null and not hero_items.is_empty():
		hero.character_data.apply_initial_items(hero_items)
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
	_hero_manager.suppress_ai_log = true  # プレイヤー操作中はログ不要
	_hero_manager.activate()


func _setup_floor_enemies(floor_idx: int) -> void:
	if floor_idx >= _all_map_data.size():
		return
	var fmap := _all_map_data[floor_idx]
	if fmap.enemy_parties.is_empty():
		return

	var fems: Array = _per_floor_enemies[floor_idx] as Array
	# enemy_parties の各パーティーごとに別々の EnemyManager を生成する
	var idx := floor_idx * 100  # ノード名が他フロアと衝突しないようにオフセット
	for ep: Variant in fmap.enemy_parties:
		var members: Array = (ep as Dictionary).get("members", [])
		if members.is_empty():
			continue
		var items: Array = (ep as Dictionary).get("items", [])
		var em := EnemyManager.new()
		em.name = "EnemyManager%d" % idx
		add_child(em)
		em.setup(members, hero, fmap, items)
		em.party_wiped.connect(_on_enemy_party_wiped)
		em.set_vision_controlled(true)
		# スポーン時にフロアインデックスをセット（クロスフロア攻撃防止）
		for ch: Character in em.get_enemies():
			ch.current_floor = floor_idx
		fems.append(em)
		idx += 1

	# 全 EnemyManager の敵を結合したリストを各マネージャーに配布する
	var all_enemies: Array[Character] = []
	for em_v: Variant in fems:
		var em := em_v as EnemyManager
		if em != null:
			all_enemies.append_array(em.get_enemies())
	for em_v: Variant in fems:
		var em := em_v as EnemyManager
		if em != null:
			em.set_all_enemies(all_enemies)

	# 現在フロアなら enemy_managers エイリアスを更新
	if floor_idx == _current_floor_index:
		enemy_managers.clear()
		for em_v2: Variant in fems:
			enemy_managers.append(em_v2 as EnemyManager)


func _setup_floor_npcs(floor_idx: int) -> void:
	if floor_idx >= _all_map_data.size():
		return
	var fmap := _all_map_data[floor_idx]
	if fmap.npc_parties.is_empty():
		return

	# 全敵リストを収集（NPC の攻撃対象として渡す）
	var all_enemies: Array[Character] = []
	for em: EnemyManager in (_per_floor_enemies[floor_idx] as Array):
		all_enemies.append_array(em.get_enemies())

	var fnms: Array = _per_floor_npcs[floor_idx] as Array
	var idx := floor_idx * 100
	for np: Variant in fmap.npc_parties:
		var members: Array = (np as Dictionary).get("members", [])
		if members.is_empty():
			continue
		var nm := NpcManager.new()
		nm.name = "NpcManager%d" % idx
		add_child(nm)
		nm.setup(members, hero, fmap)
		nm.set_vision_controlled(true)
		nm.set_enemy_list(all_enemies)
		var color: Color = _NPC_PARTY_COLORS[idx % _NPC_PARTY_COLORS.size()] as Color
		nm.set_party_color(color)
		# スポーン時にフロアインデックスをセット（クロスフロア攻撃防止）
		for ch: Character in nm.get_members():
			ch.current_floor = floor_idx
		fnms.append(nm)
		idx += 1

	# 現在フロアなら npc_managers エイリアスを更新
	if floor_idx == _current_floor_index:
		npc_managers.clear()
		npc_managers.assign(fnms)


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
			nm.suppress_ai_log = true  # 合流前の一時パーティーのログを抑制
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
	add_child(cam)
	_update_camera_limits(cam)

	camera_controller = CameraController.new()
	camera_controller.character = hero
	camera_controller.camera    = cam
	camera_controller.name      = "CameraController"
	add_child(camera_controller)


## カメラのリミットを現在の map_data に合わせて更新する
func _update_camera_limits(cam: Camera2D) -> void:
	var gs := GlobalConstants.GRID_SIZE
	cam.limit_left   = 0
	cam.limit_right  = map_data.map_width  * gs
	cam.limit_top    = 0
	cam.limit_bottom = map_data.map_height * gs


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

	# MessageLog のエリアフィルタを設定（デバッグログをプレイヤーエリアに限定）
	# nm.activate() より前に設定すること（activate 中に add_ai が呼ばれるため）
	if MessageLog != null:
		MessageLog.setup_area_filter(map_data, func() -> String:
				return vision_system.get_current_area() if vision_system != null else "")

	# NPC パーティーをアクティブ化する。
	# VisionSystem 配布後に呼ぶこと（explore 行動で VisionSystem を参照するため）
	# 訪問済みエリアのNPCのみ即時アクティブ化。未訪問エリアのNPCはVisionSystemが
	# update_visibility() 経由で自動アクティブ化する（プレイヤーが部屋に入ったとき）。
	for nm: NpcManager in npc_managers:
		if nm not in _pre_joined_npc_managers:
			var any_in_visited := false
			for member: Character in nm.get_members():
				if is_instance_valid(member):
					var a := map_data.get_area(member.grid_pos)
					if vision_system.is_area_visited(a):
						any_in_visited = true
						break
			if any_in_visited:
				nm.activate()


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

	# 消耗品バー（部屋名の左側）
	consumable_bar = ConsumableBar.new()
	consumable_bar.name = "ConsumableBar"
	add_child(consumable_bar)
	consumable_bar.update_character(hero)
	if player_controller != null:
		player_controller.consumable_bar = consumable_bar

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

	# MessageWindow の会話シグナルを接続
	if message_window != null:
		message_window.choice_confirmed.connect(_on_dialogue_choice)
		message_window.dialogue_dismissed.connect(_on_dialogue_dismissed)


# --------------------------------------------------------------------------
# 指示システム
# --------------------------------------------------------------------------

func _setup_order_window() -> void:
	order_window = OrderWindow.new()
	order_window.name = "OrderWindow"
	add_child(order_window)
	order_window.setup(party, message_window)
	order_window.set_controlled(hero)
	order_window.closed.connect(_on_order_window_closed)
	order_window.switch_requested.connect(_on_switch_character_requested)


## Tab キーで指示ウィンドウを開閉する（誰を操作中でも開ける・閲覧専用モードあり）
func _toggle_order_window() -> void:
	if order_window == null:
		return
	if order_window.visible:
		order_window.close_window()
		return
	# 会話中・その他のブロック中は開かない
	if player_controller == null:
		return
	if player_controller.is_blocked:
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

	# 消耗品バーを新キャラで更新
	if consumable_bar != null:
		consumable_bar.update_character(new_char)

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

	# NPC パーティー情報をメッセージとして表示
	var npc_name := _get_npc_party_leader_name(nm)
	if npc_initiates:
		message_window.show_message("%s のパーティーが話しかけてきた" % npc_name)
	else:
		message_window.show_message("%s のパーティーに話しかけた" % npc_name)
	# メンバー情報を表示
	for member: Character in nm.get_members():
		if not is_instance_valid(member):
			continue
		var cd: CharacterData = member.character_data
		if cd == null:
			continue
		var ratio := float(member.hp) / float(member.max_hp) if member.max_hp > 0 else 0.0
		var cond := "元気" if ratio > 0.6 else ("負傷" if ratio > 0.3 else "重傷")
		message_window.show_message("  %s [%s] %s (%s)" % [cd.character_name, cd.rank, cd.class_id, cond])

	# 選択肢を構築して MessageWindow で表示
	var choices: Array[Dictionary] = []
	if npc_initiates:
		message_window.show_message("「一緒に連れて行ってもらえないか...」")
		choices.assign([
			{"id": DialogueWindow.CHOICE_JOIN_US, "label": "（承諾する）"},
			{"id": DialogueWindow.CHOICE_CANCEL,  "label": "（断る）"},
		])
	else:
		choices.assign([
			{"id": DialogueWindow.CHOICE_JOIN_US,   "label": "「仲間になってほしい」"},
			{"id": DialogueWindow.CHOICE_JOIN_THEM, "label": "「一緒に連れて行ってほしい」"},
			{"id": DialogueWindow.CHOICE_CANCEL,    "label": "（立ち去る）"},
		])
	message_window.start_dialogue(choices)


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

	var npc_name := _get_npc_party_leader_name(_dialogue_npc_manager)
	message_window.end_dialogue()
	if not accepted:
		message_window.show_rejected("%s は申し出を断った" % npc_name)
		return

	# 合流処理
	if choice_id == DialogueWindow.CHOICE_JOIN_US:
		message_window.show_message("%s のパーティーが仲間に加わった！" % npc_name)
		_merge_npc_into_player_party(_dialogue_npc_manager)
	elif choice_id == DialogueWindow.CHOICE_JOIN_THEM:
		message_window.show_message("%s のパーティーに合流した！" % npc_name)
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
	if message_window != null:
		message_window.end_dialogue()


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


## NPC パーティーのリーダー名を返す
func _get_npc_party_leader_name(nm: NpcManager) -> String:
	for member: Character in nm.get_members():
		if is_instance_valid(member) and member.is_leader:
			if member.character_data != null and not member.character_data.character_name.is_empty():
				return member.character_data.character_name
	# リーダーがいなければ最初の生存メンバー
	for member: Character in nm.get_members():
		if is_instance_valid(member):
			if member.character_data != null and not member.character_data.character_name.is_empty():
				return member.character_data.character_name
	return "NPC"


## パーティーの総合力（最大HP合計）を返す
func _calc_party_strength(p: Party) -> float:
	var total := 0.0
	for m: Variant in p.members:
		var ch := m as Character
		if is_instance_valid(ch):
			total += float(ch.max_hp)
	return total


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


## 敵パーティー全滅シグナルを受け取り、アイテムを部屋の床に散らばらせる（部屋制圧方式）
func _on_enemy_party_wiped(items: Array, room_id: String) -> void:
	# 最終フロア（フロア4, インデックス4）での全滅チェック → ゲームクリア
	var last_floor_index: int = _all_map_data.size() - 1
	if _current_floor_index == last_floor_index:
		var all_wiped := true
		for em_v: Variant in _per_floor_enemies[last_floor_index]:
			var em := em_v as EnemyManager
			if is_instance_valid(em) and not em.get_members().is_empty():
				all_wiped = false
				break
		if all_wiped:
			_trigger_game_clear()

	if items.is_empty():
		return
	# 部屋タイルを取得して FLOORのみに絞り、既存アイテムがないタイルを候補にする
	var candidates: Array[Vector2i] = []
	if room_id.is_empty():
		# エリアIDが取れない場合はドロップをスキップ
		return
	for tile: Vector2i in map_data.get_tiles_in_area(room_id):
		if map_data.get_tile(tile) == MapData.TileType.FLOOR and not _floor_items.has(tile):
			candidates.append(tile)
	if candidates.is_empty():
		return
	# シャッフルして items の数だけタイルを割り当て（最大 candidates.size() 個）
	candidates.shuffle()
	var placed := 0
	for item_v: Variant in items:
		if placed >= candidates.size():
			break
		_floor_items[candidates[placed]] = item_v as Dictionary
		placed += 1
	if placed > 0:
		SoundManager.play(SoundManager.ITEM_GET)
		if message_window != null:
			message_window.show_message("アイテムが部屋に散らばった！（%d個）" % placed)
		queue_redraw()
		print("[GameMap] アイテム %d 個を部屋 %s に散布" % [placed, room_id])


## ゲームクリア処理
func _trigger_game_clear() -> void:
	# 入力を無効化（F5リスタートは game_map._input で KEY_F5 直接マッチのため引き続き有効）
	if player_controller != null:
		player_controller.is_blocked = true
	MessageLog.add_system("ダンジョンを制覇した！冒険者たちの名声は永遠に語り継がれるだろう。")
	print("[GameMap] GAME CLEAR")


## アイテム画像テクスチャをキャッシュ付きで読み込む
func _load_item_texture(image_path: String) -> Texture2D:
	if image_path.is_empty():
		return null
	if _item_tex_cache.has(image_path):
		return _item_tex_cache[image_path] as Texture2D
	var res_path := "res://" + image_path
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = ResourceLoader.load(res_path, "Texture2D") as Texture2D
	_item_tex_cache[image_path] = tex
	return tex


## 床アイテムの拾得チェック（_process から毎フレーム呼ぶ）
func _check_item_pickup() -> void:
	if _floor_items.is_empty() or party == null:
		return
	for member_v: Variant in party.sorted_members():
		var ch := member_v as Character
		if not is_instance_valid(ch) or ch.character_data == null:
			continue
		var pos := ch.grid_pos
		if not _floor_items.has(pos):
			continue
		# item_pickup 指示確認（プレイヤー操作キャラは常に拾う）
		var pickup_order: String = ch.current_order.get("item_pickup", "passive") as String
		if pickup_order == "avoid" and not ch.is_player_controlled:
			continue
		var item := _floor_items[pos] as Dictionary
		ch.character_data.inventory.append(item)
		_floor_items.erase(pos)
		# 操作キャラが消耗品を拾ったら ConsumableBar を更新
		if ch.is_player_controlled and consumable_bar != null \
				and (item.get("category", "") as String) == "consumable":
			consumable_bar.refresh()
		SoundManager.play(SoundManager.ITEM_GET)
		var cname := ch.character_data.character_name \
			if not ch.character_data.character_name.is_empty() else String(ch.name)
		var iname: String = item.get("item_name", "アイテム") as String
		if message_window != null:
			message_window.show_message("%s は %s を拾った" % [cname, iname])
		queue_redraw()


## 階段を踏んでいるかチェックし、踏んでいれば遷移する
func _check_stairs_step() -> void:
	if _stair_cooldown > 0.0:
		return
	if hero == null or not is_instance_valid(hero):
		return
	if hero.is_moving():
		return
	var tile := map_data.get_tile(hero.grid_pos)
	if tile == MapData.TileType.STAIRS_DOWN:
		_transition_floor(1)
	elif tile == MapData.TileType.STAIRS_UP:
		_transition_floor(-1)


## フロアを遷移する
## direction: +1 = 下（次フロア）、-1 = 上（前フロア）
func _transition_floor(direction: int) -> void:
	var new_floor := _current_floor_index + direction
	if new_floor < 0 or new_floor >= _all_map_data.size():
		return

	_stair_cooldown = 1.5  # 遷移直後の再遷移を防ぐ

	# ターゲットフロアの MapData を取得
	var new_map := _all_map_data[new_floor]

	# スポーン位置を決定（反対方向の階段タイル）
	var spawn_tile_type := MapData.TileType.STAIRS_UP if direction > 0 else MapData.TileType.STAIRS_DOWN
	var spawns := new_map.find_stairs(spawn_tile_type)
	var spawn_pos: Vector2i
	if not spawns.is_empty():
		spawn_pos = spawns[0]
	else:
		# フォールバック：入口部屋の中心（MapData の player_parties から取得）
		if not new_map.player_parties.is_empty():
			var first_member: Variant = ((new_map.player_parties[0] as Dictionary).get("members", []) as Array)
			if first_member is Array and (first_member as Array).size() > 0:
				var m := (first_member as Array)[0] as Dictionary
				spawn_pos = Vector2i(int(m.get("x", 5)), int(m.get("y", 5)))
			else:
				spawn_pos = Vector2i(5, 5)
		else:
			spawn_pos = Vector2i(5, 5)

	# 現在フロアのマネージャーを非表示・VisionSystem から除外
	for em: EnemyManager in enemy_managers:
		if is_instance_valid(em):
			vision_system.remove_enemy_manager(em)
	for nm: NpcManager in npc_managers:
		if is_instance_valid(nm):
			vision_system.remove_npc_manager(nm)

	# フロア切替
	_current_floor_index = new_floor
	map_data = new_map
	_tile_set_id = (_all_floor_data[new_floor] as Dictionary).get("tile_set", DEFAULT_TILE_SET) as String
	_load_tile_textures()

	# hero のフロア更新・移動
	hero.current_floor = new_floor
	hero.grid_pos      = spawn_pos
	hero.sync_position()

	# 新フロアの敵・NPC がまだセットアップされていなければ行う
	if (_per_floor_enemies[new_floor] as Array).is_empty() \
			and not new_map.enemy_parties.is_empty():
		_setup_floor_enemies(new_floor)
	if (_per_floor_npcs[new_floor] as Array).is_empty() \
			and not new_map.npc_parties.is_empty():
		_setup_floor_npcs(new_floor)

	# エイリアスを新フロアの管理リストに更新
	enemy_managers.clear()
	enemy_managers.assign(_per_floor_enemies[new_floor] as Array)
	npc_managers.clear()
	# パーティーに合流済みのNPCを除いた残りをセット
	npc_managers.assign(_per_floor_npcs[new_floor] as Array)

	# VisionSystem に新フロアのマネージャーを追加
	for em: EnemyManager in enemy_managers:
		if is_instance_valid(em):
			vision_system.add_enemy_manager(em)
			em.set_vision_system(vision_system)
	for nm: NpcManager in npc_managers:
		if is_instance_valid(nm):
			vision_system.add_npc_manager(nm)
			nm.set_vision_system(vision_system)
			# 訪問済みエリアのNPCのみ即時アクティブ化。未訪問エリアのNPCはVisionSystemが自動アクティブ化する

	# VisionSystem をフロア切替（switch_floor で開始エリアが訪問済みになる）
	vision_system.switch_floor(new_floor, new_map, hero)

	# switch_floor 後に訪問済みエリアが確定したのでNPCをアクティブ化する
	for nm: NpcManager in npc_managers:
		if is_instance_valid(nm):
			var any_in_visited := false
			for member: Character in nm.get_members():
				if is_instance_valid(member):
					var a := new_map.get_area(member.grid_pos)
					if vision_system.is_area_visited(a):
						any_in_visited = true
						break
			if any_in_visited:
				nm.activate()

	# PlayerController の参照を更新
	if player_controller != null:
		player_controller.map_data = new_map
		# 遷移直後フラグをセット（遷移先の階段タイルで即再遷移しないよう移動を許可）
		player_controller.stair_just_transitioned = true
		# blocking_characters を新フロアの敵・NPC で再構築（フロア間すり抜け防止）
		player_controller.blocking_characters.clear()
		for em: EnemyManager in enemy_managers:
			if is_instance_valid(em):
				player_controller.blocking_characters.append_array(em.get_enemies())
		for nm: NpcManager in npc_managers:
			if is_instance_valid(nm):
				player_controller.blocking_characters.append_array(nm.get_members())
		# 同フロアのパーティーメンバー（hero 以外）も追加
		for member_var: Variant in party.members:
			var ch := member_var as Character
			if is_instance_valid(ch) and ch != hero \
					and ch.current_floor == _current_floor_index:
				player_controller.blocking_characters.append(ch)

	# カメラのリミットを更新
	if camera_controller != null and is_instance_valid(camera_controller):
		var cam := camera_controller.camera
		if cam != null and is_instance_valid(cam):
			_update_camera_limits(cam)

	# キャラクターの表示を更新（フロアが違うキャラを非表示）
	_update_character_visibility()

	# ダイアログ強制クローズ
	if message_window != null and message_window.is_dialogue_active():
		_close_dialogue()

	var dir_str := "下" if direction > 0 else "上"
	if message_window != null:
		message_window.show_message("階段を%sに進んだ（%dF）" % [dir_str, new_floor + 1])

	queue_redraw()


## フロアに応じてキャラクターの表示/非表示を切り替える
func _update_character_visibility() -> void:
	# 全フロアの敵を走査
	for fi: int in range(_per_floor_enemies.size()):
		var is_current := (fi == _current_floor_index)
		for em: EnemyManager in (_per_floor_enemies[fi] as Array):
			if is_instance_valid(em):
				for ch: Character in em.get_enemies():
					if is_instance_valid(ch):
						# 表示は VisionSystem が制御するため、
						# 別フロアの敵は強制非表示
						if not is_current:
							ch.visible = false
	# NPC
	for fi: int in range(_per_floor_npcs.size()):
		var is_current := (fi == _current_floor_index)
		for nm: NpcManager in (_per_floor_npcs[fi] as Array):
			if is_instance_valid(nm):
				for ch: Character in nm.get_members():
					if is_instance_valid(ch):
						if not is_current:
							ch.visible = false
	# パーティーメンバー（hero 以外）：current_floor が一致するフロアのみ表示
	if party != null:
		for member_var: Variant in party.members:
			var ch := member_var as Character
			if is_instance_valid(ch) and ch != hero:
				ch.visible = (ch.current_floor == _current_floor_index)


## F2 デバッグ情報をファイルに書き出す（フルスクリーン実行対応）
## 出力先: user://debug_floor_info.txt
func _print_debug_floor_info() -> void:
	var lines: PackedStringArray = []
	lines.append("=== DEBUG FLOOR INFO ===")
	lines.append("current_floor: %d" % _current_floor_index)

	lines.append("")
	lines.append("--- Characters ---")
	# プレイヤーパーティー
	for member: Variant in party.members:
		var ch := member as Character
		if not is_instance_valid(ch):
			continue
		var cname := ch.character_data.character_name if ch.character_data != null else "?"
		lines.append("  [%s] floor=%d grid_pos=%s visible=%s is_active=true (player_party)" % [
			cname, ch.current_floor, str(ch.grid_pos), str(ch.visible)])
	# 全フロアの敵
	for fi: int in range(_per_floor_enemies.size()):
		for em: EnemyManager in (_per_floor_enemies[fi] as Array):
			if not is_instance_valid(em):
				continue
			var active := em.is_active()
			for ch: Character in em.get_enemies():
				if not is_instance_valid(ch):
					continue
				var cname := ch.character_data.character_name if ch.character_data != null else "?"
				lines.append("  [%s] floor=%d grid_pos=%s visible=%s is_active=%s" % [
					cname, fi, str(ch.grid_pos), str(ch.visible), str(active)])
	# 全フロアのNPC
	for fi: int in range(_per_floor_npcs.size()):
		for pm: NpcManager in (_per_floor_npcs[fi] as Array):
			if not is_instance_valid(pm):
				continue
			var active := pm.is_active()
			for ch: Character in pm.get_members():
				if not is_instance_valid(ch):
					continue
				var cname := ch.character_data.character_name if ch.character_data != null else "?"
				lines.append("  [%s(NPC)] floor=%d grid_pos=%s visible=%s is_active=%s" % [
					cname, fi, str(ch.grid_pos), str(ch.visible), str(active)])

	lines.append("")
	lines.append("--- Occupied Tiles (floor別) ---")
	for fi: int in range(_per_floor_enemies.size()):
		var tiles: Array[Vector2i] = []
		for em: EnemyManager in (_per_floor_enemies[fi] as Array):
			if not is_instance_valid(em):
				continue
			for ch: Character in em.get_enemies():
				if is_instance_valid(ch) and ch.hp > 0:
					for t: Vector2i in ch.get_occupied_tiles():
						tiles.append(t)
		if fi < _per_floor_npcs.size():
			for pm: NpcManager in (_per_floor_npcs[fi] as Array):
				if not is_instance_valid(pm):
					continue
				for ch: Character in pm.get_members():
					if is_instance_valid(ch) and ch.hp > 0:
						for t: Vector2i in ch.get_occupied_tiles():
							tiles.append(t)
		if fi == _current_floor_index:
			for member: Variant in party.members:
				var ch := member as Character
				if is_instance_valid(ch) and ch.hp > 0:
					for t: Vector2i in ch.get_occupied_tiles():
						tiles.append(t)
		lines.append("floor %d: %s" % [fi, str(tiles)])

	lines.append("")
	lines.append("--- Passable Check (blocking_characters) ---")
	if player_controller != null:
		lines.append("blocking_characters count: %d" % player_controller.blocking_characters.size())
		var invalid_count := 0
		for ch: Character in player_controller.blocking_characters:
			if not is_instance_valid(ch):
				invalid_count += 1
		lines.append("  invalid entries: %d" % invalid_count)
		var occupied: Array[Vector2i] = []
		for ch: Character in player_controller.blocking_characters:
			if is_instance_valid(ch):
				for t: Vector2i in ch.get_occupied_tiles():
					occupied.append(t)
		lines.append("  occupied by blocking_characters: %s" % str(occupied))
	lines.append("========================")

	# ファイルに書き出す
	var path := "user://debug_floor_info.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		for line: String in lines:
			file.store_line(line)
		file.close()
		var abs_path := ProjectSettings.globalize_path(path)
		if message_window != null:
			message_window.show_message("[DEBUG] F2: %s に出力しました" % abs_path)
	else:
		if message_window != null:
			message_window.show_message("[DEBUG] F2: ファイル書き込み失敗")


## タイル画像をプリロードする（画像がない場合はフォールバック色を使用）
func _load_tile_textures() -> void:
	_tile_textures.clear()
	var base := TILE_SET_DIR + _tile_set_id + "/"
	var names := {
		MapData.TileType.FLOOR:       "floor.png",
		MapData.TileType.WALL:        "wall.png",
		MapData.TileType.OBSTACLE:    "obstacle.png",
		MapData.TileType.CORRIDOR:    "corridor.png",
		MapData.TileType.STAIRS_DOWN: "stairs_down.png",
		MapData.TileType.STAIRS_UP:   "stairs_up.png",
	}
	for tile_type: int in names:
		var path: String = base + (names[tile_type] as String)
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_tile_textures[tile_type] = _crop_single_tile(tex)
	# corridor.png がない場合は floor.png にフォールバック
	if not _tile_textures.has(MapData.TileType.CORRIDOR) \
			and _tile_textures.has(MapData.TileType.FLOOR):
		_tile_textures[MapData.TileType.CORRIDOR] = _tile_textures[MapData.TileType.FLOOR]


## タイル画像の左上1/4を切り出して使用する
## 高解像度画像（1024x1024）をそのままセルに縮小するとパターンが細かくなりすぎるため、
## 1/4領域を切り出すことで1セルに対して適切な密度で表示する
## 512px以下の画像はそのまま返す
func _crop_single_tile(tex: Texture2D) -> Texture2D:
	var size := tex.get_size()
	var tile_size := mini(int(size.x), int(size.y)) / 2
	# 512px以下の画像は1タイル分とみなしてそのまま返す
	if tile_size <= 256:
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, 0, tile_size, tile_size)
	return atlas


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
					MapData.TileType.FLOOR:        fill_color = COLOR_FLOOR
					MapData.TileType.OBSTACLE:     fill_color = COLOR_OBSTACLE
					MapData.TileType.CORRIDOR:     fill_color = COLOR_CORRIDOR
					MapData.TileType.STAIRS_DOWN:  fill_color = COLOR_STAIRS_DOWN
					MapData.TileType.STAIRS_UP:    fill_color = COLOR_STAIRS_UP
					_:                             fill_color = COLOR_WALL
				draw_rect(rect, fill_color)

			draw_rect(rect, COLOR_GRID_LINE, false)

			# 階段タイルにシンボルを描画
			if tile == MapData.TileType.STAIRS_DOWN or tile == MapData.TileType.STAIRS_UP:
				var sym := "▼" if tile == MapData.TileType.STAIRS_DOWN else "▲"
				var sym_color := Color(1.0, 0.95, 0.7, 0.9)
				var font := ThemeDB.fallback_font
				if font != null:
					var fsize := int(float(gs) * 0.45)
					var cx := float(x * gs) + float(gs) * 0.5
					var cy := float(y * gs) + float(gs) * 0.7
					draw_string(font, Vector2(cx - float(fsize) * 0.3, cy),
						sym, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, sym_color)

	# 床アイテムを描画（訪問済みタイルのみ）
	for tile_v: Variant in _floor_items.keys():
		var ipos  := tile_v as Vector2i
		if use_vision and not visible_tiles.has(ipos):
			continue
		var item      := _floor_items[ipos] as Dictionary
		var img_path  := item.get("image", "") as String
		# image フィールドがない場合は item_type から導出
		if img_path.is_empty():
			var itype := item.get("item_type", "") as String
			if not itype.is_empty():
				img_path = "assets/images/items/" + itype + ".png"
		var irect     := Rect2(ipos.x * gs + gs * 0.15, ipos.y * gs + gs * 0.15,
			gs * 0.70, gs * 0.70)
		var tex := _load_item_texture(img_path)
		if tex != null:
			draw_texture_rect(tex, irect, false)
		else:
			draw_rect(irect, Color(1.0, 0.85, 0.15, 0.90))
			draw_rect(irect, Color(1.0, 1.0, 0.5, 0.70), false, 1)
