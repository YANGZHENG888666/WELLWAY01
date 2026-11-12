#!/bin/bash
# 一键把后台(admin/index.html)部署到 GitHub Pages 永久公网
# 用法:  bash backend/scripts/deploy-gh-pages.sh <GITHUB_TOKEN>
# 前置:  你的 GitHub 账号下已有一个仓库(没有的话告诉我,我帮你建)
set -euo pipefail
TOKEN="${1:-}"
REPO="${GITHUB_REPO:-YANGZHENG888666/WELLWAY01}"   # 改成你的仓库
BRANCH="gh-pages"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"

if [ -z "$TOKEN" ]; then
  echo "用法: bash backend/scripts/deploy-gh-pages.sh <GITHUB_TOKEN>" >&2
  echo "Token 创建: GitHub → Settings → Developer settings → Personal access tokens → 选 public_repo 权限" >&2
  exit 1
fi

mkdir -p "$WORK/admin"
cp "$ROOT/admin/index.html" "$WORK/admin/index.html"
cat > "$WORK/index.html" <<'HTML2'
<!doctype html><html lang="zh"><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=./admin/"></head><body><a href="./admin/">进入 WELL WAY 管理后台</a></body></html>
HTML2

cd "$WORK"
git init -q -b "$BRANCH"
git config user.name "WELLWAY Deploy"
git config user.email "deploy@wellway.local"
git add -A
git commit -qm "deploy admin $(date +%F_%T)"

git push -f "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "$BRANCH"
echo "✅ 已推送到 GitHub Pages 分支"
echo "🔗 后台地址(等 1~2 分钟生效): https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/admin/"
echo "📌 若首次使用,请在仓库 Settings → Pages → Branch 选 gh-pages 并保存"
