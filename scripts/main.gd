## 主场景 —— V0 阶段用于验证配置加载与战斗核心
##
## V0 不做任何 UI：运行后直接在控制台输出一场演示战斗的完整日志。
## 这一步跑通后，再进入 M2 做战斗 UI。

extends Node

const DataLoader = preload("res://scripts/data/data_loader.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")
const DamageCalc = preload("res://scripts/battle/damage_calc.gd")


func _ready() -> void:
	print("=== 幻兽绘卷 / Mirage Beast Codex · V0 ===")

	# 1) 加载并校验配置
	var loaded := DataLoader.load_all_checked()
	var db: Dictionary = loaded["db"]
	var errors: Array = loaded["errors"]

	if not errors.is_empty():
		print("配置校验失败，共 %d 项错误：" % errors.size())
		for e in errors:
			print("  ✗ %s" % e)
		return

	print("配置校验通过：卡牌 %d 张 / 技能 %d 个"
		% [(db["cards"] as Dictionary).size(), (db["skills"] as Dictionary).size()])

	# 2) 跑一场演示战斗
	var ally := [
		{"card_id": "beast_001", "level": 5},
		{"card_id": "beast_002", "level": 5},
		{"card_id": "beast_003", "level": 5},
	]
	var enemy := [
		{"card_id": "beast_005", "level": 6},
		{"card_id": "beast_007", "level": 5},
	]
	var library := [
		"beast_001", "beast_002", "beast_003", "beast_004",
		"beast_005", "beast_007", "spell_001", "spell_002",
		"beast_001", "beast_002", "beast_003", "beast_004",
		"beast_005", "beast_007", "spell_001", "spell_002",
	]

	var state := BattleState.new()
	state.setup(ally, enemy, 20261006,
		db.get("element_chart", {}),
		db.get("cards", {}), db.get("skills", {}),
		library, library)

	var tm := TurnMachine.new()
	tm.setup(state, "easy", "easy")
	var outcome := tm.run()

	print("\n----- 战斗日志 -----")
	for line in state.battle_log:
		print(line)
	print("\n结果：%s（共 %d 回合）" % [outcome, state.turn_index])

	# 3) CP 展示
	print("\n----- CP 示例 -----")
	for i in state.units.size():
		var u: Dictionary = state.units[i]
		var cp := DamageCalc.combat_power(u, int(u.get("level", 1)))
		print("  %s Lv%d  CP=%d" % [String(u.get("name", "?")), int(u.get("level", 1)), cp])

	get_tree().quit()
