# CoffeeSpot · Printer on Espreso (Option 2 trial)

After the LAN spike worked (`192.168.0.87`), Espreso can print + open kaha on **cash paid**.

## Requirement

**Phoenix must run on the same LAN as the printer** (Mac on **main shop Wi‑Fi**, not Guest).

Cloud (Fly.io) cannot reach `192.168.0.87`.

## Start for shop trial

```bash
# Mac on main Wi‑Fi (same as printer)
cd /Users/eljhunegot/Code/espreso

export PRINTER_HOST=192.168.0.87
export PRINTER_PORT=9100
# PRINTER_ENABLED is implied when PRINTER_HOST is set

mix phx.server
```

On iPad (same main Wi‑Fi): open `http://<MAC_LAN_IP>:4000/login`  
(Mac IP example was `192.168.0.x` once on main Wi‑Fi — check System Settings.)

## What triggers print

| Action | Receipt | Kaha |
|--------|---------|------|
| POS place as **Paid** (cash) | ✓ | ✓ |
| Orders **Mark paid → Cash** | ✓ | ✓ |
| Mark paid → GCash / Maya | ✓ | ✗ |
| POS **Unpaid** | ✗ | ✗ |

Staff Home also shows **Test print** / **Open kaha** when printer is enabled.

Receipt includes:
- Address: `84 Lilac St., Marikina City`
- `Employee: <logged-in staff name>`
- Wi‑Fi footer: `CoffeeSpot_Guest` / `SPOT3333` / 2-hour note

Override via env if needed: `PRINTER_WIFI_SSID`, `PRINTER_WIFI_PASSWORD`, `PRINTER_RECEIPT_ADDRESS`.

## Soft failure

Order still saves if print fails. Flash/note shows the print error.

## Loyverse

Keep Loyverse on the shop Samsung tablet until Espreso print is stable for a few days.
