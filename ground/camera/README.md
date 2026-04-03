

# Camera Subsystem

## Overview

The `camera/` directory contains the low-level code used to communicate with the ZWO ASI178 camera and save raw exposure data for the polarimeter pipeline.

This folder is responsible for:

- Taking single test exposures
- Running continuous capture for observing runs
- Writing raw `.bin` image files to disk
- Providing helper scripts for inspecting saved raw data
- Storing camera SDK dependencies and setup resources

In the full ground pipeline, the camera subsystem is typically called indirectly by:

- `ground/run-end-to-end.sh`
- `ground/readout/continuous-capture.sh`

Most users will not need to run the camera binaries directly during normal operation, but they are useful for testing and debugging.

---

## Directory Contents

### Source / binaries

- `capture-exposure.cpp`  
  Takes a single exposure and saves one raw output frame.

- `capture-continuous.cpp`  
  Continuously captures exposures until interrupted. This is the main acquisition program used during observing runs.

- `capture-exposure.out`  
  Compiled executable for single-exposure capture.

- `capture-continuous.out`  
  Compiled executable for continuous capture.

- `capture-exposure.o`, `capture-continuous.o`  
  Intermediate object files produced during compilation.

### Utilities

- `read-bin.py`  
  Python helper for inspecting raw `.bin` files written by the camera programs.

### Supporting files

- `dependencies/`  
  External SDK or camera-related dependency files.

- `setup/`  
  Setup scripts or configuration resources for camera support.

- `example-exposures/`  
  Example output data useful for testing or inspection.

- `ASI178_Manual_EN_V1.3.pdf`  
  Vendor documentation for the ZWO ASI178 camera.

- `Makefile`  
  Build rules for compiling the camera programs.

---

## Build Instructions

From the `ground/` directory:

```bash
make
```

Or from inside `ground/camera/`:

```bash
make
```

This should build the camera executables:

- `capture-exposure.out`
- `capture-continuous.out`

If compilation fails, verify that:

- the ZWO SDK files are present
- required headers and libraries are installed
- the Makefile paths match your current system

---

## Main Programs

## 1. `capture-exposure.cpp`

This program is used for taking a **single image** from the camera.

Typical uses:

- testing camera connectivity
- checking exposure settings
- verifying focus or illumination
- debugging file output

### Expected behavior

The program should:

- connect to the camera
- configure exposure settings
- capture one frame
- write the raw frame to disk

This is mainly a debugging / validation tool rather than the normal observing interface.

---

## 2. `capture-continuous.cpp`

This is the main acquisition program used by the observing pipeline.

It continuously captures frames until stopped and writes them to disk as raw `.bin` files.

Typical uses:

- collecting a full observing run
- recording exposures while the motor/encoder system is spinning
- feeding downstream processing and plotting scripts

This executable is usually launched through:

```bash
ground/readout/continuous-capture.sh
```

rather than called directly.

### Output behavior

During acquisition, frames are typically written into a run folder such as:

```text
exposures-YYYYMMDD-HHMMSS-mmm/raw/
```

These `.bin` files are later processed into:

- FITS files
- preview images
- plots
- optional animations

---

## Raw Data Format

The camera capture programs write raw `.bin` image files.

These files contain the direct image output from the camera sensor and are intended to be processed later by the readout pipeline.

### Important notes

- The raw files are not immediately human-readable image formats
- They must be interpreted with the correct sensor dimensions and bit depth
- The downstream processing pipeline assumes a fixed sensor shape

For the current processing scripts, the expected frame dimensions are:

- **Width:** `3096`
- **Height:** `2080`

These assumptions are used in:

- `read-bin.py`
- `process-exposures-batch.py`

If camera settings or output formats change, these downstream scripts may also need to be updated.

---

## Inspecting Raw Files

You can inspect saved `.bin` files using:

```bash
python3 read-bin.py <path-to-bin-file>
```

This is useful for:

- confirming that image data was captured correctly
- checking Bayer structure or raw intensity values
- debugging malformed or partially written outputs

Because `.bin` files are raw sensor outputs, this script is often the quickest way to verify whether the camera capture stage worked correctly before debugging later pipeline stages.

---

## How This Fits Into the Pipeline

The camera subsystem is only the **first stage** of the full polarimeter workflow.

Typical flow:

1. Camera records raw `.bin` exposures
2. Motor/encoder subsystem records angle/count data
3. Readout pipeline converts `.bin` files into FITS and preview products
4. Plotting scripts match exposures to encoder timestamps and generate intensity-vs-angle outputs

In practice, most users should start from the higher-level scripts in `ground/` rather than operating this folder manually.

---

## Typical Usage

### Single-run acquisition (recommended)

From `ground/`:

```bash
./run-end-to-end.sh
```

### Multi-run campaign

From `ground/`:

```bash
./multi-run.sh
```

### Camera-only testing

If needed, this folder can be used directly to validate camera behavior independently of the rest of the system.

---

## Troubleshooting

### Camera binary does not run

Check:

- camera is connected
- SDK dependencies are installed
- executable was compiled successfully
- permissions are correct

### `.bin` files look corrupted or unreadable

Check:

- expected frame dimensions
- bit depth assumptions
- whether capture was interrupted mid-write
- whether downstream scripts are interpreting the data correctly

### No frames are being written

Check:

- output directory exists
- camera initialization succeeded
- exposure settings are valid
- capture loop is actually running

---

## Recommended Next Reading

For the next stage of the pipeline, see:

- `../readout/README.md`
- `../README.md`