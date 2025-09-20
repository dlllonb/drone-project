#!/bin/bash

# Generate random port between 8888 and 9999
random_port=$((RANDOM % 1122 + 8888))

# Start Jupyter remote session
jupyter notebook --no-browser --port=$random_port