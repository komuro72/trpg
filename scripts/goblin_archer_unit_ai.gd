class_name GoblinArcherUnitAI
extends UnitAI

## ゴブリンアーチャー個体AI
## behavior_description: "弓で遠距離攻撃。敵が近づきすぎると後退して射程を確保する。"
##
## 従順度: 0.5
## 近距離対処: ターゲットがMIN_CLOSE_RANGE以内なら flee で後退する
## 経路探索: A* 最短経路
## 自己保存条件: HP < 30% なら逃走

const MIN_CLOSE_RANGE := 2  ## この距離以下になったら後退する


func _init() -> void:
	obedience = 0.5


## 自己保存フック: HP < 30% なら逃走
func _should_self_flee() -> bool:
	if _member != null and is_instance_valid(_member):
		var hp_ratio := float(_member.hp) / float(maxi(_member.max_hp, 1))
		if hp_ratio < 0.3:
			return true
	return false


## キュー生成: 攻撃戦略のとき、ターゲットが近すぎれば後退キューを優先する
func _generate_queue(strategy: int, target: Character) -> Array:
	if strategy == 0 and target != null and is_instance_valid(target):
		var dist := _manhattan(_member.grid_pos, target.grid_pos)
		if dist <= MIN_CLOSE_RANGE:
			var q: Array = []
			for _i: int in range(3):
				q.append({"action": "flee"})
			return q
	return super._generate_queue(strategy, target)


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
