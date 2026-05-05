#!/bin/bash

# This script starts a Jupyter notebook server on a random port between 8888 and 9999
# Purely for utility purposes and is not necessary for primary features of the project

# Generate random port between 8888 and 9999
random_port=$((RANDOM % 1122 + 8888))

# Start Jupyter remote session
jupyter notebook --no-browser --port=$random_port