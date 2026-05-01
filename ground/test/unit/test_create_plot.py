import pickle
import re
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

import numpy as np
from astropy.io import fits

ROOT = Path(__file__).resolve().parents[2]
CREATE_PLOT = ROOT / "readout" / "create-plot.py"


def make_test_fits(path: Path, date_obs: str, intensity: float):
    data = np.zeros((64, 64), dtype=np.float32)

    # Large bright square so the padded ROI still has a nonzero median.
    # create-plot.py pads the detected blob by ROI_PAD_PX=4, so a tiny
    # blob would make ROI_median mostly background and produce R2=nan.
    data[22:42, 22:42] = intensity

    primary = fits.PrimaryHDU()
    green1 = fits.ImageHDU(data=data, name="GREEN1")
    hdul = fits.HDUList([primary, green1])

    hdul[0].header["DATE-OBS"] = date_obs
    hdul.writeto(path)

def parse_r2_values(fitlog_text: str):
    r2_values = []
    for line in fitlog_text.splitlines():
        match = re.search(r"R2=([0-9.+\-eE]+|nan|inf|-inf)", line)
        if match:
            r2_values.append(float(match.group(1)))
    return r2_values


def test_create_plot_with_synthetic_data_outputs_plots_and_valid_fitlog(tmp_path):
    exposure_dir = tmp_path / "exposures-test"
    fits_dir = exposure_dir / "processed" / "fits"
    fits_dir.mkdir(parents=True)

    start = datetime.now(timezone.utc)

    n = 80
    counts_per_rev = 2400

    counts = np.linspace(0, counts_per_rev * 2, n)
    theta = ((counts / counts_per_rev) % 1.0) * 2.0 * np.pi

    # Strong clean 4-theta signal, matching the Fourier model in create-plot.py.
    intensities = 1000.0 + 200.0 * np.cos(4.0 * theta)

    encoder_data = {}

    for i in range(n):
        t = start + timedelta(seconds=i * 0.1)
        ts_ms = int(t.timestamp() * 1000)
        encoder_data[ts_ms] = float(counts[i])

        fits_name = fits_dir / f"frame_{i:04d}.fits"
        make_test_fits(fits_name, t.isoformat(), float(intensities[i]))

    encoder_pkl = tmp_path / "encoder_data_test.pkl"
    with open(encoder_pkl, "wb") as f:
        pickle.dump(encoder_data, f)

    subprocess.run(
        [
            "python3",
            str(CREATE_PLOT),
            "--counts-per-rev",
            str(counts_per_rev),
            str(exposure_dir),
            str(encoder_pkl),
        ],
        cwd=ROOT,
        check=True,
    )

    plots_dir = exposure_dir / "plots"

    expected_plots = [
        plots_dir / "one_pixel" / "one_pixel_vs_encoder.png",
        plots_dir / "one_pixel" / "one_pixel_vs_angle.png",
        plots_dir / "ROI_sum" / "ROI_sum_vs_encoder.png",
        plots_dir / "ROI_sum" / "ROI_sum_vs_angle.png",
        plots_dir / "ROI_average" / "ROI_average_vs_encoder.png",
        plots_dir / "ROI_average" / "ROI_average_vs_angle.png",
        plots_dir / "ROI_median" / "ROI_median_vs_encoder.png",
        plots_dir / "ROI_median" / "ROI_median_vs_angle.png",
    ]

    for plot_path in expected_plots:
        assert plot_path.exists(), f"Missing plot: {plot_path}"
        assert plot_path.stat().st_size > 0, f"Empty plot: {plot_path}"

    fitlogs = list(plots_dir.glob("fitlog_*.log"))
    assert len(fitlogs) == 1, f"Expected exactly one fitlog, found {len(fitlogs)}"

    fitlog_text = fitlogs[0].read_text()

    assert "fitlog created:" in fitlog_text
    assert "counts_per_rev: 2400" in fitlog_text
    assert "n_samples:" in fitlog_text
    assert "NO_FIT" not in fitlog_text

    for trace_name in ["one_pixel", "ROI_sum", "ROI_average", "ROI_median"]:
        assert f"{trace_name}: psi_deg_mod90=" in fitlog_text, (
            f"Missing fit result for {trace_name}"
        )

    r2_values = parse_r2_values(fitlog_text)

    assert len(r2_values) >= 4, "Expected R2 values for all four plot types"
    assert all(np.isfinite(r2) for r2 in r2_values), f"Non-finite R2 value found: {r2_values}"
    assert all(r2 > 0.95 for r2 in r2_values), f"Unexpectedly low R2 values: {r2_values}"