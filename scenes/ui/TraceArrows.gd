# TraceArrows · 宝箱定位的屏幕边缘方向箭头（R-110 新增）
# ============================================================================
# 【职责】
#   在**屏幕边缘**画最多 3 个箭头，每个指向 1 个被定位的宝箱；同一套数据
#   也驱动楼层地图上的闪烁标记（见 FloorMap.set_markers）—— 二者永远同源。
#
# 【为什么单独一个 CanvasLayer，而不是塞进 HUD 或 FloorMap】
#   · HUD 在 layer=10、**会被迷雾(9)压暗**；本箭头必须「始终亮」，
#     否则「未探索黑区里的宝箱」这个方向提示会一起变暗 → 提示失效。
#   · FloorMap 在 layer=15（地图自带 0.82 黑底）；若箭头在其**之下**，
#     玩家**打开地图看标记时箭头会被压暗** —— 而那正是箭头最主要的使用场景。
#   → 故取 layer=16：在地图之上、背包(12)/暂停(30)/死亡(20)之下。
#     背包打开时本节点由 Main 显式隐藏（见 Main._apply_trace_visuals）。
#
# 【方向怎么算：为什么用「世界空间方向」而不是「世界坐标 → 屏幕坐标」】
#   摄像机恒跟随玩家（Main._update_camera），玩家基本恒在屏幕中心。
#   边缘指示器只需要**方向**，用世界空间 `crate - player` 的归一化向量即可，
#   完全不依赖摄像机矩阵 → headless 下可精确断言，且不受右键探头
#   （AIM_LOOKAHEAD 90px）偏移影响（偏移只挪玩家、不改「箱子在玩家哪一侧」）。
#
# 【"箱子已在视野内"怎么办 —— 用户第3 轮未单独拍板，本实现取「照旧显示箭头」】
#   理由：
#     ① 用户原话是「指示出这**3个**宝箱的方向」—— 3 个箭头是**承诺**。
#        若"在屏内就不画"，玩家会看到箭头**随机增减**，在 320×180 上
#        这种闪烁比"多一个箭头"更干扰。
#     ② 箱子在屏内 ≠ 玩家看得见（迷雾会把未探索区的箱子整块盖掉）。
#        "在屏内所以不提示"会在黑区宝箱上给出错误的安全感。
#     ③ 箱子贴脸时箭头落在屏幕边缘、指向玩家脚下 —— 语义仍是
#        "那边有货"，不误导。
#   → 恒定 3 个箭头 = 恒定可断言（--verify-trace ⑦ 依赖这条）。
#
# 【320×180 的空间核实 —— 与 HUD 7 条色条的**实测**重叠检查】
#   HUD 实际墨迹包围盒（由 HUD.tscn 逐节点累加得出，--verify-trace ⑧ 实测复核）：
#     · 7 条色条 x ∈ [4, 60]（BAR_W=56，Margin 左 4）、y ∈ [4, 61]
#       （6+6+6+6+6+6+4 = 40，再加 Floor 行 10 + 7 个 separation 1 = 57）
#     · 超重红块 OverloadBg 右伸到 x = 4 + 68 = 72
#     · FloorLabel offset_right=120 → x ∈ [4, 124]
#   → 保守取keep-out 矩形 **x < 128 且 y < 64**。
#   落在其中的箭头按「它贴的是哪条边」推开：贴顶边 → 压到 y=64（色条下方），
#   贴左边 → 推到 x=128（楼层号右侧）。**绝不硬塞**。
#   右边缘(x=312)与下边缘(y=172)本就远离 HUD，不做任何限制。
# ============================================================================
extends Node2D

const VIEW_W := 320.0
const VIEW_H := 180.0
const EDGE_INSET := 8.0        # 箭头锚点距屏幕边缘 8px（留出箭头自身 3.5px + 4.5px 呼吸）
const ARROW_SIZE := 7.0# 箭头外接尺寸（px）：7×7，320×180 上3 个仍清晰可辨
const ARROW_COLOR := Color(0.30, 1.0, 0.55, 1)     # 亮绿：与出口黄/玩家蓝/4 种箱子色均可分
const ARROW_SHADOW := Color(0.0, 0.0, 0.0, 0.85)   # 1px 黑影 → 在浅色地面/白医疗箱上也读得出
# HUD 7 条色条 + 楼层号的实测包围盒 + 余量（见文件头「320×180 的空间核实」）
const HUD_KEEP_X := 128.0
const HUD_KEEP_Y := 64.0

# 目标世界坐标（与 FloorMap 的标记**同一份数组** → 永远一致）
var _targets: Array = []
var _player_pos: Vector2 = Vector2.ZERO
var _shown: bool = false        # 闪烁相位（Main 统一算，两边同步）

# ---- headless 探针（供 --verify-trace 断言，本体不参与绘制逻辑）----
func targets() -> Array:
	return _targets.duplicate()

func is_shown() -> bool:
	return _shown

## 屏幕锚点（未做 keep-out 修正的裸值）—— 供验证复算数学
func edge_point_for(world_pos: Vector2) -> Vector2:
	return _edge_point((world_pos - _player_pos).normalized())

## 实际用于绘制的锚点（含 keep-out 修正）—— 供验证断言「不压 HUD」
func placed_point_for(world_pos: Vector2) -> Vector2:
	return _edge_point(_dir_of(world_pos))

func set_targets(world_positions: Array, player_pos: Vector2, shown: bool) -> void:
	_targets = world_positions.duplicate()
	_player_pos = player_pos
	_shown = shown
	queue_redraw()

func clear_targets() -> void:
	if _targets.is_empty() and not _shown:
		return
	_targets = []
	_shown = false
	queue_redraw()

# 目标与玩家完全重合时方向未定义 —— 退化为「向上」，保证 3 个箭头**恒有**输出
# （不变量「恒 3 个」是 --verify-trace ⑦ 的断言前提）。
func _dir_of(world_pos: Vector2) -> Vector2:
	var d: Vector2 = world_pos - _player_pos
	if d.length_squared() < 0.000001:
		return Vector2.UP
	return d.normalized()

# 射线 × 以屏幕中心为中心、内缩 EDGE_INSET 的矩形 → 求边缘锚点，再做 HUD keep-out。
func _edge_point(d: Vector2) -> Vector2:
	var center := Vector2(VIEW_W * 0.5, VIEW_H * 0.5)
	var half := Vector2(VIEW_W * 0.5 - EDGE_INSET, VIEW_H * 0.5 - EDGE_INSET)
	var t := 1000000.0
	if absf(d.x) > 0.0001:
		t = min(t, half.x / absf(d.x))
	if absf(d.y) > 0.0001:
		t = min(t, half.y / absf(d.y))
	var p: Vector2 = center + d * t
	# --- HUD keep-out：绝不把箭头压在 7 条色条 / 楼层号上 ---
	if p.x < HUD_KEEP_X and p.y < HUD_KEEP_Y:
		# 它贴的是顶边还是左边？谁的偏移更小就算谁 → 推到该边「刚好不压 HUD」的位置
		if absf(p.y - EDGE_INSET) <= absf(p.x - EDGE_INSET):
			p.y = HUD_KEEP_Y
		else:
			p.x = HUD_KEEP_X
	return p

func _process(_delta: float) -> void:
	# 目标存在时必须每帧重绘：玩家在动→ 箭头方向跟着动。
	# （不依赖 FloorMap.visible，标记窗口内地图开/关都不影响箭头的计时与显隐）
	if not _targets.is_empty():
		queue_redraw()

func _draw() -> void:
	if not _shown:
		return
	var center := Vector2(VIEW_W * 0.5, VIEW_H * 0.5)
	for wp in _targets:
		var wpos: Vector2 = wp
		var d: Vector2 = _dir_of(wpos)
		var p: Vector2 = _edge_point(d)
		var perp := Vector2(-d.y, d.x)
		var tip: Vector2 = p + d * (ARROW_SIZE * 0.5)
		var half_w: float = ARROW_SIZE * 0.45
		var back: float = ARROW_SIZE * 0.35
		var b1: Vector2 = p - d * back + perp * half_w
		var b2: Vector2 = p - d * back - perp * half_w
		# 黑影（放大 1 圈并沿箭头方向外移 1px）→ 在任何底色上都有对比
		var s1: Vector2 = p + d * 1.0 - d * (back + 1.0) + perp * (half_w + 1.0)
		var s2: Vector2 = p + d * 1.0 - d * (back + 1.0) - perp * (half_w + 1.0)
		var stip: Vector2 = p + d * (ARROW_SIZE * 0.5 + 1.0)
		draw_colored_polygon(PackedVector2Array([stip, s1, s2]), ARROW_SHADOW)
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), ARROW_COLOR)
