# CoffeeSpot / Espreso — Product Roadmap

Saved: 2026-09-01. Resume development after owner completes GCash + Maya merchant setup.

## Current state (done)

- Web QR menu at `/menu` (landing, categories, detail sheet for all items, basket, checkout)
- PayMongo GCash/Maya redirect (temporary — retire after QRPh live)
- Staff web: `/orders` KDS, `/pos`, admin settings, 86 board
- Roles: `owner`, `manager`, `barista` in `Espreso.Accounts.Authorization`
- Studio product photos, hours strip, `₱1,500` comma formatting

## Target architecture

```
Customer phone (web /menu)  →  Phoenix server  ←  Samsung tablet (Flutter app)
                                    ↓
                            HS-802UL printer + kaha (Ethernet ESC/POS)
```

- **Customer:** web only (no app install)
- **Counter:** 1× Samsung Android tablet — Flutter app
- **Payment:** GCash + Maya QRPh (manual confirm v1)
- **Printer:** HS-802UL, 80mm, ESC/POS, port 9100

## Master priority (start order)

### Priority 1 — Foundations (before code)

- [ ] Printer static IP + test print + kaha kick from tablet
- [ ] GCash for Business approved + QRPh image saved
- [ ] Maya Business approved + QRPh image saved
- [ ] Flutter ESC/POS network print spike on HS-802UL

### Priority 2 — Backend API (weeks 2–4)

- [ ] JSON API: menu, orders, status, mark paid
- [ ] `payment_status`: `awaiting_payment` | `paid`
- [ ] WebSocket: new/updated orders
- [ ] Staff roster API + PIN login (`pin_hash`) + JWT

### Priority 3 — Flutter app MVP (weeks 5–10)

- [ ] Employee grid login (tap name → PIN)
- [ ] KDS + sound
- [ ] Kitchen auto-print + receipt + kaha on paid
- [ ] Unpaid queue + mark paid (cash / GCash / Maya)
- [ ] Walk-in POS

### Priority 4 — Web payment swap (weeks 11–12)

- [ ] Checkout: GCash QR | Maya QR | Cash (replace PayMongo)
- [ ] Retire PayMongo

### Priority 5 — Optional web polish

- [ ] Printable table QR cards (`?table=N`)
- [ ] Per-item notes on detail sheet

### Priority 6 — Later

- Shift open/close, reports, 86 from tablet, QRPh auto-verify API

## Staff login (app)

| Role | DB | Login |
|------|-----|-------|
| Owner | `owner` | Grid + PIN or full login |
| Manager | `manager` | Grid + PIN |
| Staff | `barista` | Tap name → PIN |

Server must enforce `Espreso.Accounts.Authorization` on every API call.

## Payment flow (v1 — manual)

1. Customer places order on web → `awaiting_payment`
2. Web shows amount + order # + GCash or Maya QR image
3. Customer pays via bank/e-wallet app
4. Staff tablet → Unpaid → Confirm paid → print receipt → kaha
5. Order → `paid` → kitchen/preparing flow

## Files to collect after merchant approval

Save in owner secure folder (not committed to git):

- `gcash-qrph.png` (or PDF) — merchant QRPh code
- `maya-qrph.png` — merchant QRPh code
- GCash Business login email (for dashboard)
- Maya Business login email
- Merchant account / wallet numbers (for reconciliation)
- Fee schedule note (MDR % per wallet)

## Dev start trigger

When ALL are true:

1. At least one of GCash or Maya QR image is ready (both preferred)
2. Printer test print works from tablet
3. Owner says "start Priority 2"

Then begin Phoenix API + PIN auth work.
