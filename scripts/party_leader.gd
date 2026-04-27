class_name PartyLeader
extends Node

## パーティーリーダー基底クラス
## パーティー全体の戦略を決定し、各メンバーの UnitAI に指示を伝達する。
## PartyLeaderAI（AI自動判断）と PartyLeaderPlayer（プレイヤー操作）が継承する。
##
## サブクラスがオーバーライドするフック:
##   _create_unit_ai()          : メンバーに対応する UnitAI の種別を返す
##   _evaluate_party_strategy() : パーティー全体の戦略判断
##   _select_target_for()       : メンバーごとの攻撃ターゲット選択
##   _select_weakest_target()   : 最弱ターゲット選択（複数候補がある場合）
##   _evaluate_strategic_status(): 統合戦略評価（full_party / nearby_allied / nearby_enemy の 3 集合で戦力・戦況を算出）
##   _get_opposing_characters() : 対立キャラリストを返す（敵AI=friendly_list、味方AI=enemy_list）

## パーティー戦略（ATTACK=0, FLEE=1, WAIT=2 は UnitAI.Strategy と int 値一致）
## DEFEND=3, EXPLORE=4, GUARD_ROOM=5 はパーティーレベル専用（UnitAI へは WAIT/ATTACK+move に変換して渡す）
enum Strategy { ATTACK, FLEE, WAIT, DEFEND, EXPLORE, GUARD_ROOM }

const REEVAL_INTERVAL := 1.5  ## 定期再評価の間隔（秒）

var _party_members: Array[Character] = []
var _player:        Character
var _map_data:      MapData
var _unit_ais:      Dictionary = {}  ## member.name -> UnitAI
var _party_strategy: Strategy = Strategy.WAIT
var _prev_strategy:  Strategy = Strategy.WAIT  ## 前回の戦略（変更検出用）
var _combat_situation: Dictionary = {}  ## 最新の戦略評価結果（_evaluate_strategic_status の戻り値）
var log_enabled:     bool  = true  ## false にするとログ出力を抑制する（一時パーティー用）
var joined_to_player: bool = false ## true の場合は _player を隊形基準として使用する（合流済み NPC パーティー）
var _reeval_timer:   float = 0.0
var _initial_count:  int   = 0  ## 初期メンバー数（逃走判定の基準）
var _friendly_list:  Array[Character] = []  ## 攻撃対象の友好キャラ一覧（敵 AI 用）
var _visited_areas:  Dictionary = {}  ## 訪問済みエリアID集合（全 UnitAI で共有）
## パーティー全体方針（Party.global_orders の参照。hp_potion/sp_mp_potion 等を UnitAI に伝達）
## set_global_orders() で Party.global_orders dict への参照を受け取る（参照共有なので変更が反映される）
var _global_orders:  Dictionary = {}
var _party_ref: Party = null  ## プレイヤーパーティー参照（合流済みNPC含む。戦況判断の自軍メンバー評価に使用）

## 避難先エリア ID（2026-04-25 改訂：リーダー推奨出口機構を廃止し、避難先エリアのみ配布する設計に）
## リーダーが「自分の現エリアから最も近い避難先エリア（フロア 0 = 安全部屋 / フロア 1 以降 =
## 上り階段エリア）」を BFS ホップ距離で決定し、`_assign_orders()` 経由で全メンバーに配布。
## 各メンバーは `UnitAI._evaluate_exit_costs()` でこの避難先までの BFS 距離を出口コストに加算する。
## "" = 避難先未決定（敵不在・MapData 不在・敵パーティー）
var _flee_refuge_area_id: String = ""


## プレイヤーパーティー参照を設定する（プレイヤー・合流済みNPCパーティー両方で使用）
func set_party_ref(party: Party) -> void:
	_party_ref = party


# --------------------------------------------------------------------------
# セットアップ
# --------------------------------------------------------------------------

## メンバー・プレイヤー・マップデータをセットアップし、各メンバーの UnitAI を生成する
func setup(members: Array[Character], player: Character, map_data: MapData,
		all_members: Array[Character]) -> void:
	_party_members = members
	_player        = player
	_map_data      = map_data
	_initial_count = members.size()
	# 連合判定で参照する全パーティー合算リスト。
	# activate() が _link_all_character_lists() より後に呼ばれる NPC 向けに、
	# setup 引数の all_members を self._all_members に代入して未伝播を防ぐ。
	_all_members   = all_members

	# メンバーごとに UnitAI を生成してノードツリーに追加（_process が動くようにする）
	for member: Character in members:
		var unit_ai := _create_unit_ai(member)
		unit_ai.name = "UnitAI_" + member.name
		add_child(unit_ai)
		unit_ai.setup(member, player, map_data, all_members)
		unit_ai.set_party_peers(members)  ## heal/buff は自パーティーメンバー限定
		unit_ai.set_follow_hero_floors(joined_to_player)  ## 合流済みメンバーのみ hero をフロア追従
		unit_ai.set_visited_areas(_visited_areas)  ## 訪問済みエリア（パーティー全員で共有）
		_unit_ais[member.name] = unit_ai

	# 初回オーダー発行
	_assign_orders()


# --------------------------------------------------------------------------
# 動的メンバー管理 API（2026-04-24 深夜追加・合流処理の完全化）
# --------------------------------------------------------------------------

## 既存 UnitAI を流用して外部から受け取ったメンバーを自パーティーに組み入れる。
## UnitAI の `_queue` / `_state` / `_flee_refuge_area_id` 等の状態は保持される（reparent のみ）。
## 呼出側（PartyManager.adopt_member）が Character 側のシグナル接続を管理する。
func adopt_member(member: Character, unit_ai: UnitAI) -> void:
	if member == null or not is_instance_valid(member):
		push_warning("[adopt_member] invalid member")
		return
	if unit_ai == null or not is_instance_valid(unit_ai):
		push_warning("[adopt_member] invalid unit_ai")
		return

	_party_members.append(member)
	_unit_ais[member.name] = unit_ai

	# UnitAI を self の子ノードに付け替える（旧 leader から remove → ここで add_child）
	if unit_ai.get_parent() != self:
		var old_parent := unit_ai.get_parent()
		if old_parent != null:
			old_parent.remove_child(unit_ai)
		add_child(unit_ai)

	# UnitAI の参照を新リーダーのものに差し替え（walker コンテキストの更新）
	unit_ai._player = _player
	unit_ai.set_visited_areas(_visited_areas)
	unit_ai.set_follow_hero_floors(joined_to_player)
	unit_ai.set_all_members(_all_members)
	unit_ai.set_map_data(_map_data)

	# 自パメンバーリストを全 UnitAI に再配布（heal/buff ターゲット候補用）
	for ua_v: Variant in _unit_ais.values():
		var ua := ua_v as UnitAI
		if ua != null:
			ua.set_party_peers(_party_members)

	# 生存 x/y の分母を更新
	_initial_count = _party_members.size()


## メンバーと UnitAI を自パーティーから切り離して返す。
## 呼出側（PartyManager.release_member → 新マネージャの adopt_member）で reparent する。
## ここではノードツリーからの remove は行わない（adopt 側で行うため）。
func release_member(member: Character) -> UnitAI:
	if member == null:
		push_warning("[release_member] null member")
		return null

	var unit_ai := _unit_ais.get(member.name) as UnitAI
	if unit_ai == null:
		push_warning("[release_member] no unit_ai for %s" % member.name)

	_party_members.erase(member)
	_unit_ais.erase(member.name)

	# 残ったメンバーに新しい peers を配布
	for ua_v: Variant in _unit_ais.values():
		var ua := ua_v as UnitAI
		if ua != null:
			ua.set_party_peers(_party_members)

	return unit_ai


# --------------------------------------------------------------------------
# セッター群（PartyManager / game_map から呼ばれる）
# --------------------------------------------------------------------------

## 攻撃対象となる友好キャラ一覧を設定する（敵 AI のターゲット選択に使用）
func set_friendly_list(friendlies: Array[Character]) -> void:
	_friendly_list = friendlies


## Party.global_orders への参照を受け取る（GDScript では Dictionary は参照型のため変更が自動反映）
## game_map が PartyManager セットアップ時に呼ぶ
func set_global_orders(orders: Dictionary) -> void:
	_global_orders = orders


## joined_to_player を各 UnitAI の _follow_hero_floors に伝播する
## PartyManager.set_joined_to_player() 経由で呼ばれる
func set_follow_hero_floors(value: bool) -> void:
	joined_to_player = value
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_follow_hero_floors(value)


## 全パーティー合算メンバーリスト（戦況判断で同陣営他パーティーの戦力加算に使用）
var _all_members: Array[Character] = []


## 全パーティー合算メンバーリストを各 UnitAI に反映する
func set_all_members(all_members: Array[Character]) -> void:
	_all_members = all_members
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_all_members(all_members)


## VisionSystem を各 UnitAI に配布する（explore 移動方針に必要）
func set_vision_system(vs: VisionSystem) -> void:
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_vision_system(vs)


## MapData を更新し各 UnitAI に反映する（フロア遷移時に game_map から呼ばれる）
func set_map_data(new_map_data: MapData) -> void:
	_map_data = new_map_data
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_map_data(new_map_data)


## 特定メンバーの UnitAI の map_data のみ更新する（個別フロア遷移時に使用）
func set_member_map_data(member_name: String, new_map_data: MapData) -> void:
	var unit_ai := _unit_ais.get(member_name) as UnitAI
	if unit_ai != null:
		unit_ai.set_map_data(new_map_data)


## デバッグウィンドウ用: 指定メンバーの行動目的の短い説明を返す
func get_member_goal_str(member_name: String) -> String:
	var unit_ai := _unit_ais.get(member_name) as UnitAI
	if unit_ai == null:
		return ""
	return unit_ai.get_debug_goal_str()


## デバッグウィンドウ用: 指定メンバーの UnitAI を返す（PartyStatusWindow の詳細表示用）
## 内部状態（_state / _timer / _queue 等）を直接参照するための窓口。null 可
func get_unit_ai(member_name: String) -> UnitAI:
	return _unit_ais.get(member_name) as UnitAI


## フロアアイテム辞書の参照を全 UnitAI に配布する（game_map から呼ばれる）
func set_floor_items(items: Dictionary) -> void:
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.set_floor_items(items)


# --------------------------------------------------------------------------
# 定期処理
# --------------------------------------------------------------------------

## リーダーの前回フロア（変化検知用。リーダーが階段で別フロアに移動したら全メンバーに通知）
var _prev_leader_floor: int = -999

func _process(delta: float) -> void:
	# 時間停止中（プレイヤーのターゲット選択中など）は再評価を止める
	if not GlobalConstants.world_time_running:
		return

	# リーダーのフロア変化を検知し、全メンバーに即時再評価を促す
	# （非リーダーが wait 中でも 3 秒待たずに階段追従に切り替わる）
	var leader_floor := -999
	for lm: Character in _party_members:
		if is_instance_valid(lm) and lm.is_leader:
			leader_floor = lm.current_floor
			break
	if leader_floor != _prev_leader_floor:
		if _prev_leader_floor != -999:
			# 初回以外: 全 UnitAI に状況変化を通知（wait 中のキューを破棄して再評価）
			for ua_v: Variant in _unit_ais.values():
				var ua := ua_v as UnitAI
				if ua != null:
					ua.notify_situation_changed()
			# PartyLeader 自身も即時再評価する
			_reeval_timer = 0.0
		_prev_leader_floor = leader_floor

	_reeval_timer -= delta
	if _reeval_timer <= 0.0:
		_reeval_timer = REEVAL_INTERVAL
		# === PERF_MEASUREMENT_START (2026-04-24 調査用・削除予定) ===
		var _perf_t_frame := Time.get_ticks_usec()
		# === PERF_MEASUREMENT_END ===
		_combat_situation = _evaluate_strategic_status()
		_assign_orders()
		# === PERF_MEASUREMENT_START (2026-04-24 調査用・削除予定) ===
		var _perf_frame_us: int = Time.get_ticks_usec() - _perf_t_frame
		if _perf_frame_us > 5000:
			var _perf_party_kind: String = "enemy" if _is_enemy_party() else "ally"
			DebugLog.log("[EXIT_FRAME] party=%s/%s total=%d us" % [
				_perf_party_kind, _get_leader_name(), _perf_frame_us
			])
		# === PERF_MEASUREMENT_END ===


# --------------------------------------------------------------------------
# 指示伝達（共通ロジック）
# --------------------------------------------------------------------------

## 戦略を評価して各メンバーにオーダーを発行する
## パーティー戦略に応じて move / combat / party_fleeing を決定し UnitAI に渡す
## 行動の最終決定は UnitAI._determine_effective_action() が行う
##
## 2026-04-21 改訂：`_party_strategy` は敵パーティー（EnemyLeaderAI 系）専用概念に変更。
## 味方（PartyLeaderPlayer / NpcLeaderAI）では戦略評価・更新を行わず、個別指示は
## `_global_orders.battle_policy` のプリセット流し込み（OrderWindow）経由のみで反映する。
## 詳細: docs/investigation_party_strategy_ally_removal.md / docs/investigation_receive_order_keys.md
func _assign_orders() -> void:
	# 戦略評価は敵パーティーのみ実施する（味方は _party_strategy を使わない）
	var is_enemy_party := _is_enemy_party()
	if is_enemy_party:
		_party_strategy = _apply_range_check(_evaluate_party_strategy())

		# 戦略変更時にログ出力
		if _party_strategy != _prev_strategy:
			var old_strategy := _prev_strategy
			_prev_strategy = _party_strategy
			if log_enabled and not _has_player_controlled_member():
				_log_strategy_change(old_strategy)

	# パーティーレベルの撤退判断（敵専用フラグ・味方は常に false）
	var party_fleeing := is_enemy_party and _party_strategy == Strategy.FLEE

	# 避難先エリア ID を更新（2026-04-25 改訂：リーダー推奨出口機構を廃止）
	# 各メンバーが UnitAI._evaluate_exit_costs() で出口コストの距離項に使う。
	# 味方は敵検知中ならつねに算出・敵パーティーは現状未対応（_find_flee_goal_legacy 経由）
	_update_flee_refuge_area_id()

	# リーダーキャラクター（UnitAI の formation 計算 + リーダー本人のターゲット決定に使用）
	var leader_char: Character = null
	for lm: Character in _party_members:
		if is_instance_valid(lm) and lm.is_leader:
			leader_char = lm
			break
	if leader_char == null and not _party_members.is_empty():
		for lm: Character in _party_members:
			if is_instance_valid(lm):
				leader_char = lm
				break

	# リーダー本人のターゲット方針を確定（自己参照解消・2026-04-26 追加）
	## 旧実装は `_party_members[0]` の `_select_target_for()` を直叩きで `leader_target`
	## を算出していた。policy lookup を経由しない構造のためリーダー本人の
	## `target = same_as_leader` でも循環せずに済んでいたが、
	## (a) リーダー個別の OrderWindow 値が無視される / (b) `_party_members[0]` ≠
	## 実リーダーの場合に非リーダーの `same_as_leader` が別人を参照する、という
	## 未定義経路を抱えていた。
	## ここでは `_decide_leader_target_policy_override()` で個別判断を経由させ、
	## `leader_target` も実リーダー基準で算出する。
	var leader_tgt_policy: String = "nearest"
	if leader_char != null:
		if joined_to_player:
			# 合流済み NPC パーティーは _global_orders をプレイヤー側が管理する
			# （実運用では _party_members 自体が空のはずだが念のためフォールバック）
			leader_tgt_policy = leader_char.current_order.get("target", "nearest")
		else:
			var override_target_policy: String = _decide_leader_target_policy_override()
			if not override_target_policy.is_empty():
				leader_tgt_policy = override_target_policy
			else:
				leader_tgt_policy = leader_char.current_order.get("target", "nearest")

	# リーダー本人のターゲットを先に決定（非リーダーの `same_as_leader` が参照する値）
	var leader_target: Character = null
	if leader_char != null:
		match leader_tgt_policy:
			"nearest":
				leader_target = _select_target_for(leader_char)
			"weakest":
				leader_target = _select_weakest_target(leader_char)
			"support":
				leader_target = _select_support_target(leader_char)
			_:
				leader_target = _select_target_for(leader_char)

	# パーティーレベルの指示参照（hp_potion / sp_mp_potion / move 等）
	## 2026-04-23：NPC（未加入）は `_global_orders` が空なので、`_build_orders_part()` の
	## サブクラスデフォルト（`hp_potion="use"` 等）を AI 実動にも反映させる。
	## 従来は `_global_orders.get("hp_potion", "never")` で常に "never" に落ち、
	## NPC がポーション自動使用しない不具合があった
	var party_orders: Dictionary = _build_orders_part()

	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue

		var order          := member.current_order
		var combat         : String = order.get("combat",          "attack")
		var on_low_hp      : String = order.get("on_low_hp",       "fall_back")
		var tgt_policy     : String = order.get("target",          "same_as_leader")
		var battle_form    : String = order.get("battle_formation", "surround")

		# ── 移動方針設定（3 層構造：ベースライン → リーダー上書き → 種族固有） ────
		## 層 1：ベースライン（`_global_orders.move`）。敵味方共通で全メンバーに適用する。
		##   - 味方（player / NPC）：`_build_orders_part()` 経由で OrderWindow / NPC デフォルト値
		##   - 敵：`EnemyLeaderAI._build_orders_part()` の baseline `"follow"` を継承
		## 層 2：リーダー上書き（モード固有値）。リーダー本人のみ・joined_to_player では適用しない。
		##   - 階段ナビ中：`stairs_down` / `stairs_up`
		##   - explore モード：`explore`
		##   - guard_room モード：`guard_room`（敵専用）
		## 層 3：種族固有上書き（敵のみ・本関数のスコープ外）
		var move_policy: String = party_orders.get("move", order.get("move", "same_room")) as String
		var formation_ref: Character = null
		if member.is_friendly:
			if leader_char == null or leader_char == member:
				if _player != null and is_instance_valid(_player) \
						and (leader_char == _player or joined_to_player):
					formation_ref = _player
			else:
				formation_ref = leader_char

		# ── 層 2：リーダーのみモード固有値で上書き ─────────────────────────
		## 非リーダーは層 1 のベースラインを継承する（cluster ハードコード廃止）
		## joined_to_player のリーダーは上書きしない（プレイヤー global_orders に従うため）
		##
		## 優先順（敵リーダーで該当する経路）：
		##   1. `_decide_leader_move_override()`（敵のみ・area_id ベース guard_room 等）
		##   2. `_is_in_explore_mode()`（NPC の探索モード分岐・敵では発火しない）
		##   3. `_is_in_guard_room_mode()`（旧 `_party_strategy.GUARD_ROOM` 経由・将来廃止予定）
		if member == leader_char and not joined_to_player:
			var override_policy: String = _decide_leader_move_override()
			if not override_policy.is_empty():
				move_policy = override_policy
			elif _is_in_explore_mode():
				move_policy = _get_explore_move_policy()
			elif _is_in_guard_room_mode():
				move_policy = "guard_room"

		# 注：2026-04-21 以前は `on_low_hp=retreat + HP低下 → move_policy=cluster` 上書きがここにあったが、
		# on_low_hp=fall_back は UnitAI 側で `_STRATEGY_FALL_BACK` を返し `fall_back` アクションキューを
		# 直接生成するようになったため、ここでの move_policy 上書きは不要（strategy=FALL_BACK 分岐が
		# move_policy を無視して fall_back 実行に進むため）。

		# ── ターゲット選択 ────────────────────────────────────────────────
		## リーダー本人は `_decide_leader_target_policy_override()` 由来の
		## `leader_tgt_policy`（既定 "nearest"）で上書きし、`current_order.target` の
		## `same_as_leader` による自己参照を回避する。`_move_policy` の 4/26 改修と同じ
		## 「リーダー個別判断」パターン。joined_to_player のリーダーは上書きしない。
		if member == leader_char and not joined_to_player:
			tgt_policy = leader_tgt_policy

		var target: Character
		match tgt_policy:
			"nearest":
				target = _select_target_for(member)
			"weakest":
				target = _select_weakest_target(member)
			"same_as_leader":
				target = leader_target if leader_target != null \
					else _select_target_for(member)
			"support":
				target = _select_support_target(member)
			_:
				target = _select_target_for(member)

		# クロスフロアターゲット排除
		if target != null and is_instance_valid(target) \
				and target.current_floor != member.current_floor:
			target = null

		# フロア間追従は UnitAI 側（_generate_move_queue）で move_policy が
		# cluster/follow/same_room の場合に判定する（リーダーが別フロアなら階段へ）
		# ここで move_policy を上書きすることはしない

		unit_ai.receive_order({
			"target":            target,
			"combat":            combat,
			"on_low_hp":         on_low_hp,
			"move":              move_policy,
			"battle_formation":  battle_form,
			"leader":            formation_ref,
			"party_fleeing":     party_fleeing,
			"hp_potion":         party_orders.get("hp_potion",    "never") as String,
			"sp_mp_potion":      party_orders.get("sp_mp_potion", "never") as String,
			"item_pickup":       member.current_order.get("item_pickup", "passive") as String,
			"special_skill":     order.get("special_skill", "strong_enemy") as String,
			"combat_situation":  _combat_situation,
			"flee_refuge_area_id": _flee_refuge_area_id,
		})


# --------------------------------------------------------------------------
# 通知・デバッグ
# --------------------------------------------------------------------------

## 状況変化通知（PartyManager から呼ばれる）：即座に再評価してオーダーを発行する
func notify_situation_changed() -> void:
	_reeval_timer = 0.0
	_combat_situation = _evaluate_strategic_status()
	_assign_orders()
	for unit_ai_var: Variant in _unit_ais.values():
		var unit_ai := unit_ai_var as UnitAI
		if unit_ai != null:
			unit_ai.notify_situation_changed()


## パーティーレベルのデバッグ情報を返す
func get_party_debug_info() -> Dictionary:
	return {
		"party_strategy": int(_party_strategy),
		"alive_count":    _party_members.size(),
		"initial_count":  _initial_count,
	}


## 初期メンバー数を返す（セットアップ時の人数・死亡後も不変）
## PartyStatusWindow の「生存:X/Y」表示の分母（Y）に使用
func get_initial_count() -> int:
	return _initial_count


# --------------------------------------------------------------------------
# FLEE 避難先エリア決定ロジック（2026-04-25 改訂：リーダー推奨出口機構を廃止）
# --------------------------------------------------------------------------

## 現在のパーティーが FLEE 状態か判定する
## 味方: `_global_orders.battle_policy == "retreat"`（OrderWindow 手動 or NpcLeaderAI 自動書き換え）
## 敵: `_party_strategy == Strategy.FLEE`（Goblin/Wolf の HP 低下時など）
func _is_party_fleeing() -> bool:
	if _is_enemy_party():
		return _party_strategy == Strategy.FLEE
	return _global_orders.get("battle_policy", "") == "retreat"


## 避難先エリア ID を更新する（2026-04-25 改訂）
##
## アルゴリズム：
##   1. リーダーの現エリアと現フロアの避難先エリア一覧を取得
##   2. 現エリアから各避難先までの BFS ホップ距離を計算し、最も近い避難先を採用
##   3. 全避難先が到達不能なら "" を残す
##
## 敵検知中の味方パーティーで常時計算（FLEE / fall_back のいずれでも使うため）
## 敵パーティー・敵不在・MapData 不在は ""（リセット）
##
## 各メンバーは UnitAI._evaluate_exit_costs() でこの ID と現エリアの距離項を出口コストに加算する。
## 出口の選定はメンバー側で完結するため、リーダー側で出口候補を計算する必要はない。
func _update_flee_refuge_area_id() -> void:
	# 敵パーティーは未対応（legacy 直線実装が動く・派生課題で対応予定）
	if _is_enemy_party():
		_flee_refuge_area_id = ""
		return
	# 敵不在ならリセット（FLEE / fall_back のどちらも発動しない）
	# ただし battle_policy="retreat"（撤退指示中）は敵不在でも維持し、
	# メンバーが避難先まで到達できるように refuge_area_id を継続提供する
	# （2026-04-25 改訂：撤退中に敵が視界外に消えると refuge が空になり、メンバーが
	# WAIT 切替後に refuge を見失って戻ってくる現象を防ぐ）
	var enemy_rank_sum: int = _combat_situation.get("nearby_enemy_rank_sum", 0) as int
	var is_retreating: bool = _global_orders.get("battle_policy", "") == "retreat"
	if enemy_rank_sum <= 0 and not is_retreating:
		_flee_refuge_area_id = ""
		return
	if _map_data == null:
		_flee_refuge_area_id = ""
		return
	var leader_char: Character = _get_first_alive_leader()
	if leader_char == null:
		_flee_refuge_area_id = ""
		return
	var current_area: String = _map_data.get_area(leader_char.grid_pos)
	if current_area.is_empty():
		_flee_refuge_area_id = ""
		return
	var refuge_area_ids: Array[String] = _map_data.get_refuge_area_ids(leader_char.current_floor)
	if refuge_area_ids.is_empty():
		_flee_refuge_area_id = ""
		return

	# リーダー位置から最も近い避難先エリアを BFS ホップ距離で選ぶ
	var best_area: String = ""
	var best_dist: int = 999999
	for refuge_area: String in refuge_area_ids:
		var d: int = _map_data.get_area_distance(current_area, refuge_area)
		if d < 0:
			continue
		if d < best_dist:
			best_dist = d
			best_area = refuge_area
	_flee_refuge_area_id = best_area  # 全避難先が到達不能なら "" のまま


## 選ばれた避難先エリア ID を返す（PartyStatusWindow 表示用）
## 空文字 = 未決定（敵不在・敵パーティー・避難先到達不能）
func get_flee_refuge_area_id() -> String:
	return _flee_refuge_area_id


## 先頭の生存メンバー（リーダー優先）を返す
func _get_first_alive_leader() -> Character:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0 and m.is_leader:
			return m
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			return m
	return null


## 戦闘方針プリセットをパーティーメンバー全員に適用する（2026-04-21 追加・ステップ 2）
## policy: "attack" / "defense" / "retreat" のいずれか
##
## 役割：`_global_orders.battle_policy` の変更を各メンバーの `current_order`（個別指示）に流し込む。
## プレイヤーは OrderWindow.`_apply_battle_policy_preset` が同じロジックで動作するが、NPC 側は
## OrderWindow を経由しないため PartyLeader 基底に同等機構を持つ。
##
## プリセット定義は `OrderWindow.BATTLE_POLICY_PRESET`（クラス別 × 方針別 → {combat, battle_formation}）
## を再利用する。ヒーラーは専用プリセット（rear / 方針対応 combat / heal=lowest_hp_first）。
##
## NpcLeaderAI が CRITICAL 時に `_global_orders["battle_policy"] = "retreat"` と書き換えた後、
## このメソッドを呼んで全メンバーの個別指示を更新する。
func apply_battle_policy_preset(policy: String) -> void:
	for mv: Variant in _party_members:
		var ch := mv as Character
		if not is_instance_valid(ch) or ch.character_data == null:
			continue
		if ch.character_data.class_id == "healer":
			# ヒーラー専用プリセット：隊形=rear、戦闘=方針に対応、回復=lowest_hp_first
			var healer_combat: String = {"attack": "attack", "defense": "defense", "retreat": "flee"}.get(policy, "attack") as String
			ch.current_order["battle_formation"] = "rear"
			ch.current_order["combat"]           = healer_combat
			ch.current_order["heal"]             = "lowest_hp_first"
		else:
			var cid: String = ch.character_data.class_id
			var class_presets: Dictionary = OrderWindow.BATTLE_POLICY_PRESET.get(cid, {}) as Dictionary
			if class_presets.is_empty():
				continue
			var preset: Dictionary = class_presets.get(policy, {}) as Dictionary
			for pkey: String in preset:
				ch.current_order[pkey] = preset.get(pkey, "") as String


## デバッグ情報を収集して返す
func get_debug_info() -> Array:
	var result: Array = []
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai != null:
			result.append(unit_ai.get_debug_info())
	return result


# --------------------------------------------------------------------------
# ログ
# --------------------------------------------------------------------------

func _has_player_controlled_member() -> bool:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_player_controlled:
			return true
	return false


func _log_strategy_change(old_strategy: Strategy) -> void:
	if MessageLog == null:
		return
	var leader_name := _get_leader_name()
	var old_name := _strategy_to_preset_name(old_strategy)
	var new_name := _strategy_to_preset_name(_party_strategy)
	var reason := _get_strategy_change_reason()
	var text := "[AI] %s: %s→%s（%s）" % [leader_name, old_name, new_name, reason]
	var leader_pos := Vector2i(-1, -1)
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_leader:
			leader_pos = m.grid_pos
			break
	MessageLog.add_ai(text, leader_pos)


func _get_leader_name() -> String:
	for m: Character in _party_members:
		if is_instance_valid(m) and m.is_leader:
			var cname: String = m.character_data.character_name if m.character_data != null else ""
			if not cname.is_empty():
				return cname
			return m.character_data.character_id if m.character_data != null else String(m.name)
	for m: Character in _party_members:
		if is_instance_valid(m):
			var cname: String = m.character_data.character_name if m.character_data != null else ""
			if not cname.is_empty():
				return cname
			return m.character_data.character_id if m.character_data != null else String(m.name)
	return "不明"


func _strategy_to_preset_name(strat: Strategy) -> String:
	match strat:
		Strategy.ATTACK:     return "攻撃"
		Strategy.FLEE:       return "撤退"
		Strategy.WAIT:       return "待機"
		Strategy.DEFEND:     return "防衛"
		Strategy.EXPLORE:    return "探索"
		Strategy.GUARD_ROOM: return "帰還"
	return "不明"


func get_current_strategy_name() -> String:
	return _strategy_to_preset_name(_party_strategy)


## 表示用の全体指示ヒントを返す（PartyStatusWindow のヘッダー行用）
## 味方パーティー（Player / 合流済み NPC）：`_global_orders` の実値を返す
## 敵パーティー：`_global_orders` は空のままなので、呼出側（party_status_window.gd の
## 敵分岐）は move/battle_policy/target/on_low_hp/item_pickup キーを参照せず、
## 代わりに `_party_strategy` を直接表示する（docs/investigation_enemy_order_effective.md 参照）
## どちらのケースでも `combat_situation` / `power_balance` / 戦力内訳キーは必ず付与する
##
## 2026-04-21 改訂：旧実装は空の `_global_orders` に対して `_party_strategy` から仮想ラベル
## （`{"move": "cluster", "battle_policy": "attack", ...}`）を合成していたが、UnitAI 実動と
## 連動しない誤解を招く表示だったため廃止（詳細は docs/history.md の同日エントリ参照）
##
## 2026-04-23 改訂：サブクラス（NpcLeaderAI）での override を廃止し、テンプレートメソッドパターンに統一。
## 指示部分の差分は `_build_orders_part()` で override し、戦況付与部分は本関数内で共通処理する。
## これにより PartyStatusWindow で使うキー（hp_real / combat_ratio 等）の追加漏れが起きない
func get_global_orders_hint() -> Dictionary:
	var hint: Dictionary = _build_orders_part()
	# 戦況判断を流し込む（全パーティー共通）
	var sit: int = _combat_situation.get("situation", int(GlobalConstants.CombatSituation.SAFE)) as int
	hint["combat_situation"] = sit
	hint["power_balance"] = _combat_situation.get("power_balance", 0)
	# HP 内訳（デバッグ表示用・ポーション込み値の可視化）
	hint["hp_real"]       = _combat_situation.get("hp_real", 0)
	hint["hp_potion"]     = _combat_situation.get("hp_potion", 0)
	hint["hp_max"]        = _combat_situation.get("hp_max", 0)
	# 戦況比の内訳（デバッグ表示用・my_strength / enemy_strength）
	hint["my_combat_strength"] = _combat_situation.get("my_combat_strength", 0.0)
	hint["combat_ratio"]       = _combat_situation.get("combat_ratio", -1.0)
	# full_party / nearby_allied / nearby_enemy の 3 系統（PartyStatusWindow 表示用）
	hint["full_party_strength"]    = _combat_situation.get("full_party_strength", 0.0)
	hint["full_party_rank_sum"]    = _combat_situation.get("full_party_rank_sum", 0)
	hint["full_party_bonus_sum"]    = _combat_situation.get("full_party_bonus_sum", 0.0)
	hint["full_party_hp_ratio"]    = _combat_situation.get("full_party_hp_ratio", 0.0)
	hint["nearby_allied_strength"] = _combat_situation.get("nearby_allied_strength", 0.0)
	hint["nearby_allied_rank_sum"] = _combat_situation.get("nearby_allied_rank_sum", 0)
	hint["nearby_allied_bonus_sum"] = _combat_situation.get("nearby_allied_bonus_sum", 0.0)
	hint["nearby_allied_hp_ratio"] = _combat_situation.get("nearby_allied_hp_ratio", 0.0)
	hint["nearby_enemy_strength"]  = _combat_situation.get("nearby_enemy_strength", 0.0)
	hint["nearby_enemy_rank_sum"]  = _combat_situation.get("nearby_enemy_rank_sum", 0)
	hint["nearby_enemy_bonus_sum"]  = _combat_situation.get("nearby_enemy_bonus_sum", 0.0)
	hint["nearby_enemy_hp_ratio"]  = _combat_situation.get("nearby_enemy_hp_ratio", 0.0)
	return hint


## 指示部分のヒントを返す（サブクラスで override 可能）
## 基底：`_global_orders` の実値を返す（空なら空辞書）
## NpcLeaderAI：未設定時は NPC デフォルト値 + 探索モード判定を上書き
##
## 2026-04-23 改訂：サブクラスはこの関数だけ override すればよく、戦況キー追加漏れは起きない
func _build_orders_part() -> Dictionary:
	if not _global_orders.is_empty():
		return _global_orders.duplicate()
	return {}


func _get_strategy_change_reason() -> String:
	match _party_strategy:
		Strategy.ATTACK:     return "敵発見"
		Strategy.FLEE:       return "撤退判断"
		Strategy.WAIT:       return "待機"
		Strategy.DEFEND:     return "防衛"
		Strategy.EXPLORE:    return "探索開始"
		Strategy.GUARD_ROOM: return "縄張り外・帰還"
	return ""


# --------------------------------------------------------------------------
# 縄張り・追跡範囲チェック（敵パーティー専用）
# --------------------------------------------------------------------------

func _apply_range_check(base_strat: Strategy) -> Strategy:
	var first_member: Character = null
	for m: Character in _party_members:
		if is_instance_valid(m):
			first_member = m
			break
	if first_member == null or first_member.is_friendly:
		return base_strat
	if _party_strategy == Strategy.GUARD_ROOM:
		if base_strat == Strategy.FLEE:
			return Strategy.FLEE
		if _any_member_can_engage():
			return Strategy.ATTACK
		if _all_members_at_home():
			return Strategy.WAIT
		return Strategy.GUARD_ROOM
	if _party_strategy == Strategy.ATTACK and base_strat == Strategy.ATTACK:
		if _all_members_out_of_range():
			return Strategy.GUARD_ROOM
	return base_strat


func _all_members_out_of_range() -> bool:
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var cd := member.character_data
		if cd == null:
			continue
		var home := unit_ai.get_home_position()
		var dist_home := (member.grid_pos - home).length()
		if dist_home <= float(cd.territory_range):
			return false
		var target := _find_nearest_friendly(member)
		if target != null and is_instance_valid(target):
			var dist_target := (member.grid_pos - target.grid_pos).length()
			if dist_target <= float(cd.chase_range):
				return false
	return true


func _any_member_can_engage() -> bool:
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var cd := member.character_data
		if cd == null:
			continue
		var home := unit_ai.get_home_position()
		var dist_home := (member.grid_pos - home).length()
		if dist_home > float(cd.territory_range):
			continue
		var target := _find_nearest_friendly(member)
		if target != null and is_instance_valid(target):
			var dist_target := (member.grid_pos - target.grid_pos).length()
			if dist_target <= float(cd.chase_range):
				return true
	return false


func _all_members_at_home() -> bool:
	for member: Character in _party_members:
		if not is_instance_valid(member):
			continue
		var unit_ai := _unit_ais.get(member.name) as UnitAI
		if unit_ai == null:
			continue
		var home := unit_ai.get_home_position()
		var dx: int = abs(member.grid_pos.x - home.x)
		var dy: int = abs(member.grid_pos.y - home.y)
		if dx + dy > 2:
			return false
	return true


# --------------------------------------------------------------------------
# ヘルパー（サブクラスから使用）
# --------------------------------------------------------------------------

## 生存している友好キャラが1体以上いるか判定する
func _has_alive_friendly() -> bool:
	for f: Character in _friendly_list:
		if is_instance_valid(f) and f.hp > 0:
			return true
	return _player != null and is_instance_valid(_player) and _player.hp > 0


## 指定メンバーから最も近い生存友好キャラを返す（_player フォールバック付き）
func _find_nearest_friendly(member: Character) -> Character:
	var closest: Character = null
	var min_dist := INF
	for f: Character in _friendly_list:
		if not is_instance_valid(f) or f.hp <= 0:
			continue
		if f.current_floor != member.current_floor:
			continue
		var dist := float((f.grid_pos - member.grid_pos).length())
		if dist < min_dist:
			min_dist = dist
			closest = f
	if closest == null and is_instance_valid(_player) and _player.hp > 0 \
			and _player.current_floor == member.current_floor:
		return _player
	return closest


## 援護優先ターゲット選択
func _select_support_target(member: Character) -> Character:
	var weakest_ally: Character = null
	var min_ratio := 2.0
	for ally: Character in _party_members:
		if not is_instance_valid(ally) or ally.hp <= 0:
			continue
		if ally == member:
			continue
		var ratio := float(ally.hp) / float(maxi(ally.max_hp, 1))
		if ratio < min_ratio:
			min_ratio = ratio
			weakest_ally = ally
	if weakest_ally != null:
		return _select_target_for(weakest_ally)
	return _select_target_for(member)


# --------------------------------------------------------------------------
# サブクラスがオーバーライドするフック
# --------------------------------------------------------------------------

## メンバーに対応する UnitAI を生成する
func _create_unit_ai(_member: Character) -> UnitAI:
	return UnitAI.new()


## 探索時の移動方針を返す（NpcLeaderAI でオーバーライド）
func _get_explore_move_policy() -> String:
	return "explore"


## 現在の探索移動方針を外部に公開する
func get_explore_move_policy() -> String:
	return _get_explore_move_policy()


## パーティー全体の戦略を評価する（敵系サブクラスのみオーバーライド）
## 2026-04-21 改訂：味方（PartyLeaderPlayer / NpcLeaderAI）は override しない。
## _assign_orders() 側で `_is_enemy_party()` ガードにより味方では呼ばれない。
## 敵系サブクラス（EnemyLeaderAI / Goblin・Wolf）は従来どおり override する。
func _evaluate_party_strategy() -> Strategy:
	return Strategy.WAIT


## 探索モードか判定する（EXPLORE 相当・leader/follower で移動方針を分岐）
## 敵：`_party_strategy == EXPLORE` で判定（基底実装）
## NPC：敵検知フラグで override（NpcLeaderAI）
func _is_in_explore_mode() -> bool:
	return _party_strategy == Strategy.EXPLORE


## 縄張り帰還モードか判定する（GUARD_ROOM 相当・敵専用）
## 味方では常に false（味方は縄張り概念を持たない）
func _is_in_guard_room_mode() -> bool:
	return _party_strategy == Strategy.GUARD_ROOM


## リーダーの `_move_policy` を直接上書きする値を返す(敵 AI 用フック・2026-04-26 追加)
## 戻り値が "" のときは上書きせず、後続の `_is_in_explore_mode()` /
## `_is_in_guard_room_mode()` / 全体指示継承にフォールスルーする。
##
## 基底 `PartyLeader` は空文字を返す（味方では使用しない）。
## `EnemyLeaderAI` が override し、area_id ベースの縄張り判断（home_area_id /
## chase_range）でリーダーの個別判断結果（例：`"guard_room"`）を返す。
##
## 設計意図：将来 `_party_strategy` を廃止する際、`_is_in_guard_room_mode()` /
## `_is_in_explore_mode()` フックも一緒に削除する想定。本フックは `_party_strategy`
## と独立したリーダー個別判断経路として、敵の縄張り守備を実装する。
func _decide_leader_move_override() -> String:
	return ""


## リーダー本人のターゲット方針を上書きする値を返す（自己参照解消・2026-04-26 追加）
## 戻り値が非空のとき：リーダーの `tgt_policy` をその値で上書きする
## 戻り値が空のとき：上書きせず `current_order.target` をそのまま使う
##
## 基底 `PartyLeader` は空文字を返す（純粋 PartyLeader を直接使うパスはないが、
## 派生で override 漏れがあった場合は素の `current_order.target` 経由になる）。
## `PartyLeaderPlayer` / `PartyLeaderAI` がそれぞれ "nearest" を返し、味方・敵の
## 既定挙動とする。種族固有 AI（EnemyLeaderAI 派生）は必要に応じて再 override する
## （4/26 の `_decide_leader_move_override()` と同じ拡張パターン）。
##
## 設計意図：リーダー本人に `target = "same_as_leader"` が割り当たると自己参照
## （precomputation 経路に依存して silently nearest 相当に落ちる未定義経路）に
## なるため、明示的に方針を上書きする。`_global_orders.target` のリーダー継承を
## 廃止する形で `_move_policy` の per-member 決定ロジック統一（4/26）と同じ思想に揃える。
func _decide_leader_target_policy_override() -> String:
	return ""


## このパーティーが敵パーティーかを判定する（先頭生存メンバーの is_friendly で判別）
## メンバー全員死亡時は false（戦略評価対象外）
func _is_enemy_party() -> bool:
	for m: Character in _party_members:
		if is_instance_valid(m):
			return not m.is_friendly
	return false


## 指定メンバーの攻撃ターゲットを選択する（サブクラスがオーバーライド）
func _select_target_for(_member: Character) -> Character:
	return _player


## UnitAI から呼び出せる target 選定の公開ラッパー（2026-04-26 追加）
##
## 用途：UnitAI.receive_order() で `_order["target"]` が freed/null になった
## ATTACK 状態のとき、即時再選定するためのコールバック経路。
##
## 経緯：target 死亡 → attack キュー消化 → キュー空 → receive_order(_order)
## 再発火 で stale な target を null として受け取り、`_generate_queue` の
## `target == null` 経路で `_generate_move_queue` → "explore" に流れて
## 同部屋の他の敵を素通りしてリーダーが部屋を出る現象が起きていた
## （PartyLeader._assign_orders の次サイクル = 最大 1.5 秒の窓）。
##
## 内部実装は `_select_target_for`（サブクラスで override 可能・基底 / NPC /
## 敵 / プレイヤーで個別実装）に委譲する。
func select_target_for(member: Character) -> Character:
	return _select_target_for(member)


## 最もHPが少ない攻撃ターゲットを選択する
func _select_weakest_target(member: Character) -> Character:
	return _select_target_for(member)


## キャラクターの装備 bonus 段階合計の平均を返す（装備なしなら 0.0）
## 対象: equipped_weapon / equipped_armor / equipped_shield のうち実装備のみ
## 各アイテムの bonuses（各ステータスの 0/1/2/3 段階）の合計を求め、装備本数で割る
##   設計意図：剣士（剣+盾の 2 装備）と魔法使い（杖のみ 1 装備）でクラス間の装備寄与をフラットにするため
## 各アイテムに bonuses フィールドがない場合は 0 扱い（セーブデータ互換・敵は装備を持たない）
func _character_bonus_sum_avg(m: Character) -> float:
	if m.character_data == null:
		return 0.0
	var total_bonus := 0
	var equipped_count := 0
	var slots := [
		m.character_data.equipped_weapon,
		m.character_data.equipped_armor,
		m.character_data.equipped_shield,
	]
	for it_v: Variant in slots:
		var it := it_v as Dictionary
		if it.is_empty():
			continue
		var bonuses := it.get("bonuses", {}) as Dictionary
		for v: Variant in bonuses.values():
			total_bonus += int(v)
		equipped_count += 1
	if equipped_count <= 0:
		return 0.0
	return float(total_bonus) / float(equipped_count)


## 状態ラベルからHP割合を推定する（敵の戦力を過大評価する安全側に倒す）
## 各ラベルの閾値範囲の最大値（その状態に「なる直前」のHP率）を返す
func _estimate_hp_ratio_from_condition(condition: String) -> float:
	match condition:
		"healthy":  return 1.0
		"wounded":  return GlobalConstants.CONDITION_WOUNDED_THRESHOLD
		"injured":  return GlobalConstants.CONDITION_INJURED_THRESHOLD
		"critical": return GlobalConstants.CONDITION_CRITICAL_THRESHOLD
		_:          return 1.0  # 不明な値 → 安全側（敵を強く見積もる）


## メンバーが所持しているヒールポーションの合計回復量を返す
func _calc_total_potion_hp(member: Character) -> int:
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


## メンバーリストの統計（rank_sum / bonus_sum / hp_ratio / strength）を返す
## use_estimated_hp = false: 実 HP + ポーション回復量
## use_estimated_hp = true:  状態ラベル（condition）からHP%を推定（敵ステータス直接参照禁止ルール）
## 戻り値: { "rank_sum": int, "bonus_sum": float, "hp_ratio": float, "strength": float, "alive_count": int }
##   rank_sum = Σ(RANK_BASE_OFFSET + RANK_VALUE[rank])  ← C=+0, B=+1, A=+2, S=+3
##   bonus_sum = Σ(member の装備 bonus 段階合計の平均)  ← 装備本数差をクラス間でフラットに吸収
##   strength = (rank_sum + bonus_sum × ITEM_BONUS_STRENGTH_WEIGHT) × avg_hp_ratio
func _calc_stats(members: Array, use_estimated_hp: bool) -> Dictionary:
	var rank_sum := 0
	var bonus_sum := 0.0
	var hp_ratio_sum := 0.0
	var alive_count := 0
	for mv: Variant in members:
		# freed オブジェクトへの as キャストはクラッシュするため、キャスト前に is_instance_valid を確認する
		if not is_instance_valid(mv):
			continue
		var m := mv as Character
		if m == null or m.hp <= 0:
			continue
		if m.character_data != null:
			rank_sum += GlobalConstants.RANK_BASE_OFFSET + (CharacterGenerator.RANK_VALUE.get(m.character_data.rank, 0) as int)
			bonus_sum += _character_bonus_sum_avg(m)
		alive_count += 1
		if use_estimated_hp:
			hp_ratio_sum += _estimate_hp_ratio_from_condition(m.get_condition())
		else:
			var total_max := m.max_hp
			if total_max <= 0:
				continue
			var cur := m.hp + _calc_total_potion_hp(m)
			hp_ratio_sum += clampf(float(cur) / float(total_max), 0.0, 1.0)
	if alive_count <= 0:
		return {"rank_sum": 0, "bonus_sum": 0.0, "hp_ratio": 0.0, "strength": 0.0, "alive_count": 0}
	var avg_hp_ratio := hp_ratio_sum / float(alive_count)
	var base := float(rank_sum) + bonus_sum * GlobalConstants.ITEM_BONUS_STRENGTH_WEIGHT
	return {
		"rank_sum":    rank_sum,
		"bonus_sum":   bonus_sum,
		"hp_ratio":    avg_hp_ratio,
		"strength":    base * avg_hp_ratio,
		"alive_count": alive_count,
	}


## 自パ（実 HP）と同陣営他パ（推定 HP）を混ぜた統計を返す
## 自パ部分は apply_initial_items で自分の inventory・max_hp を把握できるためポーション込み実 HP を使用
## 他パ部分はポーション所持を把握できないので condition ラベルからの推定 HP を使用
func _calc_stats_mixed(self_members: Array, other_members: Array) -> Dictionary:
	var self_stats := _calc_stats(self_members, false)
	var other_stats := _calc_stats(other_members, true)
	var rank_sum: int = int(self_stats.rank_sum) + int(other_stats.rank_sum)
	var bonus_sum: float = float(self_stats.bonus_sum) + float(other_stats.bonus_sum)
	var alive: int = int(self_stats.alive_count) + int(other_stats.alive_count)
	var avg_hp_ratio: float = 0.0
	if alive > 0:
		# HP 率は生存メンバー加重平均（rank_sum 側を重みにしない）
		avg_hp_ratio = (float(self_stats.hp_ratio) * float(self_stats.alive_count)
				+ float(other_stats.hp_ratio) * float(other_stats.alive_count)) / float(alive)
	var base := float(rank_sum) + bonus_sum * GlobalConstants.ITEM_BONUS_STRENGTH_WEIGHT
	return {
		"rank_sum":    rank_sum,
		"bonus_sum":   bonus_sum,
		"hp_ratio":    avg_hp_ratio,
		"strength":    base * avg_hp_ratio,
		"alive_count": alive,
	}


## 距離フィルタ（マンハッタン距離・同フロアのみ）
## center_pos / my_floor: 自パリーダーの位置情報
## radius: GlobalConstants.COALITION_RADIUS_TILES
func _within_coalition_radius(c: Character, center_pos: Vector2i, my_floor: int, radius: int) -> bool:
	if my_floor >= 0 and c.current_floor != my_floor:
		return false
	var d := absi(c.grid_pos.x - center_pos.x) + absi(c.grid_pos.y - center_pos.y)
	return d <= radius


## 統合戦略ステータス評価（戦力計算 + 戦況判断）
## 3 種類のメンバー集合で統計を算出する（エリアベース target_areas 判定は廃止）:
##   - full_party:     自パ全員（下層判定用・絶対戦力）
##   - nearby_allied:  自パ近接 + 同陣営他パ近接（戦況判断用・味方連合）
##   - nearby_enemy:   近接敵（戦況判断用）
## 距離基準: 自パリーダーのグリッド座標から COALITION_RADIUS_TILES マス以内（マンハッタン）
## 敵の非対称設計: enemy パーティーの自軍戦力は full_party のみ（協力しない世界観）
##                味方（player/npc）の自軍戦力は nearby_allied（連合）
## 結果は _assign_orders() → receive_order() の combat_situation フィールドに含めてメンバーに伝達する
func _evaluate_strategic_status() -> Dictionary:
	var radius: int = GlobalConstants.COALITION_RADIUS_TILES

	# 自パリーダー基準点（先頭の生存者）
	var leader_pos := Vector2i.ZERO
	var my_floor := -1
	var is_enemy_party := false
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			leader_pos = m.grid_pos
			my_floor = m.current_floor
			is_enemy_party = not m.is_friendly
			break

	# ==================== full_party（自パ全員） ====================
	var full_party: Array[Character] = []
	for m: Character in _party_members:
		if is_instance_valid(m) and m.hp > 0:
			full_party.append(m)

	# ==================== nearby_allied（自パ近接 + 同陣営他パ近接） ====================
	# 自パ側: _get_my_combat_members() を使う（プレイヤーは合流済み NPC を含む）
	var my_members := _get_my_combat_members()
	var nearby_allied_self: Array[Character] = []
	for m: Character in my_members:
		if not is_instance_valid(m) or m.hp <= 0:
			continue
		if _within_coalition_radius(m, leader_pos, my_floor, radius):
			nearby_allied_self.append(m)

	# 同陣営他パ: _all_members から my_members を除いた同陣営キャラを半径内で収集
	# 陣営判定は先に算出した is_enemy_party を使う（is_friendly = not is_enemy_party）
	# 直前ループで is_instance_valid 済みの生存者から導出しているため freed アクセスの心配なし
	var my_faction: bool = not is_enemy_party
	var nearby_allied_others: Array[Character] = []
	for c: Character in _all_members:
		if not is_instance_valid(c) or c.hp <= 0:
			continue
		if c.is_friendly != my_faction:
			continue
		if my_members.has(c):
			continue  # 既に nearby_allied_self でカウント候補
		if _within_coalition_radius(c, leader_pos, my_floor, radius):
			nearby_allied_others.append(c)

	# ==================== nearby_enemy（近接敵） ====================
	var nearby_enemy: Array[Character] = []
	for opp: Character in _get_opposing_characters():
		if not is_instance_valid(opp) or opp.hp <= 0:
			continue
		if _within_coalition_radius(opp, leader_pos, my_floor, radius):
			nearby_enemy.append(opp)

	# ==================== 統計計算（各集合で 1 回ずつ） ====================
	var full_stats := _calc_stats(full_party, false)
	var nearby_allied_stats := _calc_stats_mixed(nearby_allied_self, nearby_allied_others)
	var nearby_enemy_stats := _calc_stats(nearby_enemy, true)

	# ==================== 敵の非対称設計 ====================
	# 敵パーティー: 自軍戦力 = full_party（協力しない）
	# 味方（player/npc）: 自軍戦力 = nearby_allied（連合）
	var my_combat_strength: float
	var my_combat_rank_sum: int
	if is_enemy_party:
		my_combat_strength = float(full_stats.strength)
		my_combat_rank_sum = int(full_stats.rank_sum)
	else:
		my_combat_strength = float(nearby_allied_stats.strength)
		my_combat_rank_sum = int(nearby_allied_stats.rank_sum)

	# ==================== 戦況判断 ====================
	# HP 充足率は自パーティーのみで算出（他パーティーのポーション所持は把握不可）
	var hp_breakdown := _calc_hp_breakdown_for(_party_members)

	var situation: int
	var power_balance: int
	var combat_ratio: float = -1.0  # デバッグ表示用（敵なし or enemy_s=0 のとき -1）
	if nearby_enemy.is_empty():
		situation = int(GlobalConstants.CombatSituation.SAFE)
		power_balance = int(GlobalConstants.PowerBalance.OVERWHELMING)
	else:
		# 戦力比（strength 比）で situation を分類
		var enemy_s: float = float(nearby_enemy_stats.strength)
		if enemy_s <= 0.0:
			situation = int(GlobalConstants.CombatSituation.SAFE)
		else:
			var ratio := my_combat_strength / enemy_s
			combat_ratio = ratio
			if ratio >= GlobalConstants.COMBAT_RATIO_OVERWHELMING:
				situation = int(GlobalConstants.CombatSituation.OVERWHELMING)
			elif ratio >= GlobalConstants.COMBAT_RATIO_ADVANTAGE:
				situation = int(GlobalConstants.CombatSituation.ADVANTAGE)
			elif ratio >= GlobalConstants.COMBAT_RATIO_EVEN:
				situation = int(GlobalConstants.CombatSituation.EVEN)
			elif ratio >= GlobalConstants.COMBAT_RATIO_DISADVANTAGE:
				situation = int(GlobalConstants.CombatSituation.DISADVANTAGE)
			else:
				situation = int(GlobalConstants.CombatSituation.CRITICAL)
		# 戦力比（ランク和のみ）で power_balance を分類
		var enemy_rank: int = int(nearby_enemy_stats.rank_sum)
		if enemy_rank <= 0:
			power_balance = int(GlobalConstants.PowerBalance.OVERWHELMING)
		else:
			var rank_ratio := float(my_combat_rank_sum) / float(enemy_rank)
			if rank_ratio >= GlobalConstants.POWER_BALANCE_OVERWHELMING:
				power_balance = int(GlobalConstants.PowerBalance.OVERWHELMING)
			elif rank_ratio >= GlobalConstants.POWER_BALANCE_SUPERIOR:
				power_balance = int(GlobalConstants.PowerBalance.SUPERIOR)
			elif rank_ratio >= GlobalConstants.POWER_BALANCE_EVEN:
				power_balance = int(GlobalConstants.PowerBalance.EVEN)
			elif rank_ratio >= GlobalConstants.POWER_BALANCE_INFERIOR:
				power_balance = int(GlobalConstants.PowerBalance.INFERIOR)
			else:
				power_balance = int(GlobalConstants.PowerBalance.DESPERATE)

	return {
		# 戦況判断結果
		"situation":      situation,
		"power_balance":  power_balance,

		# HP 充足率の内訳（デバッグ表示用・ポーション込みの値を可視化）
		"hp_real":        int(hp_breakdown.get("hp", 0)),
		"hp_potion":      int(hp_breakdown.get("potion", 0)),
		"hp_max":         int(hp_breakdown.get("max", 0)),

		# 戦況判定に使った戦力比の内訳（デバッグ表示用・my_strength / enemy_strength）
		"my_combat_strength": my_combat_strength,
		"combat_ratio":       combat_ratio,

		# full_party（自パ全員・下層判定用・絶対戦力）
		"full_party_strength":  float(full_stats.strength),
		"full_party_rank_sum":  int(full_stats.rank_sum),
		"full_party_bonus_sum": float(full_stats.bonus_sum),
		"full_party_hp_ratio":  float(full_stats.hp_ratio),

		# nearby_allied（自パ近接 + 同陣営他パ近接・連合戦力）
		"nearby_allied_strength":  float(nearby_allied_stats.strength),
		"nearby_allied_rank_sum":  int(nearby_allied_stats.rank_sum),
		"nearby_allied_bonus_sum": float(nearby_allied_stats.bonus_sum),
		"nearby_allied_hp_ratio":  float(nearby_allied_stats.hp_ratio),

		# nearby_enemy（近接敵）
		"nearby_enemy_strength":  float(nearby_enemy_stats.strength),
		"nearby_enemy_rank_sum":  int(nearby_enemy_stats.rank_sum),
		"nearby_enemy_bonus_sum": float(nearby_enemy_stats.bonus_sum),
		"nearby_enemy_hp_ratio":  float(nearby_enemy_stats.hp_ratio),
	}


## 自軍として扱うメンバー一覧を返す（戦況判断用）
## _party_ref が設定されている場合（プレイヤー・合流済みNPCパーティー）は Party.sorted_members() を使う
## 未設定の場合（敵・未合流NPC）は _party_members のみ
func _get_my_combat_members() -> Array[Character]:
	if _party_ref == null:
		return _party_members
	var result: Array[Character] = []
	for mv: Variant in _party_ref.sorted_members():
		# freed オブジェクトへの as キャストはクラッシュするため、キャスト前に is_instance_valid を確認する
		if not is_instance_valid(mv):
			continue
		var m := mv as Character
		if m != null:
			result.append(m)
	return result




## 指定メンバーリストの HP 充足率の内訳を返す（PartyStatusWindow 表示用・ポーション込み）
## 戻り値: { "hp": int, "potion": int, "max": int }
## 2026-04-25：HpStatus enum 廃止に伴い "status" キーを削除（呼出側は hp/potion/max のみ参照）
func _calc_hp_breakdown_for(members: Array) -> Dictionary:
	var total_hp := 0
	var total_max := 0
	var total_potion := 0
	for mv: Variant in members:
		# freed オブジェクトへの as キャストはクラッシュするため、キャスト前に is_instance_valid を確認する
		if not is_instance_valid(mv):
			continue
		var m := mv as Character
		if m == null or m.hp <= 0:
			continue
		total_hp += m.hp
		total_max += m.max_hp
		total_potion += _calc_total_potion_hp(m)
	return {"hp": total_hp, "potion": total_potion, "max": total_max}


## 対立するキャラクターのリストを返す（サブクラスでオーバーライド）
## 敵 AI: _friendly_list（プレイヤー・NPC）
## 味方 AI: _enemy_list（敵キャラ）
func _get_opposing_characters() -> Array[Character]:
	return _friendly_list
