#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

while IFS= read -r -d '' script; do
  bash -n "${script}"
done < <(find . -type f -name '*.sh' -print0)

node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
  templates/profile-package.json.tpl
node tests/public-settings-bootstrap.mjs
node tests/security-contract.mjs
bash tests/deploy-env-literal.sh

grep -q 'REPO_DIR="${SCRIPT_DIR}"' install.sh
grep -q 'DSH_VERSION=0.1.1-rc.2' deploy.conf.example
test -s README.zh-CN.md
grep -q 'proxy_set_header Authorization "";' nginx/dsh.conf.tpl
grep -q 'alias ${DEPLOY_DIR}/dsh-public-settings-bootstrap.js;' nginx/dsh.conf.tpl
grep -q "sub_filter '</script>'" nginx/dsh.conf.tpl
grep -q 'allow 127.0.0.1;' nginx/dsh.conf.tpl
if grep -q 'assets|plugins' nginx/dsh.conf.tpl; then
  echo 'plugin bundles must not receive immutable asset caching' >&2
  exit 1
fi
if [[ -d plugins ]]; then
  echo 'the HTTPS-only deployment repository must not bundle plugins' >&2
  exit 1
fi
if grep -RqsE '(dsh-shift-router|dsh-agent-orchestrator|dsh-better-sidebar|dsh-web-ui-all)' \
  install.sh scripts templates systemd; then
  echo 'plugin-specific deployment logic found' >&2
  exit 1
fi

if grep -Rqs 'patch-realtime' README.md install.sh scripts systemd templates; then
  echo 'core patch reference found in the deployment path' >&2
  exit 1
fi
if grep -Rqs '@deepseek-ai/dsh@latest' install.sh scripts; then
  echo 'implicit latest core install found' >&2
  exit 1
fi

echo 'static smoke checks passed'
