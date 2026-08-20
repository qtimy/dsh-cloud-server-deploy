# DSH Cloud Server Deploy

A small, public deployment layer for exposing the official DeepSeek Harness
(DSH) web application over HTTPS on Ubuntu or Debian.

This repository contains only:

- the pinned official `@deepseek-ai/dsh` core;
- the official `dsh-base` and `dsh-web-app` profile bundles;
- a loopback-only systemd service;
- Nginx TLS, Basic Auth, WebSocket/SSE proxying, and an HTTP-to-HTTPS redirect;
- an optional authenticated-edge compatibility bridge for RC.8 browser settings;
- version-pinned update, rollback, and verification helpers.

It does not contain or install community plugins, provider choices, model routing
rules, API keys, hostnames, IP addresses, certificates, or deployment-specific
configuration. Plugins are maintained in a separate plugin collection.

## Boundary

```text
Browser
  -> HTTPS + Basic Auth
  -> Nginx :443
  -> loopback HTTP
  -> official DSH web profile :3080
       - @deepseek-ai/dsh-base
       - @deepseek-ai/dsh-web-app
```

The installer never patches the globally installed DSH package. The small RC.8
browser-settings bridge is injected by Nginx only into pages that have passed
Basic Auth. DSH itself remains bound to `127.0.0.1`.

## Install

```bash
git clone https://github.com/<github-account>/dsh-cloud-server-deploy.git
cd dsh-cloud-server-deploy
cp .env.example .env
# Set TRUSTED_HOST and BASIC_AUTH_PASSWORD.
sudo bash install.sh
```

Open `https://<TRUSTED_HOST>/`. The default self-signed certificate encrypts the
connection but produces a browser warning. To obtain a trusted certificate after
DNS and port 80 are ready:

```bash
sudo bash scripts/setup-letsencrypt.sh dsh.example.com admin@example.com
```

## Configuration

`.env` is intentionally ignored. Its public template uses placeholders only.

- `DSH_VERSION`: exact DSH version; ranges and `latest` are rejected.
- `TRUSTED_HOST`: public hostname or IP accepted by DSH.
- `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD`: Nginx credentials.
- `PUBLIC_SETTINGS_OVER_BASIC_AUTH`: enable the RC.8 authenticated-edge bridge.
- `DSH_USER`: unprivileged service account, `dsh` by default.
- `DSH_PORT`: loopback port, `3080` by default.
- `DEPLOY_DIR`: root-owned helper directory, `/opt/dsh-deploy` by default.
- `SSL_CERT_PATH` / `SSL_KEY_PATH`: optional existing certificate paths.

Variables ending in `_API_KEY` may be placed in the local `.env`; on first
install they are written to the service user's mode-0600 DSH credentials file.
They are never written into this repository.

## Updates and checks

Use an exact target version:

```bash
sudo /opt/dsh-deploy/update.sh 0.1.0-rc.8
sudo /opt/dsh-deploy/verify.sh
```

The updater stops DSH, installs the exact version, validates the full official
DSH dependency tree, and rolls back on failure. The verifier checks the profile,
linked dependencies, generated Cordis configuration, Nginx/systemd health,
browser bundles, the authenticated-edge boundary, and current-boot errors.

## Adding plugins

Keep plugin code outside this repository. Install packages with DSH's plugin
command, or use the separate plugin collection:

```bash
sudo -u dsh -H dsh plugin --profile web add package-name@exact-version
sudo /opt/dsh-deploy/verify.sh
```

For a different `DSH_USER`, substitute that account. Persistent local plugins
must not be linked from temporary directories.

## Security

- Commit neither `.env` nor generated credentials, keys, certificates, logs, or
  settings.
- Expose ports 80 and 443 only; do not expose DSH's loopback port.
- Nginx removes its Basic `Authorization` header before proxying to DSH.
- The password file uses bcrypt and is readable only by root and Nginx.
- Disable `PUBLIC_SETTINGS_OVER_BASIC_AUTH` unless the entire public edge is
  protected by the authentication boundary in this repository.

## License

MIT. DeepSeek Harness and any separately installed plugins retain their own
licenses and copyright notices.
