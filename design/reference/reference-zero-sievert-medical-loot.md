# ZS 医疗 / 消耗品 / 维修 / 掉落表 真值基准

> 文档：参考基准（**ZS 源码解析归档**）｜ 版本：v0.1（**R-18 新建**）｜ 作者：文策渊（design-strategist）
> **数据源**：`D:\games\Zero.Sievert\ZS_vanilla\gamedata\`（ZS base gamedata）
> ⚠ **定位（用户决策 · 2026-09-22）**：本文件**仅作原型阶段（阶段 0–1）的参考基准**。
> **终版的数值、命名、资产必须原创，不得完全照抄 ZS。**

---

## 1. 药品 `medication.json`（10 条）—— **推翻本作 R-14 的药品设计**

| id | 名称 | **回血 hp** | **止血 bleed** | **治伤 wound** | 辐射 | 使用耗时 `duration` | 用药移速 | **可移动使用** | 价值 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `med_wound_2` | Professional medikit | **0** | 0 | 40 | 0 | 720 | ×0 | ❌ **不可** | 6,000 |
| `medikit_3` | Modern medikit | **100** | 1 | 0 | 0 | 60 | ×0.5 | ✅ | 4,800 |
| `med_wound_1` | First aid medikit | **0** | 0 | 15 | 0 | 600 | ×0 | ❌ **不可** | 4,000 |
| `medikit_2` | Standard medikit | **60** | 1 | 0 | 0 | 120 | ×0.5 | ✅ | 3,800 |
| `medikit_1` | Improvised medikit | **40** | 0 | 0 | 0 | 180 | ×0.5 | ✅ | 2,800 |
| `anti_bleed_gel` | Anti bleed gel | **0** | 2 | 0 | 0 | 30 | ×0.5 | ✅ | 2,500 |
| `medikit_long` | Medikit T-000 | **50** | 0 | 0 | 0 | 480 | ×0 | ❌ **不可** | 2,000 |
| `bandage_sterilizzata` | Sterilised bandage | **15** | 1 | 0 | 0 | 240 | ×0.5 | ✅ | 1,200 |
| `pills_anti_rad` | Anti-rad pills | **0** | 0 | 0 | -0.5 | 120 | ×0.5 | ✅ | 1,000 |
| `bandage` | Bandage | **0** | 1 | 0 | 0 | 240 | ×1 | ✅ | 600 |

> **⚠ 四个独立轴（本作 R-19 已定为「三轴」，去掉 `wound`）**：
> - `hp` = 回血 · `bleed` = 止血等级 · `wound` = **治伤等级** · `radiation` = 抗辐射
> - **绷带（`bandage`）不回血！`hp = 0`，只止血（bleed 1）** —— 本作 R-14 写的「绷带回血」**与 ZS 不符**；**R-19 已采纳此点**（普通绷带 `hp = 0`，见 weapons-loot §3.10）。
> - **只有 medikit 系列回血**：`medikit_1` 40 / `medikit_long` 50 / `medikit_2` 60 / `medikit_3` 100 —— **回血是「医疗包」的专属职能**。
> - `med_wound_*`（First aid / Professional medikit）**只治伤不回血**，且 `can_move = false`（**用药期间完全定住**）。**本作 R-19 已「取消」`wound` 轴**——不引入此分支。
> - **`duration` ⚠ 语义待校准**：绷带 240 最长、现代医疗包 60 最短 → 更像「**使用动作耗时**」而非效果持续（绷带最慢、现代包最快，符合直觉）。**本作以秒计（绷带 1.5s / 抗毒血清 2.0s 等），只取"耗时排序"的相对关系，绝对值不照抄。**
> - **`speed_multiplier`** = 用药时移速倍率（0.5 = 减速一半，0 = 完全定住）—— 比本作「不可开火」更细。**本作 R-19 已采纳**（普通药 0.5；**抗毒血清 = 0 完全定住**）。
> - **ZS 有独立的「伤口 wound」系统**，本作 `combat.md` 只有出血/辐射，**需确认是否引入 wound** → ✅ **R-19 用户拍板「取消」**，并以原创的**尸毒感染度 `rot`** 替代 `radiation` 作为第三轴。

## 2. 注射器 `injector.json`（7 条）—— 对上 R-14「强效药剂 buff / 副作用」

> **⚠ R-34 订正（2026-09-24）：本作「强效药剂」已删除**，由「医疗包」（纯大回血 +60、无 buff/副作用）替大回血槽。故 ZS injector.json 的「正属性 buff + 负属性副作用」模型**本作不再落地**；本条仅作 ZS 数据源留存参考。

注射器 = **长时属性 buff + 副作用**（`duration` 7200–14400，量级远大于药品）。

| id | 名称 | 持续 | hp_regen | max_hp | stamina_max | stamina_regen | bleed_immune | bleed_rec | 副作用 | 价值 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `injector1` | Bloodsucker Injector | 7200 | 0 | 0 | 0 | 0 | ✅ | 25 | hunger_regen-5、thirst_regen-10 | 5,000 |
| `injector2` | Endurance Booster Injector | 14400 | 0 | 0 | 30 | 50 | — | 0 | hunger-15、hunger_regen-10、thirst-20、thirst_regen-15 | 8,000 |
| `injector3` | Body Fortifying Injector | 7200 | 0 | 30 | 0 | -35 | — | 0 | hunger-5、hunger_regen-10、thirst-10、thirst_regen-15 | 5,000 |
| `injector4` | Burden Injector | 18000 | 0 | 0 | 0 | 0 | — | 0 | hunger-25、hunger_regen-25、thirst-35、thirst_regen-25 | 15,000 |
| `injector5` | Chow-Down Injector | 600 | 0 | 0 | 0 | 0 | — | 0 | hunger_regen+75、thirst_regen+75 | 11,000 |
| `injector6` | Rad Shield Injector | 7200 | 0 | 0 | 0 | 0 | — | 25 | hunger_regen-20、thirst_regen-20 | 8,000 |
| `injector7` | Healing Stimulant Injector | 1800 | 90 | 0 | 0 | 0 | — | 0 | hunger-5、hunger_regen-10、thirst-10、thirst_regen-15 | 8,000 |

**字段全集**：`bleed_immune` / `bleed_rec` / `duration` / `hp_regen` / `hunger` / `hunger_regen` / `max_hp` / `max_weight` / `rad_def` / `rad_regen` / `stamina_max` / `stamina_regen` / `thirst` / `thirst_regen`

> **⚑ 直接可用**：这套「**正属性 buff + 负属性副作用**」模型原来可落地本作 R-14 待拍板的「强效药剂 = 增益 + 代价」，不必自己发明。**⚠ R-34：本作「强效药剂」已删除，该模型不再落地（大回血改由「医疗包」纯 +60、无 buff/副作用承担），本条仅作 ZS 设计参考留存。**

## 3. 消耗品 `consumable.json`（49 条）

**字段**：`basic` + `consumable{ animation, energy, fatigue, radiation, sound, thirst }`（食物 / 饮料 / 烟酒同一模型，靠**属性增减**区分）。

| id | 名称 | energy | fatigue | thirst | radiation | 价值 | 重量 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `blue_cigarettes` | Wilfon Cigarette | 0 | 0 | -4 | -0.2 | 5,000 | 0.05 |
| `coke` | Generic cola | 7 | 8 | 13 | 0 | 3,500 | 0.5 |
| `russian_chocolate` | Premium chocolate | 15 | 8 | 0 | 0 | 2,500 | 0.25 |
| `red_wine` | Red Wine | 13 | 0 | -8 | -0.2 | 2,000 | 1 |
| `hamburger` | Hamburger | 41 | 0 | 0 | 0 | 1,600 | 0.5 |
| `mre` | MRE | 40 | 0 | 20 | 0 | 1,500 | 1 |
| `whisky` | whisky | 14 | 0 | -22 | -2.3 | 1,200 | 0.5 |
| `stew_meat_beans` | Stew with meat and beans | 32 | 0 | 15 | 0 | 1,000 | 0.5 |
| `egg_cooked` | Cooked egg | 18 | 0 | 0 | 0 | 800 | 0.2 |
| `milk` | Milk | 8 | 10 | 18 | -0.3 | 800 | 1 |
| `pasta_cooked` | Cooked pasta | 23 | 0 | 0 | 0 | 800 | 0.2 |
| `tushonka_fish` | Canned fish | 16 | 0 | 7 | 0 | 800 | 0.5 |
| `generic_chocolate` | Generic chocolate | 10 | 5 | 0 | 0 | 700 | 0.25 |
| `meatballs` | meatballs | 17 | 0 | 0 | 0 | 650 | 0.2 |
| `pasta` | Pasta | 10 | 0 | -20 | 0 | 600 | 0.5 |
| `red_cigarettes` | Molbaro Cigarette | 0 | 0 | -3 | -0.15 | 600 | 0.05 |
| `vodka` | Vodka | 23 | 0 | -17 | -1 | 600 | 1 |
| `energy_drink` | Energy drink | 16 | 18 | 15 | 0 | 500 | 0.5 |
| `cheese` | Cheese | 14 | 0 | 0 | 0 | 450 | 0.4 |
| `egg_boiled` | Boiled egg | 11 | 0 | 0 | 0 | 450 | 0.2 |
| `meat_cooked` | Cooked meat | 16 | 0 | 0 | 0 | 400 | 1 |
| `sandwich_butter` | Sandwich with Butter | 12 | 0 | 0 | 0 | 400 | 0.1 |
| `sandwich_salame` | Sandwich with salami | 13 | 0 | 0 | 0 | 400 | 0.2 |
| `sandwich_meat` | Sandwich with meat | 22 | 0 | 0 | 0 | 350 | 0.4 |
| `sandwich_wurstel` | Sandwich with wurstel | 13 | 0 | 0 | 0 | 320 | 0.3 |
| `cup_coffee` | Cup of coffee | 0 | 13 | 5 | -0.3 | 300 | 0.3 |
| `cup_tea` | Cup of Tea | 0 | 8 | 10 | -0.19 | 300 | 0.3 |
| `water_bottle` | Bottle of water | 0 | 0 | 25 | -0.05 | 300 | 0.5 |
| `zombie_meat` | zombie meat | 0 | 0 | -20 | 1 | 300 | 0.4 |
| `butter` | Butter | 20 | 0 | -20 | 0 | 290 | 0.2 |
| `boar_meat` | boar meat | 7 | 0 | -14 | 0.2 | 250 | 0.6 |
| `tushonka_meat` | Tushonka | 18 | 0 | 0 | 0 | 250 | 0.5 |
| `fruit_juice` | Fruit Juice | 6 | 0 | 18 | 0 | 240 | 1 |
| `chips` | Chips | 11 | 0 | 0 | 0 | 230 | 0.1 |
| `egg` | Egg | 5 | 0 | 2 | 0 | 200 | 0.2 |
| `salame` | Salami | 13 | 0 | 0 | 0 | 180 | 0.25 |
| `canned_beans` | Canned beans | 13 | 0 | 10 | 0 | 150 | 0.2 |
| `raw_meat` | Raw meat | 7 | 0 | -14 | 0.2 | 150 | 0.25 |
| `wolf_meat` | Wolf meat | 7 | 0 | -14 | 0.2 | 150 | 0.35 |
| `wurstel` | Wurstel | 13 | 0 | 0 | 0 | 130 | 0.3 |
| `bread` | Bread | 10 | 0 | -3 | 0 | 100 | 0.3 |
| `milk_rotten` | Rotten Milk | 5 | 5 | 10 | 0.35 | 100 | 1 |
| `crackers` | Crackers | 7 | 0 | -2 | 0 | 80 | 0.25 |
| `crackers_rotten` | Crackers | 3 | 0 | -3 | 0.09 | 80 | 0.25 |
| `cheese_rotten` | Rotten Cheese | 6 | 0 | 0 | 0.12 | 40 | 0.4 |
| `water_bottle_rotten` | Bottle of rotten water | 0 | 0 | 12 | 0.4 | 40 | 0.5 |
| `egg_rotten` | Rotten Egg | 3 | 0 | 0 | 0.1 | 35 | 0.2 |
| `bread_rotten` | Rotten Bread | 5 | 0 | -5 | 0.15 | 30 | 0.3 |
| `salame_rotten` | Rotten Salami | 5 | 0 | 0 | 0.12 | 28 | 0.25 |

> 对照本作 `base-survival-npc` §A：本作用「食物 / 水」两个轴，**ZS 用 `energy`（精力 / 疲劳）+ `thirst`（口渴）**；且烟酒也有数值（香烟 `radiation −0.2`、`thirst −4`）。

## 4. 维修件（`repair_weapon.json` 6 条 · `repair_armor.json` 2 条）

**结构**：`repair{ caliber[], condition_gain, condition_max, condition_min }` —— 维修包**按口径限定**能用在哪把枪上。

| id | 名称 | 适用口径 | 价值 |
| --- | --- | --- | --- |
| `repair_weapon1_high` | Weapon repair kit | 9×18、9×19、5.7×28、12×70、a357magnum、7.62×25 | 7,000 |
| `repair_weapon1_low` | Weapon repair kit | 9×18、9×19、5.7×28、12×70、a357magnum、7.62×25 | 13,500 |
| `repair_weapon2_high` | Weapon repair kit | 9×39、5.45×39、5.56×45、7.62×39、.45 | 7,800 |
| `repair_weapon2_low` | Weapon repair kit | 9×39、5.45×39、5.56×45、7.62×39、.45 | 15,000 |
| `repair_weapon3_high` | Weapon repair kit | 7.62×51、7.62×54R、12.7×55 | 9,000 |
| `repair_weapon3_low` | Weapon repair kit | 7.62×51、7.62×54R、12.7×55 | 18,000 |
| `repair_armor_high` | Armor repair kit | 护甲 | 3,000 |
| `repair_armor_low` | Armor repair kit | 护甲 | 6,000 |

> **⚑ 关键差别（R-19 已采纳 ZS 侧）**：本作原是「工作台修满耐久」；ZS 是**消耗维修包道具**且**按口径匹配**。**R-19 用户拍板：改为消耗维修包**（采纳 ZS 侧），但**取消按口径限定**、改按**武器大类三档**（轻武器 / 制式 / 重武器，与上表 6 条 `repair_weapon*` 的三档分组同构、但匹配键换成大类）+ **护甲维修包独立**；`condition_gain` / `condition_max` 结构照用（**修不满**）。见 `weapons-loot` §3.7。

## 5. 掉落表 `chest.json`（143 个容器）—— **ZS 的稀有度在这里**

> **⚠ 更正 R-17 的一处结论**：此前写「ZS 没有稀有度」**不准确**。准确口径是：
> **ZS 的物品层没有 rarity，但「掉落表 + 物品实例」两层都有稀有度** —— `chest` 给档位**权重**，`items[]` 给每件物品 **rarity 标签**。

**容器字段全集**：`always_seen` · **`chance_uncommon` / `chance_rare` / `chance_epic` / `chance_legendary`** · `decay_items` · `destroy_when_empty` · `from_enemy` · `is_drop` · `item_min` / `item_max` · `items[]` · `max_durability` · `name` · `sound_type` · `special_items` · `sprite`

**统计**：`items[].rarity` 标签分布 —— 无标签 **376** · rare **292** · uncommon **235** · epic **210** · legendary **63**；**58 / 143** 个容器的 `chance_legendary > 0`。

**容器形态三类**：

| 形态 | 判据字段 | 说明 |
| --- | --- | --- |
| **场景容器** | `from_enemy=false, is_drop=false` | 箱子 / 保险柜 / 柜子等固定容器 |
| **尸体容器** | **`from_enemy=true`** | 每个敌人类型一份（`bandit_novice` / `arman` / `boar_zombie` …） |
| **投放容器** | **`is_drop=true`** | 空投 / Boss 掉落 / 商人物品 |

**Tier 梯度示例**（枪械箱按 tier 命名，权重逐级上移）：

| 容器 | name | uncommon | rare | epic | legendary |
| --- | --- | --- | --- | --- | --- |
| `weapon_box_all` | Common weapon all | 0 | 0 | 0 | 0 |
| `weapon_box_ammo` | ammo | 0 | 0 | 0 | 0 |
| `weapon_box_ammo_2` | Ammo box tier II | 60 | 30 | 15 | 0 |
| `weapon_box_common` | Weapon box tier I | 43 | 20 | 7 | 1 |
| `weapon_box_legendary` | Weapon box tier III | 50 | 30 | 15 | 5 |
| `weapon_box_mod` | weapon box mod | 0 | 0 | 0 | 0 |
| `weapon_box_mod_ak` | weapon box mod ak | 0 | 0 | 0 | 0 |
| `weapon_box_moddable` | weapon_box_moddable | 0 | 0 | 0 | 0 |
| `weapon_box_pistol` | pistol | 0 | 0 | 0 | 0 |
| `weapon_box_rare` | Weapon box tier II | 30 | 17 | 8 | 1 |
| `weapon_box_rifle` | rifle | 0 | 0 | 0 | 0 |
| `weapon_box_shotgun` | shotgun | 0 | 0 | 0 | 0 |
| `weapon_box_smg` | smg | 0 | 0 | 0 | 0 |
| `weapon_box_sniper` | sniper | 0 | 0 | 0 | 0 |

> **⚑ 与本作 `MinTier` 的对比（重要设计差异）**：
> - **ZS 是「软加权」**：容器档位越高，高级稀有度的**概率**越大，但低档物品**仍可能出现**（`weapon_box_common` 仍有 1% legendary）。
> - **本作是「硬门槛」**（R-15 `MinTier`）：未达深度的型号**根本不出**。
> - **结论**：两者不冲突、**可叠加** —— 用 ZS 式容器权重决定「档位分布」，用本作 `MinTier` 兜底「不该出现的型号不出现」。原型阶段可直接照用 ZS 的容器权重表。

> 另注：`chest.json` 含**尾随逗号**（Godot 宽容 JSON），标准解析器需做**字符串安全清理**（否则会把字符串内部切碎）。本作若自建数据管线，**建议直接采用标准 JSON**。

*交叉引用：`reference-zero-sievert-ammo-armor-mod.md`（弹药 / 护甲 / 改装 / 射程曲线）· `reference-zero-sievert-weapon-data.md`（武器）· `reference-zero-sievert-meta-npc.md`（元系统 / NPC）· `reference-zero-sievert-data-index.md`（总索引）*
