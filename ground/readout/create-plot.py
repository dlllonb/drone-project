#!/usr/bin/env python3

import sys
import os
from glob import glob
from astropy.io import fits
from datetime import datetime, timezone
import pickle
import numpy as np
import matplotlib.pyplot as plt

# === CONFIG ===
counts_per_wheel_rev_guess = 2400
plot_types = ["one_pixel", "ROI_sum", "ROI_average", "ROI_median"]

# Background ROI position/size (adjust as needed)
background_yx = (50, 50)   # top-left corner for background
roi_size = 3               # background ROI size (roi_size x roi_size)


def parse_fits_dateobs_to_timestamp(dateobs: str) -> float | None:
    """
    Parse DATE-OBS to a POSIX timestamp (seconds).
    If it ends with 'Z', treat as UTC.
    If tz-naive, treat as LOCAL and convert to UTC using system tz rules.
    """
    try:
        if not dateobs:
            return None
        s = dateobs.strip()

        if s.endswith("Z"):
            dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
            return dt.timestamp()

        dt = datetime.fromisoformat(s)

        if dt.tzinfo is not None:
            return dt.timestamp()

        # tz-naive: interpret as local time
        local_tz = datetime.now().astimezone().tzinfo
        dt_local = dt.replace(tzinfo=local_tz)
        return dt_local.astimezone(timezone.utc).timestamp()

    except Exception:
        return None


def load_encoder_data(pkl_path):
    with open(pkl_path, "rb") as f:
        data = pickle.load(f)

    encoder_times_ms = np.array(list(data.keys()))
    encoder_counts = np.array(list(data.values()))

    # epoch milliseconds -> epoch seconds (epoch is UTC)
    encoder_ts_float = encoder_times_ms.astype(np.float64) / 1000.0
    return encoder_ts_float, encoder_counts


def find_closest_encoder_angle(fits_ts, encoder_ts_array, encoder_counts):
    if fits_ts < encoder_ts_array[0] or fits_ts > encoder_ts_array[-1]:
        return None

    idx = np.searchsorted(encoder_ts_array, fits_ts)
    if idx == 0:
        return encoder_counts[0]
    if idx == len(encoder_ts_array):
        return encoder_counts[-1]

    before = encoder_ts_array[idx - 1]
    after = encoder_ts_array[idx]
    closest_idx = idx - 1 if abs(fits_ts - before) < abs(fits_ts - after) else idx
    return encoder_counts[closest_idx]


def save_plot(x, y, c, xlabel, ylabel, title, outpath):
    plt.figure(figsize=(8, 5))
    sc = plt.scatter(x, y, c=c, cmap="viridis", s=15, marker="o")
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.colorbar(sc, label="Rotation index")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(outpath)
    plt.close()


def estimate_best_time_offset_seconds(fits_ts_list, encoder_ts_array, debug=False):
    """
    Try whole-hour offsets from -12h..+12h and pick the one that yields
    the most encoder matches (range-based proxy).
    """
    if len(fits_ts_list) == 0 or len(encoder_ts_array) == 0:
        return 0

    sample = fits_ts_list[: min(200, len(fits_ts_list))]

    best_offset = 0
    best_matches = -1

    for hours in range(-12, 13):
        off = hours * 3600
        matches = 0
        for ts in sample:
            if ts is None:
                continue
            ts2 = ts + off
            if encoder_ts_array[0] <= ts2 <= encoder_ts_array[-1]:
                matches += 1

        if matches > best_matches:
            best_matches = matches
            best_offset = off

    if debug:
        print(
            f"[DEBUG] Auto time-offset search best: {best_offset/3600:+.0f} hours "
            f"(range-matches in sample={best_matches}/{len(sample)})"
        )

    return best_offset


def main():
    # Args:
    # create-plot.py [--debug] [--time-offset-hours N] <fits_exposure_dir> <encoder_data.pkl>
    args = sys.argv[1:]
    DEBUG = False
    manual_offset_sec = None

    if "--debug" in args:
        DEBUG = True
        args.remove("--debug")

    if "--time-offset-hours" in args:
        i = args.index("--time-offset-hours")
        try:
            manual_offset_sec = int(float(args[i + 1]) * 3600)
        except Exception:
            print("Error: --time-offset-hours requires a number")
            sys.exit(1)
        args.pop(i)  # flag
        args.pop(i)  # value

    if len(args) != 2:
        print(
            f"Usage: {sys.argv[0]} [--debug] [--time-offset-hours N] "
            "<fits_exposure_dir> <encoder_data.pkl>"
        )
        sys.exit(1)

    fits_dir = args[0]
    encoder_pkl = args[1]

    fits_path = os.path.join(fits_dir, "processed", "fits")
    plot_base_dir = os.path.join(fits_dir, "plots")
    os.makedirs(plot_base_dir, exist_ok=True)

    for folder in plot_types:
        os.makedirs(os.path.join(plot_base_dir, folder), exist_ok=True)

    fits_files = sorted(glob(os.path.join(fits_path, "*.fits")))
    if not fits_files:
        print(f"No FITS files found in {fits_path}")
        sys.exit(1)

    encoder_ts_array, encoder_counts = load_encoder_data(encoder_pkl)

    if DEBUG:
        print(f"[DEBUG] Encoder samples: {len(encoder_ts_array)}")
        print(f"[DEBUG] Encoder time range (s): {encoder_ts_array[0]} -> {encoder_ts_array[-1]}")
        print(f"[DEBUG] Encoder start UTC: {datetime.fromtimestamp(encoder_ts_array[0], tz=timezone.utc)}")
        print(f"[DEBUG] Encoder end   UTC: {datetime.fromtimestamp(encoder_ts_array[-1], tz=timezone.utc)}")
        print(f"[DEBUG] Encoder counts range: {np.min(encoder_counts)} -> {np.max(encoder_counts)}")
        print(f"[DEBUG] FITS files found: {len(fits_files)}")

    # Parse FITS timestamps up front
    fits_ts_raw = []
    for f in fits_files:
        s = fits.getheader(f).get("DATE-OBS")
        fits_ts_raw.append(parse_fits_dateobs_to_timestamp(s))

    # Determine offset
    if manual_offset_sec is not None:
        offset_sec = manual_offset_sec
        if DEBUG:
            print(f"[DEBUG] Using MANUAL time offset: {offset_sec/3600:+.0f} hours")
    else:
        offset_sec = estimate_best_time_offset_seconds(fits_ts_raw, encoder_ts_array, debug=DEBUG)

    if DEBUG:
        for ex in fits_files[:3]:
            s = fits.getheader(ex).get("DATE-OBS")
            ts = parse_fits_dateobs_to_timestamp(s)
            print(f"[DEBUG] Example DATE-OBS ({os.path.basename(ex)}): {s}")
            if ts is None:
                print("[DEBUG]  -> parse failed")
                continue
            print(f"[DEBUG]  -> FITS UTC (raw):    {datetime.fromtimestamp(ts, tz=timezone.utc)}")
            print(f"[DEBUG]  -> FITS UTC (offset): {datetime.fromtimestamp(ts + offset_sec, tz=timezone.utc)}")

    # === Use GREEN1 channel explicitly ===
    first_data = fits.getdata(fits_files[0], extname="GREEN1")
    y_max, x_max = np.unravel_index(np.argmax(first_data), first_data.shape)

    if DEBUG:
        print(
            f"[DEBUG] Brightest pixel in GREEN1 of first frame: "
            f"x={x_max}, y={y_max}, value={first_data[y_max, x_max]}"
        )
        print(f"[DEBUG] GREEN1 shape: {first_data.shape}, dtype={first_data.dtype}")

    encoders = []
    angles = []
    rotations = []
    vals = {k: [] for k in plot_types}

    skip_no_dateobs = 0
    skip_bad_dateobs = 0
    skip_no_encoder_match = 0
    skip_bad_roi = 0

    for ffile in fits_files:
        hdr = fits.getheader(ffile)
        fits_time_str = hdr.get("DATE-OBS")
        if not fits_time_str:
            skip_no_dateobs += 1
            continue

        fits_ts = parse_fits_dateobs_to_timestamp(fits_time_str)
        if fits_ts is None:
            skip_bad_dateobs += 1
            continue

        fits_ts += offset_sec

        encoder_val = find_closest_encoder_angle(fits_ts, encoder_ts_array, encoder_counts)
        if encoder_val is None:
            skip_no_encoder_match += 1
            if DEBUG and skip_no_encoder_match <= 5:
                print(
                    f"[DEBUG] No encoder match for {os.path.basename(ffile)} fits_ts={fits_ts} "
                    f"(encoder range {encoder_ts_array[0]}->{encoder_ts_array[-1]})"
                )
            continue

        data = fits.getdata(ffile, extname="GREEN1")

        # ROI bounds checks
        if y_max - 1 < 0 or x_max - 1 < 0 or y_max + 2 > data.shape[0] or x_max + 2 > data.shape[1]:
            skip_bad_roi += 1
            continue

        by, bx = background_yx
        if by < 0 or bx < 0 or by + roi_size > data.shape[0] or bx + roi_size > data.shape[1]:
            skip_bad_roi += 1
            continue

        # Signal ROI (3x3 around brightest pixel)
        roi = data[y_max - 1 : y_max + 2, x_max - 1 : x_max + 2]
        background_roi = data[by : by + roi_size, bx : bx + roi_size]

        # Safe math (avoid uint16 under/overflow)
        roi_i32 = roi.astype(np.int32)
        bg_i32 = background_roi.astype(np.int32)

        background_mean = float(np.mean(bg_i32))
        N = int(roi_i32.size)  # number of pixels in signal ROI (e.g., 9 for 3x3)

        encoders.append(int(encoder_val))

        rel = int(encoder_val) - int(encoder_counts[0])
        frac = (rel / counts_per_wheel_rev_guess) % 1.0
        angles.append(frac * 2 * np.pi)

        rot_index = int(np.floor(rel / counts_per_wheel_rev_guess))
        rotations.append(rot_index)

        # Values we keep
        vals["one_pixel"].append(int(data[y_max, x_max]))
        vals["ROI_sum"].append(int(np.sum(roi_i32) - background_mean * N))
        vals["ROI_average"].append(float(np.mean(roi_i32) - background_mean))
        vals["ROI_median"].append(float(np.median(roi_i32) - background_mean))

    encoders = np.array(encoders)
    angles = np.array(angles)
    rotations = np.array(rotations)

    if DEBUG:
        print("\n[DEBUG] ===== Summary =====")
        print(f"[DEBUG] FITS total: {len(fits_files)}")
        print(f"[DEBUG] matched: {len(encoders)}")
        print(f"[DEBUG] skip_no_dateobs: {skip_no_dateobs}")
        print(f"[DEBUG] skip_bad_dateobs: {skip_bad_dateobs}")
        print(f"[DEBUG] skip_no_encoder_match: {skip_no_encoder_match}")
        print(f"[DEBUG] skip_bad_roi: {skip_bad_roi}")
        if len(encoders) == 0:
            print("[DEBUG] No matched frames. Plots will be empty.")

    for k in plot_types:
        y = np.array(vals[k])

        save_plot(
            encoders,
            y,
            rotations,
            "Encoder Count",
            k.replace("_", " ").title(),
            f"{k.replace('_', ' ').title()} vs Encoder",
            outpath=os.path.join(plot_base_dir, k, f"{k}_vs_encoder.png"),
        )

        save_plot(
            angles,
            y,
            rotations,
            "Plate Angle (rad)",
            k.replace("_", " ").title(),
            f"{k.replace('_', ' ').title()} vs Plate Angle",
            outpath=os.path.join(plot_base_dir, k, f"{k}_vs_angle.png"),
        )

    print("All plots saved to:", plot_base_dir)


if __name__ == "__main__":
    main()