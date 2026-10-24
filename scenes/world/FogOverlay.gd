# FogOverlay · 世界战争迷雾覆盖层（cp2 · R-70 · art-bible §6 A-03 三态遮罩 / §6 渲染次序）
# 独立 CanvasLayer 内（layer=9：高于世界、低于 HUD=10；follow_viewport_enabled → 与世界同坐标系、随摄像机滚动）。
# 原型级实现（口径⑤：不引入光照系统、允许不用 shader）：
#   未探索 = 不透明黑；
#   已探索 = 压暗（黑覆盖 alpha≈0.55 → 结果亮度≈0.45，保色相，对齐 art-bible §6 R-22 的 ×0.45 口径）；
#   可见 = 全透明。
# 逐 tile 烘焙成一张 ImageTexture（每 tile 1 px，最近邻拉伸到世界尺寸 → 整屏 1 次绘制调用）。
# ⚠ 禁用 class_name → Main 用 @onready 引用本节点。
extends Node2D

var _img: Image = null
var _tex: ImageTexture = null
var _cols: int = 0
var _rows: int = 0
var _tile: float = 16.0

func _ready() -> void:
	# 迷雾遮罩不做插值、不吃光照 → 最近邻，保持 tile 硬边
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

# 由 Main 在迷雾变化时调用：把三态栅格烘焙成覆盖贴图
func refresh(fog) -> void:
	if fog == null:
		return
	var cols: int = fog.cols()
	var rows: int = fog.rows()
	if cols <= 0 or rows <= 0:
		return
	_cols = cols
	_rows = rows
	_tile = GameConstants.TILE
	if _img == null or _img.get_width() != cols or _img.get_height() != rows:
		_img = Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	var tiles: Array = fog.tiles()
	for y in rows:
		for x in cols:
			var st: int = int(tiles[y * cols + x])
			var a: float = 0.0
			if st == GameConstants.FOG_UNEXPLORED:
				a = 1.0                                                                # 未探索：全黑（不透明、无信息）
			elif st == GameConstants.FOG_EXPLORED:
				a = GameConstants.FOG_EXPLORED_DIM_ALPHA                               # 已探索：压暗（保色相）
			# ==== R-new（2026-10-22）：视野边缘软过渡 ====
			# 取 min(持久alpha, 过渡环渐变量)：可见圈(0) → 过渡环(0.18/0.37) → 已探索(0.55)
			#   ⇒ 半径扩大后圈外不再有"全亮直接跳黑"的硬边，亮度连续衔接。
			#   LOS 门控在 FogGrid.edge_fade 内部（墙后不亮）。
			var edge: float = fog.edge_fade(Vector2i(x, y))
			if edge > 0.0:
				a = minf(a, edge)
			var c := Color(0.0, 0.0, 0.0, a)
			_img.set_pixel(x, y, c)
	# headless（无渲染）下不建 GPU 贴图，避免报错；像素断言走 CPU 侧 _img
	if DisplayServer.get_name() != "headless":
		_tex = ImageTexture.create_from_image(_img)
	queue_redraw()

# 供 headless 验证：读取覆盖贴图的 CPU 像素（真取样，不是标志位）
func pixel_at_tile(x: int, y: int) -> Color:
	if _img == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	if x < 0 or x >= _img.get_width() or y < 0 or y >= _img.get_height():
		return Color(0.0, 0.0, 0.0, 0.0)
	return _img.get_pixel(x, y)

func _draw() -> void:
	if _tex == null:
		return
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(_cols * _tile, _rows * _tile)), false)
