#!/usr/bin/env bash
# Official-core DSH HTTPS installer. Run from the repository root with sudo.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}"
ENV_FILE="${REPO_DIR}/.env"

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run with sudo bash install.sh" >&2
  exit 2
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} is missing." >&2
  echo "Run: cp ${REPO_DIR}/.env.example ${ENV_FILE}, then edit it." >&2
  exit 2
fi

# The operator owns this file; exporting lets template variables and API-key
# names remain available to child commands without putting secrets in the repo.
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

DSH_VERSION="${DSH_VERSION:-}"
PUBLIC_SETTINGS_OVER_BASIC_AUTH="${PUBLIC_SETTINGS_OVER_BASIC_AUTH:-true}"
DSH_PORT="${DSH_PORT:-3080}"
DSH_USER="${DSH_USER:-dsh}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/dsh-deploy}"
TRUSTED_HOST="${TRUSTED_HOST:-}"
BASIC_AUTH_USER="${BASIC_AUTH_USER:-dsh}"
BASIC_AUTH_PASSWORD="${BASIC_AUTH_PASSWORD:-}"
DSH_HOME_TARGET="/home/${DSH_USER}/.dsh"
PROFILE_DIR="${DSH_HOME_TARGET}/profiles/web"

exact_version_re='^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$'
if [[ ! "${DSH_VERSION}" =~ ${exact_version_re} ]]; then
  echo "ERROR: DSH_VERSION must be an exact version (for example 0.1.1-rc.1)." >&2
  exit 2
fi
if [[ "${PUBLIC_SETTINGS_OVER_BASIC_AUTH}" != true && "${PUBLIC_SETTINGS_OVER_BASIC_AUTH}" != false ]]; then
  echo "ERROR: PUBLIC_SETTINGS_OVER_BASIC_AUTH must be true or false." >&2
  exit 2
fi
if [[ -z "${TRUSTED_HOST}" || "${TRUSTED_HOST}" == "your-server-ip-or-domain" ]]; then
  echo "ERROR: set TRUSTED_HOST in .env." >&2
  exit 2
fi
if [[ ! "${TRUSTED_HOST}" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo "ERROR: TRUSTED_HOST must be a hostname or IPv4 address, optionally with a port." >&2
  exit 2
fi
if [[ ! "${BASIC_AUTH_USER}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: BASIC_AUTH_USER contains unsupported characters." >&2
  exit 2
fi
if [[ -z "${BASIC_AUTH_PASSWORD}" || "${BASIC_AUTH_PASSWORD}" == "change-me-strong-password" ]]; then
  echo "ERROR: set a strong BASIC_AUTH_PASSWORD in .env." >&2
  exit 2
fi
if [[ ! "${DSH_PORT}" =~ ^[0-9]+$ ]] || (( DSH_PORT < 1 || DSH_PORT > 65535 )); then
  echo "ERROR: DSH_PORT must be between 1 and 65535." >&2
  exit 2
fi
if [[ ! "${DSH_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: invalid DSH_USER: ${DSH_USER}" >&2
  exit 2
fi

echo "===== 1/7 system dependencies ====="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ca-certificates curl gnupg nginx openssl apache2-utils gettext-base util-linux >/dev/null

node_major=0
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
fi
if (( node_major < 22 )); then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs >/dev/null
fi
if ! command -v pnpm >/dev/null 2>&1; then
  npm install -g pnpm
fi

echo "===== 2/7 official DSH core ${DSH_VERSION} ====="
npm view "@deepseek-ai/dsh@${DSH_VERSION}" version >/dev/null
systemctl stop dsh-autorestart dsh-web 2>/dev/null || true
npm install -g "@deepseek-ai/dsh@${DSH_VERSION}"
if [[ "$(dsh --version)" != "${DSH_VERSION}" ]]; then
  echo "ERROR: installed DSH version does not match ${DSH_VERSION}." >&2
  exit 1
fi

echo "===== 3/7 user and official web profile ====="
if ! id "${DSH_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${DSH_USER}"
fi
mkdir -p "${DSH_HOME_TARGET}"/{profiles/web,sessions,plugins,storages,marketplace}

install_if_missing() {
  local source=$1 target=$2 mode=$3
  if [[ ! -e "${target}" ]]; then
    install -o "${DSH_USER}" -g "${DSH_USER}" -m "${mode}" "${source}" "${target}"
    echo "created ${target}"
  else
    echo "preserved ${target}"
  fi
}

install_if_missing "${REPO_DIR}/templates/settings.yaml.tpl" \
  "${DSH_HOME_TARGET}/settings.yaml" 0600
install_if_missing "${REPO_DIR}/templates/profile-package.json.tpl" \
  "${PROFILE_DIR}/package.json" 0644
install_if_missing "${REPO_DIR}/templates/cordis.patch.yml.tpl" \
  "${PROFILE_DIR}/cordis.patch.yml" 0644
install_if_missing "${REPO_DIR}/templates/pnpm-workspace.yaml.tpl" \
  "${PROFILE_DIR}/pnpm-workspace.yaml" 0644

CRED_FILE="${DSH_HOME_TARGET}/.credentials.yaml"
if [[ ! -e "${CRED_FILE}" ]]; then
  install -o "${DSH_USER}" -g "${DSH_USER}" -m 0600 \
    "${REPO_DIR}/templates/credentials.yaml.tpl" "${CRED_FILE}"
  api_key_vars="$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*_API_KEY=' "${ENV_FILE}" 2>/dev/null | sed 's/=$//' | sort -u)"
  if [[ -n "${api_key_vars}" ]]; then
    printf 'version: 1\nrefs:\n' > "${CRED_FILE}"
    while IFS= read -r variable; do
      [[ -n "${variable}" ]] || continue
      printf '  %s: ' "${variable}" >> "${CRED_FILE}"
      node -e 'process.stdout.write(JSON.stringify(process.argv[1]) + "\n")' \
        "${!variable:-}" >> "${CRED_FILE}"
    done <<< "${api_key_vars}"
    chown "${DSH_USER}:${DSH_USER}" "${CRED_FILE}"
    chmod 0600 "${CRED_FILE}"
  fi
else
  echo "preserved ${CRED_FILE}"
fi

chown -R "${DSH_USER}:${DSH_USER}" "${PROFILE_DIR}"
sudo -u "${DSH_USER}" -H bash -c "cd '${PROFILE_DIR}' && pnpm install --frozen-lockfile=false"

echo "===== 4/7 deployment helpers and environment ====="
mkdir -p "${DEPLOY_DIR}" /etc
cat > "${DEPLOY_DIR}/deploy.env" <<EOF
DSH_USER=${DSH_USER}
DSH_PORT=${DSH_PORT}
TRUSTED_HOST=${TRUSTED_HOST}
EOF
if [[ "${PUBLIC_SETTINGS_OVER_BASIC_AUTH}" == true ]]; then
  install -m 0644 "${REPO_DIR}/nginx/dsh-public-settings-bootstrap.js" \
    "${DEPLOY_DIR}/dsh-public-settings-bootstrap.js"
else
  printf '/* authenticated public settings disabled */\n' \
    > "${DEPLOY_DIR}/dsh-public-settings-bootstrap.js"
  chmod 0644 "${DEPLOY_DIR}/dsh-public-settings-bootstrap.js"
fi
install -m 0755 "${REPO_DIR}/scripts/update.sh" "${DEPLOY_DIR}/update.sh"
install -m 0755 "${REPO_DIR}/scripts/verify.sh" "${DEPLOY_DIR}/verify.sh"
cat > /etc/dsh-web.env <<EOF
TRUSTED_HOST=${TRUSTED_HOST}
EOF
chmod 0600 /etc/dsh-web.env "${DEPLOY_DIR}/deploy.env"

echo "===== 5/7 Nginx TLS and Basic Auth ====="
mkdir -p /etc/nginx/certs
if [[ -f "${DEPLOY_DIR}/tls.env" ]]; then
  # Persisted by setup-letsencrypt.sh so an installer rerun keeps the trusted certificate.
  # shellcheck disable=SC1091
  source "${DEPLOY_DIR}/tls.env"
fi
SSL_CERT_PATH="${SSL_CERT_PATH:-/etc/nginx/certs/selfsigned.crt}"
SSL_KEY_PATH="${SSL_KEY_PATH:-/etc/nginx/certs/selfsigned.key}"
if [[ "${SSL_CERT_PATH}" == /etc/nginx/certs/selfsigned.crt && \
      "${SSL_KEY_PATH}" == /etc/nginx/certs/selfsigned.key && \
      ( ! -s "${SSL_CERT_PATH}" || ! -s "${SSL_KEY_PATH}" ) ]]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "${SSL_KEY_PATH}" -out "${SSL_CERT_PATH}" \
    -subj "/CN=${TRUSTED_HOST}" >/dev/null 2>&1
fi
if [[ ! -s "${SSL_CERT_PATH}" || ! -s "${SSL_KEY_PATH}" ]]; then
  echo "ERROR: configured TLS certificate or key does not exist." >&2
  exit 1
fi
chmod 0600 "${SSL_KEY_PATH}"
printf '%s\n' "${BASIC_AUTH_PASSWORD}" | \
  htpasswd -i -B -c /etc/nginx/.htpasswd "${BASIC_AUTH_USER}" >/dev/null
chmod 0640 /etc/nginx/.htpasswd
chown root:www-data /etc/nginx/.htpasswd

export SSL_CERT_PATH SSL_KEY_PATH DSH_PORT
export DEPLOY_DIR
envsubst '${SSL_CERT_PATH} ${SSL_KEY_PATH} ${DSH_PORT} ${DEPLOY_DIR}' \
  < "${REPO_DIR}/nginx/dsh.conf.tpl" > /etc/nginx/sites-available/dsh
ln -sfn /etc/nginx/sites-available/dsh /etc/nginx/sites-enabled/dsh
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx >/dev/null
systemctl restart nginx

echo "===== 6/7 systemd service ====="
sed -e "s|__DSH_USER__|${DSH_USER}|g" \
    -e "s|__DSH_PORT__|${DSH_PORT}|g" \
    "${REPO_DIR}/systemd/dsh-web.service.tpl" > /etc/systemd/system/dsh-web.service
systemctl daemon-reload
systemctl disable --now dsh-autorestart 2>/dev/null || true
rm -f /etc/systemd/system/dsh-autorestart.service
systemctl enable dsh-web >/dev/null
systemctl restart dsh-web

echo "===== 7/7 deployment verification ====="
"${DEPLOY_DIR}/verify.sh" "${DSH_VERSION}"

echo
echo "DSH ${DSH_VERSION} is ready at https://${TRUSTED_HOST}/"
echo "Basic Auth user: ${BASIC_AUTH_USER}"
echo "Run future checks with: sudo ${DEPLOY_DIR}/verify.sh"
