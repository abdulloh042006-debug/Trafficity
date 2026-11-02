#!/usr/bin/env node
/**
 * Phase 3 & Phase 6 — Uzbekistan Region Package Manager, CLI & GitHub Git Data API Pusher
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const CATALOG_PATH = path.join(REPO_ROOT, "assets/world/uzbekistan/region_catalog.json");

export const UZ_LAT_RANGE = Object.freeze({ min: 37.1, max: 45.6 });
export const UZ_LON_RANGE = Object.freeze({ min: 55.9, max: 73.2 });

export function computeSha256Hex(bufferOrString) {
  return crypto.createHash("sha256").update(bufferOrString).digest("hex");
}

export function loadRegionCatalog(catalogFile = CATALOG_PATH) {
  return JSON.parse(fs.readFileSync(catalogFile, "utf8"));
}

export function validateRegionsCatalog(catalog = loadRegionCatalog()) {
  const errors = [];
  const regions = catalog?.regions;
  if (!Array.isArray(regions) || regions.length !== 14) {
    errors.push(`Expected exactly 14 regions, found ${Array.isArray(regions) ? regions.length : 0}.`);
    return { valid: false, errors };
  }

  const codes = new Set();
  const ids = new Set();

  for (const r of regions) {
    if (!/^UZ-[A-Z]{2}$/.test(r.isoCode || "")) {
      errors.push(`Invalid isoCode format: ${r.isoCode}`);
    }
    if (codes.has(r.isoCode)) errors.push(`Duplicate isoCode: ${r.isoCode}`);
    codes.add(r.isoCode);

    if (!r.regionId) errors.push(`Missing regionId for ${r.isoCode}`);
    if (ids.has(r.regionId)) errors.push(`Duplicate regionId: ${r.regionId}`);
    ids.add(r.regionId);

    if (typeof r.latitude !== "number" || r.latitude < UZ_LAT_RANGE.min || r.latitude > UZ_LAT_RANGE.max) {
      errors.push(`Invalid latitude for ${r.isoCode}: ${r.latitude}`);
    }
    if (typeof r.longitude !== "number" || r.longitude < UZ_LON_RANGE.min || r.longitude > UZ_LON_RANGE.max) {
      errors.push(`Invalid longitude for ${r.isoCode}: ${r.longitude}`);
    }
    if (!r.bbox || r.bbox.minLat >= r.bbox.maxLat || r.bbox.minLon >= r.bbox.maxLon) {
      errors.push(`Invalid bbox for ${r.isoCode}`);
    }
  }

  if (!codes.has("UZ-TK") || !codes.has("UZ-TO")) {
    errors.push("Both Tashkent City (UZ-TK) and Tashkent Region (UZ-TO) must exist as distinct entities.");
  }

  return { valid: errors.length === 0, errors };
}

export function validateRegionPackageManifest(manifest, catalog = loadRegionCatalog()) {
  const errors = [];
  if (!manifest || typeof manifest !== "object") {
    return { valid: false, errors: ["Manifest must be an object."] };
  }
  if (manifest.schemaVersion !== "3.0.0") {
    errors.push(`Unsupported schemaVersion: ${manifest.schemaVersion}`);
  }
  const region = catalog.regions.find((r) => r.regionId === manifest.regionId && r.isoCode === manifest.isoCode);
  if (!region) {
    errors.push(`Unknown or mismatched regionId/isoCode: ${manifest.regionId} / ${manifest.isoCode}`);
  }
  const anchor = manifest.referenceAnchor;
  if (!anchor || typeof anchor.latitude !== "number" || typeof anchor.longitude !== "number") {
    errors.push("referenceAnchor must include explicit numeric latitude and longitude.");
  } else {
    if (anchor.latitude < UZ_LAT_RANGE.min || anchor.latitude > UZ_LAT_RANGE.max) {
      errors.push(`referenceAnchor.latitude out of range: ${anchor.latitude}`);
    }
    if (anchor.longitude < UZ_LON_RANGE.min || anchor.longitude > UZ_LON_RANGE.max) {
      errors.push(`referenceAnchor.longitude out of range: ${anchor.longitude}`);
    }
  }
  if (!manifest.datasetVersion || !manifest.attribution) {
    errors.push("Manifest must include datasetVersion and ODbL attribution.");
  }
  if (manifest.expectedSha256 && manifest.payloadBytes) {
    const actual = computeSha256Hex(manifest.payloadBytes);
    if (actual !== manifest.expectedSha256.toLowerCase()) {
      errors.push(`SHA-256 checksum mismatch: expected ${manifest.expectedSha256}, got ${actual}`);
    }
  }
  return { valid: errors.length === 0, errors };
}

export function redactSecrets(input, token = "") {
  let out = String(input ?? "");
  if (token && token.trim().length > 0) {
    out = out.split(token.trim()).join("[REDACTED_TOKEN]");
  }
  out = out.replace(/gh[pousr]_[A-Za-z0-9_]{10,}/g, "[REDACTED_TOKEN]");
  out = out.replace(/github_pat_[A-Za-z0-9_]{10,}/g, "[REDACTED_TOKEN]");
  out = out.replace(/Bearer\s+[A-Za-z0-9_\-\.]+/gi, "Bearer [REDACTED_TOKEN]");
  return out;
}

export async function pushFilesViaGitDataApi({
  repo,
  branch,
  token,
  commitMessage,
  files,
  fetchImpl = globalThis.fetch,
  onLog = () => {}
}) {
  if (!repo || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo.trim())) {
    throw new Error("Invalid repository format (expected owner/repo).");
  }
  if (!branch || !/^[A-Za-z0-9_./-]+$/.test(branch.trim()) || branch.includes("..")) {
    throw new Error("Invalid branch name.");
  }
  if (!token || token.trim().length < 10) {
    throw new Error("Valid GitHub token is required.");
  }
  if (!Array.isArray(files) || files.length === 0) {
    throw new Error("No files provided to push.");
  }

  const cleanRepo = repo.trim();
  const cleanBranch = branch.trim();
  const cleanToken = token.trim();

  const ghFetch = async (method, endpoint, bodyObj = null) => {
    const headers = {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${cleanToken}`,
      "X-GitHub-Api-Version": "2022-11-28"
    };
    if (bodyObj !== null) headers["Content-Type"] = "application/json";

    let res;
    try {
      res = await fetchImpl(`https://api.github.com${endpoint}`, {
        method,
        headers,
        body: bodyObj !== null ? JSON.stringify(bodyObj) : undefined
      });
    } catch (netErr) {
      throw new Error(redactSecrets(`Network error on ${endpoint}: ${netErr.message}`, cleanToken));
    }

    let data = null;
    try { data = await res.json(); } catch (_) {}

    if (!res.ok) {
      const msg = data?.message || res.statusText;
      const err = new Error(redactSecrets(`GitHub API ${res.status} on ${method} ${endpoint}: ${msg}`, cleanToken));
      err.status = res.status;
      throw err;
    }
    return data;
  };

  onLog(redactSecrets(`Checking repository ${cleanRepo}...`, cleanToken));
  const repoInfo = await ghFetch("GET", `/repos/${cleanRepo}`);
  const defaultBranch = repoInfo.default_branch || "main";

  let baseCommitSha;
  let branchExists = true;
  try {
    const refData = await ghFetch("GET", `/repos/${cleanRepo}/git/ref/heads/${cleanBranch}`);
    baseCommitSha = refData.object.sha;
  } catch (err) {
    if (err.status === 404) {
      branchExists = false;
      const defRef = await ghFetch("GET", `/repos/${cleanRepo}/git/ref/heads/${defaultBranch}`);
      baseCommitSha = defRef.object.sha;
    } else {
      throw err;
    }
  }

  const baseCommit = await ghFetch("GET", `/repos/${cleanRepo}/git/commits/${baseCommitSha}`);
  const baseTreeSha = baseCommit.tree.sha;

  const treeEntries = [];
  for (const f of files) {
    const blob = await ghFetch("POST", `/repos/${cleanRepo}/git/blobs`, {
      content: String(f.content),
      encoding: "utf-8"
    });
    treeEntries.push({
      path: f.path,
      mode: f.path.endsWith(".py") || f.path.endsWith(".mjs") ? "100755" : "100644",
      type: "blob",
      sha: blob.sha
    });
  }

  const newTree = await ghFetch("POST", `/repos/${cleanRepo}/git/trees`, {
    base_tree: baseTreeSha,
    tree: treeEntries
  });

  const newCommit = await ghFetch("POST", `/repos/${cleanRepo}/git/commits`, {
    message: commitMessage || "feat(uzbekistan): update Uzbekistan region packager files",
    tree: newTree.sha,
    parents: [baseCommitSha]
  });

  if (branchExists) {
    try {
      const updated = await ghFetch("PATCH", `/repos/${cleanRepo}/git/refs/heads/${cleanBranch}`, {
        sha: newCommit.sha,
        force: false
      });
      return { status: "updated", commitSha: newCommit.sha, ref: updated.ref };
    } catch (err) {
      if (err.status === 409 || err.status === 422) {
        throw new Error(`Branch update conflict detected on '${cleanBranch}' (HTTP ${err.status}). Refusing force-push.`);
      }
      throw err;
    }
  } else {
    const created = await ghFetch("POST", `/repos/${cleanRepo}/git/refs`, {
      ref: `refs/heads/${cleanBranch}`,
      sha: newCommit.sha
    });
    return { status: "created", commitSha: newCommit.sha, ref: created.ref };
  }
}

export function runCli(argv = process.argv.slice(2), io = { stdout: console.log, stderr: console.error }) {
  const [cmd, arg] = argv;
  if (cmd === "list-regions") {
    const catalog = loadRegionCatalog();
    for (const r of catalog.regions) {
      io.stdout(`${r.isoCode} | ${r.regionId} | lat=${r.latitude}, lon=${r.longitude} | ${r.defaultReadiness}`);
    }
    return 0;
  }
  if (cmd === "validate-regions") {
    const res = validateRegionsCatalog();
    if (!res.valid) {
      io.stderr(res.errors.join("; "));
      return 1;
    }
    io.stdout("OK: 14 Uzbekistan regions validated.");
    return 0;
  }
  if (cmd === "list-packages") {
    const catalog = loadRegionCatalog();
    const installed = catalog.regions.filter((r) => r.defaultReadiness === "INSTALLED_DETAILED");
    io.stdout(JSON.stringify(installed.map((r) => r.regionId)));
    return 0;
  }
  if (cmd === "validate-package" || cmd === "install-package") {
    if (!arg) {
      io.stderr(`Missing directory argument for ${cmd}`);
      return 2;
    }
    const manifestPath = path.join(path.resolve(arg), "manifest.json");
    if (!fs.existsSync(manifestPath)) {
      io.stderr(`Missing manifest.json at ${manifestPath}`);
      return 1;
    }
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    const check = validateRegionPackageManifest(manifest);
    if (!check.valid) {
      io.stderr(check.errors.join("; "));
      return 1;
    }
    io.stdout(`${cmd === "install-package" ? "INSTALLED" : "VALID"}: ${manifest.regionId} (${manifest.isoCode})`);
    return 0;
  }
  io.stderr("Usage: trafficity-uz <list-regions|validate-regions|list-packages|validate-package <dir>|install-package <dir>>");
  return 2;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  process.exitCode = runCli();
}
