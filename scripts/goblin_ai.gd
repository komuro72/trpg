class_name GoblinAI
extends BaseAI

## [レガシー] 旧ゴブリンAI
## Phase 6-0 のリファクタリングにより GoblinUnitAI + GoblinLeaderAI に移行しました。
## このクラスは後方互換のために残していますが、新しいコードでは使用しないでください。
##
## behavior_description: "集団で行動する。臆病な性格で強いと思った相手からはすぐ逃げる。"
##
## 戦略決定ロジック:
##   - 逃走: HP が初期値の30%未満 OR 生存仲間が初期数の50%未満
##   - 攻撃: それ以外でプレイヤーが生存している
##   - 待機: プレイヤーが存在しない
##
## ターゲット選択: 現在はプレイヤーのみ（Phase 6以降で最近傍の敵を選択予定）
## 経路探索: A*（最短経路。回り込みは行わない）


## ゴブリンの戦略決定
func _evaluate_strategy(enemy: Character) -> Strategy:
	# 逃走条件①：自分のHPが30%未満
	var hp_ratio := float(enemy.hp) / float(maxi(enemy.max_hp, 1))
	if hp_ratio < 0.3:
		return Strategy.FLEE

	# 逃走条件②：生存仲間が初期数の50%未満
	var alive_ratio := float(_enemies.size()) / float(maxi(_initial_count, 1))
	if alive_ratio < 0.5:
		return Strategy.FLEE

	# プレイヤーが生存していれば攻撃
	if _player != null and is_instance_valid(_player) and _player.hp > 0:
		return Strategy.ATTACK

	return Strategy.WAIT


## ターゲット選択（現在はプレイヤーのみ）
func _select_target(_enemy: Character) -> Character:
	return _player


## 経路探索方法（A* 最短経路）
func _select_path_method(_enemy: Character) -> PathMethod:
	return PathMethod.ASTAR
