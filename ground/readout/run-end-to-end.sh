#!/usr/bin/env bash
set -euo pipefail

# Run from readout/ no matter where invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MOTOR_SCRIPT="../motor/motor-spin-logger.py"
CAMERA_SCRIPT="./continuous-capture.sh"
PROCESS_SCRIPT="./process-exposures-batch.py"
PLOT_SCRIPT="./create-plot.py"

CAM_LOG="camera_capture_$(date +%Y%m%d-%H%M%S).log"
MOTOR_LOG="motor_logger_$(date +%Y%m%d-%H%M%S).log"

MOTOR_PID=""
CAM_PID=""
TAIL_PID=""

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
err()  { echo -e "[ERR ] $*" >&2; }

cleanup_and_exit() {
  echo
  info "Stopping acquisition (camera first, then motor)..."

  # Stop tail (so terminal isn't noisy while stopping children)
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
# Quiet motor output (but still log to file in case you need it later)
python3 -u "$MOTOR_SCRIPT" >"$MOTOR_LOG" 2>&1 &
MOTOR_PID=$!
info "Motor logger started (PID=${MOTOR_PID}). Output -> ${MOTOR_LOG}"

info "Stage 2/4: Starting camera capture (showing camera output)..."
# Run camera capture, log output, and stream the log to terminal
bash "$CAMERA_SCRIPT" >"$CAM_LOG" 2>&1 &
CAM_PID=$!
info "Camera capture started (PID=${CAM_PID}). Output -> ${CAM_LOG}"

# Stream camera output live
tail -n +1 -f "$CAM_LOG" &
TAIL_PID=$!

info "Capture running. Press Ctrl+C to stop (camera stops first)."
# Wait for camera to exit (likely via Ctrl+C)
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

info "Stage 3/4: Locating newest exposure folder and newest encoder pkl..."

# Newest exposures-* directory in readout/
EXPOSURE_DIR="$(ls -1dt exposures-* 2>/dev/null | head -n 1 || true)"
if [[ -z "$EXPOSURE_DIR" ]] || [[ ! -d "$EXPOSURE_DIR" ]]; then
  err "Could not find an exposures-* directory in $SCRIPT_DIR"
  exit 1
fi
info "Using exposure folder: ${EXPOSURE_DIR}"

# Newest encoder_data_*.pkl in ../motor
ENCODER_PKL="$(ls -1t ../motor/encoder_data_*.pkl 2>/dev/null | head -n 1 || true)"
if [[ -z "$ENCODER_PKL" ]] || [[ ! -f "$ENCODER_PKL" ]]; then
  err "Could not find ../motor/encoder_data_*.pkl"
  exit 1
fi
info "Using encoder file: ${ENCODER_PKL}"

info "Stage 4/4: Processing .bin -> .fits (no previews)..."
python3 "$PROCESS_SCRIPT" "$EXPOSURE_DIR" --no-color --no-green

info "Generating plots + fit..."
python3 "$PLOT_SCRIPT" "$EXPOSURE_DIR" "$ENCODER_PKL"

info "Done."
info "Outputs:"
info "  FITS:  ${EXPOSURE_DIR}/processed/fits/"
info "  Plots: ${EXPOSURE_DIR}/plots/"