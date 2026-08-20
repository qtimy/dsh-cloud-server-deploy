# DSH 云服务器部署

[English](README.md) | 简体中文

这是一个精简的公开部署层，用于在 Ubuntu 或 Debian 上通过 HTTPS 暴露
DeepSeek Harness（DSH）官方 Web 应用。

本仓库只包含：

- 固定精确版本的官方 `@deepseek-ai/dsh` 核心；
- 官方 `dsh-base` 与 `dsh-web-app` profile bundle；
- 仅监听回环地址的 systemd 服务；
- Nginx TLS、Basic Auth、WebSocket/SSE 反向代理及 HTTP 到 HTTPS 重定向；
- 可选的 RC.8 浏览器设置“认证边缘”兼容桥；
- 固定版本的更新、回滚与验证工具。

本仓库不包含或安装社区插件、提供方选择、模型路由规则、API Key、主机名、
IP 地址、证书或某台部署机器的专用配置。插件由独立的插件集合仓库维护。

## 边界

```text
浏览器
  -> HTTPS + Basic Auth
  -> Nginx :443
  -> 回环 HTTP
  -> 官方 DSH Web profile :3080
       - @deepseek-ai/dsh-base
       - @deepseek-ai/dsh-web-app
```

安装器绝不会修改全局安装的 DSH 包。RC.8 浏览器设置桥只由 Nginx 注入已经
通过 Basic Auth 的页面。DSH 本身始终绑定到 `127.0.0.1`。

## 安装

```bash
git clone https://github.com/<github-account>/dsh-cloud-server-deploy.git
cd dsh-cloud-server-deploy
cp .env.example .env
# 设置 TRUSTED_HOST 与 BASIC_AUTH_PASSWORD。
sudo bash install.sh
```

打开 `https://<TRUSTED_HOST>/`。默认自签名证书可以加密连接，但浏览器会显示
警告。DNS 与 80 端口准备好后，可获取受信任证书：

```bash
sudo bash scripts/setup-letsencrypt.sh dsh.example.com admin@example.com
```

## 配置

`.env` 已被有意忽略，公开模板中只使用占位值。

- `DSH_VERSION`：DSH 精确版本；拒绝版本范围和 `latest`。
- `TRUSTED_HOST`：DSH 接受的公开主机名或 IP。
- `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD`：Nginx 登录凭据。
- `PUBLIC_SETTINGS_OVER_BASIC_AUTH`：启用 RC.8 认证边缘设置桥。
- `DSH_USER`：无特权服务账户，默认为 `dsh`。
- `DSH_PORT`：回环端口，默认为 `3080`。
- `DEPLOY_DIR`：由 root 管理的辅助目录，默认为 `/opt/dsh-deploy`。
- `SSL_CERT_PATH` / `SSL_KEY_PATH`：可选的现有证书路径。

可以在本地 `.env` 中加入以 `_API_KEY` 结尾的变量。首次安装时，它们会被
写入服务账户权限为 0600 的 DSH 凭据文件，绝不会写进本仓库。

## 更新与检查

必须指定精确目标版本：

```bash
sudo /opt/dsh-deploy/update.sh 0.1.0-rc.8
sudo /opt/dsh-deploy/verify.sh
```

更新器会停止 DSH、安装精确版本、验证完整的官方 DSH 依赖树，并在失败时
回滚。验证器会检查 profile、链接依赖、生成的 Cordis 配置、Nginx/systemd
健康状况、浏览器 bundle、认证边缘边界以及当前启动周期中的错误。

## 添加插件

插件代码应放在本仓库之外。使用 DSH 插件命令或独立插件集合安装：

```bash
sudo -u dsh -H dsh plugin --profile web add package-name@exact-version
sudo /opt/dsh-deploy/verify.sh
```

如果使用其他 `DSH_USER`，请替换账户名。持久化本地插件不得从临时目录链接。

## 安全

- 不要提交 `.env`、生成的凭据、密钥、证书、日志或 settings 文件。
- 只公开 80 和 443 端口，不要公开 DSH 回环端口。
- Nginx 在代理到 DSH 前会移除 Basic `Authorization` 请求头。
- 密码文件使用 bcrypt，只有 root 与 Nginx 可以读取。
- 除非整个公开边缘都由本仓库的认证边界保护，否则应禁用
  `PUBLIC_SETTINGS_OVER_BASIC_AUTH`。

## 许可证

MIT。DeepSeek Harness 和单独安装的插件保留各自的许可证与版权声明。
