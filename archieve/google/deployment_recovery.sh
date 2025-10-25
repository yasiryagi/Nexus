#!/bin/bash

echo "🛠️  Deployment Recovery Tool"
echo "============================="

# Function to check a specific VM
check_vm_status() {
    local vm_name=$1
    local vm_zone=$2
    
    echo "🔍 Checking $vm_name..."
    
    # Check if VM is running
    vm_status=$(gcloud compute instances describe "$vm_name" --zone="$vm_zone" --format="value(status)" 2>/dev/null)
    if [ "$vm_status" != "RUNNING" ]; then
        echo "❌ $vm_name is not running (status: $vm_status)"
        return 1
    fi
    
    # Check containers
    container_info=$(gcloud compute ssh "$vm_name" --zone="$vm_zone" --command="
        echo \"=== Container Status ===\"
        sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null || echo 'No containers'
        
        echo \"=== Docker Images ===\"
        sudo docker images | grep nexus-node || echo 'No nexus-node image'
        
        echo \"=== Disk Usage ===\"
        df -h /
        
        echo \"=== Build Processes ===\"
        ps aux | grep -E '(docker|cargo|rustc)' | grep -v grep || echo 'No build processes'
    " < /dev/null 2>/dev/null)
    
    echo "$container_info"
    
    # Count containers
    container_count=$(echo "$container_info" | grep -c "nexus-" || echo "0")
    if [ "$container_count" -gt 0 ]; then
        echo "✅ $vm_name: $container_count containers found"
        return 0
    else
        echo "⚠️ $vm_name: No containers running"
        return 1
    fi
}

# Function to force restart a stuck VM
restart_vm() {
    local vm_name=$1
    local vm_zone=$2
    
    echo "🔄 Force restarting $vm_name..."
    
    echo "1. Stopping VM..."
    gcloud compute instances stop "$vm_name" --zone="$vm_zone"
    
    echo "2. Waiting 15 seconds..."
    sleep 15
    
    echo "3. Starting VM..."
    gcloud compute instances start "$vm_name" --zone="$vm_zone"
    
    echo "4. Waiting 30 seconds for boot..."
    sleep 30
    
    echo "✅ $vm_name restarted"
}

# Function to manually deploy to a specific VM
manual_deploy() {
    local vm_name=$1
    local vm_zone=$2
    local node_ids=$3
    
    echo "🚀 Manual deployment to $vm_name..."
    echo "Node IDs: $node_ids"
    
    # Deploy with timeout
    if timeout 900 ./deploy_nexus_with_env.sh "$vm_name" "$vm_zone" "$node_ids"; then
        echo "✅ Manual deployment successful"
        return 0
    else
        echo "❌ Manual deployment failed or timed out"
        return 1
    fi
}

# Main menu
while true; do
    echo
    echo "🛠️  Recovery Options:"
    echo "1. Quick status check (all VMs)"
    echo "2. Detailed check for specific VM"
    echo "3. Force restart stuck VM"
    echo "4. Manual deploy to specific VM"
    echo "5. Resume deployment from specific VM"
    echo "6. Exit"
    echo
    read -p "Choose option (1-6): " choice
    
    case $choice in
        1)
            echo "📊 Quick Status Check:"
            ./quick_status.sh 2>/dev/null || echo "quick_status.sh not found"
            ;;
        2)
            echo "Available VMs:"
            gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)"
            read -p "Enter VM name: " vm_name
            read -p "Enter zone: " vm_zone
            check_vm_status "$vm_name" "$vm_zone"
            ;;
        3)
            echo "Available VMs:"
            gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)"
            read -p "Enter VM name to restart: " vm_name
            read -p "Enter zone: " vm_zone
            restart_vm "$vm_name" "$vm_zone"
            ;;
        4)
            echo "Available VMs:"
            gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)"
            read -p "Enter VM name: " vm_name
            read -p "Enter zone: " vm_zone
            read -p "Enter node IDs (comma-separated): " node_ids
            manual_deploy "$vm_name" "$vm_zone" "$node_ids"
            ;;
        5)
            echo "Create resume file from which VM? (1-4)"
            read -p "Start from VM number: " start_vm
            
            # Create resume assignments
            tail -n +$start_vm node_assignments.txt > node_assignments_resume.txt
            echo "Created resume file starting from VM $start_vm"
            
            # Backup and replace
            cp node_assignments.txt node_assignments.txt.backup
            cp node_assignments_resume.txt node_assignments.txt
            
            echo "Starting resume deployment..."
            ./deploy_all_farms.sh
            
            # Restore
            cp node_assignments.txt.backup node_assignments.txt
            rm node_assignments_resume.txt
            echo "Resume completed, original assignments restored"
            ;;
        6)
            echo "👋 Exiting recovery tool"
            exit 0
            ;;
        *)
            echo "❌ Invalid option"
            ;;
    esac
done
