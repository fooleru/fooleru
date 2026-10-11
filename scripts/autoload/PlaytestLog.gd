# PlaytestLog · 实机试玩数据记录设施（R-83）
#
# === 这个设施服务于什么调参目的 ===
# 《百层逃生 / SKY DESCENT》CP1 阶段有 6 组「⚠ 待实测校准」的占位值：
#   ① FOG_VISION_RADIUS_TILES=10（视野半径 160px → 压迫感）
#   ② CARRY_CAPACITY=40.0（负重上限 wg）
#      （⚠ R-89 已把负重上限 40→ **60** —— 这行保留 R-83 立项时的**历史值**，
#        好让本设施记录的旧 CSV 有对照基准；**当前值以 GameConstants.CARRY_CAPACITY 为准**）
#   ③ 僵尸 HP 60-80 / 伤害 15-18 / 速度 45
#   ④ 佣兵 HP 45 / 伤害 9 / 速度 58
#   ⑤ HUNGER_DECAY_PER_SEC=0.45 / THIRST_DECAY_PER_SEC=0.65
#      （⚠ R-92 已把两者各减半为 0.225 / 0.325 —— 这行保留 R-83 立项时的**历史值**，
#        好让本设施记录的旧 CSV 有对照基准；**当前值以 GameConstants 为准**）
#   ⑥ R-82 新增 7 件材料（等概率抽）后的「开箱体感」——用户已接受「近半数用不上」，
#      但**开箱体感本身从未被实测过**。
# 这些值**只能靠人手动试玩来定**。而人手记数据必然失真、跨轮次不可比、漏记死亡原因。
# 本设施把一次试玩的关键数值**客观、追加、可比**地落成 CSV，供下一轮逐项对拍。
# 本设施**只测量，不调参** —— 它不改 GameConstants 一个数字。
#
# === 设计约束（后续改动必须继续满足）===
#   ① **默认关闭**：只有命令行带 `--playtest-log` 才工作。关闭时所有 note_* 首行即 return，
#      且 `set_process(false)` 连 _process 都不跑 → 对正常游玩零行为变化。
#   ② **不在 _process 里做文件 IO**：_process 只做「累加计时 + 读内存状态」（几次 float 加法）。
#      落盘只发生在**离散事件**上：下降一层 / 开一个箱子 / 按 F10 手动快照 / 阵亡 / 退出。
#   ③ **绝不影响玩法**：只读 GameConstants 与 player 状态，不写任何玩法数值、不改任何分支。
#
# === 输出（追加写；文件不存在时自动写表头）===
#   qa_scratch/playtest/sessions.csv  一次试玩一行：会话 + 战斗 + 搜刮 + 生存汇总
#   qa_scratch/playtest/floors.csv    每下降一层一行：「越深越险」的唯一时间轴证据
#   qa_scratch/playtest/loot.csv      每开一个箱子一行：含 7 件材料**各自**出现次数
#
# 路径选 `qa_scratch/playtest/` 的理由：qa_scratch/ 已是本工程既有的 QA 临时产物目录
# （p204 / r75 / r80 都在下面），不是任何 Godot 资源的引用路径，不会被导入管线扫到；
# 同目录下再放一个 .gitignore（`*` + `!.gitignore`），保证试玩数据永远不会进版本库。
extends Node

const OUT_DIR := "res://qa_scratch/playtest/"
const SESSIONS_CSV := OUT_DIR + "sessions.csv"
const FLOORS_CSV := OUT_DIR + "floors.csv"
const LOOT_CSV := OUT_DIR + "loot.csv"

## 是否开启（由 `--playtest-log` 决定）。关闭时整个设施空转。
var enabled: bool = false

# === 会话级累加器（整局累加，flush 时写一行）===
var _session_open: bool = false
var _session_id: String = ""
var _seed: int = 0
var _play_sec: float = 0.0             # 暂停 / 背包菜单期间不累加（PROCESS_MODE_PAUSABLE）

var _shots: int = 0                    # 扳机次数（一次 fire() 记 1；霰弹枪一次多弹丸）
var _pellets: int = 0                  # 实际发射的弹丸数（霰弹枪 > 扳机数）
var _shots_hit: int = 0                # 命中敌人的弹丸数
var _times_hit: int = 0                # 玩家被命中次数（每次 Player.take_damage 记 1）
var _dmg_total: float = 0.0
var _dmg_zombie: float = 0.0
var _dmg_merc: float = 0.0
var _dmg_unknown: float = 0.0
var _kills_zombie: int = 0
var _kills_merc: int = 0
var _crates_opened: int = 0
var _crate_items_total: int = 0
var _ammo_box_moved: int = 0           # 弹药盒从箱子挪进背包的次数（「捡到几次」）
var _ammo_box_used: int = 0            # 右键「补充备弹」成功次数
var _hunger_zero_count: int = 0
var _hunger_zero_sec: float = 0.0
var _thirst_zero_count: int = 0
var _thirst_zero_sec: float = 0.0
var _starve_damage: float = 0.0
var _dehydrate_damage: float = 0.0
var _overweight_sec: float = 0.0       # 超重（CARRY_CAPACITY 之上）累计秒数
var _max_load_ratio: float = 0.0
var _last_dmg_src: String = ""         # 最近一次造成伤害的来源 → 阵亡时作死亡原因
var _hunger_was_zero: bool = false     # 归零沿检测（做「归零次数」计数）
var _thirst_was_zero: bool = false

# === 楼层时间轴累加器（每下降一层清零并写一行）===
var _floor: int = 0
var _floor_sec: float = 0.0
var _floor_written: bool = true
var _f_shots: int = 0
var _f_pellets: int = 0
var _f_hits: int = 0
var _f_times_hit: int = 0
var _f_dmg: float = 0.0
var _f_kills_zombie: int = 0
var _f_kills_merc: int = 0
var _f_crates: int = 0

# === 玩家快照（_process 每帧只读一次，保证「关游戏那一刻」也能写出最终数值）===
var _player: Node = null
var _snap_hp: float = 0.0
var _snap_stamina: float = 0.0
var _snap_hunger: float = 0.0
var _snap_thirst: float = 0.0
var _snap_load: float = 0.0

var _item_ids: PackedStringArray = PackedStringArray()

func _ready() -> void:
	# 暂停时不计时（背包 / 暂停页的时间不算「试玩时长」）。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	enabled = "--playtest-log" in OS.get_cmdline_args()
	# loot.csv 的列 = 箱子战利品池（GameConstants.ITEM_TYPES）的全部 id。
	# 从常量表动态取 → 以后往池子里加物品，CSV 表头自动跟着长，不会漏记新物品。
	for it in GameConstants.ITEM_TYPES:
		_item_ids.append(String((it as Dictionary).get("id", "?")))
	if not enabled:
		set_process(false)   # ★ 默认关闭 → 连 _process 都不跑
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

# ==== 由 Main._ready 调用；顺带「若上一局已结束则自动开新一局」 ====
func attach(p: Node) -> void:
	if not enabled:
		return
	_player = p
	if not _session_open:
		_begin_session()

## 记录本局用的随机种子 → 同一行数据可复现（复现 = 再跑一次同种子同布局）
func set_seed(s: int) -> void:
	_seed = s

func _begin_session() -> void:
	_session_open = true
	_session_id = "S%d" % Time.get_unix_time_from_system()
	_play_sec = 0.0
	_shots = 0
	_pellets = 0
	_shots_hit = 0
	_times_hit = 0
	_dmg_total = 0.0
	_dmg_zombie = 0.0
	_dmg_merc = 0.0
	_dmg_unknown = 0.0
	_kills_zombie = 0
	_kills_merc = 0
	_crates_opened = 0
	_crate_items_total = 0
	_ammo_box_moved = 0
	_ammo_box_used = 0
	_hunger_zero_count = 0
	_hunger_zero_sec = 0.0
	_thirst_zero_count = 0
	_thirst_zero_sec = 0.0
	_starve_damage = 0.0
	_dehydrate_damage = 0.0
	_overweight_sec = 0.0
	_max_load_ratio = 0.0
	_last_dmg_src = ""
	_hunger_was_zero = false
	_thirst_was_zero = false
	_floor_written = true
	_snap_hp = 0.0
	_snap_stamina = 0.0
	_snap_hunger = 0.0
	_snap_thirst = 0.0
	_snap_load = 0.0

# ==== _process：只做计时与状态快照，**不做任何文件 IO** ====
func _process(delta: float) -> void:
	if not enabled or not _session_open:
		return
	_play_sec += delta
	_floor_sec += delta
	if _player == null or not is_instance_valid(_player):
		return
	# 玩家阵亡后节点仍在（死亡页盖着），照样快照 —— 关游戏那一刻要写最终值。
	_snap_hp = float(_player.hp)
	_snap_stamina = float(_player.stamina)
	_snap_hunger = float(_player.hunger)
	_snap_thirst = float(_player.thirst)
	_snap_load = float(_player.current_load)
	# 归零次数：靠「沿检测」数下降沿（>0 → ==0 记一次），不依赖任何 Player 侧钩子。
	var hz: bool = _snap_hunger <= 0.0
	if hz and not _hunger_was_zero:
		_hunger_zero_count += 1
	_hunger_was_zero = hz
	var tz: bool = _snap_thirst <= 0.0
	if tz and not _thirst_was_zero:
		_thirst_zero_count += 1
	_thirst_was_zero = tz
	# R-101：负重上限改从 Player 读 `carry_capacity()`（裸装 60 / 穿双肩包 80）。
	#   ⚠ 为什么这里也必须改：本设施记录的是 `max_load_ratio` 与 `overweight_sec`
	#   （R-83 立项目的就是校准负重手感）。若仍除以裸装 60，玩家穿双肩包后
	#   在 60~80 之间**不会被记成超重**，而游戏里他确实没超重 —— 数据反而"对了"；
	#   但反过来，玩家**没**穿包时它是准的，穿包时它会**低估**真实压力占比，
	#   于是同一份 CSV 里"超重时长"混合了两种分母，调参时会得出错误结论。
	#   → 统一走 Player 的权威口径。
	var cap: float = _carry_cap()
	if cap > 0.0:
		var ratio: float = _snap_load / cap
		_max_load_ratio = maxf(_max_load_ratio, ratio)
		if ratio > 1.0:
			_overweight_sec += delta

# R-101：负重上限的**唯一读取入口**（裸装 CARRY_CAPACITY / 装备后 +load_bonus）。
# ⚠ 拿不到 Player 时（未 attach / 校验失败）退回裸装常量 —— 宁可退回旧口径，也不能崩。
func _carry_cap() -> float:
	if _player != null and is_instance_valid(_player) and _player.has_method("carry_capacity"):
		return float(_player.carry_capacity())
	return GameConstants.CARRY_CAPACITY

# ==== 战斗埋点 ====

## 扳机一次（Player.fire() 内部调用）。pellets = 本次发射弹丸数（霰弹枪 > 1）。
func note_shot(pellets: int) -> void:
	if not enabled or not _session_open:
		return
	_shots += 1
	_pellets += maxi(1, pellets)
	_f_shots += 1
	_f_pellets += maxi(1, pellets)

## 玩家子弹命中一个敌人（Bullet._resolve_hit 且非敌弹）。**弹丸级**计数。
func note_hit() -> void:
	if not enabled or not _session_open:
		return
	_shots_hit += 1
	_f_hits += 1

## 玩家受到一次**战斗**伤害。src ∈ "zombie" / "merc" / ""（来源未知）
## amount = 本次**实际扣掉**的血量（已过护甲减伤）。
func note_damage_taken(amount: float, src: String) -> void:
	if not enabled or not _session_open:
		return
	_times_hit += 1
	_f_times_hit += 1
	_dmg_total += amount
	_f_dmg += amount
	_last_dmg_src = src
	match src:
		"zombie":
			_dmg_zombie += amount
		"merc":
			_dmg_merc += amount
		_:
			_dmg_unknown += amount

## 玩家受到一次**生存**伤害（饥饿 / 口渴）。src ∈ "starve" / "thirst"。
## 与战斗伤害分开走这个入口：生存伤害**不算"被击中次数"**（没人打你），
##   但**计入受到伤害总量**、并参与死亡原因归因（饿死 ≠ 被僵尸咬死，必须能分开）。
## amount = 本次实际扣血（生存伤害按设计不过护甲减伤）。
func note_survival_damage(amount: float, src: String) -> void:
	if not enabled or not _session_open:
		return
	_dmg_total += amount
	_f_dmg += amount
	_last_dmg_src = src

## 敌人死亡。faction 用 GameConstants.FACTION_* → 拆成僵尸 / 佣兵两列。
func note_enemy_died(faction: int) -> void:
	if not enabled or not _session_open:
		return
	if faction == GameConstants.FACTION_MERC:
		_kills_merc += 1
		_f_kills_merc += 1
	else:
		_kills_zombie += 1
		_f_kills_zombie += 1

## 玩家阵亡 → 立刻落盘（死亡原因 = 最后一次造成伤害的来源）
func note_player_died() -> void:
	flush("death")

# ==== 生存埋点（饥饿 / 口渴归零掉血）====
# 下面两个只在**真的归零掉血**的那一帧被调用（Player._update_survival 内部），
# 归零之前一次都不调 → 对正常游玩零开销。

## Player._update_survival：hunger 已归零、本帧按 STARVE_DPS 扣血。
func note_starve_tick(delta: float) -> void:
	if not enabled or not _session_open:
		return
	_hunger_zero_sec += delta
	_starve_damage += GameConstants.STARVE_DPS * delta
	_last_dmg_src = "starve"

## Player._update_survival：thirst 已归零、本帧按 DEHYDRATE_DPS 扣血。
func note_thirst_tick(delta: float) -> void:
	if not enabled or not _session_open:
		return
	_thirst_zero_sec += delta
	_dehydrate_damage += GameConstants.DEHYDRATE_DPS * delta
	_last_dmg_src = "thirst"

# ==== 搜刮埋点 ====

## 首次打开一个箱子：写一行 loot.csv（含该箱内 15 类物品各自的数量）。
func note_crate_opened(items: Array) -> void:
	if not enabled or not _session_open:
		return
	_crates_opened += 1
	_f_crates += 1
	_crate_items_total += items.size()
	var counts := {}
	for it in items:
		var id: String = String((it as Dictionary).get("id", "?"))
		counts[id] = int(counts.get(id, 0)) + 1
	var row := PackedStringArray()
	row.append(_now_str())
	row.append(_session_id)
	row.append(str(_floor))
	row.append(str(_crates_opened))
	row.append(str(items.size()))
	for id in _item_ids:
		row.append(str(int(counts.get(id, 0))))
	_append_csv(LOOT_CSV, _loot_cols(), row)

## 弹药盒从箱子挪进背包（Main._move_item，from=cont）→ 这就是「捡到几次」
func note_ammo_box_moved() -> void:
	if not enabled or not _session_open:
		return
	_ammo_box_moved += 1

## 右键「补充备弹」成功一次（Main._use_item 的 kind=="ammo" 分支）
func note_ammo_box_used() -> void:
	if not enabled or not _session_open:
		return
	_ammo_box_used += 1

# ==== 楼层时间轴 ====

func note_floor_start(floor: int) -> void:
	if not enabled or not _session_open:
		return
	_floor = floor
	_floor_sec = 0.0
	_floor_written = false
	_f_shots = 0
	_f_pellets = 0
	_f_hits = 0
	_f_times_hit = 0
	_f_dmg = 0.0
	_f_kills_zombie = 0
	_f_kills_merc = 0
	_f_crates = 0

## 下降一层：结算本层时间轴行（**必须在 _floor 自增之前调用**）。
func note_floor_end() -> void:
	if not enabled or not _session_open or _floor_written:
		return
	_write_floor_row("descend")

# ==== 落盘 ====

## F10 手动快照：追加一行 sessions.csv，但**不结束本局**（玩家可继续玩、再按一次）。
## 本层时间轴**不在这里结算** —— 玩家还在这一层，走完/退出会由 note_floor_end / flush 补上。
func note_manual_dump() -> void:
	if not enabled or not _session_open:
		return
	_write_session_row("manual")

## 结束本局并落盘。ending ∈ death / quit / window_close / exit
func flush(ending: String) -> void:
	if not enabled or not _session_open:
		return
	# 本局最后一层也要留下时间轴行（否则「死在第 3 层」会缺第 3 层的记录）。
	if not _floor_written:
		_write_floor_row(ending)
	_write_session_row(ending)
	_session_open = false

func _write_floor_row(ending: String) -> void:
	_floor_written = true
	var cols := PackedStringArray([
		"ts", "session_id", "floor", "floor_sec", "hp_end", "stamina_end", "hunger_end",
		"thirst_end", "shots", "pellets", "shots_hit", "hit_rate", "times_hit", "dmg_taken",
		"kills_zombie", "kills_merc", "crates_opened", "end_reason",
	])
	var row := PackedStringArray()
	row.append(_now_str())
	row.append(_session_id)
	row.append(str(_floor))
	row.append("%.1f" % _floor_sec)
	row.append("%.1f" % _snap_hp)
	row.append("%.1f" % _snap_stamina)
	row.append("%.1f" % _snap_hunger)
	row.append("%.1f" % _snap_thirst)
	row.append(str(_f_shots))
	row.append(str(_f_pellets))
	row.append(str(_f_hits))
	row.append(_rate(_f_hits, _f_pellets))
	row.append(str(_f_times_hit))
	row.append("%.1f" % _f_dmg)
	row.append(str(_f_kills_zombie))
	row.append(str(_f_kills_merc))
	row.append(str(_f_crates))
	row.append(_csv_safe(ending))
	_append_csv(FLOORS_CSV, cols, row)

func _write_session_row(ending: String) -> void:
	var hp: float = _snap_hp
	var stam: float = _snap_stamina
	var hun: float = _snap_hunger
	var thi: float = _snap_thirst
	var load: float = _snap_load
	if _player != null and is_instance_valid(_player):
		hp = float(_player.hp)
		stam = float(_player.stamina)
		hun = float(_player.hunger)
		thi = float(_player.thirst)
		load = float(_player.current_load)
	var cap: float = _carry_cap()   # R-101：与超重统计同一口径（裸装 60 / 穿包 80）
	var ratio: float = (load / cap) if cap > 0.0 else 0.0
	var cause := _last_dmg_src
	if ending != "death":
		cause = ""      # 只有阵亡才有「死亡原因」
	var cols := PackedStringArray([
		"ts", "session_id", "seed", "ending", "death_cause", "play_sec", "floor_reached",
		"final_hp", "final_stamina", "final_hunger", "final_thirst",
		"final_load", "load_cap", "load_ratio", "overweight", "overweight_sec", "max_load_ratio",
		"shots", "pellets", "shots_hit", "hit_rate", "times_hit",
		"dmg_taken_total", "dmg_from_zombie", "dmg_from_merc", "dmg_from_unknown",
		"kills_zombie", "kills_merc",
		"crates_opened", "crate_items_total", "ammo_box_moved", "ammo_box_used",
		"hunger_zero_count", "hunger_zero_sec", "thirst_zero_count", "thirst_zero_sec",
		"starve_damage", "dehydrate_damage",
		# 把当轮生效的占位值一并写下来 → CSV 自带对照语境，换参数后不用回忆上一轮跑的是什么
		"fog_vision_radius_tiles", "carry_capacity",
	])
	var row := PackedStringArray()
	row.append(_now_str())
	row.append(_session_id)
	row.append(str(_seed))
	row.append(_csv_safe(ending))
	row.append(_csv_safe(cause))
	row.append("%.1f" % _play_sec)
	row.append(str(_floor))
	row.append("%.1f" % hp)
	row.append("%.1f" % stam)
	row.append("%.1f" % hun)
	row.append("%.1f" % thi)
	row.append("%.1f" % load)
	row.append("%.1f" % cap)
	row.append("%.2f" % ratio)
	row.append("1" if ratio > 1.0 else "0")
	row.append("%.1f" % _overweight_sec)
	row.append("%.2f" % _max_load_ratio)
	row.append(str(_shots))
	row.append(str(_pellets))
	row.append(str(_shots_hit))
	row.append(_rate(_shots_hit, _pellets))
	row.append(str(_times_hit))
	row.append("%.1f" % _dmg_total)
	row.append("%.1f" % _dmg_zombie)
	row.append("%.1f" % _dmg_merc)
	row.append("%.1f" % _dmg_unknown)
	row.append(str(_kills_zombie))
	row.append(str(_kills_merc))
	row.append(str(_crates_opened))
	row.append(str(_crate_items_total))
	row.append(str(_ammo_box_moved))
	row.append(str(_ammo_box_used))
	row.append(str(_hunger_zero_count))
	row.append("%.1f" % _hunger_zero_sec)
	row.append(str(_thirst_zero_count))
	row.append("%.1f" % _thirst_zero_sec)
	row.append("%.1f" % _starve_damage)
	row.append("%.1f" % _dehydrate_damage)
	row.append(str(GameConstants.FOG_VISION_RADIUS_TILES))
	row.append("%.1f" % cap)
	_append_csv(SESSIONS_CSV, cols, row)

# ==== 退出路径：三条都要保证落盘 ====
# ① 窗口右上角关闭 / Alt+F4：只补写，不干预引擎默认的关闭流程（否则窗口关不掉）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush("window_close")
	elif what == NOTIFICATION_PREDELETE:
		flush("exit")

# ② 暂停页「退出」按钮（Main 显式调 flush("quit")）
# ③ 无头验证里的 get_tree().quit()
# ④ 任何其它退出路径 —— 全部由这里兜底，保证「关游戏时一定落盘」。
func _exit_tree() -> void:
	flush("exit")

# ==== 小工具 ====
func _rate(num: int, den: int) -> String:
	if den <= 0:
		return ""      # 没开过枪 → 命中率无定义；留空比写 0.00 诚实
	return "%.3f" % (float(num) / float(den))

func _now_str() -> String:
	return Time.get_datetime_string_from_system()

func _csv_safe(s: String) -> String:
	# 本设施写入的字符串字段都取自受控词表（death/quit/manual/zombie/...），
	# 这里只是保险：万一将来塞进逗号/引号也不会把 CSV 行列打乱。
	return s.replace(",", "_").replace("\"", "_").replace("\n", "_")

func _loot_cols() -> PackedStringArray:
	var c := PackedStringArray(["ts", "session_id", "floor", "crate_seq", "item_total"])
	for id in _item_ids:
		c.append("n_" + id)
	return c

# 追加写一行；文件不存在 / 为空时先写表头。
# ★ 用 READ_WRITE + seek_end 而不是 WRITE —— WRITE 会**截断**文件，把历史试玩数据清掉。
# ⚠ Godot 的坑：READ_WRITE **不会创建**不存在的文件（返回 null），所以必须回退到 WRITE；
#   而 WRITE 分支是「新建空文件」，**同样需要补写表头**，否则首行就是裸数据、无法解析。
func _append_csv(path: String, cols: PackedStringArray, row: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		if f.get_position() == 0:
			f.store_line(",".join(cols))     # 已存在但为空 → 补表头
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_warning("[PlaytestLog] 打不开 %s（错误码 %d）—— 本局数据丢失" % [path, FileAccess.get_open_error()])
			return
		f.store_line(",".join(cols))         # 新建文件 → 表头是必须的第一行
	f.store_line(",".join(row))
	f.close()
