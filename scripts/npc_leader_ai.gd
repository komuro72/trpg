class_name NpcLeaderAI
extends PartyLeaderAI

## NPC リーダーAI
## 敵（ゴブリン等の enemy_party）を優先的にターゲットにして攻撃する。
## 生存敵がいれば ATTACK、いなければ EXPLORE（探索行動）。

var _enemy_list: Array[Character] = []


## 攻撃対象とする敵リストを設定する（NpcManager が初期化後に呼ぶ）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies


## NPC 用 UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return NpcUnitAI.new()


## パーティー全体の戦略を評価する
## 同じフロアに生存している敵がいれば ATTACK、いなければ EXPLORE（探索行動）
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
		return Strategy.ATTACK
	return Strategy.EXPLORE


## 探索時の移動方針（フロアランクに基づいて階段移動を決定）
## party_score = average(attack_power + physical_resistance + magic_resistance + defense_accuracy)
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
			total_score += float(cd.attack_power + cd.physical_resistance \
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


## 各メンバーの攻撃ターゲットを選択する（最も近い生存敵）
func _select_target_for(member: Character) -> Character:
	var closest: Character = null
	var min_dist := INF
	for enemy: Character in _enemy_list:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var dist := float((enemy.grid_pos - member.grid_pos).length())
		if dist < min_dist:
			min_dist = dist
			closest = enemy
	return closest


# --------------------------------------------------------------------------
# 会話・合流ロジック
# --------------------------------------------------------------------------

## NPC が自発的に会話を開始したいか判断する
## 重傷者（HP50%未満）が過半数を超えた場合に申し出る
func wants_to_initiate() -> bool:
	if _party_members.is_empty():
		return false
	var wounded := 0
	for m: Character in _party_members:
		if is_instance_valid(m) and m.max_hp > 0:
			if float(m.hp) / float(m.max_hp) < 0.5:
				wounded += 1
	return wounded * 2 > _party_members.size()


## パーティーの総合力（最大HP合計）を返す（承諾/拒否判断に使用）
func get_party_strength() -> float:
	var total := 0.0
	for m: Character in _party_members:
		if is_instance_valid(m):
			total += float(m.max_hp)
	return total


## 指定の申し出を承諾するか判断する
## offer_type: "join_us"   = NPC がプレイヤー傘下に入る申し出（プレイヤーがリーダー）
##             "join_them" = プレイヤーが NPC 傘下に入る申し出（NPC がリーダー）
func will_accept(offer_type: String, player_strength: float) -> bool:
	var npc_strength := get_party_strength()
	if offer_type == "join_us":
		# NPC がプレイヤー傘下に入る場合
		# NPC が圧倒的に強い（1.5倍超）なら拒否
		return npc_strength <= player_strength * 1.5
	else:
		# プレイヤーが NPC 傘下に入る場合：戦力強化になるので常に承諾
		return true
