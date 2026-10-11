# HUD · 左上角紧凑式 · 依据 art-bible §7.1 / D-29 五项收口（R-48）
#   **R-74 紧凑化**：左上角**只保留楼层文字 + 一组色条**（HP / 体力 / 负重 / 弹匣 / 备弹）。
#   所有数字文字（HP / 体力 / 负重 / 弹药 / 超重提示）已移除 —— 超重只剩「底块颜色 + 斜纹」两档视觉。
#   弹药从文字改为**两条色条**：上条 = 弹匣余量，下条 = 该枪口径的备弹（满格参考 `RESERVE_BAR_MAX`）。
extends CanvasLayer
class_name HUD

signal restart_pressed

@onready var hp_green: ColorRect = $Margin/VBox/HP/HPGreen
@onready var hp_red: ColorRect = $Margin/VBox/HP/HPRed
@onready var hp_black: ColorRect = $Margin/VBox/HP/HPBlack
@onready var stamina_track: ColorRect = $Margin/VBox/Stamina/StaminaTrack
@onready var stamina_bar: ColorRect = $Margin/VBox/Stamina/StaminaBar
# R-103：体力槽右侧的 +/- 指示器。**两片色块**拼符号（横笔永远在，竖笔只在 `+` 时在）。
#   为什么不用 Label —— 见 HUD.tscn 里那段注释（实测：font_size=8 的 Label 会被撑到 12px 高，
#   导致与下一行的超重红块真实相交）。ColorRect 最小尺寸是 (0,0)，几何给多少就是多少。
@onready var stamina_regen_h: ColorRect = $Margin/VBox/Stamina/StaminaRegenH
@onready var stamina_regen_v: ColorRect = $Margin/VBox/Stamina/StaminaRegenV
@onready var load_track: ColorRect = $Margin/VBox/Load/LoadTrack
@onready var load_bar: ColorRect = $Margin/VBox/Load/LoadBar
@onready var load_overflow: ColorRect = $Margin/VBox/Load/LoadOverflow
@onready var load_overlay: Control = $Margin/VBox/Load/LoadOverlay
@onready var hunger_track: ColorRect = $Margin/VBox/Hunger/HungerTrack
@onready var hunger_bar: ColorRect = $Margin/VBox/Hunger/HungerBar
@onready var thirst_track: ColorRect = $Margin/VBox/Thirst/ThirstTrack
@onready var thirst_bar: ColorRect = $Margin/VBox/Thirst/ThirstBar
@onready var ammo_track: ColorRect = $Margin/VBox/Ammo/AmmoTrack
@onready var ammo_bar: ColorRect = $Margin/VBox/Ammo/AmmoBar
@onready var reserve_track: ColorRect = $Margin/VBox/Reserve/ReserveTrack
@onready var reserve_bar: ColorRect = $Margin/VBox/Reserve/ReserveBar
@onready var overload_bg: ColorRect = $Margin/VBox/Load/OverloadBg
@onready var floor_label: Label = $Margin/VBox/Floor/FloorLabel

const BAR_W := 56.0            # 色条总宽
const FILL_W := 44.8           # 负重「满槽(=CarryCapacity)」刻度位置 = BAR_W*0.8
const OVER_W := 11.2           # 负重溢出区 = BAR_W*0.2（load ratio 1.0..1.2）
const BAR_H := 5
const RESERVE_H := 3           # 备弹条（比弹匣条细，避免占太多屏）
const AMMO_COLOR := Color(0.98, 0.85, 0.2, 1)
const AMMO_RELOAD_COLOR := Color(0.95, 0.56, 0.33, 1)
# R-77：饥饿（橙棕）/ 口渴（浅蓝）
const HUNGER_COLOR := Color(0.78, 0.52, 0.22, 1)
const THIRST_COLOR := Color(0.35, 0.70, 0.90, 1)

const TIER_NORMAL := 0
const TIER_MILD := 1
const TIER_HEAVY := 2
const COLOR_WARN := Color("f25c54")
const COLOR_WHITE := Color(1, 1, 1, 1)
# ==== R-103：体力恢复指示器（`+` 加成 / `-` 惩罚）====
# ⚠ **为什么复用 `COLOR_HP_GREEN` / `COLOR_WARN`，而不是新建两个颜色常量**
#   核实过全工程既有色语义（逐处grep 过，不是假设）：
#     · 绿 `Color(0.24,0.88,0.37)`（= `GameConstants.COLOR_HP_GREEN` 的近亲）**只**用于 HP 条
#       （`HUD.tscn` 的 HPGreen / GameConstants.COLOR_HP_GREEN）；
#     · 红有两处语义：**血量损失**（COLOR_HP_RED "c42626"，HP 条里露出的红段）
#       与**告警**（COLOR_WARN "f25c54"，用于饥饿/口渴见底 + 超重红块 OverloadBg + LoadOverlay 描边）。
#   R-89 引入的绿/红是**负重超重**语义（`overload_bg` 红块 / `LoadOverlay` 斜纹），
#   与本指示器**不冲突**，理由三条：
#     ① 载体不同：超重信号是**色条区域本身**（底块变红 + 斜纹），本指示器是**色条右侧的独立字形**，
#        且挂在 **Stamina 行**而不是 Load 行 —— 位置与形态双重区分。
#     ② 语义不重叠：`-` 表示"饥渴拖慢恢复"，超重红块表示"负重超重"。两者**可以同时成立**
#        （R-103 叠加规则就是"取最严"）—— 若共用同一红色，玩家会以为"看到一个红 = 只有一个惩罚在生效"，
#        而实际上两个惩罚各自独立可见。这正是需要**第二个**红信号的原因。
#     ③ 绿色侧零冲突：全工程唯一的绿是 HP 条，而 HP 条在**最上面一行**，
#        体力指示器在**第二行**且不是色条（是 8px 字形），不会误读。
#   → 结论：`+` = 鲜绿（与 HP 同色，语义都是"正向"），`-` = COLOR_WARN 红（与超重/饥渴告警同色）。
const REGEN_BONUS_COLOR := Color(0.24, 0.88, 0.37, 1)
const REGEN_PENALTY_COLOR := Color("f25c54")

var _ammo_mag: int = 0
var _reserve: int = 0
var _tier: int = TIER_NORMAL
var _hunger: float = -1.0     # R-77：验证探针（-1 = 还没收到过信号）
var _thirst: float = -1.0
# R-103：体力恢复状态（-1 惩罚 / 0 正常 / +1 加成）。
#   `99` = **尚未收到过任何 stamina 信号**的哨兵值 —— 刻意不初始化成 0，
#   否则"第一次收到信号时状态恰好是 0（正常）"会被 `== _regen_state` 判成"没变"而**跳过首次刷新**，
#   指示器就永远停在 tscn 里的初始 `visible = false`（虽然那次恰好是对的，
#   但换个初始状态就会**静默失同步** —— 这类"靠巧合对"的代码正是 R-96 踩过的坑）。
var _regen_state: int = 99
# R-103：Player 的 `stamina_regen_state()` 查询方法（由 Main 注入，见 Main._ready）。
#   ⚠ 为什么存**函数引用**而不是 int：HUD 是纯显示层，**不持有 Player 引用**
#   （R-80 起就是单向数据流 Main → HUD）。存 Callable 保留了"数据只进不出"的方向性：
#   HUD 只能**问**状态，不能**改**状态。
var _regen_state_fn: Callable = Callable()

func _ready() -> void:
	_set_all_bar_sizes()
	_make_mouse_transparent(self)

# R-68：HUD 是纯显示层，全部 Control 设为 MOUSE_FILTER_IGNORE。
# 否则默认的 STOP 会在 GUI 命中阶段「吃掉」点击 → 背包 / 箱子的拖拽与 Ctrl 快移全部失效。
func _make_mouse_transparent(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_mouse_transparent(ch)

func _set_all_bar_sizes() -> void:
	hp_green.size = Vector2(BAR_W, BAR_H)
	hp_red.size = Vector2(BAR_W, BAR_H)
	hp_black.size = Vector2(0.0, BAR_H)
	hp_green.position = Vector2(0, 0)
	hp_red.position = Vector2(0, 0)
	hp_black.position = Vector2(0, 0)
	stamina_track.size = Vector2(BAR_W, BAR_H)
	stamina_track.position = Vector2(0, 0)
	stamina_bar.size = Vector2(BAR_W, BAR_H)
	stamina_bar.position = Vector2(0, 0)
	load_track.size = Vector2(BAR_W, BAR_H)
	load_track.position = Vector2(0, 0)
	load_bar.size = Vector2(FILL_W, BAR_H)
	load_bar.position = Vector2(0, 0)
	load_overflow.size = Vector2(OVER_W, BAR_H)
	load_overflow.position = Vector2(FILL_W, 0)
	ammo_track.size = Vector2(BAR_W, BAR_H)
	ammo_track.position = Vector2(0, 0)
	ammo_bar.size = Vector2(BAR_W, BAR_H)
	ammo_bar.position = Vector2(0, 0)
	reserve_track.size = Vector2(BAR_W, RESERVE_H)
	reserve_track.position = Vector2(0, 0)
	reserve_bar.size = Vector2(0.0, RESERVE_H)
	reserve_bar.position = Vector2(0, 0)
	hunger_track.size = Vector2(BAR_W, BAR_H)
	hunger_track.position = Vector2(0, 0)
	hunger_bar.size = Vector2(BAR_W, BAR_H)
	hunger_bar.position = Vector2(0, 0)
	thirst_track.size = Vector2(BAR_W, BAR_H)
	thirst_track.position = Vector2(0, 0)
	thirst_bar.size = Vector2(BAR_W, BAR_H)
	thirst_bar.position = Vector2(0, 0)

func _on_hp_changed(hp: float, max_hp: float) -> void:
	var ratio: float = hp / max_hp if max_hp > 0 else 0.0
	hp_green.size.x = BAR_W * ratio
	hp_green.position.x = 0.0
	var injury: float = (max_hp - hp) / max_hp if max_hp > 0 else 0.0
	hp_red.size.x = BAR_W * injury
	hp_red.position.x = BAR_W * ratio  # 红段紧接绿段右侧，避免与绿段在 (0,0) 重叠
	hp_black.size.x = 0.0              # cp1 不接尸毒 → 黑段恒 0

func _on_stamina_changed(stamina: float, max_stamina: float) -> void:
	var ratio: float = stamina / max_stamina if max_stamina > 0 else 0.0
	stamina_bar.size.x = BAR_W * ratio
	# ==== R-103：体力恢复指示器 ====
	# ⚠ **为什么在 `_on_stamina_changed` 里刷新，而不是给 `stamina_changed` 加第 3 个参数**
	#   理由见 `Player.stamina_regen_state()` 的注释（信号参数是破坏性变更 + 语义被污染）。
	#   `stamina_changed` 本来就**每物理帧**触发，所以这里刷新**不增加任何信号开销**。
	_refresh_stamina_regen()

# R-103：把 Player 的恢复状态刷到指示器上。**只有状态真变了才动节点**（visible / 文字 / 颜色）。
#   "只有变化才重绘"由 `if state == _regen_state: return` 一行守住 ——
#   状态在一次 run 内通常几十秒不变，而 `stamina_changed` 每秒触发 60 次；
#   不加这道门就等于每帧重设 Label 文字与颜色（Label 的 setter 会触发重新布局）。
func _refresh_stamina_regen() -> void:
	if not _regen_state_fn.is_valid():
		return
	var st: int = int(_regen_state_fn.call())
	if st == _regen_state:
		return
	_regen_state = st
	if st == 1:
		_set_regen_shown(REGEN_BONUS_COLOR, true)
	elif st == -1:
		_set_regen_shown(REGEN_PENALTY_COLOR, false)
	else:
		# ⚠ **正常态必须"完全不显示"** —— 用户只要求在两种异常态显示符号。
		#   两片都 `visible = false`：Godot 会**跳过整个节点** → 屏幕上真的什么都没有。
		#   （不用"空 Label"或"0 尺寸占位"：那类做法在部分渲染后端会留抗锯齿残影，
		#     而且 headless 里无法从"空串/零尺寸"断言"确实没画东西"。）
		stamina_regen_h.visible = false
		stamina_regen_v.visible = false

# R-103：显示符号。`plus = true` 画 `+`（横+竖两笔），`plus = false` 只留横笔 = `-`。
func _set_regen_shown(c: Color, plus: bool) -> void:
	stamina_regen_h.color = c
	stamina_regen_v.color = c
	stamina_regen_h.visible = true     # 横笔 = `-` 的全部；`+` 也需要它
	stamina_regen_v.visible = plus     # 竖笔只属于 `+`

# R-103：验证探针 —— HUD 当前**显示**的恢复状态（不是 Player 的状态）。
#   单独暴露这个探针是为了让 `--verify-staminareg` ⑤ 能证明"Player 状态 → HUD 显示"这条**接线**存在，
#   而不只是证明 Player 内部的纯函数返回正确（那是恒真的，测不出接线漏了）。
func stamina_regen_shown() -> int:
	return _regen_state

# R-103：验证探针 —— 指示器**整体**是否可见（横笔是"有没有符号"的总开关）。
func stamina_regen_visible() -> bool:
	return stamina_regen_h.visible

# R-103：验证探针 —— 竖笔是否可见。**这是区分 `+` 与 `-` 的唯一依据**：
#   `+` = 横+竖两笔；`-` = 只有横笔。断言它比断言一个自己拼出来的字符串更硬
#   （字符串可能与实际绘制脱节，竖笔可见性不会）。
func stamina_regen_vertical_stroke() -> bool:
	return stamina_regen_v.visible

# R-103：验证探针 —— 指示器当前颜色（供 ⑤ 逐字核对绿/红）。
func stamina_regen_color() -> Color:
	return stamina_regen_h.color

# R-103：验证探针 —— 给日志看的**派读**字符串（'+' / '-' / ''）。
#   ⚠ 这是**派生读数**，不是绘制真相 —— 断言请用上面几个直接读节点属性的探针。
func stamina_regen_text() -> String:
	if not stamina_regen_h.visible:
		return ""
	return "+" if stamina_regen_v.visible else "-"

func _on_load_changed(current: float, capacity: float, factor: float) -> void:
	var ratio: float = current / capacity if capacity > 0 else 0.0
	var fill: float = clamp(ratio, 0.0, 1.0)
	load_bar.size.x = FILL_W * fill
	var over: float = clamp((ratio - 1.0) / 0.2, 0.0, 1.0) if ratio > 1.0 else 0.0
	load_overflow.size.x = OVER_W * over
	load_overflow.visible = over > 0.001
	var tier := _tier_of(ratio)
	_tier = tier
	load_overlay.set_tier(tier)
	# R-74：超重不再显示文字 —— 轻度 = 斜纹（LoadOverlay），重度 = 斜纹 + 红色底块
	overload_bg.visible = (tier == TIER_HEAVY)

func _tier_of(ratio: float) -> int:
	if ratio > 1.2:
		return TIER_HEAVY
	if ratio > 1.0:
		return TIER_MILD
	return TIER_NORMAL

# 验证探针（--verify-load 取代原有的 overlabel 文本断言）
func overload_tier() -> int:
	return _tier

func _on_ammo_changed(current: int, mag: int, reloading: bool) -> void:
	_ammo_mag = mag
	var r: float = clampf(float(current) / float(mag), 0.0, 1.0) if mag > 0 else 0.0
	ammo_bar.size.x = BAR_W * r
	ammo_bar.color = AMMO_RELOAD_COLOR if reloading else AMMO_COLOR

# R-77：饥饿条（归零会持续掉血 → 见底时染红，给一个"该吃东西了"的视觉信号）
func _on_hunger_changed(v: float, max_v: float) -> void:
	_hunger = v
	var r: float = clampf(v / max_v, 0.0, 1.0) if max_v > 0.0 else 0.0
	hunger_bar.size.x = BAR_W * r
	hunger_bar.color = COLOR_WARN if v <= 0.0 else HUNGER_COLOR

# R-77：口渴条（同上）
func _on_thirst_changed(v: float, max_v: float) -> void:
	_thirst = v
	var r: float = clampf(v / max_v, 0.0, 1.0) if max_v > 0.0 else 0.0
	thirst_bar.size.x = BAR_W * r
	thirst_bar.color = COLOR_WARN if v <= 0.0 else THIRST_COLOR

# R-80：HUD 不直接依赖 Player（单向数据流：Main 转发信号），所以真实上限由 Main 告知。
var player_cap_hint: int = 0

# R-74：备弹条（当前武器口径的备弹数 / RESERVE_BAR_MAX）
# R-80：满格参考改为**该口径的真实上限**。
#   ⚠ 口径切换时上限是**双向不同**的（9×19=300 / 12×70=120），所以不能简单取
#   "两者较大值" —— 那样 12×70 灌满时条只到 60%，读起来像"还能再装"。
#   规则：**已知真实上限（Main 告知）→ 用它**；未知（hint=0，首帧/异常）→ 退回旧常量兜底。
#   显示层必须和逻辑上限一致，否则玩家会被自己的 HUD 误导。
func _on_reserve_changed(cur: int) -> void:
	_reserve = cur
	var cap: float = float(player_cap_hint) if player_cap_hint > 0 else float(GameConstants.RESERVE_BAR_MAX)
	var r: float = clampf(float(cur) / cap, 0.0, 1.0) if cap > 0.0 else 0.0
	reserve_bar.size.x = BAR_W * r

# 探针（验证用）
func reserve_shown() -> int:
	return _reserve

func ammo_mag_shown() -> int:
	return _ammo_mag

# 探针（--verify-survival）：HUD 实际显示的饥饿 / 口渴值
func hunger_shown() -> float:
	return _hunger

func thirst_shown() -> float:
	return _thirst

func set_floor(floor: int) -> void:
	# ⚠ R-117：`F` 是**楼层号前缀代号**（与 `ReturnBtn` 的 `F100` 同词根），刻意保留 ASCII。
	#   真正的文案来源是 `Loc` 表 key `hud.floor_prefix` —— 加语言时改表即可，不改这里。
	floor_label.text = Loc.t("hud.floor_prefix") + str(floor)
