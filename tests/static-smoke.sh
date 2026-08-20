#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

while IFS= read -r -d '' script; do
  bash -n "${script}"
done < <(find . -type f -name '*.sh' -print0)

node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
  templates/profile-package.json.tpl
while IFS= read -r -d '' package; do
  node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' "${package}"
done < <(find plugins -type f -name package.json -print0)
while IFS= read -r -d '' client; do
  node --check "${client}"
done < <(find plugins -type f -name '*.js' -print0)
node tests/public-settings-bootstrap.mjs

grep -q 'REPO_DIR="${SCRIPT_DIR}"' install.sh
grep -q 'DSH_VERSION=0.1.0-rc.8' .env.example
grep -q 'SHIFT_ROUTER_ENABLED=true' .env.example
grep -q 'ExecStart=/bin/bash __DEPLOY_DIR__/dsh-autorestart.sh' \
  systemd/dsh-autorestart.service.tpl
grep -q 'Environment=DSH_HOME=/home/__DSH_USER__/.dsh' \
  systemd/dsh-autorestart.service.tpl
grep -q 'proxy_set_header Authorization "";' nginx/dsh.conf.tpl
grep -q 'alias ${DEPLOY_DIR}/dsh-public-settings-bootstrap.js;' nginx/dsh.conf.tpl
grep -q "sub_filter '</script>'" nginx/dsh.conf.tpl
grep -q 'allow 127.0.0.1;' nginx/dsh.conf.tpl
if grep -q 'assets|plugins' nginx/dsh.conf.tpl; then
  echo 'plugin bundles must not receive immutable asset caching' >&2
  exit 1
fi
if git ls-files --error-unmatch plugins/dsh-nginx-auth-settings/package.json >/dev/null 2>&1; then
  echo 'obsolete dsh-nginx-auth-settings must not be committed' >&2
  exit 1
fi
test -f plugins/dsh-shift-router/src/deployment-catalog.ts
test -f plugins/dsh-shift-router/src/subagent-router.ts
node -e '
  const p = require("./plugins/dsh-shift-router/package.json");
  if (p.version !== "0.6.1") throw new Error(`unexpected Shift-Router version ${p.version}`);
  for (const [name, version] of Object.entries(p.dependencies)) {
    if (name.startsWith("@deepseek-ai/dsh-") && version !== "0.1.0-rc.8") {
      throw new Error(`${name} is not pinned to RC.8: ${version}`)
    }
  }
'
grep -q 'dsh-agent-orchestrator' scripts/verify.sh
grep -q '\[class\*="_toggleCluster"\]' \
  plugins/dsh-better-sidebar-skin-yield/lib/client.js

if grep -Rqs 'patch-realtime' README.md install.sh scripts systemd templates; then
  echo 'core patch reference found in the deployment path' >&2
  exit 1
fi
if grep -Rqs '@deepseek-ai/dsh@latest' install.sh scripts; then
  echo 'implicit latest core install found' >&2
  exit 1
fi

echo 'static smoke checks passed'
