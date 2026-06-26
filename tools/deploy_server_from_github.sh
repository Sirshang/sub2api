#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  SSH_HOST=your.server.ip tools/deploy_server_from_github.sh

Optional environment variables:
  SSH_USER=root
  SSH_PORT=22
  REMOTE_SCRIPT=/root/deploy_sub2api_remote.sh
  GITHUB_REPO=Sirshang/sub2api
  GITHUB_BRANCH=codex/monitor-group-filter
  SERVER_PORT=18080
  BIND_HOST=0.0.0.0

This script assumes the remote server already has the deploy script installed.
It simply SSHes to the server and triggers a redeploy from the selected GitHub branch.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SSH_HOST="${SSH_HOST:-}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_SCRIPT="${REMOTE_SCRIPT:-/root/deploy_sub2api_remote.sh}"
GITHUB_REPO="${GITHUB_REPO:-Sirshang/sub2api}"
GITHUB_BRANCH="${GITHUB_BRANCH:-codex/monitor-group-filter}"
SERVER_PORT="${SERVER_PORT:-18080}"
BIND_HOST="${BIND_HOST:-0.0.0.0}"

if [[ -z "$SSH_HOST" ]]; then
  echo "[ERROR] SSH_HOST is required." >&2
  exit 1
fi

ssh -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" \
  "GITHUB_REPO='${GITHUB_REPO}' GITHUB_BRANCH='${GITHUB_BRANCH}' SERVER_PORT='${SERVER_PORT}' BIND_HOST='${BIND_HOST}' '${REMOTE_SCRIPT}'"
