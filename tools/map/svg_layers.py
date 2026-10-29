"""OSM SVG eksporti (osm2cdr, "Map of Tashkent") qatlamlarini o'qish uchun umumiy yordamchilar."""
import re

CX, CY = 2749.8, 2565.5            # Amir Temur xiyoboni, SVG birliklarida (map.wld + EPSG:3857 dan hisoblangan)
GROUND = 4.858385231123688         # 1 SVG birligi = shuncha metr (Mercator masshtabi * cos(41.31))
SCALE = 0.999885                   # yo'l qatlami guruhlarining transform=matrix(0.999885,...) koeffitsienti
WORLD_M = 6400


def load(svg_path):
    s = open(svg_path, encoding='utf-8').read()
    marks = list(re.finditer(r'<g id="([^"]*)" inkscape:groupmode="layer"|<g id="(Shapes|Page|Background)"', s))
    pos = [m.start() for m in marks] + [len(s)]
    segs = {}
    for i, m in enumerate(marks):
        base = m.group(1) or m.group(2)
        key, k = base, 0
        while key in segs:
            k += 1
            key = f'{base}#{k}'
        segs[key] = s[pos[i]:pos[i + 1]]
    return segs, s[:pos[0]]


def crop_box():
    w = WORLD_M / GROUND
    return CX - w / 2, CY - w / 2, w


def to_game(x, y):
    """SVG yo'l qatlami koordinatasi -> o'yin koordinatasi (markaz = (3200, 3200), 1 birlik = 1 m)."""
    return 3200 + (x * SCALE - CX) * GROUND, 3200 + (y * SCALE - CY) * GROUND


# (nomi, to'ldirish rangi, eni) — fill guruhi; chetlari (casing) esa quyidagi juftlikda
ROAD_CLASSES = [
    ('trunk', '#f9b29c', 6.03253, '#aa5a3c', 8.77458),
    ('primary', '#fcd6a4', 4.3785, '#c39450', 6.81101),
    ('secondary', '#f7fabf', 3.49185, '#b2b264', 5.48719),
    ('tertiary', '#ffffff', 2.82356, '#bbbbbb', 4.5177),
    ('residential', '#ffffff', 2.06693, '#bbbbbb', 3.54331),
]
ROAD_GROUP = re.compile(r'<g stroke-linejoin="round"[^>]*stroke-width="([\d.]+)"[^>]*stroke="(#[0-9a-f]+)"[^>]*>(.*?)</g>', re.S)


def road_class(width, color, casing=False):
    for name, fc, fw, cc, cw in ROAD_CLASSES:
        if casing and cc == color and abs(cw - float(width)) < 1e-3:
            return name
        if not casing and fc == color and abs(fw - float(width)) < 1e-3:
            return name
    return None


def road_pieces(road_seg):
    """Yo'l qatlamidan (sinf, [(x, y)...]) bo'laklari, o'yin koordinatalarida (faqat ROAD_CLASSES to'ldirish guruhlari)."""
    out = []
    for m in ROAD_GROUP.finditer(road_seg):
        cls = road_class(m.group(1), m.group(2))
        if cls is None:
            continue
        for d in re.findall(r'<path[^>]* d="([^"]*)"', m.group(3)):
            n = [float(v) for v in re.findall(r'-?\d+\.?\d*', d)]
            pts = [to_game(n[i], n[i + 1]) for i in range(0, len(n) - 1, 2)]
            if any(-40 <= p[0] <= 6440 and -40 <= p[1] <= 6440 for p in pts):
                out.append((cls, pts))
    return out


def strip_imported_roads(road_seg):
    """Asosiy xaritadan o'yinga yuklanadigan yo'l sinflarini (fill va casing) olib tashlaydi: faqat xira kichik ko'chalar qoladi."""
    def keep(m):
        if road_class(m.group(1), m.group(2)) or road_class(m.group(1), m.group(2), casing=True):
            return ''
        return m.group(0)
    return ROAD_GROUP.sub(keep, road_seg)
