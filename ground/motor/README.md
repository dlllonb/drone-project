

# Motor and Encoder Subsystem

## Overview

The `motor/` directory contains the code responsible for spinning the polarimeter mechanism and recording the corresponding encoder measurements during data collection.

This subsystem is responsible for:

- commanding the motor during observing runs
- reading the quadrature encoder
- timestamping encoder measurements
- saving encoder data for later synchronization with camera exposures

In the full ground pipeline, this subsystem is typically launched automatically by:

- `ground/run-end-to-end.sh`
- `ground/multi-run.sh`

The outputs from this folder are later used by the readout pipeline to associate each exposure with the nearest encoder measurement and convert counts into plate angle.

---

## Directory Contents

### Main files

- `motor-spin-logger.py`  
  High-level script used during acquisition to run the motor and record encoder output.

- `quad_enc/record-encoder-data.c`  
  Lower-level encoder interface used to communicate with the quadrature encoder hardware and save measurements.

### Supporting files / folders

- `quad_enc/`  
  Contains encoder-related source code and supporting files.
- `scripts/`
  Contains shell scripts for controlling motor directly

Additional hardware-specific or utility files may also appear here depending on the system setup.

---

## What This Subsystem Does

During a normal observing run, the motor subsystem performs two linked jobs:

1. **Spin the optic / wheel assembly** at the requested rate
2. **Log encoder position over time** so the optical angle can later be reconstructed

This is necessary because the science analysis depends on knowing the relative plate angle for each exposure.

The encoder measurements are saved as a time series, and the downstream analysis pipeline later matches each camera frame to the nearest encoder sample.

---

## Main Program: `motor-spin-logger.py`

This is the primary entry point used by the full acquisition pipeline.

Typical responsibilities include:

- starting the motor
- maintaining the requested spin behavior
- launching or interfacing with encoder logging
- writing encoder output to disk
- handling shutdown cleanly when acquisition stops

This script is generally not run manually during normal usage unless you are debugging the motor or encoder subsystem.

### Typical usage in the full pipeline

The script is usually called indirectly by:

```bash
./run-end-to-end.sh
```

rather than run by hand.

---

## Encoder Logging: `quad_enc/record-encoder-data.c`

This C program handles low-level communication with the quadrature encoder hardware.

Its responsibilities include:

- opening the serial connection to the encoder device
- configuring encoder registers
- reading streamed count values
- timestamping each measurement
- saving the resulting data structure for later use

This lower-level component is important because the encoder data is what allows the science pipeline to reconstruct plate angle during analysis.

---

## Output Data

The encoder logger produces files typically named like:

```text
encoder_data_YYYYMMDD_HHMMSS.pkl
```

These files contain timestamped encoder values recorded during the run.

In the full pipeline, the encoder file is typically moved into the corresponding exposure folder so that camera data and encoder data stay grouped together.

For example:

```text
exposures-YYYYMMDD-HHMMSS-mmm/
    encoder_data_YYYYMMDD_HHMMSS.pkl
```

This file is later consumed by:

- `ground/readout/create-plot.py`

---

## How the Encoder Data Is Used

The encoder file is not usually analyzed directly by hand.

Instead, the downstream pipeline uses it to:

1. load the encoder timestamp/value series
2. load timestamps from processed FITS exposures
3. find the nearest encoder sample for each exposure
4. convert encoder counts into plate angle
5. generate intensity-vs-angle plots

This means that even if the camera capture stage works perfectly, the overall observing run is not scientifically useful unless the encoder data is also recorded correctly.

---

## Typical Workflow

### Normal operation (recommended)

From `ground/`:

```bash
./run-end-to-end.sh
```

This will usually:

- start motor + encoder logging
- start camera acquisition
- stop both systems cleanly
- save the encoder file into the run output folder

### Multi-run campaign

From `ground/`:

```bash
./multi-run.sh
```

This repeats the same logic across multiple runs.

### Manual testing / debugging

You may also run the motor subsystem independently if you want to test:

- whether the motor spins
- whether the encoder count changes
- whether encoder data is being saved correctly

This is useful for isolating hardware issues from the rest of the pipeline.

---

## Common Failure Modes

## 1. Encoder count does not change

Possible causes:

- encoder hardware is not connected properly
- serial device path is incorrect
- encoder is powered but not reading motion
- motor is not actually rotating the encoded shaft
- encoder register configuration is wrong

If the count stays fixed while the motor is visibly spinning, this usually indicates a hardware or configuration issue rather than a camera/readout problem.

---

## 2. Encoder count wraps / overflows unexpectedly

Depending on encoder register configuration, the encoder may behave as either:

- a continuously increasing count
- a modulo counter that wraps after a fixed maximum

If modulo counting is enabled, the downstream analysis pipeline must account for count wraparound when interpreting angle.

This is especially important for long runs or repeated rotations.

---

## 3. Encoder file is missing after a run

Possible causes:

- encoder logger did not start successfully
- process terminated before saving output
- run was interrupted before clean shutdown
- output file was written somewhere unexpected

This is one of the most important files to verify after acquisition.

---

## 4. Motor spins but downstream plots look wrong

Possible causes:

- encoder counts are not synchronized correctly with exposure timestamps
- encoder values are valid but wrapped unexpectedly
- timestamps are offset or inconsistent
- counts-per-revolution assumptions are wrong

In this case, the problem may not be in the motor hardware itself, but in how the data is interpreted later.

---

## Notes on Hardware-Specific Behavior

This subsystem depends strongly on the exact motor, encoder, serial interface, and GPIO/hardware setup being used.

That means:

- device names may differ across systems
- register settings may need adjustment
- behavior can change if the encoder is configured differently

For this reason, the motor subsystem should generally be treated as **hardware-coupled code**, not a fully portable software-only module.

---
---

## Testing

The motor and encoder subsystem is covered by the top-level test suite in `../test/`.

Relevant tests include:

### Integration tests
- `Encoder + motor data collection`
- `Encoder timestamps`
- `Camera-to-image pipeline`
- `End-to-end pipeline`
- `Multi-run pipeline`

These tests verify that:

- the motor control stack launches correctly
- the encoder logger produces valid `.pkl` outputs
- encoder timestamps increase monotonically
- encoder counts change approximately linearly with time during rotation
- encoder outputs integrate correctly with the acquisition and processing pipeline

### Manual hardware tests

The helper script:

```bash
motor/scripts/motor_test.sh
```

can be used for quick manual validation of:

- motor direction control
- start/stop behavior
- GPIO and pigpio communication

This script physically moves the motor and should only be run when the hardware is in a safe state.

### Running tests

From `ground/`:

```bash
bash test/run_integration_tests.sh
```

Because the motor subsystem is hardware-coupled, these tests should ideally be run:

- after hardware modifications
- after GPIO or pigpio changes
- after encoder register/configuration updates
- before observing sessions

## Recommended Next Reading

For the next stage of the pipeline, see:

- `../readout/README.md`
- `../README.md`