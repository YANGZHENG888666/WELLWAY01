#!/bin/bash
# 启动管理后台本地服务(默认 8000 端口;占用时自动改用 8001+)
# 以项目根目录为服务根,访问地址 http://localhost:PORT/admin/index.html
cd "$(dirname "$0")/.."
PORT=8000
for i in 0 1 2 3 4 5; do
  if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    PORT=$((PORT + i + 1))
  else
    break
  fi
done
echo "WELL WAY 管理后台: http://localhost:$PORT/admin/index.html"
exec python3 -m http.server "$PORT" --bind 127.0.0.1
