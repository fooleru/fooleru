# Brute · CharacterBody2D · R-146 第三种敌人（快速近战型僵尸）
#
# 【用户需求，逐字】
#   「增加第三种敌人：近战攻击，速度比普通僵尸更快，攻击力更强但是生命值减少一半。
#     该敌人和僵尸是同一阵营，刷新点也在一起但刷新数量比普通僵尸少一半。」
#
# 【实现策略：路径继承，不复制 Zombie.gd】
#   `extends "res://scenes/enemies/Zombie.gd"` 而**不是** `extends Zombie`：
#   后者依赖全局类缓存（`class_name Zombie`）在 headless `--script` 模式下的注册顺序，
#   本仓库已因此吃过亏（见 `Player.tscn` 那次 `has no resource loaders`）——
#   路径写法在**任何加载顺序下都能解析**，是本工程既有惯例。
#   收益：感知（双轴 + LOS）、Alert/Search/脱战、last-seen 惯性冲刺、受击硬直、
#   寻路、死亡信号**全部零改动继承**，Brute 与僵尸行为差异**只有三个数值**。
#   ⇒ 将来僵尸 AI 改一处，Brute 自动同步（不会漂移成两套 AI）。
#
# 【三个数值 = 全部差异】
#   速度 72 (> 僵尸 45，但 < 玩家冲刺 120 → 仍然跑得掉)
#   伤害 26 (> 僵尸中值 16.5)
#   生命 35 (= 僵尸中值 70 的一半)
#
# 【同阵营】
#   `faction` **不覆写** —— 继承 Zombie 的 `FACTION_UNDEAD`，因此：
#     · Brute 与僵尸互不攻击（同阵营过滤）
#     · Brute 会攻击玩家与雇佣兵
#     · 击杀计数走同一个 `died` 信号 + `faction` 绑定（Main.gd `_build_floor`）
#   ⚠ 这是**刻意不写**一行代码而不是"忘了写"：同阵营是需求的一部分，
#     写成 `faction = FACTION_UNDEAD` 反而多一处可能与父类漂移的真值。
#
# 【碰撞体】
#   与僵尸同为 12×12（见 Brute.tscn）—— 刻意**不变大**：
#   需求只说"更快/更痛/更脆"，没说更大；改碰撞盒会让玩家对"能不能挤过去"的判断失效
#   （R-79 间距类硬约束的同类教训）。
#
# 【AI 继承来的行为，全部符合"近战"语义，无需覆写】
#   · 攻击：`ZOMBIE_ATTACK_RANGE=16` 接触即打（同僵尸）
#   · 受击硬直：仍用共用的 `ENEMY_STAGGER_TIME=0.12`（< 前摇 0.2，攻击一定打得出）
#   · 徘徊：**R-146 新增的出生点徘徊由父类提供**，Brute 自动获得
extends "res://scenes/enemies/Zombie.gd"

## 覆写三个 @export（父类默认值取自 ZOMBIE_* 常量）。
## ⚠ 必须在 `_init()` 而非 `_ready()` 里设：`@export` 变量的赋值发生在 `_ready()` 之前，
##   而父类 `Zombie's _ready()` 会调用 `_scan()`（可能立刻进入 ALERT/CHASE）——
##   若等到 `_ready()` 才改数值，首帧感知已用旧速度/血量跑过了。
func _init() -> void:
    move_speed = GameConstants.BRUTE_SPEED
    damage = GameConstants.BRUTE_DAMAGE
    max_hp = GameConstants.BRUTE_HP
    hp = GameConstants.BRUTE_HP
    # ⚠ attack_range / visual_range / audio_range / attack_windup / attack_recovery /
    #   attack_interval / faction **一律不动** —— 刻意继承僵尸的近战参数，
    #   见文件头「三个数值 = 全部差异」。

## 供 headless 验证读取的标记（避免验证脚本靠 class_name 猜类型）。
## 用 `String` 而非 `class_name`：Godot 4 允许同名的 `class_name` 出现在不同文件，
##   但两个全局类同名会互相覆盖缓存 —— 所以这里用 `is_brute` 布尔标记 + 场景节点名。
var is_brute: bool = true

## R-148：**覆写**父类（Zombie）的精灵路径 → Brute 用自己那张橙褐变体。
##   ⚠⚠ **为什么必须覆写这一行**：本文件是 `extends "res://scenes/enemies/Zombie.gd"`，
##     不覆写就会**继承到 `zombie.png`**。而 `Brute.tscn` 里「僵尸红 / Brute 橙褐 /
##     佣兵黄绿」的**三向可分**是玩家在 320×180 内一瞬间分辨"普通僵尸 vs 快攻型"的
##     唯一线索 —— 继承同图 = 该线索直接失效（**这是回归，不是 cosmetic**）。
##   ⚠ 三张图**沿用同一剪影、同一记号位置**，差异严格限制在色相一维
##     （`brute.png` 与 `zombie.png` 的 alpha 逐像素一致，110 个不透明像素的 RGB 不同）
##     ⇒ 换图不引入任何新的形状/朝向回归面。
func enemy_sprite_path() -> String:
    return ENEMY_SPRITE_DIR + "brute.png"
