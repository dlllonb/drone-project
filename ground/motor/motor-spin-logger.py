"""
motor-spin-logger.py
====================

Purpose
-------
High-level control script for the motor + encoder subsystem. This script
starts the motor, sets its spin behavior, and launches the encoder readout
program to record position vs time.

It is designed to run during data acquisition and is typically invoked by
higher-level pipeline scripts such as `run-end-to-end.sh`.

Behavior
--------
The script performs the following steps:

1. Enables the motor driver
2. Sets rotation direction
3. Starts motor spin at the requested rate
4. Launches the encoder logging binary
5. Waits until interrupted (SIGINT/SIGTERM)
6. Stops encoder logging and motor cleanly

Inputs
------
Command-line arguments:

    --ground-path <path>
        Base path to the ground repository. Used to locate motor control
        scripts and encoder binary.

    --spin-rate <int>
        Motor spin rate passed to the motor control script.

    --encoder-bin <path>
        Optional override for the encoder logging binary. Defaults to:
        <ground-path>/motor/quad_enc/record-encoder-data.out

Outputs
-------
This script does not directly write data files. Instead:

- The encoder binary writes a `.pkl` file containing timestamped count data
- Motor activity is reflected in that encoder output

Shutdown Behavior
-----------------
The script traps SIGINT and SIGTERM to ensure:

- the encoder process is stopped cleanly
- the motor is stopped via motor_control.sh

This guarantees that encoder data is flushed and saved properly before exit.

Typical Usage
-------------
Normally launched indirectly via:

    ./run-end-to-end.sh

Manual testing:

    python3 motor-spin-logger.py --spin-rate 250

Notes
-----
This script assumes that:

- motor control scripts exist in `motor/scripts/`
- the encoder binary has been compiled
- hardware (motor + encoder) is connected and powered
"""

#!/usr/bin/env python3
import argparse
import subprocess
import signal
import sys
import time
from typing import Optional

DEFAULT_GROUND_PATH = "/home/declan/drone-project/ground/"
DEFAULT_SPIN_RATE = 250


def run_cmd(cmd, check=True):
    return subprocess.run(cmd, check=check)


def stop_motor(ground_path: str):
    try:
        run_cmd([ground_path + "motor/scripts/motor_control.sh", "stop"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"[WARN] Error stopping motor: {e}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description="Spin motor + run encoder readout until SIGINT.")
    ap.add_argument("--ground-path", default=DEFAULT_GROUND_PATH, help="Base path to ground repo")
    ap.add_argument("--spin-rate", type=int, default=DEFAULT_SPIN_RATE, help="Motor spin rate")
    ap.add_argument("--encoder-bin", default=None,
                    help="Path to encoder binary (default: <ground-path>/motor/quad_enc/record-encoder-data.out)")
    args = ap.parse_args()

    ground_path = args.ground_path
    if not ground_path.endswith("/"):
        ground_path += "/"

    encoder_bin = args.encoder_bin or (ground_path + "motor/quad_enc/record-encoder-data.out")
    spin_rate = str(args.spin_rate)

    readout: Optional[subprocess.Popen] = None
    shutting_down = False

    def handle_sigint(signum, frame):
        nonlocal shutting_down
        if shutting_down:
            return
        shutting_down = True
        print("\n[INFO] Caught SIGINT, stopping encoder + motor...")
        try:
            if readout is not None and readout.poll() is None:
                readout.send_signal(signal.SIGINT)
        except Exception:
            pass

    signal.signal(signal.SIGINT, handle_sigint)
    signal.signal(signal.SIGTERM, handle_sigint)

    try:
        # Enable motor
        run_cmd([ground_path + "motor/scripts/motor_control.sh", "enable"], check=True)

        # Direction
        run_cmd([ground_path + "motor/scripts/motor_control.sh", "forward"], check=True)

        # Spin
        run_cmd([ground_path + "motor/scripts/motor_control.sh", "spin", spin_rate], check=True)

        # Encoder readout
        readout = subprocess.Popen([encoder_bin])

        print("[INFO] Motor running. Press Ctrl+C to stop.")

        # Wait until encoder exits or SIGINT triggers shutdown
        while readout.poll() is None and not shutting_down:
            time.sleep(0.2)

        # If we were interrupted, wait briefly for encoder to flush/pickle
        if shutting_down and readout.poll() is None:
            readout.wait(timeout=10)

    except subprocess.CalledProcessError as e:
        print(f"[ERR ] Command failed: {e}", file=sys.stderr)
    except KeyboardInterrupt:
        pass
    finally:
        # Ensure encoder is stopped
        try:
            if readout is not None and readout.poll() is None:
                readout.send_signal(signal.SIGINT)
                readout.wait(timeout=10)
        except Exception:
            pass

        stop_motor(ground_path)
        print("[INFO] Stopped.")


if __name__ == "__main__":
    main()