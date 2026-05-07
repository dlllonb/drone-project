#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_SCRIPT="$ROOT/run-end-to-end.sh"

RUN_ROOT="$ROOT/test/test_runs/camera_to_image"
mkdir -p "$RUN_ROOT"

echo "[TEST] Camera-to-image pipeline"

"$RUN_SCRIPT" \
  --mode acquire-only \
  --output-root "$RUN_ROOT" \
  --duration-s "${TEST_ACQ_DURATION_S:-6}" \
  --cleanup-after-processing 0

EXPOSURE_DIR="$(find "$RUN_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'exposures-*' | sort | tail -n 1)"

if [[ -z "$EXPOSURE_DIR" ]]; then
  echo "[FAIL] No exposure directory created"
  exit 1
fi

BIN_COUNT="$(find "$EXPOSURE_DIR/raw" -type f -name '*.bin' | wc -l)"
if [[ "$BIN_COUNT" -lt 1 ]]; then
  echo "[FAIL] No raw .bin files found"
  exit 1
fi

python3 "$ROOT/readout/process-exposures-batch.py" "$EXPOSURE_DIR" --jobs 1

PNG_COUNT="$(find "$EXPOSURE_DIR/processed" -type f -name '*.png' | wc -l)"
FITS_COUNT="$(find "$EXPOSURE_DIR/processed/fits" -type f -name '*.fits' | wc -l)"

if [[ "$PNG_COUNT" -lt 1 ]]; then
  echo "[FAIL] No PNG files produced"
  exit 1
fi

if [[ "$FITS_COUNT" -lt 1 ]]; then
  echo "[FAIL] No FITS files produced"
  exit 1
fi

python3 - "$EXPOSURE_DIR" <<'PY'
import sys
from pathlib import Path
from PIL import Image
from astropy.io import fits

exp = Path(sys.argv[1])

png = next(exp.glob("processed/**/*.png"))
fit = next(exp.glob("processed/fits/*.fits"))

with Image.open(png) as img:
    assert img.size == (1548, 1040), f"PNG wrong dimensions: {img.size}"

with fits.open(fit) as hdul:
    assert hdul[0].data.shape == (2080, 3096), f"FITS primary wrong shape: {hdul[0].data.shape}"
    assert hdul["GREEN1"].data.shape == (1040, 1548), f"FITS GREEN1 wrong shape: {hdul['GREEN1'].data.shape}"

print("[PASS] Camera-to-image dimensions are correct")
PY

echo "[PASS] Camera-to-image pipeline passed: $EXPOSURE_DIR"