#!/usr/bin/env bash
set -euo pipefail

# Run from readout/ no matter where invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MOTOR_SCRIPT="../motor/motor-spin-logger.py"
CAMERA_SCRIPT="./continuous-capture.sh"
PROCESS_SCRIPT="./process-exposures-batch.py"
PLOT_SCRIPT="./create-plot.py"

MOTOR_PID=""
CAM_PID=""
TAIL_PID=""

EXPOSURE_DIR=""
CAM_LOG=""
MOTOR_LOG=""

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

cleanup_and_exit() {
  echo
  info "Stopping acquisition (camera first, then motor)..."

  # Stop tail first (reduces terminal noise)
  if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
  fi

  # Stop camera first
  if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
    info "Sending SIGINT to camera capture (PID=${CAM_PID})..."
    kill -INT "${CAM_PID}" 2>/dev/null || true
    wait "${CAM_PID}" 2>/dev/null || true
  fi

  # Then stop motor
  if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
    info "Sending SIGINT to motor logger (PID=${MOTOR_PID})..."
    kill -INT "${MOTOR_PID}" 2>/dev/null || true
    wait "${MOTOR_PID}" 2>/dev/null || true
  fi

  info "Stopped."
}
trap cleanup_and_exit INT TERM

# ---- Sanity checks ----
for f in "$MOTOR_SCRIPT" "$CAMERA_SCRIPT" "$PROCESS_SCRIPT" "$PLOT_SCRIPT"; do
  if [[ ! -e "$f" ]]; then
    err "Missing required file: $f"
    exit 1
  fi
done

info "Stage 1/4: Starting motor logger (quiet)..."
# Motor output quiet; we'll move/redirect log after we know exposure folder
python3 -u "$MOTOR_SCRIPT" > /dev/null 2>&1 &
MOTOR_PID=$!
info "Motor logger started (PID=${MOTOR_PID})."

info "Stage 2/4: Starting camera capture..."
# Camera output to a temporary file until we know the exposure folder
TMP_CAM_LOG="$(mktemp -p "$SCRIPT_DIR" cam_tmp_XXXXXX.log)"
bash "$CAMERA_SCRIPT" >"$TMP_CAM_LOG" 2>&1 &
CAM_PID=$!
info "Camera capture started (PID=${CAM_PID})."

# Wait for the exposure folder to appear (created by continuous-capture.sh)
info "Waiting for exposures-* folder to be created..."
START_WAIT="$(date +%s)"
TIMEOUT_SEC=30

while true; do
  # newest exposures-* directory in readout/
  found="$(ls -1dt exposures-* 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" && -d "$found" ]]; then
    EXPOSURE_DIR="$found"
    break
  fi

  # If camera died early, stop
  if ! kill -0 "$CAM_PID" 2>/dev/null; then
    err "Camera process exited before creating exposures folder. Check $TMP_CAM_LOG"
    exit 1
  fi

  now="$(date +%s)"
  if (( now - START_WAIT > TIMEOUT_SEC )); then
    err "Timed out waiting for exposures folder (${TIMEOUT_SEC}s). Check $TMP_CAM_LOG"
    exit 1
  fi

  sleep 0.2
done

info "Found exposure folder: ${EXPOSURE_DIR}"

# Create log filenames inside the exposure folder
CAM_LOG="${EXPOSURE_DIR}/camera.log"
MOTOR_LOG="${EXPOSURE_DIR}/motor.log"

# Move temp cam log into exposure folder and start following it
mv "$TMP_CAM_LOG" "$CAM_LOG"
tail -n +1 -f "$CAM_LOG" &
TAIL_PID=$!

# Re-start motor logger but now log into exposure folder (quiet to terminal)
# Stop previous motor logger instance first
if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  kill -INT "${MOTOR_PID}" 2>/dev/null || true
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

python3 -u "$MOTOR_SCRIPT" >"$MOTOR_LOG" 2>&1 &
MOTOR_PID=$!
info "Motor logger restarted with log: ${MOTOR_LOG}"

info "Capture running. Press Ctrl+C to stop (camera stops first)."
wait "$CAM_PID" 2>/dev/null || true

# Camera ended; stop tail; then stop motor (if still running)
if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
  kill "${TAIL_PID}" 2>/dev/null || true
  wait "${TAIL_PID}" 2>/dev/null || true
fi

if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  info "Camera stopped; now stopping motor logger..."
  kill -INT "${MOTOR_PID}" 2>/dev/null || true
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

info "Stage 3/4: Locating exposure folder + encoder pkl (searching in readout/)..."

# Re-resolve exposure dir (newest) as a safety net
EXPOSURE_DIR="$(ls -1dt exposures-* 2>/dev/null | head -n 1 || true)"
if [[ -z "$EXPOSURE_DIR" ]] || [[ ! -d "$EXPOSURE_DIR" ]]; then
  err "Could not find an exposures-* directory in $SCRIPT_DIR"
  exit 1
fi
info "Using exposure folder: ${EXPOSURE_DIR}"

# NEW: find newest encoder pkl in readout/ (not ../motor)
ENCODER_PKL="$(ls -1t encoder_data_*.pkl 2>/dev/null | head -n 1 || true)"
if [[ -z "$ENCODER_PKL" ]] || [[ ! -f "$ENCODER_PKL" ]]; then
  err "Could not find encoder_data_*.pkl in readout/"
  err "Files in readout matching *.pkl:"
  ls -1 *.pkl 2>/dev/null || true
  exit 1
fi
info "Using encoder file: ${ENCODER_PKL}"

# Move encoder pkl into exposure folder (single source of truth)
PKL_BASENAME="$(basename "$ENCODER_PKL")"
mv -f "$ENCODER_PKL" "${EXPOSURE_DIR}/${PKL_BASENAME}"
ENCODER_PKL="${EXPOSURE_DIR}/${PKL_BASENAME}"
info "Moved encoder file into exposure folder: ${ENCODER_PKL}"

info "Stage 4/4: Processing .bin -> .fits (no previews)..."
python3 "$PROCESS_SCRIPT" "$EXPOSURE_DIR" --no-color --no-green

info "Generating plots + fit..."
python3 "$PLOT_SCRIPT" "$EXPOSURE_DIR" "$ENCODER_PKL"

info "Done."
info "Outputs:"
info "  Logs:  ${EXPOSURE_DIR}/camera.log , ${EXPOSURE_DIR}/motor.log"
info "  FITS:  ${EXPOSURE_DIR}/processed/fits/"
info "  Plots: ${EXPOSURE_DIR}/plots/"