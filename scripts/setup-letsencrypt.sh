#!/usr/bin/env bash
# Install a trusted Let's Encrypt certificate after the base deployment.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run as root: sudo $0 <domain> [email]" >&2
  exit 2
fi

DOMAIN="${1:-}"
EMAIL="${2:-}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/dsh-deploy}"
NGINX_CONF=/etc/nginx/sites-available/dsh

if [[ ! "${DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "ERROR: provide a valid domain name." >&2
  exit 2
fi
EMAIL="${EMAIL:-admin@${DOMAIN}}"
if [[ ! "${EMAIL}" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]]; then
  echo "ERROR: provide a valid contact email." >&2
  exit 2
fi
if [[ ! -f "${NGINX_CONF}" ]]; then
  echo "ERROR: run install.sh before setting up Let's Encrypt." >&2
  exit 2
fi

echo "===== 1/5 install Certbot ====="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y certbot >/dev/null

echo "===== 2/5 enable the ACME HTTP-01 path ====="
mkdir -p /var/www/certbot/.well-known/acme-challenge
if ! grep -q 'acme-challenge' "${NGINX_CONF}"; then
  candidate="$(mktemp)"
  awk '
    { print }
    !added && /^[[:space:]]*server_name _;/ {
      print "    location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; }"
      added=1
    }
  ' "${NGINX_CONF}" > "${candidate}"
  install -m 0644 "${candidate}" "${NGINX_CONF}"
  rm -f "${candidate}"
fi
nginx -t
systemctl reload nginx

echo "===== 3/5 request the certificate ====="
certbot certonly --webroot -w /var/www/certbot \
  -d "${DOMAIN}" --email "${EMAIL}" --agree-tos --no-eff-email --non-interactive

CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

echo "===== 4/5 switch Nginx and persist the certificate paths ====="
sed -i -E "s|^[[:space:]]*ssl_certificate[[:space:]]+[^;]+;|    ssl_certificate     ${CERT};|" \
  "${NGINX_CONF}"
sed -i -E "s|^[[:space:]]*ssl_certificate_key[[:space:]]+[^;]+;|    ssl_certificate_key ${KEY};|" \
  "${NGINX_CONF}"
mkdir -p "${DEPLOY_DIR}"
printf 'SSL_CERT_PATH=%s\nSSL_KEY_PATH=%s\n' "${CERT}" "${KEY}" > "${DEPLOY_DIR}/tls.env"
chmod 0600 "${DEPLOY_DIR}/tls.env"
nginx -t
systemctl reload nginx

echo "===== 5/5 install a renewal deploy hook ====="
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
printf '#!/usr/bin/env bash\nnginx -t && systemctl reload nginx\n' \
  > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
certbot renew --dry-run

echo "OK: https://${DOMAIN}/ now uses Let's Encrypt."
