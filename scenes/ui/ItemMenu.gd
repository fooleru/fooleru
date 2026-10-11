# ItemMenu · 物品右键上下文菜单（R-71）
# 在背包 / 箱子里的物品图标上按右键弹出，选项由 Main 依据物品类别给出：
#   消耗品 → 使用 ｜ 武器、护甲 → 装备 ｜ 箱子物品 → 移入背包
# 手绘（无图片资源，文本用 GameConstants.ui_font()）；只负责几何 + 绘制 + 命中，动作由 Main 执行。
# 坐标：所在 CanvasLayer 无自定义 transform → 局部坐标 == 视口坐标（320×180），与 Backpack 一致。
extends Node2D

const VIEW_W := 320.0
const VIEW_H := 180.0
const ROW_H := 13.0
const PAD := 3.0
const MIN_W := 56.0

var open: bool = false
var entries: Array = []       # [{"action": String, "label": String}]
var pos: Vector2 = Vector2.ZERO
var hover_i: int = -1

# 面板矩形（夹在视口内，不会画到屏幕外）
func menu_rect() -> Rect2:
	var w := MIN_W
	for e in entries:
		w = maxf(w, 8.0 + float(String(e["label"]).length()) * 8.0)
	var h := PAD * 2.0 + entries.size() * ROW_H
	return Rect2(clampf(pos.x, 0.0, VIEW_W - w), clampf(pos.y, 0.0, VIEW_H - h), w, h)

func row_rect(i: int) -> Rect2:
	var r := menu_rect()
	return Rect2(r.position.x + 1.0, r.position.y + PAD + i * ROW_H, r.size.x - 2.0, ROW_H)

func open_for(at: Vector2, list: Array) -> void:
	if list.is_empty():
		return
	entries = list
	pos = at
	hover_i = -1
	open = true
	queue_redraw()

func close() -> void:
	if not open:
		return
	open = false
	entries = []
	hover_i = -1
	queue_redraw()

# 命中某一行 → 返回该行 action；未命中返回 ""（调用方据 has_point 判"点在菜单外"）
func pick(at: Vector2) -> String:
	if not open:
		return ""
	for i in entries.size():
		if row_rect(i).has_point(at):
			return String(entries[i]["action"])
	return ""

func set_hover(at: Vector2) -> void:
	var h := -1
	if open:
		for i in entries.size():
			if row_rect(i).has_point(at):
				h = i
	if h != hover_i:
		hover_i = h
		queue_redraw()

func _draw() -> void:
	if not open or entries.is_empty():
		return
	var font := GameConstants.ui_font()
	var r := menu_rect()
	draw_rect(r, Color(0.06, 0.07, 0.10, 0.98))
	draw_rect(r, Color(0.62, 0.66, 0.78, 1.0), false, 1.0)
	for i in entries.size():
		var rr := row_rect(i)
		if i == hover_i:
			draw_rect(rr, Color(0.24, 0.27, 0.36, 1.0))
		draw_string(font, Vector2(rr.position.x + 4.0, rr.position.y + 10.0),
			String(entries[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.92, 0.94, 0.98, 1.0))
		if i < entries.size() - 1:
			draw_line(Vector2(rr.position.x, rr.position.y + ROW_H),
				Vector2(rr.position.x + rr.size.x, rr.position.y + ROW_H), Color(0.22, 0.24, 0.30, 1.0), 1.0)
