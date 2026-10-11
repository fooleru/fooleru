# ZS 源码数据参考库 · 总索引

> 文档：参考基准（总入口）｜ 版本：v0.1（**R-18 新建**）｜ 作者：文策渊（design-strategist）
> **数据源**：`D:\games\Zero.Sievert\ZS_vanilla\gamedata\`（ZERO Sievert `base gamedata`，共 **40 个 `.json`**）

---

## 0. 两级口径声明（⚠ 本文件最重要的部分 · 用户决策 2026-09-22）

> 用户原话：「**其他文件也要解析，但是都只能作为原型阶段的参考，最终版不能完全照抄 Zero Sievert。**」

| 阶段 | ZS 数据的角色 | 具体做法 |
|---|---|---|
| **阶段 0–1（原型 / 垂直切片）** | ✅ **参考基准，可直接照用** | 数值、属性轴、射程曲线、掉落权重、敌人参数**可直接采用 ZS 真值**，用于**快速验证手感与节奏**——不必自己从零调参 |
| **阶段 2+（正式内容）** | ⚠ **仅作对照，必须原创** | 数值须按本作「100 层垂直大厦」的难度曲线**重新标定**；**命名、资产、UI、文案必须原创**；**不得出现 ZS 的化名 / 资产 / 原文案** |

**为什么必须原创化（三条理由）**：

1. **法律** —— ZS 的数值表、化名体系（`EC 101` / `N4o1` / `Skop H`）、美术与文案都是其知识产权。**照抄有 IP 风险**，尤其计划上架 Steam 时。
2. **设计** —— ZS 是「多地图 + 撤离点」的搜打撤；本作是「**100 层垂直大厦、按存档固化、从顶层杀到底层**」。**节奏、单局时长、难度曲线都不同**，ZS 的数值不可能直接适配。
3. **产品** —— 终版必须有**自己的辨识度**。一个「换皮的 ZS」既无卖点也有风险。

> **✅ 正确用法**：把 ZS 数据当作「**一位经验丰富的同行已经把原型调通了**」——站在它肩上**快速**走过阶段 0–1，然后在阶段 2 用**自己的**数值、命名与资产替换掉。ZS 在这里的角色是**加速器**，不是**终稿**。

---

## 1. 数据源纪律（8 条 · 全库适用）

1. **凡「ZS 侧」的数值与结构断言，一律以本数据源为准** —— 禁止凭印象书写（R-16 已因此出过一次事实错误）。
2. **阶段 0–1 可直接照用；阶段 2+ 必须原创** —— 见 §0。
3. **引用 ZS 数值时，必须在文档中标注**「引自 `reference-zero-sievert-*` · 原型参考」。
4. **ZS 的化名体系（`EC 101` / `N4o1` / `Skop H` …）不得直接复制** —— 那是 ZS 的原创虚构名；本作应**自造化名**或另立方案。
5. **终版不得原样出现 ZS 的数值表** —— 数值需经本作难度曲线重标定。
6. **ZS 数据文件是「Godot 宽容 JSON」** —— 多处含**尾随逗号**（`skills.json` 甚至无法用标准解析器读取）。本作自建数据管线时**应采用标准 JSON**。
7. **数据源可能随 ZS 版本变动** —— 本库记录的是 **2024 年版 base gamedata**；若 ZS 更新，需重新解析并标注版本。
8. **发现本作与 ZS 真值冲突时，先记差异、再等用户拍板** —— 不擅自改 GDD 数值。

---

## 2. 分册索引（4 份）

| 分册 | 覆盖文件 | 内容 |
|---|---|---|
| **`reference-zero-sievert-weapon-data.md`** | `weapon.json` · `caliber.json` · `mod_positions.json` · `mod_types.json` · `stat.json` | 49 把武器真值表（6 类 · 按 value 降序）· 13 口径 · 字段语义 · 化名对照（39 组）· 与本作 15 条差异 · 3 个采纳方案 |
| **`reference-zero-sievert-ammo-armor-mod.md`** | `ammo.json` · `armor.json` · `w_mod.json` · `grenade.json` · `weapon_glance_stat.json` · `weapon_types.json` | **六类武器射程曲线（本作完全缺失）** · 39 弹药 · 37 护甲 · 214 改装件 · 5 投掷物 |
| **`reference-zero-sievert-medical-loot.md`** | `medication.json` · `injector.json` · `consumable.json` · `chest.json` · `repair_*.json` | 药品四轴模型（**绷带不回血**）· 注射器 buff/副作用 · 49 消耗品 · **143 容器掉落表 + 稀有度机制** |
| **`reference-zero-sievert-meta-npc.md`** | `loadout.json` · `upgrade_base_kit.json` · `npc_preset.json` · `skills*.json` · `trader.json` · `barter.json` 等 | 6 套起始装备 · 13 建筑升级（**ZS 侧事实；⚠ 本作不采纳建筑升级，R-31——房间建成即为完整状态**） · NPC 双轴感知（视觉/听觉）+ 武器池梯度 · 技能系统（**ZS 侧事实；⚠ 本作不采纳任何玩家技能 / 熟练度数值成长，R-30**） · 商人经济（**ZS 侧事实；⚠ 本作不采纳 meta 解锁树 / 局外货币 `Credits`，R-32——唯一货币 = 现金，仅交易时使用**） |

**解析脚本**（可复现）：`.workbuddy/gen_zs_ref.py` · `gen_zs_b.py` · `gen_zs_cd.py` · `scan_zs.py`

---

## 3. 全部 40 个文件清单（按重要度分组）

### 3.1 A 组 · 已深度解析（26 个）

| 文件 | 条数 | 内容 | 本作对应模块 |
|---|---|---|---|
| `weapon.json` | 51 | 武器（6 类） | `weapons-loot` §3.1.1 / §4.3 |
| `ammo.json` | 39 | 弹药（口径 / 穿透 / 精度修正 / 弹丸数） | `weapons-loot` §3.8 |
| `armor.json` | 37 | 护甲（Class / pierce / 耐久损耗） | `combat` §4.1 · `weapons-loot` §3.5 |
| `w_mod.json` | 214 | 武器改装件（属性**加减**模型） | `weapons-loot` §4.4 |
| `weapon_glance_stat.json` | 6 | **六类武器基准参数 + 射程曲线** | `combat` §4.1 / §4.2（**本作缺失**） |
| `weapon_types.json` | 6 | 武器 6 类枚举 | `weapons-loot` §3.1 |
| `caliber.json` | 15 | 口径表（13 有效） | `weapons-loot` §3.8 |
| `mod_types.json` | 12 | 改装类型 | `weapons-loot` §4.4 |
| `mod_positions.json` | 11 | 改装位 | `weapons-loot` §4.4 |
| `medication.json` | 10 | 药品（ZS 四轴 hp/bleed/wound/radiation） | `weapons-loot` §3.10 · **本作改三轴（R-19）** |
| `injector.json` | 7 | 注射器（buff + 副作用） | R-14「强效药剂」**已定（R-19，副作用 = 饥渴加速）** | **⚠ R-34：本作「强效药剂」已删除，由「医疗包」（纯大回血 +60、无 buff/副作用）替大回血槽——ZS injector.json 的「buff+副作用」模型本作不再沿用** |
| `consumable.json` | 49 | 食物 / 饮料 / 烟酒 | `base-survival-npc` §A |
| `grenade.json` | 5 | 投掷物 / 地雷 | `combat`（R-12 投掷物升 T 档） |
| `chest.json` | 143 | **掉落表 + 稀有度权重** | `weapons-loot` §4.1 · `procedural-gen` |
| `repair_weapon.json` | 6 | 武器维修包（ZS 按口径限定） | `weapons-loot` §3.7 · **本作改按大类分档（R-19）** |
| `repair_armor.json` | 2 | 护甲维修包 | `weapons-loot` §3.5/§3.7 · **护甲维修包独立（R-19）** |
| `loadout.json` | 6 | 起始装备套 | `progression` §3.2 |
| `upgrade_base_kit.json` | 26 | 基地升级套件（13 建筑 × 2 级） | `base-survival-npc` §B |
| `npc_preset.json` | 31 | **NPC AI 参数 + 武器池梯度** | `enemies-ai` |
| `skills_hunter.json` | 26 | 猎人技能 | `progression` |
| `skills_masteries.json` | 3 | 6 类武器精通 | `progression` · `combat` |
| `skills_gun_passives.json` | 2 | 枪械被动（改武器轴） | `progression` |
| `backpack.json` | 13 | 背包（容量 / 移速 / 工效） | `weapons-loot` §3.3 |
| `headset.json` | 6 | 头戴（灯 / 夜视） | `fog-of-war` |
| `trader.json` | 13 | 商人（阵营 / 资金 / 库存） | `base-survival-npc` §C |
| `barter.json` | 146 | 交易材料 | `base-survival-npc` §C |

### 3.2 B 组 · 已扫描但未深挖（14 个，需要时再解析）

| 文件 | 条数 | 内容 | 备注 |
|---|---|---|---|
| `npc.json` | **110** | NPC 完整定义（含 `faction` / `arma` / `damage_melee` / `esperienza`） | 敌人行为、Boss 强度的直接来源，量大待深挖 |
| `stat.json` | 57 | 玩家统计数据项（含 6 类武器击杀/经验） | 结算界面参考 |
| `speaker.json` | 39 | NPC 对话说话人 | 叙事 |
| `item_category.json` | 20 | 物品分类枚举 | 背包分页 |
| `book.json` / `book_r.json` | 10 / 7 | 技能书（普通 / 稀有） | `progression` 技能解锁 |
| `key.json` | 16 | 钥匙（对应门锁） | 楼层门禁设计参考 |
| `documents.json` | 4 | 任务文档 | 任务系统 |
| `gamepad.json` | 1 | 手柄参数（瞄准灵敏度 / 死区 / 径向菜单） | `ux-spec` 手柄 B 档 |
| `chest_sound.json` | 8 | 开箱音效映射 | 音频 |
| `trader_pages.json` | 12 | 商人页签 | UI |
| `base_storage_use.json` | 1 | 基地仓库交互 | 基地 |
| `languages.json` | 1 | 多语言表（含简中） | 本地化 |
| `weapon_glance_stat` 已归 A 组 | — | — | — |
| ⚠ `skills.json` | **解析失败** | 非标准 JSON（**含非法字符**，连宽容清理也失败） | 需人工查看或放弃 |

---

## 4. R-18 暴露的六项 — **R-19 已全部拍板结案 ✅**

> 下表为 R-18 挂起项与 **R-19 用户拍板结果**（原始裁决见 `reference-alignment-zero-sievert.md` §2 裁决 ⑨–⑭）。

| # | R-18 挂起问题 | R-19 裁决 | 落点 |
|---|---|---|---|
| 1 | **药品模型需重构** | ✅ **改「三轴」**：`hp` / `bleed` / **尸毒感染度 `rot`**（原创命名，替代 ZS `radiation`）；**普通绷带 `hp = 0`、只止血** | weapons-loot §3.10 · combat §6.13 |
| 2 | **是否引入 `wound`（伤口）系统** | ✅ **取消**——不引入第四轴 | combat §6.13 · weapons-loot §3.10 |
| 3 | **是否引入「射程曲线」** | ✅ **采纳**——`EffRangeDmgMult` / `EffRangeRecoilMult` 折线 + `FalloffEnd`；**楼内交火距离护栏见 combat §4.8.4** | combat §4.8 · weapons-loot §3.1.1 |
| 4 | **改造模型改加减还是保留乘区** | ✅ **改纯加减**（唯一保留乘区：消音器听觉半径、镜的视野/射程） | weapons-loot §3.3/§4.4 · combat §4.1 |
| 5 | **维修是否改为消耗维修包** | ✅ **改消耗维修包**；**取消按口径限定**，改按**武器大类三档 + 护甲独立**；**修不满** | weapons-loot §3.7 · combat §4.6 |
| 6 | **敌人感知改双轴** | ✅ **改双轴**（视觉 `VisualRange` + 听觉 `HearRange`，听觉**不要求 LOS**；脱战时间减半） | enemies-ai §4.1 |

> **仍未结案（R-19 之后）**：ZS 武器数值采纳方案（A/B/C）、型号命名策略（商标风险）、是否补 `dmr` 独立族、敌人是否也有后坐、投射物 vs hitscan、投掷物升 T 档——详见 `reference-alignment-zero-sievert.md` §7 #20–#23 与 `concept.md` §8。

---

*交叉引用：`reference-alignment-zero-sievert.md`（口径契约 · 本作取舍）· 四份分册（见 §2）· 本作落点文档：`weapons-loot.md` / `combat.md` / `base-survival-npc.md` / `enemies-ai.md` / `progression.md` / `procedural-gen.md`*
