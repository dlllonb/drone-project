import pickle
import matplotlib.pyplot as plt
import sys
import os
import numpy as np

OUTLIER_FACTOR = 5.0   # how extreme a value must be vs median to be flagged

if len(sys.argv) < 2:
    print("Usage: python plot_encoder.py <path_to_pkl_file>")
    sys.exit(1)

pkl_file = sys.argv[1]

with open(pkl_file, "rb") as f:
    spacetime = pickle.load(f)  # {time_ms : encoder_count}

# --- sort by timestamp ---
items = sorted(spacetime.items())  # [(time_ms, count), ...]

times = np.array([k for k, v in items], dtype=np.float64)
counts = np.array([v for k, v in items], dtype=np.float64)

# --- normalize time to start at 0 ---
t0 = times.min()
time_sec = (times - t0) / 1000.0

# --- basic stats ---
median = np.median(counts)
min_val = counts.min()
max_val = counts.max()

print(f"[INFO] Encoder stats:")
print(f"       min = {min_val}")
print(f"       median = {median}")
print(f"       max = {max_val}")

# --- detect outliers ---
deviation = np.abs(counts - median)
outlier_mask = deviation > (OUTLIER_FACTOR * median)

num_outliers = np.sum(outlier_mask)
print(f"[INFO] Outliers detected: {num_outliers}")

if num_outliers > 0:
    print("[INFO] Outlier entries (time_s, encoder_count):")
    for t, c in zip(time_sec[outlier_mask], counts[outlier_mask]):
        print(f"       t={t:.3f} s, count={int(c)}")

# --- plotting ---
plt.figure(figsize=(9, 5))

# normal points
plt.scatter(
    time_sec[~outlier_mask],
    counts[~outlier_mask],
    s=10,
    label="normal",
)

# outliers
if num_outliers > 0:
    plt.scatter(
        time_sec[outlier_mask],
        counts[outlier_mask],
        s=60,
        color="red",
        marker="x",
        label="outlier",
        zorder=5,
    )

plt.xlabel("Time [seconds]")
plt.ylabel("Motor Position [Encoder Counts]")
plt.title("Encoder Counts vs Time")

plt.legend()
plt.grid(True)

# --- save plot ---
base_name = os.path.splitext(os.path.basename(pkl_file))[0]
output_path = os.path.join(
    os.path.dirname(pkl_file),
    f"{base_name}_encoder_diagnostic.png",
)

plt.tight_layout()
plt.savefig(output_path, dpi=150)
plt.close()

print(f"[INFO] Plot saved to {output_path}")