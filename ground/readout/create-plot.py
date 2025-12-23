#!/usr/bin/env python3

import sys
import os
from glob import glob
from astropy.io import fits
from datetime import datetime, timezone
import pickle
import numpy as np
import matplotlib.pyplot as plt
import time
from typing import Optional, Tuple

# === CONFIG ===
counts_per_wheel_rev_guess = 2400
plot_types = ["one_pixel", "ROI_sum", "ROI_average", "ROI_median"]

# Background ROI position/size (adjust as needed)
background_yx = (50, 50)   # top-left corner for background
roi_size = 3               # roi_size x roi_size for both ROI and background

# Fit config (Fourier 4θ model)
DO_FIT_ON_FOLDED = True          # only fit the folded plots (vs Plate Angle)
FIT_MIN_POINTS = 20             # require at least this many points to fit
FIT_EVAL_SAMPLES = 800          # points for the red fit curve
FIT_USE_WEIGHTS = False         # keep simple for now


def parse_fits_dateobs_to_timestamp(dateobs: str) -> float | None:
    """
    Parse DATE-OBS to a POSIX timestamp (seconds).

    IMPORTANT: We parse what the string says.
    - If it ends with 'Z', we treat it as UTC.
    - If tz-aware (has offset), we respect it.
    - If tz-naive, we treat it as LOCAL and convert to UTC using system tz rules.
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


def fit_fourier_4theta(theta: np.ndarray, y: np.ndarray) -> Optional[Tuple[float, float, float, float, float, float]]:
    """
    Fit: y(theta) = a0 + a4*cos(4θ) + b4*sin(4θ)
    Returns (a0, a4, b4, A4, phi4, psi) where:
      A4 = sqrt(a4^2 + b4^2)
      phi4 = atan2(b4, a4)  (radians)
      psi = phi4 / 4        (radians), instrument-frame polarization angle modulo pi/2
    """
    if theta.size < FIT_MIN_POINTS:
        return None

    # Remove NaNs/infs
    m = np.isfinite(theta) & np.isfinite(y)
    theta = theta[m]
    y = y[m]
    if theta.size < FIT_MIN_POINTS:
        return None

    X = np.column_stack([
        np.ones_like(theta, dtype=np.float64),
        np.cos(4.0 * theta),
        np.sin(4.0 * theta),
    ]).astype(np.float64)

    yy = y.astype(np.float64)

    try:
        if FIT_USE_WEIGHTS:
            # placeholder if you later want weights; keep unweighted for now
            pass

        beta, *_ = np.linalg.lstsq(X, yy, rcond=None)
        a0, a4, b4 = float(beta[0]), float(beta[1]), float(beta[2])

        A4 = float(np.hypot(a4, b4))
        phi4 = float(np.arctan2(b4, a4))
        psi = float(phi4 / 4.0)
        return a0, a4, b4, A4, phi4, psi
    except Exception:
        return None


def format_fit_label(a0, a4, b4, A4, phi4, psi) -> str:
    psi_deg = (psi * 180.0 / np.pi) % 90.0  # modulo pi/2
    return f"fit: A4={A4:.3g}, ψ={psi_deg:.2f}° (mod 90°)"


def save_scatter_plot(
    x: np.ndarray,
    y: np.ndarray,
    c: np.ndarray,
    xlabel: str,
    ylabel: str,
    title: str,
    outpath: str,
    fit_x_is_angle: bool = False,
):
    plt.figure(figsize=(8, 5))
    sc = plt.scatter(x, y, c=c, cmap="viridis", s=15, marker="o", label="data")

    if fit_x_is_angle and DO_FIT_ON_FOLDED:
        fit = fit_fourier_4theta(x, y)
        if fit is not None:
            a0, a4, b4, A4, phi4, psi = fit
            xs = np.linspace(0.0, 2.0 * np.pi, FIT_EVAL_SAMPLES)
            ys = a0 + a4 * np.cos(4.0 * xs) + b4 * np.sin(4.0 * xs)
            plt.plot(xs, ys, "-", color="red", linewidth=2.0, label=format_fit_label(a0, a4, b4, A4, phi4, psi))

    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.colorbar(sc, label="Rotation index")
    plt.grid(True)

    # --- legend outside ---
    plt.legend(loc="center left", bbox_to_anchor=(1.02, 0.5), borderaxespad=0.0)

    # leave room on the right for legend + colorbar
    plt.tight_layout(rect=(0, 0, 0.82, 1))

    plt.savefig(outpath, dpi=150)
    plt.close()


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
        print(f"Usage: {sys.argv[0]} [--debug] [--time-offset-hours N] <fits_exposure_dir> <encoder_data.pkl>")
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
            print(f"[DEBUG]  -> FITS UTC (offset): {datetime.fromtimestamp(ts+offset_sec, tz=timezone.utc)}")

    # === Use GREEN1 channel explicitly ===
    first_data = fits.getdata(fits_files[0], extname="GREEN1")
    y_max, x_max = np.unravel_index(np.argmax(first_data), first_data.shape)

    if DEBUG:
        print(f"[DEBUG] Brightest pixel in GREEN1 of first frame: x={x_max}, y={y_max}, value={first_data[y_max, x_max]}")
        print(f"[DEBUG] GREEN1 shape: {first_data.shape}, dtype={first_data.dtype}")

    encoders = []
    angles = []
    rotations = []
    vals = {k: [] for k in plot_types}

    skip_no_dateobs = 0
    skip_bad_dateobs = 0
    skip_no_encoder_match = 0
    skip_bad_roi = 0

    t0 = time.time()
    total_files = len(fits_files)

    for i, ffile in enumerate(fits_files, start=1):
        if i == 1 or i % 100 == 0 or i == total_files:
            elapsed = time.time() - t0
            rate = i / elapsed if elapsed > 0 else 0.0
            print(f"[INFO] Processing FITS {i}/{total_files} ({rate:.1f} files/s)")

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
        if by + roi_size > data.shape[0] or bx + roi_size > data.shape[1]:
            skip_bad_roi += 1
            continue

        roi = data[y_max-1:y_max+2, x_max-1:x_max+2]
        background_roi = data[by:by+roi_size, bx:bx+roi_size]

        # Safe math (avoid uint16 under/overflow)
        roi_i32 = roi.astype(np.int32)
        bg_i32 = background_roi.astype(np.int32)

        encoders.append(int(encoder_val))

        rel = int(encoder_val) - int(encoder_counts[0])
        frac = (rel / counts_per_wheel_rev_guess) % 1.0
        angles.append(frac * 2 * np.pi)

        rot_index = int(np.floor(rel / counts_per_wheel_rev_guess))
        rotations.append(rot_index)

        # Pixel-by-pixel background subtraction
        corrected = roi_i32 - bg_i32  # same shape (roi_size x roi_size)

        # Values we keep
        vals["one_pixel"].append(int(data[y_max, x_max]))
        vals["ROI_sum"].append(int(np.sum(corrected, dtype=np.int64)))
        vals["ROI_average"].append(float(np.mean(corrected)))
        vals["ROI_median"].append(float(np.median(corrected)))

    encoders = np.array(encoders, dtype=np.int64)
    angles = np.array(angles, dtype=np.float64)
    rotations = np.array(rotations, dtype=np.int64)

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

    print("\n[INFO] Generating plots...")
    plot_t0 = time.time()

    for j, k in enumerate(plot_types, start=1):
        print(f"[INFO] Plot {j}/{len(plot_types)}: {k}")
        y = np.array(vals[k])

        # Unfolded plot (encoder count)
        save_scatter_plot(
            encoders,
            y,
            rotations,
            "Encoder Count",
            k.replace("_", " ").title(),
            f"{k.replace('_', ' ').title()} vs Encoder",
            outpath=os.path.join(plot_base_dir, k, f"{k}_vs_encoder.png"),
            fit_x_is_angle=False,  # no fit overlay here
        )

        # Folded plot (plate angle)
        save_scatter_plot(
            angles,
            y,
            rotations,
            "Plate Angle (rad)",
            k.replace("_", " ").title(),
            f"{k.replace('_', ' ').title()} vs Plate Angle",
            outpath=os.path.join(plot_base_dir, k, f"{k}_vs_angle.png"),
            fit_x_is_angle=True,   # fit overlay here (red curve)
        )

    print(f"[INFO] Plot generation completed in {time.time() - plot_t0:.1f} s")
    print(f"[INFO] Total runtime: {time.time() - t0:.1f} s")
    print("All plots saved to:", plot_base_dir)


if __name__ == "__main__":
    main()