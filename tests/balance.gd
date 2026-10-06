## 阵容平衡度量工具
##
## 运行：
##   godot --headless --script res://tests/balance.gd [--runs 400]
##
## 用途：
##   simulate.gd 跑的是「遭遇战表 vs 我方等级」的整体胜率曲线；
##   balance.gd 跑的是「UI 默认阵容」这一组具体对局的胜率，
##   并做敌方等级扫描，找出让胜率落在目标区间的配置。
##
## 为什么需要它：
##   V0 第一版 UI 的默认对局我方 4 回合就崩了 —— 问题不在规则，
##   而在「我方三只里有两只没有输出技能」，是配队不公平。
##   这种问题靠肉眼看不出来，必须量化。
##
## 方法：双方都用 SimpleAI("easy") 驱动（把玩家近似为一个「会打但不算聪明」的人），
##       固定样本量跑批，输出胜率。

extends SceneTree

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")
const BattleUI = preload("res://scripts/battle/battle_ui.gd")

## 目标胜率区间：作为玩家的第一场战斗，应该「能赢但要动点脑子」
const TARGET_LOW := 60
const TARGET_HIGH := 85

var _runs := 400
var _db: Dictionary


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			_runs = int(args[i + 1])

	_db = DataLoader.load_all()
	print("=== 阵容平衡度量（每组 %d 局）===\n" % _runs)

	_report("UI 默认阵容", BattleUI.ALLY_TEAM, BattleUI.ENEMY_TEAM)

	# 敌方等级扫描：找出让胜率落入目标区间的等级
	print("\n── 敌方等级扫描（我方固定 Lv%d）──" % int(BattleUI.ALLY_TEAM[0]["level"]))
	print("  敌方等级   我方胜率   平均回合   判定")
	for lv in range(4, 11):
		var enemy: Array = []
		for e in BattleUI.ENEMY_TEAM:
			enemy.append({"card_id": e["card_id"], "level": lv})
		var r := _measure(BattleUI.ALLY_TEAM, enemy)
		var verdict := "OK" if r.win >= TARGET_LOW and r.win <= TARGET_HIGH else ("偏易" if r.win > TARGET_HIGH else "偏难")
		print("    Lv%-2d      %5.1f%%    %5.1f      %s" % [lv, r.win, r.turns, verdict])

	# 候选对手配置对比：把「敌方等级」从粗粒度扫描收窄到具体阵容
	print("\n── 候选对手配置对比（我方固定为 UI 默认阵容）──")
	print("  配置                                我方胜率   平均回合   判定")
	var candidates := [
		{"name": "A 旧默认（影爪猫Lv7）", "e": [["beast_005", 8], ["beast_007", 7], ["beast_001", 7]]},
		{"name": "B 影爪猫+1", "e": [["beast_005", 8], ["beast_007", 8], ["beast_001", 7]]},
		{"name": "C 焰尾狐+1", "e": [["beast_005", 8], ["beast_007", 7], ["beast_001", 8]]},
		{"name": "D 全 Lv8",   "e": [["beast_005", 8], ["beast_007", 8], ["beast_001", 8]]},
		{"name": "E 换藤蔓熊", "e": [["beast_005", 8], ["beast_004", 7], ["beast_007", 7]]},
		{"name": "F 换光羽鹭", "e": [["beast_005", 8], ["beast_006", 7], ["beast_007", 7]]},
	]
	for c in candidates:
		var enemy: Array = []
		for p in (c["e"] as Array):
			enemy.append({"card_id": p[0], "level": p[1]})
		var r := _measure(BattleUI.ALLY_TEAM, enemy)
		var verdict := "OK" if r.win >= TARGET_LOW and r.win <= TARGET_HIGH else ("偏易" if r.win > TARGET_HIGH else "偏难")
		print("  %-36s %5.1f%%   %5.1f      %s" % [c["name"], r.win, r.turns, verdict])

	print("\n目标区间：%d%% ~ %d%%（能赢但要动脑）" % [TARGET_LOW, TARGET_HIGH])
	quit()


func _report(title: String, ally: Array, enemy: Array) -> void:
	var r := _measure(ally, enemy)
	print("[%s]" % title)
	print("  我方：%s" % _fmt_team(ally))
	print("  敌方：%s" % _fmt_team(enemy))
	print("  我方胜率 %.1f%%　平均 %.1f 回合　平局 %.1f%%"
		% [r.win, r.turns, r.draw])
	print("  结束方式：全灭 %.1f%%　超时判定 %.1f%%　终局我方平均存活 %.2f 只"
		% [r.wipe, r.timeout, r.alive])


func _measure(ally: Array, enemy: Array) -> Dictionary:
	var wins := 0
	var draws := 0
	var turn_sum := 0
	var timeout := 0      # 打到回合上限、靠血量判定的局数
	var wipe := 0         # 某一方全灭的局数
	var alive_sum := 0    # 结束时我方存活数（衡量赢得多干净）
	for i in _runs:
		var st := BattleState.new()
		st.setup(
			ally.duplicate(true), enemy.duplicate(true),
			1000 + i,
			_db.get("element_chart", {}),
			_db.get("cards", {}), _db.get("skills", {}),
			BattleUI.LIBRARY.duplicate(), BattleUI.LIBRARY.duplicate(),
		)
		var tm := TurnMachine.new()
		tm.setup(st, "easy", "easy")
		tm.run()
		turn_sum += st.turn_index
		alive_sum += st.living_count(BattleState.Side.ALLY)
		if st.turn_index >= C.MAX_TURNS and st.outcome != "ongoing":
			timeout += 1
		elif st.living_count(BattleState.Side.ALLY) == 0 or st.living_count(BattleState.Side.ENEMY) == 0:
			wipe += 1
		if st.outcome == "ally_win":
			wins += 1
		elif st.outcome == "draw":
			draws += 1
	return {
		"win": float(wins) * 100.0 / float(_runs),
		"draw": float(draws) * 100.0 / float(_runs),
		"turns": float(turn_sum) / float(_runs),
		"timeout": float(timeout) * 100.0 / float(_runs),
		"wipe": float(wipe) * 100.0 / float(_runs),
		"alive": float(alive_sum) / float(_runs),
	}


func _fmt_team(t: Array) -> String:
	var parts: Array = []
	for e in t:
		var card: Dictionary = _db.get("cards", {}).get(e["card_id"], {})
		parts.append("%s Lv%d" % [String(card.get("name", e["card_id"])), int(e["level"])])
	return " + ".join(parts)
