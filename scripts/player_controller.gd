class_name PlayerController
extends Node

## プレイヤー入力コントローラー
## Phase 4: NORMAL/TARGETING/FIRINGステートマシン・攻撃スロット・飛翔体対応
## Phase 6-0: クラスJSONのスロット定義を読み込み、クラスごとの攻撃動作に対応
##   - action: "melee" → マンハッタン距離・近接判定
##   - action: "ranged" / "ranged_area" → ユークリッド距離・飛翔体
##   - damage_mult がスロット単位で適用される（背面2倍等の方向補正とは別）
## Phase 6-1: ホールド方式ターゲット選択
##   - 攻撃キーホールド中 = ターゲット選択モード
##   - キーリリース時にターゲットあり→攻撃発動、なし→ノーコストキャンセル
##   - ターゲットソート: 前方±45°を距離順、次いでそれ以外を距離順
##   - ホールド中に射程内の敵リストをリアルタイム更新
## Phase 10-2: 攻撃を Z/A の1ボタンに統合。攻撃タイプはクラスのスロット定義から自動判定

var character: Character = null
var map_data: MapData = null

## 移動先の占有チェック対象
var blocking_characters: Array[Character] = []

## 飛翔体・ターゲットカーソルの add_child 用
var map_node: Node2D = null

## 会話中など入力を一時的に無効化するフラグ
var is_blocked: bool = false

## 移動先に友好的キャラクターがいたときに発火するシグナル（会話トリガー用）
signal npc_bumped(npc_member: Character)

## 移動アニメーションの1タイルあたりの時間・基準値（秒）
## この定数が移動速度を決める。game_speed で割った値が実効値になる
## 【旧方式との違い】タイマーによる移動間隔制御を廃止し、アニメーション完了を
## 次移動の gate として使う先行入力バッファ方式に変更（Phase 9-1）
const MOVE_INTERVAL: float = 0.30
const CLASS_JSON_DIR := "res://assets/master/classes/"

## 前方コーン判定しきい値（cos 45° ≈ 0.707）
const FORWARD_CONE_DOT: float = 0.707

## デフォルトスロット（クラスデータが存在しない場合のフォールバック）
const DEFAULT_SLOT_Z: Dictionary = {
	"name": "近接攻撃", "action": "melee",  "type": "physical",
	"range": 1, "damage_mult": 1.0, "pre_delay": 0.0
}

enum Mode { NORMAL, TARGETING, FIRING }

var _mode: Mode = Mode.NORMAL
var _valid_targets: Array[Character] = []
var _target_index:  int = 0  # valid_targets.size() = キャンセル選択

## 先行入力バッファ（アニメーション中に受け付けた移動方向。ZERO=なし）
## 【問題1・2 の修正】アニメーション中は新たな移動をブロックし、この変数に上書き保存する。
## アニメーション完了後にバッファを処理することで以下の問題を解決する：
##   問題1（斜め移動）: 補間途中から別方向への補間開始を防ぐ
##   問題2（長押し停止）: OS キーリピートの位相ズレや瞬間的なZERO入力の影響を受けない
var _move_buffer: Vector2i = Vector2i.ZERO
var _cursor: TargetCursor = null

## ホールド開始時からのpre_delayカウントダウン（0以下で発動可能）
var _pre_delay_remaining: float = 0.0

## _input() で検出したターゲット循環方向（+1=次・-1=前・0=なし）
## is_action_just_pressed をポーリングするより確実にボタン1回を捕捉できる
var _cycle_direction: int = 0

## FIRING ステート用：発動待ちの情報
var _pending_target:    Character  = null
var _pending_slot_data: Dictionary = {}

## クラスJSONから読み込んだスロットデータ
var _slot_z: Dictionary = {}

## 消耗品バー UI（game_map から設定）
var consumable_bar: ConsumableBar = null


func _ready() -> void:
	_load_class_slots()


## ターゲット循環ボタン（LB/RB）をイベント駆動で確実に捕捉する
## _process でのポーリング（is_action_just_pressed）は他ボタンホールド中に
## 取りこぼす場合があるため、_input() で毎イベントを直接受け取る方式に変更
func _input(event: InputEvent) -> void:
	if _mode != Mode.TARGETING:
		return
	if event.is_action_pressed("cycle_target_next", false):
		_cycle_direction = 1
	elif event.is_action_pressed("cycle_target_prev", false):
		_cycle_direction = -1


# --------------------------------------------------------------------------
# クラス別スロット初期化
# --------------------------------------------------------------------------

## character のクラスIDに基づいてスロットデータをロードする
## クラスデータが存在しない場合はデフォルト（近接攻撃）を使用
func _load_class_slots() -> void:
	_slot_z = DEFAULT_SLOT_Z.duplicate()
	if character == null or character.character_data == null:
		return
	var class_id := character.character_data.class_id
	if class_id.is_empty():
		return
	var class_json := _read_class_json(class_id)
	if class_json.is_empty():
		return
	var slots: Dictionary = class_json.get("slots", {}) as Dictionary
	var z_data: Variant = slots.get("Z")
	if z_data != null and z_data is Dictionary:
		_slot_z = (z_data as Dictionary).duplicate()


func _get_slot() -> Dictionary:
	return _slot_z if not _slot_z.is_empty() else DEFAULT_SLOT_Z.duplicate()


# --------------------------------------------------------------------------
# メインループ
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if character == null or is_blocked:
		return

	match _mode:
		Mode.NORMAL:
			_process_normal(delta)
		Mode.TARGETING:
			_process_targeting(delta)
		Mode.FIRING:
			_process_firing(delta)


func _process_normal(_delta: float) -> void:
	# 消耗品スロット循環（LT/RT）
	if Input.is_action_just_pressed("slot_prev"):
		_cycle_consumable(-1)
	elif Input.is_action_just_pressed("slot_next"):
		_cycle_consumable(1)

	# 消耗品使用（C/X）
	if Input.is_action_just_pressed("use_item"):
		_use_selected_consumable()

	# 攻撃キーホールドでターゲット選択モードへ
	if Input.is_action_pressed("attack"):
		_move_buffer = Vector2i.ZERO
		_enter_targeting()
		return

	var dir := _get_input_direction()

	# アニメーション中は新たな移動をブロック
	# キーが押されていればバッファに上書き記録、離されたらバッファをクリア
	if character.is_moving():
		_move_buffer = dir  # ZERO でも上書き（離したらキャンセル）
		return

	# アニメーション完了後：バッファ入力を優先し、次いで現在の入力を使用
	var effective_dir := _move_buffer if _move_buffer != Vector2i.ZERO else dir
	_move_buffer = Vector2i.ZERO
	if effective_dir == Vector2i.ZERO:
		return

	_try_move(effective_dir)


func _process_targeting(delta: float) -> void:
	# ホールド中も pre_delay をカウントダウン
	_pre_delay_remaining -= delta

	# キーリリース検出 → 発動 or キャンセル
	if not _is_slot_held():
		if _target_index < _valid_targets.size():
			_commit_attack()
		else:
			_exit_targeting()
		return

	# ターゲットリストをリアルタイム更新（敵の移動・死亡に対応）
	_refresh_targets()

	# 循環選択
	# ゲームパッド LB/RB: _input() で捕捉した _cycle_direction を使用（取りこぼし防止）
	# キーボード: 右/下=次・左/上=前（is_action_just_pressed で同フレーム検出）
	if _cycle_direction != 0:
		_cycle_target(_cycle_direction)
		_cycle_direction = 0
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down"):
		_cycle_target(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up"):
		_cycle_target(-1)


func _process_firing(delta: float) -> void:
	# 残り pre_delay を消化してから発動
	_pre_delay_remaining -= delta
	if _pre_delay_remaining <= 0.0:
		_execute_pending()


# --------------------------------------------------------------------------
# ターゲット選択
# --------------------------------------------------------------------------

func _enter_targeting() -> void:
	_mode         = Mode.TARGETING
	_move_buffer  = Vector2i.ZERO

	# ホールド開始時点から pre_delay カウント開始
	var sd := _get_slot()
	_pre_delay_remaining = float(sd.get("pre_delay", 0.0))

	_valid_targets = _get_sorted_targets()
	_target_index  = 0  # 先頭の敵を自動選択（敵なしならキャンセル選択）
	character.is_targeting_mode = true

	if map_node != null:
		_cursor = TargetCursor.new()
		_cursor.z_index = 3
		map_node.add_child(_cursor)

	_update_cursor()


func _exit_targeting() -> void:
	_mode = Mode.NORMAL
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	_valid_targets.clear()
	_target_index        = 0
	_pre_delay_remaining = 0.0
	_cycle_direction     = 0
	character.is_targeting_mode = false
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null


## キーリリース時にターゲットが確定していたら発動（残 pre_delay があれば FIRING へ）
func _commit_attack() -> void:
	_pending_target    = _valid_targets[_target_index]
	_pending_slot_data = _get_slot()

	# カーソル片付け（is_targeting_mode は FIRING 中も維持）
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	_valid_targets.clear()
	_target_index = 0
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null

	if _pre_delay_remaining <= 0.0:
		_execute_pending()
	else:
		_mode = Mode.FIRING


func _execute_pending() -> void:
	_mode = Mode.NORMAL
	character.is_targeting_mode = false
	_pre_delay_remaining = 0.0

	if not is_instance_valid(_pending_target):
		_pending_target    = null
		_pending_slot_data = {}
		return

	var sd:     Dictionary = _pending_slot_data
	var action: String     = str(sd.get("action", "melee"))

	if action == "melee":
		_execute_melee(_pending_target, sd)
	elif action == "ranged" or action == "ranged_area":
		_execute_ranged(_pending_target, sd)

	_pending_target    = null
	_pending_slot_data = {}


## ターゲットリストをリフレッシュ（ホールド中の毎フレーム更新）
func _refresh_targets() -> void:
	# キャンセル状態かどうかを先に記録する
	# （_target_index == size のとき prev_target が null になり、リセットされていたバグの修正）
	var was_cancel := _target_index >= _valid_targets.size()
	var prev_target: Character = null
	if not was_cancel:
		prev_target = _valid_targets[_target_index]

	_valid_targets = _get_sorted_targets()

	if _valid_targets.is_empty():
		_target_index = 0  # キャンセル選択状態（size=0 なので 0 >= size は true）
		_update_cursor()
		return

	# キャンセル状態だった場合はキャンセルを維持（0 にリセットしない）
	if was_cancel:
		_target_index = _valid_targets.size()
		_update_cursor()
		return

	# 前回選択していた敵が新リストにあれば維持
	if prev_target != null and is_instance_valid(prev_target):
		var idx := _valid_targets.find(prev_target)
		if idx >= 0:
			_target_index = idx
			_update_cursor()
			return

	# 消えた場合は先頭へ
	_target_index = 0
	_update_cursor()


func _cycle_target(dir: int) -> void:
	var total := _valid_targets.size() + 1  # 末尾がキャンセルスロット
	_target_index = (_target_index + dir + total) % total
	_update_cursor()


func _update_cursor() -> void:
	for t: Character in _valid_targets:
		if is_instance_valid(t):
			t.is_targeted = false
	if _cursor == null:
		return
	if _target_index >= _valid_targets.size():
		_cursor.visible = false  # キャンセル選択中は非表示
	else:
		_cursor.visible = true
		var tgt := _valid_targets[_target_index]
		_cursor.position = tgt.position
		tgt.is_targeted  = true


## 有効なターゲットを前方±45°優先・距離順でソートして返す
func _get_sorted_targets() -> Array[Character]:
	return _sort_targets(_get_valid_targets())


## 前方±45°の敵を距離順 → その他の敵を距離順の順でソート
func _sort_targets(targets: Array[Character]) -> Array[Character]:
	var forward: Array[Character] = []
	var others:  Array[Character] = []
	for t: Character in targets:
		if _is_in_forward_cone(t):
			forward.append(t)
		else:
			others.append(t)
	forward.sort_custom(func(a: Character, b: Character) -> bool:
		return _dist_to(a) < _dist_to(b))
	others.sort_custom(func(a: Character, b: Character) -> bool:
		return _dist_to(a) < _dist_to(b))
	var result: Array[Character] = []
	result.append_array(forward)
	result.append_array(others)
	return result


## キャラクターの向きから前方±45°コーン内にいるか判定
func _is_in_forward_cone(target: Character) -> bool:
	var fwd  := Vector2(Character.dir_to_vec(character.facing))
	var diff := Vector2(target.grid_pos - character.grid_pos)
	if diff == Vector2.ZERO:
		return false
	return fwd.dot(diff.normalized()) >= FORWARD_CONE_DOT


func _dist_to(target: Character) -> float:
	return Vector2(character.grid_pos).distance_to(Vector2(target.grid_pos))


## 攻撃キーが現在ホールド中かを返す
func _is_slot_held() -> bool:
	return Input.is_action_pressed("attack")


## 有効なターゲット一覧を返す（ソートなし）
## "melee" → マンハッタン距離、"ranged"/"ranged_area" → ユークリッド距離
func _get_valid_targets() -> Array[Character]:
	var sd:        Dictionary = _get_slot()
	var action:    String     = str(sd.get("action", "melee"))
	var range_val: int        = int(sd.get("range",  1))
	var result: Array[Character] = []
	for c: Character in blocking_characters:
		if not is_instance_valid(c):
			continue
		# 味方キャラクター（仲間NPC含む）は攻撃対象にしない
		if c.is_friendly:
			continue
		if action == "melee":
			# 飛行ターゲットへの近接攻撃は不可（地上→飛行・飛行→飛行）
			if c.is_flying:
				continue
			var dx: int = abs(c.grid_pos.x - character.grid_pos.x)
			var dy: int = abs(c.grid_pos.y - character.grid_pos.y)
			if dx + dy <= range_val:
				result.append(c)
		elif action == "ranged" or action == "ranged_area":
			var dist: float = Vector2(character.grid_pos).distance_to(Vector2(c.grid_pos))
			if dist <= float(range_val):
				result.append(c)
	return result


# --------------------------------------------------------------------------
# 攻撃実行
# --------------------------------------------------------------------------

func _execute_melee(target: Character, slot_data: Dictionary) -> void:
	var dmg_mult: float = float(slot_data.get("damage_mult", 1.0))
	character.face_toward(target.grid_pos)
	var raw_damage := int(float(character.attack_power) * dmg_mult)
	var is_magic   := (slot_data.get("type", "physical") as String) == "magic"
	SoundManager.play_attack(character)
	target.take_damage(raw_damage, 1.0, character, is_magic)
	SoundManager.play_hit(character)
	var skill_name: String = str(slot_data.get("name", "近接"))
	print("[Player] %s → %s  スキル%.1fx  HP:%d/%d" % \
			[skill_name, target.name, dmg_mult, target.hp, target.max_hp])


func _execute_ranged(target: Character, slot_data: Dictionary) -> void:
	var dmg_mult: float = float(slot_data.get("damage_mult", 1.0))
	character.face_toward(target.grid_pos)
	var raw_damage := int(float(character.attack_power) * dmg_mult)
	var is_magic   := (slot_data.get("type", "physical") as String) == "magic"
	SoundManager.play_attack(character)
	_spawn_projectile(target, raw_damage, is_magic)


func _spawn_projectile(target: Character, raw_damage: int, is_magic: bool = false) -> void:
	if map_node == null:
		return
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)
	proj.setup(character.position, target.position, true, target, raw_damage, 1.0,
			character, is_magic)


# --------------------------------------------------------------------------
# 移動
# --------------------------------------------------------------------------

func _get_input_direction() -> Vector2i:
	if Input.is_action_pressed("ui_right"): return Vector2i(1, 0)
	if Input.is_action_pressed("ui_left"):  return Vector2i(-1, 0)
	if Input.is_action_pressed("ui_down"):  return Vector2i(0, 1)
	if Input.is_action_pressed("ui_up"):    return Vector2i(0, -1)
	return Vector2i.ZERO


func _try_move(dir: Vector2i) -> void:
	var new_pos := character.grid_pos + dir
	if _can_move_to(new_pos):
		character.move_to(new_pos, MOVE_INTERVAL / GlobalConstants.game_speed)
	else:
		# 移動先に友好的キャラクターがいれば npc_bumped を発火する
		for blocker: Character in blocking_characters:
			if not is_instance_valid(blocker):
				continue
			if blocker.is_flying != character.is_flying:
				continue
			if new_pos in blocker.get_occupied_tiles() and blocker.is_friendly:
				npc_bumped.emit(blocker)
				break


## 移動可否を判定する（WALL・範囲外・同レイヤーキャラクター占有は不可）
func _can_move_to(pos: Vector2i) -> bool:
	if map_data != null:
		if not map_data.is_walkable_for(pos, character.is_flying):
			return false
	else:
		if not (pos.x >= 0 and pos.x < MapData.MAP_WIDTH \
				and pos.y >= 0 and pos.y < MapData.MAP_HEIGHT):
			return false
	for blocker: Character in blocking_characters:
		if not is_instance_valid(blocker):
			continue
		if blocker.is_flying != character.is_flying:
			continue
		if pos in blocker.get_occupied_tiles():
			return false
	return true


# --------------------------------------------------------------------------
# 消耗品
# --------------------------------------------------------------------------

## 消耗品スロットをグループ（item_type）単位で循環する（dir: +1=次 / -1=前）
func _cycle_consumable(dir: int) -> void:
	if character == null or character.character_data == null:
		return
	var cd   := character.character_data
	var list := cd.get_consumables()
	if list.is_empty():
		return

	# グループキーリスト（出現順・重複なし）を構築
	var group_keys: Array[String] = []
	var seen: Dictionary = {}
	for item_v: Variant in list:
		var itype := (item_v as Dictionary).get("item_type", "") as String
		if not seen.has(itype):
			seen[itype] = true
			group_keys.append(itype)

	# 現在の選択グループを特定
	var cur_type := ""
	if cd.selected_consumable_index < list.size():
		cur_type = (list[cd.selected_consumable_index] as Dictionary)\
			.get("item_type", "") as String
	var cur_grp := group_keys.find(cur_type)
	if cur_grp < 0:
		cur_grp = 0

	# 次グループへ循環
	var next_grp := (cur_grp + dir + group_keys.size()) % group_keys.size()
	var next_type := group_keys[next_grp]

	# next_type の最初のアイテムのインデックスへセット
	for i: int in range(list.size()):
		if (list[i] as Dictionary).get("item_type", "") == next_type:
			cd.selected_consumable_index = i
			break

	if consumable_bar != null:
		consumable_bar.refresh()


## 選択中の消耗品を使用する
func _use_selected_consumable() -> void:
	if character == null or character.character_data == null:
		return
	var cd   := character.character_data
	var item := cd.get_selected_consumable()
	if item.is_empty():
		return
	var effect: Dictionary = item.get("effect", {}) as Dictionary
	var heal_hp:    int = int(effect.get("heal_hp",    0))
	var restore_mp: int = int(effect.get("restore_mp", 0))
	# 使用条件チェック
	if heal_hp > 0 and character.hp >= character.max_hp:
		return
	if restore_mp > 0 and character.mp >= character.max_mp:
		return
	if heal_hp == 0 and restore_mp == 0:
		return

	var used_type := item.get("item_type", "") as String

	# 使用実行（heal / MP回復・効果音は use_consumable 内）
	character.use_consumable(item)

	# inventory から同グループの先頭1個を削除（remove_at で確実に1個だけ消す）
	var inv := cd.inventory
	for i: int in range(inv.size()):
		var entry := inv[i] as Dictionary
		if entry.get("item_type", "") == used_type \
				and entry.get("category", "") == "consumable":
			inv.remove_at(i)
			break

	# 使用後インデックス: 同グループに残りがあれば維持、なければクランプ
	var remaining := cd.get_consumables()
	var found_same := false
	for i: int in range(remaining.size()):
		if (remaining[i] as Dictionary).get("item_type", "") == used_type:
			cd.selected_consumable_index = i
			found_same = true
			break
	if not found_same:
		cd.selected_consumable_index = \
			clampi(cd.selected_consumable_index, 0, maxi(0, remaining.size() - 1))

	var item_name: String = item.get("item_name", "アイテム") as String
	var char_name: String = cd.character_name if not cd.character_name.is_empty() \
		else String(character.name)
	MessageLog.add_system("%s は %s を使った！" % [char_name, item_name])
	if consumable_bar != null:
		consumable_bar.refresh()


# --------------------------------------------------------------------------
# ユーティリティ
# --------------------------------------------------------------------------

## クラス定義 JSON を読み込む
func _read_class_json(class_id: String) -> Dictionary:
	var path := CLASS_JSON_DIR + class_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}
