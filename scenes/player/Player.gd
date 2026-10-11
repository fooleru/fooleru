# Player · CharacterBody2D · cp1 阶段 1
# 状态机：IDLE / WALK / SPRINT / DODGE / DEAD
# 数值：依据 GameConstants
extends CharacterBody2D
class_name Player

const BulletScene := preload("res://scenes/player/Bullet.tscn")

signal hp_changed(hp: float, max_hp: float)
signal stamina_changed(stamina: float, max_stamina: float)
signal load_changed(current: float, capacity: float, factor: float)
signal died
signal ammo_changed(ammo: int, mag: int, reloading: bool)
signal reserve_changed(current: int)   # R-74：当前武器口径的备弹数变化
signal hunger_changed(v: float, max_v: float)   # R-77：饥饿
signal thirst_changed(v: float, max_v: float)   # R-77：口渴
signal weapon_changed(label: String)
# R-144：弹药盒补给读条进度（给 Main 走 toast 通道用；Player 自己不写字）
signal feed_progress(done: int, active: bool, rounds: int)

enum State { IDLE, WALK, SPRINT, DODGE, DEAD }

var hp: float = GameConstants.BASE_MAX_HP
var max_hp: float = GameConstants.BASE_MAX_HP
var stamina: float = GameConstants.BASE_STAMINA
var max_stamina: float = GameConstants.BASE_STAMINA
var current_load: float = 0.0
var overload_factor: float = 1.0

var state: State = State.IDLE
var input_dir: Vector2 = Vector2.ZERO
var speed_mult: float = 1.0  # 验证专用倍速（默认 1.0；无头 bot 走位用 >1 缩短跑图时间）

var dodge_timer: float = 0.0
var dodge_velocity: Vector2 = Vector2.ZERO

# === 武器（cp2 多武器切片 · 用 Dictionary 表示，规避全局类缓存依赖） ===
var weapons: Array = []          # 武器字典列表（loadout）
var weapon_index: int = 0        # 当前武器下标
var ammo_list: Array[int] = []   # 与 weapons 平行的每武器弹量
var armor: Dictionary = {}       # R-71：装备中的护甲（空 = 无甲，减伤 0）
# ==== R-101：装备栏（GEAR）· 三轮拍板落地的数据 ====
# 用户需求逐字：「装备栏包括两个武器槽位（对应的快捷键是'1'、'2'），1个护甲槽位，一个背包槽位。
#   背包是用来增加负重的。给玩家添加一个"双肩包"，增加20负重。」
var pack: Dictionary = {}        # R-101：装备中的**背包**（空 = 无背包，负重加成为 0）
# ⚠⚠ **R-101 最重要的结构决策：装备槽 == `weapons` 数组本身，不另开一套** ====
#   旧结构 `weapons` 是**无上限**的"持有的枪"，`1`/`2` 键按下标 `_switch_to(0/1)`，
#   而第 3 把及以后的枪**既不在背包里、也不在任何 UI 里**（玩家看不见、摸不着，
#   只能靠 `Q`（`_switch_next`）循环到它 —— R-71 留下的一处真实设计缺陷）。
#   用户拍板「装备栏只显示 2 个武器槽；多出来的武器留在背包容器里」→
#   **正确做法是把 `weapons` 收敛成"已装备的枪"并硬性上限 `GEAR_WEAPON_SLOTS`(2)**：
#     ① `1`/`2` 键 → `_switch_to(0)` / `_switch_to(1)` **一行都不用改**（下标语义天然对齐槽位）
#     ② `ammo_list` 继续与 `weapons` 平行，**零改动**
#     ③ `Q`（`_switch_next`）的 `% weapons.size()` 现在**只会在装备的两把之间循环**
#        —— 这正是"循环换枪"应有的语义（改动前它会循环到玩家看不见的第 3 把枪）
#     ④ **没装备的枪 = 背包里的一件普通物品**（`_inv` 里的 Dictionary），
#        复用 R-71 已有的拖拽 / 右键「装备」/ 占格绘制，**不需要新的一套容器**
var ammo: int = 0                # 当前武器弹量（HUD/验证兼容）
# R-74：备弹池（口径 → 发数）。装填从这里扣；弹药盒并入这里。
var reserve: Dictionary = {}
# R-77：饥饿 / 口渴（0..100，随时间自然下降；归零 → 缓慢持续掉血）
var hunger: float = GameConstants.HUNGER_START
var thirst: float = GameConstants.THIRST_START
# R-121：时间冻结（玩家在基地第 100 层时为 true）。
#   设计文档 base-survival-npc.md §0.2「进入基地时时间静止」：基地内保持时间戳不变，
#   **所有随游戏内时间变化的生存量一律冻结** —— 饥饿/口渴不再衰减、不因归零掉血、
#   体力不再自然恢复（要恢复得用双人床「休息」，R-42）。
#   ⚠ 由 Main 在切层时设置（单向数据流 Main → Player，Player 不反查 _floor）。
#   ⚠ 只冻结「按游戏内时间累积」的量；**即时战斗量（fire_cd / reload_t / 散射恢复）不冻结**，
#     它们按现实帧流逝，与"世界时间"无关。
var time_frozen: bool = false
var _reload_pending: int = 0     # 本次装填待入膛的发数（装填完成时入弹）
var fire_cd: float = 0.0
# R-71 射击模式：`_trigger_held` = 左键是否按住；`_trigger_edge` = 本帧是否刚按下（单发用，消费后清零）
var _trigger_held: bool = false
var _trigger_edge: bool = false
var is_reloading: bool = false
var reload_t: float = 0.0
var aim_dir: Vector2 = Vector2.RIGHT

# ==== R-144：长按 R 补给弹药盒（用户拍板）====
# 【用户需求逐字】「按住R键0.5秒后，玩家自动从背包中取出当前武器的弹药盒补充备弹，
#   每补充1个弹药盒要耗费3秒读条时间，读条期间玩家不能移动，不能开火。」
# 【方案 A（用户拍板）】短按 R（松开时 < 0.5s）= 原换弹；长按 ≥ 0.5s = 补给。
#   → 原实现是**电平轮询**（按住第 1 帧就换弹，`Input.is_physical_key_pressed(KEY_R)`），
#     本批必须改成**按下 / 松开语义**：长按期间**不得**触发换弹（见 `_r_key_step`）。
# 【默认②】一次长按**连续补到「备弹池满」或「背包没盒」为止**（不因松手而中断）。
# 【默认③】挨打**不打断**读条（`take_damage` 里没有任何取消补给的代码 —— 这条天然成立，
#   `--verify-ammofeed` ⑩ 直接驱动它钉死）。
# 【默认④】读条 = 玩家身上的**形状**进度条（`FeedBar.gd`，世界空间禁止文字的 R-128 铁律）
#   + HUD 提示通道的**文字**（toast，由 Main 接 `feed_progress` 信号显示）。
var is_feeding: bool = false        # 是否正在补给读条
var feed_t: float = 0.0             # 当前这一盒的剩余读条秒数（从 FEED_BOX_TIME 递减到 0）
var feed_caliber: String = ""       # 本次补给锁定的口径（换枪改口径 → 自愈式取消）
var _r_hold_t: float = 0.0          # R 键已按住时长（判定短按 / 长按）
var _r_long_fired: bool = false     # 本轮按住是否已触发过「长按=补给」（防重复触发）
# R-144：Main 注入的「从背包取一盒」回调。**Player 不持有物品表**（那是 Main 的私有 `_inv`），
#   所以取盒只能回调出去。`Callable()` 为空（未注入）时补给**整体失效** —— 见 `start_feeding()`。
#   ⚠ 为什么用回调而不是信号：需要**同步拿返回值**（{"ok","rounds"}）来决定下一盒还补不补，
#     信号是异步广播、拿不到返回值。
var _feed_take_box: Callable = Callable()
# R-144 缺陷⑮：Main 注入的「背包里**有没有**该口径弹药盒」**只读**查询回调。
#   【为什么非有它不可】原先 `start_feeding()` 只查 `_feed_room_ok()`（备弹池**空间**够不够），
#     **从不查背包到底有没有盒** → 没盒时照样进 3 秒读条。而读条期间 `input_dir` 被清零
#     （`_physics_process`）、`fire()` 被拦（五个 gate 之一）→ **白锁玩家 3 秒零收益**，
#     而且 `_r_key_step()` 里「长按失败 → 回落普通换弹」这条兜底**永远走不到**
#     （因为 `start_feeding()` 返回了 true）。这是玩家按住 R 就能撞到的手感 bug。
#   Player 不持有物品表 → 只能再回调一个**只读谓词**让 Main 回答（[_feed_take_box] 同理）。
#   ⚠ **fail-closed**（未注入 / 返回 false 一律当"没有盒"）：这是 R-144 的**零回归面** ——
#     既有的 65 个验证入口与正常启动路径一个都不注入回调，未注入 = 没有盒 =
#     `start_feeding()` 返回 false = 长按 R 回落普通换弹，逐帧行为不变。
var _feed_has_box: Callable = Callable()

# ==== R-114 音效（R-114：全部代码合成，见 `scripts/autoload/Sfx.gd`）====
# ⚠ **只加调用、零逻辑改动** —— 下面两个字段只服务于"什么时候响一次脚步"。
# `_foot_dist` 是**距离累加器**而不是计时器：脚步必须与"走了多远"成正比，
#否则冲刺（1.5×速度）时脚步声会稀疏得不像在跑。
# 间隔取 STEP_DIST = 30px 的依据：`MOVE_SPEED = 80px/s` → 30px ≈ 0.375s 一步
#   ≈ 160 步/分，落在真人正常步频（100~180 步/分）的上沿 → 听起来是"快步走"而不是"机器人"。
#   冲刺 120px/s 同样 30px → 0.25s 一步（240 步/分，明显的快步小跑）。
#   ⚠ 同时 `Sfx` 侧还有 MIN_REPLAY_MS=45ms 的硬闸 —— 双保险。
var _foot_dist: float = 0.0
const STEP_DIST: float = 30.0
var _forced_aim: Vector2 = Vector2.RIGHT
var _forced_facing: Vector2 = Vector2.RIGHT  # 强制瞄准时从玩家中心算的朝向（用于稳定旋转）
var _use_forced_aim: bool = false
var _remote_move: bool = false  # 无头验证用：true 时不动采集 WASD，input_dir 由外部驱动
var aiming: bool = false        # 右键瞄准姿态（枪口锁光标 + 移动减速）

# ==== 射击散射（R-86）====
# `_spread_bloom` = 当前**连射累积**角度（度），从0 线性累加到
#   `(spread_base_deg × SPREAD_MAX_MULT) - spread_base_deg` 后封顶。
# 存"累积量"而不是"当前总角"，是为了让收敛逻辑与基础值解耦：
#   换枪后基础值变了，累积量仍然按新武器的 max 重新封顶即可。
var _spread_bloom: float = 0.0
# 停火后线性收敛的计时器（秒）。为什么需要它而不是"只要没开火就收敛"：
#   连发时每帧都在 fire() 与 _update_weapon 之间来回，若无条件收敛，
#   累积速率会被收敛吃掉，"射速越快散射越大"这条需求就失效了。
#   所以只在**连续停火 SPREAD_RECOVER_DELAY 秒后**才开始收敛 —— 给一个
#   "短停顿不算停火"的宽限期，半自动点射因此完全不吃收敛惩罚。
const SPREAD_RECOVER_DELAY := 0.25
var _spread_idle_t: float = 0.0

@onready var muzzle: Marker2D = $Muzzle
@onready var _body: Polygon2D = $Sprite     # R-123：原三角形（无武器 / 无图标时的玩家表示）
var _weapon_sprite: Sprite2D = null         # R-123：武器图精灵（装备后**替换**三角形）
var _feed_bar: Node2D = null                # R-144：补给读条（形状进度条，代码 new，不动 Player.tscn）

# R-144：补给读条脚本。用 preload 而不是 `class_name` —— 与本工程「规避全局类缓存依赖」的
#   既有取向一致（见文件头 `weapons` 的 Dictionary 抉择 + Main 里的 `PlayerScript` preload）。
const FeedBarScript := preload("res://scenes/player/FeedBar.gd")

# R-123：三个武器的图标（装备 / 换枪时替换玩家三角形）。
#   ⚠ key 必须与 `GameConstants.WEAPON_ITEMS[].id` 逐字一致（pistol / smg / mp_133），
#     否则 `_sync_weapon_sprite()` 找不到纹理 → 回退三角形（不崩）。
const WEP_TEX := {
	"pistol": preload("res://assets/sprites/ui_icon_wep_pistol.png"),
	"smg": preload("res://assets/sprites/ui_icon_wep_smg.png"),
	"mp_133": preload("res://assets/sprites/ui_icon_wep_mp_133.png"),
}

func _ready() -> void:
	add_to_group("player")
	_make_weapon_sprite()
	_make_feed_bar()      # R-144：补给读条（与 _make_weapon_sprite 同款取舍：代码 new，不动 Player.tscn）
	_build_loadout()
	_emit_all_signals()

# R-144：代码 new 一个 Node2D 画补给读条（**不动 Player.tscn** —— 少一个回归面，R-112/R-123 同款取舍）。
#   ⚠⚠ **必须 `top_level = true`**：FeedBar 是 Player 的子节点，而 Player 的 `rotation`
#     每帧被写成"朝鼠标的角度"（`_update_weapon`）。若不脱离父级变换，读条会跟着枪一起转，
#     表现为「进度条歪着 / 竖着甚至倒过来」——这正是 `top_level` 要解决的那一个坑。
#   ⚠ z_index 抬高：读条要压在玩家 / 敌人 / 箱子上方（世界空间这些都是默认 z_index=0）。
func _make_feed_bar() -> void:
	_feed_bar = FeedBarScript.new()
	_feed_bar.name = "FeedBar"
	_feed_bar.top_level = true
	_feed_bar.z_index = 8
	_feed_bar.visible = false
	add_child(_feed_bar)

# R-144：把读条摆到玩家上方约 10px 并喂进度。
#   ⚠ **必须整数坐标**：本作内部基准 320×180，非整数坐标在 `viewport` 拉伸模式下会让
#     1px 的细条出现半像素发虚（与 R-131 瓦片「整数放大」是同一条理由）。
#     → 位置整体 `.round()`，形状内部同样只用整数。
func _update_feed_bar(progress: float) -> void:
	if _feed_bar == null:
		return
	_feed_bar.show_at((global_position + Vector2(0.0, -10.0)).round())
	_feed_bar.set_progress(progress)

func _hide_feed_bar() -> void:
	if _feed_bar != null and _feed_bar.visible:
		_feed_bar.hide_bar()

# R-123：代码 new 一个 Sprite2D 显示武器图（**不动 Player.tscn** —— 少一个回归面，R-112 同款取舍）。
#   ⚠ 必须**先于** `_build_loadout()` 建好：后者末尾会调 `_sync_weapon_sprite()`。
func _make_weapon_sprite() -> void:
	_weapon_sprite = Sprite2D.new()
	_weapon_sprite.name = "WeaponSprite"
	_weapon_sprite.visible = false
	add_child(_weapon_sprite)

# R-123：装备 / 换枪时同步玩家精灵。
#   有武器且有对应图标 → 显示武器图并**隐藏三角形**；否则显示三角形、隐藏武器图。
#   ⚠ 单向：本函数只读 `weapons` / `weapon_index`，**不改它们**（不制造状态回环）。
func _sync_weapon_sprite() -> void:
	var wid := ""
	if weapons.size() > 0 and weapon_index >= 0 and weapon_index < weapons.size():
		wid = String(weapons[weapon_index].get("id", ""))
	var has_tex: bool = WEP_TEX.has(wid)
	if _weapon_sprite != null:
		_weapon_sprite.texture = (WEP_TEX[wid] as Texture2D) if has_tex else null
		_weapon_sprite.visible = has_tex
	if _body != null:
		_body.visible = not has_tex

# R-143：武器图「朝左时上下颠倒」的镜像修正。
#   【为什么是 flip_v，不是 flip_h】
#     Sprite2D 的 flip 作用于**自身纹理**，先于父节点 rotation 生效，于是
#       rotation = 180° 且 flip_v = true → rotate180( flip_v(img) ) = flip_h(img)
#     即"枪口朝左、枪身正立" —— 正是要的镜像结果。
#     而只靠 rotation = 180° 得到的是 rotate180(img) = **上下颠倒**，这就是本 bug。
#   【判据为什么直接用 `rotation`】
#     `_update_weapon()` 每物理帧已经把"朝鼠标的角度"写进 `rotation` 了，
#     这里只做一次 absf 比较，**不再算一遍 atan2**（避免两处朝向算错不一致）。
#   ⚠⚠ 恰 ±90°（正上 / 正下）是个**镜像不连续点**，实测行为受浮点宽度支配：
#     `Node2D.rotation` 是 **float32**（存 1.5707963705…），GDScript 的 `PI` 是 **float64**
#     （`PI*0.5` = 1.5707963267…）→ 正朝上时 `absf(rotation) > PI*0.5` 判为 **true**。
#     但这**不是缺陷**：侧视图的枪转到竖直时，"握把在左还是右"本来就必须在一瞬间跳变
#     （从左边转上来 → 握把在左；从右边转上来 → 握把在右），任何翻面方案都躲不掉。
#     → 验证入口 `--verify-wepeicon` ⑥ 因此**只在离分界 45° 的朝向上断言**，
#       不在边界上测浮点舍入。见 `Main._verify_wepeicon_test()` ⑥ 的注释。
#   【玩家三角形为什么不用管】
#     `Sprite`(Polygon2D) 顶点 (6.44,0) (-3.22,2.59) (-3.22,-2.59) 关于 y=0 对称，
#     rotate180 的结果**本身就是**它的水平镜像 → 无需 flip（改了反而无谓扩大改动面）。
func _sync_weapon_facing() -> void:
	if _weapon_sprite == null:
		return
	_weapon_sprite.flip_v = absf(rotation) > PI * 0.5

# 方向采集：抽成纯函数，便于 headless 回归锁定符号约定（防止方向写错再次回归）
# W=上 → -y ｜ S=下 → +y ｜ A=左 → -x ｜ D=右 → +x（Godot 2D：+y 向下）
static func dir_from_keys(up: bool, down: bool, left: bool, right: bool) -> Vector2:
	var x := 0.0
	var y := 0.0
	if right: x += 1.0
	if left: x -= 1.0
	if down: y += 1.0
	if up: y -= 1.0
	return Vector2(x, y)

func _physics_process(delta: float) -> void:
	# 1. 收集输入（直接用物理按键，不依赖 project.godot input map）
	if not _remote_move:
		input_dir = dir_from_keys(
			Input.is_physical_key_pressed(KEY_W),
			Input.is_physical_key_pressed(KEY_S),
			Input.is_physical_key_pressed(KEY_A),
			Input.is_physical_key_pressed(KEY_D))
	# R-144【不能移动】：补给读条期间玩家**不能移动**（用户拍板）。
	#   ⚠ 必须在**采集输入之后、FSM 之前**清零：后面 FSM 见 `input_dir == ZERO` 自然走
	#     IDLE → `velocity.move_toward(ZERO, ...)` 自然刹停，**不需要**再改速度分支。
	#   ⚠ 同时覆盖 `_remote_move`（无头驱动）与真实 WASD 两条路径 —— 放在这里两者都截断。
	if is_feeding:
		input_dir = Vector2.ZERO
	var wants_sprint := Input.is_physical_key_pressed(KEY_SHIFT)

	# 1.5 武器更新（开火冷却 / 换弹 / 瞄准 / R 换弹）
	_update_weapon(delta)

	# 2. 更新负重系数 + 体力 + 生存（饥饿 / 口渴）
	_update_overload_factor()
	_update_stamina(delta)
	_update_survival(delta)

	# 3. FSM 切换（DODGE / DEAD 不被自动切走）
	if state != State.DODGE and state != State.DEAD:
		var moving := input_dir.length() > 0.1
		if wants_sprint and moving and _can_sprint():
			state = State.SPRINT
		elif moving:
			state = State.WALK
		else:
			state = State.IDLE

	# 4. 各状态执行
	match state:
		State.IDLE:
			velocity = velocity.move_toward(Vector2.ZERO, 800 * delta)
		State.WALK:
			velocity = input_dir.normalized() * GameConstants.MOVE_SPEED * overload_factor * speed_mult
		State.SPRINT:
			velocity = input_dir.normalized() * GameConstants.MOVE_SPEED * GameConstants.SPRINT_MULTIPLIER * overload_factor * speed_mult
		State.DODGE:
			dodge_timer -= delta
			if dodge_timer > 0.0:
				velocity = dodge_velocity
			else:
				state = State.IDLE
				velocity = Vector2.ZERO
		State.DEAD:
			velocity = Vector2.ZERO

	# 4.5 右键瞄准：非翻滚/死亡时移动减速到精确步
	if aiming and state != State.DODGE and state != State.DEAD:
		velocity *= GameConstants.AIM_MOVE_MULTIPLIER

	move_and_slide()

	# ==== R-114 脚步音效 ====
	# ⚠ **只读状态、只累加计数器**：不写 `velocity` / 不写 `state` / 不写任何玩法数值。
	#   死亡 / 停止移动时不响；只按"本帧真的走过的距离"累加（翻滚也算脚步）。
	#   节流见文件头 `STEP_DIST` 注释 —— **没有节流就会 60 只僵尸 + 玩家移动变成噪音墙**。
	if state != State.DEAD:
		var moved: float = get_real_velocity().length() * delta
		if moved > 0.01:
			_foot_dist += moved
			if _foot_dist >= STEP_DIST:
				_foot_dist = 0.0
				Sfx.play("step")
		else:
			_foot_dist = 0.0

func _input(event: InputEvent) -> void:
	# R-71：左键的「按下边沿」与「按住状态」——单发武器用边沿，连发武器用按住
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_trigger_held = true
			_trigger_edge = true
		else:
			_trigger_held = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			_try_dodge()
		elif event.physical_keycode == KEY_1:
			_switch_to(0)
		elif event.physical_keycode == KEY_2:
			_switch_to(1)
		elif event.physical_keycode == KEY_Q:
			_switch_next()

func _try_dodge() -> void:
	if state == State.DEAD or state == State.DODGE:
		return
	# R-144【不能闪避】：补给读条期间不能闪避（闪避是一次带位移的爆发动作，会破坏"不能移动"的语义）。
	#   ⚠ 早退放在**扣体力之前**：否则"读条中按空格"会白扣一次体力却什么也不做。
	if is_feeding:
		return
	if stamina < GameConstants.DODGE_STAMINA_COST:
		return
	state = State.DODGE
	dodge_timer = GameConstants.DODGE_DURATION
	stamina = max(0.0, stamina - GameConstants.DODGE_STAMINA_COST)
	var dir := input_dir if input_dir.length() > 0.1 else Vector2.DOWN
	dodge_velocity = dir.normalized() * GameConstants.DODGE_SPEED
	stamina_changed.emit(stamina, max_stamina)

# === 武器方法（cp1 阶段 3 / cp2 多武器） ===
func _update_weapon(delta: float) -> void:
	if _use_forced_aim:
		aim_dir = _forced_aim
		if _forced_facing.length_squared() > 0.0:
			rotation = _forced_facing.angle()
	else:
		aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)  # 右键瞄准姿态
		var cursor: Vector2 = get_global_mouse_position()
		aim_dir = _aim_dir_to(cursor)
		# 朝向从玩家中心算：切断"旋转→枪口→瞄准→旋转"反馈环，避免贴脸时乱抖
		rotation = (cursor - global_position).angle()
		# R-71 射击模式：半自动 = 每按一次左键打一发（边沿）；全自动 = 按住持续射击（按住）
		# ⚠ 不再用 `Input.is_mouse_button_pressed()` 轮询 —— 那会让手枪变成连发。
		var is_auto: bool = weapons.size() > 0 and bool(weapons[weapon_index].get("auto", false))
		if (is_auto and _trigger_held) or ((not is_auto) and _trigger_edge):
			fire()
		_trigger_edge = false      # 边沿每帧消费一次（无论当前武器是否自动）
	fire_cd = max(0.0, fire_cd - delta)
	# R-86：散射收敛与开火冷却同一时基（物理帧），保证 headless 可用帧数精确复现
	_update_spread_recovery(delta)
	# R-144：补给读条推进。**只在这里调一次**（本函数每物理帧跑一次）——
	#   与开火冷却 / 散射恢复同一时基 → headless 可用物理帧数精确复现「每盒恰好 3.0s」。
	_update_feeding(delta)
	if is_reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			is_reloading = false
			var wr: Dictionary = weapons[weapon_index]
			var mr: int = int(wr["mag_size"])
			# R-74：只入膛"装填时实际从备弹池取到"的发数（不再是凭空虚满）
			ammo = mini(mr, ammo + _reload_pending)
			_reload_pending = 0
			ammo_list[weapon_index] = ammo
			ammo_changed.emit(ammo, mr, false)
	else:
		# R-144【方案 A】：R 键从"电平轮询"改成"按下 / 松开语义"（抽成纯函数便于 headless 锁定，
		#   见 `_r_key_step`；本仓库既有惯例同 `dir_from_keys()`）。
		#   ⚠ 这里用 `else`（等价于原来的 `elif 按住R`）——`_r_key_step` **必须每帧都调**，
		#     否则「松开 R」那一帧收不到（松开时 `is_physical_key_pressed` 已 false），
		#     短按换弹就永远触发不了。函数内部自己判断 `held`。
		#   ⚠ 仍在「未换弹」时才有意义：换弹期间不轮询 R（与原行为一致）。
		_r_key_step(delta, Input.is_physical_key_pressed(KEY_R))
	# R-143：`rotation` 在**两个分支里**分别赋值 → 统一在函数末尾同步一次武器图镜像，
	#   避免"强制瞄准"与"跟随鼠标"两条路径漏掉一条（那正是这个 bug 的形状）。
	_sync_weapon_facing()

func fire() -> void:
	# R-144【不能开火】：补给读条期间不能开火（用户拍板）。
	#   与 `is_reloading` 同一道门 —— 都是"手上的动作被占用"，语义一致。
	if state == State.DEAD or is_reloading or is_feeding or fire_cd > 0.0 or ammo <= 0 or weapons.size() == 0:
		return
	var w: Dictionary = weapons[weapon_index]
	ammo -= 1
	ammo_list[weapon_index] = ammo
	fire_cd = w["fire_cooldown"]
	var base_ang := aim_dir.angle()
	var pellets: int = w["pellets"]
	var spread_deg := _current_spread_total_deg()
	# R-83：扳机计数（试玩记录设施）。放在所有提前 return 之后 → 记的是**真正打出去的枪**。
	#   pellets 一起报上去：霰弹枪一次扳机 6 弹丸，命中率必须按弹丸算才有意义。
	#   设施默认关闭（无 --playtest-log）→ 首行即 return，对开火路径零开销。
	PlaytestLog.note_shot(pellets)
	# ==== R-114 开火音效 ====
	# ⚠ **放在所有提前 return 之后** → 空枪 / 换弹中 / 冷却中**不响**（否则"哑枪"会有声音）。
	#   按 `w["id"]` 分派三把枪的音色；未知 id 落到 `pistol_fire`（兜底不崩）。
	#   射速/弹道/散布**一个字节都没改** —— 这是一行纯附加的音频调用。
	Sfx.play(_sfx_for_weapon(String(w.get("id", ""))))
	# 本次开火先把累积推上去（**先加后采样**：这一发就应当吃到自己造成的散布）
	_add_spread_bloom(w)
	for i in pellets:
		var b := BulletScene.instantiate()
		var off := 0.0
		# ⚠ R-86 核心修复：旧条件是 `if spread > 0.0 and pellets > 1`，
		#   而手枪 / MP5 的 pellets==1 → 条件恒假 → **完全没有散射**，每发都是精准直线。
		#   现在**所有 pellet（含单弹丸）都吃散射**。
		#   对称均匀采样 → [-总角/2, +总角/2]。常量存的是**总角**（见 GameConstants 注释）。
		if spread_deg > 0.0:
			off = deg_to_rad(randf_range(-spread_deg, spread_deg) * 0.5)
		# 弹型层：多弹丸武器再叠一个固定锥角内的均匀偏移（霰弹枪 6 弹丸用）。
		#   与瞄准层**独立** —— 这是霰弹枪散射的第二个维度，别和连射累积混成一个数。
		var cone: float = float(w.get("pellet_cone_deg", 0.0))
		if cone > 0.0 and pellets > 1:
			off += deg_to_rad(randf_range(-cone, cone) * 0.5)
		b.global_position = muzzle.global_position
		b.set_direction(Vector2.from_angle(base_ang + off))
		b.set_tail_start(global_position)  # 首帧扫掠回退到玩家中心 → 贴脸敌人也能命中
		b.damage = w["damage"]
		b.speed = w["bullet_speed"]
		get_tree().current_scene.add_child(b)
	ammo_changed.emit(ammo, w["mag_size"], false)
	if ammo == 0:
		start_reload()

# ==== R-114：武器 id -> 音效 id 的**唯一映射表** ====
# ⚠ 为什么放在 Player 而不是散在 Main：分派依据是 `weapons[i]["id"]`（战斗形态字典），
#   这个字典只有 Player 有；放这里 future「加第四把枪」只需在这里加一行。
# ⚠ 为什么不用 `category`：MP 133 的 category 是 "shotgun"，未来可能还有别的霰弹枪型号，
#   而**音效是按"这一发听起来多重"分的**，更贴近具体型号而不是类别。
func _sfx_for_weapon(wid: String) -> String:
	match wid:
		"smg":
			return "smg_fire"
		"mp_133":
			return "shotgun_fire"
		_:
			return "pistol_fire"   # 手枪 + 任何未来未知武器 = 兜底，绝不返回空串

# ==== R-86：射击散射 ====
# 本次开火使用的**瞄准层总角**（度）= 基础角 + 连射累积。
# ADS 缩紧但**不缩到 0** —— 保留一点基础精度惩罚，让"站桩瞄准 vs 移动射击"仍有取舍。
func _current_spread_total_deg() -> float:
	if weapons.size() == 0:
		return 0.0
	var w: Dictionary = weapons[weapon_index]
	var total := float(w.get("spread_base_deg", 0.0)) + _spread_bloom
	if aiming:
		total *= GameConstants.AIM_SPREAD_SCALE
	return total

# 累积封顶：总角上限 = base × SPREAD_MAX_MULT，换算成"累积量"上限
func _spread_bloom_cap() -> float:
	if weapons.size() == 0:
		return 0.0
	var w: Dictionary = weapons[weapon_index]
	return float(w.get("spread_base_deg", 0.0)) * (GameConstants.SPREAD_MAX_MULT - 1.0)

# 每发叠加一层（线性）。这是"射击频率越快散射越大"的唯一来源：
#   射速快的武器单位时间触发次数多 → 累积快。冷却时间本身没动过。
func _add_spread_bloom(w: Dictionary) -> void:
	_spread_bloom = minf(_spread_bloom + float(w.get("spread_per_shot_deg", 0.0)), _spread_bloom_cap())
	_spread_idle_t = 0.0

# 停火 SPREAD_RECOVER_DELAY 秒后，线性收敛回基础值。
# 放 _update_weapon 里（而不是 _process）→ 与开火冷却同一时基，headless 验证可用物理帧精确驱动。
func _update_spread_recovery(delta: float) -> void:
	if weapons.size() == 0:
		_spread_bloom = 0.0
		return
	_spread_idle_t += delta
	if _spread_idle_t < SPREAD_RECOVER_DELAY:
		return
	var w: Dictionary = weapons[weapon_index]
	_spread_bloom = maxf(0.0, _spread_bloom - float(w.get("spread_recover", 0.0)) * delta)

# 重置累积到 0（只剩基础值）。**换弹时调用**。
# 决策理由：换弹是有意的战术停顿（手枪 1.8s / 霰弹 2.2s / MP5 2.4s，
#   都远长于 SPREAD_RECOVER_DELAY），玩家已付出"停止输出 + 移动受限"的代价。
#   若不清零，"点射到封顶 → 换弹 → 立刻满精度"就是零成本操作，
#   散射累积会退化成一个可随时免费重置的假压力。
#   ⚠ **切枪不清零** —— 理由见 _switch_to() 注释。
func reset_spread() -> void:
	_spread_bloom = 0.0
	_spread_idle_t = 0.0

# 无头验证探针：当前瞄准层总角（度）
func spread_total_deg() -> float:
	return _current_spread_total_deg()

# 无头验证探针：当前连射累积量（度）
func spread_bloom_deg() -> float:
	return _spread_bloom

# R-74：装填 = 从「当前武器口径」的备弹池取弹；池空则装填失败（弹药不凭空出现）。返回是否开始装填。
func start_reload() -> bool:
	if weapons.size() == 0 or is_reloading or ammo >= weapons[weapon_index]["mag_size"]:
		return false
	var w: Dictionary = weapons[weapon_index]
	var mag: int = int(w["mag_size"])
	var need := mag - ammo
	var got := take_reserve(String(w.get("caliber", GameConstants.CAL_9X19)), need)
	if got <= 0:
		ammo_changed.emit(ammo, mag, false)   # 无备弹 → 装填失败（HUD 不进入"换弹中"）
		return false
	_reload_pending = got
	is_reloading = true
	reload_t = w["reload_time"]
	# R-86：换弹重置散射累积（决策理由见 reset_spread() 注释）。
	#   在**开始换弹**时而非装填完成时重置：换弹动作本身已经是玩家主动付出的停顿代价。
	reset_spread()
	ammo_changed.emit(ammo, mag, true)
	return true

# ======================================================================
# ==== R-144：长按 R 补给弹药盒 ========================================
# ======================================================================
# 【为什么补给核心放在 Player、而"取盒"回调出去】
#   `is_feeding` / `feed_t` / 读条绘制都在 Player；但**物品表在 Main 手里**（`_inv` 是 Main 的私有）。
#   → Player 只负责"读条计时 + 何时该取一盒"，真正"从背包拿掉一盒并并入备弹"由 Main 注入的回调做。
#   `--verify-ammofeed` 因此可以用**假回调**精确驱动读条（不碰真实背包），也可以用真实回调
#   验证端到端账本（备弹 +50 / 背包 -1 / 负重下降）。
#
# 【为什么"未注入回调时补给整体失效" —— 这是本批最重要的**零回归**设计】
#   既有的 62 个验证入口 / 正常启动路径**都不装**这个回调。只要 `set_feed_provider()` 没被调用，
#   `start_feeding()` 首行就返回 false → 长按 R 会回落成普通换弹（见 `_r_key_step`）→
#   那些入口的行为**逐帧不变**，天然没有回归面。
# `cb`     = "取一盒并并入备弹"（有副作用），读条到点时同步调用、拿字典返回值。
# `has_cb` = "背包里有没有该口径的盒"（**只读**，缺陷⑮；见 `_feed_has_box` 的注释）。
#   ⚠ `has_cb` 给默认值 `Callable()` 纯粹是为了旧调用点仍能编译；**得到默认值 = fail-closed = 没有盒**
#     → 与"完全不注入"同义。所以**生产调用点必须显式传**（见 `Main._process()` 与 `_feed_has_ammo_box`）。
func set_feed_provider(cb: Callable, has_cb: Callable = Callable()) -> void:
	_feed_take_box = cb
	_feed_has_box = has_cb

# 「还能不能再补一整盒」的**两个前置检查**（单一真相源，`start_feeding` 与连续补时共用）。
#   ⚠ 整盒语义：剩余空间 < 整盒容量 → 拒绝（**不做半盒**）——
#     与 `--verify-reservecap` ⑧ / `Main._use_item()` 的弹药分支同一条既有口径。
func _feed_room_ok(cal: String) -> bool:
	if reserve_of(cal) >= reserve_cap_of(cal):
		return false
	if reserve_cap_of(cal) - reserve_of(cal) < GameConstants.ammo_box_rounds_of(cal):
		return false
	return true

# 开始补给读条。返回是否真的进入读条（false = 不满足前置条件，调用方决定要不要回落换弹）。
func start_feeding() -> bool:
	if state == State.DEAD:
		return false
	# R-144【读条 ↔ 翻滚互斥 · 另一半】：补给读条期间不能翻滚（见 `_try_dodge()` 的 `is_feeding` 早退）。
	#   ⚠ 反方向必须在这里补上，否则有一个**真实的语义漏洞**（独立复核拿到原始证据）：
	#     `_physics_process` 第 254 行的 `input_dir = ZERO` 只挡「走／跑」，**挡不住 DODGE** ——
	#     第 267 行 `state != State.DODGE` 保护让翻滚态跳过 FSM 自动切换，第 284 行 DODGE 分支
	#     每帧重写 `velocity = dodge_velocity`(= DODGE_SPEED)。于是「先按住 R、翻滚中跨过 0.5s 阈值」
	#     会在**翻滚还没结束**时进读条 → 变成「读条在跑、人也在滑」，直接违反用户原话「读条期间不能移动」。
	#   ⚠ 取舍（**有意为之**，非用户拍板）：若 0.5s 阈值恰好在翻滚中途被跨过，`_r_key_step` 已把
	#     `_r_long_fired` 置位 → 本处长按的 `start_feeding()` 失败后会**回落成普通换弹而非补给**
	#     （见 `_r_key_step` 的回落设计，避免"按住半秒却什么都不发生"的死键手感）。
	#     重叠窗口只有一次 `DODGE_DURATION`(0.3s) 那么长；松开 R 再按住即可正常补给 —— **不是死键**。
	if state == State.DODGE:
		return false
	if is_feeding:                     # 已在补给中 → 不重复触发
		return false
	if weapons.is_empty():             # 空手没有"当前武器口径"
		return false
	if is_reloading:                   # 换弹中不能补给（手上的动作被占用）
		return false
	# ⚠ **口径必须在所有有效性门禁之前算出来**：下面的「有没有盒」查询要**按口径**回答，
	#   原写法把 `cal` 放在回调有效性检查之后，加这条门禁时会拿不到口径。
	#   这是缺陷⑮ 修复时**故意上移**的，注释写在这里防止有人再把它挪回去。
	var cal: String = _cur_caliber()
	if not _feed_take_box.is_valid():  # 未注入回调 → 补给整体失效（零回归设计，见上）
		return false
	# R-144 缺陷⑮【有没有盒】：背包里没有该口径的弹药盒 → **不许**进读条，`_r_key_step()` 才好回落换弹。
	#   ⚠ 为什么要在这里挡，而不是等 3 秒后让 `_feed_take_box` 返回 ok:false 才收：
	#     读条那 3 秒里玩家**不能移动、不能开火**，白锁 3 秒且零收益 —— 这是手感 bug 不是记账误差。
	#   ⚠ fail-closed：`_feed_has_box` 未注入 → 一律当"没有盒"（保住 R-144 的零回归面）。
	if not _feed_has_box.is_valid():
		return false
	if not bool(_feed_has_box.call(cal)):
		return false
	if not _feed_room_ok(cal):         # 池已满 / 装不下整盒 → 拒绝
		return false
	is_feeding = true
	feed_t = GameConstants.FEED_BOX_TIME
	feed_caliber = cal
	feed_progress.emit(0, true, 0)
	return true

# R 键的**按下 / 松开语义**（抽成纯函数便于 headless 锁定，本仓库既有惯例同 `dir_from_keys()`）。
#   `held` 由调用方从 `Input.is_physical_key_pressed(KEY_R)` 传入 —— headless 下直接喂 bool，
#   不依赖物理键盘状态（`Input.is_physical_key_pressed` 在无头环境不可靠）。
func _r_key_step(delta: float, held: bool) -> void:
	if held:
		_r_hold_t += delta
		if not _r_long_fired and _r_hold_t >= GameConstants.FEED_HOLD_TIME:
			_r_long_fired = true
			# ⚠ 已在补给中：本处长按**不重复触发**，也**不回落换弹** ——
			#   玩家正在读条，再按住 R 不该把读条打断成换弹（那不是"死键"：补给正在进行）。
			if is_feeding:
				return
			if not start_feeding():
				# 工程侧决定（**非用户拍板**）：长按却补不了（无该口径的盒 / 池已满 / 正在换弹 / 死亡）
				# → 回落到普通换弹，避免"按住 R 半秒却什么都不发生"的死键手感。
				start_reload()
	else:
		# 松开：短按（按住时长 > 0 且从未触发长按）→ 按普通换弹（**与原电平轮询行为一致**）。
		#   ⚠ 已在补给中时不触发换弹：否则"读条中轻点一下 R"会边读条边换弹。
		if _r_hold_t > 0.0 and not _r_long_fired and not is_feeding:
			start_reload()
		_r_hold_t = 0.0
		_r_long_fired = false

# 每物理帧推进读条（只在 `_update_weapon()` 里调一次）。
func _update_feeding(delta: float) -> void:
	if not is_feeding:
		_hide_feed_bar()
		return
	if state == State.DEAD:
		_cancel_feeding()
		return
	# 【自愈式取消】口径变了（换枪 / 装备 / 卸下）→ 取消补给。
	#   这一条**一处覆盖全部换枪路径**（`_switch_to` / `_switch_next` / `equip_weapon*` / `unequip_*`），
	#   而不是去那几个函数里逐个加取消 —— 将来新增换枪入口也自动被覆盖。
	if feed_caliber != _cur_caliber():
		_cancel_feeding()
		return
	feed_t -= delta
	if feed_t > 0.0:
		_update_feed_bar(1.0 - feed_t / GameConstants.FEED_BOX_TIME)   # 0 → 1
		feed_progress.emit(0, true, 0)     # 每帧重发 → Main 的"补充备弹中…"整段读条期间常驻
		return
	# ---- 本盒读条到点：取一盒并入备弹 ----
	feed_t = 0.0
	_update_feed_bar(1.0)
	if not _feed_take_box.is_valid():
		_cancel_feeding()
		return
	var res: Dictionary = _feed_take_box.call(feed_caliber)
	var rounds: int = int(res.get("rounds", 0))
	if not bool(res.get("ok", false)):
		# 没盒了 / 池已满 / 装不下整盒 → 结束。默认② 说的"连续补到满或没盒为止"就是这里收口。
		feed_progress.emit(1, false, 0)
		_cancel_feeding()
		return
	feed_progress.emit(1, true, rounds)     # 一盒完成（Main 显示 "补充备弹 +N 发"）
	# 默认②：**连续补下一盒** —— 但要重新做一遍前置检查（这一盒补完后可能刚好满 / 装不下整盒）。
	if not _feed_room_ok(feed_caliber):
		_cancel_feeding()
		return
	# R-144 缺陷⑮【还有没有下一盒】：刚刚补掉的就是最后一盒时**立刻收口**。
	#   ⚠ 缺了这一条，上面两条检查都过（空间还够）→ 又开一轮 3 秒读条，等到
	#     `_feed_take_box` 返回 ok:false 才收 → 玩家凭空多被白锁 3 秒（不能移动、不能开火）。
	#   ⚠ **静默结束即可**：玩家刚拿到「补充备弹 +N 发」的 toast，不需要再弹别的提示。
	if not _feed_has_box.is_valid():
		_cancel_feeding()
		return
	if not bool(_feed_has_box.call(feed_caliber)):
		_cancel_feeding()
		return
	feed_t = GameConstants.FEED_BOX_TIME

func _cancel_feeding() -> void:
	is_feeding = false
	feed_t = 0.0
	feed_caliber = ""
	_hide_feed_bar()

# === R-74：备弹池（按口径）===
func reserve_of(caliber: String) -> int:
	return int(reserve.get(caliber, 0))

# R-80：某个口径的备弹上限。未知口径给个保守缺省值（不返回 0，否则会永久锁死该口径）。
func reserve_cap_of(caliber: String) -> int:
	return int(GameConstants.RESERVE_CAP.get(caliber, 0))

func is_reserve_full(caliber: String) -> bool:
	return reserve_of(caliber) >= reserve_cap_of(caliber)

# R-80：加入备弹，**超过上限的部分直接丢弃**；返回**实际装入的发数**。
#   返回值让调用方能判断"这一盒到底吃掉了多少" —— 池已满时返回 0，
#   此时不应该把玩家背包里的弹药盒消耗掉（否则就是白扣一件物资）。
func add_reserve(caliber: String, rounds: int) -> int:
	var cap: int = reserve_cap_of(caliber)
	var before: int = reserve_of(caliber)
	var added: int = mini(maxi(0, rounds), maxi(0, cap - before))
	reserve[caliber] = before + added
	reserve_changed.emit(_cur_reserve())
	return added

# 取弹：不足则全给；返回实际取到的发数
func take_reserve(caliber: String, need: int) -> int:
	var have := reserve_of(caliber)
	var got := mini(have, maxi(0, need))
	reserve[caliber] = have - got
	reserve_changed.emit(_cur_reserve())
	return got

# 当前武器口径的备弹数（HUD / 验证用）
func current_reserve() -> int:
	return _cur_reserve()

# 武器 id → 口径（拾取/补给用）
func caliber_of_weapon(id: String) -> String:
	return String(_make_weapon(id).get("caliber", GameConstants.CAL_9X19))

func _cur_reserve() -> int:
	if weapons.size() == 0 or weapon_index < 0 or weapon_index >= weapons.size():
		return 0
	return reserve_of(String(weapons[weapon_index].get("caliber", GameConstants.CAL_9X19)))

# 无头验证用：外部强制瞄准某个世界坐标，并锁定瞄准（不再跟随鼠标）
func set_forced_aim(on: bool) -> void:
	_use_forced_aim = on

# 无头验证用：true 时不动采集 WASD，input_dir 由外部驱动（用于自动走位）
func set_remote_move(on: bool) -> void:
	_remote_move = on

# 瞄准方向：优先从枪口算（保证弹道穿过准星中心）；
# 目标贴到枪口附近时"枪口→目标"向量退化会乱抖，退化为从玩家中心算。
func _aim_dir_to(world_pos: Vector2) -> Vector2:
	var v := world_pos - muzzle.global_position
	if v.length() < GameConstants.AIM_MIN_DIST:
		v = world_pos - global_position
	if v.length_squared() <= 0.0:
		return Vector2.RIGHT
	return v.normalized()

func aim_toward(world_pos: Vector2) -> void:
	# 从枪口算到目标：与 GUI 一致，弹道精确命中目标点（贴脸时内部会退化为中心）
	_forced_aim = _aim_dir_to(world_pos)
	_forced_facing = world_pos - global_position

func _update_stamina(delta: float) -> void:
	# R-121：基地内时间冻结 → 体力不自然恢复、冲刺也不耗（体力条完全静止）。
	#   ⚠ 但在基地里 `stamina_changed` 信号也不发 —— 没问题：体力值不变，HUD 本就无需刷新。
	if time_frozen:
		return
	var regen := GameConstants.STAMINA_REGEN * stamina_regen_multiplier()
	if state == State.SPRINT:
		stamina = max(0.0, stamina - GameConstants.SPRINT_STAMINA_COST * delta)
	elif state != State.DODGE:
		stamina = min(max_stamina, stamina + regen * delta)
	stamina_changed.emit(stamina, max_stamina)

# ======================================================================
# ==== R-103：体力恢复速度受饥饿 / 口渴影响 ====
# ======================================================================
# 【用户需求逐字】
#   「饥饿和口渴度都大于60的时候体力恢复速度加50%，并且在体力槽的右侧显示'+'，
#     当饥饿或者口渴小于20的时候体力恢复速度减50%，并且在体力槽右侧显示'-'。」
#
# 【为什么把"判定"与"倍率"拆成两个函数（而不是把逻辑塞进 `_update_stamina`）】
#   · `stamina_regen_state()`  = **纯判定**，只读hunger/thirst，**不碰 stamina**。
#     它是"HUD 该显示 + / - /什么都不显示"的**唯一权威源** —— HUD 只问它，不重算阈值。
#     纯函数 → headless 可在**不推进任何物理帧**的前提下断言三态（`--verify-staminareg` ⑤），
#     这对"恰好等于 60.0 / 20.0"的边界断言是**必需**的（推进一帧就会让阈值漂移，见 ④）。
#   · `stamina_regen_multiplier()` = 判定 + **与超重惩罚取最严**，只被 `_update_stamina` 调用一次。
#   ⚠ 若把两者合成一个函数，边界断言就必须"推进一帧再读" → hunger 每帧衰减 0.225
#     会让 60.0 立刻掉到 59.775，**恰好等于阈值这件事根本无法测**。拆分是边界可测性的前提。
#
# 【返回值的三个取值 —— 与 HUD 指示器一一对应】
#   · `+1` = 加成（显示 `+`，绿）
#   · `-1` = 惩罚（显示 `-`，红）
#   · `0`  = 正常（**什么都不显示**）
#   ⚠ 用 int 而非 bool/枚举：bool 表达不了三态，枚举要多一个 `class_name` 暴露给 HUD。
#     int 三态在 GDScript 里比较直接，且 `--verify-staminareg` ⑤ 能逐字断言 `+1 / -1 / 0`。
#
# 【为什么**不**扩展 `stamina_changed` 信号去多带一个状态参数】
#   `stamina_changed` 有 **4 个 emit 点**（`_try_dodge` / `_update_stamina` /
#   `restore_stamina` / `_emit_all_signals`）和 **1 个监听方**（`Main` 转给 HUD）。
#   看起来"只改1 处监听方"代价很小，但：
#     ① 语义被污染 —— 信号叫 "stamina **changed**"，而恢复**倍率**并不随 stamina 变化
#        （站着不动 1 秒，stamina 从 40 涨到 60，而倍率可能整个过程都没变）；
#        把"当前恢复倍率"塞进"体力数值变了"的信号里，监听方无法区分这两种语义。
#     ② 未来风险 —— `stamina_changed` 是 Player 最核心的信号（R-46 起就在用），
#        任何新监听方（成就系统 / 音效 / 录像）都得跟着记一个"第 3 个参数是啥"。
#        加参数是**破坏性变更**（GDScript 信号参数不匹配会直接抛错，静默失败都算好的）。
#     ③ HUD 侧"只有状态变化才重绘"这条要求，恰好也不需要信号参数 ——
#        HUD 在 `_on_stamina_changed`（本来就每帧触发）里调一次纯函数，
#        内部缓存上一帧值，**只在真的变了才改visible / 重绘**。
#   → 查询方法波及面小、语义干净、可测。信号签名**保持 `stamina_changed(stamina, max)` 不变**。
#   （若将来第三方系统也要这个状态，正确做法是**另开**一个 `stamina_regen_state_changed(int)`
#     专号，而不是给既有信号加参数—— 本批未加，因为 R-103 只有 HUD 一个消费者。）
func stamina_regen_state() -> int:
	# 惩罚优先判定：任一 < 20 → -1。
	#   ⚠ 顺序说明：与加成互斥（60 > 20），所以先判惩罚还是先判加成结果相同；
	#     这里选"先惩罚"是因为它是**安全侧**（宁可少给加成，不可少给惩罚 ——
	#     玩家饿到 19.9 时绝不该因为"另一个条件"而拿到 ×1.5）。
	if hunger < GameConstants.STAMINA_REGEN_HUNGER_LOW or thirst < GameConstants.STAMINA_REGEN_THIRST_LOW:
		return -1
	# 加成：**两者都** > 60（用户「都大于60」= AND，不是 OR）
	if hunger > GameConstants.STAMINA_REGEN_HUNGER_GOOD and thirst > GameConstants.STAMINA_REGEN_THIRST_GOOD:
		return 1
	return 0

# 当前体力恢复速度的**总倍率**（含 R-46 超重惩罚，**取最严**）。
# ⚠ 这是**唯一**把「饥渴状态」与「负重状态」合成一个数的地方 —— 别在别处再乘一次。
#   取最严（`minf`）而不是叠乘（`*`）的理由写在 GameConstants 的 R-103 常量段。
# ⚠ 加成（1.5）同样会被超重惩罚（0.5）压过 → 0.5：任何一项惩罚都不该被加成抵消。
#   反过来（超重 + 饥渴惩罚）两者都是 0.5 → 0.5，**不是** 0.25。
func stamina_regen_multiplier() -> float:
	var mult := 1.0
	match stamina_regen_state():
		1:
			mult = GameConstants.STAMINA_REGEN_BONUS_MULT      # 1.5
		-1:
			mult = GameConstants.STAMINA_REGEN_PENALTY_MULT    # 0.5
	if overload_factor < GameConstants.MILD_OWE_FACTOR + 0.01:
		mult = minf(mult, GameConstants.HEAVY_OWE_STAMINA_PENALTY)
	return mult

func _can_sprint() -> bool:
	if overload_factor < GameConstants.MILD_OWE_FACTOR + 0.01:
		return false  # heavy overweight cannot sprint
	if stamina < GameConstants.SPRINT_STAMINA_COST * get_physics_process_delta_time():
		return false
	return true

func _update_overload_factor() -> void:
	# R-101：ratio 的分母从**写死的常量**改为 `carry_capacity()`（裸装 60 / 穿双肩包 80）。
	#   ⚠ 为什么必须改这里（不只是 UI 显示）：`_update_overload_factor` 是超重两档
	#   （MILD 1.0 / HEAVY 1.2）的**唯一**计算点。若 UI 显示 80 而这里仍除以 60，
	#   玩家背了 70 会**同时**看到"没超重(70/80)"和"移动变慢(ratio 1.17 > 1.0)"——
	#   两个都"对"但互相矛盾，玩家无法解释。口径必须单一。
	#   ⚠ 超重**阈值**（1.0 / 1.2）与所有**惩罚系数**一律不动：变的是"分母随装备变"，
	#   不是"阈值变了"。这与 R-89 把 40 提到 60 是同一类改动（改容量，不改规则）。
	var cap: float = carry_capacity()
	var ratio := current_load / cap if cap > 0.0 else 0.0
	var new_factor := 1.0
	if ratio > GameConstants.HEAVY_OWE_THRESHOLD:
		new_factor = GameConstants.HEAVY_OWE_FACTOR
	elif ratio > GameConstants.MILD_OWE_THRESHOLD:
		new_factor = GameConstants.MILD_OWE_FACTOR
	if new_factor != overload_factor:
		overload_factor = new_factor
		load_changed.emit(current_load, cap, overload_factor)

# ==== R-101：负重上限（基础值 + 装备加成）====
# 【为什么是"读取时计算"而不是"缓存字段"】
#   候选 A（缓存字段 `_cap_cache`，装备变化时写一次）：读路径更快，但**多一个必须同步的状态**——
#   任何新增的装备入口忘了写缓存，就会让"显示 80 / 判定按 60"这类**静默不一致**再次发生
#   （R-89 的 `Backpack.max_load` 写死 40 就是同一类 bug 的另一个实例）。
#   候选 B（本函数，每次读时相加）：**没有可失效的状态**，调用方不可能读到过期值。
#   → 选 B。代价是每帧一次字典查表 + 加法（`get("load_bonus", 0.0)`），
#     相对同帧的 `move_and_slide()` 与寻路距离场更新**完全可忽略**。
#   ⚠ 唯一要求：**所有**读上限的地方都必须走本函数，不得直接引用 `CARRY_CAPACITY`。
#     当前已全部改齐（Player 内部 4 处 + Main 的开包 / 暂停页 + Backpack 默认值 + PlaytestLog）。
#     `--verify-gear` ⑥⑦ 会断言"UI 显示值 == carry_capacity()"来钉死这一点。
func carry_capacity() -> float:
	var bonus: float = float(pack.get("load_bonus", 0.0))
	return GameConstants.CARRY_CAPACITY + bonus

# 装备中的背包提供的负重加成（0 = 没装备背包）。供 UI / 验证读取。
func pack_bonus() -> float:
	return float(pack.get("load_bonus", 0.0))

# R-83：`src` 标记伤害来源（"zombie" / "merc" / ""），**只用于试玩记录，不影响任何判定**。
#   之所以能不改所有调用点：默认参数 "" = 未知来源，旧调用方（Main 的验证探针）行为不变。
func take_damage(amount: float, src: String = "") -> void:
	if state == State.DEAD:
		return
	# R-71：护甲减伤（无甲时 reduction = 0 → 行为与改动前完全一致）
	var before: float = hp
	hp = max(0.0, hp - amount * (1.0 - armor_reduction()))
	# R-83：按**实际扣掉的血**记（已过护甲减伤），并带上来源 → 死亡原因可归因。
	PlaytestLog.note_damage_taken(before - hp, src)
	# ==== R-114 受伤闷哼 ====
	# ⚠⚠ **必须挂在 `take_damage()` 内部，不能挂 `_emit_all_signals()` / `hp_changed`**：
	#   `hp_changed` 是"属性"不是"事件" —— 装填回血、喝药回血都会发它，
	#   挂那里等于**每帧都在玩家耳边喊闷哼**。
	#   挂在 `take_damage()` 里 = 只有"真的被打了"才响，且与伤害结算严格同拍。
	# ⚠ 扣到 0 血时也响（受击反馈此刻最需要），死亡音由 `_die()` 负责。
	# ⚠ `amount <= 0` 不响（防御性：万一将来有人传 0 进来也不该有声音）。
	if amount > 0.0:
		Sfx.play("player_hurt")
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()

func add_load(weight: float) -> void:
	current_load += weight
	_update_overload_factor()
	load_changed.emit(current_load, carry_capacity(), overload_factor)

# ==== R-89：弹药盒「转为备弹」时的负重折半 ====
# 规则本体（为什么是"转换时折半"而不是"按发数计重"）写在 GameConstants.RESERVE_WEIGHT_KEEP_RATIO
#   的注释里；这里只提供**唯一入口**，让调用方（Main._use_item）不必自己算比例。
# ⚠ 为什么放在 Player 而不是 Main：这条规则改的是**负重**，而 current_load / overload_factor
#   是 Player 的私有状态。放Player 才能保证「比例常量」与「负重状态」在同一个类里，
#   将来若要加"备弹也吃负重"的完整模型，改动点也在这里。
# 返回**实际扣回的重量**（供调用方写日志 / 验证断言）。
# ⚠ 扣的是 weight × KEEP_RATIO，即**另一半永久留在玩家身上** —— 那就是"子弹带"里的重量。
#   备弹被装填消耗时（take_reserve）**不再减重**：否则"打空备弹"就成了一条刷负重的路，
#   与"负重 = 搜刮取舍"的设计意图相反（详见 GameConstants 同名常量注释里的备选 A 分析）。
func consume_ammo_box_weight(box_weight: float) -> float:
	var relieved: float = box_weight * GameConstants.RESERVE_WEIGHT_KEEP_RATIO
	add_load(-relieved)
	return relieved

# R-71：消耗品效果（使用医疗包 / 罐头 / 饮用水）
func heal(amount: float) -> void:
	if state == State.DEAD:
		return
	hp = minf(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)

func restore_stamina(amount: float) -> void:
	if state == State.DEAD:
		return
	stamina = minf(max_stamina, stamina + amount)
	stamina_changed.emit(stamina, max_stamina)

# ==== R-77：饥饿 / 口渴 ====
# 自然衰减；任一条归零 → 按各自 DPS **持续掉血**（这条伤害**不吃护甲减伤**——
# 防弹背心挡子弹不挡饿，且 armor_reduction 只该作用于战斗伤害）。
func _update_survival(delta: float) -> void:
	if state == State.DEAD:
		return
	# R-121：基地内时间冻结 → 饥饿/口渴不衰减、不因归零掉血（base-survival-npc §0.2）。
	if time_frozen:
		return
	if hunger > 0.0:
		hunger = maxf(0.0, hunger - GameConstants.HUNGER_DECAY_PER_SEC * delta)
		hunger_changed.emit(hunger, GameConstants.HUNGER_MAX)
	if thirst > 0.0:
		thirst = maxf(0.0, thirst - GameConstants.THIRST_DECAY_PER_SEC * delta)
		thirst_changed.emit(thirst, GameConstants.THIRST_MAX)
	var dps: float = 0.0
	if hunger <= 0.0:
		dps += GameConstants.STARVE_DPS
		# R-83：仅在**真的因饥饿掉血**的那一帧上报（归零前一次都不调）→ 零开销。
		PlaytestLog.note_starve_tick(delta)
	if thirst <= 0.0:
		dps += GameConstants.DEHYDRATE_DPS
		# R-83：同上，口渴归零掉血。
		PlaytestLog.note_thirst_tick(delta)
	if dps > 0.0:
		# R-83：src 按本帧实际归零的那几条给出（两条都归零 → "starve+thirst"）
		var _pt_src: String = ("starve" if hunger <= 0.0 else "") + ("+" if (hunger <= 0.0 and thirst <= 0.0) else "") + ("thirst" if thirst <= 0.0 else "")
		_survival_damage(dps * delta, _pt_src)

# 生存伤害：**绕过护甲**（与 take_damage 的唯一区别）
func _survival_damage(amount: float, src: String = "starve") -> void:
	if state == State.DEAD:
		return
	var before: float = hp
	hp = max(0.0, hp - amount)
	# R-83：生存伤害走独立入口 → 计入"受到伤害总量"与死亡原因，但**不计入"被击中次数"**。
	PlaytestLog.note_survival_damage(before - hp, src)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()

func restore_hunger(amount: float) -> void:
	if state == State.DEAD:
		return
	hunger = minf(GameConstants.HUNGER_MAX, hunger + amount)
	hunger_changed.emit(hunger, GameConstants.HUNGER_MAX)

func restore_thirst(amount: float) -> void:
	if state == State.DEAD:
		return
	thirst = minf(GameConstants.THIRST_MAX, thirst + amount)
	thirst_changed.emit(thirst, GameConstants.THIRST_MAX)

func reset_full() -> void:
	# R-144 缺陷⑯：重开必须**先**清掉陈旧的换弹状态（`is_reloading` / `_reload_pending` / `reload_t`）。
	#   原来这三样一个都不碰 → **跨局残留**：上局死亡时正在换弹的话，新一局开局就挂着"换弹中"，
	#   而且 `_reload_pending` 里的发数会卡在中间态（既不在池里也不在弹匣里）。
	#   ⚠ **位置是硬约束：必须排在 `_build_loadout()` 之前**。两个原因：
	#     ① `_cancel_reload()` 按 **当前武器口径** 决定把 `_reload_pending` 归还到哪个备弹池；
	#        `_build_loadout()` 会把 loadout 换成 [手枪, MP5]（都是 9×19）→ 放到它之后，
	#        归还口径就变成"已经换过的那把枪"，发数记错池。
	#     ② `_build_loadout()` 会**整表重建 `reserve`**（`reserve = {...}`）；放到它之后，
	#        那一笔归还会在刚重建好的新池子上凭空多出发数。
	_cancel_reload()
	hp = max_hp
	stamina = max_stamina
	hunger = GameConstants.HUNGER_START      # R-77：重开 = 生存值也满
	thirst = GameConstants.THIRST_START
	current_load = 0.0
	overload_factor = 1.0
	state = State.IDLE
	velocity = Vector2.ZERO
	aiming = false
	reset_spread()          # R-86：重开 = 散射累积也归零
	_build_loadout()
	armor = {}                 # R-71：重开 = 护甲也归零（与武器 loadout 一起复位）
	pack = {}                  # R-101：重开 = 背包也归零（负重上限回到裸装 60）
	_trigger_held = false
	_trigger_edge = false
	_cancel_feeding()          # R-144：重开 = 补给读条也复位（R 键按住时长一并清零）
	_r_hold_t = 0.0
	_r_long_fired = false
	_emit_all_signals()

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	died.emit()

# === cp2 多武器（Dictionary 表示，无 class_name 依赖） ===
# `auto` = 射击模式（R-71）：false → 单发（每按一次左键打一发）；true → 连发（按住不放持续射击）
func _make_weapon(id: String) -> Dictionary:
	if id == "smg":
		return {
			"id": "smg",
			"label": "MP5 SMG",
			"caliber": GameConstants.CAL_9X19,
			"damage": GameConstants.SMG_DAMAGE,
			"pellets": GameConstants.SMG_PELLETS,
			# R-86：散射三参数（基础总角 / 每发叠加 / 收敛速率）+ 封顶倍数。
			# 数值与 ZS 依据全部集中在 GameConstants「射击散射（R-86）」段，此处只引用。
			"spread_base_deg": GameConstants.SMG_SPREAD_BASE_DEG,
			"spread_per_shot_deg": GameConstants.SMG_SPREAD_PER_SHOT_DEG,
			"spread_recover": GameConstants.SMG_SPREAD_RECOVER,
			"pellet_cone_deg": 0.0,   # 单弹丸武器无弹型分布层
			"fire_cooldown": GameConstants.SMG_FIRE_COOLDOWN,
			"mag_size": GameConstants.SMG_MAG_SIZE,
			"reload_time": GameConstants.SMG_RELOAD_TIME,
			"bullet_speed": GameConstants.BULLET_SPEED,
			"auto": true,
		}
	# R-88：霰弹枪从通用 id `shotgun` 型号化为 `mp_133`（ZS 原 id，reference §3.5）。
	#   ⚠「霰弹枪」是**类别**、MP 133 是**型号** —— 加第二把霰弹枪时在这里**再加一个 if 分支**即可，
	#     不要把这个分支当成"霰弹枪的唯一实现"（详见 GameConstants MP133 段的 3 步说明）。
	if id == "mp_133":
		return {
			"id": "mp_133",
			"label": "霰弹枪 MP 133",
			"category": GameConstants.SHOTGUN_CATEGORY,
			"caliber": GameConstants.CAL_12X70,
			# R-88：8.5 = ZS 整枪 51 / 6 弹丸 → **一次扳机总伤 51，对齐 ZS 真值**。
			#   （若误填 51 会变成 306 总伤 —— 见 GameConstants 同名常量的口径陷阱说明）
			"damage": GameConstants.MP133_DAMAGE_PER_PELLET,
			"pellets": GameConstants.SHOTGUN_PELLETS,
			# R-86：散射三参数。这几个值当初就是**照 MP 133 真值**（精度 35 / 后坐 170）标的，
			#   R-88 把武器真身换成 MP 133 之后它们**依然成立** → 数值不动（推导见 GameConstants）。
			"spread_base_deg": GameConstants.SHOTGUN_SPREAD_BASE_DEG,
			"spread_per_shot_deg": GameConstants.SHOTGUN_SPREAD_PER_SHOT_DEG,
			"spread_recover": GameConstants.SHOTGUN_SPREAD_RECOVER,
			# ⚠ 霰弹枪独有：6 弹丸在这个固定锥角内均布（与瞄准层**独立叠加**）
			"pellet_cone_deg": GameConstants.SHOTGUN_PELLET_CONE_DEG,
			"fire_cooldown": GameConstants.MP133_FIRE_COOLDOWN,
			"mag_size": GameConstants.MP133_MAG_SIZE,
			"reload_time": GameConstants.MP133_RELOAD_TIME,
			"bullet_speed": GameConstants.BULLET_SPEED,
			"auto": false,
		}
	return {
		"id": "pistol",
		"label": "PISTOL",
		"caliber": GameConstants.CAL_9X19,
		"damage": GameConstants.PISTOL_DAMAGE,
		"pellets": 1,
		# R-86：手枪此前 spread_deg 恒为 0.0（且 `pellets > 1` 条件恒假）→ **完全没有散射**。
		#   现在基础总角来自 ZS PP Kokarev 精度 65，换算过程见 GameConstants 注释。
		"spread_base_deg": GameConstants.PISTOL_SPREAD_BASE_DEG,
		"spread_per_shot_deg": GameConstants.PISTOL_SPREAD_PER_SHOT_DEG,
		"spread_recover": GameConstants.PISTOL_SPREAD_RECOVER,
		"pellet_cone_deg": 0.0,
		"fire_cooldown": GameConstants.PISTOL_FIRE_COOLDOWN,
		"mag_size": GameConstants.PISTOL_MAG_SIZE,
		"reload_time": GameConstants.PISTOL_RELOAD_TIME,
		"bullet_speed": GameConstants.BULLET_SPEED,
		"auto": false,     # R-71：手枪 = 单发（每按一次左键一发）
	}

func _build_loadout() -> void:
	weapons = []
	ammo_list = []
	# R-74：备弹按口径分池。本函数只在 reset_full（重开 / 死亡）时调用 → **跨层下降不清零**（弹药带下楼）
	# R-89：显式预置 4 个口径的键（5.56 / 7.62 初始 0 发）。
	#   ⚠ **为什么显式写 0 而不是让 reserve_of() 走 `reserve.get(cal, 0)` 的缺省**：
	#     显示上两者没差别（都读到 0），但**写入路径**有差别 ——
	#     `add_reserve()` 会 `reserve[caliber] = ...` 动态建键，所以将来加步枪、
	#     真拿到 5.56 弹药盒时**写入本来就正常**（不依赖预置）。
	#     显式预置的价值是：① 让"这两个口径存在且为 0"成为**可断言的状态**，
	 #     而不是"键不存在"这种靠 `has()` 才能区分的隐式状态；
	 #     ② `_build_loadout` 是备弹池的**唯一初始化点**，口径清单在这里一眼可见，
	 #     将来加步枪时不会漏掉某个池子。
	#   ⚠ **不预置成"有弹药"**：5.56 / 7.62 初始必须是 0（用户拍板「初始值 0/180、0/120」），
	#     且本作本次**不加步枪**、也没有这两种口径的弹药盒 → 它们会一直是 0（见 GameConstants 诚实标注）。
	reserve = {
		GameConstants.CAL_9X19: GameConstants.START_RESERVE_9X19,
		GameConstants.CAL_12X70: GameConstants.START_RESERVE_12X70,
		GameConstants.CAL_556: 0,
		GameConstants.CAL_762: 0,
	}
	var p := _make_weapon("pistol")
	weapons.append(p)
	ammo_list.append(_load_full(p))      # 开局两把枪是"已装填"的 → 从备弹池扣
	# ==== R-101：槽 1 从「霰弹枪 MP 133」换成「MP5 冲锋枪」（用户逐字点名）====
	# 用户需求逐字：「将现有的手枪和MP5直接放在装备栏里。」
	#   → 装备栏槽 0 = 手枪、槽 1 = **MP5**（这是团队指派里 ③ 明确要求断言的一条）。
	#
	# 【为什么这一改会让 MP 133 "变成背包里的第三把枪"—— 而那正是需求要的效果】
	#   `Main._grant_starting_items()` 一直都在往背包里发一把 `mp_133`（R-88）。
	#   改动前：装备栏 = [手枪, 霰弹枪]、背包 = [MP5, 罐头, 水, 霰弹枪, 霰弹盒]
	#     → MP5 **只在背包里**，玩家要在背包里翻找它，与"装备栏放常用的两把枪"的意图相反。
	#   改动后：装备栏 = [手枪, **MP5**]、背包 = [罐头, 水, **霰弹枪**, 霰弹盒, 双肩包]
	#     → MP 133 顺理成章成为"用户拍板①里说的**多出来的武器，留在背包容器里**"的那把，
	#       可以随时拖回槽位（已由 `--verify-gear` ⑤ 覆盖）。
	#   即：**用户的装备栏需求与"多余武器留在背包"的拍板是同一件事的两面**，
	#       不需要额外新增一把枪，也不需要丢弃任何东西（数量守恒：改动前后都是 3 把枪）。
	# ⚠ 连带影响（**故意的、且已逐处同步断言**）：MP5 从"背包物品"变成"已装备"，
	#   而**已装备的枪不进 `current_load`**（`current_load` 只统计背包物品，见 `_build_loadout`）。
	#   → 开局负重由 14.3 变为 12.0（少了 MP5 的 2.3），本批新增的双肩包（1.5）再把它抬到 13.5。
	#   受影响的旧断言已按 R-100 流程同步并加注（R-101 用户需求逐字）：
	#     `--verify-item ①`、`--verify-mp133 ③`、`--verify-loadout2 ③/⑥`、`--verify-reservecap ⑥`。
	#   ⚠ **装备栏槽 1 不再是 MP 133** → `--verify-mp133` ④⑤ 里"切到槽 1 去看那把霰弹枪"
	#     的写法失效（它当年依赖的正是"开局槽 1 = mp_133"这个假设），已一并同步。
	var s := _make_weapon("smg")
	weapons.append(s)
	ammo_list.append(_load_full(s))
	weapon_index = 0
	ammo = ammo_list[0]
	reserve_changed.emit(_cur_reserve())
	_sync_weapon_sprite()          # R-123：重建装备后同步玩家精灵（开局 = 手枪）

# 从对应口径池装满一把枪：能装多少装多少（备弹不足则装不满）
func _load_full(w: Dictionary) -> int:
	var mag: int = int(w["mag_size"])
	return mini(mag, take_reserve(String(w.get("caliber", GameConstants.CAL_9X19)), mag))

func _switch_to(i: int) -> void:
	if weapons.size() == 0 or i < 0 or i >= weapons.size() or i == weapon_index:
		return
	# R-86：切枪**刻意不清零**散射累积（与换弹不同）。
	#   理由：切枪是 ~0.1s 的瞬时操作，不付任何代价。若也重置，
	#   玩家就能"手枪↔MP5 来回切"零成本刷新散射 —— 机制被完全架空。
	#   换弹要付 1.8–2.4s 的停止输出代价，所以换弹可以给重置。
	# R-84：换枪打断装填 → 先把待入膛发数还给**旧枪的口径**。
	# ⚠ 必须在 `weapon_index = i` **之前**调用 —— _cancel_reload() 靠当前武器判定口径，
	#   换完 index 再还就会还错池子（两把枪不同口径时 = 弹药凭空跨口径转移）。
	_cancel_reload()
	_save_ammo()
	weapon_index = i
	ammo = ammo_list[i]
	reload_t = 0.0
	weapon_changed.emit(weapons[i]["label"])
	ammo_changed.emit(ammo, weapons[i]["mag_size"], false)
	reserve_changed.emit(_cur_reserve())   # 换枪 → 口径可能不同，备弹读数要跟着变
	_sync_weapon_sprite()                  # R-123：换枪 → 玩家精灵换成对应武器图

func _switch_next() -> void:
	if weapons.size() == 0:
		return
	_switch_to((weapon_index + 1) % weapons.size())

func _save_ammo() -> void:
	if weapon_index >= 0 and weapon_index < ammo_list.size():
		ammo_list[weapon_index] = ammo

func give_weapon(id: String) -> bool:
	for k in weapons.size():
		if weapons[k]["id"] == id:
			return false
	# R-101：装备栏只有 2 个武器槽（用户拍板）。
	#   ⚠ **满了就返回 false，绝不 append 第三把** —— 否则会退回 R-71 的老问题：
	#   多出来的枪**不在任何 UI 里**（装备栏只画前两把、背包里也没有它），
	#   玩家既看不见也取不回来，等于凭空吞掉一件地上补给。
	#   ⚠ 返回 false 后 `WeaponPickup._try_take()` 会走它的**兜底分支**
	#   （"已拥有该枪 → 补备弹"），所以玩家的实际收益是**拿到一盒该口径的弹药**，
	#   而不是"什么也没发生"。这条链路是既有实现，本批不改。
	#   → 真正的"第 3 把枪"从今往后只会以**背包物品**的形式存在（见文件头 R-101 注释）。
	if weapons.size() >= GameConstants.GEAR_WEAPON_SLOTS:
		return false
	var nw := _make_weapon(id)
	weapons.append(nw)
	ammo_list.append(nw["mag_size"])
	weapon_index = weapons.size() - 1
	ammo = ammo_list[weapon_index]
	weapon_changed.emit(nw["label"])
	ammo_changed.emit(ammo, nw["mag_size"], false)
	reserve_changed.emit(_cur_reserve())
	_sync_weapon_sprite()          # R-123：装备新枪 → 玩家精灵换成该武器图
	return true

# 补给/补弹：从对应口径池扣（不再是凭空虚满）
func refill_weapon(id: String) -> void:
	for i in weapons.size():
		if weapons[i]["id"] == id:
			var w: Dictionary = weapons[i]
			var mag: int = int(w["mag_size"])
			var got := take_reserve(String(w.get("caliber", GameConstants.CAL_9X19)), mag - ammo_list[i])
			ammo_list[i] = mini(mag, ammo_list[i] + got)
			if i == weapon_index:
				ammo = ammo_list[i]
				ammo_changed.emit(ammo, mag, false)
			break

# === R-84：取消装填 = 把「待入膛发数」归还到对应口径的备弹池 ===
# 缺陷：`start_reload()` 已经 `take_reserve()` 把发数从池里扣走、存进 `_reload_pending`，
#   只有**正常装完**（_update_weapon 182-187）才入膛。任何**打断**（换枪 / 换武器）
#   若只置 `is_reloading = false`，那批发数就凭空消失 —— 玩家反复换枪可持续吃备弹，
#   直到手枪永久哑火。这是"弹药消耗节奏"类手感问题的头号假信号来源。
#
# ⚠ 归还必须**钳到该口径携带上限**（R-80 / RESERVE_CAP），不能直接加：
#   典型场景 —— 池子 297/300 时开始换弹（扣 12 → 285），换弹期间玩家又从弹药盒补到满池 300，
#   此时若直接 +12 会变成 312，**击穿上限**，凭空多出 12 发弹药（比吞弹更严重的作弊）。
#   所以只归还"上限之内的余量"，超出部分（理应被丢弃的溢出）不发放。
func _cancel_reload() -> void:
	var back: int = _reload_pending
	# 先清零，**防二次归还**（同一批发数被归还两次 = 凭空造弹）。
	# 顺序很重要：必须在读 _reload_pending 之后立刻清零。
	_reload_pending = 0
	is_reloading = false
	reload_t = 0.0
	if back <= 0:
		return
	var cal: String = _cur_caliber()
	var cap: int = reserve_cap_of(cal)
	var room: int = maxi(0, cap - reserve_of(cal))     # ← 上限钳制：只发得下才发
	var added: int = mini(back, room)
	if added > 0:
		reserve[cal] = reserve_of(cal) + added
	# 照 take_reserve() 的既有写法发信号，让 HUD 备弹条立刻同步（R-74 接的是同一个信号）
	reserve_changed.emit(_cur_reserve())

# 当前武器口径（无武器时兜底 9×19，与 start_reload / _load_full 的默认口径保持一致）
func _cur_caliber() -> String:
	if weapons.size() == 0 or weapon_index < 0 or weapon_index >= weapons.size():
		return GameConstants.CAL_9X19
	return String(weapons[weapon_index].get("caliber", GameConstants.CAL_9X19))

# === R-71 装备（来自背包物品） ===
# 武器：把背包里的武器装到**当前武器槽**上，返回被换下的武器 id（空串 = 原本空手）。
# 由调用方（Main）负责把换下的武器变回背包物品 → 保证"物品不凭空消失"。
func equip_weapon(weapon_id: String) -> String:
	var nw := _make_weapon(weapon_id)
	if weapons.size() == 0:
		weapons.append(nw)
		ammo_list.append(_load_full(nw))       # R-74：上膛也要从备弹池扣
		weapon_index = 0
		ammo = ammo_list[0]
		weapon_changed.emit(nw["label"])
		ammo_changed.emit(ammo, nw["mag_size"], false)
		reserve_changed.emit(_cur_reserve())
		# R-143：**空手 → 装备**这条分支原先直接 return，漏了同步 →
		#   表现为「从物品栏装备武器，玩家手上画面没变」。必须在 return **之前**同步。
		_sync_weapon_sprite()
		return ""
	var old_id: String = String(weapons[weapon_index].get("id", ""))
	# R-84：换武器打断装填 → 先把待入膛发数还给**被换下那把枪的口径**。
	# ⚠ 必须在 `weapons[weapon_index] = nw` **之前**调用 —— 口径从当前武器读，
	#   覆盖之后新旧枪口径不同就会还错池子。
	_cancel_reload()
	weapons[weapon_index] = nw
	ammo_list[weapon_index] = _load_full(nw)   # R-74：上膛从备弹池扣
	ammo = ammo_list[weapon_index]
	reload_t = 0.0
	weapon_changed.emit(nw["label"])
	ammo_changed.emit(ammo, nw["mag_size"], false)
	reserve_changed.emit(_cur_reserve())
	# R-143：换掉当前武器槽后同步玩家精灵（原先漏 → 装备后画面不跟手）
	_sync_weapon_sprite()
	return old_id

# ==== R-101：装备栏（GEAR）· 槽位定装 / 卸下 ====
# 【为什么 `equip_weapon` 之上还要另立一个 `equip_weapon_to_slot`】
#   `equip_weapon()` 装的是**当前武器槽**（`weapon_index`），那是 R-71 右键「装备」的语义：
#   "换掉我手上这把"。但 R-101 的装备栏有**两个并列的槽**，玩家拖拽时要能**指定装到哪一槽**
#   （装满时拖到槽 1 = 换掉槽 1，而不是"当前碰巧是槽 1 的那把"）。
#   两者语义不同，不能合并 —— 合并会让"拖到槽 0"在当前武器是槽 1 时悄悄装错槽。
# 返回被换下的武器 id（空串 = 该槽原本为空）。
func equip_weapon_to_slot(weapon_id: String, slot: int) -> String:
	var nw := _make_weapon(weapon_id)
	# 越界或负数 → 什么都不做（调用方负责校验槽位类型，见 Main._gear_equip）
	if slot < 0 or slot >= GameConstants.GEAR_WEAPON_SLOTS:
		return ""
	if weapons.size() > slot:
		var old_id: String = String(weapons[slot].get("id", ""))
		_cancel_reload()                    # R-84：换武器打断装填 → 先还回旧枪口径
		weapons[slot] = nw
		ammo_list[slot] = _load_full(nw)   # R-74：上膛从备弹池扣
		if weapon_index == slot:
			ammo = ammo_list[slot]
			reload_t = 0.0
			weapon_changed.emit(nw["label"])
			ammo_changed.emit(ammo, nw["mag_size"], false)
		reserve_changed.emit(_cur_reserve())
		# R-143：装到**指定槽**（拖拽到槽 0/1）后同步玩家精灵；
		#   ⚠ 即便装的是非当前槽（weapon_index != slot），也要同步 ——
		#     该槽可能是"空槽追加"以外的情况，同步是无副作用的（只读 weapons/weapon_index）。
		_sync_weapon_sprite()
		return old_id
	# 该槽为空 → 追加（`weapons` 长度因此**最多**到 GEAR_WEAPON_SLOTS）
	weapons.append(nw)
	ammo_list.append(_load_full(nw))
	weapon_index = slot
	ammo = ammo_list[slot]
	weapon_changed.emit(nw["label"])
	ammo_changed.emit(ammo, nw["mag_size"], false)
	reserve_changed.emit(_cur_reserve())
	# R-143：空槽追加（该槽成为当前武器槽）后同步玩家精灵
	_sync_weapon_sprite()
	return ""

# 卸下武器槽 `slot` 上的枪，返回它的**物品形态原型**（`""` → 空字典 = 槽本来就是空的）。
# 由调用方（Main）放进背包 —— 与 `equip_weapon` 的"换下的变回物品"约定一致。
# ⚠ **卸下时保留该枪的剩余弹量吗？—— 不保留，弹量随枪一起回到物品形态是无解的**
#   （物品形态的 Dictionary 里没有"弹匣剩余"这个字段，R-71 起就没有）。
#   这意味着"卸下再装上"会**丢掉那把枪的剩余弹量**（重新上膛从备弹池扣）。
#   这是**已知且刻意保留**的简化：真正的"枪械+弹匣"持久化需要给物品加弹量字段，
#   属于 R-71 之后的独立工作项，本批**不做**（不做比做一半更安全）。
#   ⚠ 但**上膛仍然从备弹池扣**（`_load_full`），所以"反复卸下/装上"**不会凭空造弹**
#   （只能消耗备弹）—— 方向是安全的，只是对玩家不利。
func unequip_weapon_from_slot(slot: int) -> String:
	if slot < 0 or slot >= weapons.size():
		return ""
	_cancel_reload()      # R-84：打断装填 → 把待入膛发数还给**这把枪**的口径
	_save_ammo()
	var w: Dictionary = weapons[slot]
	var out_id: String = String(w.get("id", ""))
	weapons.remove_at(slot)
	ammo_list.remove_at(slot)
	# `weapon_index` 必须跟着收缩后的下标修正，否则会指向"下一把枪"或越界
	if weapons.is_empty():
		weapon_index = 0
		ammo = 0
	else:
		weapon_index = clampi(weapon_index, 0, weapons.size() - 1)
		ammo = ammo_list[weapon_index]
		weapon_changed.emit(weapons[weapon_index]["label"])
		ammo_changed.emit(ammo, weapons[weapon_index]["mag_size"], false)
	reserve_changed.emit(_cur_reserve())
	# R-143：卸下后**当前武器**可能已经换人 / 变空手 → 必须同步玩家精灵
	#   （同一 bug 类的第三处：卸下武器而画面还举着原来那把枪）
	_sync_weapon_sprite()
	# 返回被卸下的武器 **id**（空串 = 槽本来就是空的）。
	# Main 用 `_proto_by_id(id)` 取物品形态放进背包 —— Player 不持有物品表，不该自己去查。
	return out_id

# 护甲：装上护甲，返回被换下的护甲（空 Dictionary = 原本无甲）
func equip_armor(item: Dictionary) -> Dictionary:
	var old: Dictionary = armor
	armor = {
		"id": String(item.get("id", "")),
		"label": String(item.get("label", "")),
		"reduction": float(item.get("reduction", 0.0)),
		"weight": float(item.get("weight", 0.0)),
	}
	return old

# R-101：装上背包，返回被换下的背包（空 Dictionary = 原本无背包）。
# ⚠ 与 `equip_armor` 的差别：背包**没有 `reduction`**，它给的是 `load_bonus`（负重加成）。
#   两者语义正交（一个减伤、一个扩容），所以是两个字段而不是一个"装备槽"字典 ——
#   把它们塞进同一个字典会让"换下护甲时把背包也一起清掉"这类 bug 变得容易发生。
func equip_pack(item: Dictionary) -> Dictionary:
	var old: Dictionary = pack
	pack = {
		"id": String(item.get("id", "")),
		"label": String(item.get("label", "")),
		"load_bonus": float(item.get("load_bonus", 0.0)),
		"weight": float(item.get("weight", 0.0)),
	}
	# ⚠ 负重上限变了 → 必须**重算一次超重系数并广播**。
	#   漏掉这一步的后果：玩家穿双肩包后 `load_changed` 的 capacity 仍是旧值，
	#   HUD 的负重条与暂停页会**显示 60**（而实际判定已按 80），又是一次"静默不一致"。
	#   `--verify-gear` ⑥⑧ 专门钉死"装备后 UI 显示与 carry_capacity() 一致"。
	_update_overload_factor()
	load_changed.emit(current_load, carry_capacity(), overload_factor)
	return old

func armor_reduction() -> float:
	return clampf(float(armor.get("reduction", 0.0)), 0.0, 0.9)

func _emit_all_signals() -> void:
	hp_changed.emit(hp, max_hp)
	stamina_changed.emit(stamina, max_stamina)
	hunger_changed.emit(hunger, GameConstants.HUNGER_MAX)
	thirst_changed.emit(thirst, GameConstants.THIRST_MAX)
	load_changed.emit(current_load, carry_capacity(), overload_factor)
	if weapons.size() > 0:
		ammo_changed.emit(ammo, weapons[weapon_index]["mag_size"], false)
		weapon_changed.emit(weapons[weapon_index]["label"])

func get_state() -> int:
	return state
