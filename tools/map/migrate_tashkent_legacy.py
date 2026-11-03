#!/usr/bin/env python3
"""
migrate_tashkent_legacy.py - deterministic migration of the legacy Tashkent road dataset.

Input  : assets/map/tashkent_roads.json (never modified)
           {"v": 1, "roads": [[cls, layer, oneWay, [x0, y0, x1, y1, ...]], ...]}
           cls 0..4 (trunk, primary, secondary, tertiary, residential), layer 0|1, oneWay 0|1,
           coordinates are legacy game-world units: x east, y south, world 6400x6400,
           centre (3200, 3200) = ORIGIN. 1 unit = 1 m is a documented but UNVERIFIED hypothesis.
Output : assets/world/uzbekistan/regions/tashkent_city/
           chunks/chunk_<ix>_<iy>.json   road features in WGS84 [lon, lat]
           manifest.json                 package manifest (files, sizes, SHA-256, counts, provenance)

Chunk grid: 2000 m ENU cells relative to the origin, ix = floor(east / 2000), iy = floor(north / 2000);
a road belongs to the cell of its midpoint vertex (same vertex the game uses), geometry is not clipped.

package digest (`packageSha256`): SHA-256 of the UTF-8 text made of
  "<path>\\t<bytes>\\t<sha256>\\n" for every entry of `files`, sorted by path.
This is identical to RegionPackageManifest.computePackageDigest in lib/world/region_package_manager.dart.

Exit codes: 0 ok | 1 validation failure | 2 source missing/unreadable/wrong root shape | 3 no usable roads.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = REPO_ROOT / "assets" / "map" / "tashkent_roads.json"
DEFAULT_OUT = REPO_ROOT / "assets" / "world" / "uzbekistan" / "regions" / "tashkent_city"

# Legacy frame (must match lib/world/geo_coordinate_system.dart: NationalCoordinateSystem / LegacyTashkentFrame).
ORIGIN_LON = 69.279737
ORIGIN_LAT = 41.311081
ORIGIN_ALT = 475.0
WORLD_SIZE = 6400.0
WORLD_CENTER = 3200.0
METERS_PER_UNIT = 1.0  # unverified hypothesis (basemap 2 m/px, 3200 px, 6400-unit world)
CHUNK_METERS = 2000.0
COORD_DECIMALS = 7  # ~1 cm

# WGS84
_A = 6378137.0
_F = 1.0 / 298.257223563
_E2 = _F * (2.0 - _F)

SCHEMA_VERSION = "3.0.0"
CHUNK_SCHEMA_VERSION = "1.0.0"
ATTRIBUTION = "© OpenStreetMap contributors (ODbL-1.0)"

# Fields of an existing manifest that are kept; everything else is regenerated.
_PRESERVED_FIELDS = (
    "packageId", "regionId", "isoCode", "soatoCode", "version", "latitude", "longitude",
    "referenceAnchor", "bbox", "installationStatus",
)
_DEFAULT_BASE = {
    "packageId": "pkg_uz_tashkent_city",
    "regionId": "uz_tashkent_city",
    "isoCode": "UZ-TK",
    "soatoCode": "1726",
    "version": "3.0.0",
    "latitude": ORIGIN_LAT,
    "longitude": ORIGIN_LON,
    "referenceAnchor": {
        "latitude": ORIGIN_LAT, "longitude": ORIGIN_LON, "lat": ORIGIN_LAT, "lon": ORIGIN_LON, "elevationMeters": 475,
    },
    "bbox": {"minLon": 69.114, "minLat": 41.158, "maxLon": 69.479, "maxLat": 41.425},
    "installationStatus": "INSTALLED_DETAILED",
}


class MigrationError(Exception):
    """Fatal migration problem; [code] is the process exit code."""

    def __init__(self, message: str, code: int = 1):
        super().__init__(message)
        self.code = code


# ----------------------------------------------------------------------------- geodesy

def _geodetic_to_ecef(lon: float, lat: float, alt: float) -> tuple[float, float, float]:
    phi, lam = math.radians(lat), math.radians(lon)
    s, c = math.sin(phi), math.cos(phi)
    n = _A / math.sqrt(1.0 - _E2 * s * s)
    return ((n + alt) * c * math.cos(lam), (n + alt) * c * math.sin(lam), (n * (1.0 - _E2) + alt) * s)


def _ecef_to_geodetic(x: float, y: float, z: float) -> tuple[float, float, float]:
    lon = math.atan2(y, x)
    r = math.hypot(x, y)
    lat = math.atan2(z, r * (1.0 - _E2))
    alt = 0.0
    for _ in range(12):
        s = math.sin(lat)
        n = _A / math.sqrt(1.0 - _E2 * s * s)
        c = math.cos(lat)
        alt = r / c - n if abs(c) > 1e-9 else abs(z) / abs(s) - n * (1.0 - _E2)
        lat = math.atan2(z, r * (1.0 - _E2 * n / (n + alt)))
    return math.degrees(lon), math.degrees(lat), alt


def enu_to_wgs84(east: float, north: float, up: float = 0.0,
                 origin: tuple[float, float, float] = (ORIGIN_LON, ORIGIN_LAT, ORIGIN_ALT)) -> tuple[float, float, float]:
    """Local ENU metres around [origin] (lon, lat, alt) -> (lon, lat, alt)."""
    ox, oy, oz = _geodetic_to_ecef(*origin)
    phi, lam = math.radians(origin[1]), math.radians(origin[0])
    sp, cp, sl, cl = math.sin(phi), math.cos(phi), math.sin(lam), math.cos(lam)
    dx = -sl * east - sp * cl * north + cp * cl * up
    dy = cl * east - sp * sl * north + cp * sl * up
    dz = cp * north + sp * up
    return _ecef_to_geodetic(ox + dx, oy + dy, oz + dz)


def wgs84_to_enu(lon: float, lat: float, alt: float = 0.0,
                 origin: tuple[float, float, float] = (ORIGIN_LON, ORIGIN_LAT, ORIGIN_ALT)) -> tuple[float, float, float]:
    px, py, pz = _geodetic_to_ecef(lon, lat, alt)
    ox, oy, oz = _geodetic_to_ecef(*origin)
    dx, dy, dz = px - ox, py - oy, pz - oz
    phi, lam = math.radians(origin[1]), math.radians(origin[0])
    sp, cp, sl, cl = math.sin(phi), math.cos(phi), math.sin(lam), math.cos(lam)
    return (-sl * dx + cl * dy, -sp * cl * dx - sp * sl * dy + cp * dz, cp * cl * dx + cp * sl * dy + sp * dz)


def legacy_units_to_enu(x: float, y: float) -> tuple[float, float]:
    """Legacy units (x east, y south, centre 3200) -> ENU (east, north) metres."""
    return (x - WORLD_CENTER) * METERS_PER_UNIT, -(y - WORLD_CENTER) * METERS_PER_UNIT


def legacy_units_to_wgs84(x: float, y: float) -> tuple[float, float]:
    east, north = legacy_units_to_enu(x, y)
    lon, lat, _ = enu_to_wgs84(east, north, 0.0)
    return lon, lat


# ----------------------------------------------------------------------------- parsing

REJECT_REASONS = (
    "not_a_list", "bad_length", "bad_cls", "bad_layer", "bad_oneway", "points_not_a_list",
    "odd_coordinate_count", "too_few_points", "non_numeric", "non_finite", "out_of_range",
)


def _is_int_flag(v: Any, allowed: range) -> bool:
    return isinstance(v, int) and not isinstance(v, bool) and v in allowed


def _is_number(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def parse_road(record: Any) -> tuple[dict | None, str | None]:
    """Parses one legacy road record.

    Returns (road, None) with road = {cls, layer, oneWay, points: [(x, y), ...]} or (None, reason).
    The only supported shape is the 4-element list the real file uses; every other shape is rejected.
    """
    if not isinstance(record, list):
        return None, "not_a_list"
    if len(record) != 4:
        return None, "bad_length"
    cls, layer, one_way, flat = record
    if not _is_int_flag(cls, range(0, 5)):
        return None, "bad_cls"
    if not _is_int_flag(layer, range(0, 2)):
        return None, "bad_layer"
    if not _is_int_flag(one_way, range(0, 2)):
        return None, "bad_oneway"
    if not isinstance(flat, list):
        return None, "points_not_a_list"
    if len(flat) % 2 != 0:
        return None, "odd_coordinate_count"
    if len(flat) < 4:
        return None, "too_few_points"
    if not all(_is_number(v) for v in flat):
        return None, "non_numeric"
    if not all(math.isfinite(v) for v in flat):
        return None, "non_finite"
    if any(v < 0.0 or v > WORLD_SIZE for v in flat):
        return None, "out_of_range"
    pts = [(float(flat[i]), float(flat[i + 1])) for i in range(0, len(flat), 2)]
    return {"cls": cls, "layer": layer, "oneWay": one_way == 1, "points": pts}, None


def road_id(index: int, record: Any) -> str:
    canonical = json.dumps(record, separators=(",", ":"), sort_keys=True, ensure_ascii=True)
    return f"legacy-{index:05d}-{hashlib.sha256(canonical.encode('utf-8')).hexdigest()[:8]}"


def load_source(path: Path) -> tuple[list[Any], bytes]:
    if not path.is_file():
        raise MigrationError(f"source file not found: {path}", 2)
    raw = path.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MigrationError(f"source is not valid JSON: {exc}", 2)
    if not isinstance(data, dict) or data.get("v") != 1 or not isinstance(data.get("roads"), list):
        raise MigrationError('source root must be {"v": 1, "roads": [...]}', 2)
    return data["roads"], raw


# ----------------------------------------------------------------------------- output

def _canonical_json(obj: Any) -> bytes:
    return (json.dumps(obj, separators=(",", ":"), sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def package_digest(files: list[dict]) -> str:
    text = "".join(f"{f['path']}\t{f['bytes']}\t{f['sha256']}\n" for f in sorted(files, key=lambda f: f["path"]))
    return _sha256(text.encode("utf-8"))


def chunk_key(points: list[tuple[float, float]]) -> tuple[int, int]:
    x, y = points[len(points) // 2]
    east, north = legacy_units_to_enu(x, y)
    return math.floor(east / CHUNK_METERS), math.floor(north / CHUNK_METERS)


def build_package(roads: list[Any], source_bytes: bytes, source_rel: str, base: dict) -> tuple[dict[str, bytes], dict]:
    """Converts all roads. Returns ({relative path: bytes} incl. manifest.json, manifest dict)."""
    rejected: dict[str, int] = {}
    rejected_examples: list[dict] = []
    chunks: dict[tuple[int, int], list[dict]] = {}
    point_count = 0
    converted = 0
    lon_min = lat_min = math.inf
    lon_max = lat_max = -math.inf

    for index, record in enumerate(roads):
        road, reason = parse_road(record)
        if road is None:
            rejected[reason] = rejected.get(reason, 0) + 1
            if len(rejected_examples) < 20:
                rejected_examples.append({"sourceIndex": index, "reason": reason})
            continue
        coords = []
        for x, y in road["points"]:
            lon, lat = legacy_units_to_wgs84(x, y)
            lon, lat = round(lon, COORD_DECIMALS), round(lat, COORD_DECIMALS)
            coords.append([lon, lat])
            lon_min, lon_max = min(lon_min, lon), max(lon_max, lon)
            lat_min, lat_max = min(lat_min, lat), max(lat_max, lat)
        point_count += len(coords)
        converted += 1
        chunks.setdefault(chunk_key(road["points"]), []).append({
            "id": road_id(index, record),
            "sourceIndex": index,
            "cls": road["cls"],
            "layer": road["layer"],
            "oneWay": road["oneWay"],
            "coordinates": coords,
        })

    if converted == 0:
        raise MigrationError(f"no usable roads: 0 of {len(roads)} records converted ({rejected})", 3)

    outputs: dict[str, bytes] = {}
    files: list[dict] = []
    for (ix, iy) in sorted(chunks):
        name = f"chunk_{ix}_{iy}"
        feats = sorted(chunks[(ix, iy)], key=lambda f: f["sourceIndex"])
        body = _canonical_json({
            "schemaVersion": CHUNK_SCHEMA_VERSION,
            "chunkId": name,
            "coordinateOrder": "lon,lat",
            "features": feats,
        })
        rel = f"chunks/{name}.json"
        outputs[rel] = body
        files.append({"path": rel, "bytes": len(body), "sha256": _sha256(body), "featureCount": len(feats)})

    manifest = {k: base[k] for k in _PRESERVED_FIELDS if k in base}
    manifest.update({
        "schemaVersion": SCHEMA_VERSION,
        "attribution": ATTRIBUTION,
        "coordinateConvention": (
            "WGS84 degrees; positions are [longitude, latitude] (GeoJSON order). Chunk grid: 2000 m ENU cells "
            "relative to referenceAnchor (ix = floor(east/2000), iy = floor(north/2000)); a road belongs to the "
            "cell of its midpoint vertex. Legacy source units: x east, y south, 1 unit = 1 m (unverified)."
        ),
        "coordinateVerification": {
            "status": "unverified",
            "reason": "The origin and the 1 m/unit scale come from the repository's own map-build documentation; "
                      "no independent surveyed anchor points have been compared against the converted data.",
            "checks": {
                "allConvertedPointsWithinRegionBbox": _within_bbox(manifest.get("bbox"), lon_min, lat_min, lon_max, lat_max),
                "convertedExtent": {
                    "minLon": lon_min, "minLat": lat_min, "maxLon": lon_max, "maxLat": lat_max,
                },
            },
        },
        "source": {"path": source_rel, "bytes": len(source_bytes), "sha256": _sha256(source_bytes), "format": "legacy roads v1"},
        "sourceRoadCount": len(roads),
        "convertedRoadCount": converted,
        "rejectedRoadCount": len(roads) - converted,
        "rejectedByReason": dict(sorted(rejected.items())),
        "rejectedExamples": rejected_examples,
        "pointCount": point_count,
        "chunkCount": len(files),
        "chunkGridMeters": CHUNK_METERS,
        "files": files,
        "packageSha256": package_digest(files),
    })
    outputs["manifest.json"] = _canonical_json(manifest)
    return outputs, manifest


def _within_bbox(bbox: dict | None, lon_min: float, lat_min: float, lon_max: float, lat_max: float) -> bool:
    if not bbox:
        return False
    return (bbox["minLon"] <= lon_min and lon_max <= bbox["maxLon"]
            and bbox["minLat"] <= lat_min and lat_max <= bbox["maxLat"])


def read_base(out_dir: Path) -> dict:
    existing = out_dir / "manifest.json"
    if existing.is_file():
        try:
            loaded = json.loads(existing.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                return {**_DEFAULT_BASE, **{k: v for k, v in loaded.items() if k in _PRESERVED_FIELDS}}
        except (OSError, json.JSONDecodeError):
            pass
    return dict(_DEFAULT_BASE)


def write_package(out_dir: Path, outputs: dict[str, bytes]) -> None:
    chunk_dir = out_dir / "chunks"
    chunk_dir.mkdir(parents=True, exist_ok=True)
    wanted = {rel for rel in outputs if rel.startswith("chunks/")}
    for stale in chunk_dir.glob("chunk_*.json"):
        if f"chunks/{stale.name}" not in wanted:
            stale.unlink()
    for rel, data in outputs.items():
        target = out_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def validate_package(out_dir: Path, manifest: dict, expected_source_count: int) -> list[str]:
    """Re-reads everything from disk. Returns a list of problems (empty = valid)."""
    problems: list[str] = []
    if manifest["convertedRoadCount"] + manifest["rejectedRoadCount"] != expected_source_count:
        problems.append("converted + rejected != source road count")
    if sum(manifest["rejectedByReason"].values()) != manifest["rejectedRoadCount"]:
        problems.append("rejectedByReason does not add up")
    feature_total = 0
    points_total = 0
    for f in manifest["files"]:
        path = out_dir / f["path"]
        if not path.is_file():
            problems.append(f"missing file: {f['path']}")
            continue
        data = path.read_bytes()
        if len(data) != f["bytes"]:
            problems.append(f"size mismatch: {f['path']}")
        if _sha256(data) != f["sha256"]:
            problems.append(f"sha256 mismatch: {f['path']}")
        chunk = json.loads(data.decode("utf-8"))
        if len(chunk["features"]) != f["featureCount"]:
            problems.append(f"featureCount mismatch: {f['path']}")
        feature_total += len(chunk["features"])
        points_total += sum(len(ft["coordinates"]) for ft in chunk["features"])
    if feature_total != manifest["convertedRoadCount"]:
        problems.append("chunk features do not add up to convertedRoadCount")
    if points_total != manifest["pointCount"]:
        problems.append("chunk points do not add up to pointCount")
    if package_digest(manifest["files"]) != manifest["packageSha256"]:
        problems.append("packageSha256 mismatch")
    on_disk = {f"chunks/{p.name}" for p in (out_dir / "chunks").glob("chunk_*.json")}
    listed = {f["path"] for f in manifest["files"]}
    if on_disk != listed:
        problems.append(f"chunk files on disk differ from the manifest: {sorted(on_disk ^ listed)[:5]}")
    return problems


def migrate(source: Path = DEFAULT_SOURCE, out_dir: Path = DEFAULT_OUT, source_rel: str | None = None) -> dict:
    """Runs the full migration and returns the manifest. Raises MigrationError."""
    roads, source_bytes = load_source(source)
    before = _sha256(source_bytes)
    if source_rel is None:
        try:
            source_rel = source.resolve().relative_to(REPO_ROOT).as_posix()
        except ValueError:
            source_rel = source.name
    outputs, manifest = build_package(roads, source_bytes, source_rel, read_base(out_dir))
    write_package(out_dir, outputs)
    problems = validate_package(out_dir, manifest, len(roads))
    if _sha256(source.read_bytes()) != before:
        problems.append("source file changed during migration")
    if problems:
        raise MigrationError("validation failed: " + "; ".join(problems), 1)
    return manifest


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args(argv)
    try:
        m = migrate(args.source, args.out)
    except MigrationError as exc:
        print(f"[migrate_tashkent_legacy] FAILED: {exc}", file=sys.stderr)
        return exc.code
    print(
        f"[migrate_tashkent_legacy] source roads={m['sourceRoadCount']} converted={m['convertedRoadCount']} "
        f"rejected={m['rejectedRoadCount']} points={m['pointCount']} chunks={m['chunkCount']} "
        f"-> {args.out}"
    )
    if m["rejectedByReason"]:
        print(f"[migrate_tashkent_legacy] rejected by reason: {m['rejectedByReason']}")
    print(f"[migrate_tashkent_legacy] packageSha256={m['packageSha256']}")
    print(f"[migrate_tashkent_legacy] coordinate verification: {m['coordinateVerification']['status']} "
          f"(file integrity verified; geographic accuracy not independently surveyed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
