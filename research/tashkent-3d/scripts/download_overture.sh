#!/usr/bin/env bash
set -euo pipefail
BBOX="${BBOX:-69.10,41.18,69.45,41.46}"
OUT_DIR="${OUT_DIR:-data/raw/overture}"
mkdir -p "$OUT_DIR"
command -v overturemaps >/dev/null 2>&1 || python -m pip install --upgrade overturemaps
TYPES=(building building_part place segment connector address water land land_use land_cover infrastructure division_area division_boundary)
FAILED=()
for type in "${TYPES[@]}"; do
  echo "[Overture] $type"
  if ! overturemaps download --bbox="$BBOX" -f geoparquet --type="$type" -o "$OUT_DIR/$type.geoparquet"; then
    echo "[WARN] Unsupported or failed type: $type" >&2
    FAILED+=("$type")
  fi
done
printf 'Done. BBOX=%s\\n' "$BBOX"
if (("${#FAILED[@]}")); then printf 'Failed types: %s\\n' "${FAILED[*]}"; exit 2; fi
