# 美术管线（AI 生成立绘）

> 目的：让 20 只幻兽的立绘**风格一致**。AI 生图最大的风险是"每张都好看，但放一起像不同游戏"，
> 所以这里把 prompt 模板、色板锚点、后处理流程全部固定下来。

---

## 1. 工具与参数

| 项 | 值 |
|---|---|
| 工具 | AI 生图（ImageGen） |
| 尺寸 | 生成 1024×1024，**最终缩放到 512×512** |
| 背景 | transparent（但见 §3，实际常输出白底，需抠图） |
| 质量 | high |
| 单张成本 | 约 5~10 credits |

## 2. Prompt 模板（风格锚点，不要改动风格段）

```
2D hand-drawn cartoon fantasy creature portrait, game asset.
A small {形态} creature named "{中文名}", {属性} element.
Color palette: {主色} main, {暗部} shadow, {亮部} highlight, {辅色}.
{特征描述一句}.
Thick bold dark outline (#1A1A2E, visually ~4px).
Flat two-tone cel shading only (base + shadow + outline),
NO gradients, NO glossy highlights, NO noise, NO realistic lighting.
Rounded friendly Pokemon-style mascot design, big expressive eyes, cute proportions.
Facing viewer with a slight 3/4 turn, neutral idle pose.
Character centered, occupies about 75% of the frame, generous margin around it.
Pure transparent background. Clean vector-like crisp edges.
```

**必须保留的风格句**（动它们就会漂移）：`Thick bold dark outline` / `Flat two-tone cel shading` /
`NO gradients, NO glossy highlights` / `Pokemon-style mascot design, big expressive eyes` /
`Facing viewer with a slight 3/4 turn, neutral idle pose`。

**每次只改**：形态、中文名、属性、色板、特征描述。

### 属性色板（来自 `design/dev/C-美术规格书.md` §2.2，不许自定）

| 属性 | 主色 | 暗部 | 亮部 |
|---|---|---|---|
| fire | `#E94560` | `#A32C42` | `#FF8A9B` |
| water | `#4D96FF` | `#2E5FB0` | `#9DC4FF` |
| wood | `#6BCB77` | `#3F8A4A` | `#A8E5B2` |
| light | `#FFD93D` | `#C2A323` | `#FFEE9B` |
| dark | `#9B5DE5` | `#65399E` | `#C7A3F2` |

### prompt 禁忌

- **不要**让它在图里画名字/文字（木灵鹿第一版自己加了中英文名，得裁掉重居中）
- **不要**写 "cute logo" / "sticker"（会带白边和圆形底）
- 属性词用英文（fire/water/wood/light/dark），中文属性词容易触发书法字体

## 3. 后处理（每张必做，脚本见 §5）

1. **合成白底**：生成图声称透明但实际是白底/浅灰底（每张深浅不同，焰尾狐纯白、潮汐龟 225,223,221）
2. **抠背景**：从四边 BFS 泛洪，只删**与边缘连通**的浅色区 —— 粗描边天然保护角色内部的白色
   （阈值教训：潮汐龟背景 225,223,221，阈值 222 就差 1 没抠掉，**用 210**）
3. **裁 bbox + 补 32px 边距 + 缩放 512×512**（规格要求四周留 ≥32px）
4. **检查底部文字**：生成器偶尔在下方加名字，发现就整块裁掉再重新居中
5. 1px 边缘半透明化（alpha 150）去白边

## 4. 命名与路径

`res://assets/portraits/beast_001.png`（与 `data/cards.json` 的 id 一一对应）

## 5. 后处理脚本

内联在开发记录里（PIL + BFS 泛洪），核心逻辑：

```
alpha_composite 到白底 → RGB 判定 is_bg(r,g,b ≥ 210)
→ 从四边 BFS 只删连通浅色 → 1px 边缘 alpha 150
→ crop bbox → 补 32px → resize 512×512 → optimize 保存
```

## 6. 已完成与待做

| id | 名 | 属性 | 状态 |
|---|---|---|---|
| beast_001 | 焰尾狐 | fire | ✅ |
| beast_002 | 潮汐龟 | water | ✅ |
| beast_003 | 木灵鹿 | wood | ✅ |
| beast_004~008 | 藤蔓熊/熔岩獠牙/光羽鹭/影爪猫/圣辉幼兽 | wood/fire/light/dark/light | ⬜ |

## 7. 风格一致性验收（每生成 5 张看一次）

把新图与 beast_001 并排看，检查三点：
1. 描边粗细是否一致
2. 眼睛风格是否一致（这是观感差异最大的部位）
3. 头身比是否接近（1:1.2 左右的 Q 版比例）

偏差明显的**重生成**，不要试图手工修——修一张的时间够重新生成三张。
