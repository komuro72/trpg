class_name DarkKnightUnitAI
extends UnitAI

## ダークナイト個体AI
## behavior_description: "高い防御力を持ち絶対に逃げない。正面から堂々と突進して強力な一撃を放つ。"
##
## 従順度: 1.0
## 経路探索: A* 最短経路（正面突進）
## 自己保存条件: なし（絶対に逃げない）


func _init() -> void:
	obedience = 1.0


## 自己保存フック: 絶対に逃げない
func _should_ignore_flee() -> bool:
	return true


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
