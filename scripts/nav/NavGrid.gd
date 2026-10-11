# NavGrid · 敌人寻路导航网格（R-61 新增 / R-63 改为 preload + static，去掉 autoload 依赖）
# 寻路用「流场（flow field）」：以目标（玩家）所在的**地面格**为源，在整层网格上做一次 BFS
# 距离场 `_dist`；任何敌人只要读自己所在格的 dist 并朝「dist 更小的邻格」走，就能绕过墙壁/门。
#   - 一次 BFS 服务全部敌人（远低于逐敌人 A*）
#   - 目标格不变时跳过重算（玩家每换一格才重算一次）
#   - `MAX_DIST_TILES` 限制传播距离 = **寻路最大距离**（超出视为"无路"）
# 用法（调用方）：const NavGrid := preload("res://scripts/nav/NavGrid.gd") → NavGrid.xxx()
# ⚠ 用 preload + static（而非 autoload）：preload 在**解析期**即可解析，不依赖 project.godot 的
#   autoload 注册 → 避免"编辑器未刷新项目设置 → Identifier not declared"这类脆弱问题。
# 由 Main 在 `_build_floor` 时 `set_grid(...)`、每帧 `update_field(player.global_position)`。
extends RefCounted

const TILE := 16
const MAX_DIST_TILES := 200    # 寻路最大距离（tile，200×16 = 3200px）——本层 128×86，200 已覆盖全层

static var _grid := PackedByteArray()  # 1=地面 0=实心
static var _cols := 0
static var _rows := 0
static var _dist := PackedInt32Array() # 到目标格的 BFS 距离（-1 = 不可达/未算）
static var _goal_tile := Vector2i(-1, -1)
static var _max_dist := 0              # 距离场里出现过的最大距离（诊断用）

static func set_grid(grid: PackedByteArray, cols: int, rows: int) -> void:
	_grid = grid
	_cols = cols
	_rows = rows
	_dist.resize(cols * rows)
	_dist.fill(-1)
	_goal_tile = Vector2i(-1, -1)
	_max_dist = 0

static func cols() -> int:
	return _cols

static func rows() -> int:
	return _rows

static func grid_ref() -> PackedByteArray:
	return _grid

static func max_dist() -> int:
	return _max_dist

static func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x) / TILE, int(p.y) / TILE)

static func tile_center(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)

static func is_floor(t: Vector2i) -> bool:
	if t.x < 0 or t.x >= _cols or t.y < 0 or t.y >= _rows:
		return false
	return _grid[t.y * _cols + t.x] == 1

static func dist_at(world: Vector2) -> int:
	return dist_at_tile(world_to_tile(world))

static func dist_at_tile(t: Vector2i) -> int:
	if t.x < 0 or t.x >= _cols or t.y < 0 or t.y >= _rows:
		return -1
	return _dist[t.y * _cols + t.x]

# 以目标（世界坐标）为源重算距离场；目标未换格则跳过
static func update_field(goal_world: Vector2) -> void:
	var g := world_to_tile(goal_world)
	if g == _goal_tile:
		return
	if _grid.size() == 0:
		return
	_goal_tile = g
	_dist.fill(-1)
	_max_dist = 0
	if not is_floor(g):
		return
	var start := g.y * _cols + g.x
	_dist[start] = 0
	var q := PackedInt32Array()
	q.append(start)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var d: int = _dist[cur]
		if d >= MAX_DIST_TILES:
			continue
		var cx := cur % _cols
		var cy := cur / _cols
		var nd := d + 1
		if cx > 0: _push(cur - 1, nd, q)
		if cx < _cols - 1: _push(cur + 1, nd, q)
		if cy > 0: _push(cur - _cols, nd, q)
		if cy < _rows - 1: _push(cur + _cols, nd, q)
		if nd > _max_dist:
			_max_dist = nd

static func _push(i: int, nd: int, q: PackedInt32Array) -> void:
	if _grid[i] == 1 and _dist[i] == -1:
		_dist[i] = nd
		q.append(i)

# 返回「从 t 朝目标下坡」的邻格（无更优邻格则返回自身）
static func lower_tile(t: Vector2i) -> Vector2i:
	var d := dist_at_tile(t)
	if d <= 0:
		return t
	var best := d
	var best_t := t
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = t.x + int(dx)
			var ny: int = t.y + int(dy)
			if nx < 0 or nx >= _cols or ny < 0 or ny >= _rows:
				continue
			# 对角步：两颗正交邻格必须都是地面（防切墙角）
			if dx != 0 and dy != 0:
				if _grid[t.y * _cols + nx] == 0 or _grid[ny * _cols + t.x] == 0:
					continue
			var ni: int = ny * _cols + nx
			if _grid[ni] == 0:
				continue
			var v: int = _dist[ni]
			if v >= 0 and v < best:
				best = v
				best_t = Vector2i(nx, ny)
	return best_t

# 敌人调用：返回朝目标绕开障碍的单位方向；无路返回 ZERO
static func flow_dir(from_world: Vector2) -> Vector2:
	var t := world_to_tile(from_world)
	var nxt := lower_tile(t)
	if nxt == t:
		return Vector2.ZERO
	return (tile_center(nxt) - from_world).normalized()
