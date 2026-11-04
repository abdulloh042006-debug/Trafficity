"""Tests for tools/map/migrate_tashkent_legacy.py (run: python3 -m unittest discover -s tools/tests -v)."""
import hashlib
import json
import math
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "map"))
import migrate_tashkent_legacy as mig  # noqa: E402

REAL_SOURCE = REPO / "assets" / "map" / "tashkent_roads.json"
COMMITTED = REPO / "assets" / "world" / "uzbekistan" / "regions" / "tashkent_city"

GOOD_A = [4, 0, 0, [3200.0, 3200.0, 3300.0, 3200.0]]            # at the centre, going east
GOOD_B = [0, 1, 1, [100.0, 100.0, 200.0, 150.0, 300.0, 400.0]]  # far north-west, elevated, one-way
GOOD_C = [2, 0, 0, [5000.0, 5000.0, 5100.0, 5200.0]]            # south-east


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="trafficity_mig_"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.out = self.tmp / "out"

    def write_source(self, roads, root=None, name="roads.json"):
        path = self.tmp / name
        data = root if root is not None else {"v": 1, "roads": roads}
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def tree_digest(self, d: Path):
        return {str(p.relative_to(d)): sha(p.read_bytes()) for p in sorted(d.rglob("*")) if p.is_file()}


class VerificationTests(Fixture):
    ANCHORS = REPO / "tools" / "map" / "tashkent_osm_anchors.json"

    def write_anchors(self, mutate=None, name="anchors.json"):
        doc = json.loads(self.ANCHORS.read_text(encoding="utf-8"))
        if mutate:
            mutate(doc)
        path = self.tmp / name
        path.write_text(json.dumps(doc), encoding="utf-8")
        return path

    def test_committed_anchors_are_independent_osm_nodes(self):
        doc = json.loads(self.ANCHORS.read_text(encoding="utf-8"))
        ids = [a["osmNodeId"] for a in doc["anchors"]]
        self.assertGreaterEqual(len(ids), 70)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("2026-11-04", doc["source"]["fetchedOn"])
        self.assertIn("api.openstreetmap.org", doc["source"]["osmCoordinates"])
        for a in doc["anchors"]:
            self.assertTrue(40.0 < a["osmLat"] < 42.5 and 68.0 < a["osmLon"] < 71.0, a)

    def test_real_anchors_give_verified_approximate_with_stated_numbers(self):
        v = mig.verify_against_anchors(self.ANCHORS)
        self.assertEqual(v["status"], "verified_approximate")
        self.assertGreaterEqual(v["anchorsInScope"], mig.VERIFY_MIN_ANCHORS)
        self.assertLessEqual(v["maxErrorInScopeMeters"], mig.VERIFY_TOLERANCE_METERS)
        self.assertLess(v["medianErrorInScopeMeters"], v["maxErrorInScopeMeters"] + 1e-9)
        self.assertGreater(v["maxErrorOverallMeters"], v["maxErrorInScopeMeters"])  # error grows with distance; not hidden
        self.assertIn("not survey-grade", v["reason"])
        self.assertEqual(v, mig.verify_against_anchors(self.ANCHORS))  # deterministic

    def test_perfect_anchor_has_zero_error_and_wrong_axis_fails(self):
        def perfect(doc):
            pts = [(1000.0, 3200.0), (3200.0, 1000.0), (4000.0, 4000.0), (2500.0, 2800.0)]
            doc["anchors"] = []
            for i, (x, y) in enumerate(pts):
                lon, lat = mig.legacy_units_to_wgs84(x, y)
                doc["anchors"].append({"osmNodeId": i + 1, "name": f"p{i}", "osmLat": lat, "osmLon": lon,
                                       "legacyX": x, "legacyY": y})
        v = mig.verify_against_anchors(self.write_anchors(perfect))
        self.assertEqual((v["status"], v["maxErrorInScopeMeters"]), ("verified_approximate", 0.0))

        def flipped(doc):  # same OSM positions but y axis pointing the other way
            perfect(doc)
            for a in doc["anchors"]:
                a["legacyY"] = 6400.0 - a["legacyY"]
        v = mig.verify_against_anchors(self.write_anchors(flipped, "flipped.json"))
        self.assertEqual(v["status"], "failed")
        self.assertIn("Tolerance exceeded", v["reason"])

    def test_wrong_scale_or_origin_is_detected(self):
        def shifted(doc):
            for a in doc["anchors"]:
                a["legacyX"] += 100.0  # 100 m east
        self.assertEqual(mig.verify_against_anchors(self.write_anchors(shifted))["status"], "failed")

    def test_missing_corrupt_or_too_few_anchors_stay_unverified(self):
        self.assertEqual(mig.verify_against_anchors(self.tmp / "nope.json")["status"], "unverified")
        bad = self.tmp / "bad.json"
        bad.write_text("{not json", encoding="utf-8")
        self.assertEqual(mig.verify_against_anchors(bad)["status"], "unverified")
        self.assertEqual(mig.verify_against_anchors(self.write_anchors(lambda d: d.update(anchors=d["anchors"][:2]), "two.json"))["status"],
                         "unverified")
        dup = self.write_anchors(lambda d: d["anchors"].append(dict(d["anchors"][0])), "dup.json")
        self.assertEqual(mig.verify_against_anchors(dup)["status"], "unverified")
        nan = self.write_anchors(lambda d: d["anchors"][0].update(osmLat=99.0), "range.json")
        self.assertEqual(mig.verify_against_anchors(nan)["status"], "unverified")

    def test_manifest_uses_the_verification(self):
        src = self.write_source([GOOD_A, GOOD_C])
        m = mig.migrate(src, self.out, anchors_path=self.tmp / "missing.json")
        self.assertEqual(m["coordinateVerification"]["status"], "unverified")
        m = mig.migrate(src, self.out)
        self.assertEqual(m["coordinateVerification"]["status"], "verified_approximate")
        self.assertIn("allConvertedPointsWithinRegionBbox", m["coordinateVerification"]["checks"])


class ParseRoadTests(unittest.TestCase):
    def test_real_shape_is_parsed(self):
        road, reason = mig.parse_road(GOOD_B)
        self.assertIsNone(reason)
        self.assertEqual(road["cls"], 0)
        self.assertEqual(road["layer"], 1)
        self.assertTrue(road["oneWay"])
        self.assertEqual(road["points"], [(100.0, 100.0), (200.0, 150.0), (300.0, 400.0)])

    def test_integer_coordinates_are_accepted(self):
        road, reason = mig.parse_road([1, 0, 0, [10, 20, 30, 40]])
        self.assertIsNone(reason)
        self.assertEqual(road["points"], [(10.0, 20.0), (30.0, 40.0)])

    def test_every_rejection_reason(self):
        cases = {
            "not_a_list": {"points": [1, 2, 3, 4]},
            "bad_length": [1, 0, 0],
            "bad_cls": [9, 0, 0, [1, 2, 3, 4]],
            "bad_layer": [1, 2, 0, [1, 2, 3, 4]],
            "bad_oneway": [1, 0, 5, [1, 2, 3, 4]],
            "points_not_a_list": [1, 0, 0, "abcd"],
            "odd_coordinate_count": [1, 0, 0, [1, 2, 3]],
            "too_few_points": [1, 0, 0, [1, 2]],
            "non_numeric": [1, 0, 0, [1, 2, "3", 4]],
            "non_finite": [1, 0, 0, [1, 2, float("nan"), 4]],
            "out_of_range": [1, 0, 0, [1, 2, 6400.1, 4]],
        }
        self.assertEqual(set(cases), set(mig.REJECT_REASONS))
        for expected, record in cases.items():
            road, reason = mig.parse_road(record)
            self.assertIsNone(road, expected)
            self.assertEqual(reason, expected)

    def test_infinite_negative_and_bool_values_are_rejected(self):
        self.assertEqual(mig.parse_road([1, 0, 0, [1, 2, float("inf"), 4]])[1], "non_finite")
        self.assertEqual(mig.parse_road([1, 0, 0, [-0.5, 2, 3, 4]])[1], "out_of_range")
        self.assertEqual(mig.parse_road([True, 0, 0, [1, 2, 3, 4]])[1], "bad_cls")
        self.assertEqual(mig.parse_road([1, 0, 0, [True, 2, 3, 4]])[1], "non_numeric")

    def test_dict_records_are_rejected_not_guessed(self):
        self.assertEqual(mig.parse_road({"points": [[1, 2], [3, 4]]})[1], "not_a_list")

    def test_road_id_is_deterministic_and_input_sensitive(self):
        self.assertEqual(mig.road_id(7, GOOD_A), mig.road_id(7, GOOD_A))
        self.assertNotEqual(mig.road_id(7, GOOD_A), mig.road_id(8, GOOD_A))
        self.assertNotEqual(mig.road_id(7, GOOD_A), mig.road_id(7, GOOD_B))
        self.assertRegex(mig.road_id(7, GOOD_A), r"^legacy-00007-[0-9a-f]{8}$")


class ConversionTests(unittest.TestCase):
    def test_centre_maps_to_origin(self):
        lon, lat = mig.legacy_units_to_wgs84(3200.0, 3200.0)
        self.assertAlmostEqual(lon, mig.ORIGIN_LON, places=9)
        self.assertAlmostEqual(lat, mig.ORIGIN_LAT, places=9)

    def test_axes_east_is_plus_x_and_south_is_plus_y(self):
        lon_e, lat_e = mig.legacy_units_to_wgs84(3300.0, 3200.0)
        lon_s, lat_s = mig.legacy_units_to_wgs84(3200.0, 3300.0)
        self.assertGreater(lon_e, mig.ORIGIN_LON)
        self.assertAlmostEqual(lat_e, mig.ORIGIN_LAT, places=5)
        self.assertLess(lat_s, mig.ORIGIN_LAT)
        self.assertAlmostEqual(lon_s, mig.ORIGIN_LON, places=5)

    def test_known_distances(self):
        # 100 m east at 41.311081 N is 100 / 83738.37 deg of longitude; 100 m south is 100 / 111059.93 deg of latitude.
        # The conversion uses a true tangent plane, the reference below is a flat per-degree length, so they
        # differ by curvature (~7 mm over 100 m). The delta 5e-7 deg (~4 cm) allows that and nothing more.
        lon, _ = mig.legacy_units_to_wgs84(3300.0, 3200.0)
        _, lat = mig.legacy_units_to_wgs84(3200.0, 3300.0)
        self.assertAlmostEqual(lon - mig.ORIGIN_LON, 100.0 / 83738.367, delta=5e-7)
        self.assertAlmostEqual(mig.ORIGIN_LAT - lat, 100.0 / 111059.926, delta=5e-7)

    def test_matches_values_computed_independently_by_the_dart_unit_tests(self):
        # Same constants as test/geo_coordinate_system_test.dart: 0.001 deg lon ~ 83.74 m, 0.001 deg lat ~ 111.07 m.
        e, n, _ = mig.wgs84_to_enu(mig.ORIGIN_LON + 0.001, mig.ORIGIN_LAT, mig.ORIGIN_ALT)
        self.assertAlmostEqual(e, 83.74, delta=0.2)
        self.assertLess(abs(n), 0.01)
        e, n, _ = mig.wgs84_to_enu(mig.ORIGIN_LON, mig.ORIGIN_LAT + 0.001, mig.ORIGIN_ALT)
        self.assertAlmostEqual(n, 111.07, delta=0.2)

    def test_round_trip(self):
        for east, north in [(0, 0), (1500, -2500), (-3200, 3200), (3200, -3200)]:
            lon, lat, alt = mig.enu_to_wgs84(east, north, 0.0)
            e, n, u = mig.wgs84_to_enu(lon, lat, alt)
            self.assertAlmostEqual(e, east, places=5)
            self.assertAlmostEqual(n, north, places=5)
            self.assertAlmostEqual(u, 0.0, places=5)

    def test_whole_legacy_world_stays_inside_the_tashkent_bbox(self):
        bbox = mig._DEFAULT_BASE["bbox"]
        for x in (0.0, 6400.0):
            for y in (0.0, 6400.0):
                lon, lat = mig.legacy_units_to_wgs84(x, y)
                self.assertTrue(bbox["minLon"] <= lon <= bbox["maxLon"] and bbox["minLat"] <= lat <= bbox["maxLat"], (x, y))


class MigrationTests(Fixture):
    def test_small_dataset_counts_files_and_digests(self):
        bad = [[9, 0, 0, [1, 2, 3, 4]], "junk", [1, 0, 0, [1, 2, 3]]]
        src = self.write_source([GOOD_A, bad[0], GOOD_B, bad[1], GOOD_C, bad[2]])
        m = mig.migrate(src, self.out, source_rel="roads.json")
        self.assertEqual(m["sourceRoadCount"], 6)
        self.assertEqual(m["convertedRoadCount"], 3)
        self.assertEqual(m["rejectedRoadCount"], 3)
        self.assertEqual(m["rejectedByReason"], {"bad_cls": 1, "not_a_list": 1, "odd_coordinate_count": 1})
        self.assertEqual(m["pointCount"], 2 + 3 + 2)
        self.assertEqual([e["sourceIndex"] for e in m["rejectedExamples"]], [1, 3, 5])
        total = 0
        for f in m["files"]:
            data = (self.out / f["path"]).read_bytes()
            self.assertEqual(len(data), f["bytes"])
            self.assertEqual(sha(data), f["sha256"])
            total += f["featureCount"]
        self.assertEqual(total, 3)
        self.assertEqual(m["packageSha256"], mig.package_digest(m["files"]))
        on_disk = json.loads((self.out / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(on_disk["packageSha256"], m["packageSha256"])
        self.assertEqual(m["source"]["sha256"], sha(src.read_bytes()))
        self.assertEqual(m["coordinateVerification"]["status"], "verified_approximate")

    def test_package_digest_formula_is_the_documented_one(self):
        files = [
            {"path": "chunks/b.json", "bytes": 2, "sha256": "bb"},
            {"path": "chunks/a.json", "bytes": 1, "sha256": "aa"},
        ]
        expected = sha(b"chunks/a.json\t1\taa\nchunks/b.json\t2\tbb\n")
        self.assertEqual(mig.package_digest(files), expected)

    def test_chunk_content_features_and_coordinates(self):
        m = mig.migrate(self.write_source([GOOD_A]), self.out, source_rel="roads.json")
        self.assertEqual(len(m["files"]), 1)
        chunk = json.loads((self.out / m["files"][0]["path"]).read_text(encoding="utf-8"))
        self.assertEqual(chunk["coordinateOrder"], "lon,lat")
        feat = chunk["features"][0]
        self.assertEqual(feat["cls"], 4)
        self.assertEqual(feat["layer"], 0)
        self.assertFalse(feat["oneWay"])
        self.assertEqual(feat["sourceIndex"], 0)
        self.assertRegex(feat["id"], r"^legacy-00000-[0-9a-f]{8}$")
        lon0, lat0 = feat["coordinates"][0]
        self.assertAlmostEqual(lon0, mig.ORIGIN_LON, places=6)
        self.assertAlmostEqual(lat0, mig.ORIGIN_LAT, places=6)
        self.assertGreater(feat["coordinates"][1][0], lon0)  # second point is 100 m east

    def test_chunk_assignment_uses_midpoint_and_2000m_cells(self):
        self.assertEqual(mig.chunk_key([(3200.0, 3200.0), (3300.0, 3200.0)]), (0, 0))      # midpoint vertex = 2nd point, east 100 m
        self.assertEqual(mig.chunk_key([(5200.0, 3200.0), (5200.0, 3200.0)]), (1, 0))      # east 2000 m -> next cell
        self.assertEqual(mig.chunk_key([(4199.0, 3200.0), (4199.0, 3200.0)]), (0, 0))      # east 999 m
        self.assertEqual(mig.chunk_key([(3200.0, 5300.0), (3200.0, 5300.0)]), (0, -2))     # 2100 m south -> north -2100 -> -2
        self.assertEqual(mig.chunk_key([(3200.0, 1000.0), (3200.0, 1000.0)]), (0, 1))      # 2200 m north -> 1

    def test_idempotent_byte_identical_output(self):
        src = self.write_source([GOOD_A, GOOD_B, GOOD_C, "junk"])
        mig.migrate(src, self.out, source_rel="roads.json")
        first = self.tree_digest(self.out)
        mig.migrate(src, self.out, source_rel="roads.json")
        self.assertEqual(first, self.tree_digest(self.out))

    def test_source_file_is_unchanged(self):
        src = self.write_source([GOOD_A, GOOD_B])
        before = src.read_bytes()
        mig.migrate(src, self.out, source_rel="roads.json")
        self.assertEqual(before, src.read_bytes())

    def test_stale_chunk_files_are_removed_and_manifest_extras_preserved(self):
        src = self.write_source([GOOD_A])
        (self.out / "chunks").mkdir(parents=True)
        (self.out / "chunks" / "chunk_9_9.json").write_text("{}", encoding="utf-8")
        mig.migrate(src, self.out, source_rel="roads.json")
        self.assertFalse((self.out / "chunks" / "chunk_9_9.json").exists())
        # a second run reads the previous manifest as template and must not drift
        first = self.tree_digest(self.out)
        mig.migrate(src, self.out, source_rel="roads.json")
        self.assertEqual(first, self.tree_digest(self.out))

    def test_failures_use_distinct_exit_codes(self):
        with self.assertRaises(mig.MigrationError) as ctx:
            mig.migrate(self.tmp / "missing.json", self.out)
        self.assertEqual(ctx.exception.code, 2)
        for bad_root in ({"v": 2, "roads": []}, {"roads": []}, [], {"v": 1, "roads": "x"}):
            with self.assertRaises(mig.MigrationError, msg=str(bad_root)) as ctx:
                mig.migrate(self.write_source(None, root=bad_root), self.out)
            self.assertEqual(ctx.exception.code, 2)
        broken = self.tmp / "broken.json"
        broken.write_text("{not json", encoding="utf-8")
        with self.assertRaises(mig.MigrationError) as ctx:
            mig.migrate(broken, self.out)
        self.assertEqual(ctx.exception.code, 2)
        with self.assertRaises(mig.MigrationError) as ctx:
            mig.migrate(self.write_source([]), self.out)
        self.assertEqual(ctx.exception.code, 3)
        with self.assertRaises(mig.MigrationError) as ctx:
            mig.migrate(self.write_source(["junk", [1, 2]]), self.out)
        self.assertEqual(ctx.exception.code, 3)
        self.assertFalse((self.out / "manifest.json").exists())

    def test_main_returns_exit_codes(self):
        self.assertEqual(mig.main(["--source", str(self.tmp / "nope.json"), "--out", str(self.out)]), 2)
        self.assertEqual(mig.main(["--source", str(self.write_source([])), "--out", str(self.out)]), 3)
        self.assertEqual(mig.main(["--source", str(self.write_source([GOOD_A])), "--out", str(self.out)]), 0)

    def test_validation_detects_tampering(self):
        m = mig.migrate(self.write_source([GOOD_A, GOOD_C]), self.out, source_rel="roads.json")
        self.assertEqual(mig.validate_package(self.out, m, 2), [])
        victim = self.out / m["files"][0]["path"]
        victim.write_bytes(victim.read_bytes() + b" ")
        problems = mig.validate_package(self.out, m, 2)
        self.assertTrue(any("size mismatch" in p for p in problems))
        self.assertTrue(any("sha256 mismatch" in p for p in problems))
        victim.unlink()
        self.assertTrue(any("missing file" in p for p in mig.validate_package(self.out, m, 2)))
        self.assertTrue(any("source road count" in p for p in mig.validate_package(self.out, m, 5)))


class RealDataTests(Fixture):
    @classmethod
    def setUpClass(cls):
        cls.source_before = REAL_SOURCE.read_bytes()

    def test_real_dataset_is_fully_accounted_for(self):
        raw = json.loads(self.source_before.decode("utf-8"))
        n = len(raw["roads"])
        self.assertEqual(n, 2495)
        m = mig.migrate(REAL_SOURCE, self.out)
        self.assertEqual(m["sourceRoadCount"], n)
        self.assertEqual(m["convertedRoadCount"] + m["rejectedRoadCount"], n)
        self.assertEqual(m["rejectedRoadCount"], 0)
        self.assertEqual(m["convertedRoadCount"], 2495)
        self.assertEqual(m["pointCount"], sum(len(r[3]) // 2 for r in raw["roads"]))
        self.assertTrue(m["coordinateVerification"]["checks"]["allConvertedPointsWithinRegionBbox"])
        self.assertEqual(mig.validate_package(self.out, m, n), [])
        self.assertEqual(self.source_before, REAL_SOURCE.read_bytes())

    def test_real_migration_is_deterministic(self):
        mig.migrate(REAL_SOURCE, self.out)
        first = self.tree_digest(self.out)
        mig.migrate(REAL_SOURCE, self.out)
        self.assertEqual(first, self.tree_digest(self.out))

    def test_committed_package_is_up_to_date(self):
        """Guards against editing the source without re-running the migration."""
        mig.migrate(REAL_SOURCE, self.out)
        fresh = self.tree_digest(self.out)
        committed = self.tree_digest(COMMITTED)
        committed = {k: v for k, v in committed.items() if k == "manifest.json" or k.startswith("chunks/")}
        self.assertEqual(fresh, committed)

    def test_all_chunk_ids_are_unique_across_the_package(self):
        mig.migrate(REAL_SOURCE, self.out)
        ids = []
        for p in sorted((self.out / "chunks").glob("chunk_*.json")):
            ids += [f["id"] for f in json.loads(p.read_text(encoding="utf-8"))["features"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(ids), 2495)


if __name__ == "__main__":
    unittest.main()
