# Backpack · 背包 / 容器界面
#   R-65 新增 / R-67：拖拽 + Ctrl 快速移动 + 悬停显示物品名 / R-69：左右两栏各占一半 + 两栏格子同尺寸
#   R-71：物品支持**占格**（w×h 矩形，如 MP5 冲锋枪占 3×2 = 6 格）——按物品矩形布局 / 命中 / 绘制
# 挂在 CanvasLayer（layer=12，process_mode=WHEN_PAUSED）下，用 `_draw()` 手绘（无图片资源）。
# 布局（视口 320×180）：
#   左栏 = 背包（x 2..158，宽 156 ≈ 半屏）｜ 右栏 = 箱子（x 162..318，宽 156 ≈ 半屏）
#   **左栏（R-111 起）**：标题行 → **装备栏（两行两列：行1=武器1+护甲，行2=武器2+背包）**
#                       → 12×8 网格（格子边长 10px，水平居中）→ 底部快捷栏
#   **右栏（R-111 起）**：标题行 → 12×10 网格（**向上靠**= 紧贴标题行，底部留白）→ （无快捷栏）
# ⚠⚠ **R-111：装备槽索引按「视觉阅读顺序」重排**（这是本批最易点错槽的一处，见下方索引表）。
# ⚠⚠ **R-101：左右两栏的行数与纵向起点必须分开**（旧代码两者共用 `GRID_Y` / `GRID_ROWS`）。
#   原因：用户只要求把**左栏（玩家背包）**缩成 10×10 并"靠下"，
#   而**右栏（箱子）必须保持 10×15** —— 否则箱子容量从 150 格掉到 100 格，
#   那是被用户明确排除的平衡改动（用户原话只提"物品栏"）。
#   → `GRID_ROWS/INV_GRID_Y`（左，玩家背包，R-111 起 **8 行**，下移到两行装备栏之下）
#     与 `CONT_ROWS/CONT_GRID_Y`（右，箱子，R-111 起 **10 行**、起点 15「向上靠」）
#     是**两套完全独立**的常量。R-111 起右栏纵向起点也不再借用左栏的 `GRID_Y`。
# 交互（由 Main 驱动，本脚本只负责：几何 + 占格 + 命中测试 + 绘制）
extends Node2D

const VIEW_W := 320.0
const VIEW_H := 180.0
const PAD := 4.0
const HEADER_H := 13.0
const QUICK_H := 11.0
# 两栏共用同一格子尺寸（单一权威源 = GameConstants.INV_SLOT）
const SLOT := GameConstants.INV_SLOT
const GRID_COLS := GameConstants.INV_COLS      # 12（R-111 用户逐字「左侧玩家物品栏改为 12x8 格」）
const GRID_ROWS := GameConstants.INV_ROWS      # 8 （R-111 用户逐字「12x8」）
const GRID_W := GRID_COLS * SLOT               # 120
const GRID_H := GRID_ROWS * SLOT               # 80
# 右栏（箱子）：R-111 用户逐字「右侧箱子改为 12x10 格并且向上靠」
const CONT_COLS := GameConstants.CONT_COLS    # 12
const CONT_ROWS := GameConstants.CONT_ROWS    # 10
const CONT_W := CONT_COLS * SLOT              # 120
const CONT_H := CONT_ROWS * SLOT              # 100
# 两栏面板：等宽，关于视口中线（x=160）对称
const PANEL_W := 156.0
const PANEL_Y := 2.0
const PANEL_H := 176.0
const PANEL_LX := 2.0
const PANEL_RX := VIEW_W - PANEL_LX - PANEL_W  # 162
# R-new：排序按钮（点击按「类型 → 大小 → 重量」整理背包）。画在**左栏标题行右端**，
#   横向还有富余（标题文字远未占满 156px 宽），不挤占已用满的网格/装备区（见文件头"余 6px"）。
const SORT_BTN_W := 24.0
const SORT_BTN_H := 9.0
const SORT_BTN_X := PANEL_LX + PANEL_W - PAD - SORT_BTN_W   # 右对齐到左栏面板内
const SORT_BTN_Y := PANEL_Y + 2.0
func sort_button_rect() -> Rect2:
	return Rect2(SORT_BTN_X, SORT_BTN_Y, SORT_BTN_W, SORT_BTN_H)

# R-new（2026-10-22 用户需求）：箱子（右栏）排序按钮 —— 与左栏同款，画在**右栏标题行右端**。
const CONT_SORT_BTN_X := PANEL_RX + PANEL_W - PAD - SORT_BTN_W   # 右对齐到右栏面板内
const CONT_SORT_BTN_Y := PANEL_Y + 2.0
func cont_sort_button_rect() -> Rect2:
	return Rect2(CONT_SORT_BTN_X, CONT_SORT_BTN_Y, SORT_BTN_W, SORT_BTN_H)
const GRID_Y := PANEL_Y + HEADER_H             # 15（左栏纵向起点基准；右栏**不再**用它）
const GRID_LX := PANEL_LX + (PANEL_W - GRID_W) * 0.5   # 20（120 在 156 内居中）
const GRID_RX := PANEL_RX + (PANEL_W - CONT_W) * 0.5   # 180
# ⚠⚠ **R-111：右栏网格纵向起点 `CONT_GRID_Y` 独立成常量**（R-101 只拆了行数没拆起点，
#   当时左右两栏共用 `GRID_Y`；本次把「向上靠」这条用户要求落成**独立常量**，
#   避免将来改左栏纵向起点时**连带把右栏一起挪动**）。
#   语义 = **向上靠**：紧贴面板标题行下沿（PANEL_Y + HEADER_H），
#   箱子栏底部（178）到网格底（115）的 63px **全部留白，不填任何东西**。
const CONT_GRID_Y := PANEL_Y + HEADER_H       # 15（向上靠 = 紧贴标题行）
# ==== R-101：装备栏（GEAR）几何 ====
# 用户需求逐字：「上方空出来的位置显示装备栏。装备栏包括两个武器槽位（对应的快捷键是'1'、'2'），
#   1个护甲槽位，一个背包槽位。」
# ⚠ **320×180 的空间账（本批最紧的一处布局，逐项列明以便复核）**：
#   面板内高 = PANEL_H - HEADER_H = 176 - 13 = **163px**（y 15..178）
#   装备栏需要「标题 8 + 槽高 40 + 间隔 2」= **50px**
#   网格需要 10 行 × 10px = **100px**
#   底部快捷栏 11px + 间隔 2 = **13px**
#   合计 50 + 100 + 13 = **163px** —— **恰好用满，一点不剩**。
#   ⚠ 这意味着**不能再往左栏塞任何东西**（R-78/R-80 的"挤出屏幕"教训）：
#     任何新增的左栏元素都必须先从这 163px 里挪出空间，否则会越出 y=178。
#     `--verify-gear` ② 用「装备栏底 ≤ 网格顶 且 网格底 + 快捷栏 ≤ 178」把这条钉死。
# ⚠⚠ **R-111：装备槽不再是统一尺寸**
#   武器槽 = **5×3 格 = 50×30px**（用户逐字「武器最大占格5x3」）→ 上界，不是"当前最大武器"
#   护甲槽 / 背包槽 = **2×2 格 = 20×20px**（用户逐字「护甲和背包都是2x2」）
#   → `gear_slot_rect()` 必须**按槽的种类**取尺寸，不能再像 R-101 那样"四槽同尺寸"。
const GEAR_SLOT_W := GameConstants.GEAR_SLOT_COLS * SLOT   # 武器槽宽 5 格 = 50px
const GEAR_SLOT_H := GameConstants.GEAR_SLOT_ROWS * SLOT   # 武器槽高 3 格 = 30px
const GEAR_MINOR_W := GameConstants.GEAR_MINOR_COLS * SLOT # 护甲/背包槽宽 2 格 = 20px
const GEAR_MINOR_H := GameConstants.GEAR_MINOR_ROWS * SLOT # 护甲/背包槽高 2 格 = 20px
const GEAR_GAP := 2.0
# ---- 两行两列的行内构成（每行 = 标签 + 武器槽 + 标签 + 小槽）----
# ⚠ **标签画在槽的左侧**（R-101 是画在槽**上方**；两行布局下"上方"是上一行的槽，
#   标签会与上一行槽重叠 —— 故R-111 改为**左侧**，这是两行布局的必然要求）。
const GEAR_LBL_W := 20.0        # 「武器1」标签宽（3 字 @ 字号 7）
const GEAR_MINOR_LBL_W := 16.0  # 「护甲」/「背包」标签宽（2 字 @ 字号 7）
const GEAR_COL_GAP := 4.0       # 武器列与小槽列之间的额外列间距
# 每行总宽 = 20(标签) + 2 + 50(武器槽) + 4(列距) + 16(标签) + 2 + 20(小槽) = 114px
const GEAR_ROW_W := GEAR_LBL_W + GEAR_GAP + GEAR_SLOT_W + GEAR_COL_GAP \
	+ GEAR_MINOR_LBL_W + GEAR_GAP + GEAR_MINOR_W# 114
const GEAR_LX := PANEL_LX + (PANEL_W - GEAR_ROW_W) * 0.5  # 2 + 21 = 23（行内水平居中）
# ⚠ **R-111 删除了 8px 的「装备」组标题行**（`GEAR_TITLE_H`）。
#   删除理由（三条，缺一不可）：
#     ① **空间**：左栏可用 = PANEL_H(176) - HEADER_H(13) - QUICK_H(11) = 152px；
#        两行装备栏(30+2+30=62) + 间隔2 + 12×8 网格(80) = **146px**，
#        余**6px**。而标题行占 8px → 需要 154px，**溢出 2px**（8 > 6，压不下来）。
#     ② **信息量为零**：两行布局下每个槽都已带自己的标签（武器1/护甲/武器2/背包），
#        "装备"这个组标题没有补充任何玩家读不到的信息。
#     ③ **不违反边界**：删的是**冗余元素**，**不是**压缩字号或间距
#        （标签字号仍 7、槽尺寸仍按用户逐字的 5×3 / 2×2、间隔仍 2px）。
#   ⚠ 若将来要求恢复该标题，必须同时把左栏某处的 8px 腾出来（例如网格 8→7 行），
#     **不要**靠缩小间距硬塞回去。
const GEAR_ROW1_Y := PANEL_Y + HEADER_H       # 15：第 1 行顶（紧接面板标题行）
const GEAR_ROW2_Y := GEAR_ROW1_Y + GEAR_SLOT_H + GEAR_GAP# 47：第 2 行顶
const GEAR_BOTTOM := GEAR_ROW2_Y + GEAR_SLOT_H             # 77
# ⚠ 网格因此下移到 79（= GEAR_BOTTOM + 2）。**右栏不受影响**（见上方 CONT_GRID_Y）。
const INV_GRID_Y := GEAR_BOTTOM + GEAR_GAP# 79
# 垂直落位自检（供断言与人工复核，R-111 全部字面量）：
#   行1 15..45 ｜ 行2 47..77 ｜ 网格 79..159 ｜ 快捷栏 161..172 ｜ 面板底 178 → **余 6px**
# 颜色
const BG := Color(0.09, 0.10, 0.14, 0.95)
const BORDER := Color(0.45, 0.48, 0.58, 1)
const SLOT_BG := Color(0.16, 0.17, 0.22, 1)
const SLOT_LINE := Color(0.30, 0.32, 0.40, 1)
const ITEM_LINE := Color(0.12, 0.13, 0.17, 1)
const TEXT := Color(0.92, 0.94, 0.98, 1)
const DIM := Color(0.70, 0.72, 0.80, 1)
const TIP_BG := Color(0.05, 0.05, 0.08, 0.95)
const TIP_BORDER := Color(0.75, 0.78, 0.88, 1)
# R-111：悬停提示框高度（名字行14 + 说明行 9 = 23；无说明时只有 14）
const TIP_H := 14.0
const TIP_DESC_H := 9.0
# R-101：装备栏专用色（空槽比背包格更暗，让"这里可以放东西"一眼可读）
const GEAR_EMPTY_BG := Color(0.12, 0.13, 0.17, 1)
const GEAR_SLOT_LINE := Color(0.38, 0.42, 0.52, 1)
const GEAR_ACCENT := Color(0.95, 0.78, 0.35, 1)   # 当前手持的武器槽描边（金）

var cur_load: float = 0.0
# R-89 补修：40.0 → 引用单一权威源。
#   旧值是写死的 `40.0`，与 `GameConstants.CARRY_CAPACITY` **脱钩**。R-89 把上限拍到 60
#   之后它就成了一个**静默错误源**：`_draw()`（下方 `_draw_panel(..., "负重 %.1f / %.0f")`）**无条件**读它，
#   而 `_draw` 是绘制回调、任何时刻 `queue_redraw` 都可能触发。
#   平时看不出问题，因为 `Main._open_backpack()` 每次开包都会覆盖它；
#   但只要有任何一条路径在**没走 `_open_backpack`** 的情况下重绘背包（初始化帧 / 未来新增的重绘路径），
#   就会画出「负重 14.3 / **40**」而真实上限是 **60** —— 玩家看到的是错的，且不会报错。
#   本工程既有写法就是直接引用 GameConstants（同文件第 17 行 `const SLOT := GameConstants.INV_SLOT`），
#   autoload 在脚本里可直接访问，**无需 preload、无需新增 autoload**。
#   ⚠ 本行是**默认值**，`Main._open_backpack()` 仍会覆盖它 —— 覆盖是有意保留的
#     （背包是纯展示层，不该自己算负重；权威值始终来自 GameConstants）。
var max_load: float = GameConstants.CARRY_CAPACITY
# ⚠ R-101 补注：默认值**刻意仍是 `CARRY_CAPACITY`（裸装 60），不是 80**。
#   `Backpack` 是纯展示层：它拿不到 `Player`，也不知道玩家穿没穿双肩包。
#   `Main._open_backpack()` 会用 `player.carry_capacity()` 覆盖它（裸装 60 / 穿包 80）。
#   若这里写死 80，"没穿背包"的绘制路径（初始化帧 / 未来新增的重绘路径）就会画错 ——
#   那正是 R-89 修掉的"写死 40"那类 bug 的**同构复发**。
#   `--verify-loadout2 ⑦-a`（全新实例默认值 == CARRY_CAPACITY）本批未改，仍钉死这条。
var items: Array = []            # 玩家背包物品（Dictionary；与 Main._inv 共享引用）
var container_items: Array = []  # 箱子物品
var container_open: bool = false
var hover_name: String = ""      # 悬停物品名（空=不显示提示）·R-67 起
# ⚠ R-111：悬停物品的**简要说明**（第 2 行）。R-67 只有名字，用户逐字要求
#   「鼠标移动到物品上方时，除了物品名称还要有物品的简要说明，比如恢复多少 HP，多少饥饿值」
#   （用户原话里的 "HP" 是口语；⚠ R-117 起界面上一律显示「回血」—— 见 `Loc` 表 `backpack.desc_heal`）。
#   纯展示字段，由 `Main._update_hover()` 从 `hover_test()` 的结果经 `item_desc()` 填入。
var hover_desc: String = ""     # 悬停说明（空=该物品无可显示的说明，只显示名字）
var hover_pos: Vector2 = Vector2.ZERO
var drag_item: Dictionary = {}    # 拖拽中的物品（空=未在拖拽）
var drag_pos: Vector2 = Vector2.ZERO

# ---------- 占格（R-71） ----------
func item_w(it: Dictionary) -> int:
	return maxi(1, int(it.get("w", 1)))

func item_h(it: Dictionary) -> int:
	return maxi(1, int(it.get("h", 1)))

# 物品占用的格数（MP5 = 3×2 = 6）
func item_slots(it: Dictionary) -> int:
	return item_w(it) * item_h(it)

# 占位表："x,y" → true。exclude 用于"自己不算占位"（移动 / 重新放置时）
func _occupancy(list: Array, exclude: Dictionary = {}) -> Dictionary:
	var occ := {}
	for it in list:
		if it == exclude or not it.has("gx") or not it.has("gy"):
			continue
		var gx: int = int(it.get("gx", 0))
		var gy: int = int(it.get("gy", 0))
		for dy in item_h(it):
			for dx in item_w(it):
				occ["%d,%d" % [gx + dx, gy + dy]] = true
	return occ

# 行优先找一块 w×h 的空位；找不到返回 (-1,-1)
# ⚠ R-101：`rows` 必须**按栏传入**（玩家背包 10 行 / 箱子 15 行）。
#   旧代码这里直接用全局 `GRID_ROWS`，两栏共用 —— 拆分行数后若不改，
#   在箱子里找位置会**只搜前 10 行**，箱子第 11~15 行会变成"放不下"的死区。
#   默认值 = `GRID_ROWS`（玩家背包），箱子的调用方必须显式传 `CONT_ROWS`。
# ⚠⚠ **已知隐患（只记录，本批不改代码）：列数是全局共用的，行数才是参数**
#   下面 `x` 的循环上界用的是 `GRID_COLS`（**玩家背包**的列数），
#   而 `y` 的循环上界用参数 `rows`。也就是说 `find_free()` **只按调用方传入的行数分栏，
#   不分栏 —— 列数一律按 `GRID_COLS` 算**。
#   · 为什么现在**恰好正确**：R-111 把两栏都设成 12列（INV_COLS == CONT_COLS == 12），
#     所以箱子借用背包的列数不会出错。
#   · ⚠ **什么时候会错**：若将来只改其中一栏的列数（例如把箱子改成 8 列），
#     箱子找位置会按 12 列算 → 能塞下但在第 9~12 列的物品**画到面板外**，
#     且`cont_item_rect()` 会算到面板外 —— 属于**静默错位**，不报错。
#   · **正确修法（不在本批范围内）**：给 `find_free()` 加一个 `cols` 参数，
#     调用方按所在栏传 `GRID_COLS` / `CONT_COLS`（与 `rows` 参数对称）。
#   · 本批**刻意不改**：一是超出本批授权，二是"只加注释"能让下一个改这里的人
#     一眼看到前提条件，而不是等到画面错位才回头找。
func find_free(occ: Dictionary, w: int, h: int, rows: int = -1) -> Vector2i:
	#⚠ `rows` 只影响纵向（分栏）；横向**恒用 GRID_COLS** —— 见上方"已知隐患"注释。
	var n_rows: int = rows if rows > 0 else GRID_ROWS
	for y in range(0, n_rows - h + 1):
		for x in range(0, GRID_COLS - w + 1):
			var ok := true
			for dy in h:
				for dx in w:
					if occ.has("%d,%d" % [x + dx, y + dy]):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

# 把 it 放进 list：成功则写入 gx/gy 并返回 true；放不下返回 false（不改动 it）
# ⚠ R-101：`rows` 语义同 `find_free` —— 箱子必须传 `CONT_ROWS`。
func try_place(list: Array, it: Dictionary, rows: int = -1) -> bool:
	var p := find_free(_occupancy(list, it), item_w(it), item_h(it), rows)
	if p.x < 0:
		return false
	it["gx"] = p.x
	it["gy"] = p.y
	return true

# 给列表里"还没有位置"的物品补位置（行优先，保持列表顺序 = 放置顺序）
func ensure_placement(list: Array, rows: int = -1) -> void:
	for it in list:
		if it.has("gx") and it.has("gy"):
			continue
		if not try_place(list, it, rows):
			it["gx"] = 0      # 极端：放不下 → 归零（原型保护，不至于没有坐标）
			it["gy"] = 0

# 剩余空格数（诊断 / 验证用）。⚠ R-101：同样按栏算（箱子传 CONT_ROWS）。
func free_slots(list: Array, rows: int = -1) -> int:
	var n_rows: int = rows if rows > 0 else GRID_ROWS
	return GRID_COLS * n_rows - _occupancy(list).size()

# ---------- 几何 / 命中测试 ----------
# 原始格子矩形（第 i 格，不涉及物品）
func inv_slot_rect(i: int) -> Rect2:
	var col: int = i % GRID_COLS
	var row: int = i / GRID_COLS
	return Rect2(GRID_LX + col * SLOT, INV_GRID_Y + row * SLOT, SLOT, SLOT)

func cont_slot_rect(i: int) -> Rect2:
	var col: int = i % CONT_COLS
	var row: int = i / CONT_COLS
	return Rect2(GRID_RX + col * SLOT, CONT_GRID_Y + row * SLOT, SLOT, SLOT)

# 物品矩形（按其占格 w×h 与位置 gx/gy）
func inv_item_rect(it: Dictionary) -> Rect2:
	return Rect2(GRID_LX + int(it.get("gx", 0)) * SLOT, INV_GRID_Y + int(it.get("gy", 0)) * SLOT,
		item_w(it) * SLOT, item_h(it) * SLOT)

func cont_item_rect(it: Dictionary) -> Rect2:
	return Rect2(GRID_RX + int(it.get("gx", 0)) * SLOT, CONT_GRID_Y + int(it.get("gy", 0)) * SLOT,
		item_w(it) * SLOT, item_h(it) * SLOT)

# ==== R-101：装备栏（GEAR）几何与命中 ====
# ⚠⚠⚠ **R-111 槽位索引按「视觉阅读顺序」重排（用户两行布局的直接后果）**
#用户逐字：「装备栏改成两行，第一行左侧为武器1+护甲，第二行是武器2+背包」
#   → 表格化（**全工程唯一定义**，Main / 验证 / 绘制都按这套编号）：
#
#   ┌─────────────┬─────────────┐  y = 15..45（第 1 行）
#   │ 槽 0 武器1  │ 槽 1  护甲  │
#   ├─────────────┼─────────────┤  y = 47..77（第 2 行）
#   │ 槽 2 武器2  │ 槽 3  背包  │
#   └─────────────┴─────────────┘
#
# ⚠⚠ **为什么"武器槽不再连续"是本批最大的坑（三处，逐个都会静默出错）**：
#   R-101 是「4 槽横排」，武器槽恰好是 0/1（连续），于是
#   **装备槽号 == `player.weapons[]` 数组下标** —— 这是一个**巧合**，不是契约。
#   改成两行两列后武器槽变成 **0 与 2**，两者**不再相等**：
#     🔴坑 1 `Player.equip_weapon_to_slot(wid, slot)` 的第二参是**武器数组下标**。
#            若把装备槽号 2 直接传进去 → `weapons.size()` 只有 2 → 走"追加"分支
#            → **凭空多出第三把枪**（数组可以无限增长，`GEAR_WEAPON_SLOTS` 拦不住它）。
#     🔴 坑 2 `_sync_gear_to_backpack()` 里`g[i] = p`（i 是 weapons 循环下标）
#            → weapons[1]（MP5）会被写进 `g[1]`，而`g[1]` 现在是**护甲槽**
#            → 表现为「MP5 画在护甲槽上、且护甲槽点不动」，**且不报任何错**。
#     🔴 坑 3 `backpack.gear_active = player.weapon_index`（金色描边）
#            → weapon_index=1 时会高亮**护甲槽**（槽 1），而不是武器2 槽。
#   → **处置：本文件下方 `gear_weapon_index_of()` / `gear_slot_of_weapon_index()`
#     是唯一的转换入口；任何调用点都只准走这两个函数，禁止再出现裸数字换算。**
#     断言见 `--verify-uibox` ④（kind ↔ 位置）与 ⑤（点击判定走对分支）。
const GEAR_SLOT_W1 := 0        # 第 1 行左（快捷键 '1'）
const GEAR_SLOT_ARMOR := 1     # 第 1 行右
const GEAR_SLOT_W2 := 2        # 第 2 行左（快捷键 '2'）
const GEAR_SLOT_PACK := 3      # 第 2 行右
const GEAR_SLOT_COUNT := 4
# 槽 i 的矩形（两行两列；武器槽 50×30、护甲/背包槽 20×20，行内**顶对齐**）
func gear_slot_rect(i: int) -> Rect2:
	match i:
		GEAR_SLOT_W1:
			return Rect2(GEAR_LX + GEAR_LBL_W + GEAR_GAP, GEAR_ROW1_Y, GEAR_SLOT_W, GEAR_SLOT_H)
		GEAR_SLOT_ARMOR:
			return Rect2(GEAR_LX + GEAR_LBL_W + GEAR_GAP + GEAR_SLOT_W + GEAR_COL_GAP
				+ GEAR_MINOR_LBL_W + GEAR_GAP, GEAR_ROW1_Y, GEAR_MINOR_W, GEAR_MINOR_H)
		GEAR_SLOT_W2:
			return Rect2(GEAR_LX + GEAR_LBL_W + GEAR_GAP, GEAR_ROW2_Y, GEAR_SLOT_W, GEAR_SLOT_H)
		GEAR_SLOT_PACK:
			return Rect2(GEAR_LX + GEAR_LBL_W + GEAR_GAP + GEAR_SLOT_W + GEAR_COL_GAP
				+ GEAR_MINOR_LBL_W + GEAR_GAP, GEAR_ROW2_Y, GEAR_MINOR_W, GEAR_MINOR_H)
	return Rect2()

# ==== R-111：装备槽号 ↔ 武器数组下标的**唯一**转换入口 ====
# ⚠ 详见上方「三处坑」注释。**所有调用点必须走这两个函数**，
#   禁止出现 `equip_weapon_to_slot(id, slot)` 这种直接传装备槽号的写法。
#装备槽号 → `player.weapons[]` 下标（武器槽 0→0、2→1；非武器槽 → -1）
func gear_weapon_index_of(slot: int) -> int:
	if slot == GEAR_SLOT_W1:
		return 0
	if slot == GEAR_SLOT_W2:
		return 1
	return -1

# `player.weapons[]` 下标 → 装备槽号（0→槽0、1→槽2；越界 → -1）
func gear_slot_of_weapon_index(idx: int) -> int:
	if idx == 0:
		return GEAR_SLOT_W1
	if idx == 1:
		return GEAR_SLOT_W2
	return -1

# 命中装备槽 → 返回槽位下标；未命中返回 -1。
# ⚠ 判定用**槽位矩形本身**而不是"物品矩形"：空槽也必须能被命中并显示高亮，
#   否则玩家把物品拖到空槽上时**没有任何反馈**，会以为拖拽失败（R-78 的交互教训）。
func gear_pick_test(pos: Vector2) -> int:
	for i in GEAR_SLOT_COUNT:
		if gear_slot_rect(i).has_point(pos):
			return i
	return -1

# 落在哪个面板（用于放置）："inv" / "cont" / ""（面板外）；整栏都可放，拖拽更宽容
func drop_zone(pos: Vector2) -> String:
	if Rect2(PANEL_LX, PANEL_Y, PANEL_W, PANEL_H).has_point(pos):
		return "inv"
	if container_open and Rect2(PANEL_RX, PANEL_Y, PANEL_W, PANEL_H).has_point(pos):
		return "cont"
	return ""

# 装备栏接受什么（拖放合法性由 Main 判定，这里只回答"这个槽位属于哪一类"）
# → "weapon" / "armor" / "pack"；越界返回 ""。
func gear_slot_kind(i: int) -> String:
	if i == GEAR_SLOT_W1 or i == GEAR_SLOT_W2:
		return "weapon"
	if i == GEAR_SLOT_ARMOR:
		return "armor"
	if i == GEAR_SLOT_PACK:
		return "pack"
	return ""

# 命中某个已有物品 → {"list":"inv"/"cont", "index":int}；未命中返回 {}
func pick_test(pos: Vector2) -> Dictionary:
	for i in items.size():
		if inv_item_rect(items[i]).has_point(pos):
			return {"list": "inv", "index": i}
	if container_open:
		for j in container_items.size():
			if cont_item_rect(container_items[j]).has_point(pos):
				return {"list": "cont", "index": j}
	return {}

# ==== R-111：悬停说明文本（`hover_desc` 的唯一权威源）====
# ⚠ **为什么做成纯函数而不是在 `_draw()` 里现拼**：
#   ① 验证入口需要能**直接调用**它做断言（不依赖"鼠标恰好悬停在哪"）；
#   ② 文案与绘制分离，改文案不会碰几何，改几何不会碰文案。
# ⚠ **各项顺序固定（断言的前提）**：GDScript 的 Dictionary 遍历顺序**无保证**，
#   所以这里**显式**按 heal → hunger → thirst → stamina → reduction → load_bonus → rounds → weight 取，
#   绝不 `for k in use:` 遍历。同理分隔符固定为" · "。
# ⚠ R-new：**每件物品都显示重量**（不再只作为"无恢复值时的兜底"）——
#   用户需求「悬停物品信息加上重量」。重量对"这趟搜刮值不值得带"是有用信息，
#   且对武器/护甲/弹药盒这类原本看不到重量的物品同样有意义（R-117 起**不带 wg 后缀**）。
func item_desc(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	var parts: Array = []
	var u: Dictionary = it.get("use", {}) as Dictionary
	# ---- 顺序 1~4：使用效果（固定序，逐项判断存在性）----
	if u.has("heal"):
		# ⚠ R-117：`恢复HP %d` → `Loc.t("backpack.desc_heal")` =「回血 %d」。
		#   理由：中文里混 ASCII 是本批要清的（用户需求逐字「统一成中文」）。
		#   宽度实测 font 7：`恢复HP 10` **28px** → `回血 10` **24px**，**反而窄 4px**
		#   （`HP` 两个 ASCII ≈ 8px < `回血` 两个汉字 14px，但省掉一个空格）。
		parts.append(Loc.t("backpack.desc_heal") % int(round(float(u["heal"]))))
	if u.has("hunger"):
		parts.append("饥饿 %d" % int(round(float(u["hunger"]))))
	if u.has("thirst"):
		parts.append("口渴 %d" % int(round(float(u["thirst"]))))
	if u.has("stamina"):
		parts.append("体力 %d" % int(round(float(u["stamina"]))))
	# ---- 顺序 5：护甲减伤（护甲类物品才有 `reduction`）----
	if it.has("reduction"):
		parts.append("减伤 %d%%" % int(round(float(it["reduction"]) * 100.0)))
	# ---- 顺序 6：背包负重加成（双肩包才有 `load_bonus`）----
	if it.has("load_bonus"):
		parts.append("负重 +%d" % int(round(float(it["load_bonus"]))))
	# ---- 顺序 7：弹药盒发数（ammo 类才有 `rounds`）----
	if it.has("rounds"):
		parts.append("弹药 %d 发" % int(it["rounds"]))
	# ---- 顺序 8（R-new）：重量 —— **每件物品都显示**（不再是"无效果时的兜底"）----
	# ⚠ R-117：`重量 %.1fwg` → `Loc.t("backpack.desc_weight")` =「重量 %.1f」（**去掉 wg 后缀**）。
	#   理由：`wg` 是 ASCII 字母（weight grams 的缩写），属玩家可见英文残留。
	#   ⚠ **单位信息并未丢失**：左栏面板标题已写明「负重 13.5 / 60」（同一套重量数字），
	#     且 `--verify-loadout2 ③` 钉死了暂停页的「负重  16.5 / 60.0」——重量语义由那两处承载。
	#     单件物品行只回答「有多重」，不需要再带一次单位。
	#   宽度实测 font 7：`重量 1.5wg` **36px** → `重量 1.5` **26px**，窄 10px。
	parts.append(Loc.t("backpack.desc_weight") % float(it.get("weight", 0.0)))
	return " · ".join(parts)

# 悬停到的物品（用于显示名称 + 说明）
func hover_test(pos: Vector2) -> Dictionary:
	for it in items:
		if inv_item_rect(it).has_point(pos):
			return it
	if container_open:
		for it in container_items:
			if cont_item_rect(it).has_point(pos):
				return it
	return {}

# ==== R-101：装备栏数据（由 Main 装配，本脚本只读）====
# ⚠ 装备栏**不是背包容器**，没有 gx/gy、没有占格搜索 —— 每个槽**恰好一件**物品。
#   物品的 `w`/`h` 仍然保留，只用于决定在 3×4 的槽里**画多大一块**（居中）。
#   因此这里存的是**物品形态原型**（`kind` 为 weapon/armor/pack），而不是战斗形态字典。
var gear_items: Array = []       # 长度恒为 GEAR_SLOT_COUNT；元素 = 物品 Dictionary 或 {}（空槽）
var gear_active: int = -1        # 当前手持的武器槽下标（-1 = 无/非武器）；用于金色描边

func gear_item(i: int) -> Dictionary:
	if i < 0 or i >= gear_items.size():
		return {}
	var d: Dictionary = gear_items[i]
	return d

func gear_is_empty(i: int) -> bool:
	return gear_item(i).is_empty()

# ---------- 绘制 ----------
func _draw() -> void:
	var font := GameConstants.ui_font()
	# 左栏：背包
	# ⚠ R-117：`负重 %.1f / %.0f wg` → `Loc.t("backpack.panel_load")` =「负重 %.1f / %.0f」（去 wg）。
	#   宽度实测 font 8：`负重 13.5 / 60 wg` **64px** → `负重 13.5 / 60` **51px**，窄 13px。
	#   ⚠ **可用宽 = PANEL_W(156) − PAD(4) = 152px**，51px 安全（余 101px）。
	_draw_panel(PANEL_LX, Loc.t("backpack.panel_load") % [cur_load, max_load])
	_draw_sort_button()            # R-new：标题行右端的「排序」按钮
	_draw_gear(font)               # R-101：装备栏（在网格**上方**）
	_draw_grid(GRID_LX, INV_GRID_Y, items)
	# 左栏底部：快捷栏（预留）
	var qx := PANEL_LX + PAD
	var qy := INV_GRID_Y + GRID_H + GEAR_GAP
	var qw := PANEL_W - PAD * 2.0
	draw_rect(Rect2(qx, qy, qw, QUICK_H), Color(0.13, 0.14, 0.19, 1))
	draw_rect(Rect2(qx, qy, qw, QUICK_H), SLOT_LINE, false, 1.0)
	var qslot: float = qw / float(GameConstants.QUICK_SLOTS)
	for i in range(1, GameConstants.QUICK_SLOTS):
		var lx2 := qx + i * qslot
		draw_line(Vector2(lx2, qy), Vector2(lx2, qy + QUICK_H), SLOT_LINE, 1.0)
	draw_string(font, Vector2(qx + 2.0, qy + 8.0), "快捷栏", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, DIM)
	# 右栏：箱子（⚠ R-101：位置/行数**刻意保持旧值**，不受左栏改动影响）
	if container_open:
		_draw_panel(PANEL_RX, "箱子（%d 件）" % container_items.size())
		_draw_sort_button_at(cont_sort_button_rect())   # R-new（2026-10-22）：右栏排序按钮
		# ⚠ R-111：用**右栏专属**的 `CONT_GRID_Y`（= 向上靠，紧贴标题行），不再借用左栏 `GRID_Y`。
		_draw_grid(GRID_RX, CONT_GRID_Y, container_items, CONT_ROWS)
	# 拖拽中的物品（跟随鼠标，按物品真实占格大小画）
	#   ⚠ R-154：同样走 `draw_item` —— 否则拖动时图标"变回色块"，
	#   同一件物品在"静置/拖拽"两种状态下出现两种外观（观感割裂）。
	if not drag_item.is_empty():
		var dw: float = item_w(drag_item) * SLOT
		var dh: float = item_h(drag_item) * SLOT
		draw_item(Rect2(drag_pos.x - dw * 0.5, drag_pos.y - dh * 0.5, dw, dh), drag_item)
	# ---- 悬停提示框（鼠标附近）：第 1 行物品名 + 第 2 行简要说明 ----
	# ⚠ R-111：R-67 只有一行（名字）。用户要求加"简要说明"，故框高 14 → 22px。
	# ⚠ **宽度取两行的较大值**：说明行通常比名字长（「回血 40 · 饥饿 35 ...」），
	#   若沿用"按名字长度算宽"，长说明会**画出框外**。
	# ⚠ **不溢出屏幕**：横竖都做 clamp（框必须完整落在 0..320 / 0..180 内）。
	#   断言见 `--verify-uibox` ⑥（tip 右缘 ≤ 320、底缘 ≤ 180）。
	if hover_name != "":
		var nw: float = 6.0 + float(hover_name.length()) * 7.0
		var dw: float = 0.0
		if hover_desc != "":
			dw = 6.0 + float(hover_desc.length()) * 6.0
		var tw: float = maxf(nw, dw)
		var th: float = TIP_H if hover_desc == "" else TIP_H + TIP_DESC_H
		# ⚠ `minf`/`maxf` 两侧都夹：右边夹住不让它跑出 320，下边夹住不让它跑出 180。
		var tx: float = clampf(hover_pos.x + 10.0, 0.0, maxf(0.0, VIEW_W - tw - 2.0))
		var ty: float = clampf(hover_pos.y - th, 0.0, maxf(0.0, VIEW_H - th))
		draw_rect(Rect2(tx, ty, tw, th), TIP_BG)
		draw_rect(Rect2(tx, ty, tw, th), TIP_BORDER, false, 1.0)
		draw_string(font, Vector2(tx + 2.0, ty + 10.0), hover_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, TEXT)
		if hover_desc != "":
			draw_string(font, Vector2(tx + 2.0, ty + 10.0 + TIP_DESC_H), hover_desc,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 7, DIM)

# ==== R-new：排序按钮绘制 ====
# 标题行右端的「排序」小按钮：底板 + 描边 + 文字（走 Loc 表，与全工程 UI 文案一致）。
func _draw_sort_button() -> void:
	_draw_sort_button_at(sort_button_rect())

# 在给定矩形画「排序」按钮（左/右栏共用同一外观）。
func _draw_sort_button_at(r: Rect2) -> void:
	draw_rect(r, SLOT_BG)
	draw_rect(r, GEAR_SLOT_LINE, false, 1.0)
	draw_string(GameConstants.ui_font(), Vector2(r.position.x + 2.0, r.position.y + 7.0),
		Loc.t("backpack.sort_btn"), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, TEXT)

# ==== R-101：装备栏绘制 ====
# 一栏背景 + 标题
func _draw_panel(px: float, title: String) -> void:
	draw_rect(Rect2(px, PANEL_Y, PANEL_W, PANEL_H), BG)
	draw_rect(Rect2(px, PANEL_Y, PANEL_W, PANEL_H), BORDER, false, 1.0)
	draw_string(GameConstants.ui_font(), Vector2(px + PAD, PANEL_Y + 10.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, TEXT)

# ==== R-154：物品图标实装（把已生成的 64×64 图标接进背包/装备栏）====
# ⚠⚠ **为什么资产是 10×10 而不是交付时的 64×64**：背包格 = `GameConstants.INV_SLOT`
#   = **10px**（12×8 格，R-111）。把 64×64 直接交给引擎缩到 10px = 6.4:1，
#   Nearest 下必然aliasing 成糊块（与 R-153 僵尸「画布 64×64 ≠ 世界占位」同一个坑）。
#   → **离线预降采样到 10×10**（box 滤波 + alpha 硬阈值 + 颜色吸附回原图调色板，
#     见 `outputs/item_icons/downscale_for_engine.py`），引擎 **零缩放 1:1** 绘制。
#   ⇒ 图标可读性上限就是 10px，这是**当前格距的物理上限**，不是画工问题。
#   将来若要更清楚的图标，只能**放大格距**（动 `INV_SLOT`，属布局批次），不能靠引擎硬缩。
#   ⚠ key 必须与 `GameConstants.ITEM_TYPES[].id` **逐字一致**；查不到 → 回落色块（不崩）。
#   ⚠ **未实装图标的物品仍画原色块**（可见地暴露"还没画"），而不是画成空白 ——
#     与 R-148 敌人精灵「纹理缺失 → 可见地降级回色块」同一取舍。
const ITEM_ICON_TEX := {
	"medkit": preload("res://assets/sprites/ui_icon_med_medkit.png"),
	# ⚠ `bandage` 图标已生成（`ui_icon_med_bandage.png`），但**游戏里还没有 `bandage` 这个物品**
	#   （`ITEM_TYPES` 首个药品是 `medkit` 医疗包）→ 无处可挂，暂不登记。
	#   将来加了绷带物品，这里加一行即可（资产已就位）。
}

# 物品图标（纯函数，便于 `--verify-itemicon` 直接断言，不依赖鼠标悬停位置）。
#   ⚠ 走 `get("id")` 而非 `it["id"]`：物品字典是原型拷贝，缺 `id` 时不崩。
func item_icon(it: Dictionary) -> Texture2D:
	if it.is_empty():
		return null
	var id: String = String(it.get("id", ""))
	if id == "":
		return null
	return ITEM_ICON_TEX.get(id, null) as Texture2D

# 已登记图标的物品 id 列表（**纯函数**，供 `--verify-itemicon` ④ 断言
#   「每个 key 都能在 `GameConstants.ITEM_TYPES` 里找到真实物品」——
#   否则就会写下 `bandage` 这种**游戏里根本没有的物品**的 key，图永远挂不上）。
func item_icon_ids() -> Array:
	return ITEM_ICON_TEX.keys()

# 物品在槽内的绘制矩形（**满格**，1:1 对齐 `INV_SLOT`，故 1×1 物品恰好 10×10 = 图标尺寸）。
#   ⚠ 旧实现在满格基础上 **内缩 1px** 画色块（`grow(-1)`），那是为了给边框留视觉间隙。
#   实装图标后**不再内缩**：图标本身就是满格内容，再内缩就只剩 8×8 可画 → 白白丢 20% 像素。
#   边框改画在满格边界（见 `draw_item`）。
func item_cell_rect(ox: float, oy: float, it: Dictionary) -> Rect2:
	#   ⚠ 用 `get("gx", 0)` 而非 `it["gx"]`：物品原型（`GameConstants.ITEM_TYPES` 拷贝）
	#     **尚未放进背包**、没有 gx/gy 坐标 —— 直接下标会崩（验证入口正是拿原型来试尺寸的）。
	return Rect2(ox + int(it.get("gx", 0)) * SLOT, oy + int(it.get("gy", 0)) * SLOT,
		item_w(it) * SLOT, item_h(it) * SLOT)

# 统一的物品绘制入口（网格栏 + 装备栏**共用**，避免两条路径画出两种外观）。
#   ① 有图标 → `draw_texture_rect` 1:1（零缩放，保住硬像素）
#   ② 无图标 → 回落 `color` 色块（可见地降级）
#   ③ 占格 ≥4 的多格大件再画一条内框（沿用旧口径，不画网格线避免割裂图标）
#   ⚠「图标与色块同时可见」= 双重外观，**禁止**（与 R-148 敌人精灵同一铁律）。
func draw_item(cell: Rect2, it: Dictionary) -> void:
	var tex := item_icon(it)
	if tex != null:
		draw_texture_rect(tex, cell, false)          # 1:1，不缩放
	else:
		var c: Color = Color(0.75, 0.75, 0.80)
		if it.has("color"):
			c = it["color"]
		draw_rect(cell, c)
	draw_rect(cell, ITEM_LINE, false, 1.0)
	if item_slots(it) >= 4:
		draw_rect(cell.grow(-2.0), ITEM_LINE, false, 1.0)

# 装备栏：**两行两列**（行1 = 武器1 + 护甲，行2 = 武器2 + 背包），画在背包网格上方
# ⚠⚠ **R-111：标签从「槽上方」改为「槽左侧」**（两行布局下的必然要求）：
#   R-101 单行横排时标签画在槽**正上方**是安全的（上方是空的"装备"标题行）；
#   两行布局后，第 2 行槽的"上方"是**第 1 行的槽** —— 标签会**直接画在上一行槽上面**，
#   出现「武器2」三个字糊在武器1 槽里的画面。
#   → 改为左侧：每行 = 「标签 | 武器槽 ... 标签 | 小槽」，行内左→右，
#     两行的标签各自对齐自己的槽，**永不重叠**。
#   ⚠ 槽内只放物品 + 空槽提示（物品按真实占格**居中**，见下），标签一律在槽外。
func _draw_gear(font: Font) -> void:
	for i in GEAR_SLOT_COUNT:
		var r: Rect2 = gear_slot_rect(i)
		var it: Dictionary = gear_item(i)
		# 槽底板（空槽更暗，一眼区分"装备槽"与"背包格"）
		draw_rect(r, GEAR_EMPTY_BG if it.is_empty() else SLOT_BG)
		# 边框：当前手持的武器槽用金色，一眼看出"现在打的是哪把"
		var bc: Color = GEAR_ACCENT if i == gear_active else GEAR_SLOT_LINE
		draw_rect(r, bc, false, 1.0)
		if it.is_empty():
			# 空槽提示：画一个居中的小横杠（"这里能放东西"），不写字（320px 宽放不下）
			var cx: float = r.position.x + r.size.x * 0.5
			var cy: float = r.position.y + r.size.y * 0.5
			draw_line(Vector2(cx - 4.0, cy), Vector2(cx + 4.0, cy), GEAR_SLOT_LINE, 1.0)
		else:
			# R-154：统一走 `draw_item`（装备栏里的消耗品也用真图标；武器无图标 → 回落色块）
			# ⚠ 为什么不用 `inv_item_rect`：装备栏没有 gx/gy（不是网格容器），
			#   尺寸必须由 `w`/`h` 直接算，再相对槽中心居中。
			# ⚠ R-111 **沿用 R-71 的居中画法**（用户未要求改）：武器槽是 5×3 的**上界**，
			#   放进一把 4×1（40×10）的霰弹枪时，左右各留 5px、上下各留 10px 空白，
			#   **槽边框不动、不闪烁** —— 这正是"槽尺寸不随物品变化"要买的东西。
			var iw: float = item_w(it) * SLOT
			var ih: float = item_h(it) * SLOT
			var ir: Rect2 = Rect2(
				r.position.x + (r.size.x - iw) * 0.5,
				r.position.y + (r.size.y - ih) * 0.5, iw, ih)
			draw_item(ir, it)
		# 标签：画在槽的**左侧**、与槽**顶对齐**（字号 7 = 320×180 上唯一放得下的字号）
		var lb: String = _gear_label(i)
		var lx: float = r.position.x - GEAR_GAP - (GEAR_LBL_W if _is_weapon_slot(i) else GEAR_MINOR_LBL_W)
		# ⚠ 标签基线比槽顶低 6px：字号 7 的字高约 7px，+6 让文字**视觉上**与槽顶齐平
		#   （draw_string 的基线在字底，若直接用 r.position.y 会整体偏高 1px）。
		var ly: float = r.position.y + 6.0
		draw_string(font, Vector2(lx, ly), lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, DIM)

# 槽是否武器槽（决定标签宽度用GEAR_LBL_W 还是 GEAR_MINOR_LBL_W）
func _is_weapon_slot(i: int) -> bool:
	return i == GEAR_SLOT_W1 or i == GEAR_SLOT_W2

# 装备槽标签文案。武器槽带上快捷键数字（用户逐字点名 '1' / '2'），
#   让"按哪个键切这把枪"直接写在槽位上，不需要玩家去猜。
func _gear_label(i: int) -> String:
	if i == GEAR_SLOT_W1:
		return "武器1"
	if i == GEAR_SLOT_W2:
		return "武器2"
	if i == GEAR_SLOT_ARMOR:
		return "护甲"
	if i == GEAR_SLOT_PACK:
		return "背包"
	return ""

# 一栏网格（格线 + 占格物品）；两栏共用同一 SLOT 尺寸
# ⚠ R-101：`rows` 按栏传入 —— 玩家背包 10 行、箱子 15 行，**两者格线高度不同**。
#   旧代码两栏共用 `GRID_ROWS`，拆分行数后若不改，箱子会画出 10 行格线却能放 15 行物品。
func _draw_grid(ox: float, oy: float, list: Array, rows: int = -1) -> void:
	var n_rows: int = rows if rows > 0 else GRID_ROWS
	var gh: float = float(n_rows) * SLOT
	draw_rect(Rect2(ox, oy, GRID_W, gh), SLOT_BG)
	for i in range(GRID_COLS + 1):
		var lx := ox + i * SLOT
		draw_line(Vector2(lx, oy), Vector2(lx, oy + gh), SLOT_LINE, 1.0)
	for j in range(n_rows + 1):
		var ly := oy + j * SLOT
		draw_line(Vector2(ox, ly), Vector2(ox + GRID_W, ly), SLOT_LINE, 1.0)
	for it in list:
		if not it.has("gx") or not it.has("gy"):
			continue
		# R-154：统一走 `draw_item`（有图标画图标 1:1 / 无图标回落色块 + 边框）
		draw_item(item_cell_rect(ox, oy, it), it)
