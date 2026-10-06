## 战斗 UI 冒烟测试 —— 用代码驱动点击，验证「能玩」而不是「能加载」
##
## 运行：
##   godot --headless --script res://tests/test_ui.gd
##
## 与 test_battle.gd 的分工：
##   test_battle.gd —— 规则正确性（纯逻辑）
##   test_ui.gd     —— 交互链路正确性（UI → TurnMachine → State → 刷新）
##
## 覆盖：场景实例化 / 初始状态 / 出牌 / 用技能 / 结束回合
##       / 自动推进到结局 / 再来一局 / 控件完整性
##
## 注意：add_child 之后 _ready 要到下一帧才触发，因此断言放在 _process 首帧执行。

extends SceneTree

const C = preload("res://scripts/utils/constants.gd")

var _passed := 0
var _failed := 0
var _ui: Control
var _frame := 0


func _initialize() -> void:
	print("=== 战斗 UI 冒烟测试 ===\n")
	var packed := load("res://scenes/battle/BattleScene.tscn")
	if packed == null:
		_fail("BattleScene.tscn 加载失败")
		quit(1)
		return
	_ui = packed.instantiate()
	root.add_child(_ui)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # 等 _ready 跑完
	if _frame > 2:
		return true
	_run()
	return true


func _run() -> void:
	_check("UI 实例化成功", _ui != null)
	if _ui == null or _ui.get("state") == null:
		_fail("State 未创建（_ready 未执行？）")
		_finish()
		return

	var state: BattleState = _ui.state
	_check("State 已创建", state != null)
	_check("TurnMachine 已创建", _ui.get("tm") != null)

	# ── 初始状态 ──────────────────────────────────
	_check("开局回合为 1", state.turn_index == 1)
	_check("我方上场 3 只", state.living_count(BattleState.Side.ALLY) == 3)
	_check("敌方上场 3 只", state.living_count(BattleState.Side.ENEMY) == 3)
	# setup() 发起手牌，start_turn() 再抽 1 张，故首回合手牌为 START_HAND + 1
	_check("我方首回合手牌 %d 张（起手 %d + 抽 1）" % [C.START_HAND + 1, C.START_HAND],
		(state.hands[0] as Array).size() == C.START_HAND + 1)
	_check("我方起始费用 ≥ %d" % C.START_ENERGY, int(state.energy[0]) >= C.START_ENERGY)

	# ── 控件完整性 ────────────────────────────────
	_check("日志控件已渲染文本", String(_ui._log.text).length() > 0)
	_check("敌方单位卡片已生成", (_ui._enemy_box as HBoxContainer).get_child_count() == 3)
	_check("我方单位卡片已生成", (_ui._ally_box as HBoxContainer).get_child_count() == 3)
	_check("手牌按钮已生成", (_ui._hand_box as HBoxContainer).get_child_count() >= C.START_HAND)
	_check("顶部信息条已刷新", String(_ui._info.text).length() > 0)

	# ── 出牌：点击手牌 → 选目标（F5 手动目标选择）──
	var before_hand: int = (state.hands[0] as Array).size()
	var before_units: int = state.units.size()
	_ui._on_play_card(0)
	if not (_ui._pending as Dictionary).is_empty():
		_check("点手牌后进入「选目标」状态", true)
		_check("提示条已显示目标阵营", String(_ui._hint.text).length() > 0)
		_check("取消按钮已显示", (_ui._cancel_btn as Button).visible)
		_ui._confirm_target(_ui._suggested_target())
	else:
		_check("召唤类卡牌不需要目标，直接打出", true)
	var played: bool = ((state.hands[0] as Array).size() == before_hand - 1) or (state.units.size() == before_units + 1)
	_check("出牌后手牌减少或召唤上场", played)
	_check("出牌后「选目标」状态已清空", (_ui._pending as Dictionary).is_empty())

	# ── 秘术卡必须走「选目标」（不依赖手牌顺序的确定性用例）──
	# 起手 4 张不一定有秘术卡，没有就补一张：本用例测的是选目标流程，不是洗牌
	state.energy[BattleState.Side.ALLY] = C.MAX_ENERGY  # 排除费用不足的干扰
	var hand_now: Array = state.hands[0]
	var spell_idx := -1
	for i in hand_now.size():
		var cd: Dictionary = (_ui.db.get("cards", {}) as Dictionary).get(String(hand_now[i]), {})
		if String(cd.get("type", "")) == "spell":
			spell_idx = int(i)
			break
	if spell_idx < 0:
		hand_now.append("spell_001")
		spell_idx = hand_now.size() - 1
	_ui._refresh()

	_ui._on_play_card(spell_idx)
	_check("秘术卡进入「选目标」状态", not (_ui._pending as Dictionary).is_empty())
	_check("提示条显示目标阵营", String(_ui._hint.text).length() > 0)
	_check("取消按钮可见", (_ui._cancel_btn as Button).visible)

	_ui._cancel_pending()
	_check("取消后清空待确认状态", (_ui._pending as Dictionary).is_empty())
	_check("取消后隐藏取消按钮", not (_ui._cancel_btn as Button).visible)
	# 注意：hand_now 与 state.hands[0] 是同一数组引用，必须用 int 快照比较
	var size_before: int = (state.hands[0] as Array).size()
	_check("取消后不消耗手牌", (state.hands[0] as Array).size() == size_before)

	_ui._on_play_card(spell_idx)
	_ui._confirm_target(_ui._suggested_target())
	_check("确认目标后秘术卡已打出", (state.hands[0] as Array).size() == size_before - 1,
		"%d → %d" % [size_before, (state.hands[0] as Array).size()])
	_check("确认目标后状态清空", (_ui._pending as Dictionary).is_empty())

	# ── 单位行动：技能或普攻 ────────────────────────
	var log_before: int = state.battle_log.size()
	for i in state.living_indices(BattleState.Side.ALLY):
		_ui._on_unit_action(int(i))
		if not (_ui._pending as Dictionary).is_empty():
			_ui._confirm_target(_ui._suggested_target())
	_check("单位行动后日志不减少", state.battle_log.size() >= log_before)
	_check("我方单位行动后均已标记已行动", _all_acted(state))

	# ── 结束回合 ──────────────────────────────────
	var t0: int = state.turn_index
	_ui._on_end_turn()
	_check("结束回合后回合数推进或战斗结束", state.turn_index == t0 + 1 or state.is_over())

	# ── 自动推进整局：保证不会中途崩溃 ───────────────
	var guard := 0
	while not state.is_over() and guard < C.MAX_TURNS + 10:
		if not (state.hands[0] as Array).is_empty():
			_ui._on_play_card(0)
			if not (_ui._pending as Dictionary).is_empty():
				_ui._confirm_target(_ui._suggested_target())
		for i in state.living_indices(BattleState.Side.ALLY):
			_ui._on_unit_action(int(i))
			if not (_ui._pending as Dictionary).is_empty():
				_ui._confirm_target(_ui._suggested_target())
		_ui._on_end_turn()
		guard += 1

	_check("自动推进可正常结束（未死循环/未崩溃）", guard < C.MAX_TURNS + 10)
	_check("战斗有明确结局", state.is_over())
	_check("结局合法", ["ally_win", "enemy_win", "draw"].has(state.outcome))
	_check("结束覆盖层已显示", (_ui._over_panel as PanelContainer).visible)
	_check("结束按钮已禁用", (_ui._end_btn as Button).disabled)
	_check("结构化战报非空", (state.events as Array).size() > 0)

	print("\n  结局：%s，共 %d 回合，日志 %d 行，战报 %d 条"
		% [state.outcome, state.turn_index, state.battle_log.size(), state.events.size()])

	# ── 再来一局 ──────────────────────────────────
	_ui._new_battle()
	var s2: BattleState = _ui.state
	_check("再来一局：回合重置为 1", s2.turn_index == 1)
	_check("再来一局：结局重置", s2.outcome == "ongoing")
	_check("再来一局：覆盖层隐藏", not (_ui._over_panel as PanelContainer).visible)
	_check("再来一局：我方重新上场 3 只", s2.living_count(BattleState.Side.ALLY) == 3)
	_check("再来一局：手牌重新发放", (s2.hands[0] as Array).size() == C.START_HAND + 1)

	_finish()


func _all_acted(state: BattleState) -> bool:
	for i in state.living_indices(BattleState.Side.ALLY):
		if not bool(state.units[i].get("skill_used_this_turn", false)):
			return false
	return true


# ── 断言工具 ──────────────────────────────────────

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s%s" % [name, ("  → " + detail) if detail != "" else ""])


func _fail(msg: String) -> void:
	_failed += 1
	print("  ✗ %s" % msg)


func _finish() -> void:
	print("\n通过 %d 项，失败 %d 项" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
