#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GIT_REMOTE="origin"
BRANCH=""
RUNTIME_DIR="/www/wwwroot/sub2api-deploy"
SKIP_TEST="false"
SKIP_PROD="false"
KEEP_TEST_ARTIFACTS="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-remote)
      GIT_REMOTE="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --runtime-dir)
      RUNTIME_DIR="$2"
      shift 2
      ;;
    --skip-test)
      SKIP_TEST="true"
      shift
      ;;
    --skip-prod)
      SKIP_PROD="true"
      shift
      ;;
    --keep-test-artifacts)
      KEEP_TEST_ARTIFACTS="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

cd "${REPO_ROOT}"

if [[ -z "${BRANCH}" ]]; then
  BRANCH="$(git branch --show-current)"
fi

echo "== repo =="
echo "repo_root=${REPO_ROOT}"
echo "branch=${BRANCH}"
echo "git_remote=${GIT_REMOTE}"

if [[ -n "$(git status --porcelain)" ]]; then
  STASH_NAME="release-auto-$(date +%Y%m%d-%H%M%S)"
  git stash push -u -m "${STASH_NAME}" >/dev/null
  echo "stash_saved=${STASH_NAME}"
fi

git fetch "${GIT_REMOTE}" "${BRANCH}"
git checkout "${BRANCH}"
git pull --ff-only "${GIT_REMOTE}" "${BRANCH}"

chmod +x \
  "${SCRIPT_DIR}/build_image.sh" \
  "${SCRIPT_DIR}/runtime-sync.sh" \
  "${SCRIPT_DIR}/runtime-stack.sh"

"${SCRIPT_DIR}/runtime-sync.sh" "${RUNTIME_DIR}"
chmod +x "${RUNTIME_DIR}/runtime-stack.sh"

if [[ "${SKIP_TEST}" != "true" ]]; then
  "${SCRIPT_DIR}/build_image.sh" "${TEST_IMAGE_TAG:-sub2api:monitor-group-filter-test}"
  "${RUNTIME_DIR}/runtime-stack.sh" test
fi

if [[ "${SKIP_PROD}" != "true" ]]; then
  "${SCRIPT_DIR}/build_image.sh" "${PROD_IMAGE_TAG:-sub2api:monitor-group-filter}"
  "${RUNTIME_DIR}/runtime-stack.sh" prod
fi

if [[ "${SKIP_TEST}" != "true" && "${KEEP_TEST_ARTIFACTS}" != "true" ]]; then
  "${RUNTIME_DIR}/runtime-stack.sh" cleanup-test
fi

"${RUNTIME_DIR}/runtime-stack.sh" status
