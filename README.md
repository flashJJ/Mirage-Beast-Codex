# 幻兽绘卷 / Mirage Beast Codex

> 2D 俯视角幻兽收集 + 回合制卡牌对战 · PC 单机（Windows / Linux / macOS / Web）
> 引擎 **Godot 4.3 (Standard, GDScript)** · 无联网 · 无付费 · 作品集项目

---

## 当前状态：V0 · 战斗核心骨架

| 模块 | 状态 |
|---|---|
| 配置管线（JSON → 校验 → 索引） | ✅ 完成 |
| 战斗核心（状态机 / 伤害 / 效果系统 / AI） | ✅ 完成（无 UI，控制台验证） |
| 批量模拟（确定性 + 胜率） | ✅ 完成 |
| 战斗 UI | ⬜ M2 |
| 世界探索 / 契约 / 图鉴 | ⬜ M3 |
| 美术资产 | ⬜ M4 |
| AI 增强模块（本地大模型） | ⬜ M2.5（可选） |

---

## 快速开始

```bash
# 1) 用 Godot 4.3 打开本目录（导入项目）

# 2) 运行一次演示战斗（控制台输出完整战斗日志）
godot --headless --path . res://scenes/main.tscn
# 或直接按 F5 运行主场景

# 3) 批量模拟：验证确定性 + 看胜率
godot --headless --script res://tests/simulate.gd --runs 200

# 4) 看某一场的完整日志
godot --headless --script res://tests/simulate.gd --runs 1 --verbose
```

---

## 目录结构

```
data/       全部配置（唯一真相源，加卡不加代码）
scripts/
  utils/    全局常量
  battle/   战斗核心（纯逻辑，无 UI 依赖）
    ai/     出牌 AI（规则式，不用 LLM）
  data/     配置加载与 Schema 校验
scenes/     场景
tests/      headless 批量模拟
docs/       设计文档链接与决策记录
assets/     美术资产（当前为空，V0 阶段不需要）
```

---

## 设计原则（改代码前请读）

1. **数据与逻辑分离**：卡牌、技能、敌人、遭遇全部在 `data/*.json`，代码里不出现任何卡牌数值。
   - 判据：*换一张卡会不会变？* 会变 → JSON；不会变 → `constants.gd`。
2. **定点数**：所有小数用千分比整数（`1500` = 1.5），无浮点。保证批量模拟结果可复现。
3. **效果系统硬边界**：只支持 `constants.gd` 中 `EFFECT_OPS` 列出的 **10 个原语**。
   **禁止为某张卡写特判逻辑** —— 配不出来的技能应该改 JSON，而不是改代码。
4. **AI 不用 LLM 做出牌决策**：延迟、不确定性、破坏可复现性。规则 AI 在此任务上更优。
5. **不用 autoload**：改用 `const X = preload(...)`，因为 autoload 在 `godot --headless --script` 批量模拟模式下不可靠。

---

## 加一张新卡（示例）

只改 `data/cards.json` + `data/skills.json`，**不需要改任何代码**：

```json
{
  "id": "beast_009", "name": "霜羽鹰", "type": "beast", "rarity": "SR",
  "element": "water", "faction": "relic", "cost": 3,
  "base":   { "atk": 15, "hp": 32, "def": 5, "spd": 14 },
  "growth": { "atk": 14, "hp": 29, "def": 4, "spd": 8  },
  "tags": ["pierce"], "skills": ["sk_b009_s1"],
  "persona": { "traits": ["孤高"], "tone": "简短", "catchphrase": "跟上。" },
  "assets": { "sprite": "", "portrait": "" },
  "obtain": { "type": "encounter", "zone": 3, "rate": 800 }
}
```

改完运行 `godot --headless --script res://tests/simulate.gd --runs 50`，校验器会检查引用与取值。

---

## 相关文档

设计文档在上级工作区 `design/` 目录：

| 文档 | 内容 |
|---|---|
| `design/gdd/12-PC单机2D版-独立开发方案.md` | 主方案（规模、引擎、美术、路线图） |
| `design/gdd/13-AI增强模块设计.md` | 本地大模型可选增强层 |
| `design/dev/00-项目开发计划.md` | 里程碑、WBS、风险、验收标准 |
| `design/dev/A-环境与工具链准备.md` | 环境、目录、代码规范、Git |
| `design/dev/B-数据配置规范.md` | JSON Schema、定点数、存档结构 |
| `design/dev/C-美术规格书.md` | 色板、尺寸、工时预算、素材授权 |
| `design/dev/D-PoC技术验证清单.md` | 第 1~4 周的 8 项验证 |
| `design/dev/E-术语表与全局常量.md` | 术语、常量、公式、ID 规则 |

---

## 待办（下一步）

- [ ] **P1 Web 导出验证**（`design/dev/D` 最高优先，第 1 周必须完成）
- [ ] P7 试画 2 只幻兽并计时（校准美术产能）
- [ ] M1-7 补战斗核心单元测试
- [ ] M2 战斗 UI（手牌 / 3×2 站位 / 拖拽）

---

## 许可

代码：**待定**（建议 MIT）。
美术素材：外部素材一律使用 CC0 或明确商用授权，并在 `docs/CREDITS.md` 署名。
