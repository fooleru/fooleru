# DepartTile · 第 100 层基地的「出发瓦片」（R-113 新增）
# ==============================================================================
# 【用户需求逐字 · team-lead 转述】
#   「在100层绘制一个用于出发的瓦片，进入99层之前重新生成敌人和宝箱中的物品也就是复位。」
#   「（用户第一轮拍板）出发瓦片 = **踩上 + 按键确认**，不自动触发。」
# ==============================================================================
# 【为什么用 `_draw` 手绘、而不是加 Sprite2D / 改 Main.tscn】
#   ① 与 `ReturnBtn.gd`（R-112）同款取舍：**代码 new 节点，不动 Main.tscn** ——
#      少改一个 .tscn = 少一个回归面（R-68 / R-112 两次教训）。
#   ② 本工程**零图片资源**（UI 全部手绘几何），加图片会破坏这一既有约定。
#   ③ 它是**世界空间**节点（挂在 `$TestRoom` 下、跟着摄像机走），不是 UI 层。
#
# 【⚠ 为什么是 Node2D 而不是 Control —— 与 ReturnBtn 的区别，勿混淆】
#   `ReturnBtn` 是**屏幕右下角的 UI 按钮** → 需要鼠标命中 → 必须 `Control`。
#   本瓦片是**画在地板上的世界物件** → 只需要 `position` + `_draw()` → `Node2D` 足够。
#   ⚠ **不要**给本文件加 `_gui_input` / `accept_event()`：它们是 `Control` 独有的
#     （`ReturnBtn.gd` 文件头记录了这个坑：Node2D 上访问 `gui_input` 会 Parse Error）。
#
# 【输入链路：为什么按键判定在 Main 而不在这里】
#   键位 `E` 由 `Main._unhandled_input()` 捕获（与 `F`/`V`/`Tab`/`M` 同一条链），
#   再调 `Main._try_depart()`。本节点**只负责画** + 提供命中判定。
#   ⚠ 分层好处：状态变更全在 Main（表现层不持有游戏状态，R-112 约定），
#     且无头验证能走**真实输入链路**（`Main._send_key(KEY_E)` → `push_input`）。
#   ⚠ headless 下 `push_input` **不会**派发到 `Control._gui_input`（R-112 实测），
#     但 `_unhandled_input` 是**正常派发**的 —— 这是键位判定必须放 Main 的第二个理由。
#
# 【🔴 R-128：世界空间**禁止任何文字** —— 一条铁律，勿再犯】
#   用户拍板逐字：「出发点下面不要写'出发'，游戏场景内不能出现类似的提示性文字，
#                   游戏场景的文字只能出现在美术素材中。」
#   → 本文件**已删除**方块下方的 `draw_string(... Loc.t("depart.label") ...)` 常驻标签，
#     连带删除随之失去用途的常量 `LABEL_DY` / `LABEL_COLOR` / `LABEL_ACTIVE_COLOR` /
#     `FONT_SIZE`（避免死常量留存）。
#   → 现在本瓦片的全部视觉 = **一个 12×12 实心黄方块**（站上去变亮）。零文字。
#   ⚠ **为什么这条不能靠"这个节点特殊"绕过**：它是**世界空间**物件（挂在 `$TestRoom` 下、
#     跟着摄像机走）。屏幕空间（CanvasLayer / `scenes/ui/*`）的提示文字是**允许的**
#     ——「按 F 进入下一层」走底部 `hint` 通道，那属于 UI，不属于游戏场景。
#     分界线是**空间**，不是"哪个更重要"：**世界里的东西只能靠美术素材表达语义**。
#   ⚠ 语义怎么传达？靠**形状 + 颜色 + 动态**：黄方块（唯一性、可交互的暖色）
#     + 站上去提亮（`BLOCK_ACTIVE`）构成完整反馈链。**文字不是这条链的一部分。**
#   ⚠ 若将来认为"玩家可能看不懂这个方块是干什么的"，正解是**在美术素材里做一张带图形的
#     地面贴图**（如带方向箭头的地板贴图），**不是**在这里 `draw_string`。
#   ⚠ 机器守护：`--verify-loc ①-d` 现在对 `scenes/world|player|enemies|furniture|weapons/`
#     做源码 grep —— 这些目录里出现任何 `draw_string(` 即 FAIL。
#
# 【⚠ 站上提示为什么走屏幕底部 `hint` 通道，而不是画在瓦片脚下】
#   R-122 起就是如此，本轮只是把**瓦片脚下那个标签**也一并删干净。
#   底部 `hint` 通道（R-65）是既有契约，且「按 F 进入下一层」属于**屏幕空间 UI**，
#   不受本节铁律约束。`--verify-hint` 逐字断言它的文案。
#
# 【⚠ 为什么不参与战争迷雾（R-70）—— 一个刻意的决定，理由如下】
#   `_update_object_visibility()`（R-70）会按`_fog.is_visible_world(pos)` 隐藏
#   **敌人 / 箱子 / 掉落 / 出口标记**。本瓦片**刻意不在那个名单里**：
#     · 更重要：出发瓦片是**唯一**的离开基地途径。若它被迷雾藏起来，
#       玩家在基地里「看不见路」，那是**功能性阻断**，不是体验优化。
#   → 结论：**不做「按迷雾隐藏/显示」的开关**（`visible` 与迷雾解耦）。
#   ⚠⚠ **R-124 修正一条原本写错的注释（实测推翻）**：这里原写「出生点所在格**恒为可见**，
#     所以迷雾隐藏瓦片在任何情况下都不会发生」——**这是错的**。
#     实测（quality-lead-r124 复核）：玩家站在 spawn 时瓦片格 = `FOG_VISIBLE`；
#     但玩家一旦走开，该格会降为 `FOG_EXPLORED`，`FogOverlay` 以
#     `FOG_EXPLORED_DIM_ALPHA = 0.55` 覆盖 → **瓦片被压暗到约 45% 亮度**。
#     → 真实行为是「常驻**可见**、但走远会**被压暗**」，不是「亮度也恒定」。
#     功能上可接受（不阻断交互，走回来就恢复 VISIBLE），故本批**不改行为**、只改注释。
#     ⚠ 若将来认为"出发点是唯一出路，绝不该变暗"，正确改法是给瓦片在
#       `FogOverlay` 里开一个例外通道，**不是**把它塞进 `_update_object_visibility()`
#       （后者只会让它在 EXPLORED 时直接不可见，更糟）。
#   ⚠ 若将来基地被改造成「多房间手工场景」，且瓦片被移出出生点旁，
#     则**必须**重新评估这条（例如改成「靠近到 200px 内就淡入」），否则玩家可能找不到出口。
#   ⚠ R-124 补充：瓦片位置现在是「原出口标记处」(20,15)，**不再**是"出生点旁 32px"（虽仍相距 32px）。
#
# 【视觉：纯手绘几何 · 零文字（R-128）】
#   ⚠ **R-124 改版**：旧视觉（16×16 方框 + 向下实心三角 + 英文 `DEPART`）**已废弃**。
#   用户拍板：「第 100 层不应该有『出口标记』，请统一成『出发点』，用黄方块表示，
#              并且位置也设定在现在黄方块处。」
#   → 现值 = **实心黄方块 12×12**（`BLOCK_HALF 6.0` / `BLOCK Color(0.95,0.85,0.30,1)`），
#     **逐字对齐** `Main.tscn` 里 `ExitMarker` 的 `polygon`/`color`；
#     玩家站上去时方块提亮为 `BLOCK_ACTIVE`。
#   → **R-128：方块下方的「出发」文字标签已删除**（世界空间禁止文字，见文件头铁律段）。
#     随之删除 `LABEL_DY` / `LABEL_COLOR` / `LABEL_ACTIVE_COLOR` / `FONT_SIZE`。
#   → 位置：不再是"出生点右侧 34px"，而是**原出口标记那处**（见 Main `_depart_tile_pos()`）；
#     同时 `ExitMarker` 在第 100 层**恒隐藏**（`Main._update_object_visibility`）→
#     第 100 层只剩一个黄方块，就是出发点。
#   ⚠ 全部几何尺寸都是**字面量**（R-96 教训：不许从别处推导）。
#   ⚠ 摄像机 zoom = 1（`Main.tscn` 未设 zoom）→ 1 世界 px == 1 屏幕 px。
# ==============================================================================
extends Node2D

# ---- 被测钩子（供 `--verify-depart` 断言；**不参与**绘制与命中逻辑）----
var stand_count: int = 0      # 玩家「站上」状态由 false 变 true 的次数（提示出现次数）

# ---- 几何 / 配色（全部为**字面量**，不得从别处推导 —— R-96 教训）----
# R-124：用户拍板 —— 第 100 层**不再有「出口标记」**，统一成「出发点」，
#   **用黄方块表示**，且位置就设在原来那个黄方块（`ExitMarker`）处。
#   ⚠ 因此本文件的几何/配色**逐字对齐 `Main.tscn` 的 `ExitMarker`**：
#     · `ExitMarker` = `Polygon2D`，`polygon = (-6,-6, 6,-6, 6,6, -6,6)`（12×12）
#     · `color = Color(0.95, 0.85, 0.30, 1)`
#   → `BLOCK_HALF 6.0` + `BLOCK Color(0.95,0.85,0.30,1)` 与它**完全一致**，
#     玩家看到的仍是"原来那个黄方块"，只是它现在的身份是**出发点**、踩上去会亮。
#   ⚠ 旧视觉（16×16 方框 + 向下实心三角 + `depart.label`）中，
#     **方框与三角已删除**（`HALF`/`FRAME_W`/`TRI_*` 全部移除，避免死常量留存）。
const BLOCK_HALF := 6.0          # 半边长：12×12，**逐字等于** ExitMarker 的 polygon
const BLOCK := Color(0.95, 0.85, 0.30, 1.00)        # 常驻：黄方块（= ExitMarker 原色）
const BLOCK_ACTIVE := Color(1.00, 0.95, 0.55, 1.00) # 玩家站上：亮黄（"可交互"高亮）
# 🔴 R-128：`LABEL_DY` / `LABEL_COLOR` / `LABEL_ACTIVE_COLOR` / `FONT_SIZE` **已删除** ——
#   方块下方的「出发」文字标签违反「世界空间禁止文字」铁律（见文件头）。
#   当时的取值记录在案，**只供考古、不要照抄回来**：
#     · `FONT_SIZE := 8`（与 Hint.gd / ReturnBtn.gd 同字号）
#     · `LABEL_DY := 18.0`（基线相对瓦片中心下移；实测 ui_font 在 font 8 下
#       ascent=9 / descent=3 / height=12，行盒顶 = center+9 → 3px 间隙）
#     · `LABEL_COLOR := Color(0.99,0.90,0.35,0.80)` / `LABEL_ACTIVE_COLOR := Color(1.00,0.98,0.70,1.00)`
# ⚠ R-122：站上瓦片时的「按 F 进入下一层」提示**从来就不在本文件画**——
#   它由 `Main._update_hint` 下发到**屏幕底部 hint 通道**（`scenes/ui/Hint.gd`），
#   属屏幕空间 UI，不受"世界空间禁止文字"铁律约束。
#   `PROMPT_KEY` 保留：`_ready()` 用它做「屏幕提示文案含键名 F」的一致性自证。
const PROMPT_KEY := "depart.prompt_select"   # ← Loc 表的 key（不是文案本身）

## 本瓦片中心的世界坐标（Main 在 `_build_floor` 里设 `position`）
func tile_pos() -> Vector2:
	return global_position

## 玩家是否站上了本瓦片（`Main._try_depart()` 与提示显示共用同一判定 —— 单一真相源）
func player_stands_on(player_pos: Vector2) -> bool:
	return global_position.distance_to(player_pos) <= GameConstants.DEPART_TILE_RADIUS

func _ready() -> void:
	# ⚠ 屏幕底部提示文案与键名常量的一致性自证。
	#   `GameConstants.DEPART_KEY_LABEL` 是键名的唯一真相源，而文案由
	#   `Main._update_hint` → `Loc.t(PROMPT_KEY)` 绘制（**屏幕空间**，不是世界空间）。
	#   ⚠ R-117：断言对象必须是**真实绘制路径**（`Loc.t(PROMPT_KEY)`）而不是本地字面量 ——
	#     后者会让断言在"文案改了但本地常量没改"时变成假绿。
	#   ⚠ R-128：本条**与"世界空间禁止文字"铁律不冲突** —— 它守的是屏幕空间那条提示。
	if not Loc.t(PROMPT_KEY).contains(GameConstants.DEPART_KEY_LABEL):
		push_error("DepartTile: 屏幕提示 '%s' 未包含键名 '%s' —— 提示与实际按键不符" % [
			Loc.t(PROMPT_KEY), GameConstants.DEPART_KEY_LABEL])
	visible = false   # Main 在 `_build_floor` 里显式 `visible = is_base_floor(...)`
	queue_redraw()

## 供 Main 每帧推入玩家站位（与 R-80「Main 推给视图」的单向数据流一致）
## ⚠ 用 `false → true` 的**上升沿**计次：这样"提示出现次数"与"每帧都在瓦片上"是两种数，
##   验证能区分「一直站着」（+1）与「反复上下」（+N）。
func set_player_on(on: bool) -> void:
	if _player_on == on:
		return
	if on:
		stand_count += 1
	_player_on = on
	queue_redraw()

func _draw() -> void:
	# R-124：**实心黄方块**（12×12）—— 用户拍板的唯一视觉。
	#   `BLOCK` 逐字等于 `Main.tscn` 的 `ExitMarker.color`，所以玩家看到的仍是
	#   "原来那个黄方块"，只是它现在的身份是**出发点**。
	# 🔴 R-128：本函数**只有这一行绘制**。原来下面的 `draw_string("出发")` 已删 ——
	#   世界空间禁止文字（文件头铁律段）。站上时的反馈只剩「方块提亮」。
	var block_col: Color = BLOCK_ACTIVE if _player_on else BLOCK
	draw_rect(Rect2(-BLOCK_HALF, -BLOCK_HALF, BLOCK_HALF * 2.0, BLOCK_HALF * 2.0), block_col, true)
	# ⚠ 站上时的「按 F 进入下一层」由 `Main._update_hint` 下发到**屏幕底部 hint 通道**绘制
	#   （`scenes/ui/Hint.gd`），**不在世界空间**。本节点保留「站上提亮」的视觉反馈
	#   与 `stand_count`（`--verify-depart` 用）。

# 玩家是否站上（由 Main 推入；本节点**不反向查询** Player/Main —— R-112 单向数据流）
var _player_on: bool = false
