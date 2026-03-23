#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Multi-run campaign script
#
# Supports:
#   full          : acquire + process each run
#   acquire-only  : acquire only for each run
#   process-only  : process all existing exposure folders inside a campaign dir
#
# Examples:
#   ./multi-run.sh
#   ./multi-run.sh 3 60
#   ./multi-run.sh 3 60 --mode acquire-only
#   ./multi-run.sh 3 60 --mode full -- --config config.yml --save-roi-overlays 1 --make-roi-gif 1
#   ./multi-run.sh --mode process-only --campaign-dir ./campaign-20260319-210000 -- --config config.yml
#
# Campaign layout:
#   campaign-YYYYMMDD-HHMMSS/
#     campaign.log
#     campaign_config.log
#     run_001/
#       exposures-...
#     run_002/
#       exposures-...
# ==========================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$BASE_DIR/run-end-to-end.sh"

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

usage() {
  cat <<EOF
Usage:
  ./multi-run.sh [N] [DURATION_SEC] [options] [-- <args forwarded to run-end-to-end.sh/load-config.py>]

Options:
  --mode MODE           full | acquire-only | process-only
  --campaign-dir PATH   Existing or desired campaign directory

Examples:
  ./multi-run.sh
  ./multi-run.sh 3 60
  ./multi-run.sh 3 60 --mode acquire-only
  ./multi-run.sh 5 60 --mode full -- --config config.yml --save-roi-overlays 1 --make-roi-gif 1
  ./multi-run.sh --mode process-only --campaign-dir ./campaign-20260319-210000 -- --config config.yml
EOF
}

if [[ ! -x "$RUN_SCRIPT" ]]; then
  err "Missing or not executable: $RUN_SCRIPT"
  echo "[INFO] Try: chmod +x \"$RUN_SCRIPT\"" >&2
  exit 1
fi

MODE="full"
CAMPAIGN_DIR=""

# Backward-compatible positional parsing
N="${1:-5}"
DURATION_SEC="${2:-60}"

if [[ "${1:-}" =~ ^[0-9]+$ ]]; then shift; else N="5"; fi
if [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then DURATION_SEC="$1"; shift; else DURATION_SEC="60"; fi

FORWARD_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --campaign-dir)
      CAMPAIGN_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      FORWARD_ARGS=("$@")
      break
      ;;
    *)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

case "$MODE" in
  full|acquire-only|process-only) ;;
  *)
    err "Invalid mode: $MODE"
    usage
    exit 1
    ;;
esac

if [[ -n "$CAMPAIGN_DIR" && "$CAMPAIGN_DIR" != /* ]]; then
  CAMPAIGN_DIR="$BASE_DIR/$CAMPAIGN_DIR"
fi

if [[ "$MODE" != "process-only" ]]; then
  if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 ]]; then
    err "N must be a positive integer (got: $N)"
    exit 1
  fi

  if ! [[ "$DURATION_SEC" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    err "DURATION_SEC must be a number (got: $DURATION_SEC)"
    exit 1
  fi

  if awk "BEGIN{exit !(${DURATION_SEC} <= 0)}"; then
    err "For multi-run in mode '$MODE', duration must be > 0."
    exit 1
  fi
fi

if [[ "$MODE" == "process-only" ]]; then
  if [[ -z "$CAMPAIGN_DIR" ]]; then
    err "--campaign-dir is required for --mode process-only"
    exit 1
  fi
  if [[ ! -d "$CAMPAIGN_DIR" ]]; then
    err "Campaign directory does not exist: $CAMPAIGN_DIR"
    exit 1
  fi
else
  if [[ -z "$CAMPAIGN_DIR" ]]; then
    CAMPAIGN_DIR="$BASE_DIR/campaign-$(date +%Y%m%d-%H%M%S)"
  fi
  mkdir -p "$CAMPAIGN_DIR"
fi

CAMPAIGN_LOG="$CAMPAIGN_DIR/campaign.log"
{
  echo "date: $(date -Is)"
  echo "mode: $MODE"
  echo "campaign_dir: $CAMPAIGN_DIR"
  if [[ "$MODE" != "process-only" ]]; then
    echo "runs: $N"
    echo "duration_s: $DURATION_SEC"
  fi
  echo "forward_args: ${FORWARD_ARGS[*]}"
} > "$CAMPAIGN_LOG"

if [[ "$MODE" == "process-only" ]]; then
  info "Processing existing campaign: $CAMPAIGN_DIR"

  mapfile -d '' EXPOSURE_DIRS < <(
    find "$CAMPAIGN_DIR" \
      \( -path "$CAMPAIGN_DIR/exposures-*" -o -path "$CAMPAIGN_DIR/run_*/exposures-*" \) \
      -type d -print0 | sort -z
  )

  if [[ "${#EXPOSURE_DIRS[@]}" -eq 0 ]]; then
    err "No exposures-* directories found under $CAMPAIGN_DIR"
    exit 1
  fi

  total="${#EXPOSURE_DIRS[@]}"
  idx=0
  for expdir in "${EXPOSURE_DIRS[@]}"; do
    idx=$((idx + 1))
    info "===== Campaign processing ${idx}/${total} ====="
    info "Exposure dir: $expdir"

    "$RUN_SCRIPT" \
      --mode process-only \
      --exposure-dir "$expdir" \
      "${FORWARD_ARGS[@]}"

    info "Processed ${idx}/${total}"
    echo
  done

  info "Campaign processing complete."
  exit 0
fi

info "Campaign directory: $CAMPAIGN_DIR"

for ((i=1; i<=N; i++)); do
  RUN_SUBDIR="$CAMPAIGN_DIR/run_$(printf "%03d" "$i")"
  mkdir -p "$RUN_SUBDIR"

  info "===== Run ${i}/${N} ====="
  info "Run subdir: $RUN_SUBDIR"
  info "Calling: $RUN_SCRIPT --mode $MODE --output-root $RUN_SUBDIR --duration-s $DURATION_SEC ${FORWARD_ARGS[*]}"

  "$RUN_SCRIPT" \
    --mode "$MODE" \
    --output-root "$RUN_SUBDIR" \
    --duration-s "$DURATION_SEC" \
    "${FORWARD_ARGS[@]}"

  info "Run ${i}/${N} complete."
  echo
  sleep 2
done

info "All ${N} runs complete."
info "Campaign saved at: $CAMPAIGN_DIR"