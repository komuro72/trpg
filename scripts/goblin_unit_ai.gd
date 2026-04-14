class_name GoblinUnitAI
extends UnitAI

## ゴブリン個体AI
## behavior_description: "集団で行動する。臆病な性格で強いと思った相手からはすぐ逃げる。"
##
## 従順度: 0.5（自身のHP危機時のみリーダー指示を逃走に上書き）
## 経路探索: A* 最短経路
## 自己保存条件: HP が初期値の30%未満なら逃走


func _init() -> void:
	obedience = 0.5


## 自己保存フック: HP < 30% なら逃走を優先
func _should_self_flee() -> bool:
	if _member != null and is_instance_valid(_member):
		var hp_ratio := float(_member.hp) / float(maxi(_member.max_hp, 1))
		if hp_ratio < GlobalConstants.SELF_FLEE_HP_THRESHOLD:
			return true
	return false


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
