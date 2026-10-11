# Crate · 箱子（家具，R-65 新增）
# 碰撞层 = 16：玩家 mask 含 16 → 玩家不能穿过；子弹 mask（友 13 / 敌 7）不含 16 → 子弹可穿过。
# 靠近后提示「按 F 打开」（交互与物品生成在 Main）；首次打开时随机生成物品。
#
# ==== R-104：箱子分 4 类（武器/医疗/食品/材料），每类只刷自己那类物品 ====
# 【为什么 `kind` 存在 Crate 上、而不是开箱时才随机】
#   玩家必须**在跑过去之前**就看出"这是个医疗箱"—— 类型若是开箱瞬间才决定的，
#   玩家永远看不到任何类型线索，`color` 就成了摆设（`--verify-cratetype` 守这条）。
#   → 类型由生成器 `FloorGenerator` 在**布局时**按 `seed` 定好（见 `crate_kinds`），
#     Main 建节点时写进本字段。
# 【`Crate.tscn` 刻意零改动】
#   颜色在运行时设 `Sprite.color`，而不是拆 4 个 `.tscn`：
#     ① 少 4 个文件，生成侧仍只实例化**同一个** CrateScene（Main 无需分支）；
#     ② 类型→颜色是 GameConstants.CRATE_TYPES 的**数据映射**，加第 5 种箱子 = 加一行字典；
#     ③ tscn 里的 `StaticBody2D(collision_layer=16)` + 12×12 碰撞盒**原封不动**
#        → R-93 建立的"家具层 16 / 12×12"成果零风险。
#   → tscn 里那个 `Color(0.55, 0.42, 0.25)` 保留为**无类型箱子的兜底色**
#     （`kind == ""` 时不染色，兼容 `--verify-enemyclash` 等手工实例化的裸箱子）。
#
# ==== R-133：4 类 × 2 态（关/开）= 8 张 16×16 像素精灵接入 ====
# 【为什么又加一条「外观」路径，而不是替换 R-104 的 `Sprite.color` 色块】
#   R-104 用 4 个纯色块区分箱子类型（玩家靠颜色猜类型），R-133 用户要求换成能一眼看出
#   「这是什么箱 / 开没开」的美术精灵。做法是**叠加**而非替换：
#     · kind 合法 → 运行时 new 一个 `Sprite2D`（名 `CrateArt`）显示 `{kind}_{closed|open}.png`，
#       并把 tscn 里的 `Sprite`(Polygon2D) **隐藏** → 绝不让「色块 + 精灵」同时可见（双重外观）。
#     · kind 为空 / 未知（储藏室储物箱、手工裸箱子）→ **保留** Polygon2D 兜底外观（R-104 语义不变）。
#     · 精灵缺失（未 import / 路径写错）→ **可见地降级**回 Polygon2D（`_apply_kind_color` 已染类型色），
#       而不是画一片空白 —— 与 TileGround / StaticFloor 的「坏数据要看得见」同一取舍。
#   `Crate.tscn` **零改动**（与 R-104/R-123 同款：少一个回归面，12×12 碰撞盒 / layer 16 原封不动）。
extends StaticBody2D
class_name Crate

# R-133：精灵节点名 + 目录（`crate_sprite_path()` 与 `--verify-crate-sprite` 共用同一规则）。
const CRATE_ART_NODE := "CrateArt"
const CRATE_SPRITE_DIR := "res://assets/sprites/crates/"

var items: Array = []      # 容器内的物品（Dictionary 列表）
var opened: bool = false   # 是否已生成过物品
# R-104：箱子类型 id（"weapon"/"medical"/"food"/"material"）。"" = 未指定（不染色）。
# ⚠ 这是**唯一**的类型真相源：`Main._roll_container_items()` 按它选池，
#   外观颜色也按它取 —— 二者共用一个字段，杜绝"看起来是医疗箱、刷出材料"这类不一致。
var kind: String = ""
# R-119：装饰性箱子（储藏室 25 个空箱）。true = 不加入 "crates" 组（F 键开不到）、
#   且 Main 生成时会把它碰撞层清 0（玩家可穿过）。语义 = 纯储物占位，不可交互。
var decorative: bool = false
# R-119：预置内容（起始房间宝箱）。非空数组 = 开箱时**不随机 roll**，直接用它。
#   例：["pistol", "ammo_9x19"]。空数组 = 走既有随机 roll 路径（普通箱子）。
var preset_items: Array = []
# R-120：储物箱（储藏室 25 个）。物品**持久化到存档文件**（`user://base_storage_save.json`），
#   重开游戏不丢。与 decorative 的区别：storage 箱子**入组可交互**（F 键能打开存/取），
#   但仍保持无碰撞（用户拍板「不和玩家产生碰撞」）。物品由 Main 从存档加载，
#   不随机 roll（`opened` 在生成时即置 true，跳过 `_toggle_container` 的 roll 分支）。
var storage: bool = false

func _ready() -> void:
	if not decorative:
		add_to_group("crates")
	_apply_kind_color()
	_refresh_art()

# R-104：设定箱子类型并立即刷新外观。
# ⚠ 单独暴露一个方法（而不是只靠 Main 写字段）是为了让**调用顺序**无关：
#   Main 在 `add_child()` 之前设置 → `_ready()` 会染一次；在 `add_child()` 之后设置 → 本方法染。
#   两种顺序都正确（否则会出现"设了 kind 但颜色还是旧色"的时序坑）。
func set_kind(k: String) -> void:
	kind = k
	_apply_kind_color()
	_refresh_art()

# R-133：开/关状态变化时刷新外观。Main 在**开箱处**（`_toggle_container`）调用它，
#   保证「刚打开」的箱子立刻由 `{kind}_closed.png` 变为 `{kind}_open.png`。
# ⚠ 与 `set_kind()` 同款思路：单独暴露方法让调用顺序无关 —— 生成时先 `set_opened(true)`
#   再 `add_child()`，`_ready()` 的 `_refresh_art()` 会再兜一次。
func set_opened(v: bool) -> void:
	opened = v
	_refresh_art()

# R-133-STORAGE：无 kind 但属于「基地仓储 / 预置内容」的箱子 → 走专属储物箱精灵。
# ⚠ 刻意**不**把 kind=="" 一律指向储物箱：手工 new 出来的裸箱子（--verify-enemyclash 等）
#   必须继续走 Polygon2D 兜底，否则会静默改变既有测试语义。
func uses_storage_art() -> bool:
	return storage or not preset_items.is_empty()

# R-133：按 `kind` + `opened` 选纹理路径（纯函数，便于 `--verify-crate-sprite` 逐字断言）。
# R-133-STORAGE：储物箱（storage / 预置内容）走 `storage_{closed|open}.png`。
func crate_sprite_path() -> String:
	var k: String = "storage" if uses_storage_art() else kind
	return "%s%s_%s.png" % [CRATE_SPRITE_DIR, k, ("open" if opened else "closed")]

# R-133：刷新外观（has_art 判定 / opened 变化 / 纹理缺失全部在此收敛）。
#   ⚠ 三态严格互斥：① has_art（= uses_storage_art() 或合法 kind）+ 纹理到位 → 精灵可见、色块隐藏；
#     ② 纹理缺失 → 降级回色块（可见地暴露问题）；③ 无可用美术（裸箱子）→ 色块兜底。
#     「精灵与色块同时可见」是**禁止**的（会造成双重外观）。
func _refresh_art() -> void:
	var fallback := get_node_or_null("Sprite") as Polygon2D
	var art := get_node_or_null(CRATE_ART_NODE) as Sprite2D
	# ① 无可用美术（裸箱子）→ 走 Polygon2D 兜底
	#   R-133-STORAGE：可用美术 = 储物箱（storage / 预置内容）**或** 合法 kind。
	var has_art: bool = uses_storage_art() or (kind != "" and GameConstants.CRATE_TYPES.has(kind))
	if not has_art:
		if art != null:
			art.visible = false
		if fallback != null:
			fallback.visible = true
		return
	# ② kind 合法 → 载入对应精灵
	var tex := load(crate_sprite_path()) as Texture2D
	if tex == null:
		# 纹理缺失（未 import / 路径错）→ 降级回色块（`_apply_kind_color` 已把色块染成类型色）
		if art != null:
			art.visible = false
		if fallback != null:
			fallback.visible = true
		return
	if art == null:
		art = Sprite2D.new()
		art.name = CRATE_ART_NODE
		add_child(art)
	art.texture = tex
	art.visible = true
	if fallback != null:
		fallback.visible = false

# 按 kind 染 `Sprite`（tscn 里那个 12×12 的 Polygon2D）。`kind` 为空/未知 → 保持 tscn 原色，不报错。
# ⚠ 写的是 `Polygon2D.color`（顶点色）而**不是** `CanvasItem.modulate`：
#   tscn 已经给了 `color = Color(0.55,0.42,0.25)`，若再乘一层 modulate 会变成"两次染色"，
#   实际显示色 ≠ 常量里登记的颜色 → `--verify-cratetype` ④ 断言的就是"显示色 == 常量色"，会被这个坑打中。
# ⚠ 用 `get_node_or_null` 而非 `$Sprite`：手工 new 出来、没挂 tscn 结构的 Crate 不会崩。
func _apply_kind_color() -> void:
	if kind == "" or not GameConstants.CRATE_TYPES.has(kind):
		return
	var def: Dictionary = GameConstants.CRATE_TYPES[kind]
	if not def.has("color"):
		return
	var spr := get_node_or_null("Sprite")
	if spr is Polygon2D:
		(spr as Polygon2D).color = def["color"]
