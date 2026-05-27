#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
BIN = SCRIPT_DIR / "process-exposures-batch.out"

if not BIN.exists():
    print(f"Error: missing compiled processor: {BIN}", file=sys.stderr)
    print("Try: make", file=sys.stderr)
    sys.exit(1)

os.execv(str(BIN), [str(BIN), *sys.argv[1:]])