#!/bin/bash

# Get timestamp with millisecond precision
TIMESTAMP=$(date +%Y%m%d-%H%M%S-$(date +%3N))
BASE_DIR="exposures-$TIMESTAMP"
RAW_DIR="$BASE_DIR/raw"
PROCESSED_DIR="$BASE_DIR/processed"
mkdir -p "$RAW_DIR" "$PROCESSED_DIR"

# Full path to the refactored capture binary
CAPTURE_BIN="/home/declan/RPI/zwo/capture-exposure.out"

# Exposure parameters
EXPOSURE_TIME=0.001  # in seconds (1 ms)
GAIN=100             # gain value

# Interval between exposures in seconds
INTERVAL=1.5

# Trap keyboard interrupt (Ctrl+C) and exit cleanly
trap "echo -e '\nCapture interrupted by user. Exiting.'; exit 0" SIGINT

echo "Saving exposures to $RAW_DIR. Press Ctrl+C to stop."

cd "$RAW_DIR"
while true; do
    "$CAPTURE_BIN" --exposure-time "$EXPOSURE_TIME" --gain "$GAIN"
    sleep "$INTERVAL"
done