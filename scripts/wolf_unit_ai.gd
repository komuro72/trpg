class_name WolfUnitAI
extends UnitAI

## ウルフ個体AI
## behavior_description: "高速移動して側面から奇襲する群れの狼。"
##
## 従順度: 0.8
## 経路探索: ASTAR_FLANK（ターゲットの背後・側面に回り込む）
## 速度: MOVE_INTERVAL × 0.67（標準の1.5倍速）
## 自己保存条件: なし（逃走はパーティーレベルで判断）


func _init() -> void:
	obedience = 0.8


## 経路探索方法: 側面回り込み
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR_FLANK


## 移動間隔: 標準の2/3（高速）
func _get_move_interval() -> float:
	return MOVE_INTERVAL * 0.67
