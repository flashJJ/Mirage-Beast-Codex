# -*- coding: utf-8 -*-
"""立绘后处理：抠背景 → 裁剪 → 补边距 → 缩放 512 → 边缘半透明化。

背景形态有两种（教训记录见 docs/ART-PIPELINE.md §3）：
  a) 纯白/浅灰底（beast_001~003）
  b) 棋盘格假透明（生成器把"透明底"的棋盘纹理画进图里，beast_004/006/008）
棋盘格两色都接近白色，BFS 阈值 205 能同时吃掉；格子口袋由二次清理处理。

用法：python portrait_process.py
"""
import io
import os
from collections import deque

from PIL import Image

RAW_DIR = os.path.join("assets", "raw")
OUT_DIR = os.path.join("assets", "portraits")
THRESH = 205          # r,g,b 全部 >= 该值视为浅色（棋盘两色都必须 >= 它）
EDGE_ALPHA = 150      # 1px 边缘半透明，去白边
FINAL = 512           # 输出尺寸
PAD = 32              # 四周留白
CLEAN_ITER = 60       # 二次清理最大迭代（吃掉与外部连通的格子口袋）


def load_flat(path):
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    return Image.alpha_composite(bg, im)


def bfs_edges(pix, w, h):
    """从四边泛洪，删除所有与边缘连通的浅色像素。返回删除集合。"""
    removed = set()
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if min(pix[x, y][:3]) >= THRESH and (x, y) not in removed:
                q.append((x, y)); removed.add((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if min(pix[x, y][:3]) >= THRESH and (x, y) not in removed:
                q.append((x, y)); removed.add((x, y))
    while q:
        x, y = q.popleft()
        for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in removed:
                if min(pix[nx, ny][:3]) >= THRESH:
                    removed.add((nx, ny)); q.append((nx, ny))
    return removed


def clean_pockets(pix, w, h, removed):
    """二次清理：与透明区相邻的浅色像素反复剥除（棋盘格口袋）。"""
    for _ in range(CLEAN_ITER):
        frontier = set()
        for (x, y) in removed:
            for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in removed:
                    if min(pix[nx, ny][:3]) >= THRESH:
                        frontier.add((nx, ny))
        if not frontier:
            break
        removed |= frontier
    return removed


def process(src, dst):
    im = load_flat(src)
    w, h = im.size
    pix = im.load()
    removed = bfs_edges(pix, w, h)
    removed = clean_pockets(pix, w, h, removed)

    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    opix = out.load()
    for y in range(h):
        for x in range(w):
            if (x, y) in removed:
                continue
            r, g, b, _ = pix[x, y]
            opix[x, y] = (r, g, b, 255)

    # 1px 边缘半透明化
    for y in range(h):
        for x in range(w):
            r, g, b, a = opix[x, y]
            if a == 0:
                continue
            for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
                if not (0 <= nx < w and 0 <= ny < h) or opix[nx, ny][3] == 0:
                    opix[x, y] = (r, g, b, EDGE_ALPHA)
                    break

    bbox = out.getbbox()
    if bbox is None:
        raise SystemExit("%s 全空，抠图失败" % src)
    crop = out.crop(bbox)
    side = max(crop.size)
    canvas = Image.new("RGBA", (side + PAD * 2, side + PAD * 2), (0, 0, 0, 0))
    canvas.paste(crop, (PAD + (side - crop.width) // 2, PAD + (side - crop.height) // 2))
    canvas = canvas.resize((FINAL, FINAL), Image.LANCZOS)
    canvas.save(dst, optimize=True)
    kept = 100.0 * (w * h - len(removed)) / (w * h)
    print("%s -> %s  保留 %.1f%%  bbox=%s" % (src, dst, kept, bbox))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for bid in ("beast_004", "beast_005", "beast_006", "beast_007", "beast_008"):
        src = os.path.join(RAW_DIR, "%s_raw.png" % bid)
        dst = os.path.join(OUT_DIR, "%s.png" % bid)
        if os.path.exists(src):
            process(src, dst)


if __name__ == "__main__":
    main()
