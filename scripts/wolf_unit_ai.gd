class_name WolfUnitAI
extends UnitAI

## ウルフ個体AI
## behavior_description: "高速移動して側面から奇襲する群れの狼。"
##
## 従順度: 0.8
## 経路探索: ASTAR_FLANK（ターゲットの背後・側面に回り込む）
## 速度: enemy_class_stats.json の wolf.move_speed で制御（Step 1-B〜）
##       旧 `_get_move_interval() return MOVE_INTERVAL * 0.67` は廃止
## 自己保存条件: なし（逃走はパーティーレベルで判断）


func _init() -> void:
	obedience = 0.8


## 経路探索方法: 側面回り込み
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR_FLANK
