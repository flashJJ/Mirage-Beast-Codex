## 种子随机数 —— 保证战斗可复现
##
## 用途：
##  1. 批量模拟（tests/simulate.gd）跑 1000 场做数值平衡，结果必须可复现
##  2. 回放与复盘：同一 seed + 同一操作序列 = 同一结果
##
## 注意：禁止在战斗逻辑中使用 RandomNumberGenerator.global() 或 randi()

class_name BattleRNG
extends RefCounted

var _rng: RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


## 返回 [min_v, max_v] 闭区间内的整数
func range_int(min_v: int, max_v: int) -> int:
	return _rng.randi_range(min_v, max_v)


## 按权重数组抽取索引。weights 为整数数组（千分比不必归一化）
func weighted_index(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return -1
	var roll := range_int(0, total - 1)
	var acc := 0
	for i in weights.size():
		acc += int(weights[i])
		if roll < acc:
			return i
	return weights.size() - 1
