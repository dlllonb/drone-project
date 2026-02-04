#!/usr/bin/env bash
set -euo pipefail

# Run from readout/ no matter where invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MOTOR_SCRIPT="../motor/motor-spin-logger.py"
CAMERA_SCRIPT="./continuous-capture.sh"
PROCESS_SCRIPT="./process-exposures-batch.py"
PLOT_SCRIPT="./create-plot.py"
LOAD_CONFIG="./load-config.py"

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

  if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
  fi

  if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
    info "Sending SIGINT to camera capture (PID=${CAM_PID})..."
    kill -INT "${CAM_PID}" 2>/dev/null || true
    wait "${CAM_PID}" 2>/dev/null || true
  fi

  if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
    info "Sending SIGINT to motor logger (PID=${MOTOR_PID})..."
    kill -INT "${MOTOR_PID}" 2>/dev/null || true
    wait "${MOTOR_PID}" 2>/dev/null || true
  fi

  info "Stopped."
}
trap cleanup_and_exit INT TERM

# ---- args: --config + overrides forwarded to load_config.py ----
CONFIG_PATH="config.yml"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    *)
      # forward anything else to load_config.py (e.g. --gain 50)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

# ---- Sanity checks ----
for f in "$MOTOR_SCRIPT" "$CAMERA_SCRIPT" "$PROCESS_SCRIPT" "$PLOT_SCRIPT" "$LOAD_CONFIG"; do
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
GROUND_PATH="${GROUND_PATH:-/home/declan/drone-project/ground/}"
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

info "Stage 1/4: Starting motor logger (quiet)..."
python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" > /dev/null 2>&1 &
MOTOR_PID=$!
info "Motor logger started (PID=${MOTOR_PID})."

info "Stage 2/4: Starting camera capture..."
TMP_CAM_LOG="$(mktemp -p "$SCRIPT_DIR" cam_tmp_XXXXXX.log)"

# camera script reads EXPOSURE_TIME/GAIN/INTERVAL env vars; export them
export EXPOSURE_TIME GAIN INTERVAL
bash "$CAMERA_SCRIPT" >"$TMP_CAM_LOG" 2>&1 &
CAM_PID=$!
info "Camera capture started (PID=${CAM_PID})."

info "Waiting for exposures-* folder to be created..."
START_WAIT="$(date +%s)"
TIMEOUT_SEC=30

while true; do
  found="$(ls -1dt exposures-* 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" && -d "$found" ]]; then
    EXPOSURE_DIR="$found"
    break
  fi

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

mv "$TMP_CAM_LOG" "$CAM_LOG"
tail -n +1 -f "$CAM_LOG" &
TAIL_PID=$!

# Save the resolved config + command used (for reproducibility)
python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}" --print-resolved > "${EXPOSURE_DIR}/run_config.yaml"
{
  echo "cwd: $(pwd)"
  echo "date: $(date -Is)"
  echo "command: $0 --config ${CONFIG_PATH} ${FORWARD_ARGS[*]}"
} > "${EXPOSURE_DIR}/run_command.txt"

# Restart motor logger but log into exposure folder
if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  kill -INT "${MOTOR_PID}" 2>/dev/null || true
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" >"$MOTOR_LOG" 2>&1 &
MOTOR_PID=$!
info "Motor logger restarted with log: ${MOTOR_LOG}"

info "Capture running. Press Ctrl+C to stop (camera stops first)."
wait "$CAM_PID" 2>/dev/null || true

# Stop tail
if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
  kill "${TAIL_PID}" 2>/dev/null || true
  wait "${TAIL_PID}" 2>/dev/null || true
fi

# Stop motor logger
if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  info "Camera stopped; now stopping motor logger..."
  kill -INT "${MOTOR_PID}" 2>/dev/null || true
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

info "Stage 3/4: Locating exposure folder + encoder pkl (searching in readout/)..."

EXPOSURE_DIR="$(ls -1dt exposures-* 2>/dev/null | head -n 1 || true)"
if [[ -z "$EXPOSURE_DIR" ]] || [[ ! -d "$EXPOSURE_DIR" ]]; then
  err "Could not find an exposures-* directory in $SCRIPT_DIR"
  exit 1
fi
info "Using exposure folder: ${EXPOSURE_DIR}"

ENCODER_PKL="$(ls -1t encoder_data_*.pkl 2>/dev/null | head -n 1 || true)"
if [[ -z "$ENCODER_PKL" ]] || [[ ! -f "$ENCODER_PKL" ]]; then
  err "Could not find encoder_data_*.pkl in readout/"
  ls -1 *.pkl 2>/dev/null || true
  exit 1
fi
info "Using encoder file: ${ENCODER_PKL}"

mv -f "$ENCODER_PKL" "${EXPOSURE_DIR}/$(basename "$ENCODER_PKL")"
ENCODER_PKL="${EXPOSURE_DIR}/$(basename "$ENCODER_PKL")"
info "Moved encoder file into exposure folder: ${ENCODER_PKL}"

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
info "  Logs:  ${EXPOSURE_DIR}/camera.log , ${EXPOSURE_DIR}/motor.log"
info "  Config: ${EXPOSURE_DIR}/run_config.yaml , ${EXPOSURE_DIR}/run_command.txt"
info "  FITS:  ${EXPOSURE_DIR}/processed/fits/"
info "  Plots: ${EXPOSURE_DIR}/plots/"