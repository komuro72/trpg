class_name PartyLeaderPlayer
extends PartyLeader

## プレイヤー操作パーティー用リーダー
## PartyLeader を継承し、OrderWindow の指示（global_orders）を戦略・ターゲット選択に変換する。
## プレイヤーの指示を覆さない（戦況判断はメンバーAIの条件評価のみに使う）。
##
## PartyLeaderAI との違い:
##   - 戦略は global_orders.battle_policy から決定（AIの自動判断ではない）
##   - ターゲットは global_orders.target 設定 + _friendly_list から選択
##   - _select_target_for() はプレイヤー視点の敵リスト（_enemy_list）から選択


var _enemy_list: Array[Character] = []  ## 攻撃対象の敵リスト（game_map から設定）
var _party_ref: Party = null            ## プレイヤーパーティー参照（合流済みNPCを含む）


## 攻撃対象とする敵リストを設定する（game_map から呼ばれる）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies


## プレイヤーパーティー参照を設定する（game_map から呼ばれる）
## 合流済み NPC を含む全メンバーの戦力評価に使用する
func set_party_ref(party: Party) -> void:
	_party_ref = party


## 対立するキャラクターのリスト（敵リスト）を返す
func _get_opposing_characters() -> Array[Character]:
	return _enemy_list


## 自軍として扱うメンバー一覧を返す（合流済み NPC を含む）
func _get_my_combat_members() -> Array[Character]:
	if _party_ref == null:
		return _party_members
	var result: Array[Character] = []
	for mv: Variant in _party_ref.sorted_members():
		var m := mv as Character
		if m != null and is_instance_valid(m):
			result.append(m)
	return result


## パーティー全体の戦略を評価する
## global_orders.battle_policy を戦略に変換する
func _evaluate_party_strategy() -> Strategy:
	var policy: String = _global_orders.get("battle_policy", "attack") as String
	match policy:
		"attack":
			return Strategy.ATTACK
		"defense":
			return Strategy.WAIT
		"retreat":
			return Strategy.FLEE
	return Strategy.ATTACK


## 指定メンバーの攻撃ターゲットを選択する
## 最も近い生存敵を返す（プレイヤーパーティーは敵を攻撃する側）
func _select_target_for(member: Character) -> Character:
	var closest: Character = null
	var min_dist := INF
	for enemy: Character in _enemy_list:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		if enemy.current_floor != member.current_floor:
			continue
		if not enemy.visible:
			continue
		var dist := float((enemy.grid_pos - member.grid_pos).length())
		if dist < min_dist:
			min_dist = dist
			closest = enemy
	return closest


## 最もHPが少ない敵を返す（target="weakest" 用）
func _select_weakest_target(member: Character) -> Character:
	var weakest: Character = null
	var lowest_hp := INF
	for enemy: Character in _enemy_list:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		if enemy.current_floor != member.current_floor:
			continue
		if not enemy.visible:
			continue
		if float(enemy.hp) < lowest_hp:
			lowest_hp = float(enemy.hp)
			weakest = enemy
	if weakest != null:
		return weakest
	return _select_target_for(member)
