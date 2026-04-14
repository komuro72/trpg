class_name WolfLeaderAI
extends EnemyLeaderAI

## ウルフリーダーAI
## behavior_description: "群れで行動する獰猛な狼。高速移動して側面から奇襲する。"
##
## EnemyLeaderAI との差分:
##   FLEE: 生存メンバーが初期数の50%未満


## WolfUnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return WolfUnitAI.new()


## パーティー全体の戦略を評価する（FLEE 条件を追加）
func _evaluate_party_strategy() -> Strategy:
	var alive := 0
	for member: Character in _party_members:
		if is_instance_valid(member) and member.hp > 0:
			alive += 1
	var alive_ratio := float(alive) / float(maxi(_initial_count, 1))
	if alive_ratio < GlobalConstants.PARTY_FLEE_ALIVE_RATIO:
		return Strategy.FLEE
	return super._evaluate_party_strategy()


## 戦略変更の理由
func _get_strategy_change_reason() -> String:
	if _party_strategy == Strategy.FLEE:
		return "仲間50%以下"
	return super._get_strategy_change_reason()
