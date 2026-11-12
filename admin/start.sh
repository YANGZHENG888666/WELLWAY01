#!/bin/bash
# WELL WAY 管理后台启动脚本
# 用法: ./admin/start.sh  然后浏览器打开 http://localhost:8000/admin/index.html
cd "$(dirname "$0")/.."
PORT="${1:-8000}"
if lsof -i :"$PORT" >/dev/null 2>&1; then
  echo "端口 $PORT 已被占用(后台可能已在运行)。"
else
  nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >/tmp/wellway-admin.log 2>&1 &
  sleep 1
  echo "管理后台已启动: http://localhost:$PORT/admin/index.html"
fi
