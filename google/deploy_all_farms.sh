#!/bin/bash

echo "🚀 Running: deploy_all_farms.sh"
echo "=== Dynamic Nexus Farm Deployment Across Multiple Zones ==="

# Function to install Docker on a VM (remove existing first)
install_docker() {
    local vm_name=$1
    local vm_zone=$2

    echo "🔄 Removing and reinstalling Docker on $vm_name..."

    install_script='
        # Remove any existing Docker installations
        echo "Removing existing Docker installations..."
        sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        sudo apt-get purge -y docker docker-engine docker.io containerd runc docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
        sudo rm -rf /var/lib/docker /etc/docker ~/.docker 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/docker.list /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true

        # Update package index
        sudo apt-get update -y

        # Fresh Docker installation using get.docker.com script
        echo "Installing Docker from scratch..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh

        # Start and enable Docker service
        sudo systemctl start docker
        sudo systemctl enable docker

        # Add current user to docker group
        sudo usermod -aG docker $USER

        # Verify installation
        sudo docker --version
        sudo systemctl is-active docker
        echo "Docker installation completed successfully"
    '

    echo "Fresh Docker installation on $vm_name..."
    if gcloud compute ssh "$vm_name" --zone="$vm_zone" --command="$install_script" < /dev/null; then
        echo "✅ Docker successfully installed on $vm_name"
        return 0
    else
        echo "❌ Failed to install Docker on $vm_name"
        return 1
    fi
}

# Function to ensure VM has Docker installed (always reinstall)
ensure_vm_ready() {
    local vm_name=$1
    local vm_zone=$2

    echo "🔧 Preparing $vm_name for deployment..."

    # Always install Docker fresh
    if ! install_docker "$vm_name" "$vm_zone"; then
        echo "❌ Failed to install Docker on $vm_name"
        return 1
    fi

    echo "✅ $vm_name is ready for deployment (Docker freshly installed)"
    return 0
}

# Check if node_assignments.txt exists
if [ ! -f "node_assignments.txt" ]; then
    echo "❌ node_assignments.txt file not found!"
    exit 1
fi

# Check if required Nexus files exist in parent directory
echo "🔍 Checking for required Nexus files..."
required_files=("../create_containers.sh" "../monitor_script.sh" "../Dockerfile")
missing_files=()

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    echo "❌ Missing required files in parent directory:"
    for file in "${missing_files[@]}"; do
        echo "  - $file"
    done
    echo
    echo "Please ensure these files are in the parent directory (../)"
    echo "Required files: create_containers.sh, monitor_script.sh, Dockerfile"
    exit 1
fi

echo "✅ Found all required Nexus files in parent directory"

# Count VMs needed based on node_assignments.txt (only non-comment, non-empty lines)
vm_count=$(grep -v '^[[:space:]]*#' node_assignments.txt | grep -v '^[[:space:]]*$' | wc -l)
echo "📊 Deploying to $vm_count VMs based on node configuration"

# Get all existing nexus-farm VMs with their zones - FIXED VERSION
echo "🔍 Getting VM list..."

# Test gcloud connectivity first
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
    echo "❌ gcloud authentication issue!"
    exit 1
fi

# Get VM list without suppressing stderr initially to debug issues
echo "📡 Fetching VM list from Google Cloud..."
vm_list_raw=$(gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)")
vm_list_exit_code=$?

if [ $vm_list_exit_code -ne 0 ]; then
    echo "❌ Failed to get VM list!"
    echo "Error code: $vm_list_exit_code"
    exit 1
fi

# Clean the VM list (remove empty lines)
vm_list=$(echo "$vm_list_raw" | grep -v '^[[:space:]]*$')

if [ -z "$vm_list" ]; then
    echo "❌ No nexus-farm VMs found!"
    echo "Run ./create_vms_from_config.sh to create VMs first."
    exit 1
fi

# Count total available VMs
total_vms=$(echo "$vm_list" | wc -l)
echo "📊 Found $total_vms available nexus-farm VMs"

# Validate we have VMs
if [ "$total_vms" -eq 0 ]; then
    echo "❌ No VMs available!"
    exit 1
fi

# Start any TERMINATED VMs
echo "🔍 Checking for terminated VMs to start..."
terminated_vms=$(gcloud compute instances list --filter="name:nexus-farm-* AND status:TERMINATED" --format="value(name,zone)")
if [ -n "$terminated_vms" ]; then
    echo "Starting terminated VMs..."
    while read vm_name vm_zone; do
        if [ -n "$vm_name" ]; then
            echo "Starting $vm_name in $vm_zone..."
            gcloud compute instances start "$vm_name" --zone="$vm_zone"
        fi
    done <<< "$terminated_vms"
    echo "⏳ Waiting 30 seconds for VMs to start..."
    sleep 30

    # Refresh the VM list
    vm_list=$(gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)" | grep -v '^[[:space:]]*$')
    total_vms=$(echo "$vm_list" | wc -l)
fi

echo "📍 Available VMs in multiple zones:"
echo "$vm_list" | while read vm_name vm_zone; do
    zone_short=$(basename "$vm_zone")
    echo "  $vm_name → $zone_short"
done
echo

# Debug: Show what we're reading from the file
echo "🔍 Debug: Valid lines in node_assignments.txt:"
grep -v '^[[:space:]]*#' node_assignments.txt | grep -v '^[[:space:]]*$' | nl
echo

# Initialize counters
assignment_line=0
vm_num=1
deployed_count=0
failed_count=0
preparation_failed=0

echo "📋 Reading node assignments from node_assignments.txt..."

# Create an array from vm_list for more reliable access
IFS=$'\n' read -d '' -r -a vm_array <<< "$vm_list"

echo "🔍 Debug: VM array has ${#vm_array[@]} elements"
for i in "${!vm_array[@]}"; do
    echo "  [$i]: ${vm_array[$i]}"
done
echo

# FIXED: Read assignments into array instead of using while loop
echo "📋 Loading node assignments into array..."
mapfile -t assignment_array < <(grep -v '^[[:space:]]*#' node_assignments.txt | grep -v '^[[:space:]]*$')

echo "🔍 Debug: Found ${#assignment_array[@]} assignment lines"
for i in "${!assignment_array[@]}"; do
    echo "  Assignment $((i+1)): ${assignment_array[$i]}"
done
echo

# Process each assignment using for loop instead of while loop
for i in "${!assignment_array[@]}"; do
    assignment_line=$((i + 1))
    line="${assignment_array[$i]}"
    
    echo "📋 Processing assignment line $assignment_line: '$line'"

    # Clean the line (remove leading/trailing whitespace)
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip if line is empty after cleaning
    if [ -z "$line" ]; then
        echo "⏭️  Skipping empty line $assignment_line"
        continue
    fi

    # Count nodes in this line
    node_count=$(echo "$line" | tr ',' '\n' | wc -l)

    # Check if we have more VMs available
    if [ $((vm_num-1)) -ge ${#vm_array[@]} ]; then
        echo "❌ No more VMs available! Need VM #$vm_num but only have ${#vm_array[@]} VMs"
        echo "Available VMs:"
        for j in "${!vm_array[@]}"; do
            echo "  [$((j+1))]: ${vm_array[$j]}"
        done
        echo "Skipping remaining assignments..."
        break
    fi

    # Get VM info from array
    vm_info="${vm_array[$((vm_num-1))]}"
    vm_name=$(echo "$vm_info" | awk '{print $1}')
    vm_zone=$(echo "$vm_info" | awk '{print $2}')
    zone_short=$(basename "$vm_zone")

    echo
    echo "=============================================="
    echo "=== Processing Assignment $assignment_line → VM $vm_num ($vm_name) ==="
    echo "=============================================="
    echo "🌍 Zone: $zone_short"
    echo "🏷️  Node IDs: $line"
    echo "📊 Node count: $node_count"
    echo "Assignment line: $assignment_line, VM number: $vm_num"

    # Validate VM info parsing
    if [ -z "$vm_name" ] || [ -z "$vm_zone" ]; then
        echo "❌ Failed to parse VM info: '$vm_info'"
        ((failed_count++))
        ((vm_num++))
        continue
    fi

    # Ensure VM has Docker installed
    if ! ensure_vm_ready "$vm_name" "$vm_zone"; then
        echo "❌ Failed to prepare $vm_name - Docker not available"
        ((preparation_failed++))
        ((failed_count++))
        echo "Continuing to next VM..."
        ((vm_num++))
        continue
    fi

    echo
    echo "🚀 === Deploying to Farm $vm_num ($vm_name) ==="
    echo "Executing: ./deploy_nexus_with_env.sh \"$vm_name\" \"$vm_zone\" \"$line\""

    # Deploy to this VM with proper error handling and timeout protection
    if [ -f "./deploy_nexus_with_env.sh" ]; then
        echo "🔍 DEBUG: About to deploy to $vm_name (assignment $assignment_line)"
        echo "🔍 DEBUG: Before deployment - assignment_line=$assignment_line, vm_num=$vm_num"
        
        # Ensure the deployment script has execute permissions
        chmod +x ./deploy_nexus_with_env.sh
        
        # Set deployment timeout (15 minutes)
        DEPLOYMENT_TIMEOUT=900
        
        echo "⏰ Starting deployment to $vm_name with ${DEPLOYMENT_TIMEOUT}s timeout..."
        echo "   (This prevents getting stuck on Docker builds that can take 10-20 minutes)"
        
        # Run deployment with timeout in a subshell to isolate any exit commands
        if timeout $DEPLOYMENT_TIMEOUT bash -c "(./deploy_nexus_with_env.sh \"$vm_name\" \"$vm_zone\" \"$line\")"; then
            echo "✅ Successfully deployed to $vm_name with nodes: $line"
            ((deployed_count++))
        else
            exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "⏰ Deployment to $vm_name timed out after $((DEPLOYMENT_TIMEOUT/60)) minutes"
                echo "🔧 This usually happens during Docker build (Rust compilation)"
                echo "🔍 Checking if containers were created despite timeout..."
                
                # Check if containers were created despite timeout
                timeout 30 gcloud compute ssh "$vm_name" --zone="$vm_zone" --command="
                    container_count=\$(sudo docker ps --filter 'name=nexus-' --format '{{.Names}}' 2>/dev/null | wc -l)
                    if [ \"\$container_count\" -gt 0 ]; then
                        echo \"CONTAINERS_FOUND:\$container_count\"
                        sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}'
                    else
                        echo \"NO_CONTAINERS\"
                        # Check if build was in progress
                        if sudo docker images | grep -q nexus-node; then
                            echo \"IMAGE_EXISTS\"
                        else
                            echo \"NO_IMAGE\"
                        fi
                    fi
                " < /dev/null 2>/dev/null | while read response; do
                    if [[ "$response" == CONTAINERS_FOUND:* ]]; then
                        container_count=$(echo "$response" | cut -d: -f2)
                        echo "✅ Found $container_count containers running despite timeout!"
                        echo "   Deployment likely succeeded but took longer than expected"
                        ((deployed_count++))
                        break
                    elif [[ "$response" == "IMAGE_EXISTS" ]]; then
                        echo "🔧 Docker image exists, attempting container restart..."
                        timeout 60 gcloud compute ssh "$vm_name" --zone="$vm_zone" --command="
                            cd \$HOME
                            if [ -f create_containers.sh ] && [ -f .env ]; then
                                echo 'Attempting to restart container creation...'
                                ./create_containers.sh
                            fi
                        " < /dev/null || echo "❌ Container restart failed"
                        ((failed_count++))
                    else
                        echo "❌ No containers found - deployment genuinely failed"
                        ((failed_count++))
                    fi
                done
                
                # If the check itself timed out or failed, count as failed
                if [ $? -ne 0 ]; then
                    echo "❌ Could not verify container status after timeout"
                    ((failed_count++))
                fi
            else
                echo "❌ Failed to deploy to $vm_name with nodes: $line (exit code: $exit_code)"
                echo "Check deploy_nexus_with_env.sh script and VM connectivity"
                ((failed_count++))
            fi
        fi
        
        echo "🔍 DEBUG: After deployment - assignment_line=$assignment_line, vm_num=$vm_num"
    else
        echo "❌ deploy_nexus_with_env.sh script not found!"
        ((failed_count++))
    fi

    ((vm_num++))
    
    # Only wait if this wasn't the last assignment
    if [ $assignment_line -lt ${#assignment_array[@]} ]; then
        echo "⏳ Waiting 5 seconds before next deployment..."
        sleep 5
    fi

    echo "🔍 DEBUG: Completed processing assignment $assignment_line, moving to next..."

done

echo "🔍 DEBUG: Finished processing all assignments"

# Final check - ensure we processed all expected assignments
echo
echo "📊 Processing Summary:"
echo "Total assignment lines read: $assignment_line"
echo "Total VMs processed: $(($vm_num - 1))"
echo "Available VMs: ${#vm_array[@]}"

echo
echo "=== Deployment Summary ==="
echo "✅ Successfully deployed: $deployed_count VMs"
echo "❌ Failed deployments: $failed_count VMs"
echo "⚠️ Preparation failures: $preparation_failed VMs"
echo "Total VMs processed: $(($deployed_count + $failed_count))"
deployed_farms="$deployed_count VMs with containers (actual count determined by create_containers.sh)"
echo "Deployed farms: $deployed_farms"

echo
echo "📊 Final VM Status:"
gcloud compute instances list --filter="name:nexus-farm-*" --format="table(name,zone,status)"

if [ $deployed_count -gt 0 ]; then
    echo
    echo "🎉 Deployment completed!"
    echo "Run ./check_all_farms.sh to verify all containers are running"
else
    echo
    echo "⚠️ No successful deployments!"
    echo "Check the error messages above and ensure VMs are accessible"
    if [ $preparation_failed -gt 0 ]; then
        echo "Note: $preparation_failed VMs failed during Docker installation"
    fi
fi
echo
