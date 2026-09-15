import type { CapacitorConfig } from "@capacitor/cli";

/**
 * Production ELIlai Kafe staff app loads the existing Phoenix LiveView host.
 * Do not bundle Phoenix HTML/JS/CSS into www/.
 *
 * server.url must be ORIGIN ONLY (no path). Start at /login via appStartPath.
 *
 * Development override (never commit secrets; HTTPS preferred):
 *   ELILAI_KAFE_SERVER_URL=https://espreso.fly.dev npx cap sync
 *   ELILAI_KAFE_SERVER_URL=http://192.168.x.x:4000 ELILAI_KAFE_ALLOW_CLEARTEXT=1 npx cap sync
 *
 * Paths in ELILAI_KAFE_SERVER_URL (e.g. …/login) are accepted and split into
 * origin + appStartPath.
 */
const PRODUCTION_ORIGIN = "https://espreso.fly.dev";
const PRODUCTION_HOST = "espreso.fly.dev";
const DEFAULT_START_PATH = "/login";

const allowCleartext = process.env.ELILAI_KAFE_ALLOW_CLEARTEXT === "1";
const configuredRaw =
  process.env.ELILAI_KAFE_SERVER_URL?.trim() || PRODUCTION_ORIGIN;

if (configuredRaw.startsWith("http://") && !allowCleartext) {
  throw new Error(
    "Refusing cleartext ELILAI_KAFE_SERVER_URL without ELILAI_KAFE_ALLOW_CLEARTEXT=1 (dev only)."
  );
}

if (process.env.NODE_ENV === "production" && configuredRaw.startsWith("http://")) {
  throw new Error("Production Capacitor builds must use HTTPS.");
}

const {origin: serverOrigin, startPath: appStartPath} = splitServerTarget(configuredRaw);
const allowNavigation = buildAllowNavigation(serverOrigin, allowCleartext);

const config: CapacitorConfig = {
  appId: "ph.elilai.kafe",
  appName: "Elilai Kafe",
  webDir: "www",
  backgroundColor: "#F4EFE3",
  server: {
    // Remote Phoenix LiveView document (intentional remote shell).
    // ORIGIN ONLY — path goes in appStartPath so Cap 8 origin rules match.
    url: serverOrigin,
    cleartext: allowCleartext,
    appStartPath,
    // Keep navigation on the production Phoenix host inside the WebView.
    // Cleartext LAN hosts are added only when ELILAI_KAFE_ALLOW_CLEARTEXT=1.
    allowNavigation
  },
  android: {
    // Cap 8 WebMessageListener origin matching fails for remote server.url
    // (path-bearing rules / cleartext LAN). Legacy JavascriptInterface exposes
    // window.androidBridge on the Phoenix document reliably.
    useLegacyBridge: true
  },
  plugins: {
    // Capacitor 8 core SystemBars: light icons on Forest chrome.
    SystemBars: {
      insetsHandling: "css",
      // Hint avoids first-paint inset shift; employee_root uses viewport-fit=cover.
      initialViewportFitValueHint: "cover",
      style: "DARK",
      hidden: false
    }
  }
};

export default config;

function splitServerTarget(raw: string): {origin: string; startPath: string} {
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`Invalid ELILAI_KAFE_SERVER_URL: ${raw}`);
  }

  const origin = parsed.origin;
  let startPath =
    parsed.pathname && parsed.pathname !== "/"
      ? parsed.pathname
      : DEFAULT_START_PATH;

  if (startPath.length > 1 && startPath.endsWith("/")) {
    startPath = startPath.slice(0, -1);
  }

  return {origin, startPath};
}

function buildAllowNavigation(origin: string, cleartext: boolean): string[] {
  const entries = [PRODUCTION_HOST];

  if (!cleartext) {
    return entries;
  }

  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    return entries;
  }

  if (parsed.protocol !== "http:") {
    return entries;
  }

  // Cap prefixes bare hosts with https:// for WebMessageListener rules.
  // Include http:// origin forms so cleartext LAN matching stays correct
  // even if a future build turns legacy bridge off.
  const hostname = parsed.hostname;
  const hostPort = parsed.port ? `${hostname}:${parsed.port}` : hostname;
  for (const entry of [hostname, hostPort, parsed.origin]) {
    if (!entries.includes(entry)) {
      entries.push(entry);
    }
  }

  return entries;
}
