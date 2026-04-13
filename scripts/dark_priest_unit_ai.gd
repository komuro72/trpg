class_name DarkPriestUnitAI
extends UnitAI

## ダークプリースト個体AI
## behavior_description: "後方で仲間のHPを回復し、防御力バフを付与する。HP50%以下の仲間を優先して回復する。MP切れの場合は回復・バフ不可。"
##
## 従順度: 1.0
## 行動: 回復・バフは UnitAI._generate_heal_queue() / _generate_buff_queue() で自動処理済み
## 攻撃: MP不足・回復不要のときのみ遠距離攻撃（ranged）
## 自己保存条件: なし（絶対に逃げない）


func _init() -> void:
	obedience = 1.0


## 自己保存フック: 絶対に逃げない
func _should_ignore_flee() -> bool:
	return true


## 経路探索方法: A* 最短経路
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
