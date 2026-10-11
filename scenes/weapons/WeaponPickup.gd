extends Area2D
# 武器拾取物（cp2 多武器切片）
# 玩家碰到 → 若未拥有该武器则获得，若已拥有则补满该武器弹量
var weapon_id: String = "mp_133"

func _ready() -> void:
    add_to_group("pickups")
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
    if body != null and body.is_in_group("player") and body.has_method("give_weapon"):
        if _try_take(body):
            queue_free()

# R-80：备弹有了**携带上限**，于是"站在补给上但装不下"成了常态。
#   原来只在 body_entered（首次进入）时尝试一次，玩家站着不动把弹打空后
#   就再也捡不起这个盒子了 —— 补给等于**永久消失**，这是真 bug 而非设计。
#   所以改成：只要玩家还站在范围内就每帧重试，拿到即消失。
#   （每帧成本极低：一次距离/上限比较，且拿到就 queue_free。）
func _process(_delta: float) -> void:
    if not has_overlapping_bodies():
        return
    for b in get_overlapping_bodies():
        if b != null and b.is_in_group("player") and b.has_method("give_weapon"):
            if _try_take(b):
                queue_free()
            return

# 返回是否真的拿到了东西（false = 装不下 → 留在地上）
func _try_take(body: Node) -> bool:
    var added: bool = body.give_weapon(weapon_id)
    if added:
        return true
    # R-74：已拥有该枪 → 补**备弹**（按该枪口径，一盒的量），不再是"弹匣凭空虚满"
    var cal: String = GameConstants.CAL_9X19
    if body.has_method("caliber_of_weapon"):
        cal = body.caliber_of_weapon(weapon_id)
    # ==== R-96：盒容量改为**按口径**取，不再用全局单一常量 ====
    #   ⚠⚠ **这里以前直接写 `GameConstants.AMMO_BOX_ROUNDS`（不分口径）** ——
    #     12×70 盒降到 24 发之后那就是个**真bug**，两个方向都会错：
    #       ① 玩家带 9×19 走到 12×70 补给上：剩余空间只要 ≥ 50 就会被判"装得下"，
    #          但 12×70 一盒只有 24 → 可能装下后仍差一截，或干脆该拒绝却接受；
    #       ② 玩家带 12×70 走到 9×19 补给上：按 24 判定会**误拒**一个明明装得下的整盒。
    #   → 现在统一走 `GameConstants.ammo_box_rounds_of(cal)`：**容量是口径的属性，不是全局的**。
    #     这也天然为将来 5.56 / 7.62 铺好路（那边只要在字典里加一行，本文件零改动）。
    var rounds: int = GameConstants.ammo_box_rounds_of(cal)
    # R-80：**要么整盒装下，要么一颗不装**（这一条硬约束本次**刻意保持不变**）。
    #   ⚠ 这里不能只看 add_reserve 的返回值：它会"有多少塞多少"（**例**：某口径 池 75/120
    #   还能塞 45 发，但一盒是 50 发 → 只塞得下 45），
    #   于是玩家丢了一整盒的补给、只换回部分 —— 和白捡一样是偷玩家物资。
    #   所以先判断剩余空间够不够装**整盒**，不够就原样留在地上。
    #   ⚠ 判定必须用**本口径的盒容量**（rounds）：拿 9×19 的 50 去卡 12×70 的整盒，
    #   等于对霰弹枪额外加了一道「必须空出 50发」的门槛（实际只需 24）→ 也是错的。
    # ⚠ **R-102 注**：上面原举的是"75/120 塞 45 发"的例子，那是 **12×70 盒=50 发**的旧时代
    #   （R-96 已把 12×70 盒降为 **24** 发）。今天要复现"塞得下部分"的场景，
    #   room 应取本口径整盒容量 −1（12×70 是 23/120）→ 已被 `--verify-boxsem` ② / ④ 钉死。
    #   举例保留 45 这个数字只为说明"部分装入"这种形态，**别当成当前口径**。
    if body.has_method("reserve_of") and body.has_method("reserve_cap_of"):
        var room: int = int(body.reserve_cap_of(cal)) - int(body.reserve_of(cal))
        if room < rounds:
            return false
    return int(body.add_reserve(cal, rounds)) > 0
