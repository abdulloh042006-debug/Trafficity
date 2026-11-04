#!/usr/bin/env python3
"""Exports the 3D Tashkent city (the same data as the in-game 3D view) as Wavefront OBJ + MTL for Blender.

Buildings come from assets/map/tashkent_buildings.bin (Microsoft footprints, ODbL; heights ESTIMATED), the ground is
a square textured with assets/map/tashkent.webp (OpenStreetMap basemap). OBJ convention: Y up, metres; x = east,
z = south, origin = Amir Temur xiyoboni (game point 3200, 3200). In Blender: File > Import > Wavefront (.obj).

Usage: python3 tools/map/export_tashkent_obj.py [--radius 1500] [--out build/tashkent_3d]
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_tashkent_buildings as tb  # noqa: E402

BASEMAP = REPO_ROOT / "assets" / "map" / "tashkent.webp"
CENTRE = 3200.0
WORLD = 6400.0


def triangulate(pts: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Ear clipping (either orientation); falls back to a fan for degenerate shapes."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sign = 1.0 if area >= 0 else -1.0
    idx = list(range(n))
    out: list[tuple[int, int, int]] = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    guard = 0
    while len(idx) > 3 and guard < n * n:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            if cross(pts[i0], pts[i1], pts[i2]) * sign <= 1e-9:
                continue
            if any(p not in (i0, i1, i2) and all(cross(*e, pts[p]) * sign >= 0 for e in (
                    (pts[i0], pts[i1]), (pts[i1], pts[i2]), (pts[i2], pts[i0]))) for p in idx):
                continue
            out.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            break
    out += [(idx[0], idx[k], idx[k + 1]) for k in range(1, len(idx) - 1)]
    return out


def export(out_dir: Path, radius: float) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    buildings = tb.decode(tb.OUT_BIN.read_bytes())
    lines = ["# Tashkent 3D (Trafficity). Buildings: Microsoft footprints (ODbL), heights ESTIMATED. "
             "Basemap: (c) OpenStreetMap contributors (ODbL).", "mtllib tashkent.mtl"]
    v = 0
    # ground: one textured square over the exported area
    g0x, g1x = max(0.0, CENTRE - radius), min(WORLD, CENTRE + radius)
    g0z, g1z = max(0.0, CENTRE - radius), min(WORLD, CENTRE + radius)
    lines.append("o ground")
    for x, z in ((g0x, g0z), (g1x, g0z), (g1x, g1z), (g0x, g1z)):
        lines.append(f"v {x - CENTRE:.2f} 0 {z - CENTRE:.2f}")
        lines.append(f"vt {x / WORLD:.6f} {1 - z / WORLD:.6f}")
    lines += ["usemtl basemap", "f 4/4 3/3 2/2 1/1"]
    v += 4
    lines += ["o buildings", "usemtl building"]
    count = faces = 0
    for pts, h in buildings:
        cx = sum(p[0] for p in pts) / len(pts)
        cz = sum(p[1] for p in pts) / len(pts)
        if abs(cx - CENTRE) > radius or abs(cz - CENTRE) > radius:
            continue
        n = len(pts)
        base = v + 1
        for x, z in pts:
            lines.append(f"v {x - CENTRE:.2f} 0 {z - CENTRE:.2f}")
        for x, z in pts:
            lines.append(f"v {x - CENTRE:.2f} {h:.2f} {z - CENTRE:.2f}")
        v += 2 * n
        for j in range(n):
            k = (j + 1) % n
            lines.append(f"f {base + j} {base + k} {base + n + k} {base + n + j}")
            faces += 1
        for a, b, c in triangulate(pts):
            lines.append(f"f {base + n + a} {base + n + b} {base + n + c}")
            faces += 1
        count += 1
    (out_dir / "tashkent.obj").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out_dir / "tashkent.mtl").write_text(
        "newmtl basemap\nKd 1 1 1\nmap_Kd tashkent.webp\n\nnewmtl building\nKd 0.85 0.79 0.73\n", encoding="utf-8")
    shutil.copyfile(BASEMAP, out_dir / "tashkent.webp")
    return {"buildings": count, "vertices": v, "faces": faces + 1}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--radius", type=float, default=1500.0, help="metres around Amir Temur xiyoboni (max 3200)")
    ap.add_argument("--out", type=Path, default=REPO_ROOT / "build" / "tashkent_3d")
    args = ap.parse_args(argv)
    s = export(args.out, min(3200.0, max(50.0, args.radius)))
    print(f"[export_tashkent_obj] {s['buildings']} buildings, {s['vertices']} vertices, {s['faces']} faces -> "
          f"{args.out / 'tashkent.obj'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
