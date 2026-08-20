#!/usr/bin/env bash
# Verify core consistency, profile/plugin integrity, and runtime health.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: run as root: sudo $0 [expected-version]" >&2
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
EXPECTED_VERSION="${1:-$(dsh --version)}"
DSH_VERIFY_RUNTIME="${DSH_VERIFY_RUNTIME:-1}"

echo "[verify] DSH core ${EXPECTED_VERSION}"
[[ "$(dsh --version)" == "${EXPECTED_VERSION}" ]]
GLOBAL_ROOT="$(npm root -g)"
EXPECTED_VERSION="${EXPECTED_VERSION}" GLOBAL_ROOT="${GLOBAL_ROOT}" node <<'NODE'
const fs = require('node:fs')
const path = require('node:path')
const root = path.join(process.env.GLOBAL_ROOT, '@deepseek-ai/dsh/node_modules/@deepseek-ai')
const expected = process.env.EXPECTED_VERSION
const mismatches = []
let count = 0
for (const entry of fs.readdirSync(root)) {
  const file = path.join(root, entry, 'package.json')
  if (!fs.existsSync(file)) continue
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'))
  if (!pkg.name?.startsWith('@deepseek-ai/dsh')) continue
  count += 1
  if (pkg.version !== expected) mismatches.push(`${pkg.name}@${pkg.version}`)
}
if (mismatches.length) throw new Error(`mixed DSH tree: ${mismatches.join(', ')}`)
console.log(`[verify] ${count} DSH packages match ${expected}`)
NODE

echo "[verify] profile and plugin links"
node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
  "${PROFILE}/package.json"
profile_files=("${PROFILE}/package.json")
[[ -f "${PROFILE}/pnpm-lock.yaml" ]] && profile_files+=("${PROFILE}/pnpm-lock.yaml")
if grep -Rqs 'link:/tmp' "${profile_files[@]}"; then
  echo "ERROR: volatile link:/tmp plugin dependency found." >&2
  exit 1
fi
PROFILE="${PROFILE}" node <<'NODE'
const fs = require('node:fs')
const path = require('node:path')
const profile = process.env.PROFILE
const manifest = JSON.parse(fs.readFileSync(path.join(profile, 'package.json'), 'utf8'))
for (const [name, spec] of Object.entries(manifest.dependencies ?? {})) {
  const file = path.join(profile, 'node_modules', ...name.split('/'), 'package.json')
  if (!fs.existsSync(file)) throw new Error(`missing plugin dependency: ${name} (${spec})`)
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'))
  console.log(`[verify] plugin ${name}@${pkg.version} (${spec})`)
}
NODE

config_file="$(mktemp)"
config_errors="$(mktemp)"
trap 'rm -f "${config_file}" "${config_errors}"' EXIT
sudo -u "${DSH_USER}" -H dsh --profile web --dump-config \
  > "${config_file}" 2> "${config_errors}"
if [[ -s "${config_errors}" ]]; then
  cat "${config_errors}" >&2
  echo "ERROR: DSH generated configuration contains warnings/errors." >&2
  exit 1
fi
echo "[verify] generated plugin configuration is clean"

if [[ "${DSH_VERIFY_RUNTIME}" == 0 ]]; then
  echo "[verify] offline checks complete"
  exit 0
fi

echo "[verify] services and upstream"
for _ in $(seq 1 15); do
  if systemctl is-active --quiet dsh-web && \
     curl -fsS -o /dev/null "http://127.0.0.1:${DSH_PORT}/"; then
    break
  fi
  sleep 2
done
systemctl is-active --quiet dsh-web
systemctl is-active --quiet nginx
curl -fsS -o /dev/null "http://127.0.0.1:${DSH_PORT}/"

pid_before="$(systemctl show -p MainPID --value dsh-web)"
sleep 10
pid_after="$(systemctl show -p MainPID --value dsh-web)"
if [[ "${pid_before}" == 0 || "${pid_before}" != "${pid_after}" ]]; then
  echo "ERROR: dsh-web restarted during the stability check." >&2
  exit 1
fi

echo "[verify] third-party client bundles"
while IFS= read -r package_name; do
  [[ -n "${package_name}" ]] || continue
  code="$(curl -sS -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:${DSH_PORT}/plugins/${package_name}/client.js")"
  if [[ "${code}" != 200 ]]; then
    echo "ERROR: client bundle ${package_name} returned HTTP ${code}." >&2
    exit 1
  fi
  echo "[verify] client ${package_name}: HTTP 200"
done < <(PROFILE="${PROFILE}" node <<'NODE'
const fs = require('node:fs')
const path = require('node:path')
const root = path.join(process.env.PROFILE, 'node_modules')
const names = new Set()
const inspect = (dir) => {
  const file = path.join(dir, 'package.json')
  if (!fs.existsSync(file)) return
  const pkg = JSON.parse(fs.readFileSync(file, 'utf8'))
  if (pkg.name && pkg.dsh?.client && !pkg.name.startsWith('@deepseek-ai/')) names.add(pkg.name)
}
if (!fs.existsSync(root)) process.exit(0)
for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
  if (entry.name.startsWith('.')) continue
  const full = path.join(root, entry.name)
  if (entry.name.startsWith('@')) {
    for (const child of fs.readdirSync(full, { withFileTypes: true })) {
      if (child.isDirectory() || child.isSymbolicLink()) inspect(path.join(full, child.name))
    }
  } else if (entry.isDirectory() || entry.isSymbolicLink()) inspect(full)
}
for (const name of [...names].sort()) console.log(name)
NODE
)

active_since="$(systemctl show -p ActiveEnterTimestamp --value dsh-web)"
if journalctl -u dsh-web --since "${active_since}" --no-pager 2>/dev/null | \
   grep -Eqi 'plugin tree failed|duplicate prefix route|MODULE_NOT_FOUND|keyed slot.*requires|Main process exited'; then
  echo "ERROR: current DSH boot contains a runtime/plugin failure." >&2
  exit 1
fi

echo "[verify] OK: clean core, valid plugins, stable PID ${pid_after}, upstream HTTP 200"
