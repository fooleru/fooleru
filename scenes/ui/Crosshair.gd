# Crosshair · 准星 · cp1 阶段 3
# 始终作为光标（隐藏系统箭头）；右键瞄准时切换为"圆环 + 中心红点"样式。
# 坐标：所在 CanvasLayer 无自定义 transform，Node2D.position 即视口坐标。
# R-56：光标用 CONFINED_HIDDEN 锁在窗口内 + 准星位置 clamp 到视口 → 不会跑到屏幕外。
extends Node2D

const COLOR := Color(0.98, 0.85, 0.2, 1)        # 弹药黄（通用十字 / 圆环）
const DOT_COLOR := Color(0.92, 0.22, 0.20, 1)   # 瞄准红点
const GAP := 3.0    # 中心到短线内端（像素）
const LEN := 3.0    # 短线长度（像素）
const TH := 1.0     # 线宽（像素）
const CIRCLE_R := 10.0  # 瞄准圆环半径（像素，右键瞄准时显示，= 原 5 的一倍）

func _ready() -> void:
    # 隐藏系统箭头（用准星代替）并把光标"锁"在窗口内 → 鼠标不会移出屏幕
    Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
    show()

func _process(_delta: float) -> void:
    if Input.get_mouse_mode() != Input.MOUSE_MODE_CONFINED_HIDDEN:
        Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
    # 准星限制在视口内（双保险：即便光标越界，准星也不会跑到屏幕外）
    var vp: Vector2 = get_viewport_rect().size
    position = get_viewport().get_mouse_position().clamp(Vector2.ZERO, vp)
    queue_redraw()

func _draw() -> void:
    if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        # 瞄准样式：圆环 + 中心红点
        draw_arc(Vector2.ZERO, CIRCLE_R, 0.0, TAU, 40, COLOR, TH)
        draw_circle(Vector2.ZERO, 1.0, DOT_COLOR)  # 中心红点 1 像素
    else:
        # 通用样式：开口十字 + 中心小点
        draw_line(Vector2(-GAP - LEN, 0.0), Vector2(-GAP, 0.0), COLOR, TH)
        draw_line(Vector2(GAP, 0.0), Vector2(GAP + LEN, 0.0), COLOR, TH)
        draw_line(Vector2(0.0, -GAP - LEN), Vector2(0.0, -GAP), COLOR, TH)
        draw_line(Vector2(0.0, GAP), Vector2(0.0, GAP + LEN), COLOR, TH)
        draw_rect(Rect2(-0.5, -0.5, 1.0, 1.0), COLOR)
