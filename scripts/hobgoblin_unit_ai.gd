class_name HobgoblinUnitAI
extends UnitAI

## ホブゴブリン個体AI
## behavior_description: "好戦的で絶対に逃げない。正面から突進して強力な一撃を叩き込む。"
##
## 従順度: 0.8
## 経路探索: A* 最短経路
## 自己保存条件: なし（HP がいくら減っても逃げない）


func _init() -> void:
	obedience = 0.8


## 自己保存フック: 絶対に逃げない
func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	if ordered_strategy == Strategy.FLEE:
		return Strategy.ATTACK
	return ordered_strategy


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
