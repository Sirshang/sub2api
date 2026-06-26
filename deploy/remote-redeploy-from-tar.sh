#!/bin/bash
# =============================================================================
# Sub2API Remote Redeploy From Tarball
# =============================================================================
# Redeploy a local worktree tarball on a remote server while preserving:
#   - deploy/.env
#   - deploy/data
#   - deploy/postgres_data
#   - deploy/redis_data
#
# Defaults are tuned for public-server deployment where 8080 may be blocked.
# Override with environment variables if needed.
# =============================================================================

set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/sub2api}"
TARBALL_PATH="${TARBALL_PATH:-/root/sub2api-worktree.tar.gz}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.dev.yml}"
BIND_HOST="${BIND_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-18080}"
SECRETS_FILE="${SECRETS_FILE:-/root/sub2api-deploy-secrets.txt}"

print_info() {
    printf '[INFO] %s\n' "$1"
}

print_warn() {
    printf '[WARN] %s\n' "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf '[ERROR] missing command: %s\n' "$1" >&2
        exit 1
    fi
}

ensure_line() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

generate_secret() {
    openssl rand -hex "$1"
}

require_command docker-compose
require_command openssl
require_command tar

if [ ! -f "$TARBALL_PATH" ]; then
    printf '[ERROR] tarball not found: %s\n' "$TARBALL_PATH" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
BACKUP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK_DIR" "$BACKUP_DIR"
}
trap cleanup EXIT

print_info "Preparing backup of persistent deployment files"
if [ -d "$APP_ROOT/deploy" ]; then
    for name in .env data postgres_data redis_data; do
        if [ -e "$APP_ROOT/deploy/$name" ]; then
            mkdir -p "$BACKUP_DIR/deploy"
            cp -a "$APP_ROOT/deploy/$name" "$BACKUP_DIR/deploy/"
        fi
    done

    print_info "Stopping current containers"
    (
        cd "$APP_ROOT/deploy"
        docker-compose -f "$COMPOSE_FILE" down || true
    )
fi

print_info "Extracting new release"
mkdir -p "$WORK_DIR/app"
tar xzf "$TARBALL_PATH" -C "$WORK_DIR/app"

rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT"
cp -a "$WORK_DIR/app/." "$APP_ROOT/"

mkdir -p "$APP_ROOT/deploy"
if [ -d "$BACKUP_DIR/deploy" ]; then
    cp -a "$BACKUP_DIR/deploy/." "$APP_ROOT/deploy/"
fi

cd "$APP_ROOT/deploy"

if [ ! -f .env ]; then
    print_warn "No existing .env found, creating a new one"
    cp .env.example .env
    ensure_line "POSTGRES_PASSWORD" "$(generate_secret 24)" .env
    ensure_line "JWT_SECRET" "$(generate_secret 32)" .env
    ensure_line "TOTP_ENCRYPTION_KEY" "$(generate_secret 32)" .env
fi

ensure_line "BIND_HOST" "$BIND_HOST" .env
ensure_line "SERVER_PORT" "$SERVER_PORT" .env

mkdir -p data postgres_data redis_data

grep -E '^(BIND_HOST|SERVER_PORT|POSTGRES_PASSWORD|JWT_SECRET|TOTP_ENCRYPTION_KEY|ADMIN_EMAIL)=' .env > "$SECRETS_FILE" || true

print_info "Starting containers with ${COMPOSE_FILE}"
docker-compose -f "$COMPOSE_FILE" up -d --build

print_info "Container status"
docker-compose -f "$COMPOSE_FILE" ps
