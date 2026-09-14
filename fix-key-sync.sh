#!/usr/bin/env bash
# Fetches the ansible controller's ACTUAL current public key directly via SSM
# (no manual copy-paste) and pushes it to both target servers.
# Waits for the controller's key to actually exist before proceeding, so this
# is safe to run immediately after terraform apply, before user_data finishes.
set -euo pipefail

echo "Looking up instance IDs..."
CONTROLLER_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=ansible_controller" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
WEB_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=web-server" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
MON_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=monitoring_server" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)

echo "Controller: $CONTROLLER_ID"
echo "Web:        $WEB_ID"
echo "Monitoring: $MON_ID"

echo "Waiting for SSM agents to come online..."
for id in "$CONTROLLER_ID" "$WEB_ID" "$MON_ID"; do
  for i in $(seq 1 30); do
    STATUS=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$id" --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null || echo "")
    [ "$STATUS" == "Online" ] && break
    echo "  Waiting for SSM agent on $id (attempt $i)..."
    sleep 10
  done
done

echo "Waiting for the controller to generate its SSH key (user_data may still be running)..."
PUBKEY=""
for i in $(seq 1 40); do
  CMD_ID=$(aws ssm send-command --instance-ids "$CONTROLLER_ID" --document-name "AWS-RunShellScript" --parameters '{"commands":["cat /home/ubuntu/.ssh/id_ed25519.pub 2>/dev/null || echo NOTFOUND"]}' --query "Command.CommandId" --output text)
  sleep 3
  aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$CONTROLLER_ID" || true
  OUTPUT=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CONTROLLER_ID" --query "StandardOutputContent" --output text | tr -d '\r' | head -n1)

  if [ -n "$OUTPUT" ] && [ "$OUTPUT" != "NOTFOUND" ]; then
    PUBKEY="$OUTPUT"
    break
  fi
  echo "  Controller key not ready yet (attempt $i), retrying in 15s..."
  sleep 15
done

if [ -z "$PUBKEY" ]; then
  echo "ERROR: controller never produced a public key after waiting." >&2
  exit 1
fi

echo "Got key: $PUBKEY"
echo "Fingerprint check:"
echo "$PUBKEY" > /tmp/fetched_key.pub
ssh-keygen -lf /tmp/fetched_key.pub

push_key() {
  local target_id="$1"
  local target_name="$2"
  echo "Pushing to $target_name ($target_id)..." >&2
  aws ssm send-command --instance-ids "$target_id" --document-name "AWS-RunShellScript" \
    --parameters "{\"commands\":[\"mkdir -p /home/ubuntu/.ssh\", \"touch /home/ubuntu/.ssh/authorized_keys\", \"sed -i '/ansible-controller/d' /home/ubuntu/.ssh/authorized_keys\", \"echo '$PUBKEY' >> /home/ubuntu/.ssh/authorized_keys\", \"chown -R ubuntu:ubuntu /home/ubuntu/.ssh\", \"chmod 700 /home/ubuntu/.ssh\", \"chmod 600 /home/ubuntu/.ssh/authorized_keys\"]}" \
    --query "Command.CommandId" --output text
}

WEB_CMD=$(push_key "$WEB_ID" "web server")
MON_CMD=$(push_key "$MON_ID" "monitoring server")

sleep 5
aws ssm wait command-executed --command-id "$WEB_CMD" --instance-id "$WEB_ID" || true
aws ssm wait command-executed --command-id "$MON_CMD" --instance-id "$MON_ID" || true

echo "Web server result:"
aws ssm get-command-invocation --command-id "$WEB_CMD" --instance-id "$WEB_ID" --query "Status" --output text

echo "Monitoring server result:"
aws ssm get-command-invocation --command-id "$MON_CMD" --instance-id "$MON_ID" --query "Status" --output text

echo "Done. Key sync complete."