## 跨场景会话状态 —— 卡组 / 阵容 / 战绩
##
## 为什么不用 autoload：autoload 在 `godot --headless --script` 批量模拟模式下不可靠，
## 而战斗核心必须能被批量模拟直接驱动。改用 static 变量，跨场景切换同样有效。
##
## 数据流：编组界面 → Session.set_library() → 战斗界面 Session.ensure() 读取

class_name Session
extends RefCounted

const DataLoader = preload("res://scripts/data/data_loader.gd")

const ALLY_LEVEL := 8

## 默认牌库（16 张，同名不超过 2 张）—— 未经平衡工具挑选，仅作兜底
const DEFAULT_LIBRARY := [
	"beast_001", "beast_002", "beast_003", "beast_004",
	"beast_005", "beast_006", "beast_007", "spell_001",
	"spell_002", "beast_001", "beast_002", "beast_003",
	"beast_004", "beast_005", "beast_007", "spell_001",
]

## 默认对手阵容由 tests/balance.gd 实测选定（候选 B，AI 对 AI 胜率 84.3%）
## 改动这里必须重跑：godot --headless --script res://tests/balance.gd
const DEFAULT_ENEMY := [
	{"card_id": "beast_005", "level": 8},
	{"card_id": "beast_007", "level": 8},
	{"card_id": "beast_001", "level": 7},
]

static var library: Array = []
static var ally_team: Array = []
static var enemy_team: Array = []
static var wins: int = 0
static var losses: int = 0
static var draws: int = 0


## 保证三个字段都有值（首次进入或被批量模拟直接驱动时调用）
static func ensure() -> void:
	if library.is_empty():
		library = DEFAULT_LIBRARY.duplicate()
	if ally_team.is_empty():
		ally_team = team_from_library(library, ALLY_LEVEL)
	if enemy_team.is_empty():
		enemy_team = DEFAULT_ENEMY.duplicate(true)


## 设置牌库，并据此推导首发阵容
static func set_library(lib: Array, level: int = ALLY_LEVEL) -> void:
	library = lib.duplicate()
	ally_team = team_from_library(library, level)


## 首发阵容：取牌库中前 3 张互不相同的幻兽卡
## 规则明确写在注释里 —— 玩家点「开始战斗」时看到的队伍必须可预期
static func team_from_library(lib: Array, level: int = ALLY_LEVEL) -> Array:
	var db := DataLoader.load_all()
	var cards: Dictionary = db.get("cards", {})
	var out: Array = []
	var seen := {}
	for cid in lib:
		if out.size() >= 3:
			break
		var id := String(cid)
		if seen.has(id):
			continue
		var card: Dictionary = cards.get(id, {})
		if String(card.get("type", "beast")) != "beast":
			continue
		seen[id] = true
		out.append({"card_id": id, "level": level})
	return out


static func record(outcome: String) -> void:
	if outcome == "ally_win":
		wins += 1
	elif outcome == "enemy_win":
		losses += 1
	else:
		draws += 1


static func reset_record() -> void:
	wins = 0
	losses = 0
	draws = 0
