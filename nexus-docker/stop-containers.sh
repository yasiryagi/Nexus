#!/bin/bash
echo "Stopping all optimized Nexus containers..."
sudo docker stop $(sudo docker ps --filter "name=nexus-" --format "{{.Names}}") 2>/dev/null
echo "✓ All containers stopped"
