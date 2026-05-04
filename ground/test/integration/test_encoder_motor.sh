#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOTOR_SCRIPT="$ROOT/motor/motor-spin-logger.py"

OUT_ROOT="$ROOT/test/test_runs/encoder_motor"
mkdir -p "$OUT_ROOT"

echo "[TEST] Encoder + motor data collection"

BEFORE_LIST="$OUT_ROOT/before_pkls.txt"
AFTER_LIST="$OUT_ROOT/after_pkls.txt"

find "$ROOT" -maxdepth 1 -type f -name 'encoder_data_*.pkl' | sort > "$BEFORE_LIST"

set +e
timeout -s INT 12s python3 -u "$MOTOR_SCRIPT" \
  --ground-path "$ROOT/" \
  --spin-rate "${SPIN_RATE:-250}"
status=$?
set -e

if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
  echo "[FAIL] Motor/encoder script exited with status $status"
  exit 1
fi

find "$ROOT" -maxdepth 1 -type f -name 'encoder_data_*.pkl' | sort > "$AFTER_LIST"

PKL_FILE="$(comm -13 "$BEFORE_LIST" "$AFTER_LIST" | tail -n 1 || true)"

if [[ -z "$PKL_FILE" ]]; then
  PKL_FILE="$(find "$ROOT" -maxdepth 1 -type f -name 'encoder_data_*.pkl' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2- || true)"
fi

if [[ -z "$PKL_FILE" || ! -f "$PKL_FILE" ]]; then
  echo "[FAIL] No encoder_data_*.pkl file created"
  exit 1
fi

python3 - "$PKL_FILE" <<'PY'
import pickle
import sys
import numpy as np

pkl_path = sys.argv[1]

with open(pkl_path, "rb") as f:
    data = pickle.load(f)

times = np.array(list(data.keys()), dtype=float)
counts = np.array(list(data.values()), dtype=float)

order = np.argsort(times)
times = times[order]
counts = counts[order]

assert len(times) > 50, f"Too few encoder samples: {len(times)}"
assert len(times) == len(counts), "Timestamp/count length mismatch"
assert np.all(np.diff(times) > 0), "Timestamps are not strictly increasing"

# Drop startup transients.
times = times[5:]
counts = counts[5:]

dc = np.diff(counts)
negative_fraction = np.sum(dc < 0) / len(dc)
assert negative_fraction <= 0.05, f"Too many decreasing count steps: {negative_fraction:.4%}"

changed = np.r_[True, np.diff(counts) > 0]
times = times[changed]
counts = counts[changed]

assert len(times) > 20, "Too few changing encoder samples"
assert counts[-1] - counts[0] > 20, f"Count change too small: {counts[-1] - counts[0]}"

t = (times - times[0]) / 1000.0
c = counts - counts[0]

slope, intercept = np.polyfit(t, c, 1)
fit = slope * t + intercept

ss_res = np.sum((c - fit) ** 2)
ss_tot = np.sum((c - np.mean(c)) ** 2)
r2 = 1 - ss_res / ss_tot if ss_tot > 0 else 0

assert slope > 0, f"Encoder slope is not positive: {slope}"
assert r2 > 0.90, f"Encoder count vs time is not linear enough: R2={r2:.4f}"

print(f"[PASS] Encoder pkl sanity passed: {pkl_path}")
print(f"[INFO] samples={len(times)}, delta_count={counts[-1] - counts[0]}, R2={r2:.4f}")
PY

mv "$PKL_FILE" "$OUT_ROOT/$(basename "$PKL_FILE")"

echo "[PASS] Encoder + motor test passed"