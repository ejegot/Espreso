/**
 * ELIlai Kafe native shell bootstrap.
 *
 * Injected into the remote Phoenix WebView from MainActivity because
 * server.url loads the Phoenix origin (local www/ is never the document).
 *
 * Scope: Android hardware back + ESC/POS printer bridge.
 *
 * Do not mark the shell "installed" until EscPosPrinter is confirmed available
 * via Capacitor.Plugins.EscPosPrinter or Capacitor.isPluginAvailable.
 * Bare Capacitor.nativePromise is NOT sufficient.
 */
(function elilaiNativeShell() {
  if (window.__elilaiKafeNativeShellInstalled) {
    return;
  }

  var Cap = window.Capacitor;
  if (!Cap) {
    setTimeout(elilaiNativeShell, 40);
    return;
  }

  if (!isEscPosPrinterAvailable(Cap)) {
    setTimeout(elilaiNativeShell, 40);
    return;
  }

  // Back button is Android-only; missing App plugin must not block printer install.
  if (
    Cap.Plugins &&
    Cap.Plugins.App &&
    Cap.getPlatform &&
    Cap.getPlatform() === "android"
  ) {
    var App = Cap.Plugins.App;
    App.addListener("backButton", function (event) {
      if (event && event.canGoBack) {
        window.history.back();
        return;
      }
      App.minimizeApp();
    });
  }

  window.__elilaiKafeNativeShellInstalled = true;
  window.__elilaiKafeNativePrinter = true;

  /**
   * Sends raw ESC/POS bytes via the native TCP plugin.
   * Defaults: host 192.168.0.87, port 9100 (shop HS-802UL).
   * Exactly one native send path per call (plugin stub preferred, else gated nativePromise).
   */
  window.ElilaiKafePrinter = {
    available: function () {
      return isEscPosPrinterAvailable(Cap);
    },
    send: function (opts) {
      opts = opts || {};
      if (!opts.dataBase64) {
        return Promise.reject(new Error("Missing ESC/POS payload"));
      }
      if (!isEscPosPrinterAvailable(Cap)) {
        return Promise.reject(
          new Error(
            "Printer bridge unavailable — open the ELIlai Kafe Android app on shop Wi‑Fi"
          )
        );
      }
      var payload = {
        dataBase64: opts.dataBase64,
        host: opts.host,
        port: opts.port,
        timeoutMs: opts.timeoutMs
      };
      var p = Cap.Plugins && Cap.Plugins.EscPosPrinter;
      if (p && typeof p.send === "function") {
        return p.send(payload);
      }
      if (typeof Cap.nativePromise === "function") {
        return Cap.nativePromise("EscPosPrinter", "send", payload);
      }
      return Promise.reject(
        new Error(
          "Printer bridge unavailable — open the ELIlai Kafe Android app on shop Wi‑Fi"
        )
      );
    },
    getDefaults: function () {
      if (!isEscPosPrinterAvailable(Cap)) {
        return Promise.resolve({host: "192.168.0.87", port: 9100, timeoutMs: 4000});
      }
      var p = Cap.Plugins && Cap.Plugins.EscPosPrinter;
      if (p && typeof p.getDefaults === "function") {
        return p.getDefaults();
      }
      if (typeof Cap.nativePromise === "function") {
        return Cap.nativePromise("EscPosPrinter", "getDefaults", {});
      }
      return Promise.resolve({host: "192.168.0.87", port: 9100, timeoutMs: 4000});
    }
  };

  function isEscPosPrinterAvailable(cap) {
    if (!cap) {
      return false;
    }
    if (cap.Plugins && cap.Plugins.EscPosPrinter) {
      return true;
    }
    if (
      typeof cap.isPluginAvailable === "function" &&
      cap.isPluginAvailable("EscPosPrinter")
    ) {
      return true;
    }
    return false;
  }
})();
