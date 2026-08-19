#!/usr/bin/env bash
# dsh-autorestart.sh — 监听 profile 的 package.json 变更，安装完成后自动重启 dsh-web。
# 由 dsh-autorestart.service 调用；本脚本无敏感信息，可安全入库。
set -u

WATCH="${DSH_HOME:-$HOME/.dsh}/profiles/web/package.json"
LOCK=/run/lock/dsh-autorestart

LAST=0
CUR=$(stat -c %Y "$WATCH" 2>/dev/null || echo 0)
LAST=$CUR
while true; do
  sleep 5
  CUR=$(stat -c %Y "$WATCH" 2>/dev/null || echo 0)
  [ "$CUR" != "$LAST" ] || continue
  LAST=$CUR
  if ! mkdir "$LOCK" 2>/dev/null; then continue; fi
  echo "[dsh-autorestart] package.json changed; waiting for install to finish" | systemd-cat -t dsh-autorestart
  for _ in $(seq 1 18); do
    pgrep -f 'pnpm|npm|git clone' >/dev/null 2>&1 || break
    sleep 10
  done
  sleep 10
  echo "[dsh-autorestart] restarting dsh-web" | systemd-cat -t dsh-autorestart
  systemctl restart dsh-web
  rmdir "$LOCK" 2>/dev/null
  sleep 5
done
