# FloorSelect · 第 100 层出发点「楼层选择」面板（R-new 2026-10-18 用户需求）
# ==============================================================================
# 【用户需求逐字（初版）】
#   「修改100层的出发点，按F键以后列出所有曾经探索过的楼层（也就是已经生成过的
#     楼层地图），玩家可以选择直接到达该层。」
# 【2026-10-22 改版】① 按钮靠左 + 去掉「>」+ 「99F」标签；② **行优先横向排列**
#   （99F、98F、97F… 从左到右，行满自动换行）；③ A/D 左右、鼠标点击、多列。
# → 站上出发瓦片按 F → 弹出本面板：W/S 上下、A/D 左右、F 前往、Esc 取消；鼠标可点选。
#
# 【横向（行优先 row-major）布局与列数推导（当前内容/宽度/间距）】
#   · 单元格宽 = 按钮(7px, r=3.5) + 按钮→标签间距(8.5px) + 「99F」标签(19px @font8)
#                ≈ 34.5px → 取 **CELL_W = 36px** 槽宽；列间距 COL_GAP = 8px
#   · 面板 PANEL_W = 232px − 左右各 8 = 可用 216px
#   · 每行容量 n：36n + 8(n−1) ≤ 216 → 44n ≤ 224 → n ≤ 5.09 → **每行最多 5 格**
#       （n=5：212≤216 ✓；n=6：256>216 ✗）
#   · ⚠ 想「99F~90F 一行 10 个」不可能：10×36 + 9×8 = 432px > 320 屏幕宽 →
#     按用户要求「容器宽度不足时合理换行」：第一行 99,98,97,96,95；第二行 94…90。
#   · 行数 ROWS = 12 → 每页 5×12 = 60 格；99 层 → 2 页（右上「1/2」）。
#
# 【网格流程】行优先：页内第 p 格 row = p / COLS、col = p % COLS；
#   线性下标 i → 页 = i/60、页内 = i%60。**W/S = 上下行 ±COLS**、**A/D = 左右列 ±1**（行边界不动）。
#   选中格 = 左侧按钮亮起(+内陷+按下扩散) + 淡黄高亮带；无 ">"；标签统一「99F」。
#
# 【⚠ 状态与绘制分离（R-112）】只「画」+ open/close/move_row/move_col/selected/click_at；
#   状态变更（何时开、传送到哪层）全部在 Main。
# ==============================================================================
extends Control

# ---- 几何 / 配色（全部字面量，禁止从别处推导 —— R-96 教训）----
const W := 320.0              # 全屏宽（内部分辨率）
const H := 180.0              # 全屏高
const DIM_ALPHA := 0.55       # 全屏底透明度
const PANEL_X := 44.0         # 面板左上角 x
const PANEL_Y := 10.0         # 面板左上角 y
const PANEL_W := 232.0        # 面板宽 -> x ∈ [44, 276]
const PANEL_H := 160.0        # 面板高 -> y ∈ [10, 170]
const PANEL_BG := Color(0.10, 0.12, 0.16, 0.96)   # 面板底：深蓝黑，不透明
const PANEL_BORDER := Color(0.99, 0.90, 0.35, 1.0) # 边框：暖黄（可交互）
const TITLE_COLOR := Color(0.99, 0.90, 0.35, 1.0)  # 标题：暖黄
const BODY_COLOR := Color(0.92, 0.92, 0.94, 1.0)   # 正文：近白
const DIM_COLOR := Color(0.55, 0.57, 0.62, 1.0)    # 未探索层 / 页码：灰
const KEY_COLOR := Color(0.55, 0.95, 1.00, 1.0)    # 按键提示：亮青
const CURSOR_COLOR := Color(0.99, 0.90, 0.35, 0.22) # 光标格高亮带（半透明黄）
const FONT_SIZE_TITLE := 10
const FONT_SIZE_BODY := 8
const PRESS_ANIM_T := 0.18     # 电梯按钮按下动效时长（秒）

# ---- 行优先网格（推导见文件头；5 列 = 当前宽度下每行最大格数）----
const COLS := 5               # 每行格数（36*5 + 8*4 = 212 ≤ 216）
const ROWS := 12              # 每页行数（列表 28..148，行高 10）
const PER_PAGE := 60          # 每页格数 = COLS * ROWS
const CELL_W := 36.0          # 单元格槽宽（按钮 + 间距 + 「99F」标签）
const COL_GAP := 8.0          # 列间距
const ROW_H := 10.0           # 行高（px）—— 10 ≥ 字号 8，行间不重叠
const LIST_TOP := 28.0        # 网格首行基线相对面板顶
const LIST_LEFT := 8.0        # 网格左边距（面板内相对 x）

# 单元格内部（相对单元格左）
const BTN_X := 14.0           # 左电梯按钮中心 x
const BTN_R := 3.5            # 按钮半径
const LABEL_X := 26.0         # 「99F」标签 x

var _floors: Array = []       # [{"floor": int, "explored": bool}, ...]（降序，Main 喂）
var _cursor: int = 0          # 线性选中下标（网格位置由它派生）
var _press_t: float = 0.0     # 按下动效剩余时间（_process 逐帧衰减）
var _hover_idx: int = -1      # 鼠标悬停格（-1=无；仅视觉）

func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不吃鼠标（键盘 + Main._input 命中）
	process_mode = Node.PROCESS_MODE_ALWAYS       # 面板开着=游戏暂停，动效/音效仍需照跑
	visible = false

# 打开面板（重置光标到首位）。
func open(floors: Array) -> void:
	_floors = floors
	_cursor = 0
	_press_t = PRESS_ANIM_T   # 打开时首项按钮亮一下
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

# 上下移动（W/S）：行 ±1 = 线性 ±COLS（跨页自动翻页）；越界不动。
func move_row(dir: int) -> void:
	if _floors.is_empty():
		return
	var target: int = _cursor + dir * COLS
	if target < 0 or target >= _floors.size():
		return
	_cursor = target
	_press_t = PRESS_ANIM_T
	Sfx.play("ui_confirm", -7.0, 1.35)
	queue_redraw()

# 左右移动（A/D）：同页同行内换列（±1）；行边界 / 末行不齐则不动。
func move_col(dir: int) -> void:
	if _floors.is_empty():
		return
	var total: int = _floors.size()
	var page_start: int = (_cursor / PER_PAGE) * PER_PAGE
	var pos: int = _cursor - page_start
	var row: int = pos / COLS
	var col: int = pos % COLS
	var new_col: int = col + dir
	if new_col < 0 or new_col >= COLS:
		return
	var new_idx: int = page_start + row * COLS + new_col
	if new_idx >= total:
		return
	_cursor = new_idx
	_press_t = PRESS_ANIM_T
	Sfx.play("ui_confirm", -7.0, 1.35)
	queue_redraw()

# 鼠标点击选中（local_pos = 设计空间坐标）；命中某格 → 光标移过去，返回 true。
func click_at(local_pos: Vector2) -> bool:
	var idx: int = _cell_at(local_pos)
	if idx < 0:
		return false
	_cursor = idx
	_press_t = PRESS_ANIM_T
	Sfx.play("ui_confirm", -7.0, 1.35)
	queue_redraw()
	return true

# 鼠标悬停（local_pos）：记录悬停格用于视觉反馈（不改变选中）。
func set_hover(local_pos: Vector2) -> void:
	var idx: int = _cell_at(local_pos)
	if idx != _hover_idx:
		_hover_idx = idx
		queue_redraw()

# R-new（2026-10-22）：按下动效逐帧衰减（process_mode=ALWAYS → 暂停时照跑）
func _process(delta: float) -> void:
	if _press_t > 0.0:
		_press_t = maxf(0.0, _press_t - delta)
		queue_redraw()

# 当前选中层号（空列表返回 -1）
func selected() -> int:
	if _floors.is_empty():
		return -1
	return int((_floors[_cursor] as Dictionary).get("floor", -1))

# 当前列表（verify 断言用）
func floors() -> Array:
	return _floors

# 设计坐标 → 网格下标（行优先；无命中 / 列间隙 / 超出总层数 → -1）
func _cell_at(local_pos: Vector2) -> int:
	var total: int = _floors.size()
	if total == 0:
		return -1
	var gx: float = local_pos.x - (PANEL_X + LIST_LEFT)
	var gy: float = local_pos.y - (PANEL_Y + LIST_TOP - ROW_H + 2.0)
	if gx < 0.0 or gy < 0.0:
		return -1
	var col: int = int(gx / (CELL_W + COL_GAP))
	var row: int = int(gy / ROW_H)
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return -1
	if gx - float(col) * (CELL_W + COL_GAP) > CELL_W:
		return -1
	var page: int = _cursor / PER_PAGE
	var idx: int = page * PER_PAGE + row * COLS + col   # 行优先
	if idx < 0 or idx >= total:
		return -1
	return idx

# 某层的格中心（设计坐标；与 _cell_at 互为逆，行优先）
func cell_center(idx: int) -> Vector2:
	var page_start: int = (idx / PER_PAGE) * PER_PAGE
	var pos: int = idx - page_start
	var row: int = pos / COLS
	var col: int = pos % COLS
	return Vector2(
		PANEL_X + LIST_LEFT + float(col) * (CELL_W + COL_GAP) + CELL_W * 0.5,
		PANEL_Y + LIST_TOP + float(row) * ROW_H - ROW_H * 0.5)

# 单个楼层按钮：选中=亮起+内陷+外圈(+按下扩散光环)；未选=暗灰
func _draw_button(cx: float, cy: float, sel: bool) -> void:
	var c := Vector2(cx, cy)
	if sel:
		if _press_t > 0.0:
			var bk: float = _press_t / PRESS_ANIM_T
			draw_circle(c, BTN_R + 3.0 * (1.0 - bk) + 2.0, Color(0.99, 0.90, 0.35, 0.35 * bk))
		draw_circle(c, BTN_R, Color(0.99, 0.90, 0.35, 1.0))
		draw_circle(c, BTN_R - 1.4, Color(0.55, 0.45, 0.18, 1.0))   # 内陷 = 按下感
		draw_arc(c, BTN_R + 1.3, 0.0, TAU, 14, Color(1.0, 0.97, 0.70, 1.0), 1.0)
	else:
		draw_circle(c, BTN_R, Color(0.20, 0.23, 0.28, 1.0))
		draw_arc(c, BTN_R, 0.0, TAU, 14, Color(0.40, 0.44, 0.50, 1.0), 1.0)

func _draw() -> void:
	if not visible:
		return
	# 全屏半透明底
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, DIM_ALPHA))
	# 面板
	draw_rect(Rect2(PANEL_X, PANEL_Y, PANEL_W, PANEL_H), PANEL_BG)
	draw_rect(Rect2(PANEL_X, PANEL_Y, PANEL_W, PANEL_H), PANEL_BORDER, false, 1.0)
	var font := GameConstants.ui_font()
	# 标题（面板顶部居中）
	draw_string(font, Vector2(PANEL_X, PANEL_Y + 13), Loc.t("depart.select.title"),
		HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, FONT_SIZE_TITLE, TITLE_COLOR)
	# 当前页（线性下标派生）
	var total: int = _floors.size()
	var page: int = _cursor / PER_PAGE
	var pages: int = maxi(1, (total + PER_PAGE - 1) / PER_PAGE)
	# 行优先网格：99F、98F、97F… 从左到右，行满换行
	for p in PER_PAGE:
		var idx: int = page * PER_PAGE + p
		if idx >= total:
			break
		var row: int = p / COLS
		var col: int = p % COLS
		var cx: float = PANEL_X + LIST_LEFT + float(col) * (CELL_W + COL_GAP)
		var ry: float = PANEL_Y + LIST_TOP + float(row) * ROW_H
		# 选中格高亮带（无 ">" 标记）
		if idx == _cursor:
			draw_rect(Rect2(cx + 7.0, ry - ROW_H + 2.0, CELL_W + 1.0, ROW_H), CURSOR_COLOR)
		elif idx == _hover_idx:
			# 鼠标悬停格淡高亮（区别于选中的亮黄带）
			draw_rect(Rect2(cx + 7.0, ry - ROW_H + 2.0, CELL_W + 1.0, ROW_H), Color(1.0, 1.0, 1.0, 0.08))
		# 左电梯按钮
		_draw_button(cx + BTN_X, ry - 3.5, idx == _cursor)
		# 右侧统一「99F」高度标签（探索=白、未探索=灰）
		var e: Dictionary = _floors[idx] as Dictionary
		var explored: bool = bool(e.get("explored", false))
		var label: String = Loc.t("depart.select.row") % int(e.get("floor", 0))
		var col_c: Color = BODY_COLOR if explored else DIM_COLOR
		draw_string(font, Vector2(cx + LABEL_X, ry), label,
			HORIZONTAL_ALIGNMENT_LEFT, CELL_W, FONT_SIZE_BODY, col_c)
	# 空列表兜底
	if total == 0:
		draw_string(font, Vector2(PANEL_X, PANEL_Y + LIST_TOP + ROW_H), Loc.t("depart.select.empty"),
			HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, FONT_SIZE_BODY, DIM_COLOR)
	# 页码指示（右上角；仅多页时显示）
	if pages > 1:
		draw_string(font, Vector2(PANEL_X, PANEL_Y + 13), "%d/%d" % [page + 1, pages],
			HORIZONTAL_ALIGNMENT_RIGHT, PANEL_W - 6.0, FONT_SIZE_BODY, DIM_COLOR)
	# 按键提示（下部居中）
	draw_string(font, Vector2(PANEL_X, PANEL_Y + 153), Loc.t("depart.select.keys"),
		HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, FONT_SIZE_BODY, KEY_COLOR)
