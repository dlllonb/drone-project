#!/usr/bin/env python3
"""
Calibrate star camera FITS images using master bias, dark, and flat frames.

Pipeline:
    calibrated = (raw - master_bias - scaled_master_dark) / normalized_master_flat

Assumptions:
    - Raw science FITS files are in an input directory.
    - Master calibration frames already exist in a calibration/ subdirectory.
    - FITS header contains EXPTIME for science and dark frames.
    - Master flat is normalized internally by this script.

Example usage:
python3 calibrate_images.py
    --input-dir raw
    --output-dir calibrated 
    --calib-dir calibration
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Tuple

import numpy as np
from astropy.io import fits


def load_fits_data_and_header(path: Path) -> Tuple[np.ndarray, fits.Header]:
    """Load FITS data and header as float64 for safe arithmetic."""
    with fits.open(path) as hdul:
        data = hdul[0].data.astype(np.float64)
        header = hdul[0].header.copy()
    return data, header


def get_exptime(header: fits.Header, fallback: float | None = None) -> float:
    """Get exposure time from FITS header."""
    if "EXPTIME" in header:
        return float(header["EXPTIME"])
    if fallback is not None:
        return float(fallback)
    raise KeyError("EXPTIME not found in FITS header and no fallback provided.")


def normalize_flat(master_flat: np.ndarray, min_valid: float = 1e-8) -> np.ndarray:
    """
    Normalize flat by its median over valid pixels.
    Rejects non-positive or near-zero flat normalization values.
    """
    median_val = np.median(master_flat[np.isfinite(master_flat)])
    if not np.isfinite(median_val) or median_val <= min_valid:
        raise ValueError(
            f"Master flat median is invalid for normalization: {median_val}"
        )
    return master_flat / median_val


def scale_dark(master_dark: np.ndarray, dark_exptime: float, science_exptime: float) -> np.ndarray:
    """
    Scale master dark to match science exposure time.
    Assumes master dark is in units of counts for its own EXPTIME.
    """
    if dark_exptime <= 0:
        raise ValueError(f"Invalid dark exposure time: {dark_exptime}")
    scale = science_exptime / dark_exptime
    return master_dark * scale


def calibrate_image(
    raw_data: np.ndarray,
    raw_header: fits.Header,
    master_bias: np.ndarray,
    master_dark: np.ndarray,
    dark_header: fits.Header,
    master_flat_norm: np.ndarray,
    flat_epsilon: float = 1e-8,
) -> np.ndarray:
    """Apply bias subtraction, dark subtraction, and flat-field correction."""
    sci_exptime = get_exptime(raw_header)
    dark_exptime = get_exptime(dark_header)

    scaled_dark = scale_dark(master_dark, dark_exptime, sci_exptime)

    corrected = raw_data - master_bias - scaled_dark

    safe_flat = np.where(np.abs(master_flat_norm) < flat_epsilon, np.nan, master_flat_norm)
    calibrated = corrected / safe_flat

    return calibrated


def write_fits(output_path: Path, data: np.ndarray, header: fits.Header) -> None:
    """Write calibrated data to FITS with updated header."""
    header = header.copy()
    header["HISTORY"] = "Bias subtracted"
    header["HISTORY"] = "Dark subtracted (scaled by EXPTIME)"
    header["HISTORY"] = "Flat-field corrected using normalized master flat"
    header["BUNIT"] = "counts"

    hdu = fits.PrimaryHDU(data=data.astype(np.float32), header=header)
    hdu.writeto(output_path, overwrite=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Calibrate raw FITS images using master bias, dark, and flat."
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        required=True,
        help="Directory containing raw FITS science images",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory to write calibrated FITS images",
    )
    parser.add_argument(
        "--calib-dir",
        type=Path,
        default=Path("calibration"),
        help="Directory containing master_bias.fits, master_dark.fits, master_flat.fits",
    )
    parser.add_argument(
        "--glob",
        type=str,
        default="*.fits",
        help="Glob pattern for input FITS files",
    )
    args = parser.parse_args()

    input_dir = args.input_dir
    output_dir = args.output_dir
    calib_dir = args.calib_dir

    output_dir.mkdir(parents=True, exist_ok=True)

    bias_path = calib_dir / "master_bias.fits"
    dark_path = calib_dir / "master_dark.fits"
    flat_path = calib_dir / "master_flat.fits"

    if not bias_path.exists():
        raise FileNotFoundError(f"Missing master bias: {bias_path}")
    if not dark_path.exists():
        raise FileNotFoundError(f"Missing master dark: {dark_path}")
    if not flat_path.exists():
        raise FileNotFoundError(f"Missing master flat: {flat_path}")

    master_bias, bias_header = load_fits_data_and_header(bias_path)
    master_dark, dark_header = load_fits_data_and_header(dark_path)
    master_flat, flat_header = load_fits_data_and_header(flat_path)

    if not (master_bias.shape == master_dark.shape == master_flat.shape):
        raise ValueError(
            "Master calibration frames do not all have the same shape: "
            f"bias={master_bias.shape}, dark={master_dark.shape}, flat={master_flat.shape}"
        )

    master_flat_norm = normalize_flat(master_flat)

    raw_paths = sorted(input_dir.glob(args.glob))
    if not raw_paths:
        raise FileNotFoundError(f"No FITS files found in {input_dir} matching {args.glob}")

    for raw_path in raw_paths:
        raw_data, raw_header = load_fits_data_and_header(raw_path)

        if raw_data.shape != master_bias.shape:
            print(f"Skipping {raw_path.name}: shape {raw_data.shape} != {master_bias.shape}")
            continue

        calibrated = calibrate_image(
            raw_data=raw_data,
            raw_header=raw_header,
            master_bias=master_bias,
            master_dark=master_dark,
            dark_header=dark_header,
            master_flat_norm=master_flat_norm,
        )

        out_name = raw_path.stem + "_calibrated.fits"
        out_path = output_dir / out_name
        write_fits(out_path, calibrated, raw_header)

        print(f"Calibrated: {raw_path.name} -> {out_path.name}")


if __name__ == "__main__":
    main()