#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/sync_fork.sh

Optional environment variables:
  BASE_BRANCH=main
  TARGET_BRANCH=codex/monitor-group-filter
  NO_PUSH=1

Behavior:
  1. Fetch origin and upstream
  2. Fast-forward local BASE_BRANCH to upstream/BASE_BRANCH
  3. Push BASE_BRANCH to origin unless NO_PUSH=1
  4. Merge BASE_BRANCH into TARGET_BRANCH when TARGET_BRANCH is set
  5. Push TARGET_BRANCH to origin unless NO_PUSH=1

Notes:
  - Refuses to run with a dirty worktree.
  - If merge conflicts happen, the script stops and leaves the repo in the
    current conflict state so you can resolve it manually.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

BASE_BRANCH="${BASE_BRANCH:-main}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
NO_PUSH="${NO_PUSH:-0}"

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "[ERROR] Detached HEAD is not supported by this script." >&2
  exit 1
fi

if [[ -z "$TARGET_BRANCH" ]]; then
  if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
    TARGET_BRANCH="$CURRENT_BRANCH"
  elif git show-ref --verify --quiet "refs/heads/codex/monitor-group-filter"; then
    TARGET_BRANCH="codex/monitor-group-filter"
  fi
fi

if [[ -n "$(git status --short)" ]]; then
  echo "[ERROR] Worktree is not clean. Commit or stash your changes first." >&2
  git status --short
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "[ERROR] Missing remote: origin" >&2
  exit 1
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "[ERROR] Missing remote: upstream" >&2
  exit 1
fi

echo "[INFO] Fetching origin and upstream"
git fetch origin --prune
git fetch upstream --prune

if ! git show-ref --verify --quiet "refs/remotes/upstream/${BASE_BRANCH}"; then
  echo "[ERROR] Missing upstream branch: upstream/${BASE_BRANCH}" >&2
  exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/${BASE_BRANCH}"; then
  if git show-ref --verify --quiet "refs/remotes/origin/${BASE_BRANCH}"; then
    git branch "${BASE_BRANCH}" "origin/${BASE_BRANCH}"
  else
    git branch "${BASE_BRANCH}" "upstream/${BASE_BRANCH}"
  fi
fi

echo "[INFO] Syncing ${BASE_BRANCH} from upstream/${BASE_BRANCH}"
git checkout "${BASE_BRANCH}"
git merge --ff-only "upstream/${BASE_BRANCH}"

if [[ "$NO_PUSH" != "1" ]]; then
  echo "[INFO] Pushing ${BASE_BRANCH} to origin"
  git push origin "${BASE_BRANCH}"
fi

if [[ -n "$TARGET_BRANCH" && "$TARGET_BRANCH" != "$BASE_BRANCH" ]]; then
  if ! git show-ref --verify --quiet "refs/heads/${TARGET_BRANCH}"; then
    echo "[ERROR] Missing local target branch: ${TARGET_BRANCH}" >&2
    exit 1
  fi

  echo "[INFO] Merging ${BASE_BRANCH} into ${TARGET_BRANCH}"
  git checkout "${TARGET_BRANCH}"
  git merge "${BASE_BRANCH}"

  if [[ "$NO_PUSH" != "1" ]]; then
    echo "[INFO] Pushing ${TARGET_BRANCH} to origin"
    git push origin "${TARGET_BRANCH}"
  fi
fi

if [[ "$CURRENT_BRANCH" != "$(git branch --show-current)" ]]; then
  git checkout "$CURRENT_BRANCH"
fi

echo "[INFO] Sync complete"
