# Zombie · CharacterBody2D · cp2 阶段（R-62 阵营/目标 + R-73 双轴感知 + Alert/Search/脱战）
# FSM：IDLE ─(感知命中)→ ALERT(0.4s 停步/转向) → CHASE → ATTACK ─(收招)→ CHASE
#      CHASE ─(两轴失联 > LoseTargetTime)→ SEARCH(前往最后已知位置 → 原地扫视)→ IDLE
# 感知（enemies-ai §4.1 · R-19 双轴）：
#   视觉 Visual = 距离 < visual_range 且 **LOS 通**（隔墙看不见）
#   听觉 Auditory = 距离 < audio_range × 玩家噪声修正（**不要求 LOS**，隔墙听得见）
#   任一轴命中 = 感知到；两轴都不命中且持续 → 丢目标
# 数值：依据 enemies-ai §3.2 / §4.1（⚠ 待实测校准）
# 阵营：僵尸 = 「亡灵」阵营；敌对目标 = 玩家 + 敌对阵营（雇佣兵）；同阵营不互打
extends CharacterBody2D
class_name Zombie

signal died

enum State { IDLE, ALERT, CHASE, SEARCH, ATTACK, DEAD }

const NavGrid := preload("res://scripts/nav/NavGrid.gd")
const LosUtil := preload("res://scripts/world/LosUtil.gd")

# ==== R-148 · 敌人精灵接入（照 `Crate.gd:86-127` 的既有模式，不自创）====
#   tscn 里那个 Polygon2D（名 `Sprite`）**保留不动**当兜底；运行时 `Sprite2D.new()`
#   起名 `EnemyArt` 挂上去，纹理到位 → 精灵可见 + 色块隐藏；纹理缺失 → 降级回色块。
#   ⚠「精灵与色块同时可见」是**禁止**的（会造成双重外观）。
#   ⚠ `Crate.tscn` 同理：`Zombie.tscn` / `Mercenary.tscn` / `Brute.tscn` **零改动**
#     （12×12 碰撞盒、collision_layer/mask、节点名 全部原封不动 = 少一个回归面）。
# ==== R-153 · 僵尸 4 方向图集精灵（推翻 R-145 单帧+rotation）====
#   资产：`char_zombie_{idle,move,hit,death,attack_tell,melee}.png`（6 张图集，每图集 4 行朝向）。
#   行序（与 NPC 艾拉 / R-51 约定一致）：0=背(up) / 1=右(right) / 2=正(down) / 3=左(left)。
#   列=帧，每格 64×64；`rotation` 角 → 行（见 `_dir_row`），**不再用 flip_v** 翻面。
#   ⚠ 子类（Brute/Merc/Splitter）不覆写 `enemy_atlas_prefix()` → 继承空串 → 继续单帧旧路径，零改动。
#   ⚠ 旧 `zombie.png`（16×16 占位）保留：① `--verify-enemy-sprite` ① 的 16×16 兼容性锚点；
#     ② 纹理缺失时的单帧降级兜底（见 `_refresh_art`）。
const ENEMY_ART_NODE := "EnemyArt"
const ENEMY_SPRITE_DIR := "res://assets/sprites/enemies/"
# R-153：图集参数（与 `char_zombie_meta.json` 对齐）。
const ENEMY_ATLAS_FRAME := 64
# 显示缩放：64×64 单格 → **48×48 世界占位**（杂兵类体型）。
#   ⚠ 图集单格是 64×64（16px 基准的 4× 细粒度画布），1:1 显示会占 64px ≈ 4 格 = 巨型化
#     （2026-10-13 截图反馈）⇒ 必须缩放；0.75 = 48 ÷ 64，Nearest 采样保持像素感。
#   ⚠⚠ **0.75 是用户 2026-10-22 明确要求的值，不要再改回 0.375**。
#     2026-10-23 曾因「历史注释自述 0.375 / 24×24」把常量改成 0.375，已被用户推翻 ——
#     错的**是那些过期注释，不是常量**。本轮已把全项目的 0.375 叙事统一更正为 0.75：
#       · 杂兵（本类）：0.75 → 48×48
#       · Splitter(Boss) = 本类 ×2 → **1.5** → 96×96（见 `Splitter.gd:109`）
#       · `Main.gd` `--verify-enemy-sprite` ④ / `--verify-splitter` ② 的期望值同步更正。
#     同类取向佐证：`BaseNpc.gd:24` `ATLAS_SCALE := 0.75`（用户 2026-10-22 要求）。
const ENEMY_ATLAS_SCALE := 0.75   # 64×64 单格 × 0.75 = 48×48 世界占位；Splitter(Boss) = 本类 ×2 = 1.5
const ENEMY_ATLAS_NAMES := ["idle", "move", "hit", "death", "attack_tell", "melee"]
const ENEMY_ATLAS_FRAMES := {
	"idle": 4, "move": 6, "hit": 2, "death": 6, "attack_tell": 3, "melee": 4,
}
const ENEMY_ATLAS_FPS := {
	"idle": 6.0, "move": 10.0, "hit": 12.0, "death": 8.0, "attack_tell": 8.0, "melee": 12.0,
}
const ENEMY_MELEE_SHOW := 0.12   # 攻击命中后 melee 图集续帧时长（跟随挥击），不影响 FSM 时序
var _atlases := {}               # name -> Texture2D（图集集）
var _current_atlas := ""         # 当前显示的图集名
var _facing_row: int = 1         # 朝向行（默认朝右 = rotation 0）
var _anim_frame: int = 0         # 当前帧（列）
var _anim_t: float = 0.0         # 帧推进累加器
var _melee_t: float = 0.0        # melee 续帧计时

@export var move_speed: float = GameConstants.ZOMBIE_SPEED
@export var attack_range: float = GameConstants.ZOMBIE_ATTACK_RANGE
@export var visual_range: float = GameConstants.ZOMBIE_VISUAL_RANGE
@export var audio_range: float = GameConstants.ZOMBIE_AUDIO_RANGE
@export var attack_windup: float = GameConstants.ZOMBIE_ATTACK_WINDUP
@export var attack_recovery: float = GameConstants.ZOMBIE_ATTACK_RECOVERY
@export var attack_interval: float = GameConstants.ZOMBIE_ATTACK_INTERVAL
@export var max_hp: float = (GameConstants.ZOMBIE_HP_MIN + GameConstants.ZOMBIE_HP_MAX) / 2.0  # 中值 70
@export var damage: float = (GameConstants.ZOMBIE_DAMAGE_MIN + GameConstants.ZOMBIE_DAMAGE_MAX) / 2.0  # 中值 16.5

var faction: int = GameConstants.FACTION_UNDEAD
var hp: float = max_hp
var state: int = State.IDLE
var target: Node2D = null       # 当前敌对目标（玩家 或 敌对阵营）
var attack_cd: float = 0.0
var windup_t: float = 0.0
var dead: bool = false
var _flash: float = 0.0
# ==== R-87 受击硬直（hit stagger · 局部顿帧）====
# 语义：受击时置位 ENEMY_STAGGER_TIME，期间这只僵尸**冻结**（不动、不推进攻击前摇）。
# ⚠ 绝不使用 Engine.time_scale（见 GameConstants 注释）—— 全局顿帧会连带冻住玩家与子弹。
var _stagger: float = 0.0
var _sense_t: float = 0.0       # 目标重扫节流
# QA N1 修复：空闲（无目标）时不得绕过节流每帧重扫 → 只有"上一帧持有、本帧失效"才强制立即重扫
var scan_calls: int = 0         # 重扫次数计数（验证探针：证明走的是 0.3s 节流而不是每帧）
# R-73 感知 / 脱战探针（供 headless 验证读取，避免只直调内部函数）
var sensed: bool = false            # 本帧双轴是否命中
var last_known: Vector2 = Vector2.ZERO  # 最后已知位置（Search 目标点）
var _last_sense_los: bool = false   # 上一次命中是否来自视觉轴（LOS 通）
var _alert_t: float = 0.0           # Alert 剩余时长
var _lose_t: float = 0.0            # 当前脱战累计时长
var _lose_dur: float = GameConstants.ENEMY_LOSE_TARGET_TIME  # 本目标脱战阈值（仅听觉触发 → 减半）
# ==== R-95 失联惯性前进（last-seen lunge）====
# 用户需求：「僵尸类敌人，玩家离开视野后不要停在原地，而是按照玩家离开视野时的方向继续前进2秒钟」
# 旧行为：CHASE 一旦 sensed==false 立刻 velocity=ZERO **驻足**最长 LoseTargetTime（4s / 仅听觉 2s）
#   → 玩家绕墙跑掉时僵尸"定格"，观感是 bug（它上一帧明明还在全速扑过来）。
# _lunge_dir：失联**那一帧**缓存的方向（见 _arm_lunge）。⚠ 刻意**只取一次**，之后每帧不再重取。
var _lunge_t: float = 0.0
var _lunge_dir: Vector2 = Vector2.ZERO
var _search_phase: int = 0          # 0=前往最后已知位置 1=原地扫视
var _search_t: float = 0.0
# ==== R-146：出生点徘徊 ====
# 用户逐字：「增加敌人徘徊的行为。敌人有一半的时间会在出生点附近徘徊。」
# ⚠ **只在 IDLE 生效**：ALERT/CHASE/SEARCH/ATTACK 各有自己的移动语义，不叠加徘徊。
#   `Brute` 通过继承自动获得本行为，无需重复实现。
var _spawn_home: Vector2 = Vector2.ZERO   # 出生点（_ready 时锁定，全程不变）
var _wander_ph: float = 0.0               # 占空比相位(0..PERIOD)，**不用每帧掷骰**
var _wander_tgt: Vector2 = Vector2.ZERO   # 本段徘徊的目标点
var wander_active: bool = false           # 当前是否在徘徊（供 headless 验证读）
var _wander_has_tgt: bool = false         # 是否已选定当前目标点（到点后才换）
var _wander_reach_t: float = 0.0          # 到点后的**停顿**计时（不是"目标有效"标志）
var _wander_frame: bool = false           # 本帧是否在徘徊（供 move_and_slide 之后的硬边界用）
var _wander_stall_t: float = 0.0          # 停滞累计时长（到阈值就换目标点）
var _wander_prev_pos: Vector2 = Vector2.ZERO  # 上一帧位置（用于算本帧位移）
var _wander_tgt_count: int = 0             # 已取过几个目标点（换点时用黄金角步进避免重复方向）

@onready var sprite: Polygon2D = $Sprite

func _ready() -> void:
	add_to_group("enemies")
	# R-146：出生点在 `_ready` 锁定。用 `position`（父容器局部坐标）而非
	#   `global_position`：`enemies_container` 本身不做偏移，两者等价，
	#   但局部坐标让"离出生点多远"的判定不依赖容器变换。
	_spawn_home = position
	_wander_prev_pos = position
	# 相位起点取**确定性伪随机**（按 instance id 派生）而非真随机：
	#   同一层里所有僵尸都用同一个相位 = 整批同时徘徊/同时静止，看起来很假。
	_wander_ph = fposmod(float(get_instance_id() % 997) * 0.37, GameConstants.ENEMY_WANDER_PERIOD)
	_scan()
	_refresh_art()      # R-148：精灵接入（色块 -> 程序化精灵）

func _physics_process(delta: float) -> void:
	if dead or state == State.DEAD:
		return

	# R-146：**每帧开头**复位"本帧在徘徊"标志。
	#   ⚠ 为什么不放在 `_update_wander()` 里复位：ALERT/CHASE/SEARCH/ATTACK **根本不会调用**
	#     `_update_wander()`，那只在 IDLE 里调用 ⇒ 标志会**继承上一帧的 true**，
	#     于是追击中的僵尸也被半径硬边界夹住（跑不掉）。必须在这里无条件清。
	_wander_frame = false

	# 受击高亮衰减（cp1 占位反馈）
	# R-148：改走 `_apply_flash()` —— 接入后**可见的是 EnemyArt**，只调色块会"打不亮"。
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta)
		_apply_flash(true)
	else:
		_apply_flash(false)

	# 双轴感知重扫：节流到期 或 目标失效 → 重判
	_sense_t -= delta
	var target_gone := target == null or not is_instance_valid(target) or target.is_queued_for_deletion()
	# ⚠⚠ R-new 修复（用户实机报错 Zombie.gd:218 "previously freed"）：
	#   原条件 `(target_gone and _had_target)` 有**死引用窗口** —— `_had_target` 记录的是
	#   "上一帧 target 是否有效"，target 连续失效时它变 false → 持有失效 target 的帧
	#   **不再触发重扫** → 死引用存活到节流到期（ENEMY_SENSE_INTERVAL 0.3s ≈ 18 帧），
	#   期间任何无守卫访问都报 "previously freed"。target 可以是敌对阵营敌人
	#   （_scan 候选含非同 faction 的 enemies 组成员），其死亡即触发该窗口。
	#   改为 `(target != null and target_gone)`：**持有一个失效目标就立即重扫**；
	#   target==null（从来没有 / 刚失去）时不触发 —— 避免空闲期每帧全组遍历（QA N1）。
	if _sense_t <= 0.0 or (target != null and target_gone):
		_scan()

	attack_cd = max(0.0, attack_cd - delta)

	# ==== R-87 受击硬直：局部顿帧 ====
	# 硬直期间这只僵尸**冻结**：velocity 归零（停下）、不跑状态机（= windup_t 不推进）。
	#   刻意 early-return 到 move_and_slide() 之前 —— 保证位移严格为 0（--verify-stagger ①）。
	# ⚠ 为什么「冻结 windup」而不是「打断/重置 windup」：
	#   重置 windup_t = 每次受击都把 0.2s 前摇从头再来 → SMG 0.075s 一发可以**永久钉死**
	#   这只僵尸的攻击（每次命中都重置，windup 永远归不了零）= 该敌人永久无敌，
	#   围攻时平衡直接崩。冻结只延迟、不重置 → 单次硬直最多推迟 0.12s（< 0.2s 前摇），
	#   攻击**一定会打出来**（--verify-stagger ⑤ 断言"硬直结束后仍能打出伤害"）。
	# ⚠ 为什么 velocity 必须显式归零：ATTACK/ALERT 状态本身 velocity 就是 ZERO，
	#   但 CHASE/SEARCH 下僵尸正在推进，不归零就会"滑行"（看起来没停住）。
	# ⚠ 闸门刻意放在 attack_cd 递减**之后**：攻击冷却照常走完，不被硬直拖慢
	#   （否则连续硬直会累积成"僵尸永远攻不出来"，那是隐式削弱，不是打击感）。
	if _stagger > 0.0:
		_stagger = max(0.0, _stagger - delta)
		velocity = Vector2.ZERO
		# ==== QA BUG-04 修复：僵直期间**必须**跑外观更新，只是不跑 FSM ====
		#   `_atlas_for_state()` 见 `_flash > 0` 就返回 `hit`，而 `_flash` 与 `_stagger`
		#   在 `take_damage()` 里**同帧起表、同长度**（`_flash = 0.12` /
		#   `_stagger = ENEMY_STAGGER_TIME = 0.12`）⇒ 原 early-return 让 `hit` 图集
		#   **一帧都显示不出来**（实测 B3 逐帧 f0..f13 恒 `atlas='move'`），
		#   受击反馈退化成「只有变色、没有姿态」。
		#   ⚠ 与 `:263-264` 末尾那对调用**完全同序、同参**，不新增第三种外观口径。
		#   ⚠⚠ 只补外观，**绝不**在此补 FSM / windup / move_and_slide ——
		#      `--verify-stagger` ①（位移严格为 0）与 ⑤（硬直结束后仍能打出伤害）
		#      两条断言依赖本分支的 early-return 语义，动它们必红。
		_sync_art_facing()
		_update_art_animation(delta)
		return

	match state:
		State.IDLE:
			velocity = Vector2.ZERO
			if sensed:
				_enter_alert()
			else:
				# ==== R-146：出生点徘徊（用户「敌人有一半的时间会在出生点附近徘徊」）====
				# ⚠⚠ **绝不新增 FSM 状态**：`Main.gd:4235/4263/7078/7142/7198` 按**数字**
				#   引用 `state == 3`(SEARCH) / `0`(IDLE) / `2`(CHASE) / `4`(ATTACK)。
				#   往 enum 尾部插 WANDER 不会错位，但任何**重排**都会静默破坏那 5 处断言
				#   （state 值错位不报错、只让断言测错东西 —— 最坏的一类 bug）。
				#   ⇒ 徘徊做成 **IDLE 内部的子行为**：`state` 恒为 0，语义不变、断言不变。
				_update_wander(delta)
		State.ALERT:
			velocity = Vector2.ZERO                 # 停步
			if target != null and is_instance_valid(target):
				_face(target.global_position)       # 转向
			if sensed:
				_lose_t = 0.0
				_alert_t -= delta
				if _alert_t <= 0.0:
					state = State.CHASE
			else:
				_lose_t += delta                    # 失联：计满 LoseTargetTime 才转 Search（GDD §4.1）
				if _lose_t >= _lose_dur:
					_enter_search()
		State.CHASE:
			if not sensed:
				# ==== R-95 失联惯性前进 ====
				# ⚠ 起表条件用 `_lose_t <= 0.0`（**自增之前**判）= "本段失联的第一帧"，
				#   而**不是** `_lunge_t <= 0.0` —— 后者会在惯性走完后的下一帧再次起表 → 无限扑。
				#   每次重新感知都把 _lose_t 归零，所以"第一帧"判定天然自复位。
				if _lose_t <= 0.0:
					_arm_lunge()
				_lose_t += delta
				if _lunge_t > 0.0:
					_lunge_t = maxf(0.0, _lunge_t - delta)
					velocity = _lunge_dir * move_speed   # 按离开视野时的方向继续扑
				else:
					velocity = Vector2.ZERO             # 惯性走完 → 驻足，等转 Search
				if _lose_t >= _lose_dur:
					_enter_search()
			else:
				_lose_t = 0.0
				_lunge_t = 0.0                          # 重新感知 → 惯性立即作废（不傻走）
				_lunge_dir = Vector2.ZERO
				# ⚠⚠ R-new 修复（用户实机报错）：target 可能在本帧 scan 之后、走到这里之前
				#   已被释放（敌对敌人同物理帧死亡 → 帧末实删，而本节点 scan 节流 0.3s 内不重扫）
				#   → 无守卫访问 `target.global_position` 报 "previously freed"。
				#   与 ALERT(188) / ATTACK(231) 分支同款守卫；失效 → 转入搜索（FSM 合法降级）。
				if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
					_enter_search()
				else:
					var d := target.global_position - global_position
					if d.length() <= attack_range and attack_cd <= 0.0:
						state = State.ATTACK
						windup_t = attack_windup
					else:
						velocity = _chase_dir(d) * move_speed
		State.SEARCH:
			_search_step(delta)
		State.ATTACK:
			velocity = Vector2.ZERO
			windup_t -= delta
			if windup_t <= 0.0:
				if target != null and is_instance_valid(target) and target.has_method("take_damage"):
					var d2 := target.global_position - global_position
					if d2.length() <= attack_range + 6.0:
						# R-83：把伤害来源标成 "zombie"，供试玩记录做死亡原因归因。
						#   第 2 参只用于记录，不参与伤害计算；target 也可能是敌对阵营
						#   （那种 take_damage 是敌人自己的单参版本）→ 必须只在打玩家时传。
						if target.is_in_group("player"):
							target.take_damage(damage, "zombie")
						else:
							target.take_damage(damage)
				attack_cd = attack_interval
				_melee_t = ENEMY_MELEE_SHOW         # R-153：命中瞬间续一截 melee 图集（跟随挥击，不影响 FSM）
				state = State.CHASE                 # 收招后直接回 Chase（保留既有的攻击节奏）

	move_and_slide()
	# R-146：徘徊半径的最终硬边界（必须在移动**之后**）。
	#   ⚠ 其它状态一律不受影响 —— 本函数对非徘徊帧直接 return。
	_clamp_wander_radius()
	# R-148：每帧调一次（照 `Player._update_weapon()` 末尾调 `_sync_weapon_facing()`），
	#   覆盖**所有** rotation 赋值分支 —— 不依赖调用方记得同步。
	_sync_art_facing()
	_update_art_animation(delta)                    # R-153：图集帧动画 + 朝向（仅图集模式有作用）

# ==== R-146：出生点徘徊（IDLE 内部子行为，不新增 FSM 状态）====
# 【为什么用「相位计时器」而不是每帧掷骰 —— 两条理由】
#   ① 用户说的是「**一半的时间**」= **时间占比**语义。每帧 50% 概率在数学上等价，
#      但实测方差极大（一个 4s 周期可能全是静止也可能全是徘徊），而相位计时器
#      **每个周期严格 50%**，且 headless 可精确断言。
#   ② 掷骰要消耗 `randi()`，在 headless 里不可复现 → 验证只能写"大概率"这种
#      无法证伪的断言。相位法让 `--verify-enemywave` ③ 能钉死占空比。
func _update_wander(delta: float) -> void:
	var period: float = GameConstants.ENEMY_WANDER_PERIOD
	_wander_ph = fposmod(_wander_ph + delta, period)
	# 前 DUTY 段徘徊、其余静止（周期 4s：0~2s 游走、2s~4s 站定）
	var should: bool = _wander_ph < period * GameConstants.ENEMY_WANDER_DUTY
	if not should:
		wander_active = false
		_wander_frame = false
		velocity = Vector2.ZERO
		_wander_reach_t = 0.0
		_wander_has_tgt = false
		return
	wander_active = true
	_wander_frame = true
	if _wander_reach_t > 0.0:
		_wander_reach_t -= delta             # 到点后的停顿倒计时
	if not _wander_has_tgt:
		_pick_wander_target()
	# ==== R-146 停滞检测（真实缺陷修复，不是为了迁就测试）====
	#   ⚠ **为什么必须有**：目标点是**随机**取的 ⇒ 可能落在墙的另一侧 / 家具里。
	#     僵尸会顶着障碍物推，`to_t` 永不变小 → **整个徘徊段位移恒为 0**。
	#     实测症状：占空比 0.500 完美、速度 20.3 正常，但离出生点最大距离 = 0.0。
	#     没有这一段，敌人看起来就是"站在原地抽搐" —— 那是坏手感，不是"一半时间静止"。
	#   判定：想动却几乎没动，累计超过阈值就换一个目标点。
	#   ⚠ 阈值 0.35px **必须小于**单帧位移（1/60 × 20.25 = 0.34px 附近）——
	#     反过来调大就会把正常移动误判成卡住，导致每 0.4s 疯狂换点（原地抖动）。
	if position.distance_to(_wander_prev_pos) < 0.30:
		_wander_stall_t += delta
		if _wander_stall_t >= 0.4:
			_pick_wander_target()
			_wander_stall_t = 0.0
	else:
		_wander_stall_t = 0.0
	_wander_prev_pos = position
	var to_t := _wander_tgt - position
	if to_t.length() < 3.0:
		velocity = Vector2.ZERO
		_wander_has_tgt = false              # 到点 → 下一帧重新取点
		_wander_reach_t = 0.5                # 停顿 0.5s（避免"到点即换"看起来像抽搐）
	else:
		velocity = to_t.normalized() * move_speed * 0.45   # 徘徊比追击慢（0.45x），观感更"懒"
	# ⚠ 这里的夹取是**移动前**的，属"提前纠正方向"；真正的硬边界在 `move_and_slide()`
	#   **之后**补（见 `_physics_process` 末尾 `_clamp_wander_radius()`）——
	#   只做移动前夹取会被这一帧的位移顶出半径（实测多顶出 0.3px/帧）。
	if position.distance_to(_spawn_home) > GameConstants.ENEMY_WANDER_RADIUS:
		position = _spawn_home + (position - _spawn_home).normalized() * GameConstants.ENEMY_WANDER_RADIUS
		velocity = (_spawn_home - position).normalized() * move_speed * 0.45

# R-146：在出生点半径内取一个新的徘徊目标点。
#   ⚠ **确定性伪随机，绝不用 `randi()`** —— 同一条理由见 `_ready()` 注释：
#     敌人数量现在按层不同，掷骰会消耗全局随机流、且 headless 不可复现。
#   `+ _wander_tgt_count * 2.399`：黄金角步进，保证连续取到的点**不重复**同一个方向
#     （纯 `_wander_ph` 在停滞重取时会拿到完全相同的角 ⇒ 换点等于没换）。
func _pick_wander_target() -> void:
	var ang: float = fposmod(float(get_instance_id() % 360) * 0.017 + _wander_ph + float(_wander_tgt_count) * 2.399, TAU)
	_wander_tgt = _spawn_home + Vector2(cos(ang), sin(ang)) * (GameConstants.ENEMY_WANDER_RADIUS * 0.6)
	_wander_has_tgt = true
	_wander_tgt_count += 1

# R-146：徘徊硬边界的**最终**执行点（必须在 `move_and_slide()` 之后调用）。
#   为什么不放在 `_update_wander` 里：那里 `move_and_slide()` 还没跑，
#   这一帧的位移会把刚夹回去的位置重新顶出去 ⇒ 半径约束被绕过。
#   只在"本帧确实在徘徊"时生效 ⇒ **绝不影响** CHASE/SEARCH/ATTACK 的正常移动。
func _clamp_wander_radius() -> void:
	if not _wander_frame:
		return
	var off := position - _spawn_home
	if off.length() > GameConstants.ENEMY_WANDER_RADIUS:
		position = _spawn_home + off.normalized() * GameConstants.ENEMY_WANDER_RADIUS

# 追击方向：目标是玩家时走「流场」（NavGrid，绕墙/穿门）；敌对阵营目标用直线 + 滑动
func _chase_dir(to_target: Vector2) -> Vector2:
	if target != null and target.is_in_group("player"):
		var dir := NavGrid.flow_dir(global_position)
		if dir != Vector2.ZERO:
			return dir
	return to_target.normalized()

func _face(pos: Vector2) -> void:
	var v := pos - global_position
	if v.length_squared() > 0.0001:
		rotation = v.angle()
	# R-148：朝向一变就同步 flip_v（不只在 `_physics_process` 末尾同步 ——
	#   那样 headless 直接调 `_face()` 的验证入口会读到**上一帧**的 flip_v）。
	_sync_art_facing()

# ==== R-148 · 敌人精灵接入（照 `Crate.gd` 既有模式）====

# 本敌人的精灵纹理路径（**纯函数**，便于 `--verify-enemy-sprite` ⑤ 逐字断言）。
#   ⚠ 子类（`Brute.gd` / `Mercenary.gd`）只需覆写这一个函数即可换图，无需复制接入逻辑。
func enemy_sprite_path() -> String:
	return ENEMY_SPRITE_DIR + "zombie.png"

# R-153：图集前缀（非空 = 走 4 方向图集；空串 = 走单帧旧路径）。
#   ⚠ **只在本类覆写**为 `char_zombie`；Brute/Merc/Splitter 不覆写 → 继承空串 → 继续用各自单帧图，零回归。
func enemy_atlas_prefix() -> String:
	return ENEMY_SPRITE_DIR + "char_zombie"

# 刷新外观（三态互斥，与 `Crate._refresh_art()` 同款）：
#   ① 纹理到位 → Sprite2D(EnemyArt) 可见 + tscn 的 Polygon2D `Sprite` **隐藏**；
#   ② 纹理缺失（未 import / 路径写错）→ **可见地降级**回色块，而不是画一片空白
#      （与 TileGround / StaticFloor 的「坏数据要看得见」同一取舍）。
#   ⚠ 「精灵与色块同时可见」是**禁止**的（双重外观）。
#   ⚠ 用 `get_node_or_null` 而非 `$Sprite`：手工 `new` 出来、没挂 tscn 结构的敌人不崩。
#   ⚠ R-153 双模式：`enemy_atlas_prefix()` 非空 → 图集（4 行朝向 + 帧动画）；
#     空串 → 单帧旧路径（Brute/Merc/Splitter）。
func _refresh_art() -> void:
	var fallback := get_node_or_null("Sprite") as Polygon2D
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	var prefix := enemy_atlas_prefix()
	if prefix != "":
		# ---- R-153：图集模式 ----
		_atlases.clear()
		var ok := true
		for nm in ENEMY_ATLAS_NAMES:
			var t := load(prefix + "_" + nm + ".png") as Texture2D
			if t == null:
				ok = false
			_atlases[nm] = t
		if not ok:
			# 任一图集缺失 → 降级回色块（与单帧缺失同款取舍）
			if art != null:
				art.visible = false
			if fallback != null:
				fallback.visible = true
			return
		if art == null:
			art = Sprite2D.new()
			art.name = ENEMY_ART_NODE
			# asset-spec §0：origin = 体心。本引擎零 YSort + 实体 rotation，
			#   `centered=true` / `offset=(0,0)` 才能让精灵绕体心旋转而不是绕左上角。
			art.centered = true
			art.offset = Vector2(0, 0)
			add_child(art)
		art.region_enabled = true
		art.flip_v = false
		art.scale = Vector2(ENEMY_ATLAS_SCALE, ENEMY_ATLAS_SCALE)   # R-new：64×64 → 24×24 世界占位（杂兵体积 +50%）
		art.rotation = -rotation    # 反向旋转：朝向全靠行选择表达，子精灵不随体旋转（见 _sync_art_facing）
		_current_atlas = "idle"
		art.texture = _atlases["idle"]
		_facing_row = _dir_row(rotation)
		_anim_frame = 0
		_anim_t = 0.0
		_apply_art_cell()
		art.visible = true
		if fallback != null:
			fallback.visible = false
		return
	# ---- 单帧旧模式（Brute/Merc/Splitter）----
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
		art.centered = true
		art.offset = Vector2(0, 0)
		add_child(art)
	art.texture = tex
	# ==== 单帧路径（Brute 等 16×16 单帧图）：**刻意不设 scale** ====
	#   单帧图的源尺寸即世界尺寸（brute.png 16×16 → 16px），不参与图集的 0.75 缩放。
	#   ⚠ 2026-10-23 曾在此处派生缩放（把 Brute 拉到与杂兵同尺寸），但该改动建立在
	#     `ENEMY_ATLAS_SCALE = 0.375` 这一**已被用户推翻**的前提上；按 0.75 派生会把 16px 源图
	#     放大 3×，观感未经验证 ⇒ 回退到改动前的既有行为，不做无把握的体型变更。
	#   （是否要让单帧敌人与杂兵同尺寸，属独立的体型决策，另行确认后再改。）
	#   ⚠ 不碰 `Mercenary.gd`：它 `extends CharacterBody2D`（**不是** Zombie 子类），
	#     有自己的 `_refresh_art()`，走不到本分支。
	art.region_enabled = false       # 单帧图 = 整图即一格，region 必须关（否则沿用图集模式的旧 region）
	art.visible = true
	if fallback != null:
		fallback.visible = false

# 受击高亮打到**真正可见的那个**。
#   ⚠ 接入后可见的是 `EnemyArt`；只调色块 modulate 会变成「打不亮」（色块已被隐藏）。
#   两处都设是为了**降级态**（纹理缺失时可见的是色块）也不丢反馈 —— 二者互斥可见，
#   不会叠加成"双重高亮"。
func _apply_flash(on: bool) -> void:
	var c := Color(1.6, 1.6, 1.6) if on else Color(1, 1, 1)
	if sprite != null and is_instance_valid(sprite):
		sprite.modulate = c
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	if art != null:
		art.modulate = c

# 朝左时同步朝向（asset-spec §0 铁律，照 `Player._sync_weapon_facing()`）。
#   【图集模式（R-153）】按 `rotation` 角取朝向行（见 `_dir_row`）→ 4 行朝向直接表达
#     左/右/上/下，left 行是 right 行的显式水平镜像（R-51 约定），**不翻面**（避免 180° 把上下颠倒）。
#   【单帧旧模式（Brute/Merc/Splitter，继承空串）】仍用 `flip_v`：rotation≈180° 时引擎做的是
#     rotate180(img) = **上下颠倒**；Sprite2D 的 flip 先于父节点 rotation 生效 ⇒
#     rotate180( flip_v(img) ) == flip_h(img) = 「头朝左、身子正立」的正确镜像。
#   ⚠⚠ **不得以「剪影对称」省掉朝向表达**：alpha 剪影对称 ≠ 整图 rgba 对称
#     （顶部受光是有意的体积感）→ 少了朝向行/flip_v，朝左的僵尸明暗会上下翻。
#   ⚠ 恰 ±90° 是镜像不连续点（`rotation` 是 float32，`PI` 是 float64，R-143 踩过）
#     ⇒ 验证只在 0° / 180° / 135° / 45° / -135° / -45° 断言，不在边界上测浮点舍入。
func _sync_art_facing() -> void:
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	if art == null:
		return
	if enemy_atlas_prefix() != "":
		# R-153：图集模式 → 按 rotation 角取朝向行（不翻面）
		#   ⚠⚠ EnemyArt 是本节点的**子节点**，会继承体的 `rotation`；图集模式的朝向**已由行选择表达**，
		#     子精灵必须**反向旋转归正**（否则 = 行 + 体旋转双重朝向，实测截图僵尸"横躺"）。
		#     单帧模式仍靠「继承体旋转 + flip_v」（R-145 语义，勿动）。
		_facing_row = _dir_row(rotation)
		art.flip_v = false
		art.rotation = -rotation
		_apply_art_cell()
	else:
		# 单帧旧模式 → flip_v 翻面（与 R-145 同款）
		art.flip_v = absf(rotation) > PI * 0.5

# ==== R-153 · 图集帧动画 + 朝向行映射（仅图集模式）====
# 每物理帧推进：按状态选图集 → 按帧率推进列 → 按 rotation 映射行。
#   ⚠ `_sync_art_facing()` 已把 `_facing_row` 写好；本函数只推进列帧并合成 region_rect。
#   ⚠ 状态切图集时重置到 0 帧，保证每个状态从首帧起播。
func _update_art_animation(delta: float) -> void:
	if enemy_atlas_prefix() == "":
		return                                   # 单帧旧模式：无帧动画
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	if art == null or not art.visible:
		return
	_melee_t = maxf(0.0, _melee_t - delta)        # melee 续帧计时（命中后短暂）
	var nm := _atlas_for_state()
	if nm != _current_atlas:
		_current_atlas = nm
		_anim_frame = 0
		_anim_t = 0.0
		art.texture = _atlases[nm]
	var fps := float(ENEMY_ATLAS_FPS.get(nm, 8.0))
	_anim_t += delta
	var fr := 1.0 / fps
	while _anim_t >= fr:
		_anim_t -= fr
		_anim_frame += 1
	var frames := int(ENEMY_ATLAS_FRAMES.get(nm, 1))
	if frames > 0:
		_anim_frame = _anim_frame % frames        # 循环（death 也循环；`_die` 当帧 free 故无观感问题）
	_apply_art_cell()

# 状态 → 图集（受击优先于 melee 优先于 FSM）。
#   ⚠ `_flash>0` = 正在挨打 → 显示 `hit` 图集（受击僵直/后仰姿态）；
#   ⚠ `_melee_t>0` = 刚打出一击 → 显示 `melee` 图集（挥击跟随帧，不影响 FSM 时序）；
#   ⚠ ATTACK 全程 = `attack_tell`（前摇可读 cue）；命中瞬间由 `_physics_process` 置 `_melee_t`。
func _atlas_for_state() -> String:
	if _flash > 0.0:
		return "hit"
	if _melee_t > 0.0:
		return "melee"
	match state:
		State.IDLE, State.ALERT, State.SEARCH:
			return "idle"
		State.CHASE:
			return "move"
		State.ATTACK:
			return "attack_tell"
		State.DEAD:
			return "death"
		_:
			return "idle"

# 把（列帧, 行朝向）合成 region_rect 写到 EnemyArt。
func _apply_art_cell() -> void:
	var art := get_node_or_null(ENEMY_ART_NODE) as Sprite2D
	if art == null:
		return
	art.region_rect = Rect2(
		float(_anim_frame) * float(ENEMY_ATLAS_FRAME),
		float(_facing_row) * float(ENEMY_ATLAS_FRAME),
		float(ENEMY_ATLAS_FRAME), float(ENEMY_ATLAS_FRAME))

# rotation 角 → 朝向行（与资产行序一致：0=背/1=右/2=正/3=左）。
#   ⚠ 边界归属：(-45,45]→右(1) (45,135]→正(2) (135,180]∪(-180,-135]→左(3) (-135,-45]→背(0)
#     —— 与 `--verify-enemy-sprite` ④ 的 `EXPECT_ROW` 逐字一致（见 Main.gd 该入口）。
func _dir_row(a: float) -> int:
	var d := rad_to_deg(a)
	while d <= -180.0:
		d += 360.0
	while d > 180.0:
		d -= 360.0
	if d > -45.0 and d <= 45.0:
		return 1                                     # 右
	if d > 45.0 and d <= 135.0:
		return 2                                     # 正(down)
	if d > 135.0 or d <= -135.0:
		return 3                                     # 左
	return 0                                         # 背(up)

# ==== R-95 失联惯性：起表（**只在失联首帧调用一次**）====
# 【方向取法：用户逐字「按照玩家离开视野时的方向」= 失联那一刻它自己的前进方向】
#   取当前 velocity 的方向 —— 它此刻正在追击玩家，所以这个方向 ≈ 指向玩家/玩家消失处，
#   正是"玩家从视野里消失、僵尸继续朝那个方向扑过去"的直觉。
#   ⚠ 为什么不用 `last_known`（Search 的做法）：last_known 是"玩家最后已知位置"，
#   玩家若在失联前绕了个弯，扑向 last_known 是"事后诸葛"；用户要的是**失联瞬间的动量方向**。
#   ⚠ 边界：CHASE 失联首帧 velocity 可能是 ZERO（刚进 ATTACK 前摇 / 刚收招回 CHASE，
#   那几帧 velocity 归零）。此时 velocity 取不到方向 → 依次兜底：
#     ① 上一帧的惯性方向（若已有，保留，不被 ZERO 覆盖）
#     ② rotation 朝向（僵尸 sprite 一直朝向目标，ALERT/_face 刚转过）
#     ③ last_known 方向（三者都拿不到时的最后兜底）
#   绝不能退化成"每帧重取 velocity"——那会在速度为 0 的帧里反复清零/抖动方向。
func _arm_lunge() -> void:
	if _lunge_dir.length_squared() > 0.0001:
		pass                                 # 已有方向（②兜底命中过）→ 保留，不覆盖
	elif velocity.length_squared() > 0.0001:
		_lunge_dir = velocity.normalized()    # 首选：失联瞬间的动量方向
	else:
		var fwd := Vector2.RIGHT.rotated(rotation)
		if fwd.length_squared() > 0.0001:
			_lunge_dir = fwd                  # 兜底②：sprite 朝向
		else:
			var to := last_known - global_position
			_lunge_dir = to.normalized() if to.length_squared() > 0.0001 else Vector2.ZERO
	_lunge_t = GameConstants.ENEMY_LOSE_LUNGE_TIME
	if _lunge_dir.length_squared() > 0.0001:
		_face(global_position + _lunge_dir)   # 让 sprite 也看向惯性方向（视觉一致）

func _enter_alert() -> void:
	state = State.ALERT
	wander_active = false                 # R-146：脱离 IDLE → 停徘徊（否则两套移动语义叠加）
	_alert_t = GameConstants.ENEMY_ALERT_TIME
	_lose_t = 0.0
	_lunge_t = 0.0                            # R-95：重新发现 → 惯性立即取消
	_lunge_dir = Vector2.ZERO
	if target != null and is_instance_valid(target):
		last_known = target.global_position

# 进入 Search：先「前往最后已知位置」，到达后「原地扫视」，扫视超时回 Idle
func _enter_search() -> void:
	state = State.SEARCH
	wander_active = false                 # R-146：SEARCH 已有自己的移动语义，停徘徊
	_search_phase = 0
	_search_t = 0.0
	_lose_t = 0.0

func _search_step(delta: float) -> void:
	if sensed:
		_enter_alert()      # 重新发现 → 走 Alert 过渡（单一 Alert 入口，避免重复初始化）
		return
	# ==== R-95 边界②：惯性计时器**跨状态保留** ====
	# 正常常量组合下（ENEMY_LOSE_LUNGE_TIME=2.0 ≤ _lose_dur∈{4.0, 2.0}）惯性在 CHASE 内就走完了，
	#  不会走到这里。但 `_lose_dur` 是可调数值（仅听觉时 = 4.0×0.5 = 2.0，**恰好等于**惯性时长；
	#  若日后把 AUDIO_FACTOR 调小 / LOSE_TARGET_TIME 调小，就会出现"惯性跨进 SEARCH"的情况）。
	#  方案 1（**采用**）：惯性接着走完 → 用户要的 2 秒不被状态转移截断。
	#  ⚠ 不能像 Search 的其余分支那样在惯性期间 return —— 否则 phase 0 的"到达 last_known"判定
	#    与 MOVE_TIMEOUT 计时会被跳过，Search 会退化。正确做法是**惯性期间不做 phase 推进也不判定到达**，
	#    惯性结束后由下面的正常逻辑继续（此时僵尸已前进 2s，last_known 通常已在身后或脚下 → 自然转 phase 1）。
	if _lunge_t > 0.0:
		_lunge_t = maxf(0.0, _lunge_t - delta)
		velocity = _lunge_dir * move_speed
		return
	if _search_phase == 0:
		var to := last_known - global_position
		if to.length() <= GameConstants.ENEMY_SEARCH_ARRIVE_DIST:
			_search_phase = 1
			_search_t = 0.0
			velocity = Vector2.ZERO
		else:
			velocity = to.normalized() * move_speed   # ⚠ 原型：直线前往（流场以玩家为源，无法指向任意点）
			_search_t += delta
			if _search_t >= GameConstants.ENEMY_SEARCH_MOVE_TIMEOUT:
				_search_phase = 1
				_search_t = 0.0
				velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO                        # 原地扫视
		_search_t += delta
		if _search_t >= GameConstants.ENEMY_SEARCH_SCAN_TIME:
			state = State.IDLE
			target = null

# 双轴感知重扫：视觉(要求 LOS) / 听觉(不要求 LOS，随玩家噪声缩放)；任一轴命中即候选，取最近
func _scan() -> void:
	scan_calls += 1                                 # 验证探针：统计真实重扫次数
	_sense_t = GameConstants.ENEMY_SENSE_INTERVAL   # 本次重扫后，下次重扫在节流窗口后
	sensed = false
	var best: Node2D = null
	var best_d: float = INF
	var best_los: bool = false
	var max_r: float = maxf(visual_range, audio_range)  # 超出两条轴最大半径 → 连射线都不打（性能）

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
			continue                                  # 超出两轴最大半径 → 跳过（不射线）
		var los: bool = LosUtil.has_los(self, cn.global_position)
		var vis: bool = los and d <= visual_range      # 视觉轴：范围 + LOS
		var hear: bool = d <= audio_range * _hear_factor(cn)  # 听觉轴：范围 × 噪声（不看 LOS）
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
		# 仅被听觉触发、从未 LOS → 脱战阈值减半（记不清来源 → 更快放弃 · GDD §4.1 R-19 补）
		_lose_dur = GameConstants.ENEMY_LOSE_TARGET_TIME if best_los \
			else GameConstants.ENEMY_LOSE_TARGET_TIME * GameConstants.ENEMY_LOSE_TARGET_AUDIO_FACTOR

# 听觉噪声修正（⚠ 原型简化，见 GameConstants.HEAR_FACTOR_*）：玩家 跑动/开枪/装弹 → 1.0；静止/慢走 → 0.5
func _hear_factor(c: Node2D) -> float:
	if c.is_in_group("player"):
		var loud := false
		var vel: Variant = c.get("velocity")
		if vel != null and (vel as Vector2).length() > GameConstants.MOVE_SPEED * GameConstants.PLAYER_RUN_SPEED_EPS:
			loud = true                          # 跑动（速度显著高于常速走）
		var fcd: Variant = c.get("fire_cd")
		if fcd != null and float(fcd) > 0.0:
			loud = true                          # 刚开过枪
		var rl: Variant = c.get("is_reloading")
		if rl != null and bool(rl):
			loud = true                          # 装弹中
		return GameConstants.HEAR_FACTOR_LOUD if loud else GameConstants.HEAR_FACTOR_QUIET
	return GameConstants.HEAR_FACTOR_LOUD        # 敌对阵营（无噪声模型）→ 恒 ×1.0

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
	# ==== R-114 命中血肉 + 死亡低吼 ====
	# ⚠ 湿打感挂在**扣血之后、死亡判定之前**：这样致死那一发也会响（先"啪"再低吼，
	#   符合"打死"的真实听觉顺序），且不会在 `dead` 为真时被上方的守卫挡掉。
	# ⚠ **音效绝不参与任何判定**：不改 hp / 不改 dead / 不改状态机。
	Sfx.play("hit_flesh")
	if hp <= 0.0:
		_die()
		return
	# ==== R-87 受击硬直 ====
	# ⚠ 签名保持单参 `take_damage(amount)` **刻意不动**：Bullet._resolve_hit() 里
	#   `if body.is_in_group("player")` 走双参 `take_damage(damage, src)`，
	#   否则走单参。给敌人改签名会破坏这条既有约定（R-83 引入）。
	# ⚠ 硬直在**扣血之后、死亡判定之后**才置位：
	#   · 伤害结算顺序完全不变（hp 扣减 → 死亡判定 → died 信号），硬直是纯附加反馈；
	#   · 致死那一发不再置位硬直（僵尸已经死了，没必要）。
	# ⚠ 硬直不提供任何减伤/免疫：hp 照扣、照死（--verify-stagger ④ 断言）。
	_stagger = GameConstants.ENEMY_STAGGER_TIME

func _die() -> void:
	# ⚠⚠ **防重复播放守卫**：已核实 `_die()` 的**唯一**调用点是本文件 `take_damage()` :351，
	#   而那里开头就有 `if dead or state == State.DEAD: return` —— 所以**现状不会重复调用**。
	#   但 `_die()` 是 `queue_free()` 型函数：`queue_free()` 幂等、`died.emit()` 幂等性取决于连接方，
	#   而 `Sfx.play` **不幂等** —— 同一帧内若将来有人（如范围伤害 / 爆头倍率）再调一次，
	#   就会听到"多层低吼"叠成噪音墙。所以这里先把旧值存下来再置位。
	var _was_dead: bool = dead
	dead = true
	state = State.DEAD
	wander_active = false                 # R-146：死亡时停徘徊（velocity 本来就归零）
	velocity = Vector2.ZERO
	# ==== R-114 死亡低吼（纯附加反馈，不参与任何判定）====
	if not _was_dead:
		Sfx.play("enemy_die_zombie")
	died.emit()
	queue_free()
