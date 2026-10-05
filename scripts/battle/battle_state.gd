## 战斗状态容器 —— 纯数据 + 最小操作，不含任何 UI 依赖
##
## 设计原则：
##  - 所有数值来自 data/*.json，本文件不硬编码任何卡牌属性
##  - 所有随机来自注入的 BattleRNG（种子化），保证可复现
##  - 战斗核心可被 `godot --headless --script` 直接驱动做批量模拟

class_name BattleState
extends RefCounted

enum Side { ALLY, ENEMY }

const C = preload("res://scripts/utils/constants.gd")
const DamageCalc = preload("res://scripts/battle/damage_calc.gd")

## 全部单位（敌我混在一个数组，用 side 区分）
var units: Array = []
## 牌库：libraries[side] = [card_id, ...]
var libraries: Array = [[], []]
## 手牌：hands[side] = [card_id, ...]
var hands: Array = [[], []]
## 费用
var energy: Array = [0, 0]
var turn_index: int = 0
var outcome: String = "ongoing"

var rng: BattleRNG
## 从手牌召唤时的单位等级（取该方初始队伍的平均等级，避免 Boss 召唤出 Lv1 杂兵）
var summon_level: Array = [1, 1]
var chart: Dictionary = {}
var cards_db: Dictionary = {}
var skills_db: Dictionary = {}
var battle_log: Array = []


func setup(
	ally_entries: Array,
	enemy_entries: Array,
	seed_value: int,
	element_chart: Dictionary,
	all_cards: Dictionary,
	all_skills: Dictionary,
	ally_library: Array = [],
	enemy_library: Array = []
) -> void:
	rng = BattleRNG.new(seed_value)
	chart = element_chart
	cards_db = all_cards
	skills_db = all_skills

	units = []
	turn_index = 0
	outcome = "ongoing"
	battle_log = []

	_spawn_side(ally_entries, Side.ALLY)
	_spawn_side(enemy_entries, Side.ENEMY)
	summon_level = [_avg_level(ally_entries), _avg_level(enemy_entries)]

	libraries = [ally_library.duplicate(), enemy_library.duplicate()]
	hands = [[], []]
	energy = [C.START_ENERGY, C.START_ENERGY]

	draw(Side.ALLY, C.START_HAND)
	draw(Side.ENEMY, C.START_HAND)
	log_line("战斗开始：我方 %d 只 / 敌方 %d 只" % [living_count(Side.ALLY), living_count(Side.ENEMY)])


# ── 构建单位 ──────────────────────────────────────

func _spawn_side(entries: Array, side: int) -> void:
	var slot := 0
	for e in entries:
		var card_id := String((e as Dictionary).get("card_id", ""))
		var level := int((e as Dictionary).get("level", 1))
		var u := make_unit(card_id, level, side, slot)
		if u.is_empty():
			push_warning("[BattleState] 无法生成单位：%s" % card_id)
			continue
		units.append(u)
		slot += 1
		if slot >= C.TEAM_SIZE:
			break


func make_unit(card_id: String, level: int, side: int, slot: int) -> Dictionary:
	if not cards_db.has(card_id):
		return {}
	var card: Dictionary = cards_db[card_id]
	if String(card.get("type", "beast")) != "beast":
		return {}  # 秘术卡不能作为单位上场

	var base: Dictionary = card.get("base", {})
	var growth: Dictionary = card.get("growth", {})
	var lv_delta := level - 1

	var unit := {
		"side": side,
		"card_id": card_id,
		"name": String(card.get("name", card_id)),
		"element": String(card.get("element", "")),
		"level": level,
		"slot": slot,
		"atk": int(base.get("atk", 0)) + int(growth.get("atk", 0)) * lv_delta,
		"def": int(base.get("def", 0)) + int(growth.get("def", 0)) * lv_delta,
		"spd": int(base.get("spd", 0)) + int(growth.get("spd", 0)) * lv_delta,
		"max_hp": int(base.get("hp", 0)) + int(growth.get("hp", 0)) * lv_delta,
		"hp": 0,
		"shield": 0,
		"alive": true,
		"taunted_by": -1,
		"taunt_turns": 0,
		"buffs": [],
		"skill_used_this_turn": false,
		"skills": (card.get("skills", []) as Array).duplicate(),
	}
	unit["hp"] = int(unit["max_hp"])
	return unit


# ── 查询 ──────────────────────────────────────────

func living_indices(side: int) -> Array:
	var out := []
	for i in units.size():
		var u: Dictionary = units[i]
		if int(u.get("side", -1)) == side and bool(u.get("alive", false)):
			out.append(i)
	return out


func living_count(side: int) -> int:
	return living_indices(side).size()


func board_count(side: int) -> int:
	var n := 0
	for u in units:
		if int((u as Dictionary).get("side", -1)) == side and bool((u as Dictionary).get("alive", false)):
			n += 1
	return n


func is_over() -> bool:
	return outcome != "ongoing"


func check_outcome() -> void:
	var a := living_count(Side.ALLY)
	var e := living_count(Side.ENEMY)
	if a == 0 and e == 0:
		outcome = "draw"
	elif e == 0:
		outcome = "ally_win"
	elif a == 0:
		outcome = "enemy_win"


# ── 抽牌 ──────────────────────────────────────────

func draw(side: int, n: int) -> void:
	for _i in n:
		var lib: Array = libraries[side]
		if lib.is_empty():
			# 疲劳：牌库耗尽，对随机存活单位造成伤害
			var targets := living_indices(side)
			if targets.is_empty():
				return
			var t: int = targets[rng.range_int(0, targets.size() - 1)]
			log_line("%s 牌库耗尽，受到 %d 点疲劳伤害" % [side_name(side), C.FATIGUE_DAMAGE])
			apply_damage(t, C.FATIGUE_DAMAGE, -1)
			continue
		var card_id: String = lib.pop_front()
		var hand: Array = hands[side]
		if hand.size() >= C.HAND_SIZE_MAX:
			continue  # 手牌已满，弃掉
		hand.append(card_id)


# ── 伤害与治疗 ────────────────────────────────────

## 返回实际造成的伤害。source_index 为 -1 表示无来源（疲劳等）
func apply_damage(target_index: int, amount: int, source_index: int) -> int:
	if target_index < 0 or target_index >= units.size():
		return 0
	var u: Dictionary = units[target_index]
	if not bool(u.get("alive", false)):
		return 0

	var remaining := amount
	var shield: int = int(u.get("shield", 0))
	if shield > 0:
		var absorbed := mini(shield, remaining)
		u["shield"] = shield - absorbed
		remaining -= absorbed

	u["hp"] = int(u.get("hp", 0)) - remaining
	log_line("%s 受到 %d 点伤害（护盾吸收 %d），剩余 HP %d"
		% [label(target_index), amount, amount - remaining, maxi(int(u.get("hp", 0)), 0)])

	if int(u.get("hp", 0)) <= 0:
		u["hp"] = 0
		u["alive"] = false
		log_line("%s 倒下了" % label(target_index))

	check_outcome()
	return remaining


func apply_heal(target_index: int, amount: int) -> int:
	if target_index < 0 or target_index >= units.size():
		return 0
	var u: Dictionary = units[target_index]
	if not bool(u.get("alive", false)):
		return 0
	var max_hp: int = int(u.get("max_hp", 0))
	var hp: int = int(u.get("hp", 0))
	var healed := mini(amount, max_hp - hp)
	u["hp"] = hp + healed
	if healed > 0:
		log_line("%s 恢复 %d 点生命" % [label(target_index), healed])
	return healed


func apply_shield(target_index: int, amount: int) -> void:
	if target_index < 0 or target_index >= units.size():
		return
	var u: Dictionary = units[target_index]
	if not bool(u.get("alive", false)):
		return
	u["shield"] = int(u.get("shield", 0)) + amount


# ── Buff / Debuff ─────────────────────────────────

func apply_stat_mod(target_index: int, stat: String, power: int, duration: int) -> void:
	if target_index < 0 or target_index >= units.size():
		return
	var u: Dictionary = units[target_index]
	var cur: int = int(u.get(stat, 0))
	u[stat] = (cur * power) / C.FIXED_SCALE
	u["buffs"].append({"stat": stat, "power": power, "turns": duration})


func purify(target_index: int, _count: int) -> void:
	if target_index < 0 or target_index >= units.size():
		return
	var u: Dictionary = units[target_index]
	u["buffs"] = []
	u["taunted_by"] = -1
	u["taunt_turns"] = 0


# ── 日志 ──────────────────────────────────────────

func log_line(text: String) -> void:
	battle_log.append("T%d | %s" % [turn_index, text])


## 带阵营前缀的单位名，避免敌我同名幻兽在日志里无法区分
func label(index: int) -> String:
	if index < 0 or index >= units.size():
		return "?"
	var u: Dictionary = units[index]
	var prefix := "[我]" if int(u.get("side", 0)) == Side.ALLY else "[敌]"
	return "%s%s" % [prefix, String(u.get("name", "?"))]


func _avg_level(entries: Array) -> int:
	if entries.is_empty():
		return 1
	var total := 0
	for e in entries:
		total += int((e as Dictionary).get("level", 1))
	return maxi(total / entries.size(), 1)


func side_name(side: int) -> String:
	return "我方" if side == Side.ALLY else "敌方"
