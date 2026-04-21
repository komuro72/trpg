## パーティー状態ウィンドウ（F1キーで表示/非表示トグル）
## 現在フロアの全パーティー状態をリアルタイム表示（0.2秒ごと再描画）
## 上下キーでリーダー選択（カメラ追跡）・F3 で無敵化トグル
##
## 戦力表示の凡例：`PB F(R+T)s C(R+T)s E(R+T)s`
##   PB = PowerBalance（優劣ラベル・nearby_allied vs nearby_enemy のランク比）
##   F  = full_party（自パのみ・下層判定用絶対戦力）
##   C  = nearby_allied（自パ近接 + 同陣営他パ近接・戦況判断の味方連合）
##   E  = nearby_enemy（近接敵・戦況判断の敵）
##   各括弧内: R=rank_sum / T=tier 平均の和 / 末尾 s=strength（= (R + T×WEIGHT) × HP率）
##   敵パーティー視点では F と C は同値（協力しない世界観）
##   範囲: 自パリーダーからマンハッタン距離 COALITION_RADIUS_TILES マス以内

class_name PartyStatusWindow
extends CanvasLayer

const FS:       int   = 12        ## フォントサイズ
const HDR_FS:   int   = 14        ## ヘッダー用フォントサイズ
const LINE_H:   float = 15.0      ## 1行の高さ
const PAD:      float = 8.0       ## 外側パディング
const INDENT:   float = 14.0      ## メンバー行インデント

## 参照（game_map から setup() で設定）
var _party:               Party     = null
var _get_enemy_managers:  Callable           ## () -> Array
var _get_npc_managers:    Callable           ## () -> Array
var _get_floor:           Callable           ## () -> int
var _get_map_data:        Callable           ## () -> MapData
var _hero:                Character = null
var _hero_manager:        PartyManager = null  ## プレイヤーパーティーの戦況表示用

var _control:       Control
var _redraw_timer:  float = 0.0
const REDRAW_INTERVAL: float = 0.20  ## パーティー状態の再描画間隔（秒）

## リーダー選択
var _selected_leader: Character = null  ## 選択中のリーダーキャラ（null=未選択）
var _leader_list: Array = []            ## 描画順のリーダーキャラ一覧（毎描画フレームで更新）

## 詳細度レベル（F3 で循環・セッション内のみ保持）
## 0 = 高のみ（1 行/メンバー）
## 1 = 高+中（2 行/メンバー：行動ライン + 指示ライン）
## 2 = 高+中+低（3 行/メンバー：行動ライン + 指示ライン + フラグライン）
var _detail_level: int = 0

## 変数名 → 優先度レベル（0=高 / 1=中 / 2=低）のマッピング（単一の真実源）
## 詳細度レベルと照合して表示有無を決める。新変数の追加・優先度変更はここだけ触る。
## キー名は Logger / duck typing で参照するので `_` プレフィックスなし
const VAR_PRIORITY: Dictionary = {
	# リーダー行（パーティー全体情報）
	"reeval_timer":              1,  # 中：次の戦略再評価まで残秒
	"visited_areas_size":        1,  # 中：訪問済みエリア数
	"was_refused":               2,  # 低：NPC 会話で断られたフラグ（恒久）
	"has_fought_together":       2,  # 低：共闘実績（合流スコア加点）
	"has_been_healed":           2,  # 低：回復実績（合流スコア加点）
	"joined_to_player":          2,  # 低：プレイヤー合流済み
	"suppress_floor_navigation": 2,  # 低：フロア遷移判定スキップ

	# UnitAI 行動ライン（高）
	"state":                     0,  # 高：ステートマシン現在値
	"timer":                     0,  # 高：ステートタイマー残秒
	"queue_len":                 0,  # 高：アクションキュー長
	"attack_target":             0,  # 高：確定攻撃対象
	"goal_str":                  0,  # 高：get_debug_goal_str の出力

	# UnitAI 指示ライン（中）
	"move_policy":               1,  # 中：移動方針
	"combat":                    1,  # 中：戦闘方針
	"battle_formation":          1,  # 中：戦闘隊形
	"on_low_hp":                 1,  # 中：低HP時行動
	"special_skill":             1,  # 中：特殊攻撃指示
	"hp_potion":                 1,  # 中：HP ポーション自動使用
	"sp_mp_potion":              1,  # 中：エナジーポーション自動使用
	"item_pickup":               1,  # 中：アイテム取得指示

	# UnitAI フラグライン（低）
	"party_fleeing":             2,  # 低：パーティー撤退中
	"floor_following":           2,  # 低：フロア追従中
	"warp_timer":                2,  # 低：DarkLord 固有・次ワープまで残秒

	# 敵固有・動的判断（中）※ 2026-04-21 追加
	"should_self_flee":          1,  # 中：ゴブリン系 HP 低下時の自己逃走判定
	"can_attack":                1,  # 中：魔法系の MP 不足による攻撃不可判定
	"lich_water":                1,  # 中：Lich 次攻撃の水/火フラグ（攻撃ごとに切替。2026-04-21 に 低 → 中 に再分類）

	# 敵固有・静的属性（低）※ 2026-04-21 追加
	"should_ignore_flee":        2,  # 低：DarkKnight / Zombie 等の「逃走指示を無視」フラグ
	"is_undead":                 2,  # 低：アンデッド属性（Skeleton / Lich 等）
	"is_flying":                 2,  # 低：飛行属性（Harpy / Demon / DarkLord）
	"instant_death_immune":      2,  # 低：即死耐性（ボス級）
	"projectile_type":           2,  # 低：飛翔体種別（空文字列は省略）
	"chase_range":               2,  # 低：追跡範囲（タイル）
	"territory_range":           2,  # 低：縄張り範囲（タイル）

	# Character 行動ライン（高）
	"energy":                    0,  # 高：エネルギー（MP/SP 表示の分子）
	# Character フラグライン（低）※ 2026-04-21 に 中→低 で再分類したもの群
	"max_energy":                2,  # 低：エネルギー分母（不変）
	"power":                     2,  # 低：最終威力（装備変更時のみ変化）
	"attack_range":              2,  # 低：射程（装備補正込み・ほぼ不変）
	"is_friendly":               2,  # 低：陣営（不変）※色分けで可視化済のため重要度低
	"is_leader":                 2,  # 低：リーダー（不変）※ ▶ マーカーで可視化済
}


## 指定変数を現在の詳細度レベルで表示すべきか返す
## 未登録の変数は「高」扱い（常に表示）とする
func _show_var(var_name: String) -> bool:
	var pri: int = VAR_PRIORITY.get(var_name, 0)
	return pri <= _detail_level


## リーダー選択が変わったとき発火（game_map がカメラを切り替えるために購読）
signal leader_selected(leader: Character)


func _ready() -> void:
	layer = 15
	visible = false
	process_mode = PROCESS_MODE_ALWAYS

	_control = Control.new()
	_control.name = "PartyStatusPanel"
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control.draw.connect(_on_draw)
	add_child(_control)


## game_map から呼ぶ。Callable を渡すことで常に最新のフロアデータを参照できる
func setup(p_party: Party, get_enemy_managers: Callable, get_npc_managers: Callable,
		get_floor: Callable, get_map_data: Callable, p_hero: Character,
		p_hero_manager: PartyManager = null) -> void:
	_party              = p_party
	_get_enemy_managers = get_enemy_managers
	_get_npc_managers   = get_npc_managers
	_get_floor          = get_floor
	_get_map_data       = get_map_data
	_hero               = p_hero
	_hero_manager       = p_hero_manager


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key: int = (event as InputEventKey).physical_keycode
		if key == KEY_UP:
			_navigate_selection(-1)
			get_viewport().set_input_as_handled()
		elif key == KEY_DOWN:
			_navigate_selection(1)
			get_viewport().set_input_as_handled()
		elif key == KEY_F3:
			_cycle_detail_level()
			get_viewport().set_input_as_handled()
		elif key == KEY_F6:
			_toggle_godmode()
			get_viewport().set_input_as_handled()


## F3: 詳細度レベルを 3 ステート（高のみ → 高+中 → 高+中+低 → 高のみ …）で循環
## セッション内のみ保持・ゲーム再起動で「高のみ」にリセット（_detail_level 初期値で実現）
func _cycle_detail_level() -> void:
	_detail_level = (_detail_level + 1) % 3
	_control.queue_redraw()


## F6: 選択中リーダーのパーティーメンバー全員を無敵化（HP/MP/SP を最大値の10倍に設定）
## 再度押すと元に戻す（max 値に戻す）。2026-04-21 に F3 から F6 に移動（F3 は詳細度トグルに割り当て）
func _toggle_godmode() -> void:
	if _selected_leader == null:
		print("[DEBUG] 無敵化: リーダー未選択")
		return
	# 選択中リーダーの PartyManager を探す
	var target_pm: PartyManager = null
	for pm_v: Variant in _get_enemy_managers.call():
		var pm := pm_v as PartyManager
		if is_instance_valid(pm):
			for m: Character in pm.get_members():
				if m == _selected_leader:
					target_pm = pm
					break
		if target_pm != null:
			break
	if target_pm == null:
		for pm_v: Variant in _get_npc_managers.call():
			var pm := pm_v as PartyManager
			if is_instance_valid(pm):
				for m: Character in pm.get_members():
					if m == _selected_leader:
						target_pm = pm
						break
			if target_pm != null:
				break
	# プレイヤーパーティーの場合
	if target_pm == null and _party != null:
		for mv: Variant in _party.members:
			var ch := mv as Character
			if is_instance_valid(ch) and ch == _selected_leader:
				# プレイヤーパーティー全員に適用
				var godmode := ch.hp <= ch.max_hp  # 現在通常 → 無敵化
				for mv2: Variant in _party.members:
					var ch2 := mv2 as Character
					if is_instance_valid(ch2):
						_apply_godmode(ch2, godmode)
				print("[DEBUG] 無敵化 %s: %s（パーティー全員）" % ["ON" if godmode else "OFF", _selected_leader.character_data.character_name if _selected_leader.character_data != null else "?"])
				return

	if target_pm == null:
		print("[DEBUG] 無敵化: パーティー未発見")
		return

	var members := target_pm.get_members()
	if members.is_empty():
		return
	var godmode := members[0].hp <= members[0].max_hp  # 現在通常 → 無敵化
	for m: Character in members:
		if is_instance_valid(m):
			_apply_godmode(m, godmode)
	var leader_name := _selected_leader.character_data.character_name if _selected_leader.character_data != null else "?"
	print("[DEBUG] 無敵化 %s: %s（%d人）" % ["ON" if godmode else "OFF", leader_name, members.size()])


func _apply_godmode(ch: Character, on: bool) -> void:
	if on:
		ch.hp = ch.max_hp * 10
		if ch.max_energy > 0:
			ch.energy = ch.max_energy * 10
	else:
		ch.hp = mini(ch.hp, ch.max_hp)
		if ch.max_energy > 0:
			ch.energy = mini(ch.energy, ch.max_energy)


## リーダー一覧内でカーソルを移動する。_leader_list は前回の描画で構築済み
func _navigate_selection(dir: int) -> void:
	# freed なエントリを除去
	_leader_list = _leader_list.filter(func(c: Variant) -> bool:
		return c != null and is_instance_valid(c))
	if _leader_list.is_empty():
		return
	var idx: int = _leader_list.find(_selected_leader)
	if idx < 0:
		idx = 0 if dir > 0 else _leader_list.size() - 1
	else:
		idx = (idx + dir + _leader_list.size()) % _leader_list.size()
	_selected_leader = _leader_list[idx] as Character
	leader_selected.emit(_selected_leader)
	_control.queue_redraw()


## ウィンドウを閉じるときに選択をリセットする（game_map から呼ぶ）
func clear_selection() -> void:
	_selected_leader = null
	_leader_list.clear()
	leader_selected.emit(null)


func _process(delta: float) -> void:
	if not visible:
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		_control.queue_redraw()


# --------------------------------------------------------------------------
# 描画
# --------------------------------------------------------------------------

func _on_draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = _control.get_viewport_rect().size
	# 画面中央に 85% × 85% で配置
	var pw: float = vp.x * 0.85
	var ph: float = vp.y * 0.85
	var px: float = (vp.x - pw) * 0.5
	var py: float = (vp.y - ph) * 0.5

	# 背景パネルなし（完全透過）

	# 描画前にリーダー一覧を構築（上下キー選択用）
	_leader_list = _build_leader_list()

	# 表示フロアを決定：選択中リーダーのフロア > プレイヤーのフロア
	var player_floor: int = int(_get_floor.call()) if _get_floor.is_valid() else 0
	var display_floor: int = player_floor
	if _selected_leader != null and is_instance_valid(_selected_leader):
		display_floor = _selected_leader.current_floor

	# タイトル行
	var title: String
	if display_floor != player_floor:
		title = "■ PARTY STATUS  [F1で閉じる]  Player:F%d  表示:F%d" % [player_floor, display_floor]
	else:
		title = "■ PARTY STATUS  [F1で閉じる]  Floor: %d" % player_floor
	_control.draw_string(font, Vector2(px + PAD, py + PAD + HDR_FS),
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, HDR_FS, Color(0.8, 0.8, 1.0))

	var title_bottom: float = py + HDR_FS + PAD * 2.5
	_control.draw_line(Vector2(px, title_bottom), Vector2(px + pw, title_bottom),
		Color(0.45, 0.55, 0.85, 0.5), 1.0)

	# コンテンツ領域（単独表示なので下半分分割なし）
	var c_top: float = title_bottom + 2.0
	var c_h: float   = ph - (title_bottom - py) - 2.0

	_draw_party_state(font, px + PAD, c_top + 2.0, pw - PAD * 2, c_h - 4.0, display_floor)


# --------------------------------------------------------------------------
# パーティー状態
# --------------------------------------------------------------------------

func _draw_party_state(font: Font, x: float, y_start: float,
		w: float, h: float, floor_idx: int) -> void:
	var cy: float  = y_start
	var bottom: float = y_start + h

	var ems: Array = _get_enemy_managers.call() if _get_enemy_managers.is_valid() else []
	var nms: Array = _get_npc_managers.call()   if _get_npc_managers.is_valid()   else []

	# プレイヤーパーティーを先頭に表示（情報量が多く優先表示する）
	if _party != null and cy < bottom:
		cy = _draw_player_party(font, x, cy, w, bottom, floor_idx)

	# NPC パーティー
	for nm_v: Variant in nms:
		if cy >= bottom:
			break
		var nm := nm_v as PartyManager
		if nm == null or not is_instance_valid(nm):
			continue
		cy = _draw_party_block(font, nm, "NPC", Color(0.45, 1.0, 0.55),
				x, cy, w, bottom, floor_idx, true)

	# 敵パーティー
	for em_v: Variant in ems:
		if cy >= bottom:
			break
		var em := em_v as PartyManager
		if em == null or not is_instance_valid(em):
			continue
		cy = _draw_party_block(font, em, "敵", Color(1.0, 0.45, 0.45),
				x, cy, w, bottom, floor_idx, false)


## 描画順のリーダーキャラ一覧を構築する（上下キー選択の対象リスト）
## 描画順（プレイヤー → NPC → 敵）と一致させ、上下キー操作と表示の対応を取る
## 全フロアのリーダーを含む（フロアをまたいだナビゲーションに対応）
func _build_leader_list() -> Array:
	var list: Array = []
	# 1) プレイヤーパーティー
	if _party != null:
		var leader := _get_any_leader(_party.sorted_members())
		if leader != null:
			list.append(leader)
	# 2) NPC パーティー
	var nms: Array = _get_npc_managers.call() if _get_npc_managers.is_valid() else []
	for nm_v: Variant in nms:
		var nm := nm_v as PartyManager
		if nm == null or not is_instance_valid(nm):
			continue
		var leader := _get_any_leader(nm.get_members())
		if leader != null:
			list.append(leader)
	# 3) 敵パーティー
	var ems: Array = _get_enemy_managers.call() if _get_enemy_managers.is_valid() else []
	for em_v: Variant in ems:
		var em := em_v as PartyManager
		if em == null or not is_instance_valid(em):
			continue
		var leader := _get_any_leader(em.get_members())
		if leader != null:
			list.append(leader)
	return list


## メンバーリストから「リーダー」を返す（is_leader 優先、なければ生存中の先頭）
## 描画側の leader 判定と同じロジックにして選択と表示を一致させる
func _get_any_leader(members: Array) -> Character:
	# is_leader が立っているメンバーを優先
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m) and m.hp > 0 and m.is_leader:
			return m
	# 見つからない場合は生存中の先頭
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m) and m.hp > 0:
			return m
	return null


## show_orders: false=敵（`item=` 列を省略・敵は item_pickup 指示を持たないため）、true=NPC/プレイヤー（全列表示）
func _draw_party_block(font: Font, pm: PartyManager, type_label: String,
		header_color: Color, x: float, y: float, w: float, bottom: float,
		floor_idx: int, show_orders: bool) -> float:
	var members: Array[Character] = pm.get_members()
	if members.is_empty():
		return y

	# パーティーブロック表示の条件: いずれかのメンバーが表示フロアにいる場合
	# ただし表示するメンバー一覧は全フロアにまたがって含める（リーダーだけ別フロアでも全員見えるように）
	var any_on_floor := false
	for m_v: Variant in members:
		var mc := m_v as Character
		if is_instance_valid(mc) and mc.current_floor == floor_idx:
			any_on_floor = true
			break
	if not any_on_floor:
		return y

	# 表示対象は全生存メンバー（フロアに関わらず）
	var floor_members: Array[Character] = []
	for m_v: Variant in members:
		var m := m_v as Character
		if is_instance_valid(m):
			floor_members.append(m)
	if floor_members.is_empty():
		return y

	# 生存数カウント（パーティー全体）
	var alive: int = 0
	for m: Character in floor_members:
		if m.hp > 0:
			alive += 1

	# リーダーメンバー参照（▶ 選択マーカー判定用・is_leader 優先）
	## 2026-04-21 改訂：リーダー行からリーダー名・クラスを除去。識別は [種別] + 色分け +
	## メンバー行の ★/クラス名で行う。leader_member は ▶ マーカー表示とメンバー行での
	## (クラス) 付与の特定に使う
	var leader_member: Character = null
	for m: Character in floor_members:
		if is_instance_valid(m) and m.is_leader:
			leader_member = m
			break
	if leader_member == null and not floor_members.is_empty():
		leader_member = floor_members[0]

	# 全体指示ヒント（combat_situation / power_balance / hp_status / 戦力内訳を取得）
	var hint: Dictionary = pm.get_global_orders_hint()
	var sit_str: String = _combat_situation_label(hint.get("combat_situation", 0) as int)
	var pb_str:  String = _power_balance_label(hint.get("power_balance", 0) as int)
	pb_str += " " + _format_strength_breakdown(hint)
	var hs_str:  String = _hp_status_label(hint.get("hp_status", 0) as int)

	## ヘッダー：[種別] 生存・戦況・戦力・HP・（味方のみ）全体指示 / （敵のみ）strategy=ENUM_NAME
	## 2026-04-21 改訂：敵リーダー行の mv/battle/tgt/hp 表示を廃止し、素の _party_strategy を表示。
	## 背景：敵の `_global_orders` は常に空で、旧表示は `_party_strategy` から仮想合成した
	## ラベル（UnitAI 実動と連動せず誤解を招いた）。詳細は
	## docs/investigation_enemy_order_effective.md / docs/investigation_enemy_order_system.md
	var is_enemy: bool = pm.party_type == "enemy"
	var header: String
	if is_enemy:
		## 敵：strategy=<ENUM_NAME>（ATTACK / FLEE / WAIT / DEFEND / EXPLORE / GUARD_ROOM）
		var strategy_name: String = _strategy_enum_name_for(pm)
		header = "[%s]  生存:%d/%d  戦況:%s 戦力:%s HP:%s  strategy=%s" % [
			type_label, alive, floor_members.size(),
			sit_str, pb_str, hs_str, strategy_name]
	else:
		## 味方（NPC パーティー・show_orders=true 想定）：従来通り mv/battle/tgt/hp/item
		var mv_raw:     String = hint.get("move", "-") as String
		var mv_str:     String = _label("move", mv_raw)
		# 階段移動中は目標フロアを付加表示
		if mv_raw == "stairs_down" or mv_raw == "stairs_up":
			var tgt_f: String = hint.get("target_floor", "?") as String
			mv_str += "(F" + tgt_f + ")"
		var battle_str: String = _label("battle_policy", hint.get("battle_policy", "-") as String)
		var tgt_str:    String = _label("target",        hint.get("target",        "-") as String)
		var hp_str:     String = _label("on_low_hp",     hint.get("on_low_hp",     "-") as String)
		if show_orders:
			var item_str: String = _label("item_pickup", hint.get("item_pickup", "-") as String)
			header = "[%s]  生存:%d/%d  戦況:%s 戦力:%s HP:%s  mv=%s  battle=%s  tgt=%s  hp=%s  item=%s" % [
				type_label, alive, floor_members.size(),
				sit_str, pb_str, hs_str, mv_str, battle_str, tgt_str, hp_str, item_str]
		else:
			header = "[%s]  生存:%d/%d  戦況:%s 戦力:%s HP:%s  mv=%s  battle=%s  tgt=%s  hp=%s" % [
				type_label, alive, floor_members.size(),
				sit_str, pb_str, hs_str, mv_str, battle_str, tgt_str, hp_str]

	# 詳細度レベルに応じてヘッダーに追加情報を付加
	header += _format_leader_extras(pm)

	# ヘッダーが描画可能か確認
	if y + LINE_H > bottom:
		return y

	# 選択中リーダーの「▶」マーカー
	var leader_char: Character = leader_member
	var is_selected: bool = (leader_char != null and _selected_leader != null
		and is_instance_valid(_selected_leader) and _selected_leader == leader_char)
	if is_selected:
		_control.draw_string(font, Vector2(x - INDENT, y + FS), "▶",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(1.0, 1.0, 0.3))
	_control.draw_string(font, Vector2(x, y + FS), header,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS, header_color)
	y += LINE_H

	# メンバー行を縦並びで描画（詳細度に応じて 1〜3 行/メンバー）
	for m: Character in floor_members:
		if y >= bottom:
			break
		y = _draw_member_block(font, m, x + INDENT, y, w - INDENT, bottom, pm, floor_idx)

	return y


func _draw_player_party(font: Font, x: float, y: float, w: float, bottom: float,
		floor_idx: int) -> float:
	if y >= bottom or _party == null:
		return y

	# 全メンバー（フロア問わず）を表示。表示条件はいずれか1人が表示フロアにいることのみ
	var sorted: Array = _party.sorted_members()
	var any_on_floor := false
	var floor_members: Array = []
	for m_v: Variant in sorted:
		var m := m_v as Character
		if not is_instance_valid(m):
			continue
		floor_members.append(m)
		if m.current_floor == floor_idx:
			any_on_floor = true
	if not any_on_floor or floor_members.is_empty():
		return y

	var alive: int = 0
	for m_v: Variant in floor_members:
		var m := m_v as Character
		if m.hp > 0:
			alive += 1

	# リーダーメンバー参照（▶ 選択マーカー判定用・is_leader 優先）
	## 2026-04-21 改訂：リーダー行からリーダー名・クラスを除去（メンバー行に移動済）
	var leader_member: Character = null
	for m_v: Variant in floor_members:
		var m := m_v as Character
		if is_instance_valid(m) and m.is_leader:
			leader_member = m
			break
	if leader_member == null and not floor_members.is_empty():
		leader_member = floor_members[0] as Character

	# 全体指示（party.global_orders を直接参照）
	var go: Dictionary = _party.global_orders
	var mv_str:     String = _label("move",          go.get("move",          "-") as String)
	var battle_str: String = _label("battle_policy", go.get("battle_policy", "-") as String)
	var tgt_str:    String = _label("target",        go.get("target",        "-") as String)
	var hp_str:     String = _label("on_low_hp",     go.get("on_low_hp",     "-") as String)
	var item_str:   String = _label("item_pickup",   go.get("item_pickup",   "-") as String)
	# 戦況表示（_hero_manager から取得）
	var sit_str := "?"
	var pb_str := "?"
	var hs_str := "?"
	if _hero_manager != null and is_instance_valid(_hero_manager):
		var hint: Dictionary = _hero_manager.get_global_orders_hint()
		sit_str = _combat_situation_label(hint.get("combat_situation", 0) as int)
		pb_str = _power_balance_label(hint.get("power_balance", 0) as int)
		pb_str += " " + _format_strength_breakdown(hint)
		hs_str = _hp_status_label(hint.get("hp_status", 0) as int)

	var header := "[プレイヤー]  生存:%d/%d  戦況:%s 戦力:%s HP:%s  mv=%s  battle=%s  tgt=%s  hp=%s  item=%s" % [
		alive, floor_members.size(),
		sit_str, pb_str, hs_str, mv_str, battle_str, tgt_str, hp_str, item_str]
	header += _format_leader_extras(_hero_manager)
	if y + LINE_H > bottom:
		return y

	var player_leader: Character = leader_member
	var is_selected: bool = (player_leader != null and _selected_leader != null
		and is_instance_valid(_selected_leader) and _selected_leader == player_leader)
	if is_selected:
		_control.draw_string(font, Vector2(x - INDENT, y + FS), "▶",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(1.0, 1.0, 0.3))
	_control.draw_string(font, Vector2(x, y + FS), header,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.45, 0.75, 1.0))
	y += LINE_H

	# メンバー行を縦並びで描画（詳細度に応じて 1〜3 行/メンバー）
	for m_v: Variant in floor_members:
		if y >= bottom:
			break
		var m := m_v as Character
		if not is_instance_valid(m):
			continue
		y = _draw_member_block(font, m, x + INDENT, y, w - INDENT, bottom, _hero_manager, floor_idx)

	return y


# --------------------------------------------------------------------------
# リーダー行の追加情報（詳細度で拡張）
# --------------------------------------------------------------------------

## 詳細度レベルに応じてリーダー行末尾に付加する文字列を返す
## 優先度「中」：_reeval_timer / _visited_areas サイズ
## 優先度「低」：NpcLeaderAI 固有フラグ（_was_refused / has_fought_together /
##              has_been_healed / joined_to_player / suppress_floor_navigation）
func _format_leader_extras(pm: PartyManager) -> String:
	if pm == null or not is_instance_valid(pm):
		return ""
	var leader: PartyLeader = pm.get_party_leader()
	if leader == null or not is_instance_valid(leader):
		return ""

	var parts: PackedStringArray = []

	# 中優先度
	if _show_var("reeval_timer"):
		var t: float = float(leader.get("_reeval_timer"))
		parts.append("re:%.1fs" % maxf(t, 0.0))
	if _show_var("visited_areas_size"):
		var va: Variant = leader.get("_visited_areas")
		if va != null and va is Dictionary:
			parts.append("探索:%d" % (va as Dictionary).size())

	# 低優先度（NpcLeaderAI 固有・duck typing で取得）
	if _show_var("joined_to_player"):
		var joined_v: Variant = leader.get("joined_to_player")
		if joined_v != null:
			parts.append("合流:%s" % _yn(joined_v as bool))
	if _show_var("was_refused"):
		var refused_v: Variant = leader.get("_was_refused")
		if refused_v != null:
			parts.append("拒絶:%s" % _yn(refused_v as bool))
	if _show_var("has_fought_together"):
		var ft_v: Variant = leader.get("has_fought_together")
		if ft_v != null:
			parts.append("共闘:%s" % _yn(ft_v as bool))
	if _show_var("has_been_healed"):
		var hh_v: Variant = leader.get("has_been_healed")
		if hh_v != null:
			parts.append("回復:%s" % _yn(hh_v as bool))
	if _show_var("suppress_floor_navigation"):
		var sfn_v: Variant = leader.get("suppress_floor_navigation")
		if sfn_v != null and (sfn_v as bool):
			parts.append("床固定")

	if parts.is_empty():
		return ""
	return "  " + " ".join(parts)


func _yn(b: bool) -> String:
	return "Y" if b else "N"


# --------------------------------------------------------------------------
# メンバー行の描画（詳細度に応じて 1〜3 行）
# --------------------------------------------------------------------------

## 1 メンバーを**横一列流しレイアウト**で描画し、描画後の y を返す（2026-04-21 改訂）
##   詳細度 0（高のみ）: 行動ボディ + 目的
##   詳細度 1（高+中）: 上記 + 指示グループ（"  指示: M:... C:..."）
##   詳細度 2（高+中+低）: 上記 + 状態グループ（"  状態: P↓ ..."）+ 12 ステータスグループ
## すべて同じ x から横に流し、幅 w を超えたらセグメント境界で折り返す
## 色分け：行動ボディ = HP 色、目的 = シアン、指示 = 黄緑、状態/ステータス = 茶系
func _draw_member_block(font: Font, m: Character, x: float, y: float, w: float,
		bottom: float, pm: PartyManager, display_floor: int) -> float:
	if m == null or not is_instance_valid(m):
		return y
	if y + LINE_H > bottom:
		return y

	var hp_color:     Color = _hp_color_for(m)
	const GOAL_COLOR:   Color = Color(0.55, 0.85, 1.0, 0.85)
	const ORDERS_COLOR: Color = Color(0.78, 0.85, 0.6)
	const FLAGS_COLOR:  Color = Color(0.85, 0.7, 0.6)

	# UnitAI 参照（指示・フラグで必要）
	var ai: UnitAI = null
	if pm != null and is_instance_valid(pm):
		ai = pm.get_unit_ai(m)

	# ---- 描画セグメントを組み立てる ----
	## セグメント：{"text": String, "color": Color}
	## 各セグメントはそれぞれの先頭に半角スペースまたは "  "（グループ先頭）を含む
	## 行頭でのみ、そのセグメントの先頭空白を削除して描画する（自然折返し）
	var segs: Array[Dictionary] = []

	# 行動ボディ（HP 色・常時表示）
	var body_s: String = _format_action_body(m, display_floor)
	segs.append({"text": body_s, "color": hp_color})

	# 目的（シアン・常時表示・先頭にスペース付き）
	var goal_s: String = _format_action_goal(m, pm)
	if not goal_s.is_empty():
		segs.append({"text": goal_s, "color": GOAL_COLOR})

	# 指示グループ（詳細度 >= 1・味方メンバーのみ）
	## 2026-04-21 改訂：敵メンバーでは本グループを出力しない。
	## 敵の `_combat` / `_battle_formation` / `_on_low_hp` / `_move_policy` は Character デフォルトから
	## 変化せず、`_special_skill` / `_hp_potion` / `_sp_mp_potion` は `is_friendly == false` ガードで
	## 参照されない。`_item_pickup` も実質参照されない（`_is_combat_safe()` が敵側で稀に真になる程度）。
	## 詳細は docs/investigation_enemy_order_system.md / investigation_enemy_order_effective.md
	if _detail_level >= 1 and ai != null and is_instance_valid(ai) and m.is_friendly:
		var order_parts: PackedStringArray = _build_orders_field_list(ai)
		if not order_parts.is_empty():
			segs.append({"text": "  指示:", "color": ORDERS_COLOR})
			for p: String in order_parts:
				segs.append({"text": " " + p, "color": ORDERS_COLOR})

	# 敵固有・動的判断グループ（詳細度 >= 1・敵メンバーのみ）※ 2026-04-21 追加
	## 敵は味方の指示ラインの代わりにこの「種:」グループを表示する。
	## `_build_enemy_dynamic_parts` 自身も `m.is_friendly` ガードで味方では空を返すため
	## 条件文と二重ガードになるが、意図を明示するため条件はここにも書いておく
	if _detail_level >= 1 and ai != null and is_instance_valid(ai) and not m.is_friendly:
		var enemy_dyn: PackedStringArray = _build_enemy_dynamic_parts(m, ai)
		if not enemy_dyn.is_empty():
			segs.append({"text": "  種:", "color": ORDERS_COLOR})
			for p: String in enemy_dyn:
				segs.append({"text": " " + p, "color": ORDERS_COLOR})

	# 状態グループ（UnitAI 側フラグ・詳細度 >= 2）
	if _detail_level >= 2 and ai != null and is_instance_valid(ai):
		var ai_flag_parts: PackedStringArray = _build_ai_flag_parts(ai, m)
		if not ai_flag_parts.is_empty():
			segs.append({"text": "  状態:", "color": FLAGS_COLOR})
			for p: String in ai_flag_parts:
				segs.append({"text": " " + p, "color": FLAGS_COLOR})

	# 12 ステータスグループ（Character 側・詳細度 >= 2）
	if _detail_level >= 2:
		var stat_parts: PackedStringArray = _build_char_stat_parts(m)
		for i: int in range(stat_parts.size()):
			var prefix: String = "  " if i == 0 else " "
			segs.append({"text": prefix + stat_parts[i], "color": FLAGS_COLOR})

	# 敵固有・静的属性グループ（詳細度 >= 2・敵メンバーのみ）※ 2026-04-21 追加
	## ignfle / undead / flying / immune / proj / chase / terr
	if _detail_level >= 2 and ai != null and is_instance_valid(ai):
		var enemy_stat: PackedStringArray = _build_enemy_static_parts(m, ai)
		for p: String in enemy_stat:
			segs.append({"text": " " + p, "color": FLAGS_COLOR})

	# ---- セグメントを横一列で流し、幅超過時は改行 ----
	var cx: float = x
	var cur_y: float = y
	for seg: Dictionary in segs:
		var text: String = seg["text"]
		var color: Color = seg["color"]
		var seg_w: float = font.get_string_size(text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var at_line_start: bool = (cx <= x + 0.5)
		# 行頭でなく・かつ右端を超えるなら改行
		if not at_line_start and cx + seg_w > x + w:
			cur_y += LINE_H
			if cur_y + LINE_H > bottom:
				return cur_y
			cx = x
			# 新しい行の先頭では、セグメント先頭の空白を剥がす
			text = text.lstrip(" ")
			seg_w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		_control.draw_string(font, Vector2(cx, cur_y + FS), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS, color)
		cx += seg_w

	return cur_y + LINE_H


## 行動ライン本体部分（HP 色で描画される部分・2026-04-21 にクラス名を追加）
## 形式: [Fx]★名前[ランク](クラス) HP:x/y MP|SP:x/y mv=0.40s [ス][ガ]
##   Fx      = 別フロア時のみ
##   ★      = is_player_controlled（操作中マーカー）
##   (クラス) = CLASS_NAME_JP（例：ヒーラー・剣士）。2026-04-21 にリーダー行から移動
##   [ス][ガ] = stun / guard
## MP/SP 分岐はクラスに応じて（`CharacterData.is_magic_class()`）。max_energy が 0 の場合は省略
func _format_action_body(m: Character, display_floor: int) -> String:
	var cd := m.character_data
	var name_s: String = (cd.character_name if cd != null else "?") as String
	var rank_s: String = (cd.rank          if cd != null else "?") as String
	var star_s: String = "★" if m.is_player_controlled else ""
	var class_s: String = ""
	if cd != null:
		var class_jp: String = GlobalConstants.CLASS_NAME_JP.get(cd.class_id, "") as String
		if not class_jp.is_empty():
			class_s = "(%s)" % class_jp
	var floor_s: String = ""
	if display_floor >= 0 and m.current_floor != display_floor:
		floor_s = "[F%d]" % m.current_floor
	var move_dur: float = m.get_move_duration()
	var status: String = ""
	if m.is_stunned:  status += "ス"
	if m.is_guarding: status += "ガ"
	if not status.is_empty(): status = " [%s]" % status
	# エネルギー表示（高優先度）。クラスに応じて MP/SP 切替
	var energy_s: String = ""
	if _show_var("energy") and m.max_energy > 0:
		var label: String = "MP" if (cd != null and cd.is_magic_class()) else "SP"
		energy_s = " %s:%d/%d" % [label, m.energy, m.max_energy]
	return "%s%s%s[%s]%s HP:%d/%d%s mv=%.2fs%s" % [
		floor_s, star_s, name_s, rank_s, class_s, m.hp, m.max_hp, energy_s, move_dur, status]


## 行動ラインの目的部分（シアン色で描画）
## get_debug_goal_str の結果に、_timer 残秒とキュー長を付加する
## 例: " →攻撃Goblin[ATKp 0.34s|q3]"
## UnitAI 参照は PartyManager.get_member_goal_str 経由（従来互換）＋ duck typing で
## _timer / _queue に追加アクセス
func _format_action_goal(m: Character, pm: PartyManager) -> String:
	if pm == null or not is_instance_valid(pm):
		return ""
	var raw_goal: String = pm.get_member_goal_str(m)
	if raw_goal.is_empty():
		return ""
	# 残タイマー・キュー長を末尾に付加（UnitAI 参照が取れれば）
	var ai: UnitAI = pm.get_unit_ai(m)
	if ai != null and is_instance_valid(ai):
		var t_v: Variant = ai.get("_timer")
		var q_v: Variant = ai.get("_queue")
		var extras: PackedStringArray = []
		if t_v != null:
			var t: float = maxf(float(t_v), 0.0)
			if t > 0.001:
				extras.append("%.2fs" % t)
		if q_v != null and q_v is Array:
			var q_len: int = (q_v as Array).size()
			if q_len > 0:
				extras.append("q%d" % q_len)
		if not extras.is_empty():
			# 既存の末尾 "]" の直前に " <extras>" を挿入
			if raw_goal.ends_with("]"):
				raw_goal = raw_goal.substr(0, raw_goal.length() - 1) \
					+ " " + " ".join(extras) + "]"
			else:
				raw_goal += "[" + " ".join(extras) + "]"
	return " " + raw_goal


## 指示パーツ（中優先度）：メンバーの order 関連フィールドをパーツ配列で返す
## 例: ["M:follow", "C:attack", "F:surround", "L:retreat", "S:strong", "HP:use", "E:use", "I:passive"]
## 各フィールドを個別パーツにすることで横一列流しレイアウトでの折返し精度を上げる
## _shorten() が空文字列 / null を "-" に変換するため、敵の未設定フィールドも "-" で表示される
func _build_orders_field_list(ai: UnitAI) -> PackedStringArray:
	var parts: PackedStringArray = []
	if _show_var("move_policy"):
		parts.append("M:%s" % _shorten(ai.get("_move_policy")))
	if _show_var("combat"):
		parts.append("C:%s" % _shorten(ai.get("_combat")))
	if _show_var("battle_formation"):
		parts.append("F:%s" % _shorten(ai.get("_battle_formation")))
	if _show_var("on_low_hp"):
		parts.append("L:%s" % _shorten(ai.get("_on_low_hp")))
	if _show_var("special_skill"):
		parts.append("S:%s" % _shorten(ai.get("_special_skill")))
	if _show_var("hp_potion"):
		parts.append("HP:%s" % _shorten(ai.get("_hp_potion")))
	if _show_var("sp_mp_potion"):
		parts.append("E:%s" % _shorten(ai.get("_sp_mp_potion")))
	if _show_var("item_pickup"):
		parts.append("I:%s" % _shorten(ai.get("_item_pickup")))
	return parts


## UnitAI 側フラグパーツ（低優先度）：パーティー状態・種族固有の時系列情報をパーツ配列で返す
## 例: ["P↓", "F↑", "warp:1.2s"]
##   P↓ = _party_fleeing（パーティー撤退中・敵メンバー限定）
##   F↑ = _floor_following（フロア追従中）
##   warp:1.2s = DarkLord 固有・次ワープまで残秒
## 該当フラグがない場合は空配列を返す
## ※ Lich の lich_water は 2026-04-21 に「敵固有・動的判断」として中優先度に移動
##   （`_build_enemy_dynamic_parts` で描画）
##
## 2026-04-21 改訂：`_party_fleeing` は敵専用フラグに変更（味方には配布されず常に false）。
## 味方メンバー行に P↓ が出ないよう `m.is_friendly` ガードを追加。
func _build_ai_flag_parts(ai: UnitAI, m: Character) -> PackedStringArray:
	var parts: PackedStringArray = []
	## party_fleeing は敵メンバー限定（味方では常に false なので表示する意味なし）
	if _show_var("party_fleeing") and m != null and not m.is_friendly:
		var pf_v: Variant = ai.get("_party_fleeing")
		if pf_v != null and (pf_v as bool):
			parts.append("P↓")
	if _show_var("floor_following"):
		var ff_v: Variant = ai.get("_floor_following")
		if ff_v != null and (ff_v as bool):
			parts.append("F↑")
	if _show_var("warp_timer"):
		var wt_v: Variant = ai.get("_warp_timer")
		if wt_v != null:
			parts.append("warp:%.1fs" % maxf(float(wt_v), 0.0))
	return parts


## 敵固有・動的判断パーツ（中優先度・敵パーティーのメンバーのみ）※ 2026-04-21 追加
## docs/investigation_enemy_order_system.md で特定した「敵が実際に行動判断に使う要素」のうち、
## ゲーム中に値が変化する動的なものを表示する。
##   sflee        = _should_self_flee() が true（ゴブリン系が HP 30% 未満で逃走判定）
##   nomp         = _can_attack() が false（魔法系が MP 不足で攻撃不可）
##   lich:水/火   = LichUnitAI._lich_water（次攻撃の属性切替・攻撃ごとに反転）
## 呼出前提：m.is_friendly == false（敵メンバー）。味方には空配列を返す運用
func _build_enemy_dynamic_parts(m: Character, ai: UnitAI) -> PackedStringArray:
	var parts: PackedStringArray = []
	if m == null or m.is_friendly or ai == null or not is_instance_valid(ai):
		return parts
	# 自己逃走判定（動的・HP 依存）
	if _show_var("should_self_flee") and ai._should_self_flee():
		parts.append("sflee")
	# 攻撃可否判定（動的・MP 依存）
	if _show_var("can_attack") and not ai._can_attack():
		parts.append("nomp")
	# Lich 固有の属性交替
	if _show_var("lich_water") and ai is LichUnitAI:
		var lw: bool = (ai as LichUnitAI)._lich_water
		parts.append("lich:%s" % ("水" if lw else "火"))
	return parts


## 敵固有・静的属性パーツ（低優先度・敵パーティーのメンバーのみ）※ 2026-04-21 追加
## ゲーム中に値が変化しない属性（種族特性・JSON 設定値）を表示する。
##   ignfle       = _should_ignore_flee() が true（DarkKnight / Zombie 等 9 種族）
##   undead       = is_undead（Skeleton / Skeleton-archer / Lich）
##   flying       = is_flying（Harpy / Demon / DarkLord）
##   immune       = instant_death_immune（ボス級）
##   proj:{type}  = projectile_type（空文字列は省略）
##   chase:{n}    = chase_range（敵個別 JSON）
##   terr:{n}     = territory_range（敵個別 JSON）
## 呼出前提：m.is_friendly == false（敵メンバー）。味方には空配列を返す運用
func _build_enemy_static_parts(m: Character, ai: UnitAI) -> PackedStringArray:
	var parts: PackedStringArray = []
	if m == null or m.is_friendly or ai == null or not is_instance_valid(ai):
		return parts
	var cd := m.character_data
	# フック系（true のときのみ表示）
	if _show_var("should_ignore_flee") and ai._should_ignore_flee():
		parts.append("ignfle")
	# JSON 属性（true のときのみ表示）
	if cd != null:
		if _show_var("is_undead") and cd.is_undead:
			parts.append("undead")
		if _show_var("is_flying") and cd.is_flying:
			parts.append("flying")
		if _show_var("instant_death_immune") and cd.instant_death_immune:
			parts.append("immune")
		if _show_var("projectile_type") and not cd.projectile_type.is_empty():
			parts.append("proj:%s" % cd.projectile_type)
		if _show_var("chase_range"):
			parts.append("chase:%d" % cd.chase_range)
		if _show_var("territory_range"):
			parts.append("terr:%d" % cd.territory_range)
	return parts


## Character 側 12 ステータス + fac/leader ラベルのパート配列を構築する
## 素値・装備補正ともに 0 のフィールドは省略（クラス固有差分・スケーラビリティ対応）
func _build_char_stat_parts(m: Character) -> PackedStringArray:
	var parts: PackedStringArray = []
	var cd := m.character_data
	if cd == null:
		return parts

	# 整数ステータス：Character.X = 最終値、character_data.X = 素値、差分 = 装備補正
	# 略称 / 最終値 / 素値 のタプルで並べる
	var int_specs: Array = [
		["pow",  m.power,              cd.power],
		["skl",  m.skill,              cd.skill],
		["rng",  m.attack_range,       cd.attack_range],
		["br",   m.block_right_front,  cd.block_right_front],
		["bl",   m.block_left_front,   cd.block_left_front],
		["bf",   m.block_front,        cd.block_front],
		["pr",   m.physical_resistance, cd.physical_resistance],
		["mr",   m.magic_resistance,   cd.magic_resistance],
		["da",   m.defense_accuracy,   cd.defense_accuracy],
		["ld",   m.leadership,         cd.leadership],
	]
	for spec: Array in int_specs:
		var abbr: String = spec[0] as String
		var final_v: int  = int(spec[1])
		var base_v:  int  = int(spec[2])
		var bonus:   int  = final_v - base_v
		# 素値・装備補正ともに 0 なら省略（クラス固有差分対応）
		if base_v == 0 and bonus == 0:
			continue
		parts.append(_format_stat_part(abbr, base_v, bonus))

	# obedience（0.0〜1.0 → ×100 整数化。OrderWindow の表記と整合）
	var ob_base: int  = roundi(cd.obedience * 100.0)
	var ob_final: int = roundi(m.obedience * 100.0)
	var ob_bonus: int = ob_final - ob_base
	if ob_base != 0 or ob_bonus != 0:
		parts.append(_format_stat_part("ob", ob_base, ob_bonus))

	# move_speed（0〜100 スケール・float）
	var ms_base: int  = roundi(cd.move_speed)
	var ms_final: int = roundi(m.move_speed)
	var ms_bonus: int = ms_final - ms_base
	if ms_base != 0 or ms_bonus != 0:
		parts.append(_format_stat_part("mv_s", ms_base, ms_bonus))

	# ラベル項目：fac（陣営）・leader（リーダー）
	if _show_var("is_friendly"):
		parts.append("fac:%s" % ("味方" if m.is_friendly else "敵"))
	if _show_var("is_leader") and m.is_leader:
		parts.append("leader")

	return parts


## ステータス 1 項目を `abbr:base+bonus` または `abbr:base` 形式にフォーマット
## bonus が非 0 のときだけ `+N` / `-N` を付加
func _format_stat_part(abbr: String, base: int, bonus: int) -> String:
	if bonus == 0:
		return "%s:%d" % [abbr, base]
	# 正値は明示的に "+" を付ける。負値は str(bonus) 側に "-" が含まれる
	var prefix: String = "+" if bonus > 0 else ""
	return "%s:%d%s%d" % [abbr, base, prefix, bonus]




## 文字列を短縮表示（長い値を max_len 文字で打ち切る。UI を詰めるため）
## Variant 受け取りで null / 空文字列 / 非 String にも対応
func _shorten(v: Variant, max_len: int = 8) -> String:
	if v == null:
		return "-"
	var s: String = str(v)
	if s.is_empty():
		return "-"
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len)


## OrderWindow の定数から構築したラベルキャッシュ（key → {option: label}）
var _label_cache: Dictionary = {}

## OrderWindow.GLOBAL_ROWS / MEMBER_COLS / HEALER_COLS からキャッシュを構築する
func _build_label_cache() -> void:
	if not _label_cache.is_empty():
		return
	for src: Array in [OrderWindow.GLOBAL_ROWS, OrderWindow.MEMBER_COLS, OrderWindow.HEALER_COLS]:
		for def_v: Variant in src:
			var def := def_v as Dictionary
			var key: String = def.get("key", "") as String
			if key.is_empty() or _label_cache.has(key):
				continue
			var opts: Array = def.get("options", [])
			var lbls: Array = def.get("labels",  [])
			var sub: Dictionary = {}
			for i: int in range(mini(opts.size(), lbls.size())):
				sub[opts[i] as String] = lbls[i] as String
			_label_cache[key] = sub


## key に対応する OrderWindow のラベルで val を変換する。未定義なら val をそのまま返す
func _label(key: String, val: String) -> String:
	if val == "-":
		return "-"
	# 階段移動方針は OrderWindow 定数に存在しないため個別処理
	if key == "move":
		if val == "stairs_down": return "↓階段"
		if val == "stairs_up":   return "↑階段"
	_build_label_cache()
	var sub := _label_cache.get(key, {}) as Dictionary
	return sub.get(val, val) as String


## パーティーリーダーの `_party_strategy` enum を英字名に変換する（敵ヘッダー表示用）
## 2026-04-21 追加：敵リーダー行は日本語化せず enum 名そのまま表示することで、
## 「素の変数値」であることを視覚的に明示し、味方の指示ラベル（mv=密集 等）との誤解を避ける
## ※ 日本語化が必要なケース（UI 等）では `PartyLeader.get_current_strategy_name()` を使う
func _strategy_enum_name_for(pm: PartyManager) -> String:
	if pm == null or not is_instance_valid(pm):
		return "?"
	var leader: PartyLeader = pm.get_party_leader()
	if leader == null or not is_instance_valid(leader):
		return "?"
	var s: int = int(leader._party_strategy)
	match s:
		int(PartyLeader.Strategy.ATTACK):      return "ATTACK"
		int(PartyLeader.Strategy.FLEE):        return "FLEE"
		int(PartyLeader.Strategy.WAIT):        return "WAIT"
		int(PartyLeader.Strategy.DEFEND):      return "DEFEND"
		int(PartyLeader.Strategy.EXPLORE):     return "EXPLORE"
		int(PartyLeader.Strategy.GUARD_ROOM):  return "GUARD_ROOM"
	return "?"


## CombatSituation enum 値を短い日本語ラベルに変換する
func _combat_situation_label(sit: int) -> String:
	match sit:
		int(GlobalConstants.CombatSituation.SAFE):          return "安全"
		int(GlobalConstants.CombatSituation.OVERWHELMING):  return "圧倒"
		int(GlobalConstants.CombatSituation.ADVANTAGE):     return "優勢"
		int(GlobalConstants.CombatSituation.EVEN):          return "互角"
		int(GlobalConstants.CombatSituation.DISADVANTAGE):  return "劣勢"
		int(GlobalConstants.CombatSituation.CRITICAL):      return "危険"
	return "?"


func _power_balance_label(pb: int) -> String:
	match pb:
		int(GlobalConstants.PowerBalance.OVERWHELMING):  return "圧倒"
		int(GlobalConstants.PowerBalance.SUPERIOR):      return "優位"
		int(GlobalConstants.PowerBalance.EVEN):          return "互角"
		int(GlobalConstants.PowerBalance.INFERIOR):      return "劣位"
		int(GlobalConstants.PowerBalance.DESPERATE):     return "絶望"
	return "?"


## 戦力内訳を 1 行の文字列にフォーマット
## 形式: F(R+T)s C(R+T)s E(R+T)s
##   F = full_party / C = nearby_allied / E = nearby_enemy
##   各括弧内: R=rank_sum / T=tier 平均の和 / 末尾 s=strength
##   敵パーティー視点では F と C は同値（協力しない世界観）
func _format_strength_breakdown(hint: Dictionary) -> String:
	var f_rank: int   = hint.get("full_party_rank_sum",    0) as int
	var f_tier: float = float(hint.get("full_party_tier_sum",    0.0))
	var f_str:  float = float(hint.get("full_party_strength",    0.0))
	var c_rank: int   = hint.get("nearby_allied_rank_sum", 0) as int
	var c_tier: float = float(hint.get("nearby_allied_tier_sum", 0.0))
	var c_str:  float = float(hint.get("nearby_allied_strength", 0.0))
	var e_rank: int   = hint.get("nearby_enemy_rank_sum",  0) as int
	var e_tier: float = float(hint.get("nearby_enemy_tier_sum",  0.0))
	var e_str:  float = float(hint.get("nearby_enemy_strength",  0.0))
	return "F(%d+%.1f)%.1f C(%d+%.1f)%.1f E(%d+%.1f)%.1f" % [
		f_rank, f_tier, f_str,
		c_rank, c_tier, c_str,
		e_rank, e_tier, e_str,
	]


## HP比率からデバッグ表示用の色を返す
## スプライト系パレット（白 / 黄 / 橙 / 赤）を流用・点滅なし
func _hp_color_for(ch: Character) -> Color:
	if not is_instance_valid(ch) or ch.max_hp <= 0:
		return GlobalConstants.CONDITION_COLOR_SPRITE_HEALTHY
	return GlobalConstants.condition_sprite_color(ch.get_condition())


func _hp_status_label(hs: int) -> String:
	match hs:
		int(GlobalConstants.HpStatus.FULL):     return "満"
		int(GlobalConstants.HpStatus.STABLE):   return "安"
		int(GlobalConstants.HpStatus.LOW):      return "低"
		int(GlobalConstants.HpStatus.CRITICAL): return "危"
	return "?"
