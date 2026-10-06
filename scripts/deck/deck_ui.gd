## 卡组构筑界面（F7）
##
## 规则（与 data/schema_check.gd 的 validate_deck 完全一致，不另立一套）：
##  - 牌库恰好 16 张（C.LIBRARY_SIZE）
##  - 同名卡不超过 2 张
##  - 首发阵容 = 牌库中前 3 张互不相同的幻兽卡（见 Session.team_from_library）
##
## 交互：点「+ / −」调整张数 → 「开始战斗」写入 Session 并切换场景

extends Control

const C = preload("res://scripts/utils/constants.gd")
const DataLoader = preload("res://scripts/data/data_loader.gd")
const SchemaCheck = preload("res://scripts/data/schema_check.gd")
const Session = preload("res://scripts/session.gd")

const BATTLE_SCENE := "res://scenes/battle/BattleScene.tscn"

const MAX_COPIES := 2

var _font: Font
var db: Dictionary
var _counts: Dictionary = {}     # card_id -> 已选张数
var _order: Array = []           # 收藏展示顺序（card_id）
var _grid: GridContainer
var _info: Label
var _err: Label
var _start_btn: Button


func _ready() -> void:
	_font = SystemFont.new()
	db = DataLoader.load_all()
	Session.ensure()
	_load_counts_from_session()
	_build_ui()
	_refresh()


func _load_counts_from_session() -> void:
	_counts = {}
	for cid in Session.library:
		var id := String(cid)
		_counts[id] = int(_counts.get(id, 0)) + 1
	var cards: Dictionary = db.get("cards", {})
	_order = []
	for id in cards:
		_order.append(id)
	_order.sort()


# ── 界面 ──────────────────────────────────────────

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := _label("幻兽绘卷 · 卡组构筑", 22)
	root.add_child(title)

	_info = _label("", 16)
	root.add_child(_info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	for cid in _order:
		_grid.add_child(_card_widget(String(cid)))

	_err = _label("", 13)
	root.add_child(_err)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	_start_btn = Button.new()
	_start_btn.text = "开始战斗"
	_start_btn.custom_minimum_size = Vector2(130, 38)
	_start_btn.pressed.connect(_on_start)
	bar.add_child(_start_btn)

	var rnd := Button.new()
	rnd.text = "随机填充"
	rnd.pressed.connect(_on_random_fill)
	bar.add_child(rnd)

	var clr := Button.new()
	clr.text = "清空"
	clr.pressed.connect(_on_clear)
	bar.add_child(clr)

	var back := Button.new()
	back.text = "恢复默认"
	back.pressed.connect(_on_default)
	bar.add_child(back)


func _card_widget(cid: String) -> Control:
	var card: Dictionary = db.get("cards", {}).get(cid, {})
	var p := PanelContainer.new()
	p.set_meta("card_id", cid)
	p.custom_minimum_size = Vector2(168, 132)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.22)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)

	v.add_child(_label(String(card.get("name", cid)), 15))
	var kind := "幻兽" if String(card.get("type", "beast")) == "beast" else "秘术"
	v.add_child(_label("%s · %s · 费用 %d" % [kind, String(card.get("element", "-")), int(card.get("cost", 0))], 12))

	var b: Dictionary = card.get("base", {})
	v.add_child(_label("ATK %d / HP %d" % [int(b.get("atk", 0)), int(b.get("hp", 0))], 12))

	var n := _label("× %d" % int(_counts.get(cid, 0)), 16)
	n.name = "count"
	v.add_child(n)

	var row := HBoxContainer.new()
	v.add_child(row)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(40, 28)
	minus.pressed.connect(func(): _adjust(cid, -1))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = "＋"
	plus.custom_minimum_size = Vector2(40, 28)
	plus.pressed.connect(func(): _adjust(cid, 1))
	row.add_child(plus)

	return p


# ── 操作 ──────────────────────────────────────────

func _adjust(cid: String, delta: int) -> void:
	var cur := int(_counts.get(cid, 0))
	var next := clampi(cur + delta, 0, MAX_COPIES)
	if next == cur:
		return
	_counts[cid] = next
	_refresh()


func _on_random_fill() -> void:
	_counts = {}
	for cid in _order:
		_counts[String(cid)] = 0
	var total := 0
	var guard := 0
	while total < C.LIBRARY_SIZE and guard < 500:
		guard += 1
		var cid := String(_order[randi() % _order.size()])
		if int(_counts.get(cid, 0)) >= MAX_COPIES:
			continue
		_counts[cid] = int(_counts.get(cid, 0)) + 1
		total += 1
	_refresh()


func _on_clear() -> void:
	for cid in _order:
		_counts[String(cid)] = 0
	_refresh()


func _on_default() -> void:
	_counts = {}
	for cid in Session.DEFAULT_LIBRARY:
		var id := String(cid)
		_counts[id] = int(_counts.get(id, 0)) + 1
	_refresh()


func _library_array() -> Array:
	var out: Array = []
	for cid in _order:
		var n := int(_counts.get(String(cid), 0))
		for _i in n:
			out.append(String(cid))
	return out


func _refresh() -> void:
	var lib := _library_array()
	_info.text = "已选 %d / %d 张　|　战绩 %d 胜 %d 负 %d 平" % [
		lib.size(), C.LIBRARY_SIZE, Session.wins, Session.losses, Session.draws]

	# 同步每张卡的计数显示
	for c in _grid.get_children():
		var cid := String(c.get_meta("card_id", "")) if c.has_meta("card_id") else ""
		if cid == "":
			continue
		var n = c.find_child("count", true, false)
		if n != null:
			(n as Label).text = "× %d" % int(_counts.get(cid, 0))

	var errors := SchemaCheck.validate_deck(db, lib)
	var team := Session.team_from_library(lib, Session.ALLY_LEVEL)
	if errors.is_empty() and team.size() < 3:
		errors.append("牌库中幻兽种类不足 3 种，无法组成首发阵容")

	if errors.is_empty():
		var names: Array = []
		var cards: Dictionary = db.get("cards", {})
		for e in team:
			names.append(String((cards.get(String((e as Dictionary)["card_id"]), {}) as Dictionary).get("name", "?")))
		_err.text = "合法　首发：%s" % " + ".join(names)
		_start_btn.disabled = false
	else:
		_err.text = "× " + "；".join(errors)
		_start_btn.disabled = true


func _on_start() -> void:
	var lib := _library_array()
	if not SchemaCheck.validate_deck(db, lib).is_empty():
		return
	if Session.team_from_library(lib, Session.ALLY_LEVEL).size() < 3:
		return
	Session.set_library(lib, Session.ALLY_LEVEL)
	get_tree().change_scene_to_file(BATTLE_SCENE)


# ── 小工具 ────────────────────────────────────────

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if _font:
		l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", size)
	return l
