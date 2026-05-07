#!/bin/bash

# motor_test.sh
# ==============
#
# Purpose
# -------
# Simple manual test script for validating motor control functionality.
# This script exercises the motor by enabling it, spinning in both
# directions, and stopping between actions.
#
# It is intended for quick hardware verification rather than automated
# testing. It helps confirm that:
#   - the motor driver responds to commands
#   - direction control works correctly
#   - the motor can start and stop cleanly
#
# Usage
# -----
# Run directly from the motor/scripts directory:
#
#   ./motor_test.sh
#
# This will:
#   1. Enable the motor
#   2. Spin forward for a few seconds
#   3. Stop
#   4. Spin backward for a few seconds
#   5. Stop and disable
#
# Notes
# -----
# - This script depends on `motor_control.sh`
# - Requires `pigpiod` to be running
# - This script will physically move the motor
#
# Safety
# ------
# Ensure the motor and attached hardware are in a safe state before running:
#   - nothing obstructs motion
#   - no loose cables or components
#   - system is supervised during execution

# Function to run the motor control script with the desired action and optional speed
run_motor_control() {
    if [[ -n "$2" ]]; then
        ./motor_control.sh "$1" "$2"
    else
        ./motor_control.sh "$1"
    fi
}

# Main test function
motor_test() {
    echo "Enabling motor..."
    run_motor_control "enable"
    sleep 1  # Give the motor time to enable

    echo "Spinning forward..."
    run_motor_control "forward" 1000
    sleep 3  # Spin for 3 seconds

    echo "Stopping motor..."
    run_motor_control "stop"
    sleep 1

    echo "Spinning backward..."
    run_motor_control "backward" 1000
    sleep 3  # Spin for 3 seconds

    echo "Stopping motor..."
    run_motor_control "stop"
    sleep 1

    echo "Disabling motor..."
    run_motor_control "disable"
}

# Run main test function
motor_test