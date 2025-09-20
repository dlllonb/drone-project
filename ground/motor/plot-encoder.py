import pickle
import matplotlib.pyplot as plt
import sys
import os

if len(sys.argv) < 2:
    print("Usage: python script.py <path_to_pkl_file>")
    sys.exit(1)

pkl_file = sys.argv[1]

with open(pkl_file, "rb") as f:
    spacetime = pickle.load(f)  # {time : encoder count}

loc = []
time = []

old_key = 0
old_val = 0
zero = next(iter(spacetime.keys()))
print("Starting time [millisec]:", zero)

for key, val in spacetime.items():
    if val > 0.000001:
        if old_val != val and old_key != key:
            loc.append(val)
            seconds = key / 1000.0
            time.append(seconds - (zero / 1000.0))
            old_key = key
            old_val = val

plt.figure()
plt.ylabel("Motor Position [Encoder Counts]")
plt.xlabel("Time [seconds]")
plt.scatter(time, loc)

# Save plot to PNG in same directory as the .pkl file
base_name = os.path.splitext(os.path.basename(pkl_file))[0]
output_path = os.path.join(os.path.dirname(pkl_file), f"{base_name}_plot.png")
plt.savefig(output_path)
print(f"Plot saved to {output_path}")