class_name EnemyLeaderAI
extends PartyLeaderAI

## 敵リーダーAI基底クラス
## 全敵種族の共通デフォルト行動を定義する。種族固有の行動はサブクラスでオーバーライドする。
##
## デフォルト戦略判断:
##   ATTACK: friendly（プレイヤー・NPC）が生存している
##   WAIT  : friendly がいない
##   FLEE  : なし（デフォルトでは逃げない。種族サブクラスが必要に応じて追加）
##
## 種族固有リーダーAI（GoblinLeaderAI 等）は本クラスを継承し、差分のみオーバーライドする。
## 種族固有の行動が不要な敵（dark-knight, salamander 等）は本クラスをそのまま使用する。


## 縄張り部屋 ID（2026-04-26 追加・area_id ベース GUARD_ROOM の根拠）
## 初代リーダーのスポーン位置の area_id を保持する。リーダー交代があっても
## 維持する（縄張りはパーティー単位で固定）。空文字の場合は縄張り判断不可
## （通路スポーン等）として `_decide_leader_move_override()` は "" を返す。
var _home_area_id: String = ""


## セットアップ時に縄張り部屋 ID を確定する（基底のロジックは super で実行）
func setup(members: Array[Character], player: Character, map_data: MapData,
		all_members: Array[Character]) -> void:
	super.setup(members, player, map_data, all_members)
	if map_data == null:
		return
	var leader: Character = _get_first_alive_leader()
	if leader == null:
		return
	_home_area_id = map_data.get_area(leader.grid_pos)


## メンバーの character_id に応じた UnitAI を生成する
func _create_unit_ai(member: Character) -> UnitAI:
	var cid := member.character_data.character_id if member.character_data != null else ""
	match cid:
		"goblin-archer": return GoblinArcherUnitAI.new()
		"goblin-mage":   return GoblinMageUnitAI.new()
		"zombie":        return ZombieUnitAI.new()
		"harpy":         return HarpyUnitAI.new()
		"salamander":    return SalamanderUnitAI.new()
		"dark-knight":   return DarkKnightUnitAI.new()
		"dark-mage":     return DarkMageUnitAI.new()
		"dark_priest", "dark-priest": return DarkPriestUnitAI.new()
		"lich":          return LichUnitAI.new()
		"demon":         return DarkMageUnitAI.new()  ## デーモン: 魔法遠距離（雷）はDarkMageAIと同等
		"dark-lord":     return DarkLordUnitAI.new()
		"skeleton-archer": return GoblinArcherUnitAI.new()  ## スケルトンアーチャー: 後退維持
	return UnitAI.new()


## パーティー全体の戦略を評価する
## friendly が生存していれば ATTACK、いなければ WAIT。FLEE はしない。
## 種族サブクラスは super._evaluate_party_strategy() を呼んでから FLEE 条件を追加できる。
func _evaluate_party_strategy() -> Strategy:
	if _has_alive_friendly():
		return Strategy.ATTACK
	return Strategy.WAIT


## 攻撃ターゲット: 最近傍の friendly キャラ
func _select_target_for(member: Character) -> Character:
	return _find_nearest_friendly(member)


## 敵パーティーの指示部分ヒントを返す（ベースライン："follow"）
## 種族固有ルーチンが上書きしない場合の素の挙動を「リーダー追従」とする。
## NpcLeaderAI._build_orders_part() と同じ baseline + _global_orders マージ方式。
## 派生 EnemyLeaderAI（種族固有 AI）は本関数を super 呼び出しで継承する想定。
func _build_orders_part() -> Dictionary:
	var hint: Dictionary = {"move": "follow"}
	for k: Variant in _global_orders.keys():
		hint[k] = _global_orders[k]
	return hint


## リーダーの `_move_policy` 上書き値を返す（area_id ベース GUARD_ROOM 判定・2026-04-26 追加）
##
## 戻り値が `"guard_room"`：リーダーの移動方針を「部屋を守る」に上書き
## 戻り値が `""`：上書きせず、後続フック（`_is_in_explore_mode` 等）にフォールスルー
##
## 発火条件（全て満たすと `"guard_room"` を返す）：
##   1. リーダーが縄張り部屋（`_home_area_id`）にいる
##   2. 縄張り部屋内に敵（friendly）がいない
##   3. リーダーから `chase_range`（マンハッタン距離）内に敵がいない
##
## 設計意図：
##   - 部屋単位（area_id）で縄張りを表現することで、`territory_range` の数値半径による
##     不安定な判定を回避する
##   - リーダーの個別判断結果を直接 `_move_policy` に反映し、`_party_strategy.GUARD_ROOM`
##     を経由しない（将来の `_party_strategy` 廃止と分離可能にする）
##   - 非リーダーは触らない（`_global_orders.move` 継承 → リーダー追従。リーダーが部屋を
##     守れば自然と部屋に集まり、追えば追従する）
func _decide_leader_move_override() -> String:
	if _home_area_id.is_empty():
		return ""
	if _map_data == null:
		return ""
	var leader: Character = _get_first_alive_leader()
	if leader == null:
		return ""
	# 1. リーダーが縄張り部屋にいるか
	var leader_area_id: String = _map_data.get_area(leader.grid_pos)
	if leader_area_id != _home_area_id:
		return ""  # 縄張り外 → 追跡中扱い
	# 2. 縄張り部屋内に敵がいるか（同フロアの friendly のみ確認）
	for fv: Character in _friendly_list:
		if not is_instance_valid(fv) or fv.hp <= 0:
			continue
		if fv.current_floor != leader.current_floor:
			continue
		if _map_data.get_area(fv.grid_pos) == _home_area_id:
			return ""  # 部屋内に敵あり → 戦う
	# 3. chase_range 内に敵がいるか（マンハッタン距離・同フロア）
	var chase_range: int = 0
	if leader.character_data != null:
		chase_range = leader.character_data.chase_range
	for fv: Character in _friendly_list:
		if not is_instance_valid(fv) or fv.hp <= 0:
			continue
		if fv.current_floor != leader.current_floor:
			continue
		var d: int = absi(fv.grid_pos.x - leader.grid_pos.x) \
				+ absi(fv.grid_pos.y - leader.grid_pos.y)
		if d <= chase_range:
			return ""  # chase 内 → 追う
	return "guard_room"
