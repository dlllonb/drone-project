#!/bin/bash

# Set working directory
SCRIPT_DIR="/home/declan/RPI/ip_check"
cd "$SCRIPT_DIR" || { echo "[$(date)] Error: Failed to change directory to $SCRIPT_DIR" >> ip_check.log; exit 1; }

# Load environment variables
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "[$(date)] Error: .env file not found!" >> ip_check.log
    exit 1
fi
source "$ENV_FILE"

# Set file to store the previous IP address
IP_FILE="$SCRIPT_DIR/ip_address.txt"

# Get the current private IP address
CURRENT_IP=$(hostname -I | awk '{print $1}')

# Check if IP file exists, and if not, create it
if [ ! -f "$IP_FILE" ]; then
    echo "$CURRENT_IP" > "$IP_FILE"
    exit 0
fi

# Read the last known IP from the file
LAST_IP=$(cat "$IP_FILE")

# If the IP has changed, update the file and send an email
if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    echo "$CURRENT_IP" > "$IP_FILE"

    # Email notification
    SUBJECT="astro-johnson Raspberry PI IP Address Change Notification"
    BODY="The private IP address of the device has changed. New IP: $CURRENT_IP"

    if ! echo -e "Subject: $SUBJECT\n\n$BODY" | curl --ssl-reqd \
        --url "smtps://smtp.gmail.com:465" \
        --mail-from "$EMAIL_ADDRESS" \
        --mail-rcpt "$RECIPIENT" \
        --user "$EMAIL_ADDRESS:$SMTP_PASSWORD" \
        --upload-file - &>> ip_check.log; then
        echo "[$(date)] Error: Failed to send email notification" >> ip_check.log
    fi
fi

# Trim log file to the last 100 lines to prevent it from growing indefinitely
tail -n 100 ip_check.log > ip_check.log.tmp && mv ip_check.log.tmp ip_check.log