#!/usr/bin/env bash
set -euo pipefail
set -m  # own process group

# --- logging setup ---
LOGFILE="../data/logs/run_$(date -u +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"

# Make tee line-buffered, capture both stdout+stderr
exec > >(stdbuf -oL -eL tee -a "$LOGFILE") 2>&1
echo "[runner] logging to $LOGFILE"

# Make Python unbuffered so prints appear immediately
export PYTHONUNBUFFERED=1

# --- launch children ---
python3 -u GPS/GPS.py &  GPS_PID=$!
python3 -u IMU/IMU.py &  IMU_PID=$!
python3 -u CAM/CAM.py &  CAM_PID=$!

PGID=$(ps -o pgid= $$ | tr -d ' ')

# --- graceful stop: TERM -> (wait) -> INT -> KILL ---
stop_all() {
  echo "[runner] stopping (SIGTERM to group $PGID)…"
  kill -TERM -"$PGID" 2>/dev/null || true

  # grace: 3s in 0.2s steps
  for _ in {1..15}; do
    sleep 0.2
    kill -0 $GPS_PID 2>/dev/null || kill -0 $IMU_PID 2>/dev/null || kill -0 $CAM_PID 2>/dev/null || break
  done

  # nudge with SIGINT so KeyboardInterrupt fires if they rely on it
  if kill -0 $GPS_PID 2>/dev/null || kill -0 $IMU_PID 2>/dev/null || kill -0 $CAM_PID 2>/dev/null; then
    echo "[runner] still running; sending SIGINT…"
    kill -INT -"$PGID" 2>/dev/null || true
    sleep 0.5
  fi

  # force stop if anything remains
  if kill -0 $GPS_PID 2>/dev/null || kill -0 $IMU_PID 2>/dev/null || kill -0 $CAM_PID 2>/dev/null; then
    echo "[runner] forcing stop (SIGKILL)…"
    kill -KILL -"$PGID" 2>/dev/null || true
  fi
}
trap 'stop_all' INT TERM

wait  # wait for all children to exit
echo "[runner] all children stopped"
