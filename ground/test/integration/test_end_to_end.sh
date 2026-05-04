#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN_SCRIPT="$ROOT/run-end-to-end.sh"

RUN_ROOT="$ROOT/test/test_runs/end_to_end"
mkdir -p "$RUN_ROOT"

echo "[TEST] End-to-end pipeline"

"$RUN_SCRIPT" \
  --mode full \
  --output-root "$RUN_ROOT" \
  --duration-s "${TEST_ACQ_DURATION_S:-8}" \
  --cleanup-after-processing 0

EXPOSURE_DIR="$(find "$RUN_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'exposures-*' | sort | tail -n 1)"

if [[ -z "$EXPOSURE_DIR" ]]; then
  echo "[FAIL] No exposure directory created"
  exit 1
fi

if ! find "$EXPOSURE_DIR/raw" -type f -name '*.bin' | grep -q .; then
  echo "[FAIL] No raw .bin files found"
  exit 1
fi

if ! find "$EXPOSURE_DIR" -type f -name 'encoder_data_*.pkl' | grep -q .; then
  echo "[FAIL] No encoder .pkl file found"
  exit 1
fi

if ! find "$EXPOSURE_DIR/processed/fits" -type f -name '*.fits' | grep -q .; then
  echo "[FAIL] No FITS files produced"
  exit 1
fi

if ! find "$EXPOSURE_DIR/plots" -type f -name '*.png' | grep -q .; then
  echo "[FAIL] No plot PNG files produced"
  exit 1
fi

FITLOG="$(find "$EXPOSURE_DIR/plots" -type f -name 'fitlog_*.log' | head -n 1 || true)"

if [[ -z "$FITLOG" ]]; then
  echo "[FAIL] No fitlog created"
  exit 1
fi

if grep -q "NO_FIT" "$FITLOG"; then
  echo "[WARN] Fitlog contains NO_FIT. This may be acceptable for a short/noisy run."
fi

echo "[PASS] End-to-end pipeline passed: $EXPOSURE_DIR"