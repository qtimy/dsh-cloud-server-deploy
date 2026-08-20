# Live EC2 audit: DSH RC.8 clean-core baseline

Audit date: 2026-08-20

## Core

- Top-level version: `@deepseek-ai/dsh@0.1.0-rc.8`.
- Dependency tree: 186 installed `@deepseek-ai/dsh-*` packages, all at `0.1.0-rc.8`.
- The previous deployment modified exactly three official files for SSE/WebSocket heartbeat behavior:
  - `dsh-host-apiproxy/lib/types/fetch/handler.js`
  - `dsh-client-connection/lib/index.js`
  - `dsh-client-connection/lib/client.js`
- Those files were restored from clean RC.8 package contents. DSH remained stable and all plugin checks continued to pass, so the patch is excluded from this release.

## Profile and plugins

The reference instance has more plugins than this minimal repository installs. They were audited to validate the RC.8 host and plugin structure:

| Profile dependency | Version/source | Result |
| --- | --- | --- |
| `@linxin666/dsh-web-ui-all` | `0.1.12` | Loaded; all 11 discovered client packages served HTTP 200 |
| `dsh-agent-orchestrator` | persistent local link, `0.1.0` | Present in generated config |
| `dsh-usage-stats` | persistent local link, `0.1.0` | Generated config + client HTTP 200 |
| `dsh-better-sidebar-skin-yield` | persistent local link, `0.1.0` | Generated config + client HTTP 200 |
| `dsh-better-sidebar` | `0.12.1` | Client HTTP 200; Sidebar API/file/HTML/WebSocket routes registered |
| `dsh-plugin-marketplace` | GitHub package, resolved `1.5.4` | Client HTTP 200; marketplace list HTTP 200; management routes registered |

Additional observations:

- All local links resolve under `/home/ubuntu/.dsh/plugins`; none use `/tmp`.
- DSH `--dump-config` completes with no warnings.
- AionUI, Git Graph, SSH, Marketplace, and Sidebar host route families are registered.
- `remote-web-ui` is installed by the aggregate but intentionally configured with `enabled: false` because public access already uses Nginx Basic Auth.
- After restoring clean core files, the DSH PID remained stable, upstream `/` returned HTTP 200, every discovered third-party client bundle returned HTTP 200, and the current boot log contained no plugin/runtime failures.

## Repository decisions

- Only `dsh-base` and `dsh-web-app` belong in the core profile template.
- Optional packages are installed through `dsh plugin` and remain removable dependencies.
- Compatibility edits may target plugin-owned files, but never the global DSH installation.
- The deployment verifier treats volatile links, mixed core versions, config warnings, missing client bundles, restarts, and known boot errors as failures.

## Authenticated browser follow-up

RC.8 intentionally chooses an in-memory settings controller when the browser page URL is not loopback. On the reference public deployment this hid the Models catalog and left plugin configuration empty even though Nginx already enforced Basic Auth.

The follow-up installs `dsh-nginx-auth-settings` as a client-only profile plugin. Its Nginx marker returns 401 without Basic Auth and does not exist on direct port 3080. After the authenticated same-origin marker succeeds, the plugin enables RC.8's existing host-backed controller before the official settings UI is mounted. No DSH package file is changed.

The existing sidebar/skin helper also referenced a generated CSS-module hash that changed in `dsh-better-sidebar@0.12.1`. Version `0.1.1` now selects the stable `_toggleCluster` suffix. Both plugins served HTTP 200, the generated config had no warnings, and DSH remained stable after activation.
