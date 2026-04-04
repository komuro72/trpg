class_name HobgoblinLeaderAI
extends PartyLeaderAI

## ホブゴブリンリーダーAI
## behavior_description: "配下のゴブリンを指揮する大型の亜人。好戦的で絶対に逃げない。"
##
## 戦略判断:
##   ATTACK: プレイヤーが生存（常に攻撃。絶対に逃げない）
##   WAIT  : プレイヤー不在
##
## 混成パーティー: ホブゴブリン1体+ゴブリン複数を想定
##   hobgoblin → HobgoblinUnitAI
##   goblin    → GoblinUnitAI


## メンバーの character_id に応じた UnitAI を生成する
func _create_unit_ai(member: Character) -> UnitAI:
	var cid := member.character_data.character_id if member.character_data != null else ""
	if cid == "goblin":
		return GoblinUnitAI.new()
	return HobgoblinUnitAI.new()


## パーティー全体の戦略を評価する（絶対に FLEE しない）
func _evaluate_party_strategy() -> Strategy:
	if _has_alive_friendly():
		return Strategy.ATTACK
	return Strategy.WAIT


## 攻撃ターゲット: 最近傍の友好キャラ
func _select_target_for(member: Character) -> Character:
	return _find_nearest_friendly(member)
