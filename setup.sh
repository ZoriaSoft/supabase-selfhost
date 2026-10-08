#!/usr/bin/env bash
#
# supabase-selfhost — one-command setup for a self-hosted Supabase stack.
#
# What it does:
#   1. Checks that Docker Engine + the Compose v2 plugin are installed.
#   2. Creates .env from .env.example (skipped if .env already exists).
#   3. Generates strong secrets (openssl only — no external dependencies):
#      JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY (official HS256 method),
#      POSTGRES_PASSWORD, DASHBOARD_PASSWORD, encryption keys, S3 keys.
#   4. Starts the stack with `docker compose up -d`.
#   5. Waits for the API gateway and prints access URLs.
#
# Usage:
#   ./setup.sh              # fresh install
#   ./setup.sh --reset-env  # regenerate .env secrets (keeps DB data volume)
#
set -euo pipefail
cd "$(dirname "$0")"

info()  { printf '\033[0;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[0;33m[!]\033[0m %s\n' "$*"; }
fail()  { printf '\033[0;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. checks

command -v docker >/dev/null 2>&1 || fail "docker not found. Install Docker Engine: https://docs.docker.com/engine/install/"
docker compose version >/dev/null 2>&1 || fail "docker compose (v2 plugin) not found. Install: https://docs.docker.com/compose/install/linux/"
docker info >/dev/null 2>&1 || fail "docker daemon is not reachable (is it running? do you need sudo or the docker group?)"
command -v openssl >/dev/null 2>&1 || fail "openssl is required but not found."
command -v curl >/dev/null 2>&1 || fail "curl is required (gateway readiness probe) but not found."

# ------------------------------------------------------- 2. .env bootstrap

RESET_ENV=0
[ "${1:-}" = "--reset-env" ] && RESET_ENV=1

if [ ! -f .env ]; then
    [ -f .env.example ] || fail ".env.example is missing — incomplete checkout?"
    cp .env.example .env
    chmod 600 .env
    info "Created .env from .env.example"
    GENERATE=1
elif [ "$RESET_ENV" -eq 0 ]; then
    info ".env already exists — keeping it (use --reset-env to regenerate secrets)."
fi
GENERATE=${GENERATE:-0}
chmod 600 .env   # holds JWT secret + DB password; keep owner-only
[ "$RESET_ENV" -eq 1 ] && GENERATE=1

# ---------------------------------------------------- 3. secret generation

if [ "$GENERATE" -eq 1 ]; then
    command -v shasum >/dev/null 2>&1 || true

    gen_hex()    { openssl rand -hex "$1"; }
    gen_base64() { openssl rand -base64 "$1" | tr -d '\n'; }
    b64url()     { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

    JWT_SECRET="$(gen_base64 30)"
    HEADER='{"alg":"HS256","typ":"JWT"}'
    IAT=$(date +%s)
    EXP=$((IAT + 5 * 365 * 24 * 3600))   # 5 years — same convention as upstream generate-keys.sh

    sign_jwt() {
        local payload="$1"
        local unsigned
        unsigned="$(printf %s "$HEADER" | b64url).$(printf %s "$payload" | b64url)"
        local sig
        sig=$(printf %s "$unsigned" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url)
        printf '%s.%s' "$unsigned" "$sig"
    }

    ANON_KEY=$(sign_jwt "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$IAT,\"exp\":$EXP}")
    SERVICE_ROLE_KEY=$(sign_jwt "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$IAT,\"exp\":$EXP}")

    set_env() { # set_env KEY VALUE — replace KEY=... line in .env
        # keys are generated fresh, free of sed metacharacters except +/ (base64) — use | delimiter
        sed -i "s|^$1=.*$|$1=$2|" .env
    }

    set_env JWT_SECRET                     "$JWT_SECRET"
    set_env ANON_KEY                       "$ANON_KEY"
    set_env SERVICE_ROLE_KEY               "$SERVICE_ROLE_KEY"
    if [ "$RESET_ENV" -eq 1 ] && ! grep -q '^POSTGRES_PASSWORD=your-super-secret' .env; then
        # the persistent DB volume at first init, so rotating it here would
        # leave auth/rest/storage/supavisor unable to connect. To rotate:
        #   docker exec supabase-db psql -U postgres -c \
        #     "ALTER USER postgres PASSWORD 'new-password'"
        # then update .env to match.
        warn "POSTGRES_PASSWORD kept (DB volume already initialized with it)."
    else
        set_env POSTGRES_PASSWORD "$(gen_hex 16)"
    fi
    set_env DASHBOARD_PASSWORD             "$(gen_hex 16)"
    set_env SECRET_KEY_BASE                "$(gen_base64 48)"
    set_env REALTIME_DB_ENC_KEY            "$(gen_hex 8)"
    set_env VAULT_ENC_KEY                  "$(gen_hex 16)"
    set_env PG_META_CRYPTO_KEY             "$(gen_base64 24)"
    set_env LOGFLARE_PUBLIC_ACCESS_TOKEN   "$(gen_base64 24)"
    set_env LOGFLARE_PRIVATE_ACCESS_TOKEN  "$(gen_base64 24)"
    set_env S3_PROTOCOL_ACCESS_KEY_ID      "$(gen_hex 16)"
    set_env S3_PROTOCOL_ACCESS_KEY_SECRET  "$(gen_hex 32)"
    set_env MINIO_ROOT_PASSWORD            "$(gen_hex 16)"
    set_env POOLER_TENANT_ID               "selfhost-$(gen_hex 4)"
    set_env STORAGE_TENANT_ID              "selfhost"

    # Sensible defaults for a private, single-user instance:
    set_env ENABLE_EMAIL_AUTOCONFIRM "true"   # no SMTP configured by default
    set_env ENABLE_PHONE_SIGNUP      "false"  # no SMS provider configured
    set_env ENABLE_PHONE_AUTOCONFIRM "false"

    info "Generated fresh secrets in .env (JWT secret, API keys, passwords)."
fi

# ------------------------------------------------------------ 4. bring up

info "Pulling images and starting the stack (first run downloads ~4 GB)..."
docker compose pull --quiet || warn "docker compose pull failed — trying up anyway"
docker compose up -d

# ------------------------------------------------------------- 5. wait/print

. ./.env   # shellcheck disable=SC1091 — .env is KEY=VALUE lines

GW_PORT="${API_GW_HTTP_PORT:-8000}"
ST_PORT="${STUDIO_PORT:-3000}"

info "Waiting for the API gateway on :$GW_PORT ..."
GATEWAY_UP=0
for i in $(seq 1 60); do
    if curl -fsS -o /dev/null -w '%{http_code}' "http://localhost:${GW_PORT}/" 2>/dev/null | grep -qE '^(200|301|302|401|403|404)$'; then
        GATEWAY_UP=1
        break
    fi
    sleep 5
done
if [ "$GATEWAY_UP" -eq 0 ]; then
    warn "Gateway did not answer in 5 minutes — the stack may be starting slowly. Check: docker compose ps / docker compose logs"
    echo
    docker compose ps
    exit 1
fi

cat <<EOF

==================================================================
  Supabase self-hosted stack is up.

  Studio dashboard : http://localhost:${GW_PORT}  (via gateway,
                     basic auth: \$DASHBOARD_USERNAME / \$DASHBOARD_PASSWORD)
                     http://localhost:${ST_PORT}  (direct, NO auth — loopback only;
                     from your machine: ssh -L ${ST_PORT}:localhost:${ST_PORT} <host>)
  API gateway      : http://localhost:${GW_PORT}
    REST       http://localhost:${GW_PORT}/rest/v1/
    Auth       http://localhost:${GW_PORT}/auth/v1/
    Realtime   ws://localhost:${GW_PORT}/realtime/v1/
    Storage    http://localhost:${GW_PORT}/storage/v1/
    Functions  http://localhost:${GW_PORT}/functions/v1/
  Postgres         postgresql://postgres:<POSTGRES_PASSWORD>@localhost:${POSTGRES_PORT:-5432}/postgres
  Pooler (txn)     localhost:${POOLER_PROXY_PORT_TRANSACTION:-6543}

  Credentials and keys are in .env (gitignored — never commit it).
  Read SECURITY.md before exposing any of this to a network.
==================================================================
EOF
