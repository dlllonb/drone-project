#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOTOR_CONTROL="$ROOT/motor/scripts/motor_control.sh"

echo "[TEST] Motor control script sanity"

if [[ ! -x "$MOTOR_CONTROL" ]]; then
  echo "[FAIL] Missing or not executable: $MOTOR_CONTROL"
  exit 1
fi

bash "$MOTOR_CONTROL" enable
bash "$MOTOR_CONTROL" forward
bash "$MOTOR_CONTROL" spin "${TEST_MOTOR_SPEED:-250}"

sleep "${TEST_MOTOR_DURATION_S:-2}"

bash "$MOTOR_CONTROL" stop
bash "$MOTOR_CONTROL" disable

echo "[PASS] Motor control script sanity passed"