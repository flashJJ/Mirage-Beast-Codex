## 全局规则常量
##
## 说明：卡牌 / 技能 / 敌人等「内容数值」一律放在 res://data/*.json，
##       这里只放「换一张卡也不会变」的规则常量。
##
## 用法：const C = preload("res://scripts/utils/constants.gd")
##      （不用 autoload，因为 autoload 在 `godot --headless --script` 批量模拟模式下不可靠）
##
## 定点数约定：所有小数用千分比整数表示（1500 = 1.500）

extends Node

# ── 对战规则 ──────────────────────────────────────
const MAX_ENERGY        := 8      # 费用上限
const ENERGY_PER_TURN   := 1      # 每回合恢复
const START_ENERGY      := 2      # 首回合初始费用

# ── 后手补偿（F45）──────────────────────────────
## 诊断发现：先手方优势高达 30~48 个百分点（镜像对局先手胜率 98.3%，
## 战斗 4.4 回合就结束），这是「等级悬崖」的真正根因，不是减伤模型。
## 用卡牌游戏通行的后手补偿把镜像胜率拉回 50% 附近：后手多抽 1 张、多 1 点费用。
## 详见 docs/BALANCE-ANALYSIS.md §8。V0 我方恒先手，故补偿给 ENEMY。
const SECOND_MOVER_EXTRA_DRAW   := 1
const SECOND_MOVER_EXTRA_ENERGY := 1
const HAND_SIZE_MAX     := 5      # 手牌上限
const START_HAND        := 3      # 起手牌数
const LIBRARY_SIZE      := 16     # 牌库张数
const TEAM_SIZE         := 3      # 上阵数量
const SLOT_COUNT        := 6      # 站位槽位总数（前排 0-2 / 后排 3-5）
const MAX_TURNS         := 15     # 回合上限（超时判定）
const FATIGUE_DAMAGE    := 2      # 牌库耗尽后每回合抽牌受到的伤害
const MAX_ACTIONS_TURN  := 8      # 每回合最大行动数（防死循环）
const BASIC_ATTACK_POWER := 1000  # 普攻倍率 100% 攻击力（无主动技能单位的兜底输出）

# ── 站位修正（千分比）────────────────────────────
const BACK_ROW_DAMAGE_TAKEN := 750   # 后排受到伤害 x 0.75
const BACK_ROW_DAMAGE_DEALT := 1100  # 后排造成伤害 x 1.10

# ── 伤害公式（千分比）────────────────────────────
## 乘性减伤（F43）：DMG = base × 1000 / (1000 + DEF × DEF_FACTOR / 1000)
##
## 原来是固定减算 `base − DEF×0.45`（DEF_FACTOR=450），导致**等级悬崖**：
## 攻防接近时净伤害对属性极端敏感，Lv7→Lv8（属性只涨 8%）胜率掉 49 个百分点
## （见 docs/BALANCE-ANALYSIS.md §3 P1）。乘性模型无阈值、无负值、收益递减，
## 属性曲线变平滑。5800 是让 Lv8 典型防御（DEF≈32）的减伤率 ≈16%，
## 与原模型在基线点基本等价，便于对照。
const DEF_FACTOR        := 5800  # 乘性减伤系数
const CRIT_MULT         := 1500  # 暴击倍率 1.50
const CRIT_BASE_RATE    := 50    # 基础暴击率 5.0%（千分比）
const DMG_FLOAT_MIN     := 950   # 随机浮动下限 0.95
const DMG_FLOAT_MAX     := 1050  # 随机浮动上限 1.05
const FIXED_SCALE       := 1000  # 定点数缩放因子

# ── 属性克制（千分比；详细矩阵在 data/tags.json）──
const ELEMENT_STRONG    := 1500  # 四元环克制 1.50
const ELEMENT_LD        := 1450  # 光暗互克 1.45
const ELEMENT_NEUTRAL   := 1000  # 中立 1.00

# ── 成长 ──────────────────────────────────────────
const MAX_LEVEL         := 50
const LEVEL_COEF_PER_LV := 85    # CP 等级系数斜率 0.085/级（千分比）
const BREAK_LEVELS      := [20, 40]
const SKILL_MAX_LEVEL   := 4

# ── CP 公式权重（千分比）─────────────────────────
const CP_W_ATK := 1200
const CP_W_HP  := 1000
const CP_W_DEF := 800
const CP_W_SPD := 8000

# ── 召唤（无付费）───────────────────────────────
const SUMMON_COST_SINGLE := 80
const SUMMON_COST_TEN    := 700
const SUMMON_PITY_SSR    := 30
const SUMMON_PITY_CARRY  := true

# ── 世界 ──────────────────────────────────────────
const TILE_SIZE          := 32
const ZONE_TILES         := 100
const PLAYER_SPEED       := 160     # px/s（= 5 tile/s）
const ENCOUNTER_RATE     := 45      # 每 1000 步
const ENCOUNTER_COOLDOWN := 120     # 步

# ── 试炼塔 ────────────────────────────────────────
const TOWER_FLOORS       := 30
const TOWER_BOSS_EVERY   := 5

# ── 其他 ──────────────────────────────────────────
const SAVE_SLOTS         := 1
const AUTO_SAVE_INTERVAL := 60

# ── 枚举取值（供 schema 校验使用）────────────────
const ELEMENTS := ["fire", "water", "wood", "light", "dark"]
const RARITIES := ["R", "SR", "SSR"]
const FACTIONS := ["plain", "crag", "relic", "none"]
const CARD_TYPES := ["beast", "spell"]
const EFFECT_OPS := ["DAMAGE", "HEAL", "SHIELD", "BUFF", "DEBUFF",
					 "DRAW", "ENERGY", "PURIFY", "TAUNT", "SUMMON"]
const TRIGGERS := ["active", "on_play", "on_death", "on_damaged", "turn_start", "turn_end"]
