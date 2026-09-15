# ELIlai Kafe Native App

Thin Capacitor shell for the ELIlai Kafe employee application.

## Source of truth

The Phoenix LiveView app in this repository is the UI and business-logic source of truth.

This directory does **not** contain a second frontend. The `www/` folder is only the minimum placeholder Capacitor requires.

## Production URL

The shell loads:

`https://espreso.fly.dev/login`

over HTTPS. Session cookies, CSRF, LiveView, POS, Orders, and staff flows remain on Phoenix.

## Prerequisites

- Node.js 22 LTS + npm
- JDK 21
- Android Studio + Android SDK 36 (for Android)
- Xcode 26+ (for iOS)

Example shell env:

```bash
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
```

## Development URL override (optional)

Production default stays HTTPS. For LAN Phoenix testing only:

```bash
ELILAI_KAFE_SERVER_URL=http://192.168.x.x:4000/login ELILAI_KAFE_ALLOW_CLEARTEXT=1 npx cap sync
```

Never ship a cleartext production URL.

## Sync / Android

```bash
cd apps/elilai-kafe-app
npm install
npx cap sync android
npm run build:android:debug
# APK: android/app/build/outputs/apk/debug/app-debug.apk
npx cap open android
```

### Release APK (tablet sideload)

Release signing uses a local keystore and secrets in `~/.gradle/gradle.properties`
(`ELILAI_KAFE_UPLOAD_STORE_FILE`, `ELILAI_KAFE_UPLOAD_STORE_PASSWORD`,
`ELILAI_KAFE_UPLOAD_KEY_ALIAS`, `ELILAI_KAFE_UPLOAD_KEY_PASSWORD`).
Never commit the keystore or passwords.

```bash
cd apps/elilai-kafe-app
npm run build:android:release
# APK: android/app/build/outputs/apk/release/app-release.apk
```

## Sync / iOS

Requires full Xcode (not Command Line Tools only):

```bash
cd apps/elilai-kafe-app
npx cap sync ios
npx cap open ios
```

## Native shell UX (APP PASS 3B)

- `@capacitor/app` handles Android hardware back (history.back or minimize)
- Because `server.url` loads remote Phoenix, `www/js/elilai-native-shell.js` is injected from `MainActivity`
- SystemBars: Forest chrome with light icons (`style: DARK`); WebView ivory `#F4EFE3`
- Brand launcher/splash assets from `priv/static/images/elilai-kafe/` (regenerate via `python3 scripts/generate-brand-assets.py`)
- `allowNavigation` remains `espreso.fly.dev` only

## Shop tablet performance / responsiveness (required)

This is a production shop app. Responsiveness is a core requirement — see
`docs/SHOP_TABLET_PERFORMANCE.md`.

Goals (summary):

- Fast startup; login without unnecessary blocking loaders
- Instant staff search/select, PIN keypad, Home/POS taps, cart, hamburger
- Normal LiveView navigation must not introduce unnecessary loading states
- No artificial splash/loading screens; do not block the WebView UI thread
- Loading/progress UI only for real async work (network, payment, printer, native bridge)
- Printer TCP/network must run off the Android UI thread and return asynchronously

Do **not** remove legitimate loading states. Fix only justified/measurable issues;
preserve Pass 3E-4 payment, loyalty, sales attribution, GCash/Maya, and auth rules.

## Native printer / kaha (APP PASS — LAN ESC/POS)

Tablet talks **directly** to the shop HS-802UL (`192.168.0.87:9100`).
Phoenix/Fly only builds ESC/POS bytes; it never opens a TCP socket to the printer.

- Plugin: `EscPosPrinter` (`send` / `getDefaults`)
- Injected JS: `window.ElilaiKafePrinter` via `www/js/elilai-native-shell.js`
- LiveView hook: `ElilaiPrinter` pushes `elilai-printer` jobs and confirms with `elilai_printer_result`
- Server transport: set `PRINTER_TRANSPORT=native_client` on Fly (do **not** set `PRINTER_HOST` on Fly)

### Intentionally not in this pass

- Offline mode
- Modal-first Android back
- Play Store / App Store submission packaging
- CapacitorCookies / CapacitorHttp
- Second authentication system
- Service worker changes
- Barista-facing printer IP settings UI (host/port are app defaults)
