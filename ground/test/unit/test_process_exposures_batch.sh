#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/readout/process-exposures-batch.py"

SAMPLE_BIN_DIR="$ROOT/test/test_data/sample_bins"

if ! compgen -G "$SAMPLE_BIN_DIR/*.bin" > /dev/null; then
  echo "[SKIP] No sample .bin files found in $SAMPLE_BIN_DIR"
  echo "[SKIP] Add one or more known-good camera .bin files to enable this test."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXPOSURE_DIR="$TMP_DIR/exposures-test"
RAW_DIR="$EXPOSURE_DIR/raw"
mkdir -p "$RAW_DIR"

cp "$SAMPLE_BIN_DIR"/*.bin "$RAW_DIR/"

python3 "$SCRIPT" "$EXPOSURE_DIR" --jobs 0

if ! find "$EXPOSURE_DIR" -type f -name "*.png" | grep -q .; then
  echo "[FAIL] No .png files produced"
  exit 1
fi

if ! find "$EXPOSURE_DIR" -type f -name "*.fits" | grep -q .; then
  echo "[FAIL] No .fits files produced"
  exit 1
fi

echo "[PASS] process-exposures-batch.py produced PNG and FITS outputs"