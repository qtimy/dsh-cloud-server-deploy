#!/usr/bin/env bash
# patch-plugins-key.sh — web-ui 插件 key 兼容补丁
#
# 背景: 较新版本 DSH 将 settings.plugin.item 插槽改为 keyed 协议（要求 key: 而非 id:）。
#       部分社区插件仍用旧写法 id:，需替换为 key: 才能正常加载。
#       本脚本幂等地把 id: "web-ui-plugins" 替换为 key: "web-ui-plugins"。
#
# 用法: bash patch-plugins-key.sh
# 幂等: 已修复时输出 "already OK"，不会重复替换。
set -u

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

# 目标文件（web-ui 全家桶中需兼容的插件），幂等替换
declare -a TARGETS=(
  "${DSH_HOME}/profiles/web/node_modules/@linxin666/dsh-client-ui-web-ui-settings/lib/client.js"
)

STATUS=0
for FILE in "${TARGETS[@]}"; do
  [ -f "$FILE" ] || continue
  FIXED=0
  # 1) 已修复（key: 存在）→ 跳过
  if grep -q 'key: "web-ui-plugins"' "$FILE" 2>/dev/null; then
    echo "  ✅ already OK: ${FILE}"
    continue
  fi
  # 2) 旧写法 id: → key:
  if grep -q 'id: "web-ui-plugins"' "$FILE" 2>/dev/null; then
    sed -i 's/id: "web-ui-plugins"/key: "web-ui-plugins"/g' "$FILE"
    echo "  🔧 patched web-ui-plugins: ${FILE}"
    FIXED=1
  fi
  if [ "$FIXED" = "0" ]; then
    echo "  (unchanged, no old-style id found): ${FILE}"
  fi
done

echo "patch-plugins-key: done (status=$STATUS)"
exit "$STATUS"
