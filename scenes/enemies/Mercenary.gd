# Mercenary（雇佣兵）· CharacterBody2D · cp2 多敌人切片（R-62 阵营/目标 + R-73 双轴感知 + Alert/Search/脱战）
# 远程对射：保持 PREFERRED_DIST 距离；有视线(LOS)才开火；太远推进 / 太近后撤 / 死区开火
# FSM：IDLE ─(感知命中)→ ALERT(0.4s) → COMBAT(≡Chase，走位/开火) → WINDUP → COMBAT
#      COMBAT ─(两轴失联 > LoseTargetTime)→ SEARCH → IDLE
# 感知（enemies-ai §4.1 · R-19 双轴）：**视觉主导** —— 视觉 260（要求 LOS）/ 听觉 60（不要求 LOS）
# 阵营：雇佣兵 = 「雇佣兵」阵营；敌对目标 = 玩家 + 敌对阵营（僵尸）；同阵营不互打
# 数值：依据 enemies-ai §3 / §4.1（cp2 占位，⚠ 待实测校准）
extends CharacterBody2D
class_name Mercenary

const BulletScene := preload("res://scenes/player/Bullet.tscn")
const NavGrid := preload("res://scripts/nav/NavGrid.gd")
const LosUtil := preload("res://scripts/world/LosUtil.gd")

# ==== R-148 · 敌人精灵接入（照 `Crate.gd:86-127` 的既有模式，不自创）====
#   tscn 里那个 Polygon2D（名 `Sprite`）**保留不动**当兜底；运行时 `Sprite2D.new()`
#   起名 `EnemyArt` 挂上去，纹理到位 → 精灵可见 + 色块隐藏；纹理缺失 → 降级回色块。
#   ⚠「精灵与色块同时可见」是**禁止**的（会造成双重外观）。
#   ⚠ `Mercenary.tscn` **零改动**（10×10 碰撞盒 / collision_layer 8 / 节点名 原封不动）。
const ENEMY_ART_NODE := "EnemyArt"
const ENEMY_SPRITE_DIR := "res://assets/sprites/enemies/"

signal died

enum State { IDLE, ALERT, COMBAT, SEARCH, WINDUP, DEAD }

@export var move_speed: float = GameConstants.MERC_SPEED
@export var max_hp: float = GameConstants.MERC_HP
@export var damage: float = GameConstants.MERC_DAMAGE
@export var visual_range: float = GameConstants.MERC_VISUAL_RANGE
@export var audio_range: float = GameConstants.MERC_AUDIO_RANGE
@export var preferred_dist: float = GameConstants.MERC_PREFERRED_DIST
@export var range_tol: float = GameConstants.MERC_RANGE_TOLERANCE
@export var fire_cooldown: float = GameConstants.MERC_FIRE_COOLDOWN
@export var windup_time: float = GameConstants.MERC_WINDUP

var faction: int = GameConstants.FACTION_MERC
var hp: float = max_hp
var state: int = State.IDLE
var target: Node2D = null       # 当前敌对目标（玩家 或 敌对阵营）
var fire_cd: float = 0.0
var windup_t: float = 0.0
var dead: bool = false
var _flash: float = 0.0
# ==== R-87 受击硬直（hit stagger · 局部顿帧）====
# 语义：受击时置位 ENEMY_STAGGER_TIME，期间这只雇佣兵**冻结**（不推进、不开火）。
# ⚠ 绝不使用 Engine.time_scale（见 GameConstants 注释）—— 全局顿帧会连带冻住玩家与子弹。
var _stagger: float = 0.0
var _sense_t: float = 0.0       # 目标重选节流
# QA N1 修复：空闲（无目标）时不得绕过节流每帧重扫 → 只有"上一帧持有、本帧失效"才强制立即重扫
var scan_calls: int = 0         # 重扫次数计数（验证探针）
# R-73 感知 / 脱战探针（供 headless 验证读取）
var sensed: bool = false
var last_known: Vector2 = Vector2.ZERO
var _last_sense_los: bool = false
var _alert_t: float = 0.0
var _lose_t: float = 0.0
var _lose_dur: float = GameConstants.ENEMY_LOSE_TARGET_TIME
var _search_phase: int = 0
var _search_t: float = 0.0
# === R-75 佣兵战术：点射 / 换位 / 掩体 ===
var _burst_left: int = 0          # 本组点射剩余发数（0 = 需要先开新组）
var _burst_pause_t: float = 0.0   # 组间停火剩余时长（>0 → 正在换位）
var _strafe_side: int = 1         # 侧移方向（每组点射后翻转）
var _cover_target: Vector2 = Vector2.ZERO   # 当前选定的掩体点（ZERO = 无掩体→侧移）
var shots_fired: int = 0          # 验证探针：累计开火次数（用于断言点射节奏）

@onready var sprite: Polygon2D = $Sprite
@onready var muzzle: Marker2D = $Muzzle

func _ready() -> void:
	add_to_group("enemies")
	_scan()
	_refresh_art()      # R-148：精灵接入（色块 -> 程序化精灵）

func _physics_process(delta: float) -> void:
	if dead or state == State.DEAD:
		return
	# 受击高亮衰减（占位反馈）
	# R-148：改走 `_apply_flash()` —— 接入后**可见的是 EnemyArt**，只调色块会"打不亮"。
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta)
		_apply_flash(true)
	else:
		_apply_flash(false)

	# 双轴感知重扫：节流到期 或 **目标刚刚失效** → 重判（空闲期不得每帧重扫，见 QA N1）
	_sense_t -= delta
	var target_gone := target == null or not is_instance_valid(target) or target.is_queued_for_deletion()
	# ⚠⚠ R-new 修复（与 Zombie.gd 同款死引用窗口，见那边注释）：条件改为
	#   `(target != null and target_gone)` —— 持有失效目标即重扫；target==null 不触发
	#   （保"空闲期不每帧全组遍历"的 QA N1 性能约束）。本类各访问点已有守卫，属隐患同步排除。
	if _sense_t <= 0.0 or (target != null and target_gone):
		_scan()

	fire_cd = max(0.0, fire_cd - delta)

	# ==== R-87 受击硬直：局部顿帧 ====
	# 硬直期间这只雇佣兵**冻结**：不推进、不转向、不开火。
	# ⚠ placement 选在 fire_cd 之后、朝向与状态机之前：
	#   · fire_cd / _sense_t 照常递减（放在闸门之前）—— 冷却与感知**不被硬直拖慢**，
	#     否则多次硬直会累积成"雇佣兵永远开不了枪"，那是隐式削弱，不是打击感。
	#   · 朝向 + match 状态机全部跳过 = 推进 / 后撤 / 侧移 / WINDUP 计时全部冻结。
	#     WINDUP 被冻结 → 硬直期间绝不会发射子弹（--verify-stagger ⑥ 断言 shots_fired 不变）。
	# ⚠ 冻结 windup 而非重置：重置会让 SMG 连射击穿雇佣兵的 0.35s 前摇 → 永久哑火（= 变成不会打的靶子）。
	#     冻结只延迟不取消，0.12s < MERC_WINDUP(0.35s) → 开火一定会发生。
	# ⚠ velocity 必须显式归零：COMBAT 里死区开火时 velocity 本就是 ZERO，
	#   但"太远推进/太近后撤/换位侧移"三种分支都在动，不归零就会滑行。
	if _stagger > 0.0:
		_stagger = max(0.0, _stagger - delta)
		velocity = Vector2.ZERO
		return

	# 朝向：ALERT/COMBAT/SEARCH 面朝注意方向（WINDUP 已在 COMBAT 里锁过向）
	# R-148：旋转写入收进 `_face()`（与 Zombie 同名同义），顺带同步 flip_v。
	if state != State.IDLE and state != State.DEAD:
		var aim_pos: Vector2 = target.global_position if (target != null and is_instance_valid(target)) else last_known
		_face(aim_pos)

	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			if sensed:
				_enter_alert()
		State.ALERT:
			velocity = Vector2.ZERO
			if sensed:
				_lose_t = 0.0
				_alert_t -= delta
				if _alert_t <= 0.0:
					state = State.COMBAT
			else:
				_lose_t += delta                    # 失联：计满 LoseTargetTime 才转 Search（GDD §4.1）
				if _lose_t >= _lose_dur:
					_enter_search()
		State.COMBAT:
			if not sensed:
				_lose_t += delta
				velocity = Vector2.ZERO
				if _lose_t >= _lose_dur:
					_enter_search()
			else:
				_lose_t = 0.0
				_combat_step(delta)
		State.SEARCH:
			_search_step(delta)
		State.WINDUP:
			velocity = Vector2.ZERO
			windup_t -= delta
			if windup_t <= 0.0:
				_spawn_bullet()
				shots_fired += 1                 # 验证探针
				# R-75：一组点射内用短间隔；打完一组 → 进入"停火换位"窗口
				_burst_left -= 1
				if _burst_left > 0:
					fire_cd = GameConstants.MERC_BURST_GAP
				else:
					fire_cd = fire_cooldown
					_burst_pause_t = GameConstants.MERC_BURST_PAUSE
				state = State.COMBAT

	move_and_slide()
	# R-148：每帧调一次（照 `Player._update_weapon()` 末尾调 `_sync_weapon_facing()`），
	#   覆盖**所有** rotation 赋值分支 —— 不依赖调用方记得同步。
	_sync_art_facing()

# R-148：朝向（与 `Zombie._face()` 同名同义：局部 +x = 前方）。
#   ⚠ 抽出来是为了让「写 rotation」与「同步 flip_v」只有**一处**入口，
#     避免以后有人在别处直接写 `rotation = ...` 而忘了镜像（= 朝左的敌人上下颠倒）。
func _face(pos: Vector2) -> void:
	var v := pos - global_position
	if v.length_squared() > 0.0001:
		rotation = v.angle()
	_sync_art_facing()

# ==== R-148 · 敌人精灵接入（照 `Crate.gd` 既有模式）====

# 本敌人的精灵纹理路径（**纯函数**，便于 `--verify-enemy-sprite` 逐字断言）。
func enemy_sprite_path() -> String:
	return ENEMY_SPRITE_DIR + "merc.png"

# 刷新外观（三态互斥，与 `Crate._refresh_art()` 同款）：
#   ① 纹理到位 → Sprite2D(EnemyArt) 可见 + tscn 的 Polygon2D `Sprite` **隐藏**；
#   ② 纹理缺失（未 import / 路径写错）→ **可见地降级**回色块，而不是画一片空白。
#   ⚠ 「精灵与色块同时可见」是**禁止**的（双重外观）。
func _refresh_art() -> void:
	var fallback := get_node_or_null("Sprite") as Polygon2D
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	var tex := load(enemy_sprite_path()) as Texture2D
	if tex == null:
		if art != null:
			art.visible = false
		if fallback != null:
			fallback.visible = true
		return
	if art == null:
		art = Sprite2D.new()
		art.name = ENEMY_ART_NODE
		# asset-spec §0：origin = 体心（centered + offset 0）—— 绕体心旋转，不绕左上角。
		art.centered = true
		art.offset = Vector2(0, 0)
		add_child(art)
	art.texture = tex
	art.visible = true
	if fallback != null:
		fallback.visible = false

# 受击高亮打到**真正可见的那个**（接入后是 `EnemyArt`，不是已隐藏的色块）。
#   两处都设是为了**降级态**（纹理缺失时可见的是色块）也不丢反馈。
func _apply_flash(on: bool) -> void:
	var c := Color(1.6, 1.6, 1.6) if on else Color(1, 1, 1)
	if sprite != null and is_instance_valid(sprite):
		sprite.modulate = c
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	if art != null:
		art.modulate = c

# 朝左时同步 `flip_v`（asset-spec §0 铁律，照 `Player._sync_weapon_facing()`）。
#   rotate180( flip_v(img) ) == flip_h(img) = 「头朝左、身子正立」的正确镜像。
#   ⚠ 恰 ±90° 是镜像不连续点（rotation float32 vs PI float64，R-143 踩过）
#     ⇒ 验证只在 0° / 180° / 135° / 45° 断言。
func _sync_art_facing() -> void:
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	if art == null:
		return
	art.flip_v = absf(rotation) > PI * 0.5

# 交战走位（R-75）：无视线 → 推进找角度；太远 → 推进；太近 → **避墙后撤**；死区 → **点射 + 停火换位**
func _combat_step(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var to_p := target.global_position - global_position
	var dist := to_p.length()
	if not _has_los():
		_reset_burst()
		velocity = _advance_dir(to_p) * move_speed
	elif dist > preferred_dist + range_tol:
		_reset_burst()
		velocity = _advance_dir(to_p) * move_speed
	elif dist < preferred_dist - range_tol:
		_reset_burst()
		velocity = _retreat_dir(to_p) * move_speed
	else:
		# 死区（理想距离带内）：
		#   ① 停火窗口 → 换到掩体点（没有掩体就侧移，打破玩家预瞄）
		#   ② 否则按「3–5 发一组」点射，组内用短间隔
		if _burst_pause_t > 0.0:
			_burst_pause_t -= delta
			_reposition_step(to_p)
			return
		if _burst_left <= 0:
			_burst_left = randi_range(GameConstants.MERC_BURST_MIN, GameConstants.MERC_BURST_MAX)
			_strafe_side = -_strafe_side                 # 每组换一次侧移方向
			_cover_target = _find_cover()
		velocity = Vector2.ZERO
		if fire_cd <= 0.0:
			state = State.WINDUP
			windup_t = windup_time

func _reset_burst() -> void:
	_burst_left = 0
	_burst_pause_t = 0.0
	_cover_target = Vector2.ZERO

# 后撤：直退方向若撞墙，依次试 ±45° / ±90° —— 避免"贴着墙原地磨"
func _retreat_dir(to_p: Vector2) -> Vector2:
	var away := -to_p.normalized()
	for ang in [0.0, deg_to_rad(45.0), deg_to_rad(-45.0), deg_to_rad(90.0), deg_to_rad(-90.0)]:
		# ⚠ `for x in [...]` 的元素是 Variant → 必须显式标类型，否则报 "Cannot infer the type"
		var d: Vector2 = away.rotated(float(ang))
		if NavGrid.is_floor(NavGrid.world_to_tile(global_position + d * 24.0)):
			return d
	return away

# 找掩体：自身周围采样一圈，挑「**看不到玩家**（躲在墙后）+ 离玩家距离最接近理想值」的地面点
func _find_cover() -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var pp := target.global_position
	var best := Vector2.ZERO
	var best_score := -INF
	for i in 16:
		var ang := TAU * float(i) / 16.0
		for rad in [GameConstants.MERC_COVER_RADIUS * 0.6, GameConstants.MERC_COVER_RADIUS]:
			# ⚠ 同上：数组迭代元素是 Variant，必须显式标类型
			var p: Vector2 = global_position + Vector2.from_angle(ang) * float(rad)
			if not NavGrid.is_floor(NavGrid.world_to_tile(p)):
				continue
			var d: float = p.distance_to(pp)
			if d < GameConstants.MERC_COVER_MIN_DIST:
				continue
			if LosUtil.has_los_world(self, p, pp):
				continue          # 站这里还能看见玩家 → 不是掩体
			var score: float = -abs(d - preferred_dist)
			if score > best_score:
				best_score = score
				best = p
	return best

# 停火窗口的走位：优先去掩体点；没有掩体就侧移
func _reposition_step(to_p: Vector2) -> void:
	if _cover_target != Vector2.ZERO:
		var d := _cover_target - global_position
		if d.length() <= 6.0:
			velocity = Vector2.ZERO
		else:
			velocity = d.normalized() * move_speed * GameConstants.MERC_REPOSITION_MULT
		return
	var side := Vector2(-to_p.y, to_p.x).normalized() * float(_strafe_side)
	velocity = side * move_speed * GameConstants.MERC_STRAFE_MULT

func _enter_alert() -> void:
	state = State.ALERT
	_alert_t = GameConstants.ENEMY_ALERT_TIME
	_lose_t = 0.0
	_reset_burst()      # R-75：重新进入交战 → 点射/掩体状态归零
	if target != null and is_instance_valid(target):
		last_known = target.global_position

func _enter_search() -> void:
	state = State.SEARCH
	_search_phase = 0
	_search_t = 0.0
	_lose_t = 0.0

func _search_step(delta: float) -> void:
	if sensed:
		_enter_alert()
		return
	if _search_phase == 0:
		var to := last_known - global_position
		if to.length() <= GameConstants.ENEMY_SEARCH_ARRIVE_DIST:
			_search_phase = 1
			_search_t = 0.0
			velocity = Vector2.ZERO
		else:
			velocity = to.normalized() * move_speed
			_search_t += delta
			if _search_t >= GameConstants.ENEMY_SEARCH_MOVE_TIMEOUT:
				_search_phase = 1
				_search_t = 0.0
				velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
		_search_t += delta
		if _search_t >= GameConstants.ENEMY_SEARCH_SCAN_TIME:
			state = State.IDLE
			target = null

# 视线判定（R-73 改为共用工具 LosUtil；保留此方法名以兼容 --verify-wallblock 的调用）
func _has_los() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return LosUtil.has_los(self, target.global_position)

# 推进方向：目标是玩家时走「流场」（NavGrid，绕墙）；敌对阵营目标用直线
func _advance_dir(to_p: Vector2) -> Vector2:
	if target != null and target.is_in_group("player"):
		var dir := NavGrid.flow_dir(global_position)
		if dir != Vector2.ZERO:
			return dir
	return to_p.normalized()

func _spawn_bullet() -> void:
	if target == null or not is_instance_valid(target):
		return
	var b := BulletScene.instantiate()
	b.hostile = true           # 敌方子弹 → mask 命中 玩家/敌对阵营（见 Bullet.gd）
	b.damage = damage
	b.speed = GameConstants.MERC_BULLET_SPEED
	b.global_position = muzzle.global_position
	b.set_direction((target.global_position - muzzle.global_position).normalized())
	b.set_shooter(self)
	get_tree().current_scene.add_child(b)

# 供 headless 验证直接调用：指定目标并立刻发射一发（跳过冷却/前摇）
func force_fire_at(target_node: Node2D) -> void:
	target = target_node
	_spawn_bullet()

# 双轴感知重扫：视觉(要求 LOS) / 听觉(不要求 LOS)；任一轴命中即候选，取最近
func _scan() -> void:
	scan_calls += 1                                 # 验证探针：统计真实重扫次数
	_sense_t = GameConstants.ENEMY_SENSE_INTERVAL   # 本次重扫后，下次重扫在节流窗口后
	sensed = false
	var best: Node2D = null
	var best_d: float = INF
	var best_los: bool = false
	var max_r: float = maxf(visual_range, audio_range)

	var cands: Array = []
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null:
		cands.append(p)
	for en in get_tree().get_nodes_in_group("enemies"):
		if en == self or not is_instance_valid(en):
			continue
		var f: Variant = en.get("faction")
		if f != null and int(f) == faction:
			continue  # 同阵营 → 不敌对
		var e2 := en as Node2D
		if e2 != null:
			cands.append(e2)

	for c in cands:
		var cn := c as Node2D
		if cn == null or cn.is_queued_for_deletion():
			continue
		var d: float = global_position.distance_to(cn.global_position)
		if d > max_r:
			continue
		var los: bool = LosUtil.has_los(self, cn.global_position)
		var vis: bool = los and d <= visual_range
		var hear: bool = d <= audio_range * _hear_factor(cn)
		if not (vis or hear):
			continue
		if d < best_d:
			best = cn
			best_d = d
			best_los = los

	sensed = best != null
	target = best
	if sensed:
		last_known = best.global_position
		_last_sense_los = best_los
		_lose_dur = GameConstants.ENEMY_LOSE_TARGET_TIME if best_los \
			else GameConstants.ENEMY_LOSE_TARGET_TIME * GameConstants.ENEMY_LOSE_TARGET_AUDIO_FACTOR

# 听觉噪声修正（⚠ 原型简化）：玩家 跑动/开枪/装弹 → 1.0；静止/慢走 → 0.5
func _hear_factor(c: Node2D) -> float:
	if c.is_in_group("player"):
		var loud := false
		var vel: Variant = c.get("velocity")
		if vel != null and (vel as Vector2).length() > GameConstants.MOVE_SPEED * GameConstants.PLAYER_RUN_SPEED_EPS:
			loud = true
		var fcd: Variant = c.get("fire_cd")
		if fcd != null and float(fcd) > 0.0:
			loud = true
		var rl: Variant = c.get("is_reloading")
		if rl != null and bool(rl):
			loud = true
		return GameConstants.HEAR_FACTOR_LOUD if loud else GameConstants.HEAR_FACTOR_QUIET
	return GameConstants.HEAR_FACTOR_LOUD

# === headless 验证探针（与 _scan 同口径；供 --verify-perception 断言逐轴结果） ===
# 视觉轴：范围内 且 LOS 通
func axis_visual(c: Node2D) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	var d: float = global_position.distance_to(c.global_position)
	return d <= visual_range and LosUtil.has_los(self, c.global_position)

# 听觉轴：范围内 × 噪声修正（不看 LOS）
func axis_hear(c: Node2D) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	var d: float = global_position.distance_to(c.global_position)
	return d <= audio_range * _hear_factor(c)

func take_damage(amount: float) -> void:
	if dead or state == State.DEAD:
		return
	_flash = 0.12
	hp = max(0.0, hp - amount)
	# ==== R-114 命中血肉 + 死亡短促 ====
	# ⚠ 与僵尸同款位置：扣血之后、死亡判定之前 —— 致死那一发先"啪"再短促death。
	#   音效不参与任何判定（hp / dead / 状态机一个字节都没改）。
	Sfx.play("hit_flesh")
	if hp <= 0.0:
		_die()
		return
	# ==== R-87 受击硬直 ====
	# ⚠ 签名保持单参 `take_damage(amount)`：Bullet._resolve_hit() 对玩家走双参、对敌人走单参，
	#   给敌人改签名会破坏这条既有约定（R-83）。
	# ⚠ 与僵尸一致：硬直在扣血 + 死亡判定**之后**置位 → 伤害结算顺序完全不变，
	#   硬直不提供任何减伤或无敌（--verify-stagger ④⑥ 断言 hp 照扣、照死）。
	_stagger = GameConstants.ENEMY_STAGGER_TIME

func _die() -> void:
	# ⚠⚠ **防重复播放守卫**：与 Zombie._die 同款。已核实唯一调用点是 `take_damage()` :393，
	#   那里开头有 `if dead or state == State.DEAD: return` → 现状不会重复调用；
	#   这里存旧值是为了让"响一次"在将来新增调用点时也不可能出错（`Sfx.play` 不幂等）。
	var _was_dead: bool = dead
	dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	# ==== R-114 死亡短促（纯附加反馈）====
	if not _was_dead:
		Sfx.play("enemy_die_merc")
	died.emit()
	queue_free()
