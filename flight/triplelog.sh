#!/usr/bin/env bash
set -euo pipefail

set -m

python3 GPS/GPS.py &
GPS_PID=$!
python3 IMU/IMU.py &
IMU_PID=$!
python3 CAM/CAM.py &
CAM_PID=$!

trap 'echo; echo "Stopping…"; kill -INT -$PGID' INT TERM
PGID=$(ps -o pgid= $$ | tr -d ' ')
wait