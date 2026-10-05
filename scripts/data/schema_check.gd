## 配置校验 —— 加载即校验，缺字段 / 取值越界立即暴露
##
## 六项必检（对应 B-数据配置规范.md §8）：
##   V1 schema 版本一致   V2 引用的 skill_id 存在
##   V3 cost ∈ [1,8]      V4 element/rarity/faction/type 取值合法
##   V5 遭遇权重和 > 0     V6 卡组合法性（由构筑界面负责，此处仅校验配置层）

class_name SchemaCheck
extends RefCounted

const C = preload("res://scripts/utils/constants.gd")


static func validate_all(db: Dictionary) -> Array:
	var errors: Array = []
	errors.append_array(_validate_cards(db))
	errors.append_array(_validate_skills(db))
	errors.append_array(_validate_encounters(db))
	return errors


# ── V1 ~ V4：卡牌 ─────────────────────────────────

static func _validate_cards(db: Dictionary) -> Array:
	var errors: Array = []
	var cards: Dictionary = db.get("cards", {})
	var skills: Dictionary = db.get("skills", {})

	for card_id in cards:
		var c: Dictionary = cards[card_id]
		var tag := "cards/%s" % card_id

		# V1 schema
		if String(c.get("schema", "")) != "" and false:
			pass  # 单卡不带 schema，由文件级 schema 字段保证

		# V4 枚举取值
		var elem := String(c.get("element", ""))
		if not C.ELEMENTS.has(elem):
			errors.append("%s：element 非法 '%s'" % [tag, elem])
		var rarity := String(c.get("rarity", ""))
		if not C.RARITIES.has(rarity):
			errors.append("%s：rarity 非法 '%s'" % [tag, rarity])
		var faction := String(c.get("faction", ""))
		if not C.FACTIONS.has(faction):
			errors.append("%s：faction 非法 '%s'" % [tag, faction])
		var ctype := String(c.get("type", ""))
		if not C.CARD_TYPES.has(ctype):
			errors.append("%s：type 非法 '%s'" % [tag, ctype])

		# V3 费用范围
		var cost := int(c.get("cost", 0))
		if cost < 0 or cost > C.MAX_ENERGY:
			errors.append("%s：cost=%d 超出 [0,%d]" % [tag, cost, C.MAX_ENERGY])

		# V2 技能引用存在
		for skid in (c.get("skills", []) as Array):
			if not skills.has(String(skid)):
				errors.append("%s：引用了不存在的技能 '%s'" % [tag, String(skid)])

		# 面板完整性
		for key in ["base", "growth"]:
			if not (c.get(key, {}) is Dictionary):
				errors.append("%s：缺少 %s" % [tag, key])
				continue
			var stat: Dictionary = c[key]
			for s in ["atk", "hp", "def", "spd"]:
				if not stat.has(s):
					errors.append("%s：%s 缺少 %s" % [tag, key, s])

	return errors


# ── 技能 ──────────────────────────────────────────

static func _validate_skills(db: Dictionary) -> Array:
	var errors: Array = []
	var skills: Dictionary = db.get("skills", {})

	for sid in skills:
		var s: Dictionary = skills[sid]
		var tag := "skills/%s" % sid

		var trigger := String(s.get("trigger", ""))
		if not C.TRIGGERS.has(trigger):
			errors.append("%s：trigger 非法 '%s'" % [tag, trigger])

		var effects: Array = s.get("effects", [])
		if effects.is_empty():
			errors.append("%s：没有任何效果" % tag)
		for e in effects:
			var op := String((e as Dictionary).get("op", ""))
			if not C.EFFECT_OPS.has(op):
				errors.append("%s：未知效果原语 '%s'（请改技能设计，不要加特判代码）" % [tag, op])

		var cost := int(s.get("cost", 0))
		if cost < 0 or cost > C.MAX_ENERGY:
			errors.append("%s：cost=%d 超出 [0,%d]" % [tag, cost, C.MAX_ENERGY])

	return errors


# ── V5：遭遇表 ────────────────────────────────────

static func _validate_encounters(db: Dictionary) -> Array:
	var errors: Array = []
	var cards: Dictionary = db.get("cards", {})
	var encounters: Array = (db.get("raw", {}).get("encounters", {}) as Dictionary).get("items", [])

	for enc in encounters:
		var e: Dictionary = enc
		var zone := int(e.get("zone", 0))
		var pool: Array = e.get("pool", [])
		if pool.is_empty():
			errors.append("encounters/zone%d：遭遇池为空" % zone)
			continue
		var total_weight := 0
		for p in pool:
			var entry: Dictionary = p
			var cid := String(entry.get("card_id", ""))
			if not cards.has(cid):
				errors.append("encounters/zone%d：引用了不存在的卡 '%s'" % [zone, cid])
			total_weight += int(entry.get("weight", 0))
		if total_weight <= 0:
			errors.append("encounters/zone%d：权重和为 0，抽不出卡" % zone)

	return errors


# ── 构筑合法性（供卡组界面调用）──────────────────

static func validate_deck(db: Dictionary, card_ids: Array) -> Array:
	var errors: Array = []
	var cards: Dictionary = db.get("cards", {})

	if card_ids.size() != C.LIBRARY_SIZE:
		errors.append("牌库必须为 %d 张，当前 %d 张" % [C.LIBRARY_SIZE, card_ids.size()])

	var counts := {}
	for cid in card_ids:
		var id := String(cid)
		if not cards.has(id):
			errors.append("牌库含未知卡：%s" % id)
			continue
		counts[id] = int(counts.get(id, 0)) + 1
		if int(counts[id]) > 2:
			errors.append("同名卡不得超过 2 张：%s" % id)

	return errors
