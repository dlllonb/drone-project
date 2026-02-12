#!/usr/bin/env bash
set -euo pipefail

# =========================
# Run-end-to-end script (BASE DIR)
# Place this file in: ground/   (one level above readout/)
#
# Layout assumed:
#   ground/
#     run-end-to-end.sh          <-- this script
#     config.yml
#     load-config.py
#     readout/
#       continuous-capture.sh
#       process-exposures-batch.py
#       create-plot.py
#     motor/
#       motor-spin-logger.py
# =========================

# Resolve absolute base dir where this script lives (ground/)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

# --- Scripts (absolute paths) ---
MOTOR_SCRIPT="$BASE_DIR/motor/motor-spin-logger.py"
CAMERA_SCRIPT="$BASE_DIR/readout/continuous-capture.sh"
PROCESS_SCRIPT="$BASE_DIR/readout/process-exposures-batch.py"
PLOT_SCRIPT="$BASE_DIR/readout/create-plot.py"
LOAD_CONFIG="$BASE_DIR/load-config.py"

# --- Runtime state ---
MOTOR_PID=""
CAM_PID=""
TAIL_PID=""
RUN_START_EPOCH="$(date +%s)"

EXPOSURE_DIR=""   # full path to exposures-*
CAM_LOG=""
MOTOR_LOG=""

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

# Send a signal to an entire process group (more robust than a single PID).
# This matters because continuous-capture.sh often spawns child processes.
kill_pgrp() {
  local sig="$1"
  local pid="$2"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "-${sig}" -- "-${pid}" 2>/dev/null || true
  fi
}


cleanup_and_exit() {
  echo
  info "Stopping acquisition (camera first, then motor)..."

  # Stop tail first (reduces terminal noise)
  if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
  fi

  # # Stop camera first
  # if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
  #   info "Sending SIGINT to camera capture (PID=${CAM_PID})..."
  #   kill -INT "${CAM_PID}" 2>/dev/null || true
  #   wait "${CAM_PID}" 2>/dev/null || true
  # fi

    # Stop camera first (signal process group so children stop too)
  if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
    info "Sending SIGINT to camera capture process group (PGID=${CAM_PID})..."
    kill_pgrp INT "${CAM_PID}"
    wait "${CAM_PID}" 2>/dev/null || true
  fi

  # # Then stop motor
  # if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  #   info "Sending SIGINT to motor logger (PID=${MOTOR_PID})..."
  #   kill -INT "${MOTOR_PID}" 2>/dev/null || true
  #   wait "${MOTOR_PID}" 2>/dev/null || true
  # fi

    # Then stop motor
    # Then stop motor (also as process group for consistency)
  if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
    info "Sending SIGINT to motor logger process group (PGID=${MOTOR_PID})..."
    kill_pgrp INT "${MOTOR_PID}"
    wait "${MOTOR_PID}" 2>/dev/null || true
  fi



  info "Stopped."
}
trap cleanup_and_exit INT TERM

# ---- args: --config + overrides forwarded to load-config.py ----
CONFIG_PATH="$BASE_DIR/config.yml"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    *)
      # forward anything else to load-config.py (e.g. --gain 50)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

# normalize config path to absolute if user passed relative
if [[ "$CONFIG_PATH" != /* ]]; then
  CONFIG_PATH="$BASE_DIR/$CONFIG_PATH"
fi

# ---- Sanity checks ----
for f in "$MOTOR_SCRIPT" "$CAMERA_SCRIPT" "$PROCESS_SCRIPT" "$PLOT_SCRIPT" "$LOAD_CONFIG" "$CONFIG_PATH"; do
  if [[ ! -e "$f" ]]; then
    err "Missing required file: $f"
    exit 1
  fi
done

# ---- Load config -> export env vars ----
info "Loading config: ${CONFIG_PATH}"
eval "$(python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}")"

# Provide defaults here too (extra safety)
EXPOSURE_TIME="${EXPOSURE_TIME:-0.001}"
GAIN="${GAIN:-100}"
INTERVAL="${INTERVAL:-0.001}"
GROUND_PATH="${GROUND_PATH:-$BASE_DIR/}"            # base dir of ground repo
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

info "Resolved acquisition: exposure=${EXPOSURE_TIME}s gain=${GAIN} interval=${INTERVAL}s"
info "Resolved motor: ground_path=${GROUND_PATH} spin_rate=${SPIN_RATE}"
info "Resolved processing: jobs=${PROCESS_JOBS} fits=${PROCESS_MAKE_FITS} color=${PROCESS_MAKE_COLOR} green=${PROCESS_MAKE_GREEN} quiet=${PROCESS_QUIET}"
info "Resolved plotting: counts_per_rev=${PLOT_COUNTS_PER_REV} roi_size=${PLOT_ROI_SIZE} bg=(${PLOT_BG_X},${PLOT_BG_Y}) debug=${PLOT_DEBUG} time_offset_hours=${PLOT_TIME_OFFSET_HOURS}"

# =========================
# Stage 1: Motor logger
# =========================
info "Stage 1/4: Starting motor logger (quiet)..."
python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" > /dev/null 2>&1 &
MOTOR_PID=$!
info "Motor logger started (PID=${MOTOR_PID})."

# =========================
# Stage 2: Camera capture
# =========================
info "Stage 2/4: Starting camera capture..."
TMP_CAM_LOG="$(mktemp -p "$BASE_DIR" cam_tmp_XXXXXX.log)"

# Ensure exposures-* is created OUTSIDE readout/, in BASE_DIR
export EXPOSURE_TIME GAIN INTERVAL
export EXPOSURES_ROOT="$BASE_DIR"

bash "$CAMERA_SCRIPT" >"$TMP_CAM_LOG" 2>&1 &
CAM_PID=$!
info "Camera capture started (PID=${CAM_PID})."

# Wait for the exposure folder to appear (created by continuous-capture.sh)
info "Waiting for exposures-* folder to be created in ${BASE_DIR} ..."
START_WAIT="$(date +%s)"
TIMEOUT_SEC=30

while true; do
  # newest exposures-* directory in BASE_DIR
  found="$(ls -1dt "$BASE_DIR"/exposures-* 2>/dev/null | head -n 1 || true)"
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

# Logs inside exposure folder
CAM_LOG="${EXPOSURE_DIR}/camera.log"
MOTOR_LOG="${EXPOSURE_DIR}/motor.log"

# Move temp cam log into exposure folder and start following it
mv "$TMP_CAM_LOG" "$CAM_LOG"
tail -n +1 -f "$CAM_LOG" &
TAIL_PID=$!

# Save resolved config + command used (for reproducibility) AS .log files
python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}" --print-resolved > "${EXPOSURE_DIR}/run_config.log"
{
  echo "cwd: $(pwd)"
  echo "date: $(date -Is)"
  echo "command: $0 --config ${CONFIG_PATH} ${FORWARD_ARGS[*]}"
} > "${EXPOSURE_DIR}/run_command.log"

# Restart motor logger but now log into exposure folder
if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  kill -INT "${MOTOR_PID}" 2>/dev/null || true
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" >"$MOTOR_LOG" 2>&1 &
MOTOR_PID=$!
info "Motor logger restarted with log: ${MOTOR_LOG}"
sleep 1.0

info "Capture running. Press Ctrl+C to stop (camera stops first)."
wait "$CAM_PID" 2>/dev/null || true

# Camera ended; stop tail; then stop motor (if still running)
if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
  kill "${TAIL_PID}" 2>/dev/null || true
  wait "${TAIL_PID}" 2>/dev/null || true
fi

sleep 1.0
sync || true

# if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
#   info "Camera stopped; now stopping motor logger..."
#   kill -INT "${MOTOR_PID}" 2>/dev/null || true
#   wait "${MOTOR_PID}" 2>/dev/null || true
# fi

if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  info "Camera stopped; now stopping motor logger..."
  kill_pgrp INT "${MOTOR_PID}"
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

# =========================
# Stage 3: Find encoder pkl and move into exposure folder
# =========================
info "Stage 3/4: Locating exposure folder + encoder pkl..."

# Re-resolve exposure dir (newest) as a safety net
# EXPOSURE_DIR="$(ls -1dt "$BASE_DIR"/exposures-* 2>/dev/null | head -n 1 || true)"
# if [[ -z "$EXPOSURE_DIR" ]] || [[ ! -d "$EXPOSURE_DIR" ]]; then
#   err "Could not find an exposures-* directory in $BASE_DIR"
#   exit 1
# fi
# info "Using exposure folder: ${EXPOSURE_DIR}"

# Use the exposure folder we already discovered during capture
if [[ -z "${EXPOSURE_DIR}" ]] || [[ ! -d "${EXPOSURE_DIR}" ]]; then
  err "Exposure folder variable EXPOSURE_DIR is not set or missing. Something went wrong earlier."
  exit 1
fi
info "Using exposure folder: ${EXPOSURE_DIR}"


# encoder pkl is saved to BASE_DIR (we cd'ed there at top)
#ENCODER_PKL="$(ls -1t "$BASE_DIR"/encoder_data_*.pkl 2>/dev/null | head -n 1 || true)"
sleep 1.0
sync || true
ENCODER_PKL="$(find "$BASE_DIR" -maxdepth 1 -type f -name 'encoder_data_*.pkl' -newermt "@${RUN_START_EPOCH}" 2>/dev/null | xargs -r ls -1t 2>/dev/null | head -n 1 || true)"
if [[ -z "$ENCODER_PKL" ]] || [[ ! -f "$ENCODER_PKL" ]]; then
  err "Could not find encoder_data_*.pkl in $BASE_DIR"
  err "Files in $BASE_DIR matching *.pkl:"
  ls -1 "$BASE_DIR"/*.pkl 2>/dev/null || true
  exit 1
fi
info "Using encoder file: ${ENCODER_PKL}"

# Move encoder pkl into exposure folder (single source of truth)
mv -f "$ENCODER_PKL" "${EXPOSURE_DIR}/$(basename "$ENCODER_PKL")"
ENCODER_PKL="${EXPOSURE_DIR}/$(basename "$ENCODER_PKL")"
info "Moved encoder file into exposure folder: ${ENCODER_PKL}"

# =========================
# Stage 4: Processing + plotting
# =========================
info "Stage 4/4: Processing .bin -> outputs..."

# Build processing flags based on config booleans
PROC_FLAGS=()
if [[ "$PROCESS_MAKE_COLOR" == "0" ]]; then PROC_FLAGS+=(--no-color); fi
if [[ "$PROCESS_MAKE_GREEN" == "0" ]]; then PROC_FLAGS+=(--no-green); fi
if [[ "$PROCESS_MAKE_FITS"  == "0" ]]; then PROC_FLAGS+=(--no-fits); fi
if [[ "$PROCESS_QUIET" == "1" ]]; then PROC_FLAGS+=(--quiet); fi
PROC_FLAGS+=(--jobs "$PROCESS_JOBS")

python3 "$PROCESS_SCRIPT" "$EXPOSURE_DIR" "${PROC_FLAGS[@]}"

# Plot flags
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