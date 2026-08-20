window.__ModuleLoader__.load({
  id: "dsh-nginx-auth-settings",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    const officialSettings = require("@deepseek-ai/dsh-client-ui-settings");
    const inject = officialSettings.inject;

    async function apply(ctx) {
      const connection = ctx.get("connection");
      if (connection === void 0) throw new Error("nginx-auth-settings: connection service is absent");

      if (globalThis.location?.protocol === "https:") {
        try {
          const response = await fetch("/api/dsh-public-auth", {
            credentials: "same-origin",
            cache: "no-store",
            headers: { accept: "application/json" }
          });
          const marker = response.ok ? await response.json() : void 0;
          if (marker?.authenticated === true) {
            // RC.8 selects the mirror mode once, inside the official apply().
            // Set the capability first, then start that unmodified controller.
            connection.isLoopback = true;
          }
        } catch {
          // Preserve RC.8's normal memory-only controller when the edge marker
          // is absent, malformed, or unreachable.
        }
      }

      return officialSettings.apply(ctx);
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  }
});
