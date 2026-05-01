import pickle
import subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

import numpy as np
from astropy.io import fits

ROOT = Path(__file__).resolve().parents[2]
CREATE_PLOT = ROOT / "readout" / "create-plot.py"


def make_test_fits(path: Path, date_obs: str, intensity: float):
    data = np.zeros((64, 64), dtype=np.float32)
    data[30:35, 30:35] = intensity

    primary = fits.PrimaryHDU()
    green1 = fits.ImageHDU(data=data, name="GREEN1")
    hdul = fits.HDUList([primary, green1])

    hdul[0].header["DATE-OBS"] = date_obs
    hdul.writeto(path)


def test_create_plot_with_synthetic_data(tmp_path):
    exposure_dir = tmp_path / "exposures-test"
    fits_dir = exposure_dir / "processed" / "fits"
    fits_dir.mkdir(parents=True)

    start = datetime.now(timezone.utc)

    n = 80
    counts_per_rev = 2400
    counts = np.linspace(0, counts_per_rev * 2, n)
    theta = ((counts / counts_per_rev) % 1.0) * 2.0 * np.pi
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

    assert plots_dir.exists()
    assert (plots_dir / "one_pixel" / "one_pixel_vs_encoder.png").exists()
    assert (plots_dir / "one_pixel" / "one_pixel_vs_angle.png").exists()
    assert (plots_dir / "ROI_sum" / "ROI_sum_vs_encoder.png").exists()
    assert (plots_dir / "ROI_sum" / "ROI_sum_vs_angle.png").exists()

    fitlogs = list(plots_dir.glob("fitlog_*.log"))
    assert len(fitlogs) >= 1
    assert fitlogs[0].stat().st_size > 0