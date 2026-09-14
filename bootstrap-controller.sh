#!/usr/bin/env bash
# Idempotent bootstrap for the ansible controller instance.
# Installs ansible if missing, generates an SSH key for ubuntu if missing,
# and ensures ssm-user has passwordless sudo.
set -euo pipefail

# Ensure ssm-user has passwordless sudo (fixes a common SSM default-config gap)
if [ ! -f /etc/sudoers.d/ssm-agent-users ] || ! grep -q "NOPASSWD:ALL" /etc/sudoers.d/ssm-agent-users; then
  echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users
  chmod 440 /etc/sudoers.d/ssm-agent-users
fi

# Install ansible if missing
if ! command -v ansible >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y ansible
fi

# Generate an SSH key for ubuntu if missing
if [ ! -f /home/ubuntu/.ssh/id_ed25519 ]; then
  sudo -u ubuntu mkdir -p /home/ubuntu/.ssh
  sudo -u ubuntu chmod 700 /home/ubuntu/.ssh
  sudo -u ubuntu ssh-keygen -t ed25519 -N "" -C "ansible-controller" -f /home/ubuntu/.ssh/id_ed25519
fi

# Always print the public key so the caller can capture it
cat /home/ubuntu/.ssh/id_ed25519.pub