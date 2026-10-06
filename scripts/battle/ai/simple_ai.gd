## 简易对战 AI —— 评分式决策，不使用 LLM
##
## ⚠️ 设计决策：绝不使用 LLM 做出牌决策。
##    理由：① 每回合等待 5~10 秒毁掉节奏；② 输出不确定，无法批量模拟做平衡；
##          ③ 破坏战斗的确定性（回放与复盘失效）；④ 规则 AI 在此任务上远优于 LLM。
##
## 三档难度（F6）：差异不在"数值加成"（那样只是让对手变肉），而在**决策质量**
##
## | 档位 | 主动失误 | 目标选择 | 技能选择 | 治疗阈值 |
## |---|---|---|---|---|
## | easy   | 20% 跳过 | 敌方血量最低 | 第一个用得起的 | < 50% |
## | normal | 8% 跳过  | 优先"能打死"的，其次血最少 | 第一个用得起的 | < 60% |
## | hard   | 0%       | 优先"能打死"的，其次威胁最高 | 伤害期望最高的 | < 70% |
##
## 关键：目标选择用 DamageCalc.estimate（纯函数，不消耗 RNG），
##       否则 AI 的试探会改变随机序列，破坏可复现性。

class_name SimpleAI
extends RefCounted

const C = preload("res://scripts/utils/constants.gd")
const DamageCalc = preload("res://scripts/battle/damage_calc.gd")

const SKIP_CHANCE := {"easy": 20, "normal": 8, "hard": 0}
const HEAL_THRESHOLD := {"easy": 500, "normal": 600, "hard": 700}


## 返回一个行动：
##   {"type":"play",  "hand_index":int, "target":int}
##   {"type":"skill", "unit_index":int, "skill_id":String, "target":int}
##   {"type":"basic", "unit_index":int, "target":int}
##   {"type":"pass"}
static func decide(state: BattleState, side: int, level: String = "easy") -> Dictionary:
	var energy: int = int(state.energy[side])
	var skip := int(SKIP_CHANCE.get(level, 20))
	var heal_at := int(HEAL_THRESHOLD.get(level, 500))
	var lowest_ally := _lowest_hp(state, side)

	# hard 走 1 步搜索：枚举全部可选行动打分取最优，而不是走固定优先级
	if level == "hard":
		return _decide_hard(state, side, energy)

	# 1) 残血优先治疗
	if lowest_ally >= 0 and _hp_ratio(state, lowest_ally) < heal_at:
		var heal_idx := _find_spell_with_tag(state, side, "heal", energy)
		if heal_idx >= 0:
			return {"type": "play", "hand_index": heal_idx, "target": lowest_ally}

	# 2) 场上未满，优先铺场
	if state.board_count(side) < C.TEAM_SIZE:
		var beast_idx := _find_beast(state, side, energy)
		if beast_idx >= 0:
			return {"type": "play", "hand_index": beast_idx, "target": -1}

	# 3) 输出型法术
	var dmg_idx := _find_spell_with_tag(state, side, "pierce", energy)
	if dmg_idx < 0:
		dmg_idx = _find_any_spell(state, side, energy)
	if dmg_idx >= 0:
		var caster := _strongest_index(state, side)
		return {"type": "play", "hand_index": dmg_idx,
			"target": _pick_target(state, side, level, caster, _spell_power(state, String(state.hands[side][dmg_idx])))}

	# 4) 场上单位使用主动技能（按 SPD 从高到低）
	var order := state.living_indices(side)
	order.sort_custom(func(a, b): return int(state.units[a].get("spd", 0)) > int(state.units[b].get("spd", 0)))
	for i in order:
		var u: Dictionary = state.units[i]
		if bool(u.get("skill_used_this_turn", false)):
			continue
		var pick := _best_skill(state, u, energy, level)
		if pick.is_empty():
			continue
		var skid := String(pick.get("id", ""))
		var sk: Dictionary = pick.get("data", {})
		var tags: Array = sk.get("tags", [])
		var target: int
		if tags.has("heal") or tags.has("purify"):
			target = lowest_ally
		else:
			target = _pick_target(state, side, level, int(i), _skill_power(sk))
		# 失误感：低难度有概率跳过
		if skip > 0 and state.rng.range_int(0, 99) < skip:
			continue
		return {"type": "skill", "unit_index": int(i), "skill_id": skid, "target": target}

	# 5) 没有可用主动技能的单位执行普攻，保证不会站桩
	for i2 in order:
		var u2: Dictionary = state.units[i2]
		if bool(u2.get("skill_used_this_turn", false)):
			continue
		return {"type": "basic", "unit_index": int(i2),
			"target": _pick_target(state, side, level, int(i2), C.BASIC_ATTACK_POWER)}

	return {"type": "pass"}


# ── hard：1 步搜索 ────────────────────────────────

## 枚举「打每张手牌 / 每个单位的每个技能 / 普攻」，按即时收益打分取最优。
## 评分不含未来收益（那是 2 步搜索，V0 不做），但已明显强于固定优先级。
static func _decide_hard(state: BattleState, side: int, energy: int) -> Dictionary:
	var best := {"type": "pass"}
	var best_score := -9223372036854775807
	var hand: Array = state.hands[side]
	var lowest_ally := _lowest_hp(state, side)

	# 手牌
	for i in hand.size():
		var cid := String(hand[i])
		var card: Dictionary = state.cards_db.get(cid, {})
		if card.is_empty():
			continue
		if int(card.get("cost", 0)) > energy:
			continue
		if String(card.get("type", "")) == "beast":
			if state.board_count(side) >= C.TEAM_SIZE:
				continue
			if SUMMON_SCORE > best_score:
				best_score = SUMMON_SCORE
				best = {"type": "play", "hand_index": int(i), "target": -1}
		else:
			var caster := _strongest_index(state, side)
			if caster < 0:
				continue
			var t := _pick_target(state, side, "hard", caster, _spell_power(state, cid))
			var sc := _score_damage(state, caster, t, _spell_power(state, cid))
			if sc > best_score:
				best_score = sc
				best = {"type": "play", "hand_index": int(i), "target": t}

	# 场上单位的主动技能
	for i2 in state.living_indices(side):
		var u: Dictionary = state.units[i2]
		if bool(u.get("skill_used_this_turn", false)):
			continue
		for skid in (u.get("skills", []) as Array):
			if not state.skills_db.has(skid):
				continue
			var sk: Dictionary = state.skills_db[skid]
			if String(sk.get("trigger", "active")) != "active":
				continue
			if int(sk.get("cost", 0)) > energy:
				continue
			var caster_idx := int(i2)
			for e in (sk.get("effects", []) as Array):
				var eff: Dictionary = e
				var op := String(eff.get("op", ""))
				var power := int(eff.get("power", 0))
				var sc := -1
				var tgt := -1
				match op:
					"HEAL":
						tgt = lowest_ally
						sc = _score_heal(state, caster_idx, tgt, power)
					"SHIELD":
						tgt = lowest_ally
						sc = _score_shield(state, caster_idx, power)
					"DAMAGE":
						tgt = _pick_target(state, side, "hard", caster_idx, power * (1 + maxi(int(eff.get("repeat", 0)), 0)))
						sc = _score_damage(state, caster_idx, tgt, power * (1 + maxi(int(eff.get("repeat", 0)), 0)))
					_:
						sc = 100  # 净化 / 抽牌 / 加费等辅助效果给个基础分
						tgt = lowest_ally
				if sc > best_score:
					best_score = sc
					best = {"type": "skill", "unit_index": caster_idx, "skill_id": String(skid), "target": tgt}

	# 普攻兜底
	for i3 in state.living_indices(side):
		if bool(state.units[i3].get("skill_used_this_turn", false)):
			continue
		var t3 := _pick_target(state, side, "hard", int(i3), C.BASIC_ATTACK_POWER)
		var sc3 := _score_damage(state, int(i3), t3, C.BASIC_ATTACK_POWER)
		if sc3 > best_score:
			best_score = sc3
			best = {"type": "basic", "unit_index": int(i3), "target": t3}

	return best


const KILL_BONUS := 200000     # 击杀优先级远高于单纯伤害
const SUMMON_SCORE := 25000    # 铺场的基础价值


static func _score_damage(state: BattleState, caster_index: int, target: int, power: int) -> int:
	if target < 0 or target >= state.units.size() or caster_index < 0:
		return -1
	var tgt: Dictionary = state.units[target]
	if not bool(tgt.get("alive", false)):
		return -1
	var hp: int = int(tgt.get("hp", 0))
	var est := DamageCalc.estimate(state.units[caster_index], tgt, power, 0, state.chart)
	return est + (KILL_BONUS if est >= hp else 0)


static func _score_heal(state: BattleState, caster_index: int, target: int, power: int) -> int:
	if target < 0 or target >= state.units.size() or caster_index < 0:
		return -1
	var u: Dictionary = state.units[target]
	var max_hp: int = maxi(int(u.get("max_hp", 1)), 1)
	var hp: int = int(u.get("hp", 0))
	var amount: int = (int(state.units[caster_index].get("atk", 0)) * power) / C.FIXED_SCALE
	var healed := mini(amount, max_hp - hp)
	if healed <= 0:
		return -1
	# 残血时治疗价值翻倍：把一个濒死单位拉回来 = 保住一次出手
	var w := 2 if hp * 1000 / max_hp < 500 else 1
	return healed * w + 500


static func _score_shield(state: BattleState, caster_index: int, power: int) -> int:
	var amount: int = (int(state.units[caster_index].get("atk", 0)) * power) / C.FIXED_SCALE
	return amount / 2 + 300


# ── 目标选择 ──────────────────────────────────────

## easy 只打血最少的；normal / hard 优先打「这一下能打死」的，其次血最少。
##
## ⚠️ 曾在这里给 hard 加过「打攻击力最高的目标」，实测**反而更弱**
## （我方胜率 84.8% vs easy 的 80.8%，即 hard 对手更好打）。
## 原因：集火残血能最快减员、直接降低对方出手次数，收益远高于削高攻目标的血量。
## 教训：AI 启发式的强弱不能靠直觉判断，必须用 balance.gd 实测。
static func _pick_target(state: BattleState, side: int, level: String, caster_index: int, power: int) -> int:
	var pool := state.living_indices(1 - side)
	if pool.is_empty():
		return -1
	if caster_index < 0 or caster_index >= state.units.size():
		return _lowest_hp(state, 1 - side)
	if level == "easy":
		return _lowest_hp(state, 1 - side)

	var caster: Dictionary = state.units[caster_index]
	var best := -1
	var best_kill := -1
	var best_hp := 2147483647
	for i in pool:
		var u: Dictionary = state.units[i]
		var hp: int = int(u.get("hp", 0))
		var est := DamageCalc.estimate(caster, u, power, 0, state.chart)
		var kill := 1 if est >= hp else 0
		if kill > best_kill or (kill == best_kill and hp < best_hp):
			best_kill = kill
			best_hp = hp
			best = int(i)
	return best


# ── 技能选择 ──────────────────────────────────────

## easy / normal 用第一个用得起的；hard 挑伤害期望最高的
static func _best_skill(state: BattleState, u: Dictionary, energy: int, level: String) -> Dictionary:
	var best := {}
	var best_power := -1
	for skid in (u.get("skills", []) as Array):
		if not state.skills_db.has(skid):
			continue
		var sk: Dictionary = state.skills_db[skid]
		if String(sk.get("trigger", "active")) != "active":
			continue
		if int(sk.get("cost", 0)) > energy:
			continue
		if level != "hard":
			return {"id": String(skid), "data": sk}
		var p := _skill_power(sk)
		if p > best_power:
			best_power = p
			best = {"id": String(skid), "data": sk}
	return best


## 技能的总伤害倍率（各 DAMAGE 效果 × 次数之和）；非伤害技能返回 0（治疗/护盾靠上面第 1 步分流）
static func _skill_power(sk: Dictionary) -> int:
	var total := 0
	for e in (sk.get("effects", []) as Array):
		var eff: Dictionary = e
		if String(eff.get("op", "")) != "DAMAGE":
			continue
		total += int(eff.get("power", 0)) * (1 + maxi(int(eff.get("repeat", 0)), 0))
	return total


static func _spell_power(state: BattleState, card_id: String) -> int:
	var card: Dictionary = state.cards_db.get(card_id, {})
	for skid in (card.get("skills", []) as Array):
		if state.skills_db.has(skid):
			return _skill_power(state.skills_db[skid])
	return C.BASIC_ATTACK_POWER


# ── 辅助 ──────────────────────────────────────────

static func _lowest_hp(state: BattleState, side: int) -> int:
	var best := -1
	var best_hp := 2147483647
	for i in state.living_indices(side):
		var hp: int = int(state.units[i].get("hp", 0))
		if hp < best_hp:
			best_hp = hp
			best = int(i)
	return best


static func _hp_ratio(state: BattleState, index: int) -> int:
	var u: Dictionary = state.units[index]
	var max_hp: int = maxi(int(u.get("max_hp", 1)), 1)
	return int(u.get("hp", 0)) * 1000 / max_hp


static func _strongest_index(state: BattleState, side: int) -> int:
	var best := -1
	var best_atk := -1
	for i in state.living_indices(side):
		var atk: int = int(state.units[i].get("atk", 0))
		if atk > best_atk:
			best_atk = atk
			best = int(i)
	return best


static func _find_beast(state: BattleState, side: int, energy: int) -> int:
	var hand: Array = state.hands[side]
	for i in hand.size():
		var card: Dictionary = state.cards_db.get(String(hand[i]), {})
		if card.is_empty():
			continue
		if String(card.get("type", "")) != "beast":
			continue
		if int(card.get("cost", 0)) <= energy:
			return i
	return -1


static func _find_spell_with_tag(state: BattleState, side: int, tag: String, energy: int) -> int:
	var hand: Array = state.hands[side]
	for i in hand.size():
		var card: Dictionary = state.cards_db.get(String(hand[i]), {})
		if card.is_empty():
			continue
		if String(card.get("type", "")) != "spell":
			continue
		if int(card.get("cost", 0)) > energy:
			continue
		if (card.get("tags", []) as Array).has(tag):
			return i
	return -1


static func _find_any_spell(state: BattleState, side: int, energy: int) -> int:
	var hand: Array = state.hands[side]
	for i in hand.size():
		var card: Dictionary = state.cards_db.get(String(hand[i]), {})
		if card.is_empty():
			continue
		if String(card.get("type", "")) != "spell":
			continue
		if int(card.get("cost", 0)) <= energy:
			return i
	return -1
