# NpcDialog · 基地 NPC 对话系统（R-new 2026-10-22 用户需求 Part C）
# ==============================================================================
# 【用户需求逐字】「增加 NPC 的对话系统，NPC1 的立绘概念图已经做好了。」
#   后续：首次对话严格按 1、3、2 句播放（= 索引 0、2、1）；完成后每次随机播 1 句；
#   对话状态可持久化；数据可配置 / 可扩展（任务系统可动态注入）。
#
# 【屏幕空间 UI —— R-128 世界空间禁文字不适用】挂 CanvasLayer；立绘 + 文字。
#
# 【数据结构（**可配置、可扩展，非逻辑硬编码**）】
#   DIALOGS[id] = {
#     name, title,             # 显示用
#     lines: [String...],      # 台词池（唯一真源，新增台词追加到这里）
#     first_sequence: [int...],# 首次对话按此**顺序**播放（索引指向 lines）；省略=全部顺序
#     random_pool: [int...],   # 后续对话随机池（索引指向 lines）；省略=全部 lines
#   }
#   → 首次/后续的「怎么播」全由数据决定，改数据即可改剧本。
#
# 【接入方式（任务系统如何动态新增对话）】
#   ① 给已有 NPC 加台词：`add_line("npc01", "新台词")` 返回新索引，再
#      `append_first_step("npc01", idx)`（进首次序列）或 `add_random_line("npc01", idx)`（进随机池）；
#      若 random_pool 省略（= 全池），add_line 后新句自动进入随机池。
#   ② 新增一个 NPC：`register_dialog("npc02", {name, title, lines, first_sequence, random_pool})`。
#   ③ 整段覆盖剧本：直接 `DIALOGS["npc01"] = {...}`（static var，运行时可改）。
#
# 【持久化】user://npc_dialog_save.json = {"first_done": {id: true}}。
#   首次对话**完整播完**才落盘标记（中途 Esc 关闭不算）；重启后仍记得「已完成首次」。
#
# 【立绘】assets/sprites/portraits/npc01.png（768×1024）。
# ==============================================================================
extends Node2D

const PORTRAIT := preload("res://assets/sprites/portraits/npc01.png")
const SAVE_PATH := "user://npc_dialog_save.json"

# 对话内容（static var：运行时可被任务系统动态扩展/覆盖）。
static var DIALOGS: Dictionary = {
	"npc01": {
		# 权威设定：design/concept/npc-characters.md §2（v0.6）—— 艾拉·维恩 Ella Vane。
		"name": "艾拉·维恩",
		"title": "富翁的旧日情人",
		"lines": [
			"你把我带出那间屋子时，我手里还攥着把拆信刀……谢谢你，先生。你旁边那只箱子我没动，里头有枪，有子弹，拿去用。",
			"累了就上床歇会儿。这地方别的不多，就这张床还算像样——门我给你看着，睡吧。",
			"我叫艾拉·维恩。以前是顶层那个男人养着的人——笼子很漂亮，只是我出不去。现在这扇门，是我自己开的。",
			"你进门先看箱子，才看我。……是个实在人。跟实在人打交道，省得我猜。",
			"别把我当花瓶摆着看，先生。花瓶碎了就碎了——可我还没活够呢。",
			"被关着的时候，我天天想着出去；真自由了，反倒不知道该往哪儿走。你说，人是不是都这样？",
			"别对我这么好，先生。被惯着的人，会忘了怎么自己走路的。",
			"这屋子以前比这儿大十倍，可我现在睡得踏实多了——你说，奇不奇怪。",
			"那个男人在顶楼做过什么，我多少知道一点。哪天你想听，我慢慢说。不是现在——现在我还想睡个安稳觉。",
			"别把我一个人留在这儿。……我这么说，是不是有点不讲道理？可我就是想听你应一声。",
		],
		# 首次对话：第 1 句 → 第 3 句 → 第 2 句（用户需求 1、3、2）。
		"first_sequence": [0, 2, 1],
		# random_pool 省略 = 全部 lines（= 从这 10 句随机选 1 句）。
	},
}

var _npc_id: String = ""
var _queue: Array = []        # 本次对话的播放计划（lines 的索引序列）
var _qi: int = 0              # 当前播放到 _queue 的第几句
var _is_first_conv: bool = false
var _open: bool = false
var _first_done: Dictionary = {}   # npc_id -> true（已完整完成首次对话）

func _ready() -> void:
	visible = false
	_load_state()

# ---------------- 持久化 ----------------
func _load_state() -> void:
	_first_done.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var txt: String = FileAccess.get_file_as_string(SAVE_PATH)
	if txt.is_empty():
		return
	var d = JSON.parse_string(txt)
	if d is Dictionary:
		var fd = (d as Dictionary).get("first_done", {})
		if fd is Dictionary:
			_first_done = fd

func _save_state() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"first_done": _first_done}))
	f.close()

func is_first_done(npc_id: String) -> bool:
	return _first_done.get(npc_id) == true

func mark_first_done(npc_id: String) -> void:
	_first_done[npc_id] = true
	_save_state()

# 重置全部对话进度（新游戏 / 测试用）：清内存 + 落盘空状态。
func reset_dialog_state() -> void:
	_first_done.clear()
	_save_state()

# 测试 / 工具用：当前播放计划副本（lines 索引序列）
func current_queue() -> Array:
	return _queue.duplicate()

# 测试用：清空「已完成首次」标记（仅内存，不落盘）
func clear_first_flags() -> void:
	_first_done.clear()

# ---------------- 扩展 API（任务系统接入点） ----------------
func register_dialog(npc_id: String, cfg: Dictionary) -> void:
	DIALOGS[npc_id] = cfg

# 追加一句台词到 lines，返回其索引（便于加进序列/池）。
func add_line(npc_id: String, text: String) -> int:
	if not DIALOGS.has(npc_id):
		return -1
	var arr: Array = DIALOGS[npc_id]["lines"]
	arr.append(text)
	return arr.size() - 1

# 把某句（lines 索引）追加进「首次对话序列」末尾。
func append_first_step(npc_id: String, line_idx: int) -> void:
	if not DIALOGS.has(npc_id):
		return
	if not (DIALOGS[npc_id] as Dictionary).has("first_sequence"):
		DIALOGS[npc_id]["first_sequence"] = []
	(DIALOGS[npc_id]["first_sequence"] as Array).append(line_idx)

# 把某句（lines 索引）加进「后续随机会话池」。
func add_random_line(npc_id: String, line_idx: int) -> void:
	if not DIALOGS.has(npc_id):
		return
	if not (DIALOGS[npc_id] as Dictionary).has("random_pool"):
		DIALOGS[npc_id]["random_pool"] = []
	(DIALOGS[npc_id]["random_pool"] as Array).append(line_idx)

# ---------------- 播放 ----------------
func _valid_indices(raw: Array, n: int) -> Array:
	var out: Array = []
	for e in raw:
		var k: int = int(e)
		if k >= 0 and k < n:
			out.append(k)
	return out

func is_open() -> bool:
	return _open

func has(npc_id: String) -> bool:
	return DIALOGS.has(npc_id)

# 打开对话：首次 → 按 first_sequence 顺序；已完成首次 → 随机池里选 1 句。
func open(npc_id: String) -> void:
	if not DIALOGS.has(npc_id):
		return
	_npc_id = npc_id
	var cfg: Dictionary = DIALOGS[npc_id]
	var lines: Array = cfg["lines"]
	_is_first_conv = not is_first_done(npc_id)
	if _is_first_conv:
		var fs: Array = _valid_indices(cfg.get("first_sequence", []) as Array, lines.size())
		_queue = fs if not fs.is_empty() else range(lines.size())
	else:
		var pool: Array = _valid_indices(cfg.get("random_pool", []) as Array, lines.size())
		if pool.is_empty():
			pool = range(lines.size())
		_queue = [int(pool[randi() % pool.size()])]
	_qi = 0
	_open = true
	visible = true
	queue_redraw()

# 推进一句；播放计划走完 → 若为首次对话则标记「已完成」并落盘，然后关闭。
func advance() -> void:
	if not _open:
		return
	_qi += 1
	if _qi >= _queue.size():
		if _is_first_conv:
			mark_first_done(_npc_id)
		close()
	else:
		queue_redraw()

func close() -> void:
	_open = false
	visible = false
	queue_redraw()

# 手动按可用宽度换行（避免依赖 draw_multiline_string 的签名细节；中文按字符数估算）。
func _wrap(text: String, max_chars: int) -> Array:
	var out: Array = []
	var cur := ""
	for c in text:
		cur += c
		if cur.length() >= max_chars:
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out

func _draw() -> void:
	if not _open:
		return
	var font := GameConstants.ui_font()
	# 大立绘在对话框**后方**（先画人物，后画半透明面板）
	var screen_w: float = 320.0
	var screen_h: float = 180.0
	var port_w: float = 120.0
	var port_h: float = 160.0
	var port_x: float = screen_w - port_w - 12.0
	var port_y: float = screen_h - port_h
	draw_texture_rect(PORTRAIT, Rect2(Vector2(port_x, port_y), Vector2(port_w, port_h)), false)
	# 半透明对话面板
	var panel := Rect2(8.0, 96.0, 304.0, 76.0)
	draw_rect(panel, Color(0.06, 0.07, 0.10, 0.58))
	draw_rect(panel, Color(0.60, 0.52, 0.36, 1.0), false, 1.0)
	# 人名 + 身份副标题（左侧，避开右侧人物）
	var tx: float = panel.position.x + 14.0
	draw_string_outline(font, Vector2(tx, panel.position.y + 13.0), String(DIALOGS[_npc_id]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, 1, Color(0.0, 0.0, 0.0, 0.75))
	draw_string(font, Vector2(tx, panel.position.y + 13.0), String(DIALOGS[_npc_id]["name"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(0.99, 0.85, 0.45, 1.0))
	draw_string_outline(font, Vector2(tx, panel.position.y + 23.0), String(DIALOGS[_npc_id].get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 6, 1, Color(0.0, 0.0, 0.0, 0.75))
	draw_string(font, Vector2(tx, panel.position.y + 23.0), String(DIALOGS[_npc_id].get("title", "")),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 6, Color(0.74, 0.68, 0.55, 1.0))
	# 对话文本（取 _queue[_qi] 指向的台词；越界兜底第 0 句）
	var lines: Array = DIALOGS[_npc_id]["lines"]
	var li: int = 0
	if _qi < _queue.size():
		li = int(_queue[_qi])
	if li < 0 or li >= lines.size():
		li = 0
	var line: String = String(lines[li])
	var wrapped: Array = _wrap(line, 18)
	var ty: float = panel.position.y + 36.0
	for w in wrapped:
		draw_string_outline(font, Vector2(tx, ty), String(w), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, 1, Color(0.0, 0.0, 0.0, 0.75))
		draw_string(font, Vector2(tx, ty), String(w), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(0.92, 0.92, 0.92, 1.0))
		ty += 9.0
	# 推进 / 结束提示（面板左下）
	var last: bool = _qi >= _queue.size() - 1
	var tip: String = "Esc 离开" if last else "F 继续"
	draw_string(font, Vector2(tx, panel.end.y - 6.0), tip,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(0.75, 0.75, 0.75, 1.0))
