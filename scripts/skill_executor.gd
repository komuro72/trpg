class_name SkillExecutor
extends RefCounted

## Player / AI 両方から呼ばれる特殊行動の実処理層。
## 意思決定層（UnitAI / PlayerController）は caster / target / slot を用意し、
## ここにディスパッチするだけに留める。計算式・エフェクト・ログ出力を集約する。
##
## ステージ1: heal 移行済み。
## ステージ2: melee / ranged 移行済み（Z 通常攻撃）。
## ステージ3a: flame_circle / water_stun / buff 移行済み（V 特殊攻撃・複雑3種）。
## ステージ3b: rush / whirlwind / headshot / sliding 移行済み（V 特殊攻撃・近接射撃4種）。
## 全10種の SkillExecutor 抽出完了。dark-lord のワープ・炎陣はキュー外のため別タスク。

## execute_heal の結果を呼び出し元に伝えるための enum
## FAILED        : energy 不足等で何も起きなかった
## HEALED        : 通常回復を適用した（Player 側で healed_npc_member シグナル対象）
## UNDEAD_DAMAGED: アンデッドにダメージを与えた
enum HealResult { FAILED, HEALED, UNDEAD_DAMAGED }


## Z スロット（回復）の実処理。
## Player / AI 共通で使用。計算式・エフェクト・ログ出力を一元化する。
static func execute_heal(caster: Character, target: Character, slot: Dictionary) -> int:
	if caster == null or not is_instance_valid(caster):
		return HealResult.FAILED
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		return HealResult.FAILED

	# エネルギー消費（不足なら何もしない）
	var cost := _slot_cost(slot)
	if cost > 0 and not caster.use_energy(cost):
		return HealResult.FAILED

	caster.face_toward(target.grid_pos)
	caster.spawn_heal_effect("cast")

	var skill_name := str(slot.get("name", "回復"))
	var power: int = caster.power

	# アンデッド特効：敵対陣営のアンデッドには魔法ダメージとして適用
	# base_damage = power × ATTACK_TYPE_MULT[magic] × damage_mult
	if target.character_data != null and target.character_data.is_undead \
			and target.is_friendly != caster.is_friendly:
		var damage_mult := float(slot.get("damage_mult", 1.0))
		var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("magic", 1.0)
		var base_damage := maxi(1, int(float(power) * type_mult * damage_mult))
		target.take_damage(base_damage, 1.0, caster, true)
		target.spawn_heal_effect("hit")
		MessageLog.add_combat("[%s] %s → %s %d DMG（アンデッド特効）" % \
			[skill_name, _char_name(caster), _char_name(target), base_damage])
		return HealResult.UNDEAD_DAMAGED

	# 通常回復：heal_mult で回復量を計算（heal() 内で HEAL SE 再生）
	var heal_mult := float(slot.get("heal_mult", 0.3))
	var heal_amount := maxi(1, int(float(power) * heal_mult))
	var hp_before := target.hp
	target.heal(heal_amount)
	target.spawn_heal_effect("hit")
	target.log_heal(caster, heal_amount, hp_before)
	return HealResult.HEALED


## Z スロット（近接攻撃）の実処理。
## Player / AI 共通で使用。計算式・SE・ダメージ適用を一元化する。
## slot: クラス JSON の slots.Z または同等辞書。damage_mult / type / cost を参照
## 戻り値: true なら攻撃発動、false なら不発（対象無効・エネルギー不足）
static func execute_melee(attacker: Character, target: Character, slot: Dictionary) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		return false

	var cost := _slot_cost(slot)
	if cost > 0 and not attacker.use_energy(cost):
		return false

	var dmg_mult: float = float(slot.get("damage_mult", 1.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)
	var raw_damage := int(float(attacker.power) * dmg_mult * type_mult)
	var is_magic := (slot.get("type", "physical") as String) == "magic"

	attacker.face_toward(target.grid_pos)
	SoundManager.play_attack_from(attacker)
	target.take_damage(raw_damage, 1.0, attacker, is_magic)
	SoundManager.play_hit_from(attacker)
	return true


## Z スロット（遠距離攻撃）の実処理。
## Player / AI 共通で使用。飛翔体（Projectile）を生成して命中時に take_damage。
## opts: 補助パラメータ（Lich の水弾交互など）
##   "is_water": bool — 水弾フラグを強制上書き（省略時は class_id=="magician-water" で自動判定）
## 戻り値: true なら発射、false なら不発
static func execute_ranged(attacker: Character, target: Character, slot: Dictionary,
		opts: Dictionary = {}) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		return false

	var cost := _slot_cost(slot)
	if cost > 0 and not attacker.use_energy(cost):
		return false

	var dmg_mult: float = float(slot.get("damage_mult", 1.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
	var raw_damage := int(float(attacker.power) * dmg_mult * type_mult)
	var is_magic := (slot.get("type", "physical") as String) == "magic"

	attacker.face_toward(target.grid_pos)
	SoundManager.play_attack_from(attacker)
	_spawn_projectile(attacker, target, raw_damage, is_magic, opts)
	return true


## 飛翔体を生成して setup する（execute_ranged 内部ヘルパー）
## is_water 判定: opts["is_water"] > class_id=="magician-water" の順で決定
## projectile_type: character_data.projectile_type（demon の thunder_bullet 等）
static func _spawn_projectile(attacker: Character, target: Character,
		raw_damage: int, is_magic: bool, opts: Dictionary) -> void:
	var map_node := attacker.get_parent()
	if map_node == null:
		return
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)

	var is_water: bool
	if opts.has("is_water"):
		is_water = bool(opts.get("is_water"))
	else:
		is_water = attacker.character_data != null \
				and attacker.character_data.class_id == "magician-water"
	var ptype: String = attacker.character_data.projectile_type \
			if attacker.character_data != null else ""

	proj.setup(attacker.position, target.position, true, target,
			raw_damage, 1.0, attacker, is_magic, 0.0, is_water, ptype)


## V スロット（炎陣）の実処理。
## magician-fire 専用。自分を中心に半径 range マスの炎ゾーンを設置し、継続ダメージを与える。
## slot: range / damage_mult / duration / tick_interval / cost / name を参照
## potential_targets: 炎の判定対象候補（Player 側 blocking_characters / AI 側 _all_members）
## 戻り値: true なら発動、false なら不発（エネルギー不足・親ノードなし）
static func execute_flame_circle(caster: Character, slot: Dictionary,
		potential_targets: Array = []) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	var map_node := caster.get_parent()
	if map_node == null:
		return false

	var cost := _slot_cost(slot)
	if cost > 0 and not caster.use_energy(cost):
		return false

	var dmg_mult: float = float(slot.get("damage_mult", 0.8))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("magic", 1.0)
	var damage := maxi(1, int(float(caster.power) * dmg_mult * type_mult))
	var radius: int = int(slot.get("range", 3))
	var duration: float = float(slot.get("duration", 2.5))
	var tick_ivl: float = float(slot.get("tick_interval", 0.5))

	var flame := FlameCircle.new()
	flame.z_index = 1
	map_node.add_child(flame)
	flame.setup(caster.position, caster.grid_pos, radius, damage,
			duration, tick_ivl, caster, potential_targets)
	SoundManager.play_from(SoundManager.FLAME_SHOOT, caster)

	# 自然言語バトルメッセージ（MessageWindow に表示）
	var caster_name := Character._battle_name(caster)
	var segs := Character._make_segs([
		[caster_name, Character._party_name_color(caster)],
		["が炎陣を設置した", Color.WHITE],
	])
	MessageLog.add_battle(caster.character_data, null,
		"%sが炎陣を設置した" % caster_name, caster, null, segs)
	MessageLog.add_combat("[炎陣] %s が炎を設置！（%d秒間）" % \
			[_char_name(caster), int(duration)])
	return true


## V スロット（無力化水魔法）の実処理。
## magician-water 専用。水弾を発射し、命中時にダメージ＋スタンを付与する。
## Projectile 側で damage と stun を一括適用するため直接 take_damage / apply_stun は呼ばない。
## slot: damage_mult / duration（スタン秒数）/ cost / name を参照
## 戻り値: true なら発射、false なら不発
static func execute_water_stun(caster: Character, target: Character, slot: Dictionary) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		return false
	var map_node := caster.get_parent()
	if map_node == null:
		return false

	var cost := _slot_cost(slot)
	if cost > 0 and not caster.use_energy(cost):
		return false

	var dmg_mult: float = float(slot.get("damage_mult", 0.5))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
	var raw_damage := int(float(caster.power) * dmg_mult * type_mult)
	var stun_duration: float = float(slot.get("duration", 3.0))

	caster.face_toward(target.grid_pos)
	SoundManager.play_from(SoundManager.MAGIC_SHOOT, caster)
	# 飛翔体を発射（着弾時にダメージ＋スタン付与）
	# Projectile.setup: from, to, will_hit, target, damage, multiplier, attacker,
	#                   is_magic, stun_duration, is_water, proj_type
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)
	proj.setup(caster.position, target.position, true, target,
			raw_damage, 1.0, caster, true, stun_duration, true, "")

	var skill_name := str(slot.get("name", "水魔法"))
	MessageLog.add_combat("[%s] %s → %s" % \
			[skill_name, _char_name(caster), _char_name(target)])
	return true


## V スロット（防御バフ）の実処理。
## healer 専用。対象に防御バフを duration 秒間付与する。自分自身も対象可・方向制限なし。
## 重複付与時はタイマーリセット＋エフェクト再生成（apply_defense_buff 内部仕様）。
## slot: duration / cost / name を参照
## 戻り値: true なら付与、false なら不発
static func execute_buff(caster: Character, target: Character, slot: Dictionary) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		return false

	var cost := _slot_cost(slot)
	if cost > 0 and not caster.use_energy(cost):
		return false

	var buff_duration: float = float(slot.get("duration", 0.0))
	caster.face_toward(target.grid_pos)
	target.apply_defense_buff(buff_duration)
	SoundManager.play_from(SoundManager.HEAL, caster)
	caster.spawn_heal_effect("cast")
	target.spawn_heal_effect("hit")

	var skill_name := str(slot.get("name", "防御バフ"))
	MessageLog.add_combat("[%s] %s → %s" % \
			[skill_name, _char_name(caster), _char_name(target)])
	return true


## V スロット（突進斬り・fighter-sword）の実処理。
## 向いている方向に最大 3 マス走査し、経路上の敵（step 1〜2 のみ）に damage を与える。
## 空きマスに到達したら着地位置として返す（caller が実際の移動を行う）。
## slot: damage_mult / cost / name を参照（range は固定 2、着地探索は 3 マスまで）
## map_data: is_walkable_for を呼ぶための MapData
## potential_targets: 敵の候補配列（Player=blocking_characters / AI=_all_members）
## 戻り値: {"landing_pos": Vector2i, "hit_count": int}
static func execute_rush(attacker: Character, slot: Dictionary,
		map_data, potential_targets: Array = []) -> Dictionary:
	var result := {"landing_pos": attacker.grid_pos, "hit_count": 0}
	if attacker == null or not is_instance_valid(attacker):
		return result
	if map_data == null:
		return result

	var cost := _slot_cost(slot)
	if cost > 0 and not attacker.use_energy(cost):
		return result

	var dmg_mult: float = float(slot.get("damage_mult", 1.2))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)
	var raw_damage := int(float(attacker.power) * dmg_mult * type_mult)
	var dir := Character.dir_to_vec(attacker.facing)
	var landing_pos := attacker.grid_pos
	var hit_count := 0

	# 最大 3 マス先まで探索（step 1〜2 で攻撃、空きマスに到達したら着地）
	for step: int in range(1, 4):
		var check_pos := attacker.grid_pos + Vector2i(dir) * step
		if not map_data.is_walkable_for(check_pos, false):
			break  # 壁・障害物で停止
		var occupant := _find_hostile_at(check_pos, attacker, potential_targets)
		if occupant != null:
			if step <= 2:
				var hp_before := occupant.hp
				occupant.take_damage(raw_damage, 1.0, attacker, false, true)
				_emit_v_skill_battle_msg("突進斬り", attacker, occupant, hp_before - occupant.hp)
				SoundManager.play_attack_from(attacker)
				hit_count += 1
			continue  # 敵がいるマスは着地せず通過
		landing_pos = check_pos
		break  # 空きマスに到達したら停止

	if hit_count == 0:
		var atk_name := Character._battle_name(attacker)
		var segs := Character._make_segs([
			[atk_name, Character._party_name_color(attacker)],
			["が突進斬りを放ったが敵に当たらなかった", Color.WHITE],
		])
		MessageLog.add_battle(attacker.character_data, null,
			"%sが突進斬りを放ったが敵に当たらなかった" % atk_name, attacker, null, segs)

	result["landing_pos"] = landing_pos
	result["hit_count"] = hit_count
	return result


## V スロット（振り回し・fighter-axe）の実処理。
## 自分を中心に隣接 8 マスの敵全員に damage を与える。
## slot: damage_mult / cost / name を参照
## potential_targets: 敵の候補配列
## 戻り値: 命中数（caller が空振り演出を出したい場合に使える）
static func execute_whirlwind(attacker: Character, slot: Dictionary,
		potential_targets: Array = []) -> int:
	if attacker == null or not is_instance_valid(attacker):
		return 0

	var cost := _slot_cost(slot)
	if cost > 0 and not attacker.use_energy(cost):
		return 0

	var dmg_mult: float = float(slot.get("damage_mult", 1.0))
	var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("melee", 1.0)
	var raw_damage := int(float(attacker.power) * dmg_mult * type_mult)
	var hit_count := 0

	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var pos := attacker.grid_pos + Vector2i(dx, dy)
			var occupant := _find_hostile_at(pos, attacker, potential_targets)
			if occupant != null:
				var hp_before := occupant.hp
				occupant.take_damage(raw_damage, 1.0, attacker, false, true)
				_emit_v_skill_battle_msg("振り回し", attacker, occupant, hp_before - occupant.hp)
				hit_count += 1

	SoundManager.play_attack_from(attacker)
	if hit_count == 0:
		var atk_name := Character._battle_name(attacker)
		var segs := Character._make_segs([
			[atk_name, Character._party_name_color(attacker)],
			["が振り回したが空振りに終わった", Color.WHITE],
		])
		MessageLog.add_battle(attacker.character_data, null,
			"%sが振り回したが空振りに終わった" % atk_name, attacker, null, segs)
	return hit_count


## V スロット（ヘッドショット・archer）の実処理。
## target.instant_death_immune をチェックし、
##   false → 即死（hp=0 + die()）
##   true  → 通常の 3 倍ダメージ（slot.damage_mult を参照）
## 視覚的には両方とも飛翔体を発射（ただし damage は独立に適用。Projectile は画像のみ）。
## slot: damage_mult（3.0 既定）/ cost / name を参照
## 戻り値: true なら発動、false なら不発
static func execute_headshot(attacker: Character, target: Character, slot: Dictionary) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	if target == null or not is_instance_valid(target) or target.hp <= 0:
		return false
	var map_node := attacker.get_parent()
	if map_node == null:
		return false

	var cost := _slot_cost(slot)
	if cost > 0 and not attacker.use_energy(cost):
		return false

	attacker.face_toward(target.grid_pos)
	SoundManager.play_from(SoundManager.ARROW_SHOOT, attacker)

	var is_immune: bool = false
	if target.character_data != null:
		is_immune = bool(target.character_data.instant_death_immune)

	var atk_name := Character._battle_name(attacker)
	var tgt_name := Character._battle_name(target)
	var atk_col := Character._party_name_color(attacker)
	var tgt_col := Character._party_name_color(target)

	# 飛翔体を視覚的に発射（ダメージは別途適用するため damage=0 でも可だが、
	# 旧 Player 実装と合わせて projectile にダメージを持たせる）
	var proj := Projectile.new()
	proj.z_index = 2
	map_node.add_child(proj)

	if is_immune:
		# ボス級：×3 ダメージ（battle メッセージは抑制して SkillExecutor 側で segments 出力）
		var dmg_mult: float = float(slot.get("damage_mult", 3.0))
		var type_mult: float = GlobalConstants.ATTACK_TYPE_MULT.get("ranged", 1.0)
		var raw_damage := int(float(attacker.power) * dmg_mult * type_mult)
		proj.setup(attacker.position, target.position, false, target,
				0, 1.0, attacker, false, 0.0, false, "")
		target.take_damage(raw_damage, 1.0, attacker, false, true)
		var dmg_col := Character._damage_label_color(GlobalConstants.DAMAGE_LEVEL_LARGE)
		var segs := Character._make_segs([
			[atk_name, atk_col], ["がヘッドショットで", Color.WHITE],
			[tgt_name, tgt_col], ["に", Color.WHITE],
			["大ダメージ", dmg_col], ["を与えた", Color.WHITE],
		])
		MessageLog.add_battle(attacker.character_data, target.character_data,
			"%sがヘッドショットで%sに大ダメージを与えた" % [atk_name, tgt_name],
			attacker, target, segs)
		MessageLog.add_combat("[ヘッドショット] %s → %s ×%.1fダメージ" % \
				[_char_name(attacker), _char_name(target), dmg_mult])
	else:
		# 非ボス：即死（防御・耐性を無視して直接 hp=0 + die()）
		proj.setup(attacker.position, target.position, false, target,
				0, 1.0, attacker, false, 0.0, false, "")
		target.last_attacker = attacker
		target.hp = 0
		target.die()
		var kill_col := Character._damage_label_color(GlobalConstants.DAMAGE_LEVEL_LARGE + 9999)
		var segs2 := Character._make_segs([
			[atk_name, atk_col], ["がヘッドショットで", Color.WHITE],
			[tgt_name, tgt_col], ["を", Color.WHITE],
			["仕留めた", kill_col, true],
		])
		MessageLog.add_battle(attacker.character_data, target.character_data,
			"%sがヘッドショットで%sを仕留めた" % [atk_name, tgt_name],
			attacker, target, segs2)
		MessageLog.add_combat("[ヘッドショット] %s → %s 即死！" % \
				[_char_name(attacker), _char_name(target)])
	return true


## V スロット（スライディング・scout）の実処理。
## 向いている方向に最大 3 マス走査し、敵味方を無視して通過可能な着地位置を探す。
## ダメージは発生しない（包囲脱出用）。caller が実際の移動・無敵フラグ管理を行う。
## slot: cost を参照
## map_data: is_walkable_for を呼ぶための MapData
## potential_targets: 着地判定で無視するキャラクター候補（Player=blocking_characters / AI=_all_members）
## 戻り値: 着地位置（caller が character を実際に動かす）
static func execute_sliding(attacker: Character, slot: Dictionary,
		map_data, potential_targets: Array = []) -> Vector2i:
	if attacker == null or not is_instance_valid(attacker):
		return Vector2i.ZERO
	if map_data == null:
		return attacker.grid_pos

	var cost := _slot_cost(slot)
	if cost > 0 and not attacker.use_energy(cost):
		return attacker.grid_pos

	var dir := Character.dir_to_vec(attacker.facing)
	var landing_pos := attacker.grid_pos

	for step: int in range(1, 4):
		var check_pos := attacker.grid_pos + Vector2i(dir) * step
		if not map_data.is_walkable_for(check_pos, attacker.is_flying):
			break  # 壁・障害物で停止
		if _find_any_occupant_at(check_pos, attacker, potential_targets) != null:
			continue  # 敵・味方ともすり抜け
		landing_pos = check_pos

	SoundManager.play_from(SoundManager.MELEE_DAGGER, attacker)
	var atk_name := Character._battle_name(attacker)
	var segs := Character._make_segs([
		[atk_name, Character._party_name_color(attacker)],
		["がスライディングで突進した", Color.WHITE],
	])
	MessageLog.add_battle(attacker.character_data, null,
		"%sがスライディングで突進した" % atk_name, attacker, null, segs)
	return landing_pos


## potential_targets の中から pos にいる「attacker と敵対陣営」の生存キャラクターを返す。
## rush / whirlwind のターゲット判定用。
static func _find_hostile_at(pos: Vector2i, attacker: Character,
		potential_targets: Array) -> Character:
	for c: Variant in potential_targets:
		if not is_instance_valid(c):
			continue
		var ch := c as Character
		if ch == null or ch == attacker or ch.hp <= 0:
			continue
		if ch.is_friendly == attacker.is_friendly:
			continue
		if pos in ch.get_occupied_tiles():
			return ch
	return null


## potential_targets の中から pos にいる任意の生存キャラクター（敵味方問わず）を返す。
## sliding の通過判定用。
static func _find_any_occupant_at(pos: Vector2i, attacker: Character,
		potential_targets: Array) -> Character:
	for c: Variant in potential_targets:
		if not is_instance_valid(c):
			continue
		var ch := c as Character
		if ch == null or ch == attacker or ch.hp <= 0:
			continue
		if pos in ch.get_occupied_tiles():
			return ch
	return null


## V スロット特殊攻撃の被弾メッセージ（rush / whirlwind 等で個別ヒットごとに呼ぶ）。
## "○○が{skill_name}で△△を攻撃し、{大}ダメージを与えた" の自然言語 + segments 色分け。
static func _emit_v_skill_battle_msg(skill_name: String, atk: Character,
		def: Character, dmg: int) -> void:
	if MessageLog == null or atk == null or def == null:
		return
	var atk_name := Character._battle_name(atk)
	var def_name := Character._battle_name(def)
	var dmg_val := maxi(1, dmg)
	var dmg_label := Character._damage_label(dmg_val)
	var dmg_color := Character._damage_label_color(dmg_val)
	var dmg_bold := Character._damage_is_huge(dmg_val)
	var msg := "%sが%sで%sを攻撃し、%sを与えた" % [atk_name, skill_name, def_name, dmg_label]
	var segs := Character._make_segs([
		[atk_name, Character._party_name_color(atk)], ["が" + skill_name + "で", Color.WHITE],
		[def_name, Character._party_name_color(def)], ["を攻撃し、", Color.WHITE],
		[dmg_label, dmg_color, dmg_bold], ["を与えた", Color.WHITE],
	])
	MessageLog.add_battle(atk.character_data, def.character_data, msg, atk, def, segs)


## スロット定義から energy コストを読む。
## 新形式 "cost" を優先し、旧形式 "mp_cost" / "sp_cost" にフォールバック。
static func _slot_cost(slot: Dictionary) -> int:
	if slot.has("cost"):
		return int(slot.get("cost", 0))
	var mp_c: int = int(slot.get("mp_cost", 0))
	var sp_c: int = int(slot.get("sp_cost", 0))
	return maxi(mp_c, sp_c)


## キャラクター表示名を返す
static func _char_name(c: Character) -> String:
	if c == null or not is_instance_valid(c):
		return "?"
	if c.character_data != null and not c.character_data.character_name.is_empty():
		return c.character_data.character_name
	return str(c.name)
