# FogGrid · 三态战争迷雾栅格（cp2 · R-70 · fog-of-war §3.1 三态 / §3.2 LOS / §5 FSM / §6 边界）
# 三态：0=未探索(全黑) / 1=已探索(灰暗记忆·仅地形) / 2=可见(LOS 内·地形 + 动态物体)
# 视野 = 半径 FOG_VISION_RADIUS_TILES + 墙体遮挡 LOS（Bresenham 逐格判定）
#   - 半高家具（箱子）不阻视线：LOS 只用 terrain grid（1=地面 / 0=墙·实心）
#   - 在半径内但被墙挡住的格**不得**可见（口径③④）
# FSM：进入 LOS → 2；离开 LOS → 1；已探索永不回退为未探索（§5）
# 按楼层索引缓存（Dictionary：floor → Array[int]），换层加载 / 切回不丢、不串扰（§6#4）
# ⚠ 禁用 class_name（headless 下曾报 Identifier not declared）→ 调用方用 preload("...").new()
# ⚠ 常量唯一权威源 = GameConstants（FOG_UNEXPLORED / FOG_EXPLORED / FOG_VISIBLE / FOG_VISION_RADIUS_TILES）
extends RefCounted

var _cache: Dictionary = {}          # floor_index → Array[int]（0/1/2）
var _tiles: Array = []               # 当前层（== _cache[_floor_index]；Array 为引用类型 → 原地改即写回缓存）
var _terrain: PackedByteArray = PackedByteArray()  # 当前层地形（1=地面 0=阻视线；已 duplicate，不受调用方后续改动影响）
var _cols: int = 0
var _rows: int = 0
var _floor_index: int = -999999
var _offsets: Array = []             # 半径内的格偏移（预计算）

# 绑定楼层：首次遇到该 floor_index → 新建全「未探索」；已缓存 → 直接加载（已探索不丢）
func set_floor(grid: PackedByteArray, cols: int, rows: int, floor_index: int) -> void:
	_cols = cols
	_rows = rows
	_floor_index = floor_index
	# 拷一份地形：调用方随后可能把「箱子格」清零（那只影响敌人寻路，不该影响 LOS —— 半高家具不阻视线）
	_terrain = grid.duplicate()
	if _cache.has(floor_index):
		_tiles = _cache[floor_index]
	else:
		var arr: Array = []
		arr.resize(cols * rows)
		arr.fill(GameConstants.FOG_UNEXPLORED)
		_cache[floor_index] = arr
		_tiles = arr
	_build_offsets()

func _build_offsets() -> void:
	var r: int = GameConstants.FOG_VISION_RADIUS_TILES
	_offsets = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_offsets.append(Vector2i(dx, dy))

# ==== R-147：V 键「视野扫描」—— 无视遮挡地把半径内网格升为「已探索」====
# 【与 `update_visibility` 的分工】（二者**不可互换**，语义相反）
#   · `update_visibility` = 常态：**半径 ∧ LOS**（被墙挡住的格不可见），且会维护
#     2→1 的降级（离开视野 → 已探索）。它是**每帧/换格**跑的。
#   · `reveal_radius`     = V 键一次性：**只按半径、完全不做 LOS 判定**（用户逐字
#     「无视墙壁等瓦片的遮挡」），且**只升不降**（已探索永不回退，§5）。
#
# ⚠ **为什么不直接复用 `_offsets`**：`_offsets` 是按 `FOG_VISION_RADIUS_TILES` 预计算的，
#   而扫描半径是 `TRACE_SCAN_RADIUS_TILES`（当前同值但**是两个语义不同的旋钮**——
#   一个是"看得见多远"，一个是"扫得到多远"）。写死复用会让将来调视野半径时
#    **静默改掉扫描范围**。故本函数自己按入参现算。
#
# ⚠ **只升到 FOG_EXPLORED，不升到 FOG_VISIBLE**：V 揭示的是"地形记忆"，
#    不是"此刻看得见"。若升到 VISIBLE，下一帧 `update_visibility` 就会把它降回
#    EXPLORED（净效果一样），但中间那一帧的动态物体可见性会被误判 → 白送一帧透视。
func reveal_radius(center_tile: Vector2i, radius_tiles: int) -> int:
	if _cols <= 0 or _rows <= 0 or radius_tiles < 0:
		return 0
	var revealed: int = 0
	for dy in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			if dx * dx + dy * dy > radius_tiles * radius_tiles:
				continue
			var t: Vector2i = center_tile + Vector2i(dx, dy)
			if t.x < 0 or t.x >= _cols or t.y < 0 or t.y >= _rows:
				continue
			var i: int = t.y * _cols + t.x
			if int(_tiles[i]) < GameConstants.FOG_EXPLORED:
				_tiles[i] = GameConstants.FOG_EXPLORED
				revealed += 1
	return revealed

# ==== R-147：重置某一层的探索进度（「重新生成该层地图」时的唯一入口）====
# 【用户需求逐字】「玩家探索的状态也要固化，**只有重新生成该层地图时才重置**
#   玩家的探索进度。」→ 默认**永不重置**（`_cache` 按层保留），
#   只有调用方明确说"这层重新生成了"才清。
#
# ⚠ **必须同步重置 `_tiles`**（若清的正是当前层）：`_tiles` 是 `_cache[key]` 的引用，
#   只在 `erase` 后重建数组是不够的 —— `_tiles` 仍指向被丢弃的旧数组，
#   后续 `update_visibility` 会往一个"已从 cache 摘除"的数组里写，
#   **探索进度看起来在涨，但下次换层回来全没了**（静默 bug，极难归因）。
# ⚠ 调用方在 reset 之后必须照 `Main._build_floor` 的既有模式收尾：
#   `_fog_last_tile = Vector2i(-999999, -999999)` + `_refresh_fog(true)`，
#   否则 LOS 不按新状态重算。
func reset_floor(floor_index: int) -> void:
	_cache.erase(floor_index)
	if floor_index == _floor_index:
		var arr: Array = []
		arr.resize(_cols * _rows)
		arr.fill(GameConstants.FOG_UNEXPLORED)
		_cache[floor_index] = arr
		_tiles = arr

# 整局归档（死亡重开 / 换存档时用；生产路径不需要——`_on_restart` 靠场景重载自然达成）
func clear_cache() -> void:
	_cache.clear()
	if _floor_index != -999999:
		var arr: Array = []
		arr.resize(_cols * _rows)
		arr.fill(GameConstants.FOG_UNEXPLORED)
		_cache[_floor_index] = arr
		_tiles = arr

# 以玩家位置为源重算可见性（半径 + LOS）；离开视线 → 已探索；已探索永不回退
func update_visibility(player_pos: Vector2) -> void:
	if _cols <= 0 or _rows <= 0:
		return
	var pt: Vector2i = world_to_tile(player_pos)
	if pt.x < 0 or pt.x >= _cols or pt.y < 0 or pt.y >= _rows:
		return
	# 1) 上一帧的「可见」降级为「已探索」（0/1 不受影响 → 已探索永不回退为未探索）
	var i: int = 0
	while i < _tiles.size():
		if int(_tiles[i]) == GameConstants.FOG_VISIBLE:
			_tiles[i] = GameConstants.FOG_EXPLORED
		i += 1
	# 2) 本次 LOS 内的格升为「可见」
	for off in _offsets:
		var t: Vector2i = pt + off
		if t.x < 0 or t.x >= _cols or t.y < 0 or t.y >= _rows:
			continue
		if _line_clear(pt, t):
			_tiles[t.y * _cols + t.x] = GameConstants.FOG_VISIBLE

# === 查询 ===
func cols() -> int:
	return _cols

func rows() -> int:
	return _rows

func floor_index() -> int:
	return _floor_index

func tiles() -> Array:
	return _tiles

func vision_radius() -> int:
	return GameConstants.FOG_VISION_RADIUS_TILES

func state_at_tile(t: Vector2i) -> int:
	if t.x < 0 or t.x >= _cols or t.y < 0 or t.y >= _rows:
		return GameConstants.FOG_UNEXPLORED
	return int(_tiles[t.y * _cols + t.x])

func state_at_world(pos: Vector2) -> int:
	return state_at_tile(world_to_tile(pos))

func is_visible_tile(t: Vector2i) -> bool:
	return state_at_tile(t) == GameConstants.FOG_VISIBLE

func is_visible_world(pos: Vector2) -> bool:
	return state_at_world(pos) == GameConstants.FOG_VISIBLE

func is_explored_tile(t: Vector2i) -> bool:
	return state_at_tile(t) >= GameConstants.FOG_EXPLORED

func world_to_tile(p: Vector2) -> Vector2i:
	var tile: int = int(GameConstants.TILE)
	return Vector2i(int(p.x) / tile, int(p.y) / tile)

func tile_center(t: Vector2i) -> Vector2:
	var tile: float = GameConstants.TILE
	return Vector2((t.x + 0.5) * tile, (t.y + 0.5) * tile)

# 该格是否被墙挡（LOS 不通 → 必须不可见）。测试探针 + 语义自解释。
func los_blocked(player_pos: Vector2, t: Vector2i) -> bool:
	if t.x < 0 or t.x >= _cols or t.y < 0 or t.y >= _rows:
		return true
	return not _line_clear(world_to_tile(player_pos), t)

# === LOS：Bresenham 逐格；起点与终点之间的「中间格」若有墙 → 遮挡 ===
# 终点本身即使是墙也可见（看得见墙面）；起点（玩家格）恒可见。
func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var x: int = a.x
	var y: int = a.y
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var guard: int = 0
	var limit: int = _cols + _rows + 4
	while guard <= limit:
		guard += 1
		var is_start: bool = (x == a.x and y == a.y)
		var is_target: bool = (x == b.x and y == b.y)
		if not is_start and not is_target:
			if _terrain[y * _cols + x] == 0:
				return false          # 中间有墙 → 遮挡
		if is_target:
			return true
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true
