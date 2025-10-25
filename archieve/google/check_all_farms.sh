#!/bin/bash

echo "🔍 Running: check_all_farms.sh"
echo "=== Checking All Nexus Farms Status ==="

# Get all running nexus-farm VMs
vm_list=$(gcloud compute instances list --filter="name:nexus-farm-* AND status:RUNNING" --format="value(name,zone)")

if [ -z "$vm_list" ]; then
    echo "❌ No running nexus-farm VMs found!"
    echo "Available VMs:"
    gcloud compute instances list --filter="name:nexus-farm-*" --format="table(name,zone,status)"
    exit 1
fi

total_vms=$(echo "$vm_list" | wc -l)
echo "📊 Found $total_vms running nexus-farm VMs"

# Initialize counters
vm_count=0
total_containers=0
healthy_containers=0
unhealthy_containers=0

echo "📍 Checking each VM:"
echo "$vm_list" | while read vm_name vm_zone; do
    zone_short=$(basename "$vm_zone")
    echo "  $vm_name → $zone_short"
done
echo

# Check each VM
while read vm_name vm_zone; do
    ((vm_count++))
    zone_short=$(basename "$vm_zone")
    
    echo "=============================================="
    echo "=== Checking Farm $vm_count: $vm_name ($zone_short) ==="
    echo "=============================================="
    
    # Check if VM is accessible
    if ! gcloud compute ssh "$vm_name" --zone="$vm_zone" --command="echo 'VM accessible'" >/dev/null 2>&1; then
        echo "❌ Cannot access $vm_name - VM might be starting or has connectivity issues"
        continue
    fi
    
    echo "✅ VM $vm_name is accessible"
    
    # Get container status
    echo "🔍 Checking containers on $vm_name..."
    
    container_check=$(gcloud compute ssh "$vm_name" --zone="$vm_zone" --command="
        # Count total nexus containers
        total=\$(sudo docker ps -a --filter 'name=nexus-' --format '{{.Names}}' | wc -l)
        running=\$(sudo docker ps --filter 'name=nexus-' --format '{{.Names}}' | wc -l)
        
        echo \"CONTAINERS: \$total total, \$running running\"
        
        if [ \$running -gt 0 ]; then
            echo \"=== Running Containers ===\"
            sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
            
            echo \"=== Container Health Check ===\"
            for container in \$(sudo docker ps --filter 'name=nexus-' --format '{{.Names}}'); do
                echo \"Checking \$container...\"
                
                # Check if nexus command works
                if sudo docker exec \$container nexus-network --version >/dev/null 2>&1; then
                    echo \"  ✅ Nexus command: OK\"
                else
                    echo \"  ❌ Nexus command: FAILED\"
                fi
                
                # Check screen sessions
                screen_count=\$(sudo docker exec \$container screen -ls 2>/dev/null | grep -c nexus-session || echo 0)
                echo \"  📺 Screen sessions: \$screen_count\"
                
                # Check nexus processes
                nexus_processes=\$(sudo docker exec \$container pgrep -f nexus-network | wc -l)
                echo \"  📊 Nexus processes: \$nexus_processes\"
                
                # Get recent log entry if available
                if sudo docker exec \$container test -f /root/logs/nexus.log; then
                    recent_log=\$(sudo docker exec \$container tail -1 /root/logs/nexus.log 2>/dev/null || echo \"No recent logs\")
                    echo \"  📝 Recent: \$recent_log\"
                fi
                
                echo
            done
        else
            echo \"❌ No running containers found\"
            
            # Check if any containers exist but are stopped
            stopped=\$(sudo docker ps -a --filter 'name=nexus-' --filter 'status=exited' --format '{{.Names}}' | wc -l)
            if [ \$stopped -gt 0 ]; then
                echo \"⚠️ Found \$stopped stopped containers:\"
                sudo docker ps -a --filter 'name=nexus-' --filter 'status=exited' --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
            fi
        fi
        
        # Check monitoring setup
        echo \"=== Monitoring Status ===\"
        if [ -f 'monitor_script.sh' ]; then
            echo \"✅ Monitor script: Present\"
            if crontab -l 2>/dev/null | grep -q 'monitor_script.sh'; then
                echo \"✅ Cron job: Configured\"
            else
                echo \"❌ Cron job: Not configured\"
            fi
        else
            echo \"❌ Monitor script: Missing\"
        fi
        
        # Check system resources
        echo \"=== System Resources ===\"
        echo \"💾 Disk usage:\"
        df -h / | tail -1
        echo \"🧠 Memory usage:\"
        free -h | grep Mem
        echo \"⚡ Load average:\"
        uptime
    " 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$container_check"
        
        # Parse container counts
        containers_line=$(echo "$container_check" | grep "CONTAINERS:")
        if [ -n "$containers_line" ]; then
            vm_total=$(echo "$containers_line" | sed 's/.*CONTAINERS: \([0-9]*\) total.*/\1/')
            vm_running=$(echo "$containers_line" | sed 's/.*total, \([0-9]*\) running.*/\1/')
            
            total_containers=$((total_containers + vm_total))
            healthy_containers=$((healthy_containers + vm_running))
            
            if [ "$vm_running" -gt 0 ]; then
                echo "✅ $vm_name: $vm_running/$vm_total containers running"
            else
                echo "❌ $vm_name: No containers running (0/$vm_total)"
                unhealthy_containers=$((unhealthy_containers + vm_total))
            fi
        fi
    else
        echo "❌ Failed to check containers on $vm_name"
    fi
    
    echo
    echo "⏳ Waiting 3 seconds before checking next VM..."
    sleep 3
    
done <<< "$vm_list"

echo
echo "==============================================="
echo "=== OVERALL FARM STATUS SUMMARY ==="
echo "==============================================="
echo "📊 VMs checked: $vm_count"
echo "📦 Total containers: $total_containers"
echo "✅ Healthy containers: $healthy_containers"
echo "❌ Unhealthy containers: $unhealthy_containers"

if [ $healthy_containers -gt 0 ]; then
    health_percentage=$((healthy_containers * 100 / total_containers))
    echo "📈 Health percentage: $health_percentage%"
fi

echo
echo "📍 Quick VM Overview:"
gcloud compute instances list --filter="name:nexus-farm-*" --format="table(name,zone,status,machineType.scope(machineTypes))"

echo
echo "=== Useful Commands ==="
echo "🔍 Check specific farm: gcloud compute ssh nexus-farm-1 --zone=us-central1-a"
echo "🐳 View containers: sudo docker ps --filter 'name=nexus-'"
echo "📝 View logs: sudo docker exec nexus-1 tail -f /root/logs/nexus.log"
echo "📺 Screen session: sudo docker exec -it nexus-1 screen -r nexus-session"
echo "🔄 Restart container: sudo docker restart nexus-1"
echo "🔧 Run monitoring: ./monitor_script.sh"

if [ $healthy_containers -eq $total_containers ] && [ $total_containers -gt 0 ]; then
    echo
    echo "🎉 All farms are healthy and running!"
elif [ $healthy_containers -gt 0 ]; then
    echo
    echo "⚠️ Some containers need attention"
    echo "Consider running the monitoring script or restarting unhealthy containers"
else
    echo
    echo "🚨 No healthy containers found!"
    echo "You may need to redeploy or check the deployment logs"
fi

echo
echo "📊 Farm check completed at $(date)"
