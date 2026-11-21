#!/usr/bin/env bash
set -euo pipefail
OUT_DIR="${OUT_DIR:-data/raw/osm}"
POLY="${TASHKENT_POLY:-data/boundaries/tashkent-city.poly}"
PBF="$OUT_DIR/uzbekistan-latest.osm.pbf"
mkdir -p "$OUT_DIR" "$(dirname "$POLY")"
BASE="https://download.geofabrik.de/asia/uzbekistan"
curl -fL "$BASE-latest.osm.pbf" -o "$PBF"
curl -fL "$BASE-latest.osm.pbf.md5" -o "$PBF.md5"
(cd "$OUT_DIR" && md5sum --check "uzbekistan-latest.osm.pbf.md5")
echo "Downloaded and checksum-verified: $PBF"
if [[ -f "$POLY" ]]; then
  command -v osmium >/dev/null 2>&1 || { echo "Install osmium-tool first" >&2; exit 1; }
  osmium extract --polygon="$POLY" --strategy=complete_ways -o "$OUT_DIR/tashkent-city.osm.pbf" "$PBF"
else
  echo "No verified city polygon at $POLY. Country PBF only; obtain official boundary before clipping."
fi
