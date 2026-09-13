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

## Sync / iOS

Requires full Xcode (not Command Line Tools only):

```bash
cd apps/elilai-kafe-app
npx cap sync ios
npx cap open ios
```

## Intentionally not in this pass

- Native printer / kaha bridge
- Offline mode
- Final App Store / Play Store icon sets
- Production signing / store submission
- CapacitorCookies / CapacitorHttp
- Second authentication system
