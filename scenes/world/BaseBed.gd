# BaseBed · 基地（第 100 层）起始房间「双人床」（R-new 2026-10-22 用户需求）
# ==============================================================================
# 【用户需求逐字】
#   「在基地的初始房间添加双人床 ... 在双人床旁按 F 加满玩家 hp，
#     根据恢复的 hp 扣减相应比例的饥渴值。」
#
# 【职责边界（与 DepartTile / FloorElevator 完全同款，R-112 单数据流）】
#   · 本节点只负责「画」+ 提供命中判定 `player_stands_on()`；
#   · 按 F 的判定与「回血+扣饥渴」逻辑在 `Main._try_bed()`（表现层不持有游戏状态）；
#   · 近床高亮由 Main 每帧单向推入 `set_player_on()`。
#
# 【🔴 R-128：世界空间禁止任何文字】
#   本节点只有床的图形（Sprite2D = assets/sprites/furniture/bed.png）+ 近床光晕，零文字。
#   「按 F 休息恢复」走屏幕底部 hint 通道（Main._update_hint，屏幕空间 UI，合法）。
#
# 【为什么 Sprite2D 而非 _draw 手绘】
#   bed.png 已存在于家具精灵集（16×16，已 import）→ 直接用，像素清晰、零新资源依赖。
#   近床反馈用一圈半透明光晕（不引入文字，靠亮度/形状表达"可交互"）。
#
# 【落点】由 Main 摆在起始房间空地 (GameConstants.BED_TILE_X/Y = 33,15)，
#   挂 furniture_container（每次 _build_floor 清空 → 离开基地即消失、回基地重建，语义正确）。
# ==============================================================================
extends Node2D

const BED_TEX := preload("res://assets/sprites/furniture/bed.png")

# 近床光晕（站床旁时画在床下方，反馈"可交互"；无文字）
const GLOW_COLOR := Color(0.95, 0.82, 0.45, 0.35)

var _player_near: bool = false   # 玩家是否在交互半径内（Main 单向推入）

# ⚠ 显式声明 storage=false：床挂在 furniture_container，`--verify-basecrates` ① 会对该容器
#   每个子节点调 `bool(n.get("storage"))`；缺字段会 `bool(null)` 运行时错误（§十三）。
#   有了它 → bool(false)==false → ① 干净跳过；语义也正确（床不是储物箱）。
var storage: bool = false

func _ready() -> void:
	z_index = 3                # 画在地板之上（与家具/出发瓦片同一区间）
	var art := Sprite2D.new()
	art.texture = BED_TEX
	art.centered = true
	add_child(art)

# 由 Main 每帧推入：玩家此刻是否在交互半径内（本节点不反查 Player，R-112 约定）
func set_player_on(near: bool) -> void:
	if near != _player_near:
		_player_near = near
		queue_redraw()

# 交互命中判定：玩家世界坐标距床中心 ≤ GameConstants.BED_INTERACT_DIST
#   ⚠ 用 global_position（床挂 furniture_container，父变换不保证单位阵）
func player_stands_on(p: Vector2) -> bool:
	return p.distance_to(global_position) <= GameConstants.BED_INTERACT_DIST

# 近床光晕（画在床下方，反馈"可交互"；零文字）
func _draw() -> void:
	if not _player_near:
		return
	draw_circle(Vector2(0.0, 10.0), 12.0, GLOW_COLOR)
