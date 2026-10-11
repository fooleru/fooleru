# R-118：第 100 层基地的**静态 ASCII 地图解析器**。
#
# 【为什么要有这个文件 —— 用户需求逐字】
#   「把第 100 层改成可手工编辑的静态地图，格式为 ASCII 字符网格 + 区域标签
#     （用户在这两项上明确拍板），用户要能自己直接改文件。」
#   改造前：第 100 层虽然是「基地」（不刷怪），但**几何仍走程序化生成**
#   （`FloorGenerator.generate()` 的 BSP 切房间 + 走廊 + 门），
#   也就是基地布局每次换 seed 都不一样 —— 与「静态手工场景」的设计意图矛盾。
#
# 【输出契约：与 `FloorGenerator.generate()` 同构的 Dictionary】
#   15 个键一个不少、类型一致（另加第 16 个 `regions`，仅供验证/未来渲染用）。
#   → 这样 `Main._build_floor()` 的消费代码**几乎不用改**，
#     静态地图与程序化地图在下游是**完全 interchangeable** 的。
#   ⚠ 这条"同构"是本文件存在的**全部价值**：一旦类型不一致，
#     `Main` 里十几处 `data["xxx"]` 就会各自踩坑，改动面从1 处扩大到十几处。
#
# 【⚠ 为什么解析失败「返回失败」而不是「报错崩掉」—— R-118 硬性要求】
#   用户会**手工编辑**这个文件，所以「写错一个字符」「少粘一行」是**预期内**的常态，
#   不是异常情况。若解析失败直接 `assert` / 抛错 → 整个游戏**黑屏无法启动**，
#   用户连"我改错了哪一行"都看不到（没有地图 = 连降级目标都没有）。
#   → 故：解析器**只做校验并如实返回 `{ok:false, error:"..."}`**，
#     由 `Main._current_floor_data()` 决定回退到程序化生成并打一行日志。
#   【半成品字典是最坏结果】—— 比"失败"更糟，因为下游会拿到一个
#     `spawn` 为 (0,0)、`path` 为空的字典，然后玩家掉进墙里/迷雾全黑，
#     而日志上却看不出是哪里错了。故失败时 `data` **一律为空字典**。
#
# 【本批刻意的范围限制：区域标签只解析、不渲染】
#   用户拍板的是「ASCII 网格 + 区域标签」这个**格式**，本批只交付
#   「标签被正确解析 + 可被查询（`regions`）」，**不画任何东西**。
#   理由：区域着色/区域名 UI 属于玩法表现层的独立决策（配色、是否显示中文名、
#   是否做区域边界描边），与"地图能被手工编辑"正交。提前渲染会锁死配色方案。
#   → 标签信息以 `regions`（区域名 -> 格数）+ `region_of`（格 -> 区域名）形式留存，
#     下一批要做区域渲染时**不用重新解析文件**。
extends RefCounted

const FloorGen := preload("res://scripts/gen/FloorGenerator.gd")

# 地图文件路径。⚠ 用 `res://` 而非绝对路径：本工程既有代码（`Main` 里的 preload）
#   全部走 `res://`，跟随工程目录而非机器路径 —— 否则换台机器就找不到地图了。
const MAP_PATH := "res://data/floor100.txt"

# 地面格数下限。⚠ 为什么要这条：纯ASCII 手抄很容易「整段漏粘」而**仍然格式合法**
#   （行数对、每行 128 字符、字符都合法），但地图只剩几百格甚至一个空房间。
#   那种地图能通过所有格式校验，却让玩家在基地里无处可走。
#   200格 ≈ 3200px²，足够放下基地的出生区 + 出发区（实测初版导出图远大于此值）。
const MIN_FLOOR_CELLS := 200

# `pickup`（起始武器拾取物）与出生点的**期望**最小距离（px）。
# ⚠ R-125：本常量在 `_pick_pickup()` 里**只用于限定扫描范围**，**没有**被当作
#   距离下界过滤用 —— 详见 `_pick_pickup()` 上方的「🔴 已知缺陷」段。
#   且基地层自 R-125 起已不再生成拾取物，故本常量目前**无实际作用**。
# ⚠ 沿用 `GameConstants.DEPART_TILE_SPAWN_OFFSET`（34px，右）的同一动机：
#   拾取物若正好压在出生点上，玩家一落地就自动捡枪，手感与"自己去拿"不同。
const PICKUP_MIN_DIST := 120.0

# ==== 公开 API ====

# 读文件 + 校验 + 构造数据。
# 返回 `{ok: bool, error: String, data: Dictionary}`
#   ok=false 时 data **必定为空字典**（绝不给半成品，见文件头说明）。
static func load_map(path: String = MAP_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("文件不存在：%s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("文件不可读（err=%d）：%s" % [FileAccess.get_open_error(), path])
	var text := f.get_as_text()
	f.close()
	return parse_text(text)

# 从**文本**解析（不碰文件系统）。
# ⚠ 刻意把「解析」与「读文件」拆成两个函数 —— `--verify-f100map` 的**反向验证**
#   需要喂「一份坏地图」来证明校验断言不是恒真的（验证要求 ⑥）。
#   若只有 `load_map()`，反向验证就得去真的改磁盘文件（污染用户数据 + 需��权限），
#   拆开后直接传字符串即可，**零副作用**。
static func parse_text(text: String) -> Dictionary:
	var cols: int = GameConstants.BASE_MAP_COLS
	var rows: int = GameConstants.BASE_MAP_ROWS

	# ---- ① 抽取网格行（跳过注释）----
	# ⚠⚠ **这里有个真实的坑**：地图最外圈是实心墙，所以**第0 行和第 85 行
	#   都是 128 个 `#` 开头的行**。若按字面「跳过所有 `#` 开头的行」实现，
	#   这两行会被当成注释**静默丢弃** -> 行数少2 -> 整张地图解析失败，
	#   而报错信息还会指向一个完全错误的方向（"行数不对"而不是"你删了墙"）。
	#   → 故判据是：**不是「以 # 开头」，而是「以 # 开头且不是一行合法网格」**。
	#     详见 `_is_comment_line()` 的注释。
	var raw_lines := text.split("\n")
	var grid_lines: Array[String] = []
	for ln in raw_lines:
		var line := ln
		# Windows 的 `\r\n`：Godot 的 `get_as_text()` 会保留 `\r`，
		# 不去掉会让每行长度变成 129 -> 长度校验全挂。
		if line.ends_with("\r"):
			line = line.substr(0, line.length() - 1)
		if line.strip_edges() == "" and not line.begins_with(GameConstants.BASE_MAP_WALL):
			# 纯空行：跳过（用户可能在头尾多敲了空行，不该因此失败）。
			# ⚠ 用 `strip_edges()==""` 而不是 `==""`：容忍行尾残留空格。
			continue
		if _is_comment_line(line):
			continue
		grid_lines.append(line)

	# ---- ② 行数 ----
	if grid_lines.size() != rows:
		return _fail("网格行数 = %d，期望 %d（每行 128 字符的地图行；# 开头的注释行已跳过）" % [grid_lines.size(), rows])

	# ---- ③ 逐行长度 + 字符集 ----
	# ⚠ 长度与字符集**分开报错**：用户最容易犯的错是"少敲/多敲一个字符"，
	#   报「第 N 行有 129 个字符」远比笼统的「格式错误」有用。
	for y in rows:
		var line: String = grid_lines[y]
		if line.length() != cols:
			return _fail("第 %d 行有 %d 个字符，期望 %d（每行必须正好 128 字符）" % [y + 1, line.length(), cols])
		for x in cols:
			var ch := line[x]
			if not _is_valid_char(ch):
				return _fail("第 %d 行第 %d 列出现非法字符 \"%s\"（合法字符：# . S X A-Z a-z，且 S/X 不作区域标签用）" % [y + 1, x + 1, ch])

	# ---- 扫出 S / X / 各区域标签 ----
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	var region_of := PackedByteArray()   # 0 = 无区域；否则是 GameConstants.BASE_REGION_NAMES 的下标+1
	region_of.resize(cols * rows)
	var regions := {}                    # 区域名 -> 格数
	var region_index := {}               # 字母 -> 内部下标+1
	var spawn_tile := Vector2i(-1, -1)
	var exit_tile := Vector2i(-1, -1)
	var n_spawn := 0
	var n_exit := 0
	var floor_cells := 0
	for y in rows:
		for x in cols:
			var ch: String = grid_lines[y][x]
			var i := y * cols + x
			if ch == GameConstants.BASE_MAP_WALL:
				grid[i] = 0
				continue
			# ⚠ 标签字母 / `.` / `S` / `X` **全都是地面**（grid=1）。
			#   区域标签只是"给地板加个名字"，不是另一种地形 —— 这条不变量
			#   是 ⑤（floor_rects 覆盖 == grid==1 格数）能成立的前提。
			grid[i] = 1
			floor_cells += 1
			if ch == GameConstants.BASE_MAP_SPAWN:
				n_spawn += 1
				spawn_tile = Vector2i(x, y)
			elif ch == GameConstants.BASE_MAP_EXIT:
				n_exit += 1
				exit_tile = Vector2i(x, y)
			elif ch != GameConstants.BASE_MAP_PLAIN:
				var rname := GameConstants.region_name_for(ch)
				if not region_index.has(ch):
					region_index[ch] = region_index.size() + 1
				region_of[i] = int(region_index[ch])
				regions[rname] = int(regions.get(rname, 0)) + 1

	# ---- ④ S / X 各恰好 1 个，且都是地面 ----
	# ⚠ 用 `!= 1` 而不是 `== 0`：漏写（S 写成 `.`）与写两个 S 是**两类不同的错**，
	#   但都必须拒收 —— 两个 S 意味着"到底哪个是出生点"有歧义，
	#   而 `Main` 只会用一个（第一个），另一个静默失效，是最难查的一类 bug。
	if n_spawn != 1:
		return _fail("出生点 S 数量 = %d，期望恰好 1 个" % n_spawn)
	if n_exit != 1:
		return _fail("出发瓦片位置 X 数量 = %d，期望恰好 1 个" % n_exit)
	# 显式断言「是地面」。当前实现里S/X 必然被写成 1（上面的分支），
	# 但保留这条断言是为了**钉死这个不变量**：若以后有人给 S/X 加了"可放在墙上"的
	# 变体（例如允许把 S 画在门格上），这里会立刻抓住，而不是让玩家卡在墙里。
	if grid[spawn_tile.y * cols + spawn_tile.x] != 1:
		return _fail("出生点 S 不在地面上")
	if grid[exit_tile.y * cols + exit_tile.x] != 1:
		return _fail("出发瓦片位置 X 不在地面上")

	# ---- ⑥ 地面格总数下限 ----
	if floor_cells < MIN_FLOOR_CELLS:
		return _fail("地面格总数 = %d，低于下限 %d（地图太荒谬，多半是漏粘了一大片）" % [floor_cells, MIN_FLOOR_CELLS])

	# ---- ⑤ S -> X 四连通可达（BFS）----
	# ⚠ 用 `FloorGenerator` 的 BFS（薄封装）而不是自己写一遍：
	#   连通性判定必须与程序化楼层**同一套四邻域规则**，
	#   否则会出现"解析器说可达、但游戏里 nav 走不过去"的分裂。
	var gen := FloorGen.new()
	var path: Array[Vector2] = gen.build_path_from_grid(grid, cols, rows, spawn_tile, exit_tile)
	if path.size() < 2:
		return _fail("出生点 S 到出发位置 X 四连通不可达（路径长度 %d；至少要有中间格）" % path.size())

	# ---- 派生几何 ----
	# ⚠ 墙：直接复用 `_wall_band` + `_mesh`（经薄封装），**不复制实现**。
	#   复制 = 两份贪心合并算法各自演化 = 迟早出现"墙盖住地板"的错位。
	var walls: Array[Rect2] = gen.build_walls_from_grid(grid, cols, rows)

	# ⚠⚠ 地板矩形：`_mesh` 判的是 `band[i] == 1`，而 `grid` 里**墙是 0**。
	#   若直接把 `grid` 传进 `_mesh`，会把**墙**当地板合并、地板反而漏掉 —— 完全反过来。
	#   → 必须构造一个「地面格 -> 1」的掩码再交给 `mesh_from_mask()`。
	#   这是本文件最容易写错、且错了之后**画面看起来还挺正常**（有地板也有墙，只是位置错乱）
	#   的一处，故单独注释钉死，并由 `--verify-f100map` ⑤（不重不漏）反向钉死。
	var floor_mask := PackedByteArray()
	floor_mask.resize(cols * rows)
	for i in cols * rows:
		floor_mask[i] = 1 if grid[i] == 1 else 0
	var floor_rects: Array[Rect2] = gen.mesh_from_mask(floor_mask, cols, rows)

	# 出生点 / 出口 = 格中心。⚠ 用 `tile_center_of()`（= 同一个 `_tile_center`），
	#   保证与程序化楼层**同一像素口径**；差1px 都会让 depart tile 的偏移断言漂移。
	var spawn: Vector2 = gen.tile_center_of(spawn_tile)
	var exit_pos: Vector2 = gen.tile_center_of(exit_tile)

	# `pickup` = 出生点附近一个**合法**地面格。
	#   ⚠⚠ **R-125：基地层已不再生成起始武器拾取物**（用户逐字：「删掉「起始武器
	#     拾取物」，已经用起始房间的宝箱替代了。」）→ `Main._build_floor()` 里
	#     生成 `WeaponPickup` 的那一段已加 `if not is_base_floor(_floor)` 前置。
	#     ⇒ **本函数返回值在基地层已无消费点**。之所以仍保留计算与 key：
	#       ① 字典形状保持稳定（多处验证入口按 key 存在读取 `data["pickup"]`）；
	#       ② 若将来基地又要一把起始枪，改回来只需删那个 `if`。
	#   ⚠ 真实的删除理由（有实机证据，别再"优化"回来）：`WeaponPickup.tscn` 的
	#     `Visual` 是 **6×6 黄方块** `Color(0.98,0.85,0.2)`，而 R-124 的「出发点」
	#     是 **12×12 黄方块**；非 headless 录帧实测两者分别落在屏幕 (160,74) 与
	#     (160,122) —— **同在玩家视线中轴线上、同色系**，会让玩家站错地方按 F，
	#     重演"出发提示失效"的误报（R-124 整批就是在查这个）。
	#   ----（以下为原取法说明，R-125 后仅在"将来重新启用"时才有意义）----
	#   在 S 的 BFS **可达**地面里，找离 S 距离 >= PICKUP_MIN_DIST 且不与
	#   spawn/exit 重合的**最近**一格；找不到就退回 spawn（保证一定有值，
	#   绝不返回 null —— 旧 `Main` 会直接 `pk.position = data["pickup"]`）。
	#   ⚠ 限定「BFS 可达」而不是「任意地面格」：地图上可能有**孤立的口袋房间**
	#     （玩家在静态地图里手画得出来）。把拾取物放在不可达的口袋里= 玩家永远拿不到枪。
	#   🔴 **已知缺陷（R-125 发现，现已成为死代码但仍记录在此）**：
	#     上一段描述的 ">= PICKUP_MIN_DIST" **并未真正实现** —— `_pick_pickup()`
	#     只排除了「格中心与 spawn/exit **恰好重合**」(`distance < 1.0`)，没有对
	#     BFS 距离 `d` 设下界；而 `PICKUP_MIN_DIST` 只被用来限定扫描范围
	#     `range(1, int(PICKUP_MIN_DIST / TILE) + 2)`。于是循环从 `d = 1` 起就命中并
	#     因 `best_d == -1` 只赋值一次 → **实际取到的是紧贴出生点的邻格**。
	#     实测印证：出生点 tile (20,13)，拾取物落在 **(20,12)**（相距 1 格 = 16px，
	#     而非注释所写的 120px）。R-125 删掉基地拾取物后该路径已无副作用，
	#     故**本批不改行为**；若将来重新启用基地拾取物，**必须**先补上
	#     `if d * TILE < PICKUP_MIN_DIST: continue` 这类下界过滤。
	var pickup: Vector2 = _pick_pickup(gen, grid, cols, rows, spawn_tile, spawn, exit_pos)

	# ---- 派生数据字典 ----
	# ⚠ 各空数组**必须显式标注元素类型**（`var e: Array[Vector2] = []`），
	#   不能写 `[] as Array[Vector2]`：`as` 是**对象**类型转换，
	#   对 Array 无效（静默得到无类型数组），会让下游 `for pos in data["enemies"]`
	#   拿到 Variant 而不是 Vector2 —— 类型不匹配会在赋值 `z.position = pos` 处才炸，
	#   报错点离真正的原因很远。
	var empty_pos: Array[Vector2] = []
	var empty_tile: Array[Vector2i] = []
	var empty_kind: Array = []
	var data := {
		"walls": walls,
		"floor_rects": floor_rects,
		# `rooms` 与 `floor_rects` 同值。仅被 `--verify-gen` 读，
		# 而那个入口不会跑到第 100 层 —— 但**键必须存在**，
		# 否则任何 `data["rooms"]` 的直接索引都会在基地层 KeyError。
		"rooms": floor_rects.duplicate(),
		"spawn": spawn,
		"exit": exit_pos,
		"path": path,
		# ⚠ 基地层**空内容**：敌人 / 佣兵 / 箱子 / 门 一律空数组。
		#   这与 `Main._build_floor()` 里 `is_base_floor` 分支的清空**重复**，
		#   但**刻意保留这份重复** —— 见文件末「为什么两处都清」。
		"enemies": empty_pos.duplicate(),
		"mercenaries": empty_pos.duplicate(),
		# R-146：Brute（快攻型僵尸）—— 基地层同样**空数组**。
		#   ⚠ 这个键**必须存在**：字典形状要与 `FloorGenerator.generate()` 完全一致 ——
		#   Main._build_floor 的 Brute 生成循环虽然带了 `has()` 守卫，但"基地层靠 has 兜底、
		#   战斗层靠键存在"是两套语义；补齐后两侧走同一条路径，也避免将来有人
		#   把守卫删掉时基地层直接 KeyError。基地层**永远不该有敌人**（R-118 安全屋）。
		"brutes": empty_pos.duplicate(),
		"pickup": pickup,
		"crates": empty_pos.duplicate(),
		"doors": empty_tile.duplicate(),
		# 只被 `--verify-crate` 读，基地层不走那个入口；空串 =「没有箱子池」语义自洽。
		"crate_pool_kind": "",
		"crate_kinds": empty_kind.duplicate(),
		"cols": cols,
		"rows": rows,
		"grid": grid,
		# ---- 第 16 个键（R-118 新增，不影响既有 15 个）----
		# 区域名 -> 该区域的地面格数。供验证与后续区域渲染使用。
		"regions": regions,
		# 格索引 -> 区域名（本批不渲染，见文件头「只解析不渲染」）。
		# ⚠ 一并给出是为了让下一批做区域着色时**不必重解析文件**；
		#   它是 PackedByteArray（0=无区域），与 `grid` 同索引口径。
		"region_of": region_of,
	}
	return {"ok": true, "error": "", "data": data}

# ==== 内部实现 ====

static func _fail(msg: String) -> Dictionary:
	# ⚠ `data` 必须是**空字典**而不是 null：调用方会无脑取 `res["data"]`，
	#   给 null 会变成一个更难懂的 "Invalid get index 'data'"。
	#   空字典 + ok=false 的组合是明确的"这里什么都没有，别用"。
	return {"ok": false, "error": msg, "data": {}}

# 合法字符：`#` / `.` / `S` / `X` / A-Z / a-z（**排除大写 S 与 X**）。
# ⚠ `S` / `X` 被排除的理由：它们是出生点 / 出发瓦片的**保留字符**。
#   若允许 `S` 同时当区域标签，「这个 S 是出生点还是宿舍？」就有两种解释，
#   而用户改文件时不会有任何提示。**保留字符必须唯一**。
static func _is_valid_char(ch: String) -> bool:
	if ch == GameConstants.BASE_MAP_WALL or ch == GameConstants.BASE_MAP_PLAIN:
		return true
	if ch == GameConstants.BASE_MAP_SPAWN or ch == GameConstants.BASE_MAP_EXIT:
		return true
	var code := ch.unicode_at(0)
	# A-Z
	if code >= 65 and code <= 90:
		return ch != GameConstants.BASE_MAP_SPAWN and ch != GameConstants.BASE_MAP_EXIT
	# a-z（大小写都是合法标签；区域名按字母查表，未登记的回退 "区域x"）
	if code >= 97 and code <= 122:
		return true
	return false

# 该行是否为注释行。
# ⚠⚠ **判据不是「以 # 开头」**（详见 `parse_text` ①处的坑）：
#   地图最外圈是实心墙 -> 第 0 行/第 85 行本身就是 128 个 `#`。
#   真正的判据是：**以 `#` 开头，但不是一行「长度 == 128 且字符全部合法」的网格**。
#   这样注释随便写（`#=====` / `#` / `# 医疗区 A-H`）都能跳，
#   而任何一行真网格都**绝不会**被误判成注释。
static func _is_comment_line(line: String) -> bool:
	if not line.begins_with(GameConstants.BASE_MAP_WALL):
		return false
	if line.length() != GameConstants.BASE_MAP_COLS:
		return true          # 注释通常不长
	for i in line.length():
		if not _is_valid_char(line[i]):
			return true
	return false             # 长度对 + 字符全合法 -> 这是一行真网格，**不是注释**

# 挑一个合法的拾取物格。
# ⚠ 用 BFS 距离场（`bfs_dist_from_grid`）而不是"欧氏距离"：
#   地图里有墙，欧氏近不等于走得到。
static func _pick_pickup(gen, grid: PackedByteArray, cols: int, rows: int, spawn_tile: Vector2i, spawn: Vector2, exit_pos: Vector2) -> Vector2:
	var dist: PackedInt32Array = gen.bfs_dist_from_grid(grid, cols, rows, spawn_tile)
	var best := Vector2i(-1, -1)
	var best_d := -1
	# 按 BFS 距离从小到大扫 =「最近的合法格」，无需排序（距离值域有限）。
	# ⚠ 扫描顺序固定为 y 外层 / x 内层：同距离时取**行号小**者 ->
	#   同seed / 同文件**结果完全确定**（R-104 铁律：可复现）。
	for d in range(1, int(PICKUP_MIN_DIST / FloorGen.TILE) + 2):
		for y in rows:
			for x in cols:
				var i := y * cols + x
				if dist[i] != d:
					continue
				var c := Vector2(x * FloorGen.TILE + FloorGen.TILE / 2, y * FloorGen.TILE + FloorGen.TILE / 2)
				# 不与 spawn / exit 重合：拾取物压在出发瓦片上会挡住它。
				if c.distance_to(spawn) < 1.0 or c.distance_to(exit_pos) < 1.0:
					continue
				if best_d == -1:
					best = Vector2i(x, y)
					best_d = d
	if best.x < 0:
		return spawn        # 退化：地图太小放不下 -> 退回出生点（**保证非 null**）
	return Vector2(best.x * FloorGen.TILE + FloorGen.TILE / 2, best.y * FloorGen.TILE + FloorGen.TILE / 2)

# ==== 导出器（`--export-floor100` 的实现体）====
#
# 【为什么要有导出器 —— 可复现性的双向保障】
#   用户要"手工编辑地图"，但**手写 86×128 = 11008 个字符不现实**。
#   导出器把当前程序化生成的基地层导出成 ASCII 网格，作为**可编辑的起点**，
#   用户在此基础上改画即可（而不是从空白开始）。
#   ⚠ **必须可重复运行且同 seed 同输出**（R-104 铁律）：
#     它是纯函数式的"网格 -> 文本"，不含任何 rng / 时间戳 / 随机排序，
#     所以重复导出得到**逐字节相同**的文件（用户改到一半误跑了导出也不会"地图又变了"）。
#     唯一的不稳定源是"S/X 选址"里任何依赖字典遍历顺序的写法 —— 本函数只用
#     **固定顺序的行列扫描**，不遍历 Dictionary，故稳定。
#
# 【⚠⚠ 导出器会**清空已有区域标签**】
#   程序化网格里没有标签信息（`grid` 只有 0/1），所以导出必然把标签抹平成 `.`。
#   这一点必须让用户知道，故 `export_grid_to_text()` 的调用处（`Main`）会打一行日志提醒。
#   设计上刻意**不**尝试保留标签 —— 标签是"贴在地板上的人工标注"，
#   几何一变，标注的语义（"这里是厨房"）就未必还成立，**宁可让用户重标**。
static func export_grid_to_text(grid: PackedByteArray, cols: int, rows: int, spawn_tile: Vector2i) -> String:
	# X（出发瓦片位置）：spawn **右下方**第一个合适的地板格。
	# ⚠ 为什么必须紧邻 spawn（而不是随便找个远处格）：
	#   `Main._depart_tile_pos()` 是从 spawn 按 `DEPART_TILE_SPAWN_OFFSET`(34,0)
	#   算瓦片位置并**沿 x 轴回退**找安全格的。X 只是 `floor_map` 的出口标记坐标
	#   （基地层 `exit_marker.visible=false`，不触发下降），语义上应当"在出生点附近"。
	#   固定从 (1,1) 偏移起、按 dy/dx 升序找第一个地板格 -> **确定性**且不会跑到墙里。
	var exit_tile := Vector2i(-1, -1)
	for dy in range(1, 4):
		for dx in range(1, 4):
			var cx: int = spawn_tile.x + dx
			var cy: int = spawn_tile.y + dy
			if cx < 0 or cx >= cols or cy < 0 or cy >= rows:
				continue
			if grid[cy * cols + cx] == 1:
				exit_tile = Vector2i(cx, cy)
				break
		if exit_tile.x >= 0:
			break
	if exit_tile.x < 0:
		# 退化：spawn 右下 3×3 内没有地板（极小地图）。退回 spawn 本身，
		# 保证导出的文件**一定能通过 S/X 校验**（导出器不允许产出非法文件）。
		exit_tile = spawn_tile

	var out := PackedStringArray()
	for y in rows:
		var line := ""
		for x in cols:
			var i := y * cols + x
			if Vector2i(x, y) == spawn_tile:
				line += GameConstants.BASE_MAP_SPAWN
			elif Vector2i(x, y) == exit_tile:
				line += GameConstants.BASE_MAP_EXIT
			elif grid[i] == 1:
				line += GameConstants.BASE_MAP_PLAIN
			else:
				line += GameConstants.BASE_MAP_WALL
		out.append(line)
	return "\n".join(out)

# 生成文件头注释块。
# ⚠ **图例必须写在文件里、不能只写在代码里** —— 这个文件的第一读者是**用户**，
#   他要靠这段注释知道怎么改。代码注释他看不到。
static func header_comment() -> String:
	var lines := PackedStringArray()
	lines.append("# ============================================================")
	lines.append("# 第 100 层（基地）静态地图 · R-118")
	lines.append("#")
	lines.append("# 【尺寸】%d 列 × %d 行，每格 %d px（= %d × %d px 的世界）" % [
		GameConstants.BASE_MAP_COLS, GameConstants.BASE_MAP_ROWS, 16,
		GameConstants.BASE_MAP_COLS * 16, GameConstants.BASE_MAP_ROWS * 16])
	lines.append("#        网格坐标 (x, y)：x 向右 0..%d，y 向下 0..%d" % [
		GameConstants.BASE_MAP_COLS - 1, GameConstants.BASE_MAP_ROWS - 1])
	lines.append("#")
	lines.append("# 【改法警告 —— 改之前先读这段】")
	lines.append("#   ① **不要改行数**：必须正好 %d 行网格。" % GameConstants.BASE_MAP_ROWS)
	lines.append("#   ② **不要改每行的字符数**：每行必须正好 %d 个字符。" % GameConstants.BASE_MAP_COLS)
	lines.append("#      少一个字符 -> 解析直接失败（会打日志说明是哪一行）。")
	lines.append("#   ③ 不要用 Tab 缩进或行尾加空格（空格不是合法字符）。")
	lines.append("#   ④ 以 # 开头的行是**注释**，解析时跳过；网格行本身也可能以 # 开头（墙），")
	lines.append("#      解析器靠「长度是否等于 %d」区分两者，所以别把地图行写成别的长度。" % GameConstants.BASE_MAP_COLS)
	lines.append("")
	lines.append("# 【图例】")
	lines.append("#   %s  = 墙（实心，不可走）" % GameConstants.BASE_MAP_WALL)
	lines.append("#   %s  = 地板（无区域标注）" % GameConstants.BASE_MAP_PLAIN)
	lines.append("#   %s  = 出生点（玩家出现的位置）—— **必须恰好 1 个**" % GameConstants.BASE_MAP_SPAWN)
	lines.append("#   %s  = 出发瓦片位置 —— **必须恰好 1 个**" % GameConstants.BASE_MAP_EXIT)
	lines.append("#   A-Z a-z = 地板 + 区域标签（**大写 S / X 被保留，不可当标签用**）")
	lines.append("")
	lines.append("# 【区域标签对照表】")
	var keys := ["A", "B", "C", "D", "E", "F", "G", "H"]
	for k in keys:
		lines.append("#   %s = %s" % [k, GameConstants.region_name_for(k)])
	lines.append("#   （表里没有的字母也能用，区域名会自动叫「区域<字母>」）")
	lines.append("#   ⚠ 本批标签**只被解析记录、不渲染任何东西**。")
	lines.append("")
	lines.append("# 【校验规则 —— 任何一条不过，基地层会**自动回退到程序化生成**】")
	lines.append("#   1. 网格行数 == %d，每行字符数 == %d" % [GameConstants.BASE_MAP_ROWS, GameConstants.BASE_MAP_COLS])
	lines.append("#   2. 只允许上面图例里的字符（# . S X A-Z a-z）")
	lines.append("#   3. %s 恰好 1 个、%s 恰好 1 个，且两者都必须是地面" % [
		GameConstants.BASE_MAP_SPAWN, GameConstants.BASE_MAP_EXIT])
	lines.append("#   4. %s 到 %s 必须四连通可达（不能被墙完全隔开）" % [
		GameConstants.BASE_MAP_SPAWN, GameConstants.BASE_MAP_EXIT])
	lines.append("#   5. 地面格总数 >= %d" % MIN_FLOOR_CELLS)
	lines.append("")
	lines.append("# 【重新生成初始版本】")
	lines.append("#   Godot --headless --path . --export-floor100")
	lines.append("#   ⚠ 该命令会**用程序化生成的地图覆盖本文件**（含清空区域标签）。")
	lines.append("#     所以：想保留自己的编辑成果，就**先备份**再跑。")
	lines.append("# ============================================================")
	return "\n".join(lines)

# 完整文件文本 = 头部注释 + 网格。
static func build_file_text(grid: PackedByteArray, cols: int, rows: int, spawn_tile: Vector2i) -> String:
	return header_comment() + "\n" + export_grid_to_text(grid, cols, rows, spawn_tile) + "\n"

# 【⚠ 为什么 `Main._build_floor()` 里的 `is_base_floor` 清空分支要**保留**，
#   即使静态地图已经返回空数组（两处重复）？】
#   因为那个分支承担的是**三件**与"内容清空"无关的事：
#     ① `exit_marker.visible = false`（关掉下降触发 —— 纯 `Main` 侧职责）；
#     ② 打出「本层是基地」的诊断日志；
#     ③ **回退路径的保险**：静态地图失败 -> 走程序化生成 ->
#        那份数据里**是有敌人/箱子的**，必须靠这个分支清掉。
#   若把分支删掉"因为静态地图已经清了"，回退时基地就会刷出 60 只僵尸。
#   → 故：**保留分支**，静态路径只是让清空变成幂等操作。