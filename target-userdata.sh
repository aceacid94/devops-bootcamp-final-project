#!/usr/bin/env bash
# user_data for target instances (web server, monitoring server).
# Waits for the controller to publish its public key to Parameter Store,
# then appends it to ubuntu's authorized_keys automatically.
set -uo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Target bootstrap starting: $(date) ==="

REGION="ap-southeast-1"
PARAM_NAME="/devops-bootcamp/ansible-controller/ssh-public-key"

# Install AWS CLI v2 if not already present
if ! command -v aws >/dev/null 2>&1; then
  for i in $(seq 1 6); do
    apt-get update -y && \
    apt-get install -y unzip curl && \
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && break
    echo "AWS CLI install failed (attempt $i), retrying in 15s..."
    sleep 15
  done
fi

# Install Docker and run nginx (idempotent: skip if docker already installed)
if ! command -v docker >/dev/null 2>&1; then
  for i in $(seq 1 6); do
    curl -fsSL https://get.docker.com | sh && break
    echo "Docker install failed (attempt $i), retrying in 15s..."
    sleep 15
  done
fi

id ssm-user &>/dev/null || useradd -m ssm-user
usermod -aG docker ssm-user
usermod -aG docker ubuntu

# Only start the nginx container if one isn't already running
if ! docker ps --format '{{.Names}}' | grep -q '^nginx$' 2>/dev/null; then
  docker run -d --name nginx -p 80:80 --restart unless-stopped nginx
fi

sudo -u ubuntu mkdir -p /home/ubuntu/.ssh
sudo -u ubuntu chmod 700 /home/ubuntu/.ssh
touch /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys

# Poll Parameter Store until the controller has published its key
# (handles the case where this instance boots before the controller does)
PUBKEY=""
for i in $(seq 1 60); do
  PUBKEY=$(aws ssm get-parameter --region "$REGION" --name "$PARAM_NAME" --query "Parameter.Value" --output text 2>/dev/null || true)
  if [ -n "$PUBKEY" ] && [ "$PUBKEY" != "None" ]; then
    break
  fi
  echo "Waiting for controller public key in Parameter Store (attempt $i)..."
  sleep 10
done

if [ -z "$PUBKEY" ] || [ "$PUBKEY" == "None" ]; then
  echo "ERROR: controller public key never appeared in Parameter Store after 10 minutes." >&2
  exit 1
fi

# Add it if not already present (idempotent across reboots/re-runs)
if ! grep -qxF "$PUBKEY" /home/ubuntu/.ssh/authorized_keys 2>/dev/null; then
  echo "$PUBKEY" >> /home/ubuntu/.ssh/authorized_keys
  echo "Authorized controller's SSH key."
else
  echo "Controller's SSH key already authorized."
fi

echo "=== Target bootstrap complete: $(date) ==="