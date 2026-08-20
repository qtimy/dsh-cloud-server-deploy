# Changelog

## Unreleased

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
