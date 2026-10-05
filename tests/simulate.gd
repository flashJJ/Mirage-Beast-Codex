## 批量战斗模拟 —— 脱离 UI 跑 N 场，用于数值平衡与确定性验证
##
## 运行：
##   godot --headless --script res://tests/simulate.gd --runs 1000
##   godot --headless --script res://tests/simulate.gd --runs 20 --verbose
##
## 验证点：
##   1. 同种子跑两次结果完全一致（确定性）
##   2. 各关卡胜率落在合理区间（平衡性）
##   3. 无 push_error / push_warning 输出（配置与效果系统正确）
##
## 对应 dev/D-PoC技术验证清单.md 的 P6

extends SceneTree

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")

const DECK_CORE := [
	"beast_001", "beast_002", "beast_003", "beast_004",
	"beast_005", "beast_007", "spell_001", "spell_002",
]

var _runs := 200
var _verbose := false


func _init() -> void:
	_runs = _arg_int("--runs", 200)
	_verbose = _has_flag("--verbose")

	print("=== Mirage Beast Codex · 批量战斗模拟 ===")
	print("引擎：Godot %s" % Engine.get_version_info().get("string", "?"))

	# 1) 加载并校验配置
	var loaded := DataLoader.load_all_checked()
	var db: Dictionary = loaded["db"]
	var errors: Array = loaded["errors"]
	if not errors.is_empty():
		print("\n[配置校验] 发现 %d 个错误：" % errors.size())
		for e in errors:
			print("  ✗ %s" % e)
		print("\n请先修正 data/*.json 后再运行模拟。")
		quit(1)
		return
	print("[配置校验] 通过。卡牌 %d 张 / 技能 %d 个"
		% [(db["cards"] as Dictionary).size(), (db["skills"] as Dictionary).size()])

	# 2) 确定性验证
	_verify_determinism(db)

	# 3) 批量模拟
	var encounters: Array = (db["raw"]["enemies"] as Dictionary).get("items", [])
	print("\n[批量模拟] 每关 %d 场" % _runs)
	print("%-14s %-8s %8s %8s %8s %8s" % ["关卡", "难度", "我方胜", "敌方胜", "平局", "胜率"])
	print("-".repeat(56))

	for enc in encounters:
		var e: Dictionary = enc
		var tally := {"ally_win": 0, "enemy_win": 0, "draw": 0}
		for i in _runs:
			var outcome := _run_once(db, e, i + 1)
			tally[outcome] = int(tally.get(outcome, 0)) + 1
		var total := maxi(_runs, 1)
		var rate: float = float(tally["ally_win"]) * 100.0 / float(total)
		print("%-14s %-8s %8d %8d %8d %7.1f%%"
			% [String(e.get("name", "")), String(e.get("difficulty", "")),
			   tally["ally_win"], tally["enemy_win"], tally["draw"], rate])

	print("\n提示：胜率若长期 <20% 或 >90%，说明该关数值需要调整（改 data/*.json，不要改代码）。")
	quit(0)


func _run_once(db: Dictionary, enc: Dictionary, seed_value: int) -> String:
	var ally := [
		{"card_id": "beast_001", "level": 5},
		{"card_id": "beast_002", "level": 5},
		{"card_id": "beast_003", "level": 5},
	]
	var enemy: Array = (enc.get("units", []) as Array).duplicate(true)
	var library := DECK_CORE.duplicate()
	library.append_array(DECK_CORE.duplicate())  # 8 x 2 = 16 张

	var state := BattleState.new()
	state.setup(
		ally, enemy, seed_value,
		db.get("element_chart", {}),
		db.get("cards", {}), db.get("skills", {}),
		library, library
	)

	var tm := TurnMachine.new()
	tm.setup(state, "easy", String(enc.get("ai_level", "easy")))
	var outcome := tm.run()

	if _verbose:
		print("\n----- seed=%d · %s · 结果=%s -----" % [seed_value, String(enc.get("id", "")), outcome])
		for line in state.battle_log:
			print("  " + String(line))

	return outcome


func _verify_determinism(db: Dictionary) -> void:
	var encounters: Array = (db["raw"]["enemies"] as Dictionary).get("items", [])
	if encounters.is_empty():
		return
	var enc: Dictionary = encounters[0]

	var a := _run_once(db, enc, 42)
	var b := _run_once(db, enc, 42)
	if a == b:
		print("[确定性] 通过：seed=42 两次运行结果一致（%s）" % a)
	else:
		print("[确定性] ✗ 失败：seed=42 两次结果不同（%s vs %s）" % [a, b])


func _arg_int(flag: String, default_value: int) -> int:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if String(args[i]) == flag and i + 1 < args.size():
			return int(args[i + 1])
	return default_value


func _has_flag(flag: String) -> bool:
	for a in OS.get_cmdline_args():
		if String(a) == flag:
			return true
	return false
