#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RUNS_DIR="$SCRIPT_DIR/test_runs"

echo "[INFO] Running integration tests..."

if [[ "${KEEP_TEST_OUTPUTS:-0}" != "1" ]]; then
  echo "[INFO] Cleaning old integration test outputs: $TEST_RUNS_DIR"
  rm -rf "$TEST_RUNS_DIR"
fi

mkdir -p "$TEST_RUNS_DIR"

bash "$SCRIPT_DIR/integration/test_camera_single_exposure.sh"
bash "$SCRIPT_DIR/integration/test_encoder_motor.sh"
bash "$SCRIPT_DIR/integration/test_camera_to_image_pipeline.sh"
bash "$SCRIPT_DIR/integration/test_end_to_end.sh"
bash "$SCRIPT_DIR/integration/test_multi_run.sh"

echo
echo "============================================================"
echo "[PASS] Integration tests passed."
echo "============================================================"