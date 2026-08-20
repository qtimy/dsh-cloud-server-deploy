# Changelog

## 0.3.1-rc.8 — 2026-08-20

- Update the bundled `dsh-shift-router` to 0.6.1.
- Read RC.8's full configurable-provider directory as well as its active adapter/model registry: 39 known providers, 6 active providers, 33 dormant providers, and 53 active models on the reference deployment.
- Report dormant providers without selecting them for child-agent execution; keep every user-declared custom provider classified as PAYG.

## 0.3.0-rc.8 — 2026-08-20

- Bundle and optionally install `dsh-shift-router` 0.6.0 from a persistent path.
- Integrate six-class subagent/workflow routing with the existing Fast/Smart
  router and Smart CTO orchestration.
- Discover the live DSH provider/model catalog and expose it through
  `/router catalog`; custom providers are always classified as PAYG.
- Add finite cross-provider child failover. Provider quota/auth/config errors
  quarantine the provider; transient errors quarantine only the failed model.
- Remove the redundant standalone `dsh-agent-orchestrator` profile dependency.
- Verify the Shift-Router version, persistent link, host/client bundles, and
  absence of the standalone orchestrator.
- Live EC2 validation: Smart parent on `deepseek-official/deepseek-v4-pro`;
  custom-PAYG child failover `ali/deepseek-v4-pro-0813` →
  `ccsub/claude-opus-5`; orchestration and child result completed.

## 0.2.1-rc.8 — 2026-08-20

- Restore Models and plugin configuration with an Nginx-injected authenticated-edge bootstrap that runs before RC.8 publishes its browser connection service.
- Remove the unsuccessful Cordis trust plugin approach: RC.8 creates browser plugins concurrently, so profile ordering and shared entry gates cannot order its settings controller.
- Keep RC.8 core clean and preserve the loopback-only restriction on direct port 3080.
- Fix the sidebar/skin title-bar layout helper by replacing its stale generated CSS class with a hash-independent selector.
- Stop assigning immutable one-year caching to stable plugin bundle URLs.

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
