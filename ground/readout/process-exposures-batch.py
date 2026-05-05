#!/usr/bin/env python3
"""
process-exposures-batch.py
==========================

Purpose
-------
Batch-converts raw camera `.bin` files from an exposure directory into FITS
files and optional PNG preview images.

This script is the main raw-image processing step in the polarimeter ground
pipeline. During normal operation it is called by `run-end-to-end.sh` after
camera acquisition finishes. It can also be run manually to reprocess existing
raw data.

Input Directory
---------------
The script expects an exposure directory with raw binary frames stored under:

    exposures-.../
        raw/
            exposure-YYYYMMDD-HHMMSS-mmm.bin

Command-line usage:

    python3 process-exposures-batch.py <exposure_dir>

Options
-------
    --no-color
        Skip color PNG preview generation.

    --no-green
        Skip green-channel PNG preview generation.

    --no-fits
        Skip FITS generation.

    --jobs <N>
        Number of multiprocessing workers. If 0 or negative, defaults to
        cpu_count() - 1.

    --quiet
        Reduce per-file output.

Outputs
-------
Outputs are written under:

    exposures-.../
        processed/
            fits/
            color/
            green/

FITS files contain the full raw frame in the primary HDU and Bayer-channel
extensions named RED, GREEN1, GREEN2, BLUE, and COLOR_COMPOSITE.

PNG previews are scaled to 8-bit for quick inspection. Because these previews
are extracted from Bayer channels, their dimensions are half the raw sensor
resolution.

Assumptions
-----------
Raw `.bin` files are interpreted as unsigned 16-bit images with fixed camera
geometry:

    width  = 3096
    height = 2080

If camera output settings change, these constants must be updated.
"""
import os
import sys
import argparse
from datetime import datetime
import numpy as np
from astropy.io import fits
import imageio.v2 as imageio
from multiprocessing import Pool, cpu_count

WIDTH, HEIGHT = 3096, 2080

def extract_timestamp_from_filename(filename: str) -> str:
    base = os.path.basename(filename)
    name, _ = os.path.splitext(base)
    try:
        parts = name.split("-")
        if len(parts) < 4:
            raise ValueError("Invalid timestamp format in filename")
        date_str, time_str, ms_str = parts[1], parts[2], parts[3]
        dt = datetime.strptime(date_str + time_str, "%Y%m%d%H%M%S")
        dt = dt.replace(microsecond=int(ms_str) * 1000)
        return dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    except Exception as e:
        return "UNKNOWN"

def process_one(args):
    bin_path, output_dirs, skip_green, skip_color, skip_fits, quiet = args
    base_name = os.path.splitext(os.path.basename(bin_path))[0]

    # Load once
    with open(bin_path, "rb") as f:
        pixel_data = np.frombuffer(f.read(), dtype=np.uint16).reshape((HEIGHT, WIDTH))

    timestamp = extract_timestamp_from_filename(bin_path)

    # --- FITS (raw) ---
    if not skip_fits:
        # Raw channels (uint16), only if writing FITS
        red    = pixel_data[::2, ::2]
        green1 = pixel_data[::2, 1::2]
        green2 = pixel_data[1::2, ::2]
        blue   = pixel_data[1::2, 1::2]
        color  = np.stack([red, green1, blue], axis=-1)

        hdul = fits.HDUList([
            fits.PrimaryHDU(pixel_data),
            fits.ImageHDU(red,    name="RED"),
            fits.ImageHDU(green1, name="GREEN1"),
            fits.ImageHDU(green2, name="GREEN2"),
            fits.ImageHDU(blue,   name="BLUE"),
            fits.ImageHDU(color,  name="COLOR_COMPOSITE"),
        ])
        hdul[0].header["DATE-OBS"] = timestamp

        fits_path = os.path.join(output_dirs["fits"], base_name + ".fits")
        hdul.writeto(fits_path, overwrite=True)
        if not quiet:
            print(f"✓ FITS: {os.path.basename(fits_path)}")

    # --- PNG previews (scaled) ---
    if (not skip_color) or (not skip_green):
        # Scale once, only if doing previews
        maxv = int(pixel_data.max())
        if maxv <= 0:
            preview = np.zeros_like(pixel_data, dtype=np.uint8)
        else:
            preview = (pixel_data.astype(np.float32) * (255.0 / maxv)).astype(np.uint8)

        if not skip_color:
            red_p    = preview[::2, ::2]
            green1_p = preview[::2, 1::2]
            blue_p   = preview[1::2, 1::2]
            color_p  = np.stack([red_p, green1_p, blue_p], axis=-1)
            color_path = os.path.join(output_dirs["color"], base_name + "_color.png")
            imageio.imwrite(color_path, color_p)
            if not quiet:
                print(f"✓ PNG:  {os.path.basename(color_path)}")

        if not skip_green:
            green_p = preview[::2, 1::2]
            green_path = os.path.join(output_dirs["green"], base_name + "_green.png")
            imageio.imwrite(green_path, green_p)
            if not quiet:
                print(f"✓ PNG:  {os.path.basename(green_path)}")

    return base_name

def main():
    parser = argparse.ArgumentParser(description="Batch process .bin files to FITS and previews (fast).")
    parser.add_argument("base_dir", help="Exposure directory (e.g., exposures-YYYYMMDD-HHMMSS-mmm)")
    parser.add_argument("--no-color", action="store_true", help="Skip color preview generation")
    parser.add_argument("--no-green", action="store_true", help="Skip green preview generation")
    parser.add_argument("--no-fits", action="store_true", help="Skip FITS generation")
    parser.add_argument("--jobs", type=int, default=0, help="Worker processes (default: cpu_count-1)")
    parser.add_argument("--quiet", action="store_true", help="Reduce output")
    args = parser.parse_args()

    raw_dir = os.path.join(args.base_dir, "raw")
    proc_dir = os.path.join(args.base_dir, "processed")
    fits_dir = os.path.join(proc_dir, "fits")
    color_dir = os.path.join(proc_dir, "color")
    green_dir = os.path.join(proc_dir, "green")

    if not os.path.isdir(raw_dir):
        print(f"Error: {raw_dir} does not exist.")
        sys.exit(1)

    if not args.no_fits:
        os.makedirs(fits_dir, exist_ok=True)
    if not args.no_color:
        os.makedirs(color_dir, exist_ok=True)
    if not args.no_green:
        os.makedirs(green_dir, exist_ok=True)

    output_dirs = {"fits": fits_dir, "color": color_dir, "green": green_dir}

    bin_files = sorted(
        os.path.join(raw_dir, f) for f in os.listdir(raw_dir) if f.endswith(".bin")
    )
    if not bin_files:
        print("No .bin files found.")
        return

    jobs = args.jobs
    if jobs <= 0:
        jobs = max(1, cpu_count() - 1)

    work = [(p, output_dirs, args.no_green, args.no_color, args.no_fits, args.quiet) for p in bin_files]

    if not args.quiet:
        print(f"Found {len(bin_files)} .bin files. Using {jobs} workers.")

    # Multiprocessing
    with Pool(processes=jobs) as pool:
        for i, _ in enumerate(pool.imap_unordered(process_one, work), 1):
            if not args.quiet and (i % 25 == 0 or i == len(bin_files)):
                print(f"[{i}/{len(bin_files)}] done")

    print("✅ Batch processing complete.")

if __name__ == "__main__":
    main()