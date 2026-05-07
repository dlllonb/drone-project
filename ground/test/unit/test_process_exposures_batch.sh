#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/readout/process-exposures-batch.py"

SAMPLE_BIN_DIR="$ROOT/test/test_data/sample_bins"

if ! compgen -G "$SAMPLE_BIN_DIR/*.bin" > /dev/null; then
  echo "[SKIP] No sample .bin files found in $SAMPLE_BIN_DIR"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXPOSURE_DIR="$TMP_DIR/exposures-test"
RAW_DIR="$EXPOSURE_DIR/raw"
mkdir -p "$RAW_DIR"

cp "$SAMPLE_BIN_DIR"/*.bin "$RAW_DIR/"

python3 "$SCRIPT" "$EXPOSURE_DIR" --jobs 0

PNG_FILE=$(find "$EXPOSURE_DIR" -type f -name "*.png" | head -n 1 || true)
FITS_FILE=$(find "$EXPOSURE_DIR" -type f -name "*.fits" | head -n 1 || true)

if [[ -z "$PNG_FILE" ]]; then
  echo "[FAIL] No PNG files produced"
  exit 1
fi

if [[ -z "$FITS_FILE" ]]; then
  echo "[FAIL] No FITS files produced"
  exit 1
fi

echo "[INFO] Checking image dimensions..."

python3 - <<EOF
from PIL import Image
from astropy.io import fits

png_path = "$PNG_FILE"
fits_path = "$FITS_FILE"

RAW_W = 3096
RAW_H = 2080
PREVIEW_W = 1548
PREVIEW_H = 1040

# PNG preview check
img = Image.open(png_path)
w, h = img.size
assert (w, h) == (PREVIEW_W, PREVIEW_H), f"PNG wrong size: {(w, h)}"

# FITS checks
with fits.open(fits_path) as hdul:
    primary = hdul[0].data
    h0, w0 = primary.shape
    assert (w0, h0) == (RAW_W, RAW_H), f"FITS primary wrong size: {(w0, h0)}"

    green1 = hdul["GREEN1"].data
    h1, w1 = green1.shape
    assert (w1, h1) == (PREVIEW_W, PREVIEW_H), f"FITS GREEN1 wrong size: {(w1, h1)}"

print("[PASS] Image dimensions correct")
EOF

echo "[PASS] process-exposures-batch.py outputs valid images"