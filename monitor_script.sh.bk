#!/bin/bash
# Simple nexus monitor - checks and fixes issues

# Load environment variables
if [[ -f .env ]]; then
    source .env
else
    echo "❌ .env file not found. Please create it with your NODE_IDS."
    exit 1
fi

# Convert comma-separated NODE_IDS to array
IFS=',' read -ra NODE_IDS_ARRAY <<< "$NODE_IDS"

LOG_FILE="/var/log/nexus_monitor.log"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Print and log function
print_log() {
    echo "$1"
    log "$1"
}

echo "=== Nexus Monitor Check - $(date) ==="
ACTIONS=0
HEALTHY=0

# Check each container
for i in $(seq 1 ${#NODE_IDS_ARRAY[@]}); do
    NODE_ID=${NODE_IDS_ARRAY[$((i-1))]}
    echo -n "Checking nexus-$i (node-id: $NODE_ID)... "
    
    # Check if container is running
    if ! sudo docker ps --filter "name=nexus-$i" | grep -q nexus-$i; then
        echo "❌ Container stopped - starting"
        print_log "Starting stopped container nexus-$i"
        sudo docker start nexus-$i
        sleep 3
        ((ACTIONS++))
        continue
    fi
    
    # Check if screen session exists
    SCREENS=$(sudo docker exec nexus-$i screen -list 2>/dev/null | grep -c "nexus-session" || echo "0")
    
    if [[ $SCREENS -eq 0 ]]; then
        echo "❌ No screen session - starting"
        print_log "Starting screen session in nexus-$i"
        sudo docker exec -d nexus-$i screen -dmS nexus-session bash -c "
            cd /root
            while true; do
                echo \"\$(date): Starting nexus-network with node-id $NODE_ID\" | tee -a /root/logs/restart.log
                nexus-network start --node-id $NODE_ID 2>&1 | tee -a /root/logs/nexus.log
                echo \"\$(date): Nexus exited. Restarting in 15 seconds...\" | tee -a /root/logs/restart.log
                sleep 15
            done
        "
        ((ACTIONS++))
    else
        # Check if nexus process is running
        NEXUS_PROCESSES=$(sudo docker exec nexus-$i ps aux | grep "nexus-network" | grep -v grep | wc -l)
        if [[ $NEXUS_PROCESSES -gt 0 ]]; then
            echo "✅ Healthy (screen + nexus running)"
            ((HEALTHY++))
        else
            echo "⚠️  Screen exists but no nexus process"
            ((HEALTHY++))  # Still count as healthy since it might be restarting
        fi
    fi
done

# Print summary
echo ""
echo "=== Summary ==="
echo "Total containers: ${#NODE_IDS_ARRAY[@]}"
echo "Healthy: $HEALTHY"
echo "Actions taken: $ACTIONS"

# Log summary
if [[ $ACTIONS -eq 0 ]]; then
    echo "✅ All containers healthy!"
    # Only log "healthy" once per hour to avoid spam
    if [[ $(date +%M) -eq 0 ]]; then
        log "All ${#NODE_IDS_ARRAY[@]} containers healthy"
    fi
else
    echo "🔧 Fixed $ACTIONS issues"
    log "Fixed $ACTIONS issues out of ${#NODE_IDS_ARRAY[@]} containers"
fi

echo "Logs: tail -f $LOG_FILE"
