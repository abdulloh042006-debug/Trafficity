import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  BUNDLE_MODES,
  FORBIDDEN_BRANCHES,
  PackagerError,
  TARGET_BRANCH,
  buildVerifiedBundleZip,
  createZip,
  crc32,
  isSafeRelativePath,
  packageDigest,
  pushToGitHub,
  readZip,
  redactToken,
  selectBundle,
  sha256Hex,
  validateFileManifest,
  verifyBundle,
} from "../tools/packager_core.mjs";
import { REPO_ROOT, checkPackage, checkRegions, runCli } from "../tools/uzbekistan_pack_cli.mjs";

const enc = new TextEncoder();
const quiet = { log: () => {}, err: () => {} };
const capture = () => {
  const out = { log: [], err: [] };
  return { out, io: { log: (m) => out.log.push(m), err: (m) => out.err.push(m) } };
};
const realManifest = () => JSON.parse(fs.readFileSync(path.join(REPO_ROOT, "FILE_MANIFEST.json"), "utf8"));
const tmpDir = (name) => fs.mkdtempSync(path.join(os.tmpdir(), `trafficity_${name}_`));

function copyRepoSubset(dest, rels) {
  for (const rel of rels) {
    const from = path.join(REPO_ROOT, rel);
    const to = path.join(dest, rel);
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.cpSync(from, to, { recursive: true });
  }
}
const REGION_FILES = ["assets/world/uzbekistan", "assets/map/tashkent_roads.json", "pubspec.yaml"];
const PKG = "assets/world/uzbekistan/regions/tashkent_city/manifest.json";

/* ---------------------------------------------------------------- original checks (kept) */

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

test("CLI validates regions and package manifest checksum", async () => {
  assert.equal(await runCli(["validate-regions"], quiet), 0);
  assert.equal(await runCli(["validate-package", PKG], quiet), 0);
});

test("FILE_MANIFEST.json inventories exactly 23 files (20 expansion + 3 base)", () => {
  const manifest = JSON.parse(fs.readFileSync("FILE_MANIFEST.json", "utf8"));
  assert.equal(manifest.totalFileCount, 23);
  assert.equal(manifest.expansionFileCount, 20);
  assert.equal(manifest.baseFileCount, 3);
  assert.equal(manifest.files.length, 23);
});

/* ---------------------------------------------------------------- SHA-256 and paths */

test("SHA-256 known answers", async () => {
  assert.equal(await sha256Hex(enc.encode("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  assert.equal(await sha256Hex(new Uint8Array(0)), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
});

test("package digest uses the documented formula and ignores input order", async () => {
  const a = { path: "chunks/a.json", bytes: 1, sha256: "aa" };
  const b = { path: "chunks/b.json", bytes: 2, sha256: "bb" };
  const expected = await sha256Hex(enc.encode("chunks/a.json\t1\taa\nchunks/b.json\t2\tbb\n"));
  assert.equal(await packageDigest([b, a]), expected);
  assert.equal(await packageDigest([a, b]), expected);
});

test("path safety rejects traversal, absolute, drive and backslash paths", () => {
  for (const bad of ["../x", "a/../../x", "/etc/passwd", "C:/win", "a\\b", "a//b", "./a", "", "a/\u0000b"]) assert.equal(isSafeRelativePath(bad), false, bad);
  for (const ok of ["a.txt", "dir/a.txt", "chunks/chunk_-1_0.json"]) assert.equal(isSafeRelativePath(ok), true, ok);
});

/* ---------------------------------------------------------------- FILE_MANIFEST and bundles */

test("the real FILE_MANIFEST.json is structurally valid and its files match their recorded size and SHA-256", async () => {
  const m = validateFileManifest(realManifest());
  for (const mode of Object.keys(BUNDLE_MODES)) {
    const entries = selectBundle(m, mode);
    const result = await verifyBundle(entries, async (rel) => {
      const f = path.join(REPO_ROOT, rel);
      return fs.existsSync(f) ? new Uint8Array(fs.readFileSync(f)) : null;
    });
    assert.deepEqual(result.problems, [], `${mode} bundle drifted from FILE_MANIFEST.json (run: node tools/uzbekistan_pack_cli.mjs update-manifest)`);
  }
});

test("bundle modes: exactly 20 expansion files, exactly 23 full files, sorted, no extras", () => {
  const m = validateFileManifest(realManifest());
  const exp = selectBundle(m, "expansion");
  const full = selectBundle(m, "full");
  assert.equal(exp.length, 20);
  assert.equal(full.length, 23);
  assert.ok(exp.every((e) => e.scope === "expansion"));
  assert.equal(full.filter((e) => e.scope === "base").length, 3);
  assert.deepEqual(exp.map((e) => e.path), [...exp.map((e) => e.path)].sort());
  assert.ok(exp.some((e) => e.path === "FILE_MANIFEST.json"));
  assert.throws(() => selectBundle(m, "everything"), (e) => e.code === "bad_mode");
});

test("a manifest whose counts disagree with its entries is rejected", () => {
  const bad = realManifest();
  bad.expansionFileCount = 19;
  assert.throws(() => validateFileManifest(bad), (e) => e instanceof PackagerError && /expansionFileCount/.test(e.message));
  const bad2 = realManifest();
  bad2.files.pop();
  assert.throws(() => validateFileManifest(bad2), PackagerError);
});

test("the manifest cannot carry its own digest (self-reference rule), duplicates and unsafe paths are rejected", () => {
  const selfRef = realManifest();
  selfRef.files.find((f) => f.path === "FILE_MANIFEST.json").sha256 = "a".repeat(64);
  assert.throws(() => validateFileManifest(selfRef), /self-reference/);
  const dup = realManifest();
  dup.files[3].path = dup.files[2].path;
  assert.throws(() => validateFileManifest(dup), /duplicate/);
  const unsafe = realManifest();
  unsafe.files[3].path = "../outside.txt";
  assert.throws(() => validateFileManifest(unsafe), /unsafe/);
  const badHash = realManifest();
  badHash.files[1].sha256 = "XYZ";
  assert.throws(() => validateFileManifest(badHash), /sha256/);
});

test("verifyBundle rejects a missing file, a size mismatch and a digest mismatch", async () => {
  const m = validateFileManifest(realManifest());
  const entries = selectBundle(m, "expansion");
  const files = new Map(entries.map((e) => [e.path, new Uint8Array(fs.readFileSync(path.join(REPO_ROOT, e.path)))]));
  const victimMissing = "README.md";
  const victimSize = "package.json";
  const victimHash = "LICENSE";
  const reader = async (rel) => {
    if (rel === victimMissing) return null;
    const b = files.get(rel);
    if (rel === victimSize) return b.slice(0, b.length - 1);
    if (rel === victimHash) {
      const c = b.slice();
      c[0] ^= 0xff;
      return c;
    }
    return b;
  };
  const r = await verifyBundle(entries, reader);
  assert.equal(r.ok, false);
  const byPath = Object.fromEntries(r.problems.map((p) => [p.path, p.code]));
  assert.equal(byPath[victimMissing], "missing");
  assert.equal(byPath[victimSize], "size_mismatch");
  assert.equal(byPath[victimHash], "sha256_mismatch");
  assert.equal(r.problems.length, 3);
});

/* ---------------------------------------------------------------- ZIP */

test("ZIP: deterministic bytes, sorted entries, and the contents survive a round trip", async () => {
  const files = [
    { path: "b/two.txt", bytes: enc.encode("two") },
    { path: "a.txt", bytes: enc.encode("one") },
    { path: "empty.bin", bytes: new Uint8Array(0) },
  ];
  const z1 = createZip(files);
  const z2 = createZip([...files].reverse());
  assert.deepEqual(z1, z2);
  const back = readZip(z1);
  assert.deepEqual(back.map((e) => e.path), ["a.txt", "b/two.txt", "empty.bin"]);
  assert.equal(new TextDecoder().decode(back[1].bytes), "two");
  assert.equal(back[2].bytes.length, 0);
  assert.equal(crc32(enc.encode("123456789")), 0xcbf43926);
});

test("ZIP: Python's zipfile accepts the archive (independent reader)", () => {
  const dir = tmpDir("zip");
  const file = path.join(dir, "t.zip");
  fs.writeFileSync(file, createZip([{ path: "x/y.txt", bytes: enc.encode("hello") }, { path: "z.txt", bytes: enc.encode("world") }]));
  const r = spawnSync("python3", ["-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; print(','.join(z.namelist()), z.read('z.txt').decode())", file], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), "x/y.txt,z.txt world");
});

test("ZIP: unsafe or duplicate paths cannot be written, corrupted or truncated archives are rejected", () => {
  assert.throws(() => createZip([{ path: "../evil.txt", bytes: enc.encode("x") }]), (e) => e.code === "unsafe_path");
  assert.throws(() => createZip([{ path: "/abs.txt", bytes: enc.encode("x") }]), (e) => e.code === "unsafe_path");
  assert.throws(() => createZip([{ path: "a", bytes: enc.encode("1") }, { path: "a", bytes: enc.encode("2") }]), (e) => e.code === "duplicate_path");
  const zip = createZip([{ path: "a.txt", bytes: enc.encode("payload") }]);
  const flipped = zip.slice();
  flipped[30 + 5 + 2] ^= 0xff; // a payload byte
  assert.throws(() => readZip(flipped), /CRC mismatch/);
  assert.throws(() => readZip(zip.slice(0, 20)), PackagerError);
});

test("both bundle modes produce a validated ZIP with exactly 20 / 23 entries from the real repository", async () => {
  const m = validateFileManifest(realManifest());
  const read = async (rel) => new Uint8Array(fs.readFileSync(path.join(REPO_ROOT, rel)));
  for (const [mode, count] of Object.entries(BUNDLE_MODES)) {
    const built = await buildVerifiedBundleZip(m, mode, read);
    assert.equal(built.entries.length, count);
    assert.equal(readZip(built.zip).length, count);
    assert.match(built.sha256, /^[0-9a-f]{64}$/);
    const again = await buildVerifiedBundleZip(m, mode, read);
    assert.equal(again.sha256, built.sha256, `${mode} ZIP must be reproducible`);
  }
});

test("a bundle with a tampered source file is never zipped", async () => {
  const m = validateFileManifest(realManifest());
  const read = async (rel) => {
    const b = new Uint8Array(fs.readFileSync(path.join(REPO_ROOT, rel)));
    if (rel === "LICENSE") b[0] ^= 1;
    return b;
  };
  await assert.rejects(buildVerifiedBundleZip(m, "expansion", read), (e) => e.code === "verification_failed");
});

/* ---------------------------------------------------------------- CLI: regions and packages */

test("validate-regions catches data-quality defects", () => {
  const cases = {
    "13 regions": (c) => c.regions.pop(),
    "Tashkent City/Region merged": (c) => (c.regions.find((r) => r.isoCode === "UZ-TO").regionId = "uz_tashkent_city"),
    "duplicate ISO": (c) => (c.regions[3].isoCode = c.regions[2].isoCode),
    "old centroid key": (c) => (c.regions[2].centroid = c.regions[2].representativePoint),
    "latitude out of range": (c) => (c.regions[4].latitude = 90),
    "overstated readiness": (c) => (c.regions[5].defaultReadiness = "INSTALLED_DETAILED"),
    "wrong coordinate order": (c) => (c.regions[6].representativePoint = [...c.regions[6].representativePoint].reverse()),
    "missing translation": (c) => (c.regions[7].names.ru = ""),
  };
  for (const [name, mutate] of Object.entries(cases)) {
    const root = tmpDir("regions");
    copyRepoSubset(root, REGION_FILES);
    const file = path.join(root, "assets/world/uzbekistan/region_catalog.json");
    const c = JSON.parse(fs.readFileSync(file, "utf8"));
    mutate(c);
    fs.writeFileSync(file, JSON.stringify(c));
    assert.equal(checkRegions(root).ok, false, name);
  }
});

test("validate-regions rejects an overstated GeoJSON label and a rectangle that differs from the catalog", () => {
  const root = tmpDir("geo");
  copyRepoSubset(root, REGION_FILES);
  const file = path.join(root, "assets/world/uzbekistan/administrative_boundaries.geojson");
  const g = JSON.parse(fs.readFileSync(file, "utf8"));
  g.geometryAccuracy = "verified_bounding_box_envelope_only";
  fs.writeFileSync(file, JSON.stringify(g));
  assert.ok(checkRegions(root).list.some((m) => /geometryAccuracy/.test(m)));
  g.geometryAccuracy = "approximate_bounding_box_envelope";
  g.features[0].geometry.coordinates[0][1][0] += 0.5;
  fs.writeFileSync(file, JSON.stringify(g));
  assert.ok(checkRegions(root).list.some((m) => /differs from the catalog bbox/.test(m)));
});

test("the real catalog marks only Tashkent as detailed and labels the envelopes as approximate", () => {
  const p = checkRegions(REPO_ROOT);
  assert.deepEqual(p.list, []);
  const cat = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, "assets/world/uzbekistan/region_catalog.json"), "utf8"));
  assert.deepEqual(cat.regions.filter((r) => r.defaultReadiness === "INSTALLED_DETAILED").map((r) => r.regionId), ["uz_tashkent_city"]);
  assert.equal(cat.provenance.soatoCodes.status, "unverified");
});

test("validate-package rejects tampered, missing, unlisted and traversal files", async () => {
  const mk = () => {
    const root = tmpDir("pkg");
    copyRepoSubset(root, ["assets/world/uzbekistan/regions"]);
    return root;
  };
  let root = mk();
  assert.equal((await checkPackage(PKG, root)).problems.ok, true);

  root = mk();
  const chunk = path.join(root, "assets/world/uzbekistan/regions/tashkent_city/chunks/chunk_0_0.json");
  fs.appendFileSync(chunk, " ");
  const t = await checkPackage(PKG, root);
  assert.ok(t.problems.list.some((m) => /SHA-256 mismatch|size mismatch/.test(m)));

  root = mk();
  fs.rmSync(path.join(root, "assets/world/uzbekistan/regions/tashkent_city/chunks/chunk_1_1.json"));
  assert.ok((await checkPackage(PKG, root)).problems.list.some((m) => /missing file/.test(m)));

  root = mk();
  fs.writeFileSync(path.join(root, "assets/world/uzbekistan/regions/tashkent_city/chunks/chunk_9_9.json"), "{}");
  assert.ok((await checkPackage(PKG, root)).problems.list.some((m) => /unlisted chunk/.test(m)));

  root = mk();
  const mf = path.join(root, PKG);
  const m = JSON.parse(fs.readFileSync(mf, "utf8"));
  m.files[0].path = "../../../../../etc/passwd";
  fs.writeFileSync(mf, JSON.stringify(m));
  assert.ok((await checkPackage(PKG, root)).problems.list.some((x) => /unsafe/.test(x)));

  root = mk();
  const m2 = JSON.parse(fs.readFileSync(path.join(root, PKG), "utf8"));
  m2.packageSha256 = "0".repeat(64);
  fs.writeFileSync(path.join(root, PKG), JSON.stringify(m2));
  assert.ok((await checkPackage(PKG, root)).problems.list.some((x) => /packageSha256/.test(x)));
});

test("CLI exit codes: usage errors are 2, validation failures are 1, success is printed only on 0", async () => {
  assert.equal(await runCli([], quiet), 2);
  assert.equal(await runCli(["nope"], quiet), 2);
  assert.equal(await runCli(["validate-package"], quiet), 2);
  assert.equal(await runCli(["build-zip"], quiet), 2);
  assert.equal(await runCli(["validate-package", "does/not/exist.json"], quiet), 1);
  const root = tmpDir("cli");
  copyRepoSubset(root, REGION_FILES);
  fs.rmSync(path.join(root, "assets/world/uzbekistan/cities_index.json"));
  const { out, io } = capture();
  assert.equal(await runCli(["validate-regions"], { root, ...io }), 1);
  assert.equal(out.log.length, 0, "no OK line may be printed on failure");
  assert.ok(out.err.length > 0);
});

test("the CLI resolves repository paths independent of the caller's working directory", () => {
  const r = spawnSync(process.execPath, [path.join(REPO_ROOT, "tools/uzbekistan_pack_cli.mjs"), "validate-regions"], { cwd: os.tmpdir(), encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^OK:/);
});

test("build-zip writes a ZIP that Python's zipfile validates", async () => {
  const out = path.join(tmpDir("buildzip"), "bundle.zip");
  assert.equal(await runCli(["build-zip", "--mode", "full", "--out", out], quiet), 0);
  const r = spawnSync("python3", ["-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; print(len(z.namelist()))", out], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), "23");
});

/* ---------------------------------------------------------------- GitHub Direct Push (MOCK-ONLY: proves request construction) */

const TOKEN = "github_pat_TESTTOKEN0123456789abcdef";
const OLD = "a".repeat(40);
const NEW = "c".repeat(40);

function mockGitHub({ failAt = null, status = 500, refAfter = NEW, headers = {} } = {}) {
  const calls = [];
  const fetchFn = async (url, init) => {
    const u = new URL(url);
    const key = `${init.method} ${u.pathname.replace("/repos/abdulloh042006-debug/Trafficity", "")}`;
    calls.push({ key, url, init, body: init.body ? JSON.parse(init.body) : null });
    const reply = (obj, st = 200) => ({ ok: st < 300, status: st, headers: { get: (h) => headers[h.toLowerCase()] ?? null }, json: async () => obj });
    if (failAt && key.startsWith(failAt)) return reply({ message: "boom" }, status);
    const refGets = calls.filter((c) => c.key.startsWith("GET /git/ref/heads/")).length;
    if (key.startsWith("GET /git/ref/heads/")) return reply({ object: { sha: refGets === 1 ? OLD : refAfter } });
    if (key === `GET /git/commits/${OLD}`) return reply({ sha: OLD, tree: { sha: "t".repeat(40) } });
    if (key.startsWith("POST /git/blobs")) return reply({ sha: String(calls.length).padStart(40, "b") });
    if (key.startsWith("POST /git/trees")) return reply({ sha: "d".repeat(40) });
    if (key.startsWith("POST /git/commits")) return reply({ sha: NEW });
    if (key.startsWith("PATCH /git/refs/heads/")) return reply({ object: { sha: NEW } });
    if (key === `GET /git/commits/${NEW}`) return reply({ sha: NEW });
    return reply({ message: "unexpected " + key }, 500);
  };
  return { calls, fetchFn };
}
const filesToPush = [
  { path: "README.md", bytes: enc.encode("hello") },
  { path: "lib/a.dart", bytes: enc.encode("void main() {}") },
];
const push = (m, extra = {}) => pushToGitHub({ fetchFn: m.fetchFn, token: TOKEN, files: filesToPush, message: "test", ...extra });

test("push: official Git Database API sequence, normal (non-force) ref update, verified read-back [MOCK-ONLY]", async () => {
  const m = mockGitHub();
  const res = await push(m);
  assert.deepEqual(
    m.calls.map((c) => c.key),
    [
      `GET /git/ref/heads/${TARGET_BRANCH}`,
      `GET /git/commits/${OLD}`,
      "POST /git/blobs",
      "POST /git/blobs",
      "POST /git/trees",
      "POST /git/commits",
      `PATCH /git/refs/heads/${TARGET_BRANCH}`,
      `GET /git/ref/heads/${TARGET_BRANCH}`,
      `GET /git/commits/${NEW}`,
    ],
  );
  const tree = m.calls.find((c) => c.key === "POST /git/trees").body;
  assert.equal(tree.base_tree, "t".repeat(40));
  assert.deepEqual(tree.tree.map((t) => t.path), ["README.md", "lib/a.dart"]);
  assert.ok(tree.tree.every((t) => t.mode === "100644" && t.type === "blob"));
  assert.deepEqual(m.calls.find((c) => c.key === "POST /git/commits").body.parents, [OLD]);
  const patch = m.calls.find((c) => c.key.startsWith("PATCH")).body;
  assert.equal(patch.force, false);
  assert.equal(patch.sha, NEW);
  assert.equal(res.commitSha, NEW);
  assert.equal(res.parentSha, OLD);
  const blob = m.calls.find((c) => c.key === "POST /git/blobs").body;
  assert.equal(blob.encoding, "base64");
  assert.equal(Buffer.from(blob.content, "base64").toString(), "hello");
});

test("push: the token only appears in the Authorization header, never in a URL or body", async () => {
  const m = mockGitHub();
  await push(m);
  for (const c of m.calls) {
    assert.ok(!c.url.includes(TOKEN));
    assert.ok(!(c.init.body ?? "").includes(TOKEN));
    assert.equal(c.init.headers.Authorization, `Bearer ${TOKEN}`);
  }
});

test("push: main (and any other branch) is refused before a single request is sent", async () => {
  for (const branch of [...FORBIDDEN_BRANCHES, "feature/x", "codex/uzbekistan-expansion-2"]) {
    const m = mockGitHub();
    await assert.rejects(push(m, { branch }), (e) => e.code === "branch_locked", branch);
    assert.equal(m.calls.length, 0, `${branch} must not trigger any request`);
  }
});

test("push: a conflict stops immediately, never retries and never forces [MOCK-ONLY]", async () => {
  for (const status of [409, 422]) {
    const m = mockGitHub({ failAt: "PATCH /git/refs", status });
    await assert.rejects(push(m), (e) => e.code === "conflict");
    assert.equal(m.calls.filter((c) => c.key.startsWith("PATCH")).length, 1);
    assert.ok(m.calls.every((c) => !c.body || c.body.force !== true));
    assert.equal(m.calls.at(-1).key.startsWith("PATCH"), true, "nothing may follow the failed update");
  }
});

test("push: HTTP and network failures become safe, human-readable errors", async () => {
  const table = [
    [401, {}, "auth"],
    [403, { "x-ratelimit-remaining": "0" }, "rate_limit"],
    [403, {}, "forbidden"],
    [404, {}, "not_found"],
    [429, {}, "rate_limit"],
    [500, {}, "http_error"],
  ];
  for (const [status, headers, code] of table) {
    const m = mockGitHub({ failAt: "GET /git/ref/heads", status, headers });
    await assert.rejects(push(m), (e) => e.code === code && !e.message.includes(TOKEN), `${status}`);
  }
  const boom = async () => {
    throw new Error(`socket hang up while sending ${TOKEN}`);
  };
  await assert.rejects(pushToGitHub({ fetchFn: boom, token: TOKEN, files: filesToPush, message: "x" }), (e) => e.code === "network" && !e.message.includes(TOKEN) && e.message.includes("[REDACTED]"));
});

test("push: success is not reported when the branch does not point at the new commit after the update", async () => {
  const m = mockGitHub({ refAfter: "f".repeat(40) });
  await assert.rejects(push(m), (e) => e.code === "verify_failed");
});

test("push: invalid input is refused (no token, no files, unsafe path, bad repository)", async () => {
  const m = mockGitHub();
  await assert.rejects(pushToGitHub({ fetchFn: m.fetchFn, token: "", files: filesToPush, message: "x" }), (e) => e.code === "auth");
  await assert.rejects(pushToGitHub({ fetchFn: m.fetchFn, token: TOKEN, files: [], message: "x" }), (e) => e.code === "no_files");
  await assert.rejects(pushToGitHub({ fetchFn: m.fetchFn, token: TOKEN, files: [{ path: "../x", bytes: enc.encode("x") }], message: "x" }), (e) => e.code === "unsafe_path");
  await assert.rejects(pushToGitHub({ fetchFn: m.fetchFn, token: TOKEN, repository: "evil", files: filesToPush, message: "x" }), (e) => e.code === "bad_repository");
  assert.equal(m.calls.length, 0);
});

test("token redaction removes the exact token and GitHub-style token patterns", () => {
  assert.equal(redactToken(`failed with ${TOKEN}`, TOKEN), "failed with [REDACTED]");
  assert.equal(redactToken("ghp_abcdefghijklmnop leaked", null), "[REDACTED] leaked");
  assert.equal(redactToken("nothing secret", TOKEN), "nothing secret");
});

test("source guard: no force update is possible anywhere in the packager code", () => {
  const core = fs.readFileSync(path.join(REPO_ROOT, "tools/packager_core.mjs"), "utf8");
  assert.ok(core.includes("force: false"));
  assert.ok(!/force:\s*true/.test(core));
  assert.ok(!/--force|force-with-lease/.test(core));
});
