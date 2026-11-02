#!/usr/bin/env node
import fs from "node:fs";
import crypto from "node:crypto";

export function runCli(argv = process.argv.slice(2)) {
  const [cmd, arg] = argv;
  const catalog = JSON.parse(fs.readFileSync("assets/world/uzbekistan/region_catalog.json", "utf8"));
  if (cmd === "list-regions") {
    for (const r of catalog.regions) {
      console.log(`${r.isoCode} | ${r.regionId} | lat=${r.latitude}, lon=${r.longitude} | ${r.defaultReadiness}`);
    }
    return 0;
  }
  if (cmd === "validate-regions") {
    if (catalog.regions.length !== 14) throw new Error("Expected 14 regions");
    const codes = new Set(catalog.regions.map((r) => r.isoCode));
    if (codes.size !== 14 || !codes.has("UZ-TK") || !codes.has("UZ-TO")) {
      throw new Error("Region code validation failed");
    }
    console.log("OK: 14 Uzbekistan regions verified.");
    return 0;
  }
  if (cmd === "validate-package") {
    if (!arg || !fs.existsSync(arg)) throw new Error("Manifest path required");
    const manifest = JSON.parse(fs.readFileSync(arg, "utf8"));
    const catalogBytes = fs.readFileSync("assets/world/uzbekistan/region_catalog.json");
    const actualSha = crypto.createHash("sha256").update(catalogBytes).digest("hex");
    if (manifest.sha256 !== actualSha) throw new Error("SHA-256 mismatch");
    console.log(`VALID PACKAGE: ${manifest.packageId} (${manifest.isoCode})`);
    return 0;
  }
  throw new Error("Usage: trafficity-uz <list-regions|validate-regions|validate-package <path>>");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runCli();
}
