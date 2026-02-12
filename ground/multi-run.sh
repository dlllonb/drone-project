#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run-n.sh [N] [DURATION_SEC] [-- <args forwarded to run-end-to-end.sh>]
#
# Examples:
#   ./run-n.sh                         # defaults: N=5, DURATION=60
#   ./run-n.sh 10 60                   # 10 runs, 60s each
#   ./run-n.sh 3 90 -- --gain 80       # 3 runs, 90s each, forward overrides
#   ./run-n.sh 2 60 -- --config my.yml # custom config

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$BASE_DIR/run-end-to-end.sh"

N="${1:-5}"
DURATION_SEC="${2:-60}"
shift $(( $# >= 1 ? 1 : 0 ))
shift $(( $# >= 1 ? 1 : 0 ))

FORWARD_ARGS=()
if [[ $# -gt 0 ]]; then
  if [[ "${1:-}" == "--" ]]; then
    shift
    FORWARD_ARGS=("$@")
  else
    FORWARD_ARGS=("$@")
  fi
fi

if [[ ! -x "$RUN_SCRIPT" ]]; then
  echo "[ERR ] Missing or not executable: $RUN_SCRIPT" >&2
  exit 1
fi

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

RUN_PID=""

cleanup() {
  if [[ -n "${RUN_PID}" ]] && kill -0 "${RUN_PID}" 2>/dev/null; then
    warn "Aborting: sending SIGINT to current run process group (PGID=${RUN_PID})..."
    kill -INT -- "-${RUN_PID}" 2>/dev/null || true
    wait "${RUN_PID}" 2>/dev/null || true
  fi
}
trap cleanup INT TERM

for ((i=1; i<=N; i++)); do
  info "========== Run ${i}/${N} =========="
  info "Starting: $RUN_SCRIPT ${FORWARD_ARGS[*]}"

  # Start one end-to-end run
  "$RUN_SCRIPT" "${FORWARD_ARGS[@]}" &
  RUN_PID=$!

  # Let acquisition run for fixed duration
  info "Acquiring for ${DURATION_SEC}s (PID=${RUN_PID})..."
  sleep "${DURATION_SEC}"

  # Stop acquisition (Ctrl+C equivalent)
    info "Stopping acquisition (SIGINT to process group)..."
  if kill -0 "${RUN_PID}" 2>/dev/null; then
    # Signal the entire process group (matches how Ctrl+C works in a terminal)
    kill -INT -- "-${RUN_PID}" 2>/dev/null || true

    # If it didn't exit quickly, escalate to TERM
    for _ in {1..20}; do
      if ! kill -0 "${RUN_PID}" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done

    if kill -0 "${RUN_PID}" 2>/dev/null; then
      warn "SIGINT did not stop the run quickly; escalating to SIGTERM..."
      kill -TERM -- "-${RUN_PID}" 2>/dev/null || true
    fi
  else
    warn "Run process already exited before SIGINT."
  fi


  # Wait for end-to-end to finish its processing/plotting
  info "Waiting for run-end-to-end.sh to finish processing..."
  wait "${RUN_PID}" 2>/dev/null || true
  RUN_PID=""

  info "Run ${i}/${N} complete."
  echo
  sleep 2
done

info "All ${N} runs complete."
