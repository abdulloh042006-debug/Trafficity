"""Tests for tools/map/build_uzbekistan_borders.py and the committed assets/world/uzbekistan/region_borders.json."""
import json
import math
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "map"))
import build_uzbekistan_borders as b  # noqa: E402

ASSET = REPO / "assets" / "world" / "uzbekistan" / "region_borders.json"
CATALOG = json.loads((REPO / "assets" / "world" / "uzbekistan" / "region_catalog.json").read_text(encoding="utf-8"))


def inside(pt, ring):
    x, y = pt
    c = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def in_polygon(pt, poly):
    return sum(inside(pt, r) for r in poly) % 2 == 1


def area_km2(ring):
    kx, ky = 111.32 * math.cos(math.radians(41.3)), 110.57
    return abs(sum(x1 * kx * y2 * ky - x2 * kx * y1 * ky for (x1, y1), (x2, y2) in zip(ring, ring[1:])) / 2)


class SimplifyTests(unittest.TestCase):
    def test_collinear_points_are_dropped_corners_are_kept(self):
        pts = [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2)]
        self.assertEqual(b.simplify(pts, 0.01), [(0, 0), (3, 0), (3, 2)])

    def test_short_input_is_unchanged(self):
        self.assertEqual(b.simplify([(0, 0), (1, 1)], 0.5), [(0, 0), (1, 1)])

    def test_ring_stays_closed_and_rounded(self):
        ring = [[0, 0], [10.123456, 0], [10.123456, 10], [0, 10], [0, 0]]
        out = b.simplify_ring(ring, 0.0001)
        self.assertEqual(out[0], out[-1])
        self.assertIn([10.1235, 0.0], out)

    def test_collapsed_ring_is_reported(self):
        self.assertIsNone(b.simplify_ring([[0, 0], [0.00001, 0], [0, 0.00001], [0, 0]], 0.5))


class BuildTests(unittest.TestCase):
    def feature(self, iso, name="X", admin="Uzbekistan", geom=None):
        geom = geom or {"type": "Polygon", "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]}
        return {"type": "Feature", "properties": {"iso_a2": "UZ", "admin": admin, "iso_3166_2": iso, "name_en": name}, "geometry": geom}

    def small_catalog(self):
        return {"regions": [{"regionId": "uz_a", "isoCode": "UZ-A"}, {"regionId": "uz_b", "isoCode": "UZ-B"}]}

    def run_build(self, features, catalog=None):
        src = json.dumps({"type": "FeatureCollection", "features": features}).encode()
        return b.build(src, catalog or self.small_catalog())

    def test_matches_by_iso_and_ignores_other_countries(self):
        other = {"type": "Feature", "properties": {"iso_a2": "KZ", "admin": "Kazakhstan", "iso_3166_2": "KZ-X"},
                 "geometry": {"type": "Polygon", "coordinates": [[[5, 5], [6, 5], [6, 6], [5, 5]]]}}
        doc = self.run_build([self.feature("UZ-B"), self.feature("UZ-A"), other])
        self.assertEqual(list(doc["regions"]), ["uz_a", "uz_b"])
        self.assertEqual(doc["schema"], b.SCHEMA)

    def test_missing_unknown_and_duplicate_regions_fail(self):
        with self.assertRaises(b.BorderError):
            self.run_build([self.feature("UZ-A")])  # UZ-B missing
        with self.assertRaises(b.BorderError):
            self.run_build([self.feature("UZ-A"), self.feature("UZ-B"), self.feature("UZ-Z")])
        with self.assertRaises(b.BorderError):
            self.run_build([self.feature("UZ-A"), self.feature("UZ-A"), self.feature("UZ-B")])

    def test_output_bytes_are_deterministic(self):
        feats = [self.feature("UZ-A"), self.feature("UZ-B")]
        self.assertEqual(b.canonical(self.run_build(feats)), b.canonical(self.run_build(feats)))
        # a different feature order in the source changes only the recorded source digest, never the regions
        self.assertEqual(self.run_build(feats)["regions"], self.run_build(list(reversed(feats)))["regions"])


class CommittedAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads(ASSET.read_text(encoding="utf-8"))

    def test_header_states_source_license_and_that_these_are_not_legal_borders(self):
        d = self.doc
        self.assertEqual(d["schema"], b.SCHEMA)
        self.assertIn("Natural Earth", d["source"]["name"])
        self.assertIn("Public domain", d["source"]["license"])
        self.assertRegex(d["source"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertIn("not legal", d["notice"])

    def test_exactly_the_14_catalog_regions_with_matching_iso(self):
        want = {r["regionId"]: r["isoCode"] for r in CATALOG["regions"]}
        self.assertEqual(len(want), 14)
        self.assertEqual({k: v["isoCode"] for k, v in self.doc["regions"].items()}, want)

    def test_rings_are_closed_valid_and_inside_uzbekistan(self):
        for rid, reg in self.doc["regions"].items():
            self.assertTrue(reg["polygons"], rid)
            for poly in reg["polygons"]:
                for ring in poly:
                    self.assertGreaterEqual(len(ring), b.MIN_RING_POINTS, rid)
                    self.assertEqual(ring[0], ring[-1], rid)
                    for lon, lat in ring:
                        self.assertTrue(55.9 < lon < 73.2 and 37.1 < lat < 45.6, (rid, lon, lat))
                self.assertGreater(area_km2(poly[0]), 1.0, rid)

    def test_catalog_representative_point_lies_in_its_own_polygon(self):
        for r in CATALOG["regions"]:
            rp = r["representativePoint"]
            pt = (rp[0], rp[1]) if isinstance(rp, list) else (rp["lon"], rp["lat"])
            polys = self.doc["regions"][r["regionId"]]["polygons"]
            self.assertTrue(any(in_polygon(pt, p) for p in polys), r["regionId"])

    def test_total_area_matches_the_known_area_of_uzbekistan(self):
        total = sum(area_km2(p[0]) - sum(area_km2(h) for h in p[1:]) for reg in self.doc["regions"].values() for p in reg["polygons"])
        self.assertAlmostEqual(total / 448_978, 1.0, delta=0.03)  # published area of Uzbekistan, km2

    def test_asset_is_small_enough_for_the_app(self):
        self.assertLess(ASSET.stat().st_size, 80_000)


if __name__ == "__main__":
    unittest.main()
