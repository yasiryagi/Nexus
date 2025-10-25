^/#!/bin/bash

echo "✅ Running: verify_setup.sh"
echo "=== Google Cloud Nexus Farm Setup Verification ==="
echo ""

# Check if we're in the right directory
if [ ! -f "node_assignments.txt" ]; then
  echo "❌ Not in the correct directory. Run this from the google/ directory."
  exit 1
fi

echo "✅ Directory check passed"

# Check gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
  echo "❌ gcloud CLI not installed"
  exit 1
fi

echo "✅ gcloud CLI found"

# Check authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "❌ Not authenticated with gcloud. Run: gcloud init"
  exit 1
fi

echo "✅ gcloud authentication verified"

# Check project is set
project=$(gcloud config get-value project 2>/dev/null)
if [ -z "$project" ]; then
  echo "❌ No project set. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

echo "✅ Project set: $project"

# Check Compute Engine API
if ! gcloud services list --enabled --filter="name:compute.googleapis.com" | grep -q compute; then
  echo "❌ Compute Engine API not enabled. Run: gcloud services enable compute.googleapis.com"
  exit 1
fi

echo "✅ Compute Engine API enabled"

# Check node assignments
node_count=$(grep -v '^#' node_assignments.txt | grep -v '^$' | wc -l)
if [ $node_count -eq 0 ]; then
  echo "❌ No node IDs found in node_assignments.txt"
  exit 1
fi

echo "✅ Found $node_count lines of node IDs"

# Check all scripts are executable
scripts=("create_vms_from_config.sh" "deploy_nexus_with_env.sh" "deploy_all_farms.sh" "check_all_farms.sh" "manage_farm.sh" "restart_interrupted.sh")
for script in "${scripts[@]}"; do
  if [ ! -x "$script" ]; then
    echo "❌ $script is not executable. Run: chmod +x $script"
    exit 1
  fi
done

echo "✅ All scripts are executable"

# Check quota in multiple regions
echo ""
echo "🌍 Checking quotas in multiple regions..."
regions=("us-central1" "us-east1" "us-west1" "europe-west1")
for region in "${regions[@]}"; do
  quota_info=$(gcloud compute regions describe "$region" --format="value(quotas[metric=CPUS].limit,quotas[metric=CPUS].usage)" 2>/dev/null)
  if [ ! -z "$quota_info" ]; then
    limit=$(echo "$quota_info" | cut -d\t' -f1)
    usage=$(echo "$quota_info" | cut -d\t' -f2)
    available=$((limit - usage))
    echo "  $region: $usage/$limit CPUs used (${available} available)"
  fi
done

# Check for existing VMs
existing_vms=$(gcloud compute instances list --filter="name:nexus-farm-*" --format="value(name,zone)" 2>/dev/null)
if [ ! -z "$existing_vms" ]; then
    echo ""
    echo "🖥️ Found existing nexus-farm VMs:"
    echo "$existing_vms" | while read vm_name vm_zone; do
        zone_short=$(basename "$vm_zone")
        echo "  $vm_name → $zone_short"
    done
    existing_count=$(echo "$existing_vms" | wc -l)
    echo "  Total: $existing_count VMs"
else
    echo ""
    echo "🖥️ No existing nexus-farm VMs found"
fi

echo ""
echo "🎉 Setup verification passed! You're ready to deploy."
echo ""
echo "📋 Recommended next steps:"
echo "1. Edit node_assignments.txt with your actual node IDs"
echo "2. Run: ./create_vms_from_config.sh \(creates VMs across multiple regions\)"
echo "3. Run: ./deploy_all_farms.sh \(deploys Nexus to all VMs\)"
echo "4. Run: ./check_all_farms.sh \(monitors status across all zoneso\)"

echo ""
echo "💡 Multi-zone deployment info:"
echo "• VMs will be distributed across regions to avoid quota limits"
echo "• Script automatically handles different zones for each VM"
echo "• All management scripts work across multiple zones"
