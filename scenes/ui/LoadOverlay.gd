# 超重三档视觉叠加层 · D-29 / R-46 追加（art-bible §7.1 补丁 + 禁忌 45）
# 职责：在负重条上绘制「满槽刻度(固定) + 轻度溢出斜纹 + 重度警告红描边」
# 仅做绘制，不持有状态；tier 由 HUD._on_load_changed 推入。
extends Control

const COLOR_HATCH := Color("e8e6df")   # 离白对角斜纹（轻度）
const COLOR_WARN := Color("f25c54")    # 警告红描边（重度）
const COLOR_TICK := Color("e8e6df")    # 满槽刻度（离白，固定不随负载移动）
const FILL_W := 44.8                    # = 负重总宽 * 0.8，capacity 刻度位置
const OVER_W := 11.2                    # = 负重总宽 * 0.2，溢出区
const BAR_H := 5.0

var _tier: int = 0

func set_tier(t: int) -> void:
    if t != _tier:
        _tier = t
        queue_redraw()

func _draw() -> void:
    # 满槽刻度：capacity(40wg) 固定 1px 离白竖线，不随负载移动（禁忌 45）
    draw_line(Vector2(FILL_W, 0.0), Vector2(FILL_W, BAR_H), COLOR_TICK, 1.0)
    if _tier == 1:
        # 轻度超重：溢出区对角斜纹（形先于色，不靠变红）
        var x := FILL_W
        var x1 := FILL_W + OVER_W
        while x <= x1:
            draw_line(Vector2(x, BAR_H), Vector2(x + 3.0, 0.0), COLOR_HATCH, 1.0)
            x += 3.0
    elif _tier == 2:
        # 重度超重：整条 1px 警告红描边
        draw_rect(Rect2(0.0, 0.0, FILL_W + OVER_W, BAR_H), COLOR_WARN, false, 1.0)
