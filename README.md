# DSH 部署（web-ui 版）

DeepSeek Harness (DSH) 在云服务器（AWS EC2 等）上的**自用部署模板**：官方 `@deepseek-ai/dsh` 核心 + web-ui 全家桶（`@linxin666/dsh-web-ui-all`，视为本体核心组件）+ HTTPS 公网访问。定位是**不含非必要插件的精简参考版本**，供有需要的人参考复用。

## 特性

- **官方核心 + web-ui**：`@deepseek-ai/dsh` + `@linxin666/dsh-web-ui-all`（aionui 面板 / 任务看板 / git 图 / SSH 运维 / 皮肤等，视为本体核心）。**不包含**非必要第三方插件
- **HTTPS 公网访问**：nginx 443 SSL（默认自签，任何服务器可跑；Let's Encrypt 正式证书为可选）+ Basic Auth + 80 强制跳转 443
- **可重复部署**：`install.sh` 一键从零部署；`update.sh` 升级并重打补丁
- **可重放补丁**：`patch-realtime.sh`（连接保活，幂等）+ `patch-plugins-key.sh`（rc.7 keyed 插槽兼容，幂等）

## 目录结构

```
.
├── install.sh                     # 一键部署（sudo bash install.sh）
├── .env.example                   # 环境配置模板（cp 为 .env 后填写）
├── templates/                     # settings / credentials / profile 模板
├── scripts/
│   ├── patch-realtime.sh          # 实时连接保活补丁（幂等可重放）
│   ├── patch-plugins-key.sh       # rc.7 插件 keyed 插槽兼容补丁（幂等）
│   ├── update.sh                  # 升级 + 重打补丁
│   ├── setup-letsencrypt.sh       # 可选的 Let's Encrypt 正式证书（需域名）
│   └── dsh-autorestart.sh         # 插件安装后自动重启监听
├── nginx/dsh.conf.tpl             # HTTPS + Basic Auth 反代配置
├── systemd/                       # dsh-web / dsh-autorestart 服务单元
└── LICENSE                        # MIT
```

## 快速开始

```bash
# 1. 准备环境配置
cp .env.example .env
# 编辑 .env，填入你自己的服务器地址、访问用户名密码等

# 2. 一键部署（需要 root）
sudo bash install.sh

# 3. 浏览器打开（默认自签证书会告警，确认放行即可）
#    https://<你的服务器地址>/
```

> **部署后的配置**：首次通过浏览器访问后，进入 DSH 的 Web UI 设置页配置你自己的模型 provider、API Key 等。仓库不预设任何模型/密钥配置。

## 正式证书（可选）

`install.sh` 不强制证书方案。如果你有公网域名且想用 Let's Encrypt 免费证书：

```bash
# 前提：域名已解析到本机公网 IP，且 80 端口可被公网访问
sudo bash scripts/setup-letsencrypt.sh <你的域名> [联系邮箱]
```

- 无域名 / 内网 / 纯 IP 服务器：**跳过此步**，直接用自签证书即可
- 已有自有证书（非 LetsEncrypt）：直接把证书放入 `/etc/nginx/certs/`，并修改 `nginx/dsh.conf.tpl` 的 `ssl_certificate*` 路径
- 前置已有反向代理处理 TLS：可停用本模板的 443 server 块，仅保留 dsh-web 的 3080 回源

## 版本升级

1. **查版本**：`npm view @deepseek-ai/dsh version`
2. **升级**：`sudo bash scripts/update.sh <明确版本>`（脚本会锁版安装 → 验证子包一致 → 重打补丁 → 重启 → 健康检查 → 失败自动回滚；不带版本参数会报错退出）
3. **补丁失效**：`patch-realtime.sh` 锚点对不上时，更新其 `EDITS` 锚点以匹配新版源码并重新验证。
4. **同步**：本仓库是唯一真源，服务器 `/opt/dsh-deploy/` 由脚本生成，不是维护目标。

## 安全说明

- **绝不提交 `.env`**（已 `.gitignore`）
- 部署后凭据文件权限收紧（`0600` / `0640`）
- 默认自签证书仅用于加密传输；正式证书走可选的 `scripts/setup-letsencrypt.sh`
