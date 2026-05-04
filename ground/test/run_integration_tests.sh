#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Running integration tests..."

bash test/integration/test_camera_single_exposure.sh
bash test/integration/test_encoder_motor.sh
bash test/integration/test_camera_to_image_pipeline.sh
bash test/integration/test_end_to_end.sh
bash test/integration/test_multi_run.sh

echo "[PASS] All integration tests passed."