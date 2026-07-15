# t2.llmwc.com 独立测试实例方案

## 目标

`t2.llmwc.com` 作为 `sub.llmwc.com` 之外的独立测试实例运行。它复用同一套 Sub2API 代码和镜像，但不复用 `sub.llmwc.com` 的分支代码、数据、缓存、JWT 密钥、TOTP 密钥和管理员账号。

这样配置后，t2 管理员只能登录 `t2.llmwc.com` 的后台，只能看到 t2 自己数据库里的用户、API Key、账户、分组、兑换码、订单和统计数据。除非你在 `sub.llmwc.com` 的数据库里也单独创建同一个管理员，否则 t2 管理员不能以管理员身份登录 `sub.llmwc.com`。

## 文件

- `docker-compose.t2.yml`: t2 专用 Docker Compose，容器名、网络、数据目录都与主站隔离。
- `.env.t2.example`: t2 专用环境变量模板，不包含真实密钥。
- `prepare-t2-env.sh`: 生成 `.env.t2`、随机密钥和 `deploy/t2/` 运行时目录。
- `Caddyfile.t2`: `t2.llmwc.com` 的反向代理示例，默认代理到 `127.0.0.1:18082`。

## 首次配置

```bash
cd /Users/shanzujie/Documents/home/51aigc/sub2API/deploy
chmod +x prepare-t2-env.sh
./prepare-t2-env.sh
```

生成后检查 `.env.t2`：

```bash
grep -E '^(T2_SERVER_PORT|SERVER_FRONTEND_URL|POSTGRES_USER|POSTGRES_DB|ADMIN_EMAIL)=' .env.t2
```

确认这些值符合预期：

```env
T2_SERVER_PORT=18082
SUB2API_IMAGE=weishaw/sub2api:latest
SERVER_FRONTEND_URL=https://t2.llmwc.com
POSTGRES_USER=sub2api_t2
POSTGRES_DB=sub2api_t2
ADMIN_EMAIL=admin@t2.llmwc.com
```

## 启动和验证

```bash
cd /Users/shanzujie/Documents/home/51aigc/sub2API/deploy
docker compose --env-file .env.t2 -f docker-compose.t2.yml up -d
docker compose --env-file .env.t2 -f docker-compose.t2.yml ps
curl -fsS http://127.0.0.1:18082/health
```

如果服务器不能直接拉取 Docker Hub 镜像，可以先构建或推送自己的镜像，然后修改 `.env.t2`：

```env
SUB2API_IMAGE=your-registry/sub2api:your-tag
```

如果需要查看 t2 管理员账号：

```bash
grep -E '^(ADMIN_EMAIL|ADMIN_PASSWORD)=' .env.t2
```

## 子域名接入

1. DNS 添加 `t2.llmwc.com` 到服务器公网 IP，可用 A 记录或经 Cloudflare 代理。
2. 将 `Caddyfile.t2` 的站点块加入服务器 Caddy 配置。
3. 重载 Caddy。
4. 验证公网访问：

```bash
curl -I https://t2.llmwc.com/health
```

如果服务器使用 Nginx，把 `t2.llmwc.com` 代理到 `http://127.0.0.1:18082` 即可，关键是不要代理到 `sub.llmwc.com` 实例的端口。

## 运维边界

- 主域名和 t2 可以更新同一套代码，但必须保持各自独立的 `.env`、数据目录和容器。
- 不要把主域名的 `JWT_SECRET`、`TOTP_ENCRYPTION_KEY`、PostgreSQL 数据目录或 Redis 数据目录复制给 t2。
- t2 的上游账户、分组、套餐、兑换码、支付配置和用户需要在 t2 后台重新配置。
- 备份 t2 时只备份 `deploy/t2/` 和 `.env.t2`；主域名备份不要混入 t2 数据。
