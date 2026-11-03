#!/usr/bin/env node
/**
 * trafficity-uz - validation CLI for the Uzbekistan expansion.
 *
 *   list-regions
 *   validate-regions
 *   validate-package <manifest-path>      path is resolved against the repository root unless absolute
 *   validate-bundle [--mode expansion|full]
 *   build-zip --mode expansion|full --out <file>
 *   update-manifest                        recompute size/SHA-256 of every file listed in FILE_MANIFEST.json
 *
 * Exit codes: 0 success | 1 validation failure | 2 usage error. Success is printed only after all checks passed.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  BUNDLE_MODES,
  MANIFEST_SELF_PATH,
  PackagerError,
  buildVerifiedBundleZip,
  isSafeRelativePath,
  packageDigest,
  selectBundle,
  sha256Hex,
  validateFileManifest,
  verifyBundle,
} from "./packager_core.mjs";

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORLD_DIR = "assets/world/uzbekistan";
const ENVELOPE_LABEL = "approximate_bounding_box_envelope";
const NATIONAL_BBOX = { minLon: 55.997, minLat: 37.172, maxLon: 73.132, maxLat: 45.59 };
const READINESS = new Set(["INSTALLED_DETAILED", "OVERVIEW_ONLY", "AVAILABLE_FOR_DOWNLOAD", "UPDATE_AVAILABLE"]);

class Problems {
  constructor() {
    this.list = [];
  }
  add(msg) {
    this.list.push(msg);
  }
  get ok() {
    return this.list.length === 0;
  }
}

const readJson = (root, rel) => JSON.parse(fs.readFileSync(path.join(root, rel), "utf8"));
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

/** Validates the 14-region catalog, the GeoJSON envelopes, the world manifest and the assets pubspec refers to. */
export function checkRegions(root = REPO_ROOT) {
  const p = new Problems();
  let catalog;
  try {
    catalog = readJson(root, `${WORLD_DIR}/region_catalog.json`);
  } catch (e) {
    p.add(`region_catalog.json unreadable: ${e.message}`);
    return p;
  }
  const regions = catalog.regions;
  if (!Array.isArray(regions) || regions.length !== 14) {
    p.add(`expected exactly 14 regions, found ${Array.isArray(regions) ? regions.length : "none"}`);
    return p;
  }
  const uniq = (key) => new Set(regions.map((r) => r[key])).size === regions.length || p.add(`${key} values are not unique`);
  ["regionId", "isoCode", "soatoCode"].forEach(uniq);
  const byIso = new Map(regions.map((r) => [r.isoCode, r]));
  if (!byIso.has("UZ-TK") || !byIso.has("UZ-TO")) p.add("UZ-TK (Tashkent City) and UZ-TO (Tashkent Region) must both exist");
  else if (byIso.get("UZ-TK").regionId === byIso.get("UZ-TO").regionId) p.add("Tashkent City and Tashkent Region must be separate regions");
  for (const r of regions) {
    const id = r.regionId ?? "<no id>";
    for (const k of ["regionId", "isoCode", "soatoCode", "adminType", "adminCenter", "architectureProfileId", "defaultReadiness"]) {
      if (typeof r[k] !== "string" || r[k] === "") p.add(`${id}: missing ${k}`);
    }
    for (const lang of ["uz", "ru", "en"]) if (!r.names || typeof r.names[lang] !== "string" || r.names[lang] === "") p.add(`${id}: missing names.${lang}`);
    if (!/^UZ-[A-Z]{2}$/.test(r.isoCode ?? "")) p.add(`${id}: invalid isoCode ${r.isoCode}`);
    if (!READINESS.has(r.defaultReadiness)) p.add(`${id}: invalid defaultReadiness ${r.defaultReadiness}`);
    const b = r.bbox;
    if (![b?.minLon, b?.minLat, b?.maxLon, b?.maxLat].every(isNum) || b.minLon >= b.maxLon || b.minLat >= b.maxLat) p.add(`${id}: invalid bbox`);
    if (!isNum(r.latitude) || r.latitude < NATIONAL_BBOX.minLat || r.latitude > NATIONAL_BBOX.maxLat) p.add(`${id}: latitude out of range`);
    if (!isNum(r.longitude) || r.longitude < NATIONAL_BBOX.minLon || r.longitude > NATIONAL_BBOX.maxLon) p.add(`${id}: longitude out of range`);
    const rp = r.representativePoint;
    if (!Array.isArray(rp) || rp.length !== 2 || rp[0] !== r.longitude || rp[1] !== r.latitude) p.add(`${id}: representativePoint must be [longitude, latitude] matching longitude/latitude`);
    if ("centroid" in r) p.add(`${id}: the old "centroid" key must not be used (the value is not a computed centroid)`);
    if (b && isNum(r.latitude) && (r.longitude < b.minLon || r.longitude > b.maxLon || r.latitude < b.minLat || r.latitude > b.maxLat)) p.add(`${id}: administrative center lies outside its bbox`);
    const detailed = r.defaultReadiness === "INSTALLED_DETAILED";
    if (detailed !== (r.regionId === "uz_tashkent_city")) p.add(`${id}: only uz_tashkent_city may be INSTALLED_DETAILED`);
  }
  const prov = catalog.provenance;
  if (!prov?.isoCodes?.source || !prov.isoCodes.verifiedOn) p.add("catalog provenance.isoCodes needs a source and verifiedOn");
  if (prov?.soatoCodes?.status === "verified" && !prov.soatoCodes.source) p.add("SOATO codes marked verified without a source");

  try {
    const geo = readJson(root, `${WORLD_DIR}/administrative_boundaries.geojson`);
    if (geo.type !== "FeatureCollection" || !Array.isArray(geo.features)) p.add("GeoJSON must be a FeatureCollection");
    else {
      if (geo.features.length !== 14) p.add(`GeoJSON has ${geo.features.length} features, expected 14`);
      if (geo.geometryAccuracy !== ENVELOPE_LABEL) p.add(`GeoJSON geometryAccuracy must be "${ENVELOPE_LABEL}"`);
      const ids = new Map(regions.map((r) => [r.regionId, r]));
      const seen = new Set();
      for (const f of geo.features) {
        const rid = f.properties?.regionId;
        const r = ids.get(rid);
        if (!r) {
          p.add(`GeoJSON feature ${rid} has no catalog record`);
          continue;
        }
        if (seen.has(rid)) p.add(`GeoJSON feature ${rid} appears twice`);
        seen.add(rid);
        if (f.properties.geometryAccuracy !== ENVELOPE_LABEL) p.add(`${rid}: feature geometryAccuracy must be "${ENVELOPE_LABEL}"`);
        const ring = f.geometry?.type === "Polygon" ? f.geometry.coordinates?.[0] : null;
        if (!ring || ring.length !== 5 || JSON.stringify(ring[0]) !== JSON.stringify(ring[4])) p.add(`${rid}: geometry must be one closed 5-point rectangle`);
        else if (ring.some((c) => !Array.isArray(c) || !isNum(c[0]) || !isNum(c[1]))) p.add(`${rid}: non-numeric coordinates`);
        else {
          const lons = ring.map((c) => c[0]);
          const lats = ring.map((c) => c[1]);
          const same = Math.min(...lons) === r.bbox.minLon && Math.max(...lons) === r.bbox.maxLon && Math.min(...lats) === r.bbox.minLat && Math.max(...lats) === r.bbox.maxLat;
          if (!same) p.add(`${rid}: GeoJSON rectangle differs from the catalog bbox`);
        }
      }
      if (seen.size !== 14) p.add("every region needs exactly one GeoJSON feature");
    }
  } catch (e) {
    p.add(`administrative_boundaries.geojson unreadable: ${e.message}`);
  }

  try {
    const wm = readJson(root, `${WORLD_DIR}/world_manifest.json`);
    for (const k of ["catalogRef", "boundariesRef", "citiesIndexRef"]) {
      if (!wm[k] || !isSafeRelativePath(wm[k]) || !fs.existsSync(path.join(root, wm[k]))) p.add(`world_manifest ${k} does not point to an existing file`);
    }
    if (wm.firstLevelAdminCount !== 14) p.add("world_manifest firstLevelAdminCount must be 14");
  } catch (e) {
    p.add(`world_manifest.json unreadable: ${e.message}`);
  }

  try {
    const pub = fs.readFileSync(path.join(root, "pubspec.yaml"), "utf8");
    for (const m of pub.matchAll(/^\s+-\s+(assets\/\S+)\s*$/gm)) {
      const target = path.join(root, m[1]);
      if (!fs.existsSync(target)) p.add(`pubspec asset does not exist: ${m[1]}`);
      else if (m[1].endsWith(".json") || m[1].endsWith(".geojson")) {
        try {
          JSON.parse(fs.readFileSync(target, "utf8"));
        } catch (e) {
          p.add(`pubspec asset is not valid JSON: ${m[1]}`);
        }
      }
    }
  } catch (e) {
    p.add(`pubspec.yaml unreadable: ${e.message}`);
  }
  return p;
}

/** Validates a region package manifest and every file it lists (existence, size, recomputed SHA-256, counts). */
export async function checkPackage(manifestPath, root = REPO_ROOT) {
  const p = new Problems();
  const abs = path.resolve(root, manifestPath);
  if (!fs.existsSync(abs)) {
    p.add(`manifest not found: ${manifestPath}`);
    return { problems: p };
  }
  let m;
  try {
    m = JSON.parse(fs.readFileSync(abs, "utf8"));
  } catch (e) {
    p.add(`manifest is not valid JSON: ${e.message}`);
    return { problems: p };
  }
  for (const k of ["schemaVersion", "packageId", "regionId", "version", "packageSha256"]) if (typeof m[k] !== "string" || m[k] === "") p.add(`manifest field ${k} missing`);
  if (!/^\d+\.\d+\.\d+$/.test(m.version ?? "")) p.add(`version "${m.version}" must look like 1.2.3`);
  if (!Array.isArray(m.files) || m.files.length === 0) {
    p.add("manifest files must be a non-empty list");
    return { problems: p, manifest: m };
  }
  const dir = path.dirname(abs);
  let features = 0;
  const seen = new Set();
  for (const f of m.files) {
    if (!isSafeRelativePath(f.path) || f.path === "manifest.json") {
      p.add(`unsafe or invalid file path: ${f.path}`);
      continue;
    }
    if (seen.has(f.path)) p.add(`duplicate path ${f.path}`);
    seen.add(f.path);
    const file = path.resolve(dir, f.path);
    if (!file.startsWith(dir + path.sep)) {
      p.add(`path escapes the package directory: ${f.path}`);
      continue;
    }
    if (!fs.existsSync(file)) {
      p.add(`missing file: ${f.path}`);
      continue;
    }
    const bytes = new Uint8Array(fs.readFileSync(file));
    if (bytes.length !== f.bytes) p.add(`size mismatch for ${f.path}: ${bytes.length} != ${f.bytes}`);
    if ((await sha256Hex(bytes)) !== f.sha256) p.add(`SHA-256 mismatch for ${f.path}`);
    if (f.path.endsWith(".json")) {
      try {
        const chunk = JSON.parse(Buffer.from(bytes).toString("utf8"));
        if (Array.isArray(chunk.features)) {
          features += chunk.features.length;
          if (chunk.features.length !== f.featureCount) p.add(`featureCount mismatch for ${f.path}`);
        }
      } catch (e) {
        p.add(`${f.path} is not valid JSON`);
      }
    }
  }
  if ((await packageDigest(m.files)) !== m.packageSha256) p.add("packageSha256 does not match the file list");
  if (m.convertedRoadCount !== undefined && features !== m.convertedRoadCount) p.add(`chunks hold ${features} features but convertedRoadCount is ${m.convertedRoadCount}`);
  if (m.sourceRoadCount !== undefined && m.convertedRoadCount + m.rejectedRoadCount !== m.sourceRoadCount) p.add("converted + rejected != sourceRoadCount");
  const chunkDir = path.join(dir, "chunks");
  if (fs.existsSync(chunkDir)) {
    for (const name of fs.readdirSync(chunkDir)) if (name.endsWith(".json") && !seen.has(`chunks/${name}`)) p.add(`unlisted chunk file on disk: chunks/${name}`);
  }
  return { problems: p, manifest: m };
}

const readBytesFrom = (root) => async (rel) => {
  const file = path.resolve(root, rel);
  if (!isSafeRelativePath(rel) || !file.startsWith(root + path.sep) || !fs.existsSync(file)) return null;
  return new Uint8Array(fs.readFileSync(file));
};

export async function checkBundle(mode, root = REPO_ROOT) {
  const manifest = validateFileManifest(readJson(root, MANIFEST_SELF_PATH));
  const entries = selectBundle(manifest, mode);
  return { entries, result: await verifyBundle(entries, readBytesFrom(root)), manifest };
}

function parseFlags(args) {
  const flags = {};
  const rest = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--")) {
      flags[args[i].slice(2)] = args[i + 1];
      i++;
    } else rest.push(args[i]);
  }
  return { flags, rest };
}

/** Runs one command and returns its exit code. Never throws for expected failures. */
export async function runCli(argv = process.argv.slice(2), { root = REPO_ROOT, log = console.log, err = console.error } = {}) {
  const [cmd, ...args] = argv;
  const usage = () => {
    err("Usage: trafficity-uz <list-regions | validate-regions | validate-package <manifest> | validate-bundle [--mode expansion|full] | build-zip --mode expansion|full --out <file> | update-manifest>");
    return 2;
  };
  try {
    if (cmd === "list-regions") {
      const catalog = readJson(root, `${WORLD_DIR}/region_catalog.json`);
      for (const r of catalog.regions) log(`${r.isoCode} | ${r.regionId} | lat=${r.latitude}, lon=${r.longitude} | ${r.defaultReadiness}`);
      return 0;
    }
    if (cmd === "validate-regions") {
      const p = checkRegions(root);
      if (!p.ok) {
        p.list.forEach((m) => err(`FAIL: ${m}`));
        return 1;
      }
      log("OK: 14 first-level regions, GeoJSON envelopes (approximate, not borders) and referenced assets are consistent.");
      return 0;
    }
    if (cmd === "validate-package") {
      if (!args[0]) return usage();
      const { problems, manifest } = await checkPackage(args[0], root);
      if (!problems.ok) {
        problems.list.forEach((m) => err(`FAIL: ${m}`));
        return 1;
      }
      log(`VALID PACKAGE: ${manifest.packageId} v${manifest.version} (${manifest.files.length} files, SHA-256 recomputed from file bytes, packageSha256=${manifest.packageSha256})`);
      return 0;
    }
    if (cmd === "validate-bundle") {
      const { flags } = parseFlags(args);
      const modes = flags.mode ? [flags.mode] : Object.keys(BUNDLE_MODES);
      let code = 0;
      for (const mode of modes) {
        const { entries, result } = await checkBundle(mode, root);
        if (!result.ok) {
          result.problems.forEach((x) => err(`FAIL [${mode}] ${x.path}: ${x.code} (${x.detail})`));
          code = 1;
        } else log(`OK [${mode}]: ${entries.length} files verified against FILE_MANIFEST.json (${MANIFEST_SELF_PATH} is exempt: self-reference).`);
      }
      return code;
    }
    if (cmd === "update-manifest") {
      // Recomputes sizeBytes and sha256 of every listed file from the real bytes. FILE_MANIFEST.json itself is exempt.
      const manifest = validateFileManifest(readJson(root, MANIFEST_SELF_PATH));
      const read = readBytesFrom(root);
      for (const f of manifest.files) {
        if (f.path === MANIFEST_SELF_PATH) continue;
        const bytes = await read(f.path);
        if (!bytes) throw new PackagerError("missing", `listed file does not exist: ${f.path}`);
        f.sizeBytes = bytes.length;
        f.sha256 = await sha256Hex(bytes);
      }
      fs.writeFileSync(path.join(root, MANIFEST_SELF_PATH), JSON.stringify(manifest, null, 2) + "\n");
      log(`OK: updated size and SHA-256 of ${manifest.files.length - 1} files in ${MANIFEST_SELF_PATH}.`);
      return 0;
    }
    if (cmd === "build-zip") {
      const { flags } = parseFlags(args);
      if (!flags.mode || !flags.out) return usage();
      const manifest = validateFileManifest(readJson(root, MANIFEST_SELF_PATH));
      const built = await buildVerifiedBundleZip(manifest, flags.mode, readBytesFrom(root));
      fs.writeFileSync(path.resolve(flags.out), built.zip);
      log(`OK [${flags.mode}]: wrote ${flags.out} (${built.entries.length} files, ${built.size} bytes, sha256=${built.sha256})`);
      return 0;
    }
    return usage();
  } catch (e) {
    if (e instanceof PackagerError) {
      err(`FAIL: ${e.message}`);
      return 1;
    }
    err(`FAIL: ${e.message}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli().then((code) => process.exit(code));
}
