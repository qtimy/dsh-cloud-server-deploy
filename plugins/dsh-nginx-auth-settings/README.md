# dsh-nginx-auth-settings

DSH RC.8 deliberately restricts its settings and credential APIs to browsers
whose page URL is loopback. This client-only plugin extends that capability to
the repository's authenticated HTTPS edge without modifying DSH core.

The plugin first fetches `/api/dsh-public-auth`. Nginx answers that endpoint
only after server-level Basic Auth succeeds. It then enables RC.8's existing
host-backed settings controller. Direct access to DSH on port 3080 has no marker
route and cannot activate the capability.

The bundle patch remounts the official `dsh-client-ui-settings` row after the
marker check so model and plugin settings consumers initialize in host mode.
