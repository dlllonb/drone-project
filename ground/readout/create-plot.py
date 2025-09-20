#!/usr/bin/env python3

import sys
import os
from glob import glob
from astropy.io import fits
from datetime import datetime, timezone, timedelta
import pickle
import numpy as np
import matplotlib.pyplot as plt

# === CONFIG ===
counts_per_wheel_rev_guess = 2400
timezone_offset_hours = 4
plot_types = ["one_pixel", "all_pixel_sum", "all_pixel_avg",
              "ROI_sum", "ROI_average", "ROI_median"]

# Background ROI position/size (adjust as needed)
background_yx = (50, 50)   # top-left corner for background
roi_size = 3               # 3x3 for both ROI and background


def load_encoder_data(pkl_path):
    with open(pkl_path, "rb") as f:
        data = pickle.load(f)
    encoder_times_ms = np.array(list(data.keys()))
    encoder_counts = np.array(list(data.values()))
    encoder_times = np.array([
        datetime.fromtimestamp(ts / 1000.0, tz=timezone.utc)
        for ts in encoder_times_ms
    ])
    encoder_ts_float = np.array([et.timestamp() for et in encoder_times])
    return encoder_ts_float, encoder_counts


def find_closest_encoder_angle(fits_ts, encoder_ts_array, encoder_counts):
    if fits_ts < encoder_ts_array[0] or fits_ts > encoder_ts_array[-1]:
        return None
    idx = np.searchsorted(encoder_ts_array, fits_ts)
    if idx == 0:
        return encoder_counts[0]
    elif idx == len(encoder_ts_array):
        return encoder_counts[-1]
    before = encoder_ts_array[idx - 1]
    after = encoder_ts_array[idx]
    closest_idx = idx - 1 if abs(fits_ts - before) < abs(fits_ts - after) else idx
    return encoder_counts[closest_idx]


def save_plot(x, y, c, xlabel, ylabel, title, outpath):
    plt.figure(figsize=(8, 5))
    sc = plt.scatter(x, y, c=c, cmap="viridis", s=15, marker='o')
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.colorbar(sc, label="Rotation index")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(outpath)
    plt.close()


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <fits_exposure_dir> <encoder_data.pkl>")
        sys.exit(1)

    fits_dir = sys.argv[1]
    encoder_pkl = sys.argv[2]
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

    # === Use GREEN1 channel explicitly ===
    first_data = fits.getdata(fits_files[0], extname="GREEN1")
    y_max, x_max = np.unravel_index(np.argmax(first_data), first_data.shape)

    encoders = []
    angles = []
    rotations = []
    vals = {k: [] for k in plot_types}

    for ffile in fits_files:
        hdr = fits.getheader(ffile)
        fits_time_str = hdr.get("DATE-OBS")
        if not fits_time_str:
            continue
        fits_dt = datetime.fromisoformat(
            fits_time_str.replace("Z", "+00:00")
        ) + timedelta(hours=timezone_offset_hours)
        fits_ts = fits_dt.replace(tzinfo=timezone.utc).timestamp()

        encoder_val = find_closest_encoder_angle(
            fits_ts, encoder_ts_array, encoder_counts
        )
        if encoder_val is None:
            continue

        # Load GREEN1 channel only
        data = fits.getdata(ffile, extname="GREEN1")

        # Signal ROI (around brightest pixel)
        roi = data[y_max-1:y_max+2, x_max-1:x_max+2]

        # Background ROI (fixed offset area)
        by, bx = background_yx
        background_roi = data[by:by+roi_size, bx:bx+roi_size]
        background_mean = np.mean(background_roi)
        background_sum = np.sum(background_roi)

        encoders.append(encoder_val)
        rel = encoder_val - encoder_counts[0]
        frac = (rel / counts_per_wheel_rev_guess) % 1
        angles.append(frac * 2 * np.pi)

        # Rotation index (integer turn count of the wheel)
        rot_index = int(rel // counts_per_wheel_rev_guess)
        rotations.append(rot_index)

        # === Store values ===
        vals["one_pixel"].append(data[y_max, x_max])
        vals["all_pixel_sum"].append(np.sum(data))   # no background subtraction
        vals["all_pixel_avg"].append(np.mean(data))  # no background subtraction

        # ROI metrics with background subtraction
        vals["ROI_sum"].append(np.sum(roi) - background_sum)
        vals["ROI_average"].append(np.mean(roi) - background_mean)
        vals["ROI_median"].append(np.median(roi) - background_mean)

    encoders = np.array(encoders)
    angles = np.array(angles)
    rotations = np.array(rotations)

    for k in plot_types:
        y = np.array(vals[k])
        save_plot(encoders, y, rotations,
                  "Encoder Count", k.replace("_", " ").title(),
                  f"{k.replace('_', ' ').title()} vs Encoder",
                  outpath=os.path.join(plot_base_dir, k, f"{k}_vs_encoder.png"))
        save_plot(angles, y, rotations,
                  "Plate Angle (rad)", k.replace("_", " ").title(),
                  f"{k.replace('_', ' ').title()} vs Plate Angle",
                  outpath=os.path.join(plot_base_dir, k, f"{k}_vs_angle.png"))

    print("All plots saved to:", plot_base_dir)


if __name__ == "__main__":
    main()