window.__ModuleLoader__.load({
  id: "dsh-nginx-auth-settings",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    const inject = ["connection"];

    async function apply(ctx) {
      if (globalThis.location?.protocol !== "https:") return;

      let response;
      try {
        response = await fetch("/api/dsh-public-auth", {
          credentials: "same-origin",
          cache: "no-store",
          headers: { accept: "application/json" }
        });
      } catch {
        return;
      }
      if (!response.ok) return;

      let marker;
      try {
        marker = await response.json();
      } catch {
        return;
      }
      if (marker?.authenticated !== true) return;

      const connection = ctx.get("connection");
      if (connection === void 0) throw new Error("nginx-auth-settings: connection service is absent");

      // RC.8 uses this capability bit to select the host-backed settings and
      // credentials controllers. Direct port 3080 never serves the marker;
      // only the authenticated HTTPS edge can reach this assignment.
      connection.isLoopback = true;
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  }
});
