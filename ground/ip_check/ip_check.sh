#!/bin/bash

# Set working directory
SCRIPT_DIR="/home/declan/drone-project/ground/ip_check"
cd "$SCRIPT_DIR" || { echo "[$(date)] Error: Failed to change directory to $SCRIPT_DIR" >> ip_check.log; exit 1; }

# Load environment variables
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "[$(date)] Error: .env file not found!" >> ip_check.log
    exit 1
fi
source "$ENV_FILE"

# File storing last known IP
IP_FILE="$SCRIPT_DIR/ip_address.txt"

# Get the current private IP address
CURRENT_IP=$(hostname -I | awk '{print $1}')

# If no IP file exists, initialize and exit (no email on first run)
if [ ! -f "$IP_FILE" ]; then
    echo "$CURRENT_IP" > "$IP_FILE"
    exit 0
fi

# Read last known IP
LAST_IP=$(cat "$IP_FILE")

# If IP changed, send notification
if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    echo "$CURRENT_IP" > "$IP_FILE"

    # Email notification
    SUBJECT="astro-johnson Raspberry PI IP Address Change Notification"
    BODY="The private IP address of the device has changed.

New IP: $CURRENT_IP"

    # Build recipient flags for curl
    RCPT_FLAGS=()
    for r in $RECIPIENTS; do
        RCPT_FLAGS+=(--mail-rcpt "$r")
    done

    # Build full email with proper headers
    EMAIL_CONTENT="From: $EMAIL_ADDRESS
To: $RECIPIENTS
Subject: $SUBJECT
Date: $(date -R)

$BODY"

    if ! printf "%s\n" "$EMAIL_CONTENT" | curl -sS --ssl-reqd \
        --url "smtps://smtp.gmail.com:465" \
        --mail-from "$EMAIL_ADDRESS" \
        "${RCPT_FLAGS[@]}" \
        --user "$EMAIL_ADDRESS:$SMTP_PASSWORD" \
        --upload-file - &>> ip_check.log; then
        echo "[$(date)] Error: Failed to send email notification" >> ip_check.log
    fi
fi

# Trim log file to last 100 lines
tail -n 100 ip_check.log > ip_check.log.tmp && mv ip_check.log.tmp ip_check.log