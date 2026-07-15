#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"

env_file="${1:-.env.t2}"

if [ -e "$env_file" ]; then
  echo "$env_file already exists; refusing to overwrite it." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate t2 secrets." >&2
  exit 1
fi

cp .env.t2.example "$env_file"
mkdir -p t2/data t2/postgres_data t2/redis_data

replace_line() {
  key="$1"
  value="$2"
  tmp_file="${env_file}.tmp"
  awk -v key="$key" -v value="$value" '
    BEGIN { replaced = 0 }
    $0 ~ "^" key "=" { print key "=" value; replaced = 1; next }
    { print }
    END { if (replaced == 0) print key "=" value }
  ' "$env_file" > "$tmp_file"
  mv "$tmp_file" "$env_file"
}

replace_line POSTGRES_PASSWORD "$(openssl rand -hex 24)"
replace_line REDIS_PASSWORD "$(openssl rand -hex 24)"
replace_line ADMIN_PASSWORD "$(openssl rand -base64 24 | tr -d '\n')"
replace_line JWT_SECRET "$(openssl rand -hex 32)"
replace_line TOTP_ENCRYPTION_KEY "$(openssl rand -hex 32)"

chmod 600 "$env_file"

echo "Created $env_file and t2 runtime directories."
echo "Start with: docker compose --env-file $env_file -f docker-compose.t2.yml up -d"

