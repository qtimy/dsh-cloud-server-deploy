#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "${sandbox}"' EXIT

CONFIG_FILE="${sandbox}/deploy.conf"
sentinel="${sandbox}/must-not-exist"
printf '%s\n' \
  'TRUSTED_HOST=example.test' \
  "BASIC_AUTH_PASSWORD=\$(touch ${sentinel})" \
  "UNLISTED_SETTING=\$(touch ${sentinel})" \
  > "${CONFIG_FILE}"

# Exercise the exact parser body from install.sh without running the installer.
# shellcheck disable=SC1090
source <(sed -n '/^read_deploy_setting()/,/^}/p' "${ROOT}/install.sh")

[[ "$(read_deploy_setting TRUSTED_HOST '')" == example.test ]]
expected_password="\$(touch ${sentinel})"
[[ "$(read_deploy_setting BASIC_AUTH_PASSWORD '')" == "${expected_password}" ]]
[[ "$(read_deploy_setting DSH_VERSION fallback)" == fallback ]]
[[ -z "${UNLISTED_SETTING+x}" ]]
[[ ! -e "${sentinel}" ]]

echo 'deployment values remain literal and unknown entries stay unexported'
