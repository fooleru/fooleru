# ZS 起始装备 / 基地升级 / NPC / 技能 真值基准

> 文档：参考基准（**ZS 源码解析归档**）｜ 版本：v0.1（**R-18 新建**）｜ 作者：文策渊（design-strategist）
> **数据源**：`D:\games\Zero.Sievert\ZS_vanilla\gamedata\`（ZS base gamedata）
> ⚠ **定位（用户决策 · 2026-09-22）**：本文件**仅作原型阶段（阶段 0–1）的参考基准**。
> **终版的数值、命名、资产必须原创，不得完全照抄 ZS。**

---

## 1. 起始装备 `loadout.json`（6 套）

| id | 名称 | 起始资金 | 物品数 | 关键装备 |
| --- | --- | --- | --- | --- |
| `equipment_1` | **Assault** | 7,500 | 18 | 枪: ak_74u_1、makarov ／ 甲: armor_bulletproof |
| `equipment_2` | **Bruiser** | 7,500 | 17 | 枪: sawed_off_double_shotgun ／ 甲: armor_novice |
| `equipment_3` | **Marksman** | 7,500 | 18 | 枪: mosin、makarov ／ 甲: armor_bulletproof |
| `equipment_4` | **Ranger** | 7,500 | 17 | 枪: sks、makarov ／ 甲: armor_bulletproof |
| `equipment_5` | **Tactical Operator** | 7,500 | 16 | 枪: tt_tokarev ／ 甲: armor_bandit_1 |
| `equipment_6` | **Survivor** | 0 | 8 | 枪: makarov ／ 甲: — |

> **⚑ 印证 R-15**：`equipment_1`（Assault）的起始武器是 **`ak_74u_1`（AK-74U）+ `makarov`（手枪）** —— **AK-74U 在 ZS 里确实是「最早期、最廉价」的步枪**（value 12,500，全步枪最低），与「用户把它放在阶梯低档位」方向一致。
> 6 套模板 = Assault / Bruiser / Marksman / Ranger / Tactical Operator / Survivor（最后一档资金 0、仅 8 件，属硬核难度）。

## 2. 基地升级 `upgrade_base_kit.json`（26 条 = **13 建筑 × 2 级**）

**结构**：`base_upgrade{ id, lvl_req }` + `basic{...}` —— 每栋建筑两个等级，`lvl_req` 为 0 / 1。

| 建筑 id | 中译 | 等级数 |
| --- | --- | --- |
| `ammo` | 弹药生产 | 2 |
| `bed` | 卧室 | 2 |
| `forge` | 锻造 | 2 |
| `garden` | 菜园 | 2 |
| `gym` | 健身房 | 2 |
| `med_station` | **医务室** | 2 |
| `kitchen` | 厨房 | 2 |
| `radio_central` | 电台 | 2 |
| `recycling` | 回收 | 2 |
| `scavenger` | 搜刮者 | 2 |
| `shooting_range` | 靶场 | 2 |
| `storage` | 仓储 | 2 |
| `workshop` | 工作台 | 2 |

> **⚑ 与本作基地的对照（R-13 / R-14）**：
> - ZS 只有 **13 栋建筑 × 2 级**，本作是 **R1 + R2–R10**（**10 间**、**3 级**；**R-27：R10 = 末日之源召唤器正式房间**）—— **本作建筑数更多、等级更深**。
> - ZS 的 `med_station`（医务室）**同样不是回血点**：玩法是「**制药（Medicine）+ 找 Doctor 付费治疗**」，与 R-16 修正后的口径一致。
> - ZS 有**本作没有的**：`radio_central`（电台）、`gym`（健身房）、`shooting_range`（靶场）—— 其中靶场正好对应本作 **R8「训练场」**（R-27 迁号；原 R6）。

## 3. NPC 预设 `npc_preset.json`（31 条）—— 对上 `enemies-ai`

**关键字段**：`aim_factor` · **`alert_radius`**（听觉半径）· **`alert_visual_distance`**（视觉距离）· `alert_min_distance` · `alert_visual_distance_h`（水平）· **`arma`**（**武器池**）· `armor` · `ammo_value` · `attachment_value` · `damage_melee` · `faction` · `esperienza`（经验值）· `chest_dropped`

**`general` 是模板**，其余为具体预设。**听觉 / 视觉按距离档位分组**：

| 参数 | 人类（近 / 中 / 远） | 变异体（近 / 中 / 远 / 极近） |
| --- | --- | --- |
| `alert_radius`（听觉） | 40 / 60 / 120 | — |
| `alert_visual_distance`（视觉） | 220 / 250 / 300 | 60 / 110 / 170 / 220 |

> **⚠ 重要**：**变异体的视觉距离（60–220）明显低于人类（220–300）** —— 这是「**变异体靠听觉、人类靠视觉**」的可调参数。本作 `enemies-ai` 目前用**固定视野**，建议改为该双轴模型。

**`arma`（武器池）按敌等级上移** —— 与 R-15「越深越只出高级型号」同构：

| 敌人等级 | 武器池 |
| --- | --- |
| `{bandit_rookie}` | sawed_off_double_shotgun、mp_133、makarov、skorpion、tt_tokarev、pp91、ak_74u_1、ppsh_41_1 |
| `{bandit_skilled}` | pp91、ak_74u_1、ak_74、aps、pp19_bizon、toz34、mp_133、sks、mosin |
| `{bandit_veteran}` | ak_74、akm、sks、sv98_1、svt_40 |
| `{green_army_rookie}` | mp_133、pp91、pp19_bizon、ak_74u_1、ak_74u_1、ak_74 |
| `{green_army_skilled}` | ak_74u_1、ak_74u_1、ak_74、ak_74、akm、svt_40、mosin、fn57、groza_4 |
| `{green_army_veteran}` | ak_74、ak_74、akm、akm、avt_40、ak_101、sv98_1、groza_4、groza_1 |
| `{green_army_master}` | ak_74、akm、groza_4、groza_1、ak_101、svd、as_val、protecta_1、ash12 |
| `{crimson_rookie}` | mp5、pp19_bizon_9x19、ump_1、r700_1 |

（模板中 `arma` 共 15 个等级档）

> **⚑ 洞察**：ZS 用「**敌人等级 → 武器池**」表达强度梯度，与「**楼层深度 → 武器型号池**」（本作 R-15）是同一思路的两种实现。**本作可把两者绑定**：深层不仅出好枪，敌人也用得起好枪。

## 4. 技能系统（`skills_hunter` 26 · `skills_masteries` 3 · `skills_gun_passives` 2）

- **猎人技能 `skills_hunter`**：26 条，字段含 `view_fov_bonus`（视野加成）等 —— 对应本作 `progression` 的被动解锁。
- **武器精通 `skills_masteries`**：3 条，key 为 **6 类武器**（pistol / smg / shotgun / rifle / dmr / sniper）→ 每类独立熟练度。
- **枪械被动 `skills_gun_passives`**：2 条，字段直接作用于武器轴 —— `damage` / `reload_speed` / `ergonomics` / `accuracy` / `recoil` / `knockback` / `min_range` / `max_range` / `recover_from_mouse_movement` / `scope_*`。
  → **注意**：被动直接改 `min_range` / `max_range`，**印证了「每类武器有射程曲线」这一机制**（见 `reference-zero-sievert-ammo-armor-mod.md` §1）。

## 5. 装备与杂物（概览）

| 文件 | 条数 | 用途 | 关键字段 |
| --- | --- | --- | --- |
| `backpack.json` | 13 | 背包 | `ergonomic` / `movement_speed` / `weight`（**容量**） |
| `headset.json` | 6 | 头戴（灯 / 夜视） | 灯光 / 夜视档位 |
| `key.json` | 16 | 钥匙 | 对应门锁 id |
| `book.json` / `book_r.json` | 10 / 7 | 技能书 | 提升技能 / 熟练度 |
| `barter.json` | 146 | **交易材料**（只有 `basic`） | 名称 / 价值 / 重量 |
| `trader.json` | 13 | 商人 | `faction` / `money` / `items` / `format_pages` |
| `documents.json` | 4 | 任务文档 | — |

> **⚑ 对 `base-survival-npc`（NPC / 好感）的参考**：ZS 的 `trader.json` 有 **13 个商人 × 阵营 + 独立资金 + 库存**，`barter.json` 146 种交易材料 —— 这是「**好感度 → 解锁商品**」的现成数据结构，可直接对照本作 NPC 好感系统。

*交叉引用：`reference-zero-sievert-ammo-armor-mod.md` · `reference-zero-sievert-weapon-data.md` · `reference-zero-sievert-medical-loot.md` · `reference-zero-sievert-data-index.md` · 本作落点：`progression.md` §3.2 · `base-survival-npc.md` §B · `enemies-ai.md`*
