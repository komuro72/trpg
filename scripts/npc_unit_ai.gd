class_name NpcUnitAI
extends UnitAI

## NPC 個体AI
## 従順度 1.0（完全にリーダー指示に従う）
## 経路探索: A*


func _init() -> void:
	obedience = 1.0


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
