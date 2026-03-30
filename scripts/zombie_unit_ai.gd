class_name ZombieUnitAI
extends UnitAI

## ゾンビ個体AI
## behavior_description: "死者が蘇った不死の怪物。低速だが止まらない。近くの人間に向かって直進する。"
##
## 従順度: 1.0（意思なし・命令に完全従順）
## 経路探索: 直進（DIRECT）。障害物を無視して直進するため、迂回しない
## 速度: MOVE_INTERVAL × 2.0（標準の半速）
## 自己保存条件: なし（絶対に逃げない）


func _init() -> void:
	obedience = 1.0


## 自己保存フック: 絶対に逃げない
func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	if ordered_strategy == Strategy.FLEE:
		return Strategy.ATTACK
	return ordered_strategy


## 経路探索方法: 直進（障害物を迂回しない本能的な移動）
func _get_path_method() -> PathMethod:
	return PathMethod.DIRECT


## 移動間隔: 標準の2倍（低速）
func _get_move_interval() -> float:
	return MOVE_INTERVAL * 2.0
