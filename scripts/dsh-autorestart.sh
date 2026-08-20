#!/usr/bin/env bash
# Restart dsh-web after an official plugin command changes the profile manifest.
set -Eeuo pipefail

: "${DSH_HOME:?DSH_HOME must point to the service user .dsh directory}"
WATCH="${DSH_HOME}/profiles/web/package.json"
LOCK=/run/lock/dsh-autorestart.lock

signature() {
  stat -c '%Y:%s:%i' "${WATCH}" 2>/dev/null || printf 'missing'
}

last="$(signature)"
while true; do
  sleep 5
  current="$(signature)"
  [[ "${current}" != "${last}" ]] || continue
  last="${current}"

  exec 9>"${LOCK}"
  flock -n 9 || continue
  logger -t dsh-autorestart 'profile package.json changed; waiting for package manager'
  for _ in $(seq 1 36); do
    pgrep -f '[p]npm|[n]pm|[g]it clone' >/dev/null 2>&1 || break
    sleep 5
  done
  sleep 5
  logger -t dsh-autorestart 'restarting dsh-web'
  systemctl restart dsh-web
  flock -u 9
done
