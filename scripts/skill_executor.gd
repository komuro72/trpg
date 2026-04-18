class_name SkillExecutor
extends RefCounted

## Player / AI 両方から呼ばれる特殊行動の実処理層。
## 意思決定層（UnitAI / PlayerController）は caster / target / slot を用意し、
## ここにディスパッチするだけに留める。計算式・エフェクト・ログ出力を集約する。
##
## ステージ1: heal 移行済み。
## ステージ2: melee / ranged 移行済み（Z 通常攻撃）。
## ステージ3a: flame_circle / water_stun / buff 移行済み（V 特殊攻撃・複雑3種）。
## 残り（rush / whirlwind / headshot / sliding）は段階的に移行予定。

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
