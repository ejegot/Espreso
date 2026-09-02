# CoffeeSpot — Implementation Plan (Option A)

**Approach:** Functionality & connections first. UI/UX polish after everything works end-to-end.  
**Default payments mode:** `counter_only` (PayMongo disabled until owner QRPh ready → switch to `qrph_manual`).  
**Status:** Layer 3 complete — wire existing LiveView UI done. Layer 4 next (UI/UX polish).  
**Updated:** 2026-09-02

---

## Principle

```
Layer 1 — DATA + LOGIC     → migrations, contexts, business rules, tests
Layer 2 — API + REAL-TIME  → JSON endpoints, JWT, WebSocket, auth
Layer 3 — WIRE EXISTING UI → minimal hooks so current pages use new logic
Layer 4 — UI/UX POLISH     → grid login, tablet design, modals, Flutter (later)
```

**Rule:** No visual redesign until Layer 1–3 pass tests and a human can complete full flows on existing (ugly) UI.

---

## What “working and connected” means

A flow is **done** when:

1. Database stores the right state
2. Context functions enforce business rules
3. API returns correct JSON for each role
4. WebSocket pushes updates to subscribers
5. Existing LiveView pages (or API client) can trigger and see the result
6. Automated tests cover happy path + permission denials

---

## Layer 1 — Data & business logic

### 1.1 User PIN (backend only)

| Task | Detail |
|------|--------|
| Migration | `users.pin_hash` (nullable string) |
| Context | `Accounts.set_pin/2`, `Accounts.verify_pin/2`, `Accounts.clear_pin/1` |
| Rules | Pbkdf2 hash; 4–6 digits; owner-only set/reset via existing admin |
| Tests | Set, verify, wrong PIN, inactive user rejected |

**No login UI change yet** — test via `iex` or unit tests.

### 1.2 Payment model expansion

| Task | Detail |
|------|--------|
| Migration | `orders.paid_via` — `cash` \| `gcash` \| `maya` \| `counter` \| `paymongo` (nullable) |
| Migration | Extend `payment_status`: add `awaiting_payment` (online orders waiting for QR/manual confirm) |
| Backfill | Existing `unpaid` counter → stay `unpaid`; existing online checkout → `awaiting_payment` where applicable |
| `Orders.mark_paid/2` | Accept `paid_via` option; allow staff mark for `awaiting_payment` when `payments_mode: qrph_manual` |
| `Orders.create_order/2` | Counter → `unpaid`; online QR mode → `awaiting_payment` |
| Tests | Counter paid, QR awaiting → staff confirm, online still blocked in paymongo mode |

### 1.3 Business settings — payment mode

| Task | Detail |
|------|--------|
| Migration / settings | `payments_mode`: `paymongo` \| `qrph_manual` \| `counter_only` |
| Settings keys | `gcash_qrph_path`, `maya_qrph_path` (nullable until owner uploads) |
| Context | `BusinessSettings.get/put` for payment config |
| Tests | Mode switches affect `create_order` payment_status |

### 1.4 Staff roster (read model)

| Task | Detail |
|------|--------|
| Function | `Accounts.list_active_staff_for_roster/0` → `[%{id, name, role}]` (no secrets) |
| Tests | Inactive users excluded; roles correct |

**Deliverable Layer 1:** All migrations run; `mix test` green for accounts + orders payment changes.

---

## Layer 2 — API + real-time

### 2.1 API router scope

New: `lib/espreso_web/router.ex` scope `/api/v1` with JSON pipeline.

### 2.2 Auth endpoints

| Method | Path | Auth | Body / response |
|--------|------|------|-----------------|
| POST | `/auth/pin` | public | `{user_id, pin}` → `{access_token, refresh_token, user}` |
| POST | `/auth/email` | public | `{email, password}` → same tokens (for owner/manager) |
| POST | `/auth/refresh` | refresh token | new access token |
| GET | `/staff/roster` | public | active staff list for grid (later) |

- JWT access (15 min) + refresh (7 days)
- Claims: `user_id`, `role`
- Plug: `EspresoWeb.ApiAuth` — verify JWT, load user, check permissions

### 2.3 Order endpoints

| Method | Path | Permission | Action |
|--------|------|------------|--------|
| GET | `/orders` | `:orders` | List (filters: `unpaid`, `active`, `today`) |
| GET | `/orders/:id` | `:orders` | Detail + items |
| PATCH | `/orders/:id/status` | `:orders` | `preparing` / `ready` / `completed` / `cancelled` |
| PATCH | `/orders/:id/mark_paid` | `:orders` | `{paid_via: "cash" \| "gcash" \| "maya" \| "counter"}` |
| POST | `/orders` | `:orders` | Walk-in POS order (same as `StaffPosLive`) |

### 2.4 Menu & settings endpoints

| Method | Path | Permission |
|--------|------|------------|
| GET | `/menu` | `:view_menu` or public read |
| GET | `/settings/business` | staff JWT — hours, shop name, payments_mode (no secrets) |

### 2.5 WebSocket

| Channel | Topic | Events |
|---------|-------|--------|
| `OrderChannel` | `orders:lobby` | `order_created`, `order_updated` |

- Join requires valid JWT
- Reuse existing `Orders` PubSub broadcasts — single source of truth

### 2.6 API tests

- Barista can list/mark paid; cannot access admin settings
- Manager same as barista + reports endpoints (if exposed)
- Owner can access user PIN reset endpoint (API admin scope)
- Invalid JWT → 401; wrong role → 403

**Deliverable Layer 2:** `mix test test/espreso_web/api/` — all endpoints + channel subscription work.

---

## Layer 3 — Wire existing UI (minimal, not polish)

**Goal:** Current LiveView pages use new backend logic. Looks the same, behaves correctly.

### 3.1 Orders (`StaffOrdersLive`)

| Change | Type |
|--------|------|
| `mark_paid` passes `paid_via` (default `counter`) | Logic hook |
| Show `awaiting_payment` in unpaid drawer | Data display only |
| Allow staff confirm when `qrph_manual` mode | Logic hook |
| Payment method picker | **Plain `<select>` or buttons** — not designed modal |

### 3.2 POS (`StaffPosLive`)

| Change | Type |
|--------|------|
| Pass `paid_via` on place order when paid | Logic hook |
| Unpaid walk-in creates `unpaid` + counter | Already mostly there |

### 3.3 Menu checkout (`MenuLive`)

| Change | Type |
|--------|------|
| Respect `payments_mode` from settings | Logic |
| `counter_only` → hide online pay | Simple conditional |
| `qrph_manual` → create `awaiting_payment`, skip PayMongo | Logic |
| QRPh screen | **Placeholder text + img tag** if paths set — no design |

### 3.4 Admin settings (`AdminSettingsLive`)

| Change | Type |
|--------|------|
| `payments_mode` dropdown | Plain form field |
| Upload GCash/Maya QR (file → `priv/static` or uploads) | Basic file input |
| PIN reset per user in `AdminUsersLive` | Plain form field |

### 3.5 Login

| Change | Type |
|--------|------|
| **Keep email/password UI for now** | No grid yet |
| Optional: add hidden/dev route to test PIN login via API only | Dev only |

**Deliverable Layer 3:** Manual test script — full order lifecycle on existing UI:

1. Customer orders (counter) → staff sees on KDS → mark paid (cash) → preparing → ready → complete  
2. Customer orders (QR mode when images exist) → `awaiting_payment` → staff confirm → paid  
3. POS walk-in unpaid → mark paid  
4. API client (curl/Postman) can do same flows with JWT  

---

## Layer 4 — UI/UX polish (AFTER Layer 1–3 approved)

**Do not start until you review and sign off on Layers 1–3.**

| Item | Description |
|------|-------------|
| Login grid + PIN pad | Replace email form for baristas |
| KDS tablet layout | Unpaid tab, sound, designed mark-paid modal |
| POS tablet layout | Category sidebar, touch targets |
| Customer QR checkout | Designed pay screen with GCash/Maya tabs |
| Staff home shortcuts | Role-based landing |
| Flutter app | Native UI on top of Layer 2 API |

---

## QRPh — where it fits

| When | What |
|------|------|
| **Now (Layer 1–3)** | Backend + settings + placeholder checkout; `counter_only` mode for go-live |
| **Owner QR approved** | Upload images in admin → flip `payments_mode` to `qrph_manual` — **no new backend**, only assets |
| **Layer 4** | Pretty QR checkout screen |

---

## Hardware & Flutter

| Item | Layer |
|------|-------|
| Printer IP + ESC/POS test | Parallel — not blocking Layer 1–3 |
| Flutter app | Layer 4+ — consumes Layer 2 API only after API stable |

---

## Test checklist (sign-off before UI polish)

- [ ] PIN set/verify works in context tests
- [ ] `awaiting_payment` → staff `mark_paid` with `paid_via: gcash` works
- [ ] PayMongo mode still works (or explicitly disabled via setting)
- [ ] API JWT: barista vs owner permissions enforced
- [ ] WebSocket receives order within 1s of create
- [ ] POS order via API matches POS via LiveView
- [ ] `payments_mode: counter_only` blocks online checkout
- [ ] QR image upload + display on placeholder checkout works

---

## Suggested implementation order

| Step | Layer | Est. | Blocker |
|------|-------|------|---------|
| 1 | 1.1 PIN backend | 0.5 day | — |
| 2 | 1.2–1.3 Payment model + settings | 1 day | — |
| 3 | 1.4 Roster | 0.25 day | — |
| 4 | 2.1–2.5 Full API + channel | 2–3 days | Step 1–3 |
| 5 | 2.6 API tests | 1 day | Step 4 |
| 6 | 3.1–3.5 Wire LiveView (minimal) | 1–2 days | Step 4 |
| 7 | Manual E2E + your review | 0.5 day | Step 6 |
| **—** | **Layer 4 UI/UX** | **after sign-off** | Your approval |
| 8 | QR images plug-in | 0.5 day | Owner approval |
| 9 | Flutter | 2+ weeks | Layer 2 stable |

**Total Layer 1–3:** ~6–8 dev days before any UI polish.

---

## What stays unchanged in Layer 1–3

- Customer menu visual design (already done)
- Staff login look (email form stays)
- KDS/POS visual layout (functional only)
- No new CSS beyond what’s needed to show new fields

---

## Your review — questions to answer

Before we implement, confirm:

1. **OK ba ang Layer 1–3 muna, Layer 4 after sign-off?**  
2. **Default `payments_mode` sa go-live:** `counter_only` habang wala pang QR?  
3. **PayMongo:** keep parallel until QR approved, or disable now?  
4. **API first test:** curl/Postman enough, or gusto mo simple internal `/dev/api-test` page?

---

## Start command (after your approval)

> **"Approved — start Layer 1"**

We will not write implementation code until you say this.
