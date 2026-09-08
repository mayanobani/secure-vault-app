# Secure Application Deployment with Vault-Managed Secrets & CI/CD Security Pipeline

Stack: Flask backend + Postgres + static frontend, secrets sourced from
HashiCorp Vault via a Vault Agent sidecar, deployed by a self-hosted
GitHub Actions runner, scanned by TruffleHog / Bandit / Hadolint / Trivy.

```
project/
├── backend/                # Flask API + Dockerfile
├── frontend/                # static HTML/JS + nginx Dockerfile
├── vault-infra/              # Vault SERVER (standalone, Requirement 2)
│   ├── docker-compose.yaml
│   ├── config.hcl
│   ├── policies/backend-policy.hcl
│   └── data/                 # Vault storage backend (chmod 777)
├── app-stack/                 # Application stack (Requirement 3)
│   ├── docker-compose.yaml    # db + backend + frontend + vault-agent
│   ├── vault-agent-config.hcl
│   ├── db-entrypoint.sh
│   └── templates/db-creds.ctmpl
└── .github/workflows/
    ├── build-deploy.yml       # Requirement 5
    └── security-scan.yml      # Requirement 6
```

---

## Step 1 — Push this to GitHub

```bash
cd project
git init
git add .
git commit -m "Initial scaffold: app + Dockerfiles + Vault + CI/CD"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

---

## Step 2 — Bring up the Vault server

```bash
cd vault-infra
chmod -R 777 data          # required by the task spec
docker compose up -d
```

Vault starts **sealed** and **uninitialized**. Initialize it once:

```bash
docker exec -it vault vault operator init -key-shares=5 -key-threshold=3 \
  > ../vault-init-output.txt
cat ../vault-init-output.txt
```

This prints 5 unseal keys + a root token. **Save them somewhere safe** —
this file is git-ignored on purpose; never commit real keys.

Unseal with any 3 of the 5 keys:

```bash
docker exec -it vault vault operator unseal <unseal_key_1>
docker exec -it vault vault operator unseal <unseal_key_2>
docker exec -it vault vault operator unseal <unseal_key_3>
```

Log in and enable the KV v2 secrets engine at `secret/`:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<root_token_from_init_output>

vault login $VAULT_TOKEN
vault secrets enable -path=secret kv-v2
```

---

## Step 3 — Store the DB credentials in Vault

```bash
vault kv put secret/app/db \
  username=appuser \
  password="$(openssl rand -base64 18)" \
  dbname=appdb
```

Confirm:

```bash
vault kv get secret/app/db
```

---

## Step 4 — Create an AppRole for the Vault Agent

The Vault Agent authenticates as an AppRole rather than a human token.

```bash
vault auth enable approle

vault policy write backend-policy vault-infra/policies/backend-policy.hcl

vault write auth/approle/role/backend-role \
  token_policies="backend-policy" \
  token_ttl=1h \
  token_max_ttl=4h

# Fetch the role_id (stable) and generate a secret_id (rotatable credential)
vault read -field=role_id auth/approle/role/backend-role/role-id \
  > ../app-stack/role_id

vault write -f -field=secret_id auth/approle/role/backend-role/secret-id \
  > ../app-stack/secret_id
```

These two files (`app-stack/role_id`, `app-stack/secret_id`) are what the
Vault Agent sidecar uses to log in — they are git-ignored, never pushed.

---

## Step 5 — Run the application stack

```bash
cd ../app-stack
mkdir -p secrets token
docker compose up -d --build
```

What happens on startup:
1. `vault-agent` authenticates to Vault via AppRole, renders
   `secrets/db-creds.env` from the `db-creds.ctmpl` template (real
   plaintext values only ever exist inside the running containers,
   never in git or in a `.env` file you wrote by hand).
2. `db` waits for that file, sources it, then starts Postgres.
3. `backend` waits for the same file, sources it, connects to `db`.
4. `frontend` serves the static UI on port 8080 and calls the backend
   on port 5000.

Check it:

```bash
curl http://localhost:5000/health
open http://localhost:8080      # or just visit in a browser
```

---

## Step 6 — Register a self-hosted GitHub Actions runner

On the same machine (repo → **Settings → Actions → Runners → New
self-hosted runner**, pick your OS, then run the commands GitHub shows
you), which looks like:

```bash
mkdir actions-runner && cd actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/<version>/actions-runner-<os>-<arch>-<version>.tar.gz
tar xzf actions-runner.tar.gz

./config.sh --url https://github.com/<your-username>/<your-repo> \
            --token <REGISTRATION_TOKEN_FROM_GITHUB_UI>

./run.sh          # or install as a service: ./svc.sh install && ./svc.sh start
```

Make sure this machine has `docker` and `docker compose` on PATH for the
runner's user, since both workflows shell out to them.

---

## Step 7 — Trigger the workflows

Push to `main` (or use **Actions → Run workflow** for manual dispatch):

- **Build & Deploy** (`build-deploy.yml`) builds both images and runs
  `docker compose up -d --build` against `app-stack/docker-compose.yaml`.
- **Security Scan** (`security-scan.yml`) runs four independent jobs:
  - **TruffleHog** — scans full git history for verified leaked secrets.
  - **Bandit** — SAST over `backend/` Python code.
  - **Hadolint** — lints both Dockerfiles.
  - **Trivy** — builds each image and scans it for known CVEs.

Both workflows are set to `exit-code: '0'` / non-blocking on findings by
default so you can see results first; tighten them (e.g. Trivy
`exit-code: '1'` on CRITICAL) once you're ready to gate merges.

---

## Design notes / what to check when demoing this

- No plaintext DB password ever sits in `docker-compose.yaml`, a
  `.env` file, or the git history — only in Vault and in the
  `app-stack/secrets/db-creds.env` file that Vault Agent renders at
  runtime inside the running containers (git-ignored, tmpfs-worthy).
- `role_id` is safe-ish to leak (needs a valid `secret_id` too); rotate
  `secret_id` regularly in a real deployment (`vault write -f ...
  secret-id` again) rather than reusing the one from Step 4 forever.
- The Vault **policy** (`backend-policy.hcl`) grants read-only access
  to exactly one path — least privilege.
- If you want Vault itself to unseal automatically on restart (no
  manual `vault operator unseal`), look into Vault's auto-unseal via
  a cloud KMS — out of scope for a local demo but worth mentioning if
  asked about production hardening.
