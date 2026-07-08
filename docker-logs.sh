#!/bin/bash

# ================= IGNORE SETTINGS =================
IGNORE_CONTAINERS="custom-test-container"
# ===================================================

CFG_DIR="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d"
TMP_FILE="/tmp/cw_docker.json"
FINAL_FILE="$CFG_DIR/docker_auto.json"
AGENT_CTL="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl"
LOG_FILE="/var/log/cw-docker-auto.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ ! -f "$AGENT_CTL" ]; then
    log_message "ERROR: CloudWatch Agent binary not found at $AGENT_CTL. Exiting."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_message "ERROR: 'jq' utility is not installed. Please install it."
    exit 1
fi

JSON_ITEMS=$(jq -n '[]')
found_containers=""

# Query all containers including stopped ones (-a)
for id in $(docker ps -a -q); do
    name=$(docker inspect --format '{{.Name}}' "$id" | sed 's/\///')
    log=$(docker inspect --format '{{.LogPath}}' "$id")
    
    # If the log path is empty, skip silently
    if [ -z "$log" ] || [ "$log" = "<no value>" ]; then
        continue
    fi

    # Check the ignore list
    should_ignore=false
    for skip in $IGNORE_CONTAINERS; do
        if [ "$name" = "$skip" ]; then
            should_ignore=true
            break
        fi
    done
    
    if [ "$should_ignore" = true ]; then
        continue
    fi
    
	ITEM=$(jq -n \
        --arg file "$log" \
        --arg stream "{instance_id}/$name" \
        '{file_path: $file, log_group_name: "/aws/ec2/docker-containers", log_stream_name: $stream, retention_in_days: 30}')

    
    JSON_ITEMS=$(echo "$JSON_ITEMS" | jq --argjson item "$ITEM" '. += [$item]')
    found_containers="$found_containers $name"
done

# Sort the JSON array by file_path to prevent false positives caused by docker ps ordering
jq -n --argjson list "$JSON_ITEMS" '{"logs":{"logs_collected":{"files":{"collect_list": ($list | sort_by(.file_path))}}}}' > "$TMP_FILE"

# CHECK FOR CHANGES
if ! cmp -s "$TMP_FILE" "$FINAL_FILE"; then
    # Log execution only if actual configuration changes are detected
    log_message "=== Changes detected! Starting CloudWatch configuration update ==="
    
    if [ "$found_containers" = "" ]; then
        log_message "INFO: No active containers found for log collection."
    else
        log_message "Found containers for AWS export:$found_containers"
    fi

    log_message "Updating CloudWatch Agent configuration..."
    mv "$TMP_FILE" "$FINAL_FILE"
    
    CMD_OUT=$("$AGENT_CTL" -a append-config -m ec2 -c file:"$FINAL_FILE" 2>&1)
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: New Docker configuration added to CloudWatch Agent."
    else
        log_message "ERROR during append-config execution: $CMD_OUT"
    fi
    
    log_message "=== Change processing completed ==="
    echo "" >> "$LOG_FILE"
else
    # If no changes are found, silently remove the temporary file without writing to the log
    rm -f "$TMP_FILE"
fi
