#!/bin/bash

echo "📦 Running: deploy_nexus_with_env.sh"

# Main deployment function - this allows us to use return properly
deploy_nexus() {
    local VM_NAME=$1
    local VM_ZONE=$2
    local NODE_IDS=$3

    # Validate parameters
    if [ -z "$VM_NAME" ] || [ -z "$VM_ZONE" ] || [ -z "$NODE_IDS" ]; then
        echo "❌ Usage: $0 <VM_NAME> <VM_ZONE> <NODE_IDS>"
        echo "Example: $0 nexus-farm-1 us-central1-a node1,node2,node3"
        return 1
    fi

    echo "=== Deploying to $VM_NAME ==="
    echo "Zone: $VM_ZONE"
    echo "Node IDs: $NODE_IDS"

    # Count nodes for verification
    node_count=$(echo "$NODE_IDS" | tr ',' '\n' | wc -l)
    echo "Expected containers: $node_count"

    # Check if VM exists and is running
    echo "🔍 Checking VM status..."
    vm_status=$(gcloud compute instances describe "$VM_NAME" --zone="$VM_ZONE" --format="value(status)" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "❌ VM $VM_NAME does not exist in zone $VM_ZONE!"
        return 1
    fi

    if [ "$vm_status" != "RUNNING" ]; then
        echo "⚡ Starting $VM_NAME..."
        if ! gcloud compute instances start "$VM_NAME" --zone="$VM_ZONE"; then
            echo "❌ Failed to start VM $VM_NAME"
            return 1
        fi
        echo "⏳ Waiting for VM to be ready..."
        sleep 30
    fi

    echo "✅ VM $VM_NAME is running"

    # Install dependencies on VM (minimal - just ensure Docker is working)
    echo "📦 Checking dependencies on $VM_NAME..."
    dependency_script='
        # Ensure Docker is running
        if command -v docker >/dev/null 2>&1; then
            echo "Docker is installed"
            sudo systemctl start docker 2>/dev/null || echo "Docker already running"
            sudo systemctl enable docker 2>/dev/null || echo "Docker already enabled"
            echo "Docker status: $(sudo systemctl is-active docker)"
        else
            echo "Docker not found, installing..."
            sudo apt update -y
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker $USER
        fi

        echo "Dependencies check completed"
    '

    if ! gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="$dependency_script" < /dev/null; then
        echo "❌ Failed to install dependencies on $VM_NAME"
        return 1
    fi

    echo "✅ Dependencies installed successfully"
    echo "⏳ Waiting for Docker service to be ready..."
    sleep 5

    # Copy required Nexus files to VM
    echo "📂 Copying Nexus files to $VM_NAME..."
    required_files=("../create_containers.sh" "../monitor_script.sh" "../Dockerfile")
    missing_files=()

    # Check if required files exist locally
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "❌ Missing required local files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        echo "Please ensure create_containers.sh, monitor_script.sh, and Dockerfile are in the parent directory"
        return 1
    fi

    echo "✅ Found all required local files"

    # Copy files to VM
    echo "📤 Copying files to $VM_NAME..."
    for file in "${required_files[@]}"; do
        filename=$(basename "$file")
        if gcloud compute scp "$file" "$VM_NAME:" --zone="$VM_ZONE" < /dev/null 2>/dev/null; then
            echo "✅ Copied $filename to $VM_NAME"
        else
            echo "❌ Failed to copy $filename to $VM_NAME"
            return 1
        fi
    done

    # Set permissions on VM
    echo "🔧 Setting permissions on $VM_NAME..."
    if ! gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="
        chmod +x *.sh
        echo 'Permissions set successfully'
        echo 'Files in home directory:'
        ls -la *.sh Dockerfile .env 2>/dev/null || ls -la
    " < /dev/null 2>/dev/null; then
        echo "❌ Failed to set permissions on $VM_NAME"
        return 1
    fi

    echo "✅ Files copied and permissions set successfully"

    # Deploy Nexus to VM
    echo "🚀 Deploying Nexus to $VM_NAME..."
    deployment_script="
        set -e  # Exit on any error

        echo '=== Starting Nexus deployment ==='
        echo 'Working directory:' \$(pwd)
        echo 'Available disk space:'
        df -h . || true

        # We should be in the user's home directory where files were copied
        echo 'Current directory:' \$(pwd)

        # Verify required files exist (they should have been copied by the previous step)
        echo 'Checking for required files...'
        required_files=(\"create_containers.sh\" \"monitor_script.sh\" \"Dockerfile\")
        missing_files=()

        for file in \"\${required_files[@]}\"; do
            if [ ! -f \"\$file\" ]; then
                missing_files+=(\"\$file\")
            fi
        done

        if [ \${#missing_files[@]} -gt 0 ]; then
            echo '❌ Missing required files:'
            for file in \"\${missing_files[@]}\"; do
                echo \"  - \$file\"
            done
            echo 'Available files:'
            ls -la
            exit 1
        fi

        echo 'Found all required files:'
        ls -la create_containers.sh monitor_script.sh Dockerfile

        # Create .env file with specific node IDs in the nexus directory
        echo 'Creating .env file...'
        echo \"NODE_IDS=$NODE_IDS\" > .env

        # Verify .env file
        echo '=== Created .env file ==='
        cat .env
        echo '========================='

        # Verify node count
        node_count=\$(echo '$NODE_IDS' | tr ',' '\n' | wc -l)
        echo \"Will create containers for \$node_count node IDs\"
        echo \"Note: create_containers.sh determines final container count\"

        # Make scripts executable
        chmod +x *.sh || true

        # Show script content for debugging (first 10 lines)
        echo 'create_containers.sh preview:'
        head -10 create_containers.sh || echo 'Cannot preview script'

        # Create and start containers using the create_containers.sh script
        # Note: create_containers.sh handles all container recreation automatically
        echo 'Creating containers using create_containers.sh...'
        echo 'Note: create_containers.sh will handle stopping/removing existing containers'

        if ! ./create_containers.sh; then
            echo 'Failed to create containers with create_containers.sh'
            echo 'Checking script permissions and content...'
            ls -la create_containers.sh
            echo 'Docker status:'
            sudo docker --version
            sudo systemctl status docker --no-pager || true
            echo 'Checking if Docker daemon is accessible:'
            sudo docker ps || echo 'Cannot list containers'
            exit 1
        fi

        # Wait a moment for containers to start
        sleep 5

        # Show container status
        echo '=== Containers created ==='
        sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || echo 'Failed to list containers'

        # Count actual containers created
        actual_containers=\$(sudo docker ps --filter 'name=nexus-' --format '{{.Names}}' | wc -l)
        echo \"Containers created: \$actual_containers\"

        if [ \"\$actual_containers\" -gt 0 ]; then
            echo '✅ Containers created successfully'

            # Show detailed container information
            echo '=== Container Details ==='
            sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

            # Setup monitoring with cron job
            echo '🔍 Setting up monitoring system...'
            if [ -f 'monitor_script.sh' ]; then
                echo 'Found monitor_script.sh, setting up monitoring cron job...'
                chmod +x monitor_script.sh

                # Get the full path to the script (should be in home directory)
                script_path=\$(pwd)/monitor_script.sh

                # Setup cron job to run monitoring every 15 minutes
                # First, remove any existing monitoring cron jobs to avoid duplicates
                crontab -l 2>/dev/null | grep -v \"monitor_script.sh\" | crontab - || true

                # Add new monitoring cron job
                (crontab -l 2>/dev/null; echo \"*/15 * * * * \$script_path\") | crontab -

                echo '✅ Monitoring cron job set up successfully'
                echo 'Monitoring will run every 15 minutes'

                # Show current crontab for verification
                echo '=== Current Crontab ==='
                crontab -l || echo 'No crontab entries'
                echo '======================='

                # Run the monitoring script once to test it
                echo 'Testing monitoring script...'
                if ./monitor_script.sh; then
                    echo '✅ Monitoring script test successful'
                else
                    echo '⚠️ Monitoring script test failed, but continuing deployment'
                fi
            else
                echo '⚠️ monitor_script.sh not found, skipping monitoring setup'
            fi

            exit 0
        else
            echo '❌ No containers created'
            exit 1
        fi
    "

    if gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="$deployment_script" < /dev/null; then
        echo "✅ $VM_NAME deployment complete!"

        # Final verification
        echo "🔍 Final verification..."
        verify_script="sudo docker ps --filter 'name=nexus-' --format '{{.Names}}' | wc -l"
        container_count=$(gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="$verify_script" < /dev/null 2>/dev/null | tr -d '\r\n')

        if [ "$container_count" -gt 0 ]; then
            echo "✅ Verification successful: $container_count containers running"

            # Show final status
            echo "📊 Final container status:"
            gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="sudo docker ps --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" < /dev/null 2>/dev/null

            # Verify monitoring setup
            echo "🔍 Verifying monitoring setup..."
            monitor_check=$(gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="
                if [ -f 'monitor_script.sh' ] && crontab -l 2>/dev/null | grep -q 'monitor_script.sh'; then
                    echo 'CONFIGURED'
                else
                    echo 'NOT_CONFIGURED'
                fi
            " 2>/dev/null | tr -d '\r\n')

            if [ "$monitor_check" = "CONFIGURED" ]; then
                echo "✅ Monitoring is properly configured"
            else
                echo "⚠️ Monitoring setup may have issues"
            fi

            return 0
        else
            echo "❌ Verification failed: No containers running"
            return 1
        fi
    else
        echo "❌ Failed to deploy Nexus on $VM_NAME"

        # Show any containers that might have been created
        echo "📊 Checking for any created containers..."
        gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="sudo docker ps -a --filter 'name=nexus-' --format 'table {{.Names}}\t{{.Status}}'" < /dev/null 2>/dev/null || echo "Failed to check containers"

        return 1
    fi
}

# Call the main function with all arguments
deploy_nexus "$@"

# Capture the exit code and exit with it
exit_code=$?
exit $exit_code
