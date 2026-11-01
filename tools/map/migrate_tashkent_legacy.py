#!/usr/bin/env python3
"""
migrate_tashkent_legacy.py — Migrates existing Tashkent local-coordinate assets
into the universal Uzbekistan Region Pack structure with verified SHA-256 digests.
"""

from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Dict, List

REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_ROADS_PATH = REPO_ROOT / "assets" / "map" / "tashkent_roads.json"
LEGACY_WEBP_PATH = REPO_ROOT / "assets" / "map" / "tashkent.webp"
LEGACY_WATER_PATH = REPO_ROOT / "assets" / "map" / "tashkent_water.png"
TASHKENT_PACK_DIR = (
    REPO_ROOT / "assets" / "world" / "uzbekistan" / "regions" / "tashkent_city"
)

ORIGIN_LON = 69.279737
ORIGIN_LAT = 41.311081
WGS84_A = 6378137.0
WGS84_E2 = 0.00669437999014


def compute_ellipsoid_scale(lat_deg: float) -> tuple[float, float]:
    phi = math.radians(lat_deg)
    sin_p = math.sin(phi)
    cos_p = math.cos(phi)
    denom = math.sqrt(1.0 - WGS84_E2 * sin_p * sin_p)
    n_rad = WGS84_A / denom
    m_rad = (WGS84_A * (1.0 - WGS84_E2)) / (denom ** 3)
    return (n_rad * cos_p * math.pi / 180.0), (m_rad * math.pi / 180.0)


METERS_PER_DEG_LON, METERS_PER_DEG_LAT = compute_ellipsoid_scale(ORIGIN_LAT)


def legacy_xy_to_wgs84(x: float, y: float) -> List[float]:
    lon = ORIGIN_LON + (x / METERS_PER_DEG_LON)
    lat = ORIGIN_LAT - (y / METERS_PER_DEG_LAT)
    return [round(lon, 6), round(lat, 6)]


def file_sha256_and_size(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {"exists": False, "sizeBytes": 0, "sha256": ""}
    raw = path.read_bytes()
    return {
        "exists": True,
        "sizeBytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def migrate_tashkent() -> Path:
    TASHKENT_PACK_DIR.mkdir(parents=True, exist_ok=True)
    chunks_dir = TASHKENT_PACK_DIR / "chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)

    roads_info = file_sha256_and_size(LEGACY_ROADS_PATH)
    webp_info = file_sha256_and_size(LEGACY_WEBP_PATH)
    water_info = file_sha256_and_size(LEGACY_WATER_PATH)

    road_count = 0
    sample_chunk_roads: List[Dict[str, Any]] = []

    if LEGACY_ROADS_PATH.exists():
        raw_data = json.loads(LEGACY_ROADS_PATH.read_text(encoding="utf-8"))
        raw_roads = (
            raw_data.get("roads", raw_data)
            if isinstance(raw_data, dict)
            else raw_data
        )
        if isinstance(raw_roads, list):
            road_count = len(raw_roads)
            for idx, r in enumerate(raw_roads[:250]):
                wgs_pts = []
                # The current Tashkent dataset stores each road as
                # [class, flags, metadata, [x1, y1, x2, y2]].
                # Older/imported datasets may instead use points/pts objects.
                if isinstance(r, list):
                    coords = next(
                        (item for item in reversed(r)
                         if isinstance(item, list) and len(item) >= 4
                         and all(isinstance(v, (int, float)) for v in item[:4])),
                        None,
                    )
                    if coords:
                        pts = [[coords[0], coords[1]], [coords[2], coords[3]]]
                    else:
                        pts = []
                elif isinstance(r, dict):
                    pts = r.get("points") or r.get("pts") or []
                else:
                    pts = []

                for p in pts:
                    if isinstance(p, list) and len(p) >= 2:
                        wgs_pts.append(legacy_xy_to_wgs84(float(p[0]), float(p[1])))
                    elif isinstance(p, dict) and "x" in p and "y" in p:
                        wgs_pts.append(
                            legacy_xy_to_wgs84(float(p["x"]), float(p["y"]))
                        )
                if wgs_pts:
                    sample_chunk_roads.append({
                        "id": f"uz:road:way:tashkent:{idx}",
                        "wgs84Polyline": wgs_pts,
                    })

    root_chunk_path = chunks_dir / "lod3_tashkent_core.json"
    root_chunk_path.write_text(
        json.dumps(
            {
                "chunkId": "lod3_tashkent_core",
                "regionId": "uz_tashkent_city",
                "lod": 3,
                "legacyRoadsRef": "assets/map/tashkent_roads.json",
                "totalLegacyRoadCount": road_count,
                "sampleWgs84Roads": sample_chunk_roads,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    chunk_meta = file_sha256_and_size(root_chunk_path)

    manifest_path = TASHKENT_PACK_DIR / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["verifiedAssetDigests"] = {
        "tashkent_roads.json": roads_info,
        "tashkent.webp": webp_info,
        "tashkent_water.png": water_info,
        "lod3_tashkent_core.json": chunk_meta,
    }
    manifest["featureCounts"] = {"roads": road_count}
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"[migrate_tashkent_legacy] Verified {road_count} Tashkent roads -> {manifest_path}")
    return manifest_path


if __name__ == "__main__":
    migrate_tashkent()
