#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

while IFS= read -r -d '' script; do
  bash -n "${script}"
done < <(find . -type f -name '*.sh' -print0)

node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' \
  templates/profile-package.json.tpl

grep -q 'REPO_DIR="${SCRIPT_DIR}"' install.sh
grep -q 'DSH_VERSION=0.1.0-rc.8' .env.example
grep -q 'ExecStart=/bin/bash __DEPLOY_DIR__/dsh-autorestart.sh' \
  systemd/dsh-autorestart.service.tpl
grep -q 'Environment=DSH_HOME=/home/__DSH_USER__/.dsh' \
  systemd/dsh-autorestart.service.tpl
grep -q 'proxy_set_header Authorization "";' nginx/dsh.conf.tpl

if grep -Rqs 'patch-realtime' README.md install.sh scripts systemd templates; then
  echo 'core patch reference found in the deployment path' >&2
  exit 1
fi
if grep -Rqs '@deepseek-ai/dsh@latest' install.sh scripts; then
  echo 'implicit latest core install found' >&2
  exit 1
fi

echo 'static smoke checks passed'
