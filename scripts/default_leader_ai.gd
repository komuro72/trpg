class_name DefaultLeaderAI
extends PartyLeaderAI

## デフォルトリーダーAI
## ゴブリン・ホブゴブリン・狼以外の敵種族に使用する汎用パーティーAI
##
## 戦略判断:
##   ATTACK: プレイヤーが生存
##   WAIT  : それ以外（プレイヤー不在）
##   FLEE  : しない（個体レベルでの逃走はサブクラスが判断）


## メンバーの character_id に応じた UnitAI を生成する
func _create_unit_ai(member: Character) -> UnitAI:
	var cid := member.character_data.character_id if member.character_data != null else ""
	match cid:
		"goblin-archer": return GoblinArcherUnitAI.new()
		"goblin-mage":   return GoblinMageUnitAI.new()
		"zombie":        return ZombieUnitAI.new()
		"harpy":         return HarpyUnitAI.new()
		"salamander":    return SalamanderUnitAI.new()
		"dark-knight":   return DarkKnightUnitAI.new()
		"dark-mage":     return DarkMageUnitAI.new()
		"dark_priest", "dark-priest": return DarkPriestUnitAI.new()
	return UnitAI.new()


## パーティー全体の戦略を評価する
func _evaluate_party_strategy() -> Strategy:
	if _player != null and is_instance_valid(_player) and _player.hp > 0:
		return Strategy.ATTACK
	return Strategy.WAIT


## 攻撃ターゲット: プレイヤー
func _select_target_for(_member: Character) -> Character:
	return _player
