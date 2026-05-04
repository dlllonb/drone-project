#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Running unit tests..."
bash test/run_unit_tests.sh

echo
echo "[INFO] Running integration tests..."
bash test/run_integration_tests.sh

echo
echo "[PASS] All unit and integration tests passed."