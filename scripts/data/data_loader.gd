## 配置加载器 —— res://data/*.json 是唯一真相源
##
## 用法（静态调用，无需 autoload，便于 headless 批量模拟）：
##   var db := DataLoader.load_all()
##   db["cards"]["beast_001"]

class_name DataLoader
extends RefCounted

const DATA_DIR := "res://data/"

const FILES := {
	"cards": "cards.json",
	"skills": "skills.json",
	"tags": "tags.json",
	"progression": "progression.json",
	"enemies": "enemies.json",
	"encounters": "encounters.json",
}


## 读取单个 JSON 文件
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[DataLoader] 文件不存在：%s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[DataLoader] 无法打开：%s" % path)
		return {}
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("[DataLoader] JSON 解析失败：%s" % path)
		return {}
	return parsed


## 加载全部配置，返回以 id 为键的索引字典
## 返回结构：{ "cards": {id: {...}}, "skills": {...}, "tags": {...},
##             "element_chart": {...}, "raw": {表名: 原始 Dictionary} }
static func load_all() -> Dictionary:
	var out := {
		"cards": {}, "skills": {}, "tags": {},
		"element_chart": {}, "raw": {},
	}

	for key in FILES:
		var path: String = DATA_DIR + String(FILES[key])
		var raw := load_json(path)
		if raw.is_empty():
			continue
		out["raw"][key] = raw

		if raw.has("items"):
			var index := {}
			for item in (raw["items"] as Array):
				var d: Dictionary = item
				var id := String(d.get("id", ""))
				if id.is_empty():
					push_error("[DataLoader] %s 中存在缺少 id 的条目" % path)
					continue
				index[id] = d
			out[key] = index

	# 属性克制矩阵单独提取，供战斗使用
	if out["raw"].has("tags"):
		var tags_raw: Dictionary = out["raw"]["tags"]
		if tags_raw.has("element_chart"):
			out["element_chart"] = tags_raw["element_chart"]

	return out


## 加载并校验；返回 {"db": ..., "errors": [...]} 。errors 非空时应中止。
static func load_all_checked() -> Dictionary:
	var db := load_all()
	var errors := SchemaCheck.validate_all(db)
	for e in errors:
		push_error("[SchemaCheck] %s" % e)
	return {"db": db, "errors": errors}


## 便捷：按 id 取卡
static func get_card(db: Dictionary, card_id: String) -> Dictionary:
	return (db.get("cards", {}) as Dictionary).get(card_id, {})


## 便捷：按 id 取技能
static func get_skill(db: Dictionary, skill_id: String) -> Dictionary:
	return (db.get("skills", {}) as Dictionary).get(skill_id, {})
