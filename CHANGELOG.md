# Changelog

## Unreleased

- Detect clean versus existing DSH home state before creating deployment files.
- Remove provider-credential discovery, import, templating, backup, restoration,
  and ownership changes from the installer and updater.
- Move deployment settings to an allowlisted `deploy.conf` and never open the
  legacy `.env`, which earlier releases allowed operators to use for API keys.
- Create the DSH home and `profiles` parent with service-user ownership, and
  print captured DSH configuration errors when verification fails.

## 0.3.0-rc.1 — 2026-08-21

- Pin the tested DSH baseline to `0.1.1-rc.1`.
- Generate optional API-key references using the RC.1 versioned credentials
  schema.
- Preserve settings, credentials, profile files, and Cordis patches during an
  automatic rollback.
- Allow more startup time and verify both current and legacy direct-upstream
  browser behavior without weakening the authenticated HTTPS boundary.

- Reduce the repository to the official DSH core/web profile and generic HTTPS
  exposure layer.
- Move all plugin source, plugin installation policy, provider catalogs, and
  model-routing policy to a separate plugin collection.
- Change the default unprivileged service account from a cloud-image-specific
  username to `dsh`.
- Remove deployment-specific audit data and plugin-specific verification.

## 0.2.0-rc.8 — 2026-08-20

- Pin the tested DSH baseline to `0.1.0-rc.8`.
- Preserve the official global DSH installation without source patches.
- Add Nginx TLS and Basic Auth, a loopback systemd service, exact-version
  updates with rollback, and full-tree verification.
- Add an authenticated-edge bridge for RC.8 browser settings without modifying
  the DSH core.
