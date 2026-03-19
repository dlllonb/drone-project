#!/usr/bin/env python3
"""
Calibrate star camera FITS images using master bias, dark, and flat frames.

Pipeline:
    calibrated = (raw - master_bias - scaled_master_dark) / normalized_master_flat

This version also standardizes the output FITS header so downstream code in
the measure/ pipeline can read metadata using canonical keyword names.

Assumptions:
    - Raw science FITS files are in an input directory.
    - Master calibration frames already exist in a calibration/ subdirectory.
    - Exposure time may be stored in EXPTIME, EXPOSURE, or TEXPS.
    - Master flat is normalized internally by this script.
    - Master dark is assumed to be in counts for its own EXPTIME and is scaled
      linearly to the science exposure time.

Example usage:
python3 calibrate_images.py \
    --input-dir raw \
    --output-dir calibrated \
    --calib-dir calibration
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Tuple

import numpy as np
from astropy.io import fits


def load_fits_data_and_header(path: Path) -> Tuple[np.ndarray, fits.Header]:
    """Load FITS data and header as float64 for safe arithmetic."""
    with fits.open(path) as hdul:
        data = hdul[0].data
        header = hdul[0].header.copy()

    if data is None:
        raise ValueError(f"FITS file contains no data: {path}")
    if data.ndim != 2:
        raise ValueError(f"Expected a 2-D FITS image, got ndim={data.ndim} for {path}")

    return data.astype(np.float64), header


def get_header_value(header: fits.Header, *keys: str) -> Any:
    """Return the first present, non-None header value among candidate keys."""
    for key in keys:
        if key in header and header[key] is not None:
            return header[key]
    return None


def get_exptime(header: fits.Header, fallback: float | None = None) -> float:
    """Get exposure time from FITS header using accepted aliases."""
    value = get_header_value(header, "EXPTIME", "EXPOSURE", "TEXPS")
    if value is not None:
        return float(value)
    if fallback is not None:
        return float(fallback)
    raise KeyError("Exposure time not found in EXPTIME, EXPOSURE, or TEXPS.")


def normalize_flat(master_flat: np.ndarray, min_valid: float = 1e-8) -> Tuple[np.ndarray, float]:
    """
    Normalize flat by its median over finite pixels.

    Returns
    -------
    normalized_flat : np.ndarray
        Normalized master flat.
    median_val : float
        Median used for normalization.
    """
    finite = master_flat[np.isfinite(master_flat)]
    if finite.size == 0:
        raise ValueError("Master flat contains no finite pixels.")

    median_val = float(np.median(finite))
    if not np.isfinite(median_val) or median_val <= min_valid:
        raise ValueError(
            f"Master flat median is invalid for normalization: {median_val}"
        )

    return master_flat / median_val, median_val


def scale_dark(master_dark: np.ndarray, dark_exptime: float, science_exptime: float) -> Tuple[np.ndarray, float]:
    """
    Scale master dark to match science exposure time.

    Assumes master dark is in counts for its own EXPTIME.
    """
    if dark_exptime <= 0:
        raise ValueError(f"Invalid dark exposure time: {dark_exptime}")
    scale = science_exptime / dark_exptime
    return master_dark * scale, scale


def calibrate_image(
    raw_data: np.ndarray,
    raw_header: fits.Header,
    master_bias: np.ndarray,
    master_dark: np.ndarray,
    dark_header: fits.Header,
    master_flat_norm: np.ndarray,
    flat_epsilon: float = 1e-8,
) -> Tuple[np.ndarray, float, float]:
    """
    Apply bias subtraction, dark subtraction, and flat-field correction.

    Returns
    -------
    calibrated : np.ndarray
        Calibrated image.
    sci_exptime : float
        Science exposure time in seconds.
    dark_scale : float
        Factor used to scale the master dark.
    """
    sci_exptime = get_exptime(raw_header)
    dark_exptime = get_exptime(dark_header)

    scaled_dark, dark_scale = scale_dark(master_dark, dark_exptime, sci_exptime)
    corrected = raw_data - master_bias - scaled_dark

    safe_flat = np.array(master_flat_norm, copy=True)
    bad_flat = (~np.isfinite(safe_flat)) | (np.abs(safe_flat) < flat_epsilon)
    safe_flat[bad_flat] = np.nan

    calibrated = corrected / safe_flat
    return calibrated, sci_exptime, dark_scale


def first_present(header: fits.Header, *keys: str) -> Any:
    """Alias helper for readability in header standardization."""
    return get_header_value(header, *keys)


def standardize_measurement_header(
    raw_header: fits.Header,
    calibrated_shape: tuple[int, int],
    input_filename: str,
    bias_name: str,
    dark_name: str,
    flat_name: str,
    flat_norm_value: float,
    dark_scale_factor: float,
) -> fits.Header:
    """
    Create an output header with canonical keywords expected by the
    downstream measurement pipeline.
    """
    hdr = raw_header.copy()

    ny, nx = calibrated_shape
    hdr["NAXIS1"] = nx
    hdr["NAXIS2"] = ny

    # Canonical mappings expected by measure.types.MeasurementMetadata.from_header
    mappings = {
        "RA0": ("RA0", "CRVAL1", "RA"),
        "DEC0": ("DEC0", "CRVAL2", "DEC"),
        "ROT": ("ROT", "ROLL"),
        "PLTSCL": ("PLTSCL", "PIXSCL", "PIXSCALE"),
        "PIXSIZE": ("PIXSIZE", "PIXEL", "PIXELSIZE"),
        "FOCALLEN": ("FOCALLEN", "FOCAL", "FL"),
        "FNUMBER": ("FNUMBER", "FNO", "F/#"),
        "EXPTIME": ("EXPTIME", "EXPOSURE", "TEXPS"),
        "RDNOISE": ("RDNOISE", "READNOI"),
        "GAIN": ("GAIN", "GAINE"),
        "QE": ("QE",),
        "LAMBDAN": ("LAMBDAN", "WAVELEN"),
        "BANDWID": ("BANDWID", "BAND"),
        "JITRMS": ("JITRMS", "JITTER"),
        "MASKKIND": ("MASKKIND", "MASK"),
        "MASKANG": ("MASKANG",),
        "GRATLIN": ("GRATLIN",),
    }

    for canonical_key, candidates in mappings.items():
        value = first_present(raw_header, *candidates)
        if value is not None:
            hdr[canonical_key] = value

    hdr["FILENAME"] = input_filename
    hdr["BUNIT"] = "calibrated_counts"
    hdr["CALIB"] = True
    hdr["CALTYPE"] = "BIAS,DARK,FLAT"

    # Provenance
    hdr["MBIAS"] = bias_name
    hdr["MDARK"] = dark_name
    hdr["MFLAT"] = flat_name
    hdr["DARKSCAL"] = float(dark_scale_factor)
    hdr["FLATNORM"] = float(flat_norm_value)

    hdr["HISTORY"] = "Bias subtracted"
    hdr["HISTORY"] = "Dark subtracted (scaled by EXPTIME/EXPOSURE/TEXPS)"
    hdr["HISTORY"] = "Flat-field corrected using normalized master flat"
    hdr["HISTORY"] = "Header standardized for measure.MeasurementMetadata"

    return hdr


def write_fits(
    output_path: Path,
    data: np.ndarray,
    raw_header: fits.Header,
    input_filename: str,
    bias_name: str,
    dark_name: str,
    flat_name: str,
    flat_norm_value: float,
    dark_scale_factor: float,
) -> None:
    """Write calibrated data to FITS with standardized measurement header."""
    header = standardize_measurement_header(
        raw_header=raw_header,
        calibrated_shape=data.shape,
        input_filename=input_filename,
        bias_name=bias_name,
        dark_name=dark_name,
        flat_name=flat_name,
        flat_norm_value=flat_norm_value,
        dark_scale_factor=dark_scale_factor,
    )

    hdu = fits.PrimaryHDU(data=data.astype(np.float32), header=header)
    hdu.writeto(output_path, overwrite=True)


def validate_with_measurement_parser(output_path: Path) -> None:
    """
    Smoke-test the output header against the downstream measurement parser.

    This is optional and only runs if the tele-img-sim measure package is importable.
    """
    try:
        from measure.types import MeasurementMetadata
    except ImportError:
        print(f"[warn] Could not import measure.types for validation: {output_path.name}")
        return

    with fits.open(output_path) as hdul:
        header = hdul[0].header
        meta = MeasurementMetadata.from_header(header)

    print(
        f"[validate] {output_path.name}: "
        f"EXPTIME={meta.exposure_s}, "
        f"PIXSIZE={meta.pixel_size_um}, "
        f"FOCALLEN={meta.focal_length_mm}, "
        f"RA0={meta.ra_deg}, DEC0={meta.dec_deg}, ROT={meta.rot_deg}"
    )


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
    parser.add_argument(
        "--validate-measure-header",
        action="store_true",
        help="Smoke-test output headers with measure.types.MeasurementMetadata",
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

    master_flat_norm, flat_norm_value = normalize_flat(master_flat)

    raw_paths = sorted(input_dir.glob(args.glob))
    if not raw_paths:
        raise FileNotFoundError(f"No FITS files found in {input_dir} matching {args.glob}")

    for raw_path in raw_paths:
        raw_data, raw_header = load_fits_data_and_header(raw_path)

        if raw_data.shape != master_bias.shape:
            print(
                f"Skipping {raw_path.name}: "
                f"shape {raw_data.shape} != {master_bias.shape}"
            )
            continue

        calibrated, sci_exptime, dark_scale_factor = calibrate_image(
            raw_data=raw_data,
            raw_header=raw_header,
            master_bias=master_bias,
            master_dark=master_dark,
            dark_header=dark_header,
            master_flat_norm=master_flat_norm,
        )

        out_name = raw_path.stem + "_calibrated.fits"
        out_path = output_dir / out_name

        write_fits(
            output_path=out_path,
            data=calibrated,
            raw_header=raw_header,
            input_filename=raw_path.name,
            bias_name=bias_path.name,
            dark_name=dark_path.name,
            flat_name=flat_path.name,
            flat_norm_value=flat_norm_value,
            dark_scale_factor=dark_scale_factor,
        )

        print(
            f"Calibrated: {raw_path.name} -> {out_path.name} "
            f"(EXPTIME={sci_exptime:.3f}s, DARKSCAL={dark_scale_factor:.6f})"
        )

        if args.validate_measure_header:
            validate_with_measurement_parser(out_path)


if __name__ == "__main__":
    main()