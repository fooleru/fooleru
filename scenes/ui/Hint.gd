# Hint · 屏幕交互提示（R-65 新增）
# 常驻 CanvasLayer，按 Main 设置的 `text` 在屏幕底部居中显示（如「按 F 打开箱子」）。
extends Node2D

var text: String = ""

func _draw() -> void:
	if text == "":
		return
	var font := GameConstants.ui_font()
	draw_string(font, Vector2(60.0, 172.0), text, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 8,
		Color(0.99, 0.90, 0.35, 1))
