class_name PartyLeader
extends Node

## パーティーリーダー基底クラス
## パーティー全体の戦略を決定し、各メンバーの UnitAI に指示を伝達する。
## PartyLeaderAI（AI自動判断）と PartyLeaderPlayer（プレイヤー操作）が継承する。
##
## サブクラスがオーバーライドするフック:
##   _create_unit_ai()          : メンバーに対応する UnitAI の種別を返す
##   _evaluate_party_strategy() : パーティー全体の戦略判断
##   _select_target_for()       : メンバーごとの攻撃ターゲット選択
##   _select_weakest_target()   : 最弱ターゲット選択（複数候補がある場合）
##   _evaluate_strategic_status(): 統合戦略評価（full_party / nearby_allied / nearby_enemy の 3 集合で戦力・戦況を算出）
##   _get_opposing_characters() : 対立キャラリストを返す（敵AI=friendly_list、味方AI=enemy_list）

## パーティー戦略（ATTACK=0, FLEE=1, WAIT=2 は UnitAI.Strategy と int 値一致）
## DEFEND=3, EXPLORE=4, GUARD_ROOM=5 はパーティーレベル専用（UnitAI へは WAIT/ATTACK+move に変換して渡す）
enum Strategy { ATTACK, FLEE, WAIT, DEFEND, EXPLORE, GUARD_ROOM }

const REEVAL_INTERVAL := 1.5  ## 定期再評価の間隔（秒）

## ランク文字列 → スコア数値の変換テーブル（C=3, B=4, A=5, S=6）
const RANK_VALUES: Dictionary = { "C": 3, "B": 4, "A": 5, "S": 6 }

var _party_members: Array[Character] = []
var _player:        Character
var _map_data:      MapData
var _unit_ais:      Dictionary = {}  ## member.name -> UnitAI
var _party_strategy: Strategy = Strategy.WAIT
var _prev_strategy:  Strategy = Strategy.WAIT  ## 前回の戦略（変更検出用）
var _combat_situation: Dictionary = {}  ## 最新の戦略評価結果（_evaluate_strategic_status の戻り値）
var log_enabled:     bool  = true  ## false にするとログ出力を抑制する（一時パーティー用）
var joined_to_player: bool = false ## true の場合は _player を隊形基準として使用する（合流済み NPC パーティー）
var _reeval_timer:   float = 0.0
var _initial_count:  int   = 0  ## 初期メンバー数（逃走判定の基準）
var _friendly_list:  Array[Character] = []  ## 攻撃対象の友好キャラ一覧（敵 AI 用）
var _visited_areas:  Dictionary = {}  ## 訪問済みエリアID集合（全 UnitAI で共有）
## パーティー全体方針（Party.global_orders の参照。hp_potion/sp_mp_potion 等を UnitAI に伝達）
## set_global_orders() で Party.global_orders dict への参照を受け取る（参照共有なので変更が反映される）
var _global_orders:  Dictionary = {}
var _party_ref: Party = null  ## プレイヤーパーティー参照（合流済みNPC含む。戦況判断の自軍メンバー評価に使用）

## FLEE 時の推奨出口タイル（2026-04-21 ステップ 3 追加）
## パーティー FLEE 時にリーダーが決定し、`_assign_orders()` 経由で全メンバーに配布する。
## 各メンバーはこの座標を軽いバイアスで優先しつつ、自分の位置から最適な出口を選ぶ。
## Vector2i(-1, -1) = 推奨なし（パーティー FLEE でない・計算失敗）
var _flee_recommended_goal: Vector2i = Vector2i(-1, -1)

## 選ばれた避難先エリア ID（2026-04-21 追加・PartyStatusWindow 表示用）
## 空文字 = 避難先未決定 or フォールバック
var _flee_refuge_area_id: String = ""
## 出口 → 避難先エリアまでの BFS ホップ数（-1 = 未決定）
var _flee_refuge_distance: int = -1
## フォールバック経路を通ったか（避難先エリア不明・到達不能で脅威コスト最小の出口を選んだ）
var _flee_is_fallback: bool = false

## 前回 `_flee_recommended_goal` を再評価した時刻（Time.get_ticks_msec()/1000.0 ベース）
## エリア変化時の強制再評価のクールダウン管理に使用
var _flee_last_reeval_time: float = -INF


## プレイヤーパーティー参照を設定する（プレイヤー・合流済みNPCパーティー両方で使用）
func set_party_ref(party: Party) -> void:
	_party_ref = party


# --------------------------------------------------------------------------
# セットアップ
# --------------------------------------------------------------------------

## メンバー・プレイヤー・マップデータをセットアップし、各メンバーの UnitAI を生成する
func setup(members: Array[Character], player: Character, map_data: MapData,
		all_members: Array[Character]) -> void:
	_party_members = members
	_player        = player
	_map_data      = map_data
	_initial_count = members.size()
	# 連合判定で参照する全パーティー合算リスト。
	# activate() が _link_all_character_lists() より後に呼ばれる NPC 向けに、
	# setup 引数の all_members を self._all_members に代入して未伝播を防ぐ。
	_all_members   = all_members

	# メンバーごとに UnitAI を生成してノードツリーに追加（_process が動くようにする）
	for member: Character in members:
		var unit_ai := _create_unit_ai(member)
		unit_ai.name = "UnitAI_" + member.name
		add_child(unit_ai)
		unit_ai.setup(member, player, map_data, all_members)
		unit_ai.set_party_peers(members)  ## heal/buff は自パーティーメンバー限定
		unit_ai.set_follow_hero_floors(joined_to_player)  ## 合流済みメンバーのみ hero をフロア追従
		unit_ai.set_visited_areas(_visited_areas)  ## 訪問済みエリア（パーティー全員で共有）
		_unit_ais[member.name] = unit_ai

	# 初回オーダー発行
	_assign_orders()


# --------------------------------------------------------------------------
# セッター群（PartyManager / game_map から呼ばれる）
# --------------------------------------------------------------------------

## 攻撃対象となる友好キャラ一覧を設定する（敵 AI のターゲット選択に使用）
func set_friendly_list(friendlies: Array[Character]) -> void:
	_friendly_list = friendlies


## Party.global_orders への参照を受け取る（GDScript では Dictionary は参照型のため変更が自動反映）
## game_map が PartyManager セットアップ時に呼ぶ
func set_global_orders(orders: Dictionary) -> void:
	_global_orders = orders


## joined_to_player を各 UnitAI の _follow_hero_floors に伝播する
## PartyManager.set_joined_to_player() 経由で呼ばれる
func set_follow_hero_floors(value: bool) -> void:
	joined_to_player = value
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_follow_hero_floors(value)


## 全パーティー合算メンバーリスト（戦況判断で同陣営他パーティーの戦力加算に使用）
var _all_members: Array[Character] = []


## 全パーティー合算メンバーリストを各 UnitAI に反映する
func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_all_members(all_members)


## VisionSystem を各 UnitAI に配布する（explore 移動方針に必要）
func set_vision_system(vs: VisionSystem) -> void:
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_vision_system(vs)


## MapData を更新し各 UnitAI に反映する（フロア遷移時に game_map から呼ばれる）
func set_map_data(new_map_data: MapData) -> void:
	_map_data = new_map_data
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_map_data(new_map_data)


## 特定メンバーの UnitAI の map_data のみ更新する（個別フロア遷移時に使用）
func set_member_map_data(member_name: String, new_map_data: MapData) -> void:
	var unit_ai := _unit_ais.get(member_name) as UnitAI
	if unit_ai != null:
		unit_ai.set_map_data(new_map_data)


## デバッグウィンドウ用: 指定メンバーの行動目的の短い説明を返す
func get_member_goal_str(member_name: String) -> String:
	var unit_ai := _unit_ais.get(member_name) as UnitAI
	if unit_ai == null:
		return ""
	return unit_ai.get_debug_goal_str()


## デバッグウィンドウ用: 指定メンバーの UnitAI を返す（PartyStatusWindow の詳細表示用）
## 内部状態（_state / _timer / _queue 等）を直接参照するための窓口。null 可
func get_unit_ai(member_name: String) -> UnitAI:
	return _unit_ais.get(member_name) as UnitAI


## フロアアイテム辞書の参照を全 UnitAI に配布する（game_map から呼ばれる）
func set_floor_items(items: Dictionary) -> void:
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_floor_items(items)


# --------------------------------------------------------------------------
# 定期処理
# --------------------------------------------------------------------------

## リーダーの前回フロア（変化検知用。リーダーが階段で別フロアに移動したら全メンバーに通知）
var _prev_leader_floor: int = -999

func _process(delta: float) -> void:
	# 時間停止中（プレイヤーのターゲット選択中など）は再評価を止める
	if not GlobalConstants.world_time_running:
		return

	# リーダーのフロア変化を検知し、全メンバーに即時再評価を促す
	# （非リーダーが wait 中でも 3 秒待たずに階段追従に切り替わる）
	var leader_floor := -999
	for lm: Character in _party_members:
		if is_instance_valid(lm) and lm.is_leader:
			leader_floor = lm.current_floor
			break
	if leader_floor != _prev_leader_floor:
		if _prev_leader_floor != -999:
			# 初回以外: 全 UnitAI に状況変化を通知（wait 中のキューを破棄して再評価）
			for ua_v: Variant in _unit_ais.values():
				var ua := ua_v as UnitAI
				if ua != null:
					ua.notify_situation_changed()
			# PartyLeader 自身も即時再評価する
			_reeval_timer = 0.0
		_prev_leader_floor = leader_floor

	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = REEVAL_INTERVAL
		_combat_situation = _evaluate_strategic_status()
		_assign_orders()


# --------------------------------------------------------------------------
# 指示伝達（共通ロジック）
# --------------------------------------------------------------------------

## 戦略を評価して各メンバーにオーダーを発行する
## パーティー戦略に応じて move / combat / party_fleeing を決定し UnitAI に渡す
## 行動の最終決定は UnitAI._determine_effective_action() が行う
##
## 2026-04-21 改訂：`_party_strategy` は敵パーティー（EnemyLeaderAI 系）専用概念に変更。
## 味方（PartyLeaderPlayer / NpcLeaderAI）では戦略評価・更新を行わず、個別指示は
## `_global_orders.battle_policy` のプリセット流し込み（OrderWindow）経由のみで反映する。
## 詳細: docs/investigation_party_strategy_ally_removal.md / docs/investigation_receive_order_keys.md
func _assign_orders() -> void:
	# 戦略評価は敵パーティーのみ実施する（味方は _party_strategy を使わない）
	var is_enemy_party := _is_enemy_party()
	if is_enemy_party:
		_party_strategy = _apply_range_check(_evaluate_party_strategy())

		# 戦略変更時にログ出力
		if _party_strategy != _prev_strategy:
			var old_strategy := _prev_strategy
			_prev_strategy = _party_strategy
			if log_enabled and not _has_player_controlled_member():
				_log_strategy_change(old_strategy)

	# パーティーレベルの撤退判断（敵専用フラグ・味方は常に false）
	var party_fleeing := is_enemy_party and _party_strategy == Strategy.FLEE

	# FLEE 推奨出口を更新（2026-04-21 ステップ 3）：
	# 味方は battle_policy=="retreat"、敵は _party_strategy==FLEE のときに推奨出口を算出する
	_update_flee_recommended_goal()

	# リーダーのターゲットを先に決定（same_as_leader ポリシー用）
	var leader_target: Character = null
	for lm: Character in _party_members:
		if is_instance_valid(lm):
			leader_target = _select_target_for(lm)
			break

	# リーダーキャラクター（UnitAI の formation 計算に使用）
	var leader_char: Character = null
	for lm: Character in _party_members:
		if is_instance_valid(lm) and lm.is_leader:
			leader_char = lm
			break
	if leader_char == null and not _party_members.is_empty():
		for lm: Character in _party_members:
			if is_instance_valid(lm):
				leader_char = lm
				break

	# パーティーレベルの指示参照（hp_potion / sp_mp_potion / move 等）
	## 2026-04-23：NPC（未加入）は `_global_orders` が空なので、`_build_orders_part()` の
	## サブクラスデフォルト（`hp_potion="use"` 等）を AI 実動にも反映させる。
	## 従来は `_global_orders.get("hp_potion", "never")` で常に "never" に落ち、
	## NPC がポーション自動使用しない不具合があった
	var party_orders: Dictionary = _build_orders_part()

	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue

		var order          := member.current_order
		var combat         : String = order.get("combat",          "attack")
		var on_low_hp      : String = order.get("on_low_hp",       "fall_back")
		var tgt_policy     : String = order.get("target",          "same_as_leader")
		var battle_form    : String = order.get("battle_formation", "surround")

		# ── 移動方針設定 ──────────────────────────────────────────────────
		var move_policy  : String    = "spread"
		var formation_ref: Character = null
		if member.is_friendly:
			move_policy = party_orders.get("move", order.get("move", "same_room")) as String
			if leader_char == null or leader_char == member:
				if _player != null and is_instance_valid(_player) \
						and (leader_char == _player or joined_to_player):
					formation_ref = _player
			else:
				formation_ref = leader_char

		# ── 探索モード / 帰還モードに応じた移動方針の上書き ────────────────
		## _is_in_explore_mode() / _is_in_guard_room_mode() はサブクラスが override する
		## 敵：`_party_strategy == EXPLORE / GUARD_ROOM` で判定（PartyLeader 基底実装）
		## NPC：敵検知フラグで explore を判定（NpcLeaderAI.override）
		## GUARD_ROOM は敵専用（縄張り範囲外から帰還する）ので味方では常に false
		if _is_in_explore_mode():
			if not joined_to_player:
				var pol := _get_explore_move_policy()
				if pol == "stairs_down" or pol == "stairs_up":
					if member == leader_char:
						move_policy = pol
					else:
						move_policy = "cluster"
				elif member == leader_char:
					move_policy = "explore"
				else:
					move_policy = "cluster"
		elif _is_in_guard_room_mode():
			move_policy = "guard_room"

		# 注：2026-04-21 以前は `on_low_hp=retreat + HP低下 → move_policy=cluster` 上書きがここにあったが、
		# on_low_hp=fall_back は UnitAI 側で `_STRATEGY_FALL_BACK` を返し `fall_back` アクションキューを
		# 直接生成するようになったため、ここでの move_policy 上書きは不要（strategy=FALL_BACK 分岐が
		# move_policy を無視して fall_back 実行に進むため）。

		# ── ターゲット選択 ────────────────────────────────────────────────
		var target: Character
		match tgt_policy:
			"nearest":
				target = _select_target_for(member)
			"weakest":
				target = _select_weakest_target(member)
			"same_as_leader":
				target = leader_target if leader_target != null \
					else _select_target_for(member)
			"support":
				target = _select_support_target(member)
			_:
				target = _select_target_for(member)

		# クロスフロアターゲット排除
		if target != null and is_instance_valid(target) \
				and target.current_floor != member.current_floor:
			target = null

		# フロア間追従は UnitAI 側（_generate_move_queue）で move_policy が
		# cluster/follow/same_room の場合に判定する（リーダーが別フロアなら階段へ）
		# ここで move_policy を上書きすることはしない

		unit_ai.receive_order({
			"target":            target,
			"combat":            combat,
			"on_low_hp":         on_low_hp,
			"move":              move_policy,
			"battle_formation":  battle_form,
			"leader":            formation_ref,
			"party_fleeing":     party_fleeing,
			"hp_potion":         party_orders.get("hp_potion",    "never") as String,
			"sp_mp_potion":      party_orders.get("sp_mp_potion", "never") as String,
			"item_pickup":       member.current_order.get("item_pickup", "passive") as String,
			"special_skill":     order.get("special_skill", "strong_enemy") as String,
			"combat_situation":  _combat_situation,
			"flee_recommended_goal": _flee_recommended_goal,
		})


# --------------------------------------------------------------------------
# 通知・デバッグ
# --------------------------------------------------------------------------

## 状況変化通知（PartyManager から呼ばれる）：即座に再評価してオーダーを発行する
func notify_situation_changed() -> void:
	_reeval_timer = 0.0
	_combat_situation = _evaluate_strategic_status()
	_assign_orders()
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.notify_situation_changed()


## パーティーレベルのデバッグ情報を返す
func get_party_debug_info() -> Dictionary:
	return {
		"party_strategy": int(_party_strategy),
		"alive_count":    _party_members.size(),
		"initial_count":  _initial_count,
	}


## 初期メンバー数を返す（セットアップ時の人数・死亡後も不変）
## PartyStatusWindow の「生存:X/Y」表示の分母（Y）に使用
func get_initial_count() -> int:
	return _initial_count


## 推奨出口タイルを返す（PartyStatusWindow 表示用・パーティー FLEE 中のみ有効値）
func get_flee_recommended_goal() -> Vector2i:
	return _flee_recommended_goal


# --------------------------------------------------------------------------
# FLEE 推奨出口決定ロジック（2026-04-21 ステップ 3 追加）
# --------------------------------------------------------------------------

## 現在のパーティーが FLEE 状態か判定する
## 味方: `_global_orders.battle_policy == "retreat"`（OrderWindow 手動 or NpcLeaderAI 自動書き換え）
## 敵: `_party_strategy == Strategy.FLEE`（Goblin/Wolf の HP 低下時など）
func _is_party_fleeing() -> bool:
	if _is_enemy_party():
		return _party_strategy == Strategy.FLEE
	return _global_orders.get("battle_policy", "") == "retreat"


## `_flee_recommended_goal` を更新する（`_assign_orders()` から毎回呼ばれる）
## パーティー FLEE 中のみ算出・それ以外は全避難先情報を初期値にクリア
func _update_flee_recommended_goal() -> void:
	if not _is_party_fleeing():
		_flee_recommended_goal = Vector2i(-1, -1)
		_flee_refuge_area_id   = ""
		_flee_refuge_distance  = -1
		_flee_is_fallback      = false
		return
	_flee_recommended_goal = _determine_flee_recommended_goal()


## パーティー FLEE 時の推奨出口タイルを決定する
##
## アルゴリズム：
##   1. リーダーの現在位置とエリアを取得
##   2. 現フロアの避難先エリア一覧（フロア 0 = 安全部屋 / フロア 1 以降 = 上り階段エリア）を取得
##   3. 現エリアの全内側出口タイルを列挙
##   4. 各出口について：
##      a. リーダー UnitAI の `_astar_with_cost()` で脅威コスト付き到達コストを計算
##      b. 出口の向こう側エリアから最近い避難先エリアまでの BFS 距離を計算（選ばれた refuge_area も併記録）
##      c. 総合コスト = 到達コスト + BFS距離 × FLEE_AREA_DISTANCE_WEIGHT
##   5. 最小コストの出口を選び、対応する避難先エリア ID / BFS 距離を `_flee_refuge_*` フィールドに記録
##
## フォールバック条件（`_flee_is_fallback = true`）:
##   - 避難先エリア一覧が空（フロア 0 で安全部屋なし・フロア 1+ で上り階段なし）
##   - 選ばれた出口から避難先に到達不能（BFS 経路なし）
##   - 全出口が A* 失敗で到達不能
##
## A* 呼び出しは「リーダーの UnitAI」経由で行う（walker コンテキスト = is_friendly / is_flying 等が必要なため）
func _determine_flee_recommended_goal() -> Vector2i:
	# 毎回リセット（クリーンな状態で始める）
	_flee_refuge_area_id  = ""
	_flee_refuge_distance = -1
	_flee_is_fallback     = false

	if _map_data == null:
		_flee_is_fallback = true
		return Vector2i(-1, -1)
	var leader_char: Character = _get_first_alive_leader()
	if leader_char == null:
		_flee_is_fallback = true
		return Vector2i(-1, -1)
	var leader_pos: Vector2i = leader_char.grid_pos
	var leader_floor: int    = leader_char.current_floor
	var current_area: String = _map_data.get_area(leader_pos)
	if current_area.is_empty():
		_flee_is_fallback = true
		return Vector2i(-1, -1)

	var exit_tiles: Array[Vector2i] = _map_data.get_exit_tiles_from(current_area)
	if exit_tiles.is_empty():
		_flee_is_fallback = true
		return Vector2i(-1, -1)

	# A* 呼び出し用にリーダーの UnitAI インスタンスを取得（walker コンテキスト）
	var leader_ai: UnitAI = _unit_ais.get(leader_char.name) as UnitAI
	if leader_ai == null:
		_flee_is_fallback = true
		return Vector2i(-1, -1)
	var threat_fn: Callable = Callable(leader_ai, "_calc_threat_cost")

	var refuge_area_ids: Array[String] = _map_data.get_refuge_area_ids(leader_floor)
	if refuge_area_ids.is_empty():
		# 避難先エリアが存在しない（通常はフロア仕様のバグ想定）→ 脅威コスト最小の出口にフォールバック
		_flee_is_fallback = true

	var best_exit: Vector2i = Vector2i(-1, -1)
	var best_cost: float = INF
	var best_refuge_area: String = ""
	var best_refuge_dist: int = -1
	for exit_tile: Vector2i in exit_tiles:
		var path: Array[Vector2i] = leader_ai._astar_with_cost(
				leader_pos, exit_tile, threat_fn, current_area)
		if path.is_empty() and exit_tile != leader_pos:
			continue
		var reach_cost: float = leader_ai._path_cost(path, threat_fn)
		var refuge_cost: float = 0.0
		var exit_refuge_area: String = ""
		var exit_refuge_dist: int = -1
		if not refuge_area_ids.is_empty():
			var min_refuge_dist: int = 999999
			var adj_areas: Array[String] = _map_data.get_adjacent_area_ids_of_exit(exit_tile)
			for adj_area: String in adj_areas:
				for refuge_area: String in refuge_area_ids:
					var d: int = _map_data.get_area_distance(adj_area, refuge_area)
					if d >= 0 and d < min_refuge_dist:
						min_refuge_dist = d
						exit_refuge_area = refuge_area
						exit_refuge_dist = d
			if min_refuge_dist == 999999:
				# この出口からは避難先に到達不能 → 大ペナルティ（フォールバック候補として残す）
				refuge_cost = 9999.0
			else:
				refuge_cost = float(min_refuge_dist) * GlobalConstants.FLEE_AREA_DISTANCE_WEIGHT
		var total: float = reach_cost + refuge_cost
		if total < best_cost:
			best_cost = total
			best_exit = exit_tile
			best_refuge_area = exit_refuge_area
			best_refuge_dist = exit_refuge_dist

	if best_exit == Vector2i(-1, -1):
		# 全出口が到達不能 → フォールバック状態として返す
		_flee_is_fallback = true
		return Vector2i(-1, -1)

	# 選ばれた出口に避難先情報があれば記録・なければフォールバック扱い（到達不能な出口を採用した場合）
	if best_refuge_area.is_empty():
		_flee_is_fallback = true
	else:
		_flee_refuge_area_id  = best_refuge_area
		_flee_refuge_distance = best_refuge_dist
	return best_exit


## 選ばれた避難先エリア ID を返す（PartyStatusWindow 表示用）
## 空文字 = 未決定 / フォールバック
func get_flee_refuge_area_id() -> String:
	return _flee_refuge_area_id


## 出口から選ばれた避難先エリアまでの BFS ホップ数（-1 = 未決定）
func get_flee_refuge_distance() -> int:
	return _flee_refuge_distance


## FLEE がフォールバック経路（避難先エリア不明・到達不能で脅威コスト最小の出口採用）か
func is_flee_fallback() -> bool:
	return _flee_is_fallback


## 先頭の生存メンバー（リーダー優先）を返す
func _get_first_alive_leader() -> Character:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0 and m.is_leader:
			return m
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			return m
	return null


## メンバーがエリアをまたいだときに UnitAI から呼ばれる通知
## パーティー FLEE 中なら推奨出口を即時再計算・再配布する
## FLEE_REEVAL_MIN_INTERVAL で最小インターバルを強制（過剰再計算防止）
func on_member_area_changed(_member: Character, _new_area_id: String) -> void:
	if not _is_party_fleeing():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _flee_last_reeval_time < GlobalConstants.FLEE_REEVAL_MIN_INTERVAL:
		return
	_flee_last_reeval_time = now
	_assign_orders()  # 内部で _update_flee_recommended_goal を呼ぶ


## 戦闘方針プリセットをパーティーメンバー全員に適用する（2026-04-21 追加・ステップ 2）
## policy: "attack" / "defense" / "retreat" のいずれか
##
## 役割：`_global_orders.battle_policy` の変更を各メンバーの `current_order`（個別指示）に流し込む。
## プレイヤーは OrderWindow.`_apply_battle_policy_preset` が同じロジックで動作するが、NPC 側は
## OrderWindow を経由しないため PartyLeader 基底に同等機構を持つ。
##
## プリセット定義は `OrderWindow.BATTLE_POLICY_PRESET`（クラス別 × 方針別 → {combat, battle_formation}）
## を再利用する。ヒーラーは専用プリセット（rear / 方針対応 combat / heal=lowest_hp_first）。
##
## NpcLeaderAI が CRITICAL 時に `_global_orders["battle_policy"] = "retreat"` と書き換えた後、
## このメソッドを呼んで全メンバーの個別指示を更新する。
func apply_battle_policy_preset(policy: String) -> void:
	for mv: Variant in _party_members:
		var ch := mv as Character
		if not is_instance_valid(ch) or ch.character_data == null:
			continue
		if ch.character_data.class_id == "healer":
			# ヒーラー専用プリセット：隊形=rear、戦闘=方針に対応、回復=lowest_hp_first
			var healer_combat: String = {"attack": "attack", "defense": "defense", "retreat": "flee"}.get(policy, "attack") as String
			ch.current_order["battle_formation"] = "rear"
			ch.current_order["combat"]           = healer_combat
			ch.current_order["heal"]             = "lowest_hp_first"
		else:
			var cid: String = ch.character_data.class_id
			var class_presets: Dictionary = OrderWindow.BATTLE_POLICY_PRESET.get(cid, {}) as Dictionary
			if class_presets.is_empty():
				continue
			var preset: Dictionary = class_presets.get(policy, {}) as Dictionary
			for pkey: String in preset:
				ch.current_order[pkey] = preset.get(pkey, "") as String


## デバッグ情報を収集して返す
func get_debug_info() -> Array:
	var result: Array = []
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai != null:
			result.append(unit_ai.get_debug_info())
	return result


# --------------------------------------------------------------------------
# ログ
# --------------------------------------------------------------------------

func _has_player_controlled_member() -> bool:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_player_controlled:
			return true
	return false


func _log_strategy_change(old_strategy: Strategy) -> void:
	if MessageLog == null:
		return
	var leader_name := _get_leader_name()
	var old_name := _strategy_to_preset_name(old_strategy)
	var new_name := _strategy_to_preset_name(_party_strategy)
	var reason := _get_strategy_change_reason()
	var text := "[AI] %s: %s→%s（%s）" % [leader_name, old_name, new_name, reason]
	var leader_pos := Vector2i(-1, -1)
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_leader:
			leader_pos = m.grid_pos
			break
	MessageLog.add_ai(text, leader_pos)


func _get_leader_name() -> String:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_leader:
			var cname: String = m.character_data.character_name if m.character_data != null else ""
			if not cname.is_empty():
				return cname
			return m.character_data.character_id if m.character_data != null else m.name
	for m: Character in _party_members:
		if is_instance_valid(m):
			var cname: String = m.character_data.character_name if m.character_data != null else ""
			if not cname.is_empty():
				return cname
			return m.character_data.character_id if m.character_data != null else m.name
	return "不明"


func _strategy_to_preset_name(strat: Strategy) -> String:
	match strat:
		Strategy.ATTACK:     return "攻撃"
		Strategy.FLEE:       return "撤退"
		Strategy.WAIT:       return "待機"
		Strategy.DEFEND:     return "防衛"
		Strategy.EXPLORE:    return "探索"
		Strategy.GUARD_ROOM: return "帰還"
	return "不明"


func get_current_strategy_name() -> String:
	return _strategy_to_preset_name(_party_strategy)


## 表示用の全体指示ヒントを返す（PartyStatusWindow のヘッダー行用）
## 味方パーティー（Player / 合流済み NPC）：`_global_orders` の実値を返す
## 敵パーティー：`_global_orders` は空のままなので、呼出側（party_status_window.gd の
## 敵分岐）は move/battle_policy/target/on_low_hp/item_pickup キーを参照せず、
## 代わりに `_party_strategy` を直接表示する（docs/investigation_enemy_order_effective.md 参照）
## どちらのケースでも `combat_situation` / `power_balance` / `hp_status` / 戦力内訳キーは必ず付与する
##
## 2026-04-21 改訂：旧実装は空の `_global_orders` に対して `_party_strategy` から仮想ラベル
## （`{"move": "cluster", "battle_policy": "attack", ...}`）を合成していたが、UnitAI 実動と
## 連動しない誤解を招く表示だったため廃止（詳細は docs/history.md の同日エントリ参照）
##
## 2026-04-23 改訂：サブクラス（NpcLeaderAI）での override を廃止し、テンプレートメソッドパターンに統一。
## 指示部分の差分は `_build_orders_part()` で override し、戦況付与部分は本関数内で共通処理する。
## これにより PartyStatusWindow で使うキー（hp_real / combat_ratio 等）の追加漏れが起きない
func get_global_orders_hint() -> Dictionary:
	var hint: Dictionary = _build_orders_part()
	# 戦況判断を流し込む（全パーティー共通）
	var sit: int = _combat_situation.get("situation", int(GlobalConstants.CombatSituation.SAFE)) as int
	hint["combat_situation"] = sit
	hint["power_balance"] = _combat_situation.get("power_balance", 0)
	hint["hp_status"]     = _combat_situation.get("hp_status", 0)
	# HP 内訳（デバッグ表示用・「満」の内部計算を可視化）
	hint["hp_real"]       = _combat_situation.get("hp_real", 0)
	hint["hp_potion"]     = _combat_situation.get("hp_potion", 0)
	hint["hp_max"]        = _combat_situation.get("hp_max", 0)
	# 戦況比の内訳（デバッグ表示用・my_strength / enemy_strength）
	hint["my_combat_strength"] = _combat_situation.get("my_combat_strength", 0.0)
	hint["combat_ratio"]       = _combat_situation.get("combat_ratio", -1.0)
	# full_party / nearby_allied / nearby_enemy の 3 系統（PartyStatusWindow 表示用）
	hint["full_party_strength"]    = _combat_situation.get("full_party_strength", 0.0)
	hint["full_party_rank_sum"]    = _combat_situation.get("full_party_rank_sum", 0)
	hint["full_party_tier_sum"]    = _combat_situation.get("full_party_tier_sum", 0.0)
	hint["full_party_hp_ratio"]    = _combat_situation.get("full_party_hp_ratio", 0.0)
	hint["nearby_allied_strength"] = _combat_situation.get("nearby_allied_strength", 0.0)
	hint["nearby_allied_rank_sum"] = _combat_situation.get("nearby_allied_rank_sum", 0)
	hint["nearby_allied_tier_sum"] = _combat_situation.get("nearby_allied_tier_sum", 0.0)
	hint["nearby_allied_hp_ratio"] = _combat_situation.get("nearby_allied_hp_ratio", 0.0)
	hint["nearby_enemy_strength"]  = _combat_situation.get("nearby_enemy_strength", 0.0)
	hint["nearby_enemy_rank_sum"]  = _combat_situation.get("nearby_enemy_rank_sum", 0)
	hint["nearby_enemy_tier_sum"]  = _combat_situation.get("nearby_enemy_tier_sum", 0.0)
	return hint


## 指示部分のヒントを返す（サブクラスで override 可能）
## 基底：`_global_orders` の実値を返す（空なら空辞書）
## NpcLeaderAI：未設定時は NPC デフォルト値 + 探索モード判定を上書き
##
## 2026-04-23 改訂：サブクラスはこの関数だけ override すればよく、戦況キー追加漏れは起きない
func _build_orders_part() -> Dictionary:
	if not _global_orders.is_empty():
		return _global_orders.duplicate()
	return {}


func _get_strategy_change_reason() -> String:
	match _party_strategy:
		Strategy.ATTACK:     return "敵発見"
		Strategy.FLEE:       return "撤退判断"
		Strategy.WAIT:       return "待機"
		Strategy.DEFEND:     return "防衛"
		Strategy.EXPLORE:    return "探索開始"
		Strategy.GUARD_ROOM: return "縄張り外・帰還"
	return ""


# --------------------------------------------------------------------------
# 縄張り・追跡範囲チェック（敵パーティー専用）
# --------------------------------------------------------------------------

func _apply_range_check(base_strat: Strategy) -> Strategy:
	var first_member: Character = null
	for m: Character in _party_members:
		if is_instance_valid(m):
			first_member = m
			break
	if first_member == null or first_member.is_friendly:
		return base_strat
	if _party_strategy == Strategy.GUARD_ROOM:
		if base_strat == Strategy.FLEE:
			return Strategy.FLEE
		if _any_member_can_engage():
			return Strategy.ATTACK
		if _all_members_at_home():
			return Strategy.WAIT
		return Strategy.GUARD_ROOM
	if _party_strategy == Strategy.ATTACK and base_strat == Strategy.ATTACK:
		if _all_members_out_of_range():
			return Strategy.GUARD_ROOM
	return base_strat


func _all_members_out_of_range() -> bool:
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var cd := member.character_data
		if cd == null:
			continue
		var home := unit_ai.get_home_position()
		var dist_home := (member.grid_pos - home).length()
		if dist_home <= float(cd.territory_range):
			return false
		var target := _find_nearest_friendly(member)
		if target != null and is_instance_valid(target):
			var dist_target := (member.grid_pos - target.grid_pos).length()
			if dist_target <= float(cd.chase_range):
				return false
	return true


func _any_member_can_engage() -> bool:
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var cd := member.character_data
		if cd == null:
			continue
		var home := unit_ai.get_home_position()
		var dist_home := (member.grid_pos - home).length()
		if dist_home > float(cd.territory_range):
			continue
		var target := _find_nearest_friendly(member)
		if target != null and is_instance_valid(target):
			var dist_target := (member.grid_pos - target.grid_pos).length()
			if dist_target <= float(cd.chase_range):
				return true
	return false


func _all_members_at_home() -> bool:
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var home := unit_ai.get_home_position()
		var dx: int = abs(member.grid_pos.x - home.x)
		var dy: int = abs(member.grid_pos.y - home.y)
		if dx + dy > 2:
			return false
	return true


# --------------------------------------------------------------------------
# ヘルパー（サブクラスから使用）
# --------------------------------------------------------------------------

## 生存している友好キャラが1体以上いるか判定する
func _has_alive_friendly() -> bool:
	for f: Character in _friendly_list:
		if is_instance_valid(f) and f.hp > 0:
			return true
	return _player != null and is_instance_valid(_player) and _player.hp > 0


## 指定メンバーから最も近い生存友好キャラを返す（_player フォールバック付き）
func _find_nearest_friendly(member: Character) -> Character:
	var closest: Character = null
	var min_dist := INF
	for f: Character in _friendly_list:
		if not is_instance_valid(f) or f.hp <= 0:
			continue
		if f.current_floor != member.current_floor:
			continue
		var dist := float((f.grid_pos - member.grid_pos).length())
		if dist < min_dist:
			min_dist = dist
			closest = f
	if closest == null and is_instance_valid(_player) and _player.hp > 0 \
			and _player.current_floor == member.current_floor:
		return _player
	return closest


## 援護優先ターゲット選択
func _select_support_target(member: Character) -> Character:
	var weakest_ally: Character = null
	var min_ratio := 2.0
	for ally: Character in _party_members:
		if not is_instance_valid(ally) or ally.hp <= 0:
			continue
		if ally == member:
			continue
		var ratio := float(ally.hp) / float(maxi(ally.max_hp, 1))
		if ratio < min_ratio:
			min_ratio = ratio
			weakest_ally = ally
	if weakest_ally != null:
		return _select_target_for(weakest_ally)
	return _select_target_for(member)


# --------------------------------------------------------------------------
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

## メンバーに対応する UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return UnitAI.new()


## 探索時の移動方針を返す（NpcLeaderAI でオーバーライド）
func _get_explore_move_policy() -> String:
	return "explore"


## 現在の探索移動方針を外部に公開する
func get_explore_move_policy() -> String:
	return _get_explore_move_policy()


## パーティー全体の戦略を評価する（敵系サブクラスのみオーバーライド）
## 2026-04-21 改訂：味方（PartyLeaderPlayer / NpcLeaderAI）は override しない。
## _assign_orders() 側で `_is_enemy_party()` ガードにより味方では呼ばれない。
## 敵系サブクラス（EnemyLeaderAI / Goblin・Wolf）は従来どおり override する。
func _evaluate_party_strategy() -> Strategy:
	return Strategy.WAIT


## 探索モードか判定する（EXPLORE 相当・leader/follower で移動方針を分岐）
## 敵：`_party_strategy == EXPLORE` で判定（基底実装）
## NPC：敵検知フラグで override（NpcLeaderAI）
func _is_in_explore_mode() -> bool:
	return _party_strategy == Strategy.EXPLORE


## 縄張り帰還モードか判定する（GUARD_ROOM 相当・敵専用）
## 味方では常に false（味方は縄張り概念を持たない）
func _is_in_guard_room_mode() -> bool:
	return _party_strategy == Strategy.GUARD_ROOM


## このパーティーが敵パーティーかを判定する（先頭生存メンバーの is_friendly で判別）
## メンバー全員死亡時は false（戦略評価対象外）
func _is_enemy_party() -> bool:
	for m: Character in _party_members:
		if is_instance_valid(m):
			return not m.is_friendly
	return false


## 指定メンバーの攻撃ターゲットを選択する（サブクラスがオーバーライド）
func _select_target_for(_member: Character) -> Character:
	return _player


## 最もHPが少ない攻撃ターゲットを選択する
func _select_weakest_target(member: Character) -> Character:
	return _select_target_for(member)


## キャラクターの装備中 tier の平均を返す（装備なしなら 0.0）
## 対象: equipped_weapon / equipped_armor / equipped_shield のうち実装備のみ
## 各アイテムに tier フィールドがない場合は 0 扱い（セーブデータ互換・敵は装備を持たない）
func _character_tier_avg(m: Character) -> float:
	if m.character_data == null:
		return 0.0
	var total_tier := 0
	var equipped_count := 0
	var slots := [
		m.character_data.equipped_weapon,
		m.character_data.equipped_armor,
		m.character_data.equipped_shield,
	]
	for it_v: Variant in slots:
		var it := it_v as Dictionary
		if it.is_empty():
			continue
		total_tier += int(it.get("tier", 0))
		equipped_count += 1
	if equipped_count <= 0:
		return 0.0
	return float(total_tier) / float(equipped_count)


## 状態ラベルからHP割合を推定する（敵の戦力を過大評価する安全側に倒す）
## 各ラベルの閾値範囲の最大値（その状態に「なる直前」のHP率）を返す
func _estimate_hp_ratio_from_condition(condition: String) -> float:
	match condition:
		"healthy":  return 1.0
		"wounded":  return GlobalConstants.CONDITION_WOUNDED_THRESHOLD
		"injured":  return GlobalConstants.CONDITION_INJURED_THRESHOLD
		"critical": return GlobalConstants.CONDITION_CRITICAL_THRESHOLD
		_:          return 1.0  # 不明な値 → 安全側（敵を強く見積もる）


## メンバーが所持しているヒールポーションの合計回復量を返す
func _calc_total_potion_hp(member: Character) -> int:
	if member.character_data == null:
		return 0
	var total := 0
	for item: Variant in member.character_data.inventory:
		var it := item as Dictionary
		if it == null:
			continue
		var eff := it.get("effect", {}) as Dictionary
		total += eff.get("restore_hp", 0) as int
	return total


## メンバーリストの統計（rank_sum / tier_sum / hp_ratio / strength）を返す
## use_estimated_hp = false: 実 HP + ポーション回復量
## use_estimated_hp = true:  状態ラベル（condition）からHP%を推定（敵ステータス直接参照禁止ルール）
## 戻り値: { "rank_sum": int, "tier_sum": float, "hp_ratio": float, "strength": float, "alive_count": int }
##   strength = (rank_sum + tier_sum × ITEM_TIER_STRENGTH_WEIGHT) × avg_hp_ratio
func _calc_stats(members: Array, use_estimated_hp: bool) -> Dictionary:
	var rank_sum := 0
	var tier_sum := 0.0
	var hp_ratio_sum := 0.0
	var alive_count := 0
	for mv: Variant in members:
		# freed オブジェクトへの as キャストはクラッシュするため、キャスト前に is_instance_valid を確認する
		if not is_instance_valid(mv):
			continue
		var m := mv as Character
		if m == null or m.hp <= 0:
			continue
		if m.character_data != null:
			rank_sum += RANK_VALUES.get(m.character_data.rank, 3) as int
			tier_sum += _character_tier_avg(m)
		alive_count += 1
		if use_estimated_hp:
			hp_ratio_sum += _estimate_hp_ratio_from_condition(m.get_condition())
		else:
			var total_max := m.max_hp
			if total_max <= 0:
				continue
			var cur := m.hp + _calc_total_potion_hp(m)
			hp_ratio_sum += clampf(float(cur) / float(total_max), 0.0, 1.0)
	if alive_count <= 0:
		return {"rank_sum": 0, "tier_sum": 0.0, "hp_ratio": 0.0, "strength": 0.0, "alive_count": 0}
	var avg_hp_ratio := hp_ratio_sum / float(alive_count)
	var base := float(rank_sum) + tier_sum * GlobalConstants.ITEM_TIER_STRENGTH_WEIGHT
	return {
		"rank_sum":    rank_sum,
		"tier_sum":    tier_sum,
		"hp_ratio":    avg_hp_ratio,
		"strength":    base * avg_hp_ratio,
		"alive_count": alive_count,
	}


## 自パ（実 HP）と同陣営他パ（推定 HP）を混ぜた統計を返す
## 自パ部分は apply_initial_items で自分の inventory・max_hp を把握できるためポーション込み実 HP を使用
## 他パ部分はポーション所持を把握できないので condition ラベルからの推定 HP を使用
func _calc_stats_mixed(self_members: Array, other_members: Array) -> Dictionary:
	var self_stats := _calc_stats(self_members, false)
	var other_stats := _calc_stats(other_members, true)
	var rank_sum: int = int(self_stats.rank_sum) + int(other_stats.rank_sum)
	var tier_sum: float = float(self_stats.tier_sum) + float(other_stats.tier_sum)
	var alive: int = int(self_stats.alive_count) + int(other_stats.alive_count)
	var avg_hp_ratio: float = 0.0
	if alive > 0:
		# HP 率は生存メンバー加重平均（rank_sum 側を重みにしない）
		avg_hp_ratio = (float(self_stats.hp_ratio) * float(self_stats.alive_count)
				+ float(other_stats.hp_ratio) * float(other_stats.alive_count)) / float(alive)
	var base := float(rank_sum) + tier_sum * GlobalConstants.ITEM_TIER_STRENGTH_WEIGHT
	return {
		"rank_sum":    rank_sum,
		"tier_sum":    tier_sum,
		"hp_ratio":    avg_hp_ratio,
		"strength":    base * avg_hp_ratio,
		"alive_count": alive,
	}


## 距離フィルタ（マンハッタン距離・同フロアのみ）
## center_pos / my_floor: 自パリーダーの位置情報
## radius: GlobalConstants.COALITION_RADIUS_TILES
func _within_coalition_radius(c: Character, center_pos: Vector2i, my_floor: int, radius: int) -> bool:
	if my_floor >= 0 and c.current_floor != my_floor:
		return false
	var d := absi(c.grid_pos.x - center_pos.x) + absi(c.grid_pos.y - center_pos.y)
	return d <= radius


## 統合戦略ステータス評価（戦力計算 + 戦況判断）
## 3 種類のメンバー集合で統計を算出する（エリアベース target_areas 判定は廃止）:
##   - full_party:     自パ全員（下層判定用・絶対戦力）
##   - nearby_allied:  自パ近接 + 同陣営他パ近接（戦況判断用・味方連合）
##   - nearby_enemy:   近接敵（戦況判断用）
## 距離基準: 自パリーダーのグリッド座標から COALITION_RADIUS_TILES マス以内（マンハッタン）
## 敵の非対称設計: enemy パーティーの自軍戦力は full_party のみ（協力しない世界観）
##                味方（player/npc）の自軍戦力は nearby_allied（連合）
## 結果は _assign_orders() → receive_order() の combat_situation フィールドに含めてメンバーに伝達する
func _evaluate_strategic_status() -> Dictionary:
	var radius: int = GlobalConstants.COALITION_RADIUS_TILES

	# 自パリーダー基準点（先頭の生存者）
	var leader_pos := Vector2i.ZERO
	var my_floor := -1
	var is_enemy_party := false
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			leader_pos = m.grid_pos
			my_floor = m.current_floor
			is_enemy_party = not m.is_friendly
			break

	# ==================== full_party（自パ全員） ====================
	var full_party: Array[Character] = []
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			full_party.append(m)

	# ==================== nearby_allied（自パ近接 + 同陣営他パ近接） ====================
	# 自パ側: _get_my_combat_members() を使う（プレイヤーは合流済み NPC を含む）
	var my_members := _get_my_combat_members()
	var nearby_allied_self: Array[Character] = []
	for m: Character in my_members:
		if not is_instance_valid(m) or m.hp <= 0:
			continue
		if _within_coalition_radius(m, leader_pos, my_floor, radius):
			nearby_allied_self.append(m)

	# 同陣営他パ: _all_members から my_members を除いた同陣営キャラを半径内で収集
	# 陣営判定は先に算出した is_enemy_party を使う（is_friendly = not is_enemy_party）
	# 直前ループで is_instance_valid 済みの生存者から導出しているため freed アクセスの心配なし
	var my_faction: bool = not is_enemy_party
	var nearby_allied_others: Array[Character] = []
	for c: Character in _all_members:
		if not is_instance_valid(c) or c.hp <= 0:
			continue
		if c.is_friendly != my_faction:
			continue
		if my_members.has(c):
			continue  # 既に nearby_allied_self でカウント候補
		if _within_coalition_radius(c, leader_pos, my_floor, radius):
			nearby_allied_others.append(c)

	# ==================== nearby_enemy（近接敵） ====================
	var nearby_enemy: Array[Character] = []
	for opp: Character in _get_opposing_characters():
		if not is_instance_valid(opp) or opp.hp <= 0:
			continue
		if _within_coalition_radius(opp, leader_pos, my_floor, radius):
			nearby_enemy.append(opp)

	# ==================== 統計計算（各集合で 1 回ずつ） ====================
	var full_stats := _calc_stats(full_party, false)
	var nearby_allied_stats := _calc_stats_mixed(nearby_allied_self, nearby_allied_others)
	var nearby_enemy_stats := _calc_stats(nearby_enemy, true)

	# ==================== 敵の非対称設計 ====================
	# 敵パーティー: 自軍戦力 = full_party（協力しない）
	# 味方（player/npc）: 自軍戦力 = nearby_allied（連合）
	var my_combat_strength: float
	var my_combat_rank_sum: int
	if is_enemy_party:
		my_combat_strength = float(full_stats.strength)
		my_combat_rank_sum = int(full_stats.rank_sum)
	else:
		my_combat_strength = float(nearby_allied_stats.strength)
		my_combat_rank_sum = int(nearby_allied_stats.rank_sum)

	# ==================== 戦況判断 ====================
	# HP 充足率は自パーティーのみで算出（他パーティーのポーション所持は把握不可）
	var hp_breakdown := _calc_hp_breakdown_for(_party_members)
	var hp_status: int = hp_breakdown.get("status", int(GlobalConstants.HpStatus.CRITICAL)) as int

	var situation: int
	var power_balance: int
	var combat_ratio: float = -1.0  # デバッグ表示用（敵なし or enemy_s=0 のとき -1）
	if nearby_enemy.is_empty():
		situation = int(GlobalConstants.CombatSituation.SAFE)
		power_balance = int(GlobalConstants.PowerBalance.OVERWHELMING)
	else:
		# 戦力比（strength 比）で situation を分類
		var enemy_s: float = float(nearby_enemy_stats.strength)
		if enemy_s <= 0.0:
			situation = int(GlobalConstants.CombatSituation.SAFE)
		else:
			var ratio := my_combat_strength / enemy_s
			combat_ratio = ratio
			if ratio >= GlobalConstants.COMBAT_RATIO_OVERWHELMING:
				situation = int(GlobalConstants.CombatSituation.OVERWHELMING)
			elif ratio >= GlobalConstants.COMBAT_RATIO_ADVANTAGE:
				situation = int(GlobalConstants.CombatSituation.ADVANTAGE)
			elif ratio >= GlobalConstants.COMBAT_RATIO_EVEN:
				situation = int(GlobalConstants.CombatSituation.EVEN)
			elif ratio >= GlobalConstants.COMBAT_RATIO_DISADVANTAGE:
				situation = int(GlobalConstants.CombatSituation.DISADVANTAGE)
			else:
				situation = int(GlobalConstants.CombatSituation.CRITICAL)
		# 戦力比（ランク和のみ）で power_balance を分類
		var enemy_rank: int = int(nearby_enemy_stats.rank_sum)
		if enemy_rank <= 0:
			power_balance = int(GlobalConstants.PowerBalance.OVERWHELMING)
		else:
			var rank_ratio := float(my_combat_rank_sum) / float(enemy_rank)
			if rank_ratio >= GlobalConstants.POWER_BALANCE_OVERWHELMING:
				power_balance = int(GlobalConstants.PowerBalance.OVERWHELMING)
			elif rank_ratio >= GlobalConstants.POWER_BALANCE_SUPERIOR:
				power_balance = int(GlobalConstants.PowerBalance.SUPERIOR)
			elif rank_ratio >= GlobalConstants.POWER_BALANCE_EVEN:
				power_balance = int(GlobalConstants.PowerBalance.EVEN)
			elif rank_ratio >= GlobalConstants.POWER_BALANCE_INFERIOR:
				power_balance = int(GlobalConstants.PowerBalance.INFERIOR)
			else:
				power_balance = int(GlobalConstants.PowerBalance.DESPERATE)

	return {
		# 戦況判断結果
		"situation":      situation,
		"power_balance":  power_balance,
		"hp_status":      hp_status,

		# HP 充足率の内訳（デバッグ表示用・ポーション込みで「満」表示になる理由を可視化）
		"hp_real":        int(hp_breakdown.get("hp", 0)),
		"hp_potion":      int(hp_breakdown.get("potion", 0)),
		"hp_max":         int(hp_breakdown.get("max", 0)),

		# 戦況判定に使った戦力比の内訳（デバッグ表示用・my_strength / enemy_strength）
		"my_combat_strength": my_combat_strength,
		"combat_ratio":       combat_ratio,

		# full_party（自パ全員・下層判定用・絶対戦力）
		"full_party_strength":  float(full_stats.strength),
		"full_party_rank_sum":  int(full_stats.rank_sum),
		"full_party_tier_sum":  float(full_stats.tier_sum),
		"full_party_hp_ratio":  float(full_stats.hp_ratio),

		# nearby_allied（自パ近接 + 同陣営他パ近接・連合戦力）
		"nearby_allied_strength": float(nearby_allied_stats.strength),
		"nearby_allied_rank_sum": int(nearby_allied_stats.rank_sum),
		"nearby_allied_tier_sum": float(nearby_allied_stats.tier_sum),
		"nearby_allied_hp_ratio": float(nearby_allied_stats.hp_ratio),

		# nearby_enemy（近接敵）
		"nearby_enemy_strength": float(nearby_enemy_stats.strength),
		"nearby_enemy_rank_sum": int(nearby_enemy_stats.rank_sum),
		"nearby_enemy_tier_sum": float(nearby_enemy_stats.tier_sum),
	}


## 自軍として扱うメンバー一覧を返す（戦況判断用）
## _party_ref が設定されている場合（プレイヤー・合流済みNPCパーティー）は Party.sorted_members() を使う
## 未設定の場合（敵・未合流NPC）は _party_members のみ
func _get_my_combat_members() -> Array[Character]:
	if _party_ref == null:
		return _party_members
	var result: Array[Character] = []
	for mv: Variant in _party_ref.sorted_members():
		# freed オブジェクトへの as キャストはクラッシュするため、キャスト前に is_instance_valid を確認する
		if not is_instance_valid(mv):
			continue
		var m := mv as Character
		if m != null:
			result.append(m)
	return result




## 自軍パーティーの HP 充足率の段階を返す
func _calc_hp_status() -> int:
	return _calc_hp_status_for(_party_members)


## 指定メンバーリストの HP 充足率の段階を返す
func _calc_hp_status_for(members: Array) -> int:
	return _calc_hp_breakdown_for(members).get("status", int(GlobalConstants.HpStatus.CRITICAL)) as int


## 指定メンバーリストの HP 充足率の内訳を返す（デバッグ表示用）
## 戻り値: { "hp": int, "potion": int, "max": int, "status": int }
## status は HP_STATUS_FULL/STABLE/LOW/CRITICAL のいずれか
func _calc_hp_breakdown_for(members: Array) -> Dictionary:
	var total_hp := 0
	var total_max := 0
	var total_potion := 0
	for mv: Variant in members:
		# freed オブジェクトへの as キャストはクラッシュするため、キャスト前に is_instance_valid を確認する
		if not is_instance_valid(mv):
			continue
		var m := mv as Character
		if m == null or m.hp <= 0:
			continue
		total_hp += m.hp
		total_max += m.max_hp
		total_potion += _calc_total_potion_hp(m)
	var status: int
	if total_max <= 0:
		status = int(GlobalConstants.HpStatus.CRITICAL)
	else:
		var ratio := clampf(float(total_hp + total_potion) / float(total_max), 0.0, 1.0)
		if ratio >= GlobalConstants.HP_STATUS_FULL:
			status = int(GlobalConstants.HpStatus.FULL)
		elif ratio >= GlobalConstants.HP_STATUS_STABLE:
			status = int(GlobalConstants.HpStatus.STABLE)
		elif ratio >= GlobalConstants.HP_STATUS_LOW:
			status = int(GlobalConstants.HpStatus.LOW)
		else:
			status = int(GlobalConstants.HpStatus.CRITICAL)
	return {"hp": total_hp, "potion": total_potion, "max": total_max, "status": status}


## 対立するキャラクターのリストを返す（サブクラスでオーバーライド）
## 敵 AI: _friendly_list（プレイヤー・NPC）
## 味方 AI: _enemy_list（敵キャラ）
func _get_opposing_characters() -> Array[Character]:
	return _friendly_list
