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
├── Makefile              # Build helper for camera + encoder code
└── test/                 # Unit/script-level tests and hardware integration tests
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
./multi-run.sh 3 60 --mode full --config config.yml --save-roi-overlays 1 --make-roi-gif 1
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

### Command-line overrides

Most configuration values can also be overridden from the command line. For example:

```bash
./run-end-to-end.sh --mode full --duration-s 60 --cleanup-after-processing 0
```

The `multi-run.sh` wrapper forwards additional arguments to `run-end-to-end.sh`, so configuration overrides can also be passed during campaign runs:

```bash
./multi-run.sh 3 60 --mode full --cleanup-after-processing 0
```

Use `--help` on the relevant scripts for the latest list of supported options.

---

## Software Requirements and Build Instructions

The ground pipeline was developed for a Linux-based ground-system environment connected to the camera, motor, and encoder hardware.

### System requirements

Required system components include:

- Python 3
- GNU Make
- GCC/G++
- ZWO ASI SDK v1.36
- `pigpio` / `pigpiod` for motor control

The ZWO ASI SDK version used for this project is version 1.36. On the development system, the SDK resources are located under:

```text
/home/declan/drone-project/ground/
```

### Python requirements

The Python scripts use packages including:

- `numpy`
- `matplotlib`
- `astropy`
- `imageio`
- `Pillow`
- `pytest`
- `PyYAML`

If a `requirements.txt` file is available, install dependencies with:

```bash
pip install -r requirements.txt
```

Otherwise, install the main dependencies manually:

```bash
pip install numpy matplotlib astropy imageio pillow pytest pyyaml
```

### Building compiled components

The ground system includes compiled components for:

- camera capture
- quadrature encoder logging

These are built using the top-level `Makefile` in `ground/`:

```bash
make
```

This calls the subsystem Makefiles for the camera and encoder code. The higher-level acquisition scripts also call the build step before hardware acquisition so the camera and encoder binaries are up to date.

To clean build outputs:

```bash
make clean
```

---

## Raspberry Pi Access and Hardware Bring-Up

The ground system is typically operated on a Raspberry Pi connected to the camera, motor controller, and encoder hardware.

Hardware setup should follow the project hardware documentation described in Baker (2024), https://doi.org/10.18130/04rq-2w36, and Bass et al. (in preparation). This repository documents the software pipeline and assumes the camera, motor, encoder, and polarimeter hardware have already been assembled and connected according to that hardware design.

### Hardware requirements

Required hardware includes:

- ZWO ASI178 camera
- rotating half-wave plate / wheel assembly
- motor and motor driver
- quadrature encoder and encoder interface
- Raspberry Pi or Linux host connected to the camera, motor, and encoder
- appropriate USB, GPIO, and power connections

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

## Testing

The project includes both software-only tests and hardware integration tests. The tests are stored in:

```text
test/
```

The test runners are:

```text
test/run_unit_tests.sh
test/run_integration_tests.sh
test/run_all_tests.sh
```

### Unit / script-level tests

Unit and script-level tests use sample or synthetic data and do not require active hardware acquisition:

```bash
bash test/run_unit_tests.sh
```

These tests validate:

- `load-config.py` config parsing and shell export output
- `.bin` to FITS/PNG conversion using sample camera data
- processed image dimensions
- `process-exposures-batch.py` batch processing behavior
- `create-plot.py` using synthetic sinusoidal FITS and encoder data
- `create-animation.py` GIF generation from sample frames
- encoder `.pkl` sanity using sample encoder data

### Hardware integration tests

Integration tests require the camera, motor, encoder, and associated hardware to be connected and ready:

```bash
bash test/run_integration_tests.sh
```

These tests validate:

- single camera exposure capture
- camera `.bin` file size sanity
- motor plus encoder data collection
- encoder timestamp monotonicity and approximate count linearity
- camera-to-image processing
- full end-to-end acquisition and analysis
- two-run campaign execution through `multi-run.sh`

### Full test suite

To run both unit and integration tests:

```bash
bash test/run_all_tests.sh
```

Integration tests create temporary output under:

```text
test/test_runs/
```

By default, old integration-test outputs are deleted before a new integration test run. To preserve outputs for debugging:

```bash
KEEP_TEST_OUTPUTS=1 bash test/run_integration_tests.sh
```

The integration tests intentionally produce more console output than the unit tests because they run real hardware acquisition and processing workflows.

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
./multi-run.sh 5 60 --mode full --config config.yml
```

Use this for repeated runs under the same setup.

---

## 3. Acquire now, process later

```bash
# Step 1: acquire
./multi-run.sh 5 60 --mode acquire-only --config config.yml

# Step 2: process later
./multi-run.sh --mode process-only --campaign-dir ./campaign-20260319-210000 --config config.yml
```

This is especially useful for field use or long observing sessions.

---

## Notes / Known Issues

- Encoder behavior depends on the hardware register configuration and may operate in either continuously increasing or modulo-wrapping mode depending on settings.
- Large GIF outputs can quickly consume disk space and may exceed GitHub’s file size limits.
- Processing with ROI overlays and GIF generation can significantly increase runtime and output size.
- Short hardware integration runs may produce too few frames for a meaningful Fourier fit, even if the acquisition and processing pipeline succeeds.
- Integration test outputs can be large; they are written under `test/test_runs/` and should not be committed.

---

## Recommended Git Usage

It is recommended **not** to commit large generated data products such as:

- raw `.bin` files
- FITS files
- GIF animations
- campaign output folders
- `test/test_runs/` integration-test output

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