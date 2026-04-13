class_name HobgoblinLeaderAI
extends EnemyLeaderAI

## ホブゴブリンリーダーAI
## behavior_description: "配下のゴブリンを指揮する大型の亜人。好戦的で絶対に逃げない。"
##
## EnemyLeaderAI との差分:
##   現時点ではなし（FLEEしない＝「狂暴で攻撃的」の特徴はデフォルト動作そのもの）
##   将来の差別化のためクラスは残す
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
