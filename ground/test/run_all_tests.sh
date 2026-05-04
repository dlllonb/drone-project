#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "[INFO] Starting full test suite"
echo "============================================================"

echo
echo "============================================================"
echo "[INFO] Running unit tests"
echo "============================================================"
bash "$SCRIPT_DIR/run_unit_tests.sh"

echo
echo "============================================================"
echo "[PASS] Unit tests passed"
echo "============================================================"

echo
echo "============================================================"
echo "[INFO] Running integration tests"
echo "============================================================"
bash "$SCRIPT_DIR/run_integration_tests.sh"

echo
echo "============================================================"
echo "[PASS] Unit and integration tests passed"
echo "============================================================"