#!/usr/bin/env python3
"""Builds assets/world/uzbekistan/region_borders.json from Natural Earth admin-1 outlines.

Source: Natural Earth 1:10m "Admin 1 - States, Provinces" (public domain),
https://github.com/nvkelso/natural-earth-vector (geojson/ne_10m_admin_1_states_provinces.geojson, ~40 MB, not stored here).
The 14 Uzbek units are matched to region_catalog.json by ISO 3166-2 code, generalised with Douglas-Peucker and written
deterministically. These are generalised cartographic outlines for drawing a map; they are NOT legal borders.

Usage: python3 tools/map/build_uzbekistan_borders.py --source path/to/ne_10m_admin_1_states_provinces.geojson
       (without --source the file is downloaded from the URL above)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG = REPO_ROOT / "assets" / "world" / "uzbekistan" / "region_catalog.json"
OUT = REPO_ROOT / "assets" / "world" / "uzbekistan" / "region_borders.json"
SOURCE_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/"
              "ne_10m_admin_1_states_provinces.geojson")
TOLERANCE_DEG = 0.004   # ~440 m: below one pixel at 8x zoom on a phone-sized country map
DECIMALS = 4            # ~10 m
MIN_RING_POINTS = 4     # closed ring: 3 distinct points + the repeated first point
SCHEMA = "trafficity-region-borders/1"


class BorderError(Exception):
    pass


def simplify(points: list[tuple[float, float]], tol: float) -> list[tuple[float, float]]:
    """Iterative Douglas-Peucker on an open polyline (keeps both ends)."""
    n = len(points)
    if n < 3:
        return list(points)
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = points[a]
        bx, by = points[b]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        worst, idx = -1.0, -1
        for i in range(a + 1, b):
            px, py = points[i]
            d = math.hypot(px - ax, py - ay) if length == 0 else abs(dy * (px - ax) - dx * (py - ay)) / length
            if d > worst:
                worst, idx = d, i
        if worst > tol:
            keep[idx] = True
            stack.append((a, idx))
            stack.append((idx, b))
    return [p for p, k in zip(points, keep) if k]


def simplify_ring(ring: list, tol: float) -> list[list[float]] | None:
    """Closed GeoJSON ring -> simplified, rounded, closed ring; None if it collapses."""
    pts = [(float(x), float(y)) for x, y in ring]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    out = simplify(pts + [pts[0]], tol)[:-1]
    rounded: list[tuple[float, float]] = []
    for x, y in out:
        q = (round(x, DECIMALS), round(y, DECIMALS))
        if not rounded or rounded[-1] != q:
            rounded.append(q)
    if len(rounded) > 1 and rounded[0] == rounded[-1]:
        rounded.pop()
    if len(rounded) < MIN_RING_POINTS - 1:
        return None
    return [[x, y] for x, y in rounded] + [[rounded[0][0], rounded[0][1]]]


def ring_area_deg2(ring: list) -> float:
    s = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        s += x1 * y2 - x2 * y1
    return s / 2.0


def polygons_of(geometry: dict) -> list[list[list]]:
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiPolygon":
        return geometry["coordinates"]
    raise BorderError(f"unsupported geometry type {geometry['type']}")


def build(source_bytes: bytes, catalog: dict, tol: float = TOLERANCE_DEG) -> dict:
    data = json.loads(source_bytes.decode("utf-8"))
    by_iso = {r["isoCode"]: r["regionId"] for r in catalog["regions"]}
    found: dict[str, dict] = {}
    for f in data["features"]:
        p = f.get("properties", {})
        if p.get("iso_a2") != "UZ" and p.get("admin") != "Uzbekistan":
            continue
        iso = p.get("iso_3166_2")
        if iso not in by_iso:
            raise BorderError(f"unknown ISO code in source: {iso}")
        if by_iso[iso] in found:
            raise BorderError(f"duplicate ISO code in source: {iso}")
        polys = []
        for poly in polygons_of(f["geometry"]):
            rings = []
            for i, ring in enumerate(poly):
                s = simplify_ring(ring, tol)
                if s is None:
                    if i == 0:
                        rings = []
                        break  # the whole polygon collapsed
                    continue  # a collapsed hole is dropped
                rings.append(s)
            if rings:
                polys.append(rings)
        if not polys:
            raise BorderError(f"{iso}: no polygon left after simplification")
        found[by_iso[iso]] = {"isoCode": iso, "sourceName": p.get("name_en") or p.get("name"), "polygons": polys}
    missing = sorted(set(by_iso.values()) - set(found))
    if missing:
        raise BorderError(f"regions missing in source: {missing}")
    return {
        "schema": SCHEMA,
        "source": {
            "name": "Natural Earth 1:10m Admin 1 - States, Provinces",
            "url": SOURCE_URL,
            "license": "Public domain (naturalearthdata.com/about/terms-of-use)",
            "retrieved": "2026-11-04",
            "sha256": hashlib.sha256(source_bytes).hexdigest(),
        },
        "generalization": f"Douglas-Peucker {tol} deg (~{tol * 111_000:.0f} m), coordinates rounded to {DECIMALS} decimals",
        "notice": "Generalised cartographic outlines for drawing; not legal or surveyed administrative borders. "
                  "Neighbouring outlines were simplified independently, so shared edges may differ by up to the tolerance.",
        "coordinateOrder": "[longitude, latitude]; first ring of a polygon is the outer ring, the others are holes",
        "regions": {rid: found[rid] for rid in sorted(found)},
    }


def canonical(doc: dict) -> bytes:
    return (json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", type=Path)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--tolerance", type=float, default=TOLERANCE_DEG)
    args = ap.parse_args(argv)
    try:
        source = args.source.read_bytes() if args.source else urllib.request.urlopen(SOURCE_URL, timeout=120).read()
        doc = build(source, json.loads(CATALOG.read_text(encoding="utf-8")), args.tolerance)
    except (OSError, BorderError, ValueError, KeyError) as exc:
        print(f"[build_uzbekistan_borders] FAILED: {exc}", file=sys.stderr)
        return 1
    body = canonical(doc)
    args.out.write_bytes(body)
    pts = sum(len(r) for reg in doc["regions"].values() for poly in reg["polygons"] for r in poly)
    print(f"[build_uzbekistan_borders] {len(doc['regions'])} regions, {pts} points, {len(body)} bytes -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
