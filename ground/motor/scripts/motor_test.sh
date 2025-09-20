#!/bin/bash

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