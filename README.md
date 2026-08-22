# DSH Cloud Server Deploy

[English](README.md) | [简体中文](README.zh-CN.md)

A small, public deployment layer for exposing the official DeepSeek Harness
(DSH) web application over HTTPS on Ubuntu or Debian.

This repository contains only:

- the pinned official `@deepseek-ai/dsh` core;
- the official `dsh-base` and `dsh-web-app` profile bundles;
- a loopback-only systemd service;
- Nginx TLS, Basic Auth, WebSocket/SSE proxying, and an HTTP-to-HTTPS redirect;
- an optional authenticated-edge compatibility bridge for browser settings;
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

The installer never patches the globally installed DSH package. The small
browser-settings bridge is injected by Nginx only into pages that have passed
Basic Auth. DSH itself remains bound to `127.0.0.1`.

## Install

```bash
git clone https://github.com/<github-account>/dsh-cloud-server-deploy.git
cd dsh-cloud-server-deploy
cp deploy.conf.example deploy.conf
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

`deploy.conf` is intentionally ignored. Its public template uses placeholders
only. The installer reads only the deployment names listed below, treats their
values as literal text, and never sources or evaluates the file as shell code.
Unknown entries are not exported. Do not put provider credentials in this file.

The installer never opens a legacy `.env`. Earlier repository versions allowed
provider keys there, so an existing operator must create `deploy.conf` from the
new example and copy only the deployment fields listed below. This deliberate
separation prevents the installer from reading old provider-key values.

- `DSH_VERSION`: exact DSH version; ranges and `latest` are rejected.
- `TRUSTED_HOST`: public hostname or IP accepted by DSH.
- `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD`: Nginx credentials.
- `PUBLIC_SETTINGS_OVER_BASIC_AUTH`: enable the authenticated-edge bridge.
- `DSH_USER`: unprivileged service account, `dsh` by default.
- `DSH_PORT`: loopback port, `3080` by default.
- `DEPLOY_DIR`: root-owned helper directory, `/opt/dsh-deploy` by default.
- `SSL_CERT_PATH` / `SSL_KEY_PATH`: optional existing certificate paths.

### Provider-credential boundary

Before changing the DSH home, `install.sh` classifies the run as either a clean
install (the DSH home does not exist) or an upgrade (it already exists).

- On a clean install, provider-credential discovery and import are disabled.
  The deployer does not create a DSH credential file. Configure providers from
  DSH after the deployment is healthy.
- On an upgrade, the existing DSH credential store stays in place. Neither the
  installer nor updater opens, copies, restores, changes permissions or
  ownership, or removes it.

Credential files are deliberately excluded from automatic deployment backups
and rollback because accessing them would violate this boundary. Back them up
separately with your own secret-management process if required. DSH itself will
use its credential store normally when serving configured providers; the
boundary applies to this repository's deployment scripts.

## Updates and checks

Use an exact target version:

```bash
sudo /opt/dsh-deploy/update.sh 0.1.1-rc.1
sudo /opt/dsh-deploy/verify.sh
```

The updater stops DSH, installs the exact version, validates the full official
DSH dependency tree, and rolls back on failure. The verifier checks the profile,
linked dependencies, generated Cordis configuration, Nginx/systemd health,
browser bundles, the authenticated-edge boundary, and current-boot errors.
Rollback covers the profile, settings, and Cordis patches, but intentionally
does not access the DSH credential store.

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

- Commit neither `deploy.conf`, legacy `.env`, generated credentials, keys,
  certificates, logs, nor settings.
- Expose ports 80 and 443 only; do not expose DSH's loopback port.
- Nginx removes its Basic `Authorization` header before proxying to DSH.
- The password file uses bcrypt and is readable only by root and Nginx.
- Disable `PUBLIC_SETTINGS_OVER_BASIC_AUTH` unless the entire public edge is
  protected by the authentication boundary in this repository.

## License

MIT. DeepSeek Harness and any separately installed plugins retain their own
licenses and copyright notices.
