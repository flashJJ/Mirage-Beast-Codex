## 回合状态机 —— 六阶段：START → DRAW → ENERGY → ACTION → RESOLVE → END
##
## 纯逻辑，不引用任何 UI 节点。可被 headless 批量模拟直接驱动。
## 每回合：我方先行动，敌方后行动（先后顺序由 SPD 决定会在后续版本引入，V0 固定我方先手）

class_name TurnMachine
extends RefCounted

enum Phase { START, DRAW, ENERGY, ACTION, RESOLVE, END }

const C = preload("res://scripts/utils/constants.gd")
const EffectSystem = preload("res://scripts/battle/effect_system.gd")
const SimpleAI = preload("res://scripts/battle/ai/simple_ai.gd")

var state: BattleState
var phase: int = Phase.START
var ai_levels: Array = ["easy", "easy"]


func setup(battle_state: BattleState, ally_ai: String = "easy", enemy_ai: String = "easy") -> void:
	state = battle_state
	ai_levels = [ally_ai, enemy_ai]
	phase = Phase.START
	# 初始上场的单位也要触发 on_play（否则「进场护盾」类技能在开局阵容上永远不生效）
	for i in state.units.size():
		EffectSystem.on_play(state, i)


## 开始一个新回合（START → DRAW → ENERGY），停在 ACTION 等待我方操作
## UI 模式与 headless 模式共用，保证两套驱动路径逻辑一致
func start_turn() -> void:
	_phase_start()
	_phase_draw()
	_phase_energy()
	phase = Phase.ACTION


## 结束我方行动：敌方行动 → RESOLVE → END
func end_turn() -> void:
	if state == null or state.is_over():
		return
	_phase_action(BattleState.Side.ENEMY)
	if state.is_over():
		return
	_phase_resolve()
	_phase_end()


## UI 用：结束我方行动 → 敌方行动 → 结算 → 开始下一回合
## 达到回合上限时按剩余血量判定，避免 UI 里无限进行下去
func advance_turn() -> void:
	end_turn()
	if state == null or state.is_over():
		return
	if state.turn_index >= C.MAX_TURNS:
		state.outcome = _judge_by_hp()
		state.log_line("达到 %d 回合上限，按剩余血量判定：%s" % [C.MAX_TURNS, state.outcome])
		return
	start_turn()


## 跑完整场战斗（headless 批量模拟用），返回 outcome 字符串
func run() -> String:
	if state == null:
		push_error("[TurnMachine] 未设置 BattleState")
		return "error"

	while not state.is_over() and state.turn_index < C.MAX_TURNS:
		start_turn()
		_phase_action(BattleState.Side.ALLY)
		if state.is_over():
			break
		end_turn()

	if not state.is_over():
		state.outcome = _judge_by_hp()
		state.log_line("达到 %d 回合上限，按剩余血量判定：%s" % [C.MAX_TURNS, state.outcome])

	phase = Phase.END
	return state.outcome


# ── 六阶段 ────────────────────────────────────────

func _phase_start() -> void:
	phase = Phase.START
	state.turn_index += 1
	for u in state.units:
		(u as Dictionary)["skill_used_this_turn"] = false
	state.log_line("── 回合 %d 开始 ──" % state.turn_index)
	state.events.append({"t": state.turn_index, "type": "turn_start"})


func _phase_draw() -> void:
	phase = Phase.DRAW
	state.draw(BattleState.Side.ALLY, 1)
	state.draw(BattleState.Side.ENEMY, 1)


func _phase_energy() -> void:
	phase = Phase.ENERGY
	for s in [BattleState.Side.ALLY, BattleState.Side.ENEMY]:
		state.energy[s] = mini(state.energy[s] + C.ENERGY_PER_TURN, C.MAX_ENERGY)


func _phase_action(side: int) -> void:
	phase = Phase.ACTION
	var actions := 0
	while actions < C.MAX_ACTIONS_TURN and not state.is_over():
		var act: Dictionary = SimpleAI.decide(state, side, ai_levels[side])
		if String(act.get("type", "pass")) == "pass":
			break
		var ok := _execute(side, act)
		if not ok:
			break
		actions += 1


func _phase_resolve() -> void:
	phase = Phase.RESOLVE
	# 递减 buff 与嘲讽持续回合
	for u in state.units:
		var unit: Dictionary = u
		if not bool(unit.get("alive", false)):
			continue
		var remain := []
		for b in (unit.get("buffs", []) as Array):
			var buff: Dictionary = b
			var turns := int(buff.get("turns", 0)) - 1
			if turns > 0:
				buff["turns"] = turns
				remain.append(buff)
		unit["buffs"] = remain
		var tt := int(unit.get("taunt_turns", 0)) - 1
		unit["taunt_turns"] = maxi(tt, 0)
		if tt <= 0:
			unit["taunted_by"] = -1
	EffectSystem.on_turn_end(state, BattleState.Side.ALLY)
	EffectSystem.on_turn_end(state, BattleState.Side.ENEMY)


func _phase_end() -> void:
	phase = Phase.END
	state.check_outcome()


# ── 行动执行 ──────────────────────────────────────

## 执行一个行动，并在成功后写入结构化战报（F3）
func _execute(side: int, act: Dictionary) -> bool:
	var uidx := int(act.get("unit_index", -1))
	var hand_idx := int(act.get("hand_index", -1))
	var target := int(act.get("target", -1))
	var skill_id := String(act.get("skill_id", ""))
	var card_id := ""
	if hand_idx >= 0 and hand_idx < state.hands[side].size():
		card_id = String(state.hands[side][hand_idx])

	var ok := false
	var ev := {"t": state.turn_index, "side": side, "unit": uidx}
	match String(act.get("type", "")):
		"play":
			ok = play_card(side, hand_idx, target)
			ev["type"] = "play_card"
			ev["card"] = card_id
		"skill":
			ok = use_skill(uidx, skill_id, target)
			ev["type"] = "use_skill"
			ev["skill"] = skill_id
		"basic":
			ok = basic_attack(uidx, target)
			ev["type"] = "basic_attack"
		_:
			return false

	if ok:
		state.events.append(ev)
	return ok


func play_card(side: int, hand_index: int, target: int) -> bool:
	var hand: Array = state.hands[side]
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card_id := String(hand[hand_index])
	var card: Dictionary = state.cards_db.get(card_id, {})
	if card.is_empty():
		return false
	var cost := int(card.get("cost", 0))
	if state.energy[side] < cost:
		return false

	state.energy[side] -= cost
	hand.remove_at(hand_index)

	if String(card.get("type", "beast")) == "beast":
		if state.board_count(side) >= C.TEAM_SIZE:
			state.log_line("%s 场上已满，%s 被弃置" % [_side_name(side), String(card.get("name", card_id))])
			return true
		var slot := state.board_count(side)
		var lv := int(state.summon_level[side])
		var unit := state.make_unit(card_id, lv, side, slot)
		if unit.is_empty():
			return true
		state.units.append(unit)
		state.log_line("%s 召唤 %s（Lv%d）"
			% [_side_name(side), String(unit.get("name", card_id)), lv])
		state.events.append({
			"t": state.turn_index, "type": "summon", "side": side,
			"card": card_id, "level": lv, "unit": state.units.size() - 1,
		})
		EffectSystem.on_play(state, state.units.size() - 1)
	else:
		# 秘术卡：以本方攻击力最高的存活单位作为施法者
		var caster := _strongest_index(side)
		if caster < 0:
			return true
		for skid in (card.get("skills", []) as Array):
			if state.skills_db.has(skid):
				EffectSystem.resolve(state, caster, state.skills_db[skid], target)
	return true


func use_skill(unit_index: int, skill_id: String, target: int) -> bool:
	if unit_index < 0 or unit_index >= state.units.size():
		return false
	var u: Dictionary = state.units[unit_index]
	if not bool(u.get("alive", false)):
		return false
	if bool(u.get("skill_used_this_turn", false)):
		return false
	if not state.skills_db.has(skill_id):
		return false
	var skill: Dictionary = state.skills_db[skill_id]
	if String(skill.get("trigger", "active")) != "active":
		return false
	var cost := int(skill.get("cost", 0))
	var side: int = int(u.get("side", 0))
	if state.energy[side] < cost:
		return false

	state.energy[side] -= cost
	u["skill_used_this_turn"] = true
	state.log_line("%s 使用 %s" % [state.label(unit_index), String(skill.get("name", skill_id))])
	state.events.append({
		"t": state.turn_index, "type": "skill", "side": side,
		"unit": unit_index, "skill": skill_id,
	})
	EffectSystem.resolve(state, unit_index, skill, target)
	return true


## 普攻：没有可用主动技能的单位仍应有输出，否则「只有辅助技能」的幻兽等于站桩挨打
func basic_attack(unit_index: int, target: int) -> bool:
	if unit_index < 0 or unit_index >= state.units.size():
		return false
	var u: Dictionary = state.units[unit_index]
	if not bool(u.get("alive", false)):
		return false
	if bool(u.get("skill_used_this_turn", false)):
		return false
	u["skill_used_this_turn"] = true
	state.log_line("%s 普攻" % state.label(unit_index))
	EffectSystem.deal_damage(state, unit_index, target, C.BASIC_ATTACK_POWER, 0)
	return true


# ── 辅助 ──────────────────────────────────────────

func _strongest_index(side: int) -> int:
	var best := -1
	var best_atk := -1
	for i in state.living_indices(side):
		var atk: int = int(state.units[i].get("atk", 0))
		if atk > best_atk:
			best_atk = atk
			best = i
	return best


func _judge_by_hp() -> String:
	var a_ratio := _hp_ratio(BattleState.Side.ALLY)
	var e_ratio := _hp_ratio(BattleState.Side.ENEMY)
	if absi(a_ratio - e_ratio) < 50:
		return "draw"
	return "ally_win" if a_ratio > e_ratio else "enemy_win"


func _hp_ratio(side: int) -> int:
	var cur := 0
	var maxv := 0
	for i in state.living_indices(side):
		cur += int(state.units[i].get("hp", 0))
		maxv += int(state.units[i].get("max_hp", 0))
	if maxv == 0:
		return 0
	return cur * 1000 / maxv


func _side_name(side: int) -> String:
	return "我方" if side == BattleState.Side.ALLY else "敌方"
