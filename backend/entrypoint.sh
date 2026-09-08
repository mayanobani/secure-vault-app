#!/bin/sh
set -e

SECRETS_FILE="/vault/secrets/db-creds.env"

echo "Waiting for Vault agent to render database credentials..."
until [ -f "$SECRETS_FILE" ]; do
  sleep 2
done

# Load POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB into the environment
set -a
. "$SECRETS_FILE"
set +a

echo "Credentials loaded from Vault. Starting backend..."
exec python app.py
