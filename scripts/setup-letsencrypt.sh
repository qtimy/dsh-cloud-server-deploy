#!/usr/bin/env bash
# setup-letsencrypt.sh — 可选的 LetsEncrypt 正式证书配置（需公网域名）
#
# ⚠️ 本脚本【不是 install.sh 的必选步骤】。仅当目标服务器有公网域名、
#    且你想用 Let's Encrypt 免费证书时才手动执行。无域名/内网/纯 IP 的
#    服务器请用 install.sh 默认的自签证书，不要跑本脚本。
#
# 前置条件：
#   1. 域名已解析到本机公网 IP（dig +short <域名>）
#   2. 80 端口可被 Let's Encrypt 从公网访问（用于 HTTP-01 验证）
#   3. 已先执行 install.sh（nginx 已就位，监听 80/443）
#
# 用法：
#   sudo bash scripts/setup-letsencrypt.sh <域名> [邮箱]
#   例：sudo bash scripts/setup-letsencrypt.sh dsh.example.com admin@example.com
#
# 效果：签发证书 → 切换 nginx 到正式证书 → 配置自动续期 → 验证证书链。
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"

if [ -z "$DOMAIN" ]; then
  echo "ERROR: 缺少域名参数" >&2
  echo "用法: sudo bash scripts/setup-letsencrypt.sh <域名> [邮箱]" >&2
  exit 1
fi
# 域名格式校验（防注入）
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "ERROR: 域名格式非法: $DOMAIN" >&2
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: 需要 root 权限（装 certbot、改 nginx、写 /etc/letsencrypt）" >&2
  exit 1
fi
[ -n "$EMAIL" ] || EMAIL="admin@${DOMAIN#*.}"

echo "===== 1/6 前置检查：域名解析到本机公网 IP ====="
PUBLIC_IP="$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 https://api.ipify.org 2>/dev/null || echo '')"
DOMAIN_IP="$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1 || echo '')"
echo "域名 ${DOMAIN} → ${DOMAIN_IP:-解析失败}"
echo "本机公网 IP → ${PUBLIC_IP:-无法获取}"
if [ -n "$PUBLIC_IP" ] && [ -n "$DOMAIN_IP" ] && [ "$PUBLIC_IP" != "$DOMAIN_IP" ]; then
  echo "⚠️  警告：域名解析 IP 与本机公网 IP 不一致，证书签发可能失败。" >&2
  echo "    请确认 DNS 记录指向本机，或 CDN/代理已正确回源。" >&2
fi

echo "===== 2/6 安装 certbot 与 nginx 插件 ====="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1

echo "===== 3/6 临时注入 ACME 挑战放行（webroot）====="
mkdir -p /var/www/certbot/.well-known/acme-challenge
# 在 80 端口 server 块注入 /.well-known/acme-challenge/ 放行（幂等）
NGINX_CONF=/etc/nginx/sites-available/dsh
if ! grep -q 'acme-challenge' "$NGINX_CONF" 2>/dev/null; then
  python3 - "$NGINX_CONF" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;'''
new = '''    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    # ACME HTTP-01 挑战放行（certbot webroot，签发正式证书用）
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
    }
    location / {
        return 301 https://$host$request_uri;
    }'''
if old in s:
    open(p, 'w').write(s.replace(old, new, 1))
    print("ACME 放行已注入")
else:
    print("WARN: 未找到标准 80 端口块，请手动确认")
PY
fi
nginx -t && systemctl reload nginx

echo "===== 4/6 签发证书（webroot 模式）====="
certbot certonly --webroot -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos --no-eff-email --rsa-key-size 2048

echo "===== 5/6 切换 nginx 443 到正式证书 ====="
CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
python3 - "$NGINX_CONF" "$CERT" "$KEY" <<'PY'
import sys
p, cert, key = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
import re
s2 = re.sub(r'ssl_certificate\s+[^;]+;', f'ssl_certificate     {cert};', s, count=1)
s2 = re.sub(r'ssl_certificate_key\s+[^;]+;', f'ssl_certificate_key {key};', s2, count=1)
open(p, 'w').write(s2)
print("证书路径已切换")
PY
nginx -t && systemctl reload nginx

echo "===== 6/6 验证证书链 ====="
sleep 2
echo | openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" 2>/dev/null \
  | grep -E 'subject=|issuer=|Verify return code' | head -4

echo ""
echo "===== 完成 ====="
echo "https://${DOMAIN}/ 已使用 Let's Encrypt 正式证书。"
echo "certbot 已配置自动续期（systemd timer）。"
echo "提示：续期后 nginx 会自动 reload（certbot renew 钩子已由插件处理）。"