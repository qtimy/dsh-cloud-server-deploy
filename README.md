# DSH Cloud Server Deploy — clean-core RC.8

Deploy [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) on an Ubuntu/Debian cloud server with a deliberately small boundary:

- official `@deepseek-ai/dsh` core, pinned to an exact version;
- the official `dsh-base` + `dsh-web-app` profile bundles;
- optional packages installed only through `dsh plugin`;
- Nginx TLS, Basic Auth, WebSocket/SSE proxying, and systemd supervision.

The installer does **not** patch files inside the global DSH package. RC.8 was tested on the reference EC2 instance with the official core restored byte-for-byte; the service and installed plugins remained healthy.

## Architecture

```text
Internet
   │ HTTPS + Basic Auth
   ▼
Nginx :443
   │ loopback proxy
   ▼
Official DSH web profile :3080
   ├── @deepseek-ai/dsh-base       (core)
   ├── @deepseek-ai/dsh-web-app    (core)
   └── profile packages            (plugins)
```

`@linxin666/dsh-web-ui-all` is enabled by default in `.env.example`, but it is installed through the official plugin command and remains a removable profile dependency. Set `WEB_UI_ALL_VERSION=` for an official-core-only deployment.

## What is included

- Exact-version DSH installation (`0.1.0-rc.8` in this release).
- Optional Web UI aggregate plugin (`0.1.12`, the version validated on RC.8).
- Nginx HTTP→HTTPS redirect, TLS, Basic Auth, WebSocket/SSE support, upload sizing, and stripped upstream Basic credentials.
- An optional client-only authenticated-edge bridge that restores Models and plugin settings in RC.8 public browsers without patching core.
- A systemd DSH service and a root-owned package-change watcher that can restart it safely.
- Safe upgrades with complete DSH dependency-tree validation and automatic rollback.
- `scripts/verify.sh`, which validates:
  - every installed `@deepseek-ai/dsh-*` package matches the target version;
  - profile JSON and generated Cordis configuration;
  - no plugin uses a volatile `link:/tmp` dependency;
  - linked plugin targets exist;
  - systemd/Nginx/upstream health;
  - every discovered third-party client bundle is served with HTTP 200;
  - the current DSH boot has no plugin/runtime errors.

## Quick start

```bash
git clone https://github.com/qtimy/dsh-cloud-server-deploy.git
cd dsh-cloud-server-deploy
cp .env.example .env
# Edit TRUSTED_HOST and BASIC_AUTH_PASSWORD at minimum.
sudo bash install.sh
```

Then open `https://<TRUSTED_HOST>/`. A self-signed certificate is created by default, so the browser will show a warning until you install a trusted certificate.

For a core-only profile, set this before installation:

```bash
WEB_UI_ALL_VERSION=
```

## Configuration ownership

- Core: globally installed `@deepseek-ai/dsh`; never modified by this repository.
- Profile: `/home/<user>/.dsh/profiles/web/package.json` and its plugin dependencies.
- User settings and credentials: `/home/<user>/.dsh/settings.yaml` and `.credentials.yaml`.
- Public edge: `/etc/nginx/sites-available/dsh` and `/etc/nginx/.htpasswd`.
- Service runtime: `/etc/systemd/system/dsh-web.service`.
- Deployment helpers: `/opt/dsh-deploy` by default.

Re-running `install.sh` preserves existing DSH settings, credentials, and profile manifests. It installs missing templates only, reconciles the requested optional plugin, refreshes the public/service structure, and verifies the result.

## Plugins

Install additional functionality through DSH rather than editing core files:

```bash
sudo -u ubuntu -H dsh plugin --profile web add package-name@exact-version
sudo -u ubuntu -H dsh plugin --profile web remove package-name
sudo /opt/dsh-deploy/verify.sh
```

Persistent local plugins must live under a durable path such as `/home/ubuntu/.dsh/plugins/<name>`. Never install a profile dependency from `/tmp`; the verifier rejects such links.

The Web UI `settings.plugin.item` compatibility fix is intentionally limited to the plugin's own generated client file. It does not touch DSH core.

RC.8 otherwise restricts its settings and credential plane to loopback page URLs. With `PUBLIC_SETTINGS_OVER_BASIC_AUTH=true`, the installer adds `dsh-nginx-auth-settings`: it requires an authenticated same-origin marker from Nginx before selecting RC.8's host-backed settings controller. The DSH listener remains loopback-only and the marker does not exist on port 3080.

The bundled `dsh-better-sidebar-skin-yield` plugin moves sidebar controls below fake-window skin title bars using a stable CSS-module suffix rather than a generated class hash.

## Upgrade or rollback

Always specify an exact target version:

```bash
sudo /opt/dsh-deploy/update.sh 0.1.0-rc.8
```

The updater backs up profile manifests, stops DSH, installs the pinned core, validates the complete DSH package tree, checks plugins without upgrading them, restarts, and performs a stability check. Any failure attempts an automatic rollback to the previous DSH version.

## Trusted certificate (optional)

After DNS points to the server and port 80 is publicly reachable:

```bash
sudo bash scripts/setup-letsencrypt.sh dsh.example.com admin@example.com
```

The certificate paths are persisted in `/opt/dsh-deploy/tls.env`, so a later installer run keeps the trusted certificate.

## Repository layout

```text
install.sh
scripts/
  dsh-autorestart.sh
  patch-plugins-key.sh
  setup-letsencrypt.sh
  update.sh
  verify.sh
templates/
nginx/
systemd/
tests/
docs/
```

See [the RC.8 live audit](docs/live-audit-rc8.md) and [the changelog](CHANGELOG.md) for the evidence behind this release.

## Security notes

- Never commit `.env`; it contains the Basic Auth password and may contain API keys.
- The generated password file uses bcrypt and is readable only by root/Nginx.
- Nginx authenticates public traffic and removes the Basic `Authorization` header before proxying to DSH.
- Public settings access assumes the entire HTTPS edge is protected by Nginx Basic Auth; disable `PUBLIC_SETTINGS_OVER_BASIC_AUTH` if another deployment does not provide that boundary.
- DSH listens only on `127.0.0.1`; expose ports 80/443, not 3080.
- The optional self-signed certificate encrypts traffic but does not provide public identity verification.
