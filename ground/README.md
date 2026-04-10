

# Ground System README

## Overview

The `ground/` directory contains the full data acquisition and analysis pipeline for the drone polarimeter ground test system. Its purpose is to automate the collection of synchronized camera exposures and encoder measurements, process the raw outputs into usable scientific data products, and generate plots and visual diagnostics for polarization analysis.

At a high level, the ground system performs the following steps:

1. Spins the half-wave plate using the motor system
2. Records encoder measurements during rotation
3. Captures a sequence of camera exposures
4. Converts raw camera output into FITS and/or preview images
5. Matches each exposure to encoder position
6. Extracts signal intensity from the target source
7. Produces plots and optional GIF visualizations

This directory is intended to support both:
- **single-run experiments**
- **multi-run observing campaigns**

It also supports **separating acquisition and processing**, allowing data to be collected in the field and processed later.

---

## Directory Structure

```text
ground/
├── camera/               # Camera acquisition binaries and utilities
├── motor/                # Motor + encoder logging
├── readout/              # Processing, plotting, and animation scripts
├── saved-data/           # Long-term storage for completed runs/campaigns
├── config.yml            # Main configuration file
├── load-config.py        # Loads config + CLI overrides into shell env vars
├── run-end-to-end.sh     # Single-run acquisition / processing pipeline
├── multi-run.sh          # Campaign wrapper for repeated runs
└── Makefile              # Build helper for camera + encoder code
```

---

## Pipeline Summary

### Single-run pipeline

A standard single run proceeds as:

```text
Motor + Encoder Start
        ↓
Camera Capture
        ↓
Raw .bin files written
        ↓
Encoder data saved (.pkl)
        ↓
Raw data processed into FITS / PNG
        ↓
Signal extracted and matched to encoder position
        ↓
Plots and optional GIFs generated
```

### Multi-run campaign pipeline

A multi-run campaign groups several runs into one parent directory for easier organization:

```text
campaign-YYYYMMDD-HHMMSS/
├── run_001/
│   └── exposures-.../
├── run_002/
│   └── exposures-.../
├── run_003/
│   └── exposures-.../
└── campaign.log
```

This structure keeps all runs from a single observing session together.

---

## Main Scripts

## `run-end-to-end.sh`

This is the main **single-run pipeline driver**.

It supports three operational modes:

- **`full`**  
  Acquire data and process it immediately

- **`acquire-only`**  
  Collect raw data only and process later

- **`process-only`**  
  Process a previously collected exposure directory without acquiring new data

### Responsibilities

`run-end-to-end.sh` is responsible for:

- loading config values
- launching the motor/encoder logger
- launching camera capture
- organizing outputs into a deterministic run folder
- stopping acquisition cleanly
- moving encoder data into the run folder
- launching processing and plotting scripts
- optionally generating GIFs
- optionally cleaning up large intermediate files

### Example usage

```bash
# Standard full pipeline
./run-end-to-end.sh --config config.yml

# Acquire only
./run-end-to-end.sh --mode acquire-only --config config.yml

# Process later
./run-end-to-end.sh --mode process-only --exposure-dir ./saved-data/exposures-...

# Override duration from CLI
./run-end-to-end.sh --config config.yml --duration-s 60
```

---

## `multi-run.sh`

This is the **campaign wrapper** around `run-end-to-end.sh`.

It is used when repeated observations are desired under the same setup.

### Supported modes

- **`full`**  
  Acquire + process each run

- **`acquire-only`**  
  Collect multiple runs first, process later

- **`process-only`**  
  Process all existing runs inside a campaign directory

### Responsibilities

`multi-run.sh` is responsible for:

- creating campaign folders
- organizing repeated runs into `run_001`, `run_002`, etc.
- calling `run-end-to-end.sh` repeatedly
- optionally processing all runs in a campaign later

### Example usage

```bash
# Run 5 acquisitions, 60 seconds each
./multi-run.sh 5 60

# Run 3 acquisitions without processing
./multi-run.sh 3 60 --mode acquire-only

# Process a previously acquired campaign
./multi-run.sh --mode process-only --campaign-dir ./campaign-20260319-210000

# Pass config / plotting overrides through
./multi-run.sh 3 60 --mode full -- --config config.yml --save-roi-overlays 1 --make-roi-gif 1
```

---

## Configuration

## `config.yml`

The file `config.yml` stores the default settings for acquisition, processing, and plotting.

Typical configurable items include:

### Acquisition settings
- exposure time
- camera gain
- frame interval
- acquisition duration

### Motor settings
- spin rate
- encoder ground path

### Processing settings
- whether to create FITS files
- whether to create color or green previews
- number of worker processes

### Plotting settings
- encoder counts per revolution
- debug output
- ROI overlay saving
- ROI GIF creation

### Cleanup settings
- whether to delete large intermediate files after processing

---

## Data Products

Each exposure run creates a directory of the form:

```text
exposures-YYYYMMDD-HHMMSS-mmm_PID/
```

Inside that directory, typical outputs include:

```text
exposures-.../
├── raw/                        # Raw .bin frames
├── processed/
│   ├── fits/                   # FITS files (optional)
│   ├── color/                  # Color PNG previews (optional)
│   └── green/                  # Green-channel PNG previews (optional)
├── plots/
│   ├── one_pixel/
│   ├── ROI_sum/
│   ├── ROI_average/
│   ├── ROI_median/
│   └── roi_overlays/           # Optional ROI debug overlays
├── encoder_data_*.pkl          # Encoder time series
├── camera.log
├── motor.log
├── run_config.log
└── run_command.log
```

Optional GIF outputs may also be created, such as:

- color animation GIF
- green animation GIF
- ROI tracking GIF

---

## Design Philosophy

Several design choices were made intentionally to improve reliability and reproducibility.

### 1. Separation of acquisition and processing

The system supports collecting data first and processing later. This is useful because:

- acquisition should remain as lightweight and robust as possible
- processing can take significantly longer than capture
- long observing sessions may be easier to run in acquisition-only mode
- failed processing can be rerun without recollecting data

### 2. Campaign-based organization

Multi-run observations are grouped into campaign folders so that all related runs stay together. This makes it easier to:

- compare runs from the same observing session
- rerun processing on all runs together
- archive or move an entire campaign as one unit

### 3. Raw-first storage

The camera writes raw `.bin` files during acquisition because this is faster and simpler than generating FITS files live. FITS conversion is deferred to the processing stage.

### 4. Reproducibility

Each run stores:

- resolved config values
- command invocation
- logs

This allows runs to be traced and reproduced later.

---

## Build / Compilation

The ground system includes compiled components for:

- camera capture
- quadrature encoder logging

These are built using the top-level `Makefile` in `ground/`.

### Typical usage

```bash
make
```

Depending on the build targets, this compiles the required camera and encoder binaries.

---

## Raspberry Pi Access and Hardware Bring-Up

The ground system is typically operated on a Raspberry Pi connected to the camera, motor controller, and encoder hardware.

### Connecting to the Raspberry Pi

If operating the system remotely:

1. Connect to the appropriate network (for example, on-campus Wi-Fi or VPN if required)
2. SSH into the Raspberry Pi using its current hostname or IP address

Example:

```bash
ssh <username>@<raspberry-pi-address>
```

> **Note:** IP addresses and hostnames may change over time, so they are not hardcoded here.

### Basic hardware checklist before a run

Before starting acquisition, verify the following:

- the **camera** is connected and recognized
- the **encoder USB interface** is plugged into the Raspberry Pi
- the **encoder / interface board power switch** is turned on (if applicable)
- the **motor driver and motor power** are connected
- any required GPIO / USB hardware is seated properly

### Motor daemon requirement

The motor control stack depends on `pigpiod` being available on the Raspberry Pi.

If the motor subsystem does not respond correctly, check that the daemon is running:

```bash
sudo systemctl status pigpiod
```

or start it manually if needed:

```bash
sudo pigpiod
```

In normal operation, the motor scripts may also start or check this automatically.

---

## Subsystem Documentation

Detailed documentation for each subsystem should be found in:

- `camera/README.md`
- `motor/README.md`
- `readout/README.md`

These files describe the lower-level implementation details of acquisition, encoder logging, processing, and plotting.

---

## Typical Workflows

## 1. Standard single run

```bash
./run-end-to-end.sh --config config.yml
```

Use this for a one-off test or a single observation.

---

## 2. Multi-run observing campaign

```bash
./multi-run.sh 5 60 --mode full -- --config config.yml
```

Use this for repeated runs under the same setup.

---

## 3. Acquire now, process later

```bash
# Step 1: acquire
./multi-run.sh 5 60 --mode acquire-only -- --config config.yml

# Step 2: process later
./multi-run.sh --mode process-only --campaign-dir ./campaign-20260319-210000 -- --config config.yml
```

This is especially useful for field use or long observing sessions.

---

## Notes / Known Issues

- Encoder behavior depends on the hardware register configuration and may operate in either continuously increasing or modulo-wrapping mode depending on settings.
- Large GIF outputs can quickly consume disk space and may exceed GitHub’s file size limits.
- Processing with ROI overlays and GIF generation can significantly increase runtime and output size.

---

## Recommended Git Usage

It is recommended **not** to commit large generated data products such as:

- raw `.bin` files
- FITS files
- GIF animations
- campaign output folders

Instead, only commit:

- source code
- config files
- documentation
- small example outputs if needed

A `.gitignore` should be used to exclude large generated artifacts.

---

## Summary

The `ground/` directory is the operational core of the polarimeter ground pipeline. It ties together the camera, motor/encoder, and analysis code into a reproducible workflow for collecting and analyzing polarization data.

Its key strengths are:

- modular subsystem design
- support for both single-run and multi-run operation
- separation of acquisition from processing
- structured output organization for reproducibility and analysis