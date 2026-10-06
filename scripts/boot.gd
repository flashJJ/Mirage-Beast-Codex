## 启动路由 —— 决定进入「编组界面」还是「控制台演示」
##
## - 正常启动 / 编辑器 F5      → 编组界面 → 战斗 UI（可玩流程）
## - 带 --headless / --console → 控制台演示（跑完即退出，便于 CI 与批量验证）
## - 带 --battle               → 直接进战斗（跳过编组，便于调试）

extends Node

const CONSOLE_SCENE := "res://scenes/main.tscn"
const DECK_SCENE := "res://scenes/deck/DeckScene.tscn"
const BATTLE_SCENE := "res://scenes/battle/BattleScene.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_args()
	var user_args := OS.get_cmdline_user_args()
	var target := DECK_SCENE
	if args.has("--headless") or args.has("--console") or user_args.has("--console"):
		target = CONSOLE_SCENE
	elif user_args.has("--battle"):
		target = BATTLE_SCENE
	# 必须延迟一帧：_ready 期间场景树仍在装配，直接 change_scene 会报
	# "Parent node is busy adding/removing children"
	get_tree().change_scene_to_file.call_deferred(target)
