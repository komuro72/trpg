class_name GoblinLeaderAI
extends PartyLeaderAI

## ゴブリンリーダーAI
## behavior_description: "集団で行動する。仲間が半数以下になるか、リーダーが追い詰められると逃走する。"
##
## 戦略判断:
##   FLEE  : 生存メンバーが初期数の50%未満
##   ATTACK: プレイヤーが生存
##   WAIT  : それ以外（プレイヤー不在）
##
## ターゲット: プレイヤー（将来は最近傍のプレイヤーパーティーメンバーを選択）


## ゴブリン用 UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return GoblinUnitAI.new()


## パーティー全体の戦略を評価する
func _evaluate_party_strategy() -> Strategy:
	# 逃走条件: 生存メンバーが初期数の50%未満
	var alive := 0
	for member: Character in _party_members:
		if is_instance_valid(member) and member.hp > 0:
			alive += 1
	var alive_ratio := float(alive) / float(maxi(_initial_count, 1))
	if alive_ratio < 0.5:
		return Strategy.FLEE

	# プレイヤーが生存していれば攻撃
	if _player != null and is_instance_valid(_player) and _player.hp > 0:
		return Strategy.ATTACK

	return Strategy.WAIT


## 攻撃ターゲット: プレイヤー
func _select_target_for(_member: Character) -> Character:
	return _player
