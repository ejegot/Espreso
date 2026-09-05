# CoffeeSpot · Printer + Kaha spike (Option 1)

Hardware-only test app for the Samsung tablet on shop Wi‑Fi.

**Not POS.** Only:

- Test print
- Open kaha (pin 2 / pin 5)

Printer target: **HS-802UL**, ESC/POS, port **9100**.

## Layout

```
apps/printer_spike/          Flutter Android app
scripts/printer_lan_test.py  Optional Mac LAN smoke test (same Wi‑Fi)
```

## Before anything

1. Printer + kaha powered and on the **same Wi‑Fi** as the tablet (and your Mac if testing from laptop).
2. Note the printer **static IP** (router DHCP reservation).
3. Drawer cable plugged into the printer’s RJ11/RJ12 kick port.

## A) Quick LAN test from Mac (optional)

Same Wi‑Fi as the printer:

```bash
python3 scripts/printer_lan_test.py 192.168.x.x
python3 scripts/printer_lan_test.py 192.168.x.x --drawer
python3 scripts/printer_lan_test.py 192.168.x.x --drawer5
```

If Mac print/kick works, hardware+network are OK → install the tablet app.

## B) Build APK for Samsung tablet

Needs Flutter + Android SDK (already set up on this machine if you used the project setup).

```bash
export PATH="/opt/homebrew/opt/openjdk@17/bin:/opt/homebrew/bin:$PATH"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools

cd apps/printer_spike
flutter pub get
flutter build apk --debug
```

APK path:

`apps/printer_spike/build/app/outputs/flutter-apk/app-debug.apk`

Copy to the tablet (USB, Drive, AirDrop via nearby tools, etc.), enable **Install unknown apps**, install.

Or with USB debugging:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## C) On the tablet

1. Join shop Wi‑Fi.
2. Open **CoffeeSpot · Printer spike**.
3. Enter printer IP (port `9100`).
4. Tap **Test print**.
5. Tap **Open kaha (pin 2)**. If no open, try **pin 5**.

## Success criteria

- [ ] Test print comes out
- [ ] Kaha opens on one of the kick buttons
- [ ] Failure message shows if IP wrong / printer off (app does not crash)

## Next (Option 2 — later)

WebView shell around `/pos` + `/orders` that calls this same native print/kick on **Paid · cash**.

## Notes

- Browser/Chrome **cannot** do this; native socket is required.
- Cloud Phoenix **cannot** reach `192.168.x.x` printers; tablet on LAN must talk to the printer.
