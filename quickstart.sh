#!/usr/bin/env bash
# Smoke-test the aws-core sandbox from inside the Codespace.
set -e
EP="${CLOUDLEARN_PUBLIC_URL:-http://localhost:9000}"
echo "Endpoint: $EP"
curl -fsS "$EP/healthz" && echo " ✓ healthy"
aws --endpoint-url "$EP" s3 mb s3://demo 2>/dev/null || true
aws --endpoint-url "$EP" s3 ls && echo "✓ S3 works"
aws --endpoint-url "$EP" dynamodb create-table --table-name t \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH --billing-mode PAY_PER_REQUEST 2>/dev/null || true
aws --endpoint-url "$EP" dynamodb list-tables && echo "✓ DynamoDB works"
