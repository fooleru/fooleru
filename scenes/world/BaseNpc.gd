# BaseNpc · 基地（第 100 层）起始房间「NPC1」（R-new 2026-10-22 用户需求 Part B）
# ==============================================================================
# 【用户需求逐字】「在基地的初始房间添加双人床和 NPC1 ... 增加 NPC 的对话系统。」
#   「为 NPC1 生成 sprite 图 ... 复用已完成的 NPC sprite 资产，按一致规范输出可用资产。」
#
# 【NPC1 世界 sprite（复用既有资产，非新画）】
#   资产：`assets/sprites/npc/npc01/char_siren_idle.png`（艾拉精灵代号 = siren）
#         4 列 × 4 行，每帧 64×64，fps 6，行序 up/right/down/left。
#   · 用 Sprite2D + region_rect 切 64×64 帧（同 Zombie.gd 的图集用法），
#     scale = 0.5 → 32×32 世界像素（用户 2026-10-22 要求，= 2 格高）。
#   · 默认正面朝玩家 = 行 2(down)，4 帧呼吸循环，6fps。
#   · move 图集 `char_siren_move.png`（6 列/行、fps 10）一并放入，供将来行走动画使用。
#
# 【职责边界（R-112 单数据流）】只「画」+ 命中判定 `player_stands_on()`；
#   按 F 开对话在 `Main._try_npc()`；对话内容在 `NpcDialog.gd`；近身推 `set_player_on()`。
# 【R-128】世界空间禁文字 —— 本节点零文字（贴图 + 光晕），文字只在屏幕空间 UI。
# ==============================================================================
extends Node2D

# ---- NPC1 图集参数（与 char_siren_idle.json 对齐）----
const SPRITE_TEX := preload("res://assets/sprites/npc/npc01/char_siren_idle.png")
const FRAME_W := 64
const FRAME_H := 64
const ATLAS_SCALE := 0.75         # 用户 2026-10-22 要求：64×64 帧 → **32×32 世界像素**（= 2 格高）
const IDLE_ROW := 2              # 行序 up/right/down/left → 2 = 正(下)，面对玩家
const IDLE_FRAMES := 4
const IDLE_FPS := 6.0

# 近身光晕（站 NPC 旁时画在脚下，反馈"可交互"；无文字）
const GLOW_COLOR := Color(0.45, 0.80, 0.85, 0.32)
# 兜底人形配色（贴图缺失时才用；青蓝=友好 NPC）
const BODY_COLOR := Color(0.35, 0.65, 0.75, 1.0)

var _player_near: bool = false   # 玩家是否在交互半径内（Main 单向推入）
var _art: Sprite2D = null        # 世界 sprite（idle 图集）
var _frame: int = 0              # 当前帧（列）
var _t: float = 0.0

# ⚠ 显式声明 storage=false：NPC 挂 furniture_container，`--verify-basecrates` ① 会对该容器
#   每个子节点调 `bool(n.get("storage"))`；缺字段会 `bool(null)` 运行时错误（与 BaseBed 同坑）。
var storage: bool = false

func _ready() -> void:
	z_index = 3                # 画在地板之上（与家具/出发瓦片同一区间）
	if SPRITE_TEX != null:
		_art = Sprite2D.new()
		_art.texture = SPRITE_TEX
		_art.region_enabled = true
		_art.region_rect = Rect2(0.0, float(IDLE_ROW * FRAME_H), float(FRAME_W), float(FRAME_H))
		_art.centered = true
		_art.scale = Vector2(ATLAS_SCALE, ATLAS_SCALE)
		add_child(_art)

# 由 Main 每帧推入：玩家此刻是否在交互半径内（本节点不反查 Player）
func set_player_on(near: bool) -> void:
	if near != _player_near:
		_player_near = near
		queue_redraw()

# 交互命中判定：玩家世界坐标距 NPC 中心 ≤ GameConstants.NPC_INTERACT_DIST
func player_stands_on(p: Vector2) -> bool:
	return p.distance_to(global_position) <= GameConstants.NPC_INTERACT_DIST

# idle 呼吸循环（4 帧 @6fps，行 2=正面）
func _process(delta: float) -> void:
	if _art == null:
		return
	_t += delta
	var step: float = 1.0 / IDLE_FPS
	while _t >= step:
		_t -= step
		_frame = (_frame + 1) % IDLE_FRAMES
		_art.region_rect = Rect2(float(_frame * FRAME_W), float(IDLE_ROW * FRAME_H),
			float(FRAME_W), float(FRAME_H))

func _draw() -> void:
	# 贴图缺失时回退简易人形（保证 NPC 始终可见可交互）
	if _art == null:
		draw_circle(Vector2(0.0, -6.0), 4.0, BODY_COLOR)
		draw_rect(Rect2(-4.0, -1.0, 8.0, 12.0), BODY_COLOR)
	# 近身光晕（反馈"可交互"；零文字）。注意：Sprite2D 是子节点、画在父 _draw 之上，
	#   光晕会部分被贴图遮住；交互主提示仍由屏幕底部 Hint「按 F 交谈」承担。
	if _player_near:
		draw_circle(Vector2(0.0, 6.0), 12.0, GLOW_COLOR)
