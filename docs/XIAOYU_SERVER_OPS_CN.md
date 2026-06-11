# XiaoYu 服务器运维变更说明

最后整理时间：2026-06-11

本文档记录 `www.51aigc.email` 所在服务器近期已落地的运维改动，便于后续排障、迁移和复核。

## 1. 服务托管

后端服务已改为由 systemd 托管，启用异常自动拉起。

- 服务名：`xiaoyu-fastapi.service`
- 配置文件：`/etc/systemd/system/xiaoyu-fastapi.service`
- 启动命令：`/www/server/pyporject_evn/versions/3.10.14/bin/python3 run.py`
- 工作目录：`/www/wwwroot/node/xiaoyu-main/fastapi-backend`
- 重启策略：
  - `Restart=always`
  - `RestartSec=3`

常用命令：

```bash
systemctl status xiaoyu-fastapi.service
systemctl restart xiaoyu-fastapi.service
journalctl -u xiaoyu-fastapi.service -n 100 --no-pager
```

## 2. 健康检查

后端新增了独立健康检查接口：

- 路径：`/healthz`
- 作用：
  - 检查 Web 进程是否存活
  - 检查数据库连通性（`SELECT 1`）

Nginx 已转发该接口：

- Nginx 配置文件：`/www/server/panel/vhost/nginx/node_nextjs.conf`
- 转发目标：`http://127.0.0.1:8000/healthz`

验证命令：

```bash
curl -sS http://127.0.0.1:8000/healthz
curl -sS https://www.51aigc.email/healthz
```

期望返回：

```json
{"status":"healthy","service":"fastapi-backend-mysql","database":"ok","version":"1.0.0"}
```

## 3. 日志策略

当前日志策略已收敛为“控制台/journal 为主，文件日志关闭”，避免重复写盘。

已调整的后端配置文件：

- `/www/wwwroot/node/xiaoyu-main/fastapi-backend/app/config.py`
- `/www/wwwroot/node/xiaoyu-main/fastapi-backend/app/logging_config.py`
- `/www/wwwroot/node/xiaoyu-main/fastapi-backend/main.py`
- `/www/wwwroot/node/xiaoyu-main/fastapi-backend/.env`

当前关键开关：

```env
LOG_TO_CONSOLE=true
LOG_TO_FILE=false
```

建议以 systemd journal 为主排查：

```bash
journalctl -u xiaoyu-fastapi.service -f
```

## 4. 常规垃圾清理

已部署服务器常规清理任务，用于压缩 journal、清理临时文件与轮转日志。

- service：`/etc/systemd/system/xiaoyu-cleanup.service`
- timer：`/etc/systemd/system/xiaoyu-cleanup.timer`
- 脚本：`/usr/local/sbin/xiaoyu-cleanup.sh`

用途：

- `journalctl --vacuum-size=200M`
- 清理 `/tmp`
- 触发日志轮转

检查命令：

```bash
systemctl list-timers --all | grep xiaoyu-cleanup
systemctl status xiaoyu-cleanup.service
```

## 5. api_call_history 自动保留 1 天

数据库表 `api_call_history` 已配置自动清理，仅保留最近 1 天数据。

部署项：

- service：`/etc/systemd/system/xiaoyu-api-call-history-cleanup.service`
- timer：`/etc/systemd/system/xiaoyu-api-call-history-cleanup.timer`
- 脚本：`/usr/local/sbin/xiaoyu-api-call-history-cleanup.sh`

当前策略：

- 保留窗口：`1 day`
- 执行频率：`1 minute`
- 删除方式：按 `created_at` 分批删除旧记录

验证命令：

```bash
systemctl list-timers --all | grep xiaoyu-api-call-history-cleanup
journalctl -u xiaoyu-api-call-history-cleanup.service -n 20 --no-pager
```

验证 SQL：

```sql
SELECT COUNT(*) FROM api_call_history
WHERE created_at < (NOW() - INTERVAL 1 DAY);
```

预期结果：`0`

## 6. MySQL binlog 保留策略

已将 MySQL binlog 过期时间固定为 7 天。

- 配置文件：`/etc/my.cnf`
- 参数：

```ini
binlog_expire_logs_seconds = 604800
```

验证命令：

```sql
SELECT @@binlog_expire_logs_seconds;
```

预期结果：

```text
604800
```

说明：

- 该配置用于防止 `mysql-bin.*` 持续无限增长。
- 修改后需要重启 `mysqld` 生效。

## 7. 表空间整理

已对 `api_call_history` 执行过一次表整理：

```sql
OPTIMIZE TABLE api_call_history;
```

说明：

- `DELETE` 只删除行，不会自动缩小 `.ibd` 文件。
- 当历史数据被大量清掉后，应在业务低峰执行一次 `OPTIMIZE TABLE` 回收空间。

## 8. 当前建议的巡检命令

```bash
systemctl status xiaoyu-fastapi.service
curl -sS https://www.51aigc.email/healthz
systemctl list-timers --all | grep xiaoyu-api-call-history-cleanup
journalctl -u xiaoyu-api-call-history-cleanup.service -n 20 --no-pager
df -h
ls -lh /www/server/data/mysql-bin.*
ls -lh /www/server/data/xiaoyu/api_call_history.ibd
```

## 9. 变更注意事项

1. 不要把数据库密码、上游 API Key、订阅地址直接写入仓库文档。
2. 如果迁移服务器，systemd unit、timer、清理脚本、Nginx `healthz` 转发规则都要一起迁移。
3. 如果更换数据库账号或密码，`xiaoyu-api-call-history-cleanup.sh` 里的连接配置必须同步更新。
4. 若后续要改日志策略，优先保持单写，避免同时写 journal 和业务文件日志。
