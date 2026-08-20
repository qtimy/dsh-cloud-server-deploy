# dsh-nginx-auth-settings

DSH RC.8 deliberately restricts its settings and credential APIs to browsers
whose page URL is loopback. This client-only plugin extends that capability to
the repository's authenticated HTTPS edge without modifying DSH core.

The plugin first fetches `/api/dsh-public-auth`. Nginx answers that endpoint
only after server-level Basic Auth succeeds. It then enables RC.8's existing
host-backed settings controller. Direct access to DSH on port 3080 has no marker
route and cannot activate the capability.

The bundle patch adds a service dependency to the enabled, unmodified official
`dsh-client-ui-settings` row. The trust plugin waits for the marker, updates
RC.8's capability bit, and then provides that service. This ordering matters
because RC.8 selects its settings mirror mode once during initialization.
The plugin's no-op host half also provides the gate so the shared Cordis entry
tree completes host activation; the trust decision remains browser-only.
