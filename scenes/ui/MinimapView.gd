# MinimapView · 右上角迷你地图（R-new）
# 数据由 Main 在玩家探索（tile 变更 / 迷雾更新 / 建层）与每次扫描标记变化时推送：
#   · 每格 1 字节：0=未探索 1=已探索地面 2=已探索墙
#   · 标记层（**与大地图 M 键同款**，配色逐字取自 FloorMap.gd 同名常量）：
#       exit    = 逃出点（黄 4×4）
#       player  = 玩家（蓝点）
#       crates  = 箱子（按 CRATE_TYPES 着色，1×1 + 黑描边）
#       enemies = 敌人红点（V 扫描后 5 秒内）
# ⚠ 只画形状/色块、**无文字** → 不触发 R-128 世界空间禁文字 guard。
# ⚠ 独立 Node2D：小地图重绘较贵（几千格），与每帧重画的技能按钮解耦。
extends Node2D
class_name MinimapView

var _cells: PackedByteArray = PackedByteArray()
var _cols: int = 0
var _rows: int = 0
var _player: Vector2i = Vector2i(-1, -1)
# 标记（小地图格坐标）。x/y < 0 = 无。
var _exit_cell: Vector2i = Vector2i(-1, -1)
var _crate_cells: Array = []        # [Vector2i, Color]
var _enemy_cells: Array = []        # [Vector2i]

# 与大地图 FloorMap.gd 逐字一致的配色，保证「小地图 == 大地图」的观感统一。
const PLAYER_COLOR := Color(0.40, 0.78, 1.0, 1)
const EXIT_COLOR := Color(0.95, 0.85, 0.30, 1)
const MARK_SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const ENEMY_DOT_COLOR := Color(1.0, 0.22, 0.22, 1)
# R-new【局部视图 · 每格放大】：1 格 = 2×2 像素，96×65 总框显示 48×32 格。
const CELL_PX := 1.0     # 2026-10-22：2→1（窗口 96×64 格 → 总框仍 96×64px，显示尺寸不变）
# R-new（2026-10-22）：整块小地图统一半透明（用户需求 50%~70%）——
#   既保留地图信息可读，又不完全遮挡主画面。用恒定 modulate → 各楼层/场景表现一致。
const MAP_ALPHA := 0.65

func _ready() -> void:
	# R-new【不响应鼠标】：本节点是 **Node2D**（不是 Control），HUD 那套
	#   `_make_mouse_transparent` 只遍历 Control 子节点、对本节点无效。
	#   Node2D 默认会吃掉覆盖区域的鼠标事件 → 会挡住瞄准/开火。故显式关闭。
	set_process_input(false)
	set_process_unhandled_input(false)
	# R-new（2026-10-22）：整块小地图统一半透明（MAP_ALPHA，恒定 → 各楼层/场景表现一致）。
	#   最终有效 alpha ≈ 0.51~0.65（底色 0.86 / 格 0.78~0.85 / 标记 1.0 各 ×0.65），
	#   落在用户要求的 50%~70% 区间：地图信息可读，又不完全遮挡主画面。
	modulate = Color(1.0, 1.0, 1.0, MAP_ALPHA)

func set_data(cells: PackedByteArray, cols: int, rows: int, player: Vector2i,
		exit_cell: Vector2i, crate_cells: Array, enemy_cells: Array) -> void:
	if cols == _cols and rows == _rows and player == _player and exit_cell == _exit_cell \
			and cells == _cells and crate_cells == _crate_cells and enemy_cells == _enemy_cells:
		return                      # 无变化不重画（省 draw call）
	_cells = cells
	_cols = cols
	_rows = rows
	_player = player
	_exit_cell = exit_cell
	_crate_cells = crate_cells
	_enemy_cells = enemy_cells
	queue_redraw()

func clear_data() -> void:
	_cells = PackedByteArray()
	_cols = 0
	_rows = 0
	_player = Vector2i(-1, -1)
	_exit_cell = Vector2i(-1, -1)
	_crate_cells = []
	_enemy_cells = []
	queue_redraw()

func _draw() -> void:
	if _cols <= 0 or _rows <= 0:
		return
	# 外框（1px 描边 + 半透明底板），原点即小地图左上角
	# R-new【半透明】：底板/外框 alpha 压低，叠在战场上不遮视野。
	var w_px: float = float(_cols) * CELL_PX
	var h_px: float = float(_rows) * CELL_PX
	# ⚠⚠ R-new（2026-10-21）：底板/外框**加亮加实** —— 原半透明黑底在「未探索=纯黑」的
	#   区域里与战场 VOID 黑区**融为一体**，小地图看着像"右上角一块黑"（实测）。
	#   改用「深蓝灰实底 + 亮青描边」：即使整块未探索，也能看出这是 UI 面板。
	draw_rect(Rect2(-2.0, -2.0, w_px + 4.0, h_px + 4.0), Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(Rect2(-1.0, -1.0, w_px + 2.0, h_px + 2.0), Color(0.42, 0.62, 0.78, 0.85))
	draw_rect(Rect2(0.0, 0.0, w_px, h_px), Color(0.10, 0.13, 0.20, 0.86))
	var c_floor := Color(0.28, 0.33, 0.42, 0.78)
	var c_wall := Color(0.60, 0.58, 0.52, 0.85)
	var i := 0
	for y in _rows:
		for x in _cols:
			var v: int = _cells[i] if i < _cells.size() else 0
			if v == 1:
				draw_rect(Rect2(float(x) * CELL_PX, float(y) * CELL_PX, CELL_PX, CELL_PX), c_floor)
			elif v == 2:
				draw_rect(Rect2(float(x) * CELL_PX, float(y) * CELL_PX, CELL_PX, CELL_PX), c_wall)
			i += 1
	# ---- 标记层（与大地图一致；fog 门控在 Main 侧做，这里只管画）----
	for e in _enemy_cells:                      # 敌人红点先画，避免被箱子盖住
		var ec: Vector2i = e
		if ec.x >= 0 and ec.y >= 0 and ec.x < _cols and ec.y < _rows:
			draw_rect(Rect2(float(ec.x) * CELL_PX, float(ec.y) * CELL_PX, CELL_PX, CELL_PX), ENEMY_DOT_COLOR)
	for m in _crate_cells:                      # 箱子（按类型着色 + 1px 黑描边）
		var cc: Vector2i = (m as Array)[0]
		var col: Color = (m as Array)[1]
		if cc.x >= 0 and cc.y >= 0 and cc.x < _cols and cc.y < _rows:
			var cx_px: float = (float(cc.x) + 0.5) * CELL_PX - CELL_PX * 0.5
			var cy_px: float = (float(cc.y) + 0.5) * CELL_PX - CELL_PX * 0.5
			draw_rect(Rect2(cx_px - 1.0, cy_px - 1.0, CELL_PX + 2.0, CELL_PX + 2.0), MARK_SHADOW)
			draw_rect(Rect2(cx_px - CELL_PX * 0.5, cy_px - CELL_PX * 0.5, CELL_PX, CELL_PX), col)
	if _exit_cell.x >= 0 and _exit_cell.y >= 0 and _exit_cell.x < _cols and _exit_cell.y < _rows:
		var ex_px: float = (float(_exit_cell.x) + 0.5) * CELL_PX - CELL_PX * 0.5
		var ey_px: float = (float(_exit_cell.y) + 0.5) * CELL_PX - CELL_PX * 0.5
		draw_rect(Rect2(ex_px - CELL_PX, ey_px - CELL_PX, CELL_PX * 2.0, CELL_PX * 2.0), EXIT_COLOR)
	if _player.x >= 0 and _player.y >= 0 and _player.x < _cols and _player.y < _rows:
		draw_rect(Rect2((float(_player.x) + 0.5) * CELL_PX - CELL_PX * 0.5,
			(float(_player.y) + 0.5) * CELL_PX - CELL_PX * 0.5, CELL_PX, CELL_PX), PLAYER_COLOR)
