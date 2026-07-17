#!/bin/bash
# Safe Docker cleanup script

LOG_FILE="/var/log/docker-cleanup.log"

echo "==================================" >> "$LOG_FILE"
echo "Start of cleaning: $(date)" >> "$LOG_FILE"

# Delete old containers, images, and networks (> 7 days)
docker system prune -a --filter "until=168h" -f >> "$LOG_FILE" 2>&1

# Delete old build cache (> 7 days)
docker builder prune --filter "until=168h" -f >> "$LOG_FILE" 2>&1

echo "Cleaning complete: $(date)" >> "$LOG_FILE"
