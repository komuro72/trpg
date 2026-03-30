class_name WolfLeaderAI
extends PartyLeaderAI

## ウルフリーダーAI
## behavior_description: "群れで行動する獰猛な狼。高速移動して側面から奇襲する。"
##
## 戦略判断:
##   FLEE  : 生存メンバーが初期数の50%未満
##   ATTACK: プレイヤーが生存
##   WAIT  : プレイヤー不在


## WolfUnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return WolfUnitAI.new()


## パーティー全体の戦略を評価する
func _evaluate_party_strategy() -> Strategy:
	var alive := 0
	for member: Character in _party_members:
		if is_instance_valid(member) and member.hp > 0:
			alive += 1
	var alive_ratio := float(alive) / float(maxi(_initial_count, 1))
	if alive_ratio < 0.5:
		return Strategy.FLEE

	if _player != null and is_instance_valid(_player) and _player.hp > 0:
		return Strategy.ATTACK

	return Strategy.WAIT


## 攻撃ターゲット: プレイヤー
func _select_target_for(_member: Character) -> Character:
	return _player
