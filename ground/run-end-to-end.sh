#!/usr/bin/env bash
set -euo pipefail

# ===============================================
# Run-end-to-end script (BASE DIR)
# Place this file in: ground/
#
# Modes:
#   --mode full          : acquire + process   (default)
#   --mode acquire-only  : acquire only
#   --mode process-only  : process existing exposure folder
#
# Examples:
#   ./run-end-to-end.sh --config config.yml
#   ./run-end-to-end.sh --mode acquire-only --duration-s 120
#   ./run-end-to-end.sh --mode full --output-root ./campaign-20260319/run_001
#   ./run-end-to-end.sh --mode process-only --exposure-dir ./campaign-20260319/run_001/exposures-...
#
# To run detached from SSH connection:
#   tmux new -s polarimeter
#   ./run-end-to-end.sh --config config.yml
#   Ctrl+b then d
#
#   Or:
#   nohup ./run-end-to-end.sh --config config.yml >/dev/null 2>&1 & disown
# ===============================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

MOTOR_SCRIPT="$BASE_DIR/motor/motor-spin-logger.py"
CAMERA_SCRIPT="$BASE_DIR/readout/continuous-capture.sh"
PROCESS_SCRIPT="$BASE_DIR/readout/process-exposures-batch.py"
PLOT_SCRIPT="$BASE_DIR/readout/create-plot.py"
LOAD_CONFIG="$BASE_DIR/load-config.py"
ANIMATION_SCRIPT="$BASE_DIR/readout/create-animation.py"

# Runtime state
MODE="full"
OUTPUT_ROOT="$BASE_DIR"
EXPOSURE_DIR_ARG=""

MOTOR_PID=""
CAM_PID=""
TAIL_PID=""
TIMER_PID=""

EXPOSURE_DIR=""
CAM_LOG=""
MOTOR_LOG=""
ENCODER_PKL=""

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

usage() {
  cat <<EOF
Usage:
  ./run-end-to-end.sh [options] [-- <config overrides>]

Options:
  --config PATH           Path to config.yml
  --mode MODE             full | acquire-only | process-only
  --output-root PATH      Root directory where a new exposures-* folder will be created
                          (used by full and acquire-only)
  --exposure-dir PATH     Existing exposures-* directory to process
                          (required for process-only)

Examples:
  ./run-end-to-end.sh --config config.yml
  ./run-end-to-end.sh --mode acquire-only --duration-s 60
  ./run-end-to-end.sh --mode full --output-root ./campaign-20260319/run_001
  ./run-end-to-end.sh --mode process-only --exposure-dir ./campaign-20260319/run_001/exposures-20260319-...
EOF
}

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

  if [[ -n "${TIMER_PID}" ]] && kill -0 "${TIMER_PID}" 2>/dev/null; then
    kill "${TIMER_PID}" 2>/dev/null || true
    wait "${TIMER_PID}" 2>/dev/null || true
  fi

  if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
  fi

  if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
    info "Sending SIGINT to camera capture process group (PGID=${CAM_PID})..."
    kill_pgrp INT "${CAM_PID}"
    wait "${CAM_PID}" 2>/dev/null || true
  fi

  if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
    info "Sending SIGINT to motor logger process group (PGID=${MOTOR_PID})..."
    kill_pgrp INT "${MOTOR_PID}"
    wait "${MOTOR_PID}" 2>/dev/null || true
  fi

  info "Stopped."
}
trap cleanup_and_exit INT TERM

CONFIG_PATH="$BASE_DIR/config.yml"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --output-root)
      OUTPUT_ROOT="${2:-}"
      shift 2
      ;;
    --exposure-dir)
      EXPOSURE_DIR_ARG="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
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
if [[ "$OUTPUT_ROOT" != /* ]]; then
  OUTPUT_ROOT="$BASE_DIR/$OUTPUT_ROOT"
fi
if [[ -n "$EXPOSURE_DIR_ARG" && "$EXPOSURE_DIR_ARG" != /* ]]; then
  EXPOSURE_DIR_ARG="$BASE_DIR/$EXPOSURE_DIR_ARG"
fi

case "$MODE" in
  full|acquire-only|process-only) ;;
  *)
    err "Invalid mode: $MODE"
    usage
    exit 1
    ;;
esac

if [[ "$MODE" == "process-only" && -z "$EXPOSURE_DIR_ARG" ]]; then
  err "--exposure-dir is required for --mode process-only"
  exit 1
fi

for f in "$PROCESS_SCRIPT" "$PLOT_SCRIPT" "$LOAD_CONFIG" "$CONFIG_PATH" "$ANIMATION_SCRIPT"; do
  if [[ ! -e "$f" ]]; then
    err "Missing required file: $f"
    exit 1
  fi
done

if [[ "$MODE" != "process-only" ]]; then
  for f in "$MOTOR_SCRIPT" "$CAMERA_SCRIPT"; do
    if [[ ! -e "$f" ]]; then
      err "Missing required file: $f"
      exit 1
    fi
  done
fi

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
PROCESS_CLEANUP_AFTER="${PROCESS_CLEANUP_AFTER:-0}"

PLOT_COUNTS_PER_REV="${PLOT_COUNTS_PER_REV:-2400}"
PLOT_DEBUG="${PLOT_DEBUG:-0}"
PLOT_TIME_OFFSET_HOURS="${PLOT_TIME_OFFSET_HOURS:-}"
PLOT_SAVE_ROI_OVERLAYS="${PLOT_SAVE_ROI_OVERLAYS:-0}"
PLOT_MAKE_ROI_GIF="${PLOT_MAKE_ROI_GIF:-0}"

ACQ_DURATION_S="${ACQ_DURATION_S:-0}"

if [[ "$PLOT_MAKE_ROI_GIF" == "1" && "$PLOT_SAVE_ROI_OVERLAYS" != "1" ]]; then
  warn "make_roi_gif=1 requires save_roi_overlays=1; enabling ROI overlays automatically."
  PLOT_SAVE_ROI_OVERLAYS="1"
fi

info "Resolved mode: ${MODE}"
info "Resolved acquisition: exposure=${EXPOSURE_TIME}s gain=${GAIN} interval=${INTERVAL}s duration_s=${ACQ_DURATION_S}"
info "Resolved motor: ground_path=${GROUND_PATH} spin_rate=${SPIN_RATE}"
info "Resolved processing: jobs=${PROCESS_JOBS} fits=${PROCESS_MAKE_FITS} color=${PROCESS_MAKE_COLOR} green=${PROCESS_MAKE_GREEN} quiet=${PROCESS_QUIET} cleanup_after=${PROCESS_CLEANUP_AFTER}"
info "Resolved plotting: counts_per_rev=${PLOT_COUNTS_PER_REV} debug=${PLOT_DEBUG} time_offset_hours=${PLOT_TIME_OFFSET_HOURS} save_roi_overlays=${PLOT_SAVE_ROI_OVERLAYS} make_roi_gif=${PLOT_MAKE_ROI_GIF}"

save_acquisition_logs() {
  python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}" --print-resolved > "${EXPOSURE_DIR}/run_config.log"
  {
    echo "cwd: $(pwd)"
    echo "date: $(date -Is)"
    echo "command: $0 --config ${CONFIG_PATH} --mode ${MODE} --output-root ${OUTPUT_ROOT} ${FORWARD_ARGS[*]}"
    echo "mode: ${MODE}"
    echo "output_root: ${OUTPUT_ROOT}"
    echo "run_id: ${RUN_ID}"
  } > "${EXPOSURE_DIR}/run_command.log"
}

save_process_logs() {
  python3 "$LOAD_CONFIG" --config "$CONFIG_PATH" "${FORWARD_ARGS[@]}" --print-resolved > "${EXPOSURE_DIR}/process_config.log"
  {
    echo "cwd: $(pwd)"
    echo "date: $(date -Is)"
    echo "command: $0 --config ${CONFIG_PATH} --mode ${MODE} --exposure-dir ${EXPOSURE_DIR} ${FORWARD_ARGS[*]}"
    echo "mode: ${MODE}"
    echo "exposure_dir: ${EXPOSURE_DIR}"
  } > "${EXPOSURE_DIR}/process_command.log"
}

run_processing_stage() {
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
  if [[ "$PLOT_DEBUG" == "1" ]]; then PLOT_FLAGS+=(--debug); fi
  if [[ -n "$PLOT_TIME_OFFSET_HOURS" ]]; then
    PLOT_FLAGS+=(--time-offset-hours "$PLOT_TIME_OFFSET_HOURS")
  fi
  if [[ "$PLOT_SAVE_ROI_OVERLAYS" == "1" ]]; then
    PLOT_FLAGS+=(--save-roi-overlays)
  fi

  python3 "$PLOT_SCRIPT" "${PLOT_FLAGS[@]}" "$EXPOSURE_DIR" "$ENCODER_PKL"

  if [[ "$PLOT_MAKE_ROI_GIF" == "1" ]]; then
    info "Creating ROI tracking GIF..."
    ROI_OVERLAY_DIR="$EXPOSURE_DIR/plots/roi_overlays"
    ROI_GIF_PATH="$EXPOSURE_DIR/roi_tracking.gif"

    if [[ -d "$ROI_OVERLAY_DIR" ]]; then
      python3 "$ANIMATION_SCRIPT" \
        --input-dir "$ROI_OVERLAY_DIR" \
        --output "$ROI_GIF_PATH"
    else
      warn "ROI overlay directory not found: $ROI_OVERLAY_DIR"
      warn "Skipping ROI GIF creation."
    fi
  fi

  info "Done."
  info "Outputs:"
  info "  Exposure folder: ${EXPOSURE_DIR}"
  info "  Logs:  ${EXPOSURE_DIR}/camera.log , ${EXPOSURE_DIR}/motor.log"
  if [[ "$MODE" == "process-only" ]]; then
    info "  Process logs: ${EXPOSURE_DIR}/process_config.log , ${EXPOSURE_DIR}/process_command.log"
  else
    info "  Config: ${EXPOSURE_DIR}/run_config.log , ${EXPOSURE_DIR}/run_command.log"
  fi
  info "  FITS:  ${EXPOSURE_DIR}/processed/fits/"
  info "  Plots: ${EXPOSURE_DIR}/plots/"
  if [[ "$PLOT_MAKE_ROI_GIF" == "1" ]]; then
    info "  ROI GIF: ${EXPOSURE_DIR}/roi_tracking.gif"
  fi

  if [[ "$PROCESS_CLEANUP_AFTER" == "1" ]]; then
    info "Waiting 2 seconds before cleanup..."
    sleep 2

    info "Deleting raw bin directory: ${EXPOSURE_DIR}/raw"
    rm -rf "${EXPOSURE_DIR}/raw" || true

    info "Deleting processed FITS directory..."
    rm -rf "${EXPOSURE_DIR}/processed/fits" || true

    info "Cleanup complete."
  fi
}

# ==========================================================
# MODE: process-only
# ==========================================================
if [[ "$MODE" == "process-only" ]]; then
  EXPOSURE_DIR="$EXPOSURE_DIR_ARG"

  if [[ ! -d "$EXPOSURE_DIR" ]]; then
    err "Exposure directory does not exist: $EXPOSURE_DIR"
    exit 1
  fi

  ENCODER_PKL="$(ls -1t "$EXPOSURE_DIR"/encoder_data_*.pkl 2>/dev/null | head -n 1 || true)"
  if [[ -z "$ENCODER_PKL" ]] || [[ ! -f "$ENCODER_PKL" ]]; then
    err "Could not find encoder_data_*.pkl in $EXPOSURE_DIR"
    exit 1
  fi

  info "Processing existing exposure folder: ${EXPOSURE_DIR}"
  info "Using encoder file: ${ENCODER_PKL}"

  save_process_logs
  run_processing_stage
  exit 0
fi

# ==========================================================
# MODES: full / acquire-only
# ==========================================================
mkdir -p "$OUTPUT_ROOT"

RUN_ID="$(date +%Y%m%d-%H%M%S-$(date +%3N))_$$"
EXPOSURE_DIR="$OUTPUT_ROOT/exposures-$RUN_ID"
info "This run folder will be: ${EXPOSURE_DIR}"

info "Stage 1/4: Starting motor logger (quiet)..."
setsid python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" > /dev/null 2>&1 &
MOTOR_PID=$!
info "Motor logger started (PGID=${MOTOR_PID})."

info "Stage 2/4: Starting camera capture..."
TMP_CAM_LOG="$(mktemp -p "$BASE_DIR" cam_tmp_XXXXXX.log)"

export EXPOSURE_TIME GAIN INTERVAL
export EXPOSURES_ROOT="$OUTPUT_ROOT"
export RUN_ID="$RUN_ID"

setsid bash "$CAMERA_SCRIPT" >"$TMP_CAM_LOG" 2>&1 &
CAM_PID=$!
info "Camera capture started (PGID=${CAM_PID})."

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

save_acquisition_logs

if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  kill_pgrp INT "${MOTOR_PID}"
  wait "${MOTOR_PID}" 2>/dev/null || true
fi
setsid python3 -u "$MOTOR_SCRIPT" --ground-path "$GROUND_PATH" --spin-rate "$SPIN_RATE" >"$MOTOR_LOG" 2>&1 &
MOTOR_PID=$!
info "Motor logger restarted with log (PGID=${MOTOR_PID}): ${MOTOR_LOG}"

if awk "BEGIN{exit !(${ACQ_DURATION_S} > 0)}"; then
  info "Auto-stop enabled: will stop camera after ${ACQ_DURATION_S}s"
  (
    sleep "${ACQ_DURATION_S}"
    if kill -0 "${CAM_PID}" 2>/dev/null; then
      echo "[INFO] Auto-stop timer fired; stopping camera (SIGINT to PGID=${CAM_PID})..."
      kill -INT -- "-${CAM_PID}" 2>/dev/null || true
    fi
  ) &
  TIMER_PID=$!
else
  info "Manual stop: press Ctrl+C to stop acquisition."
fi

wait "$CAM_PID" 2>/dev/null || true

if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
  kill "${TAIL_PID}" 2>/dev/null || true
  wait "${TAIL_PID}" 2>/dev/null || true
fi

sync || true

if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
  info "Camera stopped; now stopping motor logger..."
  kill_pgrp INT "${MOTOR_PID}"
  wait "${MOTOR_PID}" 2>/dev/null || true
fi

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

if [[ "$MODE" == "acquire-only" ]]; then
  info "Acquire-only mode complete."
  info "Outputs:"
  info "  Exposure folder: ${EXPOSURE_DIR}"
  info "  Logs:  ${EXPOSURE_DIR}/camera.log , ${EXPOSURE_DIR}/motor.log"
  info "  Config: ${EXPOSURE_DIR}/run_config.log , ${EXPOSURE_DIR}/run_command.log"
  info "  Encoder: ${ENCODER_PKL}"
  exit 0
fi

run_processing_stage