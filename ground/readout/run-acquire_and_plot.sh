#!/usr/bin/env bash
set -euo pipefail

# =========================================
# End-to-end acquisition + processing + plot
# Location: ground/readout/run-acquire_and_plot.sh
# =========================================

# -------- Defaults (override via flags) --------
EXPOSURE_TIME="0.001"   # seconds
GAIN="100"
INTERVAL="0.0"          # seconds between exposures (0 = as fast as camera loop can go)
DURATION=""             # seconds to run; empty = run until Ctrl+C

NO_COLOR="--no-color"
NO_GREEN="--no-green"

# -------- Paths (auto-resolve relative to this script) --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MOTOR_SCRIPT="${GROUND_DIR}/motor/motor-spin-logger.py"
PROCESS_PY="${SCRIPT_DIR}/process-exposures-batch.py"
PLOT_PY="${SCRIPT_DIR}/create-plot.py"

# Camera binary: try a few likely names, but allow override with --camera-bin
CAMERA_BIN=""
for cand in \
  "${GROUND_DIR}/camera/capture-continuous.out" \
  "${GROUND_DIR}/camera/capture-exposure.out" \
  "${GROUND_DIR}/camera/build/capture-continuous.out" \
  "${GROUND_DIR}/camera/build/capture-exposure.out"
do
  if [[ -x "$cand" ]]; then
    CAMERA_BIN="$cand"
    break
  fi
done

# -------- State --------
EXPOSURE_DIR=""
RAW_DIR=""
MOTOR_PID=""
CAMERA_PID=""
MOTOR_LOG=""
START_EPOCH=""

# -------- Helpers --------
usage() {
  cat <<EOF
Usage:
  $(basename "$0") [options]

Options:
  --exposure-time SEC     Exposure time in seconds (default: ${EXPOSURE_TIME})
  --gain N                Gain value (default: ${GAIN})
  --interval SEC          Interval between captures in seconds (default: ${INTERVAL})
  --duration SEC          Run for SEC seconds then stop (default: Ctrl+C to stop)
  --camera-bin PATH       Path to camera continuous capture binary
  --keep-motor-log        Keep motor log file (default: kept anyway, but named)
  --debug-plot            Pass --debug into create-plot.py
  -h, --help              Show this help
EOF
}

log() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
err() { echo -e "[ERROR] $*" >&2; }

# Send SIGINT and wait for process to exit
stop_pid_sigint() {
  local pid="$1"
  local name="$2"

  if [[ -z "${pid}" ]]; then
    return 0
  fi
  if kill -0 "${pid}" 2>/dev/null; then
    log "Stopping ${name} (PID ${pid}) with SIGINT..."
    kill -INT "${pid}" 2>/dev/null || true
    # Wait up to ~5s gracefully, then SIGKILL
    for _ in {1..50}; do
      if ! kill -0 "${pid}" 2>/dev/null; then
        log "${name} stopped."
        return 0
      fi
      sleep 0.1
    done
    warn "${name} did not stop; sending SIGKILL..."
    kill -KILL "${pid}" 2>/dev/null || true
  fi
}

cleanup_on_exit() {
  # Must stop camera first, then motor (your requirement)
  stop_pid_sigint "${CAMERA_PID}" "camera capture"
  stop_pid_sigint "${MOTOR_PID}" "motor logger"
}
trap cleanup_on_exit INT TERM

DEBUG_PLOT="false"

# -------- Parse args --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --exposure-time) EXPOSURE_TIME="$2"; shift 2 ;;
    --gain) GAIN="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --camera-bin) CAMERA_BIN="$2"; shift 2 ;;
    --debug-plot) DEBUG_PLOT="true"; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# -------- Sanity checks --------
if [[ ! -f "${MOTOR_SCRIPT}" ]]; then
  err "Motor script not found: ${MOTOR_SCRIPT}"
  exit 1
fi
if [[ ! -x "${CAMERA_BIN}" ]]; then
  err "Camera binary not found/executable. Tried auto-detect; got: '${CAMERA_BIN}'"
  err "Pass --camera-bin /path/to/binary"
  exit 1
fi
if [[ ! -f "${PROCESS_PY}" ]]; then
  err "Missing: ${PROCESS_PY}"
  exit 1
fi
if [[ ! -f "${PLOT_PY}" ]]; then
  err "Missing: ${PLOT_PY}"
  exit 1
fi

# -------- Create exposure folder in readout/ --------
# exposures-YYYYMMDD-HHMMSS-mmm
TS="$(date +%Y%m%d-%H%M%S-$(date +%3N))"
EXPOSURE_DIR="${SCRIPT_DIR}/exposures-${TS}"
RAW_DIR="${EXPOSURE_DIR}/raw"
mkdir -p "${RAW_DIR}" "${EXPOSURE_DIR}/processed"

MOTOR_LOG="${EXPOSURE_DIR}/motor_logger.log"
START_EPOCH="$(date +%s)"

log "=== End-to-end acquisition starting ==="
log "Exposure dir: ${EXPOSURE_DIR}"
log "Raw dir:      ${RAW_DIR}"
log "Camera bin:   ${CAMERA_BIN}"
log "Motor script: ${MOTOR_SCRIPT}"
log "Params: exposure=${EXPOSURE_TIME}s gain=${GAIN} interval=${INTERVAL}s"
if [[ -n "${DURATION}" ]]; then
  log "Duration:     ${DURATION}s (auto-stop)"
else
  log "Duration:     until Ctrl+C"
fi
echo

# -------- Stage 1: start motor logger (suppressed output) --------
log "[1/4] Starting motor logger FIRST (output -> ${MOTOR_LOG})..."
# Run motor logger from its own directory so it writes encoder_data_*.pkl where it expects
(
  cd "${GROUND_DIR}/motor"
  # suppress stdout+stderr to log file
  python3 "${MOTOR_SCRIPT}" >"${MOTOR_LOG}" 2>&1
) &
MOTOR_PID="$!"
log "Motor logger PID: ${MOTOR_PID}"
sleep 0.2

# -------- Stage 2: start camera capture (visible output) --------
log "[2/4] Starting camera capture (visible output). Press Ctrl+C to stop."
# Run in background but keep output attached to terminal
"${CAMERA_BIN}" \
  --output-dir "${RAW_DIR}" \
  --exposure-time "${EXPOSURE_TIME}" \
  --gain "${GAIN}" \
  --interval "${INTERVAL}" &
CAMERA_PID="$!"
log "Camera PID: ${CAMERA_PID}"
echo

# -------- Run duration / wait --------
if [[ -n "${DURATION}" ]]; then
  log "Running for ${DURATION}s..."
  sleep "${DURATION}"
  log "Duration reached; stopping..."
  cleanup_on_exit
else
  # Wait until camera exits or user Ctrl+C
  wait "${CAMERA_PID}" || true
  # If camera exits on its own, stop motor too
  cleanup_on_exit
fi

echo
log "Capture stopped. Proceeding to processing..."

# -------- Stage 3: Process bin -> fits (no png previews) --------
log "[3/4] Processing .bin -> .fits (no color/green previews)..."
log "Command: python3 ${PROCESS_PY} \"${EXPOSURE_DIR}\" ${NO_COLOR} ${NO_GREEN}"
python3 "${PROCESS_PY}" "${EXPOSURE_DIR}" ${NO_COLOR} ${NO_GREEN}
echo

# -------- Locate newest encoder pkl produced during this run --------
log "Locating encoder .pkl created by this run..."

# Pick newest encoder_data_*.pkl modified AFTER we started (with some slack)
# If none match, fall back to newest overall.
PKL_CANDIDATES=()
while IFS= read -r -d '' f; do PKL_CANDIDATES+=("$f"); done < <(
  find "${GROUND_DIR}/motor" -maxdepth 1 -type f -name "encoder_data_*.pkl" -print0
)

if [[ ${#PKL_CANDIDATES[@]} -eq 0 ]]; then
  err "No encoder_data_*.pkl found in ${GROUND_DIR}/motor"
  err "Check motor logger output: ${MOTOR_LOG}"
  exit 1
fi

# Prefer pkls newer than START_EPOCH-5
CUTOFF=$((START_EPOCH - 5))
NEWEST_PKL="$(ls -t "${GROUND_DIR}/motor"/encoder_data_*.pkl | head -n 1)"

NEWEST_AFTER_CUTOFF="$(find "${GROUND_DIR}/motor" -maxdepth 1 -type f -name "encoder_data_*.pkl" -newermt "@${CUTOFF}" -printf "%T@ %p\n" \
  | sort -nr | head -n 1 | awk '{print $2}')"

if [[ -n "${NEWEST_AFTER_CUTOFF}" ]]; then
  ENCODER_PKL="${NEWEST_AFTER_CUTOFF}"
else
  warn "No encoder .pkl newer than start time; falling back to newest overall."
  ENCODER_PKL="${NEWEST_PKL}"
fi

log "Using encoder file: ${ENCODER_PKL}"
echo

# -------- Stage 4: Create plots (with fit overlay etc.) --------
log "[4/4] Creating plots..."
PLOT_ARGS=()
if [[ "${DEBUG_PLOT}" == "true" ]]; then
  PLOT_ARGS+=(--debug)
fi

log "Command: python3 ${PLOT_PY} ${PLOT_ARGS[*]:-} \"${EXPOSURE_DIR}\" \"${ENCODER_PKL}\""
python3 "${PLOT_PY}" "${PLOT_ARGS[@]}" "${EXPOSURE_DIR}" "${ENCODER_PKL}"

echo
log "=== Done ==="
log "Exposure folder: ${EXPOSURE_DIR}"
log "Motor log:       ${MOTOR_LOG}"
log "Plots:           ${EXPOSURE_DIR}/plots"