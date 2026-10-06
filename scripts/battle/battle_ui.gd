## 战斗 UI（V0 可玩版）
##
## 设计原则：
##  - 全部用代码构建界面（V0 无美术资产，且避免手写 .tscn 出错）
##  - UI 只做「显示 + 转发输入」，所有规则仍在 TurnMachine / BattleState 中
##  - 无中文方块字风险：统一使用 SystemFont（系统默认字体含 CJK）
##
## 交互（F5 手动目标选择）：
##  - 点击手牌 → 若需要目标则进入「选目标」状态，再点一个单位确认；不需要目标（召唤）直接打出
##  - 点击我方单位的技能按钮 → 同样进入「选目标」状态
##  - 「选目标」状态下合法目标会出现「选为目标」按钮；可随时点「取消」退出
##  - 点击「结束回合」→ 敌方行动并进入下一回合
##
## 为什么必须手动选目标：自动选目标把玩家的决策权全拿走了，
## 「打谁」是卡牌对战最核心的决策点，交给程序就等于没有玩法。

extends Control

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const BattleState = preload("res://scripts/battle/battle_state.gd")
const TurnMachine = preload("res://scripts/battle/turn_machine.gd")

const ALLY_COLOR  := Color(0.06, 0.20, 0.38)
const ENEMY_COLOR := Color(0.38, 0.10, 0.15)
const PANEL_COLOR := Color(0.10, 0.13, 0.22)

var _font: Font
var db: Dictionary
var state: BattleState
var tm: TurnMachine

var _enemy_box: HBoxContainer
var _ally_box: HBoxContainer
var _hand_box: HBoxContainer
var _log: RichTextLabel
var _info: Label
var _end_btn: Button
var _over_panel: PanelContainer
var _over_label: Label
var _hint: Label
var _cancel_btn: Button

## 待确认目标的行动。空字典 = 当前不在「选目标」状态。
## {"kind": "card"/"skill"/"basic", "index": int, "skill": Dictionary,
##  "skill_id": String, "side": int, "title": String}
var _pending: Dictionary = {}

# 我方初始阵容与卡组（V0 固定，后续由存档/构筑界面提供）
const ALLY_TEAM := [
	{"card_id": "beast_001", "level": 8},
	{"card_id": "beast_002", "level": 8},
	{"card_id": "beast_003", "level": 8},
]
## 对手阵容由 tests/balance.gd 实测选定（候选 B，AI 对 AI 胜率 84.3%）
## 改动这里必须重跑：godot --headless --script res://tests/balance.gd
const ENEMY_TEAM := [
	{"card_id": "beast_005", "level": 8},
	{"card_id": "beast_007", "level": 8},
	{"card_id": "beast_001", "level": 7},
]
const LIBRARY := [
	"beast_001", "beast_002", "beast_003", "beast_004",
	"beast_005", "beast_006", "beast_007", "spell_001",
	"spell_002", "beast_001", "beast_002", "beast_003",
	"beast_004", "beast_005", "beast_007", "spell_001",
]


func _ready() -> void:
	_font = SystemFont.new()
	db = DataLoader.load_all()
	_build_ui()
	_new_battle()


# ── 界面构建（只建一次）──────────────────────────

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 顶部信息条
	var top := HBoxContainer.new()
	root.add_child(top)
	_info = _label("—", 16)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_info)
	_end_btn = Button.new()
	_end_btn.text = "结束回合"
	_end_btn.custom_minimum_size = Vector2(110, 34)
	_end_btn.pressed.connect(_on_end_turn)
	top.add_child(_end_btn)

	# 选目标提示条
	var hint_bar := HBoxContainer.new()
	root.add_child(hint_bar)
	_hint = _label("", 14)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_bar.add_child(_hint)
	_cancel_btn = Button.new()
	_cancel_btn.text = "取消"
	_cancel_btn.custom_minimum_size = Vector2(80, 28)
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_cancel_pending)
	hint_bar.add_child(_cancel_btn)

	# 敌方
	root.add_child(_label("敌方", 15))
	_enemy_box = HBoxContainer.new()
	_enemy_box.add_theme_constant_override("separation", 8)
	root.add_child(_enemy_box)

	# 日志
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 150)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	if _font:
		_log.add_theme_font_override("normal_font", _font)
	_log.add_theme_font_size_override("normal_font_size", 13)
	root.add_child(_log)

	# 我方
	root.add_child(_label("我方（点击使用技能）", 15))
	_ally_box = HBoxContainer.new()
	_ally_box.add_theme_constant_override("separation", 8)
	root.add_child(_ally_box)

	# 手牌
	root.add_child(_label("手牌（点击出牌）", 15))
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 8)
	root.add_child(_hand_box)

	# 结束覆盖层
	_over_panel = PanelContainer.new()
	_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	_over_panel.visible = false
	add_child(_over_panel)
	var ov := VBoxContainer.new()
	_over_panel.add_child(ov)
	_over_label = _label("", 28)
	ov.add_child(_over_label)
	var again := Button.new()
	again.text = "再来一局"
	again.pressed.connect(_new_battle)
	ov.add_child(again)


# ── 战斗流程 ──────────────────────────────────────

func _new_battle() -> void:
	state = BattleState.new()
	state.setup(
		ALLY_TEAM.duplicate(true), ENEMY_TEAM.duplicate(true),
		randi(),
		db.get("element_chart", {}),
		db.get("cards", {}), db.get("skills", {}),
		LIBRARY.duplicate(), LIBRARY.duplicate(),
	)
	tm = TurnMachine.new()
	tm.setup(state, "human", "easy")
	tm.start_turn()
	_pending = {}
	_over_panel.visible = false
	_refresh()


func _refresh() -> void:
	if state == null:
		return

	_info.text = "回合 %d / %d　|　费用 %d / %d　|　牌库 %d 张" % [
		state.turn_index, C.MAX_TURNS,
		int(state.energy[BattleState.Side.ALLY]), C.MAX_ENERGY,
		(state.libraries[BattleState.Side.ALLY] as Array).size(),
	]

	_fill_units(_enemy_box, BattleState.Side.ENEMY)
	_fill_units(_ally_box, BattleState.Side.ALLY)
	_fill_hand()
	_refresh_hint()

	# 日志：只显示最后 12 行
	var lines: Array = state.battle_log
	var start := maxi(lines.size() - 12, 0)
	var out := ""
	for i in range(start, lines.size()):
		out += String(lines[i]) + "\n"
	_log.text = out

	if state.is_over():
		_end_btn.disabled = true
		var txt := "胜利！" if state.outcome == "ally_win" else ("失败…" if state.outcome == "enemy_win" else "平局")
		_over_label.text = "%s\n共 %d 回合" % [txt, state.turn_index]
		_over_panel.visible = true
	else:
		_end_btn.disabled = false
		_over_panel.visible = false


# ── 动态区域 ──────────────────────────────────────

func _fill_units(box: HBoxContainer, side: int) -> void:
	for c in box.get_children():
		c.queue_free()
	for i in state.units.size():
		var u: Dictionary = state.units[i]
		if int(u.get("side", -1)) != side:
			continue
		box.add_child(_unit_widget(i, u, side == BattleState.Side.ALLY))


func _unit_widget(idx: int, u: Dictionary, is_ally: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(180, 118)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ALLY_COLOR if is_ally else ENEMY_COLOR
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)

	var alive: bool = bool(u.get("alive", false))
	var title := _label("%s Lv%d %s" % [
		String(u.get("name", "?")), int(u.get("level", 1)),
		"" if alive else "（倒下）"], 14)
	v.add_child(title)

	var bar := ProgressBar.new()
	bar.max_value = maxf(float(u.get("max_hp", 1)), 1.0)
	bar.value = maxf(float(u.get("hp", 0)), 0.0)
	bar.custom_minimum_size = Vector2(160, 14)
	bar.show_percentage = false
	if _font:
		bar.add_theme_font_override("font", _font)
	v.add_child(bar)

	v.add_child(_label("HP %d / %d　盾 %d" % [
		int(u.get("hp", 0)), int(u.get("max_hp", 1)), int(u.get("shield", 0))], 13))
	v.add_child(_label("ATK %d　DEF %d　SPD %d" % [
		int(u.get("atk", 0)), int(u.get("def", 0)), int(u.get("spd", 0))], 12))

	var used: bool = bool(u.get("skill_used_this_turn", false))
	v.add_child(_label("已行动" if used else "可行动", 12))

	# 「选目标」状态下：合法目标出现「选为目标」按钮
	if alive and _is_legal_target(idx):
		var tbtn := Button.new()
		tbtn.text = "选为目标"
		tbtn.pressed.connect(_confirm_target.bind(idx))
		v.add_child(tbtn)

	if is_ally and alive and not used and _pending.is_empty():
		var sk := _first_usable_skill(u)
		var btn := Button.new()
		btn.text = ("技能 · %s" % String(sk.get("name", "?"))) if not sk.is_empty() else "普攻"
		btn.pressed.connect(_on_unit_action.bind(idx))
		v.add_child(btn)

	return p


func _fill_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()
	var hand: Array = state.hands[BattleState.Side.ALLY]
	var energy: int = int(state.energy[BattleState.Side.ALLY])
	for i in hand.size():
		var cid := String(hand[i])
		var card: Dictionary = db.get("cards", {}).get(cid, {})
		var cost := int(card.get("cost", 0))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(118, 96)
		btn.text = "%s\n费用 %d" % [String(card.get("name", cid)), cost]
		btn.disabled = cost > energy
		btn.pressed.connect(_on_play_card.bind(i))
		_hand_box.add_child(btn)
	if hand.is_empty():
		_hand_box.add_child(_label("（手牌为空）", 13))


# ── 输入处理 ──────────────────────────────────────

## 按技能的 target 配置自动选目标 —— 关键：治疗/护盾/净化要打自己人
## 目标阵营来自 data/skills.json 的 target.side，UI 不许自己拍脑袋定死为敌方
func _auto_target(skill: Dictionary, caster_index: int = -1) -> int:
	var cfg: Dictionary = skill.get("target", {})
	var side_key := String(cfg.get("side", "enemy"))
	if side_key == "self":
		return caster_index
	var side := BattleState.Side.ALLY if side_key == "ally" else BattleState.Side.ENEMY
	var pool: Array = state.living_indices(side)
	if pool.is_empty():
		return -1
	if String(cfg.get("select", "lowest_hp")) == "highest_atk":
		pool.sort_custom(func(a, b): return int(state.units[a].get("atk", 0)) > int(state.units[b].get("atk", 0)))
	else:
		pool.sort_custom(func(a, b): return int(state.units[a].get("hp", 0)) < int(state.units[b].get("hp", 0)))
	return int(pool[0])


func _lowest_enemy() -> int:
	return _auto_target({"target": {"side": "enemy", "select": "lowest_hp"}})


## 该单位当前费用下第一个可用的主动技能；没有则返回空字典（应走普攻）
func _first_usable_skill(u: Dictionary) -> Dictionary:
	var energy: int = int(state.energy[BattleState.Side.ALLY])
	for skid in (u.get("skills", []) as Array):
		var sk: Dictionary = state.skills_db.get(skid, {})
		if String(sk.get("trigger", "active")) != "active":
			continue
		if int(sk.get("cost", 0)) > energy:
			continue
		return sk
	return {}


## 技能需要的目标阵营；"self" 或不需要目标时返回 -1
func _target_side(skill: Dictionary) -> int:
	var side_key := String((skill.get("target", {}) as Dictionary).get("side", "enemy"))
	if side_key == "self":
		return -1
	return BattleState.Side.ALLY if side_key == "ally" else BattleState.Side.ENEMY


func _is_legal_target(unit_index: int) -> bool:
	if _pending.is_empty():
		return false
	if int(state.units[unit_index].get("side", -1)) != int(_pending.get("side", -2)):
		return false
	return bool(state.units[unit_index].get("alive", false))


func _refresh_hint() -> void:
	if _pending.is_empty():
		_hint.text = ""
		_cancel_btn.visible = false
		return
	var who := "我方" if int(_pending.get("side", 0)) == BattleState.Side.ALLY else "敌方"
	_hint.text = "选择目标：%s → 点击一个%s单位" % [String(_pending.get("title", "?")), who]
	_cancel_btn.visible = true


func _set_pending(p: Dictionary) -> void:
	_pending = p
	_refresh()
	# 不需要选目标的行动（召唤 / 自身增益）直接进入执行，target 传 -1
	if int(p.get("side", -1)) < 0:
		_finish_pending(-1)


func _cancel_pending() -> void:
	_pending = {}
	_refresh()


func _confirm_target(target_index: int) -> void:
	_finish_pending(target_index)


func _finish_pending(target_index: int) -> void:
	if _pending.is_empty():
		return
	var kind := String(_pending.get("kind", ""))
	var idx := int(_pending.get("index", -1))
	var sid := String(_pending.get("skill_id", ""))
	_pending = {}
	match kind:
		"card":
			tm.play_card(BattleState.Side.ALLY, idx, target_index)
		"skill":
			tm.use_skill(idx, sid, target_index)
		"basic":
			tm.basic_attack(idx, target_index)
		_:
			pass
	_refresh()


## 「选目标」状态下建议的默认目标（给测试与未来的「自动」按钮用）
func _suggested_target() -> int:
	if _pending.is_empty():
		return -1
	var sk: Dictionary = _pending.get("skill", {})
	var caster := int(_pending.get("index", -1)) if String(_pending.get("kind", "")) != "card" else -1
	return _auto_target(sk, caster)


func _on_play_card(hand_index: int) -> void:
	if state == null or state.is_over():
		return
	var hand: Array = state.hands[BattleState.Side.ALLY]
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: Dictionary = db.get("cards", {}).get(String(hand[hand_index]), {})
	var sk := {}
	var skid0 := ""
	for skid in (card.get("skills", []) as Array):
		if state.skills_db.has(skid):
			sk = state.skills_db[skid]
			skid0 = String(skid)
			break
	# 召唤幻兽不需要目标，直接打出
	var side := -1 if String(card.get("type", "beast")) == "beast" else _target_side(sk)
	_set_pending({
		"kind": "card", "index": hand_index, "skill": sk, "skill_id": skid0, "side": side,
		"title": String(card.get("name", "?")),
	})


## 单位行动：优先用主动技能，没有可用技能则普攻。
## 需要目标的行动先进「选目标」状态，由玩家点单位确认。
func _on_unit_action(unit_index: int) -> void:
	if state == null or state.is_over():
		return
	if unit_index < 0 or unit_index >= state.units.size():
		return
	var u: Dictionary = state.units[unit_index]
	if not bool(u.get("alive", false)) or bool(u.get("skill_used_this_turn", false)):
		return
	for skid in (u.get("skills", []) as Array):
		var sk: Dictionary = state.skills_db.get(skid, {})
		if String(sk.get("trigger", "active")) != "active":
			continue
		if int(sk.get("cost", 0)) > int(state.energy[BattleState.Side.ALLY]):
			continue
		_set_pending({
			"kind": "skill", "index": unit_index, "skill": sk, "skill_id": String(skid),
			"side": _target_side(sk),
			"title": String(sk.get("name", "?")),
		})
		return
	# 只有进场/被动技能的单位也要有输出手段，否则等于站桩挨打
	_set_pending({
		"kind": "basic", "index": unit_index, "skill": {}, "skill_id": "",
		"side": BattleState.Side.ENEMY,
		"title": "普攻",
	})


func _on_end_turn() -> void:
	if state == null or state.is_over():
		return
	_pending = {}
	tm.advance_turn()
	_refresh()


# ── 小工具 ────────────────────────────────────────

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	return l
