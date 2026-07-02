# 51aigc new_sub2 Deployment Runbook

This file documents the public, non-secret deployment rules for the `51aigc.org` instance.
Private server details and exact local commands can live in `local/51aigc-deploy.private.md`, which is intentionally ignored by Git.

## Identity

- Production site: `https://51aigc.org`
- Instance name: `new_sub2`
- Active branch: `main`
- Writable fork: `origin git@github.com:Sirshang/sub2api.git`
- True upstream: `weishaw git@github.com:Wei-Shaw/sub2api.git`
- Deprecated old branch: `codex/monitor-group-filter`

Do not deploy from `codex/monitor-group-filter`. It is an old branch and can conflict with the current configurable recharge page work.

## Update Check

Always start with a clean-state inspection:

```bash
git status --short --branch
git fetch origin main
git fetch weishaw main
git rev-list --left-right --count HEAD...origin/main
git rev-list --left-right --count HEAD...weishaw/main
git log --oneline --decorate --graph --max-count=30 --all
```

Interpretation:

- `HEAD...origin/main = 0 0`: local and fork are in sync.
- `HEAD...origin/main = N 0`: local has unpushed commits.
- `HEAD...origin/main = 0 N`: fork has commits missing locally.
- `HEAD...weishaw/main = 0 N`: upstream has updates to merge.
- `HEAD...weishaw/main = N M`: both local custom work and upstream have changes; inspect before merging.

## Merge Rules

When syncing upstream:

```bash
git switch main
git merge --no-edit weishaw/main
```

Preserve these 51aigc custom items:

- `frontend/public/custom-pages/recharge.html`
- `frontend/public/custom-pages/recharge-admin.html`
- `frontend/public/custom-pages/recharge-admin.js`
- `frontend/public/custom-pages/recharge-config.js`
- `frontend/public/custom-pages/recharge-tabs.js`
- `frontend/public/custom-pages/customer-service-wechat-szj77563.jpg`
- `/custom-pages/` iframe headers: `X-Frame-Options: SAMEORIGIN` and `frame-ancestors 'self'`
- Caddy redirect from `www.51aigc.org` to `https://51aigc.org{uri}`

If a merge tries to use `codex/monitor-group-filter`, abort and return to `main`.

## Required Local Checks

From `backend/`:

```bash
GOPROXY=https://goproxy.cn,direct GOSUMDB=sum.golang.google.cn go test ./internal/server/middleware ./internal/service -run 'TestSecurityHeaders|TestOpenAIGatewayServiceRecordUsage'
```

From `frontend/`:

```bash
pnpm run build
```

Also check custom files and iframe code:

```bash
ls -la frontend/public/custom-pages
rg -n "isCustomStaticPagePath|SAMEORIGIN|frame-ancestors" backend/internal/server/middleware/security_headers.go backend/internal/server/middleware/security_headers_test.go
```

## Deployment Shape

The current deployment does not rely on the server pulling from GitHub. The normal pattern is:

1. Push `main` to `origin`.
2. Sync the local repo to the server deploy source with `rsync`.
3. Build a Docker image tagged as `sub2api:sirshang-<short-sha>`.
4. Update the runtime compose image.
5. Restart only the `sub2api` app container.

Exact server paths and SSH alias belong in `local/51aigc-deploy.private.md`.

## Required Post-Deploy Checks

```bash
curl -sS https://51aigc.org/health
curl -sSI https://51aigc.org/custom-pages/recharge.html
curl -sSI https://51aigc.org/custom-pages/recharge-admin.html
curl -sSIL https://www.51aigc.org/custom/879eb0c69335b581
```

Expected:

- `/health` returns `{"status":"ok"}`.
- `/custom-pages/recharge.html` returns `200`.
- `/custom-pages/recharge-admin.html` returns `200`.
- `www.51aigc.org` redirects to `51aigc.org`.
- Recharge page response headers include same-origin iframe permission.

## Reporting

Every deployment report should include:

- Local branch and commit
- `origin/main` sync state
- `weishaw/main` ahead/behind state
- Server image tag
- Container health
- Result of the recharge page, admin page, and `www` redirect checks
