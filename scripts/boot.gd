## 启动路由 —— 决定进入「可玩界面」还是「控制台演示」
##
## - 正常启动 / 编辑器 F5  → 战斗 UI（可玩）
## - 带 --headless 或 --console → 控制台演示（跑完即退出，便于 CI 与批量验证）

extends Node

const CONSOLE_SCENE := "res://scenes/main.tscn"
const BATTLE_SCENE := "res://scenes/battle/BattleScene.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_args()
	var user_args := OS.get_cmdline_user_args()
	if args.has("--headless") or args.has("--console") or user_args.has("--console"):
		get_tree().change_scene_to_file(CONSOLE_SCENE)
	else:
		get_tree().change_scene_to_file(BATTLE_SCENE)
