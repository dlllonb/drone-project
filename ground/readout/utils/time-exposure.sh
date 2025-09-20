#!/bin/bash

# This script is meant to test the total time it takes to call ./capture-exposure [time] 

# Full path to the exposure capture binary
CAPTURE_BIN="/home/declan/RPI/zwo/capture-exposure.out"

# Check if the user provided an exposure time argument
if [ -z "$1" ]; then
    echo "Usage: $0 <exposure_time_in_seconds>"
    exit 1
fi

EXPOSURE_TIME="$1"

echo "Timing a single exposure with duration ${EXPOSURE_TIME}s..."

start=$(date +%s.%N)

"$CAPTURE_BIN" "$EXPOSURE_TIME"

end=$(date +%s.%N)

elapsed=$(echo "$end - $start" | bc)

echo "Elapsed time: ${elapsed} seconds"