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
from typing import Optional, Dict, Tuple, List

# === CONFIG ===
counts_per_wheel_rev_guess = 2400
plot_types = ["one_pixel", "ROI_sum", "ROI_average", "ROI_median"]

# Background ROI position/size (adjust as needed)
background_yx = (50, 50)   # top-left corner for background
roi_size = 3               # roi_size x roi_size for both ROI and background

# Fit config (Fourier model on folded plots only)
DO_FIT_ON_FOLDED = True
FIT_MIN_POINTS = 20 # THIS MEANS "NO FIT" IF FEWER THAN THIS MANY POINTS
FIT_EVAL_SAMPLES = 1000

# Which harmonics to include in the fit (2θ + 4θ is usually the first "non-ideal" upgrade)
FIT_HARMONICS = [2, 4]
FIT_INCLUDE_8TH = False  # set True if you want to add 8θ
if FIT_INCLUDE_8TH and 8 not in FIT_HARMONICS:
    FIT_HARMONICS = FIT_HARMONICS + [8]

# --- Encoder outlier filtering ---
FILTER_ENCODER_OUTLIERS = True
OUTLIER_FACTOR = 5.0  # outlier if |count - median| > OUTLIER_FACTOR * median
MIN_MEDIAN_FOR_FILTER = 1.0  # if median is tiny, skip this filter

# NEW: ROI tracking settings
ROI_PAD_PX = 4                 # padding added around detected blob bbox
ROI_GUARD_PX = 4               # exclude ROI + guard band from background pixels
BLOB_THRESH_FRAC_OF_PEAK = 0.5 # blob = pixels >= frac * peak
MIN_BLOB_AREA = 3              # reject tiny blobs (hot pixels / noise)
MAX_ROI_SIDE = 200             # safety clamp so ROI can't explode (frame-specific)


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


def build_design_matrix(theta: np.ndarray, harmonics: List[int]) -> np.ndarray:
    """
    X columns: [1, cos(kθ), sin(kθ) for k in harmonics]
    """
    cols = [np.ones_like(theta, dtype=np.float64)]
    for k in harmonics:
        cols.append(np.cos(k * theta))
        cols.append(np.sin(k * theta))
    return np.column_stack(cols).astype(np.float64)


def fit_fourier(theta: np.ndarray, y: np.ndarray, harmonics: List[int]) -> Optional[Dict[str, float]]:
    """
    Fit y(theta) = a0 + Σ_k (a_k cos(kθ) + b_k sin(kθ))

    Returns a dict with:
      a0, (a2,b2), (a4,b4), ... as available
      A2,phi2, A4,phi4, psi (from 4θ), R2
    """
    if theta.size < FIT_MIN_POINTS:
        return None

    m = np.isfinite(theta) & np.isfinite(y)
    theta = theta[m].astype(np.float64)
    y = y[m].astype(np.float64)
    if theta.size < FIT_MIN_POINTS:
        return None

    X = build_design_matrix(theta, harmonics)
    try:
        beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    except Exception:
        return None

    yhat = X @ beta
    resid = y - yhat

    ss_res = float(np.sum(resid * resid))
    ss_tot = float(np.sum((y - np.mean(y)) ** 2))
    R2 = 1.0 - (ss_res / ss_tot) if ss_tot > 0 else float("nan")

    out: Dict[str, float] = {}
    out["a0"] = float(beta[0])
    out["R2"] = float(R2)

    # unpack harmonics
    idx = 1
    for k in harmonics:
        ak = float(beta[idx]); bk = float(beta[idx + 1])
        out[f"a{k}"] = ak
        out[f"b{k}"] = bk
        out[f"A{k}"] = float(np.hypot(ak, bk))
        out[f"phi{k}"] = float(np.arctan2(bk, ak))
        idx += 2

    # polarization angle from 4θ phase if present
    if 4 in harmonics:
        phi4 = out["phi4"]  # radians
        psi = phi4 / 4.0
        out["psi"] = float(psi)

    return out


def eval_fourier(theta: np.ndarray, params: Dict[str, float], harmonics: List[int]) -> np.ndarray:
    y = np.full_like(theta, params.get("a0", 0.0), dtype=np.float64)
    for k in harmonics:
        ak = params.get(f"a{k}", 0.0)
        bk = params.get(f"b{k}", 0.0)
        y = y + ak * np.cos(k * theta) + bk * np.sin(k * theta)
    return y


def format_fit_label(params: Dict[str, float], harmonics: List[int]) -> str:
    parts = []
    if 4 in harmonics and "psi" in params:
        psi_deg_mod90 = (params["psi"] * 180.0 / np.pi) % 90.0
        parts.append(f"ψ={psi_deg_mod90:.2f}° (mod 90°)")
        parts.append(f"A4={params.get('A4', float('nan')):.3g}")
    if 2 in harmonics:
        parts.append(f"A2={params.get('A2', float('nan')):.3g}")
    if 8 in harmonics:
        parts.append(f"A8={params.get('A8', float('nan')):.3g}")
    parts.append(f"R²={params.get('R2', float('nan')):.3f}")
    return "fit: " + ", ".join(parts)


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
    params = None
    plt.figure(figsize=(9, 5))
    sc = plt.scatter(x, y, c=c, cmap="viridis", s=15, marker="o", label="data")

    if fit_x_is_angle and DO_FIT_ON_FOLDED:
        params = fit_fourier(x, y, FIT_HARMONICS)
        if params is not None:
            xs = np.linspace(0.0, 2.0 * np.pi, FIT_EVAL_SAMPLES)
            ys = eval_fourier(xs, params, FIT_HARMONICS)
            plt.plot(xs, ys, "-", color="red", linewidth=2.0, label=format_fit_label(params, FIT_HARMONICS))

    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.colorbar(sc, label="Rotation index")
    plt.grid(True)

    # Legend above plot, with a bit of top margin
    plt.legend(
        loc="lower center",
        bbox_to_anchor=(0.5, 1.12),
        ncol=1,
        frameon=True,
    )

    plt.tight_layout()
    plt.subplots_adjust(top=0.80)

    plt.savefig(outpath, dpi=150)
    plt.close()
    return params


def filter_encoder_outliers(encoders: np.ndarray, debug: bool = False) -> np.ndarray:
    """
    Returns mask of "good" samples (True = keep).
    Robust median-based outlier filter.
    """
    if encoders.size == 0:
        return np.array([], dtype=bool)

    med = float(np.median(encoders))
    if med < MIN_MEDIAN_FOR_FILTER:
        if debug:
            print(f"[DEBUG] Encoder median is tiny ({med}); skipping outlier filter.")
        return np.ones_like(encoders, dtype=bool)

    dev = np.abs(encoders - med)
    outlier = dev > (OUTLIER_FACTOR * med)

    keep = ~outlier
    if debug or True:
        n_out = int(np.sum(outlier))
        if n_out > 0:
            print(f"[INFO] Encoder outlier filter: removed {n_out}/{encoders.size} samples "
                  f"({100.0*n_out/encoders.size:.3f}%), median={med:.3g}, factor={OUTLIER_FACTOR}")
            # print a few examples
            bad_vals = encoders[outlier]
            show = bad_vals[:10]
            print(f"[INFO] Example outlier encoder values (up to 10): {show.tolist()}")
        else:
            print(f"[INFO] Encoder outlier filter: removed 0/{encoders.size} samples (median={med:.3g})")
    return keep


# Helpers for ROI detection + background estimation
def _flood_fill_bbox(mask: np.ndarray, sy: int, sx: int) -> Optional[Tuple[int, int, int, int, int]]:
    """
    Flood-fill from seed (sy,sx) over True pixels in mask.
    Returns (y0,y1,x0,x1,area) with y1/x1 exclusive, or None if seed not True.
    """
    if not mask[sy, sx]:
        return None

    h, w = mask.shape
    stack = [(sy, sx)]
    mask2 = mask.copy()
    mask2[sy, sx] = False

    y0 = y1 = sy
    x0 = x1 = sx
    area = 0

    while stack:
        y, x = stack.pop()
        area += 1
        if y < y0: y0 = y
        if y > y1: y1 = y
        if x < x0: x0 = x
        if x > x1: x1 = x

        # 4-neighborhood
        if y > 0 and mask2[y - 1, x]:
            mask2[y - 1, x] = False
            stack.append((y - 1, x))
        if y + 1 < h and mask2[y + 1, x]:
            mask2[y + 1, x] = False
            stack.append((y + 1, x))
        if x > 0 and mask2[y, x - 1]:
            mask2[y, x - 1] = False
            stack.append((y, x - 1))
        if x + 1 < w and mask2[y, x + 1]:
            mask2[y, x + 1] = False
            stack.append((y, x + 1))

    # make exclusive bounds
    return (y0, y1 + 1, x0, x1 + 1, area)


def detect_signal_roi_bbox(data: np.ndarray, debug: bool = False) -> Optional[Tuple[int, int, int, int, int, int]]:
    """
    Find brightest pixel (per-frame), threshold around it, flood-fill blob,
    then return padded bbox.

    Returns (y0,y1,x0,x1, y_peak, x_peak) or None.
    """
    h, w = data.shape
    y_peak, x_peak = np.unravel_index(np.argmax(data), data.shape)
    peak = float(data[y_peak, x_peak])

    if not np.isfinite(peak):
        return None

    thr = peak * BLOB_THRESH_FRAC_OF_PEAK
    mask = data >= thr

    blob = _flood_fill_bbox(mask, y_peak, x_peak)
    if blob is None:
        return None

    y0, y1, x0, x1, area = blob
    if area < MIN_BLOB_AREA:
        if debug:
            print(f"[DEBUG] Blob too small (area={area}), skipping frame.")
        return None

    # pad bbox
    y0 = max(0, y0 - ROI_PAD_PX)
    x0 = max(0, x0 - ROI_PAD_PX)
    y1 = min(h, y1 + ROI_PAD_PX)
    x1 = min(w, x1 + ROI_PAD_PX)

    # safety clamp on size
    if (y1 - y0) > MAX_ROI_SIDE:
        mid = (y0 + y1) // 2
        y0 = max(0, mid - MAX_ROI_SIDE // 2)
        y1 = min(h, y0 + MAX_ROI_SIDE)
    if (x1 - x0) > MAX_ROI_SIDE:
        mid = (x0 + x1) // 2
        x0 = max(0, mid - MAX_ROI_SIDE // 2)
        x1 = min(w, x0 + MAX_ROI_SIDE)

    return (y0, y1, x0, x1, y_peak, x_peak)


def background_stats_full_minus_roi(
    data: np.ndarray,
    y0: int, y1: int, x0: int, x1: int,
    guard_px: int = ROI_GUARD_PX,
) -> Tuple[float, float]:
    """
    Background from full frame minus (ROI expanded by guard band).
    Returns (bg_mean, bg_median).
    """
    h, w = data.shape

    gy0 = max(0, y0 - guard_px)
    gx0 = max(0, x0 - guard_px)
    gy1 = min(h, y1 + guard_px)
    gx1 = min(w, x1 + guard_px)

    bg_mask = np.ones((h, w), dtype=bool)
    bg_mask[gy0:gy1, gx0:gx1] = False

    bg_pixels = data[bg_mask].astype(np.float64)
    if bg_pixels.size == 0:
        # pathological; fall back to whole-frame stats
        bg_pixels = data.astype(np.float64).ravel()

    return float(np.mean(bg_pixels)), float(np.median(bg_pixels))


def main():
    import argparse

    # Local defaults from module-level constants
    default_counts_per_rev = counts_per_wheel_rev_guess
    default_roi_size = roi_size
    default_bg_y = background_yx[0]
    default_bg_x = background_yx[1]

    parser = argparse.ArgumentParser(description="Create scatter plots from FITS + encoder pickle.")
    parser.add_argument("--debug", action="store_true", help="Enable debug prints")
    parser.add_argument("--time-offset-hours", type=float, default=None, help="Manual time offset (hours)")
    parser.add_argument("--counts-per-rev", type=int, default=default_counts_per_rev,
                        help="Counts per full plate revolution")
    parser.add_argument("--fitlog-dir", default=None,
                        help="Directory for fit log file (default: <fits_exposure_dir>/plots)")
    #parser.add_argument("--fitlog-copy-dir", default=None,
                       # help="If set, also writes a copy of the fitlog to this directory")

    parser.add_argument("fits_exposure_dir", help="Exposure dir (exposures-...)")
    parser.add_argument("encoder_pkl", help="encoder_data_*.pkl path")

    args = parser.parse_args()

    DEBUG = bool(args.debug)
    manual_offset_sec = int(args.time_offset_hours * 3600) if args.time_offset_hours is not None else None

    # Apply overrides (LOCAL variables; no globals)
    counts_per_rev = int(args.counts_per_rev)
    fits_dir = args.fits_exposure_dir
    encoder_pkl = args.encoder_pkl

    fits_path = os.path.join(fits_dir, "processed", "fits")
    plot_base_dir = os.path.join(fits_dir, "plots")
    os.makedirs(plot_base_dir, exist_ok=True)

    fitlog_dir = args.fitlog_dir or plot_base_dir
    os.makedirs(fitlog_dir, exist_ok=True)

    fitlog_dt = datetime.now().astimezone().strftime("%Y-%m-%d_%H-%M-%S")
    fitlog_name = f"fitlog_{fitlog_dt}.log"

    fitlog_path = os.path.join(fitlog_dir, fitlog_name)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    fitlog_copy_dir = os.path.abspath(os.path.join(script_dir, "..", "multi-run-logs"))
    os.makedirs(fitlog_copy_dir, exist_ok=True)

    fitlog_copy_path = os.path.join(fitlog_copy_dir, fitlog_name)

    # Write to both destinations always
    fitlog_paths = [fitlog_path, fitlog_copy_path]

    def flog_write(line: str):
        for p in fitlog_paths:
            with open(p, "a") as _f:
                _f.write(line)

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
        print(f"[DEBUG] Fit harmonics: {FIT_HARMONICS}")
        print(f"[DEBUG] counts_per_rev={counts_per_rev}")
        print(f"[DEBUG] ROI tracking: thresh_frac={BLOB_THRESH_FRAC_OF_PEAK} pad={ROI_PAD_PX} guard={ROI_GUARD_PX}")

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

    encoder_vals = []
    vals = {k: [] for k in plot_types}

    skip_no_dateobs = 0
    skip_bad_dateobs = 0
    skip_no_encoder_match = 0
    skip_bad_roi = 0
    skip_no_blob = 0  # NEW

    t0 = time.time()
    total_files = len(fits_files)

    for i, ffile in enumerate(fits_files, start=1):
        if i == 1 or i % 200 == 0 or i == total_files:
            elapsed = time.time() - t0
            rate = i / elapsed if elapsed > 0 else 0.0
            print(f"[INFO] Processing FITS {i}/{total_files} ({rate:.1f} files/s)")

        fits_time_str = fits.getheader(ffile).get("DATE-OBS")
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
            continue

        data = fits.getdata(ffile, extname="GREEN1").astype(np.float64)

        # per-frame ROI detection + tracking
        roi_info = detect_signal_roi_bbox(data, debug=DEBUG)
        if roi_info is None:
            skip_no_blob += 1
            continue

        y0, y1, x0, x1, y_peak, x_peak = roi_info

        # sanity
        if y1 <= y0 or x1 <= x0:
            skip_bad_roi += 1
            continue

        roi = data[y0:y1, x0:x1]

        # background tied to ROI (full frame minus ROI+guard)
        bg_mean, bg_median = background_stats_full_minus_roi(data, y0, y1, x0, x1, guard_px=ROI_GUARD_PX)

        # scalar ROI stats
        roi_sum = float(np.sum(roi))
        roi_mean = float(np.mean(roi))
        roi_median = float(np.median(roi))
        n_roi_pix = roi.size

        encoder_vals.append(int(encoder_val))

        # background-subtracted values (scalar subtraction only)
        vals["one_pixel"].append(float(data[y_peak, x_peak]) - bg_mean)
        vals["ROI_sum"].append(roi_sum - bg_mean * n_roi_pix)
        vals["ROI_average"].append(roi_mean - bg_mean)
        vals["ROI_median"].append(roi_median - bg_median)

    encoders = np.array(encoder_vals, dtype=np.int64)

    if DEBUG:
        print("\n[DEBUG] ===== Match Summary =====")
        print(f"[DEBUG] FITS total: {len(fits_files)}")
        print(f"[DEBUG] matched: {len(encoders)}")
        print(f"[DEBUG] skip_no_dateobs: {skip_no_dateobs}")
        print(f"[DEBUG] skip_bad_dateobs: {skip_bad_dateobs}")
        print(f"[DEBUG] skip_no_encoder_match: {skip_no_encoder_match}")
        print(f"[DEBUG] skip_bad_roi: {skip_bad_roi}")
        print(f"[DEBUG] skip_no_blob: {skip_no_blob}")

    if len(encoders) == 0:
        print("[ERR ] No matched frames. Nothing to plot.")
        sys.exit(1)

    # --- Filter outlier encoder values ---
    keep_mask = np.ones_like(encoders, dtype=bool)
    if FILTER_ENCODER_OUTLIERS:
        keep_mask = filter_encoder_outliers(encoders, debug=DEBUG)

    if not np.all(keep_mask):
        encoders = encoders[keep_mask]
        for k in plot_types:
            vals[k] = list(np.asarray(vals[k])[keep_mask])

    # --- Recompute block to attempt to make angles "absolute" ---
    enc = encoders.astype(np.int64)
    frac = (enc.astype(np.float64) / float(counts_per_rev)) % 1.0
    angles = frac * 2.0 * np.pi
    rotations = (enc // counts_per_rev).astype(np.int64)

    print(f"[INFO] Final samples after filtering: {len(encoders)}")

    # --- Plotting ---
    print("\n[INFO] Generating plots and fit log...")
    plot_t0 = time.time()

    for p in fitlog_paths:
        with open(p, "w") as _f:
            pass

    flog_write(f"fitlog created: {fitlog_dt}\n")
    flog_write(f"fits_dir: {fits_dir}\n")
    flog_write(f"encoder_pkl: {encoder_pkl}\n")
    flog_write(f"counts_per_rev: {counts_per_rev}\n")
    flog_write(f"bg_mode: full_frame_minus_signal_roi_plus_guard\n")
    flog_write(f"roi_mode: auto_blob_bbox\n")
    flog_write(f"roi_pad_px: {ROI_PAD_PX}\n")
    flog_write(f"roi_guard_px: {ROI_GUARD_PX}\n")
    flog_write(f"blob_thresh_frac_of_peak: {BLOB_THRESH_FRAC_OF_PEAK}\n")
    flog_write(f"time_offset_sec: {offset_sec}\n")
    flog_write(f"fit_harmonics: {FIT_HARMONICS}\n")
    flog_write(f"n_samples: {len(encoders)}\n")
    flog_write("\n# per-trace fits (psi_deg_mod90, A4, A2, R2)\n")

    for j, k in enumerate(plot_types, start=1):
        print(f"[INFO] Plot {j}/{len(plot_types)}: {k}")
        y = np.array(vals[k], dtype=np.float64)

        save_scatter_plot(
            encoders, y, rotations,
            "Encoder Count", k.replace("_", " ").title(),
            f"{k.replace('_', ' ').title()} vs Encoder",
            outpath=os.path.join(plot_base_dir, k, f"{k}_vs_encoder.png"),
            fit_x_is_angle=False,
        )

        params = save_scatter_plot(
            angles, y, rotations,
            "Plate Angle (rad)", k.replace("_", " ").title(),
            f"{k.replace('_', ' ').title()} vs Plate Angle",
            outpath=os.path.join(plot_base_dir, k, f"{k}_vs_angle.png"),
            fit_x_is_angle=True,
        )

        if params is None:
            flog_write(f"{k}: NO_FIT\n")
        else:
            psi_deg_mod90 = (params.get("psi", float("nan")) * 180.0 / np.pi) % 90.0
            A4 = params.get("A4", float("nan"))
            A2 = params.get("A2", float("nan"))
            R2 = params.get("R2", float("nan"))
            flog_write(f"{k}: psi_deg_mod90={psi_deg_mod90:.4f}, A4={A4:.6g}, A2={A2:.6g}, R2={R2:.6f}\n")

    # raw data dump (unchanged format)
    flog_write("\n# raw_data\n")
    flog_write("# Columns:\n")
    flog_write("# idx, encoder_count, rotation_index, plate_angle_rad, " + ", ".join(plot_types) + "\n")
    flog_write("# Notes:\n")
    flog_write("# - encoder_count is the matched encoder sample after time-offset + filtering\n")
    flog_write("# - rotation_index = encoder_count // counts_per_rev\n")
    flog_write("# - plate_angle_rad = ((encoder_count / counts_per_rev) % 1) * 2*pi\n")
    flog_write("# - intensity columns correspond to the arrays used for plots\n")
    flog_write("#\n")

    header = "idx,encoder_count,rotation_index,plate_angle_rad," + ",".join(plot_types) + "\n"
    flog_write(header)

    # Make sure we have numpy arrays for consistent indexing
    y_arrays = {k: np.asarray(vals[k]) for k in plot_types}

    for i in range(len(encoders)):
        row_vals = [
            str(i),
            str(int(encoders[i])),
            str(int(rotations[i])),
            f"{float(angles[i]):.10g}",
        ]
        for k in plot_types:
            v = y_arrays[k][i]
            row_vals.append(f"{float(v):.10g}")
        flog_write(",".join(row_vals) + "\n")

    print(f"[INFO] Plot generation completed in {time.time() - plot_t0:.1f} s")
    print(f"[INFO] Total runtime: {time.time() - t0:.1f} s")
    print("All plots saved to:", plot_base_dir)


if __name__ == "__main__":
    main()