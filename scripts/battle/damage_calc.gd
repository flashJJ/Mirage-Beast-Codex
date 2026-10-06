## 伤害与治疗计算 —— 纯函数，无副作用，便于单测与批量模拟
##
## 全部使用定点整数运算（千分比），无浮点，保证结果可复现。
##
## DMG = ATK x 技能倍率 x 1000/(1000 + DEF x DEF_FACTOR/1000 x (1 - 穿透))
##       x 克制系数 x 站位系数 x 暴击系数 x RNG(0.95~1.05)
##
## 减伤是**乘性**的（F43）。不要用固定减算：那会在「攻防接近」的区间
## 产生阈值式的等级悬崖（Lv7→Lv8 胜率掉 49 个百分点），见 BALANCE-ANALYSIS §3 P1。

class_name DamageCalc
extends RefCounted

const C = preload("res://scripts/utils/constants.gd")


## 计算伤害。attacker / defender 为 BattleState 中的 unit 字典。
static func damage(
	attacker: Dictionary,
	defender: Dictionary,
	power: int,
	pierce: int,
	chart: Dictionary,
	rng: BattleRNG
) -> int:
	var atk: int = int(attacker.get("atk", 0))
	var def: int = int(defender.get("def", 0))

	# 1) 基础伤害
	var base: int = (atk * power) / C.FIXED_SCALE

	# 2) 防御减免（乘性，收益递减，无阈值）—— 穿透按比例削减防御贡献
	var def_val: int = (def * C.DEF_FACTOR) / C.FIXED_SCALE
	if pierce > 0:
		def_val = (def_val * (C.FIXED_SCALE - pierce)) / C.FIXED_SCALE

	var dmg: int = (base * C.FIXED_SCALE) / (C.FIXED_SCALE + def_val)

	# 3) 属性克制
	var mult: int = element_multiplier(chart, String(attacker.get("element", "")),
									   String(defender.get("element", "")))
	dmg = (dmg * mult) / C.FIXED_SCALE

	# 4) 站位修正
	if int(defender.get("slot", 0)) >= 3:
		dmg = (dmg * C.BACK_ROW_DAMAGE_TAKEN) / C.FIXED_SCALE
	if int(attacker.get("slot", 0)) >= 3:
		dmg = (dmg * C.BACK_ROW_DAMAGE_DEALT) / C.FIXED_SCALE

	# 5) 暴击
	if rng.range_int(0, 999) < C.CRIT_BASE_RATE:
		dmg = (dmg * C.CRIT_MULT) / C.FIXED_SCALE

	# 6) 随机浮动 ±5%
	var f := rng.range_int(C.DMG_FLOAT_MIN, C.DMG_FLOAT_MAX)
	dmg = (dmg * f) / C.FIXED_SCALE

	return maxi(dmg, 1)


## 伤害估算（不含暴击与随机浮动）—— 给 AI 判断「这一下能不能打死」用。
## 必须是纯函数：AI 若为此消耗 RNG，会改变后续随机序列，破坏可复现性。
static func estimate(attacker: Dictionary, defender: Dictionary, power: int, pierce: int, chart: Dictionary) -> int:
	var atk: int = int(attacker.get("atk", 0))
	var def: int = int(defender.get("def", 0))
	var base: int = (atk * power) / C.FIXED_SCALE
	var def_val: int = (def * C.DEF_FACTOR) / C.FIXED_SCALE
	if pierce > 0:
		def_val = (def_val * (C.FIXED_SCALE - pierce)) / C.FIXED_SCALE
	var dmg: int = (base * C.FIXED_SCALE) / (C.FIXED_SCALE + def_val)
	var mult: int = element_multiplier(chart, String(attacker.get("element", "")), String(defender.get("element", "")))
	dmg = (dmg * mult) / C.FIXED_SCALE
	if int(defender.get("slot", 0)) >= 3:
		dmg = (dmg * C.BACK_ROW_DAMAGE_TAKEN) / C.FIXED_SCALE
	if int(attacker.get("slot", 0)) >= 3:
		dmg = (dmg * C.BACK_ROW_DAMAGE_DEALT) / C.FIXED_SCALE
	return maxi(dmg, 1)


static func element_multiplier(chart: Dictionary, atk_elem: String, def_elem: String) -> int:
	if chart.has(atk_elem):
		var row: Dictionary = chart[atk_elem]
		if row.has(def_elem):
			return int(row[def_elem])
	return C.ELEMENT_NEUTRAL


## 治疗量。power 为千分比，scale 决定以哪项属性为基准。
static func heal_amount(caster: Dictionary, power: int, scale_key: String) -> int:
	var base_stat: int = int(caster.get(scale_key, 0))
	return (base_stat * power) / C.FIXED_SCALE


## 护盾值
static func shield_amount(caster: Dictionary, power: int, scale_key: String) -> int:
	return heal_amount(caster, power, scale_key)


## 单卡战力（CP）
static func combat_power(u: Dictionary, level: int, break_mult: int = 1000) -> int:
	var atk: int = int(u.get("atk", 0))
	var hp: int = int(u.get("hp", 0))
	var def: int = int(u.get("def", 0))
	var spd: int = int(u.get("spd", 0))

	var raw: int = (atk * C.CP_W_ATK + hp * C.CP_W_HP + def * C.CP_W_DEF + spd * C.CP_W_SPD)
	raw /= C.FIXED_SCALE

	var level_coef: int = C.FIXED_SCALE + C.LEVEL_COEF_PER_LV * (level - 1)
	return (raw * level_coef / C.FIXED_SCALE) * break_mult / C.FIXED_SCALE
