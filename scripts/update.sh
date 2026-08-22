#!/usr/bin/env bash
# Pinned DSH core upgrade with full-tree validation and automatic rollback.
set -Eeuo pipefail

# CREDENTIAL SAFETY BOUNDARY: the updater never opens or changes DSH's
# provider-credential store. Backups and rollback include only the explicit
# non-secret configuration paths named below; DSH keeps its credentials in
# place throughout the core replacement.

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

DSH_USER="${DSH_USER:-dsh}"
DSH_PORT="${DSH_PORT:-3080}"
DSH_HOME_TARGET="/home/${DSH_USER}/.dsh"
PROFILE="${DSH_HOME_TARGET}/profiles/web"
TARGET="${1:-}"

if [[ ! "${TARGET}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "ERROR: provide an exact target version, for example 0.1.1-rc.1." >&2
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
if [[ -f "${PROFILE}/cordis.patch.yml" ]]; then
  cp "${PROFILE}/cordis.patch.yml" "${BACKUP}/profile-cordis.patch.yml"
fi
chown -R "${DSH_USER}:${DSH_USER}" "${BACKUP}"

rollback() {
  local rc=$?
  trap - ERR
  set +e
  echo "FAILED (exit ${rc}); rolling core back to ${OLD_DSH}." >&2
  npm install -g "@deepseek-ai/dsh@${OLD_DSH}"
  cp "${BACKUP}/package.json" "${PROFILE}/package.json"
  cp "${BACKUP}/pnpm-lock.yaml" "${PROFILE}/pnpm-lock.yaml"
  cp "${BACKUP}/settings.yaml" "${DSH_HOME_TARGET}/settings.yaml"
  if [[ -f "${BACKUP}/cordis.patch.yml" ]]; then
    cp "${BACKUP}/cordis.patch.yml" "${DSH_HOME_TARGET}/cordis.patch.yml"
  fi
  if [[ -f "${BACKUP}/profile-cordis.patch.yml" ]]; then
    cp "${BACKUP}/profile-cordis.patch.yml" "${PROFILE}/cordis.patch.yml"
  fi
  chown "${DSH_USER}:${DSH_USER}" \
    "${PROFILE}/package.json" \
    "${PROFILE}/pnpm-lock.yaml" \
    "${DSH_HOME_TARGET}/settings.yaml"
  [[ ! -f "${DSH_HOME_TARGET}/cordis.patch.yml" ]] || \
    chown "${DSH_USER}:${DSH_USER}" "${DSH_HOME_TARGET}/cordis.patch.yml"
  [[ ! -f "${PROFILE}/cordis.patch.yml" ]] || \
    chown "${DSH_USER}:${DSH_USER}" "${PROFILE}/cordis.patch.yml"
  systemctl restart dsh-web
  "${DEPLOY_DIR}/verify.sh" "${OLD_DSH}" || true
  echo "Rollback attempted; inspect journalctl -u dsh-web -n 100." >&2
  exit "${rc}"
}
trap rollback ERR

echo "===== 1/4 verify release ${TARGET} ====="
npm view "@deepseek-ai/dsh@${TARGET}" version >/dev/null

echo "===== 2/4 install a clean pinned core ====="
systemctl stop dsh-web
npm install -g "@deepseek-ai/dsh@${TARGET}"
[[ "$(dsh --version)" == "${TARGET}" ]]

echo "===== 3/4 validate core and profile offline ====="
DSH_VERIFY_RUNTIME=0 "${DEPLOY_DIR}/verify.sh" "${TARGET}"

echo "===== 4/4 restart and verify ====="
systemctl start dsh-web
"${DEPLOY_DIR}/verify.sh" "${TARGET}"

trap - ERR
echo "OK: upgraded ${OLD_DSH} -> ${TARGET}; official core remains unpatched."
echo "Backup: ${BACKUP}"
