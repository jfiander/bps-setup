#!/bin/bash

# Uploads a rotated log to s3://bps-log-archive/production/YYYY/MM/DD/<log>, called from logrotate.
# Authenticates with the instance role, which must allow s3:PutObject on that prefix and
# cloudwatch:PutMetricData in the BPS/LogUpload namespace.
#
# The AMI can serve any environment, so this decides at run time: only production.log is handled.
#
# An empty log has nothing to upload. Either way, a successful run publishes the BPS/LogUpload heartbeat that the
# "Log Upload - production" alarm watches for. A missing log is an error.
#
# Usage: upload_log_file.sh <log_name> [log_dir]
#   log_dir defaults to /var/www/bpsd9/shared/log

set -euo pipefail

log_name="$1"
log_dir="${2:-/var/www/bpsd9/shared/log}"
path="$log_dir/$log_name"
environment="${log_name%%.*}"
region=us-east-2
bucket=bps-log-archive
key="$environment/$(date "+%Y/%m/%d")/$log_name"

if [[ "$environment" != "production" ]]; then
  echo "[$(date "+%Y/%m/%dT%H:%M:%S")] Skipping, only production logs are uploaded: $path"
  exit 0
fi

if [[ -f "$path" && ! -s "$path" ]]; then
  echo "[$(date "+%Y/%m/%dT%H:%M:%S")] Nothing to upload, log is empty: $path"
else
  echo "[$(date "+%Y/%m/%dT%H:%M:%S")] Uploading logs to S3: $path"
  aws s3api put-object --region "$region" --bucket "$bucket" --key "$key" --body "$path"
fi

aws cloudwatch put-metric-data --region "$region" --namespace BPS/LogUpload --metric-name Heartbeat \
  --dimensions "Application=$environment" --value 1

echo ""
