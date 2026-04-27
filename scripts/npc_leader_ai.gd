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

## フロア基準値定数の個数（FLOOR_0〜FLOOR_4 の 5 個）
const FLOOR_THRESHOLD_COUNT: int = 5


## フロアインデックス → フロア基準ランク和（GlobalConstants の外出し定数を参照）
## 範囲外（< 0 or >= FLOOR_THRESHOLD_COUNT）は 0 を返す
func _get_floor_threshold(floor_index: int) -> int:
	match floor_index:
		0: return GlobalConstants.FLOOR_0_RANK_THRESHOLD
		1: return GlobalConstants.FLOOR_1_RANK_THRESHOLD
		2: return GlobalConstants.FLOOR_2_RANK_THRESHOLD
		3: return GlobalConstants.FLOOR_3_RANK_THRESHOLD
		4: return GlobalConstants.FLOOR_4_RANK_THRESHOLD
	return 0

# --------------------------------------------------------------------------
# 合流承諾判定スコア定数（調整しやすいよう定数化）
# --------------------------------------------------------------------------
## ランク集計値は GlobalConstants.RANK_BASE_OFFSET + CharacterGenerator.RANK_VALUE[rank]
##   → C=+0, B=+1, A=+2, S=+3（C ランクでも RANK_BASE_OFFSET 分だけ加算）
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
## NPC パーティーがフロア遷移を自律判断しないようにするフラグ
var suppress_floor_navigation: bool = false


## 攻撃対象とする敵リストを設定する（PartyManager が初期化後に呼ぶ）
func set_enemy_list(enemies: Array[Character]) -> void:
	_enemy_list = enemies


## 対立するキャラクターのリスト（敵リスト）を返す
func _get_opposing_characters() -> Array[Character]:
	return _enemy_list


## NPC 用 UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return NpcUnitAI.new()


## NPC が検知している敵（同フロア・訪問済みエリア内）がいるか判定する
## 2026-04-21 追加：旧 `_evaluate_party_strategy()` の敵検知ロジックを抽出・単独公開。
## 戦略評価を廃止したため（味方は `_party_strategy` を使わない）、基底の
## `_is_in_explore_mode()` を override してこの結果で分岐する。
##
## 判定条件（順次チェック）:
##   - 同フロア（他フロアの敵は無視）
##   - 訪問済みエリア（未探索エリアの敵は `debug_show_all` でも無視）
##   - MapData 未初期化時は `enemy.visible` にフォールバック
##
## 将来課題（ステップ 2）: `_combat_situation.situation == CRITICAL` で
## `_global_orders.battle_policy = "retreat"` に書き換えて自動 FLEE を復活する。
## 本ステップでは CRITICAL 時の自動 FLEE は一時的に失われている
## （個別指示 `on_low_hp = "flee"` による個人逃走は従来どおり発動する）。
func _has_visible_enemy() -> bool:
	var my_floor := -1
	for m: Character in _party_members:
		if is_instance_valid(m):
			my_floor = m.current_floor
			break
	for enemy: Character in _enemy_list:
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		if my_floor >= 0 and enemy.current_floor != my_floor:
			continue
		if _map_data != null:
			var area_id := _map_data.get_area(enemy.grid_pos)
			if area_id.is_empty() or not _visited_areas.has(area_id):
				continue
		elif not enemy.visible:
			continue
		return true
	return false


## 探索モードか判定する（基底 party_leader.gd:_assign_orders の EXPLORE 分岐フック）
## 敵を検知していなければ探索モード（leader=explore/stairs・非leader=cluster で動く）
func _is_in_explore_mode() -> bool:
	return not _has_visible_enemy()


## リーダー本人の `_move_policy` 上書き（`follow` 退化挙動の解消・2026-04-26 追加）
##
## NPC リーダーの層 2 上書き経路：
##   - 探索モード（敵未検知）：本フックは `""` を返す → `_is_in_explore_mode()` が true →
##     `_get_explore_move_policy()` が `stairs_*` / `explore` を返す（既存経路を維持）
##   - 戦闘モード（敵検知中）：本フックは `"explore"` を返す → 層 1 の `follow` 継承を防ぐ
##
## NPC リーダーの `formation_ref` は null（player でも leader_char でもない）になるため
## 自己参照ではないが、`_move_policy = "follow"` だと UnitAI の `_formation_satisfied()`
## が `_leader_ref == null` 経路で常に true を返し、リーダーが立ち止まる退化挙動になる。
##
## 戦闘中の `_move_policy` は ATTACK strategy + target 存在時には `_battle_formation`
## ベースで動くため実質バイパスされるが、ターゲット切替・戦闘ラル時の挙動を
## 安定させるため explore フォールバックを入れる。
func _decide_leader_move_override() -> String:
	if _is_in_explore_mode():
		return ""  # 既存の `_get_explore_move_policy()` 経路に委ねる
	return "explore"


## 現在の状態に基づく目標フロアを返す（戦力値 + HP 補正）
## 戦力値 = 自パのみの strength（装備 tier 込み・HP 充足率込み）
## full_party の HP 充足率（ポーション込み・平均）が NPC_FLOOR_DOWNGRADE_HP_RATIO 未満の場合は適正フロア - 1
## suppress_floor_navigation = true またはメンバーなしの場合は現在フロアをそのまま返す
## 値は _combat_situation から参照（_process 1.5 秒タイマーで更新済み）
func _get_target_floor() -> int:
	var current_floor := 0
	for m: Character in _party_members:
		if is_instance_valid(m):
			current_floor = m.current_floor
			break
	if suppress_floor_navigation or _party_members.is_empty():
		return current_floor

	# --- 1. 戦力値（自パのみ・装備 tier 込み・HP 充足率込み） ---
	var strength: float = float(_combat_situation.get("full_party_strength", 0.0))
	if strength <= 0.0:
		return current_floor

	# --- 2. 戦力値で適正フロアを決定 ---
	var floor_count: int = FLOOR_THRESHOLD_COUNT
	var appropriate_floor := current_floor
	if current_floor + 1 < floor_count:
		var next_rank := _get_floor_threshold(current_floor + 1)
		if strength >= float(next_rank):
			appropriate_floor = current_floor + 1
	if appropriate_floor == current_floor and current_floor > 0:
		var this_rank := _get_floor_threshold(current_floor)
		if strength < float(this_rank) * GlobalConstants.FLOOR_RETREAT_RATIO:
			appropriate_floor = current_floor - 1

	# --- 3. HP 充足率チェック（統合関数の full_party_hp_ratio を参照） ---
	var hp_ratio: float = float(_combat_situation.get("full_party_hp_ratio", 0.0))
	var hp_fail: bool = hp_ratio < GlobalConstants.NPC_FLOOR_DOWNGRADE_HP_RATIO

	# --- 4. 目標フロア決定（HP 充足率が低ければ-1） ---
	var target_floor := appropriate_floor
	if hp_fail:
		target_floor = maxi(0, appropriate_floor - 1)

	# --- 5. デバッグログ（初回 or 目標フロア変化時） ---
	if _prev_target_floor != target_floor:
		var leader_name := _get_leader_name()
		var next_rank  := _get_floor_threshold(current_floor + 1)
		var half_rank  := floori(float(_get_floor_threshold(current_floor)) * GlobalConstants.FLOOR_RETREAT_RATIO)
		var score_part := "戦力%.1f（次F%d基準%d / 退避%d）" % [
			strength, current_floor + 1, next_rank, half_rank]
		var hp_part := "HP充足率%.0f%%%s" % [hp_ratio * 100.0, "×" if hp_fail else "○"]
		var adj_part := " →補正-1" if hp_fail else ""
		MessageLog.add_ai(
			"[NPCフロア判断] %s: %s / %s / 適正F%d%s → 目標F%d" % [
				leader_name, score_part, hp_part,
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


## NPC パーティーの global_orders ヒントを返す（デバッグウィンドウ表示用）
## NPC 指示部分のヒントを返す（戦況部分は基底の `_append_combat_situation_to_hint` が付与）
## NPC 固有差分:
##   - デフォルト方針が「follow / same_as_leader / fall_back / passive」（プレイヤー追従前提）
##   - sp_mp_potion キーを持つ（ベース版は持たない）
##   - 探索モード（敵未検知）時に階段移動中なら target_floor キーを追加（_get_target_floor 固有）
##
## 2026-04-21 改訂：`_party_strategy` は敵専用概念に変更したため、`match _party_strategy` による
## ヒント合成を廃止。探索モード判定は `_is_in_explore_mode()` 経由で行う。
## CRITICAL 時の FLEE 自動切替はステップ 2 で `battle_policy="retreat"` への自動書き換え方式で復活予定。
##
## 2026-04-23 改訂：`get_global_orders_hint()` の override を廃止し、指示部分だけ `_build_orders_part()`
## で差分を返す方式に変更。戦況部分のキー追加漏れを根絶する
##
## 2026-04-23 追加改訂：NPC デフォルトをベースラインとして常に返し、`_global_orders` の値を
## その上にマージする方式に変更。従来は `_global_orders` が非空のとき defaults を一切返さず、
## NpcLeaderAI の CRITICAL 時 battle_policy 書き換え後は `hp_potion` 等の NPC デフォルトが
## 消え、ポーション自動使用が無効化される不具合があった
func _build_orders_part() -> Dictionary:
	# NPC ベースライン（OrderWindow を介さない NPC の既定指示）
	var hint: Dictionary = {
		"move":          "follow",
		"battle_policy": "attack",
		"target":        "same_as_leader",
		"on_low_hp":     "fall_back",
		"item_pickup":   "aggressive",
		"hp_potion":     "use",
		"sp_mp_potion":  "use",
	}
	# `_global_orders` の内容を上書きマージ（例：CRITICAL 時の battle_policy="retreat"）
	for k: Variant in _global_orders.keys():
		hint[k] = _global_orders[k]
	# 探索モード（敵未検知）時の move 上書き。
	# 2026-04-24 深夜：合流済み NPC は除外（プレイヤーの global_orders に従うべき）。
	# 2026-04-25 改訂：`stairs_down` / `stairs_up` / `target_floor` は `_global_orders.move`
	# （パーティー全体指示）に書き込まない方針に変更。これらは OrderWindow 定義外の値であり、
	# パーティー全体の指示ではなく「リーダー個人の動的目標」として扱う。階段ナビへの per-member
	# 配布は `_assign_orders()` 側で `_get_explore_move_policy()` を直接呼ぶ既存ロジック
	# （リーダー → stairs_* / 非リーダー → cluster）が担当する。本関数では OrderWindow 定義値
	# の範囲内（`explore`）のみ hint["move"] に反映し、ヘッダー行の表示が規約に準拠するようにする。
	if not joined_to_player and _is_in_explore_mode():
		var pol := _get_explore_move_policy()
		if pol == "explore":
			hint["move"] = pol
	return hint


## 戦略変更の理由
## 2026-04-21 改訂：味方は `_party_strategy` を計算しないため、このメソッドは
## 現状呼ばれない（`_log_strategy_change` は敵パーティーでのみ発火する）。
## 将来ステップ 2 で FLEE 自動切替を復活する際、battle_policy 変更時のログに使う余地あり。
func _get_strategy_change_reason() -> String:
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
	# 戦況 CRITICAL/SAFE に応じた battle_policy 自動書き換え（2026-04-21 追加・ステップ 2）
	## super._process は _reeval_timer 経過時に _combat_situation を更新するので、
	## その結果を見て battle_policy を切り替える。joined_to_player 中はプレイヤー管理の
	## パーティーなので対象外（プレイヤーが OrderWindow で手動設定する）。
	if not joined_to_player:
		_evaluate_and_update_battle_policy()
	# 合流済みパーティーは対象外（プレイヤーが直接管理する）
	if joined_to_player:
		return
	_auto_item_timer += delta
	if _auto_item_timer >= AUTO_ITEM_INTERVAL / GlobalConstants.game_speed:
		_auto_item_timer = 0.0
		_auto_equip_members()
		_auto_share_potions()


# --------------------------------------------------------------------------
# battle_policy 自動書き換え（2026-04-21 ステップ 2 追加）
# --------------------------------------------------------------------------

## 直近で battle_policy を書き換えた時刻（Time.get_ticks_msec()/1000.0 ベース・秒）
## `NPC_POLICY_CHANGE_COOLDOWN` のクールダウン管理に使用。
## 初期値 -INF により起動直後の切り替えは常に許可される
var _last_policy_change_time: float = -INF


## 戦況 CombatSituation に応じて `_global_orders.battle_policy` を自動書き換えする
## （ステップ 1 で削除した `_evaluate_party_strategy()` 由来の自動 FLEE を別経路で復活）
##
## 設計方針：
##   - CRITICAL（戦力比 < 0.5）→ `battle_policy = "retreat"`（個別指示を撤退プリセットに一括更新）
##   - SAFE（敵を検知していない）→ `battle_policy = "attack"`（通常の攻撃/探索に戻す）
##   - 中間領域（DISADVANTAGE / EVEN / ADVANTAGE / OVERWHELMING）は現状維持
##     → CRITICAL/SAFE の 2 閾値切替のみ。境界振動を抑える
##   - クールダウン `NPC_POLICY_CHANGE_COOLDOWN`（既定 3.0 秒）で短時間の再書き換えを抑制
##
## プリセット流し込みは基底 `PartyLeader.apply_battle_policy_preset()` を呼ぶ
## （PartyLeaderPlayer が OrderWindow 経由で行うのと同等の処理）
func _evaluate_and_update_battle_policy() -> void:
	var situation: int = _combat_situation.get("situation",
		int(GlobalConstants.CombatSituation.SAFE)) as int

	var current_policy: String = _global_orders.get("battle_policy", "attack") as String
	var new_policy: String = current_policy
	if situation == int(GlobalConstants.CombatSituation.CRITICAL):
		new_policy = "retreat"
	elif situation == int(GlobalConstants.CombatSituation.SAFE):
		new_policy = "attack"
	# 中間領域は現状維持（new_policy = current_policy）

	if new_policy == current_policy:
		return

	# クールダウンチェック（頻繁な切り替え防止）
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_policy_change_time < GlobalConstants.NPC_POLICY_CHANGE_COOLDOWN:
		return

	# 書き換え＆プリセット流し込み
	_global_orders["battle_policy"] = new_policy
	_last_policy_change_time = now
	apply_battle_policy_preset(new_policy)
	# メンバー指示へ即座に伝達（次の _reeval_timer を待たずに _assign_orders を発火）
	notify_situation_changed()

	# ログ（デバッグ・プレイ観察用）
	if MessageLog != null:
		var leader_name := _get_leader_name()
		var sit_label: String = _combat_situation_label(situation)
		MessageLog.add_ai(
			"[NPC戦況判断] %s: 戦況=%s → battle_policy=%s" % [
				leader_name, sit_label, new_policy])


## CombatSituation enum 値を短い日本語ラベルに変換する（ログ用）
## party_status_window.gd 側の同名関数と同じロジックだが、依存を作らないため NpcLeaderAI にも持つ
func _combat_situation_label(sit: int) -> String:
	match sit:
		int(GlobalConstants.CombatSituation.SAFE):          return "安全"
		int(GlobalConstants.CombatSituation.OVERWHELMING):  return "圧倒"
		int(GlobalConstants.CombatSituation.ADVANTAGE):     return "優勢"
		int(GlobalConstants.CombatSituation.EVEN):          return "互角"
		int(GlobalConstants.CombatSituation.DISADVANTAGE):  return "劣勢"
		int(GlobalConstants.CombatSituation.CRITICAL):      return "危険"
	return "?"


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
		# 未装備品を bonus 段階合計降順にソート
		entries.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return _item_bonus_sum(a.item as Dictionary) > _item_bonus_sum(b.item as Dictionary)
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
				var cur_sum := _item_bonus_sum(cur)
				if _item_bonus_sum(new_item) <= cur_sum:
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
		# HP ポーション受け渡し（状態ラベル経由：injured/critical のメンバーに配布・auto_use トリガーと揃える）
		var cond: String = needer.get_condition()
		if cond == "injured" or cond == "critical":
			if _find_potion_in_cd(cd, "hp") == null:
				var pot: Variant = _take_potion_from_party(needer, "hp")
				if pot != null:
					cd.inventory.append(pot)
		# エナジーポーション受け渡し（全クラス共通）
		if needer.max_energy > 0:
			var en_ratio := float(needer.energy) / float(needer.max_energy)
			if en_ratio < GlobalConstants.POTION_SP_MP_AUTOUSE_THRESHOLD \
					and _find_potion_in_cd(cd, "energy") == null:
				var pot: Variant = _take_potion_from_party(needer, "energy")
				if pot != null:
					cd.inventory.append(pot)


## 装備の bonus 段階合計を返す（比較用）
## bonus 段階は 0=無 / 1=小 / 2=中 / 3=大 の整数。max 値の差を吸収するため stats 値合計より公平
func _item_bonus_sum(item: Dictionary) -> int:
	if item.is_empty():
		return 0
	var total := 0
	var bonuses := item.get("bonuses", {}) as Dictionary
	for v: Variant in bonuses.values():
		total += int(v)
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
## kind: "hp" / "energy"
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


## 現在戦闘中か（共闘フラグ更新に使用）
## 2026-04-21 改訂：`_party_strategy` は敵専用概念のため、味方 NPC では敵検知フラグで判定する。
## 現状このメソッドは外部から呼ばれていないが、API として残す（将来共闘実績の更新で使う余地あり）。
func is_in_combat() -> bool:
	return _has_visible_enemy()


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
	return will_accept_with_reason(offer_type, player_party).get("accepted", false) as bool


## 合流承諾判定を実行し、承諾/拒否と主要因（reason）を返す
## 戻り値: { "accepted": bool, "reason": String }
## reason:
##   承諾: "dire"（NPC側が窮地）/ "teamwork"（共闘・回復実績）/ "power"（戦力）
##   拒否: "power_gap"（戦力差）/ "no_teamwork"（共闘不足）/ "independent"（自力で十分）
##   足切り: "unready"（適正フロア未到達）
func will_accept_with_reason(offer_type: String, player_party: Party) -> Dictionary:
	if offer_type != "join_us":
		# プレイヤーが NPC 傘下に入る場合：戦力強化になるので常に承諾
		return {"accepted": true, "reason": "power"}

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
		return {"accepted": false, "reason": "unready"}

	# ---- プレイヤー側スコア ----
	var leader_leadership := 0
	var player_rank_sum := 0
	for mv: Variant in player_party.members:
		var ch := mv as Character
		if not is_instance_valid(ch):
			continue
		if ch.is_leader and ch.character_data != null:
			## Character.leadership は装備補正込みの最終値
			leader_leadership = ch.leadership
		if ch.character_data != null:
			player_rank_sum += GlobalConstants.RANK_BASE_OFFSET + (CharacterGenerator.RANK_VALUE.get(ch.character_data.rank, 0) as int)

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
	var npc_hp_sum := 0
	var npc_max_hp_sum := 0
	for m: Character in _party_members:
		if not is_instance_valid(m):
			continue
		if m.character_data != null:
			## Character.obedience は装備補正込みの最終値
			npc_obedience_sum += m.obedience
			npc_rank_sum += GlobalConstants.RANK_BASE_OFFSET + (CharacterGenerator.RANK_VALUE.get(m.character_data.rank, 0) as int)
		npc_hp_sum     += m.hp
		npc_max_hp_sum += m.max_hp
		npc_count += 1

	var obedience_avg := npc_obedience_sum / float(npc_count) if npc_count > 0 else 0.5
	var npc_score := (100.0 - obedience_avg * 100.0) \
		+ float(npc_rank_sum) * RANK_SCORE_PER_RANK

	var result := player_score >= npc_score

	# ---- 判定理由の決定 ----
	var npc_hp_ratio: float = 1.0
	if npc_max_hp_sum > 0:
		npc_hp_ratio = float(npc_hp_sum) / float(npc_max_hp_sum)

	var reason: String
	if result:
		# 承諾：窮地を最優先（NPC側のHP低下）、次に共闘実績、なければ戦力
		if npc_hp_ratio < 0.7:
			reason = "dire"
		elif has_fought_together or has_been_healed:
			reason = "teamwork"
		else:
			reason = "power"
	else:
		# 拒否：3要因のウェイトを比較して最大を採用
		var w_power_gap: float = maxf(0.0,
			float(npc_rank_sum - player_rank_sum) * RANK_SCORE_PER_RANK)
		var w_no_teamwork: float = 0.0
		if not has_fought_together:
			w_no_teamwork += FOUGHT_TOGETHER_BONUS
		if not has_been_healed:
			w_no_teamwork += HEALED_BONUS
		var w_independent: float = 100.0 - obedience_avg * 100.0

		if w_power_gap >= w_no_teamwork and w_power_gap >= w_independent:
			reason = "power_gap"
		elif w_no_teamwork >= w_independent:
			reason = "no_teamwork"
		else:
			reason = "independent"

	# デバッグ：スコア内訳を MessageLog に出力（F1 ON 時のみ表示）
	var fought_str := "+%.0f(共闘)" % FOUGHT_TOGETHER_BONUS if has_fought_together else ""
	var healed_str := "+%.0f(回復)" % HEALED_BONUS        if has_been_healed       else ""
	MessageLog.add_ai(
		"[合流判定] P: 統率%d + ランク和%d×10%s%s = %.0f　NPC: (100-従順%.2f×100) + ランク和%d×10 = %.0f　→ %s(%s)" % [
			leader_leadership, player_rank_sum, fought_str, healed_str, player_score,
			obedience_avg, npc_rank_sum, npc_score,
			"承諾" if result else "拒否", reason
		])
	return {"accepted": result, "reason": reason}
