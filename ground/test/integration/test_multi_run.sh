#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MULTI_RUN_SCRIPT="$ROOT/multi-run.sh"

CAMPAIGN_DIR="$ROOT/test/test_runs/campaign-integration-$(date +%Y%m%d-%H%M%S)"

echo "[TEST] Multi-run pipeline"
echo "[INFO] Campaign dir: $CAMPAIGN_DIR"

"$MULTI_RUN_SCRIPT" \
  2 \
  "${TEST_ACQ_DURATION_S:-6}" \
  --mode full \
  --campaign-dir "$CAMPAIGN_DIR" \
  --cleanup-after-processing 0

if [[ ! -d "$CAMPAIGN_DIR" ]]; then
  echo "[FAIL] Campaign directory not created"
  exit 1
fi

if [[ ! -f "$CAMPAIGN_DIR/campaign.log" ]]; then
  echo "[FAIL] campaign.log not created"
  exit 1
fi

RUN_COUNT="$(find "$CAMPAIGN_DIR" -mindepth 1 -maxdepth 1 -type d -name 'run_*' | wc -l)"

if [[ "$RUN_COUNT" -ne 2 ]]; then
  echo "[FAIL] Expected 2 run directories, found $RUN_COUNT"
  exit 1
fi

for run_dir in "$CAMPAIGN_DIR"/run_*; do
  echo "[INFO] Checking $run_dir"

  EXPOSURE_DIR="$(find "$run_dir" -mindepth 1 -maxdepth 1 -type d -name 'exposures-*' | head -n 1 || true)"

  if [[ -z "$EXPOSURE_DIR" ]]; then
    echo "[FAIL] No exposure directory found in $run_dir"
    exit 1
  fi

  if ! find "$EXPOSURE_DIR/raw" -type f -name '*.bin' | grep -q .; then
    echo "[FAIL] No raw .bin files in $EXPOSURE_DIR"
    exit 1
  fi

  if ! find "$EXPOSURE_DIR" -type f -name 'encoder_data_*.pkl' | grep -q .; then
    echo "[FAIL] No encoder .pkl in $EXPOSURE_DIR"
    exit 1
  fi

  if ! find "$EXPOSURE_DIR/processed/fits" -type f -name '*.fits' | grep -q .; then
    echo "[FAIL] No FITS files in $EXPOSURE_DIR"
    exit 1
  fi

  if ! find "$EXPOSURE_DIR/plots" -type f -name '*.png' | grep -q .; then
    echo "[FAIL] No plot PNG files in $EXPOSURE_DIR"
    exit 1
  fi

  if ! find "$EXPOSURE_DIR/plots" -type f -name 'fitlog_*.log' | grep -q .; then
    echo "[FAIL] No fitlog in $EXPOSURE_DIR/plots"
    exit 1
  fi
done

echo "[PASS] Multi-run pipeline passed: $CAMPAIGN_DIR"