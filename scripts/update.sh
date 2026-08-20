#!/usr/bin/env bash
# Pinned DSH core upgrade with full-tree validation and automatic rollback.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run as root: sudo $0 <exact-version>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/deploy.env" ]]; then
  DEPLOY_DIR="${SCRIPT_DIR}"
elif [[ -f "$(dirname "${SCRIPT_DIR}")/deploy.env" ]]; then
  DEPLOY_DIR="$(dirname "${SCRIPT_DIR}")"
else
  DEPLOY_DIR="${SCRIPT_DIR}"
fi
# shellcheck disable=SC1091
[[ -f "${DEPLOY_DIR}/deploy.env" ]] && source "${DEPLOY_DIR}/deploy.env"

DSH_USER="${DSH_USER:-ubuntu}"
DSH_PORT="${DSH_PORT:-3080}"
DSH_HOME_TARGET="/home/${DSH_USER}/.dsh"
PROFILE="${DSH_HOME_TARGET}/profiles/web"
TARGET="${1:-}"

if [[ ! "${TARGET}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "ERROR: provide an exact target version, for example 0.1.0-rc.8." >&2
  exit 2
fi

OLD_DSH="$(dsh --version)"
if [[ "${OLD_DSH}" == "${TARGET}" ]]; then
  echo "DSH is already ${TARGET}; verifying the current deployment."
  "${DEPLOY_DIR}/verify.sh" "${TARGET}"
  exit 0
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="/home/${DSH_USER}/dsh-upgrades/${STAMP}-${OLD_DSH}-to-${TARGET}"
mkdir -p "${BACKUP}"
cp "${PROFILE}/package.json" "${BACKUP}/package.json"
cp "${PROFILE}/pnpm-lock.yaml" "${BACKUP}/pnpm-lock.yaml"
cp "${DSH_HOME_TARGET}/settings.yaml" "${BACKUP}/settings.yaml"
if [[ -f "${DSH_HOME_TARGET}/cordis.patch.yml" ]]; then
  cp "${DSH_HOME_TARGET}/cordis.patch.yml" "${BACKUP}/cordis.patch.yml"
fi
chown -R "${DSH_USER}:${DSH_USER}" "${BACKUP}"

rollback() {
  local rc=$?
  trap - ERR
  set +e
  echo "FAILED (exit ${rc}); rolling core back to ${OLD_DSH}." >&2
  npm install -g "@deepseek-ai/dsh@${OLD_DSH}"
  if [[ -x "${DEPLOY_DIR}/patch-plugins-key.sh" ]]; then
    sudo -u "${DSH_USER}" -H env DSH_HOME="${DSH_HOME_TARGET}" \
      bash "${DEPLOY_DIR}/patch-plugins-key.sh"
  fi
  systemctl restart dsh-web
  "${DEPLOY_DIR}/verify.sh" "${OLD_DSH}" || true
  echo "Rollback attempted; inspect journalctl -u dsh-web -n 100." >&2
  exit "${rc}"
}
trap rollback ERR

echo "===== 1/5 verify release ${TARGET} ====="
npm view "@deepseek-ai/dsh@${TARGET}" version >/dev/null

echo "===== 2/5 install a clean pinned core ====="
systemctl stop dsh-web
npm install -g "@deepseek-ai/dsh@${TARGET}"
[[ "$(dsh --version)" == "${TARGET}" ]]

echo "===== 3/5 validate core and profile offline ====="
DSH_VERIFY_RUNTIME=0 "${DEPLOY_DIR}/verify.sh" "${TARGET}"

echo "===== 4/5 apply plugin-owned compatibility only ====="
if [[ -x "${DEPLOY_DIR}/patch-plugins-key.sh" ]]; then
  sudo -u "${DSH_USER}" -H env DSH_HOME="${DSH_HOME_TARGET}" \
    bash "${DEPLOY_DIR}/patch-plugins-key.sh"
fi
sudo -u "${DSH_USER}" -H dsh --profile web --dump-config >/dev/null

echo "===== 5/5 restart and verify ====="
systemctl start dsh-web
"${DEPLOY_DIR}/verify.sh" "${TARGET}"

trap - ERR
echo "OK: upgraded ${OLD_DSH} -> ${TARGET}; official core remains unpatched."
echo "Backup: ${BACKUP}"
