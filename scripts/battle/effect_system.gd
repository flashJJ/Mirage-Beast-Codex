## 效果系统 —— 解释 data/skills.json 中的效果列表
##
## 硬边界：只支持 constants.gd 中 EFFECT_OPS 列出的 10 个原语。
## ⚠️ 禁止为某张卡写特判逻辑 —— 一旦开口，后面每张卡都会变成特判。
##    配不出来的技能，应该改技能设计（改 JSON），而不是改这里的代码。

class_name EffectSystem
extends RefCounted

const C = preload("res://scripts/utils/constants.gd")
const DamageCalc = preload("res://scripts/battle/damage_calc.gd")

## 受嘲讽约束的效果原语：这些是"打出去"的，必须指向嘲讽者
## 治疗/护盾/净化等"对自己人"的原语不受嘲讽影响，否则会出现「被嘲讽后只能给敌人加血」的荒谬结果
const ATTACK_OPS := ["DAMAGE", "DEBUFF", "TAUNT"]


# ── 对外主入口 ────────────────────────────────────

## 解析并执行一个技能的全部效果。
## caster_index: 施法者单位索引（施放秘术卡时传"我方攻击力最高的存活单位"）
## manual_target: 手动目标（V0 无 UI，传 -1 走自动选择）
static func resolve(state: BattleState, caster_index: int, skill: Dictionary, manual_target: int = -1) -> void:
	if caster_index < 0 or caster_index >= state.units.size():
		return
	var effects: Array = skill.get("effects", [])
	if effects.is_empty():
		return

	var targets := pick_targets(state, caster_index, Dictionary(skill.get("target", {})), manual_target)
	if targets.is_empty():
		return

	var taunt_target := taunt_source(state, caster_index)

	for e in effects:
		var eff: Dictionary = e
		var op := String(eff.get("op", ""))
		var use_targets: Array = ([taunt_target] if (taunt_target >= 0 and ATTACK_OPS.has(op)) else targets)
		for t in use_targets:
			_apply_one(state, caster_index, int(t), eff, op)


# ── 嘲讽约束 ──────────────────────────────────────

## 返回「本回合该单位必须攻击的对象」索引；无嘲讽约束返回 -1。
## 约束成立条件：嘲讽者存活、且与施法者不同阵营、且嘲讽仍在持续回合内。
static func taunt_source(state: BattleState, caster_index: int) -> int:
	if caster_index < 0 or caster_index >= state.units.size():
		return -1
	var caster: Dictionary = state.units[caster_index]
	var by: int = int(caster.get("taunted_by", -1))
	if by < 0 or by >= state.units.size():
		return -1
	if int(caster.get("taunt_turns", 0)) <= 0:
		return -1
	var taunter: Dictionary = state.units[by]
	if not bool(taunter.get("alive", false)):
		return -1
	if int(taunter.get("side", -1)) == int(caster.get("side", -1)):
		return -1
	return by


# ── 目标选择 ──────────────────────────────────────

static func pick_targets(state: BattleState, caster_index: int, target_cfg: Dictionary, manual_target: int) -> Array:
	var caster: Dictionary = state.units[caster_index]
	var caster_side: int = int(caster.get("side", 0))

	var side_key := String(target_cfg.get("side", "enemy"))
	var target_side: int
	match side_key:
		"ally":
			target_side = caster_side
		"self":
			return [caster_index]
		_:
			target_side = 1 - caster_side

	var pool := state.living_indices(target_side)
	if pool.is_empty():
		return []

	var select := String(target_cfg.get("select", "lowest_hp"))
	var count := int(target_cfg.get("count", 1))
	if count <= 0:
		count = pool.size()

	match select:
		"lowest_hp":
			pool.sort_custom(func(a, b): return int(state.units[a].get("hp", 0)) < int(state.units[b].get("hp", 0)))
		"highest_atk":
			pool.sort_custom(func(a, b): return int(state.units[a].get("atk", 0)) > int(state.units[b].get("atk", 0)))
		"front":
			pool.sort_custom(func(a, b): return int(state.units[a].get("slot", 0)) < int(state.units[b].get("slot", 0)))
		"back":
			pool.sort_custom(func(a, b): return int(state.units[a].get("slot", 0)) > int(state.units[b].get("slot", 0)))
		"random":
			pool.shuffle()
		"manual":
			if manual_target >= 0 and state.living_indices(target_side).has(manual_target):
				return [manual_target]
			pool.sort_custom(func(a, b): return int(state.units[a].get("hp", 0)) < int(state.units[b].get("hp", 0)))
		"all":
			return pool
		_:
			pass

	return pool.slice(0, mini(count, pool.size()))


# ── 单个效果原语 ──────────────────────────────────

static func _apply_one(state: BattleState, caster_index: int, target: int, eff: Dictionary, op: String) -> void:
	var caster: Dictionary = state.units[caster_index]
	var side: int = int(caster.get("side", 0))
	var power := int(eff.get("power", 0))
	var scale_key := String(eff.get("scale", "atk"))

	match op:
		"DAMAGE":
			var repeat := int(eff.get("repeat", 0))
			var pierce := int(eff.get("pierce", 0))
			var times := 1 + maxi(repeat, 0)
			for _i in times:
				deal_damage(state, caster_index, target, power, pierce)

		"HEAL":
			var amount := DamageCalc.heal_amount(caster, power, scale_key)
			state.apply_heal(target, amount)

		"SHIELD":
			var amount := DamageCalc.shield_amount(caster, power, scale_key)
			state.apply_shield(target, amount)

		"BUFF", "DEBUFF":
			state.apply_stat_mod(target, String(eff.get("stat", "atk")), power, int(eff.get("duration", 1)))

		"DRAW":
			state.draw(side, int(eff.get("count", 1)))

		"ENERGY":
			state.energy[side] = mini(state.energy[side] + int(eff.get("amount", 1)), C.MAX_ENERGY)

		"PURIFY":
			state.purify(target, int(eff.get("count", 1)))

		"TAUNT":
			if target >= 0 and target < state.units.size():
				var u: Dictionary = state.units[target]
				u["taunted_by"] = caster_index
				u["taunt_turns"] = int(eff.get("duration", 1))

		"SUMMON":
			push_warning("[EffectSystem] SUMMON 尚未实现（card_id=%s）" % String(eff.get("card_id", "?")))

		_:
			push_error("[EffectSystem] 未知效果原语：%s" % op)


# ── 伤害入口（含反制触发）────────────────────────

## 统一伤害入口：计算 → 应用 → 触发目标的 on_damaged 反制技能
static func deal_damage(state: BattleState, source_index: int, target: int, power: int, pierce: int) -> int:
	if source_index < 0 or target < 0 or target >= state.units.size():
		return 0
	var attacker: Dictionary = state.units[source_index]
	var defender: Dictionary = state.units[target]
	if not bool(defender.get("alive", false)):
		return 0

	var dmg := DamageCalc.damage(attacker, defender, power, pierce, state.chart, state.rng)
	state.apply_damage(target, dmg, source_index)

	# 反制：目标存活时触发其 on_damaged 技能
	if bool(state.units[target].get("alive", false)):
		_trigger(state, target, "on_damaged", source_index)

	return dmg


# ── 触发型技能 ────────────────────────────────────

static func _trigger(state: BattleState, unit_index: int, trigger: String, manual_target: int = -1) -> void:
	if unit_index < 0 or unit_index >= state.units.size():
		return
	var u: Dictionary = state.units[unit_index]
	if not bool(u.get("alive", false)):
		return
	for skill_id in (u.get("skills", []) as Array):
		if not state.skills_db.has(skill_id):
			continue
		var skill: Dictionary = state.skills_db[skill_id]
		if String(skill.get("trigger", "active")) != trigger:
			continue
		resolve(state, unit_index, skill, manual_target)


## 单位入场时触发 on_play
static func on_play(state: BattleState, unit_index: int) -> void:
	_trigger(state, unit_index, "on_play")


## 回合结束时触发 turn_end
static func on_turn_end(state: BattleState, side: int) -> void:
	for i in state.living_indices(side):
		_trigger(state, i, "turn_end")
