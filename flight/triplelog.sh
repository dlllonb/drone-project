#!/usr/bin/env bash
set -euo pipefail

# --- logging ---
LOGFILE="../data/logs/run_$(date -u +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(stdbuf -oL -eL tee -a "$LOGFILE") 2>&1
echo "[runner] logging to $LOGFILE"
export PYTHONUNBUFFERED=1

# --- launch children ---
python3 -u GPS/GPS.py &  GPS_PID=$!
python3 -u IMU/IMU.py &  IMU_PID=$!
python3 -u CAM/CAM.py &  CAM_PID=$!

# use the first child’s process group (safer than $$)
CHILD_PGID="$(ps -o pgid= "$GPS_PID" | tr -d ' ')"
echo "[runner] child PGID: $CHILD_PGID"

stop_all() {
  # don’t let errors in here abort cleanup
  set +e
  echo "[runner] stop_all invoked"

  # 1) SIGINT first (lets Python break out of blocking calls)
  echo "[runner] sending SIGINT to group $CHILD_PGID..."
  kill -INT -"$CHILD_PGID" 2>/dev/null

  for _ in {1..25}; do  # ~5s
    sleep 0.2
    kill -0 "$GPS_PID" 2>/dev/null || kill -0 "$IMU_PID" 2>/dev/null || kill -0 "$CAM_PID" 2>/dev/null || break
  done

  # 2) SIGTERM as a second nudge
  if kill -0 "$GPS_PID" 2>/dev/null || kill -0 "$IMU_PID" 2>/dev/null || kill -0 "$CAM_PID" 2>/dev/null; then
    echo "[runner] still running; sending SIGTERM…"
    kill -TERM -"$CHILD_PGID" 2>/dev/null
    sleep 1
  fi

  # 3) last resort: SIGKILL lingering PIDs directly
  for PID in "$GPS_PID" "$IMU_PID" "$CAM_PID"; do
    if kill -0 "$PID" 2>/dev/null; then
      echo "[runner] forcing stop of $PID (SIGKILL)…"
      kill -KILL "$PID" 2>/dev/null
    fi
  done
}

# run stop_all on INT/TERM and also on any exit path
trap 'stop_all' INT TERM
trap 'stop_all' EXIT

# wait shouldn’t abort the script on EINTR
while true; do
  # wait for any child; exit loop when none remain
  if ! wait -n 2>/dev/null; then
    # if wait -n not available (older bash), fall back to single wait
    wait || true
    break
  fi

  # if all gone, break
  kill -0 "$GPS_PID" 2>/dev/null || kill -0 "$IMU_PID" 2>/dev/null || kill -0 "$CAM_PID" 2>/dev/null || break
done

echo "[runner] all children stopped"
