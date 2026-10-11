# Bullet · Area2D · cp1 阶段 3 / cp2 敌我双向 / R-62 阵营分层
# 直线飞行子弹（L2 资源层 · 占位色块）
# 碰撞层：1=墙 ｜ 2=玩家 ｜ 4=亡灵(僵尸) ｜ 8=雇佣兵
#   友方(hostile=false)：mask=13(墙|亡灵|佣兵) → 打**两个阵营的敌人**（玩家子弹无友伤问题）
#   敌方(hostile=true) ：mask=7 (墙|玩家|亡灵) → 打**玩家 + 敌对阵营(亡灵)**，但**不打同阵营佣兵**
# 命中墙/出界 → 自毁。射线与 Area2D 重叠统一走 _resolve_hit，只结算一次。
# ⚠ 高速防穿透：每帧额外做"上一帧位置→当前位置"的扫掠射线检测（防 tunneling）。
extends Area2D
class_name Bullet

var speed := GameConstants.BULLET_SPEED
var damage := GameConstants.PISTOL_DAMAGE
var hostile: bool = false        # true = 敌方发射（打玩家/敌对阵营）；false = 玩家发射（打敌人）
var _shooter: Node = null        # 发射者（射线排除，防自伤）

var _vel: Vector2 = Vector2.RIGHT
var _travel: float = 0.0
var _resolved: bool = false      # 保证只结算一次
var _tail_from: Vector2 = Vector2.ZERO
var _use_tail: bool = false

func _ready() -> void:
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)
	# 阵营分层（R-62）：敌弹 mask=7(墙|玩家|亡灵) → 打玩家与敌对阵营，天然不打同阵营佣兵；
	#              友弹 mask=13(墙|亡灵|佣兵) → 打两个阵营的敌人
	collision_mask = 7 if hostile else 13
	if hostile:
		var sp := get_node_or_null("Sprite")
		if sp != null:
			sp.color = Color(1.0, 0.42, 0.22, 1.0)  # 红橙 = 敌方弹（与玩家黄弹区分）

# 发射者（射线排除自身，防子弹生成在自己体内即自毁）
func set_shooter(n: Node) -> void:
	_shooter = n

# 设置首帧扫掠起点（玩家中心）：贴脸敌人位于"中心~枪口"之间时也能打到
func set_tail_start(p: Vector2) -> void:
	_tail_from = p
	_use_tail = true

func set_direction(d: Vector2) -> void:
	_vel = d.normalized()
	rotation = _vel.angle()

# 目标判定（R-62）：
#   玩家 → 只有敌弹能打；敌人 → 友弹都打；敌弹打"敌对阵营"（同阵营佣兵已被碰撞掩码 7 排除层8 → 天然无友伤）
func _is_target(body: Node) -> bool:
	if body == null:
		return false
	if body.is_in_group("player"):
		return hostile
	return body.is_in_group("enemies")

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	# 0) 生成即重叠：命中目标
	for b in get_overlapping_bodies():
		if _is_target(b):
			_resolve_hit(b)
			return
	var step := _vel * speed * delta
	# 1) 扫掠射线：捕捉这一帧路径上跨过的小目标（首帧从出生点后方起算）
	var from_pos := position
	if _use_tail:
		from_pos = _tail_from
		_use_tail = false
	if _sweep(from_pos, position + step):
		return
	# 2) 推进
	position += step
	_travel += step.length()
	if _travel >= GameConstants.BULLET_MAX_RANGE:
		queue_free()

# 扫掠射线：从 from_pos 打到 to_pos，只检测本子弹关心的层（墙 + 目标阵营）
func _sweep(from_pos: Vector2, to_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null or (to_pos - from_pos).length_squared() <= 0.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = collision_mask
	query.hit_from_inside = true  # ★ 起点在墙内也算命中（防"子弹生成在墙体里 → 直接穿墙飞出"）
	var exclude: Array = []
	if _shooter != null and is_instance_valid(_shooter):
		exclude.append(_shooter.get_rid())
	if not hostile:
		for p in get_tree().get_nodes_in_group("player"):
			exclude.append(p.get_rid())  # 不打到玩家自己（贴脸瞄准时防自毁）
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	_resolve_hit(hit.get("collider", null) as Node)
	return true

# 统一结算入口（射线命中 / Area2D 重叠都走这里，只生效一次）
func _resolve_hit(body: Node) -> void:
	if _resolved:
		return
	_resolved = true
	if _is_target(body) and body.has_method("take_damage"):
		# ==== R-114 命中反馈 ====
		# ⚠ 打在**活体**上时声音由受害者自己发（Player.take_damage → player_hurt、
		#   Zombie/Mercenary.take_damage → hit_flesh），**这里不再重复发** ——
		#   否则霰弹枪 6 弹丸命中会响 6 次"啪"（限流只能压到 1 次，但那是掩盖不是设计）。
		# R-83：试玩记录。命中判定与伤害结算**完全不变**，只在旁边挂一条只读埋点。
		#   · 友弹打中敌人 → 一次"命中"（弹丸级；霰弹枪一发 6 弹丸最多可记 6 次）
		#   · 敌弹打中玩家 → 伤害来源标 "merc"（**当前工程唯一发射敌弹的是雇佣兵**，
		#     见 Mercenary._spawn_bullet；僵尸是近战、不经子弹）。
		#     "实际扣掉多少血"由 Player.take_damage 内部上报（那里才知道护甲减伤后的值），
		#     所以这里**不重复上报伤害**，只负责传来源标签。
		#   设施默认关闭 → 下面两个调用都是空操作。
		if body.is_in_group("player"):
			# take_damage 的第 2 参只用于记录归因，不参与任何伤害计算。
			body.take_damage(damage, "merc" if hostile else "")
		else:
			body.take_damage(damage)
			if not hostile:
				PlaytestLog.note_hit()
	else:
		# ==== R-114 命中硬物 ====
		# ⚠ 打在**墙 / 非活体**上（`else` 分支：`_is_target` 为假，或目标没有 take_damage）。
		#   这一支**没有任何实体**去发声音，所以必须由子弹自己发 —— 否则打墙是完全哑的。
		# ⚠ 不区分敌我弹：玩家打墙和敌人打墙都是"硬质撞击"。
		# ⚠ 纯附加：碰撞、层掩码、伤害结算、`_resolved` 一次性守卫全部不变。
		Sfx.play("hit_wall")
	queue_free()

func _on_body_entered(body: Node) -> void:
	_resolve_hit(body)
