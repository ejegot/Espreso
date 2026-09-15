# Manual tablet checklist — printer + kaha (native bridge)

Hardware: HS-802UL at `192.168.0.87:9100`, drawer on kick pin 2.

Install debug APK:

`apps/elilai-kafe-app/android/app/build/outputs/apk/debug/app-debug.apk`

Fly must use `PRINTER_TRANSPORT=native_client` (no `PRINTER_HOST` on Fly).

## Checklist

1. Tablet on **main** shop Wi‑Fi (same LAN as printer), not Guest.
2. Open ELIlai Kafe app → login → POS.
3. **Cash** paid order → receipt physically prints.
4. Kaha physically opens (once).
5. **GCash** paid order → receipt prints.
6. Kaha stays **closed**.
7. **Maya** paid order → receipt prints.
8. Kaha stays **closed**.
9. Unpaid / place unpaid → no receipt, no kaha.
10. With printer offline: cash paid still saves; clear error; Retry does **not** double-kick after a successful prior kick (coordinator phases).
11. Home → Test print / Open kaha (owner/manager as shown) when printer enabled.
12. Orders → Mark paid Cash vs GCash/Maya matches the same print/drawer rules.
