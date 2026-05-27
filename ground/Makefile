# ==========================================================
# Ground Pipeline Makefile
#
# Purpose
# -------
# This Makefile builds and cleans the compiled components used
# by the polarimeter ground pipeline.
#
# The primary compiled subsystems are:
#
#   - camera acquisition binaries
#   - quadrature encoder logging binaries
#
# Typical usage:
#
#   make
#   make clean
#   make camera
#   make encoder
#
# Build Targets
# -------------
# all
#     Build both camera and encoder subsystems.
#
# camera
#     Build the camera acquisition binaries located in:
#
#         ground/camera/
#
# encoder
#     Build the quadrature encoder binaries located in:
#
#         ground/motor/quad_enc/
#
# clean
#     Remove compiled outputs from all subsystems.
#
# Notes
# -----
# The camera subsystem depends on the ZWO ASI SDK being
# installed and accessible to the camera build scripts.
#
# The encoder subsystem depends on the Raspberry Pi hardware
# environment and associated GPIO / serial libraries.
# ==========================================================
.PHONY: all camera encoder readout clean camera-clean encoder-clean readout-clean

all: camera encoder readout

camera:
	$(MAKE) -C camera

encoder:
	$(MAKE) -C motor/quad_enc

readout:
	$(MAKE) -C readout

clean: camera-clean encoder-clean readout-clean

camera-clean:
	$(MAKE) -C camera clean

encoder-clean:
	$(MAKE) -C motor/quad_enc clean

readout-clean:
	$(MAKE) -C readout clean
