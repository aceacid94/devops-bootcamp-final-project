#!/usr/bin/env bash
# user_data for the ansible controller instance.
# Installs ansible, generates an SSH key for ubuntu, fixes ssm-user sudo,
# writes the ansible inventory, and publishes the public key to SSM
# Parameter Store so the target instances can pick it up automatically.
set -uo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Controller bootstrap starting: $(date) ==="

# Wait for cloud-init's own apt lock to clear before we touch apt ourselves
for i in $(seq 1 30); do
  if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for apt lock..."
  sleep 5
done

REGION="ap-southeast-1"
PARAM_NAME="/devops-bootcamp/ansible-controller/ssh-public-key"

# Authorize the laptop's SSH key so `ssh controller` works immediately after boot
LAPTOP_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB9jsh4uxaqyOkB+bSd1t36bdrKBMIszdEIUpD4Y4/oG laptop-to-controller"
mkdir -p /home/ubuntu/.ssh
touch /home/ubuntu/.ssh/authorized_keys
if ! grep -qxF "$LAPTOP_PUBKEY" /home/ubuntu/.ssh/authorized_keys 2>/dev/null; then
  echo "$LAPTOP_PUBKEY" >> /home/ubuntu/.ssh/authorized_keys
fi
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys

# Fix ssm-user's sudo (idempotent)
if [ ! -f /etc/sudoers.d/ssm-agent-users ] || ! grep -q "NOPASSWD:ALL" /etc/sudoers.d/ssm-agent-users; then
  echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users
  chmod 440 /etc/sudoers.d/ssm-agent-users
fi

# Install ansible (retry a few times in case the network/NAT route
# isn't fully up yet right at boot)
for i in $(seq 1 6); do
  apt-get update -y && apt-get install -y ansible && break
  echo "apt-get failed (attempt $i), retrying in 15s..."
  sleep 15
done

if ! command -v ansible >/dev/null 2>&1; then
  echo "ERROR: ansible failed to install after retries." >&2
fi

# Install AWS CLI v2 if not already present (avoid depending on the awscli
# apt package, since it isn't available on all Ubuntu AMI variants)
if ! command -v aws >/dev/null 2>&1; then
  for i in $(seq 1 6); do
    apt-get install -y unzip curl && \
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && break
    echo "AWS CLI install failed (attempt $i), retrying in 15s..."
    sleep 15
  done
fi

# Generate ubuntu's SSH key if it doesn't already exist
if [ ! -f /home/ubuntu/.ssh/id_ed25519 ]; then
  sudo -u ubuntu mkdir -p /home/ubuntu/.ssh
  sudo -u ubuntu chmod 700 /home/ubuntu/.ssh
  sudo -u ubuntu ssh-keygen -t ed25519 -N "" -C "ansible-controller" -f /home/ubuntu/.ssh/id_ed25519
fi

PUBKEY=$(cat /home/ubuntu/.ssh/id_ed25519.pub)

# Publish the public key to Parameter Store so web/monitoring instances can fetch it
aws ssm put-parameter \
  --region "$REGION" \
  --name "$PARAM_NAME" \
  --value "$PUBKEY" \
  --type "String" \
  --overwrite

echo "Published controller public key to $PARAM_NAME"

# Write the Ansible inventory (static private IPs, matching your network.tf layout)
cat > /home/ubuntu/inventory.ini << 'EOF'
[web]
web_server ansible_host=10.0.0.5

[monitoring]
monitoring_server ansible_host=10.0.0.136

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=/home/ubuntu/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

chown ubuntu:ubuntu /home/ubuntu/inventory.ini

# Write ansible.cfg so `ansible all -m ping` works without -i
cat > /home/ubuntu/ansible.cfg << 'EOF'
[defaults]
inventory = /home/ubuntu/inventory.ini
host_key_checking = False
EOF

chown ubuntu:ubuntu /home/ubuntu/ansible.cfg

echo "=== Controller bootstrap complete: $(date) ==="