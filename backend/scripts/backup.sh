#!/bin/bash
# WELL WAY 数据备份
# 方式一(推荐,完整 SQL):配置 SUPABASE_DB_URL 后用 pg_dump 备份整个数据库
# 方式二(JSON):仅有 service role key 时,用 Node 导出全部业务表
#
# 用法:
#   bash backend/scripts/backup.sh
# 环境变量(backend/.env):
#   SUPABASE_DB_URL=postgresql://postgres.xxxx:密码@aws-0-xxx.pooler.supabase.com:5432/postgres
#   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
OUT_ROOT="$ROOT/backups"
mkdir -p "$OUT_ROOT"

if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "!! 未找到 $ENV_FILE,请先 cp backend/.env.example backend/.env 并填入密钥"
  exit 1
fi

PG_DUMP="$(command -v pg_dump || echo /Applications/Postgres.app/Contents/Versions/latest/bin/pg_dump)"
STAMP="$(date +%Y-%m-%d-%H%M%S)"

if [ -n "${SUPABASE_DB_URL:-}" ]; then
  echo "==> 方式一:pg_dump 完整备份"
  "$PG_DUMP" "$SUPABASE_DB_URL" --format=custom --file="$OUT_ROOT/wellway-$STAMP.dump"
  echo "==> 已生成 $OUT_ROOT/wellway-$STAMP.dump ($(du -h "$OUT_ROOT/wellway-$STAMP.dump" | cut -f1))"
else
  echo "==> 未配置 SUPABASE_DB_URL,改用 JSON 备份(不含存储桶文件)"
  (cd "$ROOT/scripts" && node --env-file="$ENV_FILE" backup-json.mjs "$OUT_ROOT")
fi

# 保留最近 10 份,清理更早的
ls -1dt "$OUT_ROOT"/wellway-*.dump "$OUT_ROOT"/2* 2>/dev/null | tail -n +11 | xargs -r rm -rf
echo "==> 备份完成,保留最近 10 份于 $OUT_ROOT"
