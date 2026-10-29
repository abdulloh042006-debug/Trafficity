"""Toshkent yo'llarini (OSM SVG eksporti) o'yin yo'l tarmog'iga aylantiradi: assets/map/tashkent_roads.json.

Ishlatish: python3 tools/map/build_tashkent_roads.py /yo'l/map.svg assets/map

Jarayon: (1) trunk/primary/secondary/tertiary/residential bo'laklari; (2) uchlari boshqa bo'lakning o'rtasiga tegsa va
kesishgan joylarda (trunk bundan mustasno) tugun qo'shiladi; (3) tugunlar orasidagi bo'laklar birlashtiriladi;
(4) suv ustidan o'tgan joylar (niqob bo'yicha) estakada-ko'prik, trunk kesishmalari estakada qilinadi.
(5) parallel juft yo'llar (ikki tomonlama prospekt) o'ng tomonlama harakat bo'yicha bir tomonlama qilinadi; kichik aylanalar
(chorraha) soat miliga teskari bir tomonlama bo'ladi.
Natija: {"v":1,"roads":[[sinf, qatlam, bir_tomonlama, [x0,y0,x1,y1,...]], ...]}; sinf: 0 trunk, 1 primary, 2 secondary, 3 tertiary, 4 residential.
"""
import collections
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_layers as sl

SRC, OUT = sys.argv[1], sys.argv[2]
RANK = {c[0]: i for i, c in enumerate(sl.ROAD_CLASSES)}
CELL = 40.0
SNAP = 1.0          # uch shu masofada boshqa bo'lakka tegsa, T-chorraha
MERGE_R = 0.35      # shu masofadagi nuqtalar bitta tugun
BRIDGE_PAD = 14.0   # ko'prik qirg'oqdan oldin/keyin shuncha metr uzayadi
OVERPASS_HALF = 60.0

segs, _ = sl.load(SRC)
ways = [(c, p) for c, p in sl.road_pieces(segs['Дороги_и_улицы'])]
print('bo\'laklar:', len(ways), collections.Counter(c for c, _ in ways))


def dseg(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2))
    q = (ax + t * dx, ay + t * dy)
    return math.hypot(p[0] - q[0], p[1] - q[1]), t, q


def seg_grid(ws):
    segs_, grid = [], collections.defaultdict(list)
    for wi, (_, pts) in enumerate(ws):
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            idx = len(segs_)
            segs_.append((wi, i, a, b))
            for gx in range(int(min(a[0], b[0]) // CELL), int(max(a[0], b[0]) // CELL) + 1):
                for gy in range(int(min(a[1], b[1]) // CELL), int(max(a[1], b[1]) // CELL) + 1):
                    grid[(gx, gy)].append(idx)
    return segs_, grid


def apply_inserts(ws, inserts):
    out = []
    for wi, (cls, pts) in enumerate(ws):
        ins = inserts.get(wi)
        if not ins:
            out.append((cls, list(pts)))
            continue
        byseg = collections.defaultdict(list)
        for i, t, p in ins:
            byseg[i].append((t, p))
        res = [pts[0]]
        for i in range(len(pts) - 1):
            for t, p in sorted(byseg.get(i, [])):
                res.append(p)
            res.append(pts[i + 1])
        out.append((cls, res))
    return out


def inter(a, b, c, d):
    r = (b[0] - a[0], b[1] - a[1])
    s = (d[0] - c[0], d[1] - c[1])
    den = r[0] * s[1] - r[1] * s[0]
    if abs(den) < 1e-9:
        return None
    qp = (c[0] - a[0], c[1] - a[1])
    t = (qp[0] * s[1] - qp[1] * s[0]) / den
    u = (qp[0] * r[1] - qp[1] * r[0]) / den
    if 1e-6 < t < 1 - 1e-6 and 1e-6 < u < 1 - 1e-6:
        return (a[0] + r[0] * t, a[1] + r[1] * t), t, u
    return None


# 1) T-chorrahalar: uch boshqa bo'lak o'rtasiga tegsa, o'sha bo'lakka nuqta qo'shiladi
sg, grid = seg_grid(ways)
inserts = collections.defaultdict(list)
for wi, (cls, pts) in enumerate(ways):
    for p in (pts[0], pts[-1]):
        best = None
        cx, cy = int(p[0] // CELL), int(p[1] // CELL)
        seen = set()
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for idx in grid.get((gx, gy), []):
                    if idx in seen:
                        continue
                    seen.add(idx)
                    w2, i, a, b = sg[idx]
                    if w2 == wi:
                        continue
                    d, t, q = dseg(p, a, b)
                    if d <= SNAP and 0 < t < 1 and math.dist(q, a) > MERGE_R and math.dist(q, b) > MERGE_R:
                        if best is None or d < best[0]:
                            best = (d, w2, i, t, p)
        if best:
            inserts[best[1]].append((best[2], best[3], best[4]))
ways = apply_inserts(ways, inserts)

# 2) kesishmalar (umumiy tugunsiz): trunk bo'lmasa chorraha, trunk bo'lsa estakada
sg, grid = seg_grid(ways)
inserts = collections.defaultdict(list)
overpass = collections.defaultdict(list)   # way index -> [kesishgan nuqta]
seen = set()
for lst in grid.values():
    for ii in range(len(lst)):
        for jj in range(ii + 1, len(lst)):
            i, j = lst[ii], lst[jj]
            if (i, j) in seen:
                continue
            seen.add((i, j))
            wi, si, a, b = sg[i]
            wj, sj, c, d = sg[j]
            if wi == wj:
                continue
            r = inter(a, b, c, d)
            if not r:
                continue
            p, t, u = r
            ci, cj = ways[wi][0], ways[wj][0]
            if 'trunk' in (ci, cj):
                top = wi if (ci == 'trunk' and (cj != 'trunk' or wi < wj)) else wj
                overpass[top].append(p)
            else:
                inserts[wi].append((si, t, p))
                inserts[wj].append((sj, u, p))
ways = apply_inserts(ways, inserts)
print('trunk estakadalari uchun kesishmalar:', sum(len(v) for v in overpass.values()))
# estakada nuqtalarini indekslar o'zgarganidan keyin yo'l uzunligi bo'yicha eslab qolamiz
trunk_cross = collections.defaultdict(list)
for wi, pts in overpass.items():
    # wi eski indeks: apply_inserts tartibni saqlaydi
    trunk_cross[wi] = pts

# 3) tugunlar va bo'laklash
class VG:
    def __init__(s):
        s.g = collections.defaultdict(list)
        s.pts = []

    def node(s, p):
        cx, cy = int(p[0]), int(p[1])
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for i in s.g.get((gx, gy), []):
                    if math.dist(s.pts[i], p) <= MERGE_R:
                        return i
        i = len(s.pts)
        s.pts.append(p)
        s.g[(cx, cy)].append(i)
        return i


vg = VG()
wn = []
inc = collections.Counter()
for wi, (cls, pts) in enumerate(ways):
    ids, pp = [], []
    for p in pts:
        n = vg.node(p)
        if ids and ids[-1] == n:
            continue
        ids.append(n)
        pp.append(vg.pts[n])      # tugun koordinatasi (umumiy nuqtalar aynan bir xil)
    wn.append((cls, ids, pp, wi))
    for n in set(ids):
        inc[n] += 1
edges = []   # [sinf, a, b, nuqtalar, way index]
for cls, ids, pp, wi in wn:
    if len(ids) < 2:
        continue
    start = 0
    for k in range(1, len(ids)):
        if k == len(ids) - 1 or inc[ids[k]] >= 2:
            if ids[k] != ids[start]:
                edges.append([cls, ids[start], ids[k], pp[start:k + 1], wi])
            start = k


def merge(edges):
    inc2 = collections.defaultdict(list)
    for ei, e in enumerate(edges):
        inc2[e[1]].append(ei)
        inc2[e[2]].append(ei)
    alive = [True] * len(edges)
    changed = True
    while changed:
        changed = False
        for n in list(inc2):
            lst = [x for x in inc2[n] if alive[x]]
            inc2[n] = lst
            if len(lst) != 2 or lst[0] == lst[1]:
                continue
            ea, eb = edges[lst[0]], edges[lst[1]]
            if ea[0] != eb[0] or ea[4] != eb[4] and ea[0] == 'trunk':
                continue
            A = ea if ea[2] == n else [ea[0], ea[2], ea[1], ea[3][::-1], ea[4]]
            B = eb if eb[1] == n else [eb[0], eb[2], eb[1], eb[3][::-1], eb[4]]
            if A[1] == B[2]:
                continue          # yopiq halqa hosil bo'lmasin
            new = [A[0], A[1], B[2], A[3] + B[3][1:], A[4]]
            alive[lst[0]] = alive[lst[1]] = False
            edges.append(new)
            alive.append(True)
            ni = len(edges) - 1
            inc2[new[1]] = [y for y in inc2[new[1]] if alive[y]] + [ni]
            inc2[new[2]] = [y for y in inc2[new[2]] if alive[y]] + [ni]
            changed = True
    return [e for e, a in zip(edges, alive) if a]


edges = merge(edges)
print('tugunlar:', len(vg.pts), 'yo\'llar:', len(edges))

# 3b) juda qisqa bo'laklar (<SHORT_M) tugunlarni birlashtirib yo'qotiladi: polosasi mashinadan qisqa bo'lib qolmasin
SHORT_M = 30.0


def elen_(e):
    return sum(math.dist(e[3][k], e[3][k + 1]) for k in range(len(e[3]) - 1))


def contract(edges):
    pos = {i: p for i, p in enumerate(vg.pts)}
    inc2 = collections.defaultdict(set)
    for ei, e in enumerate(edges):
        inc2[e[1]].add(ei)
        inc2[e[2]].add(ei)
    alive = [True] * len(edges)
    n_merge = 0
    while True:
        cand = sorted((elen_(edges[i]), i) for i in range(len(edges)) if alive[i] and edges[i][1] != edges[i][2] and elen_(edges[i]) < SHORT_M)
        if not cand:
            break
        L, i = cand[0]
        e = edges[i]
        a, b = e[1], e[2]
        if len(inc2[a]) < len(inc2[b]):
            a, b = b, a                     # a: darajasi yuqori tugun, joyi saqlanadi
        alive[i] = False
        inc2[a].discard(i)
        inc2[b].discard(i)
        for ej in list(inc2[b]):
            f = edges[ej]
            if f[1] == b:
                f[1] = a
                f[3][0] = pos[a]
            if f[2] == b:
                f[2] = a
                f[3][-1] = pos[a]
            inc2[a].add(ej)
        inc2[b] = set()
        for ej in list(inc2[a]):
            f = edges[ej]
            if alive[ej] and f[1] == f[2]:       # o'z-o'ziga qaytgan: olib tashlanadi
                alive[ej] = False
                inc2[a].discard(ej)
        n_merge += 1
    print('birlashtirilgan qisqa bo\'laklar:', n_merge)
    return [e for e, al in zip(edges, alive) if al]


edges = contract(edges)
edges = merge(edges)
print('qisqa bo\'laklar olib tashlangach yo\'llar:', len(edges))

# 4) suv ustidagi ko'priklar va trunk estakadalari
mask = np.asarray(Image.open(os.path.join(OUT, 'tashkent_water.png')).convert('L')) > 127


def water(p):
    x, y = int(p[0] / 6400 * 1600), int(p[1] / 6400 * 1600)
    return 0 <= x < 1600 and 0 <= y < 1600 and bool(mask[y, x])


def cumlen(P):
    c = [0.0]
    for i in range(1, len(P)):
        c.append(c[-1] + math.dist(P[i - 1], P[i]))
    return c


def point_at(P, cum, s):
    j = 1
    while j < len(cum) - 1 and cum[j] < s:
        j += 1
    t = (s - cum[j - 1]) / max(cum[j] - cum[j - 1], 1e-9)
    return (P[j - 1][0] + (P[j][0] - P[j - 1][0]) * t, P[j - 1][1] + (P[j][1] - P[j - 1][1]) * t)


def cut(P, cum, s0, s1):
    """[s0, s1] oralig'idagi bo'lak nuqtalari (chegara nuqtalari bilan)."""
    out = [point_at(P, cum, s0)]
    for i in range(1, len(P) - 1):
        if s0 + 0.5 < cum[i] < s1 - 0.5:
            out.append(P[i])
    out.append(point_at(P, cum, s1))
    return out


def elevated_intervals(e, cum):
    L = cum[-1]
    iv = []
    n = max(2, int(L / 3))
    cur = None
    for k in range(n + 1):
        s = L * k / n
        w = water(point_at(e[3], cum, s))
        if w and cur is None:
            cur = [s, s]
        elif w:
            cur[1] = s
        elif cur is not None:
            iv.append(cur)
            cur = None
    if cur is not None:
        iv.append(cur)
    iv = [[max(0.0, a - BRIDGE_PAD), min(L, b + BRIDGE_PAD)] for a, b in iv if b - a >= 8.0]
    if e[0] == 'trunk':
        for p in trunk_cross.get(e[4], []):
            # kesishish nuqtasining yo'l bo'yicha masofasi
            best = None
            for i in range(len(e[3]) - 1):
                d, t, q = dseg(p, e[3][i], e[3][i + 1])
                if best is None or d < best[0]:
                    best = (d, cum[i] + t * (cum[i + 1] - cum[i]))
            if best and best[0] < 3.0:
                iv.append([max(0.0, best[1] - OVERPASS_HALF), min(L, best[1] + OVERPASS_HALF)])
    iv.sort()
    merged = []
    for a, b in iv:
        if merged and a <= merged[-1][1] + 6.0:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    return merged


def _elen(e):
    return sum(math.dist(e[3][k], e[3][k + 1]) for k in range(len(e[3]) - 1))


elens = {i: _elen(e) for i, e in enumerate(edges)}

# 5a) juft (ikki tomonlama prospekt) yo'llar: yon-yon, parallel, bir xil sinf -> bir tomonlama
def left_of(d):
    return (d[1], -d[0])          # y pastga yo'nalgan koordinatada chap tomon


def edge_samples(P, step=8.0):
    out = []
    for i in range(len(P) - 1):
        a, b = P[i], P[i + 1]
        L = math.dist(a, b)
        if L < 1e-6:
            continue
        d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        n = max(1, int(L / step))
        for k in range(n):
            t = (k + 0.5) / n
            out.append(((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), d))
    return out


big = [i for i, e in enumerate(edges) if e[0] in ('trunk', 'primary', 'secondary') and sum(math.dist(e[3][k], e[3][k + 1]) for k in range(len(e[3]) - 1)) >= 30]
sgrid = collections.defaultdict(list)
samples = {}
for i in big:
    samples[i] = edge_samples(edges[i][3])
    for p, d in samples[i]:
        sgrid[(int(p[0] // 40), int(p[1] // 40))].append((i, p, d))
oneway = {}
for i in big:
    sm = samples[i]
    if len(sm) < 4:
        continue
    votes = collections.defaultdict(lambda: [0, 0.0])
    for p, d in sm:
        best = None
        cx, cy = int(p[0] // 40), int(p[1] // 40)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for j, q, dq in sgrid.get((gx, gy), []):
                    if j == i or edges[j][0] != edges[i][0]:
                        continue
                    dist = math.dist(p, q)
                    if not 5.0 <= dist <= 35.0:
                        continue
                    if abs(d[0] * dq[1] - d[1] * dq[0]) > 0.35:      # parallel emas
                        continue
                    if best is None or dist < best[0]:
                        best = (dist, j, ((q[0] - p[0]) * left_of(d)[0] + (q[1] - p[1]) * left_of(d)[1]) / dist)
        if best:
            votes[best[1]][0] += 1
            votes[best[1]][1] += best[2]
    if not votes:
        continue
    j, (cnt, sgn) = max(votes.items(), key=lambda kv: kv[1][0])
    if cnt >= 0.6 * len(sm) and abs(sgn) >= 0.6 * cnt:
        oneway[i] = sgn > 0          # sherik chapda -> yo'nalish saqlanadi, o'ngda -> teskarilanadi (True: saqlanadi)
# yo'nalishlarni izchillashtirish: tugunda to'g'ri davom etadigan ikki bir tomonlama bo'lak "bosh -> dum" bo'lishi shart
inc_ow = collections.defaultdict(list)
for i in oneway:
    inc_ow[edges[i][1]].append(i)
    inc_ow[edges[i][2]].append(i)


def leave_dir(e, n):
    P = e[3] if e[1] == n else e[3][::-1]
    q = P[1]
    L = math.dist(P[0], q) or 1.0
    return ((q[0] - P[0][0]) / L, (q[1] - P[0][1]) / L)


rel = collections.defaultdict(list)       # i -> [(j, parity)]
for n, lst in inc_ow.items():
    for x in range(len(lst)):
        for y in range(x + 1, len(lst)):
            i, j = lst[x], lst[y]
            di, dj = leave_dir(edges[i], n), leave_dir(edges[j], n)
            if di[0] * dj[0] + di[1] * dj[1] < -0.8:          # to'g'ri davom etadi
                ti = 1 if edges[i][2] == n else -1             # i saqlansa tugunga kiradi (+1)
                tj = 1 if edges[j][1] == n else -1             # j saqlansa tugundan chiqadi (+1)
                rel[i].append((j, ti * tj))
                rel[j].append((i, ti * tj))
sgn = {}
for root in oneway:
    if root in sgn:
        continue
    comp, stack = [root], [root]
    sgn[root] = 1
    while stack:
        i = stack.pop()
        for j, par_ in rel[i]:
            if j not in sgn:
                sgn[j] = sgn[i] * par_
                comp.append(j)
                stack.append(j)
    score = sum((1 if oneway[i] else -1) * sgn[i] * elens.get(i, 1.0) for i in comp)
    f = 1 if score >= 0 else -1
    for i in comp:
        sgn[i] *= f
flips = 0
for i in oneway:
    if sgn[i] < 0:
        edges[i][1], edges[i][2] = edges[i][2], edges[i][1]
        edges[i][3] = edges[i][3][::-1]
        flips += 1
print('juft (bir tomonlama) yo\'llar:', len(oneway), 'yo\'nalishi o\'zgartirilgan:', flips)

# 5b) kichik aylanalar: perimetr 150..1100 m, aylanaga yaqin (4*pi*S/P^2 >= 0.8), soat miliga teskari
adj = collections.defaultdict(list)
for i, e in enumerate(edges):
    if e[0] in ('trunk', 'primary', 'secondary', 'tertiary'):
        adj[e[1]].append(i)
        adj[e[2]].append(i)


rings = {}
for n0 in list(adj):
    stack = [(n0, [], 0.0)]
    while stack:
        n, path, tot = stack.pop()
        for ei in adj[n]:
            if ei in path:
                continue
            e = edges[ei]
            m = e[2] if e[1] == n else e[1]
            t2 = tot + elens[ei]
            if t2 > 1100:
                continue
            if m == n0 and len(path) >= 2:
                cyc = path + [ei]
                key = tuple(sorted(cyc))
                if key in rings:
                    continue
                # ko'pburchak
                poly = []
                cur = n0
                seq = []
                for ci in cyc:
                    ee = edges[ci]
                    P = ee[3] if ee[1] == cur else ee[3][::-1]
                    seq.append((ci, ee[1] == cur))
                    poly += P[:-1]
                    cur = ee[2] if ee[1] == cur else ee[1]
                area = sum(poly[k][0] * poly[(k + 1) % len(poly)][1] - poly[(k + 1) % len(poly)][0] * poly[k][1] for k in range(len(poly))) / 2
                per = t2
                if per >= 150 and 4 * math.pi * abs(area) / per ** 2 >= 0.8:
                    rings[key] = (seq, area)
                continue
            if len(path) < 14:
                stack.append((m, path + [ei], t2))
ring_edges = {}
for seq, area in rings.values():
    ccw_ok = area < 0           # y pastga: soat miliga teskari = manfiy yuza
    for ci, fwd in seq:
        want_forward = fwd if ccw_ok else not fwd
        ring_edges[ci] = want_forward if ci not in ring_edges else ring_edges[ci]
for ci, fwd_ok in ring_edges.items():
    e = edges[ci]
    # sikl yo'nalishi bo'yicha: seq da (ci, fwd) bo'lsa va ccw bo'lsa, qirrani yo'nalishi saqlanadi
    pass
ring_set = set()
for seq, area in rings.values():
    for ci, fwd in seq:
        ring_set.add(ci)
        # tsikl bo'ylab yurish yo'nalishi fwd (qirra a->b bo'ylab) bo'lsa va tsikl soat miliga teskari bo'lsa - saqlanadi
        keep = fwd if area < 0 else (not fwd)
        if not keep and ci not in oneway:
            e = edges[ci]
            e[1], e[2] = e[2], e[1]
            e[3] = e[3][::-1]
        elif not keep and ci in oneway and oneway.get(ci) is not None:
            pass
        oneway[ci] = True
print('aylanalar:', len(rings), 'aylana qirralari:', len(ring_set))

# 5c) asosiy tarmoqdan uzilgan kichik orollar (<= 4 yo'l) olib tashlanadi
parent = {}


def find(x):
    while parent.setdefault(x, x) != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x


for e in edges:
    parent[find(e[1])] = find(e[2])
csize = collections.Counter(find(e[1]) for e in edges)
before = len(edges)
keep_idx = [i for i, e in enumerate(edges) if csize[find(e[1])] > 4]
remap_oneway = {new: (old in oneway) for new, old in enumerate(keep_idx)}
edges = [edges[i] for i in keep_idx]
oneway = {new: True for new, ok in remap_oneway.items() if ok}
print('olib tashlangan orol yo\'llari:', before - len(edges))

roads = []
n_bridge = 0
for ei, e in enumerate(edges):
    P = e[3]
    cum = cumlen(P)
    L = cum[-1]
    if L < 3.0:
        continue
    iv = elevated_intervals(e, cum)
    cls = RANK[e[0]]
    pos = 0.0
    parts = []
    for a, b in iv:
        if a - pos >= 15.0:
            parts.append((0, pos, a))
        else:
            a = pos          # juda qisqa oraliq: estakada oldingi bo'lak tugagan joydan (yoki tugundan) boshlanadi
        parts.append((1, a, b))
        pos = b
    if L - pos >= 15.0:
        parts.append((0, pos, L))
    elif parts:
        t, a0, b0 = parts[-1]
        parts[-1] = (t, a0, L)
    if not parts:
        parts = [(0, 0.0, L)]
    for layer, a, b in parts:
        pts = cut(P, cum, a, b) if (a > 0 or b < L) else P
        if layer == 1:
            n_bridge += 1
        flat = [round(v, 1) for p in pts for v in p]
        if any(not 0.0 <= v <= 6400.0 for v in flat):
            continue          # dunyo chegarasidan chiqqan yo'llar
        roads.append([cls, layer, 1 if ei in oneway else 0, flat])
print('estakada/ko\'prik bo\'laklari:', n_bridge, 'jami yo\'l bo\'laklari:', len(roads))
json.dump({'v': 1, 'roads': roads}, open(os.path.join(OUT, 'tashkent_roads.json'), 'w'), separators=(',', ':'))
print('yozildi:', os.path.getsize(os.path.join(OUT, 'tashkent_roads.json')), 'bayt')
