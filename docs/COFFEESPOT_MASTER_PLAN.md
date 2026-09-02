# CoffeeSpot — Master Action Plan

**Updated:** 2026-09-02  
**Goal:** Operable POS + staff system **now** (manual/cash/counter). QRPh images lang ang hihintayin pag approved na ang owner — plug-in lang, hindi full rebuild.

---

## Operating model (v1)

| Who | Device | What they do |
|-----|--------|--------------|
| **Customer** | Phone browser | Order sa `/menu` — cash, counter, or QRPh (pag ready) |
| **Staff (barista)** | Tablet/browser | KDS `/orders` — prepare, mark paid, complete |
| **Manager** | Tablet/browser | KDS + POS + availability + reports |
| **Owner** | Phone/laptop | Users, settings, QR images, dashboard |

**Interim:** Staff gamit muna ang **web** sa Samsung tablet (Chrome). Flutter app sunod. Parehong backend.

---

## Status today (already built)

- [x] Customer menu `/menu` — basket, checkout, product photos
- [x] Staff KDS `/orders` — status flow, mark paid (counter only)
- [x] Staff POS `/pos` — walk-in orders
- [x] Roles: `owner`, `manager`, `barista`
- [x] Admin: users, settings, 86 board
- [x] Login: email + password `/login`
- [x] PayMongo online GCash/Maya (temporary)

---

## Phase map

```
NOW (owner QR pending)          QR APPROVED (plug-in)           LATER
─────────────────────          ─────────────────────           ─────
A. Web staff login (grid+PIN)  E. QR images in admin           H. Flutter app
B. Backend API + JWT           F. Web checkout QR display      I. Auto-print + kaha
C. Web POS/KDS polish          G. Staff confirm QRPh paid        J. Shift close, reports+
D. Printer network test        (retire PayMongo)
```

---

# PHASE A — Staff login (web) · START NOW

**Why:** Email/password hindi practical sa counter tablet. Employee grid + PIN = mabilis na staff login.

### A1. Database
- [ ] Migration: `users.pin_hash` (nullable, Pbkdf2)
- [ ] Owner/manager sets PIN sa admin; barista PIN required bago active

### A2. Login page redesign (`/login`)
- [ ] **Screen 1:** Grid ng active staff (photo/initials, first name, role badge)
- [ ] **Screen 2:** Tap name → 4–6 digit PIN pad (no email field)
- [ ] **Screen 3 (owner/manager only):** "Login with email" link → existing email/password form
- [ ] Failed PIN: lockout after 5 tries (5 min) — same IP/device
- [ ] Session: keep cookie session (web); API uses JWT (Phase B)

### A3. Admin — user PIN management (`/admin/users`)
- [ ] Owner: set/reset PIN per user
- [ ] Show "PIN not set" warning for active baristas
- [ ] Cannot view PIN — only reset

### A4. Permissions (unchanged logic, new entry point)
| Role | After PIN login → |
|------|-------------------|
| `barista` | `/orders` |
| `manager` | `/dashboard` |
| `owner` | `/dashboard` |

**Files:** `staff_login_live.ex`, `admin_users_live.ex`, `accounts.ex`, new `pin_auth.ex`

**Test:** PIN login, lockout, role redirect, owner email fallback

---

# PHASE B — Backend API (for tablet app + future Flutter) · START NOW

**Why:** Flutter at web tablet kailangan ng JSON, hindi LiveView HTML lang.

### B1. API scope (`/api/v1/...`)
| Endpoint | Auth | Purpose |
|----------|------|---------|
| `POST /auth/pin` | public | `{user_id, pin}` → JWT |
| `POST /auth/refresh` | refresh token | extend session |
| `GET /staff/roster` | public | active users for grid (id, name, role, avatar) |
| `GET /menu` | staff JWT | categories + products + availability |
| `GET /orders` | staff JWT | list (filter: unpaid, active, today) |
| `GET /orders/:id` | staff JWT | detail |
| `PATCH /orders/:id/status` | staff JWT | preparing → ready → completed |
| `PATCH /orders/:id/mark_paid` | staff JWT | cash / gcash / maya / counter |
| `POST /orders` | staff JWT | walk-in POS order |
| `GET /settings/business` | staff JWT | hours, shop name |

### B2. Real-time
- [ ] Phoenix Channel `orders:lobby` — subscribe after JWT auth
- [ ] Events: `order_created`, `order_updated`
- [ ] Same PubSub backend as LiveView (single source of truth)

### B3. Auth
- [ ] JWT access token (15 min) + refresh (7 days)
- [ ] Tablet device: optional `device_name` on login for audit log
- [ ] Every endpoint checks `Authorization.can?(role, permission)`

### B4. Payment status model (prep for QRPh)
- [ ] Add `payment_status`: `awaiting_payment` | `unpaid` | `paid` (migrate existing `unpaid` counter = `unpaid`, online checkout = `awaiting_payment`)
- [ ] Add `paid_via`: `cash` | `gcash` | `maya` | `counter` | `paymongo` (nullable)
- [ ] Relax `mark_paid/1` — allow staff confirm for `awaiting_payment` + `payment_method: online` when QRPh mode on

**Files:** new `lib/espreso_web/api/` router scope, `StaffToken`, channel `OrderChannel`

**Test:** API integration tests per role; barista cannot access admin endpoints

---

# PHASE C — Web staff UX polish (operate manually NOW) · START NOW

**Why:** Puwedeng mag-operate na ang shop gamit browser habang wala pang QRPh / Flutter.

### C1. KDS `/orders` improvements
- [ ] **Unpaid queue tab** — counter + awaiting_payment orders, sorted oldest first
- [ ] **Sound alert** — new order (Web Audio API, toggle in localStorage)
- [ ] **Mark paid modal** — Cash | GCash | Maya | Counter (staff picks how customer paid)
- [ ] Show payment badge: UNPAID / AWAITING QR / PAID
- [ ] Big tap targets for tablet (min 48px)

### C2. POS `/pos` improvements
- [ ] Same payment modal as KDS
- [ ] Quick categories sidebar (match menu categories)
- [ ] Order number + total prominent after place

### C3. Staff home `/staff`
- [ ] Role-based quick links (barista: Orders only; manager: + POS, Availability)
- [ ] "Shop open/closed" indicator from business settings

### C4. Customer `/menu` — interim checkout (before QRPh)
- [ ] Keep **Pay at counter (cash)** as default / prominent
- [ ] Hide or de-emphasize PayMongo GCash/Maya until Phase E
- [ ] Order confirmation: "Pay at counter — Order #1234"

**Operate now:** Customer orders → staff sees on KDS → mark paid (cash) → prepare → complete.

---

# PHASE D — Hardware · OWNER + DEV (parallel)

### D1. Printer HS-802UL
- [ ] Assign static IP on shop router (e.g. `192.168.1.100`)
- [ ] Test print from laptop: `echo "test" | nc IP 9100` or print utility
- [ ] Test kaha kick (ESC/POS drawer command)
- [ ] Document IP in owner notes (not git)

### D2. Samsung tablet setup
- [ ] Install Chrome, bookmark `/login` and `/orders`
- [ ] Kiosk mode optional (Guided Access / Samsung Knox if available)
- [ ] Keep tablet plugged in at counter

### D3. Flutter print spike (optional parallel)
- [ ] Small Flutter project: network print to port 9100
- [ ] Not blocking web operation

---

# PHASE E — QRPh plug-in · WHEN OWNER APPROVED ONLY

**Trigger:** Owner sends `gcash-qrph.png` + `maya-qrph.png` (+ test payment confirmed)

### E1. Admin settings (`/admin/settings`)
- [ ] Upload GCash QRPh image
- [ ] Upload Maya QRPh image
- [ ] Toggle: `payments_mode: paymongo | qrph_manual`
- [ ] Merchant display name on checkout

### E2. Customer checkout (`/menu`)
- [ ] Replace PayMongo redirect with:
  - Order summary + amount + order #
  - Buttons: **Pay with GCash** | **Pay with Maya**
  - Show static QR image + "Scan with your bank app"
  - Note: "Show order # to staff after payment"
- [ ] Order created with `payment_status: awaiting_payment`, `payment_method: online`

### E3. Staff confirm flow
- [ ] Unpaid queue shows awaiting_payment orders
- [ ] Staff: Confirm paid → pick GCash or Maya → `paid_via` set → status → preparing
- [ ] Optional: print receipt trigger (web print dialog first; Flutter later)

### E4. Retire PayMongo
- [ ] Remove checkout session creation from `MenuLive`
- [ ] Keep webhook handler read-only for old orders
- [ ] Remove PayMongo env vars from production

**Estimated dev:** 2–3 days after QR images received (not weeks).

---

# PHASE F — Flutter counter app · AFTER B + C STABLE

### F1. Project setup
- [ ] `coffeespot_counter` Flutter app (Android first)
- [ ] Base URL config, JWT storage

### F2. Screens
- [ ] Employee grid + PIN (same as web login)
- [ ] KDS list + detail + status buttons
- [ ] Unpaid queue + mark paid
- [ ] Walk-in POS (simplified)
- [ ] Settings: printer IP, sound on/off

### F3. Native features
- [ ] New order sound + notification
- [ ] ESC/POS network print (kitchen ticket, receipt, kaha on paid)
- [ ] Offline banner (read-only when no network)

### F4. Rollout
- [ ] Side-by-side with web 1 week
- [ ] Switch tablet default to Flutter app

---

# PHASE G — Later (not blocking go-live)

- [ ] Printable table QR cards (`/menu?table=N`)
- [ ] Per-item notes on detail sheet
- [ ] Shift open/close + cash count
- [ ] Daily sales report (by payment method)
- [ ] 86 items from tablet
- [ ] QRPh auto-verify (GCash/Maya API) if wallets offer it
- [ ] Multi-table dine-in flow polish

---

# Role cheat sheet (final)

| Action | Owner | Manager | Barista |
|--------|:-----:|:-------:|:-------:|
| PIN login (grid) | ✓ | ✓ | ✓ |
| Email login | ✓ | ✓ | — |
| View KDS | ✓ | ✓ | ✓ |
| Mark paid | ✓ | ✓ | ✓ |
| POS walk-in | ✓ | ✓ | ✓ |
| 86 / availability | ✓ | ✓ | — |
| Reports | ✓ | ✓ | — |
| Manage staff + PINs | ✓ | — | — |
| Business + QR settings | ✓ | — | — |

---

# Suggested build order (dev)

| Week | Focus | Shop can operate? |
|------|-------|-------------------|
| **1** | A (PIN login) + C1 (unpaid queue, mark paid modal) | ✓ Cash/counter on web |
| **2** | B (API + JWT + channel) | ✓ Same, API ready for app |
| **3** | C2–C4 polish + D printer test | ✓ Tablet on web KDS |
| **—** | **E when QR approved** | ✓ + GCash/Maya QR manual |
| **4–6** | F Flutter MVP | ✓ Native tablet app |
| **7+** | G optional | ✓ |

---

# Owner action items (ongoing)

- [ ] GCash Business application submitted → wait approval
- [ ] Maya Business application submitted → wait approval
- [ ] Send QR images when ready
- [ ] Printer IP + test print at shop
- [ ] Create staff accounts in admin (names for PIN grid)
- [ ] Set each barista PIN with owner

---

# Dev start command

When ready to code Phase A:

> **"Start Phase A — PIN login"**

When owner sends QR images:

> **"Start Phase E — QRPh"**
