#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${1:-/www/wwwroot/sub2api-deploy}"

mkdir -p "${RUNTIME_DIR}" \
  "${RUNTIME_DIR}/data" \
  "${RUNTIME_DIR}/data-test" \
  "${RUNTIME_DIR}/postgres_data" \
  "${RUNTIME_DIR}/redis_data"

copy_file() {
  local src="$1"
  local dest="$2"
  install -D -m 0644 "${src}" "${dest}"
}

copy_exec() {
  local src="$1"
  local dest="$2"
  install -D -m 0755 "${src}" "${dest}"
}

copy_file "${SCRIPT_DIR}/docker-compose.local.yml" "${RUNTIME_DIR}/docker-compose.local.yml"
copy_file "${SCRIPT_DIR}/docker-compose.test.yml" "${RUNTIME_DIR}/docker-compose.test.yml"
copy_file "${SCRIPT_DIR}/.env.test.example" "${RUNTIME_DIR}/.env.test.example"
copy_exec "${SCRIPT_DIR}/runtime-stack.sh" "${RUNTIME_DIR}/runtime-stack.sh"

if [[ ! -f "${RUNTIME_DIR}/.env.test" ]]; then
  cp "${SCRIPT_DIR}/.env.test.example" "${RUNTIME_DIR}/.env.test"
fi

echo "runtime_dir=${RUNTIME_DIR}"
echo "synced_files=docker-compose.local.yml,docker-compose.test.yml,.env.test.example,runtime-stack.sh"
