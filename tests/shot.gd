## 界面截图工具 —— 生成 PNG 供评审 / README / itch.io 页面使用
##
## 运行（**必须非 headless**，headless 下不渲染，截出来是空的）：
##   godot --path . --script res://tests/shot.gd -- --scene res://scenes/deck/DeckScene.tscn --out res://docs/shots/deck.png
##   godot --path . --script res://tests/shot.gd -- --scene res://scenes/battle/BattleScene.tscn --out res://docs/shots/battle.png --act
##
## --act：截战斗界面时先自动打几回合，让画面上有战斗日志与血量变化（而不是开局空场）

extends SceneTree

const BattleState = preload("res://scripts/battle/battle_state.gd")

var _scene := "res://scenes/deck/DeckScene.tscn"
var _out := "res://docs/shots/shot.png"
var _act := false
var _frame := 0
var _ui: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			_scene = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
		elif args[i] == "--act":
			_act = true

	var packed := load(_scene)
	if packed == null:
		push_error("[shot] 场景加载失败：%s" % _scene)
		quit(1)
		return
	_ui = packed.instantiate()
	root.add_child(_ui)


func _process(_delta: float) -> bool:
	_frame += 1
	# 第 3 帧：_ready 已跑完，控件已布局
	if _frame == 3 and _act:
		_drive_battle()
	if _frame < 6:
		return false

	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out)
	var err := img.save_png(path)
	if err != OK:
		push_error("[shot] 保存失败：%s（err=%d）" % [path, err])
		quit(1)
		return true
	print("[shot] 已保存 %s（%dx%d）" % [path, img.get_width(), img.get_height()])
	quit()
	return true


## 自动推进几个回合，让战斗截图里有内容
func _drive_battle() -> void:
	if _ui == null or _ui.get("state") == null:
		return
	var state: BattleState = _ui.state
	if state == null:
		return
	for _t in 3:
		if state.is_over():
			break
		if not (state.hands[0] as Array).is_empty():
			_ui._on_play_card(0)
			if not (_ui._pending as Dictionary).is_empty():
				_ui._confirm_target(_ui._suggested_target())
		for i in state.living_indices(BattleState.Side.ALLY):
			_ui._on_unit_action(int(i))
			if not (_ui._pending as Dictionary).is_empty():
				_ui._confirm_target(_ui._suggested_target())
		_ui._on_end_turn()
