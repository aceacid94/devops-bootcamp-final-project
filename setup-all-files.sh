#!/usr/bin/env bash
# Run this from your project root. Creates all automation files at once.
set -euo pipefail

mkdir -p scripts

cat > controller-userdata.sh << 'FILEEOF'
#!/usr/bin/env bash
# user_data for the ansible controller instance.
# Installs ansible, generates an SSH key for ubuntu, fixes ssm-user sudo,
# writes the ansible inventory, and publishes the public key to SSM
# Parameter Store so the target instances can pick it up automatically.
set -euo pipefail

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

# Fix ssm-user's sudo (idempotent)
if [ ! -f /etc/sudoers.d/ssm-agent-users ] || ! grep -q "NOPASSWD:ALL" /etc/sudoers.d/ssm-agent-users; then
  echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users
  chmod 440 /etc/sudoers.d/ssm-agent-users
fi

# Install ansible + awscli (awscli usually preinstalled on Ubuntu AMIs, but just in case)
apt-get update -y
apt-get install -y ansible awscli

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

echo "=== Controller bootstrap complete: $(date) ==="
FILEEOF

cat > target-userdata.sh << 'FILEEOF'
#!/usr/bin/env bash
# user_data for target instances (web server, monitoring server).
# Waits for the controller to publish its public key to Parameter Store,
# then appends it to ubuntu's authorized_keys automatically.
set -euo pipefail

exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Target bootstrap starting: $(date) ==="

REGION="ap-southeast-1"
PARAM_NAME="/devops-bootcamp/ansible-controller/ssh-public-key"

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
FILEEOF

cat > outputs.tf << 'FILEEOF'
output "controller_instance_id" {
  description = "Instance ID of the Ansible controller"
  value       = module.ansible_controller.id
}

output "web_server_instance_id" {
  description = "Instance ID of the web server"
  value       = module.web_server.id
}

output "monitoring_server_instance_id" {
  description = "Instance ID of the monitoring server"
  value       = module.monitoring_server.id
}
FILEEOF

cat > iam-ssm-parameter-policy.tf << 'FILEEOF'
# Attach Parameter Store permissions to your existing EC2-SSM-Role,
# since AmazonSSMManagedInstanceCore alone does not include ssm:PutParameter
# or ssm:GetParameter for custom parameters.

data "aws_iam_role" "ec2_ssm_role" {
  name = "EC-SSM-Role" # must match the exact IAM role name shown in your EC2 console
}

resource "aws_iam_role_policy" "ssm_parameter_access" {
  name = "ssm-parameter-handoff"
  role = data.aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:*:*:parameter/devops-bootcamp/*"
      }
    ]
  })
}
FILEEOF

cat > scripts/update-ssh-config.sh << 'FILEEOF'
#!/usr/bin/env bash
# Run this after `terraform apply` to automatically update ~/.ssh/config
# with the controller's current instance ID.
set -euo pipefail

CONTROLLER_ID=$(terraform output -raw controller_instance_id)
CONFIG_FILE="$HOME/.ssh/config"

if [ -z "$CONTROLLER_ID" ]; then
  echo "Could not read controller_instance_id from terraform output." >&2
  exit 1
fi

echo "New controller instance ID: $CONTROLLER_ID"

if grep -q "^Host controller$" "$CONFIG_FILE"; then
  # Replace the HostName line inside the existing "Host controller" block
  awk -v id="$CONTROLLER_ID" '
    /^Host controller$/ { in_block=1 }
    in_block && /^Host / && !/^Host controller$/ { in_block=0 }
    in_block && /HostName/ { sub(/HostName .*/, "HostName " id) }
    { print }
  ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  echo "Updated existing 'Host controller' block in $CONFIG_FILE"
else
  # Append a fresh block if one doesn't exist yet
  cat >> "$CONFIG_FILE" << EOF

Host controller
  HostName $CONTROLLER_ID
  User ubuntu
  IdentityFile ~/.ssh/id_ed25519_laptop
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
EOF
  echo "Added new 'Host controller' block to $CONFIG_FILE"
fi

echo "Done. Try: ssh controller"
FILEEOF


chmod +x controller-userdata.sh target-userdata.sh scripts/update-ssh-config.sh

echo ""
echo "All files created:"
echo "  controller-userdata.sh"
echo "  target-userdata.sh"
echo "  outputs.tf"
echo "  iam-ssm-parameter-policy.tf"
echo "  scripts/update-ssh-config.sh"