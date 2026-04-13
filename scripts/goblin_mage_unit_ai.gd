class_name GoblinMageUnitAI
extends UnitAI

## ゴブリンメイジ個体AI
## behavior_description: "遠距離から魔法弾を放つ。MPが尽きると攻撃できなくなる。臆病でHPが減ると逃げる。"
##
## 従順度: 0.5
## MP管理: 攻撃時にMP_ATTACK_COST を消費。MP不足なら WAIT に切替
## 自己保存条件: HP < 30% なら逃走

const MP_ATTACK_COST := 2  ## 1回の魔法攻撃で消費するMP


func _init() -> void:
	obedience = 0.5


## 自己保存フック: HP < 30% なら逃走
func _should_self_flee() -> bool:
	if _member != null and is_instance_valid(_member):
		var hp_ratio := float(_member.hp) / float(maxi(_member.max_hp, 1))
		if hp_ratio < 0.3:
			return true
	return false


## MP不足なら攻撃不可
func _can_attack() -> bool:
	if _member != null and is_instance_valid(_member):
		if _member.mp < MP_ATTACK_COST:
			return false
	return true


## 攻撃後フック: MP を消費する
func _on_after_attack() -> void:
	if _member != null and is_instance_valid(_member):
		_member.use_mp(MP_ATTACK_COST)


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
