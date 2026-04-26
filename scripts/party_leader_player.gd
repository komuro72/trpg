class_name PartyLeaderPlayer
extends PartyLeader

## プレイヤー操作パーティー用リーダー
## PartyLeader を継承し、OrderWindow の指示（global_orders）でメンバーに個別指示を配布する。
## プレイヤーの指示を覆さない（戦況判断はメンバーAIの条件評価のみに使う）。
##
## 2026-04-21 改訂：`_party_strategy` / `_evaluate_party_strategy()` は敵専用概念に変更。
## 味方では `global_orders.battle_policy` が個別指示のプリセット流し込み
## （OrderWindow._apply_battle_policy_preset → member.current_order）にのみ使われる。
## party_fleeing フラグ配布も敵専用（基底 party_leader.gd:_assign_orders で味方は常に false）。
##
## PartyLeaderAI との違い:
##   - _party_strategy を計算・保持しない（味方共通の方針）
##   - ターゲットは global_orders.target 設定 + _friendly_list から選択
##   - _select_target_for() はプレイヤー視点の敵リスト（_enemy_list）から選択


var _enemy_list: Array[Character] = []  ## 攻撃対象の敵リスト（game_map から設定）


## 攻撃対象とする敵リストを設定する（game_map から呼ばれる）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies


## 対立するキャラクターのリスト（敵リスト）を返す
func _get_opposing_characters() -> Array[Character]:
	return _enemy_list


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


## リーダー本人のターゲット方針：常に "nearest"（自己参照解消・2026-04-26 追加）
## 普段はプレイヤー操作中だが、操作キャラ切替で AI 操作になった際の自己参照を回避する。
func _decide_leader_target_policy_override() -> String:
	return "nearest"


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
