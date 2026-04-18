class_name SkillExecutor
extends RefCounted

## Player / AI 両方から呼ばれる特殊行動の実処理層。
## 意思決定層（UnitAI / PlayerController）は caster / target / slot を用意し、
## ここにディスパッチするだけに留める。計算式・エフェクト・ログ出力を集約する。
##
## ステージ1: heal のみ移行済み。
## 残り（melee / ranged / flame_circle / water_stun / buff / rush / whirlwind /
## headshot / sliding）は段階的に移行予定。

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
