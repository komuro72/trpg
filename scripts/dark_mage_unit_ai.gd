class_name DarkMageUnitAI
extends UnitAI

## ダークメイジ個体AI
## behavior_description: "後方で遠距離魔法を放つ。MPが尽きると待機する。絶対に逃げない。"
##
## 従順度: 1.0
## MP管理: 攻撃時にMP_ATTACK_COST を消費。MP不足なら WAIT に切替
## 自己保存条件: なし（絶対に逃げない）

const MP_ATTACK_COST := 2  ## 1回の魔法攻撃で消費するMP


func _init() -> void:
	obedience = 1.0


## 自己保存フック: 絶対に逃げない / MP不足なら WAIT
func _resolve_strategy(ordered_strategy: Strategy) -> Strategy:
	if ordered_strategy == Strategy.FLEE:
		return Strategy.ATTACK
	if _member != null and is_instance_valid(_member):
		if _member.mp < MP_ATTACK_COST:
			return Strategy.WAIT
	return ordered_strategy


## 攻撃後フック: MP を消費する
func _on_after_attack() -> void:
	if _member != null and is_instance_valid(_member):
		_member.use_mp(MP_ATTACK_COST)


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
