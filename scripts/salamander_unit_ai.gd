class_name SalamanderUnitAI
extends UnitAI

## サラマンダー個体AI
## behavior_description: "炎を吐く大型トカゲ。接近されると後退して射程を確保する。絶対に逃げない。"
##
## 従順度: 0.8
## 近距離対処: ターゲットがMIN_CLOSE_RANGE以内なら flee で後退する
## 経路探索: A* 最短経路
## 自己保存条件: なし（絶対に逃げない）

const MIN_CLOSE_RANGE := 2  ## この距離以下になったら後退する


func _init() -> void:
	obedience = 0.8


## 自己保存フック: 絶対に逃げない
func _should_ignore_flee() -> bool:
	return true


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
