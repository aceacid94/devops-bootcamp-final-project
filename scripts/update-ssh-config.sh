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
