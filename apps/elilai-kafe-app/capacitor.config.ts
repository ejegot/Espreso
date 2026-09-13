import type { CapacitorConfig } from "@capacitor/cli";

/**
 * Production ELIlai Kafe staff app loads the existing Phoenix LiveView host.
 * Do not bundle Phoenix HTML/JS/CSS into www/.
 *
 * Development override (never commit secrets; HTTPS preferred):
 *   ELILAI_KAFE_SERVER_URL=https://espreso.fly.dev/login npx cap sync
 *   ELILAI_KAFE_SERVER_URL=http://192.168.x.x:4000/login ELILAI_KAFE_ALLOW_CLEARTEXT=1 npx cap sync
 */
const PRODUCTION_SERVER_URL = "https://espreso.fly.dev/login";
const PRODUCTION_HOST = "espreso.fly.dev";

const configuredUrl = process.env.ELILAI_KAFE_SERVER_URL?.trim() || PRODUCTION_SERVER_URL;
const allowCleartext = process.env.ELILAI_KAFE_ALLOW_CLEARTEXT === "1";

if (configuredUrl.startsWith("http://") && !allowCleartext) {
  throw new Error(
    "Refusing cleartext ELILAI_KAFE_SERVER_URL without ELILAI_KAFE_ALLOW_CLEARTEXT=1 (dev only)."
  );
}

if (
  process.env.NODE_ENV === "production" &&
  configuredUrl.startsWith("http://")
) {
  throw new Error("Production Capacitor builds must use HTTPS.");
}

const config: CapacitorConfig = {
  appId: "ph.elilai.kafe",
  appName: "ELIlai Kafe",
  webDir: "www",
  backgroundColor: "#F4EFE3",
  server: {
    // Remote Phoenix LiveView document (intentional remote shell).
    url: configuredUrl,
    cleartext: allowCleartext,
    // Keep navigation on the production Phoenix host inside the WebView.
    // Other hosts open in the system browser by Capacitor default.
    allowNavigation: [PRODUCTION_HOST]
  }
};

export default config;
