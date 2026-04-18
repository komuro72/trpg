class_name LichUnitAI
extends UnitAI

## リッチ個体AI
## behavior_description: "不死の大魔法使い。火と水の魔法弾を交互に放つ。魔法耐性が非常に高い。絶対に逃げない。"
##
## 従順度: 1.0
## 火/水魔法弾を交互に発射（_lich_water フラグで切り替え）
## MP管理: 攻撃時に MP_ATTACK_COST を消費。MP不足なら WAIT に切替
## 自己保存条件: なし（絶対に逃げない）

const MP_ATTACK_COST := 3  ## 1回の魔法攻撃で消費するMP

var _lich_water: bool = false  ## 次の攻撃が水弾かどうか


func _init() -> void:
	obedience = 1.0


## 自己保存フック: 絶対に逃げない
func _should_ignore_flee() -> bool:
	return true


## MP不足なら攻撃不可
func _can_attack() -> bool:
	if _member != null and is_instance_valid(_member):
		if _member.energy < MP_ATTACK_COST:
			return false
	return true


## 水弾切り替えフラグを返す（UnitAI の飛翔体生成で参照）
func _get_is_water_shot() -> bool:
	return _lich_water


## 攻撃後フック: 火/水を交互に切り替え・MP を消費する
func _on_after_attack() -> void:
	_lich_water = not _lich_water
	if _member != null and is_instance_valid(_member):
		_member.use_energy(MP_ATTACK_COST)


## 経路探索方法: A* 最短経路（後方維持）
func _get_path_method() -> PathMethod:
	return PathMethod.ASTAR
