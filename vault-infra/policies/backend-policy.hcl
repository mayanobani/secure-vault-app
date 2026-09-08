# Least-privilege policy for the backend/vault-agent AppRole.
# Grants read-only access to exactly the secret path it needs.

path "secret/data/app/db" {
  capabilities = ["read"]
}
