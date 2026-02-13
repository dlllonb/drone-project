#!/usr/bin/env bash
set -euo pipefail

# =========================
# Run-end-to-end script (BASE DIR)
# Place this file in: ground/
# =========================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

MOTOR_SCRIPT="$BASE_DIR/motor/motor-spin-logger.py"
CAMERA_SCRIPT="$BASE_DIR/readout/continuous-capture.sh"
PROCESS_SCRIPT="$BASE_DIR/readout/process-exposures-batch.py"
PLOT_SCRIPT="$BASE_DIR/readout/create-plot.py"
LOAD_CONFIG="$BASE_DIR/load-config.py"

# PIDs (also PGIDs because we launch with setsid)
MOTOR_PID=""
CAM_PID=""
TAIL_PID=""
TIMER_PID=""

EXPOSURE_DIR=""
CAM_LOG=""
MOTOR_LOG=""

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

# Send a signal to an entire process group (PGID)
kill_pgrp() {
  local sig="$1"
  local pgid="$2"
  if [[ -n "${pgid}" ]] && kill -0 "${pgid}" 2>/dev/null; then
    kill "-${sig}" -- "-${pgid}" 2>/dev/null || true
  fi
}

cleanup_and_exit() {
  echo
  info "Stopping acquisition (camera first, then motor)..."

  # stop timer (if running)
  if [[ -n "${TIMER_PID}" ]] && kill -0 "${TIMER_PID}" 2>/dev/null; then
    kill "${TIMER_PID}" 2>/dev/null || true
    wait "${TIMER_PID}" 2>/dev/null || true
  fi

  # stop tail
  if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
  fi

  # stop camera group
  if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
    info "Sending SIGINT to camera capture process group (PGID=${CAM_PID})..."
    kill_pgrp INT "${CAM_PID}"
    wait "${CAM_PID}" 2>/dev/null || true
  fi

  # stop motor group
  if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
    info "Sending SIGINT to motor logger process group (PGID=${MOTOR_PID})..."
    kill_pgrp INT "${MOTOR_PID}"
    wait "${MOTOR_PID}" 2>/dev/null || true
  fi

  info "Stopped."
}
trap cleanup_and_exit INT TERM

# ---- args ----
CONFIG_PATH="$BASE_DIR/config.yml"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    *)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "$CONFIG_PATH" != /* ]]; then
  CONFIG_PATH="$BASE_DIR/$CONFIG_PATH"
fi

for f in "$MOTOR_SCRIPT" "$CAMERA_SCRIPT" "$PROCESS_SCRIPT" "$PLOT_SCRIPT" "$LOAD_CONFIG" "$CONFIG_PATH"; do
  if [[ ! -e "$f" ]]; then
    err "Missing required file: $f"
    exit 1
  fi
done

info "Loading config: ${CONFIG_PATH}"
eval "$(python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}")"

# Defaults
EXPOSURE_TIME="${EXPOSURE_TIME:-0.001}"
GAIN="${GAIN:-100}"
INTERVAL="${INTERVAL:-0.001}"
GROUND_PATH="${GROUND_PATH:-$BASE_DIR/}"
SPIN_RATE="${SPIN_RATE:-250}"

PROCESS_JOBS="${PROCESS_JOBS:-0}"
PROCESS_MAKE_FITS="${PROCESS_MAKE_FITS:-1}"
PROCESS_MAKE_COLOR="${PROCESS_MAKE_COLOR:-0}"
PROCESS_MAKE_GREEN="${PROCESS_MAKE_GREEN:-0}"
PROCESS_QUIET="${PROCESS_QUIET:-1}"

PLOT_COUNTS_PER_REV="${PLOT_COUNTS_PER_REV:-2400}"
PLOT_ROI_SIZE="${PLOT_ROI_SIZE:-3}"
PLOT_BG_X="${PLOT_BG_X:-50}"
PLOT_BG_Y="${PLOT_BG_Y:-50}"
PLOT_DEBUG="${PLOT_DEBUG:-0}"
PLOT_TIME_OFFSET_HOURS="${PLOT_TIME_OFFSET_HOURS:-}"

ACQ_DURATION_S="${ACQ_DURATION_S:-0}"

info "Resolved acquisition: exposure=${EXPOSURE_TIME}s gain=${GAIN} interval=${INTERVAL}s duration_s=${ACQ_DURATION_S}"
info "Resolved motor: ground_path=${GROUND_PATH} spin_rate=${SPIN_RATE}"
info "Resolved processing: jobs=${PROCESS_JOBS} fits=${PROCESS_MAKE_FITS} color=${PROCESS_MAKE_COLOR} green=${PROCESS_MAKE_GREEN} quiet=${PROCESS_QUIET}"
info "Resolved plotting: counts_per_rev=${PLOT_COUNTS_PER_REV} roi_size=${PLOT_ROI_SIZE} bg=(${PLOT_BG_X},${PLOT_BG_Y}) debug=${PLOT_DEBUG} time_offset_hours=${PLOT_TIME_OFFSET_HOURS}"

# Deterministic run id/folder
RUN_ID="$(date +%Y%m%d-%H%M%S-$(date +%3N))_$$"
EXPOSURE_DIR="$BASE_DIR/exposures-$RUN_ID"
info "This run folder will be: ${EXPOSURE_DIR}"

# =========================
# Stage 1: Motor logger
# =========================
info "Stage 1/4: Starting motor logger (quiet)..."
# IMPORTANT: setsid => process group leader (PGID == PID)
setsid python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" > /dev/null 2>&1 &
MOTOR_PID=$!
info "Motor logger started (PGID=${MOTOR_PID})."

# =========================
# Stage 2: Camera capture
# =========================
info "Stage 2/4: Starting camera capture..."
TMP_CAM_LOG="$(mktemp -p "$BASE_DIR" cam_tmp_XXXXXX.log)"

export EXPOSURE_TIME GAIN INTERVAL
export EXPOSURES_ROOT="$BASE_DIR"
export RUN_ID="$RUN_ID"

# IMPORTANT: setsid => process group leader (PGID == PID)
setsid bash "$CAMERA_SCRIPT" >"$TMP_CAM_LOG" 2>&1 &
CAM_PID=$!
info "Camera capture started (PGID=${CAM_PID})."

# Wait for our specific folder to appear
info "Waiting for exposure folder to be created: ${EXPOSURE_DIR}"
START_WAIT="$(date +%s)"
TIMEOUT_SEC=30
while [[ ! -d "$EXPOSURE_DIR" ]]; do
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

CAM_LOG="${EXPOSURE_DIR}/camera.log"
MOTOR_LOG="${EXPOSURE_DIR}/motor.log"

mv "$TMP_CAM_LOG" "$CAM_LOG"
tail -n +1 -f "$CAM_LOG" &
TAIL_PID=$!

# Save resolved config + command used (as .log)
python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}" --print-resolved > "${EXPOSURE_DIR}/run_config.log"
{
  echo "cwd: $(pwd)"
  echo "date: $(date -Is)"
  echo "command: $0 --config ${CONFIG_PATH} ${FORWARD_ARGS[*]}"
  echo "run_id: ${RUN_ID}"
} > "${EXPOSURE_DIR}/run_command.log"

# Restart motor logger but now log into exposure folder
if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  kill_pgrp INT "${MOTOR_PID}"
  wait "${MOTOR_PID}" 2>/dev/null || true
fi
setsid python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" >"$MOTOR_LOG" 2>&1 &
MOTOR_PID=$!
info "Motor logger restarted with log (PGID=${MOTOR_PID}): ${MOTOR_LOG}"

# Optional auto-stop timer
if awk "BEGIN{exit !(${ACQ_DURATION_S} > 0)}"; then
  info "Auto-stop enabled: will stop camera after ${ACQ_DURATION_S}s"
  (
    sleep "${ACQ_DURATION_S}"
    if kill -0 "${CAM_PID}" 2>/dev/null; then
      info "Auto-stop timer fired; stopping camera (SIGINT to PGID=${CAM_PID})..."
      kill_pgrp INT "${CAM_PID}"
    fi
  ) &
  TIMER_PID=$!
else
  info "Manual stop: press Ctrl+C to stop acquisition."
fi

wait "$CAM_PID" 2>/dev/null || true

# stop tail
if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
  kill "${TAIL_PID}" 2>/dev/null || true
  wait "${TAIL_PID}" 2>/dev/null || true
fi

sync || true

# stop motor
if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  info "Camera stopped; now stopping motor logger..."
  kill_pgrp INT "${MOTOR_PID}"
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

# =========================
# Stage 3: encoder pkl -> exposure folder
# =========================
info "Stage 3/4: Locating encoder pkl..."

ENCODER_PKL="$(ls -1t "$BASE_DIR"/encoder_data_*.pkl 2>/dev/null | head -n 1 || true)"
if [[ -z "$ENCODER_PKL" ]] || [[ ! -f "$ENCODER_PKL" ]]; then
  err "Could not find encoder_data_*.pkl in $BASE_DIR"
  ls -1 "$BASE_DIR"/*.pkl 2>/dev/null || true
  exit 1
fi
info "Using encoder file: ${ENCODER_PKL}"

mv -f "$ENCODER_PKL" "${EXPOSURE_DIR}/$(basename "$ENCODER_PKL")"
ENCODER_PKL="${EXPOSURE_DIR}/$(basename "$ENCODER_PKL")"
info "Moved encoder file into exposure folder: ${ENCODER_PKL}"

# =========================
# Stage 4: processing + plotting
# =========================
info "Stage 4/4: Processing .bin -> outputs..."

PROC_FLAGS=()
if [[ "$PROCESS_MAKE_COLOR" == "0" ]]; then PROC_FLAGS+=(--no-color); fi
if [[ "$PROCESS_MAKE_GREEN" == "0" ]]; then PROC_FLAGS+=(--no-green); fi
if [[ "$PROCESS_MAKE_FITS"  == "0" ]]; then PROC_FLAGS+=(--no-fits); fi
if [[ "$PROCESS_QUIET" == "1" ]]; then PROC_FLAGS+=(--quiet); fi
PROC_FLAGS+=(--jobs "$PROCESS_JOBS")

python3 "$PROCESS_SCRIPT" "$EXPOSURE_DIR" "${PROC_FLAGS[@]}"

PLOT_FLAGS=()
PLOT_FLAGS+=(--counts-per-rev "$PLOT_COUNTS_PER_REV")
PLOT_FLAGS+=(--roi-size "$PLOT_ROI_SIZE")
PLOT_FLAGS+=(--background-x "$PLOT_BG_X" --background-y "$PLOT_BG_Y")
if [[ "$PLOT_DEBUG" == "1" ]]; then PLOT_FLAGS+=(--debug); fi
if [[ -n "$PLOT_TIME_OFFSET_HOURS" ]]; then
  PLOT_FLAGS+=(--time-offset-hours "$PLOT_TIME_OFFSET_HOURS")
fi

python3 "$PLOT_SCRIPT" "${PLOT_FLAGS[@]}" "$EXPOSURE_DIR" "$ENCODER_PKL"

info "Done."
info "Outputs:"
info "  Exposure folder: ${EXPOSURE_DIR}"
info "  Logs:  ${EXPOSURE_DIR}/camera.log , ${EXPOSURE_DIR}/motor.log"
info "  Config: ${EXPOSURE_DIR}/run_config.log , ${EXPOSURE_DIR}/run_command.log"
info "  FITS:  ${EXPOSURE_DIR}/processed/fits/"
info "  Plots: ${EXPOSURE_DIR}/plots/"

# =========================
# Stage 5: Optional hard cleanup (raw .bin + processed FITS)
# =========================

CLEAN=1   # <-- set to 0 to disable cleanup

if [[ "$CLEAN" == "1" ]]; then
  info "Waiting 2 seconds before cleanup..."
  sleep 2

  info "Deleting raw bin directory: ${EXPOSURE_DIR}/raw"
  rm -rf "${EXPOSURE_DIR}/raw" || true

  info "Deleting processed FITS directory..."
  rm -rf "${EXPOSURE_DIR}/processed/fits" || true

  info "Cleanup complete."
fi
