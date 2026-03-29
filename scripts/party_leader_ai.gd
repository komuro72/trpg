class_name PartyLeaderAI
extends Node

## リーダーAI基底クラス（2層AIアーキテクチャのパーティーレイヤー）
## パーティー全体の戦略を決定し、各メンバーの UnitAI にオーダーを渡す
## サブクラスは以下をオーバーライドする:
##   _create_unit_ai()         : メンバーに対応する UnitAI の種別を返す
##   _evaluate_party_strategy(): パーティー全体の戦略判断
##   _select_target_for()      : メンバーごとの攻撃ターゲット選択

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


func _process(delta: float) -> void:
	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = REEVAL_INTERVAL
		_assign_orders()


## 戦略を評価して各メンバーにオーダーを発行する
func _assign_orders() -> void:
	_party_strategy = _evaluate_party_strategy()
	# PartyLeaderAI.Strategy の int 値は UnitAI.Strategy と先頭3つ（ATTACK/FLEE/WAIT）が一致するため
	# int のまま order に格納して UnitAI.receive_order() に渡す（キャスト先で同一 int 値として解釈）
	var strat_int := int(_party_strategy)
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var target := _select_target_for(member)
		unit_ai.receive_order({
			"strategy": strat_int,
			"target":   target,
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
