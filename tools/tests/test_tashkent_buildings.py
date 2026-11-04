"""Tests for tools/map/build_tashkent_buildings.py and the committed assets/map/tashkent_buildings.bin."""
import gzip
import hashlib
import json
import math
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "map"))
import build_tashkent_buildings as b  # noqa: E402

BIN = REPO / "assets" / "map" / "tashkent_buildings.bin"
META = REPO / "assets" / "map" / "tashkent_buildings_meta.json"
ANCHORS = REPO / "tools" / "map" / "tashkent_osm_anchors.json"


def feature(ring):
    return json.dumps({"type": "Feature", "properties": {"height": -1.0},
                       "geometry": {"type": "Polygon", "coordinates": [ring]}})


def square_lonlat(lon, lat, side_deg):
    return [[lon, lat], [lon + side_deg, lat], [lon + side_deg, lat + side_deg], [lon, lat + side_deg], [lon, lat]]


class ProjectionTests(unittest.TestCase):
    def test_chain_matches_the_game_map_at_every_osm_anchor(self):
        # anchors' legacy positions come from the SVG node circles, i.e. from how the game map was drawn
        anchors = json.loads(ANCHORS.read_text(encoding="utf-8"))["anchors"]
        worst = max(math.hypot(b.wgs84_to_game(a["osmLon"], a["osmLat"])[0] - a["legacyX"],
                               b.wgs84_to_game(a["osmLon"], a["osmLat"])[1] - a["legacyY"]) for a in anchors)
        self.assertLess(worst, 0.05)

    def test_axes_east_is_plus_x_north_is_minus_y(self):
        x0, y0 = b.wgs84_to_game(69.28, 41.31)
        x1, _ = b.wgs84_to_game(69.29, 41.31)
        _, y1 = b.wgs84_to_game(69.28, 41.32)
        self.assertGreater(x1, x0)
        self.assertLess(y1, y0)


class HeightAndShapeTests(unittest.TestCase):
    def test_elongation_of_rectangles(self):
        self.assertAlmostEqual(b.elongation([(0, 0), (10, 0), (10, 10), (0, 10)]), 1.0, places=6)
        self.assertAlmostEqual(b.elongation([(0, 0), (60, 0), (60, 12), (0, 12)]), 5.0, places=6)
        # rotated 30 degrees: still 5
        c, s = math.cos(0.52), math.sin(0.52)
        rot = [(x * c - y * s, x * s + y * c) for x, y in [(0, 0), (60, 0), (60, 12), (0, 12)]]
        self.assertAlmostEqual(b.elongation(rot), 5.0, places=4)

    def test_heights_are_deterministic_and_follow_the_documented_bands(self):
        self.assertEqual(b.estimate_height(30, 1, 10, 10), 3.2)
        for x in range(0, 400, 37):
            self.assertEqual(b.estimate_height(500, 4, x, 7), b.estimate_height(500, 4, x, 7))
            self.assertIn(b.estimate_height(500, 4, x, 7), {4 * 3.2, 5 * 3.2, 9 * 3.2})  # Soviet block
            self.assertIn(b.estimate_height(120, 1.2, x, 7), {3.2, 6.4})  # house
            self.assertLessEqual(b.estimate_height(9000, 1, x, 7), 60)

    def test_area(self):
        self.assertAlmostEqual(b.polygon_area([(0, 0), (4, 0), (4, 3), (0, 3)]), 12.0)


class EncodingTests(unittest.TestCase):
    def test_round_trip(self):
        data = [([(0, 0), (40, 0), (40, 40)], 3.2), ([(100, 100), (200, 100), (200, 180), (100, 180)], 28.8)]
        out = b.decode(b.encode(data))
        self.assertEqual([[(x * b.QUANT, y * b.QUANT) for x, y in p] for p, _ in out], [p for p, _ in data])
        self.assertEqual([h for _, h in out], [3.0, 29.0])  # 0.5 m steps

    def test_corrupt_data_is_rejected(self):
        with self.assertRaises(b.BuildError):
            b.decode(b"XXXX" + bytes(4))
        with self.assertRaises(b.BuildError):
            b.decode(b.encode([([(0, 0), (40, 0), (40, 40)], 3)]) + b"\x00")

    def test_build_filters_and_is_deterministic(self):
        lines = [
            feature(square_lonlat(69.2797, 41.3110, 0.0003)),    # ~25 x 33 m near the centre: kept
            feature(square_lonlat(69.2797, 41.3120, 0.00001)),   # < 1 m2: dropped
            feature(square_lonlat(70.5, 41.0, 0.0003)),          # far outside the window: dropped
        ]
        body1, meta1 = b.build(lines, "x")
        body2, _ = b.build(list(reversed(lines)), "x")
        self.assertEqual(body1, body2)
        self.assertEqual(meta1["buildingCount"], 1)
        self.assertEqual(meta1["source"]["featuresRead"], 3)


class CommittedAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = BIN.read_bytes()
        cls.meta = json.loads(META.read_text(encoding="utf-8"))
        cls.buildings = b.decode(cls.data)

    def test_meta_matches_the_binary(self):
        self.assertEqual(self.meta["sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(self.meta["bytes"], len(self.data))
        self.assertEqual(self.meta["buildingCount"], len(self.buildings))
        self.assertEqual(self.meta["pointCount"], sum(len(p) for p, _ in self.buildings))
        self.assertEqual(self.meta["source"]["license"], "ODbL-1.0")
        self.assertIn("ESTIMATED", self.meta["heights"])

    def test_buildings_are_inside_the_world_with_plausible_size_and_height(self):
        self.assertGreater(len(self.buildings), 20000)
        for pts, h in self.buildings:
            self.assertGreaterEqual(len(pts), 3)
            self.assertTrue(all(0 <= x <= b.WORLD and 0 <= y <= b.WORLD for x, y in pts))
            self.assertTrue(1.0 <= h <= 60.0, h)

    def test_the_centre_is_built_up(self):
        near = [p for p, _ in self.buildings if abs(p[0][0] - 3200) < 600 and abs(p[0][1] - 3200) < 600]
        self.assertGreater(len(near), 200)  # sanity: the centre is not empty (282 at build time; large parks)

    def test_asset_size_stays_small(self):
        self.assertLess(len(self.data), 1_500_000)


if __name__ == "__main__":
    unittest.main()


class ObjExportTests(unittest.TestCase):
    def test_export_is_a_valid_obj_with_ground_and_buildings(self):
        import export_tashkent_obj as ex
        out = Path(tempfile.mkdtemp(prefix="tk_obj_"))
        try:
            s = ex.export(out, 400)
            self.assertGreater(s["buildings"], 50)
            text = (out / "tashkent.obj").read_text(encoding="utf-8")
            verts = sum(1 for ln in text.splitlines() if ln.startswith("v "))
            self.assertEqual(verts, s["vertices"])
            for ln in text.splitlines():
                if ln.startswith("f "):
                    for tok in ln.split()[1:]:
                        self.assertTrue(1 <= int(tok.split("/")[0]) <= verts, ln)
            self.assertIn("map_Kd tashkent.webp", (out / "tashkent.mtl").read_text(encoding="utf-8"))
            self.assertTrue((out / "tashkent.webp").stat().st_size > 100_000)
        finally:
            import shutil
            shutil.rmtree(out, ignore_errors=True)

    def test_triangulation_keeps_the_area_of_an_l_shape(self):
        import export_tashkent_obj as ex
        pts = [(0, 0), (30, 0), (30, 10), (10, 10), (10, 30), (0, 30)]
        tris = ex.triangulate(pts)
        self.assertEqual(len(tris), 4)
        area = sum(abs((pts[b][0] - pts[a][0]) * (pts[c][1] - pts[a][1]) - (pts[b][1] - pts[a][1]) * (pts[c][0] - pts[a][0])) / 2
                   for a, b, c in tris)
        self.assertAlmostEqual(area, b.polygon_area([(float(x), float(y)) for x, y in pts]))
