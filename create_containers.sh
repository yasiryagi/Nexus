#!/bin/bash
# Fixed container creation script

echo "=== Creating Fixed Nexus Containers ==="

# Load environment variables
if [[ -f .env ]]; then
    source .env
    echo "✅ Loaded configuration from .env"
else
    echo "❌ .env file not found. Please create it with your NODE_IDS."
    echo "Example: NODE_IDS=7306098,7324770,6766348"
    exit 1
fi

# Convert comma-separated NODE_IDS to array
IFS=',' read -ra NODE_IDS_ARRAY <<< "$NODE_IDS"
echo "Found ${#NODE_IDS_ARRAY[@]} node IDs: ${NODE_IDS_ARRAY[*]}"

# Step 1: Complete cleanup
echo "Step 1: Complete cleanup..."
sudo docker stop $(sudo docker ps -q --filter "name=nexus-") 2>/dev/null || true
sudo docker rm $(sudo docker ps -aq --filter "name=nexus-") 2>/dev/null || true
sudo docker rmi nexus-node 2>/dev/null || true
sudo rm -rf /home/nexus-containers 2>/dev/null || true

# Step 2: Create storage
echo "Step 2: Creating storage..."
sudo mkdir -p /home/nexus-containers

# Step 3: Build Docker image
echo "Step 3: Building Docker image..."
sudo docker rmi nexus-node
sudo docker build --no-cache -t nexus-node .
# Step 4: Test nexus in the image
echo "Step 4: Testing nexus in image..."
sudo docker run --rm nexus-node nexus-network --help

# Step 5: Create containers
echo "Step 5: Creating containers..."

for i in $(seq 1 ${#NODE_IDS_ARRAY[@]}); do
    NODE_ID=${NODE_IDS_ARRAY[$((i-1))]}
    echo ""
    echo "Creating nexus-$i with node-id $NODE_ID..."

    # Create directories for nexus data only (not the binary)
    sudo mkdir -p /home/nexus-containers/nexus-data-$i
    sudo mkdir -p /home/nexus-containers/logs-$i

    # Create container - mount data directory, not the nexus installation
    sudo docker run -it -d \
        --name nexus-$i \
        --restart unless-stopped \
        -v /home/nexus-containers/nexus-data-$i:/root/.nexus \
        -v /home/nexus-containers/logs-$i:/root/logs \
        nexus-node

    # Verify nexus is available in container
    sudo docker exec nexus-$i nexus-network --help > /dev/null

    # Create startup script
    sudo docker exec nexus-$i bash -c "
        cat > /root/start_nexus.sh << 'EOF'
#!/bin/bash

cd /root

# Log startup info
echo \"=== Nexus Startup for node-id $NODE_ID ===\" > /root/logs/startup.log
echo \"Date: \$(date)\" >> /root/logs/startup.log
echo \"Nexus location: \$(which nexus-network)\" >> /root/logs/startup.log
echo \"Nexus test: \$(nexus-network --help | head -1)\" >> /root/logs/startup.log

# Start nexus loop
while true; do
    echo \"\$(date): Starting nexus-network with node-id $NODE_ID\" | tee -a /root/logs/restart.log

    nexus-network start --node-id $NODE_ID 2>&1 | tee -a /root/logs/nexus.log

    echo \"\$(date): Nexus exited. Restarting in 15 seconds...\" | tee -a /root/logs/restart.log
    sleep 15
done
EOF
        chmod +x /root/start_nexus.sh
    "

    # Start in screen session
    sudo docker exec -d nexus-$i screen -dmS nexus-session /root/start_nexus.sh

    echo "✅ nexus-$i created and started"
done

echo ""
echo "🎉 All containers created!"
echo ""
echo "Waiting 20 seconds for startup..."
sleep 20

echo ""
echo "=== Status Check ==="
for i in $(seq 1 ${#NODE_IDS_ARRAY[@]}); do
    echo "nexus-$i:"

    if sudo docker ps --filter "name=nexus-$i" | grep -q nexus-$i; then
        # Test nexus command
        if sudo docker exec nexus-$i nexus-network --help > /dev/null 2>&1; then
            echo "  ✅ Nexus command works"
        else
            echo "  ❌ Nexus command failed"
        fi

        # Check screen sessions
        SCREENS=$(sudo docker exec nexus-$i screen -list 2>/dev/null | grep -c "nexus-session" || echo "0")
        echo "  📺 Screen sessions: $SCREENS"

        # Check nexus processes
        PROCESSES=$(sudo docker exec nexus-$i ps aux | grep "nexus-network" | grep -v grep | wc -l)
        echo "  📊 Nexus processes: $PROCESSES"

        # Check recent logs
        RECENT_LOG=$(sudo docker exec nexus-$i tail -1 /root/logs/restart.log 2>/dev/null || echo "No logs")
        echo "  📝 Recent: $RECENT_LOG"

    else
        echo "  ❌ Container not running"
    fi
    echo ""
done

echo "=== Commands ==="
echo "View startup: sudo docker exec nexus-1 cat /root/logs/startup.log"
echo "View logs: sudo docker exec nexus-1 tail -f /root/logs/nexus.log"
echo "Screen session: sudo docker exec -it nexus-1 screen -r nexus-session"
echo "Test nexus: sudo docker exec nexus-1 nexus-network --help"
