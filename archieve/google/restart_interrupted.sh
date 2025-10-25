#!/bin/bash

echo "🔄 Running: restart_interrupted.sh"
echo "=== Checking for Interrupted Spot Instances ==="

# Count VMs from config
vm_count=$(grep -v '^#' node_assignments.txt | grep -v '^$' | wc -l)
restarted=0

for i in $(seq 1 $vm_count); do
  vm_status=$(gcloud compute instances describe nexus-farm-$i --zone=us-central1-a --format="value(status)" 2>/dev/null)
  
  if [ "$vm_status" = "TERMINATED" ] || [ "$vm_status" = "STOPPED" ]; then
    echo "🔄 Restarting nexus-farm-$i (status: $vm_status)"
    gcloud compute instances start nexus-farm-$i --zone=us-central1-a
    ((restarted++))
    
    # Wait for VM to start, then restart containers
    sleep 90
    echo "Restarting containers on nexus-farm-$i..."
    gcloud compute ssh nexus-farm-$i --zone=us-central1-a --command="cd Nexus && ./create_containers.sh" 2>/dev/null || echo "Failed to restart containers on nexus-farm-$i"
  elif [ "$vm_status" = "RUNNING" ]; then
    echo "✅ nexus-farm-$i is running"
  else
    echo "❓ nexus-farm-$i status: $vm_status"
  fi
done

echo ""
echo "=== Summary ==="
echo "Restarted: $restarted VMs"
echo "Total VMs: $vm_count"

if [ $restarted -gt 0 ]; then
  echo ""
  echo "Waiting for containers to start..."
  sleep 60
  echo "Running status check..."
  ./check_all_farms.sh
fi
