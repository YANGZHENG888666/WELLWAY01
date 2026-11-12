#!/usr/bin/env bash
# 免费版 Supabase 闲置约 7 天会被暂停,暂停后项目域名直接 NXDOMAIN,App 读不到任何云端数据。
# 该脚本请求一次公开只读接口,让项目保持活跃。
set -euo pipefail

SUPABASE_URL="https://hyfxpcwbhfgmtwjhcxdn.supabase.co"
# publishable key:与 ios/WELLWAY/Resources/Info.plist 中的 SUPABASE_ANON_KEY 相同,本身即公开凭据
SUPABASE_KEY="sb_publishable_wUdbrbEFBtWcLO86nk_nwA_vRyXnfp4"

code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 \
  "$SUPABASE_URL/rest/v1/brands?select=id&limit=1" \
  -H "apikey: $SUPABASE_KEY")

echo "$(date '+%Y-%m-%d %H:%M:%S') keepalive -> HTTP $code"

# 200:正常;401/404:项目可能正在恢复;5xx/000:暂停或不可达
[ "$code" = "200" ]
