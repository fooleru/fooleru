# 程序化单层生成器 · cp2（R-58：两级布局 —— 走廊街区 + 沿走廊小房间，贴近现实户型图）
# 一级：BSP 用「走廊(3 tile)」把整层切成若干**街区**（Block）
# 二级：每个街区**内缩 1 tile**（形成房间↔走廊之间的墙），再用 BSP 切成**小房间**（4–12 tile），
#       房间之间薄墙(1 tile) + 门；街区在环上再开 1–2 个**通往走廊的门**
# 墙带 = 紧邻地面的实心格 → 贪心合并成少量墙矩形；BFS 求 spawn→exit（保证可达 + 给 bot 导航）
# 世界尺寸走 GameConstants（单一权威源）。无风格系统/无垂直骨架/无 Boss 房（低于 GDD）。
extends RefCounted

const TILE := 16
const BORDER := 1              # 最外围实心厚度
# 一级：街区（走廊分隔）
const BLOCK_MIN := 16          # 街区最小边长
const BLOCK_MAX := 34          # 街区最大边长（越大 → 街区越少越大）
const CORRIDOR_W := 3          # 主走廊宽（一级分割缝）
# 二级：房间（墙分隔）
const ROOM_MIN := 6            # 房间最小边长（6 tile = 96px，小房间）
const ROOM_MAX_BASE := 13      # 第 1 层房间最大边长（13 tile ≈ 208px）
const ROOM_MAX_MIN := 10       # 最深时房间最大边长
const ROOM_CORRIDOR_CHANCE := 0.15  # 房间之间偶尔形成内部过道（二级缝 2 tile）
const ROOM_CORRIDOR_W := 2
const DOOR_MIN := 3            # 门宽（房间之间；3–4 tile = 48–64px，好走且利好 bot 寻路）
const DOOR_MAX := 4
# ==== 内容数量 ====
# ==== R-105：敌人数量曲线由「线性」改为「几何增长」（每层 x1.3）====
# 【用户需求逐字· team-lead 转述原文】
#   「敌人数量随楼层增加的曲线更陡峭，每层增加约30%的敌人」
# 【用户三轮拍板（逐字· 必须严格遵守）】
#   ① **第 1 层数量保持 11 不变**，从第 1 层往后每层 x1.3。
#      （不是我最初推测的 MIN_ENEMY=8；理由：几何增长会压低浅层，
#        用户只说「更陡峭」、没说浅层要变少。）
#   ② **MAX_ENEMY 封顶 40 -> 60**（僵尸线）。
#   ③ **僵尸与佣兵两条线都改**（不只是僵尸）。
#
# 【旧口径（已删除，勿回退）】
#   僵尸：mini(MIN_ENEMY + floor * ENEMY_PER_FLOOR, MAX_ENEMY) = min(8 + floor*3, 40)
#         -> 第 1 层 11、每层 **+3**（恒定增量）、第 11 层封顶 40。
#   佣兵：clampi(floor * 2 - 4, 0, 16) -> 第 3 层 2 只、每层 **+2**、第 10 层封顶 16。
#   ⚠ **`MIN_ENEMY` 与 `ENEMY_PER_FLOOR` 已物理删除**（不是注释掉）：
#     几何增长不再有「起步基数」与「每层固定增量」两个概念，留着就是
#     **死常量 = 静默的错误源**（R-89 教训：写死值会变成没人更新的错误锚）。
#     起步基数已由 `ENEMY_BASE` 取代；每层增量由 `ENEMY_GROWTH` 取代。
#
# 【新口径 · 僵尸线】
#   count(f) = min( roundi(ENEMY_BASE * ENEMY_GROWTH^(f - ENEMY_BASE_FLOOR)), MAX_ENEMY )
#   逐层：11 / 14 / 18 / 23 / 30 / 39 / 51 / 60 / 60 / 60 ...
#   （第 8 层撞 60封顶 —— 旧口径要到第 11 层才封顶。）
#
# 【取整方式 = `roundi`（四舍五入）】—— 由我选定，理由三条：
#   ① **截断（`int()`）会让曲线系统性偏低**：`int()` 是**向零截断**，每层丢掉
#      小数部分，误差**逐层累积**（复利式漂移），曲线长期低于设计值；
#      实测同一张表截断给 11/14/18/24/31/40/53，四舍五入给 11/14/18/23/30/39/51。
#   ② **`ceil()`（进一法）系统性偏高**：每层多生成敌人，与"更陡峭"叠加后
#      浅层就被过度加压（用户明确说过浅层不变）。
#   ③ `roundi` 是**唯一无偏**的一档，且让相邻层比值最贴近 1.3（实测 1.27~1.31）。
#   ⚠⚠ **必须用 `roundi`，不要用 `int()`** —— GDScript 的 `int()` 是**向零截断**
#      而非 floor，对负数行为不同（本处永远是正数故结果相同，但语义必须写明，
#      免得后人以为 `int()` == `floor()` 而误改）。
#   ⚠ **必须是「迭代」而非「闭式」**：闭式 `roundi(11 * 1.3^(f-1))` 得到
#      11/14/**19**/24/31/41/53 —— 与用户拍板表不符（f3 就差 1）。
#      迭代式（每层拿**上一层的取整结果**再乘）才对得上用户逐字拍板的表。
#      见 `enemy_count_for_floor()`。
#
# 【新口径 · 佣兵线（同样改几何增长，用户拍板③）】
#   count(f) = 0                if f <  MERC_FROM_FLOOR   （第 1、2 层无佣兵）
#            = min( roundi(MERC_BASE * MERC_GROWTH^(f - MERC_FROM_FLOOR)), MAX_MERC )
#   逐层：0 / 0 / 2 / 3 / 4 / 5 / 7 / 9 / 12 / 16 / 16 / 16 ...
#   ⚠ **`MERC_FROM_FLOOR = 3` 保持不变** —— 「前期无佣兵、后期才有」是**刻意的
#     分层设计**（第 1、2 层是教学层，远程敌人会破坏"近战压迫"的上手节奏），
#     用户三轮拍板也没要求改起始层。
#   ⚠ **`MAX_MERC` 保持 16（不跟随 MAX_ENEMY 提到 60）** —— 见交付报告的数据支撑：
#     封顶 16 与封顶 60 在**第 1~10 层完全相同**（第 10 层都恰好= 16），
#     **差异从第 11 层才开始**（16 vs 21）。也就是说"提到 60"这个决定
#     **只在第 11 层及以后才有可观察后果**。而第 11 层起僵尸已封顶 60，
#     若佣兵也放到 60 => 单层 120 个敌人、其中 60 个是 260px 视距 + 3~5 连发
#     的远程压制，玩家走位空间被彻底封死。**故佣兵单独保留较小封顶。**
const ENEMY_BASE_FLOOR := 1# 曲线锚点层（用户拍板①：这一层不做任何增长）
# ==== R-146：数量与峰值各翻一倍（用户逐字：「每层敌人的生成数量增加一倍，峰值也增加一倍」）====
#   ENEMY_BASE 11 -> 22、MAX_ENEMY 60 -> 120。**增长率 ENEMY_GROWTH=1.3 与锚点
#   ENEMY_BASE_FLOOR=1 刻意不动** —— 用户只说"数量与峰值翻倍"，没说改增长陡峭度；
#   改 GROWTH 会让曲线在浅层就超过旧值的 2 倍（那是"更陡"，不是"翻倍"）。
#   翻倍后的逐层：22 / 29 / 38 / 49 / 64 / 83 / 108 / 120 / 120 ...（第 8 层触顶）
#   ⚠ 取整仍是 `roundi` 且仍是**迭代**（见函数注释）：22*1.3=28.6→29，
#     闭式会得到 29 但迭代链上 f4 就与闭式分叉，迭代才是"每层 x1.3"的字面语义。
const ENEMY_BASE := 22          # 第 1 层的僵尸数量（R-105 是 11，R-146 用户拍板翻倍）
const ENEMY_GROWTH := 1.3# 每层 x1.3（用户拍板①，R-146 保持不变）
const MAX_ENEMY := 120          # 僵尸封顶（R-105 是 60，R-146 用户拍板翻倍）
const MERC_FROM_FLOOR := 3      # 佣兵起始层（保持不变：第 1、2 层无佣兵）
const MERC_BASE := 2            # 第 3 层的佣兵数量（与旧口径一致：2 只）
const MERC_GROWTH := 1.3        # 佣兵每层 x1.3（用户拍板③：佣兵线也改几何增长）
const MAX_MERC := 16            # 佣兵封顶（**不**跟随 MAX_ENEMY，理由见上）
const SPAWN_CLEAR_ENEMY := 140.0
const SPAWN_CLEAR_MERC := 240.0
const EXIT_CLEAR := 60.0
# 成群生成（R-62）：同类型敌人聚成"簇"
const CLUSTER_RADIUS_UNDEAD := 3   # 僵尸簇半径（tile）
const CLUSTER_SIZE_UNDEAD := 4     # 僵尸每簇数量
const CLUSTER_RADIUS_MERC := 2     # 佣兵簇半径（tile）
const CLUSTER_SIZE_MERC := 3       # 佣兵每簇数量
# === 宝箱（R-79：数量加大 + 必须靠墙；R-94：排除门格）===
# 旧口径：clampi(3 + floor/2, 3, 8) → 第 1 层 3 个、封顶 8 个。
# 新口径：起步 5、每层 +1、封顶 20（第 1 层 6 → 第 15 层及以后 20），约 **2–2.5 倍**。
# 摆放**只从「紧邻墙的地面格」里取**（`_wall_adjacent_floor_cells`）：
#   ① 走廊中央不再摊箱子 → 不会顶死门、不会卡 bot；
#   ② 想拿 loot 必须先"走到墙角" → 天然制造探索动线，而不是箱子摊在路过的地方被白捡。
#
# ⚠⚠ R-94 修一个**既有设计缺陷**：上面 ① 写了"不会顶死门"，但实现**没做到**。
#   根因链（三步）：
#     (1) 开门 = 把门洞那些格的 `grid` 改成 1（地面）→ **门格在数据上与普通地面格完全一样**；
#     (2) `_wall_adjacent_floor_cells` 只问"四邻域有没有一格**不是地面**"，
#         **不区分那一格是墙还是门**；
#     (3) 门洞是"1 tile 宽的竖井"（房间之间的墙缝 gap=1）或"环上的一段"，
#         门洞**两端**的格子（沿门洞走向的末端）各挨着一格实心墙
#         → `near_wall = true` → **门格端点进了候选池** → 宝箱可能摆在门口。
#         （门洞**中段**的四邻域全是地面，本来就进不了贴墙池 —— 所以受影响的
#           是每个门的 2 个端点，不是整条门洞。实测占比见 `--verify-cratedoor`。）
#   为什么下面那个 `cguard` BFS 兜底**没拦住**（实测确认，见 `--verify-cratedoor`）：
#     兜底只验「所有房间中心 + 出口仍能从出生点走到」。门宽 3–4 tile（48–64px），
#     一个箱子只占 1 tile 且碰撞盒只有 12×12px（< 一格 16px），
#     **剩下的 2–3 格门洞仍然连通** → 房间照样进得去 → `all_ok = true` → 不移除。
#     换句话说兜底管的是"**路全断**"，而这个 bug 是"**门口被摆了个箱子**"：
#     两者不是同一件事，前者永远抓不到后者。
#   修法：开门时把门格坐标**显式记下来**（`door_cells`，见 `_carve_door`），
#        候选池构建时把门格剔掉。**不消耗任何 RNG**（纯记账），所以既不动布局
#        随机性，也不影响确定性（`--verify-cratedoor` 断言 ⑦ 守着这条）。
const CRATE_MIN := 5
const CRATE_PER_FLOOR := 1
const CRATE_MAX := 20
const CRATE_SPACING := 60.0        # 箱子彼此最小间距（px）
const CRATE_SPAWN_CLEAR := 80.0    # 离出生点最小距离（px）
const CRATE_EXIT_CLEAR := 40.0     # 离出口最小距离（px）

# 返回 Dictionary:
#  { "walls": Array[Rect2], "floor_rects": Array[Rect2], "rooms": Array[Rect2],
#    "spawn": Vector2, "exit": Vector2, "path": Array[Vector2],
#    "enemies": Array[Vector2], "mercenaries": Array[Vector2], "pickup": Vector2,
#    "crates": Array[Vector2],
#    # ↓ R-94 新增。`doors` = 本层**全部门格**的 tile 坐标（开门时显式记账，见 `_carve_door`），
#    #   用来把"门格"从数据上区分出来 —— 因为门格就是地面格（grid=1），光看 grid 分不出来。
#    #   `crate_pool_kind` = 宝箱候选池实际用了哪一档（"wall_no_door" / "wall_with_door" /
#    #   "floor_fallback"），供测试**观测**有没有走到兜底（断言 ④）。
#    "doors": Array[Vector2i], "crate_pool_kind": String,
#    # ↓ R-104 新增。`crate_kinds[i]` = `crates[i]` 的类型 id（weapon/medical/food/material）。
#    #   **纯哈希** (seed, floor, index) 决定，**不消耗 rng** → 布局随机性与既有基线零变动。
#    "crate_kinds": Array,
#    "cols": int, "rows": int, "grid": PackedByteArray }
func generate(seed: int, floor: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(seed, floor)
	var cols: int = int(GameConstants.WORLD_W) / TILE
	var rows: int = int(GameConstants.WORLD_H) / TILE
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	grid.fill(0)  # 0=实心(墙)，1=地面

	var max_room: int = clampi(ROOM_MAX_BASE - floor / 4, ROOM_MAX_MIN, ROOM_MAX_BASE)

	# ---- 一级：街区（分割缝 = 走廊）----
	var blocks: Array = []
	var block_seams: Array = []
	var root := Rect2i(BORDER, BORDER, cols - BORDER * 2, rows - BORDER * 2)
	_bsp(root, BLOCK_MAX, BLOCK_MIN, 1.0, CORRIDOR_W, rng, blocks, block_seams)

	# ---- 二级：每个街区内缩 1 tile 后再切小房间 ----
	var rooms: Array = []
	var room_seams: Array = []
	var block_inners: Array = []
	for b in blocks:
		var inner := Rect2i(b.position + Vector2i(1, 1), b.size - Vector2i(2, 2))
		if inner.size.x < ROOM_MIN * 2 + 1 or inner.size.y < ROOM_MIN * 2 + 1:
			# 街区太小：整体留作实心（不产房间）
			continue
		block_inners.append({"block": b, "inner": inner})
		_bsp(inner, max_room, ROOM_MIN, ROOM_CORRIDOR_CHANCE, ROOM_CORRIDOR_W, rng, rooms, room_seams)

	var floor_cells: Array[Vector2i] = []
	var floor_rects: Array[Rect2] = []
	# 1) 地面：一级走廊 + 二级房间 + 二级内部过道
	for s in block_seams:
		var sr: Rect2i = s["rect"]
		_carve_rect(grid, cols, rows, sr, floor_cells)
		floor_rects.append(Rect2(sr.position.x * TILE, sr.position.y * TILE, sr.size.x * TILE, sr.size.y * TILE))
	for r in rooms:
		_carve_rect(grid, cols, rows, r, floor_cells)
		floor_rects.append(Rect2(r.position.x * TILE, r.position.y * TILE, r.size.x * TILE, r.size.y * TILE))
	for s in room_seams:
		if s["open"]:
			var sr2: Rect2i = s["rect"]
			_carve_rect(grid, cols, rows, sr2, floor_cells)
			floor_rects.append(Rect2(sr2.position.x * TILE, sr2.position.y * TILE, sr2.size.x * TILE, sr2.size.y * TILE))
	# 2) 房间之间的墙缝 → 开门
	# R-94：`door_cells` 记账门格（开门 = 把那几格改成地面 → 数据上与普通地面格无法区分）。
	#   纯记账，**不碰 rng** → 不影响确定性，也不影响后续任何随机分布。
	var door_cells: Array[Vector2i] = []
	for s in room_seams:
		if not s["open"]:
			_punch_door(grid, cols, rows, s, floor_cells, door_cells, rng, DOOR_MIN, DOOR_MAX)
	# 3) 每个街区：环上开 1–2 个通往走廊的门
	for bi in block_inners:
		_punch_ring_door(grid, cols, rows, bi["block"], floor_cells, door_cells, rng)
		_punch_ring_door(grid, cols, rows, bi["block"], floor_cells, door_cells, rng)

	# ---- 出生点 / 出口 / 寻路 ----
	var spawn_room: Rect2i = rooms[0]
	for r in rooms:
		if r.position.x < spawn_room.position.x:
			spawn_room = r
	var spawn_tile := _rect_center(spawn_room)
	var spawn := _tile_center(spawn_tile)

	var dist := _bfs_dist(grid, cols, rows, spawn_tile)
	var exit_tile := spawn_tile
	var best := -1
	for y in rows:
		for x in cols:
			var d: int = dist[y * cols + x]
			if d > best:
				best = d
	var candidates: Array[Vector2i] = []
	if best > 0:
		var threshold: int = int(best * 0.6)
		for y in rows:
			for x in cols:
				if dist[y * cols + x] >= threshold and x >= int(cols * 0.35):
					candidates.append(Vector2i(x, y))
	if candidates.size() > 0:
		exit_tile = candidates[rng.randi_range(0, candidates.size() - 1)]
	if best <= 0:
		exit_tile = Vector2i(mini(spawn_tile.x + 40, cols - 2), spawn_tile.y)
		_carve_rect(grid, cols, rows, Rect2i(spawn_tile.x, spawn_tile.y - 1, exit_tile.x - spawn_tile.x + 1, 3), floor_cells)
		dist = _bfs_dist(grid, cols, rows, spawn_tile)
	var exit_pos := _tile_center(exit_tile)
	# ⚠ 不做"视线简化"：Bresenham 采样的直线段会切墙角（格子级通过但物理上过不去），
	#   会让 bot 卡死在墙前。保持原始 BFS 路径（4 连通，保证可走）。
	var path := _bfs_path(dist, cols, rows, spawn_tile, exit_tile)

	# ---- 内容放置（R-62：同类型"成群"生成 → 聚成簇）----
	var floor_set := {}
	for c in floor_cells:
		floor_set[c] = true
	# R-105：数量曲线改为几何增长。**这两个调用是本批唯一的改动点**，
	#   数量以参数形式传入 —— `_sample_clustered` 内部逻辑、簇半径、簇大小、
	#   间距规则一律不动（边界：不得顺手改 AI / 碰撞 / 感知）。
	var enemy_count: int = enemy_count_for_floor(floor)
	var enemies := _sample_clustered(floor_cells, floor_set, spawn, exit_pos, rng, enemy_count, SPAWN_CLEAR_ENEMY, CLUSTER_RADIUS_UNDEAD, CLUSTER_SIZE_UNDEAD)
	var merc_count: int = merc_count_for_floor(floor)
	var mercenaries := _sample_clustered(floor_cells, floor_set, spawn, exit_pos, rng, merc_count, SPAWN_CLEAR_MERC, CLUSTER_RADIUS_MERC, CLUSTER_SIZE_MERC)
	# ==== R-146 · 快攻型僵尸（Brute）====
	#   用户逐字：「刷新点也在一起但刷新数量比普通僵尸少一半」。
	#   ⚠⚠ **必须走 `enemies` 的下标抽样，绝不重新调 `_sample_clustered`** ——
	#     `_sample_clustered` 消耗 `rng`（第 1 个参数就是它），多调一次会让
	#     **同种子的箱子 / 出口 / pickup 坐标全部偏移** = 静默的全局布局变更，
	#     直接违反 R-104 铁律（`--verify-enemycurve` ⑦ 就是钉这一条的）。
	#   为什么偶数下标 = 严格「一半」且**确定性好**：`count = n/2` 精确，
	#   且不引入任何新的随机性（同 seed 两次生成结果逐字节相同）。
	var brutes: Array[Vector2] = []
	for i in range(0, enemies.size(), 2):
		brutes.append(enemies[i])
	# 家具：箱子（R-65 / R-67；R-79 数量加大 + 只贴墙放）——彼此留间距，离出生/出口留距离
	# ⚠ 箱子挡玩家 → 绝不能压在「出生→出口」主路径上（否则 bot 会顶着箱子卡死）
	var path_tiles := {}
	for p in path:
		path_tiles[Vector2i(int(p.x) / TILE, int(p.y) / TILE)] = true
	# R-79：候选池 = **紧邻墙的地面格**（而不是全部地面格）
	var wall_cells := _wall_adjacent_floor_cells(grid, cols, rows, floor_set)
	# ---- R-94：候选池**排除门格** ----
	# 门格本身也是地面格（grid=1），而且门洞两端的格子紧挨实心墙 → 会被
	# `_wall_adjacent_floor_cells` 判成"贴墙" → 混进候选池 → 箱子摆在门口。
	# 这里把 `door_cells`（开门时显式记账，见 `_carve_door`）从贴墙格里剔掉。
	#
	# ⚠ 兜底改成**三档**，且**绝不**因为剔门格就掉到"全部地面格"那一档：
	#   "wall_no_door"  = 贴墙格 − 门格（正常路径，绝大多数层走这档）
	#   "wall_with_door"= 贴墙格（含门格，仅当剔完门格一颗都不剩时）
	#   "floor_fallback"= 全部地面格（仅当**连贴墙格都没有**时 —— 理论上不可能，
	#                     因为 `BORDER=1` 的外墙必然产生大量贴墙格）
	# 为什么要分三档：`floor_fallback` 那一档会让箱子跑到**走廊中央**，
	# 同时破坏 R-79 的「必须靠墙」硬约束和"不挡 bot"的设计意图。
	# 中间那档"宁可摆门口也不破坏靠墙约束"是更安全的降级 —— 门口挡一下
	# 只是体验问题，箱子摊在走廊中央会让 bot 顶死、也会推翻 R-79 的立论。
	var door_set := {}
	for dc in door_cells:
		door_set[dc] = true
	var wall_no_door: Array[Vector2i] = []
	for wc in wall_cells:
		if not door_set.has(wc):
			wall_no_door.append(wc)
	var pool: Array[Vector2i] = []
	var crate_pool_kind := "wall_no_door"
	if wall_no_door.size() > 0:
		pool = wall_no_door
	elif wall_cells.size() > 0:
		pool = wall_cells
		crate_pool_kind = "wall_with_door"
	else:
		pool = floor_cells
		crate_pool_kind = "floor_fallback"
	pool = pool.duplicate()
	var crates: Array[Vector2] = []
	var want_crates: int = clampi(CRATE_MIN + floor * CRATE_PER_FLOOR, CRATE_MIN, CRATE_MAX)
	var ctries := 0
	while crates.size() < want_crates and ctries < want_crates * 60 + 200 and pool.size() > 0:
		ctries += 1
		# 用完即弃（swap-remove）：保证不重复抽同一格，且不会像"纯随机重试"那样偏向靠前的候选
		var pick: int = rng.randi_range(0, pool.size() - 1)
		var ct: Vector2i = pool[pick]
		pool.remove_at(pick)
		if path_tiles.has(ct):
			continue                       # 主路径上不放箱子
		var p := _tile_center(ct)
		if p.distance_to(spawn) < CRATE_SPAWN_CLEAR or p.distance_to(exit_pos) < CRATE_EXIT_CLEAR:
			continue
		var too_close := false
		for c in crates:
			if p.distance_to(c) < CRATE_SPACING:
				too_close = true
				break
		if too_close:
			continue
		crates.append(p)
	# 兜底：箱子不能把路堵死。R-79 起把口径从「出生→出口可达」升级为
	#   「**所有房间**都还能从出生点走到」—— 宝箱数量翻倍后，只保出口可达会漏掉
	#   「某个房间被堵住 → 玩家进不去、那间 loot 白生成」的情况。
	var reach_tiles: Array[Vector2i] = []
	for r in rooms:
		reach_tiles.append(_rect_center(r))
	reach_tiles.append(exit_tile)
	var cguard := 0
	while crates.size() > 0 and cguard < crates.size() + 8:
		var blocked := {}
		for cp in crates:
			blocked[int(cp.y) / TILE * cols + int(cp.x) / TILE] = true
		var d2 := _bfs_dist(grid, cols, rows, spawn_tile, blocked)
		var all_ok := true
		for rt in reach_tiles:
			if d2[rt.y * cols + rt.x] < 0:
				all_ok = false
				break
		if all_ok:
			break
		crates.remove_at(crates.size() - 1)
		cguard += 1
	# ==== R-104：给每个箱子定类型（与 `crates` **同下标**，长度必须一致）====
	# ⚠⚠ **刻意用纯哈希、绝不碰 `rng`** —— 这是本批最重要的一处实现约束。
	#   若改成"再从 rng 抽 N 次"，rng 流会整体后移 → 敌人簇 / pickup / 出口位置**全部改变**
	#   = 一次**静默的关卡布局变更**，而且 R-79/R-94 的既有基线（--verify-crate / --verify-cratedoor
	#   逐层打印的 crates 坐标）会全部漂移。纯哈希让 `crates` 数组**逐字节不变**。
	#   → 同种子两次生成：坐标**与类型**都完全一致（--verify-cratetype ⑥ 守着这条）。
	# ⚠ 哈希**必须放在 cguard 之后**（`crates` 可能被兜底删掉尾巴），否则类型数组会与坐标错位。
	var crate_kinds: Array = []
	for ci in crates.size():
		crate_kinds.append(crate_kind_of(seed, floor, ci))
	var pickup := spawn
	var ptries := 0
	while ptries < 300 and floor_cells.size() > 0:
		ptries += 1
		var pp := _tile_center(floor_cells[rng.randi_range(0, floor_cells.size() - 1)])
		if pp.distance_to(spawn) < 120.0 or pp.distance_to(exit_pos) < EXIT_CLEAR:
			continue
		pickup = pp
		break

	var band := _wall_band(grid, cols, rows)
	var walls := _mesh(band, cols, rows)

	var room_rects: Array[Rect2] = []
	for r in rooms:
		room_rects.append(Rect2(r.position.x * TILE, r.position.y * TILE, r.size.x * TILE, r.size.y * TILE))

	return {
		"walls": walls, "floor_rects": floor_rects, "rooms": room_rects,
		"spawn": spawn, "exit": exit_pos, "path": path,
		"enemies": enemies, "mercenaries": mercenaries, "pickup": pickup, "crates": crates,
		# R-146：快攻型僵尸（Brute）—— 与 enemies 同刷新点、为其一半（偶数下标）。
		#   ⚠ 键名是**新增**而非替换：63 个既有验证入口里有 12 处读 `data["enemies"]`，
		#   加键不影响它们（缺键才是破坏）。
		"brutes": brutes,
		# R-94：门格坐标（本层全部门洞的格子）+ 实际用的候选池档位（供测试观测兜底）
		"doors": door_cells, "crate_pool_kind": crate_pool_kind,
		# ↓ R-104 新增：`crate_kinds[i]` = `crates[i]` 的箱子类型 id（"weapon"/"medical"/
		#   "food"/"material"）。**与 crates 同下标、同长度**（cguard 可能删掉坐标尾巴，
		#   所以本数组在 cguard 之后才生成）。由纯哈希决定，不消耗 rng（见上方注释）。
		"crate_kinds": crate_kinds,
		"cols": cols, "rows": rows, "grid": grid,
	}

# === BSP 递归分割 ===
# corridor_chance：分割缝做成「走廊」的概率（1.0=全走廊，0.0=全墙）；corridor_gap：走廊宽
func _bsp(area: Rect2i, max_side: int, min_side: int, corridor_chance: float, corridor_gap: int, rng: RandomNumberGenerator, leaves: Array, seams: Array) -> void:
	var w: int = area.size.x
	var h: int = area.size.y
	if w <= max_side and h <= max_side:
		leaves.append(area)
		return
	var can_v: bool = w >= min_side * 2 + 1
	var can_h: bool = h >= min_side * 2 + 1
	var split_v: bool = can_v if w >= h else (not can_h)
	if split_v and not can_v:
		leaves.append(area)
		return
	if not split_v and not can_h:
		leaves.append(area)
		return

	var corridor: bool = rng.randf() < corridor_chance
	var gap: int = corridor_gap if corridor else 1
	if split_v:
		var lo: int = area.position.x + min_side
		var hi: int = area.position.x + w - min_side - gap
		if hi < lo:
			leaves.append(area)
			return
		var cut: int = rng.randi_range(lo, hi)
		var a := Rect2i(area.position, Vector2i(cut - area.position.x, h))
		var b := Rect2i(Vector2i(cut + gap, area.position.y), Vector2i(area.position.x + w - cut - gap, h))
		seams.append({"rect": Rect2i(cut, area.position.y, gap, h), "vertical": true, "open": corridor})
		_bsp(a, max_side, min_side, corridor_chance, corridor_gap, rng, leaves, seams)
		_bsp(b, max_side, min_side, corridor_chance, corridor_gap, rng, leaves, seams)
	else:
		var lo2: int = area.position.y + min_side
		var hi2: int = area.position.y + h - min_side - gap
		if hi2 < lo2:
			leaves.append(area)
			return
		var cut2: int = rng.randi_range(lo2, hi2)
		var a2 := Rect2i(area.position, Vector2i(w, cut2 - area.position.y))
		var b2 := Rect2i(Vector2i(area.position.x, cut2 + gap), Vector2i(w, area.position.y + h - cut2 - gap))
		seams.append({"rect": Rect2i(area.position.x, cut2, w, gap), "vertical": false, "open": corridor})
		_bsp(a2, max_side, min_side, corridor_chance, corridor_gap, rng, leaves, seams)
		_bsp(b2, max_side, min_side, corridor_chance, corridor_gap, rng, leaves, seams)

# 在墙缝上开门（两侧都是地面处），连通两个子树
# R-94：`door_cells` 收集门格坐标 —— 只**记账**，不碰 rng（确定性不受影响）
func _punch_door(grid: PackedByteArray, cols: int, rows: int, seam: Dictionary, floor_cells: Array[Vector2i], door_cells: Array[Vector2i], rng: RandomNumberGenerator, dmin: int, dmax: int) -> void:
	var r: Rect2i = seam["rect"]
	var vertical: bool = seam["vertical"]
	var span: int = r.size.y if vertical else r.size.x
	if span <= 0:
		return
	var door: int = mini(rng.randi_range(dmin, dmax), span)
	var start := -1
	var scan := 0
	while scan + door <= span:
		var ok := true
		for k in door:
			if vertical:
				var yy := r.position.y + scan + k
				if grid[yy * cols + (r.position.x - 1)] == 0 or grid[yy * cols + (r.position.x + r.size.x)] == 0:
					ok = false
					break
			else:
				var xx := r.position.x + scan + k
				if grid[(r.position.y - 1) * cols + xx] == 0 or grid[(r.position.y + r.size.y) * cols + xx] == 0:
					ok = false
					break
		if ok:
			start = scan
			break
		scan += 1
	if start < 0:
		start = maxi(0, (span - door) / 2)
	for k in door:
		if vertical:
			_carve_door(grid, cols, rows, r.position.x, r.position.y + start + k, floor_cells, door_cells)
		else:
			_carve_door(grid, cols, rows, r.position.x + start + k, r.position.y, floor_cells, door_cells)

# 街区环开门：在「内侧是房间地面 + 外侧是走廊地面」的位置开 2–3 tile 的门
# R-94：`door_cells` 收集门格坐标 —— 只**记账**，不碰 rng（确定性不受影响）
func _punch_ring_door(grid: PackedByteArray, cols: int, rows: int, b: Rect2i, floor_cells: Array[Vector2i], door_cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	var width: int = rng.randi_range(DOOR_MIN, DOOR_MAX)
	var start: int = rng.randi_range(0, 3)
	for i in 4:
		var s: int = (start + i) % 4
		var span: int = b.size.x if (s == 0 or s == 1) else b.size.y
		if span < width + 2:
			continue
		var cands: PackedInt32Array = PackedInt32Array()
		for off in range(1, span - width):
			var ok := true
			for k in width:
				var gx := 0
				var gy := 0
				if s == 0 or s == 1:
					gx = b.position.x + off + k
					gy = b.position.y if s == 0 else (b.position.y + b.size.y - 1)
				else:
					gy = b.position.y + off + k
					gx = b.position.x if s == 2 else (b.position.x + b.size.x - 1)
				var ix := gx
				var iy := gy
				var ox := gx
				var oy := gy
				match s:
					0:
						iy = gy + 1
						oy = gy - 1
					1:
						iy = gy - 1
						oy = gy + 1
					2:
						ix = gx + 1
						ox = gx - 1
					_:
						ix = gx - 1
						ox = gx + 1
				if grid[iy * cols + ix] == 0:
					ok = false
					break
				if oy < 0 or oy >= rows or ox < 0 or ox >= cols or grid[oy * cols + ox] == 0:
					ok = false
					break
			if ok:
				cands.append(off)
		if cands.size() > 0:
			var off2: int = cands[rng.randi_range(0, cands.size() - 1)]
			for k in width:
				var cx := 0
				var cy := 0
				if s == 0 or s == 1:
					cx = b.position.x + off2 + k
					cy = b.position.y if s == 0 else (b.position.y + b.size.y - 1)
				else:
					cy = b.position.y + off2 + k
					cx = b.position.x if s == 2 else (b.position.x + b.size.x - 1)
				_carve_door(grid, cols, rows, cx, cy, floor_cells, door_cells)
			return

# === 雕刻 ===
func _carve_rect(grid: PackedByteArray, cols: int, rows: int, r: Rect2i, floor_cells: Array[Vector2i]) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			_carve(grid, cols, rows, x, y, floor_cells)

func _carve(grid: PackedByteArray, cols: int, rows: int, x: int, y: int, floor_cells: Array[Vector2i]) -> void:
	if x < 0 or x >= cols or y < 0 or y >= rows:
		return
	var i := y * cols + x
	if grid[i] == 0:
		grid[i] = 1
		floor_cells.append(Vector2i(x, y))

# R-94：开门专用 = `_carve` + **记账门格**。
# 为什么必须在这里（唯一知道"这格是门"的地方）记账：开门就是把这格从实心改成地面，
# 之后 `grid` 里它与普通地面格**完全同构**（都是 1），靠事后看 grid / 看几何都分不出来。
# ⚠ 纯记账：不消耗 rng、不改 grid 语义 → 不影响确定性与任何后续随机分布。
#   记不记"这格之前已经是地面"（`_carve` 内部的 `grid[i] == 0` 判断）都记 ——
#   门洞语义上就是这几格，宁可多剔一点也不能漏。
func _carve_door(grid: PackedByteArray, cols: int, rows: int, x: int, y: int, floor_cells: Array[Vector2i], door_cells: Array[Vector2i]) -> void:
	if x < 0 or x >= cols or y < 0 or y >= rows:
		return
	door_cells.append(Vector2i(x, y))
	_carve(grid, cols, rows, x, y, floor_cells)

# === 连通 / 寻路 ===
# blocked：额外不可走的格子索引集合（用于「箱子挡路」检查）
func _bfs_dist(grid: PackedByteArray, cols: int, rows: int, from: Vector2i, blocked: Dictionary = {}) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(-1)
	var start := from.y * cols + from.x
	if grid[start] == 0:
		return dist
	dist[start] = 0
	var q := PackedInt32Array()
	q.append(start)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var cx := cur % cols
		var cy := cur / cols
		var nd: int = dist[cur] + 1
		if cx > 0: _push(grid, dist, q, cur - 1, nd, blocked)
		if cx < cols - 1: _push(grid, dist, q, cur + 1, nd, blocked)
		if cy > 0: _push(grid, dist, q, cur - cols, nd, blocked)
		if cy < rows - 1: _push(grid, dist, q, cur + cols, nd, blocked)
	return dist

func _push(grid: PackedByteArray, dist: PackedInt32Array, q: PackedInt32Array, ni: int, nd: int, blocked: Dictionary = {}) -> void:
	if grid[ni] == 1 and dist[ni] == -1 and not blocked.has(ni):
		dist[ni] = nd
		q.append(ni)

func _bfs_path(dist: PackedInt32Array, cols: int, rows: int, from: Vector2i, to: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if dist[to.y * cols + to.x] == -1:
		return out
	var cur := to
	var guard := 0
	while cur != from and guard < cols * rows:
		guard += 1
		out.append(_tile_center(cur))
		var d: int = dist[cur.y * cols + cur.x]
		var next := cur
		if cur.x > 0 and dist[cur.y * cols + cur.x - 1] == d - 1:
			next = Vector2i(cur.x - 1, cur.y)
		elif cur.x < cols - 1 and dist[cur.y * cols + cur.x + 1] == d - 1:
			next = Vector2i(cur.x + 1, cur.y)
		elif cur.y > 0 and dist[(cur.y - 1) * cols + cur.x] == d - 1:
			next = Vector2i(cur.x, cur.y - 1)
		elif cur.y < rows - 1 and dist[(cur.y + 1) * cols + cur.x] == d - 1:
			next = Vector2i(cur.x, cur.y + 1)
		else:
			break
		cur = next
	out.append(_tile_center(from))
	out.reverse()
	return out

# === 墙带 + 贪心合并 ===
func _wall_band(grid: PackedByteArray, cols: int, rows: int) -> PackedByteArray:
	var band := PackedByteArray()
	band.resize(cols * rows)
	for y in rows:
		for x in cols:
			var i := y * cols + x
			if grid[i] == 1:
				continue
			if _has_floor_neighbor(grid, cols, rows, x, y):
				band[i] = 1
	return band

func _has_floor_neighbor(grid: PackedByteArray, cols: int, rows: int, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
				continue
			if grid[ny * cols + nx] == 1:
				return true
	return false

func _mesh(band: PackedByteArray, cols: int, rows: int) -> Array[Rect2]:
	var used := PackedByteArray()
	used.resize(cols * rows)
	var rects: Array[Rect2] = []
	for y in rows:
		for x in cols:
			var idx := y * cols + x
			if band[idx] == 0 or used[idx] == 1:
				continue
			var w := 0
			while x + w < cols and band[y * cols + x + w] == 1 and used[y * cols + x + w] == 0:
				w += 1
			var h := 1
			while y + h < rows:
				var ok := true
				for k in w:
					var i2 := (y + h) * cols + x + k
					if band[i2] == 0 or used[i2] == 1:
						ok = false
						break
				if not ok:
					break
				h += 1
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					used[yy * cols + xx] = 1
			rects.append(Rect2(x * TILE, y * TILE, w * TILE, h * TILE))
	return rects

# ==== R-118：静态地图（R-118 `data/floor100.txt`）用的**公开薄封装** ====
#
# 【为什么加封装、而不是让 StaticFloor.gd 直接调 `_wall_band` / `_mesh`】
#   两个理由，都是"别让实现漂移"：
#   ① `_mesh` 的**贪心合并算法是几何一致性的单一权威源**：墙矩形要能和地面矩形
#      用同一套合并规则，否则会出现"墙画出来了但盖住地板"或"地板漏画"的错位。
#      复制一份 `_mesh` 到解析器 = 两份算法各自演化 = 迟早不一致。
#   ② `_`-前缀函数是**内部约定**。GDScript 没有 private，外部能调，但不该调——
#      一旦解析器直接依赖 `_mesh`，就等于把内部签名变成对外契约，
#      以后想改 `_mesh` 的实现就会连带炸掉别的模块。封装层是**稳定契约**。
#
# 【⚠ 本批刻意保持极薄 —— 只做"转发 + 明确类型"，不加任何新逻辑】
#   原函数体 `_wall_band` / `_mesh` / `_bfs_dist` / `_bfs_path` / `_tile_center`
#   **一个字符都没改**（R-118 硬性约束）。薄封装的另一重价值：
#   它们是"静态地图路径"和"程序化路径"**共用同一份几何代码**的证据 ——
#   若哪天有人改了 `_mesh`，两个入口会**同时**改变行为，不会只坏一边。
#
# 【为什么 1–99 层行为逐字不变】
#   `generate()` 内部**不调**这些封装（保持调用栈原样），所以战斗层的
#   逐字节可复现性（R-104铁律）不受任何影响。封装是"只读复用"，不是"重构"。

# 网格 -> 墙矩形。语义与 `generate()` 内部那段完全一致：
#   band = 紧邻地面的实心格（`_wall_band`），再贪心合并成矩形（`_mesh`）。
func build_walls_from_grid(grid: PackedByteArray, cols: int, rows: int) -> Array[Rect2]:
	return _mesh(_wall_band(grid, cols, rows), cols, rows)

# 任意 0/1 掩码 -> 矩形（直接暴露 `_mesh`，供解析器合并"地面格集合"用）。
# ⚠ 调用方需自己保证语义：`1` 的格会被合并，`0` 的格被忽略。
#   地面矩形 =传"ground[i]=1 当且仅当该格是地板"的掩码（`_mesh` 判的是 `band[i]==1`，
#   所以不能直接把 grid 传进去 —— grid 里墙是 0，而我们要的是"地板=1"）。
func mesh_from_mask(mask: PackedByteArray, cols: int, rows: int) -> Array[Rect2]:
	return _mesh(mask, cols, rows)

# ==== R-131：网格 -> **墙带掩码**（`1` = 该格是墙，`0` = 不是墙）====
# 【为什么需要这个新封装 —— 它不是"重复实现"，而是"补一个原本就缺的出口"】
#   `build_walls_from_grid()` 给的是**墙带合并后的矩形**（碰撞体与可视都用它）。
#   而 R-131 的 `TileGround` 需要的是**逐格的墙带掩码**，原因有两条：
#     ① 邻接收边（北侧受光高光 / 东西侧暗线）与墙脚落地阴影是**逐格邻接判定**，
#        合并后的矩形已经丢掉了「这一格四周分别邻接着什么」的信息，无法还原。
#     ② 若改用 `grid == 0` 当「墙」，会把**深埋实心区**（既不可走、也不在碰撞里）
#        也画成墙 -> 玩家看到一大片「看得见却走不过去」的假墙。
#        故必须用**与碰撞完全同源**的墙带，而不是 grid 的补集。
#   ⚠ 实现仍然**只调 `_wall_band` 一个私有函数**，不复制它的 8 邻域判据 ——
#     这样「画出来的墙」与「撞得到的墙」永远同源，不会各自演化。
# ⚠ 与 R-118 那批封装同一取舍：**只加薄转发，不改既有实现**，故 1–99 层
#   逐字节可复现性（R-104 铁律）不受影响。
func build_wall_band_from_grid(grid: PackedByteArray, cols: int, rows: int) -> PackedByteArray:
	return _wall_band(grid, cols, rows)

# 两点间BFS 路径（格坐标 -> 格中心 Vector2 序列，与 `generate()` 的 path 同构）。
# 空数组表示不可达。⚠ 不接受 blocked：本批静态地图没有"箱子挡路"的概念。
func build_path_from_grid(grid: PackedByteArray, cols: int, rows: int, from: Vector2i, to: Vector2i) -> Array[Vector2]:
	if from.x < 0 or from.x >= cols or from.y < 0 or from.y >= rows:
		return []
	if to.x < 0 or to.x >= cols or to.y < 0 or to.y >= rows:
		return []
	var dist := _bfs_dist(grid, cols, rows, from)
	return _bfs_path(dist, cols, rows, from, to)

# 从某点出发的 BFS 距离场（-1 = 不可达）。解析器用它挑"离出生点足够远的合法地面格"。
func bfs_dist_from_grid(grid: PackedByteArray, cols: int, rows: int, from: Vector2i) -> PackedInt32Array:
	if from.x < 0 or from.x >= cols or from.y < 0 or from.y >= rows:
		var empty := PackedInt32Array()
		empty.resize(cols * rows)
		empty.fill(-1)
		return empty
	return _bfs_dist(grid, cols, rows, from)

# 格坐标 -> 格中心（对外口径：`(t + 0.5) * TILE`，即 x*16+8）。
# ⚠ 与 `generate()` 用的是**同一个** `_tile_center`，保证静态地图的出生点/出口
#   与程序化楼层落在**同一像素位置口径**上（差1px 都会让 depart tile 偏移断言漂移）。
func tile_center_of(t: Vector2i) -> Vector2:
	return _tile_center(t)

# === 工具 ===
# 成群采样（R-62）：选"簇心"，再取簇心附近的地面格 → 同类型敌人聚在一起
func _sample_clustered(floor_cells: Array[Vector2i], floor_set: Dictionary, spawn: Vector2, exit_pos: Vector2, rng: RandomNumberGenerator, count: int, spawn_clear: float, radius: int, cluster_size: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var used: Dictionary = {}          # 已占用格（避免同格重复放置）
	if floor_cells.size() == 0 or count <= 0:
		return out
	var guard := 0
	while out.size() < count and guard < count * 40 + 200:
		guard += 1
		# 选一个合法簇心（离出生 / 出口够远）
		var c: Vector2i = floor_cells[rng.randi_range(0, floor_cells.size() - 1)]
		var center := _tile_center(c)
		if center.distance_to(spawn) < spawn_clear or center.distance_to(exit_pos) < EXIT_CLEAR:
			continue
		# 收集簇心附近的可放置地面格
		var near: Array[Vector2] = []
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
					var t := Vector2i(c.x + dx, c.y + dy)
					if not floor_set.has(t):
						continue
					var p := _tile_center(t)
					if p.distance_to(spawn) < spawn_clear or p.distance_to(exit_pos) < EXIT_CLEAR:
						continue
					if used.has(p):
						continue
					near.append(p)
		if near.is_empty():
			continue
		# 离簇心最近的优先 → 簇内紧凑（否则会挑到窗口边缘，形成散兵）
		near.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.distance_squared_to(center) < b.distance_squared_to(center))
		var take := cluster_size  # 局部变量（不可改参数，否则后续簇无法放置）
		while near.size() > 0 and out.size() < count and take > 0:
			out.append(near[0])
			used[near[0]] = true
			near.remove_at(0)
			take -= 1
	return out

func _rect_center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)

func _tile_center(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)

# R-79：紧邻墙的地面格（4 邻域里至少有一个**非地面**格）。
# 箱子只从这些格子里取 → 天然"靠墙"，既不挡走廊也不会顶死门。
# ⚠ `BORDER = 1` 保证所有地面格都在 [1, cols-2] × [1, rows-2] 内，所以 t±1 不会越界，无需额外判界。
# ⚠⚠ R-94 补注（本函数**故意**不做门格过滤，改在调用方过滤）：
#   "非地面格"里**混着门**—— 门格是地面格，但它旁边的实心墙让门洞两端的格子
#   也满足"四邻域有一格非地面"。本函数只回答"贴不贴墙"，**不回答"是不是门"**
#   （它拿不到门的信息）。所以 `generate()` 里用 `door_cells` 在**下游**剔除，
#   保持本函数职责单一、也便于 R-79 的既有语义与 `--verify-crate` 的基线不变。
func _wall_adjacent_floor_cells(grid: PackedByteArray, cols: int, rows: int, floor_set: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in rows:
		for x in cols:
			var t := Vector2i(x, y)
			if not floor_set.has(t):
				continue
			var near_wall: bool = not floor_set.has(t + Vector2i(1, 0)) \
				or not floor_set.has(t + Vector2i(-1, 0)) \
				or not floor_set.has(t + Vector2i(0, 1)) \
				or not floor_set.has(t + Vector2i(0, -1))
			if near_wall:
				out.append(t)
	return out

# ==== R-105：敌人 / 佣兵数量曲线（几何增长，每层 x1.3）====
# ⚠⚠ **两条曲线都是纯函数，绝不消耗 rng** —— 这是本批最重要的实现约束。
#   它们只做整数运算，不碰随机数流；`generate()` 里也是**先算数量、再当参数传下去**，
#   所以「同一个seed 的两次生成」与「改动前/改动后」在**数量相同**的楼层上
#   敌人簇 / 箱子 / pickup / 出口坐标**逐字节一致**（R-104 铁律）。
#   证据：`--verify-enemycurve` ⑦ 断言同种子两次「数量 + 坐标」全等。
#
# 【为什么用「迭代」而不是闭式 `roundi(BASE * GROWTH^(f-1))`】
#   迭代 = 每层拿**上一层的取整结果**再乘 GROWTH。这才是"每层增加约 30%"的字面语义，
#   也才逐位对得上用户拍板表（11/14/18/23/30/39/51/60）。
#   闭式会得到 11/14/**19**/24/31/41/53（第 3 层就差 1），因为闭式每层都从"未取整的
#   真实值"重新算，误差不累积 —— 听起来更好，但它**不是用户拍板的那张表**。
#   取整统一用 `roundi`（四舍五入；**不是 `int()`**，GDScript 的 `int()` 是向零截断）。
func enemy_count_for_floor(f: int) -> int:
	var n: int = ENEMY_BASE
	for _i in range(ENEMY_BASE_FLOOR + 1, f + 1):
		if n >= MAX_ENEMY:
			break
		n = roundi(float(n) * ENEMY_GROWTH)
	return mini(n, MAX_ENEMY)

# 佣兵曲线：起始层之前恒为 0（分层设计：前期无佣兵），之后同样是每层 x1.3。
# ⚠ 封顶用 `MAX_MERC`(16) 而**不是** `MAX_ENEMY`(60) —— 数据支撑见常量区注释。
func merc_count_for_floor(f: int) -> int:
	if f < MERC_FROM_FLOOR:
		return 0
	var n: int = MERC_BASE
	for _i in range(MERC_FROM_FLOOR + 1, f + 1):
		if n >= MAX_MERC:
			break
		n = roundi(float(n) * MERC_GROWTH)
	return mini(n, MAX_MERC)

func _mix(seed: int, floor: int) -> int:
	return (int(seed) * 2654435761) ^ (int(floor) * 40503)

# ==== R-104：箱子类型 = (seed, floor, index) 的**纯函数** ====
# 【为什么必须是纯函数、且不能碰 rng —— 见 `generate()` 里 `crate_kinds` 处的注释】
#   核心：多消耗一次 rng，后续所有随机分布（敌人簇 / pickup / 出口）全部偏移 = 静默布局变更。
# 【哈希构造：splitmix64 的 finalizer 风格（xor-shift + 奇数乘法 + 再次 xor-shift）】
#   为什么要 avalanche：`^` 和 `*` 单独用的低位熵很差（`index` 只在最低位变 1），
#   不做 avalanche 的话相邻 index 会得到相邻的 mod 4 结果 → 出现"一串箱子全是同一类"的规律，
#   玩家会看到地图上某个区域全是医疗箱。两次 xor-shift 之后相邻 index 的输出看着是随机的。
# ⚠ `& 0x7FFFFFFF`：清掉符号位。GDScript 的 int 是 **64 位有符号**，
#   不清符号位的话 `% 4` 可能得到**负数**下标 → `CRATE_TYPE_IDS[-1]` 越界返回 null → 静默坏掉。
#   （这是本函数唯一的"平台/语言细节"陷阱，务必保留这行 mask。）
func crate_kind_of(seed: int, floor: int, index: int) -> String:
	var h: int = _mix(seed, floor) ^ (int(index) * 0x9E3779B1)
	h = h & 0x7FFFFFFF
	h = (h ^ (h >> 16)) * 0x85EBCA6B
	h = h & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 0xC2B2AE35
	h = h & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return GameConstants.CRATE_TYPE_IDS[h % GameConstants.CRATE_TYPE_IDS.size()]
