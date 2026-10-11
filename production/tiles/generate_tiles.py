# -*- coding: utf-8 -*-
"""
R-131 · 16px 环境瓦片生成器（程序化 · 硬像素 · 逐字节可复现）
================================================================================
【为什么瓦片必须代码生成，不能用 AI 出的 tileset sheet】
  R-126 已实测走完一遍完整链路（AI sheet → 找 gutter 切格 → 内缩去框 → 缩到 16px
  → 按真实地图铺），结论是**这条路不可用**，三条硬原因：
    ① AI 把每块瓦片画成「四边带亮框的独立小图」→ 平铺出来是一摞相框；
       内缩裁掉框后，剩下的内部纹理**仍然不是无缝的**（左右边缘像素不相等）。
    ② 用 BOX 降采样 = 把 246px 平均成灰糊（丢硬像素）；
       用 NEAREST 则把 AI 的随机噪点原样搬进每一格 → **同一格重复上百次**
       形成肉眼可见的点阵格子。
    ③ 门洞 / 转角格里是大片白底，会直接漏进场景。
  ⇒ 结论：**瓦片必须像素级自己定死**，才能保证「勾缝连续」这条无缝前提。

【本生成器怎么保证无缝（与离线参考实现 outputs/r126_tiles/make_tiles16.py 同源）】
  · 所有随机纹理都走 `h01(x, y, salt)`（**纯整数哈希，无全局 RNG**）
    → 同坐标同结果、**可复现**（对齐本项目 R-104「同 seed 同输出」铁律）。
  · 地板的缝线只画在**每格最左 1 列 / 最上 1 行** → 相邻格拼起来正好是一个
    周期的完整网格，不会出现「缝只在某些格」的错位。
  · 墙顶的砖缝按 **16px 周期**设计（砖高 8 = 每格 2 层；横缝在 y%8==4，
    竖缝按层奇偶错开 x%8==0 / x%8==4）→ 横向、纵向贴出去都严丝合缝。
    ⚠ 相位必须**由 16 的整数倍推导**（16 是 8 的整数倍），否则相邻格砖缝对不齐。
  · 邻接收边（北侧高光 / 东西暗线 / 墙脚落地阴影）**由地图邻接关系算**，
    不是从瓦片里抠的 —— 这才叫「墙的外轮廓」，单块瓦片里没有这个信息。
    → 这一段在**引擎侧**（`scenes/world/TileGround.gd`）做，不在本脚本。

【🔴 与离线参考实现的一处刻意分歧：禁止混色（mix）】
  离线预览 `make_tiles16.py` 用 `mix(a, b, t)` 做倒角与颗粒，那会产出**调色板
  之外的中间色**（抗锯齿色）。本脚本是**生产工具**，产出物直接进游戏，因此：
    **每一个像素的颜色必须逐字等于该主题声明的 8 个槽位之一。**
  代价：倒角/颗粒改成「在槽位之间做硬切换」而不是「连续插值」。
  收益：`--verify-tiles` ②「调色板纯净」这条断言才可能成立（零中间色）。
  ⚠ 这条约束顺带决定了两个**必须避开格心**的画法（否则格心命中率口径会破）：
    · 地板：亮颗粒**只出现在倒角线**（x==1 或 y==1），不撒在面上；
      暗颗粒用 `floor_grout`（属「地板格心允许的颜色」集合）。
    · 墙顶：横向砖缝相位取 y%8==4、竖缝按层奇偶错开，
      使得**格心 (8,8) 永远落在砖面**而不是砖缝上。
  这两条不是 aesthetics，是 `--verify-tiles` / 实机像素统计的**口径前提**，勿改。

【调色板来源 = **美术权威表，且只有这一份；缺文件立即硬失败，无任何回落**】
  · 唯一来源：`design/art/tile_theme_palettes.json`（美术侧产出的 5 主题 × 8 槽位，
    项目内路径）。生成器 / 引擎 / `--verify-tiles` **三方都直读这一份**。
  · 文件不存在 / 结构不符 / 槽位缺失 → **立即 `SystemExit`（非零退出）**，
    **不报错就跳过、不产出任何 PNG**（`load_palette()` 在任何 `im.save()` 之前，
    所以失败时磁盘上的 PNG 不受影响）。

  · 🔴🔴 **本文件曾经有过一份「art-bible §3.1 占位表」作为回落 —— 已删除，且不许再加**
    （R-131 第一版的真实事故，独立复核 quality-lead-tiles 2026-10-08 复现并确认）：
      · 占位表与美术表**40 个槽位里 33 个不一致**，突变层更被换成
        「腐绿 #4f6b3a + 黏液绿 #7fae3a」—— 美术已逐字否决
        （黏液绿 ≈ 毒绿 #9bcf3a，1px 砖缝满铺会被读成「毒」，违禁忌 43；
         腐绿与封锁层军绿 #3f4a36 明度只差 4.6 会撞色）；
      · 5 个主题的明度阶梯**全部单调性失败**，4 层 `wall_top` 比 `wall_face` 还暗
        → 墙顶在画面上读不出来（厚度关系反了）；
      · ⚠⚠ **最危险的不是色值，是它「静默」**：60 个 headless 入口**全绿**
        （每个入口只验「贴图能不能 load」，不验「贴图颜色对不对」）。
        调色板分叉只有**逐像素比对**才抓得到。
    → 故现在的口径是「**读不到就死**」：宁可停下，也不产出「能跑但是错的」瓦片。
    → ⚠ 独立复核已实测该保险有效：临时改名美术表 → RC=1 硬失败、
      输出 `FATAL 找不到美术调色板表`、**PNG 未被污染**；改名还原后30 张逐字节复现。
  · 🔴 **§3.2 语义色（玩家橙/血红/毒绿/电青/警告红/通行绿/鲜绿）一律不得进入
    环境瓦片**。art-bible §3.3 里 sublevel 主题的「终端青 #45d4e0」正是语义色，
    故美术表已改用同段的「冷光 #6f8bb0」——这不是审美选择，是语义隔离。

【输出】
  `assets/tiles/<theme>/floor_0..3.png`   16×16  地板 4 变体
  `assets/tiles/<theme>/wall_top.png`     16×16  墙顶面（砖砌，16px 周期）
  `assets/tiles/<theme>/wall_face.png`    16× 6  墙正面（含底座线）
  → 同输入**逐字节可复现**（无时间戳 / 无随机排序 / 无浮点累积）。

  ⚠ **不再写派生调色板 JSON**（R-131 第一版曾写 `assets/tiles/tile_palettes.json`
    给引擎与验证读 —— **已删除**）。那会形成**两个调色板真相源**
    （美术表 → 生成器 → 派生表 → 引擎/验证），任何一环没跟上就是静默分叉。
    引擎与验证现在**都直接读美术权威表**。

【自检（每次运行都做，失败即非零退出）】
  每主题每图打印 尺寸 + 颜色集合，并断言 颜色集合 ⊆ 该主题 8 槽位。
================================================================================
"""
import io
import json
import os
import sys

from PIL import Image

# ---- 常量（全部是**字面量**，R-96 教训：不许从别处推导）----
TILE = 16
FACE_H = 6
FLOOR_VARIANTS = 4
THEMES = ["base", "mansion", "mutation", "blockade", "sublevel"]
SLOTS = ["floor_field", "floor_grout", "floor_highlight",
         "wall_top", "wall_joint", "wall_face", "wall_plinth", "accent"]

PROJ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ROOT = os.path.join(PROJ, "assets", "tiles")

# ==============================================================================
# 调色板：JSON 优先，缺失则回落占位（逐个 hex 取自 art-bible，**非本脚本发明**）
# ==============================================================================
# ⚠ 占位表存在的唯一目的是「把管线打通」；美术侧 JSON 就位后跑一次本脚本即自动切换。
# ⚠ 所有 hex 都必须能在 art-bible 里找到出处（注释已标章节）。
# 🔴 **本文件不再有任何占位色表**（R-131 第二版，team-lead 纠正）
#   第一版在这里放了一份「art-bible §3.1 占位表」，理由是「美术表还没就位，先打通管线」。
#   **那个决定是错的**，实测代价：
#     · 5 个主题的 8 槽位共 40 个色里**33个与美术表不一致**；
#     · 突变层用了「腐绿 #4f6b3a + 黏液绿 #7fae3a」—— 美术已逐字否决
#       （黏液绿≈毒绿，1px 砖缝满铺会被读成「毒」，违禁忌 43；
#        腐绿与封锁层军绿 #3f4a36 明度只差 4.6 会撞色）；
#     · 五个主题的明度阶梯**全部单调性失败**，4 层 `wall_top` 比 `wall_face` 还暗
#       -> 「墙比地板暗」= 墙顶在画面上读不出来（厚度关系反了）。
#   → **占位色表已删除**。本脚本现在**只认美术权威表**：
#       `design/art/tile_theme_palettes.json`（项目内路径，`load()` 可直接读）
#     文件缺失 / 结构不符 / 槽位缺失 -> **立即失败退出**，绝不静默回落。
#     理由：调色板分叉是**静默缺陷**—— 60 个headless 入口全绿也抓不到
#     （每个入口只验「贴图能不能加载」，不验「贴图颜色对不对」）。
#     宁可停下，也不产出「能跑但是错的」瓦片。
PALETTE_JSON_REL = "design/art/tile_theme_palettes.json"   # 相对工程根


def hex2rgb(h):
    h = str(h).strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError("非法 hex: %r（期望 #rgb 或 #rrggbb）" % h)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def load_palette():
    """读**美术权威表** `design/art/tile_theme_palettes.json`（项目内路径）。

    🔴 **不再有占位回落**（见 PALETTE_JSON_REL 上方说明）：任何问题都**立即失败**。
    ⚠ schema（美术侧 v1，实测确认）：顶层是**数组**，每项
      `{id, name_cn, floor_min, floor_max, colors:{8槽位}, note}`。
      ⚠ **不是** `{themes:{id:{...}}}` 的字典形状 —— 第一版按字典写，结果读不到
      任何主题（`themes` 取到空 dict），于是「恰好」回落到占位表 —— 双重失败。
    返回：`{theme_id: {slot: (r,g,b)}}`
    """
    path = os.path.join(PROJ, PALETTE_JSON_REL)
    if not os.path.isfile(path):
        raise SystemExit(
            "FATAL找不到美术调色板表：%s\n"
            "       这是**美术权威表**（art-director-tiles 产出），**不允许占位回落**：\n"
            "       调色板分叉是静默缺陷 —— 全部 headless 入口照样全绿，\n"
            "       只有逐像素比对才能发现，而那正是本批要防的事。" % path)
    with io.open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)
    items = raw.get("themes") if isinstance(raw, dict) else raw
    if not isinstance(items, list):
        raise SystemExit("FATAL %s：`themes` 必须是**数组**（实测 schema v1），实际是 %s"
                         % (path, type(items).__name__))
    out = {}
    for it in items:
        tid = str(it.get("id", ""))
        if tid not in THEMES:
            continue
        cols = it.get("colors", {})
        pal = {}
        for s in SLOTS:
            if s not in cols:
                raise SystemExit("FATAL %s：主题 '%s' 缺槽位 '%s'（需要 8 个：%s）"
                                 % (path, tid, s, ", ".join(SLOTS)))
            pal[s] = hex2rgb(cols[s])
        out[tid] = pal
    missing = [t for t in THEMES if t not in out]
    if missing:
        raise SystemExit("FATAL %s：缺主题 %s（需要 %d 个：%s）"
                         % (path, missing, len(THEMES), ", ".join(THEMES)))
    print("palette: 读自 %s（%d 主题 x %d 槽位，**无占位**）" % (path, len(out), len(SLOTS)))
    return out, path


# ==============================================================================
# 确定性哈希（与离线参考实现逐字一致 —— 引擎侧也复刻同一算法）
# ==============================================================================
def h01(x, y, salt):
    """确定性哈希 -> [0,1)。纯整数运算，无全局 RNG，故可复现。"""
    h = (x * 374761393 + y * 668265263 + salt * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65536.0


# ==============================================================================
# ① 地板瓦片 16x16（4 变体）
# ==============================================================================
def floor_tile(pal, variant):
    """风格 B「厚墙砖缝」：大块石板 + 硬像素倒角 + 勾缝只在最左列/最上��。

    ⚠ **格心 (8,8) 只会是 floor_field 或 floor_grout**（见文件头「禁止混色」段）：
      亮色只出现在倒角线 x==1 / y==1，暗颗粒用 floor_grout。
      这条是「地板格心命中率」统计口径的前提，改画法必须同步改断言。
    """
    field = pal["floor_field"]
    grout = pal["floor_grout"]
    hi = pal["floor_highlight"]
    im = Image.new("RGB", (TILE, TILE), field)
    px = im.load()
    salt = 23 + variant * 1009
    for y in range(TILE):
        for x in range(TILE):
            v = h01(x, y, salt)
            if v < 0.07:
                px[x, y] = grout          # 暗颗粒（**不用第三色**，保持格心口径）
            elif x == 1 or y == 1:
                px[x, y] = hi             # 内倒角高光：石板有厚度
    # ---- 勾缝：只画每格最左 1 列 / 最上 1 行（最后画，优先级最高）----
    #   拼起来正好是一个 16px 周期的完整网格。
    for y in range(TILE):
        px[0, y] = grout
    for x in range(TILE):
        px[x, 0] = grout
    return im


# ==============================================================================
# ② 墙顶面 16x16（砖缝按 16px 周期 -> 横向纵向都严丝合缝）
# ==============================================================================
def wall_top(pal):
    """砖砌墙顶。

    ⚠ **相位不是随手取的**，两条硬约束：
      ① 横缝 y%8==4、竖缝按层奇偶错开（偶层 x%8==0 / 奇层 x%8==4）——
         因为 TILE=16 是砖高 8 的整数倍，相位在相邻格之间**自动对齐**。
      ② 倒角高光放在 y%8==3 / y%8==11（砖缝上一行）。
      ①② 合起来保证**格心 (8,8) 落在砖面上**（既不是横缝也不是竖缝），
      这是「墙顶格心 = wall_top」命中率口径的前提，勿改。
    """
    base = pal["wall_top"]
    joint = pal["wall_joint"]
    hi = pal["floor_highlight"]
    im = Image.new("RGB", (TILE, TILE), base)
    px = im.load()
    for y in range(TILE):
        even_layer = (y // 8) % 2 == 0
        for x in range(TILE):
            if y % 8 == 4:
                px[x, y] = joint                     # 横缝
            elif x % 8 == (0 if even_layer else 4):
                px[x, y] = joint                     # 竖缝（错缝砌）
            elif y % 8 == 3 or y % 8 == 11:
                px[x, y] = hi                        # 砖面倒角高光
    return im


# ==============================================================================
# ③ 墙正面 16 x FACE_H（含底座线）
# ==============================================================================
def wall_face(pal):
    """墙正面：上 1 行接顶面（转折），下 2 行是底座（把墙「踩实」在地上）。"""
    base = pal["wall_face"]
    joint = pal["wall_joint"]
    plinth = pal["wall_plinth"]
    top = pal["wall_top"]
    im = Image.new("RGB", (TILE, FACE_H), base)
    px = im.load()
    for y in range(FACE_H):
        for x in range(TILE):
            if y == 0:
                px[x, y] = top                       # 顶面 -> 正面的转折
            elif y >= FACE_H - 2:
                px[x, y] = plinth                    # 底座线
            elif x % 8 == 0:
                px[x, y] = joint                     # 竖向砖缝（对齐墙顶 8px 周期）
    return im


# ==============================================================================
# 自检 + 落盘
# ==============================================================================
def colors_of(im):
    # ⚠ 用 `list(im.getdata())` 而不是 `im.getcolors()`：后者的返回值形态
    #   在 Pillow 各版本间变过（曾返回 list of (count, color)），跨版本不稳。
    return sorted(set(list(im.convert("RGB").getdata())))


def check_and_save(name, im, pal, expect_wh):
    w, h = im.size
    ok_size = (w, h) == expect_wh
    cols = colors_of(im)
    allowed = sorted(set(pal.values()))
    extra = [c for c in cols if c not in allowed]
    print("    %-14s %2dx%-2d  颜色%2d 种  %s  %s" % (
        name, w, h, len(cols),
        " ".join("#%02x%02x%02x" % c for c in cols),
        "OK" if (ok_size and not extra) else
        ("尺寸错(期望 %dx%d)" % expect_wh if not ok_size else "!! 调色板外颜色 %s" % extra)))
    if not ok_size or extra:
        return False
    d = os.path.join(OUT_ROOT, name.rsplit("/", 1)[0])
    if not os.path.isdir(d):
        os.makedirs(d)
    im.save(os.path.join(OUT_ROOT, name))
    return True


def main():
    pal, src = load_palette()
    print("=== R-131 tile generator · TILE=%d FACE_H=%d · %d 主题 · 风格 B 厚墙砖缝 ===" % (
        TILE, FACE_H, len(THEMES)))
    if not os.path.isdir(OUT_ROOT):
        os.makedirs(OUT_ROOT)
    all_ok = True
    for tid in THEMES:
        p = pal[tid]
        print("  [%s]" % tid)
        # ---- 🔴 **可判定性**自检（本批实测踩出来的；不是审美检查，见下）----
        #   【为什么必须查】实机像素统计有两个判据：
        #     ① 地板格心 读到的颜色必须属「地板色系」；
        #     ② 墙脚处读到「地板色系」= **漏缝**。
        #   若某个**墙色系**槽位与某个**地板色系**槽位同色，判据②就在**原理上失效**
        #   —— 墙正面本身就会被当成漏缝。首跑实测就报出 12 个**假漏缝**
        #   （`mansion.wall_face` 与 `mansion.floor_grout` 都写了 #34384a）。
        #   ⚠ 这不是「颜色好不好看」，是**这个问题还能不能被判定**。
        #   ⚠ 故规则必须**精确**，不能写成「8槽位两两不同」—— 那会误报：
        #     · `floor_highlight` **本来就同时**画在地板倒角与墙顶倒角上（共用，合法）；
        #     · `accent` **根本没被任何瓦片使用**，它撞谁都不影响判定。
        #   → 判据只看「实际被画出来的颜色」：
        #     地板色系 = {floor_field, floor_grout, floor_highlight}
        #     墙色系   = {wall_top, wall_joint, floor_highlight, wall_face, wall_plinth}
        #     要求：两个色系各自内部无重复，且交集**恰好**只有 floor_highlight。
        floor_set = ["floor_field", "floor_grout", "floor_highlight"]
        wall_set = ["wall_top", "wall_joint", "floor_highlight", "wall_face", "wall_plinth"]
        def _dup(names):
            seen = {}
            d = []
            for n_ in names:
                h_ = "#%02x%02x%02x" % p[n_]
                if h_ in seen:
                    d.append("%s==%s(%s)" % (n_, seen[h_], h_))
                seen[h_] = n_
            return d
        dup_f = _dup(floor_set)
        dup_w = _dup(wall_set)
        cross = []
        for fn in ("floor_field", "floor_grout"):
            fh_ = "#%02x%02x%02x" % p[fn]
            for wn in ("wall_top", "wall_joint", "wall_face", "wall_plinth"):
                if "#%02x%02x%02x" % p[wn] == fh_:
                    cross.append("%s==%s(%s)" % (fn, wn, fh_))
        if dup_f or dup_w or cross:
            all_ok = False
            print("    <<< FAIL 撞色 -> 墙脚漏缝判据失效: 地板系内重复=%s 墙系内重复=%s 跨系撞色=%s" % (
                dup_f, dup_w, cross))
        else:
            print("可判定性: 地板色系 3 色互异 / 墙色系 5 色互异 / 跨系仅 floor_highlight 共用 -> OK")
        all_ok &= check_and_save("%s/floor_%d.png" % (tid, 0), floor_tile(p, 0), p, (TILE, TILE))
        for v in range(1, FLOOR_VARIANTS):
            all_ok &= check_and_save("%s/floor_%d.png" % (tid, v), floor_tile(p, v), p, (TILE, TILE))
        all_ok &= check_and_save("%s/wall_top.png" % tid, wall_top(p), p, (TILE, TILE))
        all_ok &= check_and_save("%s/wall_face.png" % tid, wall_face(p), p, (TILE, FACE_H))
        # ---- 4 变体必须互不相同（否则又退化成「同一纹理重复 N 次」的��阵）----
        datas = [floor_tile(p, v).tobytes() for v in range(FLOOR_VARIANTS)]
        uniq = len(set(datas))
        print("    %-14s %d 个变体 -> %d 种不同字节 %s" % (
            "floor_0..3", FLOOR_VARIANTS, uniq, "OK" if uniq == FLOOR_VARIANTS else "<<< FAIL"))
        if uniq != FLOOR_VARIANTS:
            all_ok = False
        # ---- 无缝性可判据：格心必须是「地板允许色」/「墙顶砖面色」----
        f = floor_tile(p, 0)
        ctr = f.getpixel((8, 8))
        if ctr not in (p["floor_field"], p["floor_grout"]):
            print("    <<< FAIL 地板格心 (8,8)=#%02x%02x%02x 不在 {field,grout} 内" % ctr)
            all_ok = False
        w0 = wall_top(p)
        ctr_w = w0.getpixel((8, 8))
        if ctr_w != p["wall_top"]:
            print("    <<< FAIL 墙顶格心 (8,8)=#%02x%02x%02x != wall_top #%02x%02x%02x"
                  % (ctr_w + p["wall_top"]))
            all_ok = False
        # ---- 勾缝连续性：第 0 列与第 0 行必须逐字等于 floor_grout ----
        col0 = [f.getpixel((0, y)) for y in range(TILE)]
        row0 = [f.getpixel((x, 0)) for x in range(TILE)]
        if any(c != p["floor_grout"] for c in col0) or any(c != p["floor_grout"] for c in row0):
            print("    <<< FAIL 地板第0列/第0行不等于 floor_grout（勾缝不连续）")
            all_ok = False

    # ⚠⚠ **不再写派生调色板 JSON**（R-131 第二版，team-lead 纠正）
    #   第一版把「本次实际用的 8 槽位」另存一份 `assets/tiles/tile_palettes.json`
    #   给引擎与验证读。那样会形成**两个调色板真相源**：
    #     美术表（权威）→ 生成器 → 派生表 → 引擎 / 验证
    #   任何一环改了另一环没跟上，就是**静默分叉**（第一版正是如此：
    #   派生表里全是占位色，而 60 个入口照样全绿）。
    # → 现在引擎与验证**都直接读美术表**（`res://design/art/tile_theme_palettes.json`），
    #   派生表已删除。单一真相源。
    print("  -> %s/<theme>/{floor_0..3,wall_top,wall_face}.png（调色板唯一真相源 = %s）"
          % (OUT_ROOT, PALETTE_JSON_REL))
    print("=== %s ===" % ("SELF-CHECK OK" if all_ok else "SELF-CHECK FAILED"))
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()