#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Running unit tests..."

python3 -m pytest "$SCRIPT_DIR/unit/test_load_config.py"
python3 -m pytest "$SCRIPT_DIR/unit/test_create_plot.py"
python3 -m pytest "$SCRIPT_DIR/unit/test_create_animation.py"
python3 -m pytest "$SCRIPT_DIR/unit/test_encoder_pkl_sanity.py"

bash "$SCRIPT_DIR/unit/test_process_exposures_batch.sh"

echo
echo "============================================================"
echo "[PASS] Unit tests passed."
echo "============================================================"