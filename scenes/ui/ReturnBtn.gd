# ReturnBtn · 返回第 100 层（基地）的调试按钮（R-112 新增）
# ==============================================================================
# 【用户需求逐字 · team-lead 转述】
#   「为了测试在屏幕右下角添加返回按钮，点击后玩家返回100层并保留所有物品」
#   「返回按钮 = **调试用**，随时可回100 层并保留所有物品」
#⚠⚠ **本批不做「正式构建隐藏」**：我问过用户，用户明确选「随时可回」不选隐藏。
#   → 因此**没有任何构建开关 / DEBUG 门**包着它，它恒定可见、恒定可点。
#
# 【为什么用 `_draw` + `_gui_input`，而不是加一个真实 Control 节点】
#   ① **不改 `Main.tscn`** —— 少一个文件 = 少一个回归面（R-68 教训）。
#      Main 里有 40+ 个节点，`.tscn` 的任何改动都要重跑全量回归才敢信。
#   ② 与既有 `Hint`（`scenes/ui/Hint.gd`）**完全同构**：同一个 `CanvasLayer`
#      下的 `Node2D` + `_draw()` + `text` 由 Main 推给它的模式，风格统一。
#   ③ 按钮只占30×14 px，真实 `Button` 控件的最小尺寸 / 样式 / 焦点导航
#      在 320×180 内分辨率下全是负担，且 `HUD._make_mouse_transparent()`
#      会把 HUD 子树全设成 `MOUSE_FILTER_IGNORE`（R-68）—— 加进 HUD 反而点不到。
#
# 【几何：320×180 内的右下角，**避开 HUD 与 Hint 的实测墨迹**】
#   实测依据（不是估算）：
#     · HUD 7 条色条 + 楼层号  -> x ∈ [4,124]、y ∈ [4,61]
#       （`TraceArrows.gd` 文件头「320×180 的空间核实」段，R-110 实测并由
#         `--verify-trace ⑧` 长期守护；其 keep-out 矩形 = x<128 且 y<64）
#     · `Hint` 交互提示-> 底部居中，`draw_string(pos=(60,172), width=200, font=8)`
#       -> 墨迹 x ∈ [60,260]、y ≈ 164..172
#     · `Crosshair`             -> 屏幕正中（跟随鼠标）
#     · `TraceArrows`           -> 四边内缩 8px
#   → **右下角 (x>128 且 y>64) 完全空闲**，本按钮落在那里。
#   ⚠ **与 `Hint` 不重叠的依据**：本按钮图形 x 起于 292> 260（余量 32px）、
#     命中矩形 x 起于 286 > 260（余量 26px）—— **x 区间根本不相交**，
#     所以即便 y 带重合（都在 154..180）也**不可能压到 Hint 的字**。
#   ⚠ **与 `TraceArrows` 的关系（R-112 实测，真争用 + 已解决）**：
#     `TraceArrows` 的下边缘箭头墨迹占 `y ∈ [168.5, 175.5]`、`x ∈ [8, 312]`
#     （`_edge_point()`：锚点 y = 180/2 + (180/2-8) = 172，箭头 ±3.5），
#     与本按钮图形 `x ∈ [292,316]` / `y ∈ [160,174]` **确实重叠**。
#     且它的 CanvasLayer = **16**，本按钮原为 11 -> **箭头会盖住按钮文字**。
#     → 已把本按钮提到 **layer 17**（> 16），并把底板改成**完全不透明**。
#     （这两点是 `Main._build_return_btn()` 与本文件 `BG_COLOR` 处的注释依据。）
#
# 【命中矩形比图形大 —— 小按钮难点中，必须给外扩余量】
#   图形 24×14 -> 命中 34×26（左右各外扩 5~6px、上下各外扩 6px）。
#   命中区**故意允许探出屏幕**（y 到 180、x 到 320），
#   这样"手指/鼠标点在屏幕最右下角"也能命中，而不是差几像素点不到。
#
# 【⚠ 已知性质（不是 bug，是调试按钮的语义）】
#   **无代价单向逃生门**：可反复下到第 1 层再瞬间满状态回顶。
#   本批**没有**「回基地触发结算 / 代价」，故这是无代价的。
#   作为**用户明确要求的调试按钮**可接受。
#
# 【R-20 复位时序 —— 本批只做前半段，后半段留给R-20 专门批次】
#   设计文档 §3.1 逐字：「**返回基地后，于下一次离开基地时**：③ 层整体复位
#   （敌人/ 精英 / Boss 全部复活、地面物品与容器恢复）」。
#   → 本按钮点击**这一刻只做「回基地 + 保留玩家物品」**，
#     **不**做 ③ 层复位（**本批既无存档级持久层、也无探索级复位层**）。
#   → 复位语义随 R-20 专门批次落地，届时才在此处补挂。
#   ⚠ 另：饥饿 / 口渴**照常自然衰减、不恢复**（切层本就会衰减，R-92）——
#     返回按钮不额外改这两个数值（恢复会让它变成一个小作弊）。
# ==============================================================================
# ⚠⚠ **`extends Control` 而不是 `extends Node2D`（实测踩坑后改）**
#   最初按 `Hint` 的样子写 `extends Node2D`，结果连撞两个 Parse/Runtime 错误：
#     ① `accept_event()` not found in base self
#        —— `accept_event()` 是 **Control 独有**的方法，`Node2D` 上没有。
#     ② Invalid access to property 'gui_input' on base 'Node2D'
#        —— **`gui_input` 信号同样是 Control 独有的**，`Node2D` 没有。
#   → 按钮需要「真实鼠标命中 + 可选事件 + 对外发信号」，这三样都只在 `Control` 上。
#   → 仍然**不改 `Main.tscn`**：`Main` 里用 `ReturnBtnScript.new()` 代码建节点，
#     显式设 `position` / `size` / `mouse_filter`，与 `Main._build_floor()` 里
#     `new()` 出来再 `add_child` 的既有做法一致（R-110 `_build_trace_arrows` 同款）。
#   ⚠ 与 HUD 的区别：`HUD._make_mouse_transparent()` 把 HUD 子树全设成
#     `MOUSE_FILTER_IGNORE`（R-68，为的是别让 HUD 吃掉点击）——
#     本按钮**必须相反**：它是唯一要吃点击的东西，故`MOUSE_FILTER_STOP`。
# ==============================================================================
extends Control

# ---- 被测钩子（供 `--verify-floor100` 断言；**不参与绘制逻辑**）----
var click_count: int = 0 # 真实 `_gui_input` 命中被处理的次数

# ---- 几何常量（全部为**字面量**，不得从别处推导 —— R-96 教训）----
const BTN_X := 292.0        # 图形左边
const BTN_Y := 160.0        # 图形上边
const BTN_W := 24.0         # 图形宽 -> x ∈ [292, 316]
const BTN_H := 14.0         # 图形高 -> y ∈ [160, 174]
const HIT_PAD := 6.0        # 命中矩形外扩量 -> 34×26
# ⚠ R-117：`F100` **刻意保留 ASCII**（判据=「代号/标识符」而非「要读的词」）。
#   理由：它与 `HUD.set_floor()` 的 `F%d`（楼层号前缀）是**同一个词根**——
#   两者同屏出现（按钮在右下、楼层号在左上），改成中文会让玩家看到
#   「回100 层」与「F100」两种读法，反而更难懂。
#   ⚠ 真正的**文案来源已迁到 `Loc`**（key `return.floor_label`），本常量保留是因为
#   `--verify-floor100` 逐字断言它。改文案时**两处都要改**（由 `--verify-loc ①-c` 守护）。
#   宽度：font 8 实测 **18px**，按钮 24px 宽、右侧留 2px → 可用 22px，安全。
const LABEL := "F100"       # ← 与 Loc 表 key `return.floor_label` 同字
const FONT_SIZE := 8        # 与 `Hint.gd` 同字号
const VIEW_W := 320.0        # 内部分辨率（同 `TraceArrows.VIEW_W` 的做法：就地取字面量，
const VIEW_H := 180.0        #   **不**往 GameConstants 加条目 —— 那是"单一权威常量源"，只放玩法数值；
#                            屏幕尺寸属于表现层局部事实，故就地取字面量
# 配色：与既有 UI 同族（Hint 用暖黄 (0.99,0.90,0.35)；这里用冷青蓝以区分"功能键"）
# ⚠ **完全不透明**（alpha = 1.0）：与 `TraceArrows` 的箭头同处y≈168~175 带，
#   靠「按钮在 layer 17> 16 之上」+「底板不透明」双保险确保文字始终可读。
const BG_COLOR := Color(0.10, 0.13, 0.18, 1.0)
const BORDER_COLOR := Color(0.37, 0.64, 0.84, 1.0)
const ARROW_COLOR := Color(0.55, 0.85, 1.00, 1.0)
const TEXT_COLOR := Color(0.99, 0.90, 0.35, 1)

## 图形包围盒（右 下角）
func btn_rect() -> Rect2:
	return Rect2(BTN_X, BTN_Y, BTN_W, BTN_H)

## 命中包围盒（比图形大HIT_PAD）
func hit_rect() -> Rect2:
	return Rect2(BTN_X - HIT_PAD, BTN_Y - HIT_PAD, BTN_W + HIT_PAD * 2.0, BTN_H + HIT_PAD * 2.0)

## 图形包围盒（**控件局部坐标**，**仅供 `_draw()` 使用**）—— R-128 根因修复
## ⚠⚠ **为什么必须有这个方法（R-128 的根因）**：
##   `_draw()` 画的是**控件局部坐标**，而 `btn_rect()` 是**绝对屏幕坐标**。
##   本控件在 `_ready()` 里把原点设在 `hit_rect().position` = (286, 154)。
##   若在 `_draw()` 里直接用绝对 `btn_rect()`，图形会被**再加一次控件原点**，
##   画到 (286+292, 154+160) = **(578, 314)** —— 远在 320×180 视口之外
##   → 按钮**在任何一帧都不可见**（用户报告「右下角没有返回按钮」的根因）。
##   换算关系：局部 = 绝对 − 控件原点 = 绝对 − `hit_rect().position`
##     → 局部 (HIT_PAD, HIT_PAD) == 绝对 (BTN_X, BTN_Y) ✔
##   （`Main._input` 的命中测试走的是**绝对**坐标，故 `btn_rect()`/`hit_rect()` 保持绝对语义不动。）
func btn_rect_local() -> Rect2:
	return Rect2(HIT_PAD, HIT_PAD, BTN_W, BTN_H)

## 命中包围盒（**控件局部坐标**，**仅供 `_gui_input()` 使用**）—— R-128 根因修复
## ⚠ 控件本体（`_ready()`）已铺成 `hit_rect()` 大小、原点在 `hit_rect().position`，
##   故「局部命中区」= 整个控件 = Rect2(0, 0, size)。`_gui_input` 收到的
##   `InputEventMouseButton.position` 也是**局部**坐标，两者同系才能正确判定。
func hit_rect_local() -> Rect2:
	return Rect2(Vector2.ZERO, hit_rect().size)

## 命中测试（**供 `Main._input` 调用** —— 见文件头「输入链路」段）
## ⚠ 无头验证走这条路：`Viewport.push_input()` 在 headless 下**不会**把事件派发到
##   `Control._gui_input`（R-112 探针实测 A/B 均为 0 命中，见
##   `qa_scratch/r112/click_probe.txt`），而本工程所有既有点击也都在
##   `Main._input` 里自己做命中测试。两条路并存、判定函数共用本方法。
func hit_test(p: Vector2) -> bool:
	return hit_rect().has_point(p)

## 屏幕可见区（320×180 内部分辨率）
func view_rect() -> Rect2:
	return Rect2(0.0, 0.0, VIEW_W, VIEW_H)

func _ready() -> void:
	# 用**命中矩形**（不是图形矩形）铺满控件本体：`_gui_input` 收到的坐标是
	# 控件局部坐标，所以控件大小必须等于 hit_rect，否则命中区会被控件裁掉。
	position = hit_rect().position
	size = hit_rect().size
	# ⚠ 与 HUD 相反：HUD 全设IGNORE（R-68），本按钮**必须 STOP**才能收到点击。
	mouse_filter = Control.MOUSE_FILTER_STOP
	# ==== R-128 补修：**默认隐藏**（安全侧默认值）====
	# ⚠⚠ `Control` 的 `visible` **默认是 `true`**。而 `Main._build_return_btn()` 在
	#   `Main._ready()` 里**晚于**首个 `_build_floor(true)`（302 行 vs 305 行），
	#   所以"Main 这一帧还没来得及设显隐"是**会真实发生的失败模式**。
	#   → 把控件**自身**的默认值设成**安全侧**（隐藏）：即使 Main 漏设，
	#     也只会"少显示一次"（下一帧 `_build_floor` 会点亮），
	#     而**不会**在基地层冒出一个不该出现的按钮。
	#   ⚠ `Main.gd:_build_return_btn()` 末尾那次**显式赋值保留不删**（双保险）：
	#     本默认值负责「Main 漏设也不会错显」；那次赋值负责「建完立刻正确」。
	#     （两者职责不同，不是冗余 —— R-112 曾把"建完立刻正确"误当成唯一防线。）
	visible = false
	queue_redraw()

func _draw() -> void:
	# ⚠⚠ **R-128 根因修复**：这里**必须**用局部坐标 `btn_rect_local()`，
	#   不能用绝对 `btn_rect()`（否则会被再加一次控件原点画到视口外，按钮不可见）。
	#   底板 / 边框 / 箭头 / 文字**四处**全部改用局部坐标（下方 `r.position` 已是局部）。
	var r := btn_rect_local()
	# 底板 + 亮边框：不透明，保证下层 TraceArrows 箭头不会干扰可读性
	draw_rect(r, BG_COLOR, true)
	draw_rect(r, BORDER_COLOR, false, 1.0)
	# 复用 `TraceArrows._arrow_poly` 的三角几何（tip + 两侧倒角）——纯手绘、无 emoji。
	#指向**向上**（回顶层/基地的方向）。
	var c := r.position + Vector2(5.0, r.size.y * 0.5)
	var a := 4.0               # 箭头外接尺寸（与 ARROW_SIZE 同量级）
	var d := Vector2(0.0, -1.0)
	var perp := Vector2(-d.y, d.x)
	var tip: Vector2 = c + d * (a * 0.5)
	var b1: Vector2 = c - d * (a * 0.35) + perp * (a * 0.45)
	var b2: Vector2 = c - d * (a * 0.35) - perp * (a * 0.45)
	draw_colored_polygon(PackedVector2Array([tip, b1, b2]), ARROW_COLOR)
	# 文案右对齐到按钮右缘（"F100" 4 字符 font 8 实测 18px 宽，右侧留 2px→ 可用 22px）
	# ⚠ R-117：走 `Loc.t()`（key `return.floor_label`）—— `_draw()` 里调 autoload 安全（实测）。
	var font := GameConstants.ui_font()
	draw_string(font, Vector2(r.position.x + 9.0, r.position.y + 11.0), Loc.t("return.floor_label"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# ⚠⚠ **R-128 根因修复**：`mb.position` 是**控件局部坐标**，
			#   必须用局部命中区 `hit_rect_local()` 判定，不能拿绝对 `hit_rect()` 比
			#   （否则局部坐标恒落在绝对命中区外 -> 永远判定不中 -> `click_count` 恒为 0）。
			if hit_rect_local().has_point(mb.position):
				click_count += 1
				# `accept_event()` 是 Control 独有的方法 —— 在这里用它把这次点击
				# **吃掉**，避免继续冒泡到 Main 的别的点击处理（`_unhandled_input`）。
				accept_event()
				# 状态变更由 Main 侧连上来的 `gui_input` 信号处理（UI 层不持有游戏状态）。