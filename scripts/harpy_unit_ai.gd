class_name HarpyUnitAI
extends UnitAI

## ハーピー個体AI
## behavior_description: "飛行して障害物を無視して移動する。地上の敵に降下攻撃を仕掛ける。"
##
## 従順度: 0.8
## 攻撃タイプ: dive（飛行中の降下攻撃。UnitAI._execute_attack() で処理済み）
## 自己保存条件: なし（絶対に逃げない）


func _init() -> void:
	obedience = 0.8


## 自己保存フック: 絶対に逃げない
func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	if ordered_strategy == Strategy.FLEE:
		return Strategy.ATTACK
	return ordered_strategy


## 経路探索方法: A* 最短経路（飛行なので地上の占有チェックをスキップ）
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
