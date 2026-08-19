#!/usr/bin/env bash
# update.sh — DSH 版本升级（锁死版本，防止 caret 范围自动拉新破坏插件）
#
# 说明：@latest / 未锁定的 caret 版本范围会在升级时连带拉高众多 dsh-* 子包，
#   可能造成社区插件（id:/key: 插槽协议）不兼容。
#   因此本脚本【必须显式指定目标版本】，拒绝默认升级。
#
# 用法:
#   sudo bash update.sh <version>     # 升级到指定版本（推荐，先查 npm view）
#   sudo bash update.sh               # 报错退出，提示必须带版本
#
# 流程: 记旧版 → 锁版安装 → 验证子包一致 → 重打补丁 → 插件 key 修复 → 重启 → 健康检查 → 失败回滚
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# 读取部署变量（DSH_USER/DSH_PORT 等）
# shellcheck disable=SC1090
[ -f "$DEPLOY_DIR/deploy.env" ] && . "$DEPLOY_DIR/deploy.env"

DSH_USER="${DSH_USER:-ubuntu}"
DSH_PORT="${DSH_PORT:-3080}"

# ---- 0. 必须显式指定版本 ----
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "ERROR: 必须显式指定目标版本，例如:" >&2
  echo "  sudo bash update.sh <version>" >&2
  echo "当前最新: $(npm view @deepseek-ai/dsh version 2>/dev/null || echo '?')" >&2
  echo "已安装:   $(dsh --version 2>/dev/null || echo '?')" >&2
  echo "提示: 升级前请确认已安装的社区插件兼容该版本。" >&2
  exit 1
fi

# 校验版本号格式（防注入）
if [[ ! "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "ERROR: 版本号格式非法: $TARGET" >&2
  exit 1
fi

echo "===== 1/6 记录当前版本 ====="
OLD_DSH="$(dsh --version 2>/dev/null || echo '未知')"
echo "当前 = ${OLD_DSH}"
echo "目标 = ${TARGET}"
if [ "${OLD_DSH}" = "${TARGET}" ]; then
  echo "已是目标版本，无需升级。"
  exit 0
fi

echo "===== 2/6 锁版安装 @deepseek-ai/dsh@${TARGET} ====="
npm install -g "@deepseek-ai/dsh@${TARGET}"
echo "dsh now = $(dsh --version 2>/dev/null || echo unknown)"

echo "===== 3/6 验证关键子包版本一致性 ====="
# 若外壳是新版但子包是旧版（caret 范围解析不一致），立即中止，避免半吊子升级
EXPECT="$TARGET"
MISMATCH=0
for SUB in dsh-web-app dsh-client-ui-slots dsh-client-ui-settings-plugins dsh-host-apiproxy; do
  SUB_V="$(cat "/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/${SUB}/package.json" 2>/dev/null | grep '"version"' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?' || echo '缺失')"
  if [ "${SUB_V}" != "${EXPECT}" ]; then
    echo "  ⚠️  子包 ${SUB} 版本 = ${SUB_V}，与目标 ${EXPECT} 不一致"
    MISMATCH=1
  else
    echo "  ✅ ${SUB} = ${SUB_V}"
  fi
done
if [ "${MISMATCH}" = "1" ]; then
  echo "ERROR: 关键子包版本不一致。不要继续使用本脚本降级/混装。" >&2
  echo "建议: 整树重装 —— npm uninstall -g @deepseek-ai/dsh && npm install -g @deepseek-ai/dsh@${TARGET}" >&2
  exit 1
fi

echo "===== 4/6 重放 realtime 补丁 ====="
bash "$SCRIPT_DIR/patch-realtime.sh" || echo "  (realtime patches failed/skipped — inspect $SCRIPT_DIR/patch-realtime.sh)"

echo "===== 4.5/6 插件 key 兼容补丁 ====="
if [ -f "$SCRIPT_DIR/patch-plugins-key.sed" ]; then
  bash "$SCRIPT_DIR/patch-plugins-key.sh" || echo "  (插件 key 补丁 failed/skipped)"
else
  echo "  (未找到 patch-plugins-key.sh，跳过)"
fi

echo "===== 5/6 重启 + 健康检查 ====="
systemctl restart dsh-web
sleep 8
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${DSH_PORT}/" 2>/dev/null || echo 000)"
echo "http_code = ${HTTP_CODE}"
if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ] || [ "${HTTP_CODE}" = "401" ]; then
  echo "OK: dsh-web 健康"
else
  echo "FAILED: dsh-web 健康检查失败，回滚到 ${OLD_DSH}"
  npm install -g "@deepseek-ai/dsh@${OLD_DSH}"
  systemctl restart dsh-web
  echo "已回滚。日志: journalctl -u dsh-web -n 50"
  exit 1
fi

echo "===== 6/6 插件加载检查（keyed slot 报错检测）====="
sleep 3
if journalctl -u dsh-web --since "1 minute ago" --no-pager 2>/dev/null | grep -q 'keyed slot.*requires options.key'; then
  echo "⚠️  检测到 keyed slot 报错——插件未兼容。请运行插件 key 补丁或回滚。"
else
  echo "✅ 无 keyed slot 报错，插件加载正常"
fi

echo "Done. 硬刷新浏览器 (Ctrl/Cmd+Shift+R)。"