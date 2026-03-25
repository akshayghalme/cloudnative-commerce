#!/usr/bin/env bash
# bootstrap.sh — creates the S3 bucket and DynamoDB table needed for
# Terraform remote state BEFORE you can run `terraform init`.
#
# Run once per AWS account. Safe to re-run (idempotent).
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
#
# Prerequisites: AWS CLI configured with sufficient permissions:
#   - s3:CreateBucket, s3:PutBucketVersioning, s3:PutBucketEncryption
#     s3:PutBucketPublicAccessBlock, s3:PutLifecycleConfiguration
#   - dynamodb:CreateTable

set -euo pipefail

ACCOUNT_ID="911788523496"
REGION="ap-south-1"
BUCKET="cloudnative-commerce-tfstate-${ACCOUNT_ID}"
TABLE="cloudnative-commerce-tfstate-lock"

echo "=== Terraform Backend Bootstrap ==="
echo "Account: ${ACCOUNT_ID}"
echo "Region:  ${REGION}"
echo "Bucket:  ${BUCKET}"
echo "Table:   ${TABLE}"
echo ""

# ─── S3 Bucket ───────────────────────────────────────────────────────────────

echo "→ Creating S3 bucket..."
if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "  Bucket already exists, skipping creation"
else
  # ap-south-1 requires LocationConstraint (us-east-1 does not)
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
  echo "  ✓ Bucket created"
fi

echo "→ Enabling versioning (allows state rollback)..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled
echo "  ✓ Versioning enabled"

echo "→ Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'
echo "  ✓ Encryption enabled (AES256)"

echo "→ Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "  ✓ Public access blocked"

echo "→ Adding lifecycle policy (expire old state versions after 90 days)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-versions",
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }]
  }'
echo "  ✓ Lifecycle policy set"

# ─── DynamoDB Table ───────────────────────────────────────────────────────────

echo "→ Creating DynamoDB lock table..."
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" 2>/dev/null; then
  echo "  Table already exists, skipping creation"
else
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "  Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
  echo "  ✓ DynamoDB table created"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== Bootstrap complete! ==="
echo ""
echo "Next steps:"
echo "  cd terraform/environments/dev"
echo "  terraform init"
echo "  terraform plan"
