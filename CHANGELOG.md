# Changelog

## 0.2.0-rc.8 — 2026-08-20

- Upgrade the tested DSH baseline from `0.1.0-rc.7` to `0.1.0-rc.8`.
- Keep the official global DSH installation clean; remove the realtime source patch from the default deployment and upgrade paths.
- Install `@linxin666/dsh-web-ui-all` through `dsh plugin` as an optional, pinned profile dependency.
- Add full core/profile/plugin/runtime verification with `scripts/verify.sh`.
- Make updates exact-version-only, stop the service during package replacement, validate the complete DSH dependency tree, and roll back automatically.
- Preserve existing settings, credentials, and profile manifests on installer reruns.
- Fix the fresh-clone repository-root resolution bug.
- Fix deployment-directory creation ordering.
- Fix the auto-restart unit's script path and permission model.
- Use Node.js 22 for RC.8 and plugin compatibility.
- Disable `remote-web-ui` by default behind Nginx Basic Auth.
- Use bcrypt for Basic Auth and strip its `Authorization` header before proxying to DSH.
- Add static CI and document the live RC.8 audit.
- Preserve Let's Encrypt certificate paths across installer reruns.

## 0.1.0-rc.7 — 2026-08-19

- Initial published deployment template.
