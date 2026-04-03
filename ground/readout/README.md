

# Readout and Processing Subsystem

## Overview

The `readout/` directory contains the data processing pipeline for the polarimeter system.

This subsystem is responsible for:

- converting raw camera `.bin` files into usable formats
- generating FITS files and preview images
- analyzing exposures using encoder data
- producing plots of intensity vs rotation angle
- optionally generating animations for visualization

This is the stage where raw data becomes **scientifically usable output**.

In normal operation, this subsystem is executed automatically by:

- `ground/run-end-to-end.sh`
- `ground/multi-run.sh`

---

## Directory Contents

### Main scripts

- `continuous-capture.sh`  
  Wrapper script that runs the camera capture program and organizes output folders.

- `process-exposures-batch.py`  
  Converts raw `.bin` files into FITS files and preview images.

- `create-plot.py`  
  Core analysis script that matches exposures with encoder data and generates plots.

- `create-animation.py`  
  Utility script for creating GIF animations from processed frames or ROI overlays.

### Supporting files

- `utils/`  
  Utilities used for development work, not critical for scientific application.

---

## Pipeline Stages

The readout subsystem is composed of several sequential stages.

### 1. Data Acquisition (via wrapper)

`continuous-capture.sh` launches the camera capture binary and organizes output into a structured directory:

```text
exposures-YYYYMMDD-HHMMSS-mmm/
    raw/
    processed/
```

- `raw/` contains `.bin` files from the camera
- `processed/` will later contain derived products

---

### 2. Batch Processing

Script:

```bash
process-exposures-batch.py
```

This script converts raw `.bin` files into more usable formats.

#### Outputs

- `processed/fits/` → FITS files for each exposure
- `processed/color/` → RGB preview images
- `processed/green/` → single-channel images (used in analysis)

#### Key behavior

- Reads raw sensor data from `.bin` files
- Interprets Bayer pattern
- Extracts color channels
- Writes FITS files with metadata
- Uses multiprocessing for speed

---

### 3. Plotting and Analysis

Script:

```bash
create-plot.py
```

This is the **core scientific analysis step**.

#### Inputs

- processed FITS files
- encoder data (`encoder_data_*.pkl`)

#### Processing steps

For each exposure:

1. Detect the signal region (ROI)
2. Estimate background (full frame minus ROI + guard band)
3. Compute intensity metrics:
   - one pixel (peak)
   - ROI sum
   - ROI average
   - ROI median
4. Match exposure timestamp to nearest encoder sample
5. Convert encoder counts to rotation angle

#### Outputs

Plots are saved in:

```text
plots/
    one_pixel/
    ROI_sum/
    ROI_average/
    ROI_median/
```

Each metric produces:

- intensity vs encoder count
- intensity vs plate angle (folded)

Optional outputs:

- ROI overlay frames (`plots/roi_overlays/`)
- fit logs (`plots/fitlog_*.log`)

---

### 4. Animation (Optional)

Script:

```bash
create-animation.py
```

Used to generate GIFs from:

- processed image sequences
- ROI overlay frames

Example:

```bash
python3 create-animation.py \
  --input-dir exposures-.../plots/roi_overlays \
  --output exposures-.../roi_tracking.gif
```

---

## Typical Usage

### Full pipeline (recommended)

From `ground/`:

```bash
./run-end-to-end.sh
```

This automatically:

1. captures data
2. processes exposures
3. generates plots
4. optionally creates animations

---

### Process existing data only

```bash
./run-end-to-end.sh --mode process-only --exposure-dir <dir>
```

Or for campaigns:

```bash
./multi-run.sh --mode process-only --campaign-dir <dir>
```

---

### Manual processing steps

You can also run each stage manually:

#### Convert raw data

```bash
python3 process-exposures-batch.py exposures-...
```

#### Generate plots

```bash
python3 create-plot.py exposures-... encoder_data.pkl
```

#### Create animation

```bash
python3 create-animation.py exposures-...
```

---

## Output Structure

A typical processed run looks like:

```text
exposures-.../
    raw/
    processed/
        fits/
        color/
        green/
    plots/
        one_pixel/
        ROI_sum/
        ROI_average/
        ROI_median/
        roi_overlays/ (optional)
    roi_tracking.gif (optional)
```

---

## Key Concepts

### ROI (Region of Interest)

The pipeline automatically detects the signal region in each frame by:

- finding the brightest pixel
- growing a blob above a threshold
- defining a bounding box around that region

This allows the analysis to track the signal even if it moves slightly between frames.

---

### Background Subtraction

Background is estimated as:

```text
full frame - (ROI + guard band)
```

This avoids contamination from the signal region while using most of the image for background estimation.

---

### Encoder Matching

Each exposure is matched to the closest encoder timestamp.

This step is critical for converting intensity measurements into a function of rotation angle.

---

### Angle Folding

Encoder counts are converted into a normalized angle:

```text
angle = ((count / counts_per_rev) % 1) * 2π
```

This allows repeated rotations to be combined into a single cycle for analysis.

---

### Fourier Fitting

The pipeline optionally fits harmonic models (e.g., 2θ, 4θ terms) to the folded data.

This is used to extract polarization-related parameters from the signal.

---

## Common Failure Modes

### 1. No FITS files generated

Check:

- `.bin` files exist in `raw/`
- processing script ran successfully
- output directories were created

---

### 2. No plots generated

Check:

- encoder file exists
- timestamps are valid
- FITS files contain correct metadata

---

### 3. ROI detection fails

Symptoms:

- missing data points
- noisy or inconsistent plots

Possible causes:

- signal too faint
- threshold too high
- hot pixels dominating detection

---

### 4. Angle plots look incorrect

Possible causes:

- incorrect counts-per-revolution
- encoder wraparound not handled correctly
- time offset between encoder and camera

---

### 5. Processing is slow

Check:

- number of worker processes (`--jobs`)
- system CPU usage
- disk I/O performance

---

## Recommended Next Reading

For overall pipeline usage, see:

- `../README.md`

For acquisition details, see:

- `../camera/README.md`
- `../motor/README.md`