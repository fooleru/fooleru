# DepartConfirm · 第 100 层基地「是否出发」确认框（R-119 新增）
# ==============================================================================
# 【用户需求逐字 · team-lead 转述】
#   「将'出发'的按键改为'f'并且显示是否出发的对话框。」
# → 站上出发瓦片按 F → 弹出本确认框；F 确认下楼、Esc 取消、走开瓦片自动关闭。
#
# 【为什么用 `extends Control` + `_draw`，而不是 Button / 改 Main.tscn】
#   与 `ReturnBtn.gd`（R-112）同款取舍：**代码 new 节点，不动 Main.tscn**（少一个回归面）。
#   本框是**键盘驱动**（F / Esc），不需要鼠标命中，所以不设 `_gui_input`，
#   也不吃鼠标事件（`MOUSE_FILTER_IGNORE`），避免挡住下层 ReturnBtn / 世界点击。
#
# 【为什么不是「按 F 直接下楼」而是「先弹框再确认」】
#   出发 = 进入下一层 = **触发敌人/箱子整体复位**（R-113 的「一次新探索开始」）。
#   误触 F 的代价 = 丢掉当前基地里"已经摆好"的状态（虽然基地内无战斗，但复位语义重）。
#   弹框确认是把「有代价动作」与「无代价交互」分开的标准做法（对齐 R-113 的
#   「踩上 + 按键确认，不自动触发」第一轮拍板精神）。
#
# 【几何：320×180 内居中，避开 HUD / Hint / 出发瓦片墨迹】
#   · 全屏半透明底：遮住后方，聚焦本框
#   · 面板 190×64 居中：x ∈ [65,255]、y ∈ [58,122]，不压 HUD(x<128,y<64) 也不压 Hint(y≈164+)
#   · 三行文本：标题「出发确认」+ 正文 + 按键提示「F 确认   Esc 取消」
#
# 【⚠ 状态与绘制分离（R-112 单向数据流约定）】
#   本节点只负责「画」+ 暴露 `open/close`；状态变更（何时开、F 确认下楼、Esc 取消、
#   走开自动关）全部在 `Main`。`visible` 由 Main 显式置 true/false。
# ==============================================================================
extends Control

# ---- 几何 / 配色（全部字面量，禁止从别处推导 —— R-96 教训）----
const W := 320.0              # 全屏宽（内部分辨率）
const H := 180.0              # 全屏高
const DIM_ALPHA := 0.55       # 全屏底透明度
const PANEL_X := 65.0         # 面板左上角 x
const PANEL_Y := 58.0         # 面板左上角 y
const PANEL_W := 190.0        # 面板宽 -> x ∈ [65, 255]
const PANEL_H := 64.0         # 面板高 -> y ∈ [58, 122]
const PANEL_BG := Color(0.10, 0.12, 0.16, 0.96)   # 面板底：深蓝黑，不透明
const PANEL_BORDER := Color(0.99, 0.90, 0.35, 1.0) # 边框：暖黄（可交互）
const TITLE_COLOR := Color(0.99, 0.90, 0.35, 1.0)  # 标题：暖黄
const BODY_COLOR := Color(0.92, 0.92, 0.94, 1.0)   # 正文：近白
const KEY_COLOR := Color(0.55, 0.95, 1.00, 1.0)    # 按键提示：亮青
const FONT_SIZE_TITLE := 10
const FONT_SIZE_BODY := 8

func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不吃鼠标（键盘驱动）
	visible = false

func _draw() -> void:
	# 全屏半透明底
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, DIM_ALPHA))
	# 面板
	draw_rect(Rect2(PANEL_X, PANEL_Y, PANEL_W, PANEL_H), PANEL_BG)
	draw_rect(Rect2(PANEL_X, PANEL_Y, PANEL_W, PANEL_H), PANEL_BORDER, false, 1.0)
	var font := GameConstants.ui_font()
	# 标题（面板顶部居中）
	draw_string(font, Vector2(PANEL_X, PANEL_Y + 16), Loc.t("depart.confirm.title"),
		HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, FONT_SIZE_TITLE, TITLE_COLOR)
	# 正文（中部居中）
	draw_string(font, Vector2(PANEL_X, PANEL_Y + 34), Loc.t("depart.confirm.body"),
		HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, FONT_SIZE_BODY, BODY_COLOR)
	# 按键提示（下部居中）
	draw_string(font, Vector2(PANEL_X, PANEL_Y + 52), Loc.t("depart.confirm.keys"),
		HORIZONTAL_ALIGNMENT_CENTER, PANEL_W, FONT_SIZE_BODY, KEY_COLOR)
