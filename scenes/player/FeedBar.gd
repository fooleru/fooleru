# FeedBar · Node2D · R-144 弹药盒补给的「形状」读条（**禁止任何文字**）
# ==============================================================================
# 【这是什么 / 为什么存在】
#   长按 R 补给弹药盒时，玩家身上显示一个进度条：底槽（暗）+ 填充（亮），
#   每盒 3 秒从 0 填到满（`GameConstants.FEED_BOX_TIME`）。
#   由 `Player._make_feed_bar()` 代码 new 出来（**不动 Player.tscn**，与 `_weapon_sprite` 同款取舍）。
#
# 【🔴 世界空间零文字（R-128 用户铁律）—— 本文件一个字都不能画】
#   用户逐字：「游戏场景内不能出现类似的提示性文字，游戏场景的文字只能出现在美术素材中。」
#   本文件位于 `scenes/player/` → **在 `--verify-loc ①-d` 的目录 grep 范围内**，
#   一旦出现 `draw_string(` / `draw_multiline_string(` / `draw_char(` / `Label.new()` 立刻判 FAIL。
#   → 所以进度条**只能用形状表达**（`draw_rect`），文字提示一律走 Main 的 toast 通道（屏幕空间 UI）。
#
# 【为什么必须 top_level（由 Player 设置，但原因记在这里，别在别处"顺手改回去"）】
#   FeedBar 是 Player（CharacterBody2D）的子节点，而 Player 的 rotation 每物理帧被写成
#   "朝鼠标的角度"（`Player._update_weapon`）。若跟随父级变换，读条会跟着枪一起转
#   → 表现为「进度条平躺 / 竖立 / 倒过来」。`top_level = true` 切断父级变换，
#   位置由 Player 每帧用 `show_at()` 直接喂（并取整）。
#
# 【为什么坐标一律取整】
#   内部基准 320×180 + `viewport` 拉伸。非整数坐标会让 1px 细条出现半像素发虚，
#   与 R-131 瓦片「整数放大才干净」是同一条理由。
# ==============================================================================
extends Node2D

const BAR_W := 14.0     # 读条总宽（内部基准像素）
const BAR_H := 3.0      # 读条高度

var progress: float = 0.0   # 0..1：本盒读条完成度（0 = 刚起步，1 = 即将取盒）

# 摆到世界坐标并显示。Player 每物理帧调一次，传入**已取整**的坐标。
func show_at(global_pos: Vector2) -> void:
	global_position = global_pos
	visible = true

func hide_bar() -> void:
	visible = false

func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()

# 只画矩形：底槽（暗，整条画满，让玩家看得出"总长"）+ 填充（亮黄，宽度随进度增长）。
func _draw() -> void:
	# 原点 = 读条**底边中点**（Player 把原点摆在玩家上方约 10px 处）。
	var x0: float = -BAR_W * 0.5
	var y0: float = -BAR_H
	draw_rect(Rect2(x0, y0, BAR_W, BAR_H), Color(0.08, 0.08, 0.10, 0.85))
	# 填充宽度**取整**（半像素会让细条发虚，见文件头）
	var fw: float = float(int(round(BAR_W * progress)))
	if fw > 0.0:
		draw_rect(Rect2(x0, y0, fw, BAR_H), Color(0.95, 0.82, 0.25))
