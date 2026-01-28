#!/usr/bin/env bash
set -euo pipefail

# Run from anywhere, but treat /readout as the working dir for the camera script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READOUT_DIR="$SCRIPT_DIR"
MOTOR_DIR="$(cd "$SCRIPT_DIR/../motor" && pwd)"

CAMERA_CMD=( "./continuous-capture.sh" )
MOTOR_CMD=( "python3" "motor-spin-logger.py" )

CAM_PID=""
MOTOR_PID=""

cleanup() {
  echo
  echo "[INFO] Stopping acquisition (camera first, then motor)..."

  # Stop camera first
  if [[ -n "${CAM_PID}" ]] && kill -0 "${CAM_PID}" 2>/dev/null; then
    echo "[INFO] Sending SIGINT to camera (PID=${CAM_PID})..."
    kill -INT "${CAM_PID}" 2>/dev/null || true

    # Give it a moment to exit cleanly
    for _ in {1..30}; do
      if ! kill -0 "${CAM_PID}" 2>/dev/null; then break; fi
      sleep 0.1
    done

    # If still running, escalate
    if kill -0 "${CAM_PID}" 2>/dev/null; then
      echo "[WARN] Camera still running; sending SIGTERM..."
      kill -TERM "${CAM_PID}" 2>/dev/null || true
    fi
  fi

  # Then stop motor/encoder
  if [[ -n "${MOTOR_PID}" ]] && kill -0 "${MOTOR_PID}" 2>/dev/null; then
    echo "[INFO] Sending SIGINT to motor/encoder (PID=${MOTOR_PID})..."
    kill -INT "${MOTOR_PID}" 2>/dev/null || true

    for _ in {1..30}; do
      if ! kill -0 "${MOTOR_PID}" 2>/dev/null; then break; fi
      sleep 0.1
    done

    if kill -0 "${MOTOR_PID}" 2>/dev/null; then
      echo "[WARN] Motor still running; sending SIGTERM..."
      kill -TERM "${MOTOR_PID}" 2>/dev/null || true
    fi
  fi

  echo "[INFO] Done."
}

trap cleanup INT TERM EXIT

echo "[INFO] Starting motor/encoder in: $MOTOR_DIR"
(
  cd "$MOTOR_DIR"
  # Silence motor output completely (you said you don't care about it)
  "${MOTOR_CMD[@]}" >/dev/null 2>&1
) &
MOTOR_PID=$!
echo "[INFO] Motor PID: $MOTOR_PID"

# Give motor a moment to start logging before camera begins
sleep 0.2

echo "[INFO] Starting camera in: $READOUT_DIR"
(
  cd "$READOUT_DIR"
  # Show camera output live in this terminal
  "${CAMERA_CMD[@]}"
) &
CAM_PID=$!
echo "[INFO] Camera PID: $CAM_PID"

echo "[INFO] Acquisition running. Press Ctrl+C to stop (camera stops first)."

# Wait for either to exit; if camera exits, we stop everything via cleanup trap.
wait "$CAM_PID"