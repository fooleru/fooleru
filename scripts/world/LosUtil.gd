# LosUtil · 共用视线(LOS)工具（R-73 新增）
# 视觉感知的判定核心：从「施测者身体中心」向目标位置投射一条物理射线，命中「墙(层 1)」即被遮挡。
#   - 为什么用**物理射线**而非格子 Bresenham：与既有的 `Mercenary._has_los()` 同源（已验证），
#     且**天然忽略半高家具(层 16 箱子)**——只查层 1（墙），与迷雾口径（半高家具不阻视线）一致。
#   - ⚠ 起点用**身体中心**而非枪口：枪口(8px 前)可能戳进墙里，起点在墙内时 `hit_from_inside`
#     默认 false 会漏判；`hit_from_inside = true` 兜底。
#   - 迷雾的**玩家视野**（FogGrid.Bresenham LOS）与此**相互独立**，本工具不参与、不改变 `--verify-fog`。
# 用法：const LosUtil := preload("res://scripts/world/LosUtil.gd") → LosUtil.has_los(node, to_world)
extends RefCounted

# 返回 true = 视线通畅（无墙遮挡）；false = 被墙挡住（或施测者无效）。
# `from_node` 必须是**在场景树内**的 Node2D（需要 get_world_2d()）。
static func has_los(from_node: Node2D, to_world: Vector2) -> bool:
	if from_node == null or not is_instance_valid(from_node):
		return false
	var world := from_node.get_world_2d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters2D.create(from_node.global_position, to_world)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 1  # 只看墙
	q.hit_from_inside = true
	q.exclude = [from_node.get_rid()]
	return space.intersect_ray(q).is_empty()

# R-75：世界坐标版（掩体采样用 —— 候选点还没有实体节点，不能走 has_los(node, …)）。
# `ref_node` 只用来取 world_2d（必须是场景树内的节点）；射线本身完全用世界坐标。
static func has_los_world(ref_node: Node2D, from_world: Vector2, to_world: Vector2) -> bool:
	if ref_node == null or not is_instance_valid(ref_node):
		return false
	var world := ref_node.get_world_2d()
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters2D.create(from_world, to_world)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 1  # 只看墙
	q.hit_from_inside = true
	return space.intersect_ray(q).is_empty()
