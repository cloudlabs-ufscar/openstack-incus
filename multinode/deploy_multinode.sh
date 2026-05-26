#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "================================================="
echo " Starting OpenStack Multinode Deployment (Incus) "
echo "================================================="

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "Warning: terraform.tfvars not found."
    echo "Copying terraform.tfvars.example to terraform.tfvars..."
    cp terraform.tfvars.example terraform.tfvars
    echo "--------------------------------------------------------"
    echo "PLEASE EDIT 'multinode/terraform.tfvars' BEFORE CONTINUING!"
    echo "Ensure variables like cluster_name, target_node, and vip_address are correct."
    echo "--------------------------------------------------------"
    exit 1
fi

echo "[1/4] Initializing Terraform..."
terraform init

echo "[2/4] Applying Terraform configuration..."
terraform apply -auto-approve

# Retrieve the actual controller name from our terraform output
CONTROLLER_NAME=$(terraform output -raw controller_instance_name)

if [ -z "$CONTROLLER_NAME" ]; then
    echo "Failed to retrieve the controller instance name from Terraform state."
    exit 1
fi

echo "[3/4] Waiting for cloud-init to finish on all nodes..."

# Retrieve the compute names as well
# Output looks like: ["compute1", "compute2"]
# We use jq (or simple sed) to extract raw names
COMPUTE_NAMES=$(terraform output -json compute_instance_names | grep -o '\"[^\"]*\"' | tr -d '"')

MAX_RETRIES=90

for NODE in $CONTROLLER_NAME $COMPUTE_NAMES; do
    echo "Checking cloud-init status on $NODE..."
    RETRY=0
    while [ $RETRY -lt $MAX_RETRIES ]; do
        # We need to make sure the instance is running before exec-ing
        STATUS=$(incus exec "$NODE" -- cloud-init status 2>/dev/null || echo "waiting")
        if [[ "$STATUS" == *"status: done"* ]]; then
            echo " -> Cloud-init finished successfully on $NODE!"
            break
        elif [[ "$STATUS" == *"status: error"* ]]; then
            echo " -> Cloud-init encountered an error on $NODE. Please check the logs."
            exit 1
        fi
        echo " -> Waiting for cloud-init on $NODE... ($RETRY/$MAX_RETRIES)"
        sleep 10
        ((RETRY++))
    done

    if [ $RETRY -eq $MAX_RETRIES ]; then
        echo "Timeout waiting for cloud-init on $NODE."
        exit 1
    fi
done

echo "[4/4] Starting Kolla-Ansible automated deployment via controller..."
echo "Executing /root/run_deploy.sh inside the controller. This may take a while..."
echo "--------------------------------------------------------------------------------"

# Run the deployment script interactively to show output
incus exec "$CONTROLLER_NAME" -- bash -c "/root/run_deploy.sh"

echo "================================================="
echo " Deployment execution finished! "
echo "================================================="
echo "To access your controller node:"
echo "  incus shell $CONTROLLER_NAME"
echo ""
echo "OpenStack Admin credentials:"
echo "  Source the file /etc/kolla/admin-openrc.sh inside the controller."
echo "  E.g.: incus exec $CONTROLLER_NAME -- cat /etc/kolla/admin-openrc.sh"
echo "================================================="
