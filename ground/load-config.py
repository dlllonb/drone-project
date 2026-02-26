#!/usr/bin/env python3
import argparse
import os
from typing import Any, Dict

import yaml


def deep_get(d: Dict[str, Any], path: str, default=None):
    cur = d
    for p in path.split("."):
        if not isinstance(cur, dict) or p not in cur:
            return default
        cur = cur[p]
    return cur


def load_yaml(path: str) -> Dict[str, Any]:
    if not path or not os.path.exists(path):
        return {}
    with open(path, "r") as f:
        return yaml.safe_load(f) or {}


def main():
    ap = argparse.ArgumentParser(description="Load YAML config and emit shell exports.")
    ap.add_argument("--config", default="config.yaml", help="Path to config.yaml (default: ./config.yaml)")
    ap.add_argument("--print-resolved", action="store_true", help="Print resolved YAML to stdout (debug)")

    # acquisition overrides
    ap.add_argument("--exposure-time", type=float, default=None, help="Override exposure time (seconds)")
    ap.add_argument("--gain", type=int, default=None, help="Override gain")
    ap.add_argument("--interval", type=float, default=None, help="Override interval (seconds)")
    ap.add_argument("--duration-s", type=float, default=None, help="Override acquisition duration (seconds; 0=manual)")

    # motor overrides
    ap.add_argument("--spin-rate", type=int, default=None, help="Override motor spin rate")
    ap.add_argument("--ground-path", type=str, default=None, help="Override ground base path")

    # processing overrides
    ap.add_argument("--jobs", type=int, default=None, help="Override processing jobs (0 => auto)")
    ap.add_argument("--make-fits", type=int, choices=[0, 1], default=None, help="Override make_fits (1/0)")
    ap.add_argument("--make-color", type=int, choices=[0, 1], default=None, help="Override make_color (1/0)")
    ap.add_argument("--make-green", type=int, choices=[0, 1], default=None, help="Override make_green (1/0)")
    ap.add_argument("--quiet", type=int, choices=[0, 1], default=None, help="Override quiet (1/0)")

    # plotting overrides
    ap.add_argument("--counts-per-rev", type=int, default=None, help="Override counts_per_rev")
    ap.add_argument("--plot-debug", type=int, choices=[0, 1], default=None, help="Override debug (1/0)")
    ap.add_argument("--time-offset-hours", type=float, default=None, help="Override time_offset_hours (float)")

    args = ap.parse_args()
    cfg = load_yaml(args.config)

    # ---- defaults ----
    exposure_time = deep_get(cfg, "acquisition.exposure_time_s", 0.001)
    gain = deep_get(cfg, "acquisition.gain", 100)
    interval = deep_get(cfg, "acquisition.interval_s", 0.001)
    duration_s = deep_get(cfg, "acquisition.duration_s", 0)

    ground_path = deep_get(cfg, "motor.base_path", "/home/declan/drone-project/ground/")
    spin_rate = deep_get(cfg, "motor.spin_rate", 250)

    jobs = deep_get(cfg, "processing.jobs", 0)
    make_fits = deep_get(cfg, "processing.make_fits", True)
    make_color = deep_get(cfg, "processing.make_color", False)
    make_green = deep_get(cfg, "processing.make_green", False)
    quiet = deep_get(cfg, "processing.quiet", False)

    counts_per_rev = deep_get(cfg, "plotting.counts_per_rev", 2400)
    plot_debug = deep_get(cfg, "plotting.debug", False)
    time_offset_hours = deep_get(cfg, "plotting.time_offset_hours", None)

    # ---- apply CLI overrides (if provided) ----
    if args.exposure_time is not None:
        exposure_time = args.exposure_time
    if args.gain is not None:
        gain = args.gain
    if args.interval is not None:
        interval = args.interval
    if args.duration_s is not None:
        duration_s = args.duration_s

    if args.ground_path is not None:
        ground_path = args.ground_path
    if args.spin_rate is not None:
        spin_rate = args.spin_rate

    if args.jobs is not None:
        jobs = args.jobs
    if args.make_fits is not None:
        make_fits = bool(args.make_fits)
    if args.make_color is not None:
        make_color = bool(args.make_color)
    if args.make_green is not None:
        make_green = bool(args.make_green)
    if args.quiet is not None:
        quiet = bool(args.quiet)

    if args.counts_per_rev is not None:
        counts_per_rev = args.counts_per_rev
    if args.plot_debug is not None:
        plot_debug = bool(args.plot_debug)
    if args.time_offset_hours is not None:
        time_offset_hours = args.time_offset_hours

    # ---- emit shell exports (for bash eval) ----
    def shbool(x: bool) -> str:
        return "1" if x else "0"

    print(f'export EXPOSURE_TIME="{exposure_time}"')
    print(f'export GAIN="{gain}"')
    print(f'export INTERVAL="{interval}"')
    print(f'export ACQ_DURATION_S="{duration_s}"')

    print(f'export GROUND_PATH="{ground_path}"')
    print(f'export SPIN_RATE="{spin_rate}"')

    print(f'export PROCESS_JOBS="{jobs}"')
    print(f'export PROCESS_MAKE_FITS="{shbool(bool(make_fits))}"')
    print(f'export PROCESS_MAKE_COLOR="{shbool(bool(make_color))}"')
    print(f'export PROCESS_MAKE_GREEN="{shbool(bool(make_green))}"')
    print(f'export PROCESS_QUIET="{shbool(bool(quiet))}"')

    print(f'export PLOT_COUNTS_PER_REV="{counts_per_rev}"')
    print(f'export PLOT_DEBUG="{shbool(bool(plot_debug))}"')

    if time_offset_hours is None:
        print('export PLOT_TIME_OFFSET_HOURS=""')
    else:
        print(f'export PLOT_TIME_OFFSET_HOURS="{time_offset_hours}"')

    if args.print_resolved:
        resolved = {
            "acquisition": {"exposure_time_s": exposure_time, "gain": gain, 
                            "interval_s": interval, "duration_s": float(duration_s)},
            "motor": {"base_path": ground_path, "spin_rate": spin_rate},
            "processing": {
                "jobs": jobs,
                "make_fits": bool(make_fits),
                "make_color": bool(make_color),
                "make_green": bool(make_green),
                "quiet": bool(quiet),
            },
            "plotting": {
                "counts_per_rev": counts_per_rev,
                "debug": bool(plot_debug),
                "time_offset_hours": time_offset_hours,
            },
        }
        print("\n# --- resolved config (debug) ---")
        print(yaml.safe_dump(resolved, sort_keys=False).rstrip())


if __name__ == "__main__":
    main()