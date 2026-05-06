#!/bin/bash

# motor_control.sh
# =================
#
# Purpose
# -------
# Low-level motor control helper script for the polarimeter ground system.
# This script wraps `pigs` (pigpio command-line tool) calls to control GPIO
# pins that drive the motor controller.
#
# It provides simple commands to:
#   - enable / disable the motor driver
#   - set rotation direction
#   - spin the motor at a given speed
#   - stop the motor
#
# This script is primarily used by:
#   - motor-spin-logger.py (during acquisition)
#
# It can also be run manually for hardware testing.
#
# Usage
# -----
#   ./motor_control.sh enable
#   ./motor_control.sh forward
#   ./motor_control.sh spin 1000
#   ./motor_control.sh stop
#   ./motor_control.sh disable
#
# Hardware Notes
# --------------
# - Requires `pigpiod` to be running (this script will attempt to start it)
# - GPIO pin assignments are hardware-specific
# - Incorrect usage may cause unexpected motor motion
#
# Safety
# ------
# Use caution when running this script on a live system:
#   - Ensure the motor is free to spin
#   - Avoid running at high speeds without supervision
#
# Typical Usage
# -------------
# This script is normally not called directly. It is invoked by
# `motor-spin-logger.py` as part of the full acquisition pipeline.

# Function to run shell commands
run_command() {
    "$@"
}

# Ensure pigpiod is running
check_pigpiod() {
    if ! pgrep pigpiod > /dev/null; then
        echo "pigpiod not running. Starting pigpiod with sudo..."
        sudo pigpiod
        sleep 1  # Allow time for pigpiod to start
    else
        echo "pigpiod is running."
    fi
}

# Enable motor
enable() {
    run_command pigs w 16 0
    run_command pigs w 17 0
    run_command pigs w 20 0
    run_command pigs w 12 1
}

# Disable motor
disable() {
    run_command pigs w 12 0
}

# Set motor direction
set_direction() {
    case "$1" in
        forward)
            run_command pigs w 13 0
            ;;
        backward)
            run_command pigs w 13 1
            ;;
        *)
            echo "Invalid direction! Use 'forward' or 'backward'."
            exit 1
            ;;
    esac
}

# Spin motor continuously at given speed
spin() {
    SPEED=${1:-1000}  # Default speed if not provided
    run_command pigs hp 19 "$SPEED" 5000
}

# Stop motor
stop() {
    run_command pigs w 19 0
}

# Main script execution
check_pigpiod

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 {enable|disable|forward|backward|spin|stop} [speed]"
    exit 1
fi

ACTION=$1
PARAM=$2

case "$ACTION" in
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    forward|backward)
        set_direction "$ACTION"
        ;;
    spin)
        spin "$PARAM"
        ;;
    stop)
        stop
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Usage: $0 {enable|disable|forward|backward|spin|stop} [speed]"
        exit 1
        ;;
esac