class_name PartyLeaderAI
extends Node

## リーダーAI基底クラス（2層AIアーキテクチャのパーティーレイヤー）
## パーティー全体の戦略を決定し、各メンバーの UnitAI にオーダーを渡す
## サブクラスは以下をオーバーライドする:
##   _create_unit_ai()         : メンバーに対応する UnitAI の種別を返す
##   _evaluate_party_strategy(): パーティー全体の戦略判断
##   _select_target_for()      : メンバーごとの攻撃ターゲット選択
##   _select_weakest_target()  : 最弱ターゲット選択（複数候補がある場合）

## パーティー戦略（ATTACK=0, FLEE=1, WAIT=2 は UnitAI.Strategy と int 値一致）
## DEFEND=3, EXPLORE=4, GUARD_ROOM=5 はパーティーレベル専用（UnitAI へは WAIT/ATTACK に変換して渡す）
enum Strategy { ATTACK, FLEE, WAIT, DEFEND, EXPLORE, GUARD_ROOM }

const REEVAL_INTERVAL := 1.5  ## 定期再評価の間隔（秒）

var _party_members: Array[Character] = []
var _player:        Character
var _map_data:      MapData
var _unit_ais:      Dictionary = {}  ## member.name -> UnitAI
var _party_strategy: Strategy = Strategy.WAIT
var _prev_strategy:  Strategy = Strategy.WAIT  ## 前回の戦略（変更検出用）
var log_enabled:     bool  = true  ## false にするとログ出力を抑制する（一時パーティー用）
var joined_to_player: bool = false ## true の場合は _player を隊形基準として使用する（合流済み NPC パーティー）
var _reeval_timer:   float = 0.0
var _initial_count:  int   = 0  ## 初期メンバー数（逃走判定の基準）
var _friendly_list:  Array[Character] = []  ## 攻撃対象の友好キャラ一覧（敵 AI 用）
var _visited_areas:  Dictionary = {}  ## 訪問済みエリアID集合（全 UnitAI で共有）
## パーティー全体方針（Party.global_orders の参照。hp_potion/sp_mp_potion 等を UnitAI に伝達）
## set_global_orders() で Party.global_orders dict への参照を受け取る（参照共有なので変更が反映される）
var _global_orders:  Dictionary = {}


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


## 攻撃対象となる友好キャラ一覧を設定する（敵 AI のターゲット選択に使用）
func set_friendly_list(friendlies: Array[Character]) -> void:
	_friendly_list = friendlies


## Party.global_orders への参照を受け取る（GDScript では Dictionary は参照型のため変更が自動反映）
## game_map が NpcManager / hero_manager セットアップ時に呼ぶ
func set_global_orders(orders: Dictionary) -> void:
	_global_orders = orders


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


func _process(delta: float) -> void:
	# 時間停止中（プレイヤーのターゲット選択中など）は再評価を止める
	if not GlobalConstants.world_time_running:
		return
	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = REEVAL_INTERVAL
		_assign_orders()


## 戦略を評価して各メンバーにオーダーを発行する
## current_order の各項目をパーティー戦略とマージして UnitAI に渡す
func _assign_orders() -> void:
	_party_strategy = _apply_range_check(_evaluate_party_strategy())

	# 戦略変更時にログ出力
	# - プレイヤー操作中のメンバーがいる場合はスキップ（プレイヤーが指示を出す側）
	# - 初回評価でも、デフォルト（WAIT）から変わっていればログを出す（敵のアクティブ化時など）
	if _party_strategy != _prev_strategy:
		var old_strategy := _prev_strategy
		_prev_strategy = _party_strategy
		if log_enabled and not _has_player_controlled_member():
			_log_strategy_change(old_strategy)

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
		# 敵は move 制約なし（spread）。味方は global_orders.move を優先使用（OrderWindow の全体方針）
		var move_policy  : String    = "spread"
		var formation_ref: Character = null
		if member.is_friendly:
			# "move" は GLOBAL_ROWS 専用キーのため global_orders から読む（未設定時は current_order にフォールバック）
			move_policy = _global_orders.get("move", order.get("move", "same_room")) as String
			if leader_char == null or leader_char == member:
				# この member がリーダー（または1人パーティー）の場合：
				# ① hero がこのパーティーのリーダー（hero パーティー）
				# ② 合流済み NPC パーティー（joined_to_player フラグ）
				# のいずれかであれば hero を隊形基準にする。
				# それ以外（未加入 NPC）は formation_ref = null のまま（NPC リーダーは自由行動）。
				if _player != null and is_instance_valid(_player) \
						and (leader_char == _player or joined_to_player):
					formation_ref = _player
			else:
				formation_ref = leader_char

		# ── 有効戦略を決定 ───────────────────────────────────────────────
		# 1. パーティー逃走は最優先（GoblinLeaderAI などの集団判断）
		var effective_strat: int
		if _party_strategy == Strategy.FLEE:
			effective_strat = int(Strategy.FLEE)
		elif _party_strategy == Strategy.EXPLORE:
			if joined_to_player:
				# 合流済みメンバー：探索ではなく global_orders の移動方針（follow 等）に従う
				# move_policy は上で _global_orders から設定済みのためここでは上書きしない
				var cd := member.character_data
				if cd != null and (cd.power > 0 or cd.buff_mp_cost > 0):
					effective_strat = int(Strategy.WAIT)
				else:
					effective_strat = int(Strategy.ATTACK)
			else:
				# 未合流 NPC：リーダーは探索、非リーダーはリーダーを追従
				var cd := member.character_data
				if cd != null and (cd.power > 0 or cd.buff_mp_cost > 0):
					effective_strat = int(Strategy.WAIT)
				else:
					effective_strat = int(Strategy.ATTACK)
				var pol := _get_explore_move_policy()
				if pol == "stairs_down" or pol == "stairs_up":
					# フロア移動判断: リーダーのみ階段を目指す、非リーダーはリーダーを追従
					if member == leader_char:
						move_policy = pol
					else:
						move_policy = order.get("move", "follow") as String
				elif member == leader_char:
					# リーダーのみ探索行動（自律的に未訪問エリアへ向かう）
					move_policy = "explore"
				else:
					# 非リーダーメンバーはリーダーを追従
					# current_order["move"] のデフォルトは "follow"
					move_policy = order.get("move", "follow") as String
		elif _party_strategy == Strategy.GUARD_ROOM:
			# 帰還中：全員を WAIT + guard_room ポリシーで動かす
			effective_strat = int(Strategy.WAIT)
			move_policy = "guard_room"
		else:
			# 回復・バフ専用キャラ（heal_mp_cost > 0 または buff_mp_cost > 0）は常に WAIT を渡す
			# UnitAI._generate_queue() の先頭で heal/buff キューが自動生成される
			# ※ power フィールドは攻撃・魔法共通のため heal/buff 専用チェックで判定
			var cd := member.character_data
			if cd != null and (cd.heal_mp_cost > 0 or cd.buff_mp_cost > 0):
				effective_strat = int(Strategy.WAIT)
			else:
				# 個別の戦闘指示から変換
				# combat: "attack" → ATTACK（旧 "aggressive" も互換）
				#         "defense" / "standby" / "support" → WAIT（旧値も互換）
				#         "flee" → FLEE
				match combat:
					"attack", "aggressive":
						effective_strat = int(Strategy.ATTACK)
					"flee":
						effective_strat = int(Strategy.FLEE)
					"defense", "support", "standby":
						effective_strat = int(Strategy.WAIT)
					_:
						# DEFEND 等のパーティー専用戦略は WAIT に変換
						if int(_party_strategy) > int(Strategy.WAIT):
							effective_strat = int(Strategy.WAIT)
						else:
							effective_strat = int(_party_strategy)

		# 2. 個別低HP条件（on_low_hp）：NEAR_DEATH_THRESHOLD 未満で発動
		if member.max_hp > 0 \
				and float(member.hp) / float(member.max_hp) < GlobalConstants.NEAR_DEATH_THRESHOLD:
			match on_low_hp:
				"flee":
					effective_strat = int(Strategy.FLEE)
				"retreat":
					# 戦略を WAIT に切替、隊形を cluster に上書き（リーダーそばに退避）
					if effective_strat != int(Strategy.FLEE):
						effective_strat = int(Strategy.WAIT)
					move_policy = "cluster"
				# "keep_fighting" は何も変えない

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
				# 援護優先：最もHPが低いパーティーメンバーの近くの敵を狙う
				target = _select_support_target(member)
			_:
				target = _select_target_for(member)

		# クロスフロアターゲット排除（別フロアのキャラを攻撃しない）
		if target != null and is_instance_valid(target) \
				and target.current_floor != member.current_floor:
			target = null

		unit_ai.receive_order({
			"strategy":         effective_strat,
			"target":           target,
			"combat":           combat,
			"move":             move_policy,
			"battle_formation": battle_form,
			"leader":           formation_ref,
			"hp_potion":        _global_orders.get("hp_potion",    "never") as String,
			"sp_mp_potion":     _global_orders.get("sp_mp_potion", "never") as String,
		})


## 状況変化通知（PartyManager から呼ばれる）：即座に再評価してオーダーを発行する
func notify_situation_changed() -> void:
	_reeval_timer = 0.0
	_assign_orders()
	# 各 UnitAI にもフォールバック再評価タイマーをリセット
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.notify_situation_changed()


## パーティーレベルのデバッグ情報を返す（RightPanel のパーティーヘッダー行に使用）
func get_party_debug_info() -> Dictionary:
	return {
		"party_strategy": int(_party_strategy),
		"alive_count":    _party_members.size(),
		"initial_count":  _initial_count,
	}


## デバッグ情報を収集して返す（RightPanel の AI デバッグ表示に使用）
## 返す形式は BaseAI.get_debug_info() と同一（互換性維持）
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
# AI戦略変更ログ
# --------------------------------------------------------------------------

## プレイヤーが直接操作中のメンバーがいるか判定する
func _has_player_controlled_member() -> bool:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_player_controlled:
			return true
	return false


## 戦略変更時にログ出力する。サブクラスが _get_strategy_change_reason() をオーバーライドして理由を提供可能
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


## リーダーキャラの名前を取得する
func _get_leader_name() -> String:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_leader:
			var cname: String = m.character_data.character_name if m.character_data != null else ""
			if not cname.is_empty():
				return cname
			return m.character_data.character_id if m.character_data != null else m.name
	# リーダーがいなければ最初の生存メンバー
	for m: Character in _party_members:
		if is_instance_valid(m):
			var cname: String = m.character_data.character_name if m.character_data != null else ""
			if not cname.is_empty():
				return cname
			return m.character_data.character_id if m.character_data != null else m.name
	return "不明"


## Strategy を日本語プリセット名に変換する
func _strategy_to_preset_name(strat: Strategy) -> String:
	match strat:
		Strategy.ATTACK:     return "攻撃"
		Strategy.FLEE:       return "撤退"
		Strategy.WAIT:       return "待機"
		Strategy.DEFEND:     return "防衛"
		Strategy.EXPLORE:    return "探索"
		Strategy.GUARD_ROOM: return "帰還"
	return "不明"


## 現在の戦略名を返す（DebugWindow から参照する用途）
func get_current_strategy_name() -> String:
	return _strategy_to_preset_name(_party_strategy)


## 全体指示のヒントを返す（DebugWindow 表示用）
## _global_orders が設定されていればそれを返す。なければ _party_strategy から合成する
func get_global_orders_hint() -> Dictionary:
	if not _global_orders.is_empty():
		return _global_orders
	# _global_orders 未設定（敵パーティー等）→ 戦略から合成
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


## 戦略変更の理由を返す（サブクラスがオーバーライド可能）
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

## _evaluate_party_strategy() の結果を縄張り・追跡ルールでラップする
## 敵パーティーのみ適用。友好パーティーはそのまま返す
func _apply_range_check(base_strat: Strategy) -> Strategy:
	# 友好パーティーには適用しない
	var first_member: Character = null
	for m: Character in _party_members:
		if is_instance_valid(m):
			first_member = m
			break
	if first_member == null or first_member.is_friendly:
		return base_strat

	# 現在 GUARD_ROOM（帰還中）の場合：再交戦 or 帰還完了を判定
	if _party_strategy == Strategy.GUARD_ROOM:
		if base_strat == Strategy.FLEE:
			return Strategy.FLEE
		if _any_member_can_engage():
			return Strategy.ATTACK
		if _all_members_at_home():
			return Strategy.WAIT
		return Strategy.GUARD_ROOM

	# 現在 ATTACK の場合：縄張り外に追い出されたら帰還へ
	if _party_strategy == Strategy.ATTACK and base_strat == Strategy.ATTACK:
		if _all_members_out_of_range():
			return Strategy.GUARD_ROOM

	return base_strat


## 全メンバーが縄張り外かつ目標から離れているか判定する
## true → ATTACK→GUARD_ROOM 遷移トリガー
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
		# まだ縄張り内にいる → このメンバーは「範囲内」→ false を返す
		if dist_home <= float(cd.territory_range):
			return false
		# 縄張り外：目標が近ければ追跡を継続する
		var target := _find_nearest_friendly(member)
		if target != null and is_instance_valid(target):
			var dist_target := (member.grid_pos - target.grid_pos).length()
			if dist_target <= float(cd.chase_range):
				return false
	return true


## 少なくとも1体が縄張り内かつ目標射程内にいるか判定する
## true → GUARD_ROOM→ATTACK 再交戦トリガー
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
			continue  # まだ縄張り外なので再交戦不可
		var target := _find_nearest_friendly(member)
		if target != null and is_instance_valid(target):
			var dist_target := (member.grid_pos - target.grid_pos).length()
			if dist_target <= float(cd.chase_range):
				return true
	return false


## 全メンバーがスポーン地点の近くに戻っているか判定する（マンハッタン距離2以内）
## true → GUARD_ROOM→WAIT 帰還完了トリガー
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
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

## メンバーに対応する UnitAI を生成する（サブクラスで種別に応じて切り替える）
func _create_unit_ai(_member: Character) -> UnitAI:
	return UnitAI.new()


## 探索時の移動方針を返す（NpcLeaderAI でオーバーライドしてフロアランク判断を追加）
func _get_explore_move_policy() -> String:
	return "explore"


## 現在の探索移動方針を外部に公開する（game_map が NPC の階段意図を判定するために使用）
func get_explore_move_policy() -> String:
	return _get_explore_move_policy()


## パーティー全体の戦略を評価する（サブクラスがオーバーライドする）
func _evaluate_party_strategy() -> Strategy:
	return Strategy.WAIT


## 指定メンバーの攻撃ターゲットを選択する（サブクラスがオーバーライドする）
func _select_target_for(_member: Character) -> Character:
	return _player


## 最もHPが少ない攻撃ターゲットを選択する
## サブクラスがオーバーライドして複数候補から選択できる。
## デフォルトは _select_target_for() と同一（ターゲットが1体のみの場合など）
func _select_weakest_target(member: Character) -> Character:
	return _select_target_for(member)


## 援護優先ターゲット選択：最もHPが低いパーティーメンバーに最も近い脅威（敵）を返す
## パーティーメンバーが1人なら通常のターゲット選択にフォールバック
func _select_support_target(member: Character) -> Character:
	# 最もHPが低いパーティーメンバーを探す（自分以外）
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
	# その味方への脅威（最も近い敵）を選ぶ
	if weakest_ally != null:
		return _select_target_for(weakest_ally)
	return _select_target_for(member)
