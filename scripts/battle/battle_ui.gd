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
const Session = preload("res://scripts/session.gd")

const DECK_SCENE := "res://scenes/deck/DeckScene.tscn"

const ALLY_COLOR  := Color(0.06, 0.20, 0.38)
const ENEMY_COLOR := Color(0.38, 0.10, 0.15)
const PANEL_COLOR := Color(0.10, 0.13, 0.22)

## 属性色（与 design/dev/C-美术规格书.md §2.2 一致，不要自定）
const ELEMENT_COLOR := {
	"fire":  Color("#E94560"),
	"water": Color("#4D96FF"),
	"wood":  Color("#6BCB77"),
	"light": Color("#FFD93D"),
	"dark":  Color("#9B5DE5"),
}

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
## 本局战绩是否已计入 Session（_refresh 会被多次调用，只能记一次）
var _recorded := false
## 单位下标 → 界面上的卡片控件（打击动效需要按单位找节点）
var _widget_by_idx: Dictionary = {}

## 阵容与牌库来自 Session（由编组界面写入，默认见 scripts/session.gd）


func _ready() -> void:
	_font = SystemFont.new()
	db = DataLoader.load_all()
	Session.ensure()
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
	_log.custom_minimum_size = Vector2(0, 100)
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
	var back := Button.new()
	back.text = "返回编组"
	back.pressed.connect(func(): get_tree().change_scene_to_file(DECK_SCENE))
	ov.add_child(back)


# ── 战斗流程 ──────────────────────────────────────

func _new_battle() -> void:
	Session.ensure()
	state = BattleState.new()
	state.setup(
		Session.ally_team.duplicate(true), Session.enemy_team.duplicate(true),
		randi(),
		db.get("element_chart", {}),
		db.get("cards", {}), db.get("skills", {}),
		Session.library.duplicate(), Session.library.duplicate(),
	)
	tm = TurnMachine.new()
	tm.setup(state, "human", "easy")
	tm.start_turn()
	_pending = {}
	_recorded = false
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

	_widget_by_idx.clear()
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
		if not _recorded:
			Session.record(state.outcome)
			_recorded = true
		_end_btn.disabled = true
		var txt := "胜利！" if state.outcome == "ally_win" else ("失败…" if state.outcome == "enemy_win" else "平局")
		_over_label.text = "%s\n共 %d 回合\n战绩 %d 胜 %d 负 %d 平" % [
			txt, state.turn_index, Session.wins, Session.losses, Session.draws]
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
	p.custom_minimum_size = Vector2(200, 124)
	_widget_by_idx[idx] = p
	var sb := StyleBoxFlat.new()
	sb.bg_color = ALLY_COLOR if is_ally else ENEMY_COLOR
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = ELEMENT_COLOR.get(String(u.get("element", "")), Color(0.5, 0.5, 0.5))
	p.add_theme_stylebox_override("panel", sb)

	# 横向布局：左边立绘，右边数值与按钮
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)

	var alive: bool = bool(u.get("alive", false))
	h.add_child(_portrait_node(
		String(u.get("card_id", "")), String(u.get("element", "")), alive))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)

	var title := _label("%s Lv%d" % [String(u.get("name", "?")), int(u.get("level", 1))], 13)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_child(title)
	if not alive:
		var dead := _label("倒下", 12)
		dead.add_theme_color_override("font_color", Color(0.75, 0.7, 0.7))
		v.add_child(dead)

	var bar := ProgressBar.new()
	bar.max_value = maxf(float(u.get("max_hp", 1)), 1.0)
	bar.value = maxf(float(u.get("hp", 0)), 0.0)
	bar.custom_minimum_size = Vector2(100, 12)
	bar.show_percentage = false
	if _font:
		bar.add_theme_font_override("font", _font)
	v.add_child(bar)

	v.add_child(_label("HP %d/%d 盾%d" % [
		int(u.get("hp", 0)), int(u.get("max_hp", 1)), int(u.get("shield", 0))], 11))
	v.add_child(_label("攻%d 防%d 速%d" % [
		int(u.get("atk", 0)), int(u.get("def", 0)), int(u.get("spd", 0))], 11))

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


## 单位立绘节点。有立绘用立绘；没有就用属性色占位块，
## 保证美术还没铺满时界面不会塌（20 只不可能一次做完）。
## 取立绘贴图；没有则返回 null（调用方需自行降级为占位块）
func _portrait_texture(card_id: String) -> Texture2D:
	var path := "res://assets/portraits/%s.png" % card_id
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _portrait_node(card_id: String, element: String, alive: bool) -> Control:
	var tex := _portrait_texture(card_id)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(80, 80)
		if not alive:
			tr.modulate = Color(0.45, 0.45, 0.5, 0.6)  # 倒下：变灰半透明
		return tr

	# 占位块：属性色 + 幻兽名首字
	var ph := PanelContainer.new()
	ph.custom_minimum_size = Vector2(80, 80)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ELEMENT_COLOR.get(element, Color(0.35, 0.35, 0.4))
	sb.set_corner_radius_all(8)
	ph.add_theme_stylebox_override("panel", sb)
	var card: Dictionary = db.get("cards", {}).get(card_id, {})
	var nm := String(card.get("name", "?"))
	var initial := nm.substr(0, 1) if nm.length() > 0 else "?"
	var lb := _label(initial, 28)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.add_child(lb)
	if not alive:
		ph.modulate = Color(0.45, 0.45, 0.5, 0.6)
	return ph


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
		btn.custom_minimum_size = Vector2(104, 112)
		btn.text = "%s\n费用 %d" % [String(card.get("name", cid)), cost]
		# 手牌缩略图：秘术卡没有立绘，用属性色块占位
		var tex := _portrait_texture(cid)
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
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
	# 打击动效：先拍快照，执行后对比 HP/护盾/存活，谁变了谁闪
	var before := _hp_snapshot()
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
	# card 的 index 是手牌下标不是单位下标，攻击冲拳只给单位行动用
	_play_action_fx(idx if kind != "card" else -1, before)


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
	var before := _hp_snapshot()
	tm.advance_turn()
	_refresh()
	# 敌方整回合的行动一次结算，被影响的单位统一闪受击
	for i in state.units.size():
		if _hp_changed(i, before):
			_fx_hit(i)


# ── 打击动效（纯 Tween，不需要额外美术）────────────
## 设计说明：单位卡片在 HBoxContainer 里，position 会被容器接管，
## 但 scale / rotation / modulate 容器不管 —— 动效只用这三个属性。

func _hp_snapshot() -> Dictionary:
	var snap := {}
	for i in state.units.size():
		snap[i] = [int(state.units[i].get("hp", 0)),
			int(state.units[i].get("shield", 0)),
			bool(state.units[i].get("alive", true))]
	return snap


func _hp_changed(idx: int, before: Dictionary) -> bool:
	var b: Array = before.get(idx, [0, 0, true])
	var u: Dictionary = state.units[idx]
	return b[0] != int(u.get("hp", 0)) or b[1] != int(u.get("shield", 0)) \
		or b[2] != bool(u.get("alive", true))


## 行动动效：攻击方冲拳，受击方闪白抖动。actor_idx < 0 表示秘术卡（无攻击方）
func _play_action_fx(actor_idx: int, before: Dictionary) -> void:
	if actor_idx >= 0 and actor_idx < state.units.size():
		_fx_punch(actor_idx)
	for i in state.units.size():
		if i != actor_idx and _hp_changed(i, before):
			_fx_hit(i)


func _widget_of(idx: int) -> Control:
	return _widget_by_idx.get(idx) as Control


## 攻击方：向对方阵营方向顶一下再弹回
func _fx_punch(idx: int) -> void:
	var w := _widget_of(idx)
	if w == null:
		return
	var to_enemy := int(state.units[idx].get("side", 0)) == BattleState.Side.ALLY
	var dir := Vector2(0, -12) if to_enemy else Vector2(0, 12)
	# 绑定在控件上的 Tween：控件被 _refresh 重建销毁时动画自动终止，不报警告
	var tw := w.create_tween()
	tw.tween_property(w, "scale", Vector2(1.08, 1.08), 0.05)
	tw.parallel().tween_property(w, "position", w.position + dir, 0.05)
	tw.tween_property(w, "scale", Vector2.ONE, 0.08)
	tw.parallel().tween_property(w, "position", w.position, 0.08)


## 受击方：闪白 + 左右抖动；倒下则灰化下沉
func _fx_hit(idx: int) -> void:
	var w := _widget_of(idx)
	if w == null:
		return
	var tw := w.create_tween()
	if not bool(state.units[idx].get("alive", true)):
		w.modulate = Color(0.45, 0.45, 0.5, 0.6)
		tw.tween_property(w, "rotation_degrees", 4.0, 0.06)
		tw.tween_property(w, "rotation_degrees", 0.0, 0.06)
		return
	w.modulate = Color(6, 6, 6, 1)
	tw.tween_property(w, "modulate", Color.WHITE, 0.18)
	var base_x := w.position.x
	for off in [7.0, -6.0, 3.0, 0.0]:
		tw.tween_property(w, "position:x", base_x + off, 0.04)


# ── 小工具 ────────────────────────────────────────

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	return l
