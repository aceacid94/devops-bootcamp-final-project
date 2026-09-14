#!/usr/bin/env bash
# Usage: ssm-run.sh <instance-id> <shell-command>
# Runs <shell-command> on <instance-id> via AWS SSM RunShellScript,
# waits for completion, prints stdout, and exits non-zero on failure.
set -euo pipefail

INSTANCE_ID="$1"
COMMAND="$2"

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "{\"commands\":[$(jq -Rs . <<< "$COMMAND")]}" \
  --query "Command.CommandId" \
  --output text)

# Wait for the command to finish (ignore the wait command's own exit code;
# we check status explicitly below so we can surface stderr on failure).
aws ssm wait command-executed \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" || true

STATUS=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "Status" \
  --output text)

STDOUT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" \
  --output text)

STDERR=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query "StandardErrorContent" \
  --output text)

if [ "$STATUS" != "Success" ]; then
  echo "SSM command failed on $INSTANCE_ID (status: $STATUS)" >&2
  echo "$STDERR" >&2
  exit 1
fi

# Print only stdout to stdout so callers can capture it with $(...)
echo "$STDOUT"