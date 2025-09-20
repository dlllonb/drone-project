import matplotlib.pyplot as plt
from astropy.io import fits
import pickle
import numpy as np
import sys
import os
from datetime import datetime

if len(sys.argv) < 3:
    print("Usage: python script.py <fits_directory> <pkl_file>")
    sys.exit(1)

# Inputs
base_dir = sys.argv[1]
fits_dir = os.path.join(base_dir, "processed", "fits")
pkl_file = sys.argv[2]

# Load FITS timestamps
fits_times = []
fits_files = sorted(f for f in os.listdir(fits_dir) if f.endswith(".fits"))
for filename in fits_files:
    with fits.open(os.path.join(fits_dir, filename)) as hdul:
        header = hdul[0].header
        if 'DATE-OBS' in header:
            try:
                dt = datetime.strptime(header['DATE-OBS'], "%Y-%m-%dT%H:%M:%S.%fZ")
            except ValueError:
                dt = datetime.strptime(header['DATE-OBS'], "%Y-%m-%dT%H:%M:%SZ")
            fits_times.append(dt.timestamp())

# Load encoder timestamps
with open(pkl_file, "rb") as f:
    spacetime = pickle.load(f)
encoder_times = [k / 1000.0 for k in spacetime.keys()]  # ms to s

# Normalize time to start from zero
start_time = min(min(fits_times), min(encoder_times))
fits_times = [t - start_time for t in fits_times]
encoder_times = [t - start_time for t in encoder_times]

# Plot
plt.figure(figsize=(12, 4))
plt.eventplot([fits_times, encoder_times], colors=['blue', 'orange'], lineoffsets=[1, 0], linelengths=0.8)
plt.yticks([0, 1], ["Encoder", "FITS"])
plt.xlabel("Time [s]")
plt.title("FITS vs Encoder Timestamps")
plt.grid(True)
plt.tight_layout()
output_path = os.path.join(base_dir, "timestamp_alignment_plot.png")
plt.savefig(output_path)
print(f"Timestamp alignment plot saved to {output_path}")