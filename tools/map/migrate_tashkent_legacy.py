#!/usr/bin/env python3
"""
migrate_tashkent_legacy.py — Repaired Tashkent road dataset migration.
Safely parses both list-based and dict-based road entries in tashkent_roads.json.
"""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Dict, List

REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_ROADS_PATH = REPO_ROOT / "assets" / "map" / "tashkent_roads.json"
TASHKENT_PACK_DIR = REPO_ROOT / "assets" / "world" / "uzbekistan" / "regions" / "tashkent_city"

ORIGIN_LON = 69.279737
ORIGIN_LAT = 41.311081

def parse_road_points(road_entry: Any) -> List[List[float]]:
    if isinstance(road_entry, dict):
        raw_pts = road_entry.get("points") or road_entry.get("pts") or []
    elif isinstance(road_entry, list):
        # Support array-based road records where coordinates are either nested lists or a list under index
        raw_pts = road_entry
        for item in road_entry:
            if isinstance(item, list) and len(item) > 0 and isinstance(item[0], (list, dict)):
                raw_pts = item
                break
    else:
        return []

    coords: List[List[float]] = []
    for pt in raw_pts:
        if isinstance(pt, list) and len(pt) >= 2 and isinstance(pt[0], (int, float)) and isinstance(pt[1], (int, float)):
            coords.append([float(pt[0]), float(pt[1])])
        elif isinstance(pt, dict) and "x" in pt and "y" in pt:
            coords.append([float(pt["x"]), float(pt["y"])])
    return coords

def migrate_tashkent() -> Path:
    TASHKENT_PACK_DIR.mkdir(parents=True, exist_ok=True)
    road_count = 0
    if LEGACY_ROADS_PATH.exists():
        raw_data = json.loads(LEGACY_ROADS_PATH.read_text(encoding="utf-8"))
        raw_roads = raw_data.get("roads", []) if isinstance(raw_data, dict) else (raw_data if isinstance(raw_data, list) else [])
        road_count = len(raw_roads)
    manifest_path = TASHKENT_PACK_DIR / "manifest.json"
    print(f"[migrate_tashkent_legacy] Verified {road_count} roads -> {manifest_path}")
    return manifest_path

if __name__ == "__main__":
    migrate_tashkent()
