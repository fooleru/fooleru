# Corpse · 敌人尸体（R-new 用户需求，2026-10-13）
# 【用户需求逐字】
#   「敌人死后会留下尸体，里面包含1到3件战利品。敌人尸体也和箱子一样，玩家靠近后出现
#     按'F'键搜索的提示，玩家按F后打开箱子界面。如果地面上同一瓦片内有多具尸体那么将
#     战利品合并到一个尸体内（即同一瓦片内存在多具尸体则仅保留一具）。」
#
# 【为什么是 Node2D 而不是 StaticBody2D（与 Crate 的关键差异）】
#   尸体**不挡玩家**：Crate 有 12×12 碰撞盒（layer 16）因为"箱子是障碍物"；
#   而尸体是"地上的残骸"，挡路会让玩家在窄走廊/门口被尸体卡住（近战场景尤其致命）。
#   → 本类**无任何 CollisionShape**，玩家与子弹直接穿过。
#
# 【为什么鸭子类型对齐 Crate（items/opened/preset_items/kind/set_opened）】
#   Main._toggle_container / _update_hint / _open_backpack 全部按 Crate 的字段名工作，
#   尸体提供**同名同义**字段 → 交互链路零分支复用（只有 roll 那一处需区分，见 `loot_ready`）。
#
# 【⚠⚠ 绝不加入 "crates" 组 —— R-110 用户铁律】
#   R-110 用户逐字：「只显示宝箱，**不包括敌人尸体**」（V 键扫描标记）。
#   Main.gd `_build_trace_arrows` 注释段亦警告过：「将来若加入尸体系统，必须复查这里：
#   新尸体节点若也进 crates 组会被误标」→ 故本类只进 **"corpses"** 组。
#
# 【战利品在死亡时就 roll 好（loot_ready = true）】
#   箱子的物品是"开箱瞬间才 roll"（R-104：类型必须开箱前可见）；
#   尸体的战利品必须**死亡瞬间**定好 —— 否则"同瓦片合并"无从实现（合并的是已 roll 的
#   物品列表，不是"再 roll 一次的概率"）。
#   → `_toggle_container` 的 roll 分支用 `loot_ready` 跳过（物品已在 `items` 里）。
extends Node2D

const CORPSE_ART_NODE := "CorpseArt"

var items: Array = []          # 战利品（Dictionary 列表；死亡时 roll 好）
var opened: bool = false       # 是否已被搜索过
var preset_items: Array = []   # 对齐 Crate 接口（尸体恒空 → 不走 preset 分支）
var kind: String = ""          # 尸体无类型（对齐 Crate 接口；hint 走 corpse 专门文案）
var loot_ready: bool = true    # 战利品已就绪 → Main 跳过 roll 分支
var tile: Vector2i = Vector2i.ZERO  # 死亡瓦片格（同格合并的唯一键）

func _ready() -> void:
	# ⚠ 只进 "corpses" 组：V 扫描（R-110）只标 "crates" 组，尸体不得被误标。
	add_to_group("corpses")

# 生成尸体外观 + 定位。`tex`/`spr_scale` 取自死亡敌人的 EnemyArt（保持"看得出原本是什么怪"）。
# tex == null（敌人没有精灵节点）→ 画兜底色块（坏数据要看得见，不画空白）。
# ⚠⚠ **`region` / `region_enabled` 必须一起带**（R-new 修复"一个死后一大片死尸"）：
#   Zombie 的 EnemyArt 是 R-153 图集模式（`region_enabled=true` + `region_rect` 选帧，
#   图集 256x256 = 4 帧 x 4 朝向）。只复制 texture/scale 而漏掉 region ->
#   Sprite2D 按默认（region_enabled=false）画**整张图集** = 16 只僵尸平铺成一片。
#   单帧模式（Brute/Merc/Splitter）的 region_enabled=false -> 两个参数天然无副作用。
func setup(pos: Vector2, tex: Texture2D, spr_scale: Vector2, t: Vector2i,
		region: Rect2 = Rect2(), region_enabled: bool = false) -> void:
	position = pos
	tile = t
	var art := Sprite2D.new()
	art.name = CORPSE_ART_NODE
	art.centered = true
	art.offset = Vector2(0, 0)
	art.rotation = PI * 0.5          # 躺平（与"站立敌人"形成可读差异）
	art.modulate = Color(0.55, 0.5, 0.5, 0.9)   # 压暗 = 死亡感（半透明可透出地面细节）
	if tex != null:
		art.texture = tex
		art.scale = spr_scale
		art.region_enabled = region_enabled
		if region_enabled:
			art.region_rect = region
	add_child(art)
	if tex == null:
		# 无贴图兜底：暗红色块（12×12，与家具同规格），保证"这里有东西"看得见
		var blob := Polygon2D.new()
		blob.polygon = PackedVector2Array([Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)])
		blob.color = Color(0.45, 0.15, 0.15)
		add_child(blob)

# 对齐 Crate.set_opened（Main 开箱/搜索处调用）。
func set_opened(v: bool) -> void:
	opened = v

# 同瓦片合并：把另一具尸体的战利品并入本具（节点本身不创建、不销毁）。
func add_loot(more: Array) -> void:
	for it in more:
		items.append(it)
