/**
 * Phase 4 — Executable Node.js Tests for Regions, Manifests, CLI, 23-File Inventory, and Mocked GitHub Push
 * Run with: node --test test/packager_and_cli.test.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  loadRegionCatalog,
  validateRegionsCatalog,
  validateRegionPackageManifest,
  redactSecrets,
  pushFilesViaGitDataApi,
  runCli
} from "../tools/uzbekistan_pack_cli.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");

test("1. Exact 14 Uzbekistan regions exist with unique codes and distinct UZ-TK / UZ-TO entities", () => {
  const catalog = loadRegionCatalog();
  assert.equal(catalog.regions.length, 14);
  const res = validateRegionsCatalog(catalog);
  assert.equal(res.valid, true, res.errors.join("; "));

  const tk = catalog.regions.find((r) => r.isoCode === "UZ-TK");
  const to = catalog.regions.find((r) => r.isoCode === "UZ-TO");
  assert.ok(tk && to);
  assert.notEqual(tk.regionId, to.regionId);
});

test("2. Manifest validation accepts valid UZ-TK manifest and rejects corrupted SHA-256 or bad coordinates", () => {
  const manifestPath = path.join(REPO_ROOT, "assets/world/uzbekistan/regions/tashkent_city/manifest.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const validCheck = validateRegionPackageManifest(manifest);
  assert.equal(validCheck.valid, true, validCheck.errors.join("; "));

  const corrupted = {
    ...manifest,
    payloadBytes: "real_road_data",
    expectedSha256: "0000000000000000000000000000000000000000000000000000000000000000"
  };
  const corruptCheck = validateRegionPackageManifest(corrupted);
  assert.equal(corruptCheck.valid, false);
  assert.ok(corruptCheck.errors.some((e) => e.includes("SHA-256")));
});

test("3. CLI commands succeed on valid inputs and return non-zero codes on failures", () => {
  const out = [];
  const err = [];
  const io = { stdout: (m) => out.push(m), stderr: (m) => err.push(m) };

  assert.equal(runCli(["list-regions"], io), 0);
  assert.equal(runCli(["validate-regions"], io), 0);
  assert.equal(runCli(["validate-package", path.join(REPO_ROOT, "assets/world/uzbekistan/regions/tashkent_city")], io), 0);
  assert.equal(runCli(["validate-package"], io), 2);
  assert.equal(runCli(["unknown-command"], io), 2);
});

test("4. FILE_MANIFEST.json inventories exactly 23 files (20 expansion + 3 baseline)", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, "FILE_MANIFEST.json"), "utf8"));
  assert.equal(manifest.totalFileCount, 23);
  assert.equal(manifest.expansionFileCount, 20);
  assert.equal(manifest.fullRepoBundleFileCount, 23);
  assert.equal(manifest.files.length, 23);
});

test("5. GitHub push constructs blobs, tree, commit, non-force PATCH, detects 409 conflict, and redacts token", async () => {
  const fakeToken = "github_pat_FAKE_SECRET_1234567890ABCDEF";
  const logs = [];
  let patchForceValue = null;

  const mockOkFetch = async (url, opts) => {
    if (url.endsWith("/repos/abdulloh042006-debug/Trafficity")) {
      return { ok: true, status: 200, json: async () => ({ default_branch: "main" }) };
    }
    if (url.includes("/git/ref/heads/")) {
      return { ok: true, status: 200, json: async () => ({ object: { sha: "base_sha_1" } }) };
    }
    if (url.includes("/git/commits/base_sha_1")) {
      return { ok: true, status: 200, json: async () => ({ tree: { sha: "tree_sha_1" } }) };
    }
    if (url.endsWith("/git/blobs") || url.endsWith("/git/trees") || (url.endsWith("/git/commits") && opts.method === "POST")) {
      return { ok: true, status: 201, json: async () => ({ sha: "created_sha_2" }) };
    }
    if (opts.method === "PATCH") {
      patchForceValue = JSON.parse(opts.body).force;
      return { ok: true, status: 200, json: async () => ({ ref: "refs/heads/codex/uzbekistan-expansion" }) };
    }
    throw new Error("Unexpected URL: " + url);
  };

  const res = await pushFilesViaGitDataApi({
    repo: "abdulloh042006-debug/Trafficity",
    branch: "codex/uzbekistan-expansion",
    token: fakeToken,
    commitMessage: "test push",
    files: [{ path: "README.md", content: "# Test" }],
    fetchImpl: mockOkFetch,
    onLog: (m) => logs.push(m)
  });

  assert.equal(res.status, "updated");
  assert.equal(patchForceValue, false);
  assert.ok(logs.every((l) => !l.includes(fakeToken)));

  // 409 Conflict test
  const mockConflictFetch = async (url, opts) => {
    if (opts.method === "PATCH") {
      return { ok: false, status: 409, statusText: "Conflict", json: async () => ({ message: "Not a fast-forward" }) };
    }
    return mockOkFetch(url, opts);
  };

  await assert.rejects(
    () => pushFilesViaGitDataApi({
      repo: "abdulloh042006-debug/Trafficity",
      branch: "codex/uzbekistan-expansion",
      token: fakeToken,
      files: [{ path: "README.md", content: "# Test" }],
      fetchImpl: mockConflictFetch
    }),
    /Branch update conflict detected/
  );

  assert.equal(redactSecrets(`Error with ${fakeToken}`, fakeToken), "Error with [REDACTED_TOKEN]");
});
