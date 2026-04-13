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
##   _evaluate_combat_situation(): 戦況判断（自軍と同エリア敵の戦力比較）
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
var _combat_situation: Dictionary = {}  ## 最新の戦況判断結果（_evaluate_combat_situation の戻り値）
var log_enabled:     bool  = true  ## false にするとログ出力を抑制する（一時パーティー用）
var joined_to_player: bool = false ## true の場合は _player を隊形基準として使用する（合流済み NPC パーティー）
var _reeval_timer:   float = 0.0
var _initial_count:  int   = 0  ## 初期メンバー数（逃走判定の基準）
var _friendly_list:  Array[Character] = []  ## 攻撃対象の友好キャラ一覧（敵 AI 用）
var _visited_areas:  Dictionary = {}  ## 訪問済みエリアID集合（全 UnitAI で共有）
## パーティー全体方針（Party.global_orders の参照。hp_potion/sp_mp_potion 等を UnitAI に伝達）
## set_global_orders() で Party.global_orders dict への参照を受け取る（参照共有なので変更が反映される）
var _global_orders:  Dictionary = {}


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


## 全パーティー合算メンバーリストを各 UnitAI に反映する
func set_all_members(all_members: Array[Character]) -> void:
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


## フロアアイテム辞書の参照を全 UnitAI に配布する（game_map から呼ばれる）
func set_floor_items(items: Dictionary) -> void:
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_floor_items(items)


# --------------------------------------------------------------------------
# 定期処理
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	# 時間停止中（プレイヤーのターゲット選択中など）は再評価を止める
	if not GlobalConstants.world_time_running:
		return
	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = REEVAL_INTERVAL
		_combat_situation = _evaluate_combat_situation()
		_assign_orders()


# --------------------------------------------------------------------------
# 指示伝達（共通ロジック）
# --------------------------------------------------------------------------

## 戦略を評価して各メンバーにオーダーを発行する
## パーティー戦略に応じて move / combat / party_fleeing を決定し UnitAI に渡す
## 行動の最終決定は UnitAI._determine_effective_action() が行う
func _assign_orders() -> void:
	_party_strategy = _apply_range_check(_evaluate_party_strategy())

	# 戦略変更時にログ出力
	if _party_strategy != _prev_strategy:
		var old_strategy := _prev_strategy
		_prev_strategy = _party_strategy
		if log_enabled and not _has_player_controlled_member():
			_log_strategy_change(old_strategy)

	# パーティーレベルの撤退判断
	var party_fleeing := (_party_strategy == Strategy.FLEE)

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

	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue

		var order          := member.current_order
		var combat         : String = order.get("combat",          "attack")
		var on_low_hp      : String = order.get("on_low_hp",       "retreat")
		var tgt_policy     : String = order.get("target",          "same_as_leader")
		var battle_form    : String = order.get("battle_formation", "surround")

		# ── 移動方針設定 ──────────────────────────────────────────────────
		var move_policy  : String    = "spread"
		var formation_ref: Character = null
		if member.is_friendly:
			move_policy = _global_orders.get("move", order.get("move", "same_room")) as String
			if leader_char == null or leader_char == member:
				if _player != null and is_instance_valid(_player) \
						and (leader_char == _player or joined_to_player):
					formation_ref = _player
			else:
				formation_ref = leader_char

		# ── パーティー戦略に応じた移動方針の上書き ──────────────────────────
		if _party_strategy == Strategy.EXPLORE:
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
		elif _party_strategy == Strategy.GUARD_ROOM:
			move_policy = "guard_room"

		# on_low_hp=retreat 時は cluster に上書き
		if on_low_hp == "retreat" and member.max_hp > 0 \
				and float(member.hp) / float(member.max_hp) < GlobalConstants.NEAR_DEATH_THRESHOLD:
			move_policy = "cluster"

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

		# フロアをまたいだ追従（未加入 NPC 非リーダーメンバー専用）
		if not joined_to_player and member.is_friendly \
				and leader_char != null and is_instance_valid(leader_char) \
				and member != leader_char \
				and member.current_floor != leader_char.current_floor:
			var floor_dir: int = sign(leader_char.current_floor - member.current_floor)
			move_policy = "stairs_down" if floor_dir > 0 else "stairs_up"
			target = null

		unit_ai.receive_order({
			"target":            target,
			"combat":            combat,
			"on_low_hp":         on_low_hp,
			"move":              move_policy,
			"battle_formation":  battle_form,
			"leader":            formation_ref,
			"party_fleeing":     party_fleeing,
			"hp_potion":         _global_orders.get("hp_potion",    "never") as String,
			"sp_mp_potion":      _global_orders.get("sp_mp_potion", "never") as String,
			"item_pickup":       member.current_order.get("item_pickup", "passive") as String,
			"combat_situation":  _combat_situation,
		})


# --------------------------------------------------------------------------
# 通知・デバッグ
# --------------------------------------------------------------------------

## 状況変化通知（PartyManager から呼ばれる）：即座に再評価してオーダーを発行する
func notify_situation_changed() -> void:
	_reeval_timer = 0.0
	_combat_situation = _evaluate_combat_situation()
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


func get_global_orders_hint() -> Dictionary:
	if not _global_orders.is_empty():
		return _global_orders
	var hint: Dictionary = {}
	match _party_strategy:
		Strategy.ATTACK:
			hint = {"move": "cluster", "battle_policy": "attack",   "target": "nearest", "hp_potion": "never", "on_low_hp": "keep_fighting", "item_pickup": "avoid"}
		Strategy.FLEE:
			hint = {"move": "cluster", "battle_policy": "retreat",  "target": "nearest", "hp_potion": "never", "on_low_hp": "flee",          "item_pickup": "avoid"}
		Strategy.WAIT:
			hint = {"move": "standby", "battle_policy": "defense",  "target": "nearest", "hp_potion": "never", "on_low_hp": "keep_fighting", "item_pickup": "avoid"}
		Strategy.DEFEND:
			hint = {"move": "same_room", "battle_policy": "defense","target": "nearest", "hp_potion": "never", "on_low_hp": "keep_fighting", "item_pickup": "avoid"}
		Strategy.EXPLORE:
			hint = {"move": "explore",     "battle_policy": "attack",   "target": "nearest", "hp_potion": "never", "on_low_hp": "keep_fighting", "item_pickup": "avoid"}
		Strategy.GUARD_ROOM:
			hint = {"move": "guard_room",  "battle_policy": "retreat",  "target": "nearest", "hp_potion": "never", "on_low_hp": "keep_fighting", "item_pickup": "avoid"}
		_:
			hint = {"move": "-", "battle_policy": "-", "target": "-", "hp_potion": "-", "on_low_hp": "-", "item_pickup": "-"}
	return hint


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


## パーティー全体の戦略を評価する（サブクラスがオーバーライド）
func _evaluate_party_strategy() -> Strategy:
	return Strategy.WAIT


## 指定メンバーの攻撃ターゲットを選択する（サブクラスがオーバーライド）
func _select_target_for(_member: Character) -> Character:
	return _player


## 最もHPが少ない攻撃ターゲットを選択する
func _select_weakest_target(member: Character) -> Character:
	return _select_target_for(member)


## パーティーの戦力値を算出する（ランク和 × HP充足率）
## HP充足率にはHPポーションの回復量を加味する
## 生存メンバーが0人の場合は 0.0 を返す
## 自パーティーの戦力を評価する（正確なHP%とポーション回復量を使用）
## 既存の呼び出し箇所を壊さないラッパー
func _evaluate_party_strength() -> float:
	return _evaluate_party_strength_for(_party_members, false)


## 指定メンバーリストの戦力を評価する
## use_estimated_hp = false: 正確なHP%とポーション回復量を使う（自軍用）
## use_estimated_hp = true:  状態ラベル（condition）からHP%を推定する（敵用。hp/max_hp を直接参照しない）
func _evaluate_party_strength_for(members: Array, use_estimated_hp: bool = false) -> float:
	var rank_sum := 0
	var hp_ratio_sum := 0.0
	var alive_count := 0
	for mv: Variant in members:
		var m := mv as Character
		if m == null or not is_instance_valid(m) or m.hp <= 0:
			continue
		if m.character_data != null:
			rank_sum += RANK_VALUES.get(m.character_data.rank, 3) as int
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
		return 0.0
	var avg_hp_ratio := hp_ratio_sum / float(alive_count)
	return float(rank_sum) * avg_hp_ratio


## 状態ラベルからHP割合を推定する（敵の戦力を過大評価する安全側に倒す）
## 各ラベルの閾値範囲の最大値を返す
func _estimate_hp_ratio_from_condition(condition: String) -> float:
	match condition:
		"healthy":  return 1.0
		"wounded":  return GlobalConstants.CONDITION_HEALTHY_THRESHOLD
		"critical": return GlobalConstants.CONDITION_WOUNDED_THRESHOLD
		_:          return 1.0  # 不明な値 → 安全側（敵を強く見積もる）


## メンバーが所持しているHPポーションの合計回復量を返す
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


## 戦況判断の共通ルーチン
## 自パーティーの戦力と、同じエリアにいる敵の戦力を比較して戦況を分類する
## 結果は _assign_orders() → receive_order() の combat_situation フィールドに含めてメンバーに伝達する
func _evaluate_combat_situation() -> Dictionary:
	# 自パーティーのフロアとエリアを取得
	var my_floor := -1
	var my_area := ""
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			my_floor = m.current_floor
			if _map_data != null:
				my_area = _map_data.get_area(m.grid_pos)
			break

	# 同じエリアにいる敵を収集
	var area_enemies: Array[Character] = []
	# 敵 AI → _friendly_list が攻撃対象（プレイヤー・NPC）。自分が敵の場合、_friendly_list が「敵」
	# 味方 AI → _enemy_list は PartyLeaderPlayer / NpcLeaderAI が保持。PartyLeader には直接ない
	# → 共通化のため、_get_opposing_characters() 仮想メソッドで取得する
	var opponents := _get_opposing_characters()
	for opp: Character in opponents:
		if not is_instance_valid(opp) or opp.hp <= 0:
			continue
		if opp.current_floor != my_floor:
			continue
		if _map_data != null:
			var opp_area := _map_data.get_area(opp.grid_pos)
			if my_area.is_empty() or opp_area != my_area:
				continue
		area_enemies.append(opp)

	# 敵がいなければ安全
	if area_enemies.is_empty():
		return {
			"situation": int(GlobalConstants.CombatSituation.SAFE),
			"ratio": 0.0,
			"my_strength": _evaluate_party_strength(),
			"enemy_strength": 0.0,
		}

	# 戦力比較
	var my_strength := _evaluate_party_strength()
	var enemy_strength := _evaluate_party_strength_for(area_enemies, true)

	var ratio := 0.0
	var situation: int
	if enemy_strength <= 0.0:
		ratio = 99.0
		situation = int(GlobalConstants.CombatSituation.SAFE)
	else:
		ratio = my_strength / enemy_strength
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

	return {
		"situation": situation,
		"ratio": ratio,
		"my_strength": my_strength,
		"enemy_strength": enemy_strength,
	}


## 対立するキャラクターのリストを返す（サブクラスでオーバーライド）
## 敵 AI: _friendly_list（プレイヤー・NPC）
## 味方 AI: _enemy_list（敵キャラ）
func _get_opposing_characters() -> Array[Character]:
	return _friendly_list
