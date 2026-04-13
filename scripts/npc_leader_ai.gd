class_name NpcLeaderAI
extends PartyLeaderAI

## NPC リーダーAI
## 敵（ゴブリン等の enemy_party）を優先的にターゲットにして攻撃する。
## 生存敵がいれば ATTACK、いなければ EXPLORE（探索行動）。

# --------------------------------------------------------------------------
# 装備クラス対応テーブル（order_window.gd の CLASS_EQUIP_TYPES と同内容）
# --------------------------------------------------------------------------
const CLASS_EQUIP_TYPES: Dictionary = {
	"fighter-sword":  ["sword",  "armor_plate", "shield"],
	"fighter-axe":    ["axe",    "armor_plate", "shield"],
	"archer":         ["bow",    "armor_cloth"],
	"scout":          ["dagger", "armor_cloth"],
	"magician-fire":  ["staff",  "armor_robe"],
	"magician-water": ["staff",  "armor_robe"],
	"healer":         ["staff",  "armor_robe"],
}

## 自動装備・ポーション受け渡しの実行間隔（秒）
const AUTO_ITEM_INTERVAL: float = 2.0

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
var _auto_item_timer: float = 0.0

## 同じ敵パーティーと共に戦ったことがあるか
var has_fought_together: bool = false
## プレイヤー側ヒーラーに回復されたことがあるか
var has_been_healed: bool = false

## 前回の目標フロア（変化検出用。-1=未初期化）
var _prev_target_floor: int = -1

## trueにするとフロア遷移スコア判断をスキップして常に "explore" を返す
## hero パーティーのマネージャー（_hero_manager）など、
## プレイヤーが階段を手動操作するケースで使用する
var suppress_floor_navigation: bool = false


## 攻撃対象とする敵リストを設定する（NpcManager が初期化後に呼ぶ）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies


## NPC 用 UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return NpcUnitAI.new()


## パーティー全体の戦略を評価する
## 同じフロアに生存 かつ NPC自身が訪問済みのエリアにいる敵がいれば ATTACK、いなければ EXPLORE
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
		# NPC 自身が訪問済みのエリアにいる敵のみ ATTACK トリガーにする
		# （debug_show_all による全敵可視化の影響を受けない）
		if _map_data != null:
			var area_id := _map_data.get_area(enemy.grid_pos)
			if area_id.is_empty() or not _visited_areas.has(area_id):
				continue
		elif not enemy.visible:
			# MapData なし（初期化前）のフォールバック
			continue
		return Strategy.ATTACK
	return Strategy.EXPLORE


## 現在の状態に基づく目標フロアを返す（HP/Energy 補正込み）
## rank_sum = 全メンバーの RANK_VALUES（C=3, B=4, A=5, S=6）の和
## ① ランク和スコアで適正フロアを決定
## ② HP最低値・エネルギー平均値が閾値を下回る場合は適正フロア-1（休息・浅層退避）
## suppress_floor_navigation = true またはメンバーなしの場合は現在フロアをそのまま返す
func _get_target_floor() -> int:
	# hero パーティーマネージャー等ではフロア遷移判断を行わない
	var current_floor := 0
	for m: Character in _party_members:
		if is_instance_valid(m):
			current_floor = m.current_floor
			break
	if suppress_floor_navigation or _party_members.is_empty():
		return current_floor

	# --- 1. ランク和スコア（全メンバーの RANK_VALUES 合計） ---
	var rank_sum := 0
	var count := 0
	for m: Character in _party_members:
		if not is_instance_valid(m):
			continue
		if m.character_data != null:
			rank_sum += RANK_VALUES.get(m.character_data.rank, 3) as int
		count += 1
	if count == 0:
		return current_floor

	# --- 2. ランク和スコアで適正フロアを決定 ---
	var floor_count: int = GlobalConstants.FLOOR_RANK.size()
	var appropriate_floor := current_floor
	if current_floor + 1 < floor_count:
		var next_rank := GlobalConstants.FLOOR_RANK.get(current_floor + 1, 9999) as int
		if rank_sum >= next_rank:
			appropriate_floor = current_floor + 1
	if appropriate_floor == current_floor and current_floor > 0:
		var this_rank := GlobalConstants.FLOOR_RANK.get(current_floor, 0) as int
		if rank_sum < this_rank / 2:
			appropriate_floor = current_floor - 1

	# --- 3. HP チェック（最低値） ---
	var hp_fail := false
	var hp_min_ratio := 1.0
	for m: Character in _party_members:
		if not is_instance_valid(m) or m.max_hp <= 0:
			continue
		var recoverable := float(_calc_recoverable_hp(m))
		var ratio := clampf((float(m.hp) + recoverable) / float(m.max_hp), 0.0, 1.0)
		hp_min_ratio = minf(hp_min_ratio, ratio)
	if hp_min_ratio < GlobalConstants.NPC_HP_THRESHOLD:
		hp_fail = true

	# --- 4. エネルギー（MP/SP）チェック（平均値） ---
	var energy_fail := false
	var energy_sum := 0.0
	var energy_count := 0
	for m: Character in _party_members:
		if not is_instance_valid(m):
			continue
		var max_energy := m.max_mp if m.max_mp > 0 else m.max_sp
		if max_energy <= 0:
			continue
		var cur_energy := m.mp if m.max_mp > 0 else m.sp
		var recoverable := float(_calc_recoverable_energy(m))
		energy_sum += clampf((float(cur_energy) + recoverable) / float(max_energy), 0.0, 1.0)
		energy_count += 1
	if energy_count > 0 and energy_sum / float(energy_count) < GlobalConstants.NPC_ENERGY_THRESHOLD:
		energy_fail = true

	# --- 5. 目標フロア決定（HP/Energy が低ければ-1） ---
	var target_floor := appropriate_floor
	if hp_fail or energy_fail:
		target_floor = maxi(0, appropriate_floor - 1)

	# --- 6. デバッグログ（初回 or 目標フロア変化時） ---
	if _prev_target_floor != target_floor:
		var leader_name := _get_leader_name()
		var next_rank  := GlobalConstants.FLOOR_RANK.get(current_floor + 1, 9999) as int
		var half_rank  := (GlobalConstants.FLOOR_RANK.get(current_floor, 0) as int) / 2
		var score_part := "ランク和%d（次F%d基準%d / 退避%d）" % [
			rank_sum, current_floor + 1, next_rank, half_rank]
		var hp_part := "HP最低%.0f%%%s" % [hp_min_ratio * 100.0, "×" if hp_fail else "○"]
		var en_avg  := (energy_sum / float(energy_count) * 100.0) if energy_count > 0 else 100.0
		var en_part := "En平均%.0f%%%s" % [en_avg, "×" if energy_fail else "○"]
		var adj_part := " →補正-1" if (hp_fail or energy_fail) else ""
		MessageLog.add_ai(
			"[NPCフロア判断] %s: %s / %s / %s / 適正F%d%s → 目標F%d" % [
				leader_name, score_part, hp_part, en_part,
				appropriate_floor, adj_part, target_floor]
		)
		_prev_target_floor = target_floor

	return target_floor


## 探索時の移動方針を返す（_get_target_floor() の結果を方針文字列に変換）
func _get_explore_move_policy() -> String:
	if suppress_floor_navigation or _party_members.is_empty():
		return "explore"
	var current_floor := 0
	for m: Character in _party_members:
		if is_instance_valid(m):
			current_floor = m.current_floor
			break
	var target_floor := _get_target_floor()
	if target_floor > current_floor:
		return "stairs_down"
	if target_floor < current_floor:
		return "stairs_up"
	return "explore"


## インベントリ内の HP 回復ポーションで回復できる HP 量を計算する
func _calc_recoverable_hp(member: Character) -> int:
	if member.character_data == null:
		return 0
	var total := 0
	for item: Variant in member.character_data.inventory:
		var it := item as Dictionary
		if it == null:
			continue
		var eff := it.get("effect", {}) as Dictionary
		total += eff.get("restore_hp", 0) as int
	return total


## インベントリ内のポーションで回復できるエネルギー（MP または SP）量を計算する
func _calc_recoverable_energy(member: Character) -> int:
	if member.character_data == null:
		return 0
	var use_mp := member.max_mp > 0
	var key := "restore_mp" if use_mp else "restore_sp"
	var total := 0
	for item: Variant in member.character_data.inventory:
		var it := item as Dictionary
		if it == null:
			continue
		var eff := it.get("effect", {}) as Dictionary
		total += eff.get(key, 0) as int
	return total


## NPC パーティーの global_orders ヒントを返す（デバッグウィンドウ表示用）
## _global_orders が設定されていない場合は NPC デフォルト値＋現在戦略を合成して返す
func get_global_orders_hint() -> Dictionary:
	if not _global_orders.is_empty():
		return _global_orders
	var hint: Dictionary = {
		"move":          "follow",
		"battle_policy": "attack",
		"target":        "same_as_leader",
		"on_low_hp":     "retreat",
		"item_pickup":   "passive",
		"hp_potion":     "use",
		"sp_mp_potion":  "use",
	}
	match _party_strategy:
		Strategy.FLEE:
			hint["battle_policy"] = "retreat"
			hint["on_low_hp"]     = "flee"
		Strategy.WAIT, Strategy.DEFEND:
			hint["battle_policy"] = "defense"
		Strategy.EXPLORE:
			var pol := _get_explore_move_policy()
			hint["move"] = pol
			if pol == "stairs_down" or pol == "stairs_up":
				hint["target_floor"] = str(_get_target_floor())
		Strategy.GUARD_ROOM:
			hint["move"] = "guard_room"
	return hint


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
# 自動装備・ポーション受け渡し
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	# 合流済みパーティーは対象外（プレイヤーが直接管理する）
	if joined_to_player:
		return
	_auto_item_timer += delta
	if _auto_item_timer >= AUTO_ITEM_INTERVAL / GlobalConstants.game_speed:
		_auto_item_timer = 0.0
		_auto_equip_members()
		_auto_share_potions()


## パーティー全体の未装備品を最適配分する
## 装備種類ごとに未装備品をまとめ、最も恩恵を受けるメンバー（現装備が最弱）から順に装備させる
func _auto_equip_members() -> void:
	# 装備可能な item_type ごとに未装備品を収集
	var pool_by_type: Dictionary = {}  # item_type -> Array[{item, owner_data}]
	for mv: Variant in _party_members:
		if not is_instance_valid(mv):
			continue
		var member := mv as Character
		if member == null or member.character_data == null:
			continue
		var cd := member.character_data
		for item_var: Variant in cd.inventory:
			var item := item_var as Dictionary
			if item == null:
				continue
			var cat: String = item.get("category", "") as String
			if cat not in ["weapon", "armor", "shield"]:
				continue
			var itype: String = item.get("item_type", "") as String
			if itype.is_empty():
				continue
			if not pool_by_type.has(itype):
				pool_by_type[itype] = []
			(pool_by_type[itype] as Array).append({"item": item, "owner": cd})

	# 各 item_type ごとに最適配分
	for itype: String in pool_by_type:
		var entries: Array = pool_by_type[itype] as Array
		if entries.is_empty():
			continue
		# 未装備品をステータス合計降順にソート
		entries.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return _item_stats_sum(a.item as Dictionary) > _item_stats_sum(b.item as Dictionary)
		)
		for entry_var: Variant in entries:
			var entry := entry_var as Dictionary
			if entry == null:
				continue
			var new_item := entry.get("item", {}) as Dictionary
			var owner_cd := entry.get("owner") as CharacterData
			if owner_cd == null:
				continue
			# 最も恩恵を受けるメンバー（このタイプの現装備が最弱）を探す
			var best_target: Character = null
			var lowest_cur_sum := INF
			for mv2: Variant in _party_members:
				var member2 := mv2 as Character
				if not is_instance_valid(member2) or member2.character_data == null:
					continue
				var cd2 := member2.character_data
				var allowed: Array = CLASS_EQUIP_TYPES.get(cd2.class_id, []) as Array
				if itype not in allowed:
					continue
				# 新装備が現装備より強い場合のみ候補にする
				var cur := _get_equipped_for_type(cd2, itype)
				var cur_sum := _item_stats_sum(cur)
				if _item_stats_sum(new_item) <= cur_sum:
					continue
				if cur_sum < lowest_cur_sum:
					lowest_cur_sum = cur_sum
					best_target = member2
			if best_target == null:
				continue
			var target_cd := best_target.character_data
			# 旧装備を未装備品としてオーナーのインベントリに戻す
			var old_equipped := _get_equipped_for_type(target_cd, itype)
			# 自分が持ちからオーナーの手持ちに移す
			owner_cd.inventory.erase(new_item)
			if not old_equipped.is_empty():
				target_cd.inventory.append(old_equipped)
			target_cd._equip_item(new_item)
			best_target.refresh_stats_from_equipment()


## 必要なポーションがないメンバーに、余剰分を持つメンバーから渡す
func _auto_share_potions() -> void:
	for mv: Variant in _party_members:
		var needer := mv as Character
		if not is_instance_valid(needer) or needer.character_data == null:
			continue
		var cd := needer.character_data
		# HP ポーション受け渡し
		var hp_ratio := float(needer.hp) / float(needer.max_hp) if needer.max_hp > 0 else 1.0
		if hp_ratio < GlobalConstants.NEAR_DEATH_THRESHOLD:
			if _find_potion_in_cd(cd, "hp") == null:
				var pot: Variant = _take_potion_from_party(needer, "hp")
				if pot != null:
					cd.inventory.append(pot)
		# SP/MP ポーション受け渡し
		var use_mp := needer.max_mp > 0
		if use_mp:
			var mp_ratio := float(needer.mp) / float(needer.max_mp) if needer.max_mp > 0 else 1.0
			if mp_ratio < 0.5 and _find_potion_in_cd(cd, "mp") == null:
				var pot: Variant = _take_potion_from_party(needer, "mp")
				if pot != null:
					cd.inventory.append(pot)
		elif needer.max_sp > 0:
			var sp_ratio := float(needer.sp) / float(needer.max_sp)
			if sp_ratio < 0.5 and _find_potion_in_cd(cd, "sp") == null:
				var pot: Variant = _take_potion_from_party(needer, "sp")
				if pot != null:
					cd.inventory.append(pot)


## ステータス補正値の合計を返す（比較用）
func _item_stats_sum(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var total := 0.0
	var stats := item.get("stats", {}) as Dictionary
	for v: Variant in stats.values():
		total += float(v)
	return total


## item_type に対応する現在の装備 Dictionary を返す（未装備なら空辞書）
func _get_equipped_for_type(cd: CharacterData, itype: String) -> Dictionary:
	match itype:
		"sword", "axe", "bow", "dagger", "staff":
			return cd.equipped_weapon
		"armor_plate", "armor_cloth", "armor_robe":
			return cd.equipped_armor
		"shield":
			return cd.equipped_shield
	return {}


## キャラクターのインベントリからポーションを検索する
func _find_potion_in_cd(cd: CharacterData, kind: String) -> Variant:
	var key := "restore_" + kind
	for item_var: Variant in cd.inventory:
		var it := item_var as Dictionary
		if it == null:
			continue
		var eff := it.get("effect", {}) as Dictionary
		if (eff.get(key, 0) as int) > 0:
			return it
	return null


## needer 以外のメンバーからポーションを取り出す（所持あれば削除して返す）
func _take_potion_from_party(needer: Character, kind: String) -> Variant:
	for mv: Variant in _party_members:
		var donor := mv as Character
		if not is_instance_valid(donor) or donor == needer:
			continue
		if donor.character_data == null:
			continue
		var pot: Variant = _find_potion_in_cd(donor.character_data, kind)
		if pot != null:
			donor.character_data.inventory.erase(pot)
			return pot
	return null


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

	# ---- 足切り：適正フロアに到達していなければ断る ----
	# まだ下層に進む必要がないため、仲間を増やすメリットが薄い
	var current_floor := 0
	for m: Character in _party_members:
		if is_instance_valid(m):
			current_floor = m.current_floor
			break
	if current_floor < _get_target_floor():
		MessageLog.add_ai(
			"[合流判定] %s: 適正フロア未到達のため断る（現在F%d）" % [_get_leader_name(), current_floor])
		return false

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
