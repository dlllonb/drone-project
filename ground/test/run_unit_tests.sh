#!/usr/bin/env bash
set -euo pipefail

python3 -m pytest tests/unit/test_load_config.py
python3 -m pytest tests/unit/test_create_plot.py
python3 -m pytest tests/unit/test_create_animation.py

bash tests/unit/test_process_exposures_batch.sh