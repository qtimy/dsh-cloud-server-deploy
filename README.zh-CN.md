# DSH 云服务器部署

[English](README.md) | [简体中文](README.zh-CN.md)

这是一个小型公开部署层，用于在 Ubuntu 或 Debian 上通过 HTTPS 暴露官方
DeepSeek Harness（DSH）Web 应用。

本仓库仅包含：

- 固定版本的官方 `@deepseek-ai/dsh` 核心；
- 官方 `dsh-base` 和 `dsh-web-app` profile bundles；
- 仅监听 loopback 的 systemd 服务；
- Nginx TLS、Basic Auth、WebSocket/SSE 代理和 HTTP 到 HTTPS 跳转；
- 可选的浏览器设置 authenticated-edge 兼容桥；
- 固定版本的更新、回滚和验证工具。

本仓库不包含也不会安装社区插件、提供方选择、模型路由规则、API 密钥、
主机名、IP 地址、证书或部署专用配置。插件由独立的插件集合维护。

## 边界

```text
浏览器
  -> HTTPS + Basic Auth
  -> Nginx :443
  -> loopback HTTP
  -> 官方 DSH web profile :3080
       - @deepseek-ai/dsh-base
       - @deepseek-ai/dsh-web-app
```

安装程序不会修改全局安装的 DSH 包。浏览器设置兼容桥仅由 Nginx 注入已经
通过 Basic Auth 的页面。DSH 本身始终绑定到 `127.0.0.1`。

## 安装

```bash
git clone https://github.com/<github-account>/dsh-cloud-server-deploy.git
cd dsh-cloud-server-deploy
cp deploy.conf.example deploy.conf
# 设置 TRUSTED_HOST 和 BASIC_AUTH_PASSWORD。
sudo bash install.sh
```

打开 `https://<TRUSTED_HOST>/`。默认自签名证书会加密连接，但浏览器会显示
警告。DNS 和 80 端口就绪后，可申请受信任证书：

```bash
sudo bash scripts/setup-letsencrypt.sh dsh.example.com admin@example.com
```

## 配置

`deploy.conf` 已被忽略，公开模板仅使用占位符。安装程序只读取下方列出的部署
变量，将变量值视为普通文本，绝不会把该文件作为 shell 脚本 source 或执行。
未知条目不会被导出。请勿在此文件中存放提供方凭据。

安装程序绝不会打开旧版 `.env`。本仓库早期版本曾允许在该文件中保存提供方
密钥，因此现有用户必须基于新示例创建 `deploy.conf`，并且只复制下方列出的
部署字段。这种文件级隔离可防止安装程序读取旧的提供方密钥值。

- `DSH_VERSION`：DSH 精确版本；拒绝版本范围和 `latest`。
- `TRUSTED_HOST`：DSH 接受的公开主机名或 IP。
- `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD`：Nginx 登录凭据。
- `PUBLIC_SETTINGS_OVER_BASIC_AUTH`：启用 authenticated-edge 兼容桥。
- `DSH_USER`：非特权服务账户，默认为 `dsh`。
- `DSH_PORT`：loopback 端口，默认为 `3080`。
- `DEPLOY_DIR`：root 管理的工具目录，默认为 `/opt/dsh-deploy`。
- `SSL_CERT_PATH` / `SSL_KEY_PATH`：可选的现有证书路径。

### 提供方凭据边界

在修改 DSH home 之前，`install.sh` 会先判断本次运行是全新安装（DSH home
不存在）还是升级（DSH home 已存在）。

- 全新安装：禁用提供方凭据发现和导入。部署程序不会创建 DSH 凭据文件；
  请在部署通过健康检查后，通过 DSH 配置提供方。
- 升级：现有 DSH 凭据存储保持原位。安装程序和更新程序都不会打开、复制、
  恢复、修改其权限或所有者，也不会删除它。

凭据文件会被明确排除在自动部署备份和回滚之外，因为访问它们会破坏上述
边界。如需备份，请使用您自己的密钥管理流程单独完成。DSH 在提供已配置的
模型服务时仍会正常使用自己的凭据存储；上述边界仅适用于本仓库的部署脚本。

## 更新与检查

使用精确目标版本：

```bash
sudo /opt/dsh-deploy/update.sh 0.1.1-rc.1
sudo /opt/dsh-deploy/verify.sh
```

更新程序会停止 DSH、安装精确版本、验证完整官方依赖树，并在失败时自动
回滚。验证程序会检查 profile、依赖链接、生成的 Cordis 配置、Nginx/systemd
状态、浏览器 bundles、authenticated-edge 边界和当前启动日志错误。
回滚包含 profile、settings 和 Cordis patches，但会有意避免访问 DSH 凭据
存储。

## 添加插件

插件代码应保存在本仓库之外。使用 DSH 插件命令安装包，或使用独立插件
集合：

```bash
sudo -u dsh -H dsh plugin --profile web add package-name@exact-version
sudo /opt/dsh-deploy/verify.sh
```

如果使用不同的 `DSH_USER`，请替换相应账户。持久化本地插件不得链接到临时
目录。

## 安全

- 不要提交 `deploy.conf`、旧版 `.env`、生成的凭据、密钥、证书、日志或
  settings。
- 只开放 80 和 443 端口，不要开放 DSH loopback 端口。
- Nginx 在转发到 DSH 前会移除 Basic `Authorization` 请求头。
- 密码文件使用 bcrypt，且仅 root 与 Nginx 可读。
- 除非整个公开入口均由本仓库的认证边界保护，否则请禁用
  `PUBLIC_SETTINGS_OVER_BASIC_AUTH`。

## 许可证

MIT。DeepSeek Harness 及任何独立安装的插件保留各自的许可证和版权声明。
