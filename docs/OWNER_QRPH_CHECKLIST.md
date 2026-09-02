# Owner checklist — GCash + Maya merchant (QRPh)

Complete this before dev continues. Espreso cannot accept GCash/Maya in-app until these are done.

---

## Documents to prepare (one folder, photos or PDF)

### Sole proprietorship (most cafes)

- [ ] DTI Certificate of Business Name Registration
- [ ] BIR Form 2303 (Certificate of Registration)
- [ ] Mayor's Permit / Business Permit (if available)
- [ ] Valid government ID of owner (with signature)
- [ ] Proof of business address (utility bill or lease)
- [ ] Proof of bank account (passbook page or statement) — settlement account
- [ ] Business email (dedicated, not used on GCash/Maya before)

### Also required personally

- [ ] Owner's personal GCash account — **fully verified**, ideally 12+ months active
- [ ] Owner's personal Maya account — verified

**Business name on documents must match exactly** (e.g. Elilai Kafe / CoffeeSpot — use registered name).

---

## A. GCash for Business

**Portal:** https://business.gcash.com  
**Help:** https://help.gcash.com (search "GCash for Business merchant")

### Steps

1. [ ] Owner logs in / applies as merchant at business.gcash.com
2. [ ] Use **new business email** (never used on GCash for Business)
3. [ ] Select business type: Sole Proprietorship (or correct type)
4. [ ] Upload DTI, BIR 2303, ID, address proof, bank proof
5. [ ] Submit and wait for review (**~3–7 business days**)
6. [ ] When approved: log in to GCash Business dashboard
7. [ ] Go to **Receive Payments** → **Generate QR Code**
8. [ ] Choose **QR Ph** (not GCash-only QR) — works with Maya and banks too
9. [ ] Download QR image → save as `gcash-qrph.png`
10. [ ] Print one copy for counter backup

### Notes

- Fee (typical): ~2.5% + ₱3 per transaction — confirm in dashboard
- Settlement: often T+1 business day to linked bank
- Keep transaction reference on receipts for BIR records

---

## B. Maya Business

**Portal:** https://www.maya.ph/business or https://business.maya.ph  
**App:** Maya Business on Google Play (owner can use phone; tablet later for shop)

**Support:** (+632) 8845-7700

### Steps (full business account)

1. [ ] Sign up at maya.ph/business → Register
2. [ ] Continue under **Maya Business Manager** (full features)
3. [ ] Verify email and mobile number
4. [ ] Complete business profile + upload same core docs (DTI, BIR, ID, bank)
5. [ ] Wait for verification (**varies — days to ~2 weeks**)

### Faster path (QR only, fewer features)

- [ ] Maya Business **mobile app** → Register → upgrade account
- [ ] Some merchants get QR acceptance with lighter docs — ask Maya support if full onboarding is slow

### After approval

1. [ ] Open Maya Business Manager or app
2. [ ] Find **Maya QR** / **QR Ph** section
3. [ ] Generate or download merchant QR
4. [ ] Save as `maya-qrph.png`
5. [ ] Print one copy for counter

### Notes

- Maya QR / QR Ph MDR often ~1.5% — confirm in contract
- Track payments in Maya Business app (amount, time, reference)

---

## C. What to send dev team when done

Message or shared folder with:

| Item | File / info |
|------|-------------|
| GCash QRPh image | `gcash-qrph.png` |
| Maya QRPh image | `maya-qrph.png` |
| Registered business legal name | exact spelling |
| Display name on receipts | CoffeeSpot Marikina |
| Settlement bank | bank name + last 4 digits only |
| Test payment done? | Yes — owner sent ₱1 to each QR to confirm |

**Do not share** passwords or full bank account numbers in chat.

---

## D. While waiting for approval

Owner can still:

- [ ] Run shop with **cash at counter** on web menu
- [ ] Use personal GCash/Maya manually (customer sends to personal — not ideal long-term)
- [ ] Complete printer network setup (static IP on HS-802UL)

---

## E. Optional: one QRPh only?

If GCash and Maya issue **separate** QRPh codes, Espreso v1 will show **two buttons** on checkout: Pay with GCash | Pay with Maya.

If one wallet's QRPh is **interoperable** (customer can scan with any app), you may still want both for clearer reconciliation.

---

## Checklist complete?

When owner checks all applicable boxes and sends QR images:

→ Dev starts **Priority 2** (Phoenix API + PIN auth) per `docs/COFFEESPOT_ROADMAP.md`
