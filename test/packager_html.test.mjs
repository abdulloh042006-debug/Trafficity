// Static and structural tests for Trafficity-Uzbekistan-Complete-Packager.html.
// The real-browser behaviour (File API, ZIP download, mocked GitHub push) was verified separately with Chromium;
// those runs are not part of `npm test` because they need a browser.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

import { BEGIN, CORE_PATH, END, HTML_PATH, coreForHtml, embeddedCoreFromHtml } from "../tools/sync_packager_html.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(HTML_PATH, "utf8");
const coreSource = readFileSync(CORE_PATH, "utf8");

test("the HTML packager exists at the repository root", () => {
  assert.ok(html.length > 5000);
  assert.ok(html.startsWith("<!doctype html>"));
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
});

test("the embedded core is byte-identical to tools/packager_core.mjs (no drift)", () => {
  assert.equal(embeddedCoreFromHtml(html), coreForHtml(coreSource));
  assert.equal(html.split(BEGIN).length, 2);
  assert.equal(html.split(END).length, 2);
});

test("the sync script --check passes on the real repository", () => {
  const r = spawnSync(process.execPath, [join(ROOT, "tools", "sync_packager_html.mjs"), "--check"], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /identical/);
});

test("the embedded script is plain script code (no module syntax) and defines the packager API", () => {
  const code = embeddedCoreFromHtml(html);
  assert.equal(/^\s*(export|import)\s/m.test(code), false);
  const ctx = vm.createContext({ TextEncoder, TextDecoder, crypto: globalThis.crypto, btoa });
  vm.runInContext(code, ctx);
  for (const name of ["pushToGitHub", "verifyBundle", "selectBundle", "buildVerifiedBundleZip", "redactToken", "validateFileManifest"]) {
    assert.equal(vm.runInContext(`typeof ${name}`, ctx), "function", name);
  }
  assert.equal(vm.runInContext("TARGET_BRANCH", ctx), "codex/uzbekistan-expansion");
  assert.deepEqual(JSON.parse(vm.runInContext("JSON.stringify(FORBIDDEN_BRANCHES)", ctx)), ["main", "master"]); // JSON: the array comes from another realm
});

test("no external scripts, stylesheets or CDN: everything is inline and the CSP limits network access", () => {
  assert.equal(/<script[^>]+src=/i.test(html), false);
  assert.equal(/<link[^>]+href=/i.test(html), false);
  const csp = html.match(/Content-Security-Policy" content="([^"]+)"/)[1];
  assert.match(csp, /default-src 'none'/);
  assert.equal(csp.includes("unsafe-eval"), false);
  const connect = csp.match(/connect-src ([^;]+)/)[1].split(" ").sort();
  assert.deepEqual(connect, ["https://api.github.com", "https://raw.githubusercontent.com"]);
  const hosts = new Set([...html.matchAll(/https?:\/\/([a-z0-9.-]+)/gi)].map((m) => m[1]));
  for (const h of hosts) assert.ok(["api.github.com", "raw.githubusercontent.com", "github.com"].includes(h), `unexpected host ${h}`);
});

test("the two bundle modes are offered with the 20 / 23 file contract", () => {
  assert.match(html, /value="expansion" checked> Expansion ZIP — <b>20<\/b> files/);
  assert.match(html, /value="full"> Full ZIP — <b>23<\/b> files/);
});

test("the push target is locked: no branch control, no force, main/master rejected in code", () => {
  assert.equal(/<input[^>]+(name|id)="branch"/i.test(html), false);
  assert.equal(/<select/i.test(html), false);
  assert.equal(/force:\s*true/.test(html), false);
  assert.equal((html.match(/\bforce:\s*false\s*\}/g) || []).length, 1, "exactly one ref update, and it is explicitly not forced");
  assert.match(html, /FORBIDDEN_BRANCHES\.includes\(branch\)/);
  const ui = html.slice(html.indexOf('<script id="packager-ui">'));
  assert.equal(/branch\s*[:=]/.test(ui.replace(/TARGET_BRANCH/g, "")), false, "the UI must not pass its own branch");
});

test("the token is handled safely: password field, no storage, cleared in a finally block, redacted in messages", () => {
  assert.match(html, /<input id="token" type="password" autocomplete="off"/);
  const ui = html.slice(html.indexOf('<script id="packager-ui">'));
  assert.equal(/localStorage|sessionStorage|indexedDB|document\.cookie/.test(html), false);
  assert.match(ui, /finally \{\s*\$\("token"\)\.value = "";/);
  assert.match(ui, /redactToken\(/);
  assert.equal(/fetch\([^)]*token/i.test(ui), false, "the token must never be placed in a URL");
});

test("the page shows everything the owner asked for", () => {
  for (const id of ["repo", "branch", "mver", "summary", "status", "btn-validate", "btn-zip", "btn-push", "log", "inventory", "progress"]) {
    assert.ok(html.includes(`id="${id}"`), `missing #${id}`);
  }
  assert.match(html, /aria-live="polite"/);
  assert.match(html, /color-scheme: dark/);
  assert.match(html, /Manifest file inventory/);
});
