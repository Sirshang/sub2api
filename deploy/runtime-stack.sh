#!/usr/bin/env bash

set -euo pipefail

RUNTIME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-status}"
DEPLOY_NETWORK_NAME="${DEPLOY_NETWORK_NAME:-sub2api-deploy_sub2api-network}"

log() {
  printf '[runtime-stack] %s\n' "$*"
}

die() {
  printf '[runtime-stack] ERROR: %s\n' "$*" >&2
  exit 1
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -Fxq "$1"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -Fxq "$1"
}

container_health() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || true
}

wait_for_container_health() {
  local name="$1"
  local status=""
  for _ in $(seq 1 45); do
    status="$(container_health "${name}")"
    case "${status}" in
      healthy|running)
        return 0
        ;;
      unhealthy|exited|dead)
        docker logs --tail 80 "${name}" >&2 || true
        return 1
        ;;
    esac
    sleep 2
  done
  docker logs --tail 80 "${name}" >&2 || true
  die "container ${name} did not become healthy/running (last status=${status})"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 45); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  curl -fsS "${url}"
}

load_base_env() {
  [[ -f "${RUNTIME_DIR}/.env" ]] || die "missing ${RUNTIME_DIR}/.env"
  set -a
  # shellcheck disable=SC1091
  source "${RUNTIME_DIR}/.env"
  set +a

  PROD_BIND_HOST="${BIND_HOST:-0.0.0.0}"
  PROD_HOST_PORT="${SERVER_PORT:-8080}"
}

load_test_env() {
  TEST_BIND_HOST="${TEST_BIND_HOST:-127.0.0.1}"
  TEST_HOST_PORT="${TEST_SERVER_PORT:-18080}"
  TEST_IMAGE_TAG="${TEST_IMAGE_TAG:-sub2api:monitor-group-filter-test}"
  TEST_DATA_DIR="${TEST_DATA_DIR:-data-test}"

  if [[ -f "${RUNTIME_DIR}/.env.test" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${RUNTIME_DIR}/.env.test"
    set +a
    TEST_BIND_HOST="${TEST_BIND_HOST:-127.0.0.1}"
    TEST_HOST_PORT="${TEST_SERVER_PORT:-18080}"
    TEST_IMAGE_TAG="${TEST_IMAGE_TAG:-sub2api:monitor-group-filter-test}"
    TEST_DATA_DIR="${TEST_DATA_DIR:-data-test}"
  fi
}

prepare_app_env() {
  export AUTO_SETUP=true
  export SERVER_HOST=0.0.0.0
  export SERVER_PORT=8080
  export SERVER_MODE="${SERVER_MODE:-release}"
  export RUN_MODE="${RUN_MODE:-standard}"

  export DATABASE_HOST=postgres
  export DATABASE_PORT="${DATABASE_PORT:-5432}"
  export DATABASE_USER="${POSTGRES_USER:-sub2api}"
  export DATABASE_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
  export DATABASE_DBNAME="${POSTGRES_DB:-sub2api}"
  export DATABASE_SSLMODE="${DATABASE_SSLMODE:-disable}"
  export DATABASE_MAX_OPEN_CONNS="${DATABASE_MAX_OPEN_CONNS:-50}"
  export DATABASE_MAX_IDLE_CONNS="${DATABASE_MAX_IDLE_CONNS:-10}"
  export DATABASE_CONN_MAX_LIFETIME_MINUTES="${DATABASE_CONN_MAX_LIFETIME_MINUTES:-30}"
  export DATABASE_CONN_MAX_IDLE_TIME_MINUTES="${DATABASE_CONN_MAX_IDLE_TIME_MINUTES:-5}"

  export REDIS_HOST=redis
  export REDIS_PORT="${REDIS_PORT:-6379}"
  export REDIS_PASSWORD="${REDIS_PASSWORD:-}"
  export REDIS_DB="${REDIS_DB:-0}"
  export REDIS_POOL_SIZE="${REDIS_POOL_SIZE:-1024}"
  export REDIS_MIN_IDLE_CONNS="${REDIS_MIN_IDLE_CONNS:-10}"
  export REDIS_ENABLE_TLS="${REDIS_ENABLE_TLS:-false}"

  export ADMIN_EMAIL="${ADMIN_EMAIL:-admin@sub2api.local}"
  export ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
  export JWT_SECRET="${JWT_SECRET:-}"
  export JWT_EXPIRE_HOUR="${JWT_EXPIRE_HOUR:-24}"
  export TOTP_ENCRYPTION_KEY="${TOTP_ENCRYPTION_KEY:-}"
  export TZ="${TZ:-Asia/Shanghai}"

  export GEMINI_OAUTH_CLIENT_ID="${GEMINI_OAUTH_CLIENT_ID:-}"
  export GEMINI_OAUTH_CLIENT_SECRET="${GEMINI_OAUTH_CLIENT_SECRET:-}"
  export GEMINI_OAUTH_SCOPES="${GEMINI_OAUTH_SCOPES:-}"
  export GEMINI_QUOTA_POLICY="${GEMINI_QUOTA_POLICY:-}"
  export GEMINI_CLI_OAUTH_CLIENT_SECRET="${GEMINI_CLI_OAUTH_CLIENT_SECRET:-}"
  export ANTIGRAVITY_OAUTH_CLIENT_SECRET="${ANTIGRAVITY_OAUTH_CLIENT_SECRET:-}"
  export ANTIGRAVITY_USER_AGENT_VERSION="${ANTIGRAVITY_USER_AGENT_VERSION:-}"

  export SECURITY_URL_ALLOWLIST_ENABLED="${SECURITY_URL_ALLOWLIST_ENABLED:-false}"
  export SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP="${SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP:-false}"
  export SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS="${SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS:-false}"
  export SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS="${SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS:-}"
  export UPDATE_PROXY_URL="${UPDATE_PROXY_URL:-}"

  export GATEWAY_OPENAI_RESPONSE_HEADER_TIMEOUT="${GATEWAY_OPENAI_RESPONSE_HEADER_TIMEOUT:-0}"
  export GATEWAY_OPENAI_HTTP2_ENABLED="${GATEWAY_OPENAI_HTTP2_ENABLED:-true}"
  export GATEWAY_OPENAI_HTTP2_ALLOW_PROXY_FALLBACK_TO_HTTP1="${GATEWAY_OPENAI_HTTP2_ALLOW_PROXY_FALLBACK_TO_HTTP1:-true}"
  export GATEWAY_OPENAI_HTTP2_FALLBACK_ERROR_THRESHOLD="${GATEWAY_OPENAI_HTTP2_FALLBACK_ERROR_THRESHOLD:-2}"
  export GATEWAY_OPENAI_HTTP2_FALLBACK_WINDOW_SECONDS="${GATEWAY_OPENAI_HTTP2_FALLBACK_WINDOW_SECONDS:-60}"
  export GATEWAY_OPENAI_HTTP2_FALLBACK_TTL_SECONDS="${GATEWAY_OPENAI_HTTP2_FALLBACK_TTL_SECONDS:-600}"
  export GATEWAY_IMAGE_STREAM_DATA_INTERVAL_TIMEOUT="${GATEWAY_IMAGE_STREAM_DATA_INTERVAL_TIMEOUT:-900}"
  export GATEWAY_IMAGE_STREAM_KEEPALIVE_INTERVAL="${GATEWAY_IMAGE_STREAM_KEEPALIVE_INTERVAL:-10}"
  export GATEWAY_IMAGE_CONCURRENCY_ENABLED="${GATEWAY_IMAGE_CONCURRENCY_ENABLED:-false}"
  export GATEWAY_IMAGE_CONCURRENCY_MAX_CONCURRENT_REQUESTS="${GATEWAY_IMAGE_CONCURRENCY_MAX_CONCURRENT_REQUESTS:-0}"
  export GATEWAY_IMAGE_CONCURRENCY_OVERFLOW_MODE="${GATEWAY_IMAGE_CONCURRENCY_OVERFLOW_MODE:-reject}"
  export GATEWAY_IMAGE_CONCURRENCY_WAIT_TIMEOUT_SECONDS="${GATEWAY_IMAGE_CONCURRENCY_WAIT_TIMEOUT_SECONDS:-30}"
  export GATEWAY_IMAGE_CONCURRENCY_MAX_WAITING_REQUESTS="${GATEWAY_IMAGE_CONCURRENCY_MAX_WAITING_REQUESTS:-100}"
}

ensure_network() {
  if ! docker network inspect "${DEPLOY_NETWORK_NAME}" >/dev/null 2>&1; then
    log "creating network ${DEPLOY_NETWORK_NAME}"
    docker network create "${DEPLOY_NETWORK_NAME}" >/dev/null
  fi
}

ensure_dirs() {
  mkdir -p \
    "${RUNTIME_DIR}/data" \
    "${RUNTIME_DIR}/data-test" \
    "${RUNTIME_DIR}/postgres_data" \
    "${RUNTIME_DIR}/redis_data"
}

remove_legacy_variant() {
  local standard_name="$1"
  local suffix="$2"
  while IFS= read -r name; do
    [[ -z "${name}" || "${name}" == "${standard_name}" ]] && continue
    log "removing legacy container ${name}"
    docker rm -f "${name}" >/dev/null 2>&1 || true
  done < <(docker ps -a --format '{{.Names}}' | grep -E "(^|[0-9a-f]+_)${suffix}$" || true)
}

ensure_postgres() {
  remove_legacy_variant "sub2api-postgres" "sub2api-postgres"
  if container_exists sub2api-postgres; then
    container_running sub2api-postgres || docker start sub2api-postgres >/dev/null
    docker network connect "${DEPLOY_NETWORK_NAME}" sub2api-postgres >/dev/null 2>&1 || true
    wait_for_container_health sub2api-postgres
    return
  fi

  docker run -d \
    --name sub2api-postgres \
    --restart unless-stopped \
    --ulimit nofile=100000:100000 \
    --network "${DEPLOY_NETWORK_NAME}" \
    --network-alias postgres \
    -v "${RUNTIME_DIR}/postgres_data:/var/lib/postgresql/data" \
    -e POSTGRES_USER="${POSTGRES_USER:-sub2api}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}" \
    -e POSTGRES_DB="${POSTGRES_DB:-sub2api}" \
    -e PGDATA=/var/lib/postgresql/data \
    -e TZ="${TZ:-Asia/Shanghai}" \
    --health-cmd="pg_isready -U ${POSTGRES_USER:-sub2api} -d ${POSTGRES_DB:-sub2api}" \
    --health-interval=10s \
    --health-timeout=5s \
    --health-retries=5 \
    --health-start-period=10s \
    postgres:18-alpine >/dev/null

  wait_for_container_health sub2api-postgres
}

ensure_redis() {
  remove_legacy_variant "sub2api-redis" "sub2api-redis"
  if container_exists sub2api-redis; then
    container_running sub2api-redis || docker start sub2api-redis >/dev/null
    docker network connect "${DEPLOY_NETWORK_NAME}" sub2api-redis >/dev/null 2>&1 || true
    wait_for_container_health sub2api-redis
    return
  fi

  docker run -d \
    --name sub2api-redis \
    --restart unless-stopped \
    --ulimit nofile=100000:100000 \
    --network "${DEPLOY_NETWORK_NAME}" \
    --network-alias redis \
    -v "${RUNTIME_DIR}/redis_data:/data" \
    -e TZ="${TZ:-Asia/Shanghai}" \
    -e REDIS_PASSWORD="${REDIS_PASSWORD:-}" \
    -e REDISCLI_AUTH="${REDIS_PASSWORD:-}" \
    --health-cmd="redis-cli ping" \
    --health-interval=10s \
    --health-timeout=5s \
    --health-retries=5 \
    --health-start-period=5s \
    redis:8-alpine \
    sh -lc 'redis-server --save 60 1 --appendonly yes --appendfsync everysec ${REDIS_PASSWORD:+--requirepass "$REDIS_PASSWORD"}' >/dev/null

  wait_for_container_health sub2api-redis
}

ensure_deps() {
  ensure_network
  ensure_dirs
  ensure_postgres
  ensure_redis
}

run_app() {
  local name="$1"
  local image="$2"
  local bind_host="$3"
  local host_port="$4"
  local data_dir="$5"

  prepare_app_env

  docker rm -f "${name}" >/dev/null 2>&1 || true

  docker run -d \
    --name "${name}" \
    --restart unless-stopped \
    --ulimit nofile=100000:100000 \
    --network "${DEPLOY_NETWORK_NAME}" \
    --network-alias "${name}" \
    -p "${bind_host}:${host_port}:8080" \
    -v "${RUNTIME_DIR}/${data_dir}:/app/data" \
    -e AUTO_SETUP \
    -e SERVER_HOST \
    -e SERVER_PORT \
    -e SERVER_MODE \
    -e RUN_MODE \
    -e DATABASE_HOST \
    -e DATABASE_PORT \
    -e DATABASE_USER \
    -e DATABASE_PASSWORD \
    -e DATABASE_DBNAME \
    -e DATABASE_SSLMODE \
    -e DATABASE_MAX_OPEN_CONNS \
    -e DATABASE_MAX_IDLE_CONNS \
    -e DATABASE_CONN_MAX_LIFETIME_MINUTES \
    -e DATABASE_CONN_MAX_IDLE_TIME_MINUTES \
    -e REDIS_HOST \
    -e REDIS_PORT \
    -e REDIS_PASSWORD \
    -e REDIS_DB \
    -e REDIS_POOL_SIZE \
    -e REDIS_MIN_IDLE_CONNS \
    -e REDIS_ENABLE_TLS \
    -e ADMIN_EMAIL \
    -e ADMIN_PASSWORD \
    -e JWT_SECRET \
    -e JWT_EXPIRE_HOUR \
    -e TOTP_ENCRYPTION_KEY \
    -e TZ \
    -e GEMINI_OAUTH_CLIENT_ID \
    -e GEMINI_OAUTH_CLIENT_SECRET \
    -e GEMINI_OAUTH_SCOPES \
    -e GEMINI_QUOTA_POLICY \
    -e GEMINI_CLI_OAUTH_CLIENT_SECRET \
    -e ANTIGRAVITY_OAUTH_CLIENT_SECRET \
    -e ANTIGRAVITY_USER_AGENT_VERSION \
    -e SECURITY_URL_ALLOWLIST_ENABLED \
    -e SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP \
    -e SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS \
    -e SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS \
    -e UPDATE_PROXY_URL \
    -e GATEWAY_OPENAI_RESPONSE_HEADER_TIMEOUT \
    -e GATEWAY_OPENAI_HTTP2_ENABLED \
    -e GATEWAY_OPENAI_HTTP2_ALLOW_PROXY_FALLBACK_TO_HTTP1 \
    -e GATEWAY_OPENAI_HTTP2_FALLBACK_ERROR_THRESHOLD \
    -e GATEWAY_OPENAI_HTTP2_FALLBACK_WINDOW_SECONDS \
    -e GATEWAY_OPENAI_HTTP2_FALLBACK_TTL_SECONDS \
    -e GATEWAY_IMAGE_STREAM_DATA_INTERVAL_TIMEOUT \
    -e GATEWAY_IMAGE_STREAM_KEEPALIVE_INTERVAL \
    -e GATEWAY_IMAGE_CONCURRENCY_ENABLED \
    -e GATEWAY_IMAGE_CONCURRENCY_MAX_CONCURRENT_REQUESTS \
    -e GATEWAY_IMAGE_CONCURRENCY_OVERFLOW_MODE \
    -e GATEWAY_IMAGE_CONCURRENCY_WAIT_TIMEOUT_SECONDS \
    -e GATEWAY_IMAGE_CONCURRENCY_MAX_WAITING_REQUESTS \
    --health-cmd="wget -q -T 5 -O /dev/null http://localhost:8080/health || exit 1" \
    --health-interval=30s \
    --health-timeout=10s \
    --health-retries=3 \
    --health-start-period=10s \
    "${image}" >/dev/null

  wait_for_container_health "${name}"
  wait_for_http "http://127.0.0.1:${host_port}/health"
}

show_status() {
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -E 'sub2api|NAMES' || true
}

load_base_env
load_test_env

case "${COMMAND}" in
  deps)
    ensure_deps
    ;;
  prod)
    ensure_deps
    run_app "sub2api" "${PROD_IMAGE_TAG:-sub2api:monitor-group-filter}" "${PROD_BIND_HOST}" "${PROD_HOST_PORT}" "data"
    ;;
  test)
    ensure_deps
    run_app "sub2api-test" "${TEST_IMAGE_TAG}" "${TEST_BIND_HOST}" "${TEST_HOST_PORT}" "${TEST_DATA_DIR}"
    ;;
  all)
    ensure_deps
    run_app "sub2api-test" "${TEST_IMAGE_TAG}" "${TEST_BIND_HOST}" "${TEST_HOST_PORT}" "${TEST_DATA_DIR}"
    run_app "sub2api" "${PROD_IMAGE_TAG:-sub2api:monitor-group-filter}" "${PROD_BIND_HOST}" "${PROD_HOST_PORT}" "data"
    ;;
  status)
    show_status
    ;;
  *)
    die "usage: $0 {deps|prod|test|all|status}"
    ;;
esac

if [[ "${COMMAND}" != "status" ]]; then
  show_status
fi
