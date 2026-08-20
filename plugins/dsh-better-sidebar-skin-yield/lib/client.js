window.__ModuleLoader__.load({
  id: "dsh-better-sidebar-skin-yield",
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });

    const inject = [];
    const STYLE_ID = "dsh-better-sidebar-skin-yield";
    const RULE = 'body:has([data-skin-chrome="titlebar"]) [class*="_toggleCluster"]{top:34px!important;z-index:1000001!important}';

    function apply(ctx) {
      const start = () => {
        const body = document.body;
        const head = document.head;
        if (!body || !head) {
          requestAnimationFrame(start);
          return;
        }

        const refresh = () => {
          const active = body.querySelector('[data-skin-chrome="titlebar"]') !== null;
          let style = head.querySelector(`style#${CSS.escape(STYLE_ID)}`);
          if (!active) {
            style?.remove();
            return;
          }
          if (!style) {
            style = document.createElement("style");
            style.id = STYLE_ID;
            head.appendChild(style);
          }
          if (style.textContent !== RULE) style.textContent = RULE;
        };

        refresh();
        const observer = new MutationObserver(refresh);
        observer.observe(body, { attributes: true, childList: true, subtree: true });
        ctx.effect(() => () => {
          observer.disconnect();
          head.querySelector(`style#${CSS.escape(STYLE_ID)}`)?.remove();
        }, "dsh-better-sidebar-skin-yield");
      };

      if (document.body) start();
      else document.addEventListener("DOMContentLoaded", start, { once: true });
    }

    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  }
});
