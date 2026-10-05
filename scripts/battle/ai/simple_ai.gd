## 简易对战 AI —— 评分式决策，不使用 LLM
##
## ⚠️ 设计决策：绝不使用 LLM 做出牌决策。
##    理由：① 每回合等待 5~10 秒毁掉节奏；② 输出不确定，无法批量模拟做平衡；
##          ③ 破坏战斗的确定性（回放与复盘失效）；④ 规则 AI 在此任务上远优于 LLM。
##
## 三档难度：easy / normal / hard（V0 只实现 easy + normal 的差异化倾向）

class_name SimpleAI
extends RefCounted

const C = preload("res://scripts/utils/constants.gd")


## 返回一个行动：
##   {"type":"play",  "hand_index":int, "target":int}
##   {"type":"skill", "unit_index":int, "skill_id":String, "target":int}
##   {"type":"pass"}
static func decide(state: BattleState, side: int, level: String = "easy") -> Dictionary:
	var hand: Array = state.hands[side]
	var energy: int = int(state.energy[side])
	var lowest_ally := _lowest_hp(state, side)
	var lowest_enemy := _lowest_hp(state, 1 - side)

	# 1) 残血优先治疗
	if lowest_ally >= 0 and _hp_ratio(state, lowest_ally) < 500:
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
		return {"type": "play", "hand_index": dmg_idx, "target": lowest_enemy}

	# 4) 场上单位使用主动技能（按 SPD 从高到低）
	var order := state.living_indices(side)
	order.sort_custom(func(a, b): return int(state.units[a].get("spd", 0)) > int(state.units[b].get("spd", 0)))
	for i in order:
		var u: Dictionary = state.units[i]
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
			var tags: Array = sk.get("tags", [])
			var target: int = lowest_ally if (tags.has("heal") or tags.has("purify")) else lowest_enemy
			# easy 难度：20% 概率跳过，制造失误感
			if level == "easy" and state.rng.range_int(0, 99) < 20:
				continue
			return {"type": "skill", "unit_index": int(i), "skill_id": String(skid), "target": target}

	# 5) 没有可用主动技能的单位执行普攻，保证不会站桩
	for i2 in order:
		var u2: Dictionary = state.units[i2]
		if bool(u2.get("skill_used_this_turn", false)):
			continue
		return {"type": "basic", "unit_index": int(i2), "target": lowest_enemy}

	return {"type": "pass"}


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
