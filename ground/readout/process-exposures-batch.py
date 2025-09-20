#!/usr/bin/env python3

import os
import sys
import argparse
from datetime import datetime
import numpy as np
import matplotlib.pyplot as plt
from astropy.io import fits

def extract_timestamp_from_filename(filename):
    """
    Extract timestamp from filenames like: exposure-YYYYMMDD-HHMMSS-mmm.bin
    """
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
        print(f"Warning: failed to parse timestamp from {filename}: {e}")
        return "UNKNOWN"

def process_bin_file(bin_path, output_dirs, skip_green, skip_color, skip_fits):
    width, height = 3096, 2080
    base_name = os.path.splitext(os.path.basename(bin_path))[0]

    # === Load raw data ===
    with open(bin_path, "rb") as f:
        pixel_data = np.frombuffer(f.read(), dtype=np.uint16).reshape((height, width))

    # === Extract raw channels (for FITS) ===
    red    = pixel_data[::2, ::2]
    green1 = pixel_data[::2, 1::2]
    green2 = pixel_data[1::2, ::2]
    blue   = pixel_data[1::2, 1::2]
    color  = np.stack([red, green1, blue], axis=-1)

    # === Scaled 8-bit versions (for PNG previews only) ===
    preview_data = (pixel_data / pixel_data.max() * 255).astype(np.uint8)
    red_preview    = preview_data[::2, ::2]
    green1_preview = preview_data[::2, 1::2]
    blue_preview   = preview_data[1::2, 1::2]
    color_preview  = np.stack([red_preview, green1_preview, blue_preview], axis=-1)
    green_preview  = green1_preview.astype(np.uint8)

    timestamp = extract_timestamp_from_filename(bin_path)

    # === Create FITS with raw data ===
    if not skip_fits:
        hdul = fits.HDUList()
        hdu_gray = fits.PrimaryHDU(pixel_data)
        hdu_gray.header['DATE-OBS'] = timestamp
        hdul.append(hdu_gray)
        hdul.append(fits.ImageHDU(red,    name='RED'))
        hdul.append(fits.ImageHDU(green1, name='GREEN1'))
        hdul.append(fits.ImageHDU(green2, name='GREEN2'))
        hdul.append(fits.ImageHDU(blue,   name='BLUE'))
        hdul.append(fits.ImageHDU(color,  name='COLOR_COMPOSITE'))

        fits_path = os.path.join(output_dirs["fits"], base_name + ".fits")
        hdul.writeto(fits_path, overwrite=True)
        print(f"✓ FITS saved: {fits_path}")

    # === Save PNG previews (scaled) ===
    if not skip_color:
        color_path = os.path.join(output_dirs["color"], base_name + "_color.png")
        plt.imsave(color_path, color_preview)
        print(f"✓ Color preview: {color_path}")

    if not skip_green:
        green_path = os.path.join(output_dirs["green"], base_name + "_green.png")
        plt.imsave(green_path, green_preview, cmap="gray")
        print(f"✓ Green preview: {green_path}")

def main():
    parser = argparse.ArgumentParser(description="Batch process .bin files to FITS and previews.")
    parser.add_argument("base_dir", help="Path to exposure directory (e.g., exposures-YYYYMMDD-HHMMSS)")
    parser.add_argument("--no-color", action="store_true", help="Skip color preview generation")
    parser.add_argument("--no-green", action="store_true", help="Skip green preview generation")
    parser.add_argument("--no-fits", action="store_true", help="Skip FITS file generation")
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

    output_dirs = {
        "fits": fits_dir,
        "color": color_dir,
        "green": green_dir,
    }

    bin_files = sorted(f for f in os.listdir(raw_dir) if f.endswith(".bin"))
    if not bin_files:
        print("No .bin files found.")
        sys.exit(0)

    for i, fname in enumerate(bin_files, 1):
        full_path = os.path.join(raw_dir, fname)
        print(f"[{i}/{len(bin_files)}] Processing: {fname}")
        process_bin_file(full_path, output_dirs, args.no_green, args.no_color, args.no_fits)

    print("\n✅ Batch processing complete.")

if __name__ == "__main__":
    main()