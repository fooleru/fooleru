# Furniture · 家具瓦片（R-155 新增 · 4 档功能分档）
# ==============================================================================
# 【本文件解决什么】
#   地图原本只有「地板 / 墙 / 箱子」三种格子语义，房间内部空荡且功能单一。
#   本节点给房间内补上**家具**：按**功能**分 4 档（而非按外观分），每档的物理行为
#   严格复用工程既有的碰撞层体系，不新造一套判定。
#
# 【四档 → 碰撞层映射（唯一权威在 `GameConstants.FURNITURE_TYPES` 的 `cat`）】
#   a 挡一切（=墙）      → collision_layer = 1  （LOS 射线只查 layer 1，故 a 必然挡视线）
#   b 仅视线穿过         → collision_layer = 32 （LOS mask 恒为 1，不含 32 → 视线穿过；
#                                                但 32 已加进玩家/敌人/两种子弹的 mask → 其余全挡）
#   c 视线+子弹穿过（=箱）→ collision_layer = 16 （与 `Crate.tscn` 完全相同，零改动）
#   d 全穿过（=地板）    → 不建碰撞形状、layer/mask 归 0，只画精灵
#   ⚠ a/b/c 三档**还必须**由 Main 把对应格子写进 NavGrid 置 0 ——
#     NavGrid 只读 `PackedByteArray`、**完全不读物理**（见 `NavGrid.set_grid`），
#     只建碰撞体不置网格 → 敌人寻路会直接穿过家具。
#
# 【为什么代码 new 而不新建 Furniture.tscn】
#   与工程既有取舍一致（R-112 / R-123 / R-144：少一个 .tscn = 少一个回归面）。
#   家具 16 种的差异只有「精灵 + 分档」，用 `fid` / `fcat` 两个变量表达即可，
#   不需要 16 个场景文件，也不需要 4 个（每档一个）。
#
# 【精灵缺失时**可见地降级**，不画空白】
#   与 Crate(R-133) / TileGround / StaticFloor 同一取舍：纹理没 import 或路径写错时，
#   退化成一块**分档染色**的 12×12 色块 —— 让人一眼看出"这里有个家具，但图没接上"，
#   而不是"这里什么都没有"（后者会被误判成生成器漏摆）。
# ==============================================================================
extends StaticBody2D

const FURN_ART_NODE := "FurnArt"
const FURN_SPRITE_DIR := "res://assets/sprites/furniture/"

## 家具 id（对应 `GameConstants.FURNITURE_TYPES[].id`）
var fid: String = ""
## 功能分档 a / b / c / d（由 id 查表得出，也可外部直接指定）
var fcat: String = ""

var _art: Sprite2D = null
var _fallback: Polygon2D = null

func _ready() -> void:
	if fcat == "":
		fcat = GameConstants.furniture_cat(fid)
	_apply_cat()
	_refresh_art()

# 分档 → 碰撞层/形状。**只动本节点**，不动任何既有 tscn 或 mask 语义。
func _apply_cat() -> void:
	# 先清干净：d 档复用同一节点类型但不参与任何碰撞
	collision_layer = 0
	collision_mask = 0
	for c in get_children():
		if c is CollisionShape2D:
			c.queue_free()
	match fcat:
		"a":
			collision_layer = 1      # = 墙
		"b":
			collision_layer = 32     # 仅视线穿过（LOS mask=1 不含 32）
		"c":
			collision_layer = 16     # = 箱子
		_:
			return                   # d（或未知档）：无碰撞体
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(12, 12)        # 与 Crate 同款 12×12（"家具层"既有口径）
	cs.shape = sh
	add_child(cs)

# 只读探针：闸门用它断言"这档家具到底挡不挡"（不依赖物理实测，便于单点验证）。
func blocks_sight() -> bool:
	return fcat == "a"          # 只有 a 在 LOS 的 mask 1 里
func blocks_bullet() -> bool:
	return fcat == "a" or fcat == "b"
func blocks_body() -> bool:
	return fcat == "a" or fcat == "b" or fcat == "c"
func needs_nav_block() -> bool:
	return blocks_body()

# 精灵接入（三态互斥：精灵可见 XOR 色块可见，禁双重外观）。
func _refresh_art() -> void:
	if _fallback != null and is_instance_valid(_fallback):
		_fallback.queue_free()
		_fallback = null
	var tex: Texture2D = null
	if fid != "":
		var p: String = FURN_SPRITE_DIR + fid + ".png"
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	if tex != null:
		if _art == null:
			_art = Sprite2D.new()
			_art.name = FURN_ART_NODE
			_art.centered = true
			add_child(_art)
		_art.texture = tex
		_art.visible = true
		return
	# 降级：分档染色色块（可见地暴露"图没接上"）
	if _art != null:
		_art.visible = false
	var poly := Polygon2D.new()
	poly.name = "FurnFallback"
	poly.polygon = PackedVector2Array([
		Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)])
	poly.color = _fallback_color()
	add_child(poly)
	_fallback = poly

func _fallback_color() -> Color:
	match fcat:
		"a": return Color(0.42, 0.42, 0.46)   # 近墙的灰
		"b": return Color(0.55, 0.72, 0.78)   # 玻璃的冷蓝
		"c": return Color(0.55, 0.42, 0.25)   # 沿用箱子兜底色
		_:   return Color(0.35, 0.36, 0.30)   # 地毯/装饰的暗色
	return Color(0.5, 0.5, 0.5)

## 供 Main 调用：设置家具类型并重刷外观（add_child 前后均可，`_ready` 会再跑一次）。
func set_furniture(id: String) -> void:
	fid = id
	fcat = GameConstants.furniture_cat(id)
	if _art != null or _fallback != null:
		_apply_cat()
		_refresh_art()
