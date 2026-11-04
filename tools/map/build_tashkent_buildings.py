#!/usr/bin/env python3
"""Builds the 3D building layer of the Tashkent map (assets/map/tashkent_buildings.bin + _meta.json).

Source: Microsoft Global ML Building Footprints (ODbL-1.0), https://github.com/microsoft/GlobalMLBuildingFootprints,
the Uzbekistan quadkey file that covers Tashkent (121322232, ~70 MB csv.gz, one GeoJSON feature per line; not stored
in the repository). The footprints have no heights for Uzbekistan (height = -1), so every height here is an
ESTIMATE from footprint area and shape (see estimate_height); it is not measured data.

Coordinates follow the same chain as the game's own map (tools/map/svg_layers.py): WGS84 -> Web Mercator
(EPSG:3857) -> SVG document units through the export's world file (map.wld) -> game units
(3200 + (svg - centre) * GROUND, x east, y south, 1 unit ~ 1 m). So buildings line up with the drawn roads and the
basemap, not only with true WGS84.

Binary format (little-endian): b"TKB1", uint32 count, then per building: uint8 n, uint8 height in 0.5 m,
n x (uint16 x, uint16 y) in 0.25 game units. Buildings are sorted by centroid (y, x).

Usage: python3 tools/map/build_tashkent_buildings.py --source path/to/121322232.csv.gz
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import svg_layers  # noqa: E402

OUT_BIN = REPO_ROOT / "assets" / "map" / "tashkent_buildings.bin"
OUT_META = REPO_ROOT / "assets" / "map" / "tashkent_buildings_meta.json"
SOURCE_URL = ("https://minedbuildings.z5.web.core.windows.net/global-buildings/2026-02-03/global-buildings.geojsonl/"
              "RegionName=Uzbekistan/quadkey=121322232/part-00189-4feead82-d499-422b-94cb-c036c212127a.c000.csv.gz")

# World file of the SVG export (map.wld, EPSG:3857): pixel size x, rotation terms, pixel size y, origin x, origin y.
WLD_A, WLD_E = 6.4680379070, -6.4681812985
WLD_C, WLD_F = 7694399.4310595589, 5074929.2621606430
EARTH_R = 6378137.0

WORLD = 6400.0
QUANT = 4.0          # 0.25 game units
MIN_AREA = 15.0      # m2: drops slivers and sheds below this
MAX_POINTS = 255     # uint8 vertex count
MAGIC = b"TKB1"


class BuildError(Exception):
    pass


def wgs84_to_game(lon: float, lat: float) -> tuple[float, float]:
    """Same chain as the game's map: WGS84 -> EPSG:3857 -> SVG document units (map.wld) -> game units."""
    mx = EARTH_R * math.radians(lon)
    my = EARTH_R * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))
    # A world file refers to the CENTRE of the upper-left pixel, which is SVG point (0.5, 0.5); without this half
    # pixel every building sits 3.4 m off (checked against the 79 OSM anchors: max 0.004 m with it).
    sx = (mx - WLD_C) / WLD_A + 0.5
    sy = (my - WLD_F) / WLD_E + 0.5
    return 3200 + (sx - svg_layers.CX) * svg_layers.GROUND, 3200 + (sy - svg_layers.CY) * svg_layers.GROUND


def polygon_area(pts: list[tuple[float, float]]) -> float:
    n = len(pts)
    return abs(sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))) / 2


def elongation(pts: list[tuple[float, float]]) -> float:
    """Long side / short side of the minimum-area rectangle aligned with one of the polygon's edges."""
    best = None
    n = len(pts)
    for i in range(n):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        ln = math.hypot(dx, dy)
        if ln < 1e-6:
            continue
        ux, uy = dx / ln, dy / ln
        us = [px * ux + py * uy for px, py in pts]
        vs = [-px * uy + py * ux for px, py in pts]
        w, h = max(us) - min(us), max(vs) - min(vs)
        if best is None or w * h < best[0]:
            best = (w * h, max(w, h) / max(min(w, h), 1e-6))
    return best[1] if best else 1.0


def _hash01(x: float, y: float) -> float:
    """Deterministic pseudo-random number in [0, 1) from a position (32-bit integer mix, platform independent)."""
    h = (int(round(x * QUANT)) * 73856093) ^ (int(round(y * QUANT)) * 19349663)
    h &= 0xFFFFFFFF
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & 0xFFFFFFFF
    h ^= h >> 16
    return h / 4294967296.0


def estimate_height(area: float, elong: float, cx: float, cy: float) -> float:
    """ESTIMATED height in metres (no source heights exist). Typical Tashkent stock: 1-2 storey houses (mahalla),
    4/5/9-storey Soviet blocks (long, mid-size footprints), 3-6 storey compact mid-rise, low wide halls."""
    r = _hash01(cx, cy)
    if area < 40:
        floors = 1
    elif area < 200:
        floors = 2 if r < 0.35 else 1
    elif area < 700:
        floors = (4, 5, 5, 9)[int(r * 4)] if elong >= 2.5 else 2 + int(r * 3)
    elif area < 3000:
        floors = (5, 9, 9, 12)[int(r * 4)] if elong >= 2.5 else 3 + int(r * 4)
    else:
        floors = 2 + int(r * 3)
    per_floor = 4.5 if area >= 3000 else 3.2
    return min(60.0, floors * per_floor)


def parse_feature(line: str) -> list[tuple[float, float]] | None:
    f = json.loads(line)
    geom = f.get("geometry") or {}
    if geom.get("type") != "Polygon" or not geom.get("coordinates"):
        return None
    return [(float(x), float(y)) for x, y in geom["coordinates"][0]]


def to_building(ring_lonlat: list[tuple[float, float]]) -> tuple[list[tuple[int, int]], float] | None:
    """Ring in WGS84 -> (quantised game-unit polygon without the closing point, estimated height) or None."""
    pts = [wgs84_to_game(lon, lat) for lon, lat in ring_lonlat]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    q: list[tuple[int, int]] = []
    for x, y in pts:
        if not (0 <= x <= WORLD and 0 <= y <= WORLD):
            return None
        p = (int(round(x * QUANT)), int(round(y * QUANT)))
        if not q or q[-1] != p:
            q.append(p)
    if len(q) > 1 and q[0] == q[-1]:
        q.pop()
    if len(q) < 3 or len(q) > MAX_POINTS:
        return None
    real = [(x / QUANT, y / QUANT) for x, y in q]
    area = polygon_area(real)
    if area < MIN_AREA:
        return None
    cx = sum(x for x, _ in real) / len(real)
    cy = sum(y for _, y in real) / len(real)
    return q, estimate_height(area, elongation(real), cx, cy)


def encode(buildings: list[tuple[list[tuple[int, int]], float]]) -> bytes:
    out = bytearray(MAGIC + struct.pack("<I", len(buildings)))
    for pts, h in buildings:
        out += struct.pack("<BB", len(pts), max(1, min(255, int(round(h * 2)))))
        for x, y in pts:
            out += struct.pack("<HH", x, y)
    return bytes(out)


def decode(data: bytes) -> list[tuple[list[tuple[float, float]], float]]:
    if data[:4] != MAGIC:
        raise BuildError("bad magic")
    (count,) = struct.unpack_from("<I", data, 4)
    off, out = 8, []
    for _ in range(count):
        n, h2 = struct.unpack_from("<BB", data, off)
        off += 2
        pts = []
        for _ in range(n):
            x, y = struct.unpack_from("<HH", data, off)
            off += 4
            pts.append((x / QUANT, y / QUANT))
        out.append((pts, h2 / 2))
    if off != len(data):
        raise BuildError("trailing bytes")
    return out


def build(lines, source_sha256: str) -> tuple[bytes, dict]:
    buildings = []
    seen = 0
    for line in lines:
        if not line.strip():
            continue
        seen += 1
        ring = parse_feature(line)
        if ring is None:
            continue
        lon, lat = ring[0]
        if abs(lat - 41.311081) > 0.035 or abs(lon - 69.279737) > 0.045:  # cheap pre-filter around the game window
            continue
        b = to_building(ring)
        if b is not None:
            buildings.append(b)

    def key(b):
        pts = b[0]
        return (sum(y for _, y in pts) / len(pts), sum(x for x, _ in pts) / len(pts), pts)

    buildings.sort(key=key)
    body = encode(buildings)
    heights = sorted(h for _, h in buildings)
    meta = {
        "schema": "trafficity-tashkent-buildings/1",
        "file": "assets/map/tashkent_buildings.bin",
        "bytes": len(body),
        "sha256": hashlib.sha256(body).hexdigest(),
        "buildingCount": len(buildings),
        "pointCount": sum(len(p) for p, _ in buildings),
        "source": {
            "name": "Microsoft Global ML Building Footprints",
            "url": SOURCE_URL,
            "quadkey": "121322232",
            "sha256": source_sha256,
            "retrieved": "2026-11-04",
            "featuresRead": seen,
            "license": "ODbL-1.0",
            "attribution": "Building footprints © Microsoft (ODbL-1.0)",
        },
        "window": "game world 0..6400 units around Amir Temur xiyoboni (3200, 3200)",
        "coordinates": "same chain as the game map: WGS84 -> EPSG:3857 -> SVG units (map.wld) -> game units; "
                       "x east, y south, 0.25-unit quantisation",
        "heights": "ESTIMATED from footprint area and elongation (source has no heights for Uzbekistan); "
                   f"median {heights[len(heights) // 2] if heights else 0} m, max {heights[-1] if heights else 0} m",
        "filters": f"area >= {MIN_AREA} m2, 3..{MAX_POINTS} vertices, fully inside the window",
    }
    return body, meta


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", type=Path, required=True, help="Microsoft quadkey csv.gz (download it from SOURCE_URL)")
    ap.add_argument("--out", type=Path, default=OUT_BIN)
    ap.add_argument("--meta", type=Path, default=OUT_META)
    args = ap.parse_args(argv)
    try:
        raw = args.source.read_bytes()
        with gzip.open(args.source, "rt", encoding="utf-8") as fh:
            body, meta = build(fh, hashlib.sha256(raw).hexdigest())
    except (OSError, ValueError, BuildError) as exc:
        print(f"[build_tashkent_buildings] FAILED: {exc}", file=sys.stderr)
        return 1
    args.out.write_bytes(body)
    args.meta.write_text(json.dumps(meta, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[build_tashkent_buildings] {meta['buildingCount']} buildings, {meta['pointCount']} points, "
          f"{len(body)} bytes -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
