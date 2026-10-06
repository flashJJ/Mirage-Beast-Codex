## 卡组构筑 UI 冒烟测试（F7）
##
## 运行：
##   godot --headless --script res://tests/test_deck.gd
##
## 覆盖：场景实例化 / 收藏展示 / 默认牌库合法 / 清空后禁止开战
##       / 随机填充 / +− 调整 / 同名上限 / 首发阵容推导 / 写入 Session
##
## 注意：add_child 之后 _ready 要到下一帧才触发，断言放在 _process 第 2 帧。

extends SceneTree

const C = preload("res://scripts/utils/constants.gd")
const Session = preload("res://scripts/session.gd")

var _passed := 0
var _failed := 0
var _ui: Control
var _frame := 0


func _initialize() -> void:
	print("=== 卡组构筑 UI 冒烟测试 ===\n")
	var packed := load("res://scenes/deck/DeckScene.tscn")
	if packed == null:
		_fail("DeckScene.tscn 加载失败")
		quit(1)
		return
	_ui = packed.instantiate()
	root.add_child(_ui)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if _frame > 2:
		return true
	_run()
	return true


func _run() -> void:
	_check("UI 实例化成功", _ui != null)
	if _ui == null or _ui.get("db") == null:
		_fail("db 未加载（_ready 未执行？）")
		_finish()
		return

	var cards: Dictionary = _ui.db.get("cards", {})
	_check("收藏已加载卡牌", cards.size() > 0)
	_check("卡片控件数量与收藏一致",
		(_ui._grid as GridContainer).get_child_count() == cards.size(),
		"%d vs %d" % [(_ui._grid as GridContainer).get_child_count(), cards.size()])

	# ── 默认牌库应合法 ──────────────────────────────
	_check("默认已选 %d 张" % C.LIBRARY_SIZE, (_ui._library_array() as Array).size() == C.LIBRARY_SIZE)
	_check("默认牌库合法，可开战", not (_ui._start_btn as Button).disabled)

	# ── 清空后必须禁止开战 ──────────────────────────
	_ui._on_clear()
	_check("清空后张数为 0", (_ui._library_array() as Array).is_empty())
	_check("清空后禁止开战", (_ui._start_btn as Button).disabled)
	_check("清空后显示错误原因", String(_ui._err.text).length() > 0)

	# ── 随机填充 ────────────────────────────────────
	_ui._on_random_fill()
	_check("随机填充后为 %d 张" % C.LIBRARY_SIZE, (_ui._library_array() as Array).size() == C.LIBRARY_SIZE)
	_check("随机填充后合法", not (_ui._start_btn as Button).disabled)

	# ── +/− 与同名上限 ──────────────────────────────
	_ui._on_clear()
	var cid := String((_ui._order as Array)[0])
	_ui._adjust(cid, 1)
	_check("＋ 生效", int(_ui._counts.get(cid, -1)) == 1)
	_ui._adjust(cid, 1)
	_check("＋ 可加到 2", int(_ui._counts.get(cid, -1)) == 2)
	_ui._adjust(cid, 1)
	_check("同名上限为 2，再加无效", int(_ui._counts.get(cid, -1)) == 2)
	_ui._adjust(cid, -1)
	_check("− 生效", int(_ui._counts.get(cid, -1)) == 1)
	_ui._adjust(cid, -5)
	_check("− 不会低于 0", int(_ui._counts.get(cid, -1)) == 0)

	# ── 恢复默认 + 首发阵容推导 ──────────────────────
	_ui._on_default()
	var lib: Array = _ui._library_array()
	_check("恢复默认后为 %d 张" % C.LIBRARY_SIZE, lib.size() == C.LIBRARY_SIZE)
	var team := Session.team_from_library(lib, Session.ALLY_LEVEL)
	_check("首发阵容 3 只", team.size() == 3, str(team.size()))
	var ids := {}
	var ok := true
	for e in team:
		var id := String((e as Dictionary).get("card_id", ""))
		if ids.has(id):
			ok = false
		ids[id] = true
		var cd: Dictionary = cards.get(id, {})
		if String(cd.get("type", "")) != "beast":
			ok = false
	_check("首发阵容为 3 只互不相同的幻兽", ok)

	# ── 写入 Session ────────────────────────────────
	Session.set_library(lib, Session.ALLY_LEVEL)
	_check("Session.library 已写入", (Session.library as Array).size() == C.LIBRARY_SIZE)
	_check("Session.ally_team 已推导", (Session.ally_team as Array).size() == 3)

	# ── balance.gd 读取的正是这份配置 ────────────────
	Session.ensure()
	_check("Session.ensure() 不覆盖已设牌库", (Session.library as Array).size() == C.LIBRARY_SIZE)

	_finish()


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
