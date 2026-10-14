#!/usr/bin/env bash
#
# backup-db.sh — dump the Kantyna Postgres database and ship it to S3.
#
# Usage:
#   PGHOST=... PGUSER=... PGPASSWORD=... BACKUP_BUCKET=... ./scripts/backup-db.sh
#
# Environment:
#   PGHOST          Postgres host            (default: localhost)
#   PGPORT          Postgres port            (default: 5432)
#   PGUSER          Postgres user            (default: kantyna)
#   PGPASSWORD      Postgres password        (required)
#   PGDATABASE      Database name            (default: kantyna)
#   BACKUP_BUCKET   Target S3 bucket         (required)
#   BACKUP_PREFIX   Key prefix in the bucket (default: postgres/kantyna)
#   RETENTION_DAYS  Local retention in days  (default: 7)
#   STAGING_DIR     Local staging directory  (default: /var/backups/kantyna)
#
set -euo pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-kantyna}"
PGDATABASE="${PGDATABASE:-kantyna}"
BACKUP_BUCKET="${BACKUP_BUCKET:?BACKUP_BUCKET is required}"
BACKUP_PREFIX="${BACKUP_PREFIX:-postgres/kantyna}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAGING_DIR="${STAGING_DIR:-/var/backups/kantyna}"
AWS_REGION="${AWS_REGION:-eu-central-1}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
DAY="$(date -u +%Y/%m/%d)"
DUMP_FILE="${STAGING_DIR}/${PGDATABASE}-${TS}.sql.gz"
PARTIAL_FILE="${DUMP_FILE}.partial"
LOG_FILE="${STAGING_DIR}/backup.log"

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$STAGING_DIR"

# Never leave a half-written dump behind, whatever fails.
trap 'rm -f "$PARTIAL_FILE"' EXIT

log "starting backup: host=${PGHOST}:${PGPORT} db=${PGDATABASE} user=${PGUSER}"

export PGPASSWORD
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
  --no-owner --no-privileges --format=plain | gzip -9 > "$PARTIAL_FILE"

# Publish the dump only after it is complete and readable.
gzip -t "$PARTIAL_FILE"
mv "$PARTIAL_FILE" "$DUMP_FILE"

SIZE="$(du -h "$DUMP_FILE" | cut -f1)"
log "dump written: ${DUMP_FILE} (${SIZE})"

S3_KEY="${BACKUP_PREFIX}/${DAY}/$(basename "$DUMP_FILE")"
aws s3 cp "$DUMP_FILE" "s3://${BACKUP_BUCKET}/${S3_KEY}" \
  --region "$AWS_REGION" --only-show-errors

# Verify the object in S3 matches the local file before trusting it.
LOCAL_BYTES="$(wc -c < "$DUMP_FILE" | tr -d ' ')"
REMOTE_BYTES="$(aws s3api head-object --bucket "$BACKUP_BUCKET" --key "$S3_KEY" \
  --region "$AWS_REGION" --query ContentLength --output text)"
if [ "$LOCAL_BYTES" != "$REMOTE_BYTES" ]; then
  log "size mismatch: local=${LOCAL_BYTES} s3=${REMOTE_BYTES}"
  exit 1
fi
log "uploaded to s3://${BACKUP_BUCKET}/${S3_KEY}"

# Rotate local copies (reached only after a verified upload)
log "pruning local dumps older than ${RETENTION_DAYS} days"
find "$STAGING_DIR" -maxdepth 1 -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | tee -a "$LOG_FILE"

log "backup finished"
