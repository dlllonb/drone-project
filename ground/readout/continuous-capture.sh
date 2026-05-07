#!/bin/bash

# continuous-capture.sh
# =====================
#
# Purpose
# -------
# Wrapper script for continuous camera acquisition. This script creates the
# standard exposure directory structure, then launches the compiled ZWO camera
# capture binary to write raw `.bin` frames into the run's `raw/` folder.
#
# This script is normally called by `run-end-to-end.sh`, but it can also be run
# manually for camera-only acquisition tests.
#
# Inputs
# ------
# Configuration is supplied through environment variables:
#
#   EXPOSURES_ROOT
#       Parent directory where `exposures-*` folders should be created.
#       Defaults to the current working directory.
#
#   RUN_ID
#       Optional deterministic run identifier supplied by `run-end-to-end.sh`.
#       If unset, this script creates a timestamp-based run id.
#
#   CAPTURE_BIN
#       Optional path to the compiled camera capture executable.
#       Defaults to `/home/declan/drone-project/ground/camera/capture-continuous.out`.
#
#   EXPOSURE_TIME
#       Exposure duration in seconds. Default: 0.001
#
#   GAIN
#       Camera gain setting. Default: 100
#
#   INTERVAL
#       Delay between completed captures. Default: 0.001
#
# Outputs
# -------
# Creates an exposure directory:
#
#   exposures-<RUN_ID or timestamp>/
#       raw/
#       processed/
#
# Raw `.bin` files are written into the `raw/` directory by the camera binary.
#
# Shutdown
# --------
# On SIGINT, the script exits cleanly. The compiled camera binary handles camera
# cleanup and file finalization.

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