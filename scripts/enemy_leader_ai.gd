class_name EnemyLeaderAI
extends PartyLeaderAI

## 敵リーダーAI基底クラス
## 全敵種族の共通デフォルト行動を定義する。種族固有の行動はサブクラスでオーバーライドする。
##
## デフォルト戦略判断:
##   ATTACK: friendly（プレイヤー・NPC）が生存している
##   WAIT  : friendly がいない
##   FLEE  : なし（デフォルトでは逃げない。種族サブクラスが必要に応じて追加）
##
## 種族固有リーダーAI（GoblinLeaderAI 等）は本クラスを継承し、差分のみオーバーライドする。
## 種族固有の行動が不要な敵（dark-knight, salamander 等）は本クラスをそのまま使用する。


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
		"lich":          return LichUnitAI.new()
		"demon":         return DarkMageUnitAI.new()  ## デーモン: 魔法遠距離（雷）はDarkMageAIと同等
		"dark-lord":     return DarkLordUnitAI.new()
		"skeleton-archer": return GoblinArcherUnitAI.new()  ## スケルトンアーチャー: 後退維持
	return UnitAI.new()


## パーティー全体の戦略を評価する
## friendly が生存していれば ATTACK、いなければ WAIT。FLEE はしない。
## 種族サブクラスは super._evaluate_party_strategy() を呼んでから FLEE 条件を追加できる。
func _evaluate_party_strategy() -> Strategy:
	if _has_alive_friendly():
		return Strategy.ATTACK
	return Strategy.WAIT


## 攻撃ターゲット: 最近傍の friendly キャラ
func _select_target_for(member: Character) -> Character:
	return _find_nearest_friendly(member)
