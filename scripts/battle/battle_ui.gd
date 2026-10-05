## 战斗 UI —— V0 可玩版
##
## 设计原则：
##  - V0 不使用任何美术资产，全部用 ColorRect + Label 表达（美术在 M4 替换）
##  - UI 只做「显示 + 转发输入」，所有规则判定交给 TurnMachine，不重复实现
##  - 每次操作后整体重建界面（V0 规模极小，重建比增量更新更不容易出错）
##
## 交互约定：
##  - 点击手牌        → 打出该卡
##  - 点击我方单位    → 使用该单位的主动技能（本回合未用过才可）
##  - 点击「结束回合」 → 敌方行动并进入下一回合

extends Control

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")

const COL_BG    := Color8(0x16, 0x21, 0x3E)
const COL_PANEL := Color8(0x0F, 0x34, 0x60)
const COL_ENEMY := Color8(0xE9, 0x45, 0x60)
const COL_ALLY  := Color8(0x6B, 0xCB, 0x77)
const COL_TEXT  := Color8(0xF0, 0xF0, 0xF0)
const COL_GOLD  := Color8(0xFF, 0xD9, 0x3D)

var db: Dictionary
var state: BattleState
var tm: TurnMachine

var _info: Label
var _log: RichTextLabel
var _stage: Control
var _result: Label


func _ready() -> void:
	_build_shell()
	_start_battle()


# ── 界面骨架 ──────────────────────────────────────

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_info = Label.new()
	_info.position = Vector2(16, 10)
	_info.size = Vector2(700, 28)
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", COL_GOLD)
	add_child(_info)

	_stage = Control.new()
	_stage.position = Vector2(16, 44)
	_stage.size = Vector2(928, 380)
	add_child(_stage)

	_log = RichTextLabel.new()
	_log.position = Vector2(16, 432)
	_log.size = Vector2(928, 92)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 13)
	add_child(_log)

	var end_btn := Button.new()
	end_btn.text = "结束回合"
	end_btn.position = Vector2(790, 8)
	end_btn.size = Vector2(150, 32)
	end_btn.pressed.connect(_on_end_turn)
	add_child(end_btn)

	_result = Label.new()
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.size = Vector2(600, 60)
	_result.position = Vector2(180, 240)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 40)
	_result.add_theme_color_override("font_color", COL_GOLD)
	_result.visible = false
	add_child(_result)


# ── 战斗初始化 ────────────────────────────────────

func _start_battle() -> void:
	var loaded := DataLoader.load_all_checked()
	db = loaded["db"]
	var errors: Array = loaded["errors"]
	if not errors.is_empty():
		_result.text = "配置错误 %d 项，详见控制台" % errors.size()
		_result.visible = true
		for e in errors:
			push_error(e)
		return

	var ally := [
		{"card_id": "beast_001", "level": 6},
		{"card_id": "beast_002", "level": 6},
		{"card_id": "beast_003", "level": 6},
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

	state = BattleState.new()
	state.setup(ally, enemy, randi(),
		db.get("element_chart", {}),
		db.get("cards", {}), db.get("skills", {}),
		library, library)

	tm = TurnMachine.new()
	tm.setup(state, "player", "easy")
	tm.start_turn()
	_refresh()


# ── 刷新 ──────────────────────────────────────────

func _refresh() -> void:
	if state == null:
		return

	for c in _stage.get_children():
		c.queue_free()

	_info.text = "回合 %d / %d　　费用 %d/%d　　牌库 我 %d / 敌 %d" % [
		state.turn_index, C.MAX_TURNS,
		int(state.energy[BattleState.Side.ALLY]), C.MAX_ENERGY,
		(state.libraries[BattleState.Side.ALLY] as Array).size(),
		(state.libraries[BattleState.Side.ENEMY] as Array).size(),
	]

	_row(BattleState.Side.ENEMY, Vector2(0, 0))
	_row(BattleState.Side.ALLY, Vector2(0, 130))
	_hand(Vector2(0, 270))

	var lines: Array = state.battle_log
	var show_from := maxi(lines.size() - 8, 0)
	var txt := ""
	for i in range(show_from, lines.size()):
		txt += String(lines[i]) + "\n"
	_log.text = txt

	if state.is_over():
		_result.text = _result_text(state.outcome)
		_result.visible = true


func _result_text(outcome: String) -> String:
	match outcome:
		"ally_win":
			return "胜利！"
		"enemy_win":
			return "败北…"
		"draw":
			return "平局"
		_:
			return outcome


# ── 单位行 ────────────────────────────────────────

func _row(side: int, pos: Vector2) -> void:
	var is_ally := side == BattleState.Side.ALLY
	var idx := 0
	for i in state.units.size():
		var u: Dictionary = state.units[i]
		if int(u.get("side", -1)) != side:
			continue
		_stage.add_child(_unit_panel(i, u, is_ally, pos + Vector2(idx * 250, 0)))
		idx += 1


func _unit_panel(index: int, u: Dictionary, is_ally: bool, pos: Vector2) -> Control:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(230, 110)

	var bg := ColorRect.new()
	bg.color = COL_PANEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(bg)

	var alive := bool(u.get("alive", false))
	var accent := COL_ALLY if is_ally else COL_ENEMY
	if not alive:
		accent = Color8(0x8A, 0x8A, 0x8A)

	var name_lbl := Label.new()
	name_lbl.position = Vector2(8, 6)
	name_lbl.size = Vector2(214, 22)
	name_lbl.text = "%s Lv%d" % [String(u.get("name", "?")), int(u.get("level", 1))]
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", accent)
	panel.add_child(name_lbl)

	var hp := ProgressBar.new()
	hp.position = Vector2(8, 32)
	hp.size = Vector2(214, 14)
	hp.max_value = maxi(int(u.get("max_hp", 1)), 1)
	hp.value = maxi(int(u.get("hp", 0)), 0)
	hp.show_percentage = false
	panel.add_child(hp)

	var hp_lbl := Label.new()
	hp_lbl.position = Vector2(8, 48)
	hp_lbl.size = Vector2(214, 18)
	var shield: int = int(u.get("shield", 0))
	hp_lbl.text = "HP %d/%d%s" % [
		maxi(int(u.get("hp", 0)), 0), int(u.get("max_hp", 1)),
		(" 盾%d" % shield) if shield > 0 else "",
	]
	hp_lbl.add_theme_font_size_override("font_size", 13)
	hp_lbl.add_theme_color_override("font_color", COL_TEXT)
	panel.add_child(hp_lbl)

	var stat_lbl := Label.new()
	stat_lbl.position = Vector2(8, 68)
	stat_lbl.size = Vector2(214, 18)
	stat_lbl.text = "ATK %d  DEF %d  SPD %d" % [
		int(u.get("atk", 0)), int(u.get("def", 0)), int(u.get("spd", 0))]
	stat_lbl.add_theme_font_size_override("font_size", 12)
	stat_lbl.add_theme_color_override("font_color", COL_TEXT)
	panel.add_child(stat_lbl)

	var used: bool = bool(u.get("skill_used_this_turn", false))
	var act_lbl := Label.new()
	act_lbl.position = Vector2(8, 88)
	act_lbl.size = Vector2(214, 18)
	act_lbl.text = "已行动" if used else "可行动"
	act_lbl.add_theme_font_size_override("font_size", 12)
	act_lbl.add_theme_color_override("font_color", COL_GOLD if not used else Color8(0x8A, 0x8A, 0x8A))
	panel.add_child(act_lbl)

	# 我方单位可点击 → 使用主动技能
	if is_ally and alive and not used:
		var btn := Button.new()
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.pressed.connect(_on_unit_pressed.bind(index))
		panel.add_child(btn)

	return panel


# ── 手牌 ──────────────────────────────────────────

func _hand(pos: Vector2) -> void:
	var hand: Array = state.hands[BattleState.Side.ALLY]
	var energy: int = int(state.energy[BattleState.Side.ALLY])
	for i in hand.size():
		var card_id := String(hand[i])
		var card: Dictionary = db.get("cards", {}).get(card_id, {})
		var cost := int(card.get("cost", 0))
		var affordable := cost <= energy

		var btn := Button.new()
		btn.position = pos + Vector2(i * 160, 0)
		btn.size = Vector2(150, 100)
		btn.text = "%s\n费用 %d\n%s" % [
			String(card.get("name", card_id)), cost,
			("ATK %d / HP %d" % [int(card.get("base", {}).get("atk", 0)),
								  int(card.get("base", {}).get("hp", 0))])
			if String(card.get("type", "")) == "beast" else "秘术卡",
		]
		btn.disabled = not affordable or state.is_over()
		btn.pressed.connect(_on_card_pressed.bind(i))
		_stage.add_child(btn)


# ── 输入处理 ──────────────────────────────────────

func _on_card_pressed(hand_index: int) -> void:
	if state == null or state.is_over():
		return
	var target := _default_target()
	tm.play_card(BattleState.Side.ALLY, hand_index, target)
	_after_action()


func _on_unit_pressed(unit_index: int) -> void:
	if state == null or state.is_over():
		return
	var u: Dictionary = state.units[unit_index]
	for skid in (u.get("skills", []) as Array):
		var sk: Dictionary = state.skills_db.get(skid, {})
		if String(sk.get("trigger", "active")) != "active":
			continue
		if int(sk.get("cost", 0)) > int(state.energy[BattleState.Side.ALLY]):
			continue
		if tm.use_skill(unit_index, String(skid), _default_target()):
			break
	_after_action()


func _on_end_turn() -> void:
	if state == null or state.is_over():
		return
	tm.advance_turn()
	_refresh()


func _after_action() -> void:
	_refresh()
	if state.is_over():
		_result.text = _result_text(state.outcome)
		_result.visible = true


## 自动目标：敌方血量最低的存活单位（V0 无手动选目标 UI）
func _default_target() -> int:
	var best := -1
	var best_hp := 2147483647
	for i in state.living_indices(BattleState.Side.ENEMY):
		var hp: int = int(state.units[i].get("hp", 0))
		if hp < best_hp:
			best_hp = hp
			best = int(i)
	return best
