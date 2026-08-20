window.__ModuleLoader__.load({
  id: "dsh-nginx-auth-settings",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    const inject = ["connection"];

    async function apply(ctx) {
      const connection = ctx.get("connection");
      if (connection === void 0) throw new Error("nginx-auth-settings: connection service is absent");

      let authenticated = false;
      if (globalThis.location?.protocol === "https:") {
        try {
          const response = await fetch("/api/dsh-public-auth", {
            credentials: "same-origin",
            cache: "no-store",
            headers: { accept: "application/json" },
            signal: AbortSignal.timeout(5000)
          });
          const marker = response.ok ? await response.json() : void 0;
          if (marker?.authenticated === true) {
            authenticated = true;
            connection.isLoopback = true;
          }
        } catch {
          // The official controller starts in its normal memory-only mode when
          // the marker is absent, malformed, or unreachable.
        }
      }

      // The official ui-settings entry declares this as an extra dependency in
      // cordis.patch.yml, so it cannot choose its one-time mirror mode earlier.
      ctx.provide("nginxAuthSettingsReady", { authenticated });
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  }
});
