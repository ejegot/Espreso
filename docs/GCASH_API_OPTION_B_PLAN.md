# Option B — GCash API Portal (direct auto-verify)

**Goal:** Replace PayMongo for online GCash payments. Server creates payment per order → customer pays → GCash callback → order auto `paid`.

**Not the same as:** Static QRPh PNG in admin (`qrph_manual`) — that stays manual confirm unless we fully switch to API-generated payments.

**Owner status:** GCash Business merchant approved ✅ — this is step 1 only. **API Portal access is a separate partner onboarding.**

---

## How GCash API Portal access works

GCash API Portal is **not** a public self-signup (unlike PayMongo). It is **partner-gated**.

| Portal | URL |
|--------|-----|
| Sandbox | https://apiportal.lab.gcash.com |
| Production | https://apiportal.gcash.com |

Official FAQ: [gcash.com/business/api-portal-faqs](https://gcash.com/business/api-portal-faqs)

> *"GCash API Portal is currently only available for selected partner organizations — please reach out to any of our GCash account managers to get more information on the onboarding process."*

---

## Step-by-step: How to apply (owner / dev)

### 1. Use existing GCash Business relationship

Owner is already approved → ask the **same GCash Business contact / account manager** (from approval email or dashboard):

> "We want **API Portal access** to integrate GCash payments into our custom ordering web app (CoffeeSpot). We need **Webpay** and/or **In-Store QR** API products with **payment notification webhooks**."

If no account manager on file, email **partnersolutions@gcash.com** (GCash Partner Solutions).

Support (after enrolled): **api-portal-support@gcash.com** (cc account manager on issues).

### 2. Prepare application packet

| Item | Notes |
|------|--------|
| Registered business name | Exact match DTI/BIR (e.g. Elilai / CoffeeSpot) |
| GCash Business merchant email | Same org as approved account |
| DTI + BIR 2303 | Already submitted for merchant — have copies ready |
| Product description | "QR menu ordering web app for café — customers pay via GCash on order page" |
| Live URL | Production menu URL (or staging + go-live date) |
| Webhook URL (planned) | e.g. `https://your-domain.com/webhooks/gcash` |
| Tech contact | Dev name + email for portal invite |
| Expected volume | Orders/day estimate (small café is fine) |

### 3. Wait for portal invite

GCash creates an **Organization** and invites users by email. You cannot log in until activated ("Not found" = not enrolled yet).

Typical timeline: **weeks** (not days) — partner review, not instant.

### 4. Subscribe to API products (inside portal)

After login:

1. Browse **Products** (search: Webpay, In-Store QR, Payments)
2. **Subscribe** to the plan (free or paid — needs approval)
3. When approved → **Request Credentials** (sandbox first)
4. Register **Application** + webhook/notification URL per product docs

Roles matter: Developer can subscribe to **free** plans; paid plans need Subscriber role (see API Portal FAQ).

### 5. Sandbox → production

1. Build against **apiportal.lab.gcash.com** credentials
2. Test: create payment → pay in sandbox → receive callback → mark order paid
3. GCash production approval for live credentials
4. Switch CoffeeSpot config to production keys

---

## CoffeeSpot technical plan (after API access)

### Phase 0 — Now (no API yet)

- [x] `qrph_manual` + static GCash QR + staff confirm
- [ ] Owner applies for API Portal (this doc)
- [ ] Keep PayMongo code dormant (`counter_only` / `qrph_manual` in prod)

### Phase 1 — Config & module (~2–3 days dev)

- [ ] `GCash` context module (like existing `Espreso.PayMongo`)
- [ ] Settings: `gcash_api_enabled`, client id, keys (encrypted env), webhook secret
- [ ] New `payments_mode`: `gcash_api` (or extend `qrph_manual` with auto branch)
- [ ] Migration if new fields needed on `business_settings`

### Phase 2 — Checkout flow (~3–5 days dev)

Replace static QR path for GCash online orders:

```
Customer picks GCash → POST create payment (amount, order ref)
→ Show dynamic QR OR redirect to GCash Webpay
→ Customer pays in GCash app
→ GCash POST notifyPayment / webhook → verify signature
→ Orders.mark_paid(order, paid_via: "gcash")
→ PubSub → KDS updates (same as PayMongo webhook today)
```

Reuse patterns from:

- `lib/espreso/paymongo.ex` — webhook verify + mark paid
- `lib/espreso_web/controllers/paymongo_webhook_controller.ex`
- `lib/espreso_web/live/menu_live.ex` — `place_qrph_order` → new `place_gcash_api_order`
- `lib/espreso_web/live/order_live.ex` — show dynamic QR / payment status polling fallback

### Phase 3 — Staff UX (~1 day)

- [ ] KDS: auto-paid orders skip "Confirm payment" for GCash API
- [ ] Keep manual confirm as fallback if webhook delayed (optional timeout + staff button)
- [ ] Reconciliation log (payment id, GCash reference on order)

### Phase 4 — Maya (optional, separate)

GCash API Portal = **GCash only**. Maya needs Maya Business API or stay on static QRPh / PayMongo for Maya.

### Phase 5 — Retire PayMongo

When GCash API stable in production:

- [ ] `payments_mode: gcash_api` default for online
- [ ] Static QR optional backup at counter only
- [ ] PayMongo webhook read-only for old orders

---

## Fees (owner expectation)

| | PayMongo | GCash API direct |
|--|----------|------------------|
| Gateway fee | Yes (~3.5% + ₱15) | No |
| GCash MDR | Bundled | Yes (~2.5% + ₱3 — confirm in contract) |
| Settlement | Via PayMongo | GCash Business → bank (T+1) |

---

## Email template (copy-paste for owner)

**To:** partnersolutions@gcash.com (or your GCash account manager)  
**Subject:** API Portal access — CoffeeSpot merchant QR ordering integration

```
Good day,

We are an approved GCash for Business merchant (CoffeeSpot, Lilac Marikina).
We operate a web-based QR menu and staff order system and would like to integrate
GCash payments with automatic payment confirmation via API (webhooks).

We are requesting:
1. GCash API Portal organization access (sandbox + production)
2. Subscription guidance for Webpay and/or In-Store QR API products suitable for
   e-commerce / per-order dynamic QR payments
3. Documentation for payment notification callbacks and credential setup

Business details:
- Legal name: [DTI registered name]
- GCash Business email: [merchant email]
- Website: [production URL]
- Planned webhook: https://[domain]/webhooks/gcash
- Technical contact: [name, email]

We have DTI, BIR 2303, and mayor's permit available upon request.

Thank you,
[Owner name]
[Phone]
```

---

## Decision tree

```
Owner has GCash Business QR only?
  → Use qrph_manual now (manual confirm)

Owner wants auto-verify?
  → Apply API Portal (this doc)
  → While waiting: PayMongo OR keep manual

API Portal approved?
  → Build Phase 1–3 in CoffeeSpot
  → Retire PayMongo when stable
```

---

## References

- [GCash API Portal FAQ](https://gcash.com/business/api-portal-faqs)
- [GCash for Business](https://business.gcash.com)
- CoffeeSpot existing webhook pattern: `lib/espreso/paymongo.ex`, `PaymongoWebhookController`
- Owner QR checklist: `docs/OWNER_QRPH_CHECKLIST.md`
