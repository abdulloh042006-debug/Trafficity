/* CORE:BEGIN
 * packager_core.mjs - pure logic shared by the CLI (tools/uzbekistan_pack_cli.mjs), the browser packager
 * (Trafficity-Uzbekistan-Complete-Packager.html) and the tests.
 *
 * Rules for this file (so it can be pasted verbatim into the HTML page by tools/sync_packager_html.mjs):
 *   - no `import` statements and no Node-only APIs (uses Web Crypto, TextEncoder, btoa);
 *   - the only module syntax is the `export` keyword in front of declarations.
 */

export const REPOSITORY = "abdulloh042006-debug/Trafficity";
export const TARGET_BRANCH = "codex/uzbekistan-expansion";
export const FORBIDDEN_BRANCHES = ["main", "master"];
export const MANIFEST_SELF_PATH = "FILE_MANIFEST.json";
export const BUNDLE_MODES = { expansion: 52, full: 55 };

export class PackagerError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "PackagerError";
    this.code = code;
  }
}

const HEX64 = /^[0-9a-f]{64}$/;
const textEncoder = new TextEncoder();

/* ------------------------------------------------------------------ hashing */

export async function sha256Hex(bytes) {
  const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** SHA-256 of the sorted "<path>\t<bytes>\t<sha256>\n" lines (same formula as the Dart and Python tools). */
export async function packageDigest(files) {
  const lines = [...files]
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
    .map((f) => `${f.path}\t${f.bytes}\t${f.sha256}\n`)
    .join("");
  return sha256Hex(textEncoder.encode(lines));
}

/* ------------------------------------------------------------------ paths */

/** Rejects absolute paths, drive prefixes, NUL, empty / "." / ".." segments, backslashes. */
export function isSafeRelativePath(p) {
  if (typeof p !== "string" || p.length === 0) return false;
  if (p.includes("\\") || p.includes("\u0000") || p.startsWith("/") || /^[A-Za-z]:/.test(p)) return false;
  const trimmed = p.endsWith("/") ? p.slice(0, -1) : p;
  if (trimmed.length === 0) return false;
  return trimmed.split("/").every((seg) => seg !== "" && seg !== "." && seg !== "..");
}

/* ------------------------------------------------------------------ FILE_MANIFEST.json */

/**
 * Validates the structure of FILE_MANIFEST.json and returns it. Throws PackagerError.
 * Self-reference rule: the manifest cannot contain its own digest, so the entry for
 * FILE_MANIFEST.json must NOT carry sizeBytes/sha256 and is exempt from digest checks.
 */
export function validateFileManifest(m) {
  const fail = (msg) => {
    throw new PackagerError("invalid_manifest", msg);
  };
  if (!m || typeof m !== "object" || !Array.isArray(m.files)) fail("FILE_MANIFEST.json must contain a files array");
  const seen = new Set();
  let expansion = 0;
  let base = 0;
  m.files.forEach((f, i) => {
    if (!isSafeRelativePath(f.path)) fail(`unsafe or missing path at entry ${i}: ${f.path}`);
    if (seen.has(f.path)) fail(`duplicate path: ${f.path}`);
    seen.add(f.path);
    if (f.index !== i + 1) fail(`entry ${f.path} has index ${f.index}, expected ${i + 1}`);
    if (f.scope === "expansion") expansion++;
    else if (f.scope === "base") base++;
    else fail(`entry ${f.path} has unknown scope ${f.scope}`);
    if (f.path === MANIFEST_SELF_PATH) {
      if ("sha256" in f || "sizeBytes" in f) fail("FILE_MANIFEST.json must not list its own digest or size (self-reference)");
    } else {
      if (!Number.isInteger(f.sizeBytes) || f.sizeBytes < 0) fail(`entry ${f.path} needs an integer sizeBytes`);
      if (!HEX64.test(f.sha256 ?? "")) fail(`entry ${f.path} needs a 64-character lowercase sha256`);
    }
  });
  if (m.totalFileCount !== m.files.length) fail(`totalFileCount ${m.totalFileCount} != ${m.files.length} listed files`);
  if (m.expansionFileCount !== expansion) fail(`expansionFileCount ${m.expansionFileCount} != ${expansion} expansion entries`);
  if (m.baseFileCount !== base) fail(`baseFileCount ${m.baseFileCount} != ${base} base entries`);
  if (m.fullRepoBundleFileCount !== m.files.length) fail("fullRepoBundleFileCount must equal the number of listed files");
  return m;
}

/** Entries of a bundle, sorted by path. "expansion" = 52 files, "full" = 55 files. */
export function selectBundle(manifest, mode) {
  if (!Object.prototype.hasOwnProperty.call(BUNDLE_MODES, mode)) {
    throw new PackagerError("bad_mode", `unknown bundle mode "${mode}" (use expansion or full)`);
  }
  const picked = manifest.files.filter((f) => mode === "full" || f.scope === "expansion");
  if (picked.length !== BUNDLE_MODES[mode]) {
    throw new PackagerError("bad_bundle_size", `${mode} bundle has ${picked.length} files, expected ${BUNDLE_MODES[mode]}`);
  }
  return [...picked].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

/**
 * Checks every entry against the real bytes. `readBytes(path)` returns Uint8Array or null/undefined when missing.
 * Returns { ok, problems: [{ path, code, detail }] } - never throws for a bad file.
 */
export async function verifyBundle(entries, readBytes) {
  const problems = [];
  for (const e of entries) {
    const bytes = await readBytes(e.path);
    if (bytes === null || bytes === undefined) {
      problems.push({ path: e.path, code: "missing", detail: "file not found" });
      continue;
    }
    if (e.path === MANIFEST_SELF_PATH) continue; // self-reference: nothing to compare
    if (bytes.length !== e.sizeBytes) {
      problems.push({ path: e.path, code: "size_mismatch", detail: `${bytes.length} != ${e.sizeBytes}` });
      continue;
    }
    const actual = await sha256Hex(bytes);
    if (actual !== e.sha256) problems.push({ path: e.path, code: "sha256_mismatch", detail: `${actual} != ${e.sha256}` });
  }
  return { ok: problems.length === 0, problems };
}

/* ------------------------------------------------------------------ ZIP (deterministic, STORE only) */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

const DOS_TIME = 0; // 00:00:00
const DOS_DATE = 0x0021; // 1980-01-01 (fixed so that equal input gives equal bytes)

/** Builds a ZIP from [{ path, bytes }]. Entries are written sorted by path with fixed timestamps and attributes. */
export function createZip(files) {
  const sorted = [...files].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  const seen = new Set();
  const parts = [];
  const central = [];
  let offset = 0;
  const u16 = (v) => [v & 0xff, (v >>> 8) & 0xff];
  const u32 = (v) => [v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff];
  for (const f of sorted) {
    if (!isSafeRelativePath(f.path) || f.path.endsWith("/")) throw new PackagerError("unsafe_path", `unsafe ZIP path: ${f.path}`);
    if (seen.has(f.path)) throw new PackagerError("duplicate_path", `duplicate ZIP path: ${f.path}`);
    seen.add(f.path);
    const name = textEncoder.encode(f.path);
    const crc = crc32(f.bytes);
    const local = new Uint8Array([
      ...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(DOS_TIME), ...u16(DOS_DATE),
      ...u32(crc), ...u32(f.bytes.length), ...u32(f.bytes.length), ...u16(name.length), ...u16(0),
    ]);
    parts.push(local, name, f.bytes);
    central.push(
      new Uint8Array([
        ...u32(0x02014b50), ...u16(0x0314), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(DOS_TIME), ...u16(DOS_DATE),
        ...u32(crc), ...u32(f.bytes.length), ...u32(f.bytes.length), ...u16(name.length), ...u16(0), ...u16(0),
        ...u16(0), ...u16(0), ...u32(((0o100644 << 16) >>> 0)), ...u32(offset),
      ]),
      name,
    );
    offset += local.length + name.length + f.bytes.length;
  }
  const cdSize = central.reduce((n, p) => n + p.length, 0);
  const eocd = new Uint8Array([
    ...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(sorted.length), ...u16(sorted.length), ...u32(cdSize), ...u32(offset), ...u16(0),
  ]);
  const all = [...parts, ...central, eocd];
  const out = new Uint8Array(all.reduce((n, p) => n + p.length, 0));
  let pos = 0;
  for (const p of all) {
    out.set(p, pos);
    pos += p.length;
  }
  return out;
}

/** Re-opens a ZIP made by createZip (or any STORE-only ZIP), verifies the central directory and every CRC. */
export function readZip(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 65535); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new PackagerError("bad_zip", "end of central directory not found");
  const count = dv.getUint16(eocd + 10, true);
  const cdSize = dv.getUint32(eocd + 12, true);
  const cdOffset = dv.getUint32(eocd + 16, true);
  if (cdOffset + cdSize > eocd) throw new PackagerError("bad_zip", "central directory is out of range");
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const entries = [];
  let p = cdOffset;
  for (let i = 0; i < count; i++) {
    if (dv.getUint32(p, true) !== 0x02014b50) throw new PackagerError("bad_zip", `bad central header #${i}`);
    const method = dv.getUint16(p + 10, true);
    const crc = dv.getUint32(p + 16, true);
    const csize = dv.getUint32(p + 20, true);
    const usize = dv.getUint32(p + 24, true);
    const nlen = dv.getUint16(p + 28, true);
    const elen = dv.getUint16(p + 30, true);
    const clen = dv.getUint16(p + 32, true);
    const lho = dv.getUint32(p + 42, true);
    const path = decoder.decode(bytes.subarray(p + 46, p + 46 + nlen));
    if (method !== 0) throw new PackagerError("bad_zip", `unsupported compression for ${path}`);
    if (!isSafeRelativePath(path)) throw new PackagerError("unsafe_path", `unsafe path in ZIP: ${path}`);
    if (dv.getUint32(lho, true) !== 0x04034b50) throw new PackagerError("bad_zip", `bad local header for ${path}`);
    const lnlen = dv.getUint16(lho + 26, true);
    const lelen = dv.getUint16(lho + 28, true);
    const start = lho + 30 + lnlen + lelen;
    const data = bytes.slice(start, start + csize);
    if (csize !== usize || data.length !== usize) throw new PackagerError("bad_zip", `size mismatch for ${path}`);
    if (crc32(data) !== crc) throw new PackagerError("bad_zip", `CRC mismatch for ${path}`);
    entries.push({ path, bytes: data });
    p += 46 + nlen + elen + clen;
  }
  return entries;
}

/** Builds the ZIP for a bundle after verifying the sources, then re-opens it and validates entries and counts. */
export async function buildVerifiedBundleZip(manifest, mode, readBytes) {
  const entries = selectBundle(manifest, mode);
  const check = await verifyBundle(entries, readBytes);
  if (!check.ok) throw new PackagerError("verification_failed", `bundle verification failed: ${JSON.stringify(check.problems)}`);
  const files = [];
  for (const e of entries) files.push({ path: e.path, bytes: await readBytes(e.path) });
  const zip = createZip(files);
  const reopened = readZip(zip);
  if (reopened.length !== BUNDLE_MODES[mode]) throw new PackagerError("zip_validation_failed", `ZIP has ${reopened.length} entries, expected ${BUNDLE_MODES[mode]}`);
  const expected = entries.map((e) => e.path);
  const got = reopened.map((e) => e.path);
  if (JSON.stringify(expected) !== JSON.stringify(got)) throw new PackagerError("zip_validation_failed", "ZIP entry list differs from the bundle");
  for (const f of files) {
    const r = reopened.find((x) => x.path === f.path);
    if ((await sha256Hex(r.bytes)) !== (await sha256Hex(f.bytes))) throw new PackagerError("zip_validation_failed", `ZIP content differs for ${f.path}`);
  }
  return { zip, entries: reopened.map((e) => e.path), sha256: await sha256Hex(zip), size: zip.length, mode };
}

/* ------------------------------------------------------------------ GitHub Direct Push (Git Database API) */

export function redactToken(text, token) {
  let out = String(text);
  if (token) out = out.split(token).join("[REDACTED]");
  return out.replace(/(ghp_|gho_|ghs_|ghu_|github_pat_)[A-Za-z0-9_]+/g, "[REDACTED]");
}

export function toBase64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function apiError(status, headers, token) {
  const remaining = headers && typeof headers.get === "function" ? headers.get("x-ratelimit-remaining") : null;
  if (status === 401) return new PackagerError("auth", "GitHub rejected the token (401). Check that it is valid, not expired, and allowed to write to this repository.");
  if (status === 403 && remaining === "0") return new PackagerError("rate_limit", "GitHub rate limit reached (403). Wait and try again later.");
  if (status === 403) return new PackagerError("forbidden", "The token has no permission for this action (403). It needs Contents: read and write on this repository only.");
  if (status === 404) return new PackagerError("not_found", "Repository or branch not found (404), or the token cannot see the repository.");
  if (status === 409 || status === 422) return new PackagerError("conflict", `The branch changed or the update is not a fast-forward (${status}). Nothing was forced; reload the branch state and try again.`);
  if (status === 429) return new PackagerError("rate_limit", "GitHub rate limit reached (429). Wait and try again later.");
  return new PackagerError("http_error", `GitHub returned HTTP ${status}.`);
}

/**
 * Pushes `files` ([{ path, bytes }]) as ONE commit on TARGET_BRANCH using the official Git Database API:
 *   read ref -> read commit -> create blobs -> create tree (base = current tree) -> create commit (parent = old tip)
 *   -> update ref with force:false -> read the ref and the commit back.
 * Success is reported only when the ref read back points at the new commit and that commit can be read.
 * `fetchFn` is injectable for tests. The token is only ever placed in the Authorization header.
 */
export async function pushToGitHub({ fetchFn, token, repository = REPOSITORY, branch = TARGET_BRANCH, files, message, onProgress = () => {} }) {
  if (FORBIDDEN_BRANCHES.includes(branch) || branch !== TARGET_BRANCH) {
    throw new PackagerError("branch_locked", `Refusing to push to "${branch}". Only ${TARGET_BRANCH} is allowed.`);
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) throw new PackagerError("bad_repository", "Repository must look like owner/name");
  if (typeof token !== "string" || token.length < 10) throw new PackagerError("auth", "A GitHub token is required.");
  if (!Array.isArray(files) || files.length === 0) throw new PackagerError("no_files", "Nothing to push.");
  for (const f of files) if (!isSafeRelativePath(f.path)) throw new PackagerError("unsafe_path", `Unsafe path: ${f.path}`);

  const base = `https://api.github.com/repos/${repository}`;
  const call = async (method, path, body) => {
    let res;
    try {
      res = await fetchFn(base + path, {
        method,
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${token}`,
          "X-GitHub-Api-Version": "2022-11-28",
          ...(body ? { "Content-Type": "application/json" } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
    } catch (err) {
      throw new PackagerError("network", `Network error: ${redactToken(err && err.message ? err.message : err, token)}`);
    }
    if (!res.ok) throw apiError(res.status, res.headers, token);
    return res.json();
  };

  onProgress("Reading branch reference");
  const ref = await call("GET", `/git/ref/heads/${branch}`);
  const parentSha = ref.object.sha;
  onProgress("Reading current commit");
  const parent = await call("GET", `/git/commits/${parentSha}`);
  const tree = [];
  let n = 0;
  for (const f of files) {
    n++;
    onProgress(`Creating blob ${n}/${files.length}: ${f.path}`);
    const blob = await call("POST", "/git/blobs", { content: toBase64(f.bytes), encoding: "base64" });
    tree.push({ path: f.path, mode: "100644", type: "blob", sha: blob.sha });
  }
  onProgress("Creating tree");
  const newTree = await call("POST", "/git/trees", { base_tree: parent.tree.sha, tree });
  onProgress("Creating commit");
  const commit = await call("POST", "/git/commits", { message, tree: newTree.sha, parents: [parentSha] });
  onProgress("Updating branch reference (no force)");
  await call("PATCH", `/git/refs/heads/${branch}`, { sha: commit.sha, force: false });
  onProgress("Verifying result");
  const after = await call("GET", `/git/ref/heads/${branch}`);
  if (after.object.sha !== commit.sha) throw new PackagerError("verify_failed", "The branch does not point at the new commit; do not assume the push succeeded.");
  const readBack = await call("GET", `/git/commits/${commit.sha}`);
  if (readBack.sha !== commit.sha) throw new PackagerError("verify_failed", "The new commit could not be read back.");
  return { commitSha: commit.sha, parentSha, branch, repository, fileCount: files.length };
}
/* CORE:END */
