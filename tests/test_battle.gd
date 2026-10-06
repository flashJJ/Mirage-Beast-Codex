## 战斗核心单元测试 —— 纯逻辑，不依赖 UI
##
## 运行：
##   godot --headless --script res://tests/test_battle.gd
##
## 覆盖：配置校验 / 属性克制 / 伤害确定性 / 护盾抵扣 / 死亡判定
##       / 嘲讽 / 反制 / 净化 / 牌库合法性 / 结构化战报
##
## 对应 design/dev/00-项目开发计划.md 的 M1-7

extends SceneTree

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const SchemaCheck = preload("res://scripts/data/schema_check.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")
const DamageCalc = preload("res://scripts/battle/damage_calc.gd")
const BattleRNG = preload("res://scripts/battle/rng.gd")
const EffectSystem = preload("res://scripts/battle/effect_system.gd")

var _db: Dictionary
var _passed := 0
var _failed := 0


func _init() -> void:
	print("=== 战斗核心单元测试 ===\n")

	var loaded := DataLoader.load_all_checked()
	_db = loaded["db"]

	test_schema_validation(loaded["errors"])
	test_element_multipliers()
	test_determinism_of_damage()
	test_multiplicative_defense()
	test_shield_absorbs_first()
	test_death_sets_alive_false()
	test_taunt_sets_target()
	test_taunt_constrains_target()
	test_counter_triggers_on_damaged()
	test_purify_clears_buffs()
	test_deck_legality()
	test_structured_events()

	print("\n通过 %d 项，失败 %d 项" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ── 断言 ──────────────────────────────────────────

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s%s" % [name, ("  → " + detail) if detail != "" else ""])


func _make_state(ally: Array, enemy: Array, seed_v: int) -> BattleState:
	var st := BattleState.new()
	st.setup(ally, enemy, seed_v,
		_db.get("element_chart", {}),
		_db.get("cards", {}), _db.get("skills", {}),
		[], [])
	return st


# ── 用例 ──────────────────────────────────────────

func test_schema_validation(errors: Array) -> void:
	print("[配置校验]")
	_check("data/*.json 全部通过 Schema 校验", errors.is_empty(), str(errors))
	_check("卡牌数量 > 0", (_db.get("cards", {}) as Dictionary).size() > 0)
	_check("技能数量 > 0", (_db.get("skills", {}) as Dictionary).size() > 0)


func test_element_multipliers() -> void:
	print("\n[属性克制]")
	var st := _make_state([{"card_id": "beast_001", "level": 1}],
			[{"card_id": "beast_003", "level": 1}], 1)
	var chart: Dictionary = st.chart
	_check("四元环克制 = 1.50", DamageCalc.element_multiplier(chart, "fire", "wood") == 1500)
	_check("光暗互克 = 1.45", DamageCalc.element_multiplier(chart, "light", "dark") == 1450)
	_check("同属性中立 = 1.00", DamageCalc.element_multiplier(chart, "fire", "fire") == 1000)
	_check("无关属性中立 = 1.00", DamageCalc.element_multiplier(chart, "fire", "light") == 1000)


func test_determinism_of_damage() -> void:
	print("\n[伤害计算]")
	var st := _make_state([{"card_id": "beast_001", "level": 5}],
			[{"card_id": "beast_002", "level": 5}], 12345)
	var attacker: Dictionary = st.units[0]
	var defender: Dictionary = st.units[1]
	var r1 := DamageCalc.damage(attacker, defender, 1000, 0, st.chart, BattleRNG.new(999))
	var r2 := DamageCalc.damage(attacker, defender, 1000, 0, st.chart, BattleRNG.new(999))
	var r3 := DamageCalc.damage(attacker, defender, 1000, 0, st.chart, BattleRNG.new(1000))

	_check("同种子伤害结果一致", r1 == r2)
	_check("不同种子结果可不同（浮动生效）", r1 != r3)
	_check("伤害恒为正（不会为 0 或负）", r1 >= 1, "r1=%d" % r1)

	# 穿透应提高伤害
	var no_pierce := DamageCalc.damage(attacker, defender, 1000, 0, st.chart, BattleRNG.new(7))
	var with_pierce := DamageCalc.damage(attacker, defender, 1000, 500, st.chart, BattleRNG.new(7))
	_check("穿透 50% 提高伤害", with_pierce >= no_pierce, "%d vs %d" % [with_pierce, no_pierce])


## F43 乘性减伤的回归测试。
## 目的：把「减伤模型」这个结构性决策钉死 —— 若有人改回固定减算，这些断言会立刻红。
## 用 estimate()（不含暴击与随机浮动）来断言精确值，避免受 RNG 影响。
func test_multiplicative_defense() -> void:
	print("\n[乘性减伤 F43]")
	var chart := {}
	var a := {"atk": 100, "def": 10, "element": "fire", "slot": 0}
	var d0 := {"atk": 50, "def": 0, "element": "wood", "slot": 0}
	var d32 := {"atk": 50, "def": 32, "element": "wood", "slot": 0}
	var d64 := {"atk": 50, "def": 64, "element": "wood", "slot": 0}
	var dbig := {"atk": 50, "def": 5000, "element": "wood", "slot": 0}

	# 1) 钉住精确值：base=100，DEF=32 → def_val=32*5800/1000=185 → 100*1000/1185=84
	_check("DEF=32 时伤害 = 84（公式锚点）",
		DamageCalc.estimate(a, d32, 1000, 0, chart) == 84,
		"实际 %d" % DamageCalc.estimate(a, d32, 1000, 0, chart))
	_check("DEF=0 时无减伤（= 攻击力）",
		DamageCalc.estimate(a, d0, 1000, 0, chart) == 100)
	_check("穿透 50% 使 DEF=32 的减伤减半（185→92 → 91）",
		DamageCalc.estimate(a, d32, 1000, 500, chart) == 91,
		"实际 %d" % DamageCalc.estimate(a, d32, 1000, 500, chart))

	# 2) 乘性的两个本质特征：单调递减 + 收益递减
	var e0 := DamageCalc.estimate(a, d0, 1000, 0, chart)
	var e32 := DamageCalc.estimate(a, d32, 1000, 0, chart)
	var e64 := DamageCalc.estimate(a, d64, 1000, 0, chart)
	_check("防御越高伤害越低（单调）", e0 > e32 and e32 > e64, "%d/%d/%d" % [e0, e32, e64])
	_check("减伤收益递减（后 32 点防御的收益 < 前 32 点）",
		(e0 - e32) > (e32 - e64), "前段 -%d，后段 -%d" % [e0 - e32, e32 - e64])

	# 3) 固定减算的致命缺陷：防御足够高会出现 0/负伤害；乘性永远不会
	_check("超高防御下伤害仍 ≥1（无阈值/非负）",
		DamageCalc.estimate(a, dbig, 1000, 0, chart) >= 1)
	_check("超高防御下伤害显著低于无甲（说明防御确实有效）",
		DamageCalc.estimate(a, dbig, 1000, 0, chart) < e32 / 2)

	# 4) 无等级悬崖：攻击力小幅增长，伤害应近似线性增长（不该出现突变）
	var a2 := {"atk": 110, "def": 10, "element": "fire", "slot": 0}
	var e_a := DamageCalc.estimate(a, d32, 1000, 0, chart)
	var e_a2 := DamageCalc.estimate(a2, d32, 1000, 0, chart)
	_check("攻击 +10% → 伤害增幅在 8%~12%（线性，无悬崖）",
		e_a2 * 100 >= e_a * 108 and e_a2 * 100 <= e_a * 112,
		"%d → %d" % [e_a, e_a2])


func test_shield_absorbs_first() -> void:
	print("\n[护盾抵扣]")
	var st := _make_state([{"card_id": "beast_001", "level": 5}],
			[{"card_id": "beast_003", "level": 5}], 2)
	var hp_before: int = int(st.units[0].get("hp", 0))
	st.apply_shield(0, 40)
	st.apply_damage(0, 25, -1)
	_check("护盾优先抵扣，HP 不变", int(st.units[0].get("hp", 0)) == hp_before)
	_check("护盾余额 = 40-25", int(st.units[0].get("shield", 0)) == 15)

	st.apply_damage(0, 30, -1)
	_check("护盾击穿后溢出伤害打 HP",
		int(st.units[0].get("hp", 0)) == hp_before - 15,
		"hp=%d 期望=%d" % [int(st.units[0].get("hp", 0)), hp_before - 15])
	_check("护盾归零", int(st.units[0].get("shield", 0)) == 0)


func test_death_sets_alive_false() -> void:
	print("\n[死亡判定]")
	var st := _make_state([{"card_id": "beast_007", "level": 1}],
			[{"card_id": "beast_003", "level": 1}], 3)
	st.apply_damage(0, 9999, -1)
	_check("HP 归零后 alive = false", not bool(st.units[0].get("alive", true)))
	_check("HP 不会为负", int(st.units[0].get("hp", -1)) == 0)
	_check("我方全灭 → outcome = enemy_win", st.outcome == "enemy_win", st.outcome)


func test_taunt_sets_target() -> void:
	print("\n[嘲讽]")
	var st := _make_state([{"card_id": "beast_004", "level": 5}],
			[{"card_id": "beast_001", "level": 5}], 4)
	# 藤蔓熊的嘲讽技能：目标为敌方全体
	var skill: Dictionary = _db.get("skills", {}).get("sk_b004_s1", {})
	_check("嘲讽技能配置存在", not skill.is_empty())
	if not skill.is_empty():
		EffectSystem.resolve(st, 0, skill, -1)
		var enemy_unit: Dictionary = st.units[1]
		_check("嘲讽后敌方 taunted_by 指向施法者",
			int(enemy_unit.get("taunted_by", -1)) == 0,
			"taunted_by=%d" % int(enemy_unit.get("taunted_by", -1)))


func test_taunt_constrains_target() -> void:
	print("\n[嘲讽约束 F42]")
	# 历史缺口：taunted_by 写进了单位字典，但选目标时没人读它 —— 嘲讽的"控制"效果其实失效了，
	# 只有 DEBUFF 那部分数值在起作用。这里锁死约束行为。

	# ── 1) 伤害类效果被强制指向嘲讽者 ──────────────
	# 我方：藤蔓熊 Lv5（嘲讽者，血厚）+ 焰尾狐 Lv5（血薄，正常情况下会被优先攻击）
	# 敌方：焰尾狐 Lv5（双尾连击，target.select = lowest_hp）
	var st := _make_state(
		[{"card_id": "beast_004", "level": 5}, {"card_id": "beast_001", "level": 5}],
		[{"card_id": "beast_001", "level": 5}], 77)
	var TAUNTER := 0
	var SOFT := 1
	var ENEMY := 2
	_check("前提：不嘲讽时敌方会打血量更低的焰尾狐",
		int(st.units[SOFT].get("hp", 0)) < int(st.units[TAUNTER].get("hp", 0)))

	EffectSystem.resolve(st, TAUNTER, st.skills_db["sk_b004_s1"], -1)
	_check("嘲讽已生效（taunt_source 指向嘲讽者）", EffectSystem.taunt_source(st, ENEMY) == TAUNTER)

	var t_hp: int = int(st.units[TAUNTER].get("hp", 0))
	var s_hp: int = int(st.units[SOFT].get("hp", 0))
	EffectSystem.resolve(st, ENEMY, st.skills_db["sk_b001_s1"], -1)
	_check("嘲讽生效：伤害强制打在嘲讽者身上", int(st.units[TAUNTER].get("hp", 0)) < t_hp,
		"%d → %d" % [t_hp, int(st.units[TAUNTER].get("hp", 0))])
	_check("嘲讽生效：软目标未被波及", int(st.units[SOFT].get("hp", 0)) == s_hp)

	# ── 2) 嘲讽不影响治疗（否则会出现「被嘲讽只能给敌人加血」）──
	var st2 := _make_state([{"card_id": "beast_003", "level": 5}],
		[{"card_id": "beast_004", "level": 5}, {"card_id": "beast_001", "level": 5}], 78)
	st2.apply_damage(0, 50, -1)
	var h0: int = int(st2.units[0].get("hp", 0))
	EffectSystem.resolve(st2, 1, st2.skills_db["sk_b004_s1"], -1)  # 敌方藤蔓熊嘲讽我方木灵鹿
	_check("我方处于被嘲讽状态", EffectSystem.taunt_source(st2, 0) == 1)
	# 注意：不能用「敌方 HP == max_hp」判断 —— _make_state 传空牌库，setup 抽牌会触发疲劳伤害
	var e_hp: int = int(st2.units[1].get("hp", 0))
	EffectSystem.resolve(st2, 0, st2.skills_db["sk_b003_s1"], -1)  # 木灵回春，target.side = ally
	_check("嘲讽不影响治疗：我方回血", int(st2.units[0].get("hp", 0)) > h0)
	_check("嘲讽不影响治疗：敌方没有回血", int(st2.units[1].get("hp", 0)) <= e_hp)

	# ── 3) 普攻同样受嘲讽约束 ──────────────────────
	var st3 := _make_state(
		[{"card_id": "beast_004", "level": 5}, {"card_id": "beast_001", "level": 5}],
		[{"card_id": "beast_001", "level": 5}], 79)
	EffectSystem.resolve(st3, 0, st3.skills_db["sk_b004_s1"], -1)
	var tm3 := TurnMachine.new()
	tm3.setup(st3, "easy", "easy")
	var before3: int = int(st3.units[0].get("hp", 0))
	var soft3: int = int(st3.units[1].get("hp", 0))
	tm3.basic_attack(2, 1)  # 敌方本想打 index 1，应被强制改打嘲讽者 index 0
	_check("普攻受嘲讽约束：打向嘲讽者", int(st3.units[0].get("hp", 0)) < before3)
	_check("普攻受嘲讽约束：非嘲讽者未掉血", int(st3.units[1].get("hp", 0)) == soft3)

	# ── 4) 嘲讽持续回合结束失效 ────────────────────
	var st4 := _make_state(
		[{"card_id": "beast_004", "level": 5}, {"card_id": "beast_001", "level": 5}],
		[{"card_id": "beast_001", "level": 5}], 80)
	EffectSystem.resolve(st4, 0, st4.skills_db["sk_b004_s1"], -1)
	st4.units[2]["taunt_turns"] = 0
	_check("嘲讽回合归零后约束解除", EffectSystem.taunt_source(st4, 2) == -1)
	st4.units[0]["alive"] = false
	st4.units[2]["taunt_turns"] = 2
	_check("嘲讽者阵亡后约束解除", EffectSystem.taunt_source(st4, 2) == -1)


func test_counter_triggers_on_damaged() -> void:
	print("\n[反制]")
	# 熔岩獠牙带 on_damaged 反制；让我方攻击它，我方应受到反弹伤害
	var st := _make_state([{"card_id": "beast_001", "level": 5}],
			[{"card_id": "beast_005", "level": 5}], 5)
	var hp_before: int = int(st.units[0].get("hp", 0))
	var enemy_hp_before: int = int(st.units[1].get("hp", 0))
	EffectSystem.deal_damage(st, 0, 1, 1000, 0)
	_check("普攻对敌方造成伤害", int(st.units[1].get("hp", 0)) < enemy_hp_before)
	_check("反制触发，我方也掉血", int(st.units[0].get("hp", 0)) < hp_before,
		"我方 %d → %d" % [hp_before, int(st.units[0].get("hp", 0))])


func test_purify_clears_buffs() -> void:
	print("\n[净化]")
	var st := _make_state([{"card_id": "beast_001", "level": 5}],
			[{"card_id": "beast_003", "level": 5}], 6)
	st.apply_stat_mod(0, "atk", 850, 2)
	_check("减益已施加", (st.units[0].get("buffs", []) as Array).size() > 0)
	st.purify(0, 3)
	_check("净化后 buffs 清空", (st.units[0].get("buffs", []) as Array).is_empty())
	_check("净化后嘲讽清除", int(st.units[0].get("taunted_by", -1)) == -1)


func test_deck_legality() -> void:
	print("\n[卡组合法性]")
	var legal: Array = []
	for i in C.LIBRARY_SIZE:
		legal.append("beast_001" if i % 2 == 0 else "beast_002")
	_check("16 张同名各 8 张 → 应报超量",
		not SchemaCheck.validate_deck(_db, legal).is_empty())

	var ok_deck: Array = []
	var core := ["beast_001", "beast_002", "beast_003", "beast_004",
				 "beast_005", "beast_007", "spell_001", "spell_002"]
	ok_deck.append_array(core)
	ok_deck.append_array(core)
	_check("16 张同名各 2 张 → 合法", SchemaCheck.validate_deck(_db, ok_deck).is_empty(),
		str(SchemaCheck.validate_deck(_db, ok_deck)))

	var short_deck: Array = ["beast_001", "beast_002"]
	_check("数量不足 → 报错", not SchemaCheck.validate_deck(_db, short_deck).is_empty())


func test_structured_events() -> void:
	print("\n[结构化战报 F3]")
	var ally := [{"card_id": "beast_001", "level": 6}, {"card_id": "beast_002", "level": 6}]
	var enemy := [{"card_id": "beast_003", "level": 6}]
	var st := BattleState.new()
	var library: Array = []
	for i in C.LIBRARY_SIZE:
		library.append("spell_002")
	st.setup(ally, enemy, 777, _db.get("element_chart", {}),
		_db.get("cards", {}), _db.get("skills", {}), library, library)

	var tm := TurnMachine.new()
	tm.setup(st, "easy", "easy")
	tm.run()

	_check("战报非空", st.events.size() > 0, "events=%d" % st.events.size())
	_check("战报条目均为字典", st.events[0] is Dictionary)
	var has_damage := false
	var has_turn_start := false
	for e in st.events:
		var ev: Dictionary = e
		if String(ev.get("type", "")) == "damage":
			has_damage = true
		if String(ev.get("type", "")) == "turn_start":
			has_turn_start = true
	_check("含 damage 事件", has_damage)
	_check("含 turn_start 事件", has_turn_start)
	_check("战斗有明确结局", st.outcome != "ongoing", st.outcome)
