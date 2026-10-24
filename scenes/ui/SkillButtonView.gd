# SkillButtonView · 左下角 V 技能（视野扫描）图标按钮 + 时钟状扇形冷却（R-new）
# 方形按钮 + 雷达图标；冷却时按钮上覆盖一圈"时钟"扇形（自 12 点顺时针 = 剩余比例，深色），
#   归零（就绪）时无覆盖、图标全亮。数据由 Main 每帧推送剩余比例。
# ⚠ 只画形状/色块、**无文字** → 不触发 R-128 guard。
extends Node2D
class_name SkillButtonView

const BTN := 16.0             # 按钮边长（px）
var _ratio: float = 0.0       # 剩余冷却比例：0=就绪 .. 1=刚放完

func set_cd(ratio: float) -> void:
	var r: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(r, _ratio):
		return                  # 无变化不重画
	_ratio = r
	queue_redraw()

func _draw() -> void:
	var h := BTN
	# 按钮底 + 边框
	draw_rect(Rect2(0.0, 0.0, h, h), Color(0.09, 0.10, 0.14, 0.88))
	draw_rect(Rect2(0.5, 0.5, h - 1.0, h - 1.0), Color(0.55, 0.58, 0.66, 0.9), false, 1.0)
	var cx := h * 0.5
	var cy := h * 0.5
	# 雷达图标（青色；冷却中变暗）
	var ic: Color = Color(0.30, 0.85, 0.95, 1.0) if _ratio <= 0.0 else Color(0.30, 0.85, 0.95, 0.30)
	draw_arc(Vector2(cx, cy), 5.0, 0.0, TAU, 24, ic, 1.0)
	draw_arc(Vector2(cx, cy), 2.4, 0.0, TAU, 16, ic, 1.0)
	draw_line(Vector2(cx, cy), Vector2(cx + 3.5, cy - 3.5), ic, 1.0)   # 扫描线（指向右上）
	draw_circle(Vector2(cx, cy), 0.9, ic)
	# 扇形冷却覆盖：12 点起、顺时针扫「剩余比例」，深色（扣在图标上）
	if _ratio > 0.002:
		var pts: PackedVector2Array = PackedVector2Array([Vector2(cx, cy)])
		var segs := 20
		var a0 := -PI * 0.5
		for i in segs + 1:
			var a := a0 + TAU * _ratio * (float(i) / float(segs))
			pts.append(Vector2(cx + cos(a) * 7.2, cy + sin(a) * 7.2))
		draw_colored_polygon(pts, Color(0.04, 0.05, 0.08, 0.72))
