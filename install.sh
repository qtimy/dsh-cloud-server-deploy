#!/usr/bin/env bash
# install.sh — DSH 一键部署（官方核心 + web-ui 全家桶 + HTTPS 公网访问）
#
# 功能：
#   1. 从 .env 读取密钥/配置（密钥不落库、不落脚本）
#   2. 安装 Node 依赖（pnpm）+ 全局 DSH（官方 @deepseek-ai/dsh，默认锁定版本）
#   3. 生成 ~/.dsh 配置（settings.yaml / .credentials.yaml / profiles/web）
#   4. 安装 web-ui 插件（@linxin666/dsh-web-ui-all）+ key 兼容补丁
#   5. 重放 realtime-connectivity 补丁（patch-realtime.sh）
#   6. 配置 nginx HTTPS + Basic Auth 反向代理（浏览器加密访问）
#   7. 安装 systemd 服务（dsh-web / dsh-autorestart）并健康检查
#
# 用法：sudo bash install.sh   （首次会引导你 cp .env.example .env）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_DIR/.env"

# ---- 0. 前置：必须有 .env ----
if [ ! -f "$ENV_FILE" ]; then
  echo "[install] 未找到 $ENV_FILE，请先:"
  echo "    cp $REPO_DIR/.env.example $ENV_FILE"
  echo "    然后编辑 .env 填入真实密钥与配置。"
  exit 1
fi
# 读取 .env（不 set -a，避免污染；逐项 source）
set -a; source "$ENV_FILE"; set +a

# ---- 版本参数（必须从 .env 提供，不提供默认值，避免硬编码过期版本）----
DSH_VERSION="${DSH_VERSION:-}"
WEB_UI_ALL_VERSION="${WEB_UI_ALL_VERSION:-}"
DSH_PORT="${DSH_PORT:-3080}"
DSH_USER="${DSH_USER:-ubuntu}"
DSH_HOME_TARGET="/home/${DSH_USER}/.dsh"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/dsh-deploy}"

if [ "$(id -u)" -ne 0 ]; then
  echo "[install] 需要 root 权限（写入 /etc/nginx、/etc/systemd、全局 npm）。请用 sudo bash install.sh"
  exit 1
fi
# 版本必填：避免硬编码过期版本号，复制 .env.example 后必须显式填写
# 占位符（<...>）或空值均视为未填写
if [ -z "$DSH_VERSION" ] || [[ "$DSH_VERSION" == *"<"*">"* ]]; then
  echo "[install] 错误：请先在 .env 中填写 DSH_VERSION（例如 npm view @deepseek-ai/dsh version 查最新）。" >&2
  exit 1
fi
if [ -z "$WEB_UI_ALL_VERSION" ] || [[ "$WEB_UI_ALL_VERSION" == *"<"*">"* ]]; then
  echo "[install] 错误：请先在 .env 中填写 WEB_UI_ALL_VERSION（例如 npm view @linxin666/dsh-web-ui-all version 查最新）。" >&2
  exit 1
fi

echo "===== [install] 开始 DSH web-ui 部署 ====="

# ---- 1. 安装系统依赖 ----
echo "===== 1/7 安装系统依赖 (node/npm/pnpm/nginx/openssl) ====="
export DEBIAN_FRONTEND=noninteractive
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
if ! command -v pnpm >/dev/null 2>&1; then
  npm install -g pnpm
fi
apt-get install -y nginx openssl curl >/dev/null 2>&1 || true

# ---- 2. 安装 DSH 核心（官方包）----
echo "===== 2/7 安装 DSH 核心 (@deepseek-ai/dsh) ====="
if [ "${DSH_VERSION}" = "latest" ]; then
  npm install -g @deepseek-ai/dsh@latest
else
  npm install -g "@deepseek-ai/dsh@${DSH_VERSION}"
fi
echo "dsh = $(dsh --version 2>/dev/null || echo unknown)"

# ---- 3. 生成 ~/.dsh 配置 ----
echo "===== 3/7 生成 ~/.dsh 配置 ====="
mkdir -p "${DSH_HOME_TARGET}"/{profiles/web,sessions,plugins,storages,marketplace}
chown -R "${DSH_USER}:${DSH_USER}" "${DSH_HOME_TARGET}"

# 3a. credentials（通用：从 .env 自动发现所有 *_API_KEY 变量，映射到 credentials.yaml，写成 0600）
CRED_FILE="${DSH_HOME_TARGET}/.credentials.yaml"
cp "$REPO_DIR/templates/credentials.yaml.tpl" "$CRED_FILE"
# 从 .env 提取所有 *_API_KEY 变量名，逐个映射（值不落明文模板，仅在此写入最终文件）
API_KEY_VARS="$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*_API_KEY=' "$ENV_FILE" 2>/dev/null | sed 's/=$//' | sort -u)"
if [ -n "$API_KEY_VARS" ]; then
  : > "$CRED_FILE"
  for VAR in $API_KEY_VARS; do
    VAL="${!VAR:-}"
    printf '%s: %s\n' "$VAR" "$VAL" >> "$CRED_FILE"
  done
fi
chmod 600 "$CRED_FILE"
chown "${DSH_USER}:${DSH_USER}" "$CRED_FILE"

# 3b. settings.yaml
cp "$REPO_DIR/templates/settings.yaml.tpl" "${DSH_HOME_TARGET}/settings.yaml"
chmod 600 "${DSH_HOME_TARGET}/settings.yaml"
chown "${DSH_USER}:${DSH_USER}" "${DSH_HOME_TARGET}/settings.yaml"

# 3c. profiles/web/{package.json,cordis.patch.yml,pnpm-workspace.yaml}
PROFILE_DIR="${DSH_HOME_TARGET}/profiles/web"
cp "$REPO_DIR/templates/profile-package.json.tpl"   "$PROFILE_DIR/package.json"
cp "$REPO_DIR/templates/cordis.patch.yml.tpl"        "$PROFILE_DIR/cordis.patch.yml"
cp "$REPO_DIR/templates/pnpm-workspace.yaml.tpl"     "$PROFILE_DIR/pnpm-workspace.yaml"
# envsubst 渲染模板中残留的 ${...}（干净版基本无占位，但保险起见）
command -v envsubst >/dev/null 2>&1 && for f in "$PROFILE_DIR"/package.json "$PROFILE_DIR"/cordis.patch.yml "$PROFILE_DIR"/pnpm-workspace.yaml; do
  envsubst < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
chown -R "${DSH_USER}:${DSH_USER}" "$PROFILE_DIR"

# 3d. 安装 profile 依赖
echo "      安装 profile 依赖 (pnpm install)..."
sudo -u "$DSH_USER" bash -c "cd '$PROFILE_DIR' && pnpm install --frozen-lockfile=false 2>/dev/null || pnpm install"

# 3e. web-ui 插件 key 兼容补丁（rc.7 起 settings.plugin.item 为 keyed 协议，
#     部分旧插件需 id: → key:）
if [ -f "$SCRIPT_DIR/patch-plugins-key.sh" ]; then
  echo "      应用 web-ui key 兼容补丁..."
  sudo -u "$DSH_USER" DSH_HOME="$DSH_HOME_TARGET" bash "$SCRIPT_DIR/patch-plugins-key.sh"
fi

# ---- 4. 重放 realtime-connectivity 补丁 ----
echo "===== 4/7 重放 realtime 补丁 ====="
bash "$SCRIPT_DIR/patch-realtime.sh"

# ---- 5. 生成 dsh-web.env / deploy.env ----
echo "===== 5/7 生成环境文件 ====="
mkdir -p /etc
# dsh-web.env 只写 TRUSTED_HOST；模型/密钥统一走 ~/.dsh/.credentials.yaml（见 3a）
cat > /etc/dsh-web.env <<EOF
TRUSTED_HOST=${TRUSTED_HOST}
EOF
chmod 600 /etc/dsh-web.env

cat > "$DEPLOY_DIR/env-placeholder" <<EOF
# (占位) deploy.env 由 install.sh 生成到 /opt/dsh-deploy/deploy.env
EOF
mkdir -p "$DEPLOY_DIR"
cat > "$DEPLOY_DIR/deploy.env" <<EOF
DSH_USER=${DSH_USER}
DSH_PORT=${DSH_PORT}
EOF
cp "$SCRIPT_DIR"/patch-realtime.sh "$DEPLOY_DIR/patch-realtime.sh"
cp "$SCRIPT_DIR"/patch-plugins-key.sh "$DEPLOY_DIR/patch-plugins-key.sh"
cp "$SCRIPT_DIR"/update.sh "$DEPLOY_DIR/update.sh"
cp "$SCRIPT_DIR"/dsh-autorestart.sh "$DEPLOY_DIR/dsh-autorestart.sh"
chmod +x "$DEPLOY_DIR"/*.sh

# ---- 6. nginx HTTPS + Basic Auth ----
echo "===== 6/7 配置 nginx HTTPS + Basic Auth ====="
mkdir -p /etc/nginx/certs
# 默认自签证书（零假设，任何服务器可跑）。正式证书见 scripts/setup-letsencrypt.sh（可选，需域名）。
SSL_CERT_PATH="/etc/nginx/certs/selfsigned.crt"
SSL_KEY_PATH="/etc/nginx/certs/selfsigned.key"
if [ ! -f "$SSL_CERT_PATH" ] || [ ! -f "$SSL_KEY_PATH" ]; then
  echo "      生成自签证书（如需正式证书，见 scripts/setup-letsencrypt.sh）"
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$SSL_KEY_PATH" \
    -out "$SSL_CERT_PATH" \
    -subj "/CN=${TRUSTED_HOST}" >/dev/null 2>&1
fi
# htpasswd
printf '%s:%s\n' "${BASIC_AUTH_USER:-dsh}" "$(openssl passwd -apr1 "${BASIC_AUTH_PASSWORD:-change-me}")" > /etc/nginx/.htpasswd
chmod 640 /etc/nginx/.htpasswd

# 渲染 nginx 配置
export SSL_CERT_PATH SSL_KEY_PATH DSH_PORT
envsubst < "$REPO_DIR/nginx/dsh.conf.tpl" > /etc/nginx/sites-available/dsh
ln -sf /etc/nginx/sites-available/dsh /etc/nginx/sites-enabled/dsh
# 移除默认站点避免冲突
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl enable --now nginx || systemctl reload nginx

# ---- 7. systemd 服务 ----
echo "===== 7/7 安装 systemd 服务 ====="
sed -e "s|__DSH_USER__|${DSH_USER}|g" \
    -e "s|__DSH_PORT__|${DSH_PORT}|g" \
    "$REPO_DIR/systemd/dsh-web.service.tpl" > /etc/systemd/system/dsh-web.service
sed -e "s|__DSH_USER__|${DSH_USER}|g" \
    -e "s|__DEPLOY_DIR__|${DEPLOY_DIR}|g" \
    "$REPO_DIR/systemd/dsh-autorestart.service.tpl" > /etc/systemd/system/dsh-autorestart.service
systemctl daemon-reload
systemctl enable --now dsh-web dsh-autorestart

# ---- 健康检查 ----
sleep 6
echo "===== 健康检查 ====="
systemctl is-active dsh-web
CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${DSH_PORT}/" 2>/dev/null || echo 000)"
echo "dsh-web http_code = ${CODE}"
if [ "${CODE}" = "200" ] || [ "${CODE}" = "302" ] || [ "${CODE}" = "401" ]; then
  echo "OK: dsh-web 已就绪"
else
  echo "警告：健康检查未通过，查看日志: journalctl -u dsh-web -n 50"
fi

echo ""
echo "===== 部署完成 ====="
echo "供浏览器加密访问的地址: https://${TRUSTED_HOST}/"
echo "登录账号: ${BASIC_AUTH_USER:-dsh}  （密码见 .env 的 BASIC_AUTH_PASSWORD）"
echo "提示: 自签证书会触发浏览器告警，可替换 /etc/nginx/certs/ 下为真实证书。"
