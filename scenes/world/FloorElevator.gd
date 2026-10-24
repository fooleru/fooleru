# FloorElevator · 战斗层（99–1）「出发点电梯」（R-new 2026-10-22 用户需求）
# ==============================================================================
# 【用户需求逐字】
#   「在游戏的99层及以下每一层目前都存在一个固定出发点，地图生成时在该点正上方绘制
#     一个占据3×3瓦片的电梯，确保出发点位于电梯门口。该点作为每层固定的出发与返回点，
#     当玩家到达此处并按下F键时，触发传送返回100层的基地。」
#
# 【几何（设计口径，全部字面量）】
#   · 出发点 = 每层固定 spawn（生成器 `rooms[0]` 中心，`_floor_spawn`）。
#   · 电梯占 **3×3 瓦片 = 48×48 px**，画在出发点**正上方**：
#       电梯左上 = spawn_pos + (-24, -48)，右下 = spawn_pos + (+24, 0)
#     ⇒ 电梯**底边正好压在出发点格顶边**，出发点格 = 电梯正下方的「门口」。
#   · `player_stands_on()`：与 DepartTile 同一口径（半径判定），站在门口即触发条件。
#
# 【为什么用 `_draw` 手绘、Node2D、不改 Main.tscn】
#   与 DepartTile / ReturnBtn 同款取舍：代码 new 节点，少一个回归面；本工程零图片资源。
#   世界空间节点（挂 `$TestRoom`，跟摄像机走）。
#
# 【🔴 R-128：世界空间禁止任何文字】
#   本文件**只有图形**（金属框 / 电梯井 / 双门 / 向上箭头），零 `draw_string`。
#   「按 F 返回基地」走屏幕底部 hint 通道（Main._update_hint，屏幕空间 UI，合法）。
#
# 【输入链路：为什么按键判定在 Main 而不在这里】
#   与 DepartTile 完全同款：F 由 `Main._unhandled_input()` 捕获 → `Main._try_elevator()`；
#   本节点只负责「画」+ 提供命中判定（R-112 单数据流：表现层不持有游戏状态）。
#
# 【语义表达（无文字怎么让人看懂这是电梯）】
#   形状 + 颜色 + 动效三件套：
#     · 双开门 + 电梯井 = 一眼可辨的电梯轮廓（区别于黄方块出发点）
#     · 井内**向上箭头**（▲ 三角形）= 「往上回基地」的方向语义
#     · 玩家站门口 → 门缝亮起 + 箭头变亮（反馈链完整）
# ==============================================================================
extends Node2D

const ELEV_W := 48.0            # 电梯宽 = 3 瓦片
const ELEV_H := 48.0            # 电梯高 = 3 瓦片
const STAND_RADIUS := 18.0      # 门口命中半径（与 DepartTile.TILE_RADIUS 同口径）

const FRAME_COLOR := Color(0.72, 0.75, 0.82, 1.0)      # 金属框：亮钢灰
const SHAFT_COLOR := Color(0.08, 0.09, 0.13, 0.92)     # 电梯井：深井
const DOOR_COLOR := Color(0.42, 0.46, 0.55, 1.0)       # 双门：钢门
const DOOR_OPEN_COLOR := Color(0.20, 0.22, 0.28, 1.0)  # 开门态（站上时）
const ARROW_COLOR := Color(0.99, 0.90, 0.35, 1.0)      # 向上箭头：暖黄（与出发瓦片同色系）
const ARROW_ACTIVE_COLOR := Color(1.0, 0.98, 0.60, 1.0)# 箭头激活（站上时提亮）
const GLOW_COLOR := Color(0.99, 0.90, 0.35, 0.30)      # 门口光晕（站上时）

var _player_on: bool = false     # 玩家是否站在门口（Main 单向推入）

func _ready() -> void:
	visible = false            # 由 Main 按层设置（仅战斗层可见）
	z_index = 3                # 画在地板之上、墙之前（与 DepartTile 同一区间）

# 由 Main 每帧推入：玩家此刻是否站在门口（本节点不反查 Player，R-112 约定）
func set_player_on(on: bool) -> void:
	if on != _player_on:
		_player_on = on
		queue_redraw()

# 门口命中判定（与 DepartTile.player_stands_on 同一口径：半径而非精确格）
func player_stands_on(p: Vector2) -> bool:
	return p.distance_to(door_pos()) <= STAND_RADIUS

# 门口世界坐标 = 电梯底边中点 = spawn 格中心（Main 把 position 摆在 spawn-(24,48)）
func door_pos() -> Vector2:
	return position + Vector2(ELEV_W * 0.5, ELEV_H)

# 电梯门口下方那一格的地面高亮（站上时的反馈，画在电梯底边下方）
func _draw() -> void:
	if not visible:
		return
	# 电梯井（深色井口）
	draw_rect(Rect2(0.0, 0.0, ELEV_W, ELEV_H), SHAFT_COLOR)
	# 金属外框（四边各 2px）
	draw_rect(Rect2(0.0, 0.0, ELEV_W, 2.0), FRAME_COLOR)
	draw_rect(Rect2(0.0, ELEV_H - 2.0, ELEV_W, 2.0), FRAME_COLOR)
	draw_rect(Rect2(0.0, 0.0, 2.0, ELEV_H), FRAME_COLOR)
	draw_rect(Rect2(ELEV_W - 2.0, 0.0, 2.0, ELEV_H), FRAME_COLOR)
	# 双开门（两扇，中间留门缝）：站门口时门向两侧滑开（变深色 = 开启的井）
	var door_w: float = (ELEV_W - 4.0) * 0.5
	var door_col: Color = DOOR_OPEN_COLOR if _player_on else DOOR_COLOR
	draw_rect(Rect2(2.0, 2.0, door_w - 1.0, ELEV_H - 4.0), door_col)
	draw_rect(Rect2(2.0 + door_w + 1.0, 2.0, door_w - 1.0, ELEV_H - 4.0), door_col)
	# 门缝（井的纵深）
	draw_rect(Rect2(2.0 + door_w, 2.0, 1.0, ELEV_H - 4.0), SHAFT_COLOR)
	# 向上箭头（▲ = 回基地的方向语义）：门上居中，站上时提亮
	var ac: Color = ARROW_ACTIVE_COLOR if _player_on else ARROW_COLOR
	var cx: float = ELEV_W * 0.5
	var cy: float = ELEV_H * 0.5
	var s: float = 7.0
	var tri := PackedVector2Array([Vector2(cx, cy - s), Vector2(cx - s * 0.8, cy + s * 0.6), Vector2(cx + s * 0.8, cy + s * 0.6)])
	draw_colored_polygon(tri, ac)
	# 门口光晕（站上时，画在电梯底边下方那一格 —— 出发点格）
	if _player_on:
		draw_rect(Rect2(-4.0, ELEV_H - 2.0, ELEV_W + 8.0, 6.0), GLOW_COLOR)
