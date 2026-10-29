"""Toshkent xaritasi aktivlarini OpenStreetMap SVG eksportidan (osm2cdr, "Map of Tashkent") yaratadi.

Ishlatish (Python 3 + Pillow + numpy, Node + playwright/Chromium kerak):
    python3 tools/map/build_tashkent.py /yo'l/map.svg assets/map

Natija: assets/map/tashkent.webp (3200x3200, 2 m/piksel) va assets/map/tashkent_water.png (1600x1600 suv niqobi).
Dunyo: 6400x6400 birlik (1 birlik ~ 1 metr), markaz = Amir Temur xiyoboni (41.3111N, 69.2797E).
Xarita ma'lumotlari: (c) OpenStreetMap contributors (ODbL).
"""
import os
import re
import subprocess
import sys
from collections import deque

import numpy as np
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(OUT)
TMP = os.path.join(OUT, '_tmp')
os.makedirs(TMP, exist_ok=True)

CX, CY = 2749.8, 2565.5            # Amir Temur xiyoboni, SVG birliklarida (map.wld + EPSG:3857 dan hisoblangan)
GROUND = 4.858385231123688         # 1 SVG birligi = shuncha metr (Mercator masshtabi * cos(41.31))
WORLD_M = 6400
PX = 3200

s = open(SRC, encoding='utf-8').read()
marks = list(re.finditer(r'<g id="([^"]*)" inkscape:groupmode="layer"|<g id="(Shapes|Page|Background)"', s))
pos = [m.start() for m in marks] + [len(s)]
segs = {}
for i, m in enumerate(marks):
    key, k = (m.group(1) or m.group(2)), 0
    while key in segs:
        k += 1
        key = f'{m.group(1) or m.group(2)}#{k}'
    segs[key] = s[pos[i]:pos[i + 1]]
head = s[:pos[0]]
sys.path.insert(0, HERE)
import svg_layers as sl  # noqa: E402

# o'yinga haqiqiy yo'l sifatida yuklanadigan sinflar asosiy xaritadan olib tashlanadi (faqat xira kichik ko'chalar qoladi)
segs['Дороги_и_улицы'] = sl.strip_imported_roads(segs['Дороги_и_улицы'])
box_w = WORLD_M / GROUND
box = (CX - box_w / 2, CY - box_w / 2, box_w)
num = re.compile(r'-?\d+\.?\d*')


def keep_path(tag, margin=30):
    m = re.search(r' d="([^"]*)"', tag)
    if not m:
        return True
    n = num.findall(m.group(1))
    if len(n) < 2:
        return True
    xs, ys = [float(v) for v in n[0::2]], [float(v) for v in n[1::2]]
    x0, y0, w = box
    return not (max(xs) < x0 - margin or min(xs) > x0 + w + margin or max(ys) < y0 - margin or min(ys) > y0 + w + margin)


def filter_paths(seg):
    out, last = [], 0
    for m in re.finditer(r'<path\b[^>]*?/>|<path\b[^>]*?>.*?</path>', seg, flags=re.S):
        out.append(seg[last:m.start()])
        if keep_path(m.group(0)):
            out.append(m.group(0))
        last = m.end()
    out.append(seg[last:])
    return ''.join(out)


def build(keys, bg=None, extra=''):
    x0, y0, w = box
    r = re.sub(r'viewBox="[^"]*"', f'viewBox="{x0:.3f} {y0:.3f} {w:.3f} {w:.3f}"', head, count=1)
    r = re.sub(r'width="[^"]*mm"', f'width="{PX}"', r, count=1)
    r = re.sub(r'height="[^"]*mm"', f'height="{PX}"', r, count=1)
    if bg:
        r = r.replace('fill="#f2efe9" clip-path="url(#area_mask)"', f'fill="{bg}"')
    return r + ''.join(filter_paths(segs[k]) for k in keys) + extra + '</svg>'


def group_end(seg, start):
    depth = 0
    for t in re.finditer(r'<g\b[^>]*>|</g>', seg[start:]):
        depth += -1 if t.group(0).startswith('</g') else 1
        if depth == 0:
            return start + t.end()


nat = ['Природа', 'Озеленение_жилых_кварталов_оценка', 'Землепользование', 'Природа_2', 'Зелёные_зоны']
water = ['Природа_3', 'Водные_объекты', 'Природа_4', 'Водотоки']
roads = ['Транспорт', 'Дороги_и_улицы']
rail = ['Транспорт_2', 'Железные_дороги']
base = ['Shapes', 'Page', 'Background', 'Подложка_области']
files = {
    'land': build(base + nat),
    'water_t': build(water, bg='none'),
    'roads_t': build(roads, bg='none'),
    'rail_t': build(rail, bg='none'),
}
# suv niqobi: faqat keng daryo/kanallar (chiziq eni >= 2.9 birlik) va suv havzalari
wseg = segs['Водотоки']
wide = [wseg[m.start():group_end(wseg, m.start())]
        for m in re.finditer(r'<g [^>]*stroke-width="([\d.]+)"[^>]*stroke="#aad3df"[^>]*>', wseg)
        if float(m.group(1)) >= 2.9]
files['water_mask'] = build([], bg='#ffffff', extra=segs['Природа_3'] + segs['Водные_объекты'] + segs['Природа_4'] + ''.join(wide) + '</g></g></g>')
args = []
for name, svg in files.items():
    p = os.path.join(TMP, name + '.svg')
    open(p, 'w', encoding='utf-8').write(svg)
    args += [p, os.path.join(TMP, name + '.png'), 't' if name.endswith('_t') else 'o']
subprocess.run(['node', os.path.join(HERE, 'shot.js'), str(PX)] + args, check=True)

Image.MAX_IMAGE_PIXELS = None
rgb = lambda n: Image.open(os.path.join(TMP, n + '.png')).convert('RGBA')
land = np.asarray(rgb('land').convert('RGB')).astype(np.float32)
land = land * 0.55 + land.mean(axis=2, keepdims=True) * 0.45   # to'yinganlikni kamaytirish
land = land * 0.70 + 255 * 0.30                                # oqartirish: o'yin obyektlari ajralib tursin
out = Image.fromarray(np.clip(land, 0, 255).astype(np.uint8)).convert('RGBA')


def layer(name, color, alpha):
    a = np.asarray(rgb(name)).astype(np.float32)
    c = np.zeros_like(a)
    c[..., 0], c[..., 1], c[..., 2], c[..., 3] = color[0], color[1], color[2], a[..., 3] * alpha
    return Image.fromarray(c.astype(np.uint8))


out = Image.alpha_composite(out, layer('water_t', (150, 196, 228), 1.0))
out = Image.alpha_composite(out, layer('roads_t', (250, 248, 240), 0.80))   # "ruh" ko'chalar
out = Image.alpha_composite(out, layer('rail_t', (150, 152, 156), 0.45))
out.convert('RGB').save(os.path.join(OUT, 'tashkent.webp'), quality=88, method=6)

# suv niqobi 1600x1600: kichik hovuzlar olib tashlanadi, 1 piksel kengaytiriladi
m = np.asarray(Image.open(os.path.join(TMP, 'water_mask.png')).convert('L').resize((1600, 1600), Image.BOX)) < 235
H, W = m.shape
lab = np.zeros((H, W), np.int32)
keep = np.zeros_like(m)
n = 0
for y0, x0 in zip(*np.nonzero(m)):
    if lab[y0, x0]:
        continue
    n += 1
    q, comp = deque([(y0, x0)]), []
    lab[y0, x0] = n
    while q:
        y, x = q.popleft()
        comp.append((y, x))
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                yy, xx = y + dy, x + dx
                if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    q.append((yy, xx))
    ys, xs = [c[0] for c in comp], [c[1] for c in comp]
    if len(comp) >= 150 or max(max(ys) - min(ys), max(xs) - min(xs)) >= 40:
        for y, x in comp:
            keep[y, x] = True
d = keep.copy()
for dy in (-1, 0, 1):
    for dx in (-1, 0, 1):
        d |= np.roll(np.roll(keep, dy, 0), dx, 1)
Image.fromarray((d * 255).astype(np.uint8)).save(os.path.join(OUT, 'tashkent_water.png'), optimize=True)
print('tayyor:', OUT)
