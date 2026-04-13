class_name UnitAI
extends Node

## 個体AI基底クラス（2層AIアーキテクチャの個体レイヤー）
## PartyLeaderAI からオーダーを受け取り、担当キャラクター1体の行動を実行する
## ステートマシン・A*経路探索・アクションキュー管理を担う
## サブクラスは _should_ignore_flee() / _should_self_flee() / _can_attack() をオーバーライドして種族固有行動を実装する

enum PathMethod { DIRECT, ASTAR, ASTAR_FLANK }
## 後方互換用（PartyLeader.Strategy と int 値一致。_assign_orders 側で参照する値）
enum Strategy   { ATTACK, FLEE, WAIT }

const MOVE_INTERVAL  := 0.40  ## タイル移動の間隔・基準値（秒）。game_speed=1.0 時の標準速度
const WAIT_DURATION  := 3.0  ## wait アクションの待機時間・基準値（秒）
const QUEUE_MIN_LEN  := 3    ## キューがこれ以下になったら補充するしきい値

## 従順度（0.0=完全自律 / 1.0=完全にリーダー指示に従う）
## サブクラスで上書きする。ゴブリン=0.5（自己HP危機時のみリーダー指示を上書き）
var obedience: float = 1.0

enum _State { IDLE, MOVING, WAITING, ATTACKING_PRE, ATTACKING_POST }

## セットアップで渡されるもの
var _member:      Character                   ## 担当キャラクター
var _player:      Character                   ## プレイヤー（ターゲット・_is_passable 用）
var _map_data:    MapData
var _all_members:  Array[Character] = []       ## 全パーティー合算（占有チェック用）
var _party_peers:  Array[Character] = []       ## 同一パーティーメンバー（heal/buff ターゲット限定用）
var _floor_following: bool = false             ## フロア追従中：_is_passable で友好キャラを通過可能にする
var _follow_hero_floors: bool = false          ## true: hero が別フロアにいるとき階段を追う（合流済みメンバー専用）
var _vision_system: VisionSystem = null       ## 探索行動（explore）に使用
var _visited_areas: Dictionary = {}           ## 訪問済みエリアID集合（PartyLeaderAI が共有 dict を渡す）

## ステートマシン
var _state:         _State = _State.IDLE
var _goal:          Vector2i
var _timer:         float  = 0.0
var _attack_target: Character

## 現在のオーダー・キュー
var _order:          Dictionary = {}  ## PartyLeaderAI から受け取ったオーダー
var _queue:          Array      = []  ## アクションキュー
var _current_action: Dictionary = {}  ## 実行中アクション

## 行動決定用フィールド（receive_order で更新）
var _combat:           String    = "attack"   ## 戦闘方針 (attack / defense / flee / standby)
var _on_low_hp:        String    = "retreat"  ## 低HP時行動 (keep_fighting / retreat / flee)
var _party_fleeing:    bool      = false      ## パーティーレベルの撤退指示（全員逃走）
var _target:           Character
var _reeval_timer:     float     = 0.0  ## フォールバック再評価タイマー（オーダーなし時）
## 後方互換: _strategy は _generate_queue の内部判断結果を保存（デバッグ・キュー補充判定用）
var _strategy:         int       = 2  ## 0=ATTACK, 1=FLEE, 2=WAIT 相当

const _REEVAL_FALLBACK := 1.5  ## フォールバック再評価間隔（秒）

## 指示項目（receive_order で更新）
## move_policy:      explore / same_room / cluster / guard_room / standby / spread（敵デフォルト）/ follow（新）
## battle_formation: surround / rush / rear（旧: front / same_as_leader も後方互換で受け付ける）
var _move_policy:      String    = "same_room"
var _battle_formation: String    = "surround"
## グローバル方針（party_leader_ai から receive_order で受け取る）
var _hp_potion:        String    = "never"  ## "use" = 瀕死時に自動使用
var _sp_mp_potion:     String    = "never"  ## "use" = 特殊攻撃前に自動使用
var _item_pickup:      String    = "passive"  ## "aggressive" / "passive" / "avoid"
var _combat_situation:  Dictionary = {}       ## 戦況判断結果（PartyLeader から receive_order 経由で受信）
var _leader_ref:       Character = null  ## 隊形計算の基準となるリーダーキャラ
var _guard_room_area:  String    = ""    ## guard_room 時の記憶部屋ID（初回設定後不変）
var _home_position:    Vector2i  = Vector2i.ZERO  ## スポーン地点（帰還の基点。setup() で初期化）
var _dbg_stuck_count:  int       = 0              ## デバッグ: 連続停滞回数
var _all_floor_items:  Dictionary = {}  ## {floor_idx: {Vector2i: item}} 参照（game_map から設定）


func setup(member: Character, player: Character, map_data: MapData,
		all_members: Array[Character]) -> void:
	_member        = member
	_player        = player
	_map_data      = map_data
	_all_members   = all_members
	_goal          = member.grid_pos
	_home_position = member.grid_pos


func get_home_position() -> Vector2i:
	return _home_position


func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members
	# --- デバッグ: _all_members の構成をログ出力（初回のみ） ---
	if _member != null and is_instance_valid(_member) and _member.is_friendly:
		var my_name := _member.character_data.character_name if _member.character_data != null else String(_member.name)
		var friendly_count := 0
		var friendly_names: PackedStringArray = []
		for m: Character in _all_members:
			if is_instance_valid(m) and m.is_friendly:
				friendly_count += 1
				var n := m.character_data.character_name if m.character_data != null else String(m.name)
				friendly_names.append(n)
		MessageLog.add_ai("[DBG_AM] %s: _all_members=%d friendly=%d(%s)" % [
			my_name, _all_members.size(), friendly_count, ",".join(friendly_names)])


## heal/buff ターゲット検索に使う同一パーティーメンバーリストを設定する
## PartyLeaderAI.setup() から呼ばれ、自分の管理メンバーのみをセットする
func set_party_peers(peers: Array[Character]) -> void:
	_party_peers = peers


## hero が別フロアにいるときに階段追従するかを設定する
## 合流済みパーティーメンバーのみ true（未加入 NPC は false のまま）
func set_follow_hero_floors(value: bool) -> void:
	_follow_hero_floors = value


## MapData を更新する（フロア遷移時に game_map から呼ばれる）
func set_map_data(new_map_data: MapData) -> void:
	_map_data = new_map_data


## VisionSystem をセットする（explore 移動方針に必要）
func set_vision_system(vs: VisionSystem) -> void:
	_vision_system = vs


## 訪問済みエリア辞書をセットする（PartyLeaderAI が全 UnitAI に同一 dict を渡して共有）
func set_visited_areas(d: Dictionary) -> void:
	_visited_areas = d


## PartyLeaderAI からオーダーを受け取る
## order: { "target": Character, "combat": String, "on_low_hp": String,
##          "move": String, "battle_formation": String, "leader": Character,
##          "party_fleeing": bool, "combat_situation": Dictionary, ... }
func receive_order(order: Dictionary) -> void:
	_order = order
	var raw_target: Variant = order.get("target", null)
	var ordered_target: Character = null
	if raw_target != null and is_instance_valid(raw_target):
		ordered_target = raw_target as Character

	# 移動方針を更新（変化があったか記録してから更新）
	var new_move := order.get("move", "spread") as String
	var prev_move_policy := _move_policy
	# guard_room: 初回設定時に現在地の部屋を記憶する
	if new_move == "guard_room":
		if _guard_room_area.is_empty() and _map_data != null \
				and _member != null and is_instance_valid(_member):
			var area := _map_data.get_area(_member.grid_pos)
			if not area.is_empty():
				_guard_room_area = area
	else:
		_guard_room_area = ""
	_move_policy = new_move

	_battle_formation  = order.get("battle_formation", "surround") as String
	_hp_potion         = order.get("hp_potion",    "never") as String
	_sp_mp_potion      = order.get("sp_mp_potion", "never") as String
	_item_pickup       = order.get("item_pickup",  "passive") as String
	_combat_situation  = order.get("combat_situation", {}) as Dictionary
	_combat            = order.get("combat",       "attack") as String
	_on_low_hp         = order.get("on_low_hp",    "retreat") as String
	_party_fleeing     = order.get("party_fleeing", false) as bool

	var raw_leader: Variant = order.get("leader", null)
	if raw_leader != null and is_instance_valid(raw_leader):
		_leader_ref = raw_leader as Character
	else:
		_leader_ref = null

	_target = ordered_target

	# 現在の行動決定結果を算出（キュー補充判定用）
	var new_effective := _determine_effective_action()

	# 階段タイルに乗っているときはキューを強制再生成する（階段回避コードを確実に走らせる）
	var on_stair := _member != null and is_instance_valid(_member) \
			and _is_stair_tile(_member.grid_pos) \
			and _move_policy != "stairs_down" and _move_policy != "stairs_up"
	# 移動方針が変化した場合もキューを強制再生成する
	var policy_changed := prev_move_policy != _move_policy
	# 移動アニメーション中は戦略・方針が変わらない限りキューを再生成しない
	var is_mid_move := _state == _State.MOVING
	# アイテム取得優先チェック（早期リターン前）
	if _is_combat_safe() and not is_mid_move and _item_pickup != "avoid":
		var item_pos := _find_item_pickup_target()
		if item_pos != Vector2i(-1, -1) and item_pos != _member.grid_pos:
			_strategy = new_effective
			_queue    = [{"action": "move_to_explore", "goal": item_pos}]
			if _state != _State.ATTACKING_PRE and _state != _State.ATTACKING_POST:
				_current_action = {}
				_state = _State.IDLE
				if _member != null and is_instance_valid(_member):
					_member.is_attacking = false
			return
	if not on_stair and not policy_changed \
			and new_effective == _strategy and ordered_target == _target \
			and (_queue.size() >= QUEUE_MIN_LEN or is_mid_move):
		return

	_strategy = new_effective

	var new_queue := _generate_queue(new_effective, ordered_target)
	if new_queue.is_empty():
		return
	_queue = new_queue

	if _state != _State.ATTACKING_PRE and _state != _State.ATTACKING_POST:
		_current_action = {}
		_state = _State.IDLE
		if _member != null and is_instance_valid(_member):
			_member.is_attacking = false


## 状況変化通知（PartyLeaderAI から呼ばれる）
func notify_situation_changed() -> void:
	_reeval_timer = 0.0


## デバッグ情報を返す（RightPanel / PartyLeaderAI.get_debug_info() が収集）
func get_debug_info() -> Dictionary:
	return {
		"name":             _member.name if (_member != null and is_instance_valid(_member)) else "?",
		"strategy":         _strategy,
		"combat":           _combat,
		"target_name":      _target.name if (_target != null and is_instance_valid(_target)) else "-",
		"current_action":   _current_action.duplicate(),
		"queue":            _queue.duplicate(),
		"grid_pos":         _member.grid_pos if (_member != null and is_instance_valid(_member)) else Vector2i.ZERO,
	}


# --------------------------------------------------------------------------
# ステートマシン
# --------------------------------------------------------------------------

var _dbg_process_timer: float = 0.0  ## デバッグ: _process 動作確認用タイマー

func _process(delta: float) -> void:
	if _member == null or not is_instance_valid(_member):
		return
	# プレイヤーが直接操作中のキャラクターは AI 処理をスキップする
	if _member.is_player_controlled:
		return
	# 時間停止中（プレイヤーのターゲット選択中など）は AI 処理を停止する
	if not GlobalConstants.world_time_running:
		return

	# --- デバッグ: AI が動作しているか3秒ごとに確認 ---
	if _member.is_friendly:
		_dbg_process_timer += delta
		if _dbg_process_timer >= 3.0:
			_dbg_process_timer = 0.0
			var my_name := _member.character_data.character_name if _member.character_data != null else String(_member.name)
			MessageLog.add_ai("[DBG_AI] %s F%d@%s state=%d queue=%d combat=%s mv=%s _all=%d" % [
				my_name, _member.current_floor, _member.grid_pos,
				int(_state), _queue.size(), _combat, _move_policy, _all_members.size()])

	# スタン中は行動をスキップしてキューをクリア
	if _member.is_stunned:
		if _state != _State.IDLE:
			_state = _State.IDLE
			_member.is_attacking = false
		_queue.clear()
		return

	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = _REEVAL_FALLBACK
		if _order.is_empty():
			_fallback_evaluate_action()

	match _state:
		_State.IDLE:
			var action := _pop_action()
			if not action.is_empty():
				_start_action(action)
			elif _queue.is_empty():
				if not _order.is_empty():
					receive_order(_order)
				else:
					_fallback_evaluate_action()

		_State.MOVING:
			# 移動先が他キャラに取られた場合はアボートして再評価
			# ただし相手がすでにそのタイルを離れる途中（別の場所へ pending 移動中）なら無視する
			if _member.is_pending() and _is_dest_blocked_by_other(_member.get_pending_grid_pos()):
				_member.abort_move()
				_queue.clear()
				notify_situation_changed()
				_state = _State.IDLE
				return
			_timer -= delta
			if _timer <= 0.0:
				var still_moving := _step_toward_goal()
				if still_moving:
					_timer = _get_move_interval()
				else:
					_state = _State.IDLE
					_complete_action()

		_State.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				_state = _State.IDLE
				_complete_action()

		_State.ATTACKING_PRE:
			_timer -= delta
			if _timer <= 0.0:
				_execute_attack()
				_on_after_attack()
				_member.is_attacking = false
				_state = _State.ATTACKING_POST
				var post := _member.character_data.post_delay if _member.character_data else 0.5
				_timer = post

		_State.ATTACKING_POST:
			_timer -= delta
			if _timer <= 0.0:
				_state = _State.IDLE
				_complete_action()


func _start_action(action: Dictionary) -> void:
	match action.get("action", "") as String:
		"move_to_attack":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			var goal := _calc_attack_goal(_target, _get_path_method())
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = 0.0  ## 最初の1歩は即時開始

		"move_to_formation":
			var fgoal := _formation_move_goal()
			if fgoal == _member.grid_pos:
				_complete_action()
				return
			_goal  = fgoal
			_state = _State.MOVING
			_timer = 0.0  ## 最初の1歩は即時開始

		"move_to_explore":
			var goal_var: Variant = action.get("goal", null)
			if goal_var == null:
				_complete_action()
				return
			var goal := goal_var as Vector2i
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = 0.0  ## 最初の1歩は即時開始

		"flee":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			var goal := _find_flee_goal(_target)
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = 0.0  ## 最初の1歩は即時開始

		"move_to_home":
			if _home_position == _member.grid_pos:
				_complete_action()
				return
			_goal  = _home_position
			_state = _State.MOVING
			_timer = 0.0  ## 最初の1歩は即時開始

		"attack":
			if _target == null or not is_instance_valid(_target):
				_complete_action()
				return
			var atype := _get_attack_type()
			if not _can_attack_target(_target, atype):
				_complete_action()
				return
			_attack_target = _target
			_state = _State.ATTACKING_PRE
			_timer = _member.character_data.pre_delay if _member.character_data else 0.3
			_member.is_attacking = true

		"move_to_heal", "move_to_buff":
			var tgt_var: Variant = action.get("target", null)
			if tgt_var == null or not is_instance_valid(tgt_var):
				_complete_action()
				return
			var tgt := tgt_var as Character
			var range_val := _member.attack_range if _member.character_data else 1
			if _manhattan(_member.grid_pos, tgt.grid_pos) <= range_val:
				_complete_action()
				return
			var goal := _find_adjacent_goal(tgt)
			if goal == _member.grid_pos:
				_complete_action()
				return
			_goal  = goal
			_state = _State.MOVING
			_timer = 0.0  ## 最初の1歩は即時開始

		"heal":
			var tgt_var: Variant = action.get("target", null)
			if tgt_var == null or not is_instance_valid(tgt_var):
				_complete_action()
				return
			var tgt := tgt_var as Character
			var range_val := _member.attack_range if _member.character_data else 1
			if _manhattan(_member.grid_pos, tgt.grid_pos) > range_val:
				_complete_action()
				return
			var cost := _member.character_data.heal_mp_cost if _member.character_data else 0
			# アンデッド特効：回復量をダメージとして適用
			if tgt.character_data != null and tgt.character_data.is_undead \
					and tgt.is_friendly != _member.is_friendly:
				if _member.use_mp(cost):
					var power := _member.character_data.power if _member.character_data else 0
					tgt.take_damage(power, 1.0, _member, true)
					_member.spawn_heal_effect("cast")
					tgt.spawn_heal_effect("hit")
			else:
				# 通常回復
				if _member.use_mp(cost):
					var power := _member.character_data.power if _member.character_data else 0
					var hp_before := tgt.hp
					tgt.heal(power)  # heal() 内で HEAL SE 再生
					tgt.log_heal(_member, power, hp_before)
					_member.spawn_heal_effect("cast")
					tgt.spawn_heal_effect("hit")
			_state = _State.WAITING
			_timer = _member.character_data.post_delay if _member.character_data else 0.5

		"buff":
			var tgt_var: Variant = action.get("target", null)
			if tgt_var == null or not is_instance_valid(tgt_var):
				_complete_action()
				return
			var tgt := tgt_var as Character
			var range_val := _member.attack_range if _member.character_data else 1
			if _manhattan(_member.grid_pos, tgt.grid_pos) > range_val:
				_complete_action()
				return
			# バフ付与
			var cost := _member.character_data.buff_mp_cost if _member.character_data else 0
			if _member.use_mp(cost):
				tgt.apply_defense_buff()
				SoundManager.play_from(SoundManager.HEAL, _member)
				_member.spawn_heal_effect("cast")
				tgt.spawn_heal_effect("hit")
			_state = _State.WAITING
			_timer = _member.character_data.post_delay if _member.character_data else 0.5

		"use_potion":
			# インベントリからポーションを使用して短い待機
			var item_v: Variant = action.get("item", null)
			if item_v != null and _member != null and is_instance_valid(_member):
				var item := item_v as Dictionary
				if item != null and _member.character_data != null:
					_member.use_consumable(item)
					# 使用後に再評価
					notify_situation_changed()
			_state = _State.WAITING
			_timer = 0.3  # 使用後の短い硬直

		"wait":
			_state = _State.WAITING
			_timer = WAIT_DURATION / GlobalConstants.game_speed

		_:
			_complete_action()


## 目標に向かって1タイル進む。移動継続中なら true、到達またはスタックなら false
func _step_toward_goal() -> bool:
	var action_type := _current_action.get("action", "") as String
	if action_type == "move_to_formation":
		_goal = _formation_move_goal()
	elif action_type == "move_to_explore":
		pass  # goal は _start_action で固定済み（リアルタイム更新しない）
	elif _target != null and is_instance_valid(_target):
		if action_type == "move_to_attack":
			_goal = _calc_attack_goal(_target, _get_path_method())
		elif action_type == "flee":
			_goal = _find_flee_goal(_target)

	if _member.grid_pos == _goal:
		return false

	var next := _get_next_step(_goal)
	if next != _member.grid_pos:
		# 階段を目指しているとき、次のタイルに友好キャラがいれば押し出しを試みる
		if _move_policy == "stairs_down" or _move_policy == "stairs_up":
			var push_dir := next - _member.grid_pos
			_try_push_friendly_at(next, push_dir)
		_member.move_to(next, _get_move_interval())
		_dbg_stuck_count = 0
		return _member.grid_pos != _goal

	# --- デバッグ: 移動先が見つからず停滞している場合 ---
	if _member.is_friendly:
		_dbg_stuck_count += 1
		if _dbg_stuck_count >= 5:  # 5回連続で動けなかったらログ出力
			_dbg_stuck_count = 0
			var my_name := _member.character_data.character_name if _member.character_data != null else String(_member.name)
			var dbg_act := _current_action.get("action", "?") as String
			# 隣接タイルのブロック状況を調べる
			var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			var block_info: PackedStringArray = []
			for d: Vector2i in dirs:
				var adj := _member.grid_pos + d
				var passable := _is_passable(adj)
				if not passable:
					# 誰がブロックしているか特定
					var blocker_name := ""
					for other: Character in _all_members:
						if is_instance_valid(other) and other != _member \
								and other.current_floor == _member.current_floor \
								and adj in other.get_occupied_tiles():
							blocker_name = other.character_data.character_name if other.character_data != null else String(other.name)
							break
					if blocker_name.is_empty() and _player != null and is_instance_valid(_player) \
							and _player != _member and adj in _player.get_occupied_tiles():
						blocker_name = "hero"
					if blocker_name.is_empty():
						blocker_name = "wall/tile"
					block_info.append("%s=%s" % [adj, blocker_name])
			MessageLog.add_ai("[DBG_STUCK] %s@%s F%d act=%s goal=%s mv=%s blocks=[%s] _all=%d" % [
				my_name, _member.grid_pos, _member.current_floor,
				dbg_act, _goal, _move_policy,
				",".join(block_info), _all_members.size()])

	return false


func _get_next_step(goal: Vector2i) -> Vector2i:
	var method := _get_path_method()
	if method == PathMethod.DIRECT:
		return _next_step_direct(goal)
	var path := _astar(_member.grid_pos, goal)
	if path.is_empty():
		return _next_step_direct(goal)
	return path[0]


func _next_step_direct(goal: Vector2i) -> Vector2i:
	var dx := goal.x - _member.grid_pos.x
	var dy := goal.y - _member.grid_pos.y
	var candidates: Array[Vector2i] = []
	if abs(dx) >= abs(dy):
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
	else:
		if dy != 0: candidates.append(Vector2i(0, sign(dy)))
		if dx != 0: candidates.append(Vector2i(sign(dx), 0))
	for step: Vector2i in candidates:
		var next := _member.grid_pos + step
		if _is_passable(next):
			return next
	return _member.grid_pos


# --------------------------------------------------------------------------
# フォールバック評価（オーダーなし時の自律行動）
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# キュー管理
# --------------------------------------------------------------------------

func _generate_queue(strategy: int, target: Character) -> Array:
	# 現在いるエリアを訪問済みとして記録（NPC の階段探索に使用）
	if _map_data != null and _member != null and is_instance_valid(_member):
		var cur_area := _map_data.get_area(_member.grid_pos)
		if cur_area != "":
			_visited_areas[cur_area] = true

	# フロア追従（最優先）：合流済みメンバーが hero と別フロアにいる場合は階段を目指す
	# 未加入 NPC は _follow_hero_floors=false のため対象外（自律行動を維持）
	_floor_following = false
	if _member != null and is_instance_valid(_member) and _follow_hero_floors \
			and _player != null and is_instance_valid(_player) \
			and _member.current_floor != _player.current_floor:
		_floor_following = true
		return _generate_floor_follow_queue()

	# 階段タイルに乗ったまま待機しない（他キャラの通行を塞がないようにする）
	# 意図的に階段を使う場合（stairs_down/up ポリシー）および階段上での wait は除く
	if _is_stair_tile(_member.grid_pos) \
			and _move_policy != "stairs_down" and _move_policy != "stairs_up":
		var off_stair := _find_non_stair_adjacent(_member.grid_pos)
		if off_stair != _member.grid_pos:
			return [{"action": "move_to_explore", "goal": off_stair}]

	# HPポーション自動使用（瀕死かつ在庫あり・heal/buff より前に処理）
	var potion_q := _generate_potion_queue()
	if not potion_q.is_empty():
		return potion_q

	# 回復・バフ行動は戦略に関わらず最優先でキューに積む
	var heal_q := _generate_heal_queue()
	if not heal_q.is_empty():
		return heal_q
	var buff_q := _generate_buff_queue()
	if not buff_q.is_empty():
		return buff_q

	# アイテム取得ナビゲーション（戦況 SAFE のときのみ。戦闘中・撤退中は行わない）
	if _is_combat_safe():
		var item_pos := _find_item_pickup_target()
		if item_pos != Vector2i(-1, -1) and item_pos != _member.grid_pos:
			return [{"action": "move_to_explore", "goal": item_pos}]

	# --- 行動決定（strategy: 0=ATTACK, 1=FLEE, 2=WAIT） ---

	# FLEE: 逃走
	if strategy == 1:
		if target == null or not is_instance_valid(target):
			return [{"action": "wait"}]
		var q: Array = []
		for _i: int in range(5):
			q.append({"action": "flee"})
		return q

	# ATTACK: 戦闘
	if strategy == 0:
		if target == null or not is_instance_valid(target):
			# ターゲットがいない場合は move_policy に従って行動
			return _generate_move_queue()
		var atype := _get_attack_type()
		# standby: 移動せず射程内のみ攻撃
		if _move_policy == "standby":
			if _can_attack_target(target, atype):
				return [{"action": "attack"}]
			return [{"action": "wait"}]
		# 戦闘中は battle_formation のみで移動先を決定（move_policy を無視）
		match _battle_formation:
			"rear":
				if _can_attack_target(target, atype):
					return [{"action": "attack"}, {"action": "attack"}]
				return [{"action": "move_to_attack"}, {"action": "attack"}]
			_:  # surround / rush / gather
				var q: Array = []
				q.append({"action": "move_to_attack"})
				q.append({"action": "attack"})
				return q

	# WAIT: 移動方針に従って行動
	return _generate_move_queue()


## 移動方針（_move_policy）に従ってキューを生成する（WAIT/ATTACK(ターゲットなし)共通）
func _generate_move_queue() -> Array:
	match _move_policy:
		"explore":
			return _generate_explore_queue()
		"stairs_down":
			return _generate_stair_queue(1)
		"stairs_up":
			return _generate_stair_queue(-1)
		"standby":
			return [{"action": "wait"}]
		"guard_room":
			return _generate_guard_room_queue()
		_:
			if not _formation_satisfied():
				var q: Array = []
				for _i: int in range(3):
					q.append({"action": "move_to_formation"})
				q.append({"action": "wait"})
				return q
			return [{"action": "wait"}]


## 探索行動キューを生成する（move_policy == "explore" 時に使用）
func _generate_explore_queue() -> Array:
	var target_pos := _find_explore_target()
	if target_pos == Vector2i(-1, -1) or target_pos == _member.grid_pos:
		return [{"action": "wait"}]
	return [{"action": "move_to_explore", "goal": target_pos}]


## フロア追従キューを生成する（hero が別フロアにいる仲間専用）
## hero のフロアに向かう方向の階段を目標地点として A* 経路探索する
func _generate_floor_follow_queue() -> Array:
	if _map_data == null or _member == null or not is_instance_valid(_member):
		return [{"action": "wait"}]
	if _player == null or not is_instance_valid(_player):
		return [{"action": "wait"}]
	var direction: int = sign(_player.current_floor - _member.current_floor)
	var stair_type := MapData.TileType.STAIRS_DOWN if direction > 0 \
		else MapData.TileType.STAIRS_UP
	var stairs := _map_data.find_stairs(stair_type)
	if stairs.is_empty():
		return [{"action": "wait"}]
	# join_index で階段を分散割り当て（複数メンバーが同じ階段に重なるのを防ぐ）
	# 手順: 距離順にソート → join_index % 件数 番目を選択
	stairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _manhattan(_member.grid_pos, a) < _manhattan(_member.grid_pos, b))
	var idx := _member.join_index % stairs.size()
	var best := stairs[idx]
	# すでに階段タイルにいる場合は待機（game_map が遷移を処理する）
	if best == _member.grid_pos:
		return [{"action": "wait"}]
	return [{"action": "move_to_explore", "goal": best}]


## 階段移動キューを生成する（move_policy == "stairs_down"/"stairs_up" 時に使用）
## 未加入 NPC のフロアランク判断による階段移動に使用する
## GlobalConstants.NPC_KNOWS_STAIRS_LOCATION が false の場合は訪問済みエリアの階段のみ対象
## 訪問済みエリアに目的の階段がなければ通常の探索行動にフォールバック
func _generate_stair_queue(direction: int) -> Array:
	if _map_data == null or _member == null or not is_instance_valid(_member):
		return [{"action": "wait"}]
	var stair_type := MapData.TileType.STAIRS_DOWN if direction > 0 \
		else MapData.TileType.STAIRS_UP
	var stairs := _map_data.find_stairs(stair_type)
	if stairs.is_empty():
		return [{"action": "wait"}]

	# すでに目的の階段タイル上にいる場合は即座に待機（game_map が遷移を処理する）
	if _member.grid_pos in stairs:
		return [{"action": "wait"}]

	# 視界ベース：訪問済みエリアの階段のみ対象（フラグで地図持ちに切り替え可）
	if not GlobalConstants.NPC_KNOWS_STAIRS_LOCATION:
		var known: Array[Vector2i] = []
		for s: Vector2i in stairs:
			var area := _map_data.get_area(s)
			# エリアIDが空（通路・境界）の場合も隣接していれば既知扱い
			if area.is_empty():
				if _manhattan(_member.grid_pos, s) <= 3:
					known.append(s)
			elif _visited_areas.has(area):
				known.append(s)
		if known.is_empty():
			# 訪問済みエリアに階段未発見 → 通常探索にフォールバック
			return _generate_explore_queue()
		stairs = known

	var best := stairs[0]
	var best_dist := _manhattan(_member.grid_pos, best)
	for s: Vector2i in stairs:
		var d := _manhattan(_member.grid_pos, s)
		if d < best_dist:
			best_dist = d
			best      = s
	if best == _member.grid_pos:
		return [{"action": "wait"}]  # game_map が遷移を処理する
	return [{"action": "move_to_explore", "goal": best}]


## 帰還キューを生成する（move_policy == "guard_room" 時に使用）
## スポーン地点から2タイル以内なら待機。それ以外はスポーン地点へ移動する
func _generate_guard_room_queue() -> Array:
	if _member == null or not is_instance_valid(_member):
		return [{"action": "wait"}]
	if _manhattan(_member.grid_pos, _home_position) <= 2:
		return [{"action": "wait"}]
	return [{"action": "move_to_home"}]


## フロアアイテム辞書の参照を設定する（game_map から一度だけ呼ばれる）
## Dictionary は参照型なので、以降の追加・削除が自動的に反映される
## 戦況が SAFE（同エリアに敵なし）かどうかを返す
func _is_combat_safe() -> bool:
	var sit: int = _combat_situation.get("situation",
		int(GlobalConstants.CombatSituation.SAFE)) as int
	return sit == int(GlobalConstants.CombatSituation.SAFE)


func set_floor_items(items: Dictionary) -> void:
	_all_floor_items = items


## item_pickup 指示に従って取得すべきフィールドアイテムのタイル座標を返す
## アイテムがない・avoid の場合は Vector2i(-1,-1) を返す
func _find_item_pickup_target() -> Vector2i:
	if _item_pickup == "avoid" or _all_floor_items.is_empty():
		return Vector2i(-1, -1)
	if _map_data == null or _member == null or not is_instance_valid(_member):
		return Vector2i(-1, -1)
	var floor_idx := _member.current_floor
	if not _all_floor_items.has(floor_idx):
		return Vector2i(-1, -1)
	var floor_dict := _all_floor_items[floor_idx] as Dictionary
	if floor_dict.is_empty():
		return Vector2i(-1, -1)
	var my_area := _map_data.get_area(_member.grid_pos)
	var best_pos := Vector2i(-1, -1)
	var best_dist: float = INF
	for pos_v: Variant in floor_dict.keys():
		var item_pos := pos_v as Vector2i
		var dist := float(_manhattan(_member.grid_pos, item_pos))
		if _item_pickup == "aggressive":
			# 同じ部屋のアイテムのみ対象（通路にいる場合はスキップ）
			if my_area.is_empty():
				continue
			var item_area := _map_data.get_area(item_pos)
			if item_area != my_area:
				continue
		elif _item_pickup == "passive":
			# ITEM_PICKUP_RANGE マス以内のアイテムのみ対象
			if dist > float(GlobalConstants.ITEM_PICKUP_RANGE):
				continue
		if dist < best_dist:
			best_dist = dist
			best_pos = item_pos
	return best_pos


## 探索目標タイルを選ぶ
## 未訪問エリアがあればその最近傍タイル、全訪問済みならランダムエリアのタイル
func _find_explore_target() -> Vector2i:
	if _map_data == null:
		return Vector2i(-1, -1)
	var all_areas := _map_data.get_all_area_ids()
	if all_areas.is_empty():
		return Vector2i(-1, -1)

	# 未訪問エリアを収集
	var unvisited: Array[String] = []
	for area_id: String in all_areas:
		if _vision_system == null or not _vision_system.is_area_visited(area_id):
			unvisited.append(area_id)

	if unvisited.is_empty():
		# 全訪問済み → ランダムなエリアを巡回（階段以外のタイルを選ぶ）
		var random_area := all_areas[randi() % all_areas.size()]
		var tiles := _map_data.get_tiles_in_area(random_area)
		if tiles.is_empty():
			return Vector2i(-1, -1)
		var non_stair := tiles.filter(func(t: Vector2i) -> bool: return not _is_stair_tile(t))
		var pool: Array[Vector2i] = non_stair if not non_stair.is_empty() else tiles
		return pool[randi() % pool.size()]

	# 未訪問エリアを距離順にソートして候補リストを作る
	# NPC ごとに異なるインデックスを選ぶことで、全員が同じ目標に集中するのを防ぐ
	var candidates: Array[Dictionary] = []
	for area_id: String in unvisited:
		var tiles := _map_data.get_tiles_in_area(area_id)
		if tiles.is_empty():
			continue
		var non_stair := tiles.filter(func(t: Vector2i) -> bool: return not _is_stair_tile(t))
		var pool: Array[Vector2i] = non_stair if not non_stair.is_empty() else tiles
		var mid := pool[pool.size() / 2]
		var d   := _manhattan(_member.grid_pos, mid)
		if d > 0:
			candidates.append({"pos": mid, "dist": d})
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)
	# メンバー名のハッシュでオフセットを決定 → 各 NPC が異なるエリアを担当
	var offset: int = abs(_member.name.hash()) % candidates.size()
	return candidates[offset].get("pos", Vector2i(-1, -1)) as Vector2i


func _pop_action() -> Dictionary:
	if _queue.is_empty():
		return {}
	var action := _queue[0] as Dictionary
	_queue.pop_front()
	_current_action = action
	return action


func _complete_action() -> void:
	_current_action = {}


# --------------------------------------------------------------------------
# 攻撃実行
# --------------------------------------------------------------------------

func _execute_attack() -> void:
	if _attack_target == null or not is_instance_valid(_attack_target):
		return
	var atype := _get_attack_type()
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get(atype, 1.0)
	var dmg_power := int(float(_member.power) * type_mult)
	match atype:
		"ranged", "magic":
			# 遠距離攻撃（物理弓/魔法）：飛翔体を生成して命中確定ダメージ
			_member.face_toward(_attack_target.grid_pos)
			SoundManager.play_attack_from(_member)
			var map_node := _member.get_parent()
			if map_node != null:
				var proj := Projectile.new()
				proj.z_index = 2
				map_node.add_child(proj)
				var is_magic := (atype == "magic")
				var is_water := _get_is_water_shot()
				var ptype := _member.character_data.projectile_type \
						if _member.character_data != null else ""
				proj.setup(_member.position, _attack_target.position,
						true, _attack_target, dmg_power, 1.0, _member, is_magic,
						0.0, is_water, ptype)
		"dive":
			# 降下攻撃：方向倍率なし（飛行中の奇襲）、降下エフェクト表示
			SoundManager.play_attack_from(_member)
			_attack_target.take_damage(dmg_power, 1.0, _member, false)
			SoundManager.play_hit_from(_member)
			_spawn_dive_effect()
		_:
			# melee（近接攻撃）
			SoundManager.play_attack_from(_member)
			_attack_target.take_damage(dmg_power, 1.0, _member, false)
			SoundManager.play_hit_from(_member)


## 降下攻撃エフェクトを生成する（簡易：黄色→白のフラッシュ円）
func _spawn_dive_effect() -> void:
	var map_node := _member.get_parent()
	if map_node == null:
		return
	var effect := DiveEffect.new()
	effect.position = _member.position
	map_node.add_child(effect)


# --------------------------------------------------------------------------
# 目標座標計算
# --------------------------------------------------------------------------

func _calc_attack_goal(target: Character, method: PathMethod) -> Vector2i:
	var atype := _get_attack_type()
	if atype == "ranged" or atype == "magic":
		# 遠距離（物理/魔法）：射程内ならその場で攻撃。射程外なら射程内の最近傍タイルへ
		var range_val := _member.attack_range if _member.character_data else 5
		var dist := _manhattan(_member.grid_pos, target.grid_pos)
		if dist <= range_val:
			return _member.grid_pos
		return _find_ranged_goal(target, range_val)
	if method == PathMethod.ASTAR_FLANK:
		return _find_flank_goal(target)
	return _find_adjacent_goal(target)


## 遠距離攻撃用：ターゲットから range_val タイル以内で最近傍の通行可能タイルを返す
func _find_ranged_goal(target: Character, range_val: int) -> Vector2i:
	var best      := _member.grid_pos
	var best_dist := 999999
	var r := range_val
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var candidate := target.grid_pos + Vector2i(dx, dy)
			if _manhattan(candidate, target.grid_pos) > r:
				continue
			if not _is_passable(candidate):
				continue
			var d := _manhattan(_member.grid_pos, candidate)
			if d < best_dist:
				best_dist = d
				best      = candidate
	return best


## ターゲットに隣接する最近傍の空きタイルを返す（他のキャラが占有していないもの）
func _find_adjacent_goal(target: Character) -> Vector2i:
	var d := target.grid_pos - _member.grid_pos
	if abs(d.x) + abs(d.y) == 1:
		return _member.grid_pos
	var best           := _member.grid_pos
	var best_dist      := 999999
	var best_on_stair  := true  # 非階段タイルを優先
	for offset: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var candidate := target.grid_pos + offset
		if candidate == _member.grid_pos:
			return candidate
		if _is_passable(candidate):
			var dist     := _manhattan(_member.grid_pos, candidate)
			var on_stair := _is_stair_tile(candidate)
			# 非階段タイルを優先。同種類（stair/non-stair）なら近い方を選ぶ
			if (best_on_stair and not on_stair) \
					or (best_on_stair == on_stair and dist < best_dist):
				best_dist     = dist
				best          = candidate
				best_on_stair = on_stair
	return best


## クラスター隊形用：メンバーごとに方向をずらした隣接ゴールを返す
## join_index を使って異なる方向を優先させることで、全員が同じタイルに集中するのを防ぐ
func _find_spread_adjacent_goal(target: Character) -> Vector2i:
	# 既に隣接していれば現在位置を返す
	var d := target.grid_pos - _member.grid_pos
	if abs(d.x) + abs(d.y) == 1:
		return _member.grid_pos
	# 方向候補リストを join_index でローテーションする（4方向）
	var base_offsets: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)
	]
	var idx := (_member.join_index if _member != null else 0) % base_offsets.size()
	# join_index 番目から試す（ローテーション）
	for i: int in range(base_offsets.size()):
		var offset := base_offsets[(idx + i) % base_offsets.size()]
		var candidate := target.grid_pos + offset
		if candidate == _member.grid_pos:
			return candidate
		if _is_passable(candidate) and not _is_stair_tile(candidate):
			return candidate
	# 通行不可の場合は通常の隣接ゴール探索にフォールバック
	return _find_adjacent_goal(target)


## 現在地から最近傍の非階段タイルを BFS で探す（距離5まで・味方はすり抜け可能）
## 密集時に隣接4タイルが全て塞がれていても脱出経路を見つけられる
func _find_non_stair_adjacent(pos: Vector2i) -> Vector2i:
	if _map_data == null:
		return pos
	var visited: Dictionary = {pos: true}
	var queue: Array[Vector2i] = [pos]
	var dirs: Array[Vector2i] = [Vector2i(0,1), Vector2i(0,-1), Vector2i(1,0), Vector2i(-1,0)]
	while not queue.is_empty():
		var cur := queue.pop_front() as Vector2i
		if cur != pos and not _is_stair_tile(cur):
			return cur
		if abs(cur.x - pos.x) + abs(cur.y - pos.y) >= 5:
			continue
		for d: Vector2i in dirs:
			var nb := cur + d
			if visited.has(nb):
				continue
			visited[nb] = true
			# 壁・障害物は無条件にスキップ。友好キャラが占有していても通過可能扱い
			if _map_data.is_walkable_for(nb, _member.is_flying):
				queue.append(nb)
	return pos


## 指定タイルが階段（上り・下り）かどうか返す
func _is_stair_tile(pos: Vector2i) -> bool:
	if _map_data == null:
		return false
	var t := _map_data.get_tile(pos)
	return t == MapData.TileType.STAIRS_DOWN or t == MapData.TileType.STAIRS_UP


func _find_flank_goal(target: Character) -> Vector2i:
	var facing_vec := Character.dir_to_vec(target.facing)
	var behind     := target.grid_pos - facing_vec
	if _map_data != null and _map_data.is_walkable_for(behind, _member.is_flying):
		return behind
	return _find_adjacent_goal(target)


func _find_flee_goal(threat: Character) -> Vector2i:
	var dx := _member.grid_pos.x - threat.grid_pos.x
	var dy := _member.grid_pos.y - threat.grid_pos.y
	var flee_dir := Vector2i(
		sign(dx) if dx != 0 else (randi() % 3 - 1),
		sign(dy) if dy != 0 else (randi() % 3 - 1)
	)
	if flee_dir == Vector2i.ZERO:
		flee_dir = Vector2i(1, 0)
	var goal := _member.grid_pos
	for i: int in range(1, 6):
		var candidate := _member.grid_pos + flee_dir * i
		if _map_data != null and _map_data.is_walkable_for(candidate, _member.is_flying):
			goal = candidate
		else:
			break
	if goal == _member.grid_pos:
		var alts: Array[Vector2i] = [
			Vector2i(flee_dir.y,  flee_dir.x),
			Vector2i(-flee_dir.y, -flee_dir.x),
		]
		for alt: Vector2i in alts:
			var candidate := _member.grid_pos + alt
			if _map_data != null and _map_data.is_walkable_for(candidate, _member.is_flying):
				return candidate
	return goal


# --------------------------------------------------------------------------
# A* 経路探索
# --------------------------------------------------------------------------

func _astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return []
	var open_set:  Array[Vector2i] = [start]
	var came_from: Dictionary      = {}
	var g_score:   Dictionary      = {start: 0}
	var f_score:   Dictionary      = {start: _manhattan(start, goal)}
	var max_iter   := 400
	var iter       := 0
	while not open_set.is_empty() and iter < max_iter:
		iter += 1
		var current := open_set[0] as Vector2i
		for p: Vector2i in open_set:
			if (f_score.get(p, 99999) as int) < (f_score.get(current, 99999) as int):
				current = p
		if current == goal:
			var path: Array[Vector2i] = []
			var c := current
			while c != start:
				path.push_front(c)
				c = came_from[c] as Vector2i
			return path
		open_set.erase(current)
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor := current + offset
			# A* はタイル（壁・障害物）のみチェックし、キャラクター占有は無視する
			# 実際の移動ステップでは _is_passable() で占有チェックするため問題ない
			if _map_data != null and not _map_data.is_walkable_for(neighbor, _member.is_flying):
				continue
			# 階段タイルはゴール以外では中間経由地点として使わない
			# （意図しない階段使用を防ぐ。ゴールが階段 or stairs ポリシー時は除く）
			if _is_stair_tile(neighbor) and neighbor != goal \
					and _move_policy != "stairs_down" and _move_policy != "stairs_up":
				continue
			var tentative_g: int = (g_score.get(current, 99999) as int) + 1
			if tentative_g < (g_score.get(neighbor, 99999) as int):
				came_from[neighbor] = current
				g_score[neighbor]   = tentative_g
				f_score[neighbor]   = tentative_g + _manhattan(neighbor, goal)
				if neighbor not in open_set:
					open_set.append(neighbor)
	return []


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# --------------------------------------------------------------------------
# 移動方針（move_policy）ロジック
# --------------------------------------------------------------------------

## 現在の移動方針制約が満たされているか確認する
func _formation_satisfied() -> bool:
	match _move_policy:
		"spread", "standby", "explore", "stairs_down", "stairs_up":
			return true
		"follow":
			# リーダーの後方1マス周辺にいれば満足（後方・左後方・右後方）
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			var fwd_sat  := Character.dir_to_vec(_leader_ref.facing)
			var behind_sat := _leader_ref.grid_pos - fwd_sat
			var front_sat  := _leader_ref.grid_pos + fwd_sat
			# 前方にいる場合は常に不満足（後ろに回り込む）
			if _member.grid_pos == front_sat:
				return false
			# 後方が通行可：後方から1タイル以内なら満足（後方・左後方・右後方をカバー）
			if _map_data != null and _map_data.is_walkable_for(behind_sat, _member.is_flying):
				return _manhattan(_member.grid_pos, behind_sat) <= 1
			# 後方が壁・障害物：リーダーの隣接にいれば満足
			return _manhattan(_member.grid_pos, _leader_ref.grid_pos) <= 1
		"cluster":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			return _manhattan(_member.grid_pos, _leader_ref.grid_pos) <= 5
		"same_room":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			if _map_data == null:
				return true
			var my_area     := _map_data.get_area(_member.grid_pos)
			var leader_area := _map_data.get_area(_leader_ref.grid_pos)
			if my_area.is_empty() or leader_area.is_empty():
				# どちらかが通路にいる場合：近距離（3タイル以内）なら満足とみなす
				# 遠い場合は未満足 → リーダーに向かって移動する
				return _manhattan(_member.grid_pos, _leader_ref.grid_pos) <= 3
			return my_area == leader_area
		"gather":
			# パーティー重心から2タイル以内なら満足
			var centroid_sat := _calc_party_centroid()
			return _manhattan(_member.grid_pos, centroid_sat) <= 2
		"guard_room":
			if _guard_room_area.is_empty() or _map_data == null:
				return true
			var my_area := _map_data.get_area(_member.grid_pos)
			return my_area == _guard_room_area
	return true


## ターゲットが移動方針ゾーン内にいるか確認する（ゾーン外の敵は追わない）
func _target_in_formation_zone(target: Character) -> bool:
	match _move_policy:
		"spread", "explore", "stairs_down", "stairs_up":
			return true
		"follow":
			# リーダーの近く（4タイル以内）にいる敵を攻撃
			if _leader_ref == null or not is_instance_valid(_leader_ref):
				return true
			return _manhattan(target.grid_pos, _leader_ref.grid_pos) <= 4
		"standby":
			# 待機中は隣接マスの敵のみ攻撃
			var dv := target.grid_pos - _member.grid_pos
			return abs(dv.x) + abs(dv.y) <= 1
		"cluster":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			var attack_goal := _find_adjacent_goal(target)
			return _manhattan(attack_goal, _leader_ref.grid_pos) <= 3
		"same_room":
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return true
			if _map_data == null:
				return true
			var target_area: String = _map_data.get_area(target.grid_pos)
			var leader_area: String = _map_data.get_area(_leader_ref.grid_pos)
			if target_area.is_empty() or leader_area.is_empty():
				# 通路にいる場合は近距離チェックで代替
				return _manhattan(_member.grid_pos, _leader_ref.grid_pos) <= 3
			return target_area == leader_area
		"gather":
			# 重心から4タイル以内の敵を攻撃
			var centroid_zone := _calc_party_centroid()
			return _manhattan(target.grid_pos, centroid_zone) <= 4
		"guard_room":
			if _guard_room_area.is_empty() or _map_data == null:
				return true
			var target_area: String = _map_data.get_area(target.grid_pos)
			return target_area == _guard_room_area
	return true


## 移動方針ゴール：制約を満たすための目標タイルを返す
func _formation_move_goal() -> Vector2i:
	match _move_policy:
		"guard_room":
			# 守る部屋に戻る（最近傍タイル）
			if not _guard_room_area.is_empty() and _map_data != null:
				var tiles := _map_data.get_tiles_in_area(_guard_room_area)
				if not tiles.is_empty():
					var best      := tiles[0]
					var best_dist := _manhattan(_member.grid_pos, best)
					for t: Vector2i in tiles:
						var dist := _manhattan(_member.grid_pos, t)
						if dist < best_dist:
							best_dist = dist
							best      = t
					return best
			return _member.grid_pos
		"follow":
			# 後方優先で候補を探す（後方→左後方→右後方→左→右）
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return _member.grid_pos
			var fwd_g  := Character.dir_to_vec(_leader_ref.facing)
			var perp_g := Vector2i(-fwd_g.y, fwd_g.x)  # リーダー視点の左方向
			var behind_g := _leader_ref.grid_pos - fwd_g
			var candidates_g: Array[Vector2i] = [
				behind_g,                           # 後方
				behind_g + perp_g,                  # 左後方
				behind_g - perp_g,                  # 右後方
				_leader_ref.grid_pos + perp_g,      # 左
				_leader_ref.grid_pos - perp_g,      # 右
			]
			for cand_g: Vector2i in candidates_g:
				if _map_data != null and _map_data.is_walkable_for(cand_g, _member.is_flying) \
						and _is_passable(cand_g):
					return cand_g
			return _find_adjacent_goal(_leader_ref)
		"gather":
			# パーティー全メンバーの重心へ向かう
			return _calc_party_centroid()
		"cluster":
			# メンバーごとに異なる隣接タイルを優先する（join_index で方向をずらす）
			# → 全員が同一タイルを目標にして衝突・振動するのを防ぐ
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return _member.grid_pos
			return _find_spread_adjacent_goal(_leader_ref)
		_:
			# same_room → リーダーの隣接タイルへ
			if _leader_ref == null or not is_instance_valid(_leader_ref) \
					or _leader_ref == _member:
				return _member.grid_pos
			return _find_adjacent_goal(_leader_ref)


## パーティー全メンバーのグリッド座標重心を返す
func _calc_party_centroid() -> Vector2i:
	if _party_peers.is_empty():
		return _member.grid_pos if (_member != null and is_instance_valid(_member)) else Vector2i.ZERO
	var sx := 0
	var sy := 0
	var cnt := 0
	for peer_v: Variant in _party_peers:
		var peer := peer_v as Character
		if not is_instance_valid(peer):
			continue
		sx += peer.grid_pos.x
		sy += peer.grid_pos.y
		cnt += 1
	if cnt == 0:
		return _member.grid_pos if (_member != null and is_instance_valid(_member)) else Vector2i.ZERO
	return Vector2i(sx / cnt, sy / cnt)


# --------------------------------------------------------------------------
# 通行可能チェック
# --------------------------------------------------------------------------

## 移動先の座標が他キャラの確定位置（grid_pos）に被っているか調べる（旧・互換）
func _is_dest_occupied_by_other(pos: Vector2i) -> bool:
	return _is_dest_blocked_by_other(pos)


## 移動先の座標が「実際にブロックされている」か調べる
## 相手がすでに pos から離れる途中（is_pending かつ pending_grid_pos != pos）なら無視する
func _is_dest_blocked_by_other(pos: Vector2i) -> bool:
	for other: Character in _all_members:
		if not is_instance_valid(other) or other == _member:
			continue
		if other.current_floor != _member.current_floor:
			continue
		if other.is_flying != _member.is_flying:
			continue
		if other.grid_pos == pos:
			# 相手がそのタイルから別の場所へ移動中（押し出され済み）なら無視
			if other.is_pending() and other.get_pending_grid_pos() != pos:
				continue
			return true
	if _player != null and is_instance_valid(_player) and _player != _member:
		if _player.current_floor == _member.current_floor \
				and _player.is_flying == _member.is_flying \
				and _player.grid_pos == pos:
			if _player.is_pending() and _player.get_pending_grid_pos() != pos:
				pass  # 離れる途中なら無視
			else:
				return true
	return false


## 指定タイルにいる友好キャラを隣接タイルへ押し出す（階段移動中のリーダー専用）
## 成功すれば true を返す。push_dir は「リーダーが進んでいる方向」
func _try_push_friendly_at(pos: Vector2i, push_dir: Vector2i) -> bool:
	# 対象キャラを探す
	var target_char: Character = null
	for other: Character in _all_members:
		if not is_instance_valid(other) or other == _member:
			continue
		if other.current_floor != _member.current_floor:
			continue
		if other.is_flying != _member.is_flying:
			continue
		if other.grid_pos == pos and other.is_friendly and not other.is_player_controlled:
			target_char = other
			break
	if target_char == null:
		# _all_members に含まれない場合（player 自身）は押し出し不要
		return false
	# 押し出し先候補：前方（進行方向）→ 左 → 右 の順で試す
	var perp := Vector2i(-push_dir.y, push_dir.x)
	var candidates: Array[Vector2i] = [pos + push_dir, pos + perp, pos - perp]
	for dest: Vector2i in candidates:
		if _map_data == null or not _map_data.is_walkable_for(dest, target_char.is_flying):
			continue
		# 押し出し先に別キャラがいないか確認（pending 含む）
		var blocked := false
		for ch: Character in _all_members:
			if not is_instance_valid(ch) or ch == target_char:
				continue
			if ch.current_floor != _member.current_floor:
				continue
			if ch.grid_pos == dest or (ch.is_pending() and ch.get_pending_grid_pos() == dest):
				blocked = true
				break
		if blocked:
			continue
		if _player != null and is_instance_valid(_player) and _player != target_char:
			if _player.grid_pos == dest or (_player.is_pending() and _player.get_pending_grid_pos() == dest):
				continue
		# 押し出し実行（リーダーの移動と同じ速度で同時移動）
		target_char.move_to(dest, _get_move_interval())
		return true
	return false


func _is_passable(pos: Vector2i) -> bool:
	if _map_data != null and not _map_data.is_walkable_for(pos, _member.is_flying):
		return false
	# 飛行キャラは地上キャラの占有タイルを通過できる（同レイヤーのみブロック）
	for other: Character in _all_members:
		if not is_instance_valid(other):
			continue
		if other == _member:
			continue
		# 別フロアのキャラはブロックしない（マルチフロア対応）
		if other.current_floor != _member.current_floor:
			continue
		# フロア追従中は友好キャラをすり抜け可能（NPC 密集を抜けて階段に向かうため）
		if _floor_following and other.is_friendly:
			continue
		# 飛行同士はブロックし合う。地上同士もブロックし合う。飛行↔地上は通過可能
		if other.is_flying != _member.is_flying:
			continue
		if pos in other.get_occupied_tiles():
			return false
		# 移動予約中（アニメーション前半）の目的地もブロック扱いにする
		# → 複数メンバーが同一タイルを目標に選んで衝突するのを防ぐ
		if other.is_pending() and other.get_pending_grid_pos() == pos:
			return false
	# _player == _member の場合（hero の自己AI）は自分のタイルをブロックしない
	if _player != null and is_instance_valid(_player) and _player != _member:
		if _player.current_floor == _member.current_floor \
				and _player.is_flying == _member.is_flying \
				and pos in _player.get_occupied_tiles():
			return false
		if _player.is_pending() and _player.get_pending_grid_pos() == pos \
				and _player.current_floor == _member.current_floor \
				and _player.is_flying == _member.is_flying:
			return false
	return true


# --------------------------------------------------------------------------
# 攻撃タイプヘルパー
# --------------------------------------------------------------------------

## キャラデータの attack_type を返す（未設定時は "melee"）
func _get_attack_type() -> String:
	if _member != null and _member.character_data != null:
		return _member.character_data.attack_type
	return "melee"


## 指定ターゲットに攻撃タイプで攻撃可能か判定する
## melee: 隣接かつターゲットが地上（飛行→地上OK、地上→飛行NG、飛行→飛行NG）
## ranged: 射程内かつ double-layer 無関係
## dive:  隣接かつターゲットが地上（地上→飛行NG。飛行→飛行NGは仕様）
func _can_attack_target(target: Character, atype: String) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	match atype:
		"ranged", "magic":
			var range_val := _member.attack_range if _member.character_data else 5
			return _manhattan(_member.grid_pos, target.grid_pos) <= range_val
		"dive":
			# 降下攻撃：飛行キャラが地上キャラに隣接して攻撃（ターゲットは地上のみ）
			if target.is_flying:
				return false
			var d := target.grid_pos - _member.grid_pos
			return abs(d.x) + abs(d.y) == 1
		_:  # melee
			# 地上→飛行・飛行→飛行は不可
			if target.is_flying:
				return false
			var d := target.grid_pos - _member.grid_pos
			return abs(d.x) + abs(d.y) == 1


# --------------------------------------------------------------------------
# 回復・バフキュー生成
# --------------------------------------------------------------------------

## 回復行動キューを返す。回復すべき状況でなければ空配列
func _generate_heal_queue() -> Array:
	if _member == null or _member.character_data == null:
		return []
	if _member.character_data.power <= 0:
		return []
	var cost := _member.character_data.heal_mp_cost
	if cost <= 0:
		return []
	if _member.mp < cost:
		return []
	# 味方の回復を優先
	var heal_target := _find_heal_target()
	if heal_target != null:
		return [{"action": "move_to_heal", "target": heal_target},
				{"action": "heal", "target": heal_target}]
	# 次にアンデッド敵への特効攻撃（ヒーラーの回復魔法がアンデッドにダメージ）
	var undead_target := _find_undead_target()
	if undead_target != null:
		return [{"action": "move_to_heal", "target": undead_target},
				{"action": "heal", "target": undead_target}]
	return []


## バフ行動キューを返す。バフを付与すべき状況でなければ空配列
func _generate_buff_queue() -> Array:
	if _member == null or _member.character_data == null:
		return []
	if _member.character_data.buff_mp_cost <= 0:
		return []
	if _member.mp < _member.character_data.buff_mp_cost:
		return []
	# バフが切れているパーティーメンバーを探す
	var buff_target := _find_buff_target()
	if buff_target == null:
		return []
	return [{"action": "move_to_buff", "target": buff_target},
			{"action": "buff", "target": buff_target}]


## 回復対象を返す。heal（current_order.heal）に従って選定する。
## _party_peers（自パーティーメンバー）と _player（hero）のみを対象とする。
## heal:
##   "aggressive"    : NEAR_DEATH_THRESHOLD 以下のキャラで最もHPが低い者
##   "leader_first"  : リーダー（_leader_ref）が閾値未満なら優先、その後 aggressive と同じ
##   "lowest_hp_first": 閾値なし・最もHP割合が低い者（0%は除く）
##   "none"          : 回復しない（null を返す）
func _find_heal_target() -> Character:
	if _member == null:
		return null
	var heal_mode: String = "lowest_hp_first"
	if _member.current_order != null:
		heal_mode = _member.current_order.get("heal", "lowest_hp_first") as String

	if heal_mode == "none":
		return null

	# 候補リストを構築
	var candidates: Array[Character] = []
	candidates.assign(_party_peers)
	if _player != null and is_instance_valid(_player) and not candidates.has(_player):
		candidates.append(_player)
	var my_friendly: bool = _member.is_friendly if _member != null else true

	match heal_mode:
		"leader_first":
			# リーダーが閾値未満なら最優先
			if _leader_ref != null and is_instance_valid(_leader_ref) \
					and _leader_ref.hp > 0 and _leader_ref.is_friendly == my_friendly:
				var lr := float(_leader_ref.hp) / float(maxi(_leader_ref.max_hp, 1))
				if lr < GlobalConstants.NEAR_DEATH_THRESHOLD:
					return _leader_ref
			# その後 aggressive と同じ挙動
			return _find_heal_target_by_ratio(candidates, my_friendly,
					GlobalConstants.NEAR_DEATH_THRESHOLD)
		"lowest_hp_first":
			# 閾値なし・最もHP割合が低い者（HP > 0 のみ）
			return _find_heal_target_by_ratio(candidates, my_friendly, 1.0)
		_:  # "aggressive"
			return _find_heal_target_by_ratio(candidates, my_friendly,
					GlobalConstants.NEAR_DEATH_THRESHOLD)


## heal候補リストから最もHP割合が低いキャラを返すヘルパー
## threshold: この割合未満のキャラのみ対象
func _find_heal_target_by_ratio(candidates: Array[Character], my_friendly: bool,
		threshold: float) -> Character:
	var best: Character = null
	var best_ratio := threshold
	for ch: Character in candidates:
		if not is_instance_valid(ch) or ch.hp <= 0:
			continue
		if ch.is_friendly != my_friendly:
			continue
		var ratio := float(ch.hp) / float(maxi(ch.max_hp, 1))
		if ratio < best_ratio:
			best_ratio = ratio
			best = ch
	return best


## アンデッド攻撃対象（射程内・同フロア・敵陣営のアンデッドキャラ）を返す
## ヒーラーが回復魔法でアンデッドに特効ダメージを与えるために使用
func _find_undead_target() -> Character:
	if _member == null or _member.character_data == null:
		return null
	var range_val := _member.character_data.attack_range
	for ch: Character in _all_members:
		if not is_instance_valid(ch) or ch.hp <= 0:
			continue
		if ch.is_friendly == _member.is_friendly:
			continue  # 同じ陣営はスキップ
		if ch.character_data == null or not ch.character_data.is_undead:
			continue
		if ch.current_floor != _member.current_floor:
			continue
		if _manhattan(_member.grid_pos, ch.grid_pos) <= range_val:
			return ch
	return null


## HPポーション / SP・MPポーション自動使用キューを生成する
## _hp_potion == "use" かつ 瀕死（NEAR_DEATH_THRESHOLD 未満）かつ在庫ありのとき "use_potion" を返す
## SP/MPポーションは _sp_mp_potion == "use" かつ MP/SP が半分以下のとき使用
func _generate_potion_queue() -> Array:
	if _member == null or _member.character_data == null:
		return []
	var cd := _member.character_data

	# HPポーション
	if _hp_potion == "use" and _member.max_hp > 0:
		var hp_ratio := float(_member.hp) / float(_member.max_hp)
		if hp_ratio < GlobalConstants.NEAR_DEATH_THRESHOLD:
			var potion: Variant = _find_potion_in_inventory(cd, "hp")
			if potion != null:
				return [{"action": "use_potion", "item": potion}]

	# SP/MPポーション
	if _sp_mp_potion == "use":
		var is_magic := cd.class_id in ["magician-fire", "magician-water", "healer"]
		if is_magic and _member.max_mp > 0 and float(_member.mp) / float(_member.max_mp) < 0.5:
			var potion: Variant = _find_potion_in_inventory(cd, "mp")
			if potion != null:
				return [{"action": "use_potion", "item": potion}]
		elif not is_magic and _member.max_sp > 0 and float(_member.sp) / float(_member.max_sp) < 0.5:
			var potion: Variant = _find_potion_in_inventory(cd, "sp")
			if potion != null:
				return [{"action": "use_potion", "item": potion}]

	return []


## インベントリからポーション種別を検索して返す（なければ null）
func _find_potion_in_inventory(cd: CharacterData, kind: String) -> Variant:
	var effect_key := "restore_" + kind  ## "restore_hp" / "restore_mp" / "restore_sp"
	for item_v: Variant in cd.inventory:
		var item := item_v as Dictionary
		if item == null:
			continue
		var cat: String = item.get("category", "") as String
		if cat != "consumable":
			continue
		# 装備中アイテムをスキップ
		if item == cd.equipped_weapon or item == cd.equipped_armor or item == cd.equipped_shield:
			continue
		var effect := item.get("effect", {}) as Dictionary
		if effect.has(effect_key) and int(effect[effect_key]) > 0:
			return item
	return null


## バフ対象（同一パーティー内でバフが切れているキャラ）を返す
## _party_peers（自パーティーメンバー）と _player（hero）のみを対象とする。
## 未加入 NPC など他パーティーのキャラは対象外。
func _find_buff_target() -> Character:
	var candidates: Array[Character] = []
	candidates.assign(_party_peers)
	if _player != null and is_instance_valid(_player) and not candidates.has(_player):
		candidates.append(_player)
	var my_friendly: bool = _member.is_friendly if _member != null else true
	for ch: Character in candidates:
		if not is_instance_valid(ch) or ch.hp <= 0:
			continue
		if ch.is_friendly != my_friendly:
			continue  # 同じ陣営のみ対象
		if ch.defense_buff_timer <= 0.0:
			return ch
	return null


# --------------------------------------------------------------------------
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

## 現在の指示と状態から有効な行動を決定する（0=ATTACK, 1=FLEE, 2=WAIT 相当の int を返す）
## _generate_queue() に渡す値を算出し、キュー補充判定にも使う
func _determine_effective_action() -> int:
	# 1. パーティーレベルの撤退指示が来ている場合
	if _party_fleeing:
		if _should_ignore_flee():
			return 0  # ATTACK: 逃げない種族は戦闘継続
		return 1  # FLEE

	# 2. 種族固有の自己判断で逃走する場合（ゴブリン系: HP30%未満）
	if _should_self_flee():
		return 1  # FLEE

	# 3. 種族固有の攻撃不能判断（MP不足の魔法系）
	if not _can_attack():
		return 2  # WAIT（MP回復待ち）

	# 4. on_low_hp 条件: メンバー個別の低HP時行動
	if _member != null and is_instance_valid(_member) and _member.max_hp > 0 \
			and float(_member.hp) / float(_member.max_hp) < GlobalConstants.NEAR_DEATH_THRESHOLD:
		match _on_low_hp:
			"flee":
				if not _should_ignore_flee():
					return 1  # FLEE
			"retreat":
				return 2  # WAIT（cluster 移動はリーダー側で move_policy に設定済み）

	# 5. combat_situation が SAFE なら移動方針に従う（WAIT 相当）
	if _is_combat_safe():
		return 2  # WAIT

	# 6. 戦闘中: combat 方針に従う
	match _combat:
		"attack", "aggressive":
			return 0  # ATTACK
		"flee":
			if not _should_ignore_flee():
				return 1  # FLEE
			return 0  # ATTACK
		"defense", "support", "standby":
			return 2  # WAIT
	return 0  # デフォルト: ATTACK


## 種族フック: FLEE 指示を無視するか（逃げない種族が true を返す）
func _should_ignore_flee() -> bool:
	return false

## 種族フック: 自己判断で逃走するか（ゴブリン系が HP 低下時に true を返す）
func _should_self_flee() -> bool:
	return false

## 種族フック: 攻撃可能か（MP 不足の魔法系が false を返す）
func _can_attack() -> bool:
	return true


## フォールバック再評価（オーダーなし時のフォールバック用）
func _fallback_evaluate_action() -> void:
	var new_effective := _determine_effective_action()
	if new_effective == _strategy and _queue.size() >= QUEUE_MIN_LEN:
		return
	_strategy = new_effective
	var new_queue := _generate_queue(new_effective, _target)
	if new_queue.is_empty():
		return
	_queue = new_queue
	if _state != _State.ATTACKING_PRE and _state != _State.ATTACKING_POST:
		_current_action = {}
		_state = _State.IDLE
		if is_instance_valid(_member):
			_member.is_attacking = false


func _select_target() -> Character:
	return _player


## 戦闘隊形（battle_formation）に基づいて経路探索方法を選択する
func _get_path_method() -> PathMethod:
	match _battle_formation:
		"rear":  return PathMethod.ASTAR_FLANK  # 背後を取る
		"rush":  return PathMethod.ASTAR         # 直線突撃（surround と同じ経路だが攻撃優先）
		_:       return PathMethod.ASTAR


## 移動間隔（秒/タイル）。サブクラスで上書きして速度変更可能
## zombie=遅い(MOVE_INTERVAL*2.0) / wolf=速い(MOVE_INTERVAL*0.67) など
## GlobalConstants.game_speed で割ることで設定画面の速度変更に対応する
func _get_move_interval() -> float:
	return MOVE_INTERVAL / GlobalConstants.game_speed


## 攻撃実行後に呼ばれるフック。MP消費などはここで行う（サブクラスでオーバーライド）
func _on_after_attack() -> void:
	pass


## 遠距離魔法攻撃時に水弾を使うかどうかを返す（サブクラスでオーバーライド）
## LichUnitAI が火/水を交互に切り替えるために使用
func _get_is_water_shot() -> bool:
	return false
