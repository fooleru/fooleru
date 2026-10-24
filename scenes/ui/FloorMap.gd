# FloorMap · 楼层地图叠加层（R-56 新增，按 M 显示/隐藏；R-70 复用战争迷雾）
# 把生成器的网格烘焙成一张 ImageTexture（一次性），绘制时只画「贴图 + 玩家/出口点」→ 快
# 屏幕空间（挂在 CanvasLayer），不随摄像机移动；每次 `_build_floor` 由 Main 重新 set_floor。
# R-70：与主视角世界**复用同一份 FogGrid**——未探索格画全黑、已探索/可见格画正常地形色；
#       玩家 / 出口标记**仅在其所在格非「未探索」时**绘制；不画敌人 / 箱子（仅地形，不透视）。
extends Node2D

const CELL := 2            # 每个 tile 在屏幕上的像素（128×86 → 256×172，居中于 320×180）
const WALL_COLOR := Color(0.32, 0.30, 0.28, 1)
const FLOOR_COLOR := Color(0.14, 0.14, 0.18, 1)
const BLACK := Color(0.0, 0.0, 0.0, 1)              # 未探索：全黑（无信息）
const PLAYER_COLOR := Color(0.40, 0.78, 1.0, 1)
const EXIT_COLOR := Color(0.95, 0.85, 0.30, 1)
const BG_COLOR := Color(0.0, 0.0, 0.0, 0.82)       # 半透明底，压暗游戏画面
const BORDER_COLOR := Color(0.48, 0.48, 0.54, 1)
const TITLE_COLOR := Color(0.85, 0.85, 0.90, 1)
# ==== R-110 crate trace markers ====
# 用户拍板：显示所有未打开宝箱，**包括迷雾黑区（未探索）**。
# DESIGN TENSION (user knowingly accepted): R-70 迷雾语义是「未探索 = 无信息」。
#   本功能故意在黑区也画标记。代价 = 玩家能瞄到没走过的区域，削弱探索张力。
#   缓解：只给位置（不给类型/距离数字）+ 1 游戏小时冷却 + 一次只暴露 3 个。
#   要收回时：只需在下面的 _draw() 里加回fog gating（一处）。
# 与 TraceArrows.ARROW_COLOR 同色是刻意的（同源同色，两种视觉一个含义）。
const MARK_COLOR := Color(0.30, 1.0, 0.55, 1)
const MARK_SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const MARK_SIZE := 7.0
# ==== R-147：视野扫描的两类新标记 ====
#   · 敌人红点 = **临时**（5 秒窗口内显示，窗口结束即撤）
#   · 宝箱方块 = **持久**（按箱子类型着色；`opened` 与否**不影响**——用户逐字
#     「已经发现的宝箱，无论是否打开过，都要用不同颜色标记出来」）
# ⚠ 宝箱颜色**不在这里写死**：由 Main 从 `GameConstants.CRATE_TYPES[kind]["color"]`
#    取了推过来 —— 与 art-bible「调色板唯一来源」同源纪律，避免两处色值打架。
const ENEMY_DOT_COLOR := Color(1.0, 0.22, 0.22, 1)
const ENEMY_DOT_SHADOW := Color(0.0, 0.0, 0.0, 0.85)
const ENEMY_DOT_RADIUS := 2.5
const CRATE_MARK_SIZE := 6.0

var _img: Image = null
var _tex: ImageTexture = null
var _grid: PackedByteArray = PackedByteArray()
var _cols: int = 0
var _rows: int = 0
var _origin: Vector2 = Vector2.ZERO
var _exit: Vector2 = Vector2.ZERO
var _player: Node2D = null
var _tile: float = 16.0
var _floor_no: int = 0            # R-new（2026-10-21）：层号（标题用；0 = 未设置）
var _fog = null                  # FogGrid 实例（preload，无 class_name → 不标注类型）
# R-110：宝箱定位标记（世界坐标 + 闪烁相位）。
# 与 TraceArrows 共用**同一份数组**（Main 把同一个 Array 推给两个节点）
#   -> 「地图标记与边缘箭头指向一致」是构造性保证，不靠两处各算一遍。
var _mark_pos: Array = []
var _mark_shown: bool = false
# ==== R-147 视野扫描层（两类标记，生命周期**故意不同**）====
# · `_enemy_dots`：**临时**。世界坐标数组，只活 5 秒（由 Main 的计时器拥有），
#     窗口结束 Main 调 `set_scan_layer([], ...)` 把点撤掉。
# · `_crate_marks`：**持久**。元素 = [world_pos: Vector2, color: Color]。
#     ⚠ **画不画由本节点按 fog 现判**（见 `_draw()`），不靠 Main 在推送时过滤 ——
#     理由：「该宝箱已被发现」≡「它所在格已探索」，而 fog 是这一事实的**唯一真相源**。
#     Main 只管「这层有哪些箱子、各是什么颜色」；判"发现没发现"交给 fog，
#     于是自动获得：①跨层往返仍显示 ②开箱后仍显示 ③重新生成该层时随 fog 一起重置。
#     若改成 Main 在 V 键那一刻快照一份"已发现箱子 id 列表"，就成了第三份状态，
#     会与 fog 漂移（典型 bug：开了箱回到地图标记却没了 / 换层后错位）。
var _enemy_dots: Array = []
var _crate_marks: Array = []

# 由 Main 在每层生成后调用（fog = 与主视角世界共用的 FogGrid）
func set_floor(grid: PackedByteArray, cols: int, rows: int, exit_pos: Vector2, player_ref: Node2D, tile: float, fog = null, floor_no: int = 0) -> void:
	# ⚠ R-new（2026-10-21）：末尾新增 floor_no（带默认值，旧调用点不破）→ 标题显示层号。
	_floor_no = floor_no
	_grid = grid
	_cols = cols
	_rows = rows
	_exit = exit_pos
	_player = player_ref
	_tile = tile
	_fog = fog
	_bake()

# M 键打开时用当前迷雾重新烘焙（探索进度可能已变）
func refresh() -> void:
	if _cols == 0 or _rows == 0:
		return
	_bake()

# ==== R-110 宝箱定位标记 ====
# `world_positions`：目标**世界坐标**（<=3 个）。`shown`：闪烁相位（true = 亮）。
# 刻意**不依赖 `visible`**：5 秒窗口由 Main 的计时器拥有，
#   玩家在标记期间按 M 开/关地图既不暂停也不重置它 —— 本节点只管「画不画」。
func set_markers(world_positions: Array, shown: bool) -> void:
	_mark_pos = world_positions.duplicate()
	_mark_shown = shown
	queue_redraw()

func clear_markers() -> void:
	if _mark_pos.is_empty() and not _mark_shown:
		return
	_mark_pos = []
	_mark_shown = false
	queue_redraw()

# ---- headless 探针（--verify-trace 的断言面）----
func marker_positions() -> Array:
	return _mark_pos.duplicate()

# ---- headless 探针（--verify-fog-off 的断言面）----
# R-141：基地层(100) 时 `Main._build_floor` 故意把 fog 传 null → 地图走「无迷雾」分支。
# 为什么需要它：地图的 `_fog` 是私有的，而「基地层全图可见」这条需求**只对地图**的
#   证据就是「没绑迷雾」；没有探针就只能靠「地形色不是黑」间接推断（弱，且会被
#   「基地层本来就没有黑格」这类巧合放行）。
# 只暴露「绑没绑」，不暴露 FogGrid 引用本身 —— 外部想验三态应走 `Main._fog`。
func fog_bound() -> bool:
	return _fog != null

func markers_shown() -> bool:
	return _mark_shown

# ==== R-147 视野扫描层推送入口 ====
# `enemy_dots`：敌人**世界坐标**数组（临时，5 秒）。`crate_marks`：本层全部箱子
#   [[pos, color], ...]（持久；画不画由 `_draw()` 按 fog 现判）。
# 为什么**单独一个入口**而不塞进 `set_floor()`：
#   `set_floor()` 是"换层重建"语义（7 参），两处调用点（Main.gd:2914 / :3856）都在
#   建层流程里；扫描层是"运行时高频推送"（敌人每帧会动）。混进同一入口会让
#   「刷敌人点」顺带把整张地形贴图重新烘焙一遍（`_bake()` 是 128×86 全图循环）。
func set_scan_layer(enemy_dots: Array, crate_marks: Array) -> void:
	_enemy_dots = enemy_dots.duplicate()
	_crate_marks = crate_marks.duplicate()
	queue_redraw()

# 5 秒窗口结束：只撤敌人红点，**保留**宝箱（宝箱由 fog 决定，不随窗口消失）
func clear_enemy_dots() -> void:
	if _enemy_dots.is_empty():
		return
	_enemy_dots = []
	queue_redraw()

# ---- headless 探针（--verify-scan 的断言面）----
func enemy_dot_positions() -> Array:
	return _enemy_dots.duplicate()

# 返回**当前实际会画出来**的宝箱标记（已按 fog 过滤）——验证要断言的是
#   「地图上真能看到几个」，不是「Main 推了几个」，所以过滤必须在这里做、探针才能看见。
func visible_crate_marks() -> Array:
	var out: Array = []
	for e in _crate_marks:
		var wp: Vector2 = e[0]
		if _fog == null or _fog.state_at_world(wp) != GameConstants.FOG_UNEXPLORED:
			out.append(e)
	return out

# 标记的屏幕像素位置（世界 -> tile -> 像素）。
# 必须复用 `_tile_of()`，不在这里另写一份 int(pos.x)/tile ——
#   R-104 已踩过「同一换算写两遍、后来只改一处」的坑。
func marker_screen_pos(world_pos: Vector2) -> Vector2:
	var t: Vector2 = Vector2(_tile_of(world_pos))
	return _origin + t * float(CELL)

func _bake() -> void:
	var img := Image.create(_cols, _rows, false, Image.FORMAT_RGBA8)
	for y in _rows:
		for x in _cols:
			var st: int = GameConstants.FOG_VISIBLE
			if _fog != null:
				st = _fog.state_at_tile(Vector2i(x, y))
			if st == GameConstants.FOG_UNEXPLORED:
				img.set_pixel(x, y, BLACK)          # 未探索：全黑
			else:
				img.set_pixel(x, y, WALL_COLOR if _grid[y * _cols + x] == 0 else FLOOR_COLOR)
	_img = img
	# headless（无渲染）下不建 GPU 贴图，避免报错；尺寸断言走 _img
	if DisplayServer.get_name() != "headless":
		_tex = ImageTexture.create_from_image(img)
	var map_size := Vector2(_cols * CELL, _rows * CELL)
	# ⚠⚠ R-new（2026-10-21）：按**设计空间**居中，不是真实视口 ——
	#   本节点被 Main._apply_ui_scale 放大 UI_SCALE 倍（实际 640×360），
	#   而 `_origin` 是**节点局部坐标**（会被一起放大）→ 用真实视口算会偏出屏幕。
	#   真实视口 / UI_SCALE 才是本节点的局部空间 → 用 DESIGN_W/H 显式表达。
	var design_size := Vector2(GameConstants.DESIGN_W, GameConstants.DESIGN_H)
	_origin = ((design_size - map_size) * 0.5).floor()
	queue_redraw()

# 供 headless 验证：地图以 tile 计的尺寸
func map_tiles() -> Vector2i:
	return _img.get_size() if _img != null else Vector2i.ZERO

# 供 headless 验证：读取烘焙贴图的 CPU 像素（真取样）
func pixel_at_tile(x: int, y: int) -> Color:
	if _img == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	if x < 0 or x >= _img.get_width() or y < 0 or y >= _img.get_height():
		return Color(0.0, 0.0, 0.0, 0.0)
	return _img.get_pixel(x, y)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # 玩家点会移动，需要重绘

func _tile_of(pos: Vector2) -> Vector2i:
	var t: int = int(_tile)
	return Vector2i(int(pos.x) / t, int(pos.y) / t)

func _draw() -> void:
	if _cols == 0 or _rows == 0:
		return
	var vp: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG_COLOR)
	var map_size := Vector2(_cols * CELL, _rows * CELL)
	if _tex != null:
		draw_texture_rect(_tex, Rect2(_origin, map_size), false)
	else:
		draw_rect(Rect2(_origin, map_size), FLOOR_COLOR)
	draw_rect(Rect2(_origin, map_size), BORDER_COLOR, false, 1.0)
	# ⚠⚠ R-new（2026-10-21）：**层号标题 + 关闭提示** —— 大地图此前**零文字**，
	#   玩家不知道自己在第几层、也不知道怎么关。画在地图内左上角（不被边框压住）。
	if _floor_no > 0:
		var font := GameConstants.ui_font()
		var title: String = "第 %d 层" % _floor_no
		draw_string(font, _origin + Vector2(6.0, 14.0), title, HORIZONTAL_ALIGNMENT_LEFT,
			map_size.x - 12.0, 10, TITLE_COLOR)
		draw_string(font, _origin + Vector2(6.0, 26.0), Loc.t("map.close_hint"),
			HORIZONTAL_ALIGNMENT_LEFT, map_size.x - 12.0, 8, Color(0.70, 0.78, 0.88, 1.0))
	# 出口（仅当其所在格非「未探索」时绘制；持久标记语义：仅坐标、不透视地形/敌人）
	# ⚠ **R-124 语义说明（不改行为）**：用户拍板「第 100 层**不应该有出口标记**，
	#   统一成**出发点**，用黄方块表示，并且位置也设定在**现在黄方块处**」。
	#   而 `Main._depart_tile_pos()` 现在返回的就是 `exit_marker.position`，
	#   且 `Main` 传给 `set_floor()` 的 `exit_pos` 也是同一处 ——
	#   → **基地层小地图上这一个方块，位置与颜色都与世界里的「出发点」逐字重合**，
	#     所以它已经是"出发点"的标记，不需要为基地层单独分支。
	#   ⚠ 若将来基地的出发点被移离出口坐标，本处**必须**改为读出发点坐标，
	#     否则小地图会画出两个不一致的黄点。
	if _fog == null or _fog.state_at_world(_exit) != GameConstants.FOG_UNEXPLORED:
		var e := _origin + (_exit / _tile) * CELL
		draw_rect(Rect2(e - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), EXIT_COLOR)
	# 玩家（所在格恒非未探索；防御式判定）
	if _player != null and is_instance_valid(_player):
		if _fog == null or _fog.state_at_world(_player.global_position) != GameConstants.FOG_UNEXPLORED:
			var p := _origin + (_player.global_position / _tile) * CELL
			draw_circle(p, 2.0, PLAYER_COLOR)
	# ==== R-110 宝箱定位标记 ====
	# 刻意**不做迷雾 gating**（用户拍板：未探索黑区的宝箱也要标出）。
	#   对比：上面出口/玩家标记都判了 FOG_UNEXPLORED —— 那是 R-70 的「不透视」语义，
	#   本功能**故意不同**（设计张力见 MARK_COLOR 上方说明）。
	if _mark_shown and not _mark_pos.is_empty():
		for wp in _mark_pos:
			var mp: Vector2 = marker_screen_pos(wp)
			var h := float(MARK_SIZE) * 0.5
			# 1px 黑影打底 -> 在纯黑（未探索）与白 medical 箱上都读得出形状
			draw_rect(Rect2(mp - Vector2(h, h) - Vector2(0.5, 0.5), Vector2(MARK_SIZE + 1.0, MARK_SIZE + 1.0)), MARK_SHADOW)
			draw_rect(Rect2(mp - Vector2(h, h), Vector2(MARK_SIZE, MARK_SIZE)), MARK_COLOR)
	# ==== R-147 宝箱标记（**持久**，按类型着色）====
	# ⚠ 这里是唯一一处"发现判定"：`fog.state_at_world() != UNEXPLORED`。
	#   与 `opened` **完全无关** —— 用户逐字「无论是否打开过，都要用不同颜色标记出来」。
	#   颜色由 Main 从 `GameConstants.CRATE_TYPES[kind]["color"]` 取来（本文件不写死色值）。
	for e in _crate_marks:
		var cwp: Vector2 = e[0]
		if _fog != null and _fog.state_at_world(cwp) == GameConstants.FOG_UNEXPLORED:
			continue                                  # 没探索到 = 没发现 = 不画
		var cp: Vector2 = marker_screen_pos(cwp)
		var ch := float(CRATE_MARK_SIZE) * 0.5
		draw_rect(Rect2(cp - Vector2(ch, ch) - Vector2(0.5, 0.5), Vector2(CRATE_MARK_SIZE + 1.0, CRATE_MARK_SIZE + 1.0)), MARK_SHADOW)
		draw_rect(Rect2(cp - Vector2(ch, ch), Vector2(CRATE_MARK_SIZE, CRATE_MARK_SIZE)), e[1])
	# ==== R-147 敌人红点（**临时**，5 秒窗口）====
	# 不做 fog gating：V 扫描刚把半径内全升为已探索，红点必然落在已探索区；
	#   且"短暂透视"正是本功能的意图（用户逐字「无视墙壁等瓦片的遮挡」）。
	for wp2 in _enemy_dots:
		var dp: Vector2 = marker_screen_pos(wp2)
		draw_circle(dp, ENEMY_DOT_RADIUS + 0.5, ENEMY_DOT_SHADOW)
		draw_circle(dp, ENEMY_DOT_RADIUS, ENEMY_DOT_COLOR)
