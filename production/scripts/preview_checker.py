# -*- coding: utf-8 -*-
"""棋盘底预览：验证抠图无白边 + 看目标尺寸下的剪影可辨性。"""
import sys
from PIL import Image

def checker(w, h, cell=8):
    bg = Image.new("RGBA", (w, h), (60, 60, 66, 255))
    px = bg.load()
    for y in range(h):
        for x in range(w):
            if ((x // cell) + (y // cell)) % 2 == 0:
                px[x, y] = (90, 90, 96, 255)
    return bg

src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA")
# 等比缩放到 target 内接尺寸
ratio = min(target / im.width, target / im.height)
sw, sh = max(1, round(im.width * ratio)), max(1, round(im.height * ratio))
small = im.resize((sw, sh), Image.NEAREST)   # 像素风用 NEAREST
# 拼两个：原尺寸放大2x + 目标尺寸放大6x
scale_big = 2
big = im.resize((im.width * scale_big, im.height * scale_big), Image.NEAREST)
zoom = 6
tiny = small.resize((sw * zoom, sh * zoom), Image.NEAREST)
pad = 16
W = big.width + pad * 3 + tiny.width
H = max(big.height, tiny.height) + pad * 2
canvas = checker(W, H, 10)
canvas.alpha_composite(big, (pad, pad))
canvas.alpha_composite(tiny, (pad * 2 + big.width, pad))
canvas.convert("RGB").save(dst)
print("OK -> %s | 原 %s -> 目标 %d 内接 %s (x%d 放大另存)" % (dst, im.size, target, (sw, sh), zoom))
