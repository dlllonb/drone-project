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
        run_cmd([ground_path + "motor/scripts/motor_control.sh", "backward"], check=True)

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