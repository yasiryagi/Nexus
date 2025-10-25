#!/bin/bash

echo "🖥️ Running: create_vms_from_config.sh"
echo "=== Creating VMs Across Multiple Regions ==="

# Define regions and zones (3 VMs per region to stay within 24 vCPU limit)
zones=("us-central1-a" "us-east1-a" "us-west1-a" "europe-west1-a" "asia-southeast1-a")
vms_per_zone=3  # 3 VMs per zone = 24 vCPUs per region

# Count non-empty lines in node_assignments.txt
vm_count=$(grep -v '^#' node_assignments.txt | grep -v '^$' | wc -l)

echo "Found $vm_count lines of node IDs"
echo "Will create $vm_count VMs across multiple regions"
estimated_cost=$((vm_count * 14))
echo "Estimated monthly cost: ~\$$estimated_cost for spot instances"
echo "Distribution: 3 VMs per region to stay within quota limits"
echo

# Show planned distribution
echo "📍 Planned VM Distribution:"
for i in $(seq 1 $vm_count); do
  zone_index=$(( (i - 1) / vms_per_zone ))
  zone=${zones[$zone_index]}
  if [ -z "$zone" ]; then
    zone="us-central1-a"  # fallback
  fi
  echo "  nexus-farm-$i → $zone"
done
echo

# Check for existing VMs
existing_vms=$(gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)" 2>/dev/null)

if [ ! -z "$existing_vms" ]; then
    echo "🗑️ Found existing nexus-farm VMs:"
    echo "$existing_vms"
    echo
    read -p "Delete all existing nexus-farm VMs and recreate? (y/N): " confirm_delete
    
    if [[ $confirm_delete == [yY] ]]; then
        echo "Deleting existing VMs..."
        # Extract VM names and zones, then delete them
        while read -r vm_info; do
            if [ ! -z "$vm_info" ]; then
                vm_name=$(echo "$vm_info" | awk '{print $1}')
                vm_zone=$(echo "$vm_info" | awk '{print $2}')
                vm_zone_short=$(basename "$vm_zone")
                echo "Deleting $vm_name in $vm_zone_short..."
                gcloud compute instances delete "$vm_name" --zone="$vm_zone_short" --quiet
            fi
        done <<< "$existing_vms"
        echo "✅ All existing VMs deleted"
        echo
    else
        echo "Cancelled - keeping existing VMs"
        exit 0
    fi
fi

read -p "Continue with creating $vm_count new VMs? (y/N): " confirm
if [[ $confirm != [yY] ]]; then
    echo "Cancelled"
    exit 0
fi

echo "🚀 Starting VM creation across multiple regions..."
echo

# Create VMs distributed across zones
failed_vms=0
created_vms=0

for i in $(seq 1 $vm_count); do
  # Select zone based on VM number
  zone_index=$(( (i - 1) / vms_per_zone ))
  target_zone=${zones[$zone_index]}
  
  if [ -z "$target_zone" ]; then
    target_zone="us-central1-a"  # fallback
  fi
  
  echo "Creating nexus-farm-$i in zone $target_zone..."
  
  if gcloud compute instances create nexus-farm-$i \
    --zone="$target_zone" \
    --machine-type=e2-standard-8 \
    --provisioning-model=SPOT \
    --instance-termination-action=STOP \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-standard \
    --maintenance-policy=TERMINATE 2>/dev/null; then
    
    echo "✅ nexus-farm-$i created successfully in $target_zone"
    ((created_vms++))
  else
    echo "❌ Failed to create nexus-farm-$i in $target_zone"
    echo "   Trying other available zones..."
    ((failed_vms++))
    
    # Try other zones if current one fails
    for fallback_zone in "${zones[@]}"; do
      if [ "$fallback_zone" != "$target_zone" ]; then
        echo "   Attempting nexus-farm-$i in $fallback_zone..."
        if gcloud compute instances create nexus-farm-$i \
          --zone="$fallback_zone" \
          --machine-type=e2-standard-8 \
          --provisioning-model=SPOT \
          --instance-termination-action=STOP \
          --image-family=ubuntu-2204-lts \
          --image-project=ubuntu-os-cloud \
          --boot-disk-size=20GB \
          --boot-disk-type=pd-standard \
          --maintenance-policy=TERMINATE 2>/dev/null; then
          
          echo "✅ nexus-farm-$i created successfully in $fallback_zone (fallback)"
          ((created_vms++))
          ((failed_vms--))
          break
        fi
      fi
    done
  fi
  
  # Small delay between VM creations
  sleep 2
done

echo
echo "=== Creation Summary ==="
echo "✅ Successfully created: $created_vms VMs"
if [ $failed_vms -gt 0 ]; then
    echo "❌ Failed to create: $failed_vms VMs"
fi
echo "Total VMs requested: $vm_count"

echo
echo "📍 Actual VM Distribution:"
gcloud compute instances list --filter="name:nexus-farm-*" --format="table(name,zone,status,machineType.scope(machineTypes))" 2>/dev/null

if [ $created_vms -gt 0 ]; then
    echo
    echo "🎉 VM creation completed!"
    echo "Region distribution achieved to avoid quota limits."
    echo "Next step: Run ./deploy_all_farms.sh to deploy Nexus to all VMs"
else
    echo
    echo "⚠️ No VMs were created successfully."
    echo "This might be due to quota limits across all regions."
    echo "Consider:"
    echo "1. Using smaller machine types (e2-standard-4)"
    echo "2. Requesting quota increases"
    echo "3. Trying different regions"
fi
