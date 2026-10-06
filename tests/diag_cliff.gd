## 等级悬崖根因诊断（F43 配套）
##
## 运行：godot --headless --script res://tests/diag_cliff.gd --runs 400
##
## 为什么需要它：改成乘性减伤后，等级扫描仍然是 Lv7 90% → Lv8 37%，
## 说明「悬崖」的根因不是减伤模型。必须把三个可能因素分开：
##   1) 模型不对称（同阵容镜像对局，理论应 ≈50%）
##   2) 先手 / AI 偏差（同一组对局**换边**后，胜率应互补）
##   3) 阵容不公平（我方 3 只里 2 只没有输出技能，P4）
## 只有量化出各自贡献，才知道该改模型、改规则还是改配队数据。

extends SceneTree

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")
const Session = preload("res://scripts/session.gd")

var _runs := 400
var _db: Dictionary


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			_runs = int(args[i + 1])

	_db = DataLoader.load_all()
	Session.ensure()
	print("=== 等级悬崖根因诊断（每组 %d 局）===" % _runs)

	var a := Session.ally_team.duplicate(true)
	var b := Session.enemy_team.duplicate(true)

	# ① 镜像对局：双方完全同阵容同等级 → 理论 50%
	print("\n① 镜像对局（双方阵容与等级完全相同）")
	print("  阵容               等级   左方胜率   平均回合   偏离 50%")
	for lv in [6, 8, 10]:
		var m: Dictionary = _measure(_same_level(a, lv), _same_level(a, lv))
		var m2: Dictionary = _measure(_same_level(b, lv), _same_level(b, lv))
		_row("焰尾狐队 镜像", lv, m)
		_row("熔岩队   镜像", lv, m2)

	# ② 换边对照：A(我方阵容) vs B(敌方阵容) 同等级，再反过来
	print("\n② 换边对照（两边同等级，只交换先后手与阵容归属）")
	print("  对局                       等级   左方胜率   平均回合")
	for lv in [7, 8, 9]:
		var ab := _measure(_same_level(a, lv), _same_level(b, lv))
		var ba := _measure(_same_level(b, lv), _same_level(a, lv))
		print("  A(焰尾狐队) vs B(熔岩队)    Lv%-2d   %5.1f%%     %5.1f" % [lv, ab.win, ab.turns])
		print("  B(熔岩队)   vs A(焰尾狐队)  Lv%-2d   %5.1f%%     %5.1f" % [lv, ba.win, ba.turns])
		print("     └ 互补性 = %5.1f%%（应≈100%%，偏离说明先手/AI 有系统偏差）"
			% [ab.win + ba.win])

	# ③ 等级差扫描（细粒度：以 0.5 级为单位是不可能的，改成看 ±1 级的斜率）
	print("\n③ 等级差扫描（我方固定 Lv8，敌方 Lv6~Lv10）")
	print("  敌方等级   我方胜率   相邻级差   平均回合")
	var prev := -1.0
	for lv in range(6, 11):
		var r := _measure(a, _same_level(b, lv))
		var delta := "" if prev < 0 else "%+.1f pt" % (r.win - prev)
		print("    Lv%-2d      %5.1f%%   %9s   %5.1f" % [lv, r.win, delta, r.turns])
		prev = r.win
	quit()


func _row(title: String, lv: int, r: Dictionary) -> void:
	print("  %-22s Lv%-2d   %5.1f%%     %5.1f     %+5.1f pt"
		% [title, lv, r.win, r.turns, r.win - 50.0])


func _same_level(team: Array, lv: int) -> Array:
	var out := []
	for e in team:
		out.append({"card_id": (e as Dictionary)["card_id"], "level": lv})
	return out


func _measure(ally: Array, enemy: Array) -> Dictionary:
	var wins := 0
	var turn_sum := 0
	for i in _runs:
		var st := BattleState.new()
		st.setup(
			ally.duplicate(true), enemy.duplicate(true),
			1000 + i,
			_db.get("element_chart", {}),
			_db.get("cards", {}), _db.get("skills", {}),
			Session.library.duplicate(), Session.library.duplicate(),
		)
		var tm := TurnMachine.new()
		tm.setup(st, "easy", "easy")
		tm.run()
		turn_sum += st.turn_index
		if st.outcome == "ally_win":
			wins += 1
	return {
		"win": float(wins) * 100.0 / float(_runs),
		"turns": float(turn_sum) / float(_runs),
	}
