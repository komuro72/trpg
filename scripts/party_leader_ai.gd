class_name PartyLeaderAI
extends PartyLeader

## AI自動判断リーダー基底クラス
## PartyLeader を継承し、AI がパーティー全体の戦略を自動で判断する。
## EnemyLeaderAI / NpcLeaderAI 等が更にこれを継承する。
##
## PartyLeader との差分:
##   - _evaluate_party_strategy() のデフォルト実装（WAIT を返す）
##   - _select_target_for() のデフォルト実装（_player を返す）
##   - 再評価タイマーによる定期的な戦略再評価は PartyLeader._process() で共通実装済み


## パーティー全体の戦略を評価する（サブクラスがオーバーライドする）
func _evaluate_party_strategy() -> Strategy:
	return Strategy.WAIT


## 指定メンバーの攻撃ターゲットを選択する（サブクラスがオーバーライドする）
func _select_target_for(_member: Character) -> Character:
	return _player
