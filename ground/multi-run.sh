#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./multi-run.sh [N] [DURATION_SEC] [-- <args forwarded to run-end-to-end.sh/load-config.py>]
#
# Examples:
#   ./multi-run.sh
#   ./multi-run.sh 3 10
#   ./multi-run.sh 2 45 -- --gain 80 --interval 0.002
#   ./multi-run.sh 5 60 -- --config config.yml
#
# Notes:
# - DURATION_SEC is passed as "--duration-s" which your load-config.py understands.
# - This runs sequentially (run 1 finishes processing/plotting before run 2 starts).

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$BASE_DIR/run-end-to-end.sh"

N="${1:-5}"
DURATION_SEC="${2:-60}"

# Shift off N and DURATION_SEC if they were provided
if [[ $# -ge 1 ]]; then shift; fi
if [[ $# -ge 1 ]]; then shift; fi

# Everything after optional "--" is forwarded
FORWARD_ARGS=()
if [[ $# -gt 0 ]]; then
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  FORWARD_ARGS=("$@")
fi

if [[ ! -x "$RUN_SCRIPT" ]]; then
  echo "[ERR ] Missing or not executable: $RUN_SCRIPT" >&2
  echo "[INFO] Try: chmod +x \"$RUN_SCRIPT\"" >&2
  exit 1
fi

# Basic numeric sanity
if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 ]]; then
  echo "[ERR ] N must be a positive integer (got: $N)" >&2
  exit 1
fi
if ! [[ "$DURATION_SEC" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[ERR ] DURATION_SEC must be a number (got: $DURATION_SEC)" >&2
  exit 1
fi

for ((i=1; i<=N; i++)); do
  echo "[INFO] ===== Run ${i}/${N} ====="
  echo "[INFO] Calling: $RUN_SCRIPT --duration-s $DURATION_SEC ${FORWARD_ARGS[*]}"

  "$RUN_SCRIPT" --duration-s "$DURATION_SEC" "${FORWARD_ARGS[@]}"

  echo "[INFO] Run ${i}/${N} complete."
  echo
  sleep 2
done

echo "[INFO] All ${N} runs complete."