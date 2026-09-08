#!/bin/bash
set -e

SECRETS_FILE="/vault/secrets/db-creds.env"

echo "[db] waiting for Vault agent to render database credentials..."
until [ -f "$SECRETS_FILE" ]; do
  sleep 2
done

set -a
. "$SECRETS_FILE"
set +a

echo "[db] credentials loaded from Vault, starting postgres..."
exec docker-entrypoint.sh postgres
