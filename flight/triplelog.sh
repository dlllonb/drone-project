#!/usr/bin/env bash
set -euo pipefail

# --- logging ---
LOGFILE="../data/logs/run_$(date -u +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"

# 1) normal stdout/stderr -> line-buffered tee, and tee ignores SIGINT (-i)
exec > >(stdbuf -oL -eL tee -ai "$LOGFILE") 2>&1

# 2) open a direct-append FD that bypasses the pipe (for shutdown logs)
exec 3>>"$LOGFILE"

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
  printf "[runner] stop_all invoked\n" >&3

  # 1) SIGINT first (lets Python break out of blocking calls)
  echo "[runner] sending SIGINT to group $CHILD_PGID..."
  printf "[runner] sending SIGINT to group %s...\n" "$CHILD_PGID" >&3
  kill -INT -"$CHILD_PGID" 2>/dev/null

  # grace ~5s
  for _ in {1..25}; do
    sleep 0.2
    kill -0 "$GPS_PID" 2>/dev/null || kill -0 "$IMU_PID" 2>/dev/null || kill -0 "$CAM_PID" 2>/dev/null || break
  done

  # 2) SIGTERM as a second nudge
  if kill -0 "$GPS_PID" 2>/dev/null || kill -0 "$IMU_PID" 2>/dev/null || kill -0 "$CAM_PID" 2>/dev/null; then
    echo "[runner] still running; sending SIGTERM…"
    printf "[runner] still running; sending SIGTERM…\n" >&3
    kill -TERM -"$CHILD_PGID" 2>/dev/null
    sleep 1
  fi

  # 3) last resort: SIGKILL lingering PIDs directly
  for PID in "$GPS_PID" "$IMU_PID" "$CAM_PID"; do
    if kill -0 "$PID" 2>/dev/null; then
      echo "[runner] forcing stop of $PID (SIGKILL)…"
      printf "[runner] forcing stop of %s (SIGKILL)…\n" "$PID" >&3
      kill -KILL "$PID" 2>/dev/null
    fi
  done

  printf "[runner] all children stopped\n" >&3
  sync  # flush filesystem buffers (including fd 3)
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
printf "[runner] all children stopped\n" >&3
