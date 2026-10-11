# TileGround · R-131 楼层地面/墙面的**真 16px 瓦片渲染层**
# ==============================================================================
# 【本文件解决什么】
#   改造前：楼层地面 = 每房间/走廊一块**纯色 `Polygon2D`**（`Main.FLOOR_COLOR`），
#           墙 = 每块合并矩形一块**纯色 `Polygon2D`**（`Main.WALL_COLOR`）。
#           → 画面是「色块拼图」，没有任何材质、勾缝、砖缝、墙脚。
#   改造后：本节点按**世界格坐标**逐格贴 16×16 瓦片 PNG（`assets/tiles/<theme>/`）：
#           地板 4 变体、墙顶砖砌、墙正面 + 邻接收边 + 墙脚落地阴影。
#
# 【🔴 R-126 事故换来的铁律：瓦片必须程序化生成，AI 图一律不用】
#   实测走完「AI tileset sheet → 切格 → 内缩 → 缩到 16px → 铺图」全链路，
#   结论**不可用**（三条硬原因见 `production/tiles/generate_tiles.py` 文件头）：
#     ① AI 每格带亮框 → 平铺成一摞相框；内缩后左右边缘像素仍不相等 → **不无缝**；
#     ② BOX 降采样丢硬像素 / NEAREST 把噪点原样搬进每格 → **同一格重复成点阵**；
#     ③ 门洞转角格是白底 → 直接漏进场景。
#   → 瓦片由 `production/tiles/generate_tiles.py` **代码生成**（纯整数哈希、可复现）。
#   ⚠ 本文件**只消费** PNG，不新增任何非 PNG 美术资源。
#
# 【为什么在 `_draw` 里逐格画，而不是用 TileMapLayer】
#   ① **墙的「外轮廓」不在瓦片里** —— 邻接收边（北侧受光高光 / 东西侧暗线 /
#      墙脚落地阴影）必须**由地图邻接关系算**，单块瓦片里没有这个信息。
#      TileMapLayer 的 tile 是「一格一图」，画不出「跨格的收边」。
#   ② **墙正面会跨格**：它贴在墙格**底部 6px**，实际落在**下方地板格**里。
#      用 TileMapLayer 就得再开一个 layer 专门错位贴，画序也难保证。
#   ③ 与既有 `FogOverlay.gd` / `DepartTile.gd` 同款做法（`_draw` + 代码 new 节点），
#      **不动 `Main.tscn`**（本工程铁律：少改一个 .tscn = 少一个回归面，R-68/R-112 教训）。
#
# 【为什么贴图挂在 `FloorVis`（index 0）而不是 `Walls`（index 1）】
#   墙的**碰撞体仍然留在 `walls_container`**（`Main._make_wall_rect`，一字未改），
#   但墙的**可视**改由本节点画在地板层。取舍三条：
#     ① 地板与墙顶/墙脚是**同一套贴图、同一套勾缝相位**，分成两个容器两个层级画
#        就必须在两个节点里各写一遍绘制顺序 → 迟早画序漂移。
#     ② 墙正面只有 6px、贴在墙格底缘（伸进地板格），与地板是**跨格咬合**关系；
#        分层画必然出现「墙脚被地板盖住 1px」的接缝。
#     ③ 墙的 1px 收边/落地阴影同理，必须和地板同层一次画完。
#   ⚠ 代价：墙面的**画序**从「Walls 层（玩家之下、敌人之上）」变成「地板层（最底）」。
#     实测无观感回归：墙正面只占**墙格**底部 6px，而敌人 / 箱子 / 掉落物 / 出口标记
#     **永不落在墙格上**（生成器只在地板格上采样它们），故不存在「本该被墙挡住却被画出」的情况。
#
# 【⚠ 性能：为什么按纹理分组画】
#   战斗层世界 128×86 = **11008 格**。逐格 `draw_texture_rect` 若按格子顺序画，
#   相邻格会在 4 张地板贴图之间**反复横跳** → 批次被打散、每帧重放上万次 draw call。
#   → 故先把 Rect2 **按贴图分组**再画：纹理切换从「每格一次」降到「每主题 6 次」。
#   ⚠ 分组**只改变 draw call 顺序，不改变哪格用哪张图**（变体仍按世界格哈希选）。
#
# 【🔴 世界空间零文字铁律（R-128）—— 本文件不得引入任何文字】
#   `--verify-loc ①-d` 对 `res://scenes/world/` 做源码 grep，出现任何文字绘制调用即 FAIL。
#   本文件全部视觉 = 贴图 + 纯色矩形，零文字。
#
# 【调色板唯一来源 =美术权威表】
#   `res://design/art/tile_theme_palettes.json`（art-director-tiles 产出，项目内路径）。
#   邻接收边 / 落地阴影的颜色从**该主题的 8 个槽位**里取，不在代码里硬编码颜色，
#   也不使用 §3.2 语义色（玩家橙 / 血红 / 毒绿 / 电青 / 警告红 / 通行绿 / 鲜绿 ——
#   那些是玩法色，环境瓦片一律不得挪用，art-bible §3 铁律）。
#   ⚠⚠ **第一版曾指向 `res://assets/tiles/tile_palettes.json`（生成器派生表）——
#     该文件已删除**。两个真相源（美术表 → 生成器 → 派生表 → 引擎）会静默分叉：
#     第一版实测派生表全是占位色，而 60 个 headless 入口**照样全绿**
#     （每个入口只验「贴图能不能 load」，不验「贴图颜色对不对」）。
#     现引擎与验证**都直接读美术表**，见下方 `PALETTE_JSON`。
#     ⚠ 本段与 `PALETTE_JSON` 常量必须一致 —— 独立复核（quality-lead-tiles 2026-10-08）
#     就是因为这里与常量自相矛盾而报出的缺陷。
# ==============================================================================
extends Node2D

## 瓦片边长(px)。**必须**与生成器 `TILE`、以及 `FloorGenerator.TILE` 一致。
const TILE := 16
## 墙正面高度(px)。**必须**与生成器 `FACE_H` 一致。
const FACE_H := 6
## 地板变体数。**必须**与生成器 `FLOOR_VARIANTS` 一致。
const FLOOR_VARIANTS := 4
## 5 个主题 id（顺序 = 楼层带从高到低，见 `theme_id_for_floor()`）。
const THEME_IDS: Array[String] = ["base", "mansion", "mutation", "blockade", "sublevel"]
## **美术权威调色板表**（art-director-tiles 产出，项目内路径，`load()` 可直接读）。
## ⚠⚠ **唯一真相源**。第一版指向 `assets/tiles/tile_palettes.json`（生成器派生表）——
##   那形成了**两个调色板真相源**（美术表 → 生成器 → 派生表 → 引擎），
##   派生表没跟上时就是**静默分叉**（第一版实测：派生表全是占位色，60 个入口照样全绿）。
##   → 派生表已删除，引擎与验证都**直接读这一份**。
const PALETTE_JSON := "res://design/art/tile_theme_palettes.json"
## 墙脚落地阴影：3 行的遮罩 alpha（**字面量**，与离线参考实现 `make_tiles16.py` 同值）。
## ⚠ 这三个值是「墙踩实在地上」的观感调节，不是物理参数；改它必须同步重录实机基线。
const SHADOW_ALPHA: Array[float] = [0.42, 0.29, 0.16]
## 地板变体选择用的哈希 salt（**字面量**；改它 = 整张地图的变体分布全变）。
const VARIANT_SALT := 131

## ---- 运行时状态（全部由 `setup()` 填好后 `queue_redraw()` 一次）----
var _theme_id: String = ""
var _floor_no: int = 0
var _loaded: bool = false
var _load_error: String = ""

# 🔴 R-131：**建层瞬间**的网格快照（`grid.duplicate()`）。
# 【为什么必须快照 —— 这是本批踩到的一个真实既有缺陷的护栏】
#   Godot 4.7 的 `PackedByteArray` **赋值即别名**（实测：写b 会改 a，见文件末「实测记录」）。
#   而 `Main._build_floor()` 里给敌人寻路屏蔽箱子格的那段是：
#       var nav_grid: PackedByteArray = data["grid"]
#       nav_grid[ty * nav_cols + tx] = 0#← 这一行**同时改掉了 data["grid"]**
#   `_floor_grid` 也是同一块缓冲的别名（`_floor_grid = data["grid"]`），
#   所以**在 `setup()` 之后**去读 `_floor_grid` 看到的已经不是`setup()` 当初看到的那份。
#   实测后果（R-131 首次跑 `--verify-tiles --verify-startfloor99`）：
#     实绘地板 8690 格 vs 事后读到的网格地板 8684 格 —— 差6 格 = 6 个箱子格。
#     （第 100 层恰好 0 差：R-119 把储藏室箱子放在 `data["crates"]` 之外，
#      故那段循环在基地层空转 -> **缺陷一直存在，只是基地层看不出来**。）
#   → 本节点在 `setup()` 里 `duplicate()` 一份，验证与外部统计都读这份快照。
#   ⚠ **本批不修那个既有缺陷**：它牵动寻路 / 迷雾 / 地图三处读同一份 grid 的语义，
#     改它属于另一个批次的事（已上报team-lead）。本节点只保证**自己不被它影响**。
var _grid_snap: PackedByteArray = PackedByteArray()
var _cols_snap: int = 0
var _rows_snap: int = 0

# 贴图（4 张地板 + 墙顶 + 墙正面）
var _tex_floor: Array = []          # Array[Texture2D]
var _tex_wall_top: Texture2D = null
var _tex_wall_face: Texture2D = null

# 按贴图分组的绘制矩形（构造期填，`_draw` 只读）
var _floor_rects: Array = []       # [variant] -> Array[Rect2]
var _walltop_rects: Array = []     # Array[Rect2]
var _face_rects: Array = []        # Array[Rect2]
var _edge_n_rects: Array = []      # Array[Rect2]北侧受光高光
var _edge_w_rects: Array = []      # Array[Rect2]西侧暗线
var _edge_e_rects: Array = []      # Array[Rect2]东侧暗线
var _shadow_rects: Array = []      # [k] -> Array[Rect2]

# 邻接收边用的颜色（自 JSON 主题槽位取）
var _edge_n_color: Color = Color(1, 1, 1, 1)
var _edge_dark_color: Color = Color(0, 0, 0, 1)

# ==============================================================================
# 静态：楼层号 -> 主题 id（**纯函数**，`--verify-tiles` ④ 直接拿它当被测对象）
# ==============================================================================
## 楼层带 -> 主题（art-bible §3.3 楼层主题色 + §3.4 基地主题）。
## ⚠ **纯函数**：不读节点、不读全局状态、不含随机。
## ⚠ 边界一律用 `>=` 写成**闭区间上界**，避免「99 与 100 之间漏掉一层」的缝：
##   100 -> base / 99..71 -> mansion / 70..41 -> mutation /
##   40..11 -> blockade / 10..1 -> sublevel
static func theme_id_for_floor(f: int) -> String:
	if f >= 100:
		return "base"
	if f >= 71:
		return "mansion"
	if f >= 41:
		return "mutation"
	if f >= 11:
		return "blockade"
	return "sublevel"

## 确定性哈希 -> [0,1)。**纯整数运算、无 RNG**，故同坐标恒等（可复现，R-104 铁律）。
## ⚠ 算法与 `production/tiles/generate_tiles.py` 的 `h01()` **逐字一致** ——
##   两边不一致会导致「同一坐标在生成器与引擎算出不同变体」，属最难查的一类 bug。
static func h01(x: int, y: int, salt: int) -> float:
	var hv: int = (x * 374761393 + y * 668265263 + salt * 1274126177) & 0xFFFFFFFF
	hv = ((hv ^ (hv >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((hv ^ (hv >> 16)) & 0xFFFF) / 65536.0

## 该世界格应贴哪张地板变体（0..3）。**按世界格坐标**取 → 同格恒定、每格不同。
static func floor_variant_of(gx: int, gy: int) -> int:
	return int(h01(gx, gy, VARIANT_SALT) * float(FLOOR_VARIANTS)) % FLOOR_VARIANTS

# ==============================================================================
# 构造：一次性算出所有绘制矩形
# ==============================================================================
## 由 `Main._build_floor()` 调用（**代码 new 节点，不动 Main.tscn**）。
## @param grid      本层网格（1=地板 / 0=非地板），与 `data["grid"]` 同索引口径
## @param wall_band 墙带掩码（1=有碰撞的墙格），由 `FloorGenerator.build_wall_band_from_grid()`
##                 产出。⚠ **必须用墙带而不是「grid==0」**：grid==0 还包含深埋的实心区
##                 （既不可走、也不在碰撞里），拿它当墙会给玩家画出一片
##                 「看得见却走不过去」的假墙 —— 那是最容易被误读成 bug 的画面缺陷。
func setup(grid: PackedByteArray, cols: int, rows: int, wall_band: PackedByteArray, floor_no: int) -> void:
	_floor_no = floor_no
	_theme_id = theme_id_for_floor(floor_no)
	_load_error = ""
	_loaded = false
	# 🔴 建层瞬间快照（见 `_grid_snap` 字段头的「为什么必须快照」）。
	#   必须在**任何其它人有机会改这份 grid 之前**拍：`_build_floor()` 里
	#   屏蔽箱子格的那段在 `setup()` 之后才跑，而它是别名写。
	_grid_snap = grid.duplicate()
	_cols_snap = cols
	_rows_snap = rows
	_tex_floor = []
	_floor_rects = []
	for v in FLOOR_VARIANTS:
		_floor_rects.append([] as Array)
	_walltop_rects = [] as Array
	_face_rects = [] as Array
	_edge_n_rects = [] as Array
	_edge_w_rects = [] as Array
	_edge_e_rects = [] as Array
	_shadow_rects = []
	for k in SHADOW_ALPHA.size():
		_shadow_rects.append([] as Array)

	if not _load_theme():
		push_error("TileGround: " + _load_error)
		return

	# ---- 越界一律视为「既不是地板也不是墙」----
	#⚠ 收成两个闭包，避免主循环里散落 4 份越界判断（复制 = 迟早漏改一处）。
	var is_floor := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= cols or y >= rows:
			return false
		return grid[y * cols + x] == 1
	var is_wall := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= cols or y >= rows:
			return false
		return wall_band[y * cols + x] == 1

	for gy in rows:
		for gx in cols:
			var idx: int = gy * cols + gx
			var bx: float = float(gx * TILE)
			var by: float = float(gy * TILE)
			if grid[idx] == 1:
				# ---- ① 地板格：按**世界格哈希**选变体 ----
				var bucket: Array = _floor_rects[floor_variant_of(gx, gy)]
				bucket.append(Rect2(bx, by, float(TILE), float(TILE)))
				# ---- ⑤ 墙脚落地阴影：**北侧是墙**的地板格，顶部 3 行压暗 ----
				#   跨格效果，单块地板瓦片里做不了，故必须由地图邻接关系算。
				if bool(is_wall.call(gx, gy - 1)):
					for k in SHADOW_ALPHA.size():
						var sb: Array = _shadow_rects[k]
						sb.append(Rect2(bx, by + float(k), float(TILE), 1.0))
			elif wall_band[idx] == 1:
				# ---- ② 墙顶面：**每个**墙格都铺砖砌顶面 ----
				#   → 竖排 / 横排都接成连续墙顶（砖缝按 16px 周期，见生成器）。
				_walltop_rects.append(Rect2(bx, by, float(TILE), float(TILE)))
				# ---- ③ 墙正面：**只给「下方是地板」的墙格** ----
				#   → 只在墙的南边缘出现一条连续墙脚；贴在墙格底部 6px（跨进地板格）。
				if bool(is_floor.call(gx, gy + 1)):
					_face_rects.append(Rect2(bx, by + float(TILE - FACE_H), float(TILE), float(FACE_H)))
				# ---- ④ 邻接收边（**由地图邻接关系算**，不是从瓦片里抠）----
				# 北侧暴露 = 远端轮廓 -> 1px 受光高光
				if bool(is_floor.call(gx, gy - 1)):
					_edge_n_rects.append(Rect2(bx, by, float(TILE), 1.0))
				# 西侧暴露 = 侧面 -> 1px 暗线
				if bool(is_floor.call(gx - 1, gy)):
					_edge_w_rects.append(Rect2(bx, by, 1.0, float(TILE)))
				# 东侧暴露 = 侧面 -> 1px 暗线
				if bool(is_floor.call(gx + 1, gy)):
					_edge_e_rects.append(Rect2(bx + float(TILE - 1.0), by, 1.0, float(TILE)))

	_loaded = true
	queue_redraw()

## 载入某主题的 6 张贴图 + 从 JSON 取该主题 8 个槽位里的 2 个（供收边用）。
func _load_theme() -> bool:
	var base_dir := "res://assets/tiles/" + _theme_id + "/"
	for v in FLOOR_VARIANTS:
		var p := base_dir + "floor_%d.png" % v
		if not ResourceLoader.exists(p):
			_load_error = "贴图缺失：%s（新增 PNG 必须先跑 --headless --path . --import）" % p
			return false
		var t: Texture2D = ResourceLoader.load(p) as Texture2D
		if t == null:
			_load_error = "贴图不可加载：%s" % p
			return false
		_tex_floor.append(t)
	var ptop := base_dir + "wall_top.png"
	var pface := base_dir + "wall_face.png"
	if not ResourceLoader.exists(ptop) or not ResourceLoader.exists(pface):
		_load_error = "墙顶/墙正面贴图缺失：%s / %s" % [ptop, pface]
		return false
	_tex_wall_top = ResourceLoader.load(ptop) as Texture2D
	_tex_wall_face = ResourceLoader.load(pface) as Texture2D
	if _tex_wall_top == null or _tex_wall_face == null:
		_load_error = "墙顶/墙正面贴图不可加载"
		return false
	# ---- 调色板（邻接收边的取色来源）----
	# ⚠ schema（美术侧 v1）：`themes` 是**数组**，每项 `{id, colors:{8槽位}}`。
	#   第一版按字典 `{themes:{id:{...}}}` 取 -> 空 dict -> 静默用回退色。
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_JSON))
	if not (parsed is Dictionary):
		_load_error = "调色板 JSON 解析失败：%s" % PALETTE_JSON
		return false
	var items: Variant = (parsed as Dictionary).get("themes", null)
	if not (items is Array):
		_load_error = "调色板 JSON 的 `themes` 必须是数组（实际 %s）：%s" % [
			type_string(typeof(items)), PALETTE_JSON]
		return false
	var pal: Dictionary = {}
	for it in (items as Array):
		if not (it is Dictionary):
			continue
		var entry := it as Dictionary
		if String(entry.get("id", "")) == _theme_id:
			pal = entry.get("colors", {}) as Dictionary
			break
	if pal.is_empty():
		_load_error = "调色板 JSON 缺主题 '%s'：%s" % [_theme_id, PALETTE_JSON]
		return false
	# 北侧受光高光 = 该主题的 `floor_highlight`（唯一亮槽位）
	_edge_n_color = _hex_color(String(pal.get("floor_highlight", "#8a8f9e")))
	# 东西侧暗线 = 该主题的 `wall_plinth`（最深槽位）
	_edge_dark_color = _hex_color(String(pal.get("wall_plinth", "#0e0f15")))
	return true

## `"#8a8f9e"` / `"8a8f9e"` -> `Color`。解析不了时回退到中性灰（**不抛异常**）。
## ⚠ 刻意容错：调色板是外部产物，一个手误不该让整层楼黑屏。
## ⚠⚠ **用 `String.hex_to_int()` 而不是 `Color(String,String,String,float)`**：
##   ① Godot 4 **没有** 4 字符串参数的 Color 构造器（实测 Parse Error）；
##   ② 也**没有**全局函数 `hex_to_int()`（实测 Parse Error）——
##      它是 `String` 的**方法**（`"8a".hex_to_int() = 138`），不是全局函数。
##   两条都是本批实测踩出来的，记在这里免得下次再写一遍。
static func _hex_color(s: String) -> Color:
	var t := s.strip_edges()
	if t.begins_with("#"):
		t = t.substr(1, t.length() - 1)
	if t.length() != 6:
		push_warning("TileGround: 非法 hex '%s'，回退 #8a8f9e" % s)
		return Color(0.541, 0.561, 0.620, 1.0)
	var r: float = float(t.substr(0, 2).hex_to_int()) / 255.0
	var g: float = float(t.substr(2, 2).hex_to_int()) / 255.0
	var b: float = float(t.substr(4, 2).hex_to_int()) / 255.0
	return Color(r, g, b, 1.0)

# ==============================================================================
# 绘制
# ==============================================================================
func _ready() -> void:
	# 瓦片必须最近邻（内部分辨率 320×180 整数放大到 1280×720 也不能糊）
	# —— 与 project.godot `default_texture_filter = 0` 一致；
	# 这里再显式设一次是为了**节点级**自我表达（万一将来有人改了全局默认，
	# 本节点仍然硬像素）。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	if not _loaded:
		return
	# ---- ① 地板：按变体分组（4 组）→ 纹理切换 4 次而非每格 1 次 ----
	for v in FLOOR_VARIANTS:
		var tex: Texture2D = _tex_floor[v]
		for r in (_floor_rects[v] as Array):
			draw_texture_rect(tex, r, false)
	# ---- ② 墙顶面 ----
	for r2 in _walltop_rects:
		draw_texture_rect(_tex_wall_top, r2, false)
	# ---- ③ 墙正面（16×6，贴在墙格底部）----
	for r3 in _face_rects:
		draw_texture_rect(_tex_wall_face, r3, false)
	# ---- ④ 邻接收边：1px 硬线，颜色取自主题槽位 ----
	for r4 in _edge_n_rects:
		draw_rect(r4, _edge_n_color, true)
	for r5 in _edge_w_rects:
		draw_rect(r5, _edge_dark_color, true)
	for r6 in _edge_e_rects:
		draw_rect(r6, _edge_dark_color, true)
	# ---- ⑤ 墙脚落地阴影：自上而下 3 行 alpha 递减 ----
	#   ⚠ 必须画在**墙正面之后**：参考实现里阴影就压在墙脚顶缘（把墙脚压进地里）；
	#     顺序反了会得到「墙脚上有一道亮边」的相反观感。
	for k in SHADOW_ALPHA.size():
		var c := Color(0.0, 0.0, 0.0, SHADOW_ALPHA[k])
		for r7 in (_shadow_rects[k] as Array):
			draw_rect(r7, c, true)

# ==============================================================================
# 供 `--verify-tiles` 观察（**只读**，不改任何渲染状态）
# ==============================================================================
func theme_id() -> String:
	return _theme_id

func loaded_ok() -> bool:
	return _loaded

func load_error() -> String:
	return _load_error

## 本层实际画了多少格（分类计数）。验证入口用它对账「画出来的格数 == 网格统计」。
func counts() -> Dictionary:
	var nf: int = 0
	for v in FLOOR_VARIANTS:
		nf += (_floor_rects[v] as Array).size()
	return {
		"floor": nf,
		"wall_top": _walltop_rects.size(),
		"wall_face": _face_rects.size(),
		"edge_n": _edge_n_rects.size(),
		"edge_w": _edge_w_rects.size(),
		"edge_e": _edge_e_rects.size(),
		"shadow": (_shadow_rects[0] as Array).size(),
	}

## 建层瞬间的网格**快照**（`setup()` 当时看到的那份）。
## ⚠ 外部（验证入口 / 实机像素统计脚本）要读「本层长什么样」时**必须读这个**，
##   不能读 `Main._floor_grid` —— 后者会被寻路的箱子屏蔽段就地改写（见 `_grid_snap` 字段头）。
func grid_snapshot() -> PackedByteArray:
	return _grid_snap

func grid_dims() -> Vector2i:
	return Vector2i(_cols_snap, _rows_snap)

# ==============================================================================
# 附：本文件开发期的实测记录（Godot 4.7.2 · 供后来者对照，勿凭记忆下结论）
# ==============================================================================
#   ① `PackedByteArray` **赋值即别名**（不是值类型）：
#        var a := PackedByteArray([1,1,1,0])
#        var b: PackedByteArray = a
#        b[0] = 0            # 实测：a 也变成 [0,1,1,0]
#      → 凡「拿到一份 grid 之后要就地改」的代码，都必须先 `duplicate()`。
#   ② Godot 4 **没有** `Color(String, String, String, float)` 构造器（Parse Error）。
#   ③ 也**没有**全局函数 `hex_to_int()` —— 它是 `String` 的方法（`"8a".hex_to_int()`）。