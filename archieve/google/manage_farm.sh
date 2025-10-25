#!/bin/bash
echo "⚙️ Running: manage_farm.sh"

FARM_NUM=$1
ACTION=$2

if [ -z "$FARM_NUM" ] || [ -z "$ACTION" ]; then
  echo "Usage: ./manage_farm.sh <farm_number> <action>"
  echo "Actions: status, restart, logs, connect, stop, start, env"
  echo "Example: ./manage_farm.sh 3 status"
  exit 1
fi

VM_NAME="nexus-farm-$FARM_NUM"

case $ACTION in
  "status")
    echo "=== $VM_NAME Status ==="
    vm_status=$(gcloud compute instances describe $VM_NAME --zone=us-central1-a --format="value(status)" 2>/dev/null)
    echo "VM Status: $vm_status"
    if [ "$vm_status" = "RUNNING" ]; then
      gcloud compute ssh $VM_NAME --zone=us-central1-a --command="sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}'"
    fi
    ;;
  "restart")
    echo "Restarting containers on $VM_NAME..."
    gcloud compute ssh $VM_NAME --zone=us-central1-a --command="cd Nexus && ./create_containers.sh"
    ;;
  "logs")
    echo "Showing logs for $VM_NAME (nexus-1)..."
    gcloud compute ssh $VM_NAME --zone=us-central1-a --command="sudo docker exec nexus-1 tail -f /root/logs/nexus.log"
    ;;
  "connect")
    echo "Connecting to $VM_NAME..."
    gcloud compute ssh $VM_NAME --zone=us-central1-a
    ;;
  "stop")
    echo "Stopping $VM_NAME..."
    gcloud compute instances stop $VM_NAME --zone=us-central1-a
    ;;
  "start")
    echo "Starting $VM_NAME..."
    gcloud compute instances start $VM_NAME --zone=us-central1-a
    ;;
  "env")
    echo "Checking .env file on $VM_NAME..."
    gcloud compute ssh $VM_NAME --zone=us-central1-a --command="cd Nexus && echo '=== .env file ===' && cat .env"
    ;;
  *)
    echo "Unknown action: $ACTION"
    ;;
esac
