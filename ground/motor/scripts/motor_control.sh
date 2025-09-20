#!/bin/bash

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