#!/bin/bash
# 双击本文件即可启动 WELL WAY 管理后台(保持这个终端窗口开着,关掉就停止服务)
cd "$(dirname "$0")/.."
echo "=========================================="
echo " WELL WAY 管理后台"
echo " 访问地址: http://localhost:8000/admin/index.html"
echo " 关闭本窗口即停止服务"
echo "=========================================="
python3 -m http.server 8000 --bind 127.0.0.1
echo "服务已停止(窗口即将关闭...)"
sleep 2
