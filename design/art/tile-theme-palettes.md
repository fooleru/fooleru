# 瓦片调色板 · 5 楼层主题（风格 B「厚墙砖缝」）

> 机器可读版：`design/art/tile_theme_palettes.json`（工程侧 `load()` 直接消费）
> 权威色源：`design/art/art-bible.md` §3.1 全局基底 / §3.3 楼层主题色 / §3.4 基地主题色
> 风格基准：`outputs/r126_tiles/tiles16/R126_three_sets.png` 第 2 段「B 厚墙砖缝」
> 规格：瓦片 16×16，墙正面 6px（3/4 厚度读法）

---

## 1. 对照表（5 层 × 8 色）

| 楼层带 | 主题 | `floor_field` 地板 | `floor_grout` 勾缝 | `floor_highlight` 倒角 | `wall_top` 墙顶 | `wall_joint` 砖缝 | `wall_face` 墙正面 | `wall_plinth` 踢脚 | `accent` 点缀 |
|---|---|---|---|---|---|---|---|---|---|
| **100** | 基地 | <span style="background:#7a5a3a">&nbsp;&nbsp;&nbsp;</span> `#7a5a3a` | <span style="background:#4a3520">&nbsp;&nbsp;&nbsp;</span> `#4a3520` | <span style="background:#faf3e0">&nbsp;&nbsp;&nbsp;</span> `#faf3e0` | <span style="background:#f0e2c0">&nbsp;&nbsp;&nbsp;</span> `#f0e2c0` | <span style="background:#8a7458">&nbsp;&nbsp;&nbsp;</span> `#8a7458` | <span style="background:#b0a184">&nbsp;&nbsp;&nbsp;</span> `#b0a184` | <span style="background:#241a12">&nbsp;&nbsp;&nbsp;</span> `#241a12` | <span style="background:#f2a23c">&nbsp;&nbsp;&nbsp;</span> `#f2a23c` |
| **99–71** | 豪宅层 | <span style="background:#9e9a92">&nbsp;&nbsp;&nbsp;</span> `#9e9a92` | <span style="background:#4a4842">&nbsp;&nbsp;&nbsp;</span> `#4a4842` | <span style="background:#f2ede1">&nbsp;&nbsp;&nbsp;</span> `#f2ede1` | <span style="background:#e6e1d6">&nbsp;&nbsp;&nbsp;</span> `#e6e1d6` | <span style="background:#8f8a7d">&nbsp;&nbsp;&nbsp;</span> `#8f8a7d` | <span style="background:#bcb4a4">&nbsp;&nbsp;&nbsp;</span> `#bcb4a4` | <span style="background:#2b2823">&nbsp;&nbsp;&nbsp;</span> `#2b2823` | <span style="background:#e8ce68">&nbsp;&nbsp;&nbsp;</span> `#e8ce68` |
| **70–41** | 突变层 | <span style="background:#ad6a83">&nbsp;&nbsp;&nbsp;</span> `#ad6a83` | <span style="background:#6b3a4d">&nbsp;&nbsp;&nbsp;</span> `#6b3a4d` | <span style="background:#e0aec6">&nbsp;&nbsp;&nbsp;</span> `#e0aec6` | <span style="background:#d194b0">&nbsp;&nbsp;&nbsp;</span> `#d194b0` | <span style="background:#3a5230">&nbsp;&nbsp;&nbsp;</span> `#3a5230` | <span style="background:#c07f9c">&nbsp;&nbsp;&nbsp;</span> `#c07f9c` | <span style="background:#2e1a24">&nbsp;&nbsp;&nbsp;</span> `#2e1a24` | <span style="background:#e8c4d2">&nbsp;&nbsp;&nbsp;</span> `#e8c4d2` |
| **40–11** | 封锁层 | <span style="background:#3d3f4a">&nbsp;&nbsp;&nbsp;</span> `#3d3f4a` | <span style="background:#22242c">&nbsp;&nbsp;&nbsp;</span> `#22242c` | <span style="background:#8a8e9c">&nbsp;&nbsp;&nbsp;</span> `#8a8e9c` | <span style="background:#7d8d61">&nbsp;&nbsp;&nbsp;</span> `#7d8d61` | <span style="background:#3a442c">&nbsp;&nbsp;&nbsp;</span> `#3a442c` | <span style="background:#66754f">&nbsp;&nbsp;&nbsp;</span> `#66754f` | <span style="background:#1b1d26">&nbsp;&nbsp;&nbsp;</span> `#1b1d26` | <span style="background:#f2a23c">&nbsp;&nbsp;&nbsp;</span> `#f2a23c` |
| **10–1** | 底层 | <span style="background:#1a2338">&nbsp;&nbsp;&nbsp;</span> `#1a2338` | <span style="background:#0a0b10">&nbsp;&nbsp;&nbsp;</span> `#0a0b10` | <span style="background:#6f8bb0">&nbsp;&nbsp;&nbsp;</span> `#6f8bb0` | <span style="background:#55658a">&nbsp;&nbsp;&nbsp;</span> `#55658a` | <span style="background:#1a2138">&nbsp;&nbsp;&nbsp;</span> `#1a2138` | <span style="background:#3d4a68">&nbsp;&nbsp;&nbsp;</span> `#3d4a68` | <span style="background:#06070b">&nbsp;&nbsp;&nbsp;</span> `#06070b` | <span style="background:#9db8d6">&nbsp;&nbsp;&nbsp;</span> `#9db8d6` |

### 质感说明（每层 ≤15 字）

| 楼层带 | 质感说明 |
|---|---|
| **100** 基地 | 打磨木地板，暖漆砖墙，灯常亮 |
| **99–71** 豪宅层 | 大理石地，米黄石墙，金箔残光 |
| **70–41** 突变层 | 组织紫红肉墙，腐绿砖缝 |
| **40–11** 封锁层 | 混凝土地，军绿漆砖，弹孔密布 |
| **10–1** 底层 | 近黑机房蓝地，冷光砖墙 |

---

## 2. 为什么这样分

地板与墙用**两套独立色相**（而非同色明暗阶），保证 16px 下「一眼分得开」；墙顶恒比墙正面亮，撑起 3/4 厚度读法。亮度沿层深递降：基地 94 → 豪宅 154 → 突变 122 → 封锁 63 → 底层 35，基地是唯一暖调且明度居中，与下层冷调形成 §3.4 反差。全部色相取自 §3.3/§3.4，仅在同色相上调明度作阶梯；§3.2 六个语义色一律未用。

---

## 3. 推导链（逐层）

| 层 | 主色来源 | 阶梯推导 |
|---|---|---|
| **base** | §3.4 暖白 `#f0e2c0` / 暖琥珀 `#f2a23c` / 木棕 `#7a5a3a` | 地板 = 木棕原值；墙顶 = 暖白原值；`floor_highlight` 取 §3.8 已登记的「暖白提亮 `#faf3e0`」；墙正面 = 暖白压暗至 `#b0a184`；勾缝 = 木棕 ×0.6 → `#4a3520`；踢脚 = 木棕 ×0.35 → `#241a12`；`accent` = 暖琥珀原值 |
| **mansion** | §3.3 金 `#d4af37` / 大理石 `#e6e1d6` | 墙顶 = 大理石原值；地板 = 大理石 ×0.62 → `#9e9a92`；墙正面 = 大理石 ×0.72 → `#bcb4a4`；`accent` = 金提亮至 `#e8ce68`（原金 `#d4af37` 明度 174 低于墙正面 181，会被墙吃掉，故上调一档） |
| **mutation** | §3.3 组织紫红 `#7a3b5a` / 腐绿 `#4f6b3a` | ⚠ **弃用黏液 `#7fae3a`** —— 与 §3.2 毒绿 `#9bcf3a` 仅差明度一档，砖缝满铺会被读成「毒」语义（违禁忌 43）。改以腐绿作 `wall_joint`（小面积砖缝，安全）；地板/墙身走组织紫红阶梯：原值 `#7a3b5a` 明度 75 偏暗，地板提亮至 `#ad6a83`（122）以拉开与封锁层的距离。**✅ R-131 用户拍板：突变层采用组织紫红主调（原值），不压暗——本行 8 色为终态，非待选项** |
| **blockade** | §3.3 军绿 `#3f4a36` / 混凝土 `#3d3f4a` / 警示条 `#f2a23c` / 弹孔 `#1b1d26` | 地板 = 混凝土原值；踢脚 = 弹孔原值；墙顶/墙正面 = 军绿提亮两档（`#7d8d61` / `#66754f`）；`accent` = 警示条原值（仅作极小面积警示条，**不得**铺底） |
| **sublevel** | §3.3 近黑 `#0a0b10` / 机房蓝 `#243049` / 冷光 `#6f8bb0` | 勾缝 = 近黑原值；地板 = 机房蓝压暗至 `#1a2338`（终局压迫）；墙顶/墙正面 = 机房蓝提亮两档；`floor_highlight`/`accent` = 冷光 `#6f8bb0` 原值与提亮 `#9db8d6`。⚠ **未用终端青 `#45d4e0`** —— 它与 §3.2 电青同 hex，属恒定玩法色 |

---

## 4. 自检结果（交付前已跑）

**① JSON 与楼层区间**
- `grep -c '"id"'` = **5** ✓
- JSON 解析通过；`style=B_thick_brick` / `tile_px=16` / `wall_face_px=6` / `version=1` ✓
- 8 个槽位键名与 schema **完全一致**（无增删改）✓
- 十个边界各归到恰好一条：100→base、99/71→mansion、70/41→mutation、40/11→blockade、10/1→sublevel ✓
- 1–100 无缝隙无重叠 ✓
- ⚠ **区间一律升序**：本文件与 `tile_theme_palettes.json` 中 `floor_min ≤ floor_max`（**数值升序**）。
  §3.3 的楼层带表述是「99–71」这种**递减**写法；若加载器按升序比较而数据按递减落盘，会**一条都匹配不上且不报错**（静默落空）。
  正确写法：`mansion` = `floor_min: 71, floor_max: 99`。**见 art-bible §3.3.1 同款警示。**

**② 逐层明度阶梯**（sRGB 近似 `0.2126R+0.7152G+0.0722B`，R/G/B 取 0–255）

要求序列：`wall_plinth` < `floor_grout` < `floor_field` < `wall_face` < `wall_top` < `floor_highlight` / `accent`

| 楼层带 | plinth | grout | field | face | top | highlight | accent | 单调 |
|---|---|---|---|---|---|---|---|---|
| **base** | 27.5 | 55.9 | 94.5 | 162.1 | 226.5 | **243.1** | 171.6 | ✓ |
| **mansion** | 40.3 | 72.0 | 154.3 | 180.5 | 225.3 | **237.2** | 204.2 | ✓ |
| **mutation** | 31.0 | 69.8 | 122.0 | 142.9 | 163.0 | **186.4** | 204.7 | ✓ |
| **blockade** | 29.2 | 36.2 | 63.4 | 111.1 | 134.4 | **142.2** | 171.6 | ✓ |
| **sublevel** | 7.1 | 11.1 | 34.6 | 73.4 | 100.3 | **135.7** | 180.4 | ✓ |

- 五层**全部单调递增** ✓；每层 `wall_top` > `wall_face`（3/4 厚度读法前提）✓
- 每层 `accent` ≥ `wall_face`（点缀不会比墙面还暗而被吞）✓
- 地板与墙正面分离度 ΔL：base 67.6 / mansion 26.3 / mutation 20.9 / blockade 47.7 / sublevel 38.8，**均 ≥ 20** ✓
- `wall_joint` 恒 < `wall_face`（砖缝不会盖过墙面）✓

**③ 语义色禁用（禁忌 7 / 14 / 43）**
- 对 §3.2 全部 7 色（玩家橙 `#ff7a1a`、血红 `#c0392f`、毒绿 `#9bcf3a`、电青 `#45d4e0`、警告红 `#f25c54`、通行绿 `#4fd06a`、鲜绿 `#3ee05f`）做全 40 格扫描 → **零命中** ✓
- 主动规避两处易混：突变层弃黏液 `#7fae3a`（≈毒绿）；底层弃终端青 `#45d4e0`（= 电青）✓

**④ 5 层 `floor_field` 两两可区分**

| 对 | ΔL | 对 | ΔL |
|---|---|---|---|
| base / mansion | 59.8 | mansion / mutation | 32.2 |
| base / mutation | 27.6 | mansion / blockade | 90.9 |
| base / blockade | 31.1 | mansion / sublevel | 119.7 |
| base / sublevel | 59.9 | mutation / blockade | 58.7 |
| mutation / sublevel | 87.4 | blockade / sublevel | 28.8 |

- 最小 ΔL = **27.6**（base/mutation），全部 ≥ 18 门槛 ✓
- 色相上：基地为暖棕（R>B）、突变层为紫红（B>R）、封锁层为冷灰蓝、底层为机房蓝——四层色相两两不同，灰度下靠 ΔL 兜底 ✓
- 基地区暖调显著：R 122 > B 58（暖棕），是五层中**唯一** R 通道占主导者，与 §3.4「与下层冷恐强反差」一致 ✓

---

## 5. 使用纪律（工程侧）

1. `accent` 仅用于**极少量**高光 / 杂物点缀，**不得**作大面积底色。
2. §3.2 六个语义色为跨层恒定玩法色，**环境瓦片一律不得挪用**（禁忌 7 / 14 / 43）。
3. 全部 hex 唯一来源为本文件 + `art-bible.md`，禁止散落硬编码。
4. 本作**禁 gradient / glow / neon / 投影**，明暗层次一律用硬像素阶梯表达。
5. 调色板切换只改环境色；**敌人 / 玩家 / 掉落物颜色跨层不变**，保证同一 hazard 在豪宅与底层都一眼可辨。

---

## 6. 复核状态（✅ 已完成 · R-131 收口）

> 配色已由用户拍板定稿（突变层取组织紫红原值，不压暗）。本节记的是**逐像素复核**结果。

**✅ 逐像素复核已通过（30 张 PNG 全覆盖，独立解 PNG 取唯一色 + 像素计数，未采信工程侧自报）**

| 检查项 | 结果 |
|---|---|
| 像素色集合 vs 8 槽位 | **5/5 层的像素色集合恰好等于 7 个结构槽位，无缺失、无多余色**（零漂移） |
| `accent` 像素数 | **5 层均为 0 px** —— 符合设计（`accent` 仅供 prop/decal 层，结构瓦片不该出现） |
| 突变层地板主色 | **`#ad6a83` × 730 px**，确认已是**组织紫红**（不再是腐绿） |
| 突变层禁用色 | `#7fae3a`(黏液) **0 px**、`#4f6b3a`(腐绿) **0 px**；五层**全部** themes 对 `#7fae3a`/`#4f6b3a`/`#9bcf3a` 均 **0 px** |
| 明度阶梯（naive luma 0–255） | **5/5 层严格单调递增**；`wall_top` > `wall_face` 5/5；地板/墙 ΔL 全部 ≥ 20（最低 mutation +20.9）；`accent` ≥ `wall_face` 5/5 |
| 与 §3.3.1 表逐字一致 | **5/5 层完全吻合**（偏差 ≤ 0.1） |

- **口径已固化为契约**：`naive sRGB luma（0–255）`，**不做 sRGB→线性化**。见 art-bible §3.3.1「口径是契约的一部分」段（含 linear 口径会把 sublevel 的 ΔL 判反的实证）。
- **对照图已产出**：`outputs/r126_tiles/tiles16/R131_five_themes.png`（行 1-3 实机录帧、行 4-5 合成，图内已标注）。
- **突变层贴线风险仍在但不改**：ΔL = **+20.9**，阈值 20，**余量仅 0.9**。用户已拍板原值不压暗；若将来有人要调突变层配色，**这一位最先翻**。