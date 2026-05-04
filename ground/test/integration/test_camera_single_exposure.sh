#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAMERA_SCRIPT="$ROOT/readout/continuous-capture.sh"

RUN_ID="integration-camera-$(date +%Y%m%d-%H%M%S)"
OUT_ROOT="$ROOT/test/test_runs/camera_single"
EXPOSURE_DIR="$OUT_ROOT/exposures-$RUN_ID"

mkdir -p "$OUT_ROOT"

echo "[TEST] Camera single exposure"
echo "[INFO] Output: $EXPOSURE_DIR"

export EXPOSURE_TIME="${EXPOSURE_TIME:-0.001}"
export GAIN="${GAIN:-100}"
export INTERVAL="${INTERVAL:-0.5}"
export EXPOSURES_ROOT="$OUT_ROOT"
export RUN_ID="$RUN_ID"

set +e
timeout -s INT 6s bash "$CAMERA_SCRIPT"
status=$?
set -e

# timeout returns 124 when it stops the process. That is acceptable here.
if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
  echo "[FAIL] Camera script exited with status $status"
  exit 1
fi

BIN_COUNT="$(find "$EXPOSURE_DIR/raw" -type f -name '*.bin' 2>/dev/null | wc -l)"

if [[ "$BIN_COUNT" -lt 1 ]]; then
  echo "[FAIL] No .bin files created"
  exit 1
fi

BIN_FILE="$(find "$EXPOSURE_DIR/raw" -type f -name '*.bin' | head -n 1)"
if [[ ! -s "$BIN_FILE" ]]; then
  echo "[FAIL] .bin file exists but is empty: $BIN_FILE"
  exit 1
fi

EXPECTED_BYTES=$((3096 * 2080 * 2))
ACTUAL_BYTES="$(stat -c%s "$BIN_FILE")"

if [[ "$ACTUAL_BYTES" -ne "$EXPECTED_BYTES" ]]; then
  echo "[FAIL] .bin file has wrong size: got $ACTUAL_BYTES, expected $EXPECTED_BYTES"
  exit 1
fi

echo "[PASS] Camera created valid .bin file: $BIN_FILE"