# -*- coding: utf-8 -*-
"""AI 武器图 → 真透明 PNG + 缩放到目标尺寸（技能 Step 2）。
坑：AI 图生图的 background:transparent 不生效，一律靠本地近白阈值抠图。"""
import sys, os
from PIL import Image, ImageDraw, ImageFilter

THRESH_L = 244      # 亮度 >= 此值算近白背景
FEATHER = 0.8       # alpha 羽化，消白边

def matte(src_path, dst_path):
    im = Image.open(src_path).convert("RGB")
    w, h = im.size
    L = im.convert("L")
    # ⚠ 用「全局近白 → 透明」而不是「四角 floodfill」：
    #   武器图标主体是深色金属/木色、**不含纯白**，而手枪的扳机护圈 / 枪管镂空是
    #   **闭合孔洞** —— 四角 floodfill 灌不进去、会残留白块（校准帧实测踩到）。
    #   全局近白能把闭合孔洞一并透明化；阈值 244 足够高于主体最亮的浅灰（~180）。
    alpha = L.point(lambda v: 0 if v >= THRESH_L else 255)
    alpha = alpha.filter(ImageFilter.GaussianBlur(FEATHER))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    # 裁到 alpha 的紧致包围盒（去空白边）
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    out.save(dst_path)
    # 透明率
    a = out.getchannel("A")
    px = list(a.getdata())
    trans = sum(1 for v in px if v == 0) / max(1, len(px))
    return out.size, trans

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    size, trans = matte(src, dst)
    print("OK %s -> %s | cropped=%s transparent=%.1f%%" % (src, dst, size, trans * 100))
