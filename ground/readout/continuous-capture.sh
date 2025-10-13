#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S-$(date +%3N))
BASE_DIR="exposures-$TIMESTAMP"
RAW_DIR="$BASE_DIR/raw"
PROCESSED_DIR="$BASE_DIR/processed"
mkdir -p "$RAW_DIR" "$PROCESSED_DIR"

CAPTURE_BIN="/home/declan/drone-project/ground/camera/capture-continuous.out"

EXPOSURE_TIME=0.001
GAIN=100
INTERVAL=1.5

trap "echo -e '\nStopping capture...'; exit 0" SIGINT

echo "Starting capture. Files will be saved to $RAW_DIR"
"$CAPTURE_BIN" --output-dir "$RAW_DIR" --exposure-time "$EXPOSURE_TIME" --gain "$GAIN" --interval "$INTERVAL"