#!/usr/bin/env bash
set -euo pipefail

python3 -m pytest test/unit/test_load_config.py
python3 -m pytest test/unit/test_create_plot.py
python3 -m pytest test/unit/test_create_animation.py

bash test/unit/test_process_exposures_batch.sh