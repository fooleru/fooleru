# Splitter · CharacterBody2D · R-149 Boss 敌人「分裂怪」
#
# 【用户需求，逐字】
#   「在生成90层敌人时。在最大的房间内生成Boss级敌人"分裂怪"，它的体型比普通僵尸大4倍
#     （2x2个普通僵尸），速度是普通僵尸一半，血量是十倍，移动逻辑和普通僵尸一致但不会攻击，
#     每隔2秒从它的位置连续生成1只普通僵尸和1只快速僵尸（间隔0.1秒连续生成5次共10只）。」
#
# 【实现策略：路径继承，不复制 Zombie.gd（照抄 Brute.gd 的既有范式）】
#   `extends "res://scenes/enemies/Zombie.gd"` 而**不是** `extends Zombie`：
#   路径写法在任何加载顺序下都能解析（Brute.gd 文件头已写清这条血的教训）。
#   收益：感知（双轴 + LOS）、Alert/Search/脱战、last-seen 惯性冲刺、受击硬直、
#   寻路、死亡信号**全部零改动继承**。分裂怪与僵尸的行为差异只有**数值 + 不攻击 +
#   周期性生成小怪**三处。
#
# 【「不会攻击」的实现口径】
#   分裂怪继承完整 FSM（移动/感知/追击与僵尸一致），但**永不进入 ATTACK**。
#   最干净做法 = 在 `_init()` 里 `attack_range = 0.0`（CHASE 里 `d.length() <= 0`
#   对非重叠目标恒不成立 → 永不攻击），并 `damage = 0.0` 兜底。
#   **不改父类 FSM、不加新状态**：父类 `state` 数字被 `--verify-*` 多处按字面量
#   引用，重排/加状态会静默破坏断言。
#
# 【生成小怪（周期性 · R-150 起「仅视觉发现玩家时才生成」）】
#   每 `SPLITTER_SPAWN_INTERVAL`（2s）为一个周期；周期触发后**连续 5 次**生成
#   （每次间隔 `SPLITTER_SPAWN_GAP` = 0.1s），每次生成 1 普通僵尸 + 1 快速僵尸
#   （Brute），即每周期共 10 只；之后进入下一个 2s 周期，无限循环。
#   生成位置 = 分裂怪**当前**所在位置。
#
#   【R-150 用户需求，逐字】
#     「分裂怪 Boss行为修改：发现玩家时才生成僵尸，玩家离开视野后停止生成，
#       否则生成的僵尸会填满楼层。」
#
#   【口径①「发现玩家」= 仅视觉（用户已拍板，不得自行放宽）】
#     必须**同时**满足 `d <= visual_range`(60) **且** `LosUtil.has_los()` 通视。
#     **听觉不算**：听觉半径 180px 且**穿墙**，若把听觉并入「发现」，
#     玩家躲在墙后 150px 仍会被无限刷怪 —— 需求没解决，只是把 bug 挪了位置。
#     ⇒ **直接复用父类 `Zombie.axis_visual(c)`**（`Zombie.gd` 第 531~535 行
#       现成探针，语义 = 「范围内 且 LOS 通」，与本需求逐字吻合）。
#       **严禁**新写一套 LOS 逻辑、**严禁**改 `Zombie.gd`（父类 `state` 数字被
#       `--verify-*` 多处按字面量引用，改动会静默破坏既有断言）。
#
#   【口径②玩家中途离开视野 → 本轮照打，只是不再开新周期（用户已拍板）】
#     `_burst_left > 0`（本轮已开启）→ **完全不看视野**，把剩下几次打完。
#     理由：本轮 5 连是「已经扣扳机的一次齐射」，中途掐断会让生成节奏变得不可预期
#     （玩家在视野边缘抖动时，僵尸数忽增忽减），观感更差。用户明确要「打完再停」。
#
#   【为什么「暂停」`_spawn_cycle_t` 而不是「重置」—— 这是本条最容易被写错的地方】
#     无视野时**原值保留、什么都不做**（暂停），**不**清零、**不**重新计时。两条理由：
#     1. **重置会让「反复探头」的玩家彻底饿死生成器**：每次重新进视野都从 2.0s
#        重新起算，玩家在视野边缘一进一出就能让 `_spawn_cycle_t` 永远回不到 0 ——
#        分裂怪**在玩家看得见它的时候也不生成**，与需求语义直接矛盾。
#        暂停则只累计「玩家在视野内的时长」，进视野即继续走到触发点。
#     2. **重置等于给了玩家一个无成本的安全位**：只要在触发前跑出视野再回来，
#        就能把周期无限拖后 —— 而这正是需求想消灭的「填满楼层」体验的变体。
#     ⚠ 与口径②的一致性：暂停只作用于「**未开新周期**」的等待段；一旦
#       `_burst_left > 0`，即便玩家离开视野也照打（见 `_update_spawner`）。
#
#   ⚠ 生成小怪的**具体 spawn 动作由外部注入**（`set_minion_spawner`，由 Main.gd 提供），
#     分裂怪只负责**节奏**（何时 spawn 什么 kind、在哪 spawn）。
#     **fail-closed**：未注入 spawner = 不生成 —— 保证其它验证入口 / 正常路径零回归面。
#   ⚠ 性能：`_player_in_sight()` 每物理帧调用一次 → 1 次射线检测（60 次/秒/只）。
#     场上分裂怪恒为 1 只（`_build_floor` 只在第 90 层最大房间实例化 1 个），
#     量级可忽略；父类 `_scan()` 本就每 `ENEMY_SENSE_INTERVAL`(0.3s) 打射线，
#     本条的频率与之同量级。**刻意不加节流**：加了就引入「时滞导致漏判/延迟触发」，
#     而生成节奏是被 `--verify-splitter` 按帧精确断言的，任何时滞都会让断言变脆。
#
# 【碰撞体 / 体型】
#   碰撞盒 24×24 由 `Splitter.tscn` 给出（= 2 × 12 普通僵尸）。
#   程序化精灵 `EnemyArt` 的 `scale = Vector2(2,2)`（16×16 精灵 → 32×32，
#   线性 2× = 面积 4×，正好「体型大 4 倍」），在 `_ready()` 里设。
extends "res://scenes/enemies/Zombie.gd"

## 供 headless 验证读取的标记（避免验证脚本靠 class_name 猜类型）。
## 与 `Brute.gd` 的 `is_brute` 同款：用布尔标记 + 场景节点名，不用 class_name。
var is_splitter: bool = true

## 覆写数值（同 Brute）：⚠ 必须在 `_init()` 而非 `_ready()` 里设——
##   `@export` 赋值发生在 `_ready()` 之前，而父类 `_ready()` 会 `_scan()`。
func _init() -> void:
    move_speed = GameConstants.SPLITTER_SPEED          # 速度一半
    max_hp = GameConstants.SPLITTER_HP                 # 血量 10 倍
    hp = GameConstants.SPLITTER_HP
    attack_range = 0.0                                 # 永不进入 ATTACK
    damage = 0.0                                       # 兜底：就算进了 ATTACK 也无害
    # ⚠ visual_range / audio_range / attack_windup / attack_recovery / attack_interval /
    #   faction **一律不动** —— 刻意继承僵尸的感知/移动参数（「移动逻辑和普通僵尸一致」）。

# ==== R-149 · 周期性生成小怪 ====

## 生成小怪的回调（由 Main.gd 注入，签名 `cb(kind: String, at: Vector2) -> void`）。
## ⚠ **fail-closed**：未注入（空 Callable）→ `_do_burst_spawn()` 直接 return，不生成。
var _minion_spawner: Callable = Callable()

## 生成状态机字段（physics 帧驱动，headless 60Hz 下 2.0s = 120 帧，可精确断言）
var _spawn_cycle_t: float = GameConstants.SPLITTER_SPAWN_INTERVAL   # 距下一周期触发还剩多久
var _burst_left: int = 0                                            # 本周期还剩几次生成
var _burst_gap: float = 0.0                                         # 距下一次生成还剩多久
var _spawned_bursts: int = 0                                        # 已触发的生成次数（探针用）

func set_minion_spawner(cb: Callable) -> void:
    _minion_spawner = cb

## 只读探针：本分裂怪已生成的**小怪总数**（每次生成 = 1 普通 + 1 快速 = 2 只）。
##   ⚠ 只在 spawner 注入后计数（fail-closed 路径 `_do_burst_spawn` 提前 return，不自增）。
func splitter_spawn_count() -> int:
    return _spawned_bursts * GameConstants.SPLITTER_SPAWN_TYPES.size()

func _ready() -> void:
    super._ready()
    # R-149：体型大 4 倍 —— 16×16 精灵 scale 2× = 32×32（线性 2× = 面积 4×）。
    #   `super._ready()` 末尾 `_refresh_art()` 已把 `EnemyArt` 建出来（纹理到位时）。
    var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
    if art != null:
        art.scale = Vector2(2, 2)

func _physics_process(delta: float) -> void:
    super._physics_process(delta)
    if dead or state == State.DEAD:
        return
    _update_spawner(delta)

# R-150 · 「发现玩家」判定 —— **仅视觉**（范围内 且 LOS 通）。
#   ⚠ 取玩家节点的写法照抄父类 `Zombie._scan()`（`get_first_node_in_group("player")`），
#     保持同一口径；**不**缓存节点（玩家可能被 free/替换，缓存会拿到失效引用）。
#   ⚠ 「发现」判定**整体委托**给父类 `axis_visual()`：它是父类已有的只读探针，
#     语义与本需求逐字吻合。**严禁**在这里重写一套距离/LOS 判断 —— 两套口径必然漂移。
#   ⚠ **听觉（`axis_hear`，180px 且穿墙）刻意不参与**：见文件头口径①。
#     玩家在墙后 / 超出 60px 时，本函数返回 false → 不生成。
#   ⚠ 取不到玩家 / 玩家已失效 → **false（fail-closed，不生成）**。
#     宁可「不生成」也不生成：生成器在无 spawner 注入时同样 fail-closed，两者口径一致。
func _player_in_sight() -> bool:
    var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
    if p == null or not is_instance_valid(p):
        return false
    return axis_visual(p)

# 生成节奏状态机（R-150：**仅视觉发现玩家时才推进**）。
#   语义：t=2.0 首次触发 → 立即生成第 1 次 → 0.1s 后再生成 → … → 第 5 次在 t≈2.4 完成
#   → 下一周期 t=4.0。每周期 10 只。
#   【三条分支的优先级（顺序不可调换）】
#     ① `_burst_left > 0` → 本轮已开启 → **无视视野，照旧打完**（用户拍板口径②）。
#     ② 未开周期 且 **看不见**玩家 → **直接 return**：`_spawn_cycle_t` 原值保留（暂停），
#        玩家重新进视野后走完剩余时间即触发。见文件头「为什么暂停而不是重置」。
#     ③ 未开周期 且 **看得见**玩家 → 照旧推进 `_spawn_cycle_t`，到点开新周期。
func _update_spawner(delta: float) -> void:
    # ---- ① 本轮已开启：口径②，照旧打完，**完全不看视野** ----
    if _burst_left > 0:
        _burst_gap -= delta
        if _burst_gap <= 0.0:
            _do_burst_spawn()
            _burst_left -= 1
            if _burst_left <= 0:
                _spawn_cycle_t = GameConstants.SPLITTER_SPAWN_INTERVAL
            else:
                _burst_gap = GameConstants.SPLITTER_SPAWN_GAP
        return
    # ---- ② 看不见玩家：暂停（**不清零、不重置** `_spawn_cycle_t`）----
    if not _player_in_sight():
        return
    # ---- ③ 看得见玩家：照旧推进 / 开新周期 ----
    _spawn_cycle_t -= delta
    if _spawn_cycle_t <= 0.0:
        _burst_left = GameConstants.SPLITTER_SPAWN_BURST
        _burst_gap = 0.0    # 周期触发后**第一次立即生成**

func _do_burst_spawn() -> void:
    if not _minion_spawner.is_valid():
        return
    for kind in GameConstants.SPLITTER_SPAWN_TYPES:
        _minion_spawner.call(kind, global_position)
    _spawned_bursts += 1

## R-149：**覆写**父类的精灵路径 → 本批复用僵尸图，靠 `scale = Vector2(2,2)` 表达「大」。
##   ⚠ **专用 Boss 图是后续美术批，本批不做**（写在这里是为了将来改图只动这一行）。
##   ⚠ 返回值与父类相同（`zombie.png`），覆写的意义在于**把"复用僵尸图"这一决定显式化**，
##     并留下换图的单一改动点（与 `Brute.gd` 覆写 `enemy_sprite_path()` 同一动机）。
func enemy_sprite_path() -> String:
    return ENEMY_SPRITE_DIR + "zombie.png"
