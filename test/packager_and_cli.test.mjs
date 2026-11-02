import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { runCli } from "../tools/uzbekistan_pack_cli.mjs";

test("14 Uzbekistan regions have unique ISO codes and valid latitude/longitude", () => {
  const catalog = JSON.parse(fs.readFileSync("assets/world/uzbekistan/region_catalog.json", "utf8"));
  assert.equal(catalog.regions.length, 14);
  const codes = new Set(catalog.regions.map((r) => r.isoCode));
  assert.equal(codes.size, 14);
  assert.ok(codes.has("UZ-TK"));
  assert.ok(codes.has("UZ-TO"));
  for (const r of catalog.regions) {
    assert.ok(r.latitude >= 37.1 && r.latitude <= 45.6);
    assert.ok(r.longitude >= 55.9 && r.longitude <= 73.2);
  }
});

test("CLI validates regions and package manifest checksum", () => {
  assert.equal(runCli(["validate-regions"]), 0);
  assert.equal(runCli(["validate-package", "assets/world/uzbekistan/regions/tashkent_city/manifest.json"]), 0);
});

test("FILE_MANIFEST.json inventories exactly 23 files (20 expansion + 3 base)", () => {
  const manifest = JSON.parse(fs.readFileSync("FILE_MANIFEST.json", "utf8"));
  assert.equal(manifest.totalFileCount, 23);
  assert.equal(manifest.expansionFileCount, 20);
  assert.equal(manifest.baseFileCount, 3);
  assert.equal(manifest.files.length, 23);
});
