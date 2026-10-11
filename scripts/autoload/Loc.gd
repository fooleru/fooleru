# ==============================================================================
# Loc · 面向玩家的文案表（R-117 新增 · autoload `Loc`）
# ==============================================================================
# 【用户需求逐字 · team-lead 转述】
#   「⑤ 测试版统一成中文，**后续版本加入多语言支持**」
#   → 本文件同时满足两条：① 本批把英文文案改成中文；② 为多语言留最小可用结构。
#
# 【为什么现在就需要它（不是"为将来准备"的空壳）】
#   改文案这件事本身就有"漏改"风险：320×180 的 UI 里散着七八处 draw 文本，
#   手工改一遍只能靠肉眼。`--verify-loc ①` 因此把「表里不许出现英文」钉成断言，
#   以后新增文案忘填 / 填了英文，回归立刻红。**结构本身就是防漏改的护栏。**
#
# 【⚠⚠ 为什么刻意"最小"，不引 `tr()` / `TranslationServer` / `.csv`】
#   那三样是**正式多语言**的答案（要建 `.po`/`.csv`、要跑导入、要重编 `.translation`、
#   要处理字体回退与复数规则），而本工程当前**只有简体中文一种语言**。
#   现在就上= 引入一条尚无使用者的构建链路 + 每个新语言都要改构建配置，纯负担。
#   → 本批只留**结构占位**：一张表 + 一个查表函数 + 一个切换钩子。
#     将来真要加语言时，`T_ZH_CN` 旁边并列一张 `T_EN_US` 即可，
#     `t()` / `set_locale()` 的调用点**一行都不用改**—— 这就是本文件存在的意义。
#
# 【查不到 key 时回退到 key 本身（不是空串、不是崩）】
#   这是**故意**选的失败模式：新加文案时如果忘了填表，
#   玩家看到的是 `hint.crate_open_prefix` 这样的一串 key（**一眼看得出是 bug**），
#   而不是屏幕上**空一块**（看不出是 bug，还是"这里本来就没字"，最难查）。
#   → `--verify-loc ②` 把这条钉成断言。
#
# 【⚠ `t()` 在 `_draw()` 里调是安全的（Godot 4.7.2 实测）】
#   本工程 UI 全部是 `_draw()` 手绘 + `GameConstants.ui_font()` 渲染，
#   所以"文案怎么拿"只能靠 autoload（没有 `.tscn` 里的 Label 可以挂文本）。
#   **实测结论：可行。** autoload 只是场景树根下的一个普通 Node，
#   `_draw()` 里读它的 `Dictionary` 不涉及任何渲染状态，不触发重入。
#   由 `--verify-loc ④-b` 在**真实 `_draw()` 回调里**调 `Loc.t()` 并断言返回值守护。
#   ⚠ 若将来把这些 UI 换成真实 `Control`+`Label`，应改用 `tr()`（本批不引）。
# ==============================================================================
# 【「保留 ASCII」清单 —— 逐条给出理由（用户需求逐字：报告里须列出每一处）】
#   ⚠ 判据：**该字符串是"代号/ 标识符 / 键名"而非"要读的词"**。
#     代号译成中文反而会让玩家看不懂（`F100` 是"第 100 层"的内部记法，
#     而 `Hud` 的楼层号也是 `F%d`，两者必须**同族一致**，不能一个中文一个英文）。
#   ① `return.floor_label = "F100"` —— 楼层代号。与 `hud.floor_prefix` 组成的
#      `F100` 同一个词根；改成「回100 层」会让按钮与 HUD 楼层号**读法不一致**。
#   ② `hud.floor_prefix = "F"` —— HUD 楼层号前缀，同上。
#   ③ `GameConstants.DEPART_KEY_LABEL = "E"` —— **键名**（不在本表，见该常量注释）。
#      所有提示语里的键（F / E / Tab / M / V）都属于这一类，一律保留。
#   ⚠ 除以上三类外，**任何**面向玩家的英文散文都必须回中文
#     —— 由 `--verify-loc ①` 逐条断言（它只对上面这些 key 开白名单）。
# ==============================================================================
extends Node

## 已注册的语言 id（本批**只有**简体中文；加语言时在此登记即可）
const SUPPORTED: Array[String] = ["zh_CN"]

## 默认语言
const DEFAULT_LOCALE: String = "zh_CN"

## ⚠⚠ **单一文案表**——全工程**屏幕空间**面向玩家的文案**只允许**出现在这里。
##   任何 `scenes/ui/*` 的 `draw_string` / `Label.text` 都必须走 `Loc.t("<key>")`，
##   不得就地写字面量。（`--verify-loc ①` 逐条断言本表 value 不含英文散文。）
##   🔴 **R-128 铁律 · 世界空间（`scenes/world|player|enemies|furniture|weapons/`）
##   一律禁止任何文字** —— 用户逐字：「游戏场景内不能出现类似的提示性文字，
##   游戏场景的文字只能出现在美术素材中。」世界物件的语义只能靠**美术素材 + 形状/颜色/动态**表达。
##   机器守护：`--verify-loc ①-d` 对上述目录做源码 grep，出现 `draw_string(` 即 FAIL。
##   ⚠ 分界线是**空间**：`hint.*` / `toast.*` 走底部 hint 通道（`scenes/ui/Hint.gd`），
##     属屏幕空间 UI，**允许**有文字。
##
## 【键名约定】`<界面域>.<语义>`，全小写下划线（与既有代码的 snake_case 风格一致）：
##   · `hint.*`底部交互提示通道（`Hint.gd`，底部居中，**可用宽 200px @ font 8**）
##   · `toast.*`    瞬时提示（同一条 hint 通道，会压过常驻提示）
##   · `depart.*`   第 100 层出发瓦片相关的**屏幕空间** UI（出发确认框）+ 屏幕底部提示
##                  🔴 R-128：`depart.label`（方块下方的世界空间文字标签）**已删除**
##   · `return.*`   右下角返回按钮（**保留 ASCII 代号**，见文件头「保留 ASCII」段）
##   · `hud.*`      HUD 常驻（**保留 ASCII 代号**）
##   · `backpack.*` 背包面板标题 + 悬停说明（font 8 / font 7）
const T_ZH_CN: Dictionary = {
	# ---- 交互提示：靠近箱子 ----
	# ⚠ 前缀与类型名**分开**：类型名来自 `GameConstants.CRATE_TYPES[kind]["label"]`
	#   （R-107 建立的单一真相源，见 `--verify-cratetype` ⓪），前缀才归Loc 管。
	"hint.crate_open_prefix": "按 F 打开",
	"hint.crate_open_generic": "按 F 打开箱子",
	# ---- 瞬时提示：V 键「全地图箱子都开过」 ----
	# ⚠ 用户拍板时长 1.5s（`TRACE_REJECT_TOAST_SECONDS`），本条**只管文案不管时长**。
	"toast.crates_all_opened": "全部箱子已打开",
	# ---- 第 100 层出发（🔴 R-128：`depart.label` 已删，见文件头「世界空间禁止文字」铁律）----
	"depart.prompt": "按 F 进入下一层",
	# ---- R-119 出发确认框 ----
	"depart.confirm.title": "出发确认",
	"depart.confirm.body": "是否离开基地，前往下一层？",
	"depart.confirm.keys": "F 确认    Esc 取消",
	# ---- 返回按钮 / HUD 楼层号：**刻意保留 ASCII**，见文件头「保留 ASCII」段 ----
	"return.floor_label": "F100",
	"hud.floor_prefix": "F",
	# ---- 背包：面板标题 + 悬停说明第2 行 ----
	# ⚠ `%.1f` / `%d` 是**格式说明符**不是文案，`--verify-loc ①` 会先剥掉它们再查英文。
	"backpack.panel_load": "负重 %.1f / %.0f",
	"backpack.desc_heal": "回血 %d",
	"backpack.desc_weight": "重量 %.1f",
}

## 当前语言 id
var _locale: String = DEFAULT_LOCALE

func _ready() -> void:
	# 兜底：万一项目设置里把autoload 顺序改了导致本节点不是第一个，
	# `_locale` 也必须是已登记的语言（`t()` 会拒绝未登记 id 并回退默认语言）。
	if not SUPPORTED.has(_locale):
		_locale = DEFAULT_LOCALE


## 查表取文案。**查不到时返回 key 本身**（见文件头「回退」段）。
## ⚠ 这是全工程取文案的**唯一**入口 —— 不要在别处直接读 `T_ZH_CN`，
##   否则绕过 `set_locale()` 就永远切不了语言。
func t(key: String) -> String:
	if key == "":
		return ""
	var tbl: Dictionary = _table()
	if tbl.has(key):
		return String(tbl[key])
	# ⚠ 回退到 key 本身：**故意不返回空串**（理由见文件头）。
	return key


## 当前语言的整张表（未登记 id → 默认语言表）。
func _table() -> Dictionary:
	match _locale:
		"zh_CN":
			return T_ZH_CN
	return T_ZH_CN


## 切换语言。返回是否切换成功（未登记的 id 返回 false 且**不改**当前语言）。
## ⚠ 本批**只注册 `zh_CN`**，所以除 `"zh_CN"` 外一律 false —— 这是刻意的：
##   没有第二个语言时静默"切换成功"等于骗人。
##   （将来加语言：往 `T_ZH_CN` 旁并列一张表 + 往 `SUPPORTED` 加 id + `_table()` 加分支。）
func set_locale(id: String) -> bool:
	if not SUPPORTED.has(id):
		return false
	_locale = id
	return true


func get_locale() -> String:
	return _locale


## 该 key 在当前语言下是否真的有词条（用于区分"查得到"与"回退到 key"）。
func has_key(key: String) -> bool:
	return _table().has(key)


## 当前语言的 key 列表（`--verify-loc ①` 遍历用）。
func keys() -> Array:
	return _table().keys()


# ======================================================================
# ==== R-117 宽度核算（供 `--verify-loc ④` 调用；**不参与任何绘制**）====
# ======================================================================
## 用**真实字体度量**量一段文案在给定字号下的像素宽度。
## ⚠ 为什么不用"字符数 × 经验值"：`Backpack.gd` 画悬停框时用的是
##   `6.0 + len * 6.0` 这种**按字符数估**的公式，而中文字宽（font 7 实测 7px/字）
##   与 ASCII（约 4px/字）**不一样** —— 估出来的框只保证"装得下估的宽度"，
##   不保证"装得下真实墨迹"。`--verify-loc ④` 用本函数拿真实值来核对。
static func text_width(text: String, font_size: int) -> float:
	if text == "":
		return 0.0
	# ⚠ 与 `draw_string(..., HORIZONTAL_ALIGNMENT_LEFT, -1, size)` 完全同参。
	return GameConstants.ui_font().get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x