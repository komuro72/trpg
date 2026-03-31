class_name PartyLeaderAI
extends Node

## リーダーAI基底クラス（2層AIアーキテクチャのパーティーレイヤー）
## パーティー全体の戦略を決定し、各メンバーの UnitAI にオーダーを渡す
## サブクラスは以下をオーバーライドする:
##   _create_unit_ai()         : メンバーに対応する UnitAI の種別を返す
##   _evaluate_party_strategy(): パーティー全体の戦略判断
##   _select_target_for()      : メンバーごとの攻撃ターゲット選択
##   _select_weakest_target()  : 最弱ターゲット選択（複数候補がある場合）

## パーティー戦略（UnitAI.Strategy と int 値を合わせる：ATTACK=0, FLEE=1, WAIT=2）
enum Strategy { ATTACK, FLEE, WAIT, DEFEND }

const REEVAL_INTERVAL := 1.5  ## 定期再評価の間隔（秒）

var _party_members: Array[Character] = []
var _player:        Character
var _map_data:      MapData
var _unit_ais:      Dictionary = {}  ## member.name -> UnitAI
var _party_strategy: Strategy = Strategy.WAIT
var _reeval_timer:   float = 0.0
var _initial_count:  int   = 0  ## 初期メンバー数（逃走判定の基準）


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
		_unit_ais[member.name] = unit_ai

	# 初回オーダー発行
	_assign_orders()


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


func _process(delta: float) -> void:
	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = REEVAL_INTERVAL
		_assign_orders()


## 戦略を評価して各メンバーにオーダーを発行する
## current_order の各項目をパーティー戦略とマージして UnitAI に渡す
func _assign_orders() -> void:
	_party_strategy = _evaluate_party_strategy()

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
		var combat         : String = order.get("combat",          "aggressive")
		var on_low_hp      : String = order.get("on_low_hp",       "retreat")
		var tgt_policy     : String = order.get("target",          "nearest")
		var battle_form    : String = order.get("battle_formation", "surround")

		# ── 移動方針設定 ──────────────────────────────────────────────────
		# 敵は move 制約なし（spread）。味方は current_order.move を使用
		var move_policy  : String    = "spread"
		var formation_ref: Character = null
		if member.is_friendly:
			move_policy = order.get("move", "same_room") as String
			# 1人パーティーまたは自分がリーダーの場合は _player（英雄）を基準にする
			if leader_char == null or leader_char == member:
				if _player != null and is_instance_valid(_player):
					formation_ref = _player
			else:
				formation_ref = leader_char

		# ── 有効戦略を決定 ───────────────────────────────────────────────
		# 1. パーティー逃走は最優先（GoblinLeaderAI などの集団判断）
		var effective_strat: int
		if _party_strategy == Strategy.FLEE:
			effective_strat = int(Strategy.FLEE)
		else:
			# 回復・バフ専用キャラ（magic_power > 0）は常に WAIT を渡す
			# UnitAI._generate_queue() の先頭で heal/buff キューが自動生成される
			var cd := member.character_data
			if cd != null and (cd.magic_power > 0 or cd.buff_mp_cost > 0):
				effective_strat = int(Strategy.WAIT)
			else:
				# 個別の戦闘指示から変換
				match combat:
					"aggressive": effective_strat = int(Strategy.ATTACK)
					"support":    effective_strat = int(Strategy.WAIT)
					"standby":    effective_strat = int(Strategy.WAIT)
					_:            effective_strat = int(_party_strategy)

		# 2. 個別低HP条件（on_low_hp）：HP50%未満で処理
		if member.max_hp > 0 and float(member.hp) / float(member.max_hp) < 0.5:
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
			_:
				target = _select_target_for(member)

		unit_ai.receive_order({
			"strategy":         effective_strat,
			"target":           target,
			"combat":           combat,
			"move":             move_policy,
			"battle_formation": battle_form,
			"leader":           formation_ref,
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
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

## メンバーに対応する UnitAI を生成する（サブクラスで種別に応じて切り替える）
func _create_unit_ai(_member: Character) -> UnitAI:
	return UnitAI.new()


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
