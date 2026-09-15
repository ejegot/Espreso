/**
 * ELIlai Kafe native shell bootstrap.
 *
 * Injected into the remote Phoenix WebView from MainActivity because
 * server.url loads espreso.fly.dev (local www/ is never the document).
 *
 * Scope: Android hardware back + ESC/POS printer bridge.
 */
(function elilaiNativeShell() {
  if (window.__elilaiKafeNativeShellInstalled) {
    return;
  }

  var Cap = window.Capacitor;
  if (!Cap || !Cap.Plugins || !Cap.Plugins.App) {
    setTimeout(elilaiNativeShell, 40);
    return;
  }

  // Back button is Android-only; other platforms no-op safely.
  if (Cap.getPlatform && Cap.getPlatform() !== "android") {
    window.__elilaiKafeNativeShellInstalled = true;
    return;
  }

  var App = Cap.Plugins.App;
  window.__elilaiKafeNativeShellInstalled = true;
  window.__elilaiKafeNativePrinter = true;

  App.addListener("backButton", function (event) {
    if (event && event.canGoBack) {
      window.history.back();
      return;
    }
    App.minimizeApp();
  });

  /**
   * Sends raw ESC/POS bytes via the native TCP plugin.
   * Defaults: host 192.168.0.87, port 9100 (shop HS-802UL).
   */
  window.ElilaiKafePrinter = {
    available: function () {
      return !!(Cap.Plugins && Cap.Plugins.EscPosPrinter);
    },
    send: function (opts) {
      opts = opts || {};
      var plugin = Cap.Plugins && Cap.Plugins.EscPosPrinter;
      if (!plugin || typeof plugin.send !== "function") {
        return Promise.reject(
          new Error("Printer bridge unavailable — open the ELIlai Kafe Android app on shop Wi‑Fi")
        );
      }
      if (!opts.dataBase64) {
        return Promise.reject(new Error("Missing ESC/POS payload"));
      }
      return plugin.send({
        dataBase64: opts.dataBase64,
        host: opts.host,
        port: opts.port,
        timeoutMs: opts.timeoutMs
      });
    },
    getDefaults: function () {
      var plugin = Cap.Plugins && Cap.Plugins.EscPosPrinter;
      if (!plugin || typeof plugin.getDefaults !== "function") {
        return Promise.resolve({host: "192.168.0.87", port: 9100, timeoutMs: 4000});
      }
      return plugin.getDefaults();
    }
  };
})();
