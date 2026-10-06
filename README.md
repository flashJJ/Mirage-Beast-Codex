# 幻兽绘卷 / Mirage Beast Codex

> 2D 俯视角幻兽收集 + 回合制卡牌对战 · PC 单机（Windows / Linux / macOS / Web）
> 引擎 **Godot 4.3 (Standard, GDScript)** · 无联网 · 无付费 · 作品集项目

---

## 当前状态：V0 · 可玩（编组 → 战斗 → 结算）

| 模块 | 状态 |
|---|---|
| 配置管线（JSON → 校验 → 索引） | ✅ 完成 |
| 战斗核心（状态机 / 伤害 / 效果系统 / AI） | ✅ 完成 |
| **卡组构筑界面**（16 张 / 同名 ≤2 / 首发阵容推导） | ✅ 完成 |
| **战斗 UI**（手牌 / 站位 / 血条 / 手动选目标 / 战报 / 战绩） | ✅ 完成 |
| 批量模拟 + 平衡度量 | ✅ 完成 |
| 世界探索 / 契约 / 图鉴 | ⬜ M3 |
| 美术资产 | ⬜ M4 |
| AI 增强模块（本地大模型） | ⬜ M2.5（可选） |

**游戏流程**：启动 → 编组界面（选 16 张）→ 战斗（点卡 → 选目标 → 点单位；点单位用技能/普攻；结束回合）→ 结算 → 再来一局 / 返回编组。

---

## 快速开始

```bash
# 1) 用 Godot 4.3 打开本目录（导入项目）；直接按 F5 运行即可进入编组界面

# 2) 全部测试（规则 / 战斗 UI / 编组 UI）
godot --headless --script res://tests/test_battle.gd   # 44 项
godot --headless --script res://tests/test_ui.gd       # 38 项
godot --headless --script res://tests/test_deck.gd     # 21 项

# 3) 控制台演示战斗（跑完即退出，便于 CI）
godot --headless --path . -- --console

# 4) 批量模拟：验证确定性 + 看遭遇战胜率
godot --headless --script res://tests/simulate.gd --runs 200

# 5) 阵容平衡度量：改了阵容/数值后必跑
godot --headless --script res://tests/balance.gd --runs 400
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
  deck/     卡组构筑界面
  session.gd  跨场景会话状态（牌库 / 阵容 / 战绩，不用 autoload）
scenes/
  boot.tscn     启动路由
  deck/         卡组构筑
  battle/       战斗
tests/      headless 模拟与三套冒烟/单元测试
docs/       决策记录、待办清单、平衡分析
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

- [ ] **F1 Web 导出验证**（最高优先，但需先在 Godot 编辑器内下载导出模板）
- [ ] F6 AI 三档难度差异化（嘲讽约束已补，阻塞解除）
- [ ] F8 存档系统
- [ ] F43 伤害模型改乘性减伤（见 `docs/BALANCE-ANALYSIS.md` P1，越早越便宜）
- [ ] P7 试画 2 只幻兽并计时（校准美术产能）

详见 `docs/BACKLOG.md`；平衡现状见 `docs/BALANCE-ANALYSIS.md`。

---

## 许可

代码：**待定**（建议 MIT）。
美术素材：外部素材一律使用 CC0 或明确商用授权，并在 `docs/CREDITS.md` 署名。
