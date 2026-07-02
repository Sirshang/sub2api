# Codex Project Rules

This repository contains the `51aigc.org` production fork of `sub2api`.

Before checking updates, committing, or deploying this project, read:

- `docs/51aigc-new-sub2-deploy.md`
- `local/51aigc-deploy.private.md` if it exists on this machine

Hard rules for the `51aigc.org` / `new_sub2` instance:

- Use `main` as the active deployment branch.
- Do not use `codex/monitor-group-filter`; that is an old deployment branch.
- Writable fork: `git@github.com:Sirshang/sub2api.git`
- True upstream: `git@github.com:Wei-Shaw/sub2api.git`
- Do not use `zero199901/sub2api` as upstream for this project.
- Preserve the 51aigc custom recharge pages under `frontend/public/custom-pages/`.
- Preserve the `/custom-pages/` same-origin iframe header behavior in `backend/internal/server/middleware/security_headers.go`.
- Preserve the server-side `www.51aigc.org` to `https://51aigc.org{uri}` redirect.

When in doubt, stop and report the current branch, ahead/behind counts, and server image before changing files or deploying.
