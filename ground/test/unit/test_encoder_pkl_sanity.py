import pickle
from pathlib import Path

import numpy as np

ENCODER_PKL = (
    Path(__file__).resolve().parents[2]
    / "test"
    / "test_data"
    / "encoder_data_20260501_174523.pkl"
)


def load_encoder_pkl(path: Path):
    with open(path, "rb") as f:
        data = pickle.load(f)

    times_ms = np.array(list(data.keys()), dtype=np.float64)
    counts = np.array(list(data.values()), dtype=np.float64)

    order = np.argsort(times_ms)
    return times_ms[order], counts[order]


def test_encoder_pkl_sanity():
    assert ENCODER_PKL.exists(), f"Missing test file: {ENCODER_PKL}"

    times_ms, counts = load_encoder_pkl(ENCODER_PKL)

    assert len(times_ms) > 100, "Too few encoder samples"
    assert len(times_ms) == len(counts), "Mismatched timestamps/counts"

    # Timestamps should be strictly increasing.
    dt_ms = np.diff(times_ms)
    assert np.all(dt_ms > 0), "Encoder timestamps are not strictly increasing"

    # Drop the first few startup samples. The QSB can emit stale/zero/spike values
    # immediately after stream startup.
    STARTUP_DROP = 5
    times_ms = times_ms[STARTUP_DROP:]
    counts = counts[STARTUP_DROP:]

    # Counts may repeat when the logger records NC/no-change samples, so require
    # mostly non-decreasing rather than strictly increasing.
    dc = np.diff(counts)
    negative_steps = dc < 0
    negative_fraction = np.sum(negative_steps) / len(dc)

    assert negative_fraction <= 0.02, (
        f"Too many decreasing count steps: {negative_fraction:.4%}"
    )

    # Remove obvious count jumps/spikes before checking linearity.
    positive_steps = dc[dc > 0]
    assert len(positive_steps) > 10, "Too few positive encoder steps"

    median_positive_step = np.median(positive_steps)

    good = np.ones_like(counts, dtype=bool)

    # A bad transition makes the later sample suspicious.
    bad_step = (
        (dc < 0)
        | (dc > 10.0 * max(median_positive_step, 1.0))
    )
    good[1:] = ~bad_step

    times_good = times_ms[good]
    counts_good = counts[good]

    assert len(times_good) > 50, "Too few samples after outlier filtering"

    # For the linear fit, keep only samples where the count changes.
    # This avoids over-weighting repeated NC/no-change samples.
    changed = np.r_[True, np.diff(counts_good) > 0]
    times_changed = times_good[changed]
    counts_changed = counts_good[changed]

    assert len(times_changed) > 20, "Too few changed-count samples"

    t = (times_changed - times_changed[0]) / 1000.0
    c = counts_changed - counts_changed[0]

    slope, intercept = np.polyfit(t, c, 1)
    fit = slope * t + intercept

    ss_res = np.sum((c - fit) ** 2)
    ss_tot = np.sum((c - np.mean(c)) ** 2)
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0

    assert slope > 0, f"Encoder count slope is not positive: {slope}"
    assert r2 > 0.95, f"Encoder counts are not approximately linear with time: R2={r2:.4f}"

    total_count_change = counts_changed[-1] - counts_changed[0]
    assert total_count_change > 50, (
        f"Encoder count did not change enough: Δcount={total_count_change}"
    )