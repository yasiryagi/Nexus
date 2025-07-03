#!/bin/bash
# Simple nexus monitor - checks and fixes issues
# Enhanced with optional auto-upgrade functionality

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
UPGRADE_LOG_FILE="/var/log/nexus_upgrade.log"
BACKUP_DIR="/home/nexus-containers/backups"
LAST_UPGRADE_CHECK_FILE="/tmp/nexus_last_upgrade_check"

# Default upgrade settings (can be overridden in .env)
AUTO_UPGRADE_ENABLED=${AUTO_UPGRADE_ENABLED:-false}
CHECK_UPGRADE_INTERVAL=${CHECK_UPGRADE_INTERVAL:-86400}  # 24 hours
FORCE_UPGRADE=${FORCE_UPGRADE:-false}

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | sudo tee -a "$LOG_FILE" > /dev/null
}

# Upgrade log function
log_upgrade() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | sudo tee -a "$UPGRADE_LOG_FILE" > /dev/null
}

# Print and log function
print_log() {
    echo "$1"
    log "$1"
}

# Get current Nexus version in container
get_current_nexus_version() {
    local container_name=$1
    
    if sudo docker exec "${container_name}" which nexus-network &>/dev/null; then
        # Try different version extraction methods
        local version_output=$(sudo docker exec "${container_name}" nexus-network --version 2>/dev/null || echo "")
        
        # Try multiple regex patterns to extract version
        local version=""
        
        # Pattern 1: v1.2.3 format
        version=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        
        # Pattern 2: 1.2.3 format (without v)
        if [[ -z "$version" ]]; then
            version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [[ -n "$version" ]]; then
                version="v$version"
            fi
        fi
        
        # Pattern 3: Look for any version-like pattern
        if [[ -z "$version" ]]; then
            version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
            if [[ -n "$version" ]]; then
                version="v$version"
            fi
        fi
        
        # Return version or unknown if not found
        if [[ -n "$version" ]]; then
            echo "$version"
        else
            echo "unknown"
        fi
    else
        echo "not_installed"
    fi
}

# Get latest Nexus CLI version from GitHub
get_latest_nexus_version() {
    # Since we're using the official installer, we can just check what version it installs
    # For display purposes, we'll try to get the latest release tag
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/nexus-xyz/nexus-cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || echo "latest")
    echo "$latest_version"
}

# Check if upgrade check is needed
should_check_for_upgrade() {
    if [[ "$FORCE_UPGRADE" == "true" ]]; then
        return 0
    fi
    
    if [[ ! -f "$LAST_UPGRADE_CHECK_FILE" ]]; then
        echo "First run - upgrade check needed"
        return 0
    fi
    
    local last_check=$(cat "$LAST_UPGRADE_CHECK_FILE")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_check))
    
    if [[ $time_diff -ge $CHECK_UPGRADE_INTERVAL ]]; then
        return 0
    else
        return 1
    fi
}

# Update last upgrade check timestamp
update_upgrade_check_timestamp() {
    echo "$(date +%s)" | sudo tee "$LAST_UPGRADE_CHECK_FILE" > /dev/null
}

# Install/Update Nexus in container using official installer
install_nexus_in_container() {
    local container_name=$1
    
    log_upgrade "INFO: ${container_name}: Installing/updating Nexus using official installer"
    
    # Run the installation process inside the container
    sudo docker exec "${container_name}" bash -c '
        # Download and run the official installer
        curl -L https://cli.nexus.xyz/ -o /root/install.sh
        chmod +x /root/install.sh
        cd /root && echo "y" | bash install.sh
        
        # Copy nexus binary to /usr/local/bin so it is always available
        cp /root/.nexus/bin/nexus-network /usr/local/bin/nexus-network
        chmod +x /usr/local/bin/nexus-network
        
        # Verify installation
        /usr/local/bin/nexus-network --version
    ' 2>&1
    
    # Check if installation was successful
    if sudo docker exec "${container_name}" test -f /usr/local/bin/nexus-network; then
        log_upgrade "INFO: ${container_name}: Nexus installation successful"
        return 0
    else
        log_upgrade "ERROR: ${container_name}: Nexus installation failed"
        return 1
    fi
}

# Create backup before upgrade
create_upgrade_backup() {
    local container_name=$1
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${BACKUP_DIR}/${container_name}_upgrade_${backup_timestamp}"
    
    sudo mkdir -p "${backup_path}"
    
    # Backup current binary
    if sudo docker exec "${container_name}" which nexus-network &>/dev/null; then
        sudo docker exec "${container_name}" cp /usr/local/bin/nexus-network /tmp/nexus-network-backup 2>/dev/null || true
        sudo docker cp "${container_name}:/tmp/nexus-network-backup" "${backup_path}/nexus-network-original" 2>/dev/null || true
        sudo docker exec "${container_name}" rm -f /tmp/nexus-network-backup
    fi
    
    # Create backup manifest
    local current_version=$(get_current_nexus_version "${container_name}")
    sudo tee "${backup_path}/backup_manifest.txt" > /dev/null << EOF
Backup created: ${backup_timestamp}
Container: ${container_name}
Backup type: Auto-upgrade backup
Current Nexus version: ${current_version}
EOF
    
    echo "${backup_path}"
}

# Upgrade single container
upgrade_container() {
    local container_name=$1
    local target_version=$2
    local node_id=$3
    
    echo "🔄 ${container_name}: Starting upgrade process..."
    log_upgrade "INFO: Upgrading ${container_name}"
    
    # Get current version for comparison
    local current_version
    current_version=$(get_current_nexus_version "${container_name}")
    echo "   Current version: ${current_version}"
    
    # Create backup
    local backup_path
    backup_path=$(create_upgrade_backup "${container_name}")
    echo "   ✅ Backup created: $(basename "${backup_path}")"
    
    # Stop current screen session
    echo "   🛑 Stopping screen session..."
    log_upgrade "INFO: ${container_name}: Stopping current screen session"
    sudo docker exec "${container_name}" screen -S nexus-session -X quit 2>/dev/null || true
    sudo docker exec "${container_name}" pkill -f "nexus-network" 2>/dev/null || true
    sleep 3
    
    # Install/update Nexus using official installer
    echo "   📥 Installing latest Nexus..."
    if ! install_nexus_in_container "${container_name}"; then
        echo "   ❌ Installation failed"
        
        # Restore backup if available
        if [[ -f "${backup_path}/nexus-network-original" ]]; then
            echo "   🔄 Restoring previous binary..."
            log_upgrade "INFO: ${container_name}: Restoring previous binary"
            sudo docker cp "${backup_path}/nexus-network-original" "${container_name}:/usr/local/bin/nexus-network"
            sudo docker exec "${container_name}" chmod +x /usr/local/bin/nexus-network
        fi
        return 1
    fi
    
    # Verify installation and get new version
    local new_version
    new_version=$(get_current_nexus_version "${container_name}")
    echo "   📦 New version: ${new_version}"
    
    # Start new screen session with updated binary
    echo "   ▶️  Starting screen session..."
    log_upgrade "INFO: ${container_name}: Starting screen session with new version"
    sudo docker exec -d "${container_name}" screen -dmS nexus-session bash -c "
        cd /root
        while true; do
            echo \"\$(date): Starting nexus-network with node-id ${node_id}\" | tee -a /root/logs/restart.log
            nexus-network start --node-id ${node_id} 2>&1 | tee -a /root/logs/nexus.log
            echo \"\$(date): Nexus exited. Restarting in 15 seconds...\" | tee -a /root/logs/restart.log
            sleep 15
        done
    "
    
    # Verify it's running
    sleep 5
    if sudo docker exec "${container_name}" screen -list 2>/dev/null | grep -q nexus-session; then
        echo "   ✅ Screen session started successfully"
        log_upgrade "SUCCESS: ${container_name}: Upgraded successfully (${current_version} → ${new_version})"
        return 0
    else
        echo "   ❌ Failed to start screen session"
        log_upgrade "ERROR: ${container_name}: Failed to start after upgrade"
        return 1
    fi
}

# Check and perform upgrades
check_and_upgrade() {
    if [[ "$AUTO_UPGRADE_ENABLED" != "true" ]]; then
        return 0
    fi
    
    if ! should_check_for_upgrade; then
        echo "⏰ Upgrade check not due yet (next check in $((CHECK_UPGRADE_INTERVAL - ($(date +%s) - $(cat "$LAST_UPGRADE_CHECK_FILE" 2>/dev/null || echo 0)))) seconds)"
        return 0
    fi
    
    echo "🔍 Checking for Nexus upgrades..."
    log_upgrade "INFO: Checking for Nexus upgrades..."
    
    # Get latest version
    local latest_version
    latest_version=$(get_latest_nexus_version)
    if [[ -z "$latest_version" ]]; then
        echo "❌ Could not fetch latest Nexus version from GitHub"
        log_upgrade "WARN: Could not fetch latest Nexus version"
        return 1
    fi
    
    echo "📦 Latest available version: ${latest_version}"
    log_upgrade "INFO: Latest available version: ${latest_version}"
    
    # Check each container and show current versions
    echo ""
    echo "=== Version Check ==="
    local upgrade_needed=false
    local containers_to_upgrade=()
    
    for i in $(seq 1 ${#NODE_IDS_ARRAY[@]}); do
        local container_name="nexus-$i"
        local node_id=${NODE_IDS_ARRAY[$((i-1))]}
        
        # Only check running containers
        if ! sudo docker ps --filter "name=${container_name}" | grep -q ${container_name}; then
            echo "${container_name}: ⏸️  Container not running - skipping"
            continue
        fi
        
        local current_version
        current_version=$(get_current_nexus_version "${container_name}")
        
        if [[ "$current_version" == "not_installed" ]]; then
            echo "${container_name}: ❌ Nexus not installed"
            log_upgrade "WARN: ${container_name}: Nexus not installed"
            continue
        fi
        
        if [[ "$current_version" != "$latest_version" ]]; then
            echo "${container_name}: 🔄 ${current_version} → ${latest_version} (upgrade needed)"
            log_upgrade "INFO: ${container_name}: Upgrade available (${current_version} → ${latest_version})"
            containers_to_upgrade+=("${container_name}:${node_id}:${current_version}")
            upgrade_needed=true
        else
            echo "${container_name}: ✅ ${current_version} (up to date)"
            log_upgrade "INFO: ${container_name}: Already up to date (${current_version})"
        fi
    done
    
    # Perform upgrades if needed
    if [[ "$upgrade_needed" == "true" ]]; then
        echo ""
        echo "=== Starting Upgrades ==="
        sudo mkdir -p "${BACKUP_DIR}"
        
        local successful_upgrades=0
        local failed_upgrades=0
        
        for container_info in "${containers_to_upgrade[@]}"; do
            local container_name=$(echo "$container_info" | cut -d: -f1)
            local node_id=$(echo "$container_info" | cut -d: -f2)
            local current_version=$(echo "$container_info" | cut -d: -f3)
            
            echo ""
            echo "⬆️  Upgrading ${container_name}: ${current_version} → ${latest_version}"
            
            if upgrade_container "$container_name" "$latest_version" "$node_id"; then
                echo "✅ ${container_name}: Upgrade successful"
                ((successful_upgrades++))
            else
                echo "❌ ${container_name}: Upgrade failed"
                ((failed_upgrades++))
            fi
            sleep 2  # Brief pause between upgrades
        done
        
        echo ""
        echo "=== Upgrade Summary ==="
        echo "✅ Successful: ${successful_upgrades}"
        echo "❌ Failed: ${failed_upgrades}"
        
        log_upgrade "SUCCESS: Upgrade summary: ${successful_upgrades} successful, ${failed_upgrades} failed"
        
        if [[ $failed_upgrades -gt 0 ]]; then
            echo "⚠️  Some upgrades failed. Check upgrade logs for details."
            log "UPGRADE: Some container upgrades failed. Check ${UPGRADE_LOG_FILE} for details"
        fi
    else
        echo "✅ All containers are up to date"
        log_upgrade "INFO: All containers are up to date"
    fi
    
    # Update check timestamp
    update_upgrade_check_timestamp
}

# Main monitoring logic (original functionality)
echo "=== Nexus Monitor Check - $(date) ==="
ACTIONS=0
HEALTHY=0

# Check each container (original logic)
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
        NEXUS_PROCESSES=$(sudo docker exec nexus-$i ps aux | grep "nexus-network" | grep -v grep | wc -l | tr -d ' \n')
        if [[ "${NEXUS_PROCESSES}" -gt 0 ]]; then
            echo "✅ Healthy (screen + nexus running)"
            ((HEALTHY++))
        else
            echo "⚠️  Screen exists but no nexus process"
            ((HEALTHY++))  # Still count as healthy since it might be restarting
        fi
    fi
done

# Print summary (original)
echo ""
echo "=== Summary ==="
echo "Total containers: ${#NODE_IDS_ARRAY[@]}"
echo "Healthy: $HEALTHY"
echo "Actions taken: $ACTIONS"

# Add upgrade check after main monitoring
if [[ "$AUTO_UPGRADE_ENABLED" == "true" ]]; then
    echo "Auto-upgrade: Enabled"
    check_and_upgrade
else
    echo "Auto-upgrade: Disabled"
fi

# Log summary (original logic)
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
if [[ "$AUTO_UPGRADE_ENABLED" == "true" ]]; then
    echo "Upgrade logs: tail -f $UPGRADE_LOG_FILE"
fi
