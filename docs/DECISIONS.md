# 决策记录（DECISIONS）

> 每个里程碑复盘时更新。格式：日期 / 决策 / 理由 / 影响。

---

## 2026-10-06 · 项目初始化

| # | 决策 | 理由 | 影响 |
|---|---|---|---|
| D1 | 引擎选 **Godot 4.3 Standard + GDScript** | 本作是 2D，2D 是 Godot 最强、Unity 最弱领域；GDScript ≈ Python，学习成本近零；支持 Web 导出 | 原案 Unity 选型作废 |
| D2 | **不使用 autoload**，改用 `preload` 常量 | autoload 在 `godot --headless --script` 批量模拟模式下不可靠 | 所有模块用 `const X = preload(...)` |
| D3 | 常量与内容数值分离 | 判据："换一张卡会不会变？" | 规则常量在 `constants.gd`，内容数值在 `data/*.json` |
| D4 | 效果系统限定 **10 个原语**，禁止特判 | 防止陷入"万能技能引擎"陷阱 | 配不出的技能改 JSON 设计，不改代码 |
| D5 | 出牌 AI 用规则式，**不用 LLM** | 延迟 / 不确定性 / 破坏可复现性 | `scripts/battle/ai/simple_ai.gd` |
| D6 | V0 不做任何美术、不做 UI | 先验证战斗逻辑与配置管线 | 主场景仅输出控制台日志 |
| D7 | 全部数值定点整数（千分比） | 保证 1000 场批量模拟结果可复现 | JSON 中禁止出现 `1.5` 这类浮点 |

---

## 2026-10-06 · Godot 4.3 实机验证结果

环境：Godot 4.3.stable.official.77dcf97d8（win64 console），项目导入 0 错误。

### 发现并修复的 5 个问题

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| B1 | 加载 encounters.json 报 3 次 "缺少 id" | 遭遇条目只有 `zone` 没有 `id`，而 loader 按 id 索引 | 补 `enc_z1_grass` / `enc_z2_crag` / `enc_z3_relic` |
| B2 | `simulate.gd` 崩溃 `Nonexistent 'String' constructor` | `String(int)` 在 GDScript 非法，应为 `str()` | 改用 `str()`；`%-14s` 左对齐语法 Godot 也不支持，改用 `rpad()` |
| B3 | 日志无法区分敌我同名幻兽 | 单位只记名字 | 新增 `BattleState.label()`，输出 `[我]xxx` / `[敌]xxx` |
| B4 | **on_play 不对初始阵容生效** → 潮汐龟护盾永远不触发 | 只有从手牌打出才触发 | 在 `TurnMachine.setup()` 中对全部初始单位触发一次 on_play |
| B5 | **只有辅助技能的幻兽 0 输出**（潮汐龟站桩挨打） | 无主动技能就没有任何行动 | 新增**普攻机制**（`BASIC_ATTACK_POWER=1000`，每单位每回合 1 次） |

### 平衡调优（改 JSON，未改代码）

| 改动 | 原因 |
|---|---|
| 熔岩獠牙反制 40% → **22%** | Lv10 时 atk 162，反弹 65/次，我方 4 次攻击即自杀 |
| 熔岩獠牙 atk 成长 16 → **13** | SR 卡成长过高 |
| 关卡 2 补第 3 个敌方单位 | 2 打 3 结构性劣势，胜率虚高 |
| 模拟改为「我方等级 = 敌方均值 + (难度-1)」 | 严格同级测的是越级挑战，不是平衡性 |

### 当前胜率基线（400 场/关）

| 关卡 | 难度 | 胜率 |
|---|---|---|
| 草原初战 | 1 | 99.3% |
| 裂谷巡逻 | 2 | 98.8% |
| 熔岩獠牙 | 3 | 75.5% |

判定：**CONCERNS** —— 前两关过于简单（R 卡队伍碾压同级的 R 卡敌人属预期，但 98%+ 说明关卡 2 缺少挑战）。
下一步应给关卡 2 引入属性克制压力（如换成克制我方木系的水/火系敌人），而不是继续堆数值。
确定性验证通过（seed=42 两次结果一致）。

---

## 2026-10-06 · 战斗 UI 实机验证 + 首份平衡量化

### 决策

| # | 决策 | 理由 | 影响 |
|---|---|---|---|
| D8 | UI **纯代码构建**，不手写 `.tscn` 节点树 | V0 无美术资产；手写 tscn 易出错且难 diff | `battle_ui.gd` 用 `SystemFont` + ColorRect/Label/Button 构建 |
| D9 | UI 只做「显示 + 转发输入」，规则仍在 `TurnMachine` | 保证 headless 模拟与 UI 走**同一套**回合逻辑 | 新增 `start_turn/end_turn/advance_turn` 拆分，两套驱动共用 |
| D10 | 新增 `tests/test_ui.gd`（用代码模拟点击） | B6/B7 两个 bug **只有真去点才会暴露**，headless 模拟永远测不出来 | 28 项断言进 CI 式回归 |
| D11 | 新增 `tests/balance.gd` 量化阵容胜率 | 「我方 4 回合就崩了」这种问题肉眼看不出来 | 对手阵容由实测选定，不再拍脑袋 |
| D12 | 对手阵容定**候选 B**（熔岩獠牙8 + 影爪猫8 + 焰尾狐7） | AI 对 AI 胜率 84.3%，落在目标区间 60~85% | 改 `ENEMY_TEAM` 必须重跑 balance |

### 发现并修复的 2 个 UI 层 bug

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| **B6** | 木灵鹿点「使用技能」反而给**敌人**回血 | `_auto_target()` 写死返回敌方；而技能目标阵营其实写在 `skills.json` 的 `target.side` | 改为读 JSON 的 `target.side`；`self` 返回施法者自身 |
| **B7** | 潮汐龟（只有 `on_play` 技能）点按钮无反应 | UI 只遍历 `trigger=="active"`，找不到就什么都不做 | 找不到可用主动技能时回退**普攻**，按钮显示「普攻」 |

### 关键量化发现

- **等级悬崖**：敌方 Lv7→Lv8（属性仅 +8%），我方胜率 **87.0% → 38.3%**，掉 49 个百分点
- 根因是**减防式伤害模型**在攻防接近区间无过渡带 + 雪球效应无阻尼
- 战斗长度健康：全灭结束 82.8%，超时判定 17.3%，平均 10.9 回合（上限 15）
- **规则缺口**：`pick_targets()` 完全不读 `taunted_by` —— 嘲讽的**控制效果当前是失效的**
- 完整报告见 `docs/BALANCE-ANALYSIS.md`

### F42 · 嘲讽的目标约束（2026-10-06 补记）

`taunted_by` 一直被写进单位字典，但 `pick_targets()` 从不读它 —— 嘲讽的**控制效果是失效的**，
只有 DEBUFF 那部分数值在起作用。补上约束，并用 `ATTACK_OPS` 白名单把治疗类效果排除在外。

### F7 · 卡组构筑与场景串联（2026-10-06 补记）

新增 `scripts/session.gd`（static 变量，不用 autoload）+ `scenes/deck/DeckScene.tscn` + `scenes/boot.tscn`。
流程闭环：启动 → 编组（选 16 张）→ 战斗 → 结算 → 再来一局 / 返回编组。

首发阵容规则：**取牌库中前 3 张互不相同的幻兽卡**（写在 `Session.team_from_library`，规则可预期）。

### F5 · 手动目标选择（2026-10-06 补记）

原实现自动选目标（敌方血量最低）。**这等于把玩家唯一的决策点拿走了** ——
「打谁」是卡牌对战最核心的决策，交给程序就是没有玩法。改为：点卡/技能 → 进入选目标状态 → 点单位确认，可取消。

### 技术坑（值得记住）

> `add_child()` 之后 `_ready()` **要到下一帧才触发**。
> headless 测试里立刻读 `state` 会拿到 `null`。`test_ui.gd` 的断言因此放在 `_process()` 第 2 帧。

> GDScript 的 `Array` 是**共享引用**：`var a = state.hands[0]` 后 `a.append(x)` 会直接改到 state 里。
> 测试里比较「操作前后数量」必须先取 `int` 快照，否则前后比较的是同一个数组，断言恒假。

> `SceneTree.change_scene_to_file()` **不能在 `_ready()` 里直接调用**，会报
> `Parent node is busy adding/removing children`。必须用 `call_deferred`。

> Python `io.open(p, 'w')` 在 Windows 会把 `\n` 转成 `\r\n`。
> 写 GDScript 时用 `newline=''`，否则会污染 `.gitattributes` 声明的 LF 行尾。

---

---

## 2026-10-06 · GUI 实机运行验证（首次非 headless）

用 `Godot_v4.3-stable_win64.exe --path .` 正常启动，**连续运行 4 分 22 秒后由用户手动关闭**。
全程输出只有引擎版本与 GPU 信息（OpenGL 3.3 / RTX 5070 Ti），**零 SCRIPT ERROR、零 WARNING、零崩溃堆栈**。

判定：**PASS**。这是首次证明项目不只在 headless 下能跑，在真实渲染管线 + 真实窗口下同样健康。

### 同批发现并修复的布局 bug

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| **B8** | **手牌区在整个屏幕外，玩家无法出牌** | 窗口 960×540，而布局总高约 598px | 窗口 → 1024×640；战斗日志区 150px → 100px |

> B8 是"headless 测试永远测不出来"的第二类典型（第一类是 B6/B7 的交互链路）：
> headless 不渲染，也就不关心布局。结论是——**每完成一个界面，必须真渲染一帧并截图**。
> 因此新增 `tests/shot.gd`（非 headless 截图工具，`--act` 可先自动打几回合）。

### 截图产物

| 文件 | 内容 |
|---|---|
| `docs/shots/deck.png` | 卡组构筑界面（1024×640） |
| `docs/shots/battle.png` | 战斗界面（自动推进 3 回合后，含血量变化与战斗日志） |

---

## 2026-10-06 · F1 Web 导出验证（PoC 最高优先项，PASS）

**结论：Web 导出可用。** 导出 → 本地 HTTP 托管 → 浏览器可运行，判定 **PASS**。
这意味着作品集可以做成"点开就能玩"的链接，而不是只能给源码或录屏。

### 产物（release，nothreads）

| 文件 | 大小 |
|---|---|
| `index.wasm` | 33.7 MB |
| `index.pck` | 177 KB |
| `index.js` | 324 KB |
| `index.html` + 图标 | ~45 KB |
| **合计** | **约 34.2 MB** |

> 未 gzip 的 wasm 就是这个量级；若托管到支持 gzip/brotli 的服务可压到约 10 MB。
> itch.io 的上传上限是 1 GB，34 MB 完全没问题。

### 关键决策：用 nothreads 模板

`export_presets.cfg` 中 `variant/extensions_support = false`，Godot 会自动选用
`web_nothreads_release.zip` 而非 `web_release.zip`。

理由：**带线程的模板要求服务端返回 COOP/COEP 响应头**，而 itch.io 的 iframe
和普通静态托管都不会给，结果就是直接白屏。V0 不需要 GDExtension，关掉最稳。

### 踩到的坑

| # | 问题 | 修复 |
|---|---|---|
| W1 | `export_presets.cfg` 里用 `#` 写注释 → `ConfigFile parse error` | Godot 的 ConfigFile 注释符是 **`;`**，不是 `#` |
| W2 | 模板解压后多一层 `templates/` → 报"指定路径不存在导出模板" | 模板文件必须直接放在 `export_templates/4.3.stable/` 下，不能再套 `templates/` |
| W3 | GitHub release 的 CDN 被网络策略挡住，下不动 | 改走 **API asset 端点**下载：`GET /repos/godotengine/godot/releases/assets/{id}` + `Accept: application/octet-stream` |

### 本地验证方式

```bash
godot --headless --path . --export-release "Web" "build/web/index.html"
cd build/web && python -m http.server 8000
# 打开 http://127.0.0.1:8000
```

---

## 待决策（PoC 第 4 周末填写）

| # | 问题 | 影响 |
|---|---|---|
| Q1 | Web 导出能用吗？ | 决定作品集呈现方式 |
| Q2 | 单只幻兽美术实际几小时？ | 决定 20 只 / 12 只 / 退像素风 |
| Q3 | 10 个效果原语够用吗？ | 决定是否扩展（上限 12） |
| Q4 | 是否做 AI 增强模块（M2.5）？ | +50~146 h，但作品集差异化价值高 |
