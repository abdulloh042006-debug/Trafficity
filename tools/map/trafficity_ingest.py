#!/usr/bin/env python3
"""
trafficity-ingest — Universal OSM & GeoJSON Region Packager for Trafficity.
"""

from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
UZ_WORLD_DIR = REPO_ROOT / "assets" / "world" / "uzbekistan"


def sha256_file(path: Path) -> Tuple[str, int]:
    h = hashlib.sha256()
    data = path.read_bytes()
    h.update(data)
    return h.hexdigest(), len(data)


def wgs84_to_tile_xy(lon: float, lat: float, zoom: int) -> Tuple[int, int]:
    lat_rad = math.radians(max(-85.0511, min(85.0511, lat)))
    n = 1 << zoom
    xtile = int((lon + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return xtile, ytile


def tile_xy_to_bbox(x: int, y: int, zoom: int) -> Dict[str, float]:
    n = float(1 << zoom)
    min_lon = x / n * 360.0 - 180.0
    max_lon = (x + 1) / n * 360.0 - 180.0
    max_lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / n))))
    min_lat = math.degrees(
        math.atan(math.sinh(math.pi * (1.0 - 2.0 * (y + 1) / n)))
    )
    return {
        "minLon": round(min_lon, 6),
        "minLat": round(min_lat, 6),
        "maxLon": round(max_lon, 6),
        "maxLat": round(max_lat, 6),
    }


def ingest_region(
    region_id: str,
    input_geojson: Path | None,
    dataset_version: str = "2026.11.0",
) -> Path:
    catalog_path = UZ_WORLD_DIR / "region_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    region_entry = next(
        (r for r in catalog["regions"] if r["regionId"] == region_id),
        None,
    )
    if region_entry is None:
        raise ValueError(f"Unknown regionId '{region_id}' in {catalog_path}")

    slug = region_id.replace("uz_", "")
    region_dir = UZ_WORLD_DIR / "regions" / slug
    chunks_dir = region_dir / "chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)

    roads: List[Dict[str, Any]] = []
    buildings: List[Dict[str, Any]] = []
    signals: List[Dict[str, Any]] = []
    waterways: List[Dict[str, Any]] = []
    parks: List[Dict[str, Any]] = []

    if input_geojson and input_geojson.exists():
        raw = json.loads(input_geojson.read_text(encoding="utf-8"))
        features = raw.get("features", [])
        for idx, feat in enumerate(features):
            props = feat.get("properties") or {}
            geom = feat.get("geometry") or {}
            gtype = geom.get("type")
            coords = geom.get("coordinates") or []

            if "highway" in props:
                hw = props["highway"]
                if hw == "traffic_signals" and gtype == "Point":
                    signals.append({
                        "id": f"uz:signal:{region_id}:{idx}",
                        "wgs84": coords[:2],
                    })
                elif gtype == "LineString" and len(coords) >= 2:
                    roads.append({
                        "id": f"uz:road:way:{props.get('id', idx)}",
                        "highway": hw,
                        "name": props.get("name", ""),
                        "lanes": int(props.get("lanes", 2)),
                        "oneway": props.get("oneway") in ("yes", "1", True),
                        "wgs84Polyline": coords,
                    })
            elif "building" in props and gtype == "Polygon":
                buildings.append({
                    "id": f"uz:building:{region_id}:{idx}",
                    "building": props.get("building", "yes"),
                    "height": float(props["height"]) if "height" in props else None,
                    "levels": int(props["building:levels"])
                    if "building:levels" in props
                    else None,
                    "wgs84Ring": coords[0] if coords else [],
                })
            elif "waterway" in props or props.get("natural") == "water":
                waterways.append({
                    "id": f"uz:water:{region_id}:{idx}",
                    "geometry": geom,
                })
            elif props.get("leisure") == "park":
                parks.append({
                    "id": f"uz:park:{region_id}:{idx}",
                    "geometry": geom,
                })

    chunk_buckets: Dict[str, List[Dict[str, Any]]] = {}
    for road in roads:
        first_pt = road["wgs84Polyline"][0]
        tx, ty = wgs84_to_tile_xy(float(first_pt[0]), float(first_pt[1]), 14)
        cid = f"lod3_14_{tx}_{ty}"
        chunk_buckets.setdefault(cid, []).append(road)

    chunk_descriptors: List[Dict[str, Any]] = []
    for cid, c_roads in chunk_buckets.items():
        _, _, tx_s, ty_s = cid.split("_")
        tx, ty = int(tx_s), int(ty_s)
        cbbox = tile_xy_to_bbox(tx, ty, 14)
        chunk_file = chunks_dir / f"{cid}.json"
        chunk_payload = {
            "chunkId": cid,
            "regionId": region_id,
            "lod": 3,
            "bbox": cbbox,
            "roads": c_roads,
        }
        chunk_file.write_text(
            json.dumps(chunk_payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        digest, size_b = sha256_file(chunk_file)
        chunk_descriptors.append({
            "chunkId": cid,
            "regionId": region_id,
            "lod": 3,
            "center": [
                round((cbbox["minLon"] + cbbox["maxLon"]) * 0.5, 6),
                round((cbbox["minLat"] + cbbox["maxLat"]) * 0.5, 6),
            ],
            "bbox": cbbox,
            "radiusMeters": 1200.0,
            "assetPath": f"chunks/{cid}.json",
            "sha256": digest,
            "sizeBytes": size_b,
        })

    chunk_index_path = chunks_dir / "chunk_index.json"
    chunk_index_path.write_text(
        json.dumps({"chunks": chunk_descriptors}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    has_detailed = len(roads) > 0
    manifest_data = {
        "schemaVersion": "3.0.0",
        "regionId": region_id,
        "isoCode": region_entry["isoCode"],
        "soatoCode": region_entry.get("soatoCode", ""),
        "parentAdminId": "UZ",
        "adminLevel": "FIRST_LEVEL_ADMIN",
        "names": region_entry["names"],
        "primaryCityId": region_entry["primaryCityId"],
        "bbox": region_entry["bbox"],
        "referenceAnchor": {
            "lon": region_entry["centroid"][0],
            "lat": region_entry["centroid"][1],
            "elevationMeters": 450.0,
        },
        "crs": {
            "canonical": "EPSG:4326",
            "localProjection": "LOCAL_ENU_WGS84",
        },
        "architectureProfileId": region_entry["architectureProfileId"],
        "datasetVersion": dataset_version,
        "dataSource": ["OpenStreetMap Contributors (ODbL)"],
        "attribution": "© OpenStreetMap contributors (ODbL)",
        "availableFeatureLayers": (
            ["boundaries", "roads", "buildings", "signals", "parks", "waterways"]
            if has_detailed
            else ["boundaries"]
        ),
        "availableDetailLevels": [1, 2, 3, 4] if has_detailed else [1, 2],
        "chunkIndexRef": "chunks/chunk_index.json",
        "featureCounts": {
            "roads": len(roads),
            "buildings": len(buildings),
            "signals": len(signals),
            "waterways": len(waterways),
            "parks": len(parks),
        },
        "installationStatus": (
            "INSTALLED_DETAILED" if has_detailed else "OVERVIEW_ONLY"
        ),
    }

    manifest_path = region_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest_data, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    region_entry["defaultReadiness"] = (
        "INSTALLED_DETAILED" if has_detailed else "OVERVIEW_ONLY"
    )
    region_entry["availableDetailLevels"] = [1, 2, 3, 4] if has_detailed else [1, 2]
    catalog_path.write_text(
        json.dumps(catalog, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return manifest_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Package OSM/GeoJSON data into a Trafficity Uzbekistan Region Pack."
    )
    parser.add_argument("--region", required=True, help="Region ID, e.g. uz_samarkand")
    parser.add_argument("--input", type=Path, default=None, help="Input GeoJSON path")
    parser.add_argument("--version", default="2026.11.0", help="Dataset version string")
    args = parser.parse_args()

    out = ingest_region(args.region, args.input, args.version)
    print(f"[trafficity-ingest] Wrote region manifest: {out}")


if __name__ == "__main__":
    main()
