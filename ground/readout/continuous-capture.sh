#!/bin/bash
set -euo pipefail

# Root where exposures-* should be created (default: current dir)
EXPOSURES_ROOT="${EXPOSURES_ROOT:-$(pwd)}"

# Optional run id supplied by run-end-to-end so folders are deterministic
# If not provided, fall back to a timestamp-based id
if [[ -n "${RUN_ID:-}" ]]; then
  TIMESTAMP="$RUN_ID"
else
  TIMESTAMP="$(date +%Y%m%d-%H%M%S-$(date +%3N))"
fi

BASE_DIR="${EXPOSURES_ROOT}/exposures-$TIMESTAMP"
RAW_DIR="$BASE_DIR/raw"
PROCESSED_DIR="$BASE_DIR/processed"
mkdir -p "$RAW_DIR" "$PROCESSED_DIR"

CAPTURE_BIN="${CAPTURE_BIN:-/home/declan/drone-project/ground/camera/capture-continuous.out}"

# Defaults so script runs standalone
EXPOSURE_TIME="${EXPOSURE_TIME:-0.001}"
GAIN="${GAIN:-100}"
INTERVAL="${INTERVAL:-0.001}"

trap "echo -e '\nStopping capture...'; exit 0" SIGINT

echo "Starting capture."
echo "Exposures root: ${EXPOSURES_ROOT}"
echo "Files will be saved to: $RAW_DIR"
echo "Exposure time: ${EXPOSURE_TIME}s | Gain: ${GAIN} | Interval: ${INTERVAL}s"

"$CAPTURE_BIN" --output-dir "$RAW_DIR" --exposure-time "$EXPOSURE_TIME" --gain "$GAIN" --interval "$INTERVAL"