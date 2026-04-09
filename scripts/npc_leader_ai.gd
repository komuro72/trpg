class_name NpcLeaderAI
extends PartyLeaderAI

## NPC リーダーAI
## 敵（ゴブリン等の enemy_party）を優先的にターゲットにして攻撃する。
## 生存敵がいれば ATTACK、いなければ EXPLORE（探索行動）。

# --------------------------------------------------------------------------
# 合流承諾判定スコア定数（調整しやすいよう定数化）
# --------------------------------------------------------------------------
## ランク文字列 → スコア数値の変換テーブル（C=3, B=4, A=5, S=6）
const RANK_VALUES: Dictionary = { "C": 3, "B": 4, "A": 5, "S": 6 }
## ランク和への乗数
const RANK_SCORE_PER_RANK: float = 10.0
## 共闘フラグによるボーナス
const FOUGHT_TOGETHER_BONUS: float = 5.0
## 回復フラグによるボーナス
const HEALED_BONUS: float = 5.0

var _enemy_list: Array[Character] = []
var _was_refused: bool = false  ## 一度断られたら二度と自発申し出をしない

## 同じ敵パーティーと共に戦ったことがあるか
var has_fought_together: bool = false
## プレイヤー側ヒーラーに回復されたことがあるか
var has_been_healed: bool = false


## 攻撃対象とする敵リストを設定する（NpcManager が初期化後に呼ぶ）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies


## NPC 用 UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return NpcUnitAI.new()


## パーティー全体の戦略を評価する
## 同じフロアに生存 かつ 可視（訪問済みエリア）の敵がいれば ATTACK、いなければ EXPLORE
func _evaluate_party_strategy() -> Strategy:
	# 自パーティーのフロアを取得
	var my_floor := -1
	for m: Character in _party_members:
		if is_instance_valid(m):
			my_floor = m.current_floor
			break
	for enemy: Character in _enemy_list:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		# 同フロアの敵のみ ATTACK トリガーにする（他フロアの敵は無視）
		if my_floor >= 0 and enemy.current_floor != my_floor:
			continue
		# 未探索エリアの敵は無視（プレイヤーが発見していない敵には反応しない）
		if not enemy.visible:
			continue
		return Strategy.ATTACK
	return Strategy.EXPLORE


## 探索時の移動方針（フロアランクに基づいて階段移動を決定）
## party_score = average(power + physical_resistance + magic_resistance + defense_accuracy)
## FLOOR_RANK との比較で上下フロア移動を決定する
func _get_explore_move_policy() -> String:
	if _party_members.is_empty():
		return "explore"
	# パーティースコアを計算
	var total_score := 0.0
	var count := 0
	for m: Character in _party_members:
		if is_instance_valid(m) and m.character_data != null:
			var cd := m.character_data
			total_score += float(cd.power + cd.physical_resistance \
				+ cd.magic_resistance + cd.defense_accuracy)
			count += 1
	if count == 0:
		return "explore"
	var party_score := total_score / float(count)
	# 現在フロアインデックスを取得（いずれかのメンバーから）
	var current_floor := 0
	for m: Character in _party_members:
		if is_instance_valid(m):
			current_floor = m.current_floor
			break
	var floor_count: int = GlobalConstants.FLOOR_RANK.size()
	# 次フロアが存在する場合、スコアが十分なら下へ
	if current_floor + 1 < floor_count:
		var next_rank := GlobalConstants.FLOOR_RANK.get(current_floor + 1, 100) as int
		if party_score >= float(next_rank):
			return "stairs_down"
	# 前フロアが存在する場合、スコアが現フロア基準の半分未満なら退却
	if current_floor > 0:
		var this_rank := GlobalConstants.FLOOR_RANK.get(current_floor, 0) as int
		if party_score < float(this_rank) * 0.5:
			return "stairs_up"
	return "explore"


## 戦略変更の理由
func _get_strategy_change_reason() -> String:
	if _party_strategy == Strategy.ATTACK:
		return "敵を検知"
	if _party_strategy == Strategy.EXPLORE:
		return "敵なし・周辺探索"
	if _party_strategy == Strategy.WAIT:
		return "敵なし"
	return super._get_strategy_change_reason()


## 各メンバーの攻撃ターゲットを選択する（最も近い生存・可視敵）
## visible=false の敵（未探索エリア）はターゲットにしない
func _select_target_for(member: Character) -> Character:
	var closest: Character = null
	var min_dist := INF
	for enemy: Character in _enemy_list:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		# 未探索エリアの敵は対象外（壁越し・未発見エリアへの攻撃を防ぐ）
		if not enemy.visible:
			continue
		var dist := float((enemy.grid_pos - member.grid_pos).length())
		if dist < min_dist:
			min_dist = dist
			closest = enemy
	return closest


# --------------------------------------------------------------------------
# 会話・合流ロジック
# --------------------------------------------------------------------------

## 一度断られた場合に自発申し出を永続的に停止する
func mark_refused() -> void:
	_was_refused = true


## NPC が自発的に会話を開始したいか判断する
## 現在は無効（プレイヤー起点の会話のみ対応）
func wants_to_initiate() -> bool:
	return false


## 現在 ATTACK 戦略中か（共闘フラグ更新に使用）
func is_in_combat() -> bool:
	return _party_strategy == Strategy.ATTACK


## 共闘フラグを設定する（game_map が同エリア戦闘を検出したときに呼ぶ）
func notify_fought_together() -> void:
	has_fought_together = true


## 回復フラグを設定する（player_controller がNPCメンバーを回復したときに呼ぶ）
func notify_healed() -> void:
	has_been_healed = true


## 指定の申し出を承諾するか判断する
## offer_type: "join_us"   = NPC がプレイヤー傘下に入る申し出（プレイヤーがリーダー）
##             "join_them" = プレイヤーが NPC 傘下に入る申し出（NPC がリーダー）
##
## 【判定式】join_us のみスコア比較。join_them は常に承諾。
##   プレイヤー側スコア = リーダーの統率力
##                     + パーティーランク和 × RANK_SCORE_PER_RANK
##                     + has_fought_together × FOUGHT_TOGETHER_BONUS
##                     + has_been_healed × HEALED_BONUS
##   NPC側スコア = (100 - 従順度平均×100) + パーティーランク和 × RANK_SCORE_PER_RANK
##   プレイヤー側スコア ≥ NPC側スコア なら承諾
func will_accept(offer_type: String, player_party: Party) -> bool:
	if offer_type != "join_us":
		# プレイヤーが NPC 傘下に入る場合：戦力強化になるので常に承諾
		return true

	# ---- プレイヤー側スコア ----
	var leader_leadership := 0
	var player_rank_sum := 0
	for mv: Variant in player_party.members:
		var ch := mv as Character
		if not is_instance_valid(ch):
			continue
		if ch.is_leader and ch.character_data != null:
			leader_leadership = ch.character_data.leadership
		if ch.character_data != null:
			player_rank_sum += RANK_VALUES.get(ch.character_data.rank, 3) as int

	var player_score := float(leader_leadership) \
		+ float(player_rank_sum) * RANK_SCORE_PER_RANK
	if has_fought_together:
		player_score += FOUGHT_TOGETHER_BONUS
	if has_been_healed:
		player_score += HEALED_BONUS

	# ---- NPC 側スコア ----
	var npc_obedience_sum := 0.0
	var npc_rank_sum := 0
	var npc_count := 0
	for m: Character in _party_members:
		if not is_instance_valid(m):
			continue
		if m.character_data != null:
			npc_obedience_sum += m.character_data.obedience
			npc_rank_sum += RANK_VALUES.get(m.character_data.rank, 3) as int
		npc_count += 1

	var obedience_avg := npc_obedience_sum / float(npc_count) if npc_count > 0 else 0.5
	var npc_score := (100.0 - obedience_avg * 100.0) \
		+ float(npc_rank_sum) * RANK_SCORE_PER_RANK

	var result := player_score >= npc_score
	# デバッグ：スコア内訳を MessageLog に出力（F1 ON 時のみ表示）
	var fought_str := "+%.0f(共闘)" % FOUGHT_TOGETHER_BONUS if has_fought_together else ""
	var healed_str := "+%.0f(回復)" % HEALED_BONUS        if has_been_healed       else ""
	MessageLog.add_ai(
		"[合流判定] P: 統率%d + ランク和%d×10%s%s = %.0f　NPC: (100-従順%.2f×100) + ランク和%d×10 = %.0f　→ %s" % [
			leader_leadership, player_rank_sum, fought_str, healed_str, player_score,
			obedience_avg, npc_rank_sum, npc_score,
			"承諾" if result else "拒否"
		])
	return result
