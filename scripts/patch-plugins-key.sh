#!/usr/bin/env bash
# Plugin-owned compatibility for older @linxin666/dsh-web-ui releases.
# This script never modifies the global @deepseek-ai/dsh installation.
set -Eeuo pipefail

DSH_HOME="${DSH_HOME:-${HOME}/.dsh}"
FILE="${DSH_HOME}/profiles/web/node_modules/@linxin666/dsh-client-ui-web-ui-settings/lib/client.js"

if [[ ! -f "${FILE}" ]]; then
  echo "patch-plugins-key: web-ui settings plugin is not installed; skipped"
  exit 0
fi
if grep -q 'key: "web-ui-plugins"' "${FILE}"; then
  echo "patch-plugins-key: already compatible"
  exit 0
fi
if ! grep -q 'id: "web-ui-plugins"' "${FILE}"; then
  echo "patch-plugins-key: ERROR: unknown plugin slot shape in ${FILE}" >&2
  exit 1
fi

sed -i 's/id: "web-ui-plugins"/key: "web-ui-plugins"/g' "${FILE}"
grep -q 'key: "web-ui-plugins"' "${FILE}"
echo "patch-plugins-key: patched plugin-owned settings slot"
