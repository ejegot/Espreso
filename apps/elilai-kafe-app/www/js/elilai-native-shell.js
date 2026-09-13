/**
 * ELIlai Kafe native shell bootstrap.
 *
 * Injected into the remote Phoenix WebView from MainActivity because
 * server.url loads espreso.fly.dev (local www/ is never the document).
 *
 * Scope: Android hardware back only. No custom route stack.
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

  App.addListener("backButton", function (event) {
    if (event && event.canGoBack) {
      window.history.back();
      return;
    }
    App.minimizeApp();
  });
})();
